class_name FeedAvisos
extends CanvasLayer
## Hotfix 62.1 / Fase 63: feed global de avisos, en la capa 16.
##
## POR QUÉ EXISTE: hasta acá el único "feed de avisos" del juego era el toast
## de `PanelMisiones`, que se cuelga de la ESCENA precisamente para sobrevivir
## a que el panel se abra y se cierre (lección de la 45.2, que ya lo declaraba
## global de nombre pero en la práctica solo lo usaba el sistema de misiones).
##
## Con las fases 54–62 sobre la mesa esto se quedó corto: media docena de
## sistemas querían avisar al jugador (Hecho desbloqueado, refugio reclamado,
## fogata prendida, falta de leña, enfermedad) y ninguno tenía por dónde.
## Sin esto, el Hotfix 62.1 se arreglaba pero NO se veía: talar un árbol
## subía `tala` y no había forma de enterarse de nada.
##
## POR QUÉ OTRA CAPLA Y NO LA 15: la 15 es el toast de misiones, entrelazado
## con su banner de "misión completada" (`PanelMisiones._construir_toast`).
## Desarmar ese ovillo es un refactor con riesgo propio y sin premio inmediato, así
## que este feed vive en la 16, que estaba libre, y los dos conviven. Cuando
## el toast de misiones se unifique, esta clase pasa a la 15.
##
## - Es un SISTEMA: se registra en `Systems` como `feed_avisos` y cualquier
##   sistema lo encuentra con `Systems.obtener(&"feed_avisos")`. Nadie se lo
##   pasa a mano.
## - UI pura: solo escribe en sus propios nodos. Quien avisa no sabe nada de
##   cómo se ve.
## - Apila hasta `MAX_VISIBLES` y se come los viejos: es un feed, no una cola
##   infinita de objetos (los objetos se liberan, no se ocultan).

## Capa propia (`UiLayers.FEED_AVISOS`). La 15 es el toast de misiones.
const CAPA: int = UiLayers.FEED_AVISOS
## Cuántos avisos se ven a la vez. Los que entran de más expulsan al más viejo.
const MAX_VISIBLES: int = 3
## Segundos que vive un aviso normal antes de empezar a irse.
const VIDA: float = 4.0
## Segundos del fundido de salida.
const FUNDIDO: float = 0.6
## Los logros (Hechos) viven más: son dos líneas y hay que leerlas.
const VIDA_LOGRO: float = 7.0
## Ancho del aviso. Los dos textos de un Hecho (título + qué hace) no entran
## en menos, y 420 es lo que ya usa la brújula.
const ANCHO: float = 420.0

const COLOR_FONDO: Color = Color(0.05, 0.05, 0.08, 0.92)
const COLOR_BORDE: Color = Color(0.75, 0.62, 0.3)
const COLOR_TITULO: Color = Color(1.0, 0.88, 0.55)
const COLOR_TEXTO: Color = Color(0.85, 0.85, 0.9)
const COLOR_LOGRO: Color = Color(1.0, 0.78, 0.30)

## Emitido cada vez que se muestra un aviso. Lo usan los tests; el juego no.
signal avisado(texto: String, es_logro: bool)

## §9.1: todo sistema declara su id para poder registrarse en `Systems`.
var system_id: StringName = &"feed_avisos"

var _caja: VBoxContainer = null
var _vivo: Array = []


func _ready() -> void:
	layer = CAPA
	_construir()
	visible = true


func _construir() -> void:
	_caja = VBoxContainer.new()
	_caja.name = "Avisos"
	# Abajo-derecha, encima del minimapa (que está en la esquina opuesta del
	# HUD). Crece hacia ARRIBA para que los avisos nuevos no empijen el layout
	# hacia abajo (lección 11: `visible = false` al arrancar; acá el feed
	# existe siempre pero nace vacío).
	_caja.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_caja.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caja.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_caja.offset_right = -24.0
	_caja.offset_bottom = -24.0
	_caja.add_theme_constant_override("separation", 6)
	_caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caja)


## Aviso normal, una línea. Para lo de rutina: cogiste algo, te falta leña,
## el árbol ya está talado.
func aviso(texto: String) -> void:
	_crear(texto, "", COLOR_TITULO, VIDA, false)


## Logro, dos líneas: título + qué cambia. Para los Hechos de la 59, que sin
## el detalle son inútiles: "Leñador" solo no dice que ahora sacás 3 troncos.
func logro(titulo: String, detalle: String) -> void:
	_crear(titulo, detalle, COLOR_LOGRO, VIDA_LOGRO, true)


func _crear(titulo: String, detalle: String, color: Color, vida: float, es_logro: bool) -> void:
	if _caja == null:
		return
	# Se come el más viejo si ya hay demasiados. Liberar, no esconder: un
	# feed que acumula nodos es una fuga (§9.5).
	while _vivo.size() >= MAX_VISIBLES:
		var viejo: Dictionary = _vivo.pop_front()
		var n: Node = viejo.get("nodo") as Node
		if n != null and is_instance_valid(n):
			n.queue_free()

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(ANCHO, 0)
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = COLOR_FONDO
	estilo.border_color = color
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(4)
	estilo.content_margin_left = 12
	estilo.content_margin_right = 12
	estilo.content_margin_top = 7
	estilo.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", estilo)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 1)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(caja)

	var lbl_t := Label.new()
	lbl_t.text = titulo
	lbl_t.add_theme_font_size_override("font_size", 15)
	lbl_t.add_theme_color_override("font_color", color)
	lbl_t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(lbl_t)

	if detalle != "":
		var lbl_d := Label.new()
		lbl_d.text = detalle
		lbl_d.add_theme_font_size_override("font_size", 12)
		lbl_d.add_theme_color_override("font_color", COLOR_TEXTO)
		lbl_d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl_d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caja.add_child(lbl_d)

	_caja.add_child(panel)
	avisado.emit(titulo, es_logro)

	# El tween vive en la entrada de la pila para poder cancelarlo si el panel
	# se libera antes de tiempo.
	var tween: Tween = create_tween()
	tween.tween_interval(vida)
	tween.tween_property(panel, "modulate:a", 0.0, FUNDIDO)
	tween.tween_callback(_reirse.bind(panel))
	_vivo.append({"nodo": panel, "tween": tween})


func _reirse(panel: Node) -> void:
	for i in _vivo.size():
		if _vivo[i].get("nodo") == panel:
			_vivo.remove_at(i)
			break
	if is_instance_valid(panel):
		panel.queue_free()


## Cuántos avisos hay en pantalla. Para los tests; el juego no lo consulta.
func visibles() -> int:
	return _vivo.size()
