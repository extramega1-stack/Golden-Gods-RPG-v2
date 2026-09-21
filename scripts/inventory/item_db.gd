class_name ItemDB
extends RefCounted
## Catálogo de items: carga `res://data/items.json` UNA sola vez y lo cachea.
##
## Solo LEE el JSON; no valida game design (eso lo hacen Inventario/Equipo).
## Idempotente: llamar `cargar()` varias veces no relee el archivo.


static var _cache: Dictionary = {}
static var _cargado: bool = false


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	var texto: String = FileAccess.get_file_as_string("res://data/items.json")
	if texto == "":
		push_warning("[ItemDB] no se pudo leer res://data/items.json")
		return
	# parse_string retorna Variant: NUNCA `:=` aquí (warning como error).
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		push_warning("[ItemDB] items.json no es un diccionario JSON válido")
		return
	var lista: Array = datos.get("items", [])
	for entrada in lista:
		if not (entrada is Dictionary):
			continue
		var item: Dictionary = entrada
		var item_id: String = str(item.get("id", ""))
		if item_id == "":
			continue
		if _cache.has(item_id):
			push_warning("[ItemDB] id duplicado en items.json: %s" % item_id)
			continue
		_cache[item_id] = item


static func existe(item_id: String) -> bool:
	cargar()
	return _cache.has(item_id)


static func obtener(item_id: String) -> Dictionary:
	cargar()
	var item: Variant = _cache.get(item_id, {})
	if item is Dictionary:
		return item
	return {}


static func ids() -> Array[String]:
	cargar()
	var resultado: Array[String] = []
	for k in _cache:
		resultado.append(str(k))
	return resultado
