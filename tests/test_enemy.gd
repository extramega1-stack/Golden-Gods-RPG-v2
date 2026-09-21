extends SceneTree
## Tests headless de la Fase 4 (enemigo + ataque del jugador + oro).
##
## Cómo correrlos (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_enemy.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _botines: int = 0
var _oros: int = 0


func _init() -> void:
	print("[TEST] Fase 4 — enemigo y ataque del jugador")


var _empezo: bool = false


## El árbol de escena solo existe a partir del primer frame: los tests que
## usan posiciones/globales corren aquí, no en _init().
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_configurar()
	_t_transiciones()
	_t_objetivo_muerto()
	_t_golpear()
	_t_morir_botin_xp()
	_t_ataque_jugador()
	_t_oro()
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


func _nuevo_jugador() -> Player:
	var j: Player = PL.new(SB.new(10.0, 8.0, 6.0, 4.0))
	root.add_child(j)
	_basura.append(j)
	return j


func _nuevo_enemigo(j: Player) -> Enemy:
	var e: Enemy = EN.new()
	e.rng.seed = 4242
	e.configurar(_arquetipo())
	e.objetivo = j
	root.add_child(e)
	_basura.append(e)
	return e


func _al_botin(_drops: Array, _pos: Vector3) -> void:
	_botines += 1


func _al_oro(_oro: int) -> void:
	_oros += 1


func _t_configurar() -> void:
	var j: Player = _nuevo_jugador()
	var e: Enemy = _nuevo_enemigo(j)
	_check(e.stats.vida_max == 260.0, "configurar: vida de fuerza 8", str(e.stats.vida_max))
	_check(e.radio_aggro == 10.0, "configurar: radio_aggro")
	_check(e.rango_ataque == 2.2, "configurar: rango_ataque")
	_check(e.xp_recompensa == 50, "configurar: xp_recompensa")
	_check(e.estado == Enemy.Estado.QUIETO, "nace QUIETO")


func _t_transiciones() -> void:
	var j: Player = _nuevo_jugador()
	var e: Enemy = _nuevo_enemigo(j)
	e.position = Vector3.ZERO
	j.position = Vector3(30, 0, 0)
	e._actualizar_estado()
	_check(e.estado == Enemy.Estado.QUIETO, "lejos del aggro: QUIETO")
	j.position = Vector3(5, 0, 0)
	e._actualizar_estado()
	_check(e.estado == Enemy.Estado.PERSEGUIR, "dentro del aggro: PERSEGUIR")
	j.position = Vector3(1, 0, 0)
	e._actualizar_estado()
	_check(e.estado == Enemy.Estado.ATACAR, "dentro del rango: ATACAR")
	j.position = Vector3(5, 0, 0)
	e._actualizar_estado()
	_check(e.estado == Enemy.Estado.PERSEGUIR, "sale del rango: PERSEGUIR")
	j.position = Vector3(20, 0, 0)
	e._actualizar_estado()
	_check(e.estado == Enemy.Estado.QUIETO, "más allá del leash: QUIETO")


func _t_objetivo_muerto() -> void:
	var j: Player = _nuevo_jugador()
	var e: Enemy = _nuevo_enemigo(j)
	e.position = Vector3.ZERO
	j.position = Vector3(1, 0, 0)
	e._actualizar_estado()
	_check(e.estado == Enemy.Estado.PERSEGUIR, "pre: PERSEGUIR")
	e._actualizar_estado()
	_check(e.estado == Enemy.Estado.ATACAR, "pre: ATACAR")
	j.die()
	e._actualizar_estado()
	_check(e.estado == Enemy.Estado.QUIETO, "objetivo muerto: QUIETO")


func _t_golpear() -> void:
	var j: Player = _nuevo_jugador()
	var e: Enemy = _nuevo_enemigo(j)
	e.position = Vector3.ZERO
	j.position = Vector3(1, 0, 0)
	var vida_antes: float = j.vida_actual
	e._golpear()
	_check(j.vida_actual < vida_antes, "golpear aplica daño por fórmulas",
		"vida %f -> %f" % [vida_antes, j.vida_actual])


func _t_morir_botin_xp() -> void:
	var j: Player = _nuevo_jugador()
	var e: Enemy = _nuevo_enemigo(j)
	_botines = 0
	e.botin_generado.connect(_al_botin)
	var xp_antes: int = j.xp_actual
	e.take_damage(99999.0, j)
	_check(not e.esta_vivo(), "daño letal mata")
	_check(e.estado == Enemy.Estado.MUERTO, "estado MUERTO al morir")
	_check(_botines == 1, "botín generado una sola vez")
	_check(j.xp_actual == xp_antes + 50, "el asesino gana la XP", str(j.xp_actual))
	e.take_damage(99999.0, j)
	e.die(j)
	_check(_botines == 1, "morir dos veces no duplica el botín")


func _t_ataque_jugador() -> void:
	var j: Player = _nuevo_jugador()
	var e: Enemy = _nuevo_enemigo(j)
	j.position = Vector3.ZERO
	e.position = Vector3(1, 0, 0)
	j.objetivo_ataque = e
	j._cd_ataque = 0.0
	_check(j.puede_atacar(), "en rango y sin cooldown: puede atacar")
	var vida_antes: float = e.vida_actual
	j.ejecutar_ataque()
	_check(e.vida_actual < vida_antes, "el ataque del jugador aplica daño",
		"vida %f -> %f" % [vida_antes, e.vida_actual])
	_check(not j.puede_atacar(), "tras atacar hay cooldown")
	e.position = Vector3(30, 0, 0)
	j._cd_ataque = 0.0
	_check(not j.puede_atacar(), "fuera de rango: no puede atacar")
	e.position = Vector3(1, 0, 0)
	e.take_damage(99999.0, j)
	j._cd_ataque = 0.0
	_check(not j.puede_atacar(), "objetivo muerto: no puede atacar")
	j.objetivo_ataque = null
	_check(not j.puede_atacar(), "sin objetivo: no puede atacar")


func _t_oro() -> void:
	var j: Player = _nuevo_jugador()
	_oros = 0
	j.oro_cambiado.connect(_al_oro)
	j.ganar_oro(50)
	_check(j.oro == 50 and _oros == 1, "ganar_oro suma y emite señal")
	j.ganar_oro(-999)
	_check(j.oro == 0, "el oro nunca baja de 0")
	j.guardar_item({"tipo": "item", "item_id": "x"})
	_check(j.inventario_simple.size() == 1, "guardar_item apila datos")
