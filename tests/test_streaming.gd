extends SceneTree
## Tests headless de la Fase 12.1 (hotfix de rendimiento: "va super lageado").
##
## Causa (fase 12): `_instanciar_spawns()` creaba los 1121 creeps de una vez
## como nodos Enemy completos (cada uno con _physics_process, move_and_slide,
## material propio y draw call). El fix: `StreamingMobs` mantiene los spawns
## como DATOS e instancia solo los cercanos (radio data-driven con
## histéresis); la IA piensa escalonada por distancia; los materiales por
## arquetipo se comparten.
##
## Cubre:
## (a) solo se instancian los registros dentro de radio_alta;
## (b) histéresis: en la banda (alta, baja] no hay churn (ni se instancia
##     lo nuevo ni se libera lo ya instanciado);
## (c) al alejarse más allá de radio_baja los nodos se liberan (señal
##     mob_liberado) y al volver se re-instancian;
## (d) el respawn del SpawnerMobs sobrevive al streaming: la puerta veta
##     reaparecer lejos (el pendiente se reprograma, no se pierde) y al
##     acercarse el mob reaparece y el streaming lo re-asocia a su registro;
## (e) `Enemy.intervalo_cerebro(dist)` puro: 1/3/6 por bandas;
## (f) materiales compartidos por color de arquetipo (no uno por mob).
##
## Cómo correrlo: ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_streaming.gd

const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const ST: GDScript = preload("res://scripts/mundo/streaming_mobs.gd")
const SP: GDScript = preload("res://scripts/mundo/spawner_mobs.gd")
const ESCENA_ENEMIGO: PackedScene = preload("res://scenes/enemy/enemigo.tscn")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false

var _liberados: int = 0
var _instanciados: int = 0


func _init() -> void:
	print("[TEST] Fase 12.1 — streaming de mobs, puerta de respawn, IA escalonada")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_instancia_solo_cercanos()
	_test_histeresis_sin_churn()
	_test_liberar_y_reinstanciar()
	_test_respawn_con_puerta()
	_test_intervalo_cerebro()
	_test_materiales_compartidos()
	print("[TEST] streaming: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String) -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] " + nombre)


## Factory de tests: Enemy con arquetipo, añadido al árbol (como la demo).
func _factory(arq_id: String, pos: Vector3) -> Enemy:
	var e: Enemy = EN.new()
	e.arquetipo_id = arq_id
	e.position = pos
	root.add_child(e)
	return e


func _jugador_en(pos: Vector3) -> Node3D:
	var j: Node3D = Node3D.new()
	j.position = pos
	root.add_child(j)
	return j


func _spawner() -> SpawnerMobs:
	var s: SpawnerMobs = SP.new()
	s.configurar_arquetipos({"goblin": {"respawn_seg": 0.05}})
	s.fijar_factory(_factory)
	root.add_child(s)
	return s


func _streaming_con(jugador: Node3D, spawner: SpawnerMobs, registros: Array) -> StreamingMobs:
	var st: StreamingMobs = ST.new()
	st.configurar(registros)
	st.fijar_factory(_factory)
	st.fijar_jugador(jugador)
	st.fijar_spawner(spawner)
	st.fijar_radios(100.0, 200.0)
	st.mob_instanciado.connect(func(_e: Enemy) -> void: _instanciados += 1)
	st.mob_liberado.connect(func(_e: Enemy) -> void: _liberados += 1)
	# Como la demo: lo instanciado se vigila para el respawn.
	st.mob_instanciado.connect(func(e: Enemy) -> void: spawner.vigilar(e))
	root.add_child(st)
	return st


func _regs() -> Array:
	return [
		{"arquetipo": "goblin", "origen": Vector3(10, 0, 0)},
		{"arquetipo": "goblin", "origen": Vector3(50, 0, 0)},
		{"arquetipo": "goblin", "origen": Vector3(150, 0, 0)},
		{"arquetipo": "goblin", "origen": Vector3(5000, 0, 0)},
		{"arquetipo": "goblin", "origen": Vector3(9000, 0, 0)},
	]


func _limpiar(nodos: Array) -> void:
	for n in nodos:
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()


## (a) Solo se instancian los registros dentro de radio_alta.
func _test_instancia_solo_cercanos() -> void:
	_instanciados = 0
	var j: Node3D = _jugador_en(Vector3.ZERO)
	var s: SpawnerMobs = _spawner()
	var st: StreamingMobs = _streaming_con(j, s, _regs())
	st.actualizar()
	_chk(st.conteo_instanciados() == 2, "a: solo 2 cercanos instanciados (10 y 50)")
	_chk(_instanciados == 2, "a: señal mob_instanciado x2")
	_chk(st.conteo_registros() == 5, "a: los 5 registros siguen en datos")
	_limpiar([j, s, st])


## (b) Histéresis: en la banda (100, 200] no hay churn.
func _test_histeresis_sin_churn() -> void:
	_instanciados = 0
	_liberados = 0
	var j: Node3D = _jugador_en(Vector3.ZERO)
	var s: SpawnerMobs = _spawner()
	var st: StreamingMobs = _streaming_con(j, s, _regs())
	st.actualizar()
	# El registro a 150 está en la banda: NO se instancia de nuevas...
	_chk(st.conteo_instanciados() == 2, "b: el de la banda (150) no se instancia solo")
	# ...pero si ya estaba instanciado, NO se libera en la banda.
	j.position = Vector3(60, 0, 0)  # el de 150 queda a 90 (dentro de alta)
	st.actualizar()
	_chk(st.conteo_instanciados() == 3, "b: al acercarse se instancia el de 150")
	j.position = Vector3.ZERO  # el de 150 vuelve a la banda (150)
	st.actualizar()
	_chk(st.conteo_instanciados() == 3, "b: en la banda no se libera lo instanciado")
	_chk(_liberados == 0, "b: cero liberaciones en la banda")
	_limpiar([j, s, st])


## (c) Más allá de radio_baja se libera; al volver se re-instancia.
func _test_liberar_y_reinstanciar() -> void:
	_instanciados = 0
	_liberados = 0
	var j: Node3D = _jugador_en(Vector3.ZERO)
	var s: SpawnerMobs = _spawner()
	var st: StreamingMobs = _streaming_con(j, s, _regs())
	st.actualizar()
	_chk(st.conteo_instanciados() == 2, "c: arranque con 2")
	j.position = Vector3(3000, 0, 0)
	st.actualizar()
	_chk(st.conteo_instanciados() == 0, "c: lejos se liberan todos")
	_chk(_liberados == 2, "c: señal mob_liberado x2")
	_chk(st.conteo_registros() == 5, "c: los registros sobreviven")
	j.position = Vector3.ZERO
	st.actualizar()
	_chk(st.conteo_instanciados() == 2, "c: al volver se re-instancian")
	_limpiar([j, s, st])


## (d) Respawn sobre streaming: la puerta veta lejos, al acercarse reaparece.
func _test_respawn_con_puerta() -> void:
	_instanciados = 0
	var puerta: Dictionary = {"abierta": false}
	var j: Node3D = _jugador_en(Vector3.ZERO)
	var s: SpawnerMobs = _spawner()
	s.puerta_reaparicion = func(_a: String, _o: Vector3) -> bool: return bool(puerta["abierta"])
	var st: StreamingMobs = _streaming_con(j, s, [
		{"arquetipo": "goblin", "origen": Vector3(10, 0, 0)},
	])
	st.actualizar()
	_chk(st.conteo_instanciados() == 1, "d: un mob instanciado")
	var e: Enemy = st._registros[0]["nodo"] as Enemy
	e.die()
	_chk(s.pendientes() == 1, "d: el spawner programó el respawn")
	# Puerta cerrada (jugador lejos): el timer corre pero NO reaparece,
	# y el pendiente se reprograma (no se pierde).
	j.position = Vector3(5000, 0, 0)
	st.actualizar()  # el cadáver se libera por distancia
	s.avanzar(0.06)
	_chk(st.conteo_instanciados() == 0, "d: con la puerta cerrada no reaparece")
	_chk(s.pendientes() == 1, "d: el pendiente se reprogramó, no se perdió")
	# Puerta abierta (jugador cerca): al cumplirse el reintento reaparece
	# y el streaming lo re-asocia a su registro.
	j.position = Vector3.ZERO
	st.actualizar()
	puerta["abierta"] = true
	s.avanzar(5.1)
	_chk(st.conteo_instanciados() == 1, "d: al acercarse el mob reaparece")
	_chk(s.pendientes() == 0, "d: ya no hay pendientes")
	var e2: Enemy = st._registros[0]["nodo"] as Enemy
	_chk(e2 != null and e2.esta_vivo(), "d: el reaparecido está vivo y trackeado")
	_limpiar([j, s, st])


## (e) IA escalonada: bandas de distancia puras y testeables.
func _test_intervalo_cerebro() -> void:
	_chk(EN.intervalo_cerebro(10.0) == 1, "e: <60 m piensa cada frame")
	_chk(EN.intervalo_cerebro(59.9) == 1, "e: borde 60 -> 1")
	_chk(EN.intervalo_cerebro(100.0) == 3, "e: <250 m cada 3 frames")
	_chk(EN.intervalo_cerebro(300.0) == 6, "e: lejos cada 6 frames")
	_chk(EN.intervalo_cerebro(INF) == 6, "e: sin objetivo cada 6 frames")


## (f) El tinte por arquetipo comparte material (no uno por mob).
func _test_materiales_compartidos() -> void:
	var a: Node3D = ESCENA_ENEMIGO.instantiate() as Node3D
	var b: Node3D = ESCENA_ENEMIGO.instantiate() as Node3D
	root.add_child(a)
	root.add_child(b)
	var ea: Enemy = a as Enemy
	var eb: Enemy = b as Enemy
	ea.configurar({"color": [0.8, 0.25, 0.25]})
	eb.configurar({"color": [0.8, 0.25, 0.25]})
	var ca: MeshInstance3D = a.get_node("Cuerpo") as MeshInstance3D
	var cb: MeshInstance3D = b.get_node("Cuerpo") as MeshInstance3D
	_chk(ca.material_override == cb.material_override,
		"f: dos mobs del mismo arquetipo comparten material")
	eb.configurar({"color": [0.2, 0.5, 0.9]})
	_chk(ca.material_override != cb.material_override,
		"f: distinto color -> distinto material")
	_limpiar([a, b])
