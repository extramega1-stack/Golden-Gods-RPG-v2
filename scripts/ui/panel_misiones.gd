class_name PanelMisiones
extends CanvasLayer
## Panel de misiones de la fase 8 (capa `UiLayers.PANEL_MISIONES` = 27).
##
## Arranca OCULTO (`visible = false`; lección 11) y no se come clics
## inactivo. La tecla **J** (acción `abrir_misiones` del Input Map) alterna
## visible; ESC cierra (consumido en `_input` antes que el Player).
##
## REGLA: la UI SOLO LEE. Todo pasa por `QuestLog` (aceptar/entregar se
## hacen desde la VentanaDialogo). Se reconstruye al abrirse y ante la
## señal `cambiada` del QuestLog.
##
## Toast: CanvasLayer hijo (capa 15) con un Label que muestra mensajes
## 2.5 s con fundido; API `toast(texto)`.

var _jugador: Player = null
var _misiones: QuestLog = null

var _lista_activas: VBoxContainer = null
var _lista_entregadas: VBoxContainer = null

var _toast_layer: CanvasLayer = null
var _toast_label: Label = null
var _toast_tween: Tween = null

## Fase 9: sub-ventana de detalle de misión (capa UiLayers.DETALLE_MISION).
## Es hija de este panel: su _input corre antes que el del panel, así que
## ESC la cierra primero (además del guard explícito en _input).
var _detalle: VentanaDetalleMision = null


func _ready() -> void:
	layer = UiLayers.PANEL_MISIONES
	_construir()
	_construir_toast()
	# Fase 9: la sub-ventana de detalle vive como hija (capa 28 > 27).
	_detalle = VentanaDetalleMision.new()
	_detalle.name = "DetalleMision"
	add_child(_detalle)
	# Lección 11: oculto desde el arranque.
	visible = false


func _construir() -> void:
	var velo: ColorRect = ColorRect.new()
	velo.name = "Velo"
	velo.color = Color(0.0, 0.0, 0.0, 0.55)
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	velo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(velo)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(480, 520)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(0.07, 0.07, 0.1, 0.97)
	estilo.border_color = Color(0.75, 0.62, 0.3)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", estilo)
	add_child(panel)

	var caja: VBoxContainer = VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(caja)

	var titulo: Label = Label.new()
	titulo.text = "Misiones"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titulo.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	titulo.add_theme_font_size_override("font_size", 22)
	caja.add_child(titulo)

	caja.add_child(_etiqueta_seccion("En curso"))
	var scroll_a: ScrollContainer = ScrollContainer.new()
	scroll_a.custom_minimum_size = Vector2(460, 210)
	scroll_a.mouse_filter = Control.MOUSE_FILTER_PASS
	caja.add_child(scroll_a)
	_lista_activas = VBoxContainer.new()
	_lista_activas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lista_activas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lista_activas.add_theme_constant_override("separation", 8)
	scroll_a.add_child(_lista_activas)

	caja.add_child(_etiqueta_seccion("Completadas"))
	var scroll_e: ScrollContainer = ScrollContainer.new()
	scroll_e.custom_minimum_size = Vector2(460, 110)
	scroll_e.mouse_filter = Control.MOUSE_FILTER_PASS
	caja.add_child(scroll_e)
	_lista_entregadas = VBoxContainer.new()
	_lista_entregadas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lista_entregadas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lista_entregadas.add_theme_constant_override("separation", 4)
	scroll_e.add_child(_lista_entregadas)

	var fila: HBoxContainer = HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_END
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(fila)
	var cerrar: Button = Button.new()
	cerrar.text = "Cerrar  (ESC)"
	cerrar.focus_mode = Control.FOCUS_NONE
	cerrar.mouse_filter = Control.MOUSE_FILTER_STOP
	cerrar.pressed.connect(cerrar_panel)
	fila.add_child(cerrar)


func _construir_toast() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.name = "Toast"
	_toast_layer.layer = 15
	_toast_layer.visible = false
	add_child(_toast_layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position -= Vector2(200, 140)
	panel.custom_minimum_size = Vector2(400, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	estilo.border_color = Color(0.75, 0.62, 0.3)
	estilo.set_border_width_all(1)
	estilo.set_corner_radius_all(4)
	estilo.content_margin_left = 16
	estilo.content_margin_right = 16
	estilo.content_margin_top = 10
	estilo.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", estilo)
	_toast_layer.add_child(panel)

	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	_toast_label.add_theme_font_size_override("font_size", 17)
	panel.add_child(_toast_label)


func _etiqueta_seccion(texto: String) -> Label:
	var l: Label = Label.new()
	l.text = texto
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", Color(0.75, 0.72, 0.68))
	l.add_theme_font_size_override("font_size", 14)
	return l


## Conecta el panel al jugador y al QuestLog; re-llamar reconecta (tras
## cargar partida el QuestLog se restaura en sitio, igual que Tienda).
func conectar(j: Player, q: QuestLog) -> void:
	if _misiones != null and _misiones.cambiada.is_connected(_al_cambio):
		_misiones.cambiada.disconnect(_al_cambio)
	_jugador = j
	_misiones = q
	if _misiones != null:
		_misiones.cambiada.connect(_al_cambio)
	if esta_abierta():
		_reconstruir()


func alternar() -> void:
	if esta_abierta():
		cerrar_panel()
	else:
		_reconstruir()
		visible = true


func cerrar_panel() -> void:
	if _detalle != null:
		_detalle.cerrar_detalle()
	visible = false


func esta_abierta() -> bool:
	return visible


## Muestra un mensaje 2.5 s (2 s fijo + 0.5 s de fundido).
func toast(texto: String) -> void:
	if _toast_label == null or _toast_layer == null:
		return
	_toast_label.text = texto
	_toast_label.modulate = Color(1, 1, 1, 1)
	_toast_layer.visible = true
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(_ocultar_toast)


func _ocultar_toast() -> void:
	if _toast_layer != null:
		_toast_layer.visible = false


func _al_cambio() -> void:
	if esta_abierta():
		_reconstruir()


func _reconstruir() -> void:
	if _misiones == null:
		return
	for h in _lista_activas.get_children():
		h.queue_free()
	for h in _lista_entregadas.get_children():
		h.queue_free()
	var hay_activas: bool = false
	var hay_entregadas: bool = false
	for qid in QuestDB.ids():
		var est: String = _misiones.estado(qid)
		if est == "activa" or est == "lista":
			_agregar_activa(qid, est)
			hay_activas = true
		elif est == "entregada":
			_agregar_entregada(qid)
			hay_entregadas = true
	if not hay_activas:
		_lista_activas.add_child(_etiqueta_seccion("(sin misiones en curso; habla con los NPCs)"))
	if not hay_entregadas:
		_lista_entregadas.add_child(_etiqueta_seccion("(ninguna)"))


func _agregar_activa(qid: String, est: String) -> void:
	var datos: Dictionary = QuestDB.obtener(qid)
	# Fase 9: el nombre es un botón (con pinta de etiqueta) que abre la
	# sub-ventana de detalle de la misión.
	var boton: Button = Button.new()
	boton.name = "Detalle_" + qid
	boton.text = str(datos.get("nombre", qid))
	boton.tooltip_text = "Ver detalle"
	boton.focus_mode = Control.FOCUS_NONE
	boton.mouse_filter = Control.MOUSE_FILTER_STOP
	boton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boton.alignment = HORIZONTAL_ALIGNMENT_LEFT
	boton.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	boton.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.68))
	boton.add_theme_color_override("font_pressed_color", Color(0.9, 0.75, 0.4))
	boton.add_theme_font_size_override("font_size", 17)
	var plano: StyleBoxEmpty = StyleBoxEmpty.new()
	boton.add_theme_stylebox_override("normal", plano)
	boton.add_theme_stylebox_override("hover", plano)
	boton.add_theme_stylebox_override("pressed", plano)
	boton.add_theme_stylebox_override("focus", plano)
	boton.add_theme_stylebox_override("disabled", plano)
	boton.pressed.connect(_abrir_detalle.bind(qid))
	_lista_activas.add_child(boton)
	for linea in _misiones.progreso_texto(qid).split("\n"):
		var prog: Label = Label.new()
		prog.text = "  " + linea
		prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		prog.add_theme_color_override("font_color", Color(0.88, 0.86, 0.8))
		prog.add_theme_font_size_override("font_size", 15)
		_lista_activas.add_child(prog)
	if est == "lista":
		var lista: Label = Label.new()
		lista.text = "  ¡Lista para entregar!"
		lista.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lista.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
		lista.add_theme_font_size_override("font_size", 15)
		_lista_activas.add_child(lista)


## Fase 9: abre la sub-ventana con el detalle de la misión.
func _abrir_detalle(qid: String) -> void:
	if _detalle != null and _misiones != null:
		_detalle.mostrar(qid, _misiones)


func _agregar_entregada(qid: String) -> void:
	var datos: Dictionary = QuestDB.obtener(qid)
	var nombre: Label = Label.new()
	nombre.text = str(datos.get("nombre", qid)) + "  (completada)"
	nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nombre.add_theme_color_override("font_color", Color(0.6, 0.58, 0.55))
	nombre.add_theme_font_size_override("font_size", 15)
	_lista_entregadas.add_child(nombre)


## J (acción `abrir_misiones`) alterna el panel.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("abrir_misiones"):
		alternar()
		get_viewport().set_input_as_handled()


## _input corre antes que el _unhandled_input del Player: el panel
## consume ESC (cerrar) antes de que llegue al juego. Si la sub-ventana
## de detalle está abierta, ella consume ESC primero (fase 9).
func _input(event: InputEvent) -> void:
	if not esta_abierta():
		return
	if _detalle != null and _detalle.esta_abierta():
		return
	if event.is_action_pressed("cancelar_seleccion"):
		cerrar_panel()
		get_viewport().set_input_as_handled()
