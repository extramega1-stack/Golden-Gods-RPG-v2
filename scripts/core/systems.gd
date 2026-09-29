class_name Systems
extends Node
## Fase 51.1: contenedor de sistemas (§9.1 del spec).
##
## El problema que resuelve: hasta la fase 51.1, CERO de los 82 scripts del
## proyecto se registraba en el grupo `gg_system` ni exponía `system_id`,
## aunque el spec lo exige. El descubrimiento de sistemas era 100% rutas de
## nodo hardcodeadas desde una cadena de demos de 6 niveles de herencia
## (`fase14_demo` → `fase12_demo` → `fase9_demo` → `fase5_1_demo` → …) con
## 12 variables `@onready` apuntando a `$Player`, `$Terreno`, etc.
##
## Eso rompía tres cosas concretas:
## - Los tests de integración no podían montar una escena parcial: si el
##   nodo no estaba exactamente donde el `@onready` lo busca, era null.
## - Ningún sistema se podía encontrar por identidad: había que recorrer el
##   árbol a mano o adivinar la ruta.
## - El orden de instanciación quedaba atado a la demo, no al sistema.
##
## ALCANCE DELIBERADO Y PARCIAL: esto NO migra los 82 scripts. Migra los
## cuatro que estorban —`SaveSystem`, `Arena`, `GestorVetas` y
## `ViajeRapido`— que son los que hoy se instancian con `.new()` DENTRO de
## una demo. Los otros 78 siguen con acceso directo; la deuda queda
## documentada en el spec, no escondida.
##
## No hay autoload: la escena del juego lo crea y lo registra.

const GRUPO: StringName = &"gg_system"

## id -> sistema. Es la fuente de verdad propia (el grupo es el índice
## global, este diccionario evita `get_first_node_in_group` lineal).
var _registrados: Dictionary = {}


func _ready() -> void:
	add_to_group(GRUPO)


## Registra un sistema con su identidad. Lo llama el dueño del sistema al
## construirse, no el que lo busca.
##
## Acepta los dos tipos que hay en el proyecto: los que son `Node` (Arena,
## GestorVetas) entran además al grupo `gg_system`, y los que son
## `RefCounted` (SaveSystem, ViajeRapido) solo quedan en el diccionario del
## contenedor — un RefCounted no vive en el árbol, así que `add_to_group` no
## existe para él.
func registrar(sistema: Object, id: StringName) -> void:
	if sistema == null or not is_instance_valid(sistema):
		push_warning("[Systems] registro de '%s' con sistema null" % id)
		return
	if not &"system_id" in sistema:
		# El script del sistema tiene que declarar `system_id: StringName`.
		push_warning("[Systems] '%s' no declara system_id" % id)
		return
	sistema.set(&"system_id", id)
	if sistema is Node:
		var n: Node = sistema
		if not n.is_in_group(GRUPO):
			n.add_to_group(GRUPO)
	_registrados[id] = sistema


## Da de baja un sistema. La demo lo llama al recargar la partida.
func desregistrar(id: StringName) -> void:
	_registrados.erase(id)


## El sistema con esa id, o null. Con `solo_vivo` (default) descarta los que
## están en la cola de liberación: leer uno y que se libere en el frame
## siguiente es la forma más fácil de tener un crash elusive.
## Bloque 65: la instancia viva, para los sistemas que no la tienen a mano (el
## menú de pausa y el panel de opciones son `CanvasLayer`, cuelgan de la escena
## y no ven el `Systems` de la demo). Es estático a propósito: el problema que
## este contenedor resolvió en la 51.1 era justo no tener una ruta única.
static var actual: Systems = null


func _init() -> void:
	actual = self


func obtener(id: StringName, solo_vivo: bool = true) -> Object:
	if not _registrados.has(id):
		return null
	var s: Object = _registrados[id]
	if solo_vivo and s != null and not is_instance_valid(s):
		_registrados.erase(id)
		return null
	return s


## Como `obtener`, pero con error visible si no existe. Para los call sites
## donde la ausencia ES un bug (y no una configuración opcional).
func exigir(id: StringName) -> Object:
	var s: Object = obtener(id)
	if s == null:
		push_error("[Systems] no está registrado el sistema '%s'" % id)
	return s


## Ids registrados, ordenados. Para diagnóstico y tests.
func ids() -> Array[StringName]:
	var salida: Array[StringName] = []
	for k in _registrados.keys():
		salida.append(StringName(str(k)))
	return salida


func cantidad() -> int:
	return _registrados.size()
