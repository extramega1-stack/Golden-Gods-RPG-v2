class_name PantallaCarga
extends CanvasLayer
## Pantalla de carga del mundo (fase 20, P0-3).
##
## Antes el arranque congelaba el juego varios segundos (terreno 36 chunks
## + 9 ciudades construidos en el primer frame). Ahora el mundo se
## construye por partes y esta pantalla cubre la espera con barra y texto.
## Solo LEE progreso (0..1); la demo la crea, la actualiza y la libera.
##
## Uso:
##   var carga := PantallaCarga.new()
##   add_child(carga)
##   carga.fijar_progreso(0.5, "Levantando Moon Town…")
##   ...
##   carga.queue_free()

var _fondo: ColorRect = null
var _barra: ProgressBar = null
var _texto: Label = null
var _titulo: Label = null


func _init() -> void:
	layer = UiLayers.CARGA
	_construir()


func _construir() -> void:
	_fondo = ColorRect.new()
	_fondo.color = Color(0.01, 0.01, 0.02, 1.0)
	_fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fondo)
	_titulo = Label.new()
	_titulo.text = "GOLDEN GODS"
	_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titulo.add_theme_font_size_override("font_size", 42)
	_titulo.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	_titulo.set_anchors_preset(Control.PRESET_CENTER)
	_titulo.position = Vector2(-200.0, -90.0)
	_titulo.size = Vector2(400.0, 60.0)
	add_child(_titulo)
	_barra = ProgressBar.new()
	_barra.min_value = 0.0
	_barra.max_value = 1.0
	_barra.value = 0.0
	_barra.show_percentage = false
	_barra.set_anchors_preset(Control.PRESET_CENTER)
	_barra.position = Vector2(-200.0, -10.0)
	_barra.size = Vector2(400.0, 22.0)
	add_child(_barra)
	_texto = Label.new()
	_texto.text = "Cargando…"
	_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_texto.add_theme_font_size_override("font_size", 14)
	_texto.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	_texto.set_anchors_preset(Control.PRESET_CENTER)
	_texto.position = Vector2(-200.0, 22.0)
	_texto.size = Vector2(400.0, 24.0)
	add_child(_texto)


## Fija el progreso (0..1, con clamp) y el texto de fase.
func fijar_progreso(fraccion: float, texto: String = "") -> void:
	if _barra != null:
		_barra.value = clampf(fraccion, 0.0, 1.0)
	if _texto != null and texto != "":
		_texto.text = texto


## Progreso actual (0..1). Solo lectura (tests).
func progreso_actual() -> float:
	if _barra == null:
		return 0.0
	return float(_barra.value)
