extends SceneTree
## Tests headless de la Fase 13 (minimapa estilo WC3/L2/MU).
##
## (a) Transformaciones puras: mundo_a_mapa / mapa_a_mundo redondas
##     (mundo->mapa->mundo ~= identidad) y esquinas exactas.
## (b) configurar() con todo null no revienta; mouse_filter STOP.
## (c) Terreno.color_en sin bin no revienta (devuelve el color por defecto).
## (d) Pre-render del fondo: con terreno "listo" genera ImageTexture;
##     sin terreno listo deja _fondo en null (fondo oscuro liso).
## (e) Fade en reposo: quieto > 4 s -> alfa baja hacia 0.35; al moverse
##     vuelve a 1.0 (simulando tiempo con _process directo; sin fisica
##     entre llamadas porque todo corre en un solo frame).
## (f) Clic izquierdo normal -> jugador.ordenar_mover_a al punto del mundo;
##     arrastrar actualiza el destino; soltar termina el arrastre.
## (g) Alt+clic -> ping (coords de mundo), sigue vivo a los 2 s y expira
##     solo pasados los 5 s.
## (h) fijar_npcs guarda la lista (puntos dorados).
## (i) Etiqueta de region: muestra el nombre de region_en(x, z) y se vacia
##     fuera del mapa.
## (j) Smoke de _draw: unos frames con jugador + npcs + ping + fondo para
##     que cualquier error de dibujado salga en la salida.
##
## Cómo correrlo (un solo comando):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase13_minimapa.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const NP: GDScript = preload("res://scripts/npc/npc.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []
var _fase: int = 0
var _mm: Minimapa = null
var _jug: Player = null


func _init() -> void:
	print("[TEST] Fase 13 - minimapa: transformaciones, fade, pings, clic, region")


## El arbol existe recien en el primer _process (leccion 13b). Fase 0: toda
## la logica testeable en un solo frame (sin fisica entre llamadas).
## Fases 1-2: smoke de _draw. Fase 3: cierre.
func _process(_delta: float) -> bool:
	match _fase:
		0:
			_todo_logica()
		1:
			_setup_draw()
		2:
			pass
		_:
			_finalizar()
			return true
	_fase += 1
	return false


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


func _cerca(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func _jugador_en(pos: Vector3) -> Player:
	var p: Player = PL.new()
	p.add_to_group("jugador")
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


func _npc_en(pos: Vector3) -> NPC:
	var n: NPC = NP.new()
	root.add_child(n)
	n.global_position = pos
	_basura.append(n)
	return n


func _clic(pos: Vector2, alt: bool, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.alt_pressed = alt
	ev.position = pos
	return ev


func _todo_logica() -> void:
	_mm = Minimapa.new()
	root.add_child(_mm)
	_basura.append(_mm)
	_t_transformaciones()
	_t_configurar_null()
	_t_color_sin_bin()
	_t_fondo_prerender()
	_jug = _jugador_en(Vector3(100, 0, 100))
	var db := RegionDB.new()
	_mm.configurar(_jug, null, null, db, null)
	_t_fade()
	_t_clic_mueve()
	_t_ping()
	_t_npcs()
	_t_region(db)


func _t_transformaciones() -> void:
	var centro: Vector2 = _mm.mundo_a_mapa(Vector2(0, 0))
	_check(_cerca(centro.x, 100.0, 0.01) and _cerca(centro.y, 100.0, 0.01),
			"mundo_a_mapa: centro del mundo -> centro del mapa")
	var pts: Array[Vector2] = [
		Vector2(-18432, -18432), Vector2(18432, 18432),
		Vector2(1234.5, -9876.25), Vector2(-500.25, 17000.75),
		Vector2(0, 0),
	]
	for w in pts:
		var m: Vector2 = _mm.mundo_a_mapa(w)
		var w2: Vector3 = _mm.mapa_a_mundo(m)
		_check(_cerca(w2.x, w.x, 0.05) and _cerca(w2.z, w.y, 0.05),
				"round-trip mundo->mapa->mundo %s" % str(w))
	var e00: Vector3 = _mm.mapa_a_mundo(Vector2(0, 0))
	_check(e00 == Vector3(-18432, 0, -18432),
			"mapa_a_mundo: esquina (0,0) -> (-18432, 0, -18432)")
	var e11: Vector3 = _mm.mapa_a_mundo(Vector2(200, 200))
	_check(e11 == Vector3(18432, 0, 18432) and e11.y == 0.0,
			"mapa_a_mundo: esquina (200,200) -> (18432, 0, 18432), y=0")


func _t_configurar_null() -> void:
	_mm.configurar(null, null, null, null, null)
	_check(_mm._fondo == null, "configurar todo null: sin fondo, sin reventar")
	_check(_mm.mouse_filter == Control.MOUSE_FILTER_STOP,
			"mouse_filter STOP: no come clics fuera de su rect")


func _t_color_sin_bin() -> void:
	# Sin arbol: _ready no corre, no hay bin cargado.
	var t: Terreno = Terreno.new()
	var c: Color = t.color_en(0, 0)
	_check(c == Color(0.1, 0.1, 0.12), "color_en sin bin no revienta")
	t.free()


func _t_fondo_prerender() -> void:
	var t: Terreno = Terreno.new()
	t._colores = PackedColorArray()
	t._colores.resize(Terreno.LADO * Terreno.LADO)
	for i in range(t._colores.size()):
		t._colores[i] = Color(0.2, 0.4, 0.1)
	var mm2: Minimapa = Minimapa.new()
	mm2.configurar(null, t, null, null, null)
	_check(mm2._fondo != null, "fondo pre-renderizado UNA vez con terreno listo")
	_check(mm2._fondo.get_width() == 144 and mm2._fondo.get_height() == 144,
			"fondo: grilla 144x144")
	var mm3: Minimapa = Minimapa.new()
	mm3.configurar(null, Terreno.new(), null, null, null)
	_check(mm3._fondo == null, "terreno no listo: fondo null (oscuro liso)")
	mm2.free()
	mm3.free()
	t.free()


func _t_fade() -> void:
	_jug.global_position = Vector3(100, 0, 100)
	for i in range(45):
		_mm._process(0.1)
	_check(_mm.modulate.a < 0.9, "quieto > 4 s: el fade empieza a bajar")
	for i in range(30):
		_mm._process(0.1)
	_check(_cerca(_mm.modulate.a, 0.35, 0.08),
			"quieto prolongado: alfa ~= 0.35", "alfa=%.3f" % _mm.modulate.a)
	_jug.global_position = Vector3(500, 0, 500)
	for i in range(30):
		_mm._process(0.1)
	_check(_cerca(_mm.modulate.a, 1.0, 0.08),
			"al moverse: alfa vuelve a 1.0", "alfa=%.3f" % _mm.modulate.a)


func _t_clic_mueve() -> void:
	_jug.global_position = Vector3(100, 0, 100)
	_mm._gui_input(_clic(Vector2(50, 150), false, true))
	_check(_jug._tiene_destino, "clic normal: fija orden de mover")
	var esperado: Vector3 = _mm.mapa_a_mundo(Vector2(50, 150))
	_check(_jug._destino == esperado,
			"clic normal: destino = punto del mundo", "dest=%s" % str(_jug._destino))
	_check(_mm._arrastrando, "clic normal inicia el arrastre")
	var mov := InputEventMouseMotion.new()
	mov.position = Vector2(60, 140)
	_mm._gui_input(mov)
	var esperado2: Vector3 = _mm.mapa_a_mundo(Vector2(60, 140))
	_check(_jug._destino == esperado2, "arrastrar actualiza el destino")
	_mm._gui_input(_clic(Vector2(60, 140), false, false))
	_check(not _mm._arrastrando, "soltar termina el arrastre")


func _t_ping() -> void:
	_jug._tiene_destino = false
	_mm._gui_input(_clic(Vector2(100, 100), true, true))
	_check(_mm._pings.size() == 1, "Alt+clic crea un ping")
	var pg: Dictionary = _mm._pings[0]
	_check(_cerca(float(pg["x"]), 0.0, 0.05) and _cerca(float(pg["z"]), 0.0, 0.05),
			"el ping queda en el punto del mundo clicado")
	_check(not _jug._tiene_destino, "Alt+clic NO ordena mover (solo ping)")
	_mm._process(2.0)
	_check(_mm._pings.size() == 1, "el ping sigue vivo a los 2 s")
	_mm._process(3.5)
	_check(_mm._pings.is_empty(), "el ping expira solo a los 5 s")


func _t_npcs() -> void:
	var n1: NPC = _npc_en(Vector3(1000, 0, -500))
	var n2: NPC = _npc_en(Vector3(-2000, 0, 1500))
	_mm.fijar_npcs([n1, n2])
	_check(_mm._npcs.size() == 2, "fijar_npcs guarda la lista (puntos dorados)")


func _t_region(db: RegionDB) -> void:
	_check(db.cargar(), "regiones.json carga")
	var r: Dictionary = db.region_en(0, 0)
	var esperado: String = str(r.get("nombre", ""))
	_jug.global_position = Vector3.ZERO
	_mm._process(0.1)
	_check(esperado != "" and _mm._etiqueta.text == esperado,
			"etiqueta muestra la region actual", "etiqueta='%s'" % _mm._etiqueta.text)
	_jug.global_position = Vector3(30000, 0, 0)
	_mm._process(0.1)
	_check(_mm._etiqueta.text == "", "fuera del mapa: etiqueta vacia")


## Fase 1: deja el minimapa con jugador + npcs + ping + fondo y deja que
## _draw corra en los frames siguientes (smoke de dibujado).
func _setup_draw() -> void:
	var t: Terreno = Terreno.new()
	t._colores = PackedColorArray()
	t._colores.resize(Terreno.LADO * Terreno.LADO)
	for i in range(t._colores.size()):
		t._colores[i] = Color(0.25, 0.35, 0.15)
	_mm.configurar(_jug, t, null, null, null)
	_mm._poner_ping(Vector2(100, 100))
	_jug.rotation.y = 0.7
	t.free()


func _finalizar() -> void:
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
