class_name RefugioDB
extends RefCounted
## Fase 60: puntos reclamables del Refugio, de `data/refugios.json`.
## Mismo patrón que el resto de DBs: carga idempotente y lecturas tolerantes.

const RUTA: String = "res://data/refugios.json"

static var _cache: Dictionary = {}
static var _orden: Array[String] = []
static var _cargado: bool = false


static func cargar(ruta: String = RUTA) -> void:
	if _cargado:
		return
	_cargado = true
	_orden.clear()
	_cache.clear()
	var texto: String = FileAccess.get_file_as_string(ruta)
	if texto.is_empty():
		push_warning("[RefugioDB] no se pudo leer " + ruta)
		return
	var crudo = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[RefugioDB] JSON inválido: " + ruta)
		return
	for r in (crudo as Dictionary).get("refugios", []):
		if not (r is Dictionary):
			continue
		var rd: Dictionary = r
		var rid: String = str(rd.get("id", ""))
		if rid == "":
			continue
		_cache[rid] = rd
		_orden.append(rid)


static func ids() -> Array[String]:
	cargar()
	return _orden


static func existe(id: String) -> bool:
	cargar()
	return _cache.has(id)


static func obtener(id: String) -> Dictionary:
	cargar()
	return _cache.get(id, {})


static func nombre_de(id: String) -> String:
	return str(obtener(id).get("nombre", id))


static func ciudad_de(id: String) -> String:
	return str(obtener(id).get("ciudad", id))


static func radio(id: String) -> float:
	return float(obtener(id).get("radio", 40.0))


## Techo de piezas construibles. Es un dato, no una constante en el código,
## porque es un presupuesto de VRAM (§9.5) y tiene que poder ajustarse sin
## recompilar.
static func piezas_max(id: String) -> int:
	return maxi(0, int(obtener(id).get("piezas_max", 24)))
