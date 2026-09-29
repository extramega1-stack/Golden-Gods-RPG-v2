class_name AfijosLoot
extends RefCounted
## La política de afijos en el CAMINO REAL del drop (punto 4 del bloque 68).
##
## POR QUÉ EXISTE: `Afijos` (el bloque 68) sabe GENERAR afijos y el panel sabe
## COMPARARLOS, pero entre medias faltaba el paso corto que falta: decidir si
## un item que CAE lleva afijos, cuántos y de qué rareza. Eso es lo que hace
## este script, y solo eso. `Afijos` no cambia: aquí se la llama.
##
## - DATA-DRIVEN: la probabilidad por rareza, el tope por item y los tipos que
##   pueden llevarlos viven en `data/afijos_loot.json`. Cambiar el balance del
##   loot afijado es editar un número, no recompilar.
## - EL TECHO LO MANDA EL ITEM, NO EL SORTEO: un afijo nunca puede ser más
##   raro que el item que lo lleva. Se cumple por construcción (se genera con
##   la escala del item), no con un `if` de kinder.
## - SOLO EQUIPABLES: un afijo de +fuerza en un colmillo o en una poción es
##   ruido. Y sobre todo: los apilables se fusionan por `item_id`, así que dos
##   items con afijos distintos en la misma pila serían indistinguibles. Los
##   afijos solo van a `arma`/`armadura`/`accesorio`, que nunca se apilan.
## - DETERMINISTA POR SEMILLA: el mismo mob con el mismo RNG suelta el mismo
##   item afijado. Se consume UNA sola vez el RNG de la muerte (la semilla), y
##   la tirada de probabilidad sale de un RNG local derivado de ella.
##
## Lo único que NO hace es escribir en el inventario: eso es de `Inventario`.
## Y lo único que no decide es el valor del afijo, que es de `Afijos`.

const RUTA: String = "res://data/afijos_loot.json"

static var _datos: Dictionary = {}
static var _cargado: bool = false


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	var texto: String = FileAccess.get_file_as_string(RUTA)
	if texto == "":
		push_warning("[AfijosLoot] no se pudo leer %s: el loot cae sin afijos" % RUTA)
		return
	var d: Variant = JSON.parse_string(texto)
	if d is Dictionary:
		_datos = d as Dictionary


## ¿Este item puede llevar afijos? False = ni se tira el RNG por él, así que un
## loot de solo materiales o consumibles se comporta EXACTAMENTE como antes.
static func admite(item_id: String) -> bool:
	cargar()
	if _datos.is_empty() or item_id == "":
		return false
	if not ItemDB.existe(item_id):
		return false
	var tipos: Array = _datos.get("tipos_con_afijos", [])
	return tipos.has(str(ItemDB.obtener(item_id).get("tipo", "")))


## La escala 1..5 del item (de `rareza` en items.json). Es el TECHO de rareza
## de sus afijos. 0 = el item no admite afijos.
static func escala_de_item(item_id: String) -> int:
	if not admite(item_id):
		return 0
	var item: Dictionary = ItemDB.obtener(item_id)
	var mapa: Dictionary = _datos.get("rarezas_item", {})
	var escala: int = int(mapa.get(str(item.get("rareza", "")),
		int(_datos.get("rareza_por_defecto", 1))))
	return clampi(escala, 1, Afijos.RAREZAS.size())


static func prob_para(escala: int) -> float:
	cargar()
	var probs: Dictionary = _datos.get("prob_por_rareza", {})
	var p: float = float(probs.get(str(clampi(escala, 1, Afijos.RAREZAS.size())),
		float(_datos.get("prob_por_defecto", 0.0))))
	return clampf(p, 0.0, 1.0)


## Cuántos afijos lleva como máximo un item de esa rareza. `afijos_extra` es
## el margen del NG+ (prestigio): sube el tope, nunca el techo de rareza.
static func tope_para(escala: int, afijos_extra: int = 0) -> int:
	cargar()
	var topes: Dictionary = _datos.get("tope_por_rareza", {})
	var base: int = int(topes.get(str(clampi(escala, 1, Afijos.RAREZAS.size())),
		int(_datos.get("tope_por_defecto", 1))))
	var n: int = base + maxi(0, afijos_extra)
	return clampi(n, 0, int(_datos.get("tope_maximo", Afijos.RAREZAS.size())))


## LA FUNCIÓN QUE CONECTA EL LOOT. Devuelve los afijos de un item que cae, o
## `[]` si cae sin afijos. Consume UNA vez `rng` (la semilla) y solo si el item
## admite afijos: un loot de materiales deja intacto el stream del RNG.
static func generar_para_item(item_id: String, rng: RandomNumberGenerator,
		nivel: int = 0, afijos_extra: int = 0) -> Array:
	if rng == null or not admite(item_id):
		return []
	var escala: int = escala_de_item(item_id)
	var tope: int = tope_para(escala, afijos_extra)
	if tope <= 0:
		return []
	var semilla: int = rng.randi()
	# RNG local: la probabilidad se tira una vez por item, pero NO avanza el
	# stream del mob (si no, un +fuerza cambiaría en secreto la tirada de oro
	# del siguiente item, y el loot dejaría de ser reproducible).
	var local := RandomNumberGenerator.new()
	local.seed = semilla
	if local.randf() >= prob_para(escala):
		return []
	var afijos: Array = Afijos.generar_varios("", escala, semilla, nivel)
	if afijos.size() > tope:
		return afijos.slice(0, tope)
	return afijos
