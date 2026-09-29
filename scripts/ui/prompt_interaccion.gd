class_name PromptInteraccion
extends CanvasLayer
## Fase 64: el rótulo "E — Prender fogata" que aparece al acercarse.
##
## POR QUÉ: la interacción por proximidad no se ve. Sin esto, el jugador tiene
## que adivinar que la fogata existe y que hay que pararse encima. El rótulo
## es la diferencia entre un mundo con objetos y un mundo con adornos.
##
## - Se suscribe a `Player.interactuable_cerca`, que ya emite "" cuando no hay
##   nada. No sondea el mundo por frame.
## - Solo MUESTRA. No decide qué se puede usar: eso es del nodo, que expone
##   su propio `texto_interaccion(jugador)`.

const CAPA: int = UiLayers.PROMPT
## Segundos que se queda el rótulo después de perder el objetivo, para que
## no parpadee al dar el último paso.
const GRACIA: float = 0.25

## §9.1
var system_id: StringName = &"prompt_interaccion"

var _caja: PanelContainer = null
var _etiqueta: Label = null
var _gracia: float = 0.0
var _texto_actual: String = ""


func _ready() -> void:
	layer = CAPA
	_construir()
	visible = false
	set_process(true)


func _construir() -> void:
	_caja = PanelContainer.new()
	_caja.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_caja.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caja.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Justo encima de la barra de acciones (que reserva 100 px) y de los
	# vitales. Si se solapan, el rótulo tapa la información.
	_caja.offset_bottom = -(UiLayers.ZONA_INFERIOR_RESERVADA + 60.0)
	_caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caja.add_theme_stylebox_override("panel", TemaFlyFF.marco())
	add_child(_caja)

	_etiqueta = Label.new()
	_etiqueta.add_theme_font_size_override("font_size", 15)
	_etiqueta.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	_etiqueta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caja.add_child(_etiqueta)
	# La CAJA arranca oculta, no el CanvasLayer: `visible` del layer se
	# apaga en `_process` y con él se va también lo que hay dentro. Si solo
	# se ocultara el layer, la caja seguiría "visible" para cualquier test
	# que la mirara, y es la caja la que dibuja.
	_caja.visible = false


func vigilar(j: Player) -> void:
	if j == null or not is_instance_valid(j):
		return
	if not j.interactuable_cerca.is_connected(_al_cambiar):
		j.interactuable_cerca.connect(_al_cambiar)


func _al_cambiar(texto: String, _nodo: Node) -> void:
	if texto == "":
		_gracia = GRACIA
		return
	_gracia = 0.0
	if texto == _texto_actual:
		return
	_texto_actual = texto
	_etiqueta.text = texto
	_caja.visible = true


func _process(delta: float) -> void:
	# La gracia es lo que evita el parpadeo en el borde: sin ella, el rótulo
	# se enciende y apaga mientras el jugador da el último paso hacia la fogata.
	if _caja.visible and _gracia > 0.0:
		_gracia -= delta
		if _gracia <= 0.0:
			_caja.visible = false
			_texto_actual = ""


## ¿Está visible? Para los tests.
func mostrado() -> bool:
	return _caja.visible


## El texto que muestra. Para los tests.
func texto() -> String:
	return _texto_actual
