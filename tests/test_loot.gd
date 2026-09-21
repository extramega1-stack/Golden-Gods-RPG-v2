extends SceneTree
## Tests headless de la Fase 4 (tablas de botín + pickups).
##
## Cómo correrlos (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_loot.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const DT: GDScript = preload("res://scripts/loot/drop_table.gd")
const PK: GDScript = preload("res://scripts/loot/pickup.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _recogidos: int = 0


func _init() -> void:
	print("[TEST] Fase 4 — loot")
	_t_determinista()
	_t_oro_en_rango()
	_t_items_prob()
	_t_tabla_vacia()


var _empezo: bool = false


## Los pickups necesitan el árbol (get_tree); corren en el primer frame.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_pickup()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
	return true


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


func _nueva_rng(semilla: int) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = semilla
	return r


func _tabla() -> Dictionary:
	return {
		"oro_min": 5, "oro_max": 10,
		"items": [
			{"item_id": "pocion", "nombre": "Poción", "prob": 1.0, "min": 1, "max": 2},
			{"item_id": "nunca", "nombre": "Nunca", "prob": 0.0, "min": 1, "max": 1},
		],
	}


func _t_determinista() -> void:
	var a: Array = DT.roll_drops(_tabla(), _nueva_rng(7))
	var b: Array = DT.roll_drops(_tabla(), _nueva_rng(7))
	_check(str(a) == str(b), "misma semilla → mismos drops", str(a))


func _t_oro_en_rango() -> void:
	var drops: Array = DT.roll_drops(_tabla(), _nueva_rng(11))
	var oro: int = -1
	for d in drops:
		var dd: Dictionary = d
		if str(dd.get("tipo", "")) == "oro":
			oro = int(dd.get("cantidad", -1))
	_check(oro >= 5 and oro <= 10, "oro dentro de [min, max]", str(oro))


func _t_items_prob() -> void:
	var drops: Array = DT.roll_drops(_tabla(), _nueva_rng(13))
	var ids: Array = []
	for d in drops:
		var dd: Dictionary = d
		if str(dd.get("tipo", "")) == "item":
			ids.append(str(dd.get("item_id", "")))
			var c: int = int(dd.get("cantidad", 0))
			_check(c >= 1 and c <= 2, "cantidad de item en [min, max]", str(c))
	_check(ids.has("pocion"), "prob 1.0 siempre cae")
	_check(not ids.has("nunca"), "prob 0.0 nunca cae")


func _t_tabla_vacia() -> void:
	var drops: Array = DT.roll_drops({}, _nueva_rng(1))
	_check(drops.is_empty(), "tabla vacía → sin drops")


func _al_recogido(_drop: Dictionary) -> void:
	_recogidos += 1


func _t_pickup() -> void:
	var j: Player = PL.new(SB.new(10.0, 8.0, 6.0, 4.0))
	root.add_child(j)
	j.add_to_group("jugador")
	j.position = Vector3(1, 0, 0)
	_basura.append(j)
	var p: Pickup = PK.new()
	p.drop = {"tipo": "oro", "cantidad": 10}
	_recogidos = 0
	p.recogido.connect(_al_recogido)
	root.add_child(p)
	p.position = Vector3.ZERO
	p._revisar_recogida()
	_check(_recogidos == 1, "pickup emite recogido por proximidad")
	_check(p.is_queued_for_deletion(), "pickup se destruye al recogerse")
	var p2: Pickup = PK.new()
	p2.drop = {"tipo": "oro", "cantidad": 10}
	root.add_child(p2)
	_basura.append(p2)
	p2.position = Vector3(50, 0, 0)
	p2._revisar_recogida()
	_check(_recogidos == 1, "lejos no se recoge")
