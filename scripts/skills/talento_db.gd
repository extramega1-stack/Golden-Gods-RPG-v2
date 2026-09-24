class_name TalentoDB
extends RefCounted
## Catálogo de talentos: carga `res://data/talentos.json` UNA sola vez y lo
## cachea. Mismo patrón que SkillDB/QuestDB (fase 28): solo LEE el JSON.

static var _cache: Dictionary = {}
static var _cargado: bool = false


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	var texto: String = FileAccess.get_file_as_string("res://data/talentos.json")
	if texto == "":
		push_warning("[TalentoDB] no se pudo leer res://data/talentos.json")
		return
	# parse_string retorna Variant: NUNCA `:=` aquí (warning como error).
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		push_warning("[TalentoDB] talentos.json no es un diccionario JSON válido")
		return
	var lista: Array = datos.get("talentos", [])
	for entrada in lista:
		if not (entrada is Dictionary):
			continue
		var tal: Dictionary = entrada
		var tid: String = str(tal.get("id", ""))
		if tid == "":
			continue
		if _cache.has(tid):
			push_warning("[TalentoDB] id duplicado en talentos.json: %s" % tid)
			continue
		_cache[tid] = tal


static func existe(talento_id: String) -> bool:
	cargar()
	return _cache.has(talento_id)


static func obtener(talento_id: String) -> Dictionary:
	cargar()
	var tal: Variant = _cache.get(talento_id, {})
	if tal is Dictionary:
		return tal
	return {}


static func ids() -> Array[String]:
	cargar()
	var resultado: Array[String] = []
	for k in _cache:
		resultado.append(str(k))
	return resultado


## Ids de talentos de una clase, en orden de requiere_nivel.
static func talentos_por_clase(clase_id: String) -> Array[String]:
	cargar()
	var pares: Array = []
	for k in _cache:
		var tal: Dictionary = _cache[k]
		if str(tal.get("clase", "")) == clase_id:
			pares.append([int(tal.get("requiere_nivel", 1)), str(k)])
	pares.sort()
	var resultado: Array[String] = []
	for p in pares:
		resultado.append(str((p as Array)[1]))
	return resultado
