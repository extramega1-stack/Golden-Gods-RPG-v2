class_name VetaDB
extends RefCounted
## Vetas mineras (fase 45) — fuente de datos de `data/vetas.json`, que a su
## vez lo produce `tools/generar_vetas.py` (determinista, misma semilla que el
## terreno). Igual que el resto de DBs: carga idempotente, ids en orden del
## JSON y lecturas tolerantes. Sin estado: la lógica de minar vive en
## `Mineria` y el estado de cada veta, en `Veta`.

const RUTA: String = "res://data/vetas.json"

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
		push_warning("[VetaDB] no se pudo leer " + RUTA)
		return
	var crudo: Variant = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[VetaDB] JSON inválido en " + RUTA)
		return
	for v in (crudo as Dictionary).get("vetas", []):
		if not (v is Dictionary):
			continue
		var vd: Dictionary = v
		var vid: String = str(vd.get("id", ""))
		if vid == "":
			continue
		_cache[vid] = vd
		_orden.append(vid)


## Ids de veta en orden del JSON.
static func ids() -> Array[String]:
	cargar()
	return _orden.duplicate()


static func existe(veta_id: String) -> bool:
	cargar()
	return _cache.has(veta_id)


static func obtener(veta_id: String) -> Dictionary:
	cargar()
	return _cache.get(veta_id, {})


## Vetas de una región ("" = todas), en orden del JSON.
static func vetas_de_region(region_id: String) -> Array[String]:
	cargar()
	if region_id == "":
		return _orden.duplicate()
	var res: Array[String] = []
	for vid in _orden:
		if str((_cache[vid] as Dictionary).get("region", "")) == region_id:
			res.append(vid)
	return res


## Posición de una veta en el mundo, en coordenadas Godot (y = 0: la Y la
## pone el terreno). Vector3.ZERO si el id no existe.
static func posicion_de(veta_id: String) -> Vector3:
	var v: Dictionary = obtener(veta_id)
	if v.is_empty():
		return Vector3.ZERO
	return Vector3(float(v.get("x", 0.0)), 0.0, float(v.get("z", 0.0)))
