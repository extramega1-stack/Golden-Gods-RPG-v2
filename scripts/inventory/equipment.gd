class_name Equipo
extends RefCounted
## Equipo del jugador estilo FlyFF (fase 31): 12 slots.
##
## Principio de la rebuild (directriz de Juan Diego): el equipo NUNCA escribe
## stats base; solo aporta modificadores identificados por fuente
## ("equipo:<slot>:<stat>") vía StatBlock.add_mod / remove_mod. Al desequipar
## (o al reemplazar por otro item) los mods se quitan con la misma fuente.
##
## Criterio de equipable: el item trae campo "slot" válido. Los items con
## slot "pendiente"/"anillo" (genérico) ocupan el primer libre del par
## (pendiente_1/pendiente_2, anillo_1/anillo_2); si el par está lleno se
## reemplaza el primero (el viejo vuelve al inventario).

signal cambiado()

## Orden de paperdoll: izq arma/escudo, centro armadura, der accesorios.
const SLOTS: Array[String] = ["arma", "escudo", "casco", "armadura",
	"guantes", "botas", "pendiente_1", "pendiente_2", "collar",
	"anillo_1", "anillo_2", "amuleto"]
## Slots genéricos de joyería (el item dice "pendiente"/"anillo").
const SLOTS_JOYA: Dictionary = {
	"pendiente": ["pendiente_1", "pendiente_2"],
	"anillo": ["anillo_1", "anillo_2"],
}
const SAVE_VERSION: int = 1

## slot -> item_id ("" = vacío).
var _equipado: Dictionary = {}


func _init() -> void:
	for s in SLOTS:
		_equipado[s] = ""


## Nombres bonitos para la UI (paperdoll).
static func nombre_slot(slot: String) -> String:
	match slot:
		"arma":
			return "Arma"
		"escudo":
			return "Escudo"
		"casco":
			return "Casco"
		"armadura":
			return "Armadura"
		"guantes":
			return "Guantes"
		"botas":
			return "Botas"
		"pendiente_1", "pendiente_2":
			return "Pendiente"
		"collar":
			return "Collar"
		"anillo_1", "anillo_2":
			return "Anillo"
		"amuleto":
			return "Amuleto"
	return slot.capitalize()


func equipado_en(slot: String) -> String:
	return str(_equipado.get(slot, ""))


## ¿El item es equipable? Criterio fase 31: trae "slot" válido
## (directo o genérico de joyería).
static func es_equipable(item_id: String) -> bool:
	if not ItemDB.existe(item_id):
		return false
	var slot: String = str(ItemDB.obtener(item_id).get("slot", ""))
	return SLOTS.has(slot) or SLOTS_JOYA.has(slot)


## ¿El slot del item encaja en este slot concreto? (los genéricos de
## joyería encajan en cualquiera de su par).
static func slot_valido_para(item_slot: String, slot: String) -> bool:
	if item_slot == slot:
		return true
	var par: Array = SLOTS_JOYA.get(item_slot, [])
	return (par as Array).has(slot)


## Resuelve el slot destino de un item: los genéricos van al primer libre
## del par; si el par está lleno, al primero (reemplazo).
static func resolver_slot(item: Dictionary, equipado: Dictionary) -> String:
	var item_slot: String = str(item.get("slot", ""))
	var par: Array = SLOTS_JOYA.get(item_slot, [])
	if par.is_empty():
		return item_slot
	for s in par:
		if str(equipado.get(str(s), "")) == "":
			return str(s)
	return str(par[0])


## Equipa un item del inventario en su slot.
## Si el slot estaba ocupado, primero se desequipa (devuelve al inventario).
## Retorna false si el item no existe, no es equipable o no hay stock.
## No toca stats base.
func equipar(item_id: String, stats: StatBlock, inventario: Inventario) -> bool:
	if not ItemDB.existe(item_id):
		push_warning("[Equipo] item desconocido: %s" % item_id)
		return false
	var item: Dictionary = ItemDB.obtener(item_id)
	var slot: String = resolver_slot(item, _equipado)
	if not SLOTS.has(slot):
		push_warning("[Equipo] no es equipable: %s" % item_id)
		return false
	if inventario.contar(item_id) <= 0:
		push_warning("[Equipo] sin stock en inventario: %s" % item_id)
		return false
	var actual: String = str(_equipado.get(slot, ""))
	if actual != "":
		desequipar(slot, stats, inventario)
	inventario.quitar(item_id, 1)
	_equipado[slot] = item_id
	_aplicar_mods(slot, item, stats)
	cambiado.emit()
	return true


## Desequipa el slot: quita los mods (misma fuente) y devuelve al inventario.
func desequipar(slot: String, stats: StatBlock, inventario: Inventario) -> bool:
	if not SLOTS.has(slot):
		push_warning("[Equipo] slot desconocido: %s" % slot)
		return false
	var item_id: String = str(_equipado.get(slot, ""))
	if item_id == "":
		return false
	var item: Dictionary = ItemDB.obtener(item_id)
	_quitar_mods(slot, item, stats)
	_equipado[slot] = ""
	inventario.agregar(item_id, 1)
	cambiado.emit()
	return true


func _aplicar_mods(slot: String, item: Dictionary, stats: StatBlock) -> void:
	var mods: Array = item.get("mods", [])
	for m in mods:
		if not (m is Dictionary):
			continue
		var stat: String = str(m.get("stat", ""))
		if stat == "":
			continue
		stats.add_mod(_fuente(slot, stat), stat, int(m.get("kind", 0)), float(m.get("valor", 0.0)))


func _quitar_mods(slot: String, item: Dictionary, stats: StatBlock) -> void:
	var mods: Array = item.get("mods", [])
	for m in mods:
		if not (m is Dictionary):
			continue
		var stat: String = str(m.get("stat", ""))
		if stat == "":
			continue
		stats.remove_mod(_fuente(slot, stat))


static func _fuente(slot: String, stat: String) -> String:
	return "equipo:" + slot + ":" + stat


## Serialización versionada (los mods se reaplican en from_dict).
func to_dict() -> Dictionary:
	var bloque: Dictionary = {}
	for slot in SLOTS:
		bloque[slot] = equipado_en(slot)
	return {
		"version": SAVE_VERSION,
		"slots": bloque,
	}


## Reconstruye desde un dict y REAPLICA los mods al StatBlock.
## Tolera campos ausentes y slots con ids inválidos (los ignora).
static func from_dict(d: Dictionary, stats: StatBlock) -> Equipo:
	var eq: Equipo = Equipo.new()
	var slots: Dictionary = d.get("slots", {})
	for slot in SLOTS:
		var item_id: String = str(slots.get(slot, ""))
		if item_id == "" or not ItemDB.existe(item_id):
			continue
		var item: Dictionary = ItemDB.obtener(item_id)
		if not slot_valido_para(str(item.get("slot", "")), slot):
			push_warning("[Equipo] from_dict ignora %s (slot %s)" % [item_id, slot])
			continue
		eq._equipado[slot] = item_id
		eq._aplicar_mods(slot, item, stats)
	return eq
