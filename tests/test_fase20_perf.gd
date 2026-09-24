extends SceneTree
## Tests headless de la Fase 20 (P0-5 + harness): budget de luces,
## tope de partículas y monitor FPS.
##
## Cubre:
## (a) Antorcha sin jugador: siempre encendida (compatibilidad);
## (b) Antorcha con jugador: lejos se apaga (+salta el flicker), cerca
##     enciende; `luz_activa()` lo refleja;
## (c) CiudadLuna.fijar_jugador() propaga a las Antorcha construidas;
## (d) Clima.tope_gotas recorta el amount (default 2000 intacto);
## (e) MonitorFPS refresca el texto a 2 Hz sin reventar.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase20_perf.gd

const CD: GDScript = preload("res://scripts/mundo/ciclo_dia.gd")
const CL: GDScript = preload("res://scripts/mundo/clima.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const BV: GDScript = preload("res://scripts/combate/barra_vida_mob.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 20 — budget de luces, tope de lluvia, monitor FPS")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_antorcha_sin_jugador()
	_test_antorcha_culling()
	_test_fijar_jugador()
	_test_tope_gotas()
	_test_monitor_fps()
	_test_barra_compartida()
	print("[TEST] fase20_perf: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _antorcha() -> Antorcha:
	var a: Antorcha = Antorcha.new()
	root.add_child(a)
	_basura.append(a)
	return a


func _jugador_en(pos: Vector3) -> Node3D:
	var j: Node3D = Node3D.new()
	j.position = pos
	root.add_child(j)
	_basura.append(j)
	return j


## (a) Sin jugador: comportamiento de siempre.
func _test_antorcha_sin_jugador() -> void:
	var a: Antorcha = _antorcha()
	a._process(0.016)
	_chk(a.luz_activa(), "a: sin jugador siempre encendida")


## (b) Culling por distancia.
func _test_antorcha_culling() -> void:
	var a: Antorcha = _antorcha()
	var j: Node3D = _jugador_en(Vector3.ZERO)
	a.jugador = j
	j.position = Vector3(10, 0, 0)
	a._process(0.016)
	_chk(a.luz_activa(), "b: cerca encendida")
	j.position = Vector3(5000, 0, 0)
	a._process(0.016)
	_chk(not a.luz_activa(), "b: lejos apagada")
	j.position = Vector3(10, 0, 0)
	a._process(0.016)
	_chk(a.luz_activa(), "b: al volver enciende")


## (c) La ciudad propaga el jugador a sus antorchas reales.
func _test_fijar_jugador() -> void:
	var t: Terreno = Terreno.new()
	root.add_child(t)
	_basura.append(t)
	var c: CiudadLuna = CiudadLuna.new()
	c.terreno = t
	root.add_child(c)
	_basura.append(c)
	var reales: Array = []
	for l in c._luces:
		if l is Antorcha:
			reales.append(l)
	_chk(not reales.is_empty(), "c: Moon Town tiene antorchas reales (sanity)")
	var j: Node3D = _jugador_en(Vector3.ZERO)
	c.fijar_jugador(j)
	var todas: bool = true
	for l in reales:
		if (l as Antorcha).jugador != j:
			todas = false
	_chk(todas, "c: fijar_jugador propaga a las %d reales" % reales.size())


## (d) Tope de gotas data-driven.
func _test_tope_gotas() -> void:
	var w1: Clima = _montar(0)
	var gotas1: GPUParticles3D = w1.get_node("Lluvia") as GPUParticles3D
	_chk(gotas1.amount == 2000, "d: sin tope amount=2000 (%d)" % gotas1.amount)
	var w2: Clima = _montar(500)
	var gotas2: GPUParticles3D = w2.get_node("Lluvia") as GPUParticles3D
	_chk(gotas2.amount == 500, "d: tope 500 recorta (%d)" % gotas2.amount)


func _montar(tope: int) -> Clima:
	var ciclo: CicloDia = CD.new()
	root.add_child(ciclo)
	_basura.append(ciclo)
	var jugador := Node3D.new()
	root.add_child(jugador)
	_basura.append(jugador)
	var w: Clima = CL.new()
	w.ciclo = ciclo
	w.jugador = jugador
	w.cambio_automatico = false
	w.tope_gotas = tope
	root.add_child(w)
	_basura.append(w)
	return w


## (e) Monitor FPS.
func _test_monitor_fps() -> void:
	var m: MonitorFPS = MonitorFPS.new()
	root.add_child(m)
	_basura.append(m)
	m.configurar(null)
	m._process(0.6)
	_chk(m.text != "…", "e: el texto se refresca")
	_chk(m.text.find("FPS") >= 0 and m.text.find("mobs") >= 0,
		"e: formato 'FPS · ms · mobs'", m.text)


## (f) Barra de vida: quad + materiales compartidos entre instancias.
func _test_barra_compartida() -> void:
	var e1: Enemy = EN.new()
	root.add_child(e1)
	_basura.append(e1)
	var b1: BarraVidaMob = BV.new()
	e1.add_child(b1)
	var e2: Enemy = EN.new()
	root.add_child(e2)
	_basura.append(e2)
	var b2: BarraVidaMob = BV.new()
	e2.add_child(b2)
	var fg1: MeshInstance3D = b1.get("_fg") as MeshInstance3D
	var fg2: MeshInstance3D = b2.get("_fg") as MeshInstance3D
	var fo1: MeshInstance3D = b1.get("_fondo") as MeshInstance3D
	var fo2: MeshInstance3D = b2.get("_fondo") as MeshInstance3D
	_chk(fg1.mesh == fg2.mesh and fo1.mesh == fg2.mesh,
		"f: un solo QuadMesh compartido")
	_chk(fo1.material_override == fo2.material_override,
		"f: fondo con material compartido")
	e1.take_damage(e1.stats.vida_max * 0.5, null, false)
	e2.take_damage(e2.stats.vida_max * 0.5, null, false)
	_chk(fg1.material_override == fg2.material_override,
		"f: mismo pct = mismo peldaño")
	e2.take_damage(e2.stats.vida_max * 0.4, null, false)
	_chk(fg1.material_override != fg2.material_override,
		"f: distinto pct = distinto peldaño")
	# Reset para el pool: oculta y sin reloj.
	e1.take_damage(999999.0, null, false)
	(b1 as BarraVidaMob).reiniciar()
	_chk(not b1.visible, "f: reiniciar oculta la barra")
