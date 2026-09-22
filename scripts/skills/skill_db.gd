class_name SkillDB
extends RefCounted
## Base de datos de skills (data-driven): lee res://data/skills.json una vez.
##
## Fase 5. Los skills son DATOS: id, nombre, descripcion, mana, cooldown,
## rango, power, magica, bonus_crit, varianza y efecto {tipo, cantidad}.
## SkillSystem los ejecuta; este archivo solo los sirve. Agregar un skill
## nuevo = editar el JSON, no código.

const RUTA: String = "res://data/skills.json"

static var _cache: Dictionary = {}
static var _orden: Array[String] = []


## Lee el JSON una sola vez; llamadas repetidas no hacen nada (idempotente).
static func cargar() -> void:
	if not _cache.is_empty():
		return
	if not FileAccess.file_exists(RUTA):
		push_error("[SkillDB] no existe " + RUTA)
		return
	var f: FileAccess = FileAccess.open(RUTA, FileAccess.READ)
	if f == null:
		push_error("[SkillDB] no se pudo abrir " + RUTA)
		return
	var texto: String = f.get_as_text()
	f.close()
	# JSON.parse_string retorna Variant: NUNCA `:=` sobre él (ver AGENTS.md).
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		push_error("[SkillDB] JSON inválido en " + RUTA)
		return
	var dict_datos: Dictionary = datos
	var lista_skills: Array = dict_datos.get("skills", [])
	for s in lista_skills:
		if not (s is Dictionary):
			continue
		var dict_skill: Dictionary = s
		var sid: String = str(dict_skill.get("id", ""))
		if sid == "" or _cache.has(sid):
			continue
		_cache[sid] = dict_skill
		_orden.append(sid)


static func existe(skill_id: String) -> bool:
	cargar()
	return _cache.has(skill_id)


static func obtener(skill_id: String) -> Dictionary:
	cargar()
	var d: Dictionary = _cache.get(skill_id, {})
	return d


## Los ids en orden de hotbar (el orden del JSON).
static func lista() -> Array[String]:
	cargar()
	var copia: Array[String] = []
	copia.append_array(_orden)
	return copia


## Fase 18: ids de la clase dada (en orden del JSON). Incluye los skills sin
## clase asignada ("" = todas las clases). Clase desconocida → lista vacía.
static func skills_por_clase(clase_id: String) -> Array[String]:
	cargar()
	var res: Array[String] = []
	for sid in _orden:
		var sk: Dictionary = _cache.get(sid, {})
		var c: String = str(sk.get("clase", ""))
		if c == "" or c == clase_id:
			res.append(sid)
	return res
