extends SceneTree
## Tests headless de la Fase 9.3 (pedido de Juan Diego: al morir un mob no
## queda seleccionado y el jugador nunca camina a su cadáver).
##
## (a) Matar el mob seleccionado limpia la selección (y emite null).
## (b) Pulsar T tras matar, con solo el cadáver cerca: no fija objetivo
##     muerto ni ordena caminar hacia él.
## (c) Skill dañina pendiente cuyo objetivo muere antes del casteo: se
##     cancela el pendiente Y la orden de acercarse (no camina al cadáver).
## (d) Skill cuyo casteo mata al objetivo: no sigue caminando al cadáver.
## (e) Skill tras matar (sin selección): no fija objetivo muerto ni camina.
## (f) Clic sobre un cadáver (`_clic_en_vacio`): deselecciona sin mover.
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase93.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const SDB: GDScript = preload("res://scripts/skills/skill_db.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _sel_count: int = 0
var _sel_ultima: Entity = null


func _init() -> void:
	print("[TEST] Fase 9.3 — el muerto no queda seleccionado, nadie camina al cadaver")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	SDB.cargar()
	_t_matar_limpia_seleccion()
	_t_tras_matar_no_camina()
	_t_skill_pendiente_muere_no_camina()
	_t_skill_casteo_mata_no_camina()
	_t_skill_tras_matar_no_fija_muerto()
	_t_clic_cadaver_no_mueve()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
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


func _al_seleccion(e: Entity) -> void:
	_sel_count += 1
	_sel_ultima = e


func _player(pos: Vector3) -> Player:
	var p: Player = PL.new()
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


func _enemigo(pos: Vector3) -> Enemy:
	var e: Enemy = EN.new()
	e.add_to_group("enemigos")
	root.add_child(e)
	e.global_position = pos
	_basura.append(e)
	return e


func _frames(p: Player, n: int) -> void:
	for i in n:
		p._physics_process(0.016)


## (a) Matar el mob seleccionado limpia la selección (emite null).
func _t_matar_limpia_seleccion() -> void:
	var p: Player = _player(Vector3.ZERO)
	p.seleccion_cambiada.connect(_al_seleccion)
	_sel_count = 0
	var e: Enemy = _enemigo(Vector3(2, 0, 0))
	p.seleccionar(e)
	p.solicitar_ataque()
	_check(p.seleccion == e and p.objetivo_ataque == e, "setup: seleccionado y con objetivo", "")
	e.take_damage(999999.0, p)
	_frames(p, 5)
	_check(p.seleccion == null, "matar limpia la seleccion", "")
	_check(_sel_ultima == null, "matar emite seleccion_cambiada(null)", "")
	_check(p.objetivo_ataque == null, "matar limpia el objetivo de ataque", "")


## (b) T tras matar, con solo el cadáver cerca: nada que atacar, nada que caminar.
func _t_tras_matar_no_camina() -> void:
	var p: Player = _player(Vector3.ZERO)
	var e: Enemy = _enemigo(Vector3(2, 0, 0))
	p.seleccionar(e)
	p.solicitar_ataque()
	e.take_damage(999999.0, p)
	_frames(p, 5)
	# Solo queda el cadáver a 2 m: T no debe fijarlo ni caminar hacia él.
	p.solicitar_ataque()
	_check(p.objetivo_ataque == null, "T tras matar no fija objetivo muerto", "")
	_check(not p._tiene_destino, "T tras matar no ordena caminar al cadaver", "")


## (c) Skill pendiente cuyo objetivo muere antes del casteo: se cancela todo.
func _t_skill_pendiente_muere_no_camina() -> void:
	var p: Player = _player(Vector3.ZERO)
	var e: Enemy = _enemigo(Vector3(20, 0, 0))
	p.seleccionar(e)
	p.lanzar_skill_id("bola_fuego")  # Bola de fuego, rango 12 < 20: queda pendiente y camina.
	_check(p.tiene_lanzamiento_pendiente(), "setup: skill pendiente", "")
	_check(p._tiene_destino, "setup: caminando a castear", "")
	e.take_damage(999999.0, p)
	_frames(p, 5)
	_check(not p.tiene_lanzamiento_pendiente(), "muerte cancela el pendiente", "")
	_check(not p._tiene_destino, "muerte cancela la orden de acercarse", "")
	_check(p.objetivo_ataque == null, "muerte no deja objetivo pendiente", "")


## (d) El casteo mata al objetivo: no sigue caminando al cadáver.
func _t_skill_casteo_mata_no_camina() -> void:
	var p: Player = _player(Vector3.ZERO)
	var e: Enemy = _enemigo(Vector3(20, 0, 0))
	e.vida_actual = 1.0  # la bola lo one-shotea
	p.seleccionar(e)
	p.lanzar_skill_id("bola_fuego")  # pendiente, camina hacia él
	p.global_position = Vector3(10, 0, 0)  # dentro del rango: castea
	_frames(p, 5)
	_check(not e.esta_vivo(), "setup: el casteo lo mato", "")
	_check(not p._tiene_destino, "tras el casteo mortal no camina al cadaver", "")
	_check(p.seleccion == null, "tras el casteo mortal no queda seleccionado", "")


## (e) Skill tras matar (sin selección): no fija objetivo muerto ni camina.
func _t_skill_tras_matar_no_fija_muerto() -> void:
	var p: Player = _player(Vector3.ZERO)
	var e: Enemy = _enemigo(Vector3(2, 0, 0))
	p.seleccionar(e)
	e.take_damage(999999.0, p)
	_frames(p, 5)
	p.lanzar_skill_id("bola_fuego")
	_check(not p.tiene_lanzamiento_pendiente(), "skill tras matar no deja pendiente", "")
	_check(not p._tiene_destino, "skill tras matar no ordena caminar", "")
	_check(p.objetivo_ataque == null, "skill tras matar no fija objetivo", "")


## (f) Clic sobre un cadáver: deselecciona sin ordenar moverse.
func _t_clic_cadaver_no_mueve() -> void:
	var p: Player = _player(Vector3.ZERO)
	var e: Enemy = _enemigo(Vector3(2, 0, 0))
	var otro: Enemy = _enemigo(Vector3(30, 0, 0))
	p.seleccionar(otro)
	e.take_damage(999999.0, p)
	# Simula la rama de cadáver de _clic_izquierdo (el rayo necesita cámara).
	p._clic_en_vacio()
	_check(p.seleccion == null, "clic en cadaver deselecciona", "")
	_check(p.objetivo_ataque == null, "clic en cadaver quita objetivo", "")
	_check(not p._tiene_destino, "clic en cadaver no ordena moverse", "")
