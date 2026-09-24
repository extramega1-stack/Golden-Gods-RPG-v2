class_name Minimapa
extends Control
## Minimapa estilo WC3/L2/MU (Fase 13).
##
## - 200x200 abajo-derecha (margen 16 px), borde dorado fino sobre fondo
##   oscuro (direccion visual L2/MU).
## - Fondo: pre-render UNA vez al `configurar` (o al llegar `terreno_listo`)
##   muestreando `terreno.color_en(x, z)` en una grilla de 144x144. Sin
##   terreno listo: fondo oscuro liso, sin reventar.
## - Transformaciones puras y testeables: `mundo_a_mapa` / `mapa_a_mundo`
##   (redondas: mundo->mapa->mundo ~= identidad).
## - Puntos: jugador = triangulo blanco orientado con `rotation.y`;
##   mobs = puntos rojos (solo lectura de `streaming.mobs_vivos()`);
##   NPCs = puntos dorados (lista fijada con `fijar_npcs`); pings = anillo
##   dorado expansible (Alt+clic, expira a los 5 s).
## - Clic izquierdo (sin Alt) / arrastrar: ordena mover al jugador
##   (`ordenar_mover_a`, modelo Flyff) con clamp al mundo y altura del
##   terreno.
## - Fade en reposo: quieto > 4 s -> modulate.a 0.35 suave; al moverse -> 1.0.
##   Solo LEE `global_position` del jugador.
## - Etiqueta de region: Label hijo debajo del mapa con el nombre de
##   `region_db.region_en(x, z)` (se refresca al cambiar; vacio si no hay).
##
## REGLA DURA de clics: `mouse_filter = STOP` solo en este Control (recibe
## _gui_input UNICAMENTE dentro de su rect por defecto) y NADA de overlays
## fullscreen: nunca se come clics fuera de su rect.
## Todo puede ser null: el minimapa dibuja lo que tenga, sin reventar.

## Lado del mapa en px (fijo).
const TAM_MAPA: float = 200.0
## Margen al borde inferior-derecho del viewport.
const MARGEN: float = 16.0
## Celdas por lado del pre-render del terreno.
const GRILLA: int = 144
## Segundos quieto antes de atenuar.
const TIEMPO_REPOSO: float = 4.0
## Alfa atenuado en reposo.
const ALFA_REPOSO: float = 0.35
## Duracion del ping en segundos.
const PING_DURACION: float = 5.0
## Umbral (m) para considerar que el jugador se movio.
const UMBRAL_MOVIMIENTO: float = 0.05
## Fase 20 (P0-2): throttle del redibujo en movimiento (10 Hz: a 6 m/s el
## paso es 0.6 m = 0.003 px, invisible) y latido en reposo con mobs
## visibles (los mobs caminan; sus puntos se refrescan a 2 Hz).
const INTERVALO_REDIBUJO: float = 0.1
const LATIDO_QUIETO: float = 0.5

const DORADO: Color = Color(0.85, 0.68, 0.25)
const FONDO_OSCURO: Color = Color(0.02, 0.02, 0.04, 0.95)
const ROJO_MOB: Color = Color(0.9, 0.15, 0.15)
const BLANCO_JUGADOR: Color = Color(1.0, 1.0, 1.0)

var _jugador: Player = null
var _terreno: Terreno = null
var _camara: CameraRig = null
var _region_db: RegionDB = null
var _streaming: StreamingMobs = null

var _fondo: ImageTexture = null
var _npcs: Array = []
## Pings: Array de {x: float, z: float, edad: float} (coords de mundo).
var _pings: Array = []
var _etiqueta: Label = null
var _region_actual: String = ""

var _ultima_pos: Vector3 = Vector3.ZERO
var _tiene_pos: bool = false
var _tiempo_quieto: float = 0.0
var _arrastrando: bool = false
## Fase 20 (P0-2): redibujo dirty-driven. Antes `_process` hacía
## `queue_redraw()` cada frame (60/s) y `_dibujar_mobs` recorría los 1127
## registros del streaming por frame. Ahora solo se redibuja si algo
## visible cambió: el jugador se movió, hay pings animados, el fade sigue
## en transición, el streaming instanció/liberó (señal) o late el
## temporizador con mobs visibles (caminan).
var _forzar_redibujo: bool = false
var _acum_redibujo: float = 0.0
var _ultima_pos_dibujo: Vector3 = Vector3.ZERO
var _tiene_dibujo: bool = false
var _alfa_objetivo: float = 1.0
var _streaming_suscrito: StreamingMobs = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = UiLayers.MINIMAPA
	# Abajo-derecha con margen; los offsets se fijan DESPUES del preset.
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var m: float = TAM_MAPA + MARGEN
	offset_left = -m
	offset_top = -m
	offset_right = -MARGEN
	offset_bottom = -MARGEN
	# Tamano explicito para que mundo_a_mapa funcione aun sin layout
	# (tests headless); con anclas reales el layout manda igual.
	size = Vector2(TAM_MAPA, TAM_MAPA)
	_construir_etiqueta()


func _construir_etiqueta() -> void:
	_etiqueta = Label.new()
	_etiqueta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_etiqueta.position = Vector2(0.0, TAM_MAPA + 4.0)
	_etiqueta.size = Vector2(TAM_MAPA, 22.0)
	_etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_etiqueta.add_theme_font_size_override("font_size", 13)
	_etiqueta.add_theme_color_override("font_color", TemaFlyFF.DORADO_CLARO)
	_etiqueta.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_etiqueta.add_theme_constant_override("shadow_offset_x", 1)
	_etiqueta.add_theme_constant_override("shadow_offset_y", 1)
	# Fase 32: pastilla oscura detrás del nombre de región (FlyFF).
	var pastilla := StyleBoxFlat.new()
	pastilla.bg_color = Color(0.02, 0.02, 0.04, 0.85)
	pastilla.set_corner_radius_all(4)
	pastilla.content_margin_left = 6.0
	pastilla.content_margin_right = 6.0
	_etiqueta.add_theme_stylebox_override("normal", pastilla)
	add_child(_etiqueta)


## Configuracion completa. Todo puede ser null: el minimapa dibuja lo que
## tenga. Pre-renderiza el fondo del terreno UNA vez (si ya esta listo;
## si no, lo intenta al llegar `terreno_listo`).
func configurar(jugador: Player, terreno: Terreno, camara: CameraRig,
		region_db: RegionDB, streaming: StreamingMobs) -> void:
	_suscribir_streaming(streaming)
	_jugador = jugador
	_terreno = terreno
	_camara = camara
	_region_db = region_db
	_streaming = streaming
	_tiempo_quieto = 0.0
	_tiene_pos = false
	_region_actual = ""
	_forzar_redibujo = false
	_acum_redibujo = 0.0
	_tiene_dibujo = false
	_alfa_objetivo = 1.0
	if _etiqueta != null:
		_etiqueta.text = ""
	if _terreno != null:
		if _terreno._colores.is_empty():
			if not _terreno.terreno_listo.is_connected(_al_terreno_listo):
				_terreno.terreno_listo.connect(_al_terreno_listo)
		else:
			_render_fondo()
	queue_redraw()


func _al_terreno_listo() -> void:
	_render_fondo()


## Suscripción al streaming para el redibujo dirty-driven: instanciar o
## liberar un mob cambia los puntos rojos (re-conectar no duplica).
func _suscribir_streaming(streaming: StreamingMobs) -> void:
	if _streaming_suscrito != null and is_instance_valid(_streaming_suscrito):
		if _streaming_suscrito.mob_instanciado.is_connected(_al_mob_cambio):
			_streaming_suscrito.mob_instanciado.disconnect(_al_mob_cambio)
		if _streaming_suscrito.mob_liberado.is_connected(_al_mob_cambio):
			_streaming_suscrito.mob_liberado.disconnect(_al_mob_cambio)
	_streaming_suscrito = streaming
	if _streaming_suscrito != null and is_instance_valid(_streaming_suscrito):
		if not _streaming_suscrito.mob_instanciado.is_connected(_al_mob_cambio):
			_streaming_suscrito.mob_instanciado.connect(_al_mob_cambio)
		if not _streaming_suscrito.mob_liberado.is_connected(_al_mob_cambio):
			_streaming_suscrito.mob_liberado.connect(_al_mob_cambio)


## El set de mobs instanciados cambió: el próximo _process redibuja.
## La firma con parámetro sirve a ambas señales (mob_instanciado/liberado).
func _al_mob_cambio(_e: Enemy) -> void:
	_forzar_redibujo = true


## Fija la lista de NPCs a dibujar (puntos dorados). Solo lectura.
func fijar_npcs(npcs: Array) -> void:
	_npcs = npcs.duplicate()
	queue_redraw()


## Lado util del mapa (el `size` real; 200x200 de respaldo sin layout).
func _tam() -> Vector2:
	if size.x > 0.0 and size.y > 0.0:
		return size
	return Vector2(TAM_MAPA, TAM_MAPA)


## Mundo (x, z) -> mapa (px). Pura y testeable.
func mundo_a_mapa(p: Vector2) -> Vector2:
	var t: Vector2 = _tam()
	return Vector2(
		(p.x - Terreno.X0) / Terreno.TAMANO * t.x,
		(p.y - Terreno.Z0) / Terreno.TAMANO * t.y)


## Mapa (px) -> mundo (x, 0, z). La altura la pone el que llama. Pura y
## testeable; redonda con `mundo_a_mapa`.
func mapa_a_mundo(p: Vector2) -> Vector3:
	var t: Vector2 = _tam()
	return Vector3(
		Terreno.X0 + p.x / t.x * Terreno.TAMANO,
		0.0,
		Terreno.Z0 + p.y / t.y * Terreno.TAMANO)


## Pre-render del fondo UNA vez: muestrea `terreno.color_en` en la grilla.
## Si el terreno no esta listo, deja `_fondo` en null (fondo oscuro liso).
func _render_fondo() -> void:
	if _terreno == null or _terreno._colores.is_empty():
		return
	var img: Image = Image.create(GRILLA, GRILLA, false, Image.FORMAT_RGB8)
	for j in range(GRILLA):
		var z: float = Terreno.Z0 + (float(j) + 0.5) / float(GRILLA) * Terreno.TAMANO
		for i in range(GRILLA):
			var x: float = Terreno.X0 + (float(i) + 0.5) / float(GRILLA) * Terreno.TAMANO
			img.set_pixel(i, j, _terreno.color_en(x, z))
	_fondo = ImageTexture.create_from_image(img)
	queue_redraw()


func _process(delta: float) -> void:
	_actualizar_fade(delta)
	_actualizar_pings(delta)
	_refrescar_region()
	if _redibujo_sucio(delta):
		queue_redraw()


## ¿Toca redibujar este frame? Pura en lecturas (testeable): decide sin
## mutar salvo el snapshot interno al redibujar. Al redibujar consume el
## forzado, reinicia el acumulador y congela la posición del jugador.
func _redibujo_sucio(delta: float) -> bool:
	_acum_redibujo += delta
	var sucio: bool = _forzar_redibujo
	# Sin dibujo previo, el primer frame siempre dibuja (sin throttle).
	if _jugador_se_movio() and (not _tiene_dibujo or _acum_redibujo >= INTERVALO_REDIBUJO):
		sucio = true
	if not _pings.is_empty():
		sucio = true
	if _fade_en_transicion():
		sucio = true
	if _acum_redibujo >= LATIDO_QUIETO and _hay_mobs():
		sucio = true
	if sucio:
		_forzar_redibujo = false
		_acum_redibujo = 0.0
		_tiene_dibujo = true
		if _jugador != null and is_instance_valid(_jugador):
			_ultima_pos_dibujo = _jugador.global_position
	return sucio


## ¿Se movió el jugador desde el último dibujo? Sin dibujo previo, sí
## (el primer frame siempre dibuja). Sin jugador, no.
func _jugador_se_movio() -> bool:
	if _jugador == null or not is_instance_valid(_jugador):
		return false
	if not _tiene_dibujo:
		return true
	return _jugador.global_position.distance_to(_ultima_pos_dibujo) > UMBRAL_MOVIMIENTO


## ¿El fade aún viaja hacia su objetivo? (modulate no necesita _draw,
## pero el cambio de alfa sí merece frames contiguos: sin esto el
## redibujo se cortaría a mitad de la transición.)
func _fade_en_transicion() -> bool:
	return absf(modulate.a - _alfa_objetivo) > 0.005


## ¿Hay mobs instanciados que caminen? (caché exacta del streaming: O(1).)
func _hay_mobs() -> bool:
	if _streaming == null or not is_instance_valid(_streaming):
		return false
	return not _streaming.mobs_vivos().is_empty()


## Fade en reposo: solo LEE la posicion del jugador.
func _actualizar_fade(delta: float) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var jp: Vector3 = _jugador.global_position
	if not _tiene_pos:
		_ultima_pos = jp
		_tiene_pos = true
		_tiempo_quieto = 0.0
	elif jp.distance_to(_ultima_pos) > UMBRAL_MOVIMIENTO:
		_ultima_pos = jp
		_tiempo_quieto = 0.0
	else:
		_tiempo_quieto += delta
	var objetivo: float = 1.0
	if _tiempo_quieto >= TIEMPO_REPOSO:
		objetivo = ALFA_REPOSO
	_alfa_objetivo = objetivo
	# lerpf es concreto (no Variant); minf evita sobrepasar en lag spikes.
	modulate.a = lerpf(modulate.a, objetivo, minf(delta * 3.0, 1.0))


func _actualizar_pings(delta: float) -> void:
	if _pings.is_empty():
		return
	for i in range(_pings.size() - 1, -1, -1):
		var pg: Dictionary = _pings[i]
		var edad: float = float(pg["edad"]) + delta
		if edad >= PING_DURACION:
			_pings.remove_at(i)
		else:
			pg["edad"] = edad


func _refrescar_region() -> void:
	if _region_db == null or _jugador == null:
		return
	if not is_instance_valid(_jugador):
		return
	var jp: Vector3 = _jugador.global_position
	var r: Dictionary = _region_db.region_en(jp.x, jp.z)
	var nombre: String = str(r.get("nombre", ""))
	if nombre != _region_actual:
		_region_actual = nombre
		if _etiqueta != null:
			_etiqueta.text = nombre


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.alt_pressed:
					_poner_ping(mb.position)
				else:
					_arrastrando = true
					_mover_a(mb.position)
			else:
				_arrastrando = false
			_aceptar()
	elif event is InputEventMouseMotion and _arrastrando:
		var mm: InputEventMouseMotion = event
		_mover_a(mm.position)
		_aceptar()


func _aceptar() -> void:
	if is_inside_tree():
		accept_event()


## Alt+clic: ping en ese punto del mundo, expira solo a los 5 s.
func _poner_ping(map_pos: Vector2) -> void:
	var w: Vector3 = mapa_a_mundo(map_pos)
	_pings.append({"x": w.x, "z": w.z, "edad": 0.0})
	queue_redraw()


## Clic normal / arrastrar: orden Flyff de mover al punto (con clamp al
## mundo y altura del terreno). Sin jugador o sin terreno util, no hace nada.
func _mover_a(map_pos: Vector2) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var w: Vector3 = mapa_a_mundo(map_pos)
	var x: float = w.x
	var z: float = w.z
	var y: float = 0.0
	if _terreno != null and is_instance_valid(_terreno):
		x = clampf(x, Terreno.X0, Terreno.X0 + Terreno.TAMANO)
		z = clampf(z, Terreno.Z0, Terreno.Z0 + Terreno.TAMANO)
		y = _terreno.altura_en(x, z)
	_jugador.ordenar_mover_a(Vector3(x, y, z))


func _rot(base: Vector2, v: Vector2, ang: float) -> Vector2:
	var c: float = cos(ang)
	var s: float = sin(ang)
	return base + Vector2(v.x * c - v.y * s, v.x * s + v.y * c)


func _draw() -> void:
	var t: Vector2 = _tam()
	var rect := Rect2(Vector2.ZERO, t)
	if _fondo != null:
		draw_texture_rect(_fondo, rect, false)
	else:
		draw_rect(rect, FONDO_OSCURO)
	_dibujar_pings()
	_dibujar_mobs()
	_dibujar_npcs()
	_dibujar_jugador()
	# Fase 32: marco FlyFF — borde dorado exterior (2 px) + filo interior
	# oscuro, encima de todo.
	draw_rect(rect, TemaFlyFF.DORADO, false, 2.0)
	draw_rect(rect.grow(-2.0), Color(0.02, 0.02, 0.04, 0.9), false, 1.0)


func _dibujar_pings() -> void:
	for p in _pings:
		var pg: Dictionary = p
		var centro: Vector2 = mundo_a_mapa(Vector2(float(pg["x"]), float(pg["z"])))
		var edad: float = float(pg["edad"])
		var radio: float = 3.0 + edad * 7.0
		var alfa: float = clampf(1.0 - edad / PING_DURACION, 0.0, 1.0)
		var col := Color(1.0, 0.84, 0.3, alfa)
		draw_arc(centro, radio, 0.0, TAU, 32, col, 2.0)
		draw_circle(centro, 2.0, col)


func _dibujar_mobs() -> void:
	if _streaming == null or not is_instance_valid(_streaming):
		return
	for e in _streaming.mobs_vivos():
		var en: Node3D = e as Node3D
		if en == null or not is_instance_valid(en):
			continue
		var c: Vector2 = mundo_a_mapa(Vector2(en.global_position.x, en.global_position.z))
		draw_circle(c, 2.0, ROJO_MOB)


func _dibujar_npcs() -> void:
	for n in _npcs:
		var npc: Node3D = n as Node3D
		if npc == null or not is_instance_valid(npc):
			continue
		var c: Vector2 = mundo_a_mapa(Vector2(npc.global_position.x, npc.global_position.z))
		draw_circle(c, 2.5, DORADO)


## Triangulo blanco orientado con `rotation.y` del jugador.
## (yaw 0 mira a -Z: en el mapa es "arriba"; rotar el triangulo por -yaw.)
func _dibujar_jugador() -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var jp: Vector3 = _jugador.global_position
	var c: Vector2 = mundo_a_mapa(Vector2(jp.x, jp.z))
	var ang: float = -_jugador.rotation.y
	var pts := PackedVector2Array([
		_rot(c, Vector2(0.0, -7.0), ang),
		_rot(c, Vector2(-5.0, 5.0), ang),
		_rot(c, Vector2(5.0, 5.0), ang),
	])
	draw_colored_polygon(pts, BLANCO_JUGADOR)
