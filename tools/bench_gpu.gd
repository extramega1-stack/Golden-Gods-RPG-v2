extends SceneTree
## Bench de la GPU REAL (fase 48). Complementa a `tools/bench_fps.gd`, que con
## drivers dummy mide solo CPU/lógica y por eso no sabe nada de draw calls ni
## de triángulos.
##
## OJO: hay que lanzarlo **SIN `--headless`** (con ventana), o el motor usa el
## driver dummy y todos los monitores de render dan 0. Es la contrapartida de
## que el CI no pueda medirlo: esto se ejecuta a mano, en la máquina, cuando
## entra arte nuevo.
##
## Qué hace: monta el mundo real, espera a que esté construido, calienta
## (para no medir la carga progresiva), muestrea N frames y saca el informe
## contra el presupuesto de `MedidorGPU` (§9.5).
##
## Uso:
##   godot --path . --script res://tools/bench_gpu.gd -- --frames=600 --warmup=180 --out=build/bench_gpu.json
##
## Flags (todos opcionales):
##   --frames=N     frames a medir (mín 30)
##   --warmup=N     frames de calentamiento (mín 0)
##   --out=RUTA     dónde escribir el JSON
##   --vsync=0|1    0 = QUITA el tope de vsync (default) y mide el coste real
##   --calidad=0..3 fuerza la calidad gráfica sin tocar las opciones del usuario
##   --etiqueta=TXT nombre del escenario, va al informe
##   --cargar       mide DESDE EL FRAME 0, sin esperar el gate de mundo_listo:
##                  así entra en la muestra la carga progresiva y los picos de
##                  compilación de shader, que es donde el jugador los sufre
##   --dump=RUTA    vuelca las muestras crudas frame a frame (para atribuir
##                  cada pico; sin esto el p95 es un número sin dueño)
##   --res=ANxAL    redimensiona la ventana (para meter a la GPU en el cuello
##                  de botella: con el monitor a 240 Hz el presenting impone un
##                  piso de 4,17 ms y oculta cualquier diferencia de calidad)
##   --tope=N       tope de FPS propio de Godot (0 = sin tope). Con vsync
##                  apagado este es el ÚNICO límite que no viene del
##                  compositor, así que es la forma limpia de comprobar que el
##                  juego sostiene 60.
##
## POR QUÉ EL VSYNC SE QUITA POR DEFECTO: con vsync puesto, `delta` de cada
## frame es el del monitor (16,67 ms en 60 Hz) SIEMPRE que se llegue o no, así
## que el p95 mide la FRECUENCIA DEL MONITOR, no el juego. Un "p95 16,67 ms
## veredicto OK" con vsync no dice si sobran 10 ms de margen o si el frame real
## cuesta 30 ms y el compositor está sacando 30 de cada 60. Desbloqueando, el
## frame time es el coste de verdad y el presupuesto se puede auditar.
##
## Exit code 0 siempre (es un bench, no un test): el veredicto sale impreso.

const MEDIDOR: GDScript = preload("res://scripts/core/medidor_gpu.gd")
const VEREDICTO: GDScript = preload("res://scripts/render/veredicto_render.gd")
const PP: GDScript = preload("res://scripts/core/post_proceso.gd")

var _medidor: RefCounted = null
var _demo: Node = null
var _fase: int = 0
var _n_frames: int = 600
var _n_warmup: int = 180
var _espera: int = 0
var _out: String = ""
var _dump: String = ""
var _etiqueta: String = ""
var _calidad: int = -1
var _vsync: bool = false
## Medir desde el frame 0 (carga incluida) en vez del estado ya caliente.
var _cargar: bool = false
## El frame en el que el mundo terminó de construirse, para separar en el
## informe la carga del estado estacionario.
var _frame_mundo_listo: int = -1
var _frame_actual: int = 0
var _frame_de_muestra: Array[int] = []
## Resolución de la ventana para el bench ("" = la del proyecto).
var _res: String = ""
## Tope de FPS propio del motor (0 = sin tope).
var _tope: int = 0
## Supersampling para el bench (>1 renderiza más pixeles que pixeles de
## ventana). Es la forma de meter a la GPU en el cuello de botella en una
## máquina cuyo monitor va a 240 Hz: sin esto, todo lo que el juego puede
##culation cabe en los 4,17 ms del presenting y los niveles de calidad parecen
## hacer lo mismo.
var _escala: float = 0.0
## En modo carga, que los overrides ya se reaplicaron tras la puerta.
var _ya_forzado: bool = false
## Reloj de pared entre frames consecutivos. `delta` es el paso del motor y
## con vsync engagement vale el del monitor; el reloj de pared es lo que de
## verdad tardó el frame, y es el que contrasta el monitor TIME_PROCESS (que en
## una corrida sin tope llega a reportar más tiempo del que dura el frame).
var _ticks_prev: int = 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_n_frames = maxi(int(a.get_slice("=", 1)), 30)
		elif a.begins_with("--warmup="):
			_n_warmup = maxi(int(a.get_slice("=", 1)), 0)
		elif a.begins_with("--out="):
			_out = a.get_slice("=", 1)
		elif a.begins_with("--etiqueta="):
			_etiqueta = a.get_slice("=", 1)
		elif a.begins_with("--vsync="):
			_vsync = int(a.get_slice("=", 1)) != 0
		elif a.begins_with("--calidad="):
			_calidad = clampi(int(a.get_slice("=", 1)), 0, 3)
		elif a == "--cargar":
			_cargar = true
		elif a.begins_with("--dump="):
			_dump = a.get_slice("=", 1)
		elif a.begins_with("--res="):
			_res = a.get_slice("=", 1)
		elif a.begins_with("--tope="):
			_tope = maxi(int(a.get_slice("=", 1)), 0)
		elif a.begins_with("--escala="):
			_escala = maxf(float(a.get_slice("=", 1)), 0.25)
	_medidor = MEDIDOR.new()
	print("[BENCH-GPU] frames=%d warmup=%d vsync=%s calidad=%s" % [
		_n_frames, _n_warmup, str(_vsync),
		("forzada " + str(_calidad)) if _calidad >= 0 else "la del usuario"])
	if DisplayServer.get_name() == "headless":
		printerr("[BENCH-GPU] AVISO: sin ventana el render es dummy; los valores de GPU serán 0")
	_demo = load("res://scenes/demo/fase14_demo.tscn").instantiate()
	root.add_child(_demo)
	# Pide el foco una vez mapeada la ventana: sin esto, en Wayland el
	# compositor estrangula el presenting a ~7 Hz y el p95 no mide el juego.
	# `grab_focus()` es el método; `request_focus()` NO EXISTE en 4.7 (era un
	# typo que dejaba la ventana sin enfocar en cada corrida anterior).
	root.grab_focus()


## Pone las opciones del bench POR ENCIMA de las del usuario, sin guardarlas.
##
## POR QUÉ NO AL `_initialize`: la demo llama `Opciones.cargar()` en su
## propio `_ready`, y `cargar()` VACÍA el diccionario y lo vuelve a leer del
## `user://opciones.json`. Cualquier valor puesto antes se lo come: por eso
## `--vsync=0` no apagaba el vsync y el p95 salía clavado en el del monitor
## (1/240 s clavados), que es medir la pantalla, no el juego. Se aplican
## cuando el mundo ya está montado, que es además el momento en que lo hace el
## panel de opciones de verdad.
func _forzar_opciones() -> void:
	Opciones.cargar()
	# Sin tope de fps: si el usuario tenía 30 en `fps_max`, el p95 sale 33 ms
	# y parece que la GPU no llega cuando lo único que lo frena es el tope.
	Opciones.poner("fps_max", float(_tope))
	Opciones.poner("vsync", _vsync)
	if _calidad >= 0:
		Opciones.poner("calidad", _calidad)
	if _res != "":
		var partes: PackedStringArray = _res.to_lower().split("x")
		if partes.size() == 2:
			root.size = Vector2i(maxi(int(partes[0]), 320), maxi(int(partes[1]), 240))
	Opciones.aplicar_video()
	Opciones.poner("fps_max", float(_tope))  # `aplicar_video` la vuelve a leer
	if _escala > 0.0:
		root.scaling_3d_scale = _escala
	print("[BENCH-GPU] forzadas: calidad=%d (%s) vsync=%d tope=%d ventana=%dx%d"
		% [Opciones.entero("calidad", 2), Opciones.calidad_nombre(),
			DisplayServer.window_get_vsync_mode(), Engine.max_fps,
			root.size.x, root.size.y]
		+ (" escala=%.2f (supersampling)" % _escala if _escala > 0.0 else ""))


func _process(delta: float) -> bool:
	_frame_actual += 1
	match _fase:
		0:
			# Espera a que el mundo esté construido (el gate de carga), salvo
			# que se esté midiendo la carga: entonces se empieza ya, porque el
			# frame que al jugador le tarda 800 ms ES parte del juego.
			_espera += 1
			if _cargar:
				_fase = 1
				_frame_mundo_listo = -1
				_forzar_opciones()
				_medidor.limpiar()
				print("[BENCH-GPU] midiendo la CARGA desde el frame 0...")
			elif _mundo_listo() or _espera > 3000:
				_fase = 1
				_frame_mundo_listo = _frame_actual
				_forzar_opciones()
				_medidor.limpiar()
				print("[BENCH-GPU] mundo listo (fase %d), calentando %d frames..."
						% [_espera, _n_warmup])
		1:
			# Calienta: mide, pero no guarda (la carga progresiva distorsionaría).
			_muestrear(delta)
			if _medidor.total() >= _n_warmup:
				_medidor.limpiar()
				_fase = 2
				print("[BENCH-GPU] calentado, midiendo %d frames..." % _n_frames)
		2:
			# En modo `--cargar` los overrides se pusieron en el frame 1, pero la
			# demo vuelve a leer el `user://` del jugador cuando el mundo queda
			# listo (`_al_mundo_listo`). Se reaplican UNA vez, en esa puerta, sin
			# tocar el buffer: así la carga se mide con la calidad pedida y no
			# con la que tenga guardada el que corre el bench.
			if _cargar and not _ya_forzado and _mundo_listo():
				_ya_forzado = true
				_frame_mundo_listo = _frame_actual
				_forzar_opciones()
				print("[BENCH-GPU] overrides reaplicados en el frame %d (mundo listo)"
						% _frame_actual)
			_muestrear(delta)
			if _medidor.total() >= _n_frames:
				_fase = 3
				_informe()
		3:
			quit(0)
			return true
	return false


## ¿Terminó de construirse el mundo?
##
## OJO, LA TRAMPA: antes esto era `has_method("_al_mundo_listo") or
## get_child_count() > 20`, que da `true` en el PRIMER frame (la demo tiene 29
## hijos apenas la instanciás) — o sea, no esperaba nada y daba por warmup
## mientras la ciudad se seguía levantando. La señal buena es
## `_mundo_pendiente` de `fase12_demo`, que la demo pone en `true` al arrancar
## la construcción progresiva y en `false` cuando terminó.
##
## Y hay una segunda cosa atada a esa misma señal: cuando el mundo queda
## listo, `_al_mundo_listo` → `_instalar_fase63_64_ui` hace
## `Opciones.cargar()` + `Opciones.aplicar()`, o sea que VUELVE a leer el
## `user://opciones.json` del jugador. Por eso los overrides del bench se
## aplican DESPUÉS de esta puerta y no en `_initialize`: puestos antes, la
## demo se los come y el bench mide con el vsync y la calidad del usuario.
func _mundo_listo() -> bool:
	if _demo == null or not is_instance_valid(_demo):
		return false
	var pendiente: Variant = _demo.get("_mundo_pendiente")
	if pendiente == null:
		# Sin la señal (otro juego de pruebas): el conteo de hijos es lo que
		# hay, aunque avisa que es una puerta débil.
		return _demo.get_child_count() > 20
	return not bool(pendiente)


## Una muestra + el número de frame en que se tomó. El índice de frame es lo
## que permite atribuir un pico: sin él, un p95 de 34 ms no dice si fue el
## horneado de materiales, un GC o un spawn.
func _muestrear(delta: float) -> void:
	var ahora: int = Time.get_ticks_usec()
	var m: Dictionary = _medidor.tomar_muestra(delta)
	m["wall_ms"] = (float(ahora - _ticks_prev) / 1000.0) if _ticks_prev > 0 else 0.0
	_ticks_prev = ahora
	_frame_de_muestra.append(_frame_actual)


func _informe() -> void:
	var res: Dictionary = _medidor.informe()
	res["ventana_en_foco"] = root.has_focus()
	res["display"] = DisplayServer.get_name()
	res["gpu"] = RenderingServer.get_video_adapter_name()
	res["api"] = str(ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "forward_plus"))
	res["calidad"] = Opciones.calidad_nombre()
	# Qué post-proceso estaba encendido en la corrida: sin esto, el p50 de una
	# calidad y el de otra no significan nada, porque no se sabe si la SSAO
	# estaba o no. El número sin su contexto no es un número.
	res["efectos"] = PP.efectos_de(Opciones.entero("calidad", 2))
	res["escala_render"] = root.scaling_3d_scale
	res["vsync"] = _vsync
	res["tope_fps"] = Engine.max_fps
	res["ventana"] = "%dx%d" % [root.size.x, root.size.y]
	res["resolucion"] = "%dx%d" % [root.get_visible_rect().size.x,
		root.get_visible_rect().size.y]
	if _etiqueta != "":
		res["etiqueta"] = _etiqueta
	res["frame_mundo_listo"] = _frame_mundo_listo
	res["cpu_ms"] = _cpu_medio()
	res["picos"] = _picos(10)

	# La trampa de AGENTS.md: si el compositor estrangula el presenting, TODOS
	# los frames caen clavados en 133,3 ms (7,5 Hz exactos) con la GPU al 0% y
	# eso NO es el juego. La firma es la CUANTIZACIÓN, no el flag de foco (ver
	# `VeredictoRender`): en un setup donde la ventana nueva nunca queda
	# enfocada el presenting puede ir perfecto, y al revés.
	var p50: float = float(res.get("frame_ms_p50", 0.0))
	var p95: float = float(res.get("frame_ms_p95", 0.0))
	var fps_min: float = float(res.get("fps_min", 0.0))
	var nota: String = VEREDICTO.nota(p50, p95, fps_min, bool(res["ventana_en_foco"]))
	res["valido"] = not VEREDICTO.estrangulado(p50, p95, fps_min)
	if nota != "":
		if not bool(res["valido"]):
			printerr("[BENCH-GPU] " + nota)
		else:
			print("[BENCH-GPU] " + nota)

	print(MEDIDOR.linea_informe(res))
	print("[BENCH-GPU] gpu=%s | api=%s | %s | calidad=%s escala=%.2f | "
			% [str(res["gpu"]), str(res["api"]), str(res["resolucion"]),
				str(res["calidad"]), float(res["escala_render"])]
			+ "cpu proceso %.2f ms + fisica %.2f ms (reloj de pared %.2f ms) | "
			% [float((res["cpu_ms"] as Dictionary)["proceso"]),
				float((res["cpu_ms"] as Dictionary)["fisica"]),
				float((res["cpu_ms"] as Dictionary)["reloj"])]
			+ "draw %d | prim %d | %.0f MB | válido=%s"
			% [int(res.get("draw_calls_max", 0)), int(res.get("primitivas_max", 0)),
				float(res.get("video_mem_mb", 0.0)), str(res["valido"])])
	if not (res.get("fallos", []) as Array).is_empty():
		for f in (res.get("fallos", []) as Array):
			print("[BENCH-GPU]   FUERA: %s" % str(f))
	if _out != "":
		var f2: FileAccess = FileAccess.open(_out, FileAccess.WRITE)
		if f2 != null:
			f2.store_string(JSON.stringify(res, "  "))
			f2.close()
			print("[BENCH-GPU] informe escrito en %s" % _out)
		else:
			printerr("[BENCH-GPU] no se pudo escribir %s" % _out)
	if _dump != "":
		_volcar_muestras()
	_principal(_picos(1))


## Los `n` frames más caros, con el contexto de cada uno. Es la mitad del
## diagnóstico: un p95 sin decir QUÉ frame fue no sirve para arreglar nada.
func _picos(n: int) -> Array:
	var filas: Array = []
	var total: int = _medidor.total()
	for i in range(total):
		var m: Dictionary = _medidor.muestras[i]
		filas.append({
			"frame": _frame_de_muestra[i] if i < _frame_de_muestra.size() else i,
			"ms": float(m.get("frame_ms", 0.0)),
			"cpu": float(m.get("process_ms", 0.0)) + float(m.get("physics_ms", 0.0)),
			"draw": int(m.get("draw_calls", 0)),
			"prim": int(m.get("primitivas", 0)),
			"nodos": int(m.get("nodos", 0)),
		})
	filas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["ms"]) > float(b["ms"]))
	return filas.slice(0, maxi(n, 1))


## Lo peor de la corrida, impreso. Si esto está lleno de frames de carga, el
## problema es el arranque; si son frames de juego ya underway, es el runtime.
func _principal(picos: Array) -> void:
	if picos.is_empty():
		return
	print("[BENCH-GPU] frames más caros:")
	for p in picos:
		print("[BENCH-GPU]   frame %5d  %7.2f ms  cpu %5.2f  draw %4d  prim %7d  nodos %5d"
			% [int(p["frame"]), float(p["ms"]), float(p["cpu"]), int(p["draw"]),
				int(p["prim"]), int(p["nodos"])])


## Muestras crudas frame a frame: el p95 se puede reanalizar sin volver a correr
## el bench (y los picos se pueden correlacionar con el nodo que los causa).
func _volcar_muestras() -> void:
	var f: FileAccess = FileAccess.open(_dump, FileAccess.WRITE)
	if f == null:
		printerr("[BENCH-GPU] no se pudo escribir el dump %s" % _dump)
		return
	var filas: Array = []
	for i in range(_medidor.total()):
		var m: Dictionary = (_medidor.muestras[i] as Dictionary).duplicate()
		m["frame"] = _frame_de_muestra[i] if i < _frame_de_muestra.size() else i
		filas.append(m)
	f.store_string(JSON.stringify(filas))
	f.close()
	print("[BENCH-GPU] dump de %d muestras escrito en %s" % [filas.size(), _dump])


## El coste de CPU (lógica, sin render) por frame. Sirve para separar los dos
## cuellos: si `frame_ms` es mucho mayor que esto, la GPU es la que manda; si
## son parecidos, la lógica come el frame y bajar calidad gráfica no lo arregla.
func _cpu_medio() -> Dictionary:
	var n: int = _medidor.total()
	if n <= 0:
		return {"proceso": 0.0, "fisica": 0.0, "reloj": 0.0}
	var sp: float = 0.0
	var sf: float = 0.0
	var sr: float = 0.0
	for i in range(n):
		var m: Dictionary = _medidor.muestras[i]
		sp += float(m.get("process_ms", 0.0))
		sf += float(m.get("physics_ms", 0.0))
		sr += float(m.get("wall_ms", 0.0))
	return {"proceso": sp / float(n), "fisica": sf / float(n), "reloj": sr / float(n)}
