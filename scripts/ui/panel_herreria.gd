class_name PanelHerreria
extends CanvasLayer
## Panel de forja (fase 44): lista las recetas del herrero (Bram general,
## Durnan de fuego), muestra materiales y resultado, y forja con un clic.
##
## REGLA DURA: la UI solo LEE inventario/oro y llama a `Herreria.forjar`
## (que los consume). Nunca escribe stats — el equipo aplica sus mods.
## Se cierra con ESC, el velo o "Cerrar".

const ANCHO_MIN: Vector2 = Vector2(520, 540)

var _jugador: Player = null
var _herrero_id: String = ""
## Fase 50.4: esto era un Array de 4 `Herreria` con la que solo se usaba
## `_herrerias[0]`. Los otros 3 eran objetos muertos. `Herreria` no tiene
## estado propio (es lógica pura sobre el jugador), así que una sola alcanza.
var _herreria: Herreria = null

var _titulo: Label = null
var _oro: Label = null
var _lista: VBoxContainer = null
var _estado: Label = null
var _boton_cerrar: Button = null


func _ready() -> void:
	layer = UiLayers.PANEL_HERRERIA
	_construir()
	visible = false
	PilaUI.cerrar(self)


func _construir() -> void:
	RecetasDB.cargar()
	_herreria = Herreria.new()

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
	panel.custom_minimum_size = ANCHO_MIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(0.08, 0.06, 0.06, 0.97)
	estilo.border_color = Color(0.85, 0.55, 0.25)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", estilo)
	add_child(panel)

	var caja: VBoxContainer = VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(caja)

	_titulo = Label.new()
	_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_titulo.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	_titulo.add_theme_font_size_override("font_size", 22)
	caja.add_child(_titulo)

	_oro = Label.new()
	_oro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_oro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_oro.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	_oro.add_theme_font_size_override("font_size", 17)
	caja.add_child(_oro)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 380)
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	caja.add_child(scroll)
	_lista = VBoxContainer.new()
	_lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lista.add_theme_constant_override("separation", 6)
	scroll.add_child(_lista)

	_estado = Label.new()
	_estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_estado.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_estado.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	_estado.add_theme_font_size_override("font_size", 14)
	caja.add_child(_estado)

	_boton_cerrar = Button.new()
	_boton_cerrar.text = "Cerrar"
	_boton_cerrar.focus_mode = Control.FOCUS_NONE
	_boton_cerrar.mouse_filter = Control.MOUSE_FILTER_STOP
	_boton_cerrar.pressed.connect(cerrar_panel)
	var fila: HBoxContainer = HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_END
	fila.add_child(_boton_cerrar)
	caja.add_child(fila)


func conectar(j: Player) -> void:
	_jugador = j
	if _jugador == null:
		return
	if not _jugador.inventario.cambiado.is_connected(_al_cambio_inv):
		_jugador.inventario.cambiado.connect(_al_cambio_inv)
	if not _jugador.oro_cambiado.is_connected(_al_cambio_oro):
		_jugador.oro_cambiado.connect(_al_cambio_oro)


## Abre el panel de un herrero (npc_id = bram, durnan...).
func mostrar(npc_id: String) -> void:
	if _jugador == null:
		return
	_herrero_id = npc_id
	_titulo.text = "Herrería de %s" % str(NpcDB.obtener(npc_id).get("nombre", npc_id))
	visible = true
	PilaUI.abrir(self)
	_reconstruir()
	_pintar_oro()


func cerrar_panel() -> void:
	visible = false
	PilaUI.cerrar(self)


func esta_abierta() -> bool:
	return visible


func herrero_id_actual() -> String:
	return _herrero_id


## Recetas que el panel está mostrando (para tests).
func recetas_visibles() -> Array[String]:
	var res: Array[String] = []
	for c in _lista.get_children():
		if c.is_queued_for_deletion():
			continue
		var rid: String = str(c.get_meta("receta_id", ""))
		if rid != "":
			res.append(rid)
	return res


func _al_cambio_inv() -> void:
	if visible:
		_reconstruir()


func _al_cambio_oro(_oro_actual: int) -> void:
	_pintar_oro()
	if visible:
		_reconstruir()


func _pintar_oro() -> void:
	if _jugador != null and _oro != null:
		_oro.text = "Oro: %d" % _jugador.oro


func _reconstruir() -> void:
	if _lista == null:
		return
	for c in _lista.get_children():
		# remove_child + queue_free (no solo queue_free): si no, las filas
		# viejas siguen en el árbol un frame y el panel se ve duplicado al
		# cambiar de herrero.
		_lista.remove_child(c)
		c.queue_free()
	var ids: Array[String] = RecetasDB.recetas_de_herrero(_herrero_id)
	if ids.is_empty():
		var vacio: Label = Label.new()
		vacio.text = "Este herrero no tiene recetas."
		vacio.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lista.add_child(vacio)
		return
	for rid in ids:
		_lista.add_child(_fila_receta(rid))


func _fila_receta(receta_id: String) -> Control:
	var r: Dictionary = RecetasDB.obtener(receta_id)
	var caja := HBoxContainer.new()
	caja.add_theme_constant_override("separation", 8)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.set_meta("receta_id", receta_id)

	var datos := VBoxContainer.new()
	datos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	datos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nombre: Label = Label.new()
	nombre.text = "%s  (Nv %d)" % [str(r.get("nombre", receta_id)), int(r.get("nivel", 1))]
	nombre.add_theme_font_size_override("font_size", 15)
	nombre.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	datos.add_child(nombre)
	var mats: Label = Label.new()
	var lista_mats: Array[Dictionary] = _herreria.estado_materiales(receta_id, _jugador)
	mats.text = "Materiales: %s · %d oro" % [
		Herreria.texto_materiales(lista_mats), int(r.get("oro", 0))]
	mats.add_theme_font_size_override("font_size", 12)
	mats.add_theme_color_override("font_color", Color(0.72, 0.7, 0.62))
	mats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	datos.add_child(mats)
	var res: Dictionary = r.get("resultado", {})
	var item_id: String = str(res.get("item_id", ""))
	var item: Dictionary = ItemDB.obtener(item_id)
	var desc: Label = Label.new()
	desc.text = "→ %s: %s" % [str(item.get("nombre", item_id)),
		_texto_mods(item.get("mods", []))]
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.65, 0.8, 0.95))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	datos.add_child(desc)
	caja.add_child(datos)

	var motivo: String = _herreria.puede_forjar(receta_id, _jugador)
	var btn: Button = Button.new()
	btn.text = "Forjar" if motivo == "ok" else "Bloqueado"
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.disabled = motivo != "ok"
	btn.tooltip_text = Herreria.texto_motivo(motivo)
	btn.pressed.connect(_al_forjar.bind(receta_id))
	caja.add_child(btn)
	return caja


func _texto_mods(mods: Array) -> String:
	var partes: PackedStringArray = []
	for m in mods:
		if not (m is Dictionary):
			continue
		var md: Dictionary = m
		var v: float = float(md.get("valor", 0.0))
		if int(md.get("kind", 0)) == 1:
			partes.append("+%d%% %s" % [int(round(v * 100.0)), str(md.get("stat", ""))])
		elif absf(v) < 1.0:
			partes.append("%+.0f%% %s" % [v * 100.0, str(md.get("stat", ""))])
		else:
			partes.append("%+d %s" % [int(round(v)), str(md.get("stat", ""))])
	return ", ".join(partes)


func _al_forjar(receta_id: String) -> void:
	if _jugador == null:
		return
	var res: Dictionary = RecetasDB.obtener(receta_id)
	var item_id: String = str((res.get("resultado", {}) as Dictionary).get("item_id", ""))
	var motivo: String = _herreria.forjar(receta_id, _jugador)
	if motivo == "ok":
		_estado.text = "Forjaste %s" % str(ItemDB.obtener(item_id).get("nombre", item_id))
	else:
		_estado.text = Herreria.texto_motivo(motivo)
	_pintar_oro()
	_reconstruir()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if PilaUI.es_cima(self) and event.is_action_pressed("cancelar_seleccion"):
		cerrar_panel()
		get_viewport().set_input_as_handled()
