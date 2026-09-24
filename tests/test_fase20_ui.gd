extends SceneTree
## Tests headless de la Fase 20 (P0-2): UI dirty-driven + caché de vivos.
##
## Cubre:
## (a) `StreamingMobs.mobs_vivos()` es caché exacta: dos llamadas seguidas
##     devuelven LA MISMA instancia (cero recorridos/allocs extra) y refleja
##     instanciar/liberar sin llamadas de más;
## (b) `Minimapa._redibujo_sucio`: primer frame sí; quieto sin mobs/pings
##     no; jugador movido sí (con throttle); señal del streaming sí;
##     ping activo sí; latido con mobs visibles sí;
## (c) `Brujula._vista_cambio`: primer frame sí; estática no; yaw movido
##     sí; jugador movido sí.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase20_ui.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const ST: GDScript = preload("res://scripts/mundo/streaming_mobs.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 20 — UI dirty-driven + caché de mobs_vivos")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_cache_vivos()
	_test_minimapa_sucio()
	_test_minimapa_senal()
	_test_brujula_vista()
	print("[TEST] fase20_ui: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String) -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] " + nombre)


func _factory(arq_id: String, pos: Vector3) -> Enemy:
	var e: Enemy = EN.new()
	e.arquetipo_id = arq_id
	e.position = pos
	root.add_child(e)
	_basura.append(e)
	return e


func _jugador_en(pos: Vector3) -> Player:
	var p: Player = PL.new()
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


## (a) Caché exacta de mobs_vivos.
func _test_cache_vivos() -> void:
	var j: Node3D = Node3D.new()
	root.add_child(j)
	_basura.append(j)
	var st: StreamingMobs = ST.new()
	st.configurar([
		{"arquetipo": "goblin", "origen": Vector3(10, 0, 0)},
		{"arquetipo": "goblin", "origen": Vector3(5000, 0, 0)},
	])
	st.fijar_factory(_factory)
	st.fijar_jugador(j)
	st.fijar_radios(100.0, 200.0)
	root.add_child(st)
	_basura.append(st)
	st.actualizar()
	var a1: Array = st.mobs_vivos()
	var a2: Array = st.mobs_vivos()
	_chk(a1.size() == 1, "a: 1 vivo cerca")
	_chk(is_same(a1, a2), "a: misma instancia (cero reconstrucción)")
	j.position = Vector3(2500, 0, 0)
	st.actualizar()
	_chk(st.mobs_vivos().size() == 0, "a: lejos se libera (caché invalidada)")
	_chk(not is_same(a1, st.mobs_vivos()),
		"a: tras mutar se reconstruye (instancia nueva)")
	j.position = Vector3.ZERO
	st.actualizar()
	_chk(st.mobs_vivos().size() == 1, "a: al volver se reinstancia")


## (b) Minimapa: solo redibuja si algo visible cambió.
func _test_minimapa_sucio() -> void:
	var jug: Player = _jugador_en(Vector3(100, 0, 100))
	var mm: Minimapa = Minimapa.new()
	root.add_child(mm)
	_basura.append(mm)
	mm.configurar(jug, null, null, null, null)
	_chk(mm._redibujo_sucio(0.016), "b: primer frame dibuja")
	_chk(not mm._redibujo_sucio(0.016), "b: quieto sin mobs/pings no dibuja")
	_chk(not mm._redibujo_sucio(0.016), "b: sigue quieto, sigue sin dibujar")
	jug.global_position = Vector3(500, 0, 500)
	_chk(mm._redibujo_sucio(0.1), "b: jugador movido dibuja")
	_chk(not mm._redibujo_sucio(0.016), "b: tras dibujar, quieto no dibuja")
	# Ping activo anima: necesita frames.
	mm._poner_ping(Vector2(100, 100))
	_chk(mm._redibujo_sucio(0.016), "b: con ping vivo dibuja")
	mm._process(6.0)
	_chk(mm._pings.is_empty(), "b: el ping expira (sanity)")
	# Fade en transición: quieto justo 4 s (el objetivo cae a 0.35 pero el
	# alfa aún viaja) → necesita frames. (El cambio de posición resetea el
	# temporizador de reposo; repetir la misma no.)
	jug.global_position = Vector3(600, 0, 600)
	_chk(mm._redibujo_sucio(0.1), "b: jugador movido dibuja (sanity)")
	# 1 frame para resetear el reposo + 40 para llegar justo a 4 s.
	for i in range(41):
		mm._process(0.1)
	_chk(mm._redibujo_sucio(0.1), "b: fade en transición dibuja")


## (b2) La señal del streaming fuerza el redibujo (puntos rojos cambian).
func _test_minimapa_senal() -> void:
	var jug: Player = _jugador_en(Vector3.ZERO)
	var st: StreamingMobs = ST.new()
	st.configurar([{"arquetipo": "goblin", "origen": Vector3(10, 0, 0)}])
	st.fijar_factory(_factory)
	st.fijar_jugador(jug)
	st.fijar_radios(100.0, 200.0)
	root.add_child(st)
	_basura.append(st)
	var mm: Minimapa = Minimapa.new()
	root.add_child(mm)
	_basura.append(mm)
	mm.configurar(jug, null, null, null, st)
	_chk(mm._redibujo_sucio(0.1), "b2: primer frame dibuja")
	_chk(not mm._redibujo_sucio(0.016), "b2: quieto no dibuja")
	st.actualizar()
	_chk(mm._redibujo_sucio(0.016), "b2: mob instanciado (señal) dibuja")
	_chk(not mm._redibujo_sucio(0.016), "b2: consumido el forzado, no dibuja")
	# Latido con mobs visibles (caminan): a los 0.5 s redibuja.
	_chk(mm._redibujo_sucio(0.6), "b2: latido con mobs visibles dibuja")
	jug.position = Vector3(5000, 0, 0)
	st.actualizar()
	_chk(mm._redibujo_sucio(0.016), "b2: mob liberado (señal) dibuja")
	_chk(not mm._hay_mobs(), "b2: sin mobs (sanity)")
	_chk(not mm._redibujo_sucio(0.6), "b2: sin mobs ni movimiento no late")


## (c) Brújula: estática no redibuja; yaw/jugador sí.
func _test_brujula_vista() -> void:
	var br: Brujula = Brujula.new()
	root.add_child(br)
	_basura.append(br)
	br.configurar(null, null, null, null)
	_chk(br._vista_cambio(), "c: primer frame dibuja")
	_chk(not br._vista_cambio(), "c: estática no dibuja")
	_chk(not br._vista_cambio(), "c: sigue estática, no dibuja")
	var jug: Player = _jugador_en(Vector3.ZERO)
	var br2: Brujula = Brujula.new()
	root.add_child(br2)
	_basura.append(br2)
	br2.configurar(null, jug, null, null)
	_chk(br2._vista_cambio(), "c: primer frame con jugador dibuja")
	_chk(not br2._vista_cambio(), "c: jugador quieto no dibuja")
	jug.global_position = Vector3(100, 0, 0)
	_chk(br2._vista_cambio(), "c: jugador movido dibuja")
	_chk(not br2._vista_cambio(), "c: tras dibujar no dibuja")
