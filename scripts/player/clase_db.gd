class_name ClaseDB
extends RefCounted
## Catálogo de clases del héroe: carga `res://data/clases.json` UNA sola vez
## y lo cachea.
##
## Mismo patrón que QuestDB/NpcDB/TiendaDB/ItemDB/SkillDB (fases 6–11): solo
## LEE el JSON; `cargar()` es idempotente. `ids()` respeta el "orden" del
## JSON (el orden de las tarjetas en la pantalla de creación).
##
## Fase 11: solo el guerrero es jugable. Activar otra clase después es solo
## tocar datos ("jugable": true): el código no cambia.

static var _cache: Dictionary = {}
static var _orden: Array[String] = []
static var _cargado: bool = false


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	var texto: String = FileAccess.get_file_as_string("res://data/clases.json")
	if texto == "":
		push_warning("[ClaseDB] no se pudo leer res://data/clases.json")
		return
	# parse_string retorna Variant: NUNCA `:=` aquí (warning como error).
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		push_warning("[ClaseDB] clases.json no es un diccionario JSON válido")
		return
	var dict: Dictionary = datos
	var orden: Array = dict.get("orden", [])
	for id_crudo in orden:
		var cid: String = str(id_crudo)
		if cid != "" and not _orden.has(cid):
			_orden.append(cid)
	var clases: Dictionary = dict.get("clases", {})
	for clave in clases:
		var cid2: String = str(clave)
		if _cache.has(cid2):
			push_warning("[ClaseDB] id duplicado en clases.json: %s" % cid2)
			continue
		var entrada: Variant = clases[clave]
		if entrada is Dictionary:
			_cache[cid2] = entrada
	# Sin "orden" declarado: se usa el orden de inserción del diccionario.
	if _orden.is_empty():
		for cid3 in _cache:
			_orden.append(str(cid3))


static func existe(clase_id: String) -> bool:
	cargar()
	return _cache.has(clase_id)


static func obtener(clase_id: String) -> Dictionary:
	cargar()
	var c: Variant = _cache.get(clase_id, {})
	if c is Dictionary:
		return c
	return {}


## Ids en el orden del JSON (pantalla de creación).
static func ids() -> Array[String]:
	cargar()
	return _orden.duplicate()


## Solo las jugables (en orden).
static func jugables() -> Array[String]:
	cargar()
	var res: Array[String] = []
	for cid in _orden:
		if es_jugable(cid):
			res.append(cid)
	return res


static func es_jugable(clase_id: String) -> bool:
	return bool(obtener(clase_id).get("jugable", false))


## Atributos base de la clase: {fuerza, aguante, destreza, inteligencia}
## (fase 34: sin agilidad; 15 base + 15 de rol, presupuesto 90).
## Clase desconocida → todo 0.0 (tolerante).
static func stats_base(clase_id: String) -> Dictionary:
	var c: Dictionary = obtener(clase_id)
	return {
		"fuerza": float(c.get("fuerza", 0.0)),
		"aguante": float(c.get("aguante", 0.0)),
		"destreza": float(c.get("destreza", 0.0)),
		"inteligencia": float(c.get("inteligencia", 0.0)),
	}


## Color primario de la clase (borde del emblema). Si falta o es inválido,
## dorado por defecto.
static func color_primario(clase_id: String) -> Color:
	return _color_de(clase_id, "color_primario")


## Color secundario de la clase (fondo del emblema). Mismo default.
static func color_secundario(clase_id: String) -> Color:
	return _color_de(clase_id, "color_secundario")


static func _color_de(clase_id: String, clave: String) -> Color:
	var dorado: Color = Color(0.95, 0.75, 0.30)
	var hex: String = str(obtener(clase_id).get(clave, ""))
	if hex.length() != 6 and hex.length() != 8:
		if hex != "":
			push_warning("[ClaseDB] color inválido '%s' en %s" % [hex, clase_id])
		return dorado
	return Color(hex)
