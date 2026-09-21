class_name NpcDB
extends RefCounted
## Catálogo de NPCs: carga `res://data/npcs.json` UNA sola vez y lo cachea.
##
## Mismo patrón que ItemDB/SkillDB (fase 6): solo LEE el JSON; `cargar()` es
## idempotente. REGLA DURA: los NPCs no son combatibles (no se atacan);
## aquí solo se guardan sus datos (nombre, rol, líneas de diálogo).

static var _cache: Dictionary = {}
static var _cargado: bool = false


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	var texto: String = FileAccess.get_file_as_string("res://data/npcs.json")
	if texto == "":
		push_warning("[NpcDB] no se pudo leer res://data/npcs.json")
		return
	# parse_string retorna Variant: NUNCA `:=` aquí (warning como error).
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		push_warning("[NpcDB] npcs.json no es un diccionario JSON válido")
		return
	var lista: Array = datos.get("npcs", [])
	for entrada in lista:
		if not (entrada is Dictionary):
			continue
		var npc: Dictionary = entrada
		var npc_id: String = str(npc.get("id", ""))
		if npc_id == "":
			continue
		if _cache.has(npc_id):
			push_warning("[NpcDB] id duplicado en npcs.json: %s" % npc_id)
			continue
		_cache[npc_id] = npc


static func existe(npc_id: String) -> bool:
	cargar()
	return _cache.has(npc_id)


static func obtener(npc_id: String) -> Dictionary:
	cargar()
	var npc: Variant = _cache.get(npc_id, {})
	if npc is Dictionary:
		return npc
	return {}


static func ids() -> Array[String]:
	cargar()
	var resultado: Array[String] = []
	for k in _cache:
		resultado.append(str(k))
	return resultado
