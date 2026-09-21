class_name VentanaDetalleMision
extends CanvasLayer
## Sub-ventana de detalle de misión (fase 9, capa `UiLayers.DETALLE_MISION`).
##
## La abre el PanelMisiones al pulsar el nombre de una misión en curso.
## Muestra: nombre, lore (autowrap, con aire), objetivos con progreso
## ("Goblins derrotados: 3/5" vía `QuestLog.progreso_texto`) y recompensas
## (oro, XP, items con cantidad vía ItemDB).
##
## Arranca OCULTA (`visible = false`; lección 11) y no se come clics
## inactiva. Cierra con ESC (consumido en `_input` antes que el
## PanelMisiones), clic fuera (velo propio) o el botón "Cerrar".
##
## REGLA: la UI SOLO LEE. Todo sale de QuestDB / QuestLog / ItemDB.

var _mision_actual: String = ""

var _velo: ColorRect = null
var _lbl_nombre: Label = null
var _lbl_lore: Label = null
var _lbl_objetivos: Label = null
var _lbl_recompensas: Label = null


func _ready() -> void:
	layer = UiLayers.DETALLE_MISION
	_construir()
	# Lección 11: oculta desde el arranque.
	visible = false


func _construir() -> void:
	_velo = ColorRect.new()
	_velo.name = "VeloDetalle"
	_velo.color = Color(0.0, 0.0, 0.0, 0.45)
	_velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_velo.mouse_filter = Control.MOUSE_FILTER_STOP
	_velo.gui_input.connect(_al_clic_velo)
	add_child(_velo)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "PanelDetalle"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(460, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(0.08, 0.07, 0.1, 0.98)
	estilo.border_color = Color(0.75, 0.62, 0.3)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(6)
	estilo.content_margin_left = 18
	estilo.content_margin_right = 18
	estilo.content_margin_top = 14
	estilo.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", estilo)
	add_child(panel)

	var caja: VBoxContainer = VBoxContainer.new()
	caja.add_theme_constant_override("separation", 10)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(caja)

	_lbl_nombre = Label.new()
	_lbl_nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_nombre.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_lbl_nombre.add_theme_font_size_override("font_size", 21)
	caja.add_child(_lbl_nombre)

	_lbl_lore = Label.new()
	_lbl_lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_lore.custom_minimum_size = Vector2(424, 0)
	_lbl_lore.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_lore.add_theme_color_override("font_color", Color(0.92, 0.88, 0.74))
	_lbl_lore.add_theme_font_size_override("font_size", 16)
	caja.add_child(_lbl_lore)

	caja.add_child(HSeparator.new())

	var h_obj: Label = Label.new()
	h_obj.text = "Objetivos"
	h_obj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h_obj.add_theme_color_override("font_color", Color(0.75, 0.72, 0.68))
	h_obj.add_theme_font_size_override("font_size", 14)
	caja.add_child(h_obj)

	_lbl_objetivos = Label.new()
	_lbl_objetivos.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_objetivos.custom_minimum_size = Vector2(424, 0)
	_lbl_objetivos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_objetivos.add_theme_color_override("font_color", Color(0.88, 0.86, 0.8))
	_lbl_objetivos.add_theme_font_size_override("font_size", 15)
	caja.add_child(_lbl_objetivos)

	var h_rec: Label = Label.new()
	h_rec.text = "Recompensas"
	h_rec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h_rec.add_theme_color_override("font_color", Color(0.75, 0.72, 0.68))
	h_rec.add_theme_font_size_override("font_size", 14)
	caja.add_child(h_rec)

	_lbl_recompensas = Label.new()
	_lbl_recompensas.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_recompensas.custom_minimum_size = Vector2(424, 0)
	_lbl_recompensas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_recompensas.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	_lbl_recompensas.add_theme_font_size_override("font_size", 15)
	caja.add_child(_lbl_recompensas)

	var fila: HBoxContainer = HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_END
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(fila)
	var cerrar: Button = Button.new()
	cerrar.text = "Cerrar  (ESC)"
	cerrar.focus_mode = Control.FOCUS_NONE
	cerrar.mouse_filter = Control.MOUSE_FILTER_STOP
	cerrar.pressed.connect(cerrar_detalle)
	fila.add_child(cerrar)


## Muestra el detalle de la misión; no hace nada (sin reventar) si la
## misión no existe o el log es null.
func mostrar(quest_id: String, log: QuestLog) -> void:
	if log == null or not QuestDB.existe(quest_id):
		return
	var datos: Dictionary = QuestDB.obtener(quest_id)
	_mision_actual = quest_id
	_lbl_nombre.text = str(datos.get("nombre", quest_id))
	_lbl_lore.text = QuestDB.lore(quest_id)
	var prog: String = log.progreso_texto(quest_id)
	_lbl_objetivos.text = prog if prog != "" else "(sin objetivos)"
	_lbl_recompensas.text = _texto_recompensas(datos)
	visible = true


func cerrar_detalle() -> void:
	visible = false
	_mision_actual = ""


func esta_abierta() -> bool:
	return visible


func mision_actual() -> String:
	return _mision_actual


func _texto_recompensas(datos: Dictionary) -> String:
	var rec: Dictionary = datos.get("recompensas", {})
	var lineas: Array[String] = []
	var oro: int = int(rec.get("oro", 0))
	if oro > 0:
		lineas.append("+%d oro" % oro)
	var xp: int = int(rec.get("xp", 0))
	if xp > 0:
		lineas.append("+%d XP" % xp)
	var items: Array = rec.get("items", [])
	for it in items:
		if not (it is Dictionary):
			continue
		var di: Dictionary = it
		var iid: String = str(di.get("id", ""))
		var cant: int = maxi(1, int(di.get("cantidad", 1)))
		var nombre: String = iid
		if ItemDB.existe(iid):
			nombre = str(ItemDB.obtener(iid).get("nombre", iid))
		lineas.append("%s ×%d" % [nombre, cant])
	if lineas.is_empty():
		return "(sin recompensas)"
	return "\n".join(lineas)


## Clic fuera de la sub-ventana (el velo es propio de esta ventana).
func _al_clic_velo(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var clic: InputEventMouseButton = event
		if clic.pressed and clic.button_index == MOUSE_BUTTON_LEFT:
			cerrar_detalle()
			get_viewport().set_input_as_handled()


## _input corre antes que el _unhandled_input del Player y antes que el
## _input del PanelMisiones (esta ventana es hija suya): ESC cierra el
## detalle primero y se consume para que el panel no se cierre también.
func _input(event: InputEvent) -> void:
	if not esta_abierta():
		return
	if event.is_action_pressed("cancelar_seleccion"):
		cerrar_detalle()
		get_viewport().set_input_as_handled()
