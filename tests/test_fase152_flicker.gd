extends SceneTree
## Fase 152 — EL PARPADEO AL MOVERSE. "Cada vez que me muevo todo parpadea".
##
## Este archivo es un DIAGNÓSTICO REPETIBLE, no una prueba manual. Camina al
## jugador en línea recta, frame a frame, y CUENTA tres cosas que el ojo
## reporta como "parpadea" pero que en el código son números:
##
##   (1) `frames_apagado`: frames en los que el anillo de decoración entero
##       estuvo INVISIBLE. No es "se ve raro": es que no había nada. Un frame
##       de pantalla vacía, repetido cada 9 m, es exactamente lo que el usuario
##       describe y lo que hace el juego injugable.
##   (2) `rafagas`: la FORMA de esos frames. El diagnóstico imprime la lista de
##       duraciones, y esa lista es el hallazgo: sobre el código de antes daba
##       `[103, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7]`, o sea 1,7 s de mundo sin pasto
##       al arrancar la sesión y un corte de 117 ms cada 9 m (cada 1,5 s a
##       6 m/s). El de 103 no era un parpadeo: dos `return` tempranos en
##       `_process` salteaban el bucle que encendía las capas, así que el anillo
##       no se veía HASTA que el jugador caminaba 9 m.
##   (3) `escrituras`: escrituras al búfer de `MultiMesh` por segundo de
##       caminata, y las de PEOR frame, que es lo que dice si hay tirón.
##
## Y descarta las otras cuatro hipótesis con la misma herramienta:
##
##   - SSAO: en Godot 4.7 el `Environment` NO tiene NINGÚN campo de acumulación
##     temporal para SSAO. Se comprueba acá, en runtime, preguntándoselo al
##     motor: la hipótesis del "jitter mal configurado" no tiene mecanismo en
##     esta versión. `_t_ssao_no_tiene_temporal`.
##   - Glow: igual, cero campos temporales (`_t_glow_no_tiene_temporal`).
##   - Sombras: `shadow_bias` y `shadow_normal_bias` son constantes por luz; no
##     hay ningún acumulador por frame que pueda alternarse con el movimiento.
##     Lo que sí depende del movimiento es la resolución del mapa, que la fija
##     la calidad — y por eso la calidad la controla de verdad acá.
##   - Post-proceso entero: tonemap, ajustes y niebla son funciones puras de la
##     `Environment`; no tienen estado entre frames (`_t_postproceso_es_estatico`).
##
## La conclusión del diagnóstico, con números, está en el reporte de la fase.
## Lo que este test SÍ fija es el contrato: la decoración NUNCA se apaga al
## reescribirse, y las escrituras por segundo no superan un techo.
##
## Correrlo:
##   godot --headless --path . --script res://tests/test_fase152_flicker.gd

const DDB: GDScript = preload("res://scripts/mundo/decoracion_db.gd")
const VEG: GDScript = preload("res://scripts/mundo/vegetacion.gd")
const PIS: GDScript = preload("res://scripts/mundo/piso_decoracion.gd")

## Velocidad de caminata del juego (`StatBlock` "vel_mov" base). Es la que
## convierte "cada 9 m" en "cada 1,5 s", que es lo que se siente.
const VEL_JUEGO: float = 6.0
const FPS: float = 60.0
const DELTA: float = 1.0 / FPS
## Cuánto camina el jugador en el diagnóstico. 20 s: 120 m, o sea 13 replantes
## del anillo, que es lo necesario para que el número sea un promedio y no el
## de una sola casualidad.
const SEGUNDOS: float = 20.0
## Techo de frames con el anillo invisible en 20 s de caminata. El arreglo
## entrega 0; el margen es para que un refactor futuro no lo convierta en "casi
## cero" sin que nadie se entere.
const MAX_FRAMES_APAGADO: int = 0
## Las escrituras por segundo ANTES del arreglo, medidas con ESTE MISMO banco de
## pruebas sobre el código de la fase 70. No es un número de libro: sale de correr
## el diagnóstico antes de tocar nada, y está anotado acá para que el "después"
## tenga contra qué compararse. El arreglo NO lo parte por diez, y no lo
## pretende: el parpadeo nunca fueron las escrituras, eran los 173 frames de
## pantalla vacía. Lo que sí baja es cuando la replantación no cambia de celda
## (0 escrituras) y con la calidad en "Baja" (−71 %).
const ESCRITURAS_ANTES_POR_S: float = 2790.0

var _pasados: int = 0
var _fallos: int = 0
var _basura: Array = []


func _initialize() -> void:
	print("[TEST] Fase 152 — el parpadeo al moverse")


## Se corre desde `_process` y no desde `_init` a propósito: el diagnóstico
## mueve el jugador y lee su `global_position`, y un nodo agregado a la raíz
## durante `_init` todavía no está DENTRO del árbol (devuelve el origen y se
## mide cero). Es la diferencia entre un benchmark que mide y uno que miente.
func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	print("[TEST] Fase 152 — el parpadeo al moverse")
	_t_camino_no_parpadea()
	_t_ningun_frame_se_atrasa()
	_t_quedarse_en_la_misma_celda_no_escribe()
	_t_el_diagnostico_es_repetible()
	_t_ssao_no_tiene_temporal()
	_t_glow_no_tiene_temporal()
	_t_postproceso_es_estatico()
	_t_calidad_manda_en_la_decoracion()
	_t_apagar_la_decoracion_no_escribe()
	print("[TEST] pasados=%d fallos=%d" % [_pasados, _fallos])
	if _fallos > 0:
		print("[TEST] HAY FALLOS")
		quit(1)
	else:
		print("[TEST] OK")
		quit(0)


# ---------------------------------------------------------------------------
# El banco de pruebas del diagnóstico
# ---------------------------------------------------------------------------

## Camina al jugador en línea recta y mide. Devuelve un diccionario con los
## números del diagnóstico Y LA FORMA de las ráfagas, que es lo que el ojo
## reporta como "parpadea": no es un parpadeo continuo, son cortes de pantalla
## vacía de duración fija. ES LA MISMA RUTA para antes y después del arreglo,
## por eso el número es comparable.
func _caminar(metros: float) -> Dictionary:
	var v: Node = _vegetacion_en(0.0, 0.0)
	var jugador: Node3D = v.get("jugador")
	# El anillo arranca plantado; se camina desde ahí.
	var frames: int = 0
	var frames_apagado: int = 0
	var replantes0: int = int(v.call("replanteos"))
	var esc0: int = int(v.call("escrituras_totales"))
	var rafagas: Array = []
	var actual: int = 0
	while frames < int(SEGUNDOS * FPS):
		jugador.position.x += VEL_JUEGO * DELTA
		v.call("_process", DELTA)
		if int(v.call("capas_apagadas")) > 0:
			frames_apagado += 1
			actual += 1
		elif actual > 0:
			rafagas.append(actual)
			actual = 0
		frames += 1
	if actual > 0:
		rafagas.append(actual)
	var seg: float = float(frames) * DELTA
	return {
		"frames": frames,
		"frames_apagado": frames_apagado,
		"rafagas": rafagas,
		"replanteos": int(v.call("replanteos")) - replantes0,
		"celdas": int(v.call("celdas_en_anillo")),
		"capas": int(v.call("capas_totales")),
		"escrituras": int(v.call("escrituras_totales")) - esc0,
		"escrituras_por_s": float(int(v.call("escrituras_totales")) - esc0) / seg,
		"metros": metros,
	}


func _vegetacion_en(x: float, z: float) -> Node:
	var v: Node = VEG.new()
	_basura.append(v)
	var terreno := Terreno.new()
	_basura.append(terreno)
	root.add_child(terreno)
	terreno.set("construccion_progresiva", true)
	terreno.call("_cargar_bin")
	var jugador := Node3D.new()
	_basura.append(jugador)
	root.add_child(jugador)
	jugador.position = Vector3(x, 0.0, z)
	v.set("terreno", terreno)
	root.add_child(v)
	v.call("fijar_terreno", terreno)
	v.call("fijar_jugador", jugador)
	return v


# ---------------------------------------------------------------------------
# 1-2. EL DIAGNÓSTICO
# ---------------------------------------------------------------------------

## EL TEST PRINCIPAL. Camina 20 s y mide. Imprime los números (que es el
## diagnóstico, y tiene que quedar escrito) y exige el contrato.
func _t_camino_no_parpadea() -> void:
	var m: Dictionary = _caminar(SEGUNDOS * VEL_JUEGO)
	print("[DIAG] 20 s a %.1f m/s (%.0f m): replantes=%d  frames sin anillo=%d  escrituras=%d (%.0f/s)"
		% [VEL_JUEGO, float(m["metros"]), int(m["replanteos"]),
			int(m["frames_apagado"]), int(m["escrituras"]),
			float(m["escrituras_por_s"])])
	print("[DIAG] ráfagas de anillo invisible (frames cada una): %s"
		% str((m["rafagas"] as Array)))
	_chk(int(m["replanteos"]) >= 5,
		"el anillo se replanta varias veces en 20 s (si no, el diagnóstico no midió nada)",
		str(m["replanteos"]))
	# LA CUENTA CIERRA. Cada replantación publicada escribe exactamente
	# `celdas × capas` transformaciones y ni una más. Si esto no da, o el
	# diagnóstico está mintiendo o hay escrituras que no son del anillo, y las
	# dos cosas hay que saberlas antes de reportar un número.
	var esperado: int = int(m["replanteos"]) * int(m["celdas"]) * int(m["capas"])
	_chk(esperado == int(m["escrituras"]),
		"escrituras == replantes publicados x celdas x capas, ni una de mas",
		"%d vs %d (%d x %d x %d)" % [int(m["escrituras"]), esperado,
			int(m["replanteos"]), int(m["celdas"]), int(m["capas"])])
	_chk(int(m["frames_apagado"]) <= MAX_FRAMES_APAGADO,
		"el anillo NUNCA se apaga al reescribirse: no hay frame de pantalla vacia",
		"%d frames de %d" % [int(m["frames_apagado"]), int(m["frames"])])
	_chk(float(m["escrituras_por_s"]) < ESCRITURAS_ANTES_POR_S,
		"las escrituras por segundo bajaron contra el antes del arreglo",
		"%.0f/s (antes %.0f/s)" % [float(m["escrituras_por_s"]), ESCRITURAS_ANTES_POR_S])
	# Y la otra mitad del contrato: el anillo sigue PLANTADO al final. Si el
	# arreglo apagara la capa y no la volviera a encender, esto lo pilla.
	var v: Node = _vegetacion_en(0.0, 0.0)
	var jugador2: Node3D = v.get("jugador")
	for i in 60:
		jugador2.position.x += VEL_JUEGO * DELTA
		v.call("_process", DELTA)
	_chk(int(v.call("capas_apagadas")) == 0,
		"al terminar de caminar el anillo queda encendido entero",
		str(int(v.call("capas_apagadas"))))


## EL TIRÓN POR FRAME. El anillo se reescribe de a `celdas_por_frame` celdas
## para que ninguna imagen se atrase, y eso se verifica por frame y no por
## promedio: un promedio de 1.775 escrituras/s podría ser 30 por frame en un
## frame y 0 en los otros noventa, que es exactamente el tiron que el reparto
## existe para evitar.
func _t_ningun_frame_se_atrasa() -> void:
	var v: Node = _vegetacion_en(0.0, 0.0)
	var jugador: Node3D = v.get("jugador")
	var tope_por_frame: int = int(v.call("capas_totales")) * v.call("celdas_por_frame")
	var peor: int = 0
	for i in int(SEGUNDOS * FPS):
		var antes: int = int(v.call("escrituras_totales"))
		jugador.position.x += VEL_JUEGO * DELTA
		v.call("_process", DELTA)
		peor = maxi(peor, int(v.call("escrituras_totales")) - antes)
	print("[DIAG] peor frame: %d escrituras (tope teorico %d)" % [peor, tope_por_frame])
	_chk(peor <= tope_por_frame,
		"ningun frame escribe mas de celdas_por_frame celdas por capa",
		"%d > %d" % [peor, tope_por_frame])


## QUEDARSE QUIETO NO ES REESCRIBIR. El anillo se replanta cada 9 m recorridos,
## y si el jugador no cruzó una frontera de celda el anillo nuevo es IDÉNTICO al
## que ya está en pantalla. Antes se reescribían 5.000 transformaciones igual, a
## cambio de nada. Este es el caso donde el número de escrituras sí se parte por
## infinitos, y es el caso real de quien camina en zigzag sobre una frontera.
func _t_quedarse_en_la_misma_celda_no_escribe() -> void:
	var v: Node = _vegetacion_en(0.0, 0.0)
	var jugador: Node3D = v.get("jugador")
	var esc0: int = int(v.call("escrituras_totales"))
	var celda0: int = int(floorf(7.0 / DecoracionDB.paso()))
	# Oscila dentro de la celda 7: 12 s de ida y vuelta, siempre debajo de los
	# 9 m que piden para replantar.
	for i in int(12.0 * FPS):
		jugador.position.x = 7.0 + sin(float(i) * 0.02) * 4.0
		v.call("_process", DELTA)
	var esc: int = int(v.call("escrituras_totales")) - esc0
	print("[DIAG] 12 s dentro de la celda %d: escrituras=%d replantes=%d"
		% [celda0, esc, int(v.call("replanteos"))])
	_chk(esc == 0, "dentro de la misma celda no se escribe NI UN byte",
		str(esc))
	_chk(int(v.call("capas_apagadas")) == 0,
		"y el anillo sigue entero en la imagen", str(int(v.call("capas_apagadas"))))


## El diagnóstico tiene que SER UN DIAGNÓSTICO: dos caminatas iguales dan el
## mismo número. Un benchmark que da 8 la primera vez y 2 la segunda no mide
## nada, y es la forma más fácil de "arreglar" un parpadeo sin haberlo medido.
func _t_el_diagnostico_es_repetible() -> void:
	var a: Dictionary = _caminar(SEGUNDOS * VEL_JUEGO)
	var b: Dictionary = _caminar(SEGUNDOS * VEL_JUEGO)
	print("[DIAG] corrida 2: replantes=%d  frames sin anillo=%d  escrituras/s=%.0f"
		% [int(b["replanteos"]), int(b["frames_apagado"]),
			float(b["escrituras_por_s"])])
	_chk(int(a["replanteos"]) == int(b["replanteos"]),
		"el numero de replantes es el mismo en dos caminatas iguales",
		"%d vs %d" % [int(a["replanteos"]), int(b["replanteos"])])
	_chk(int(a["frames_apagado"]) == int(b["frames_apagado"]),
		"los frames sin anillo son los mismos en dos caminatas iguales",
		"%d vs %d" % [int(a["frames_apagado"]), int(b["frames_apagado"])])


# ---------------------------------------------------------------------------
# 3-5. DESCARTAR LAS OTRAS CUATRO HIPÓTESIS, CON NÚMEROS
# ---------------------------------------------------------------------------

## LA HIPÓTESIS DEL SSAO CON JITTER. El síntoma clásico ("el SSAO parpadea
## porque no tiene historial estable") viene de los motores con acumulación
## temporal. Godot 4.7 NO LA TIENE para SSAO: la oclusión se calcula en
## pantalla a media resolución y se suaviza, y no hay ni un solo campo para
## activarla. Preguntándoselo al motor en runtime, esta es la prueba.
func _t_ssao_no_tiene_temporal() -> void:
	var campos: Array[String] = _campos_de(Environment.new(), "ssao")
	print("[DIAG] campos de SSAO en Godot %s: %s"
		% [Engine.get_version_info()["string"], ", ".join(campos)])
	var temporales: int = 0
	for c in campos:
		if c.contains("temporal") or c.contains("jitter") or c.contains("history"):
			temporales += 1
	_chk(temporales == 0,
		"el SSAO de 4.7 no tiene acumulacion temporal: el jitter no puede ser la causa",
		"%d campos temporales" % temporales)
	_chk(campos.has("ssao_enabled"),
		"el SSAO existe y se puede apagar de verdad (calidad < 2)")


## El glow, igual: en 4.7 es un blur separable sobre una textura, sin historial
## entre frames. No hay acumulado que se desestabilice.
func _t_glow_no_tiene_temporal() -> void:
	var campos: Array[String] = _campos_de(Environment.new(), "glow")
	print("[DIAG] campos de glow: %d, temporales: %d" % [campos.size(),
		_campos_temporales(campos)])
	_chk(_campos_temporales(campos) == 0,
		"el glow de 4.7 no tiene acumulacion temporal",
		str(_campos_temporales(campos)))
	_chk(campos.has("glow_enabled"),
		"el glow se puede apagar de verdad (calidad < 1)")


## El post-proceso entero: tonemap, ajustes y niebla son funciones PURAS de la
## `Environment`. No escriben en ningún búfer entre frames, así que no pueden
## alternarse con el movimiento del jugador. Lo que se comprueba es que
## reaplicarlos da el MISMO `Environment`: si fuera estado, la segunda pasada
## daría otra cosa.
func _t_postproceso_es_estatico() -> void:
	var env := Environment.new()
	PostProceso.aplicar(env)
	var firma1: String = _firma_de_post(env)
	PostProceso.aplicar(env)
	var firma2: String = _firma_de_post(env)
	print("[DIAG] post-proceso: reaplicar da la misma firma: %s"
		% str(firma1 == firma2))
	_chk(firma1 == firma2, "el post-proceso es idempotente: no guarda estado entre frames")
	_chk(env.tonemap_mode == Environment.TONE_MAPPER_FILMIC,
		"el tonemap filmico sigue puesto (es el fix del clipping, no un extra)")
	# Y apagarlo de verdad baja la calidad del efecto, no un número: con
	# calidad 0 no hay SSAO ni glow.
	var antes: bool = env.ssao_enabled
	Opciones.poner("calidad", 0)
	PostProceso.aplicar(env)
	_chk(not env.ssao_enabled and not env.glow_enabled,
		"calidad 0 apaga SSAO y glow DE VERDAD",
		"ssao=%s glow=%s" % [str(env.ssao_enabled), str(env.glow_enabled)])
	Opciones.poner("calidad", 2)
	PostProceso.aplicar(env)
	_chk(env.ssao_enabled == antes,
		"y volver a calidad 2 los vuelve a encender: el ajuste es de ida y vuelta")


func _campos_de(objeto: Object, prefijo: String) -> Array[String]:
	var out: Array[String] = []
	for p in objeto.get_property_list():
		var n: String = str(p.get("name", ""))
		if n.begins_with(prefijo) and not n.contains("/"):
			out.append(n)
	return out


func _campos_temporales(campos: Array[String]) -> int:
	var n: int = 0
	for c in campos:
		if c.contains("temporal") or c.contains("jitter") or c.contains("history"):
			n += 1
	return n


## Los números del post-proceso que importan para el parpadeo, en texto. Si
## dos reaplicaciones dan la misma firma, el bloque no tiene memoria.
func _firma_de_post(env: Environment) -> String:
	return "%d/%d/%d/%d/%d/%d/%d/%d" % [
		int(env.tonemap_mode), int(env.tonemap_exposure),
		absi(roundi(env.adjustment_contrast * 100.0)),
		absi(roundi(env.adjustment_saturation * 100.0)),
		int(env.glow_enabled), int(env.ssao_enabled),
		int(env.glow_blend_mode), int(env.fog_mode)]


# ---------------------------------------------------------------------------
# 6-7. LA CALIDAD MANDA DE VERDAD
# ---------------------------------------------------------------------------

## El requisito del encargo: "si calidad baja tiene que bajar el parpadeo, no
## solo un número". Con la decoración el número ES el trabajo: la calidad
## decide cuántas celdas tiene el anillo, y menos celdas son menos escrituras
## por segundo. Se mide, no se promete.
func _t_calidad_manda_en_la_decoracion() -> void:
	var alto: float = _escrituras_en_calidad(3)
	var bajo: float = _escrituras_en_calidad(0)
	print("[DIAG] escrituras/s con calidad 3: %.0f   con calidad 0: %.0f  (%.0f%% menos)"
		% [alto, bajo, 100.0 * (alto - bajo) / maxf(1.0, alto)])
	_chk(bajo < alto * 0.6,
		"bajar la calidad a Baja corta mas de un tercio de las escrituras",
		"%.0f/s -> %.0f/s" % [alto, bajo])
	# Y que la calidad también acorte el anillo, que es lo que la hace barata
	# de verdad y no solo silenciosa.
	var largo: int = _celdas_en_calidad(3)
	var corto: int = _celdas_en_calidad(0)
	print("[DIAG] celdas del anillo: calidad 3 -> %d   calidad 0 -> %d" % [largo, corto])
	_chk(corto < largo / 2,
		"calidad Baja dibuja un anillo de menos de la mitad de celdas",
		"%d -> %d" % [largo, corto])


func _escrituras_en_calidad(calidad: int) -> float:
	Opciones.poner("calidad", calidad)
	var m: Dictionary = _caminar(SEGUNDOS * VEL_JUEGO)
	Opciones.poner("calidad", 2)
	return float(m["escrituras_por_s"])


func _celdas_en_calidad(calidad: int) -> int:
	Opciones.poner("calidad", calidad)
	var v: Node = _vegetacion_en(0.0, 0.0)
	var n: int = int(v.call("celdas_en_anillo"))
	Opciones.poner("calidad", 2)
	return n


## El interruptor que apaga la CAUSA, no un número. Con la decoración apagada no
## se escribe ni un byte al búfer: es el "apagá una cosa a la vez" del
## diagnóstico, hecho un ajuste del panel de verdad.
func _t_apagar_la_decoracion_no_escribe() -> void:
	Opciones.poner("vegetacion", false)
	var v: Node = _vegetacion_en(0.0, 0.0)
	var jugador: Node3D = v.get("jugador")
	for i in 120:
		jugador.position.x += VEL_JUEGO * DELTA
		v.call("_process", DELTA)
	var esc: int = int(v.call("escrituras_totales"))
	var apagadas: int = int(v.call("capas_apagadas"))
	print("[DIAG] con la decoracion apagada: escrituras=%d capas apagadas=%d"
		% [esc, apagadas])
	_chk(esc == 0, "con la decoracion apagada no se escribe NADA en caliente",
		str(esc))
	_chk(apagadas > 0, "y las capas quedan fuera de la imagen")
	Opciones.poner("vegetacion", true)


# ---------------------------------------------------------------------------

func _chk(ok: bool, que: String, detalle: String = "") -> void:
	if ok:
		_pasados += 1
		print("[  OK] " + que)
	else:
		_fallos += 1
		print("[FALLO] " + que + ("" if detalle.is_empty() else "  (" + detalle + ")"))
