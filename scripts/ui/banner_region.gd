class_name BannerRegion
extends Control
## Banner de descubrimiento de región (Fase 12).
##
## Texto discreto arriba-centro: "Has descubierto: <nombre>" + subtítulo
## (p.ej. "Nivel recomendado 1–5"). Visible ~3.5 s con fundido de entrada y
## salida. La UI solo LEE los datos que recibe en `mostrar()`: no toca stats
## ni estado del juego.
##
## REGLA DURA de overlays: arranca oculto y `mouse_filter = IGNORE` en el
## banner y en todos sus hijos, para no comerse nunca un clic del juego.

const DURACION: float = 3.5
const FUNDIDO_ENTRADA: float = 0.35
const FUNDIDO_SALIDA: float = 0.9

var _restante: float = 0.0
var _titulo: Label
var _subtitulo: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0
	_construir()


func _construir() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.02, 0.02, 0.04, 0.72)
	estilo.border_color = Color(0.85, 0.68, 0.25, 0.9)
	estilo.set_border_width_all(1)
	estilo.set_corner_radius_all(6)
	estilo.content_margin_left = 28.0
	estilo.content_margin_right = 28.0
	estilo.content_margin_top = 12.0
	estilo.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", estilo)
	var caja := VBoxContainer.new()
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_theme_constant_override("separation", 2)
	_titulo = Label.new()
	_titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titulo.add_theme_font_size_override("font_size", 24)
	_titulo.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	_subtitulo = Label.new()
	_subtitulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitulo.add_theme_font_size_override("font_size", 15)
	_subtitulo.add_theme_color_override("font_color", Color(0.78, 0.78, 0.82))
	caja.add_child(_titulo)
	caja.add_child(_subtitulo)
	panel.add_child(caja)
	# Arriba-centro: los offsets se fijan DESPUÉS del preset (lo resetea).
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -300.0
	offset_right = 300.0
	offset_top = 28.0
	offset_bottom = 120.0
	add_child(panel)


## Muestra el banner con el nombre y el subtítulo dados. Reinicia el temporizador.
func mostrar(nombre: String, subtitulo: String) -> void:
	_titulo.text = "Has descubierto: " + nombre
	_subtitulo.text = subtitulo
	_restante = DURACION
	visible = true
	modulate.a = 0.0


func _process(delta: float) -> void:
	if _restante <= 0.0:
		return
	_restante -= delta
	if _restante <= 0.0:
		_restante = 0.0
		visible = false
		modulate.a = 0.0
		return
	var transcurrido: float = DURACION - _restante
	var alfa: float = 1.0
	if transcurrido < FUNDIDO_ENTRADA:
		alfa = transcurrido / FUNDIDO_ENTRADA
	elif _restante < FUNDIDO_SALIDA:
		alfa = _restante / FUNDIDO_SALIDA
	modulate.a = clampf(alfa, 0.0, 1.0)
