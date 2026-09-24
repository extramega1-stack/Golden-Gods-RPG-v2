extends SceneTree
## Tests headless de la Fase 42 (fixes de playtest: barra, arena, daño).
##
## (a) Barra de vida: UNA sola barra. El frente usa malla propia que se
##     redimensiona (el billboard ignora scale.x del nodo) y el nodo no
##     lleva escala.
## (b) Arena: centro_campo() existe y devuelve el centro de data/arena.json
##     (el "Entrenar" reventaba con Nonexistent function).
## (c) Stat principal de daño por clase (data/clases.json → StatBlock):
##     guerrero STR, arquero/daguero DEX, mago/clérigo INT. Subir el stat
##     principal sube `ataque` y `poder`; los demás no tocan el daño.
## (d) Player.repartir_atributo (el bug reportado): +1 DEX al daguero sube
##     su ataque base, y las skills (punalada) escalan con él.
## (e) Save: stat_daño en round-trip; dict v1 sin el campo → "fuerza".
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase42_dano.gd

const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const CDB: GDScript = preload("res://scripts/player/clase_db.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const FM: GDScript = preload("res://scripts/core/formulas.gd")
const SS: GDScript = preload("res://scripts/skills/skill_system.gd")
const SDB: GDScript = preload("res://scripts/skills/skill_db.gd")
const AR: GDScript = preload("res://scripts/arena/arena.gd")
const BVM: GDScript = preload("res://scripts/combate/barra_vida_mob.gd")
const ENT: GDScript = preload("res://scripts/core/entity.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 42 — barra, arena y daño por stat principal")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_barra()
	_test_arena()
	_test_datos_clase()
	_test_escalado()
	_test_player()
	_test_skills()
	_test_save()
	print("[TEST] fase42_dano: %d ok, %d fallos" % [_ok, _fallos])
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


## (a) Barra: una sola, el frente crece por MALLA (no por scale del nodo).
func _test_barra() -> void:
	var e: Entity = ENT.new(SB.new(20.0, 20.0, 20.0, 20.0))
	var barra: BarraVidaMob = BVM.new()
	e.add_child(barra)
	root.add_child(e)
	_basura.append(e)
	_chk(barra._fg != null and barra._fondo != null, "a: dos quads (frente+fondo)")
	_chk(barra._fg.scale == Vector3.ONE,
		"a: el nodo frente NO lleva escala (billboard la ignoraría)",
		str(barra._fg.scale))
	_chk(barra._fg.position == Vector3.ZERO,
		"a: el frente NO se desplaza (caía al lado)", str(barra._fg.position))
	_chk(barra._quad_frente != null, "a: frente con malla propia")
	e.take_damage(e.stats.vida_max * 0.5, null)
	_chk(is_equal_approx(barra._quad_frente.size.x, BVM.ANCHO * 0.5),
		"a: malla del frente = 50%", str(barra._quad_frente.size.x))
	_chk(is_equal_approx(barra._quad_frente.size.y, BVM.ALTO),
		"a: alto intacto")
	_chk(is_equal_approx(barra._quad_frente.center_offset.x, BVM.ANCHO * 0.25),
		"a: crece desde la izquierda", str(barra._quad_frente.center_offset.x))
	e.take_damage(e.stats.vida_max * 0.25, null)
	_chk(is_equal_approx(barra._quad_frente.size.x, BVM.ANCHO * 0.25),
		"a: 25% tras más daño", str(barra._quad_frente.size.x))


## (b) Arena: centro_campo() (el "Entrenar" fallaba con Nonexistent function).
func _test_arena() -> void:
	var a: Arena = AR.new()
	_basura.append(a)
	var datos: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/arena.json"))
	a.configurar(datos as Dictionary)
	var centro: Vector3 = a.centro_campo()
	_chk(not is_zero_approx(centro.x) and not is_zero_approx(centro.z),
		"b: centro del campo", str(centro))
	_chk(centro.distance_to(Vector3(-2000.0, 0.0, -8000.0)) < 1.0,
		"b: centro = (-2000, -8000)", str(centro))


## (c) El stat principal vive en data/clases.json.
func _test_datos_clase() -> void:
	_chk(CDB.stat_daño("guerrero") == "fuerza", "c: guerrero → fuerza")
	_chk(CDB.stat_daño("arquero") == "destreza", "c: arquero → destreza")
	_chk(CDB.stat_daño("daguero") == "destreza", "c: daguero → destreza")
	_chk(CDB.stat_daño("mago") == "inteligencia", "c: mago → inteligencia")
	_chk(CDB.stat_daño("clerigo") == "inteligencia", "c: clerigo → inteligencia")
	_chk(CDB.stat_daño("no_existe") == "fuerza", "c: clase desconocida → fuerza")


## (d) Subir el stat principal sube ataque y poder; los otros no.
func _test_escalado() -> void:
	# Guerrero (STR): +1 fuerza → +2 ataque / +2 poder.
	var g: StatBlock = SB.new(30.0, 30.0, 15.0, 15.0)
	g.set_stat_daño("fuerza")
	var a0: float = g.ataque
	var p0: float = g.poder
	g.set_base("fuerza", 31.0)
	_chk(is_equal_approx(g.ataque, a0 + 2.0), "d: guerrero +1 STR → +2 ataque",
		str(g.ataque - a0))
	_chk(is_equal_approx(g.poder, p0 + 2.0), "d: guerrero +1 STR → +2 poder",
		str(g.poder - p0))
	# Arquero/Daguero (DEX): +1 destreza → +1.75 ataque y poder; +1 fuerza → nada.
	var d: StatBlock = SB.new(15.0, 15.0, 45.0, 15.0)
	d.set_stat_daño("destreza")
	a0 = d.ataque
	p0 = d.poder
	d.set_base("destreza", 46.0)
	_chk(is_equal_approx(d.ataque, a0 + 1.75), "d: daguero +1 DEX → +1.75 ataque",
		str(d.ataque - a0))
	_chk(is_equal_approx(d.poder, p0 + 1.75), "d: daguero +1 DEX → +1.75 poder",
		str(d.poder - p0))
	a0 = d.ataque
	d.set_base("fuerza", 16.0)
	_chk(is_equal_approx(d.ataque, a0), "d: daguero +1 STR no toca su daño",
		str(d.ataque - a0))
	# Mago/Clérigo (INT): +1 inteligencia → +2.5 poder.
	var m: StatBlock = SB.new(15.0, 15.0, 15.0, 45.0)
	m.set_stat_daño("inteligencia")
	p0 = m.poder
	m.set_base("inteligencia", 46.0)
	_chk(is_equal_approx(m.poder, p0 + 2.5), "d: mago +1 INT → +2.5 poder",
		str(m.poder - p0))
	# Stat inválido no cambia nada.
	_chk(not m.set_stat_daño("agilidad"), "d: stat inválido rechazado")
	_chk(m.stat_daño == "inteligencia", "d: stat sigue inteligenica")


## (e) El bug reportado: repartir +1 DEX al daguero sube su ataque, y la
##     skill física escala con el (Formulas.damage lee `ataque`).
func _test_player() -> void:
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)
	p.fijar_identidad("Sombra", "daguero")
	p.aplicar_clase("daguero")
	_chk(p.stats.stat_daño == "destreza", "e: player toma el stat de su clase",
		p.stats.stat_daño)
	_chk(is_equal_approx(p.stats.ataque, 5.0 + 45.0 * 1.75),
		"e: ataque daguero = 5 + DEX×1.75", str(p.stats.ataque))
	var atk0: float = p.stats.ataque
	var poder0: float = p.stats.poder
	var mana0: float = p.mana_actual
	p.puntos_atributo = 1
	_chk(p.repartir_atributo("destreza") == "ok", "e: +1 DEX repartido")
	_chk(p.stats.destreza == 46.0, "e: DEX sube", str(p.stats.destreza))
	_chk(p.stats.ataque > atk0, "e: el ataque base sube (+%.2f)" % (p.stats.ataque - atk0))
	_chk(p.stats.poder > poder0, "e: el poder sube (+%.2f)" % (p.stats.poder - poder0))
	_chk(p.stats.crit_prob > 0.23, "e: el crítico también sube",
		str(p.stats.crit_prob))
	_chk(p.stats.vel_ataque > 1.36, "e: la vel. de ataque también sube",
		str(p.stats.vel_ataque))
	# Magia: +1 INT al mago sube poder y maná; curas escalan con poder.
	var g: Player = PL.new()
	root.add_child(g)
	_basura.append(g)
	g.fijar_identidad("Mago", "mago")
	g.aplicar_clase("mago")
	var poder_m0: float = g.stats.poder
	var mana_m0: float = g.stats.mana_max
	var bonus0: float = SS.bono_curacion(g.stats.poder)
	g.puntos_atributo = 1
	_chk(g.repartir_atributo("inteligencia") == "ok", "e: +1 INT al mago")
	_chk(g.stats.poder > poder_m0, "e: poder del mago sube",
		str(g.stats.poder - poder_m0))
	_chk(g.stats.mana_max > mana_m0, "e: maná del mago sube")
	_chk(SS.bono_curacion(g.stats.poder) > bonus0,
		"e: las curas escalan con INT (bono_curacion)")


## (f) Las skills escalan con el stat principal.
func _test_skills() -> void:
	SDB.cargar()
	var sb: StatBlock = SB.new(15.0, 15.0, 45.0, 15.0)
	sb.set_stat_daño("destreza")
	var skill: Dictionary = SDB.obtener("punalada")
	var r0: Dictionary = FM.damage(sb, SB.new(), skill, 0.99, 0.0)
	sb.set_base("destreza", 46.0)
	var r1: Dictionary = FM.damage(sb, SB.new(), skill, 0.99, 0.0)
	_chk(float(r1["base"]) > float(r0["base"]),
		"f: punalada escala con +1 DEX", "%s -> %s" % [r0["base"], r1["base"]])
	var sm: StatBlock = SB.new(15.0, 15.0, 15.0, 45.0)
	sm.set_stat_daño("inteligencia")
	var fuego: Dictionary = SDB.obtener("bola_fuego")
	var m0: Dictionary = FM.damage(sm, SB.new(), fuego, 0.99, 0.0)
	sm.set_base("inteligencia", 46.0)
	var m1: Dictionary = FM.damage(sm, SB.new(), fuego, 0.99, 0.0)
	_chk(float(m1["base"]) > float(m0["base"]),
		"f: bola de fuego escala con +1 INT", "%s -> %s" % [m0["base"], m1["base"]])


## (g) Save: stat_daño en round-trip; v1 sin campo → fuerza.
func _test_save() -> void:
	var sb: StatBlock = SB.new(15.0, 15.0, 45.0, 15.0)
	sb.set_stat_daño("destreza")
	var d: Dictionary = sb.to_dict()
	_chk(int(d.get("version", 0)) == 2, "g: StatBlock v2", str(d.get("version", 0)))
	_chk(str(d.get("stat_daño", "")) == "destreza", "g: stat_daño guardado")
	var sb2: StatBlock = SB.from_dict(d)
	_chk(sb2.stat_daño == "destreza", "g: round-trip conserva stat_daño")
	_chk(is_equal_approx(sb2.ataque, sb.ataque), "g: round-trip mismo ataque")
	var viejo: StatBlock = SB.from_dict({"version": 1, "base": {
		"fuerza": 30.0, "aguante": 15.0, "destreza": 15.0, "inteligencia": 15.0}})
	_chk(viejo.stat_daño == "fuerza", "g: save v1 → fuerza (tolerante)")
	_chk(is_equal_approx(viejo.ataque, 65.0), "g: ataque v1 = 65", str(viejo.ataque))
