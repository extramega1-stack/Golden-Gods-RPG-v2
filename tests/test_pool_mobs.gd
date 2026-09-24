extends SceneTree
## Tests headless de la Fase 20 (P0-1): PoolMobs + Enemy.reiniciar().
##
## Cubre:
## (a) la escena se precarga una vez y obtener() instancia por arquetipo;
## (b) devolver() + obtener() reutiliza el mismo nodo (cero instantiate),
##     vivo, con vida llena y cuerpo visible;
## (c) reiniciar() revive un muerto (estado QUIETO, colisión viva);
## (d) doble devolver() no duplica el pool (idempotente);
## (e) arquetipo desconocido retorna null sin reventar;
## (f) integración con StreamingMobs: liberar devuelve al pool y al volver
##     se reutiliza sin crear de más (la factory es pool.obtener).
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_pool_mobs.gd

const PM: GDScript = preload("res://scripts/mundo/pool_mobs.gd")
const ST: GDScript = preload("res://scripts/mundo/streaming_mobs.gd")
const SP: GDScript = preload("res://scripts/mundo/spawner_mobs.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false


func _init() -> void:
	print("[TEST] Fase 20 — PoolMobs (preload + reciclaje por arquetipo)")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_obtener_instancia()
	_test_devolver_y_reutilizar()
	_test_reiniciar_revive()
	_test_doble_devolver_idempotente()
	_test_arquetipo_desconocido()
	_test_integracion_streaming()
	print("[TEST] pool_mobs: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String) -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] " + nombre)


func _arqs() -> Dictionary:
	return {
		"goblin": {"nombre": "Goblin", "fuerza": 8.0,
			"destreza": 5.0, "inteligencia": 3.0, "color": [0.8, 0.25, 0.25]},
		"lobo": {"nombre": "Lobo", "fuerza": 10.0,
			"destreza": 6.0, "inteligencia": 2.0, "color": [0.2, 0.5, 0.9]},
	}


func _pool() -> PoolMobs:
	var p: PoolMobs = PM.new()
	p.configurar_arquetipos(_arqs())
	root.add_child(p)
	return p


func _limpiar(nodos: Array) -> void:
	for n in nodos:
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()


## (a) Obtener instancia por arquetipo (escena precargada, sin load por llamada).
func _test_obtener_instancia() -> void:
	var p: PoolMobs = _pool()
	var a: Enemy = p.obtener("goblin", Vector3(10, 0, 0))
	var b: Enemy = p.obtener("lobo", Vector3(20, 0, 0))
	_chk(a != null and b != null, "a: obtener retorna enemigos")
	_chk(a.arquetipo_id == "goblin" and b.arquetipo_id == "lobo",
		"a: cada uno con su arquetipo")
	_chk(a.esta_vivo() and b.esta_vivo(), "a: nacen vivos")
	_chk(a.global_position == Vector3(10, 0, 0), "a: colocado en su posición")
	_chk(p.creados == 2, "a: 2 instantiate (uno por obtener)")
	_chk(p.reutilizados == 0, "a: 0 reutilizados aún")
	_limpiar([p])


## (b) Devolver + obtener reutiliza el mismo nodo.
func _test_devolver_y_reutilizar() -> void:
	var p: PoolMobs = _pool()
	var a: Enemy = p.obtener("goblin", Vector3(10, 0, 0))
	var iid: int = a.get_instance_id()
	p.devolver(a)
	_chk(p.total_libres() == 1, "b: 1 aparcado tras devolver")
	_chk(not a.visible, "b: el devuelto queda invisible")
	var c: Enemy = p.obtener("goblin", Vector3(30, 0, 5))
	_chk(c != null, "b: obtener tras devolver retorna")
	_chk(c.get_instance_id() == iid, "b: es EL MISMO nodo (cero instantiate)")
	_chk(p.creados == 1 and p.reutilizados == 1,
		"b: creados 1, reutilizados 1")
	_chk(c.esta_vivo(), "b: el reutilizado está vivo")
	_chk(c.vida_actual >= c.stats.vida_max, "b: con vida llena")
	_chk(c.visible, "b: visible de nuevo")
	var cuerpo: MeshInstance3D = c.get_node_or_null("Cuerpo") as MeshInstance3D
	_chk(cuerpo != null and cuerpo.visible, "b: cuerpo visible")
	_chk(c.global_position == Vector3(30, 0, 5), "b: en la posición nueva")
	_limpiar([p])


## (c) Reiniciar revive un muerto con colisión y estado limpios.
func _test_reiniciar_revive() -> void:
	var p: PoolMobs = _pool()
	var a: Enemy = p.obtener("goblin", Vector3.ZERO)
	a.take_damage(99999.0, null)
	_chk(not a.esta_vivo(), "c: el daño masivo lo mata")
	p.devolver(a)
	var c: Enemy = p.obtener("goblin", Vector3(5, 0, 5))
	_chk(c.esta_vivo(), "c: el reutilizado revive")
	_chk(c.estado == Enemy.Estado.QUIETO, "c: estado QUIETO")
	_chk(c.collision_layer == Enemy.CAPA_VIVA
		and c.collision_mask == Enemy.MASCARA_VIVA,
		"c: colisión viva restaurada")
	_chk(c.velocity == Vector3.ZERO, "c: velocidad a cero")
	_limpiar([p])


## (d) Doble devolver no duplica.
func _test_doble_devolver_idempotente() -> void:
	var p: PoolMobs = _pool()
	var a: Enemy = p.obtener("goblin", Vector3.ZERO)
	p.devolver(a)
	p.devolver(a)
	_chk(p.total_libres() == 1, "d: doble devolver = 1 aparcado")
	_chk(p.devueltos == 1, "d: contador no duplica")
	_limpiar([p])


## (e) Arquetipo desconocido: null sin reventar.
func _test_arquetipo_desconocido() -> void:
	var p: PoolMobs = _pool()
	var e: Enemy = p.obtener("dragon_inexistente", Vector3.ZERO)
	_chk(e == null, "e: arquetipo desconocido retorna null")
	_chk(p.creados == 0, "e: no instancia nada")
	p.devolver(null)
	_chk(p.total_libres() == 0, "e: devolver null es no-op")
	_limpiar([p])


## (f) Streaming + pool: liberar recicla y reinstanciar reutiliza.
func _test_integracion_streaming() -> void:
	var p: PoolMobs = _pool()
	var j: Node3D = Node3D.new()
	j.position = Vector3.ZERO
	root.add_child(j)
	var s: SpawnerMobs = SP.new()
	s.configurar_arquetipos({"goblin": {"respawn_seg": 60.0}})
	s.fijar_factory(p.obtener)
	root.add_child(s)
	var st: StreamingMobs = ST.new()
	st.configurar([{"arquetipo": "goblin", "origen": Vector3(10, 0, 0)}])
	st.fijar_factory(p.obtener)
	st.fijar_jugador(j)
	st.fijar_spawner(s)
	st.fijar_pool(p)
	st.fijar_radios(100.0, 200.0)
	root.add_child(st)
	st.actualizar()
	_chk(st.conteo_instanciados() == 1, "f: 1 instanciado cerca")
	_chk(p.creados == 1, "f: 1 instantiate real")
	j.position = Vector3(5000, 0, 0)
	st.actualizar()
	_chk(st.conteo_instanciados() == 0, "f: lejos se desinstancia")
	_chk(p.total_libres() == 1, "f: el liberado vuelve al pool (no free)")
	j.position = Vector3.ZERO
	st.actualizar()
	_chk(st.conteo_instanciados() == 1, "f: al volver se reinstancia")
	_chk(p.creados == 1 and p.reutilizados == 1,
		"f: reutilizado del pool, cero instantiate extra")
	_limpiar([j, s, st, p])
