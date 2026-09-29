class_name RecetasCocinaDB
extends RefCounted
## Fase 56: recetas de `data/recetas_cocina.json`. Mismo patrón que
## `RecetasDB` (herrería) y el resto de DBs del proyecto: carga idempotente,
## lectura tolerante, sin estado.

const RUTA: String = "res://data/recetas_cocina.json"

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
		push_warning("[RecetasCocinaDB] no se pudo leer " + RUTA)
		return
	var crudo = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[RecetasCocinaDB] JSON inválido: " + RUTA)
		return
	for r in (crudo as Dictionary).get("recetas", []):
		if not (r is Dictionary):
			continue
		var rd: Dictionary = r
		var ing: String = str(rd.get("ingrediente", ""))
		if ing == "":
			continue
		_cache[ing] = rd
		_orden.append(ing)


static func ids() -> Array[String]:
	cargar()
	return _orden


## ¿Hay receta para este ingrediente?
static func tiene(ingrediente: String) -> bool:
	cargar()
	return _cache.has(ingrediente)


static func receta(ingrediente: String) -> Dictionary:
	cargar()
	return _cache.get(ingrediente, {})


## Todos los ingredientes que se pueden cocinar.
static func ingredientes() -> Array[String]:
	return ids()
