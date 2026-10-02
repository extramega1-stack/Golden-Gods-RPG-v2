class_name MenuPausa
extends CanvasLayer
## Bloque 65: el menú de pausa, y el dueño de la PILA de paneles.
##
## POR QUÉ ES UNA PILA Y NO OTRO `_unhandled_input`: antes de esto, DIEZ
## scripts de UI se apropiaban del ESC por su cuenta (`_input` en cada uno). Con
## dos paneles abiertos, el ESC cerraba los dos a la vez o ninguno, según el
## orden del árbol. Es el bug clásico de "cada panel resuelve su propio teclado",
## y se nota en cuanto hay dos paneles.
##
## La pila: el último panel abierto es el primero en cerrar. El de pausa es la
## BASE y nunca se cierra con ESC (se cierra con "Reanudar" o con la misma tecla
## de pausa). Un panel que se empuja a sí mismo sobre la pausa, como opciones,
## se sitúa por ENCIMA de ella.
##
## - `get_tree().paused = true` con `process_mode = ALWAYS`, y los paneles
##   registrados se ponen también en ALWAYS para que sigan recibiendo ratón.
## - Volver al título pasa por `Transicion` para que no sea un corte seco.

const CAPA: int = UiLayers.MENU_PAUSA

## §9.1
var system_id: StringName = &"menu_pausa"

## El panel de pausa emite esto para que la demo (o quien lo quiera) sepa que
## el jugador volvió al mundo. Antes no había forma de enterarse.
signal reanudado
signal pausado

var _pila: Array = []
var _caja: VBoxContainer = null
var _capa_fondo: Control = null
var _abierto: bool = false


func _init() -> void:
	layer = CAPA
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir()
	visible = false


func _construir() -> void:
	# Un oscurecido por detrás: sin él, el panel de pausa se lee como algo
	# flotando sobre el juego todavía vivo, cuando lo que tiene que decir es
	# "el juego está parado".
	_capa_fondo = ColorRect.new()
	_capa_fondo.name = "Oscurecido"
	_capa_fondo.color = Color(0, 0, 0, 0.55)
	_capa_fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: es lo que hace que un clic detrás no llegue al mundo pausado.
	_capa_fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	_capa_fondo.gui_input.connect(_al_fondo)
	add_child(_capa_fondo)

	var fondo := PanelContainer.new()
	fondo.set_anchors_preset(Control.PRESET_CENTER)
	# Bloque 67: tamaño y posicion del viewport, no numeros duros.
	AjustaUI.centrar(fondo, 0.30, 0.47)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.add_theme_constant_override("margin_left", 18)
	margen.add_theme_constant_override("margin_right", 18)
	margen.add_theme_constant_override("margin_top", 14)
	margen.add_theme_constant_override("margin_bottom", 14)
	fondo.add_child(margen)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 8)
	margen.add_child(caja)
	_caja = caja

	var titulo := Label.new()
	titulo.text = "Pausa"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 24)
	titulo.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	caja.add_child(titulo)

	_boton("Reanudar", _al_reanudar)
	_boton("Opciones", _al_opciones)
	_boton("Guardar partida", _al_guardar)
	_boton("Volver al título", _al_titulo)
	_boton("Salir del juego", _al_salir)


func _boton(texto: String, accion: Callable) -> void:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Vector2(0, 40.0)
	b.pressed.connect(accion)
	# Fase 72: el clic. Esta factory es la UNICA vía por la que el menú crea
	# botones, así que un `SonidoUI.boton()` acá cubre los cinco sin que cada
	# uno se acuerde.
	SonidoUI.boton(b)
	_caja.add_child(b)


func esta_abierto() -> bool:
	return _abierto


## Abre o cierra. Devuelve si quedó abierto, que es lo que necesita el input
## global para no seguir procesando cuando ya no toca.
func alternar() -> bool:
	if _abierto:
		cerrar()
	else:
		abrir()
	return _abierto


func abrir() -> void:
	if _abierto:
		return
	_abierto = true
	_pila.clear()
	visible = true
	get_tree().paused = true
	var sv: SaveSystem = _sistema_saves()
	if sv != null:
		sv.fijar_autosave(false)
	# Los hijos tienen que ser ALWAYS también: un CanvasLayer con ALWAYS
	# alcanza a sus hijos, pero un panel que se registre después en la pila no.
	for c in get_children():
		if c is Control:
			(c as Control).process_mode = Node.PROCESS_MODE_ALWAYS
	pausado.emit()


func cerrar() -> void:
	if not _abierto:
		return
	_abierto = false
	_pila.clear()
	visible = false
	get_tree().paused = false
	var sv: SaveSystem = _sistema_saves()
	if sv != null:
		sv.fijar_autosave(true)
	reanudado.emit()


## Empuja un panel a la pila: se pausa el juego, el panel se hace visible, y el
## ESC lo cierra en orden inverso. Devuelve si se pudo.
func apilar(panel: CanvasLayer) -> bool:
	if panel == null or not is_instance_valid(panel):
		return false
	if _pila.has(panel):
		return true
	_pila.append(panel)
	if not _abierto:
		abrir()
	else:
		# Un panel por encima de la pausa tiene que verse por encima de ella.
		panel.layer = maxi(panel.layer, CAPA + 1)
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = true
	return true


## Cierra el panel de la cima. Devuelve si cerró algo.
func desapilar() -> bool:
	if _pila.is_empty():
		return false
	var panel: CanvasLayer = _pila.pop_back() as CanvasLayer
	if panel != null and is_instance_valid(panel):
		panel.visible = false
	# Si era el último encima de la pausa, la pausa sigue: salir del submenú
	# no es cerrar la pausa.
	return true


func _al_fondo(event: InputEvent) -> void:
	# Clic en el oscurecido = ESC. Es lo que espera cualquiera que haga clic
	# fuera de un menú.
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_al_reanudar()


func _al_reanudar() -> void:
	if _pila.is_empty():
		cerrar()
	else:
		desapilar()


## El guardado no se pierde por tocar "volver al título": es la forma más
## rápida de que un jugador deje de tocar el botón. Se guarda SIEMPRE, sin
## preguntar por "hay cambios": preguntar es una decisión del jugador y un
## diálogo modal que puede dejar la partida sin guardar.
func _guardar_si_hay_sistema() -> bool:
	var s: SaveSystem = _sistema_saves()
	if s == null:
		return false
	return s.guardar()


func _sistema_saves() -> SaveSystem:
	if Systems.actual == null:
		return null
	return Systems.actual.obtener(&"save_system") as SaveSystem


func _sistema_feed() -> FeedAvisos:
	if Systems.actual == null:
		return null
	return Systems.actual.obtener(&"feed_avisos") as FeedAvisos


func _al_opciones() -> void:
	var pa: PanelOpciones = _sistema_opciones()
	if pa == null:
		return
	apilar(pa)
	pa.abrir()


func _al_guardar() -> void:
	if _guardar_si_hay_sistema():
		var f: FeedAvisos = _sistema_feed()
		if f != null:
			f.aviso("Partida guardada")


func _al_titulo() -> void:
	_guardar_si_hay_sistema()
	cerrar()
	Transicion.ir_a(Escenas.TITULO)


func _al_salir() -> void:
	_guardar_si_hay_sistema()
	get_tree().quit()


func _sistema_opciones() -> PanelOpciones:
	if Systems.actual == null:
		return null
	return Systems.actual.obtener(&"panel_opciones") as PanelOpciones


## La entrada global. `PROCESS_MODE_ALWAYS` porque la pausa pausa el árbol.
## Bloque 65: el reloj del autosave. `MenuPausa` vive en el árbol, así que es
## quien le da el `delta` al `SaveSystem` (un `RefCounted`, sin `_process`).
## Se pausa con el juego: si la partida está parada, no hay nada que guardar.
func _process(delta: float) -> void:
	if _abierto:
		return
	var s: SaveSystem = _sistema_saves()
	if s != null:
		s.avanzar_autosave(delta)


func _unhandled_input(event: InputEvent) -> void:
	# SOLO Bajadas. Una tecla que se SUELTA también llega como evento, y sin
	# esta guarda el primer ESC de la partida se pierde: el arnés y el motor
	# mandan el `pressed=false` antes del `pressed=true`, y ese primer evento
	# —que no es una pulsación— consumía el turno. Medido con un ESC solo: el
	# primero no abría nada y el segundo sí.
	#
	# No es un detalle del arnés: cualquier consumidor de `is_action_pressed`
	# tiene que mirar esto, porque `Input.parse_input_event` entrega el release
	# como un evento más.
	if event is InputEventKey and not (event as InputEventKey).pressed:
		return
	# El ESC de la PILA va primero: si hay un panel encima (opciones, o una
	# ventana de diálogo), ese es el que lo cierra. La pausa no se cierra con
	# ESC mientras haya algo encima.
	if event.is_action_pressed("cerrar_menu"):
		if _pila.is_empty():
			if _abierto:
				cerrar()
			else:
				abrir()
		else:
			desapilar()
		get_viewport().set_input_as_handled()
		return
	# El MISMO ESC con otra acción (`abrir_pausa`), que es la tecla de pausa
	# dedicada. Se deja el camino viejo por si algo la usa todavía.
	if event.is_action_pressed("abrir_pausa"):
		if _abierto:
			_al_reanudar()
		else:
			abrir()
		get_viewport().set_input_as_handled()
