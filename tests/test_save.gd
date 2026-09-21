extends SceneTree
## Tests headless de la Fase 4 (save/load versionado y tolerante).
##
## Cómo correrlos (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_save.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)
## Usa user://partida.json y lo borra al final (no toca partidas reales del
## editor: el headless usa su propio user://).

const SS: GDScript = preload("res://scripts/save/save_system.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _botines: int = 0


func _init() -> void:
	print("[TEST] Fase 4 — save/load")
	_t_sin_partida()


var _empezo: bool = false


## El round-trip necesita el árbol (posiciones globales); primer frame.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_round_trip()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).free()
	# Limpieza: el test no deja archivo detrás.
	DirAccess.remove_absolute("user://partida.json")
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


func _al_botin(_drops: Array, _pos: Vector3) -> void:
	_botines += 1


func _arquetipo() -> Dictionary:
	return {
		"nombre": "Dummy",
		"color": [0.8, 0.2, 0.2],
		"fuerza": 8.0, "agilidad": 6.0, "destreza": 4.0, "inteligencia": 2.0,
		"radio_aggro": 10.0, "rango_ataque": 2.2, "cooldown_ataque": 1.5,
		"xp": 50,
		"oro_min": 5, "oro_max": 10,
		"loot": {"items": []},
	}


func _t_sin_partida() -> void:
	DirAccess.remove_absolute("user://partida.json")
	var s: SaveSystem = SS.new()
	_check(not s.hay_partida(), "sin archivo: hay_partida() es false")
	_check(not s.cargar(), "sin archivo: cargar() es false")


func _t_round_trip() -> void:
	var j: Player = PL.new(SB.new(10.0, 8.0, 6.0, 4.0))
	root.add_child(j)
	_basura.append(j)
	var e: Enemy = EN.new()
	e.rng.seed = 99
	e.configurar(_arquetipo())
	e.objetivo = j
	root.add_child(e)
	_basura.append(e)
	e.botin_generado.connect(_al_botin)

	var s: SaveSystem = SS.new()
	s.jugador = j
	s.enemigos = [e]

	# Estado a guardar: jugador herido con oro y posición; enemigo muerto.
	j.take_damage(80.0, null)
	j.ganar_oro(75)
	j.guardar_item({"tipo": "item", "item_id": "x"})
	j.position = Vector3(3, 0, 4)
	e.position = Vector3(6, 0, -6)
	_botines = 0
	e.take_damage(99999.0, j)
	_check(_botines == 1, "pre: el botín se generó al morir")

	_check(s.guardar(), "guardar() retorna true")
	_check(s.hay_partida(), "hay_partida() true tras guardar")

	# Se modifica todo para probar que la carga restaura.
	j.heal(9999.0)
	j.oro = 0
	j.inventario_simple = []
	j.position = Vector3.ZERO

	_check(s.cargar(), "cargar() retorna true")
	_check(j.vida_actual == 220.0, "vida restaurada", str(j.vida_actual))
	_check(j.oro == 75, "oro restaurado", str(j.oro))
	_check(j.inventario_simple.size() == 1, "items restaurados")
	_check(j.position == Vector3(3, 0, 4), "posición restaurada", str(j.position))
	_check(not e.esta_vivo(), "el enemigo sigue muerto tras cargar")
	_check(e.estado == Enemy.Estado.MUERTO, "estado MUERTO tras cargar")
	_check(e.position == Vector3(6, 0, -6), "posición del enemigo restaurada")
	_check(_botines == 1, "cargar no re-emite el botín")
