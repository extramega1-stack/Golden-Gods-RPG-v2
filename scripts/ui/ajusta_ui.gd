class_name AjustaUI
extends RefCounted
## Bloque 67: hace que los paneles se ajusten al viewport.
##
## POR QUÉ EXISTE: con `canvas_items` + `expand` (project.godot), el juego ya
## escala con la ventana, pero los 12 paneles con `size = Vector2(560, 470)` y
## `position = Vector2(-280, -235)` seguían siendo DUROS: en una ventana
## estrecha se salían por los bordes, y en una enorme quedaban RIDÍCULOS en
## una esquina.
##
## LA REGLA, Y POR QUÉ NO ES "TODO ANCLADO": un panel de juego (el inventario,
## las habilidades) tiene un tamaño que el jugador aprende a memoria; si se
## estira con la ventana, la posición de cada botón cambia y se pierde la
## familiaridad. Lo que tiene que pasar es lo de la mayoría de juegos:
## - TAMAÑO proporcional (con un mínimo y un máximo) para que en una ventana
##   enorme no se convierta en una pantalla vacía,
## - y ANCLADO a los bordes (no centrado en coordenadas absolutas) para que
##   en una ventana estrecha no se salga.
##
## Se aplica una sola vez por panel (en su `_ready`), no por frame.

## Proporción del viewport que ocupará el panel, por defecto.
const ESCALA_ANCHO: float = 0.44
const ESCALA_ALTO: float = 0.66
## Nunca más pequeño que esto, ni más grande: por debajo el texto no se lee,
## por encima el panel es una pantalla y el juego se ve en una esquina.
const ANCHO_MIN: float = 380.0
const ANCHO_MAX: float = 680.0
const ALTO_MIN: float = 320.0
const ALTO_MAX: float = 820.0


## Ajusta un panel centrado al viewport. `ancho_rel` y `alto_rel` son la
## proporción del viewport (0.0 = usar la de por defecto). Devuelve el tamaño
## final, que el test usa para comprobar los límites.
static func centrar(panel: Control, ancho_rel: float = 0.0, alto_rel: float = 0.0) -> Vector2:
	if panel == null or not is_instance_valid(panel):
		return Vector2.ZERO
	var vp: Vector2 = _viewport()
	var aw: float = ancho_rel if ancho_rel > 0.0 else ESCALA_ANCHO
	var ah: float = alto_rel if alto_rel > 0.0 else ESCALA_ALTO
	var w: float = clampf(vp.x * aw, ANCHO_MIN, ANCHO_MAX)
	var h: float = clampf(vp.y * ah, ALTO_MIN, ALTO_MAX)
	# El tamaño se fuerza con `custom_minimum_size` + `size`, y la posición se
	# recalcula al centrar. Con `PRESET_CENTER` el anclaje ya lo hace, pero
	# muchos paneles fijan `position` a mano después, así que se corrige aquí.
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(w, h)
	panel.size = Vector2(w, h)
	panel.position = Vector2((vp.x - w) * 0.5, (vp.y - h) * 0.5)
	return panel.size


## Ajusta un panel ANCLADO a una esquina (arriba-izq, arriba-der, etc.). Para
## los paneles que viven en una esquina (inventario, ayuda) y que con
## `PRESET_CENTER` + posición absoluta se salían en ventanas estrechas.
static func anclar(panel: Control, preset: int, margen: float = 24.0) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var vp: Vector2 = _viewport()
	panel.set_anchors_preset(preset)
	# Con el preset puesto, los offsets son RELATIVOS al borde: `offset_right`
	# es la distancia al borde derecho. Por eso se fija el lado "lejos" con
	# `-margen` y el tamaño explicitamente.
	match preset:
		Control.PRESET_TOP_LEFT:
			panel.offset_left = margen
			panel.offset_top = margen
		Control.PRESET_TOP_RIGHT:
			panel.offset_right = -margen
			panel.offset_top = margen
		Control.PRESET_BOTTOM_LEFT:
			panel.offset_left = margen
			panel.offset_bottom = -margen
		Control.PRESET_BOTTOM_RIGHT:
			panel.offset_right = -margen
			panel.offset_bottom = -margen
		_:
			return
	# El tamaño se respeta, pero no puede empujar el panel fuera del viewport.
	var w: float = minf(panel.custom_minimum_size.x, vp.x - margen * 2.0)
	var h: float = minf(panel.custom_minimum_size.y, vp.y - margen * 2.0)
	panel.custom_minimum_size = Vector2(maxf(w, 200.0), maxf(h, 150.0))


## El tamaño del viewport en pixeles de UI. Con `canvas_items` + `expand` es
## donde miden de verdad los `Control` (independiente de la escala de la
## ventana), que es lo que hace que los límites valgan.
static func _viewport() -> Vector2:
	var arbol: SceneTree = Engine.get_main_loop() as SceneTree
	if arbol == null or arbol.root == null:
		return Vector2(1280, 720)
	var vp: Viewport = arbol.root
	var s: Vector2 = vp.get_visible_rect().size
	return s if s.x > 1.0 and s.y > 1.0 else Vector2(1280, 720)


## ¿Caben todos los paneles del viewport a este tamaño? Lo usan los tests para
## comprobar 1920x1080, 2560x1440 y una ventana estrecha (1024x600).
static func cabe(panel: Control) -> bool:
	if panel == null or not is_instance_valid(panel):
		return true
	var vp: Vector2 = _viewport()
	var r: Rect2 = Rect2(panel.position, panel.size)
	return r.position.x >= -1.0 and r.position.y >= -1.0 \
		and r.position.x + r.size.x <= vp.x + 1.0 \
		and r.position.y + r.size.y <= vp.y + 1.0
