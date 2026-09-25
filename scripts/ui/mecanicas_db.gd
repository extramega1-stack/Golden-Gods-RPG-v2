class_name MecanicasDB
extends RefCounted
## Contenido del manual de ayuda (fase 46) — `data/mecanicas.json`.
## Mismas reglas que el resto de DBs: carga idempotente, ids en orden del JSON
## y lecturas tolerantes. La columna de CONTROLES no vive aquí: se lee del
## Input Map en runtime (`PanelAyuda.lista_controles`), para que no pueda
## desincronizarse de las teclas reales.

const RUTA: String = "res://data/mecanicas.json"

static var _cache: Array[Dictionary] = []
static var _cargado: bool = false


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	_cache.clear()
	var texto: String = FileAccess.get_file_as_string(RUTA)
	if texto.is_empty():
		push_warning("[MecanicasDB] no se pudo leer " + RUTA)
		return
	var crudo: Variant = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[MecanicasDB] JSON inválido en " + RUTA)
		return
	for s in (crudo as Dictionary).get("secciones", []):
		if s is Dictionary:
			_cache.append(s as Dictionary)


## Secciones en orden del JSON. Cada una: {id, titulo, entradas: [{titulo,
## texto, teclas}]}.
static func secciones() -> Array[Dictionary]:
	cargar()
	return _cache.duplicate()


static func total_entradas() -> int:
	cargar()
	var n: int = 0
	for s in _cache:
		n += (s.get("entradas", []) as Array).size()
	return n
