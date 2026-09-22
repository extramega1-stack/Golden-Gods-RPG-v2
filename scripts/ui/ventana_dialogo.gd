class_name VentanaDialogo
extends CanvasLayer
## Ventana de diálogo de la fase 6: muestra nombre, rol y líneas del NPC
## con el que el jugador habla (acción `interactuar`, tecla E).
##
## Solo LEE los datos del NPC (nombre_mostrado, rol, lineas_dialogo);
## nunca escribe stats ni llama a take_damage.
##
## Lección 11: arranca OCULTA (visible=false) y sin velo activo; cuando
## está inactiva no se come ningún clic. Al abrirse, el velo a pantalla
## completa SÍ captura clics (modal): el juego detrás no recibe órdenes.
##
## Avance: E (acción `interactuar`), clic izquierdo sobre la ventana o el
## botón "Continuar"/"Cerrar". ESC cierra el diálogo (la ventana consume
## el ESC en _input antes de que el Player lo vea como deselección).

signal dialogo_cerrado
## Fase 7: el jugador pulsó "Comerciar" con un NPC vendedor (la demo abre
## el PanelTienda; el diálogo se cierra solo).
signal comerciar_solicitado(npc: NPC)
## Fase 8: el jugador pulsó el botón de misión ("¡Misión disponible!" o
## "Entregar misión"). NO cierra el diálogo: la demo acepta/entrega y
## refresca el botón.
signal mision_solicitada(npc: NPC)
## Fase 16: el jugador pulsó "Viajar" con un NPC portero (la demo abre el
## PanelViaje; el diálogo se cierra solo).
signal viaje_solicitado(npc: NPC)

var _npc: NPC = null
var _lineas: Array[String] = []
var _indice: int = 0

var _titulo: Label = null
var _rol: Label = null
var _texto: Label = null
var _boton: Button = null
## Fase 7: solo visible si el NPC actual tiene tienda
## (TiendaDB.tienda_de_npc != ""); sin tienda no hay botón ni flujo.
var _boton_comerciar: Button = null
## Fase 8: botón + descripción de misión (ocultos por defecto; la demo los
## refresca con mostrar_mision() según oferta_para_npc).
var _boton_mision: Button = null
var _desc_mision: Label = null
## Fase 16: "Viajar" solo si el NPC actual es portero (viaje_id en
## data/npcs.json; sin viaje_id no hay botón ni flujo).
var _boton_viajar: Button = null


func _ready() -> void:
	layer = UiLayers.VENTANA_DIALOGO
	_construir()
	# Lección 11: oculto desde el arranque; el velo no existe como obstáculo
	# mientras no hay diálogo abierto.
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
	# Fase 8.1: anclado abajo-centro RESPONSIVO — el panel crece hacia ARRIBA
	# (GROW_DIRECTION_BEGIN) y su borde inferior queda por encima de la
	# barra de skills (ZONA_INFERIOR_RESERVADA + 16 px de aire). Sin offsets
	# mágicos ligados a la resolución: el contenido empuja el panel hacia
	# arriba y nunca se sale por el borde inferior del viewport.
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_top = -float(UiLayers.ZONA_INFERIOR_RESERVADA) - 16.0
	panel.offset_bottom = panel.offset_top
	panel.custom_minimum_size = Vector2(520, 180)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	velo.gui_input.connect(_al_gui_input_velo)
	panel.gui_input.connect(_al_gui_input_panel)
	add_child(panel)

	var margen: MarginContainer = MarginContainer.new()
	margen.add_theme_constant_override("margin_left", 20)
	margen.add_theme_constant_override("margin_right", 20)
	margen.add_theme_constant_override("margin_top", 16)
	margen.add_theme_constant_override("margin_bottom", 16)
	margen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margen)

	var caja: VBoxContainer = VBoxContainer.new()
	caja.add_theme_constant_override("separation", 8)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margen.add_child(caja)

	_titulo = Label.new()
	_titulo.add_theme_font_size_override("font_size", 20)
	_titulo.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(_titulo)

	_rol = Label.new()
	_rol.add_theme_font_size_override("font_size", 14)
	_rol.add_theme_color_override("font_color", Color(0.75, 0.72, 0.68))
	_rol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(_rol)

	_texto = Label.new()
	_texto.add_theme_font_size_override("font_size", 17)
	_texto.add_theme_color_override("font_color", Color(0.94, 0.93, 0.9))
	_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_texto.custom_minimum_size = Vector2(480, 64)
	_texto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(_texto)

	var fila: HBoxContainer = HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_END
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(fila)

	# Fase 8: descripción de la misión ofrecida (oculta por defecto).
	_desc_mision = Label.new()
	_desc_mision.add_theme_font_size_override("font_size", 15)
	_desc_mision.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_desc_mision.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_mision.custom_minimum_size = Vector2(480, 0)
	_desc_mision.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_mision.visible = false
	caja.add_child(_desc_mision)
	# Se mueve antes de la fila de botones (el orden visual importa).
	caja.move_child(_desc_mision, fila.get_index())

	_boton = Button.new()
	_boton.focus_mode = Control.FOCUS_NONE
	_boton.mouse_filter = Control.MOUSE_FILTER_STOP
	_boton.pressed.connect(avanzar)
	fila.add_child(_boton)

	# Fase 7: "Comerciar" solo si el NPC vende (se muestra en mostrar()).
	_boton_comerciar = Button.new()
	_boton_comerciar.text = "Comerciar"
	_boton_comerciar.focus_mode = Control.FOCUS_NONE
	_boton_comerciar.mouse_filter = Control.MOUSE_FILTER_STOP
	_boton_comerciar.pressed.connect(_al_comerciar)
	fila.add_child(_boton_comerciar)
	_boton_comerciar.visible = false

	# Fase 8: botón de misión (la demo lo muestra con mostrar_mision()).
	_boton_mision = Button.new()
	_boton_mision.focus_mode = Control.FOCUS_NONE
	_boton_mision.mouse_filter = Control.MOUSE_FILTER_STOP
	_boton_mision.pressed.connect(_al_mision)
	fila.add_child(_boton_mision)
	_boton_mision.visible = false

	# Fase 16: "Viajar" solo si el NPC es portero (se muestra en mostrar()).
	_boton_viajar = Button.new()
	_boton_viajar.text = "Viajar"
	_boton_viajar.focus_mode = Control.FOCUS_NONE
	_boton_viajar.mouse_filter = Control.MOUSE_FILTER_STOP
	_boton_viajar.pressed.connect(_al_viajar)
	fila.add_child(_boton_viajar)
	_boton_viajar.visible = false


## Abre el diálogo con un NPC. Sin NPC (null) no hace nada (sin errores).
func mostrar(npc: NPC) -> void:
	if npc == null:
		return
	_npc = npc
	_lineas = npc.lineas_dialogo.duplicate()
	_indice = 0
	if _lineas.is_empty():
		_lineas.append("…")
	# Fase 7: botón "Comerciar" solo para NPCs vendedores.
	_boton_comerciar.visible = TiendaDB.tienda_de_npc(npc.npc_id) != ""
	# Fase 16: botón "Viajar" solo para NPCs portero.
	_boton_viajar.visible = ViajeRapido.viaje_id_de_npc(npc.npc_id) != ""
	# Fase 8: la misión se refresca desde fuera (la demo llama
	# mostrar_mision()); aquí se oculta para no arrastrar estado viejo.
	_boton_mision.visible = false
	_desc_mision.visible = false
	_pintar()
	visible = true


## Avanza a la siguiente línea; al pasar la última cierra el diálogo.
func avanzar() -> void:
	if not esta_abierta():
		return
	_indice += 1
	if _indice >= _lineas.size():
		cerrar()
	else:
		_pintar()


func cerrar() -> void:
	if not esta_abierta():
		return
	visible = false
	_npc = null
	_lineas.clear()
	_indice = 0
	dialogo_cerrado.emit()


func esta_abierta() -> bool:
	return visible


## NPC actual (null si el diálogo está cerrado). Solo lectura.
func npc_actual() -> NPC:
	return _npc


## Línea que se está mostrando ("" si está cerrado).
func linea_actual() -> String:
	if not esta_abierta():
		return ""
	return _lineas[_indice]


## Posición de la línea actual (0-based); -1 si está cerrado.
func indice() -> int:
	return _indice if esta_abierta() else -1


## Texto que muestra el título (nombre del NPC); solo lectura (tests).
func titulo_texto() -> String:
	return _titulo.text


## Texto que muestra el rol; solo lectura (tests).
func rol_texto() -> String:
	return _rol.text


## Fase 7: true si el botón "Comerciar" está visible (el NPC actual vende).
## Sin tienda no hay botón: el comportamiento de la fase 6 queda intacto.
func tiene_comerciar() -> bool:
	return _boton_comerciar != null and _boton_comerciar.visible


## Fase 16: true si el botón "Viajar" está visible (el NPC actual es
## portero). Sin viaje_id no hay botón.
func tiene_viajar() -> bool:
	return _boton_viajar != null and _boton_viajar.visible


## Fase 8: true si el botón de misión está visible (hay oferta disponible
## o lista para entregar para el NPC actual).
func tiene_mision() -> bool:
	return _boton_mision != null and _boton_mision.visible


## Fase 8: refresca el botón/descripción de misión. modo "" oculta ambos;
## "disponible" muestra "¡Misión disponible: <nombre>!" + la descripción;
## "entregar" muestra "Entregar misión: <nombre>" (sin descripción).
func mostrar_mision(modo: String, nombre: String, descripcion: String) -> void:
	if modo == "":
		_boton_mision.visible = false
		_desc_mision.visible = false
		return
	if modo == "disponible":
		_boton_mision.text = "¡Misión disponible: %s!" % nombre
		_desc_mision.text = descripcion
		_desc_mision.visible = true
	elif modo == "entregar":
		_boton_mision.text = "Entregar misión: %s" % nombre
		_desc_mision.visible = false
	else:
		_boton_mision.visible = false
		_desc_mision.visible = false
		return
	_boton_mision.visible = true


## Fase 8: pulsar el botón de misión emite la señal SIN cerrar el diálogo
## (la demo acepta/entrega y refresca el botón en su lugar).
func _al_mision() -> void:
	if not esta_abierta() or _npc == null:
		return
	mision_solicitada.emit(_npc)


## Fase 7: pulsar "Comerciar" emite la señal y cierra el diálogo (la demo
## abre el PanelTienda con ese NPC).
func _al_comerciar() -> void:
	if not esta_abierta() or _npc == null:
		return
	var n: NPC = _npc
	comerciar_solicitado.emit(n)
	cerrar()


## Fase 16: pulsar "Viajar" emite la señal y cierra el diálogo (la demo
## abre el PanelViaje con la ciudad del portero).
func _al_viajar() -> void:
	if not esta_abierta() or _npc == null:
		return
	var n: NPC = _npc
	viaje_solicitado.emit(n)
	cerrar()


func _pintar() -> void:
	_titulo.text = _npc.nombre_mostrado if _npc != null else "NPC"
	_rol.text = _npc.rol if _npc != null and _npc.rol != "" else ""
	_texto.text = _lineas[_indice]
	_boton.text = "Cerrar" if _indice == _lineas.size() - 1 else "Continuar"


## Clic izquierdo sobre el velo o el panel: avanza el diálogo. El velo
## tiene MOUSE_FILTER_STOP, así que estos clics nunca llegan al Player
## (el juego detrás no se mueve mientras se habla).
func _al_gui_input_velo(event: InputEvent) -> void:
	_al_clic_avanzar(event)


func _al_gui_input_panel(event: InputEvent) -> void:
	_al_clic_avanzar(event)


func _al_clic_avanzar(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			avanzar()


## _input corre antes que el _unhandled_input del Player: el diálogo
## consume E (avanzar) y ESC (cerrar) antes de que lleguen al juego.
func _input(event: InputEvent) -> void:
	if not esta_abierta():
		return
	if event.is_action_pressed("interactuar"):
		avanzar()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancelar_seleccion"):
		cerrar()
		get_viewport().set_input_as_handled()
