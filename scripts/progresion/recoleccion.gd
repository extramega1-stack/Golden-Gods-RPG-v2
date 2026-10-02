class_name Recoleccion
extends RefCounted
## Fase 72: el CUARTO eje de habilidad, que era el único que no subía.
##
## POR QUÉ ESTE ARCHIVO EXISTE: `data/habilidades.json` declara cuatro
## habilidades —tala, mineria, cocina y recoleccion— y las tres primeras
## subían jugando. `recoleccion` NO: `habilidades.ganar("recoleccion", ...)`
## aparecía en un solo lugar de todo el repositorio, un test
## (`tests/test_fase59_hechos.gd:165`). Se podía testear que el Hecho
## "Sed ausente" se abría y no había forma de ganarlo, porque su habilidad
## jamás subía de tramo.
##
## POR QUÉ NO SE PEGÓ EL `ganar` EN `Pickup` Y LISTO: porque el CUÁNTO tiene
## que ser un dato, no un número en el código (§9.4), igual que el XP de un
## árbol está en `data/arboles.json` y el de una receta en
## `data/recetas_cocina.json`. Acá el dato es `data/recoleccion.json`.
##
## DÓNDE SE CONECTA: en `Pickup._revisar_recogida()`, el nodo que suelta el
## botín en el suelo y avisa cuando el jugador lo pisa. Es el ÚNico punto por
## el que pasa todo lo que se junta del mundo —el botín de cada mob y lo que
## sueltan las cajas—, así que engancharlo ahí es lo que hace que sea imposible
## que un objeto llegue al inventario sin sumar su XP. Conectarlo en la escena,
## en cambio, dependería de que cada demo se acuerde.
##
## PURA salvo `otorgar`, que recibe el jugador.

const RUTA: String = "res://data/recoleccion.json"

## Datos cacheados. `cargar()` es idempotente y lee el archivo UNA vez: esto
## se llama en cada recogida y releerlo sería una lectura de disco por pickup.
static var _datos: Dictionary = {}
static var _cargado: bool = false


## Con defaults si el JSON falta o está roto. Un loot sin XP de recolección es
## un Hecho que no llega; un loot que CRASHEA el juego es peor.
static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	var texto: String = FileAccess.get_file_as_string(RUTA)
	if texto.is_empty():
		push_warning("[Recoleccion] no se pudo leer " + RUTA
			+ ": la habilidad 'recoleccion' no sube")
		return
	var d: Variant = JSON.parse_string(texto)
	if d is Dictionary:
		_datos = d as Dictionary


## La habilidad a la que se le da el XP. Sale del dato, no de una const.
static func habilidad() -> String:
	cargar()
	return str(_datos.get("habilidad", "recoleccion"))


## Cuánto XP da este drop. Un item da `xp_item` por PICKUP (no por unidad: un
## botín de 3 con el mismo item no debería valer el triple) y el oro da 1 cada
## `oro_por_xp`. Un drop de 0 XP devuelve 0, que es el caso normal de un botín
## de materiales.
static func xp_de(drop: Dictionary) -> int:
	cargar()
	if drop.is_empty():
		return 0
	var total: int = 0
	match str(drop.get("tipo", "")):
		"item":
			total = int(_datos.get("xp_item", 0))
		"oro":
			var por_xp: int = maxi(1, int(_datos.get("oro_por_xp", 1)))
			total = int(drop.get("cantidad", 0)) / por_xp
	return maxi(0, total)


## Le da el XP al jugador. Devuelve cuánto se le dio (0 si no había jugador, si
## no tenía `Habilidades`, o si el drop no da XP).
##
## `jugador` es `Node` y no `Player` a propósito: el que junta se busca por el
## grupo "jugador" —una etiqueta, no un tipo— y atar la firma a `Player` haría
## que un test que colgara un nodo cualquiera se comiera un error de parseo en
## vez de un fallo legible.
static func otorgar(jugador: Node, drop: Dictionary) -> int:
	var xp: int = xp_de(drop)
	if xp <= 0 or jugador == null or not is_instance_valid(jugador):
		return 0
	var hab: Variant = jugador.get("habilidades")
	if hab == null:
		return 0
	var h: Habilidades = hab as Habilidades
	if h == null:
		return 0
	h.ganar(habilidad(), xp)
	return xp
