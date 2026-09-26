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
## Exit code 0 siempre (es un bench, no un test): el veredicto sale impreso.

const MEDIDOR: GDScript = preload("res://scripts/core/medidor_gpu.gd")

var _medidor: RefCounted = null
var _demo: Node = null
var _fase: int = 0
var _n_frames: int = 600
var _n_warmup: int = 180
var _espera: int = 0
var _out: String = ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_n_frames = maxi(int(a.get_slice("=", 1)), 30)
		elif a.begins_with("--warmup="):
			_n_warmup = maxi(int(a.get_slice("=", 1)), 0)
		elif a.begins_with("--out="):
			_out = a.get_slice("=", 1)
	_medidor = MEDIDOR.new()
	print("[BENCH-GPU] frames=%d warmup=%d" % [_n_frames, _n_warmup])
	if DisplayServer.get_name() == "headless":
		printerr("[BENCH-GPU] AVISO: sin ventana el render es dummy; los valores de GPU serán 0")
	# El p95 mide el tiempo de frame REAL, que incluye la espera por presentar.
	# En Wayland, una ventana sin el foco la estrangula el compositor (~7 Hz:
	# 133 ms clavados en cada frame con la GPU al 0%), y el veredicto sale
	# "FUERA DE PRESUPUESTO" por algo que NO es el juego. Se registra si la
	# ventana tenía el foco, para que el número venga con su contexto.
	if not root.has_focus():
		printerr("[BENCH-GPU] AVISO: la ventana NO tiene el foco. Bajo Wayland el "
			+ "compositor estrangula el presenting y el p95 sale inventado; "
			+ "dale foco a la ventana y vuelve a correrlo. El p50 sigue valiendo.")
	_demo = load("res://scenes/demo/fase14_demo.tscn").instantiate()
	root.add_child(_demo)
	# Pide el foco una vez mapeada la ventana: sin esto, en Wayland el
	# compositor estrangula el presenting a ~7 Hz y el p95 no mide el juego.
	root.request_focus()


func _process(delta: float) -> bool:
	match _fase:
		0:
			# Espera a que el mundo esté construido (el gate de carga).
			_espera += 1
			if _mundo_listo() or _espera > 3000:
				_fase = 1
				_medidor.limpiar()
				print("[BENCH-GPU] mundo listo (fase %d), calentando %d frames..."
						% [_espera, _n_warmup])
		1:
			# Calienta: mide, pero no guarda (la carga progresiva distorsionaría).
			_medidor.tomar_muestra(delta)
			if _medidor.total() >= _n_warmup:
				_medidor.limpiar()
				_fase = 2
				print("[BENCH-GPU] calentado, midiendo %d frames..." % _n_frames)
		2:
			_medidor.tomar_muestra(delta)
			if _medidor.total() >= _n_frames:
				_fase = 3
				_informe()
		3:
			quit(0)
			return true
	return false


func _mundo_listo() -> bool:
	if _demo == null or not is_instance_valid(_demo):
		return false
	return _demo.has_method("_al_mundo_listo") or _demo.get_child_count() > 20


func _informe() -> void:
	var res: Dictionary = _medidor.informe()
	res["ventana_en_foco"] = root.has_focus()
	res["display"] = DisplayServer.get_name()
	print(MEDIDOR.linea_informe(res))
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
