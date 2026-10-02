class_name PanelFinal
extends CanvasLayer
## Fase 72: la pantalla de FIN. La que nunca existió.
##
## POR QUÉ ES UN `CanvasLayer` Y NO UN PANEL MÁS: el final es un MODAL CRÍTICO
## (rango 90-99 de `ui_layers.gd`), como la pausa o el título. Va en la capa
## 92, y los dos finales usan la MISMA capa a propósito: son la misma pantalla
## con distinto texto, y hacer dos pantallas distintas para "Sello" y "Espada"
## es duplicar el layout y el fondo Oscurecido para cambiar cuatro `Label`.
##
## LA UI NO DECIDE NADA (§9, §9.5): se suscribe a `ResultadoPartida.victoria` y
## DIBUJA lo que le llega. No mira el `QuestLog`, no busca el final, no calcula
## si ganó. Si el sistema no está conectado, esta pantalla no aparece — y por
## eso el test del final mira la SEÑAL, no el panel.
##
## EL TEXTO VIENE DEL DATO. `data/derrota.json` → `victoria.finales.<senda>`.
## El tono es el del canon (MASTER_SPEC §3, punto 4): el Sello es la renuncia y
## se lleva la magia; la Espada es ganar la guerra y perder la paz. Nada de eso
## está escrito acá, así que se puede retocar el final sin tocar una línea de
## código.
##
## Los dos botones, y por qué son los dos que hay:
## - "Volver al título": es la salida de una partida terminada. Se guarda
##   PRIMERO (§7.10: perder la partida por tocar el botón es la forma más
##   rápida de que un jugador borre su progreso sin querer).
## - "Continuar en NG+": el NG+ ya existe (`pantalla_titulo.gd` y
##   `SaveSystem.reiniciar_para_ngplus`) y el final es justo el momento en que
##   tiene sentido ofrecerlo. Sale DESHABILITADO con el motivo escrito abajo
##   cuando el NG+ todavía no está disponible (hace falta nivel 70), en vez de
##   dejar un botón que no hace nada: un botón muerto en la pantalla final es
##   la peor forma de cerrar el juego.

const CAPA: int = UiLayers.PANEL_FINAL

## §9.1
var system_id: StringName = &"panel_final"

## Cuántas veces se abrió. No es decorativo: el test final mira que la pantalla
## se abra DE VERDAD cuando llega la señal, y no que exista.
var _aperturas: int = 0

var _resultado: ResultadoPartida = null
var _titulo: Label = null
var _subtitulo: Label = null
var _cuerpo: Label = null
var _cierre: Label = null
var _epigrafe: Label = null
var _b_ngplus: Button = null
var _motivo_ngplus: Label = null
var _senda_actual: String = ""
var _abierto: bool = false


func _init() -> void:
	layer = CAPA
	# ALWAYS: el final pausa el árbol, y un nodo pausado no recibe input.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir()
	visible = false


## Se suscribe al sistema. Lo llama el demo al terminar de construir el mundo.
## Recibe la victoria que ya hubiera en el guardado, así que continuar una
## partida ganada vuelve a mostrar el final en vez de perderlo.
func vigilar(resultado: ResultadoPartida) -> void:
	if resultado == null:
		return
	_resultado = resultado
	if not _resultado.victoria.is_connected(_al_victoria):
		_resultado.victoria.connect(_al_victoria)
	# Si el guardado ya traía un final, la señal ya pasó por esta instancia del
	# sistema antes de que el panel existiera. Sin esto, "cargar una partida
	# ganada" no mostraría nada y el test de persistencia del resultado
	# fallaría justo en el caso que importa.
	if _resultado.hay_victoria():
		_al_victoria(_resultado.senda)


func _construir() -> void:
	# Un oscurecido por detrás: el final es el ÚLTIMO fotograma de la partida y
	# tiene que leerse como eso, no como un cartel pegado sobre el juego vivo.
	var velo := ColorRect.new()
	velo.name = "Oscurecido"
	velo.color = Color(0, 0, 0, 0.82)
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: es lo que hace que un clic detrás no llegue al mundo pausado.
	velo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(velo)

	var fondo := PanelContainer.new()
	fondo.name = "Fondo"
	fondo.set_anchors_preset(Control.PRESET_CENTER)
	# Un final es más ancho que alto: es texto de leer, no una ficha.
	AjustaUI.centrar(fondo, 0.56, 0.72)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	fondo.add_theme_stylebox_override("panel", _estilo_fondo())
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.add_theme_constant_override("margin_left", 34)
	margen.add_theme_constant_override("margin_right", 34)
	margen.add_theme_constant_override("margin_top", 26)
	margen.add_theme_constant_override("margin_bottom", 22)
	fondo.add_child(margen)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 12)
	margen.add_child(caja)

	_titulo = _nueva_etiqueta(46, Color(0.95, 0.78, 0.32))
	caja.add_child(_titulo)

	_subtitulo = _nueva_etiqueta(17, Color(0.68, 0.60, 0.42))
	caja.add_child(_subtitulo)

	var linea := HSeparator.new()
	caja.add_child(linea)

	_cuerpo = _nueva_etiqueta(16, Color(0.88, 0.85, 0.78))
	_cuerpo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cuerpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(_cuerpo)

	_cierre = _nueva_etiqueta(16, Color(0.82, 0.78, 0.68))
	_cierre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(_cierre)

	_epigrafe = _nueva_etiqueta(15, Color(0.72, 0.64, 0.40))
	_epigrafe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(_epigrafe)

	var botones := HBoxContainer.new()
	botones.add_theme_constant_override("separation", 14)
	botones.alignment = BoxContainer.ALIGNMENT_CENTER
	caja.add_child(botones)

	var b_titulo: Button = _nuevo_boton("Volver al título")
	b_titulo.pressed.connect(_al_titulo)
	botones.add_child(b_titulo)

	_b_ngplus = _nuevo_boton("Continuar en NG+")
	_b_ngplus.pressed.connect(_al_ngplus)
	botones.add_child(_b_ngplus)

	# El motivo por el que el NG+ no está disponible, SI no lo está. Vive
	# siempre en el árbol (nunca se crea en caliente) y cambia de texto.
	_motivo_ngplus = _nueva_etiqueta(14, Color(0.62, 0.58, 0.50))
	_motivo_ngplus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_motivo_ngplus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(_motivo_ngplus)


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
	b.custom_minimum_size = Vector2(220, 46)
	b.add_theme_color_override("font_color", Color(0.93, 0.88, 0.74))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.90, 0.55))
	b.add_theme_color_override("font_disabled_color", Color(0.42, 0.40, 0.38))
	b.add_theme_stylebox_override("normal", _estilo_boton(
		Color(0.10, 0.10, 0.14, 0.92), Color(0.55, 0.42, 0.18)))
	b.add_theme_stylebox_override("hover", _estilo_boton(
		Color(0.16, 0.14, 0.12, 0.95), Color(0.95, 0.76, 0.32)))
	b.add_theme_stylebox_override("pressed", _estilo_boton(
		Color(0.22, 0.17, 0.10, 0.97), Color(0.95, 0.76, 0.32)))
	b.add_theme_stylebox_override("disabled", _estilo_boton(
		Color(0.07, 0.07, 0.09, 0.90), Color(0.26, 0.24, 0.22)))
	return b


func _estilo_fondo() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.10, 0.97)
	sb.border_color = Color(0.75, 0.62, 0.30)
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


## Cuántas veces se mostró. Para el test: un panel que existe pero que nunca
## se abre no es una pantalla de final.
func aperturas() -> int:
	return _aperturas


## La senda del final que se está mostrando, o "" si está cerrado.
func senda_mostrada() -> String:
	return _senda_actual


## Abre el final de una senda. La llama la SEÑAL, no el juego.
func _al_victoria(senda: String) -> void:
	var texto: Dictionary = ResultadoPartida.final_de(senda)
	if texto.is_empty():
		# Sin dato para esta senda, no hay pantalla: es peor mostrar un final
		# en blanco que no mostrar nada, y el aviso deja la causa escrita.
		push_warning("[PanelFinal] sin final en el dato para la senda '%s'" % senda)
		return
	_senda_actual = senda
	_titulo.text = str(texto.get("titulo", "FIN"))
	_subtitulo.text = str(texto.get("subtitulo", ""))
	_cuerpo.text = str(texto.get("cuerpo", ""))
	_cierre.text = str(texto.get("cierre", ""))
	_epigrafe.text = str(texto.get("epigrafe", ""))
	_refrescar_ngplus()
	_abierto = true
	_aperturas += 1
	visible = true
	_sincronizar_pausa()


## Cierra el final. No lo llama nadie por ahora (el final es terminal: sus dos
## botones son "al título" y "NG+"), pero existe para que el test pueda cerrar
## la pantalla y devolver el árbol, y para el caso de que mañana el final tenga
## un "seguir mirando el mundo".
func cerrar() -> void:
	if not _abierto:
		return
	_abierto = false
	_senda_actual = ""
	visible = false
	_sincronizar_pausa()


## ¿El NG+ está disponible? Lo decide el GUARDADO, no este panel: el botón se
## habilita o no con la misma respuesta que el `SaveSystem` le da a la pantalla
## de título, para que los dos offerentes no puedan discrepar.
func ngplus_disponible() -> bool:
	return SaveSystem.puede_nuevo_game_plus()


## El motivo por el que el NG+ no está disponible, o "" si lo está. Vive en el
## dato, no en el texto del botón: el botón dice QUÉ hace y el rótulo explica
## POR QUÉ no se puede.
func motivo_ngplus() -> String:
	if ngplus_disponible():
		return ""
	return "El NG+ se abre en el nivel %d, el tope del mundo. Llegaste al %d." % [
		NuevoJuegoPlus.tope_nivel(), SaveSystem.nivel_guardado()]


func _refrescar_ngplus() -> void:
	var disponible: bool = ngplus_disponible()
	_b_ngplus.disabled = not disponible
	_b_ngplus.text = "Continuar en NG+" if disponible else "NG+ todavía no"
	_motivo_ngplus.text = motivo_ngplus()


func _sincronizar_pausa() -> void:
	# El final pausa el árbol. Si el `MenuPausa` está abierto lo deja así (es
	# él el dueño del flag), y si no lo está, lo pausa y lo reanuda al cerrar.
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

func _guardar() -> bool:
	if Systems.actual == null:
		return false
	var sv: SaveSystem = Systems.actual.obtener(&"save_system") as SaveSystem
	if sv == null:
		return false
	return sv.guardar()


func _al_titulo() -> void:
	# Guardar SIEMPRE antes de salir de la partida. Preguntar "¿guardar?" en la
	# pantalla final es la forma más rápida de que alguien salga sin guardar.
	_guardar()
	cerrar()
	Transicion.ir_a(Escenas.TITULO)


func _al_ngplus() -> void:
	if not ngplus_disponible():
		# El botón está deshabilitado; esto es la red por si alguien lo
		# dispara con el teclado o el ratón en el mismo frame en que se
		# deshabilitó.
		_refrescar_ngplus()
		return
	_guardar()
	# El NG+ real lo decide el `SaveSystem` (escribe por el mismo camino atómico
	# que un guardado normal) y después hay que pedir "continuar" para que el
	# mundo arranque en la vuelta nueva. Es el mismo contrato que usa la
	# pantalla de título; el final no reimplementa el reinicio.
	if not SaveSystem.reiniciar_para_ngplus():
		_refrescar_ngplus()
		return
	DatosSesion.pedir_continuar()
	cerrar()
	Transicion.ir_a(Escenas.JUEGO)
