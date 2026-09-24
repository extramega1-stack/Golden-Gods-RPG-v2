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

var _jugador: Player = null
var _conectado: bool = false

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
	_barra_xp.max_value = float(maxi(siguiente, 1))
	_barra_xp.value = float(actual)


func _al_nivel(nivel: int) -> void:
	_etiqueta_nivel.text = "Nv %d" % nivel


func _al_oro(oro: int) -> void:
	_etiqueta_oro.text = "Oro: %d" % oro
