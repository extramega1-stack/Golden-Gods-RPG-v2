extends SceneTree
## Tests headless de la Fase 19.1 (hotfix: "Trying to cast a freed object").
##
## Causa: al matar 2+ mobs antes de un respawn, `_al_reaparecer_enemigo`
## (fase9_demo) liberaba con `_ultimo_muerto` el cadáver EQUIVOCADO; el
## streaming se quedaba con `rd["nodo"]` apuntando a un objeto liberado y
## cada tick de `actualizar()` disparaba "Trying to cast a freed object" en
## `rd["nodo"] as Enemy`, lo que ABORTABA el ciclo a la mitad (los mobs
## posteriores del arreglo no se instanciaban/liberaban ese tick).
##
## Cubre:
## (a) una referencia liberada en el registro no aborta `actualizar()`:
##     el tick sigue con los demás registros y el registro se limpia;
## (b) tras limpiar, el respawn del spawner re-asocia el registro;
## (c) `_indice_cadaver_cercano`: encuentra el cadáver correcto, ignora
##     vivos y referencias liberadas sin abortar;
## (d) `_al_reaparecer_enemigo`: con 2 muertes y 1 respawn se libera el
##     cadáver que corresponde al respawn, no el último muerto.
##
## Cómo correrlo: ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase19_1.gd

const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const ST: GDScript = preload("res://scripts/mundo/streaming_mobs.gd")
const SP: GDScript = preload("res://scripts/mundo/spawner_mobs.gd")
const DEMO9: GDScript = preload("res://scenes/demo/fase9_demo.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false

var _liberados: int = 0


func _init() -> void:
	print("[TEST] Fase 19.1 — hotfix freed object en streaming/respawn")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_referencia_liberada_no_aborta()
	_test_respawn_reasocia_tras_limpieza()
	_test_indice_cadaver_cercano()
	_test_reaparecer_libera_cadaver_correcto()
	print("[TEST] fase19_1: %d ok, %d fallos" % [_ok, _fallos])
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
	_liberados = 0
	st.mob_liberado.connect(func(_e: Enemy) -> void: _liberados += 1)
	# Como la demo: lo instanciado se vigila para el respawn.
	st.mob_instanciado.connect(func(e: Enemy) -> void: spawner.vigilar(e))
	root.add_child(st)
	return st


func _regs() -> Array:
	return [
		{"arquetipo": "goblin", "origen": Vector3(10, 0, 0)},
		{"arquetipo": "goblin", "origen": Vector3(50, 0, 0)},
		{"arquetipo": "goblin", "origen": Vector3(5000, 0, 0)},
	]


func _limpiar(nodos: Array) -> void:
	for n in nodos:
		# Fase 19.1: validar antes de castear también aquí (e1 ya está
		# liberado en el test c cuando se limpia).
		if not is_instance_valid(n):
			continue
		var nd: Node = n as Node
		if nd != null:
			nd.queue_free()


## (a) Referencia liberada en el registro: actualizar() no se aborta.
func _test_referencia_liberada_no_aborta() -> void:
	var j: Node3D = _jugador_en(Vector3.ZERO)
	var s: SpawnerMobs = _spawner()
	var st: StreamingMobs = _streaming_con(j, s, _regs())
	st.actualizar()
	_chk(st.conteo_instanciados() == 2, "a: A y B instanciados al inicio")
	# Se mata A (el registro queda muerto=true, nodo=cadáver) y se libera
	# el cadáver por fuera del streaming (lo que hacía la demo con el
	# cadáver equivocado en la fase 19).
	var mob_a: Enemy = st.mobs_vivos()[0]
	mob_a.die()
	mob_a.free()
	# El jugador se aleja: el tick debe liberar B aunque el registro de A
	# tenga una referencia liberada (antes: el `as` abortaba el ciclo aquí).
	j.position = Vector3(10000, 0, 0)
	st.actualizar()
	_chk(_liberados == 1, "a: el tick no se abortó (B se liberó)")
	var vivos: Variant = st.mobs_vivos()
	_chk(vivos is Array and vivos.is_empty(), "a: mobs_vivos sin referencias colgadas")
	_limpiar([j, s, st])


## (b) Tras la limpieza, el respawn re-asocia el registro.
func _test_respawn_reasocia_tras_limpieza() -> void:
	var j: Node3D = _jugador_en(Vector3.ZERO)
	var s: SpawnerMobs = _spawner()
	var st: StreamingMobs = _streaming_con(j, s, _regs())
	st.actualizar()
	var mob_a: Enemy = st.mobs_vivos()[0]
	mob_a.die()
	mob_a.free()
	st.actualizar()
	# El respawn pendiente de A (0.05 s) se cumple y el streaming lo
	# re-asocia a su registro aunque la referencia anterior se liberó.
	s.avanzar(1.0)
	st.actualizar()
	_chk(st.mobs_vivos().size() == 2, "b: A reapareció y B sigue instanciado")
	_limpiar([j, s, st])


## (c) El matcher de cadáveres de la demo.
func _test_indice_cadaver_cercano() -> void:
	var demo: Node3D = DEMO9.new()
	var e1: Enemy = _factory("goblin", Vector3(10, 0, 10))
	var e2: Enemy = _factory("goblin", Vector3(100, 0, 100))
	demo.set("_lista_enemigos", [e1, e2])
	e1.die()
	_chk(demo.call("_indice_cadaver_cercano", Vector3(12, 0, 12)) == 0,
		"c: encuentra el cadáver cercano (e1)")
	_chk(demo.call("_indice_cadaver_cercano", Vector3(500, 0, 500)) == -1,
		"c: -1 si no hay cadáver en el margen")
	_chk(demo.call("_indice_cadaver_cercano", Vector3(100, 0, 100)) == -1,
		"c: ignora a los vivos aunque estén cerca")
	e1.free()
	_chk(demo.call("_indice_cadaver_cercano", Vector3(12, 0, 12)) == -1,
		"c: referencia liberada se salta sin abortar")
	_limpiar([e1, e2, demo])


## (d) Dos muertes y un respawn: se libera el cadáver del respawn.
func _test_reaparecer_libera_cadaver_correcto() -> void:
	var demo: Node3D = DEMO9.new()
	var a: Enemy = _factory("goblin", Vector3(10, 0, 0))
	var b: Enemy = _factory("goblin", Vector3(60, 0, 0))
	demo.set("_lista_enemigos", [a, b])
	a.die()
	b.die()
	# Reaparece A cerca de su origen: debe reemplazar/liberar a 'a', no a 'b'
	# (con _ultimo_muerto se liberaba 'b', el último muerto).
	var nuevo: Enemy = _factory("goblin", Vector3(11, 0, 1))
	demo.call("_al_reaparecer_enemigo", nuevo)
	var lista: Array = demo.get("_lista_enemigos")
	_chk(lista[0] == nuevo, "d: el respawn reemplaza su propio cadáver")
	_chk(lista[1] == b, "d: el otro cadáver no se toca")
	_chk(a.is_queued_for_deletion(), "d: se marcó para liberar el cadáver correcto")
	_chk(not b.is_queued_for_deletion(), "d: el cadáver ajeno sigue intacto")
	_limpiar([a, b, nuevo, demo])
