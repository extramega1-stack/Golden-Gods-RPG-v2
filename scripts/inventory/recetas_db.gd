class_name RecetasDB
extends RefCounted
## Recetas de herrería (fase 44) — fuente de datos de `data/recetas.json`.
## Igual que el resto de DBs: carga idempotente, ids en orden del JSON y
## lecturas tolerantes. Sin estado: la lógica de forjar vive en `Herreria`.

const RUTA: String = "res://data/recetas.json"

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
		push_warning("[RecetasDB] no se pudo leer " + RUTA)
		return
	var crudo: Variant = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[RecetasDB] JSON inválido en " + RUTA)
		return
	for r in (crudo as Dictionary).get("recetas", []):
		if not (r is Dictionary):
			continue
		var rd: Dictionary = r
		var rid: String = str(rd.get("id", ""))
		if rid == "":
			continue
		_cache[rid] = rd
		_orden.append(rid)


## Ids de receta en orden del JSON.
static func ids() -> Array[String]:
	cargar()
	return _orden.duplicate()


static func existe(receta_id: String) -> bool:
	cargar()
	return _cache.has(receta_id)


static func obtener(receta_id: String) -> Dictionary:
	cargar()
	return _cache.get(receta_id, {})


## Recetas de un herrero ("" = todas), en orden del JSON.
static func recetas_de_herrero(herrero_id: String) -> Array[String]:
	cargar()
	if herrero_id == "":
		return _orden.duplicate()
	var res: Array[String] = []
	for rid in _orden:
		if str((_cache[rid] as Dictionary).get("herrero", "")) == herrero_id:
			res.append(rid)
	return res
