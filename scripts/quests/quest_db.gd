class_name QuestDB
extends RefCounted
## Catálogo de misiones: carga `res://data/quests.json` UNA sola vez y lo
## cachea.
##
## Mismo patrón que NpcDB/TiendaDB (fases 6/7): solo LEE el JSON;
## `cargar()` es idempotente. Las misiones son datos puros; la lógica de
## estados vive en QuestLog (fase 8).

static var _cache: Dictionary = {}
static var _cargado: bool = false


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	var texto: String = FileAccess.get_file_as_string("res://data/quests.json")
	if texto == "":
		push_warning("[QuestDB] no se pudo leer res://data/quests.json")
		return
	# parse_string retorna Variant: NUNCA `:=` aquí (warning como error).
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		push_warning("[QuestDB] quests.json no es un diccionario JSON válido")
		return
	var lista: Array = datos.get("quests", [])
	for entrada in lista:
		if not (entrada is Dictionary):
			continue
		var quest: Dictionary = entrada
		var quest_id: String = str(quest.get("id", ""))
		if quest_id == "":
			continue
		if _cache.has(quest_id):
			push_warning("[QuestDB] id duplicado en quests.json: %s" % quest_id)
			continue
		_cache[quest_id] = quest


static func existe(quest_id: String) -> bool:
	cargar()
	return _cache.has(quest_id)


static func obtener(quest_id: String) -> Dictionary:
	cargar()
	var quest: Variant = _cache.get(quest_id, {})
	if quest is Dictionary:
		return quest
	return {}


static func ids() -> Array[String]:
	cargar()
	var resultado: Array[String] = []
	for k in _cache:
		resultado.append(str(k))
	return resultado


## Lore de una misión (fase 9): 1–3 líneas de texto narrativo desde
## `data/quests.json`. Mismo patrón que el resto de campos: "" si la
## misión no existe o no declara lore.
static func lore(quest_id: String) -> String:
	return str(obtener(quest_id).get("lore", ""))
