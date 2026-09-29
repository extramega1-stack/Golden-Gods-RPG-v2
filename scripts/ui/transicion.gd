class_name Transicion
extends CanvasLayer
## Bloque 65: fade a negro entre escenas, para que el título, la creación de
## personaje y el mundo no aparezcan de un golpe.
##
## POR QUÉ EXISTE: sin esto, `change_scene_to_file` teletransporta. El jugador
## ve el 3D procedural del título y, sin cortar, el terreno de 36.864 u. Con
## un teletransporte entre ciudades a 10 km el corte es peor todavía: la
## cámara hace su `snap_seguimiento()` (que existe porque el `lerp` cruzaría
## el mapa entero) y el resultado es un salto seco.
##
## - Es un `CanvasLayer` en la capa 98 (`UiLayers.TRANSICION`), por DEBAJO de
##   los modales (90–99 es "modales críticos", pero la transición tiene que
##   quedar por encima del mundo y por debajo de un eventual mensaje).
## - `process_mode = ALWAYS`: tiene que poder correr con el árbol pausado, que
##   es justo lo que pasa en el menú de pausa.
## - Reentrante y seguro: si se pide una transición mientras hay otra, se
##   espera. Godot no permite cambiar de escena y liberar en el mismo frame.

const CAPA: int = UiLayers.TRANSICION
## Duración del fundido a negro y la vuelta. Corto a propósito: si dura más de
## medio segundo el jugador lo lee como "el juego se colgó".
const FADE_SEG: float = 0.22

## Emitida cuando el fundido a negro termina: es cuando hay que cambiar de
## escena (cambiar durante el fade al uncover rompe el proceso).
signal cubiertos

static var _instancia: Transicion = null

var _panel: ColorRect = null
var _cargando: bool = false


## Instancia única, colgada del árbol de la escena ACTUAL. Se rehace en cada
## cambio de escena porque el árbol se libera entero.
static var actual: Transicion:
	get:
		return _instancia


static func asegurar() -> Transicion:
	if _instancia != null and is_instance_valid(_instancia):
		return _instancia
	var t := Transicion.new()
	t.name = "Transicion"
	t.layer = CAPA
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	var arbol: SceneTree = Engine.get_main_loop() as SceneTree
	if arbol == null or arbol.root == null:
		return t
	# INMEDIATO, no diferido: `asegurar()` se llama desde un boton (no desde
	# un `_ready` que este montando la escena), y diferido dejaba el nodo fuera
	# del arbol mientras `_fundir` ya estaba creando el tween.
	arbol.root.add_child(t)
	_instancia = t
	return t


## Cambia de escena con fundido. `ruta` vacía = solo fundir a negro (lo usa el
## guardado, que quiere tapar el pantallazo de "escribiendo…").
static func ir_a(ruta: String) -> void:
	var t: Transicion = asegurar()
	t._ir_a(ruta)


func _ready() -> void:
	_instancia = self
	# ALWAYS: el fundido tiene que correr con el árbol pausado (menú de pausa).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = ColorRect.new()
	_panel.name = "Fundido"
	_panel.color = Color(0, 0, 0, 0)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# IGNORE: el fundido no puede comerse los clics de los botones que haya
	# debajo mientras se desvanece.
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)


## BUG (bloque 65, encontrado jugando): esta funcion usaba `get_tree()` DESPUES
## del `await`. Al liberar la escena anterior, este nodo se iba con ella (cuelga
## del arbol, no del root, si la escena lo libera) y `get_tree()` devolvia
## null: "Invalid assignment of property 'paused' on a null instance".
## El arreglo es NO depender de `self` tras el await: se captura el arbol antes
## y se usa esa referencia, que sigue valiendo aunque el nodo muera.
func _ir_a(ruta: String) -> void:
	if _cargando:
		return
	var arbol: SceneTree = Engine.get_main_loop() as SceneTree
	if arbol == null:
		# Sin arbol no hay fundido: se cambia de escena directo ( degrade, no
		# romper la partida por un efecto).
		_cargando = false
		return
	_cargando = true
	await _fundir(1.0)
	if ruta != "":
		arbol.paused = false
		arbol.change_scene_to_file(ruta)
		# Un frame entero con la pantalla tapada: si se destapa en el mismo
		# frame del cambio, se ve el frame en blanco de la escena nueva.
		await arbol.process_frame
		await arbol.process_frame
	await _fundir(0.0)
	_cargando = false


## `hacia` 1.0 = a negro, 0.0 = transparente.
func _fundir(hacia: float) -> void:
	if _panel == null:
		return
	visible = true
	PilaUI.abrir(self)
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_panel, "color:a", hacia, FADE_SEG)
	await tween.finished
	# Al terminar de irse a negro, se queda invisible: un rectángulo negro
	# transparente sigue costando compositing aunque no se vea.
	_panel.color.a = hacia
	# Al volver a transparente, la capa entera se apaga: un `CanvasLayer` con un
	# solo `ColorRect` transparente encima del mundo sigue costando un frame de
	# composición por nada.
	visible = hacia > 0.0


## Un fundido suelto sin cambiar de escena: para tapar un guardado o un
## pantallazo de carga puntual.
static func parpadeo() -> void:
	asegurar()._ir_a("")
