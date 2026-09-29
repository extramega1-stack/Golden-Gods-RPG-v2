class_name CodiceDB
extends RefCounted
## Bloque 68: el códice (bestiario). Lo que YA EXISTÍA en el JSON y no se
## mostraba nunca.
##
## POR QUÉ ES BARATO Y VALE LA PENA: `data/enemies.json` tiene los 20
## arquetipos con su nombre, su lore y su tabla de drops. Toda esa
## información estaba en el repo, testeada, y NO SE MOSTRABA. Un códice es,
## literalmente, un panel que la lee. Y da al jugador dos cosas que en un
## RPG importan: saber a qué se está matando, y decidir dónde cazar
## por un drop concreto.
##
## Data-driven como todo lo demás: la información sale de los JSON, no de
## arrays en el código.

const RUTA_ENEMIGOS: String = "res://data/enemies.json"

static var _arquetipos: Dictionary = {}
static var _cargado: bool = false


static func cargar() -> void:
	if _cargado:
		return
	var texto: String = FileAccess.get_file_as_string(RUTA_ENEMIGOS)
	var d: Variant = JSON.parse_string(texto)
	if d is Dictionary:
		_arquetipos = (d as Dictionary).get("arquetipos", {})
	_cargado = true


static func ids() -> Array:
	cargar()
	return _arquetipos.keys()


static func existe(arq_id: String) -> bool:
	cargar()
	return _arquetipos.has(arq_id)


static func nombre_de(arq_id: String) -> String:
	cargar()
	if not _arquetipos.has(arq_id):
		return ""
	return str((_arquetipos[arq_id] as Dictionary).get("nombre", arq_id))


## El lore del arquetipo. La 22 le puso `descripcion` a los enemigos; si no la
## tiene, cae a la `nota` y si tampoco, al nombre.
static func lore_de(arq_id: String) -> String:
	cargar()
	if not _arquetipos.has(arq_id):
		return ""
	var a: Dictionary = _arquetipos[arq_id]
	for campo in ["lore", "descripcion", "nota"]:
		var v: String = str(a.get(campo, ""))
		if v != "":
			return v
	return nombre_de(arq_id)


## Los ids de item que suelta. Del bloque `loot` de los datos.
static func drops_de(arq_id: String) -> Array:
	cargar()
	if not _arquetipos.has(arq_id):
		return []
	var loot: Dictionary = (_arquetipos[arq_id] as Dictionary).get("loot", {})
	var out: Array = []
	for i in loot.get("items", []):
		out.append(str((i as Dictionary).get("item_id", "")))
	return out


static func nivel_de(arq_id: String) -> int:
	cargar()
	if not _arquetipos.has(arq_id):
		return 0
	return int((_arquetipos[arq_id] as Dictionary).get("nivel", 0))


## La region donde sale, para el codice "donde cazar X".
static func region_de(arq_id: String) -> String:
	cargar()
	if not _arquetipos.has(arq_id):
		return ""
	return str((_arquetipos[arq_id] as Dictionary).get("region", ""))


## La ficha completa, para pintar una fila del panel.
static func ficha(arq_id: String) -> Dictionary:
	cargar()
	if not _arquetipos.has(arq_id):
		return {}
	return {
		"id": arq_id,
		"nombre": nombre_de(arq_id),
		"lore": lore_de(arq_id),
		"drops": drops_de(arq_id),
		"nivel": nivel_de(arq_id),
		"region": region_de(arq_id),
	}


## ¿Cuántos arquetipos hay documentados? Para la cabecera del panel.
static func total() -> int:
	cargar()
	return _arquetipos.size()
