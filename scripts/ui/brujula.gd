class_name Brujula
extends Control
## Brújula superior (Fase 13): tira centrada ~420×30 px con rosa de los
## vientos que gira con la cámara + marcador dorado del objetivo de la
## misión activa (diamante + distancia en metros).
##
## Solo LEE datos y señales: jamás escribe stats ni mueve al jugador.
## REGLA DURA de overlays (lección 11): `mouse_filter = IGNORE` siempre;
## este Control nunca intercepta un clic del juego.
##
## Convención de ángulos: norte del mundo = -Z = ángulo 0; este = +X =
## ángulo +90°. El offset en la tira es proporcional a
## wrapf(angulo_mundo - yaw_camara, -PI, PI): 0 = al frente (centrado),
## positivo = a la derecha. `CameraRig.yaw()` (radianes) es el yaw.

## Ángulos de mundo (radianes) de los cardinales: N=0 (-Z), E=+90° (+X),
## S=180°, O=-90°. Consts Array TIPADAS (lección 4): sin tipar, el
## indexado es Variant y `:=` posterior truena.
const LETRAS: Array[String] = ["N", "E", "S", "O"]
const ANGULOS: Array[float] = [0.0, PI / 2.0, PI, -PI / 2.0]
## Ticks menores cada 45° (sin letra).
const ANGULOS_MENORES: Array[float] = [
	PI / 4.0, 3.0 * PI / 4.0, -3.0 * PI / 4.0, -PI / 4.0]
## Más allá de este ángulo el marcador de misión se pega al borde (~75°).
const ANG_BORDE: float = 1.3090
const ANCHO: float = 420.0
const ALTO: float = 30.0

const COLOR_FONDO: Color = Color(0.015, 0.015, 0.03, 0.62)
const COLOR_DORADO: Color = Color(0.92, 0.78, 0.42, 1.0)
const COLOR_DORADO_DIM: Color = Color(0.55, 0.45, 0.25, 0.9)
const COLOR_BORDE: Color = Color(0.78, 0.62, 0.28, 0.85)
const COLOR_MARCADOR: Color = Color(1.0, 0.8, 0.2, 1.0)
const TAM_LETRA: int = 15
const TAM_LETRA_DIST: int = 11
## Fase 20 (P0-2): redibujo dirty-driven. Antes `_process` hacía
## `queue_redraw()` cada frame con `draw_string` por frame. La tira solo
## cambia si gira la cámara, se mueve el jugador/objetivo o cambia la
## misión: en reposo total no se redibuja.
const UMBRAL_YAW: float = 0.002
const UMBRAL_POS: float = 0.5

var _camara: CameraRig = null
var _jugador: Player = null
var _quest_log: QuestLog = null
var _streaming: StreamingMobs = null
var _npcs: Array = []
var _objetivo: Node3D = null
## Snapshot de la última vista dibujada (para el dirty-driven).
var _tiene_vista: bool = false
var _vista_yaw: float = 0.0
var _vista_jug: Vector3 = Vector3.ZERO
var _vista_tiene_jug: bool = false
var _vista_obj: Vector3 = Vector3.ZERO
var _vista_tiene_obj: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Arriba-centro; los offsets se fijan DESPUÉS del preset (lo resetea).
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -ANCHO / 2.0
	offset_right = ANCHO / 2.0
	offset_top = 8.0
	offset_bottom = 8.0 + ALTO


## Offset horizontal (px) en la tira para un ángulo de mundo, dado el yaw
## de la cámara (radianes). 0 = justo al frente (centrado). Pura/testeable.
static func offset_para(angulo_mundo: float, yaw_cam: float, ancho: float) -> float:
	var theta: float = wrapf(angulo_mundo - yaw_cam, -PI, PI)
	return offset_rel(theta, ancho)


## Offset para un ángulo relativo ya envuelto en [-PI, PI]. Pura/testeable.
static func offset_rel(theta: float, ancho: float) -> float:
	return ancho * theta / PI


## Offset del marcador de misión: igual que los cardinales, pero si el
## objetivo está detrás (|θ| > ~75°) el diamante se pega al borde.
## Pura/testeable.
static func offset_marcador(angulo_mundo: float, yaw_cam: float, ancho: float) -> float:
	var theta: float = wrapf(angulo_mundo - yaw_cam, -PI, PI)
	if theta > ANG_BORDE:
		theta = ANG_BORDE
	elif theta < -ANG_BORDE:
		theta = -ANG_BORDE
	return offset_rel(theta, ancho)


## Conecta las fuentes de datos (todas nullable: nada revienta con null).
## Si hay quest_log, se suscribe a su señal `cambiada` para refrescar el
## objetivo (re-conectar no duplica la suscripción).
func configurar(camara: CameraRig, jugador: Player, quest_log: QuestLog,
		streaming: StreamingMobs) -> void:
	if _quest_log != null and _quest_log.cambiada.is_connected(_al_quest_cambiada):
		_quest_log.cambiada.disconnect(_al_quest_cambiada)
	_camara = camara
	_jugador = jugador
	_quest_log = quest_log
	_streaming = streaming
	if _quest_log != null and not _quest_log.cambiada.is_connected(_al_quest_cambiada):
		_quest_log.cambiada.connect(_al_quest_cambiada)
	_refrescar_objetivo()


## Fija la lista de NPCs del mundo (se busca por `npc_id`). Reemplaza la
## anterior y refresca el objetivo.
func fijar_npcs(npcs: Array) -> void:
	_npcs = npcs.duplicate()
	_refrescar_objetivo()


## Objetivo actual de la brújula (Node3D) o null si no hay marcador.
## Solo lectura; la demo puede usarlo para depuración.
func objetivo_actual() -> Node3D:
	return _objetivo


## Resuelve el objetivo del marcador según la misión activa:
##  - sin misión → null (sin marcador).
##  - estado "lista" → NPC con npc_id == quest["npc_origen"].
##  - estado "activa", primer objetivo "matar" → mob vivo más cercano del
##    arquetipo pedido; "hablar" → NPC con npc_id == objetivo["npc"];
##    otro tipo → NPC npc_origen.
##  - sin candidato (NPC/mob inexistente) → null.
## Pura en datos (solo lee); testeable.
func resolver_objetivo() -> Node3D:
	if _quest_log == null:
		return null
	var mision: Dictionary = _quest_log.mision_activa()
	if mision.is_empty():
		return null
	var quest: Dictionary = mision.get("quest", {})
	var estado: String = str(mision.get("estado", ""))
	if estado == "lista":
		return _npc_por_id(str(quest.get("npc_origen", "")))
	if estado != "activa":
		return null
	var objetivos: Array = quest.get("objetivos", [])
	if objetivos.is_empty():
		return null
	var obj: Dictionary = objetivos[0]
	var tipo: String = str(obj.get("tipo", ""))
	if tipo == "matar":
		return _mob_cercano(str(obj.get("arquetipo", "")))
	if tipo == "hablar":
		return _npc_por_id(str(obj.get("npc", "")))
	return _npc_por_id(str(quest.get("npc_origen", "")))


func _npc_por_id(npc_id: String) -> NPC:
	if npc_id == "":
		return null
	for n in _npcs:
		var npc: NPC = n as NPC
		if npc != null and is_instance_valid(npc) and npc.npc_id == npc_id:
			return npc
	return null


func _mob_cercano(arquetipo: String) -> Enemy:
	if arquetipo == "" or _streaming == null or _jugador == null:
		return null
	var mejor: Enemy = null
	var mejor_d: float = INF
	var jp: Vector3 = _jugador.global_position
	for m in _streaming.mobs_vivos():
		var e: Enemy = m as Enemy
		if e == null or not is_instance_valid(e):
			continue
		if e.arquetipo_id != arquetipo:
			continue
		var d: float = _dist_plana(jp, e.global_position)
		if d < mejor_d:
			mejor_d = d
			mejor = e
	return mejor


## Ángulo de mundo (radianes, convención N=0/E=+90°) de la dirección
## jugador → objetivo. atan2 tiene retorno float declarado; el tipo
## explícito evita el warning de Variant (lección 8).
func _angulo_hacia(objetivo: Node3D) -> float:
	var d: Vector3 = objetivo.global_position - _jugador.global_position
	var ang: float = atan2(d.x, -d.z)
	return ang


func _distancia_hacia(objetivo: Node3D) -> float:
	return _dist_plana(_jugador.global_position, objetivo.global_position)


static func _dist_plana(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


func _yaw_camara() -> float:
	if _camara == null or not is_instance_valid(_camara):
		return 0.0
	return _camara.yaw()


func _al_quest_cambiada() -> void:
	_refrescar_objetivo()


func _refrescar_objetivo() -> void:
	_objetivo = resolver_objetivo()
	# La misión cambió: el marcador puede aparecer/desaparecer.
	queue_redraw()


func _process(_delta: float) -> void:
	# Si el objetivo se liberó (mob muerto/streaming), re-resolver.
	if _objetivo != null and not is_instance_valid(_objetivo):
		_refrescar_objetivo()
	elif _vista_cambio():
		queue_redraw()


## ¿Cambió la vista desde el último dibujo? Compara yaw de cámara y
## posiciones de jugador/objetivo contra el snapshot (testeable). Al
## detectar cambio, actualiza el snapshot. Sin snapshot previo, sí.
func _vista_cambio() -> bool:
	var yaw: float = _yaw_camara()
	var jug: Vector3 = Vector3.ZERO
	var tiene_jug: bool = _jugador != null and is_instance_valid(_jugador)
	if tiene_jug:
		jug = _jugador.global_position
	var obj: Vector3 = Vector3.ZERO
	var tiene_obj: bool = _objetivo != null and is_instance_valid(_objetivo)
	if tiene_obj:
		obj = _objetivo.global_position
	if not _tiene_vista:
		_guardar_vista(yaw, jug, tiene_jug, obj, tiene_obj)
		return true
	var cambio: bool = absf(yaw - _vista_yaw) > UMBRAL_YAW
	if tiene_jug != _vista_tiene_jug:
		cambio = true
	elif tiene_jug and jug.distance_to(_vista_jug) > UMBRAL_POS:
		cambio = true
	if tiene_obj != _vista_tiene_obj:
		cambio = true
	elif tiene_obj and obj.distance_to(_vista_obj) > UMBRAL_POS:
		cambio = true
	if cambio:
		_guardar_vista(yaw, jug, tiene_jug, obj, tiene_obj)
	return cambio


## Congela la vista actual como "ya dibujada".
func _guardar_vista(yaw: float, jug: Vector3, tiene_jug: bool,
		obj: Vector3, tiene_obj: bool) -> void:
	_tiene_vista = true
	_vista_yaw = yaw
	_vista_jug = jug
	_vista_tiene_jug = tiene_jug
	_vista_obj = obj
	_vista_tiene_obj = tiene_obj


func _draw() -> void:
	var ancho: float = size.x
	var alto: float = size.y
	if ancho <= 0.0 or alto <= 0.0:
		return
	var cx: float = ancho * 0.5
	var yaw: float = _yaw_camara()
	# Fondo oscuro semitransparente estilo L2/MU + filetes dorados.
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_FONDO)
	draw_line(Vector2(0.0, 0.5), Vector2(ancho, 0.5), COLOR_BORDE, 1.0)
	draw_line(Vector2(0.0, alto - 0.5), Vector2(ancho, alto - 0.5), COLOR_BORDE, 1.0)
	var fuente: Font = get_theme_default_font()
	# Ticks menores cada 45° (solo los visibles al frente, |θ| <= 90°).
	for a: float in ANGULOS_MENORES:
		var tm: float = wrapf(a - yaw, -PI, PI)
		if absf(tm) > PI / 2.0:
			continue
		var xm: float = cx + offset_rel(tm, ancho)
		draw_line(Vector2(xm, 4.0), Vector2(xm, 9.0), COLOR_DORADO_DIM, 1.0)
	# Letras cardinales N/E/S/O (margen para que no se corten al borde).
	for i in range(LETRAS.size()):
		var tc: float = wrapf(ANGULOS[i] - yaw, -PI, PI)
		if absf(tc) > PI / 2.0 + 0.08:
			continue
		var xc: float = cx + offset_rel(tc, ancho)
		draw_string(fuente, Vector2(xc - 30.0, 20.0), LETRAS[i],
			HORIZONTAL_ALIGNMENT_CENTER, 60.0, TAM_LETRA, COLOR_DORADO)
	# Marca central: hacia dónde mira la cámara.
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 5.0, 1.0), Vector2(cx + 5.0, 1.0), Vector2(cx, 8.0)]),
		COLOR_DORADO)
	_dibujar_marcador(cx, yaw, ancho, fuente)


func _dibujar_marcador(cx: float, yaw: float, ancho: float, fuente: Font) -> void:
	if _objetivo == null or not is_instance_valid(_objetivo):
		return
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var x: float = cx + offset_marcador(_angulo_hacia(_objetivo), yaw, ancho)
	# Diamante dorado.
	var diamante := PackedVector2Array([
		Vector2(x, 3.0), Vector2(x + 5.0, 9.0),
		Vector2(x, 15.0), Vector2(x - 5.0, 9.0)])
	draw_colored_polygon(diamante, COLOR_MARCADOR)
	# Distancia en metros bajo el diamante.
	var texto: String = "%d m" % int(_distancia_hacia(_objetivo))
	var xt: float = clampf(x, 45.0, ancho - 45.0)
	draw_string(fuente, Vector2(xt - 45.0, 28.0), texto,
		HORIZONTAL_ALIGNMENT_CENTER, 90.0, TAM_LETRA_DIST, COLOR_DORADO)
