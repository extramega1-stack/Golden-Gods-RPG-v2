class_name PanelDerrota
extends CanvasLayer
## Fase 72: la pantalla de DERROTA. Antes de esta fase, morir no era morir:
## `RespawnHeros` te devolvía a la plaza con la vida llena, sin perder nada, y
## no pasaba nada visible. No había forma de perder porque no había pantalla de
## derrota.
##
## POR QUÉ NO ES UN CARTEL: la muerte es el momento en que el jugador necesita
## saber dos cosas, y las dos están escritas: cuánto costó, y a dónde vuelve. Un
## "Has muerto" en una esquina con un botón de reintento no dice ninguna de las
## dos, y el jugador deduce que no pasó nada (que era exactamente lo que pasaba).
##
## LA UI PIDE, EL SISTEMA COBRA (§9). El botón llama a
## `ResultadoPartida.revivir()`, que es el que devuelve el control al respawn y
## teletransporta al último refugio. Este panel no toca el oro, ni el XP, ni la
## posición del jugador, y no escribe un stat. Muestra lo que le llega por la
## señal `muerte_registrada` y nada más.
##
## Capa 93, la de al lado del final (92). Los dos son modales críticos: por
## encima de todos los paneles de sistema y por debajo de la transición (98).

const CAPA: int = UiLayers.PANEL_DERROTA

## §9.1
var system_id: StringName = &"panel_derrota"

## Cuántas veces se mostró. El test lo mira: un panel que existe pero que nunca
## se abre no es una pantalla de derrota.
var _aperturas: int = 0

var _resultado: ResultadoPartida = null
var _titulo: Label = null
var _subtitulo: Label = null
var _detalle: Label = null
var _aviso: Label = null
var _abierto: bool = false


func _init() -> void:
	layer = CAPA
	# ALWAYS: la derrota pausa el árbol y un nodo pausado no recibe input.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir()
	visible = false


## Se suscribe al sistema. Lo llama el demo al terminar de construir el mundo.
func vigilar(resultado: ResultadoPartida) -> void:
	if resultado == null:
		return
	_resultado = resultado
	if not _resultado.muerte_registrada.is_connected(_al_morir):
		_resultado.muerte_registrada.connect(_al_morir)
	if not _resultado.revivido.is_connected(_al_revivido):
		_resultado.revivido.connect(_al_revivido)


func _construir() -> void:
	# Más claro que el del final, y no por capricho: el fondo es un velo sobre
	# una escena de acción y el jugador tiene que leer esto en un segundo.
	var velo := ColorRect.new()
	velo.name = "Oscurecido"
	velo.color = Color(0.10, 0.0, 0.0, 0.72)
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	velo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(velo)

	var fondo := PanelContainer.new()
	fondo.name = "Fondo"
	fondo.set_anchors_preset(Control.PRESET_CENTER)
	AjustaUI.centrar(fondo, 0.34, 0.44)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	fondo.add_theme_stylebox_override("panel", _estilo_fondo())
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.add_theme_constant_override("margin_left", 24)
	margen.add_theme_constant_override("margin_right", 24)
	margen.add_theme_constant_override("margin_top", 18)
	margen.add_theme_constant_override("margin_bottom", 16)
	fondo.add_child(margen)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 10)
	margen.add_child(caja)

	_titulo = _nueva_etiqueta(38, Color(0.86, 0.22, 0.20))
	_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(_titulo)

	_subtitulo = _nueva_etiqueta(16, Color(0.80, 0.72, 0.60))
	_subtitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(_subtitulo)

	_detalle = _nueva_etiqueta(16, Color(0.90, 0.84, 0.70))
	_detalle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detalle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(_detalle)

	_aviso = _nueva_etiqueta(14, Color(0.66, 0.60, 0.50))
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(_aviso)

	var botones := HBoxContainer.new()
	botones.add_theme_constant_override("separation", 12)
	botones.alignment = BoxContainer.ALIGNMENT_CENTER
	caja.add_child(botones)

	var b_revivir: Button = _nuevo_boton("Revivir en el refugio")
	b_revivir.pressed.connect(_al_revivir)
	botones.add_child(b_revivir)

	var b_titulo: Button = _nuevo_boton("Volver al título")
	b_titulo.pressed.connect(_al_titulo)
	botones.add_child(b_titulo)


func _nueva_etiqueta(tam: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _nuevo_boton(texto: String) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(210, 44)
	b.add_theme_color_override("font_color", Color(0.93, 0.88, 0.74))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.90, 0.55))
	b.add_theme_stylebox_override("normal", _estilo_boton(
		Color(0.10, 0.10, 0.14, 0.92), Color(0.55, 0.42, 0.18)))
	b.add_theme_stylebox_override("hover", _estilo_boton(
		Color(0.16, 0.14, 0.12, 0.95), Color(0.95, 0.76, 0.32)))
	b.add_theme_stylebox_override("pressed", _estilo_boton(
		Color(0.22, 0.17, 0.10, 0.97), Color(0.95, 0.76, 0.32)))
	return b


func _estilo_fondo() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.07, 0.97)
	sb.border_color = Color(0.55, 0.20, 0.18)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 0.0
	sb.content_margin_right = 0.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	return sb


func _estilo_boton(fondo: Color, borde: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fondo
	sb.border_color = borde
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	return sb


# --- apertura --------------------------------------------------------------

func esta_abierto() -> bool:
	return _abierto


func aperturas() -> int:
	return _aperturas


## Abre la pantalla con el coste que el sistema ya cobró.
func _al_morir(coste: Dictionary) -> void:
	var oro: int = int(coste.get("oro", 0))
	var xp: int = int(coste.get("xp", 0))
	_titulo.text = "HAS CAÍDO"
	_subtitulo.text = "Liberty se olvida de los que mueren fuera de sus murallas."
	_detalle.text = _linea_de_coste(oro, xp)
	_aviso.text = "El último refugio sigue en pie. Te espera."
	_abierto = true
	_aperturas += 1
	visible = true
	_sincronizar_pausa()


## La línea de lo que costó. Las dos mitades del texto salen de la señal, no
## de un cálculo propio: si el dato de `data/derrota.json` cambia, lo que se
## lee acá cambia con él sin que nadie toque este archivo.
func _linea_de_coste(oro: int, xp: int) -> String:
	var partes: Array[String] = []
	if oro > 0:
		partes.append("-%d de oro" % oro)
	if xp > 0:
		partes.append("-%d de XP del nivel" % xp)
	if partes.is_empty():
		return "No perdiste nada. Todavía."
	return "Perdiste " + " y ".join(partes) + "."


func _al_revivido(_coste: Dictionary) -> void:
	cerrar()


func cerrar() -> void:
	if not _abierto:
		return
	_abierto = false
	visible = false
	_sincronizar_pausa()


func _sincronizar_pausa() -> void:
	# Igual que el final: si el `MenuPausa` es el dueño del flag de pausa, no
	# se lo pisa. La derrota pausa porque el héroe está muerto y `Entity.die()`
	# le apagó el procesado: sin esto, el mundo seguiría corriendo solo detrás
	# de una pantalla de derrota.
	var pausa: MenuPausa = _sistema_pausa()
	if _abierto:
		if pausa == null or not pausa.esta_abierto():
			get_tree().paused = true
		return
	if pausa == null or not pausa.esta_abierto():
		get_tree().paused = false


func _sistema_pausa() -> MenuPausa:
	if Systems.actual == null:
		return null
	return Systems.actual.obtener(&"menu_pausa") as MenuPausa


# --- acciones --------------------------------------------------------------

func _al_revivir() -> void:
	# La UI PIDE. El sistema cobra y revive: si se llama dos veces, la segunda
	# es no-op (`revivir()` corta con `derrota_pendiente`), así que el doble
	# clic no teletransporta dos veces ni cobra dos veces.
	if _resultado == null:
		return
	_resultado.revivir()


func _al_titulo() -> void:
	# Guardar antes de salir: el coste de la muerte YA se cobró en memoria, y
	# esto lo escribe en disco. Sin esto, "volver al título" desde la pantalla
	# de derrota devolvía al jugador su oro y su XP enteros.
	_guardar()
	cerrar()
	Transicion.ir_a(Escenas.TITULO)


func _guardar() -> bool:
	if Systems.actual == null:
		return false
	var sv: SaveSystem = Systems.actual.obtener(&"save_system") as SaveSystem
	if sv == null:
		return false
	return sv.guardar()
