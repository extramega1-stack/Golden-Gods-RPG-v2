class_name PanelNgPlus
extends CanvasLayer
## Bloque 68: el NG+ POR PANTALLA. Antes era `NuevoJuegoPlus` sola, matemática
## pura sin nadie que la llamara: se podía testear el multiplicador y no verlo
## jamás jugando. Este panel es el que la hace visible.
##
## - Capa propia (`UiLayers.PANEL_NGPLUS`, rango de panel de sistema, §9.1).
## - UI que SOLO LEE (§7.11): pregunta al `EstadoNgPlus` y escribe labels. No
##   toca el save ni el `StatBlock`; reiniciar la vuelta es del guardado
##   (`SaveSystem.reiniciar_para_ngplus`), no de un panel.
## - Se SUSCRIBE a `EstadoNgPlus.cambiado` (§9.5): el texto se repinta cuando
##   cambia el dato, no cada frame. Por eso conectar la señal en el test NO
##   basta: hay que mover el estado y ver el label cambiar.
## - Nace cerrado (`visible = false` al construir, lección 11).
##
## Lo abre la pantalla de título o, jugando, la línea de wiring que registra
## este panel en `fase14_demo._instalar_fase63_64_ui`. `alternar()` +
## `actual` están para eso: un panel que nadie puede abrir no existe.

const CAPA: int = UiLayers.PANEL_NGPLUS

## §9.1
var system_id: StringName = &"panel_ngplus"

## La instancia viva, para el atajo de teclado y para el test. Es estática
## por el mismo motivo que `Systems.actual`: un panel colgado de un
## `CanvasLayer` deep en la escena no tiene a nadie a quien preguntarle.
static var actual: PanelNgPlus = null

var _estado: EstadoNgPlus = null
var _ciclo: Label = null
var _prestigio: Label = null
var _multiplicadores: VBoxContainer = null
var _aviso: Label = null


func _init() -> void:
	layer = CAPA
	_construir()
	visible = false


func _construir() -> void:
	var fondo: PanelContainer = PanelContainer.new()
	# Bloque 67: tamaño y posición del viewport, no números duros.
	AjustaUI.centrar(fondo, 0.30, 0.50)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fondo)

	var margen: MarginContainer = MarginContainer.new()
	margen.add_theme_constant_override("margin_left", 14)
	margen.add_theme_constant_override("margin_right", 14)
	margen.add_theme_constant_override("margin_top", 10)
	margen.add_theme_constant_override("margin_bottom", 10)
	fondo.add_child(margen)

	var caja: VBoxContainer = VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	margen.add_child(caja)

	var titulo: Label = Label.new()
	titulo.text = "Nueva vuelta (NG+)"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 22)
	titulo.add_theme_color_override("font_color", Color(0.95, 0.76, 0.32))
	caja.add_child(titulo)

	var explicacion: Label = Label.new()
	explicacion.text = "Al llegar al nivel %d el personaje vuelve a empezar,\npero el prestigio se queda." % NuevoJuegoPlus.tope_nivel()
	explicacion.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explicacion.add_theme_font_size_override("font_size", 13)
	explicacion.add_theme_color_override("font_color", Color(0.72, 0.70, 0.64))
	caja.add_child(explicacion)

	_ciclo = _nueva_linea("Ciclo", caja)
	_prestigio = _nueva_linea("Prestigio acumulado", caja)

	var separador: Label = Label.new()
	separador.text = "Lo que da el prestigio"
	separador.add_theme_font_size_override("font_size", 15)
	separador.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	caja.add_child(separador)

	_multiplicadores = VBoxContainer.new()
	_multiplicadores.add_theme_constant_override("separation", 4)
	caja.add_child(_multiplicadores)

	_aviso = Label.new()
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.add_theme_font_size_override("font_size", 13)
	_aviso.add_theme_color_override("font_color", Color(0.80, 0.60, 0.35))
	_aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(_aviso)

	var cerrar: Button = Button.new()
	cerrar.text = "Cerrar (ESC)"
	cerrar.pressed.connect(cerrar_panel)
	caja.add_child(cerrar)


## Una fila "etiqueta: valor" con el valor en un Label propio, para poder
## repintarlo sin reconstruir el panel (reconstruir en cada `cambiado` sería
## tirar los nodos cada vez que se prestigia).
func _nueva_linea(etiqueta: String, padre: VBoxContainer) -> Label:
	var fila: HBoxContainer = HBoxContainer.new()
	padre.add_child(fila)
	var l: Label = Label.new()
	l.text = etiqueta
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.74, 0.72, 0.66))
	fila.add_child(l)
	var valor: Label = Label.new()
	valor.text = "0"
	valor.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	valor.add_theme_font_size_override("font_size", 15)
	valor.add_theme_color_override("font_color", Color(0.95, 0.92, 0.84))
	fila.add_child(valor)
	return valor


## Abre con el estado del NG+ del jugador. Sin estado (o uno destruido) no
## abre: un panel de NG+ sin NG+ que mostrar es ruido.
func abrir(estado: EstadoNgPlus) -> bool:
	if estado == null or not is_instance_valid(estado):
		push_warning("[PanelNgPlus] abrir sin EstadoNgPlus")
		return false
	_desuscribir()
	_estado = estado
	_estado.cambiado.connect(_al_cambiar)
	actual = self
	_refrescar()
	visible = true
	PilaUI.abrir(self)
	return true


## Abre/cierra. Lo llama el atajo de teclado desde la escena.
func alternar() -> bool:
	if visible:
		cerrar_panel()
		return false
	return abrir(_estado)


## Cierra y se desuscribe. Desuscribirse al cerrar (y no solo al morir el
## nodo) evita el `Callable` colgando a un `RefCounted` liberado: `cambiado`
## es de un RefCounted y el panel es de la escena, y sus vidas no coinciden.
func cerrar_panel() -> void:
	visible = false
	PilaUI.cerrar(self)
	_desuscribir()
	_estado = null
	if actual == self:
		actual = null


func _desuscribir() -> void:
	if _estado == null or not is_instance_valid(_estado):
		return
	if _estado.cambiado.is_connected(_al_cambiar):
		_estado.cambiado.disconnect(_al_cambiar)


## Lo dispara la señal del estado: el dato se movió, el texto se repinta.
func _al_cambiar() -> void:
	_refrescar()


func _refrescar() -> void:
	if _estado == null or not is_instance_valid(_estado):
		return
	_ciclo.text = "Ciclo %d" % _estado.ciclo
	_prestigio.text = "%d puntos" % _estado.prestigio
	_pintar_multiplicadores()
	_aviso.text = "" if SaveSystem.puede_nuevo_game_plus() else _motivo_bloqueo()


## Los multiplicadores son un número de filas VARIABLE (3 sin prestigio, 8
## con él), y solo cambian al prestigiar: se reconstruyen enteros en ese
## momento y no se tocan nunca más. Es el compromiso de §9.5 — nada de
## reconstruir el panel por frame — y el precio son 8 nodos, una vez cada
## varias horas de juego.
func _pintar_multiplicadores() -> void:
	for n in _multiplicadores.get_children():
		var fila: Node = n as Node
		if fila == null or not is_instance_valid(fila):
			continue
		# `remove_child` ANTES de `queue_free`: un nodo solo liberado sigue
		# colgando del árbol hasta el final del frame, y como este panel se
		# repinta entero, se leería dos veces (la vieja y la nueva).
		_multiplicadores.remove_child(fila)
		fila.queue_free()
	_agregar_fila("XP", "x%.2f" % _estado.multiplicador_xp())
	_agregar_fila("Enemigos", "x%.2f" % _estado.multiplicador_enemigo())
	_agregar_fila("Afijos extra por item", "+%d" % _estado.afijos_extra())
	var bon: Dictionary = _estado.bonificacion()
	if bon.is_empty():
		return
	_agregar_fila("Ataque", "+%d%%" % _porcentaje(bon, "ataque"))
	_agregar_fila("Poder", "+%d%%" % _porcentaje(bon, "poder"))
	_agregar_fila("Vida máxima", "+%d%%" % _porcentaje(bon, "vida_max"))
	_agregar_fila("Maná máximo", "+%d%%" % _porcentaje(bon, "mana_max"))
	_agregar_fila("Defensa", "+%d%%" % _porcentaje(bon, "defensa"))


func _agregar_fila(etiqueta: String, valor: String) -> void:
	_nueva_linea(etiqueta, _multiplicadores).text = valor


func _porcentaje(bon: Dictionary, stat: String) -> int:
	return int(round(float(bon.get(stat, 0.0)) * 100.0))


## Todos los textos que el panel tiene pintados, para el test y para el
## diagnóstico. Sin esto, comprobar que la UI "se movió" exigiría recorrer el
## árbol a mano desde el test, y un test que no puede FALLAR no es un test.
## Solo LEE: no muta nada.
func textos() -> Array[String]:
	var salida: Array[String] = []
	_recolectar_textos(self, salida)
	return salida


func _recolectar_textos(n: Node, salida: Array[String]) -> void:
	if n is Label:
		salida.append((n as Label).text)
	for hijo in n.get_children():
		_recolectar_textos(hijo, salida)


## Por qué el botón del título no se puede usar. El panel NO reinicia la
## partida: reescribir el save desde la UI es la forma corta de perder el
## atomicidad que lo protege, así que de eso se encarga el guardado.
func _motivo_bloqueo() -> String:
	if not FileAccess.file_exists(SaveSystem.RUTA):
		return "Todavía no hay partida que cerrar."
	return "Llegá al nivel %d para cerrar el ciclo." % NuevoJuegoPlus.tope_nivel()
