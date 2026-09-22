extends SceneTree
## Tests headless de la Fase 10 (auto-ataque persistente, pedido de Juan Diego:
## "yo selecciono una habilidad y cuando llega le pega, el personaje le sigue
## atacando al mob").
##
## (a) Skill dañina en rango: fija objetivo_ataque y los básicos se repiten
##     solos tras el casteo, sin más input.
## (b) Skill dañina fuera de rango: queda pendiente, al llegar castea y
##     DESPUÉS sigue pegando básicos (el caso literal del pedido).
## (c) T sobre un mob: los golpes se repiten sin más input.
## (d) El objetivo se aleja: el destino lo sigue y al volver a rango retoma.
## (e) El objetivo muere en el bucle: se detiene, deselecciona y no camina
##     al cadáver (compatible con fase 9.3).
## (f) Orden de mover cancela el bucle: no hay más golpes.
## (g) Doble clic (modelo Flyff) inicia el bucle persistente.
## (h) La curación no fija objetivo ni mueve (no interfiere con el combate).
##
## NOTA del harness: move_and_slide() no integra movimiento real en --script
## (ver test_seleccion.gd): las llegadas se simulan teletransportando; el
## movimiento físico lo cubren test_player + el playtest de Juan Diego.
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase10.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const SDB: GDScript = preload("res://scripts/skills/skill_db.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []
var _golpes: int = 0
var _p_foco: Player = null
var _usadas: Array = []


func _init() -> void:
	print("[TEST] Fase 10 — auto-ataque persistente: tras el primer golpe el heroe sigue solo")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	SDB.cargar()
	_t_skill_en_rango_retoma()
	_t_ataque_t_persiste()
	_t_skill_lejos_castea_y_sigue()
	_t_objetivo_se_aleja_lo_persigue()
	_t_muerte_detiene_bucle()
	_t_orden_mover_cancela()
	_t_doble_clic_inicia_bucle()
	_t_curacion_no_altera_combate()
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


func _al_daniado(_cantidad: float, fuente: Entity) -> void:
	if fuente == _p_foco:
		_golpes += 1


func _al_usada(skill_id: String) -> void:
	_usadas.append(skill_id)


func _player(pos: Vector3) -> Player:
	var p: Player = PL.new()
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


func _enemigo(pos: Vector3, vida: float = 100000.0) -> Enemy:
	var e: Enemy = EN.new()
	e.add_to_group("enemigos")
	root.add_child(e)
	e.global_position = pos
	e.vida_actual = vida
	e.daniado.connect(_al_daniado)
	_basura.append(e)
	return e


func _frames(p: Player, n: int) -> void:
	for i in n:
		p._physics_process(0.016)


func _contar_desde(p: Player) -> void:
	_p_foco = p
	_golpes = 0


## (a) Skill dañina en rango: el casteo fija el objetivo y los básicos
## siguen solos. golpe_heroico = índice 0, rango 3.0.
func _t_skill_en_rango_retoma() -> void:
	var p: Player = _player(Vector3.ZERO)
	var e: Enemy = _enemigo(Vector3(2, 0, 0))
	_contar_desde(p)
	p.mana_actual = 999.0
	p.seleccionar(e)
	p.lanzar_skill(0)
	_check(p.objetivo_ataque == e, "skill en rango fija objetivo_ataque", "")
	_frames(p, 200) # ~3.2 s -> 1 skill + ~4 basicos a 1.08/s
	_check(_golpes >= 4, "tras el casteo los basicos se repiten solos",
		"golpes=%d" % _golpes)


## (c) T sobre un mob: sin más input, los golpes se repiten.
func _t_ataque_t_persiste() -> void:
	var p: Player = _player(Vector3(200, 0, 200))
	var e: Enemy = _enemigo(Vector3(200, 0, 202))
	_contar_desde(p)
	p.seleccionar(e)
	p.solicitar_ataque()
	_frames(p, 200)
	_check(_golpes >= 3, "T inicia un bucle que se repite solo",
		"golpes=%d" % _golpes)


## (b) El caso literal del pedido: skill fuera de rango -> pendiente ->
## al llegar castea -> DESPUÉS sigue pegando básicos.
## bola_fuego por id (fase 17), rango 12. El hotbar lanzar_skill(i) es por
## clase desde la fase 18; la mecánica de pendiente se prueba con el id.
func _t_skill_lejos_castea_y_sigue() -> void:
	var p: Player = _player(Vector3(100, 0, 100))
	var e: Enemy = _enemigo(Vector3(100, 0, 120))
	_contar_desde(p)
	p.mana_actual = 999.0
	p.skills.skill_usada.connect(_al_usada)
	_usadas.clear()
	p.seleccionar(e)
	p.lanzar_skill_id("bola_fuego") # a 20 m > rango 12: pendiente y camina
	_check(p.tiene_lanzamiento_pendiente(), "setup: skill pendiente", "")
	_check(p.objetivo_ataque == e, "el pendiente ya fija objetivo_ataque", "")
	# Simulamos la llegada al rango del skill (el harness no integra
	# movimiento; el movimiento real lo cubre el playtest).
	p.global_position = Vector3(100, 0, 112) # a 8 m: dentro del rango 12
	_frames(p, 5)
	_check(not p.tiene_lanzamiento_pendiente(), "al llegar al rango castea", "")
	_check(_usadas.has("bola_fuego"), "se lanzo la bola_fuego", "")
	var g0: int = _golpes
	_check(g0 >= 1, "el casteo pego", "")
	# Ahora a rango cuerpo a cuerpo: los básicos deben seguir solos.
	p.global_position = e.global_position + Vector3(2, 0, 0)
	_frames(p, 120) # ~1.9 s -> ~2 basicos
	_check(_golpes > g0, "tras el casteo sigue pegando basicos solo",
		"antes=%d despues=%d" % [g0, _golpes])


## (d) Si el objetivo se aleja, el destino lo sigue; al volver a rango,
## retoma los golpes sin más input.
func _t_objetivo_se_aleja_lo_persigue() -> void:
	var p: Player = _player(Vector3(300, 0, 300))
	var e: Enemy = _enemigo(Vector3(300, 0, 302))
	_contar_desde(p)
	p.seleccionar(e)
	p.solicitar_ataque()
	_frames(p, 30)
	var g0: int = _golpes
	_check(g0 >= 1, "setup: ya estaba pegando", "")
	e.global_position = Vector3(300, 0, 312) # huye a 10 m
	_frames(p, 3)
	_check(p._tiene_destino, "al alejarse retoma la persecucion", "")
	_check(p._destino.distance_to(e.global_position) < 1.0,
		"el destino sigue al objetivo que huye", "")
	p.global_position = e.global_position + Vector3(2, 0, 0) # de vuelta a rango
	_frames(p, 60)
	_check(_golpes > g0, "al volver a rango retoma los golpes",
		"antes=%d despues=%d" % [g0, _golpes])


## (e) El bucle mata al objetivo: se detiene, deselecciona y el jugador
## no camina al cadáver (compatible con fase 9.3).
func _t_muerte_detiene_bucle() -> void:
	var p: Player = _player(Vector3(400, 0, 400))
	var e: Enemy = _enemigo(Vector3(400, 0, 402), 150.0)
	p.seleccionar(e)
	p.solicitar_ataque()
	var muerto: bool = false
	for i in 300:
		p._physics_process(0.016)
		if not e.esta_vivo():
			muerto = true
			break
	_check(muerto, "el bucle de auto-ataque lo mato", "")
	_frames(p, 5) # la limpieza (deselección) corre en los frames siguientes
	_check(p.objetivo_ataque == null, "al morir se suelta el objetivo", "")
	_check(p.seleccion == null, "al morir se deselecciona", "")
	var pos: Vector3 = p.global_position
	_frames(p, 60)
	_check(pos.distance_to(p.global_position) < 0.01,
		"muerto el objetivo, el heroe no camina al cadaver", "")


## (f) Una orden de mover cancela el bucle: no hay más golpes.
func _t_orden_mover_cancela() -> void:
	var p: Player = _player(Vector3(500, 0, 500))
	var e: Enemy = _enemigo(Vector3(500, 0, 502))
	_contar_desde(p)
	p.seleccionar(e)
	p.solicitar_ataque()
	_frames(p, 30)
	var g0: int = _golpes
	_check(g0 >= 1, "setup: estaba pegando", "")
	p._orden_mover_punto(Vector3(500, 0, 530)) # clic en suelo
	_check(p.objetivo_ataque == null, "la orden de mover suelta el objetivo", "")
	_frames(p, 90)
	_check(_golpes == g0, "tras la orden no hay mas golpes",
		"antes=%d despues=%d" % [g0, _golpes])


## (g) El doble clic (modelo Flyff) inicia el mismo bucle persistente.
func _t_doble_clic_inicia_bucle() -> void:
	var p: Player = _player(Vector3(600, 0, 600))
	var e: Enemy = _enemigo(Vector3(600, 0, 602))
	_contar_desde(p)
	p.seleccionar(e) # primer clic
	var acc: int = p._resolver_clic_entidad(e) # segundo clic: decide...
	_check(acc == 1, "segundo clic en mob = ATACAR", "acc=%d" % acc)
	p._aplicar_clic(e, acc) # ...y ejecuta
	_frames(p, 120)
	_check(_golpes >= 2, "el doble clic inicia el bucle persistente",
		"golpes=%d" % _golpes)


## (h) La curación no fija objetivo ni ordena moverse.
## curacion_menor por id (fase 17): el hotbar lanzar_skill(i) es por clase
## desde la fase 18 (el guerrero ya no tiene curar en su lista).
func _t_curacion_no_altera_combate() -> void:
	var p: Player = _player(Vector3(700, 0, 700))
	var e: Enemy = _enemigo(Vector3(700, 0, 702))
	_contar_desde(p)
	p.mana_actual = 999.0
	p.seleccionar(e)
	p.take_damage(30.0, null)
	p.lanzar_skill_id("curacion_menor")
	_check(p.objetivo_ataque == null, "la curacion no fija objetivo", "")
	_check(not p._tiene_destino, "la curacion no ordena moverse", "")
	_check(_golpes == 0, "la curacion no pega", "")
	_check(p.seleccion == e, "la curacion no toca la seleccion", "")
