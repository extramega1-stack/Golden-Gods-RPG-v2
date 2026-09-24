class_name PanelInventario
extends CanvasLayer
## Inventario estilo FlyFF (fase 31): pestañas Todos / Equipo / Consumibles /
## Materiales / Misión, rejilla de 6 columnas de celdas coloreadas por tipo
## (inicial del nombre + cantidad). Clic en una celda = seleccionar; la barra
## inferior muestra nombre, descripción y los botones Usar / Equipar.
##
## "Usar" en consumibles → `inventario.usar(id, jugador)`; "Equipar" en
## equipables → `equipo.equipar(id, stats, inventario)`.
##
## Regla dura: arranca con visible=false (oculto no intercepta nada); al
## mostrarse, solo el panel lleva mouse_filter STOP (lección 11 de AGENTS.md).
## Se reconstruye al abrirse y al recibir `inventario.cambiado`/`equipo.cambiado`.

## Orden de las pestañas (FlyFF).
const PESTANAS: Array[String] = ["Todos", "Equipo", "Consumibles",
	"Materiales", "Misión"]
## Columnas de la rejilla.
const COLUMNAS: int = 6

var _jugador: Player = null
var _rejillas: Dictionary = {}
var _sel_id: String = ""
var _sel_nombre: Label = null
var _sel_desc: Label = null
var _btn_usar: Button = null
var _btn_equipar: Button = null


func _init() -> void:
	layer = UiLayers.PANEL_INVENTARIO
	_construir_cromo()
	visible = false


func _construir_cromo() -> void:
	var fondo := PanelContainer.new()
	fondo.set_anchors_preset(Control.PRESET_CENTER)
	fondo.position = Vector2(-280.0, -260.0)
	fondo.size = Vector2(560.0, 520.0)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	# Fase 32: marco FlyFF compartido (dorado sobre fondo oscuro).
	fondo.add_theme_stylebox_override("panel", TemaFlyFF.marco())
	add_child(fondo)
	var margen := MarginContainer.new()
	margen.add_theme_constant_override("margin_left", 16)
	margen.add_theme_constant_override("margin_right", 16)
	margen.add_theme_constant_override("margin_top", 12)
	margen.add_theme_constant_override("margin_bottom", 12)
	fondo.add_child(margen)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 8)
	margen.add_child(caja)
	var titulo := Label.new()
	titulo.text = "Inventario (I)"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 20)
	titulo.add_theme_color_override("font_color", TemaFlyFF.DORADO_CLARO)
	titulo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	titulo.add_theme_constant_override("shadow_offset_x", 1)
	titulo.add_theme_constant_override("shadow_offset_y", 1)
	caja.add_child(titulo)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(tabs)
	for pestana in PESTANAS:
		tabs.add_child(_pestana(pestana))
	caja.add_child(_barra_seleccion())


func _pestana(pestana: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = pestana
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rejilla := GridContainer.new()
	rejilla.columns = COLUMNAS
	rejilla.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rejilla.add_theme_constant_override("h_separation", 6)
	rejilla.add_theme_constant_override("v_separation", 6)
	scroll.add_child(rejilla)
	_rejillas[pestana] = rejilla
	return scroll


func _barra_seleccion() -> VBoxContainer:
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 4)
	_sel_nombre = Label.new()
	_sel_nombre.text = "Selecciona un item"
	_sel_nombre.add_theme_font_size_override("font_size", 15)
	caja.add_child(_sel_nombre)
	_sel_desc = Label.new()
	_sel_desc.text = ""
	_sel_desc.add_theme_font_size_override("font_size", 12)
	_sel_desc.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
	_sel_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_desc.custom_minimum_size = Vector2(0, 34)
	caja.add_child(_sel_desc)
	var botones := HBoxContainer.new()
	botones.add_theme_constant_override("separation", 8)
	caja.add_child(botones)
	_btn_usar = Button.new()
	_btn_usar.text = "Usar"
	_btn_usar.pressed.connect(_al_usar)
	botones.add_child(_btn_usar)
	_btn_equipar = Button.new()
	_btn_equipar.text = "Equipar"
	_btn_equipar.pressed.connect(_al_equipar)
	botones.add_child(_btn_equipar)
	return caja


## Conecta (o reconecta) al jugador. Re-suscribe sin duplicar.
func conectar(j: Player) -> void:
	if _jugador != null and is_instance_valid(_jugador):
		if _jugador.inventario.cambiado.is_connected(_reconstruir):
			_jugador.inventario.cambiado.disconnect(_reconstruir)
		if _jugador.equipo.cambiado.is_connected(_reconstruir):
			_jugador.equipo.cambiado.disconnect(_reconstruir)
	_jugador = j
	_sel_id = ""
	if _jugador != null and is_instance_valid(_jugador):
		if not _jugador.inventario.cambiado.is_connected(_reconstruir):
			_jugador.inventario.cambiado.connect(_reconstruir)
		if not _jugador.equipo.cambiado.is_connected(_reconstruir):
			_jugador.equipo.cambiado.connect(_reconstruir)
	_reconstruir()


func _reconstruir(_arg = null) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var items: Array = _jugador.inventario.listar()
	for pestana in PESTANAS:
		var rejilla: GridContainer = _rejillas.get(pestana)
		if rejilla == null:
			continue
		for h in rejilla.get_children():
			h.queue_free()
		for entrada in items:
			var item: Dictionary = entrada.get("item", {})
			if pasa_filtro(item, pestana):
				rejilla.add_child(_celda(entrada, item))
	_actualizar_barra()


## Lógica de filtrado por pestaña (testeable sin UI).
static func pasa_filtro(item: Dictionary, pestana: String) -> bool:
	match pestana:
		"Todos":
			return true
		"Equipo":
			return Equipo.es_equipable(str(item.get("id", "")))
		"Consumibles":
			return str(item.get("tipo", "")) == "consumible"
		"Materiales":
			return str(item.get("tipo", "")) == "material"
		"Misión":
			return str(item.get("tipo", "")) == "mision"
	return false


## Color de celda por tipo (FlyFF).
static func color_tipo(tipo: String) -> Color:
	match tipo:
		"arma":
			return Color(0.45, 0.16, 0.16)
		"armadura":
			return Color(0.18, 0.24, 0.34)
		"accesorio":
			return Color(0.34, 0.20, 0.44)
		"consumible":
			return Color(0.14, 0.34, 0.16)
		"material":
			return Color(0.34, 0.27, 0.14)
		"mision":
			return Color(0.40, 0.32, 0.12)
	return Color(0.22, 0.22, 0.26)


func _celda(entrada: Dictionary, item: Dictionary) -> Button:
	var iid: String = str(entrada.get("id", ""))
	var cant: int = int(entrada.get("cantidad", 1))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(72.0, 72.0)
	btn.toggle_mode = true
	btn.button_pressed = (iid == _sel_id)
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = color_tipo(str(item.get("tipo", "")))
	# Fase 32: selección dorada gruesa (FlyFF); resto filo oscuro fino.
	if iid == _sel_id:
		estilo.border_color = TemaFlyFF.DORADO_CLARO
		estilo.set_border_width_all(3)
	else:
		estilo.border_color = Color(0.08, 0.08, 0.10)
		estilo.set_border_width_all(1)
	estilo.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", estilo)
	btn.add_theme_stylebox_override("hover", estilo)
	btn.add_theme_stylebox_override("pressed", estilo)
	var inicial := Label.new()
	inicial.text = str(item.get("nombre", "?")).left(1).to_upper()
	inicial.add_theme_font_size_override("font_size", 28)
	inicial.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	inicial.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	inicial.add_theme_constant_override("shadow_offset_x", 1)
	inicial.add_theme_constant_override("shadow_offset_y", 2)
	inicial.set_anchors_preset(Control.PRESET_FULL_RECT)
	inicial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inicial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inicial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(inicial)
	if cant > 1:
		var badge := Label.new()
		badge.text = "x%d" % cant
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.position = Vector2(-34.0, -20.0)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(badge)
	btn.tooltip_text = "%s x%d" % [str(item.get("nombre", iid)), cant]
	btn.pressed.connect(_al_celda.bind(iid))
	return btn


func _al_celda(iid: String) -> void:
	_sel_id = iid
	_reconstruir()


func _actualizar_barra() -> void:
	if _sel_id == "" or _jugador == null or not is_instance_valid(_jugador):
		_sel_nombre.text = "Selecciona un item"
		_sel_desc.text = ""
		_btn_usar.disabled = true
		_btn_equipar.disabled = true
		return
	if _jugador.inventario.contar(_sel_id) <= 0:
		_sel_id = ""
		_actualizar_barra()
		return
	var item: Dictionary = ItemDB.obtener(_sel_id)
	_sel_nombre.text = item.get("nombre", _sel_id)
	_sel_desc.text = item.get("descripcion", "")
	_btn_usar.disabled = str(item.get("tipo", "")) != "consumible"
	_btn_equipar.disabled = not Equipo.es_equipable(_sel_id)


func _al_usar() -> void:
	if _sel_id == "" or _jugador == null or not is_instance_valid(_jugador):
		return
	_jugador.inventario.usar(_sel_id, _jugador)


func _al_equipar() -> void:
	if _sel_id == "" or _jugador == null or not is_instance_valid(_jugador):
		return
	_jugador.equipo.equipar(_sel_id, _jugador.stats, _jugador.inventario)


## I alterna el inventario.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("abrir_inventario"):
		visible = not visible
		if visible:
			_reconstruir()
		get_viewport().set_input_as_handled()


## ESC cierra (corre antes que el _unhandled_input del Player).
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancelar_seleccion"):
		visible = false
		get_viewport().set_input_as_handled()
