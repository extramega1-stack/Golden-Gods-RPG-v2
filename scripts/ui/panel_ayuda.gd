class_name PanelAyuda
extends CanvasLayer
## Manual de ayuda (fase 46): los CONTROLES y las MECÁNICAS del juego, en una
## sola pantalla, con la tecla `?` (Input Map: `abrir_ayuda`).
##
## REGLA DURA de esta fase: la columna de controles **se lee del Input Map en
## runtime** (`InputMap.get_actions()` + `InputEventKey.as_text()`), no de un
## JSON. Así no puede desincronizarse nunca: ni de las teclas reales, ni del
## rebind por slot de la fase 38, ni de las teclas que se añadan después. Las
## mecánicas sí son datos (`data/mecanicas.json`), porque son texto editorial.
##
## Es una ESCENA (`scenes/ui/panel_ayuda.tscn`) para poder correrla sola desde
## el editor (F6) y revisarla sin entrar al juego; dentro del juego la abre y
## la cierra la tecla `?` y ESC.
##
## La UI solo lee: no toca stats, inventario ni oro.

## Tamaño ideal del manual. Se AJUSTA al viewport (nunca se sale de la
## pantalla): con una ventana pequeña el manual ocupa lo que hay.
const ANCHO_MIN: Vector2 = Vector2(1180, 660)
const MARGEN_BORDES: int = 40
var _controles: VBoxContainer = null
var _mecanicas: VBoxContainer = null
var _pestanas: TabContainer = null
var _raiz: Control = null
var _caja: PanelContainer = null
var _mecanicas_db: MecanicasDB = null
## Tamaño actual del panel (el ideal recortado al viewport).
var _tam: Vector2 = ANCHO_MIN

## Fase 46: si es true, el panel aparece al abrir la escena (así se puede
## correr solo con F6). El juego lo pone en false y lo abre con la tecla.
@export var abrir_al_arrancar: bool = true


func _ready() -> void:
	layer = UiLayers.PANEL_AYUDA
	get_viewport().size_changed.connect(_ajustar_al_viewport)
	_construir()
	_ajustar_al_viewport()
	_mecanicas_db = MecanicasDB.new()
	_mecanicas_db.cargar()
	_rellenar_controles()
	_rellenar_mecanicas()
	visible = abrir_al_arrancar


## Reajusta el panel al viewport: con una ventana más pequeña que la ideal,
## el manual se encoge en vez de salirse (se lee igual de bien).
## Ancho de lectura de una línea de texto: lo que quede de menos el panel,
## los márgenes y el scroll. Se recalcula al cambiar de ventana.
func _ajustar_al_viewport() -> void:
	var vp: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	_tam = Vector2(maxf(vp.x - float(MARGEN_BORDES), 320.0),
		maxf(vp.y - float(MARGEN_BORDES), 240.0))


## Abre el manual (idempotente: lo deja como estaba si ya estaba abierto).
func mostrar_manual() -> void:
	visible = true
	_rellenar_controles()
	_rellenar_mecanicas()


func cerrar_panel() -> void:
	visible = false


func esta_abierta() -> bool:
	return visible


func alternar() -> void:
	if visible:
		cerrar_panel()
	else:
		mostrar_manual()


## Número de filas de la pestaña de controles (solo las filas, no el
## encabezado ni la nota final). Para tests.
func controles_visibles() -> int:
	return _contar_por_meta(_controles, "control")


## Número de secciones de la pestaña de mecánicas (solo las secciones). Para
## tests.
func secciones_visibles() -> int:
	return _contar_por_meta(_mecanicas, "seccion")


func _contar_por_meta(c: VBoxContainer, tipo: String) -> int:
	if c == null:
		return 0
	var n: int = 0
	for hijo in c.get_children():
		if hijo.is_queued_for_deletion():
			continue
		if str(hijo.get_meta("tipo", "")) == tipo:
			n += 1
	return n


## Las teclas que el motor tiene asignadas a una acción, en texto
## ("W", "F4", "Escape"...). Vacía si la acción no tiene teclas.
func teclas_de(accion: String) -> Array[String]:
	var res: Array[String] = []
	if not InputMap.has_action(accion):
		return res
	for e in InputMap.action_get_events(accion):
		if e is InputEventKey:
			var t: String = OS.get_keycode_string((e as InputEventKey).physical_keycode)
			if t != "" and not res.has(t):
				res.append(t)
	return res


## Las acciones del juego (las del Input Map propio, no las `ui_*` internas
## de Godot), con su tecla y su etiqueta, ordenadas por tecla para que se
## pueda encontrar de un vistazo.
func lista_controles() -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	var acciones: Array[StringName] = InputMap.get_actions()
	for a in acciones:
		var accion: String = str(a)
		if accion.begins_with("ui_"):
			continue
		var teclas: Array[String] = teclas_de(accion)
		if teclas.is_empty():
			continue
		res.append({"accion": accion, "teclas": teclas, "etiqueta": etiqueta_de(accion)})
	res.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return str((x as Dictionary)["teclas"][0]) < str((y as Dictionary)["teclas"][0]))
	return res


## Fase 46: la tecla ? abre y cierra el manual. NO se comprueba `visible`
## para `abrir_ayuda`: un CanvasLayer oculto sigue recibiendo
## `_unhandled_input` (es justo lo que hacen el resto de paneles con su
## tecla), y con la guarda el manual no se podría abrir nunca.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("abrir_ayuda"):
		alternar()
		get_viewport().set_input_as_handled()
		return
	if visible and event.is_action_pressed("cancelar_seleccion"):
		cerrar_panel()
		get_viewport().set_input_as_handled()


func _construir() -> void:
	var fondo: ColorRect = ColorRect.new()
	fondo.name = "Fondo"
	fondo.color = Color(0.02, 0.02, 0.03, 0.93)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fondo)

	_raiz = Control.new()
	_raiz.name = "Raiz"
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_raiz)

	_caja = PanelContainer.new()
	_caja.name = "Panel"
	# Anclado a PANTALLA COMPLETA con un margen: así el manual NUNCA se sale
	# de la ventana, venga del tamaño que venga (la 1280x720 de siempre, una
	# ventana pequeña o un monitor vertical).
	_caja.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m: float = float(MARGEN_BORDES) * 0.5
	_caja.offset_left = m
	_caja.offset_top = m
	_caja.offset_right = -m
	_caja.offset_bottom = -m
	_caja.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.add_child(_caja)
	_caja.add_theme_stylebox_override("panel", _estilo_panel())

	var col: VBoxContainer = VBoxContainer.new()
	col.name = "Caja"
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caja.add_child(col)

	var cabecera: HBoxContainer = HBoxContainer.new()
	cabecera.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cabecera)
	var titulo: Label = Label.new()
	titulo.text = "GOLDEN GODS RPG — Cómo se juega"
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titulo.add_theme_font_size_override("font_size", 26)
	titulo.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
	cabecera.add_child(titulo)
	var btn: Button = Button.new()
	btn.name = "Cerrar"
	btn.text = "Cerrar (ESC)"
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(cerrar_panel)
	cabecera.add_child(btn)

	_pestanas = TabContainer.new()
	_pestanas.name = "Pestanas"
	_pestanas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pestanas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_pestanas)

	_controles = _pestana("Controles", "Todos los atajos, leídos del juego:")
	_mecanicas = _pestana("Mecánicas", "Lo que hay que saber para jugar:")


## Crea una pestaña con su encabezado y devuelve el VBox donde se mete el
## contenido (el TabContainer necesita un hijo con el nombre de la pestaña).
func _pestana(nombre: String, subtitulo: String) -> VBoxContainer:
	var scroller: ScrollContainer = ScrollContainer.new()
	scroller.name = nombre
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pestanas.add_child(scroller)
	var caja := VBoxContainer.new()
	caja.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caja.add_theme_constant_override("separation", 4)
	scroller.add_child(caja)
	var sub: Label = Label.new()
	sub.text = subtitulo
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.65, 0.63, 0.55))
	caja.add_child(sub)
	return caja


## Columna de controles: se genera del Input Map cada vez que se abre, así
## que un rebind o una tecla nueva se ven al instante.
func _rellenar_controles() -> void:
	_vaciar(_controles)
	for c in lista_controles():
		_controles.add_child(_fila_control(c))
	_controles.add_child(_nota(
		"F4-F11 son los 8 slots de la barra; 1-5 lanzan las skills de tu clase. "
		+ "El 1 también es el ataque básico. Esta lista se genera del Input Map: "
		+ "si reasignas una tecla, aquí cambia sola."))


func _rellenar_mecanicas() -> void:
	_vaciar(_mecanicas)
	for s in _mecanicas_db.secciones():
		var sd: Dictionary = s
		var seccion: Control = _titulo_seccion(str(sd.get("titulo", "")))
		seccion.set_meta("tipo", "seccion")
		_mecanicas.add_child(seccion)
		for e in (sd.get("entradas", []) as Array):
			_mecanicas.add_child(_fila_mecanica(e as Dictionary))


func _fila_control(c: Dictionary) -> Control:
	var caja := HBoxContainer.new()
	caja.add_theme_constant_override("separation", 10)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tecla: Label = Label.new()
	tecla.text = " / ".join(c.get("teclas", []) as Array[String])
	tecla.custom_minimum_size = Vector2(110, 0)
	tecla.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tecla.add_theme_font_size_override("font_size", 17)
	tecla.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
	caja.add_child(tecla)
	var et: Label = Label.new()
	et.text = str(c.get("etiqueta", ""))
	et.mouse_filter = Control.MOUSE_FILTER_IGNORE
	et.add_theme_font_size_override("font_size", 15)
	et.add_theme_color_override("font_color", Color(0.88, 0.86, 0.78))
	caja.add_child(et)
	caja.set_meta("tipo", "control")
	return caja


func _titulo_seccion(texto: String) -> Control:
	var l: Label = Label.new()
	l.text = texto.to_upper()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", Color(0.98, 0.76, 0.32))
	var sep: HSeparator = HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 2)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(l)
	caja.add_child(sep)
	caja.set_meta("tipo", "seccion")
	return caja


func _fila_mecanica(e: Dictionary) -> Control:
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 0)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: Label = Label.new()
	t.text = str(e.get("titulo", ""))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", Color(0.95, 0.90, 0.70))
	caja.add_child(t)
	var x: Label = Label.new()
	x.text = str(e.get("texto", ""))
	x.mouse_filter = Control.MOUSE_FILTER_IGNORE
	x.add_theme_font_size_override("font_size", 14)
	x.add_theme_color_override("font_color", Color(0.80, 0.79, 0.73))
	x.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caja.add_child(x)
	if not (e.get("teclas", []) as Array).is_empty():
		var k: Label = Label.new()
		k.text = "Teclas: %s" % ", ".join(e.get("teclas", []) as Array)
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		k.add_theme_font_size_override("font_size", 12)
		k.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
		caja.add_child(k)
	return caja


func _nota(texto: String) -> Control:
	var l: Label = Label.new()
	l.text = texto
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.60, 0.58, 0.52))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _vaciar(c: VBoxContainer) -> void:
	for c2 in c.get_children():
		# remove_child + queue_free: si no, las filas viejas siguen en el
		# árbol un frame y el manual se ve duplicado al reabrirlo.
		c.remove_child(c2)
		c2.queue_free()


func _estilo_panel() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.08, 0.98)
	sb.border_color = Color(0.55, 0.42, 0.18)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 16.0
	return sb


## Etiqueta legible de una acción del Input Map. Las acciones ya están
## nombradas en español (§9.3), pero "mover_adelante" no se lee: aquí se
## traduce a una frase corta y los prefijos de la barra se develops.
static func etiqueta_de(accion: String) -> String:
	match accion:
		"mover_adelante": return "Andar hacia delante"
		"mover_atras": return "Andar hacia atrás"
		"mover_izquierda": return "Andar a la izquierda"
		"mover_derecha": return "Andar a la derecha"
		"atacar": return "Atacar"
		"interactuar": return "Interactuar / hablar / minar"
		"cancelar_seleccion": return "Cancelar / cerrar"
		"abrir_ayuda": return "Abrir y cerrar este manual"
		"guardar_partida": return "Guardar la partida"
		"cargar_partida": return "Cargar la partida"
		"abrir_inventario": return "Abrir inventario"
		"abrir_equipo": return "Abrir equipo"
		"abrir_misiones": return "Abrir misiones"
		"abrir_habilidades": return "Abrir habilidades y talentos"
		"abrir_personaje": return "Abrir personaje"
		"limpiar_slot": return "Vaciar el slot delante"
	for pre in ["barra_", "habilidad_"]:
		if accion.begins_with(pre):
			return "Barra, slot " + accion.substr(pre.length())
	return accion.replace("_", " ")
