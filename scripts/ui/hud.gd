class_name HUD
extends CanvasLayer
## HUD mínimo de la fase 4: barras de vida/maná/XP + nivel + oro.
##
## REGLA DURA (directriz de Juan Diego): la UI solo LEE el StatBlock y las
## señales del Player; nunca escribe stats ni llama a take_damage/gain_xp.
## Todos los controles llevan mouse_filter IGNORE para no comerse ni un
## clic del juego (lección 11 de AGENTS.md).

var _jugador: Player = null
var _conectado: bool = false

var _barra_vida: ProgressBar = null
var _barra_mana: ProgressBar = null
var _barra_xp: ProgressBar = null
var _etiqueta_nivel: Label = null
var _etiqueta_oro: Label = null


func _ready() -> void:
	_construir()


func _construir() -> void:
	var caja_inf: VBoxContainer = VBoxContainer.new()
	caja_inf.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	caja_inf.position = Vector2(16, -96)
	caja_inf.custom_minimum_size = Vector2(300, 80)
	caja_inf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja_inf.add_theme_constant_override("separation", 4)
	add_child(caja_inf)
	_barra_vida = _nueva_barra(Color(0.75, 0.16, 0.16), Vector2(300, 20))
	_barra_mana = _nueva_barra(Color(0.16, 0.35, 0.8), Vector2(300, 16))
	caja_inf.add_child(_barra_vida)
	caja_inf.add_child(_barra_mana)

	_barra_xp = _nueva_barra(Color(0.25, 0.65, 0.25), Vector2(1, 8))
	_barra_xp.anchor_left = 0.0
	_barra_xp.anchor_right = 1.0
	_barra_xp.anchor_top = 1.0
	_barra_xp.anchor_bottom = 1.0
	_barra_xp.offset_left = 0.0
	_barra_xp.offset_right = 0.0
	_barra_xp.offset_top = -12.0
	_barra_xp.offset_bottom = -4.0
	add_child(_barra_xp)

	var caja_sup: VBoxContainer = VBoxContainer.new()
	caja_sup.set_anchors_preset(Control.PRESET_TOP_LEFT)
	caja_sup.position = Vector2(16, 12)
	caja_sup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja_sup.add_theme_constant_override("separation", 2)
	add_child(caja_sup)
	_etiqueta_nivel = _nueva_etiqueta("Nv 1")
	_etiqueta_oro = _nueva_etiqueta("Oro: 0")
	caja_sup.add_child(_etiqueta_nivel)
	caja_sup.add_child(_etiqueta_oro)


func _nueva_barra(color: Color, tam: Vector2) -> ProgressBar:
	var b: ProgressBar = ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 100.0
	b.value = 100.0
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.custom_minimum_size = tam
	var fondo: StyleBoxFlat = StyleBoxFlat.new()
	fondo.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	var relleno: StyleBoxFlat = StyleBoxFlat.new()
	relleno.bg_color = color
	b.add_theme_stylebox_override("background", fondo)
	b.add_theme_stylebox_override("fill", relleno)
	return b


func _nueva_etiqueta(texto: String) -> Label:
	var l: Label = Label.new()
	l.text = texto
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	l.add_theme_font_size_override("font_size", 18)
	return l


## Conecta el HUD al jugador (solo lectura: señales + StatBlock).
func conectar(j: Player) -> void:
	if _conectado:
		return
	_jugador = j
	j.vida_cambiada.connect(_al_vida)
	j.mana_cambiado.connect(_al_mana)
	j.xp_cambiada.connect(_al_xp)
	j.subio_nivel.connect(_al_nivel)
	j.oro_cambiado.connect(_al_oro)
	_conectado = true
	refrescar()


## Relee todo el estado (tras cargar partida, por ejemplo).
func refrescar() -> void:
	if _jugador == null:
		return
	_al_vida(_jugador.vida_actual, _jugador.stats.vida_max)
	_al_mana(_jugador.mana_actual, _jugador.stats.mana_max)
	_al_xp(_jugador.xp_actual, Formulas.xp_for_level(_jugador.nivel + 1))
	_al_nivel(_jugador.nivel)
	_al_oro(_jugador.oro)


func _al_vida(actual: float, maxima: float) -> void:
	_barra_vida.max_value = maxima
	_barra_vida.value = actual


func _al_mana(actual: float, maxima: float) -> void:
	_barra_mana.max_value = maxima
	_barra_mana.value = actual


func _al_xp(actual: int, siguiente: int) -> void:
	_barra_xp.max_value = float(maxi(siguiente, 1))
	_barra_xp.value = float(actual)


func _al_nivel(nivel: int) -> void:
	_etiqueta_nivel.text = "Nv %d" % nivel


func _al_oro(oro: int) -> void:
	_etiqueta_oro.text = "Oro: %d" % oro
