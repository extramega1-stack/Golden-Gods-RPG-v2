extends SceneTree
## Tests headless de la Fase 41 (arena PvE por oleadas).
##
## Cubre (skills `rpg` + `level-design`: encuentros como datos con ritmo):
## (a) datos: 10 oleadas, campo remoto, composición y recompensas;
## (b) oleadas: iniciar genera, matar todo paga oro/XP extra y avanza tras
##     el descanso (avanzar(dt) testeable, sin espera real);
## (c) derrota al morir el jugador y victoria al limpiar las 10, con
##     trofeos (mejor_oleada, victorias) y señales;
## (d) save v12 con bloque arena + round-trip; sin bloque → ceros;
## (e) el Maestro existe en datos y es_maestro() lo reconoce.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase41_arena.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const AR: GDScript = preload("res://scripts/arena/arena.gd")
const SS: GDScript = preload("res://scripts/save/save_system.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []
var _eventos: Array = []


func _init() -> void:
	print("[TEST] Fase 41 — arena PvE")
	NpcDB.cargar()


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_datos()
	_test_oleadas()
	_test_derrota()
	_test_victoria()
	_test_save()
	_test_maestro()
	print("[TEST] fase41_arena: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _datos_arena() -> Dictionary:
	return JSON.parse_string(
		FileAccess.get_file_as_string("res://data/arena.json"))


func _arquetipos() -> Dictionary:
	return (JSON.parse_string(
		FileAccess.get_file_as_string("res://data/enemies.json"))
		as Dictionary)["arquetipos"]


func _kit() -> Array:
	var p: Player = PL.new()
	p.fijar_identidad("T", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	var a: Arena = AR.new()
	root.add_child(a)
	_basura.append(a)
	a.configurar(_datos_arena())
	a.fijar_arquetipos(_arquetipos())
	a.fijar_factory(_factory)
	a.fijar_jugador(p)
	_eventos.clear()
	a.oleada_iniciada.connect(func(n: int) -> void: _eventos.append(["ini", n]))
	a.oleada_superada.connect(func(n: int, _o: int, _x: int) -> void: _eventos.append(["sup", n]))
	a.arena_terminada.connect(func(v: bool, n: int) -> void: _eventos.append(["fin", v, n]))
	return [p, a]


func _factory(arq_id: String, _pos: Vector3) -> Enemy:
	var e: Enemy = EN.new()
	root.add_child(e)
	_basura.append(e)
	e.configurar((_arquetipos().get(arq_id, {}) as Dictionary).duplicate(true))
	return e


func _matar_todo(p: Player, a: Arena) -> void:
	for e in a._vivos.duplicate():
		if is_instance_valid(e) and (e as Enemy).esta_vivo():
			(e as Enemy).take_damage(99999.0, p)


## (a) Datos.
func _test_datos() -> void:
	var d: Dictionary = _datos_arena()
	_chk(int(d.get("version", 0)) == 1, "a: arena.json v1")
	var olas: Array = d.get("oleadas", [])
	_chk(olas.size() == 10, "a: 10 oleadas", str(olas.size()))
	var total: int = 0
	for w in olas:
		for arq_id in (w as Dictionary).get("mobs", {}):
			total += int(((w as Dictionary).get("mobs", {}) as Dictionary).get(arq_id, 0))
	_chk(total > 40, "a: unas 60 fieras en total", str(total))
	var c: Array = d.get("centro", [])
	_chk(c.size() == 2 and absf(float(c[0]) + 2000.0) < 1.0,
		"a: campo remoto", str(c))


## (b) Oleadas, recompensa y descanso.
func _test_oleadas() -> void:
	var kit: Array = _kit()
	var p: Player = kit[0]
	var a: Arena = kit[1]
	a.iniciar()
	_chk(a.activa() and a.oleada() == 1, "b: arranca en oleada 1")
	_chk(a.vivos() == 3, "b: oleada 1 = 3 goblins", str(a.vivos()))
	_chk(_eventos == [["ini", 1]], "b: señal oleada_iniciada", str(_eventos))
	var oro0: int = p.oro
	var xp0: int = p.xp_actual
	_matar_todo(p, a)
	_chk(a.vivos() == 0, "b: oleada limpia")
	# 3 goblins × 40 XP de kill + 30 del bonus de oleada.
	_chk(p.oro == oro0 + 25 and p.xp_actual == xp0 + 150,
		"b: paga 25 oro + 150 XP (120 kills + 30 bonus)",
		"%d/%d" % [p.oro - oro0, p.xp_actual - xp0])
	_chk(a.mejor_oleada == 1, "b: trofeo mejor=1")
	_chk(_eventos.has(["sup", 1]), "b: señal oleada_superada", str(_eventos))
	a.avanzar(999.0)
	_chk(a.oleada() == 2 and a.vivos() == 4, "b: descanso → oleada 2",
		"%d/%d" % [a.oleada(), a.vivos()])
	a.detener()
	_chk(not a.activa() and a.vivos() == 0, "b: detener limpia")


## (c) Derrota al morir.
func _test_derrota() -> void:
	var kit: Array = _kit()
	var p: Player = kit[0]
	var a: Arena = kit[1]
	a.iniciar()
	_matar_todo(p, a)
	a.avanzar(999.0)
	_chk(a.oleada() == 2, "c: setup en oleada 2")
	var verdugo: Enemy = _factory("ogro", Vector3.ZERO)
	p.take_damage(99999.0, verdugo)
	_chk(not a.activa(), "c: muerte termina la arena")
	_chk(_eventos.has(["fin", false, 2]), "c: señal derrota", str(_eventos))
	_chk(a.mejor_oleada == 1, "c: mejor conserva la 1")


## (d) Victoria limpiando las 10.
func _test_victoria() -> void:
	var kit: Array = _kit()
	var p: Player = kit[0]
	var a: Arena = kit[1]
	a.iniciar()
	var vueltas: int = 0
	while a.activa() and vueltas < 30:
		_matar_todo(p, a)
		a.avanzar(999.0)
		vueltas += 1
	_chk(not a.activa(), "d: termina tras la 10")
	_chk(_eventos.has(["fin", true, 11]), "d: señal victoria", str(_eventos))
	_chk(a.victorias == 1 and a.mejor_oleada == 10,
		"d: trofeos 1 victoria + mejor 10",
		"%d/%d" % [a.victorias, a.mejor_oleada])


## (e) Save v12 + round-trip + sin bloque.
func _test_save() -> void:
	_chk(SaveSystem.SAVE_VERSION == 12, "e: save v12")
	var a: Arena = AR.new()
	_basura.append(a)
	a.mejor_oleada = 7
	a.victorias = 2
	var d: Dictionary = a.to_dict()
	_chk(int(d.get("version", 0)) == 1, "e: bloque arena v1")
	var a2: Arena = AR.new()
	_basura.append(a2)
	a2.cargar_estado(d)
	_chk(a2.mejor_oleada == 7 and a2.victorias == 2, "e: round-trip")
	var a3: Arena = AR.new()
	_basura.append(a3)
	a3.cargar_estado({})
	_chk(a3.mejor_oleada == 0 and a3.victorias == 0, "e: sin bloque → ceros")


## (f) Maestro en datos.
func _test_maestro() -> void:
	_chk(Arena.es_maestro("maestro_arena"), "f: Renn es maestro")
	_chk(not Arena.es_maestro("ilya"), "f: Ilya no")
	_chk(NpcDB.obtener("maestro_arena").get("nombre", "") != "",
		"f: maestro en npcs.json")
