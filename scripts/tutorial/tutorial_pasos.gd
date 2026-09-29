class_name TutorialPasos
extends RefCounted
## FASE 69 — los pasos del tutorial como DATOS (`data/tutorial.json`).
##
## Por qué existe: antes los 6 textos vivían en un `const Array` dentro de
## `tutorial.gd`. Para cambiar lo que un jugador nuevo ve al arrancar había
## que tocar código (y recompilar), y el §11 del spec dice lo contrario:
## "datos primero". Este es el único archivo que hay que tocar para reescribir
## el tutorial.
##
## PURA salvo `cargar()`. No lee el árbol, no mira al jugador, no emite
## señales: solo valida y devuelve diccionarios. El `Tutorial` es quien decide
## qué hacer con ellos.

const RUTA: String = "res://data/tutorial.json"

## Tipos de objetivo válidos. Un tipo desconocido NO se rompe: `paso()` lo
## deja pasar y `Tutorial` lo trata como "ninguno" (sin marca en el mundo).
## Un tutorial roto no puede impedir jugar.
const TIPOS_OBJETIVO: Array[String] = ["punto", "npc", "mob", "ninguno"]

## `Tutorial.PASOS` (la constante que el test de la fase 39 y el save leen)
## sale de acá. La clase `Tutorial` la carga en su `_init` y por eso los dos
## caminos de datos nunca divergen.
static var _pasos: Array[Dictionary] = []
static var _titulo: String = "Primeros 5 minutos"
static var _cierre: Dictionary = {}
static var _cargado: bool = false


## Lee el JSON. Idempotente: la segunda llamada no vuelve a leer el disco.
## Devuelve false si el archivo falta o no tiene pasos (el Tutorial avisa).
static func cargar(ruta: String = RUTA) -> bool:
	if _cargado:
		return not _pasos.is_empty()
	_cargado = true
	_pasos.clear()
	_cierre = {}
	var texto: String = FileAccess.get_file_as_string(ruta)
	if texto.is_empty():
		push_warning("[TutorialPasos] no se pudo leer " + ruta)
		return false
	var crudo: Variant = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[TutorialPasos] JSON inválido: " + ruta)
		return false
	var datos: Dictionary = crudo
	_titulo = str(datos.get("titulo", _titulo))
	var cierre: Variant = datos.get("cierre", {})
	if cierre is Dictionary:
		_cierre = cierre
	for p in datos.get("pasos", []):
		if not (p is Dictionary):
			continue
		var pd: Dictionary = p
		var pid: String = str(pd.get("id", ""))
		if pid == "":
			continue
		_pasos.append(_normalizar(pd))
	return not _pasos.is_empty()


## Copia del paso con todos los campos con valor por defecto. Así el código
## que lo lee NUNCA hace `.get()` sobre algo que puede faltar: es lo mismo
## que el `configurar(datos)` de `NPC` (tolerante por diseño).
static func _normalizar(d: Dictionary) -> Dictionary:
	var paso: Dictionary = {
		"id": str(d.get("id", "")),
		"texto": str(d.get("texto", "")),
		"detalle": str(d.get("detalle", "")),
		"regalo": str(d.get("regalo", "")),
		"objetivo": _objetivo_de(d.get("objetivo", {})),
	}
	return paso


## El objetivo, ya normalizado a la forma que consume `Tutorial`:
## {"tipo": String, "x": float, "z": float, "npc": String, "arquetipo": String}
static func _objetivo_de(v: Variant) -> Dictionary:
	var base: Dictionary = {
		"tipo": "ninguno", "x": 0.0, "z": 0.0,
		"npc": "", "arquetipo": "",
	}
	if not (v is Dictionary):
		return base
	var d: Dictionary = v
	base["tipo"] = str(d.get("tipo", "ninguno"))
	if not TIPOS_OBJETIVO.has(str(base["tipo"])):
		push_warning("[TutorialPasos] tipo de objetivo desconocido: '%s'"
			% str(base["tipo"]))
		base["tipo"] = "ninguno"
	base["x"] = float(d.get("x", 0.0))
	base["z"] = float(d.get("z", 0.0))
	base["npc"] = str(d.get("npc", ""))
	base["arquetipo"] = str(d.get("arquetipo", ""))
	return base


## Copia de los pasos. `Tutorial.PASOS` la expone: se llama una vez al
## cargar, no por frame.
static func pasos() -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	for p in _pasos:
		salida.append(p.duplicate(true))
	return salida


static func cantidad() -> int:
	return _pasos.size()


## El paso del índice, o {} si el índice se pasó.
static func paso(indice: int) -> Dictionary:
	if indice < 0 or indice >= _pasos.size():
		return {}
	return _pasos[indice].duplicate(true)


static func indice_de(id: String) -> int:
	for i in range(_pasos.size()):
		if str(_pasos[i].get("id", "")) == id:
			return i
	return -1


static func titulo() -> String:
	return _titulo


## Texto de cierre ("¡Listo!") y su detalle de a dónde ir ahora.
static func cierre() -> Dictionary:
	return _cierre.duplicate()


static func texto_cierre() -> String:
	return str(_cierre.get("texto", ""))


static func detalle_cierre() -> String:
	return str(_cierre.get("detalle", ""))


## Test/dev: olvidarse lo cargado para releer el disco.
static func olvidar() -> void:
	_cargado = false
	_pasos.clear()
	_cierre = {}
