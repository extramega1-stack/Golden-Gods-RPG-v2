class_name PanelEquipo
extends CanvasLayer
## Panel de equipo de la fase 5: una fila por slot ("arma", "armadura") con
## el item equipado y botón "Quitar" → `equipo.desequipar(slot, stats, inventario)`.
##
## Regla dura: arranca con visible=false (oculto no intercepta nada); al
## mostrarse, solo el panel lleva mouse_filter STOP (lección 11 de AGENTS.md).
## Se reconstruye al abrirse y al recibir `equipo.cambiado`/`inventario.cambiado`.

var _jugador: Player = null
var _lista: VBoxContainer = null


func _ready() -> void:
	layer = UiLayers.PANEL_EQUIPO
	visible = false
	_construir()


func _construir() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(400, 220)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(0.07, 0.07, 0.1, 0.97)
	estilo.border_color = Color(0.75, 0.62, 0.3)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", estilo)
	add_child(panel)
	var caja: VBoxContainer = VBoxContainer.new()
	caja.add_theme_constant_override("separation", 8)
	panel.add_child(caja)
	var titulo: Label = Label.new()
	titulo.text = "Equipo   (C para cerrar)"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titulo.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	titulo.add_theme_font_size_override("font_size", 20)
	caja.add_child(titulo)
	_lista = VBoxContainer.new()
	_lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lista.add_theme_constant_override("separation", 6)
	caja.add_child(_lista)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("abrir_equipo"):
		visible = not visible
		if visible:
			_reconstruir()
		get_viewport().set_input_as_handled()


## Conecta el panel al jugador; re-llamar reconecta (tras cargar partida
## el Inventario/Equipo son instancias nuevas).
func conectar(j: Player) -> void:
	if _jugador != null:
		if is_instance_valid(_jugador.equipo) \
				and _jugador.equipo.cambiado.is_connected(_al_cambio):
			_jugador.equipo.cambiado.disconnect(_al_cambio)
		if is_instance_valid(_jugador.inventario) \
				and _jugador.inventario.cambiado.is_connected(_al_cambio):
			_jugador.inventario.cambiado.disconnect(_al_cambio)
	_jugador = j
	if _jugador != null:
		if _jugador.equipo != null:
			_jugador.equipo.cambiado.connect(_al_cambio)
		if _jugador.inventario != null:
			_jugador.inventario.cambiado.connect(_al_cambio)
	_reconstruir()


func _al_cambio() -> void:
	_reconstruir()


func _reconstruir() -> void:
	if _lista == null or _jugador == null or _jugador.equipo == null:
		return
	for h in _lista.get_children():
		h.queue_free()
	var eq: Equipo = _jugador.equipo
	for slot in Equipo.SLOTS:
		var item_id: String = eq.equipado_en(slot)
		var fila: HBoxContainer = HBoxContainer.new()
		fila.add_theme_constant_override("separation", 8)
		fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lista.add_child(fila)
		var lab: Label = Label.new()
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if item_id == "":
			lab.text = "%s: —" % slot.capitalize()
		else:
			var nombre: String = str(ItemDB.obtener(item_id).get("nombre", item_id))
			lab.text = "%s: %s" % [slot.capitalize(), nombre]
		fila.add_child(lab)
		if item_id != "":
			var b: Button = Button.new()
			b.text = "Quitar"
			b.pressed.connect(_quitar.bind(slot))
			fila.add_child(b)


func _quitar(slot: String) -> void:
	if _jugador == null or _jugador.equipo == null or _jugador.inventario == null:
		return
	_jugador.equipo.desequipar(slot, _jugador.stats, _jugador.inventario)
