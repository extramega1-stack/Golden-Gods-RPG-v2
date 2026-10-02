class_name PanelTutorial
extends CanvasLayer
## FASE 69 — el "hacé esto ahora" del tutorial, siempre a la vista.
##
## POR QUÉ ESTO EXISTE: el tutorial de la fase 39 era una lista de textos por
## toast de 2 segundos. Si el jugador miraba para otro lado, la instrucción
## desaparecía para siempre: no había forma de volver a leerla, ni de saltar
## el tutorial, ni de saber dónde está el objetivo. Este panel es la
## respuesta a las tres cosas: la instrucción PERMANECE, tiene botón de
## saltar, y tiene botón de ir y una pestaña para reabrirlo.
##
## §9.5 — LA REGLA QUE ESTE ARCHIVO RESPETA AL PIE DE LA LETRA: la UI NO
## LEE NADA POR FRAME. No hay `_process` aquí. Todo llega por señales de
## `Tutorial`:
##   - `paso_cambiado`   → cambia el texto, el contador y el botón Ir.
##   - `distancia_actualizada` → cambia los metros. `Tutorial` la emite SOLO
##     cuando el metro entero cambia (el mismo umbral `TOQUE_MIN` que
##     `Vitals.vital_cambiado` de la fase 63), así que en una plaza quieta
##     no llega ni una.
##   - `completado` / `saltado` / `reanudado` → el estado final.
## Un panel que "está conectado" y que en la práctica no se mueve cuando el
## dato se mueve es el bug que se acaba de encontrar en otra UI del
## proyecto: `tests/test_tutorial_primeros_minutos.gd` muerde el dato y
## comprueba que la etiqueta se mueva.
##
## CAPA: 19. `UiLayers` (scripts/core/) declara el rango 10-19 para el HUD
## persistente y 19 es el único libre del rango; el tutorial es HUD
## persistente (acompaña toda la partida), no un panel de sistema. Cuando
## `UiLayers` sea editable, esta constante se sube allá y esta pasa a ser
## `UiLayers.TUTORIAL`.
##
## Posición: abajo a la izquierda de la pantalla, justo sobre la barra de
## skills. Arriba a la izquierda vive el bloque de estado (H, 12 px) y los
## vitales (96 px); abajo a la derecha el minimapa y el feed de avisos; la
## brújula y la barra de skills, en el centro. La esquina inferior izquierda
## estaba vacía.

const CAPA: int = 19
## §9.1: sin esto `Systems.registrar()` RECHAZA el sistema con un warning y no
## lo registra, en silencio para quien mira. Pasó al cablearlo en la escena: el
## panel se creaba y se agregaba, y no aparecía en el contenedor.
var system_id: StringName = &"panel_tutorial"
const MARGEN: float = 16.0
## Alto reservado para la barra de acciones (UiLayers.ZONA_INFERIOR_RESERVADA).
const RESERVADO_INFERIOR: int = 100
const ANCHO: float = 330.0

var _pestana: Button = null
var _caja: PanelContainer = null
var _indice: Label = null
var _texto: Label = null
var _detalle: Label = null
var _distancia: Label = null
var _btn_ir: Button = null
var _btn_saltar: Button = null

var _tutorial: Tutorial = null
## true mientras el jugador lo dejó abierto a mano (aunque el tutorial esté
## terminado): es el "volver a abrir" del enunciado.
var _abierto_manual: bool = false
## El jugador cerró la caja con ESC y todavía no pidió volver a abrirla.
##
## SIN ESTE FLAG la caja era imposible de cerrar, y no por un bug de evento:
## cada señal del tutorial (`paso_cambiado`, `completado`, `saltado`) llama a
## `_abrir()`, así que la caja se cerraba y se reabría en el mismo frame.
## Medido por la partida completa (`tools/jugar.sh`, P11): el paso «el ESC
## cierra lo que hay abierto» se quedaba 9001 frames (150 s de partida) sin
## terminar, y el resumen lo atribuía a que "el ESC no cerraba el tutorial".
##
## La regla: **cerrar a mano manda**. Una señal SÍ puede abrir la caja —el
## jugador no pidió un tutorial y le sirve saber qué hacer—, pero no puede
## reabrir lo que él acaba de cerrar. Se levanta el flag cuando el jugador
## vuelve a abrirla (la pestaña, o `reabrir()` del tutorial).
var _cerrado_por_el_jugador: bool = false


func _ready() -> void:
	layer = CAPA
	_construir()
	# Lección 11: la caja nace oculta. La PESTAÑA sí se ve (es el acceso al
	# tutorial), pero sin caja no hay nada que tapar.
	_caja.visible = false


func _construir() -> void:
	_pestana = Button.new()
	_pestana.name = "PestanaTutorial"
	_pestana.text = "T"
	_pestana.tooltip_text = "Tutorial: qué hacer ahora"
	_pestana.focus_mode = Control.FOCUS_NONE
	_pestana.custom_minimum_size = Vector2(30.0, 30.0)
	_pestana.anchor_left = 0.0
	_pestana.anchor_right = 0.0
	_pestana.anchor_top = 1.0
	_pestana.anchor_bottom = 1.0
	_pestana.offset_left = MARGEN
	_pestana.offset_right = MARGEN + 30.0
	_pestana.offset_top = -(float(RESERVADO_INFERIOR) + 40.0)
	_pestana.offset_bottom = -(float(RESERVADO_INFERIOR) + 10.0)
	_pestana.add_theme_font_size_override("font_size", 16)
	_pestana.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	_pestana.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.70))
	_pestana.add_theme_stylebox_override("normal", _estilo(Color(0.10, 0.09, 0.07, 0.92)))
	_pestana.add_theme_stylebox_override("hover", _estilo(Color(0.18, 0.15, 0.10, 0.96)))
	_pestana.add_theme_stylebox_override("pressed", _estilo(Color(0.24, 0.19, 0.11, 0.98)))
	_pestana.pressed.connect(_al_pulsar_pestana)
	add_child(_pestana)

	_caja = PanelContainer.new()
	_caja.name = "Caja"
	_caja.anchor_left = 0.0
	_caja.anchor_right = 0.0
	_caja.anchor_top = 1.0
	_caja.anchor_bottom = 1.0
	_caja.offset_left = MARGEN
	_caja.offset_right = MARGEN + ANCHO
	_caja.offset_top = -(float(RESERVADO_INFERIOR) + 46.0)
	_caja.offset_bottom = -8.0
	_caja.mouse_filter = Control.MOUSE_FILTER_STOP
	_caja.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caja.add_theme_stylebox_override("panel", _estilo(Color(0.06, 0.05, 0.04, 0.94), 1))
	add_child(_caja)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caja.add_child(col)

	var cabecera := HBoxContainer.new()
	cabecera.add_theme_constant_override("separation", 6)
	cabecera.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cabecera)

	_indice = Label.new()
	_indice.text = "1/6"
	_indice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indice.add_theme_color_override("font_color", Color(0.75, 0.68, 0.45))
	_indice.add_theme_font_size_override("font_size", 13)
	cabecera.add_child(_indice)

	_texto = Label.new()
	_texto.text = ""
	_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_texto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_texto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texto.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	_texto.add_theme_font_size_override("font_size", 16)
	cabecera.add_child(_texto)

	_detalle = Label.new()
	_detalle.text = ""
	_detalle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detalle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detalle.add_theme_color_override("font_color", Color(0.82, 0.80, 0.74))
	_detalle.add_theme_font_size_override("font_size", 13)
	col.add_child(_detalle)

	var pie := HBoxContainer.new()
	pie.add_theme_constant_override("separation", 6)
	pie.alignment = BoxContainer.ALIGNMENT_END
	pie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pie)

	_distancia = Label.new()
	_distancia.text = ""
	_distancia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_distancia.add_theme_color_override("font_color", Color(0.7, 0.86, 1.0))
	_distancia.add_theme_font_size_override("font_size", 13)
	_distancia.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_distancia.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pie.add_child(_distancia)

	_btn_ir = _boton("Ir", "Caminar hasta el objetivo marcado")
	_btn_ir.pressed.connect(_al_pulsar_ir)
	pie.add_child(_btn_ir)

	_btn_saltar = _boton("Saltar", "Terminar el tutorial y no volver a mostrarlo")
	_btn_saltar.pressed.connect(_al_pulsar_saltar)
	pie.add_child(_btn_saltar)


func _boton(texto: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = texto
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	b.add_theme_stylebox_override("normal", _estilo(Color(0.13, 0.11, 0.07, 0.95), 1))
	b.add_theme_stylebox_override("hover", _estilo(Color(0.22, 0.18, 0.10, 0.98), 1))
	b.add_theme_stylebox_override("pressed", _estilo(Color(0.30, 0.24, 0.12, 1.0), 1))
	b.add_theme_stylebox_override("disabled", _estilo(Color(0.10, 0.10, 0.10, 0.7), 1))
	return b


func _estilo(fondo: Color, grosor: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fondo
	sb.border_color = Color(0.85, 0.68, 0.30)
	sb.set_border_width_all(grosor)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


# --- suscripción (y SOLO suscripción) ---------------------------------

## Se engancha al tutorial. Idempotente: re-llamarlo con el mismo objeto no
## duplica conexiones.
func conectar(t: Tutorial) -> void:
	if _tutorial != null and is_instance_valid(_tutorial):
		_desconectar(_tutorial)
	_tutorial = t
	if _tutorial == null:
		return
	_tutorial.paso_cambiado.connect(_al_paso)
	_tutorial.distancia_actualizada.connect(_al_distancia)
	_tutorial.completado.connect(_al_completado)
	_tutorial.saltado.connect(_al_saltado)
	_tutorial.reanudado.connect(_al_reanudado)
	_tutorial.destacado.connect(_al_destacado)
	_tutorial.abierto.connect(_abrir)


func _desconectar(t: Tutorial) -> void:
	if t.paso_cambiado.is_connected(_al_paso):
		t.paso_cambiado.disconnect(_al_paso)
	if t.distancia_actualizada.is_connected(_al_distancia):
		t.distancia_actualizada.disconnect(_al_distancia)
	if t.completado.is_connected(_al_completado):
		t.completado.disconnect(_al_completado)
	if t.saltado.is_connected(_al_saltado):
		t.saltado.disconnect(_al_saltado)
	if t.reanudado.is_connected(_al_reanudado):
		t.reanudado.disconnect(_al_reanudado)
	if t.destacado.is_connected(_al_destacado):
		t.destacado.disconnect(_al_destacado)
	if t.abierto.is_connected(_abrir):
		t.abierto.disconnect(_abrir)


# --- la señal mueve la UI (y solo la señal) ---------------------------

func _al_paso(indice: int, paso: Dictionary) -> void:
	_indice.text = "%d/%d" % [indice + 1, maxi(indice + 1, Tutorial.PASOS.size())]
	_texto.text = str(paso.get("texto", ""))
	_detalle.text = str(paso.get("detalle", ""))
	_distancia.text = ""
	_btn_saltar.visible = true
	_btn_ir.visible = str(paso.get("objetivo", {}).get("tipo", "ninguno")) != "ninguno"
	_abrir()


func _al_distancia(metros: int) -> void:
	# La UI se mueve porque el DATO se movió: no hay ningún _process que la
	# empujara. Un metro de diferencia ya es información (el jugador sabe si
	# tiene que caminar o cruzar la ciudad).
	if metros < 0:
		_distancia.text = ""
		return
	_distancia.text = "· %d m" % metros


func _al_completado() -> void:
	_indice.text = "Listo"
	_texto.text = TutorialPasos.texto_cierre()
	_detalle.text = TutorialPasos.detalle_cierre()
	_distancia.text = ""
	_btn_ir.visible = false
	_btn_saltar.visible = false
	_abrir()


func _al_saltado() -> void:
	_indice.text = "Saltado"
	_texto.text = "Tutorial saltado."
	_detalle.text = "La pestaña T lo reabre cuando lo necesites."
	_distancia.text = ""
	_btn_ir.visible = false
	_btn_saltar.visible = false
	_abrir()


func _al_reanudado() -> void:
	_abierto_manual = true
	# `reanudado` ES el gesto de "vuelve a mostrarse el tutorial": si el
	# jugador lo pidió, el cierre por ESC deja de mandar.
	_cerrado_por_el_jugador = false
	_abrir()


func _al_destacado(texto: String) -> void:
	_detalle.text = texto


## Este panel NO entra en `PilaUI`: es HUD persistente, no una ventana
## modal. Si se apuntara, el ESC de la mochila lo cerraría a él en vez de a
## la mochila y los dos|· se pelearían.
## ESTE PANEL NO ENTRA EN `PilaUI`, y es a proposito: es HUD persistente, no
## una ventana modal. Si se apuntara, el ESC de la mochila lo cerraria a el en
## vez de a la mochila, y los dos se pelearian.
##
## PERO ESO DEJABA UN AGUJERO REAL, y lo cazó la partida completa
## (`tools/jugar.sh`, P11): el tutorial abre una CAJA visible y el ESC no la
## cerraba. La unica salida era la pestana de 30 px. Un modal sin salida no es
## un HUD persistente: es una trampa.
##
## EL ESC, ADEMÁS, NO ES DE ESTA CAJA: es del menú de pausa, que es global.
## La caja tiene TRES salidas propias —la tecla 0, la pestaña y "Saltar"—, así
## que no necesita el ESC para no ser una trampa. Ver el comentario del
## `_unhandled_input` de abajo: quedarse con el ESC rompía el menú de pausa.
func _unhandled_input(evento: InputEvent) -> void:
	# La tecla del tutorial. `abrir_tutorial` estaba declarada en el Input Map
	# (project.godot) y NADIE la escuchaba: la tecla 0 no abría nada. Es el
	# mismo bug de siempre del repo — un atajo declarado, un panel que lo
	# espera, y el puente sin construir — y lo cazó la partida completa
	# (`tools/jugar.sh`, P11), que la pedía como los otros nueve paneles.
	#
	# Va PRIMERO y sin mirar si la caja está visible: la tecla tiene que
	# alternar, como la pestaña.
	if evento.is_action_pressed("abrir_tutorial"):
		get_viewport().set_input_as_handled()
		_al_pulsar_pestana()
		return
	if not _caja.visible:
		return
	if not evento.is_action_pressed("cancelar_seleccion"):
		return
	# `abierta()` devuelve un INT (cuantos paneles hay), no un bool.
	if PilaUI.abierta() > 0:
		return
	# EL ESC ES DEL MENÚ DE PAUSA, Y ESTA CAJA NO LO TOCA.
	#
	# No es una preferencia: es un bug medido. `PanelTutorial` se cuelga antes
	# en el orden del árbol, así que su `set_input_as_handled()` se quedaba con
	# el ESC y el `MenuPausa._unhandled_input` NUNCA lo veía. Con un ESC solo,
	# en una partida recién creada, el primero no abría la pausa y el segundo
	# sí: el menú de pausa era inalcanzable con una sola tecla.
	#
	# El menú de pausa es modal y global, tiene que funcionar SIEMPRE. Esta caja
	# es un HUD con TRES salidas propias —la tecla 0, la pestaña T y el botón
	# "Saltar"—, así que no le hace falta el ESC para no ser una trampa. Cederlo
	# es lo correcto, y además deja de haber dos Dueños de la misma tecla.
	return


func _abrir() -> void:
	# Una señal puede abrir la caja, pero no reabrir la que el jugador acaba de
	# cerrar con ESC. Ver `_cerrado_por_el_jugador`.
	if _cerrado_por_el_jugador:
		return
	_caja.visible = true


func _cerrar_caja() -> void:
	_caja.visible = false


## El jugador la cerró a propósito: hasta que vuelva a pedirla, ninguna
## señal la reabre.
func _cerrar_por_esc() -> void:
	_cerrado_por_el_jugador = true
	_caja.visible = false


# --- botones ----------------------------------------------------------

## La pestaña alterna la caja. Es el "volver a abrir" del enunciado: el
## jugador que ya sabe no recibe nada más que un botón de 30 px, y puede
## volver a abrir el tutorial cuando quiera.
func _al_pulsar_pestana() -> void:
	if _caja.visible:
		_cerrar_por_esc()
	else:
		_abierto_manual = true
		# Volver a pedir la caja es el gesto que levanta el cierre: el jugador
		# la quiere de vuelta, así que las señales vuelven a poder abrirla.
		_cerrado_por_el_jugador = false
		if _tutorial != null and is_instance_valid(_tutorial):
			_tutorial.mostrar_resumen()
		_abrir()


func _al_pulsar_ir() -> void:
	if _tutorial == null or not is_instance_valid(_tutorial):
		return
	_tutorial.ir_al_objetivo()
	_al_destacado("Caminando al objetivo…")


func _al_pulsar_saltar() -> void:
	if _tutorial == null or not is_instance_valid(_tutorial):
		return
	_tutorial.saltar()


## ¿Se ve la caja del objetivo? (tests).
func esta_visible() -> bool:
	return _caja != null and _caja.visible


## ¿Se ve la pestaña de reapertura? (tests).
func pestana_visible() -> bool:
	return _pestana != null and _pestana.visible


## Texto del objetivo que se está mostrando (tests).
func texto_actual() -> String:
	return "" if _texto == null else _texto.text


## Texto del contador "3/6" (tests).
func indice_actual() -> String:
	return "" if _indice == null else _indice.text


## Metros que se están mostrando (tests).
func distancia_actual() -> String:
	return "" if _distancia == null else _distancia.text


## Detalle que se está mostrando (tests).
func detalle_actual() -> String:
	return "" if _detalle == null else _detalle.text
