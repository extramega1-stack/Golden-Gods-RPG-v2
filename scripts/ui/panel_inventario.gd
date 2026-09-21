class_name PanelInventario
extends CanvasLayer
## Panel de inventario de la fase 5: lista los items del Inventario real del
## jugador. "Usar" en consumibles → `inventario.usar(id, jugador)`; "Equipar"
## en armas/armaduras → `equipo.equipar(id, stats, inventario)`.
##
## Regla dura: arranca con visible=false (oculto no intercepta nada); al
## mostrarse, solo el panel lleva mouse_filter STOP (lección 11 de AGENTS.md).
## Se reconstruye al abrirse y al recibir `inventario.cambiado`/`equipo.cambiado`.

var _jugador: Player = null
var _lista: VBoxContainer = null


func _ready() -> void:
	layer = UiLayers.PANEL_INVENTARIO
	visible = false
	_construir()


func _construir() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(400, 440)
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
	panel.add_child(caja)
	var titulo: Label = Label.new()
	titulo.text = "Inventario   (I para cerrar)"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titulo.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	titulo.add_theme_font_size_override("font_size", 20)
	caja.add_child(titulo)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	caja.add_child(scroll)
	_lista = VBoxContainer.new()
	_lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lista.add_theme_constant_override("separation", 4)
	scroll.add_child(_lista)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("abrir_inventario"):
		visible = not visible
		if visible:
			_reconstruir()
		get_viewport().set_input_as_handled()


## Conecta el panel al jugador; re-llamar reconecta (tras cargar partida
## el Inventario/Equipo son instancias nuevas).
func conectar(j: Player) -> void:
	if _jugador != null:
		if is_instance_valid(_jugador.inventario) \
				and _jugador.inventario.cambiado.is_connected(_al_cambio):
			_jugador.inventario.cambiado.disconnect(_al_cambio)
		if is_instance_valid(_jugador.equipo) \
				and _jugador.equipo.cambiado.is_connected(_al_cambio):
			_jugador.equipo.cambiado.disconnect(_al_cambio)
	_jugador = j
	if _jugador != null:
		if _jugador.inventario != null:
			_jugador.inventario.cambiado.connect(_al_cambio)
		if _jugador.equipo != null:
			_jugador.equipo.cambiado.connect(_al_cambio)
	_reconstruir()


func _al_cambio() -> void:
	_reconstruir()


func _reconstruir() -> void:
	if _lista == null or _jugador == null or _jugador.inventario == null:
		return
	for h in _lista.get_children():
		h.queue_free()
	var inv: Inventario = _jugador.inventario
	if inv.entradas.is_empty():
		var vacio: Label = Label.new()
		vacio.text = "(vacío)"
		vacio.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lista.add_child(vacio)
		return
	for e in inv.entradas:
		if not (e is Dictionary):
			continue
		var ed: Dictionary = e
		var item_id: String = str(ed.get("item_id", ""))
		var cant: int = int(ed.get("cantidad", 0))
		var item: Dictionary = ItemDB.obtener(item_id)
		var nombre: String = str(item.get("nombre", item_id))
		var tipo: String = str(item.get("tipo", ""))
		var fila: HBoxContainer = HBoxContainer.new()
		fila.add_theme_constant_override("separation", 8)
		fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lista.add_child(fila)
		var lab: Label = Label.new()
		lab.text = "%s x%d" % [nombre, cant]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fila.add_child(lab)
		if tipo == "consumible":
			fila.add_child(_boton("Usar", _usar.bind(item_id)))
		elif tipo == "arma" or tipo == "armadura":
			fila.add_child(_boton("Equipar", _equipar.bind(item_id)))


func _boton(texto: String, accion: Callable) -> Button:
	var b: Button = Button.new()
	b.text = texto
	b.pressed.connect(accion)
	return b


func _usar(item_id: String) -> void:
	if _jugador == null or _jugador.inventario == null:
		return
	_jugador.inventario.usar(item_id, _jugador)


func _equipar(item_id: String) -> void:
	if _jugador == null or _jugador.inventario == null or _jugador.equipo == null:
		return
	_jugador.equipo.equipar(item_id, _jugador.stats, _jugador.inventario)
