class_name Equipo
extends RefCounted
## Equipo del jugador: slots "arma" y "armadura".
##
## Principio de la rebuild (directriz de Juan Diego): el equipo NUNCA escribe
## stats base; solo aporta modificadores identificados por fuente
## ("equipo:<slot>:<stat>") vía StatBlock.add_mod / remove_mod. Al desequipar
## (o al reemplazar por otro item) los mods se quitan con la misma fuente.

signal cambiado()

const SLOTS: Array[String] = ["arma", "armadura"]
const SAVE_VERSION: int = 1

## slot -> item_id ("" = vacío).
var _equipado: Dictionary = {"arma": "", "armadura": ""}


func equipado_en(slot: String) -> String:
	return str(_equipado.get(slot, ""))


## Equipa un item del inventario en su slot.
## Si el slot estaba ocupado, primero se desequipa (devuelve al inventario).
## Retorna false si el item no existe, no es arma/armadura, su slot es
## inválido o no hay stock en el inventario. No toca stats base.
func equipar(item_id: String, stats: StatBlock, inventario: Inventario) -> bool:
	if not ItemDB.existe(item_id):
		push_warning("[Equipo] item desconocido: %s" % item_id)
		return false
	var item: Dictionary = ItemDB.obtener(item_id)
	var tipo: String = str(item.get("tipo", ""))
	if tipo != "arma" and tipo != "armadura":
		push_warning("[Equipo] no es equipable: %s" % item_id)
		return false
	var slot: String = str(item.get("slot", ""))
	if not SLOTS.has(slot):
		push_warning("[Equipo] slot inválido '%s' para %s" % [slot, item_id])
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
	return {
		"version": SAVE_VERSION,
		"slots": {"arma": equipado_en("arma"), "armadura": equipado_en("armadura")},
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
		if str(item.get("slot", "")) != slot:
			push_warning("[Equipo] from_dict ignora %s (slot %s)" % [item_id, slot])
			continue
		eq._equipado[slot] = item_id
		eq._aplicar_mods(slot, item, stats)
	return eq
