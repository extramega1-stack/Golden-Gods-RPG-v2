class_name TiendaDB
extends RefCounted
## Catálogo de tiendas: carga `res://data/tiendas.json` UNA sola vez y lo
## cachea. Mismo patrón que NpcDB/ItemDB/SkillDB: solo LEE el JSON;
## `cargar()` es idempotente. Las tiendas ligan con su NPC vendedor por el
## campo `tienda_id` en data/npcs.json (y, como respaldo, por `npc_id`
## dentro de cada tienda de data/tiendas.json).

static var _cache: Dictionary = {}
static var _cargado: bool = false


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	var texto: String = FileAccess.get_file_as_string("res://data/tiendas.json")
	if texto == "":
		push_warning("[TiendaDB] no se pudo leer res://data/tiendas.json")
		return
	# parse_string retorna Variant: NUNCA `:=` aquí (warning como error).
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		push_warning("[TiendaDB] tiendas.json no es un diccionario JSON válido")
		return
	var lista: Array = datos.get("tiendas", [])
	for entrada in lista:
		if not (entrada is Dictionary):
			continue
		var tienda: Dictionary = entrada
		var tienda_id: String = str(tienda.get("id", ""))
		if tienda_id == "":
			continue
		if _cache.has(tienda_id):
			push_warning("[TiendaDB] id duplicado en tiendas.json: %s" % tienda_id)
			continue
		_cache[tienda_id] = tienda


static func existe(tienda_id: String) -> bool:
	cargar()
	return _cache.has(tienda_id)


static func obtener(tienda_id: String) -> Dictionary:
	cargar()
	var t: Variant = _cache.get(tienda_id, {})
	if t is Dictionary:
		return t
	return {}


static func ids() -> Array[String]:
	cargar()
	var resultado: Array[String] = []
	for k in _cache:
		resultado.append(str(k))
	return resultado


## Id de la tienda ligada a un NPC; "" si el NPC no vende. Primero mira el
## campo `tienda_id` de data/npcs.json; como respaldo, el `npc_id` dentro
## de cada tienda de data/tiendas.json.
static func tienda_de_npc(npc_id: String) -> String:
	cargar()
	if npc_id == "":
		return ""
	var desde_npc: String = str(NpcDB.obtener(npc_id).get("tienda_id", ""))
	if desde_npc != "":
		if _cache.has(desde_npc):
			return desde_npc
		push_warning("[TiendaDB] npcs.json apunta a tienda desconocida: %s" % desde_npc)
		return ""
	for tid in _cache:
		var t: Dictionary = _cache[tid]
		if str(t.get("npc_id", "")) == npc_id:
			return str(tid)
	return ""
