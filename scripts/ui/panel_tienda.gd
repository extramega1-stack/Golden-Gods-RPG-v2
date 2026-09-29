class_name PanelTienda
extends CanvasLayer
## Panel de tienda de la fase 7 (capa `UiLayers.PANEL_TIENDA` = 82).
##
## Arranca OCULTO (`visible = false`; lección 11) y no se come clics
## inactivo. Al abrirse: velo modal fullscreen con MOUSE_FILTER_STOP (como
## VentanaDialogo); ESC cierra (consumido en `_input` antes que el Player).
##
## Dos listas: stock del vendedor (nombre, precio, cantidad, botón
## "Comprar") y mochila del jugador (nombre xN, precio de venta, botón
## "Vender"; los equipados muestran la etiqueta "equipado" sin botón).
## Muestra el oro actual (se refresca con `oro_cambiado`).
##
## REGLA: la UI SOLO LEE. Todas las mutaciones pasan por
## `Tienda.comprar()`/`Tienda.vender()`. Se reconstruye al abrirse y ante
## las señales `tienda.cambiada`, `inventario.cambiado` y `oro_cambiado`.

signal tienda_cerrada

var _tienda: Tienda = null
var _tienda_id: String = ""
var _jugador: Player = null

var _titulo: Label = null
var _oro: Label = null
var _lista_stock: VBoxContainer = null
var _lista_mochila: VBoxContainer = null
var _estado: Label = null


func _ready() -> void:
	layer = UiLayers.PANEL_TIENDA
	_construir()
	# Lección 11: oculto desde el arranque.
	visible = false
	PilaUI.cerrar(self)


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

	_titulo = Label.new()
	_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_titulo.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_titulo.add_theme_font_size_override("font_size", 22)
	caja.add_child(_titulo)

	_oro = Label.new()
	_oro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_oro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_oro.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	_oro.add_theme_font_size_override("font_size", 17)
	caja.add_child(_oro)

	caja.add_child(_etiqueta_seccion("El vendedor"))
	var scroll_v: ScrollContainer = ScrollContainer.new()
	scroll_v.custom_minimum_size = Vector2(460, 170)
	scroll_v.mouse_filter = Control.MOUSE_FILTER_PASS
	caja.add_child(scroll_v)
	_lista_stock = VBoxContainer.new()
	_lista_stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lista_stock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lista_stock.add_theme_constant_override("separation", 4)
	scroll_v.add_child(_lista_stock)

	caja.add_child(_etiqueta_seccion("Tu mochila"))
	var scroll_m: ScrollContainer = ScrollContainer.new()
	scroll_m.custom_minimum_size = Vector2(460, 170)
	scroll_m.mouse_filter = Control.MOUSE_FILTER_PASS
	caja.add_child(scroll_m)
	_lista_mochila = VBoxContainer.new()
	_lista_mochila.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lista_mochila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lista_mochila.add_theme_constant_override("separation", 4)
	scroll_m.add_child(_lista_mochila)

	_estado = Label.new()
	_estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_estado.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_estado.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	_estado.add_theme_font_size_override("font_size", 14)
	caja.add_child(_estado)

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


func _etiqueta_seccion(texto: String) -> Label:
	var l: Label = Label.new()
	l.text = texto
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", Color(0.75, 0.72, 0.68))
	l.add_theme_font_size_override("font_size", 14)
	return l


## Conecta el panel al jugador; re-llamar reconecta (tras cargar partida
## el Inventario/Equipo son instancias nuevas, como en PanelInventario).
func conectar(j: Player) -> void:
	if _jugador != null:
		if is_instance_valid(_jugador.inventario) \
				and _jugador.inventario.cambiado.is_connected(_al_cambio):
			_jugador.inventario.cambiado.disconnect(_al_cambio)
		if _jugador.oro_cambiado.is_connected(_al_oro):
			_jugador.oro_cambiado.disconnect(_al_oro)
	_jugador = j
	if _jugador != null:
		if _jugador.inventario != null:
			_jugador.inventario.cambiado.connect(_al_cambio)
		_jugador.oro_cambiado.connect(_al_oro)
	if esta_abierta():
		_reconstruir()


## Abre la tienda de un NPC. Con NPC sin tienda (o null) no hace nada:
## no revienta y no se abre.
func mostrar(tienda: Tienda, npc: NPC) -> void:
	if tienda == null or npc == null:
		return
	var tid: String = TiendaDB.tienda_de_npc(npc.npc_id)
	if tid == "" or not TiendaDB.existe(tid):
		return
	if _tienda != null and _tienda.cambiada.is_connected(_al_cambio):
		_tienda.cambiada.disconnect(_al_cambio)
	_tienda = tienda
	_tienda_id = tid
	_tienda.cambiada.connect(_al_cambio)
	_titulo.text = str(TiendaDB.obtener(tid).get("nombre", "Tienda"))
	_reconstruir()
	visible = true
	PilaUI.abrir(self)


func cerrar_panel() -> void:
	if not esta_abierta():
		return
	visible = false
	PilaUI.cerrar(self)
	tienda_cerrada.emit()


func esta_abierta() -> bool:
	return visible


## Id de la tienda mostrada ("" si nunca se abrió).
func tienda_id_actual() -> String:
	return _tienda_id


## Mensaje de estado actual ("" si ninguno); solo lectura (tests).
func estado_texto() -> String:
	return _estado.text


func _al_cambio() -> void:
	if esta_abierta():
		_reconstruir()


func _al_oro(_oro_actual: int) -> void:
	if esta_abierta():
		_reconstruir()


func _reconstruir() -> void:
	if _tienda == null or _tienda_id == "":
		return
	_reconstruir_stock()
	_reconstruir_mochila()
	_pintar_oro()


func _pintar_oro() -> void:
	if _jugador == null:
		_oro.text = "Oro: —"
	else:
		_oro.text = "Oro: %d" % _jugador.oro


func _reconstruir_stock() -> void:
	for h in _lista_stock.get_children():
		h.queue_free()
	var filas: Array = _tienda.stock_de(_tienda_id)
	if filas.is_empty():
		_lista_stock.add_child(_etiqueta_seccion("(agotado)"))
		return
	for f in filas:
		var fd: Dictionary = f
		var item_id: String = str(fd.get("item_id", ""))
		var item: Dictionary = ItemDB.obtener(item_id)
		var nombre: String = str(item.get("nombre", item_id))
		var precio: int = int(fd.get("precio_compra", 0))
		var cant: int = int(fd.get("cantidad", 0))
		var fila: HBoxContainer = HBoxContainer.new()
		fila.add_theme_constant_override("separation", 8)
		fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lista_stock.add_child(fila)
		var lab: Label = Label.new()
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if cant > 0:
			lab.text = "%s — %d oro (x%d)" % [nombre, precio, cant]
			fila.add_child(lab)
			fila.add_child(_boton("Comprar", _comprar.bind(item_id)))
		else:
			lab.text = "%s — agotado" % nombre
			fila.add_child(lab)


func _reconstruir_mochila() -> void:
	for h in _lista_mochila.get_children():
		h.queue_free()
	if _jugador == null or _jugador.inventario == null:
		_lista_mochila.add_child(_etiqueta_seccion("(sin jugador)"))
		return
	var inv: Inventario = _jugador.inventario
	if inv.entradas.is_empty():
		_lista_mochila.add_child(_etiqueta_seccion("(vacía)"))
		return
	for e in inv.entradas:
		if not (e is Dictionary):
			continue
		var ed: Dictionary = e
		var item_id: String = str(ed.get("item_id", ""))
		var cant: int = int(ed.get("cantidad", 0))
		var item: Dictionary = ItemDB.obtener(item_id)
		var nombre: String = str(item.get("nombre", item_id))
		var fila: HBoxContainer = HBoxContainer.new()
		fila.add_theme_constant_override("separation", 8)
		fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lista_mochila.add_child(fila)
		var lab: Label = Label.new()
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fila.add_child(lab)
		if _esta_equipado(item_id):
			lab.text = "%s — equipado" % nombre
		else:
			lab.text = "%s x%d — %d oro" % [nombre, cant, _tienda.precio_venta(item_id)]
			fila.add_child(_boton("Vender", _vender.bind(item_id)))


func _esta_equipado(item_id: String) -> bool:
	if _jugador == null or _jugador.equipo == null:
		return false
	for slot in Equipo.SLOTS:
		if _jugador.equipo.equipado_en(slot) == item_id:
			return true
	return false


func _boton(texto: String, accion: Callable) -> Button:
	var b: Button = Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(accion)
	return b


## La UI solo lee: las mutaciones pasan por Tienda.
func _comprar(item_id: String) -> void:
	if _tienda == null or _jugador == null or _tienda_id == "":
		return
	_informar(_tienda.comprar(_jugador, _tienda_id, item_id))


func _vender(item_id: String) -> void:
	if _tienda == null or _jugador == null:
		return
	_informar(_tienda.vender(_jugador, item_id))


func _informar(codigo: String) -> void:
	match codigo:
		"ok":
			_estado.text = "Transacción completa."
		"sin_oro":
			_estado.text = "No tienes oro suficiente."
		"sin_stock":
			_estado.text = "Sin stock."
		"sin_espacio":
			_estado.text = "Mochila llena: no cupo el item (oro revertido)."
		"equipado":
			_estado.text = "Está equipado: desequípalo primero."
		"tienda_desconocida":
			_estado.text = "Tienda desconocida."
		"item_desconocido":
			_estado.text = "Item desconocido."
		_:
			_estado.text = "Error: %s." % codigo
	_reconstruir()


## _input corre antes que el _unhandled_input del Player: la tienda
## consume ESC (cerrar) antes de que llegue al juego.
func _input(event: InputEvent) -> void:
	if not esta_abierta():
		return
	if PilaUI.es_cima(self) and event.is_action_pressed("cancelar_seleccion"):
		cerrar_panel()
		get_viewport().set_input_as_handled()
