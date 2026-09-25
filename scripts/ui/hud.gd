class_name HUD
extends CanvasLayer
## HUD estilo FlyFF Universe (fase 32): bloque de estado arriba-izquierda
## (retrato + barras HP/MP con valores "actual/máx" + Nv/Oro) y barra de XP
## fina de ancho completo al filo inferior. Fase 4/11: variables y señales
## intactas; solo cambia el cromo (TemaFlyFF).
##
## REGLA DURA (directriz de Juan Diego): la UI solo LEE el StatBlock y las
## señales del Player; nunca escribe stats ni llama a take_damage/gain_xp.
## Todos los controles llevan mouse_filter IGNORE para no comerse ni un
## clic del juego (lección 11 de AGENTS.md).

## Fase 46.1: el jugador pidió el botón de la ayuda. La emite el HUD (que
## solo hace de botón) y la escucha quien tenga el `PanelAyuda` (la demo).
signal ayuda_solicitada

var _jugador: Player = null
var _conectado: bool = false
## Botón "?" del manual (esquina superior derecha).
var _boton_ayuda: Button = null

var _barra_vida: ProgressBar = null
var _barra_mana: ProgressBar = null
var _barra_xp: ProgressBar = null
var _valor_vida: Label = null
var _valor_mana: Label = null
var _etiqueta_nivel: Label = null
var _etiqueta_oro: Label = null
## Fase 11: retrato del héroe (emblema + nombre + nivel), arriba-izquierda.
var _retrato: RetratoHeroe = null


func _ready() -> void:
	_construir()


func _construir() -> void:
	# Bloque de estado FlyFF: marco dorado con retrato + barras.
	var marco := PanelContainer.new()
	marco.set_anchors_preset(Control.PRESET_TOP_LEFT)
	marco.position = Vector2(16, 12)
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.add_theme_stylebox_override("panel", TemaFlyFF.marco())
	add_child(marco)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 10)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.add_child(fila)
	_retrato = RetratoHeroe.new()
	_retrato.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fila.add_child(_retrato)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(col)
	var sup := HBoxContainer.new()
	sup.add_theme_constant_override("separation", 12)
	sup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sup)
	_etiqueta_nivel = _nueva_etiqueta("Nv 1")
	_etiqueta_oro = _nueva_etiqueta("Oro: 0")
	sup.add_child(_etiqueta_nivel)
	sup.add_child(_etiqueta_oro)
	_barra_vida = _nueva_barra(TemaFlyFF.HP, Vector2(240, 18))
	_valor_vida = _nuevo_valor()
	col.add_child(_fila_barra(_barra_vida, _valor_vida))
	_barra_mana = _nueva_barra(TemaFlyFF.MP, Vector2(240, 14))
	_valor_mana = _nuevo_valor()
	col.add_child(_fila_barra(_barra_mana, _valor_mana))

	_boton_ayuda = _nuevo_boton_ayuda()
	add_child(_boton_ayuda)

	# XP: fina, de ancho completo al filo inferior (como antes).
	_barra_xp = _nueva_barra(TemaFlyFF.XP, Vector2(1, 10))
	_barra_xp.anchor_left = 0.0
	_barra_xp.anchor_right = 1.0
	_barra_xp.anchor_top = 1.0
	_barra_xp.anchor_bottom = 1.0
	_barra_xp.offset_left = 0.0
	_barra_xp.offset_right = 0.0
	_barra_xp.offset_top = -14.0
	_barra_xp.offset_bottom = -4.0
	add_child(_barra_xp)


## Fila barra + valor "actual/máx" a la derecha (FlyFF).
## Fase 46.1 — botón "?" del manual, arriba a la derecha (esquina libre del
## HUD: el marco de estado vive arriba a la izquierda, la brújula arriba en el
## centro y el minimapa abajo a la derecha). Con la misma piel dorada del
## resto, y con tooltip: si el jugador no lo vio, le basta con pasar el ratón.
func _nuevo_boton_ayuda() -> Button:
	var b := Button.new()
	b.name = "BotonAyuda"
	b.text = "?"
	b.tooltip_text = "Manual de controles y mecánicas (tecla ?)"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(38, 38)
	b.size = Vector2(38, 38)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 0.0
	b.anchor_bottom = 0.0
	b.offset_left = -54.0
	b.offset_right = -16.0
	b.offset_top = 12.0
	b.offset_bottom = 50.0
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.70))
	b.add_theme_color_override("font_pressed_color", Color(0.95, 0.76, 0.32))
	b.add_theme_stylebox_override("normal", _estilo_ayuda(Color(0.10, 0.09, 0.07, 0.92)))
	b.add_theme_stylebox_override("hover", _estilo_ayuda(Color(0.18, 0.15, 0.10, 0.96)))
	b.add_theme_stylebox_override("pressed", _estilo_ayuda(Color(0.24, 0.19, 0.11, 0.98)))
	b.pressed.connect(func() -> void: ayuda_solicitada.emit())
	return b


func _estilo_ayuda(fondo: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fondo
	sb.border_color = Color(0.85, 0.68, 0.30)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb


func _fila_barra(barra: ProgressBar, valor: Label) -> HBoxContainer:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(barra)
	fila.add_child(valor)
	return fila


func _nuevo_valor() -> Label:
	var l: Label = TemaFlyFF.etiqueta("0/0", 12, TemaFlyFF.APAGADO)
	l.custom_minimum_size = Vector2(110, 0)
	return l


func _nueva_barra(color: Color, tam: Vector2) -> ProgressBar:
	var b: ProgressBar = ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 100.0
	b.value = 100.0
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.custom_minimum_size = tam
	b.add_theme_stylebox_override("background", TemaFlyFF.fondo_barra())
	b.add_theme_stylebox_override("fill", TemaFlyFF.relleno(color))
	return b


func _nueva_etiqueta(texto: String) -> Label:
	return TemaFlyFF.etiqueta(texto, 18)


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
	_retrato.conectar(j)
	_conectado = true
	refrescar()


## Relee todo el estado (tras cargar partida, por ejemplo).
func refrescar() -> void:
	if _jugador == null:
		return
	_retrato.refrescar()
	_al_vida(_jugador.vida_actual, _jugador.stats.vida_max)
	_al_mana(_jugador.mana_actual, _jugador.stats.mana_max)
	_al_xp(_jugador.xp_actual, Formulas.xp_for_level(_jugador.nivel + 1))
	_al_nivel(_jugador.nivel)
	_al_oro(_jugador.oro)


func _al_vida(actual: float, maxima: float) -> void:
	_barra_vida.max_value = maxima
	_barra_vida.value = actual
	_valor_vida.text = "%d/%d" % [int(actual), int(maxima)]


func _al_mana(actual: float, maxima: float) -> void:
	_barra_mana.max_value = maxima
	_barra_mana.value = actual
	_valor_mana.text = "%d/%d" % [int(actual), int(maxima)]


func _al_xp(actual: int, siguiente: int) -> void:
	# Fase 37: tramo dentro del nivel (antes se pintaban acumulados y la
	# barra nunca se reseteaba al subir).
	var t: Vector2 = tramo_xp(actual, _nivel_actual())
	_barra_xp.max_value = t.y
	_barra_xp.value = t.x


## Tramo de XP del nivel dado, puro y testeable: x = valor, y = máximo.
## Acotado (nunca negativo ni por encima del máximo).
static func tramo_xp(actual: int, nivel: int) -> Vector2:
	var base: int = Formulas.xp_for_level(maxi(nivel, 1))
	var siguiente: int = Formulas.xp_for_level(maxi(nivel, 1) + 1)
	var maximo: float = float(maxi(siguiente - base, 1))
	var valor: float = clampf(float(actual - base), 0.0, maximo)
	return Vector2(valor, maximo)


## El botón "?" del manual (para tests).
func boton_ayuda() -> Button:
	return _boton_ayuda


func _nivel_actual() -> int:
	if _jugador != null:
		return _jugador.nivel
	return 1


func _al_nivel(nivel: int) -> void:
	_etiqueta_nivel.text = "Nv %d" % nivel
	# Fase 37: al subir cambia la base del tramo; se repinta con el XP actual.
	if _jugador != null:
		_al_xp(_jugador.xp_actual, Formulas.xp_for_level(nivel + 1))


func _al_oro(oro: int) -> void:
	_etiqueta_oro.text = "Oro: %d" % oro
