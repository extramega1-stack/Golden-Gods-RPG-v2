class_name AnclajesDB
extends RefCounted
## Tabla de anclajes del paper-doll (fase 48) — `data/anclajes.json`.
##
## Es la que el spec promete desde la fase 43 y que hasta ahora no existía:
## `slot -> {anclaje, mesh_path, offset, rotacion, escala, tinte}`. `PaperDoll`
## la lee en vez de tener offsets hardcodeados, así que:
## - Poner un modelo GLB pasa a ser RELLENAR `mesh_path` (y el `anclaje` pasa a
##   ser el nombre del hueso del modelo), no reescribir el paper-doll.
## - La `forma` (primitivas) es el respaldo procedural mientras no haya modelo.
##
## Los 85 GLB de Meshy quedaron autorizados con licencia CC0/CC-BY (Juan Diego,
## 2026-09-25) pero aún no están en el repo: por eso todos los `mesh_path`
## están vacíos y el mundo sigue siendo 100% procedural.

const RUTA: String = "res://data/anclajes.json"

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
		push_warning("[AnclajesDB] no se pudo leer " + RUTA)
		return
	var crudo: Variant = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[AnclajesDB] JSON inválido en " + RUTA)
		return
	for a in (crudo as Dictionary).get("anclajes", []):
		if not (a is Dictionary):
			continue
		var ad: Dictionary = a
		var slot: String = str(ad.get("slot", ""))
		if slot == "":
			continue
		_cache[slot] = ad
		_orden.append(slot)


## Slots con anclaje, en orden del JSON.
static func slots() -> Array[String]:
	cargar()
	return _orden.duplicate()


static func existe(slot: String) -> bool:
	cargar()
	return _cache.has(slot)


static func obtener(slot: String) -> Dictionary:
	cargar()
	return _cache.get(slot, {})


## ¿Este slot ya tiene modelo 3D? (Fase 48: ninguno todavía.)
static func tiene_malla(slot: String) -> bool:
	return str(obtener(slot).get("mesh_path", "")) != ""


## Slots que aún usan el respaldo procedural: la lista de trabajo de la fase
## que mete los modelos (el "qué falta" del pipeline de arte).
static func slots_sin_malla() -> Array[String]:
	cargar()
	var res: Array[String] = []
	for s in _orden:
		if not tiene_malla(s):
			res.append(s)
	return res


## Hueso del futuro modelo donde cuelga la pieza ("Hand.R", "Head"...).
static func anclaje_de(slot: String) -> String:
	return str(obtener(slot).get("anclaje", ""))


static func offset_de(slot: String) -> Vector3:
	var o: Array = obtener(slot).get("offset", [])
	if o.size() < 3:
		return Vector3.ZERO
	return Vector3(float(o[0]), float(o[1]), float(o[2]))


static func rotacion_de(slot: String) -> Vector3:
	var o: Array = obtener(slot).get("rotacion", [])
	if o.size() < 3:
		return Vector3.ZERO
	return Vector3(float(o[0]), float(o[1]), float(o[2]))


static func escala_de(slot: String) -> float:
	return float(obtener(slot).get("escala", 1.0))


## Tinte por defecto del slot ("#b3b8c7" -> Color). Gris si no está.
static func tinte_de(slot: String) -> Color:
	var hex: String = str(obtener(slot).get("tinte", ""))
	if hex == "":
		return Color(0.7, 0.7, 0.7)
	return Color.from_string(hex, Color(0.7, 0.7, 0.7))


## La forma procedural del respaldo (el "qué se dibuja mientras no hay GLB").
static func forma_de(slot: String) -> Dictionary:
	return obtener(slot).get("forma", {})
