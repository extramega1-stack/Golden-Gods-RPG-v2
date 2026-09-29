class_name PiezasDB
extends RefCounted
## Fase 61: catálogo de piezas construibles, de `data/piezas.json`.
## Los patrones del proyecto: carga idempotente, lectura tolerante, sin
## estado (el estado de qué hay puesto en cada refugio vive en `Refugio`).

const RUTA: String = "res://data/piezas.json"

static var _cache: Dictionary = {}
static var _orden: Array[String] = []
static var _cargado: bool = false


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	_orden.clear()
	_cache.clear()
	var texto: String = FileAccess.get_file_as_string(RUTA)
	if texto.is_empty():
		push_warning("[PiezasDB] no se pudo leer " + RUTA)
		return
	var crudo = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[PiezasDB] JSON inválido: " + RUTA)
		return
	var piezas: Dictionary = (crudo as Dictionary).get("piezas", {})
	for id in piezas.keys():
		var pid: String = str(id)
		_cache[pid] = piezas[id]
		_orden.append(pid)


static func ids() -> Array[String]:
	cargar()
	return _orden


static func existe(id: String) -> bool:
	cargar()
	return _cache.has(id)


static func pieza(id: String) -> Dictionary:
	cargar()
	return _cache.get(id, {})


static func nombre_de(id: String) -> String:
	return str(pieza(id).get("nombre", id))


## La pieza ocupa espacio: [ancho, alto, fondo] en unidades de mundo.
static func caja(id: String) -> Vector3:
	var c: Array = pieza(id).get("cajas", [1.0, 1.0, 1.0])
	return Vector3(float(c[0]), float(c[1]), float(c[2]))


static func admite_rotacion(id: String) -> bool:
	return bool(pieza(id).get("rot", false))


## Qué hace la pieza cuando se la usa ("cocinar", "forjar", "dormir"… o "").
static func accion(id: String) -> String:
	return str(pieza(id).get("interactiva", ""))


## Materiales que cuesta. Dictionary {item_id: cantidad}.
static func costo(id: String) -> Dictionary:
	return pieza(id).get("costo", {})
