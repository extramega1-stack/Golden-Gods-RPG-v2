extends SceneTree
## Tests headless de la Fase 31 (skills nivel 1–20 estilo FlyFF).
##
## Cubre:
## (a) skills.json: 32 skills con max_nivel=20, power_nivel, mana_nivel;
##     curación migrada a power (curacion_menor=80, luz_sanadora=200);
## (b) configurar_clase: skills de la clase en 1, ajenas en 0; al cambiar
##     de clase devuelve los puntos invertidos y es idempotente;
## (c) subir_nivel: gasta puntos, escala power/maná, tope 20, motivos;
## (d) lanzar: power_efectivo en daño/cura, mana_efectivo gastado,
##     "no_aprendida" para skills ajenas;
## (e) Player: 2 puntos_skill por nivel; save v10 con bloque skills y
##     carga v9 tolerante (skills de la clase en 1).
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase31_skills.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const SS: GDScript = preload("res://scripts/skills/skill_system.gd")
const SV: GDScript = preload("res://scripts/save/save_system.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 31 — skills nivel 1–20")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	SkillDB.cargar()
	_test_json()
	_test_configurar()
	_test_subir()
	_test_lanzar()
	_test_player_save()
	print("[TEST] fase31_skills: %d ok, %d fallos" % [_ok, _fallos])
	if _fallos == 0:
		print("[TEST] TODO VERDE")
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


func _player(clase: String = "guerrero") -> Player:
	var p: Player = PL.new()
	p.nombre = "Test"
	p.clase_id = clase
	root.add_child(p)
	_basura.append(p)
	return p


## (a) JSON: campos de nivel en las 32 + migración de curación.
func _test_json() -> void:
	_chk(SkillDB.lista().size() == 32, "a: 32 skills en el JSON")
	for sid in SkillDB.lista():
		var sk: Dictionary = SkillDB.obtener(sid)
		_chk(int(sk.get("max_nivel", 0)) == 20, "a: max_nivel 20 en " + sid)
		_chk(sk.has("power_nivel") and sk.has("mana_nivel"),
			"a: power_nivel + mana_nivel en " + sid)
	_chk(float(SkillDB.obtener("curacion_menor").get("power", 0.0)) == 80.0,
		"a: curacion_menor power=80 (migración)")
	_chk(float(SkillDB.obtener("luz_sanadora").get("power", 0.0)) == 200.0,
		"a: luz_sanadora power=200 (migración)")


## (b) configurar_clase: niveles iniciales, purga con devolución, idempotencia.
func _test_configurar() -> void:
	var s: SkillSystem = SS.new()
	s.puntos_skill = 0
	_chk(s.configurar_clase("guerrero") == 0, "b: primera config no devuelve nada")
	_chk(s.nivel_de("golpe_heroico") == 1, "b: skill propia en 1")
	_chk(s.nivel_de("descarga_arcana") == 0, "b: skill ajena en 0")
	# Invierto 3 puntos en guerrero y cambio a mago: devuelve 3.
	s.puntos_skill = 3
	_chk(s.subir_nivel("golpe_heroico") == "ok", "b: subir nv2")
	_chk(s.subir_nivel("golpe_heroico") == "ok", "b: subir nv3")
	_chk(s.subir_nivel("golpe_heroico") == "ok", "b: subir nv4")
	_chk(s.nivel_de("golpe_heroico") == 4, "b: golpe_heroico en nv4")
	_chk(s.configurar_clase("mago") == 3, "b: cambiar de clase devuelve 3")
	_chk(s.nivel_de("golpe_heroico") == 0, "b: la vieja se borra")
	_chk(s.nivel_de("descarga_arcana") == 1, "b: la nueva empieza en 1")
	_chk(s.puntos_skill == 3, "b: puntos devueltos", str(s.puntos_skill))
	# Idempotente: repetir la misma clase no reinicia nada.
	s.puntos_skill = 2
	s.subir_nivel("descarga_arcana")
	_chk(s.configurar_clase("mago") == 0, "b: misma clase no devuelve nada")
	_chk(s.nivel_de("descarga_arcana") == 2,
		"b: misma clase conserva el nivel", str(s.nivel_de("descarga_arcana")))
	_chk(s.puntos_skill == 1, "b: misma clase no toca puntos",
		str(s.puntos_skill))


## (c) subir_nivel: gasto, escala, topes y motivos.
func _test_subir() -> void:
	var s: SkillSystem = SS.new()
	s.configurar_clase("guerrero")
	_chk(s.puede_subir("descarga_arcana") == "no_aprendida",
		"c: ajena no se sube")
	_chk(s.puede_subir("no_existe") == "desconocida", "c: desconocida no se sube")
	_chk(s.puede_subir("golpe_heroico") == "sin_puntos", "c: sin puntos no se sube")
	_chk(s.subir_nivel("golpe_heroico") == "sin_puntos", "c: subir sin puntos")
	s.puntos_skill = 25
	var p1: float = s.power_efectivo("golpe_heroico")
	var m1: float = s.mana_efectivo("golpe_heroico")
	_chk(s.subir_nivel("golpe_heroico") == "ok", "c: subir ok")
	_chk(s.nivel_de("golpe_heroico") == 2, "c: nv2")
	_chk(s.puntos_skill == 24, "c: gastó 1 punto")
	var base: Dictionary = SkillDB.obtener("golpe_heroico")
	_chk(is_equal_approx(s.power_efectivo("golpe_heroico"),
			p1 + float(base.get("power_nivel", 0.0))),
		"c: power escala por nivel", str(s.power_efectivo("golpe_heroico")))
	_chk(is_equal_approx(s.mana_efectivo("golpe_heroico"),
			m1 + float(base.get("mana_nivel", 0.0))),
		"c: maná escala por nivel")
	# Tope 20.
	for i in range(18):
		s.subir_nivel("golpe_heroico")
	_chk(s.nivel_de("golpe_heroico") == 20, "c: tope nv20")
	_chk(s.subir_nivel("golpe_heroico") == "max_nivel", "c: más allá de 20 no")
	_chk(s.puede_subir("golpe_heroico") == "max_nivel", "c: motivo max_nivel")
	# Curación escala desde power migrado.
	var c: SkillSystem = SS.new()
	c.configurar_clase("clerigo")
	_chk(is_equal_approx(c.power_efectivo("curacion_menor"), 80.0),
		"c: cura nv1 = 80", str(c.power_efectivo("curacion_menor")))
	c.puntos_skill = 1
	c.subir_nivel("curacion_menor")
	_chk(is_equal_approx(c.power_efectivo("curacion_menor"), 86.0),
		"c: cura nv2 = 86", str(c.power_efectivo("curacion_menor")))


## (d) lanzar: efectivos aplicados, maná gastado, no_aprendida.
func _test_lanzar() -> void:
	var p: Player = _player("guerrero")
	var dummy: Player = _player("guerrero")
	p.skills.puntos_skill = 2
	p.skills.subir_nivel("golpe_heroico")
	p.skills.subir_nivel("golpe_heroico")  # nv3
	_chk(p.skills.puede_lanzar("descarga_arcana", p, dummy) == "no_aprendida",
		"d: ajena no se lanza")
	var mana0: float = p.mana_actual
	_chk(p.skills.lanzar("golpe_heroico", p, dummy),
		"d: lanzar golpe_heroico nv3")
	_chk(is_equal_approx(p.mana_actual, mana0 - p.skills.mana_efectivo("golpe_heroico")),
		"d: gasta maná efectivo", str(p.mana_actual))
	# Curación e2e: la fuente es power_efectivo (80 a nv1) × bono de poder
	# (fase 35: clérigo poder 80 → ×1.4 → 112).
	var c: Player = _player("clerigo")
	c.aplicar_clase("clerigo")
	c.take_damage(200.0, c, false)
	var vida0: float = c.vida_actual
	var mana_c0: float = c.mana_actual
	_chk(c.skills.lanzar("curacion_menor", c, null), "d: lanzar curacion_menor")
	_chk(is_equal_approx(c.vida_actual, minf(c.stats.vida_max, vida0 + 112.0)),
		"d: cura 112 a nv1 (80 × 1.4)", str(c.vida_actual))
	_chk(is_equal_approx(c.mana_actual, mana_c0 - c.skills.mana_efectivo("curacion_menor")),
		"d: cura gasta maná efectivo")


## (e) Player: 2 puntos por nivel; save v10 con bloque; carga v9 tolerante.
func _test_player_save() -> void:
	var p: Player = _player("guerrero")
	_chk(p.skills.nivel_de("golpe_heroico") == 1,
		"e: player guerrero arranca con skills en 1")
	_chk(p.skills.puntos_skill == 0, "e: 0 puntos al arrancar")
	p.gain_xp(100000)
	_chk(p.skills.puntos_skill == (p.nivel - 1) * 2,
		"e: 2 puntos_skill por nivel", str(p.skills.puntos_skill))
	# Guardar con niveles comprados.
	DirAccess.remove_absolute("user://partida.json")
	p.skills.subir_nivel("golpe_heroico")
	var s: SaveSystem = SV.new()
	s.jugador = p
	s.enemigos = []
	s.npcs = []
	s.tienda = null
	s.misiones = null
	s.barra_acciones = null
	_chk(s.guardar(), "e: guardar() true")
	var crudo: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.RUTA))
	var dj: Dictionary = (crudo as Dictionary).get("jugador", {})
	_chk(int((crudo as Dictionary).get("version", 0)) == 11,
		"e: version 11 en disco (fase 39)")
	var blk: Dictionary = dj.get("skills", {})
	_chk(int(blk.get("version", 0)) == 1, "e: bloque skills v1")
	_chk(int(blk.get("puntos_skill", -1)) == p.skills.puntos_skill,
		"e: puntos_skill guardados")
	_chk(int((blk.get("niveles", {}) as Dictionary).get("golpe_heroico", 0)) == 2,
		"e: nivel golpe_heroico=2 guardado")
	# Cargar v10 restaura.
	var p2: Player = PL.new()
	var s2: SaveSystem = SV.new()
	s2.jugador = p2
	_chk(s2.cargar(), "e: cargar() v10 true")
	_chk(p2.skills.nivel_de("golpe_heroico") == 2,
		"e: nivel restaurado", str(p2.skills.nivel_de("golpe_heroico")))
	_chk(p2.skills.puntos_skill == p.skills.puntos_skill,
		"e: puntos restaurados")
	# Carga v9 (sin bloque "skills"): skills de la clase en 1, 0 puntos.
	var sin_bloque: Dictionary = (crudo as Dictionary).duplicate(true)
	(sin_bloque.get("jugador", {}) as Dictionary).erase("skills")
	var f: FileAccess = FileAccess.open(SaveSystem.RUTA, FileAccess.WRITE)
	f.store_string(JSON.stringify(sin_bloque))
	f.close()
	var p3: Player = PL.new()
	var s3: SaveSystem = SV.new()
	s3.jugador = p3
	_chk(s3.cargar(), "e: cargar() v9 true")
	_chk(p3.skills.nivel_de("golpe_heroico") == 1,
		"e: v9 → skills de la clase en 1")
	_chk(p3.skills.puntos_skill == 0, "e: v9 → 0 puntos")
	DirAccess.remove_absolute("user://partida.json")
