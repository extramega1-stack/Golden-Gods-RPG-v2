class_name PanelEquipo
extends CanvasLayer
## Paperdoll de equipo estilo FlyFF (fase 31): 12 slots en 3 columnas
## (izq arma/escudo · centro casco/armadura/guantes/botas · der joyería).
## Clic en un slot ocupado = "Quitar" → `equipo.desequipar(slot, stats,
## inventario)`. Equipar se hace desde el inventario (botón "Equipar").
##
## Regla dura: arranca con visible=false (oculto no intercepta nada); al
## mostrarse, solo el panel lleva mouse_filter STOP (lección 11 de AGENTS.md).
## Se reconstruye al abrirse y al recibir `equipo.cambiado`/`inventario.cambiado`.

## Columnas del paperdoll.
const COL_IZQ: Array[String] = ["arma", "escudo"]
const COL_CENTRO: Array[String] = ["casco", "armadura", "guantes", "botas"]
const COL_DER: Array[String] = ["pendiente_1", "pendiente_2", "collar",
	"anillo_1", "anillo_2", "amuleto"]

var _jugador: Player = null
var _columnas: VBoxContainer = null
var _linea_stats: Label = null


func _init() -> void:
	layer = UiLayers.PANEL_EQUIPO
	_construir_cromo()
	visible = false



func _construir_cromo() -> void:
	var fondo := PanelContainer.new()
	# Bloque 67: el tamaño y la posición salen del viewport, no de
	# numeros duros: con una ventana estrecha el panel se salia, y
	# en una enorme quedaba ridiculo en una esquina.
	AjustaUI.centrar(fondo, 0.36, 0.69)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
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
	titulo.text = "Equipo (C)"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 20)
	titulo.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	caja.add_child(titulo)
	_columnas = VBoxContainer.new()
	caja.add_child(_columnas)
	_linea_stats = Label.new()
	_linea_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_linea_stats.add_theme_font_size_override("font_size", 13)
	_linea_stats.add_theme_color_override("font_color", Color(0.75, 0.72, 0.62))
	caja.add_child(_linea_stats)


## Conecta (o reconecta) al jugador. Re-suscribe sin duplicar.
func conectar(j: Player) -> void:
	if _jugador != null and is_instance_valid(_jugador):
		if _jugador.equipo.cambiado.is_connected(_reconstruir):
			_jugador.equipo.cambiado.disconnect(_reconstruir)
		if _jugador.inventario.cambiado.is_connected(_reconstruir):
			_jugador.inventario.cambiado.disconnect(_reconstruir)
	_jugador = j
	if _jugador != null and is_instance_valid(_jugador):
		if not _jugador.equipo.cambiado.is_connected(_reconstruir):
			_jugador.equipo.cambiado.connect(_reconstruir)
		if not _jugador.inventario.cambiado.is_connected(_reconstruir):
			_jugador.inventario.cambiado.connect(_reconstruir)
	_reconstruir()


func _reconstruir(_arg = null) -> void:
	if _columnas == null:
		return
	for h in _columnas.get_children():
		h.queue_free()
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var fila := HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_CENTER
	fila.add_theme_constant_override("separation", 12)
	_columnas.add_child(fila)
	fila.add_child(_columna(COL_IZQ))
	fila.add_child(_columna(COL_CENTRO))
	fila.add_child(_columna(COL_DER))
	_actualizar_stats()


func _columna(slots: Array) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	for slot in slots:
		col.add_child(_celda_slot(str(slot)))
	return col


func _celda_slot(slot: String) -> VBoxContainer:
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 2)
	var etiqueta := Label.new()
	etiqueta.text = Equipo.nombre_slot(slot)
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiqueta.add_theme_font_size_override("font_size", 11)
	etiqueta.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
	caja.add_child(etiqueta)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(120.0, 40.0)
	var iid: String = _jugador.equipo.equipado_en(slot)
	if iid != "":
		btn.text = str(ItemDB.obtener(iid).get("nombre", iid))
		btn.tooltip_text = "%s\nClic para quitar" % str(ItemDB.obtener(iid).get("descripcion", ""))
		btn.pressed.connect(_al_quitar.bind(slot))
	else:
		btn.text = "—"
		btn.disabled = true
	caja.add_child(btn)
	return caja


func _al_quitar(slot: String) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	# Fase 72: quitar algo que no se puede quitar tiene que sonar a error. El
	# sonido va en el botón, no en `Equipment.desequipar()`: la lógica también
	# devuelve false al cargar un guardado, y eso no es un error del jugador.
	if not _jugador.equipo.desequipar(slot, _jugador.stats, _jugador.inventario):
		SonidoUI.error()


func _actualizar_stats() -> void:
	if _linea_stats == null:
		return
	if _jugador == null or not is_instance_valid(_jugador):
		_linea_stats.text = ""
		return
	var st: StatBlock = _jugador.stats
	_linea_stats.text = "Ataque %d · Defensa %d · Vida %d/%d" % [
		int(st.ataque), int(st.defensa),
		int(_jugador.vida_actual), int(st.vida_max)]


## C alterna el equipo.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("abrir_equipo"):
		visible = not visible
		# ABRIR POR PILA, NO POR `visible` A PELO.
		#
		# Este panel antes flipeaba `visible` y solo llamaba `PilaUI.cerrar()`
		# al cerrar. O sea que al abrir NO se apilaba, y el ESC de mas abajo
		# comprueba `PilaUI.es_cima(self)`, que era falso: el ESC no cerraba el equipo.
		# Medido por la partida completa (`tools/jugar.sh`, P11).
		#
		# La pila es la unica que sabe que esta arriba. Un panel que se abre sin
		# apilarse es invisible para el sistema de cierre.
		if visible:
			PilaUI.abrir(self)
		else:
			PilaUI.cerrar(self)
		if visible:
			_reconstruir()
		get_viewport().set_input_as_handled()


## ESC cierra (corre antes que el _unhandled_input del Player).
func _input(event: InputEvent) -> void:
	if visible and PilaUI.es_cima(self) \
			and event.is_action_pressed("cancelar_seleccion"):
		visible = false
		PilaUI.cerrar(self)
		get_viewport().set_input_as_handled()
