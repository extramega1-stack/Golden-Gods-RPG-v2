extends SceneTree
## Tests headless de la Fase 20 (P0-3): construcción progresiva del mundo.
##
## Cubre:
## (a) Terreno progresivo: al entrar al árbol NO congela (0 chunks), el
##     bin ya sirve alturas, avanzar por partes emite progreso, al vaciar
##     emite terreno_listo UNA vez y deja 72 meshes (36x2 LOD);
## (b) Terreno síncrono por defecto intacto (tests viejos);
## (c) CiudadLuna progresiva: al entrar no construye; avanzar completa,
##     emite ciudad_lista UNA vez, 18 edificios y puntos_npc listos;
## (d) CiudadLuna síncrona por defecto intacta;
## (e) PantallaCarga: progreso con clamp y capa UiLayers.CARGA.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase20_carga.gd

const TG: GDScript = preload("res://scripts/mundo/terreno.gd")
const CL: GDScript = preload("res://scripts/mundo/ciudad_luna.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []
var _listos_terreno: int = 0
var _listas_ciudad: int = 0
var _prog_terreno: Array = []
var _prog_ciudad: Array = []


func _init() -> void:
	print("[TEST] Fase 20 — construcción progresiva + pantalla de carga")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_terreno_progresivo()
	_test_terreno_sincrono()
	_test_ciudad_progresiva()
	_test_ciudad_sincrona()
	_test_pantalla_carga()
	print("[TEST] fase20_carga: %d ok, %d fallos" % [_ok, _fallos])
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


func _meshes(n: Node) -> int:
	var c: int = 0
	var pila: Array = [n]
	while not pila.is_empty():
		var actual: Node = pila.pop_back()
		if actual is MeshInstance3D:
			c += 1
		for h in actual.get_children():
			pila.append(h)
	return c


## (a) Terreno progresivo por partes.
func _test_terreno_progresivo() -> void:
	_listos_terreno = 0
	_prog_terreno = []
	var t: Terreno = TG.new()
	t.construccion_progresiva = true
	t.terreno_listo.connect(func() -> void: _listos_terreno += 1)
	t.progreso_construccion.connect(
		func(h: int, tot: int) -> void: _prog_terreno.append([h, tot]))
	root.add_child(t)
	_basura.append(t)
	_chk(_meshes(t) == 0, "a: al entrar no construye (cero freeze)")
	_chk(not t.construccion_terminada(), "a: no terminada al arrancar")
	_chk(t.fraccion_construccion() == 0.0, "a: fracción 0")
	# El bin ya cargó: las alturas funcionan desde el primer frame.
	_chk(absf(t.altura_en(0.0, 0.0) - 40.0) < 30.0,
		"a: altura_en sirve sin meshes (y=%.1f)" % t.altura_en(0.0, 0.0))
	_chk(t.avanzar_construccion(10) == false, "a: con 10 no termina")
	_chk(_meshes(t) == 20, "a: 10 chunks = 20 meshes")
	_chk(t.avanzar_construccion(100) == true, "a: el resto termina")
	_chk(_meshes(t) == 72, "a: 36 chunks = 72 meshes")
	_chk(_listos_terreno == 1, "a: terreno_listo UNA vez")
	_chk(t.construccion_terminada(), "a: terminada al vaciar")
	_chk(t.fraccion_construccion() == 1.0, "a: fracción 1")
	_chk(not _prog_terreno.is_empty()
		and int(_prog_terreno[-1][0]) == 36 and int(_prog_terreno[-1][1]) == 36,
		"a: progreso termina en 36/36")
	_chk(t.avanzar_construccion(5) == true and _listos_terreno == 1,
		"a: avanzar de más no re-emite")


## (b) Terreno síncrono por defecto (compatibilidad).
func _test_terreno_sincrono() -> void:
	var t: Terreno = TG.new()
	root.add_child(t)
	_basura.append(t)
	_chk(_meshes(t) == 72, "b: síncrono construye al entrar")
	_chk(t.construccion_terminada(), "b: terminada")
	_chk(t.fraccion_construccion() == 1.0, "b: fracción 1")


## Terreno real con bin (para las ciudades progresivas).
func _terreno_real() -> Terreno:
	var t: Terreno = TG.new()
	root.add_child(t)
	_basura.append(t)
	return t


## (c) Ciudad progresiva por pasos.
func _test_ciudad_progresiva() -> void:
	_listas_ciudad = 0
	_prog_ciudad = []
	var t: Terreno = _terreno_real()
	var c: CiudadLuna = CL.new()
	c.terreno = t
	c.construccion_progresiva = true
	c.ciudad_lista.connect(func() -> void: _listas_ciudad += 1)
	c.progreso_ciudad.connect(
		func(h: int, tot: int) -> void: _prog_ciudad.append([h, tot]))
	root.add_child(c)
	_basura.append(c)
	_chk(c.edificios.is_empty(), "c: al entrar no construye")
	_chk(not c.construccion_terminada(), "c: no terminada al arrancar")
	_chk(c.fraccion_construccion() == 0.0, "c: fracción 0")
	_chk(c.avanzar_construccion(4) == false, "c: con 4 pasos no termina")
	_chk(c.edificios.is_empty(), "c: 4 pasos = paleta/plaza/calles/muralla")
	_chk(c.avanzar_construccion(1) == false, "c: el 5to paso es el 1er edificio")
	_chk(not c.edificios.is_empty(), "c: ya hay edificios parciales")
	var n: int = 0
	while not c.avanzar_construccion(5) and n < 20:
		n += 1
	_chk(c.construccion_terminada(), "c: al vaciar termina")
	_chk(_listas_ciudad == 1, "c: ciudad_lista UNA vez")
	_chk(c.edificios.size() == 18, "c: 18 edificios (%d)" % c.edificios.size())
	_chk(c.puntos_npc.has("ilya"), "c: puntos_npc listos (ilya)")
	_chk(c.fraccion_construccion() == 1.0, "c: fracción 1")
	_chk(c.avanzar_construccion(5) == true and _listas_ciudad == 1,
		"c: avanzar de más no re-emite")


## (d) Ciudad síncrona por defecto (compatibilidad).
func _test_ciudad_sincrona() -> void:
	var t: Terreno = _terreno_real()
	var c: CiudadLuna = CL.new()
	c.terreno = t
	root.add_child(c)
	_basura.append(c)
	_chk(c.edificios.size() == 18, "d: síncrona construye al entrar")
	_chk(c.construccion_terminada(), "d: terminada")


## (e) Pantalla de carga.
func _test_pantalla_carga() -> void:
	var p: PantallaCarga = PantallaCarga.new()
	root.add_child(p)
	_basura.append(p)
	_chk(p.layer == UiLayers.CARGA, "e: capa CARGA (99)")
	_chk(p.progreso_actual() == 0.0, "e: arranca en 0")
	p.fijar_progreso(0.5, "Mitad")
	_chk(p.progreso_actual() == 0.5, "e: fija 0.5")
	p.fijar_progreso(2.0)
	_chk(p.progreso_actual() == 1.0, "e: clamp arriba")
	p.fijar_progreso(-1.0)
	_chk(p.progreso_actual() == 0.0, "e: clamp abajo")
