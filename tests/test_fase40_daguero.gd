extends SceneTree
## Tests headless de la Fase 40 (daguero, quinta clase jugable).
##
## Cubre (skill `rpg`: build diversity con datos, no código):
## (a) clase: jugable, base 15/15/45/15 y derivados (ataque 35, vida 625,
##     maná 275, crit 23% ×1.95, vel.atq 1.36); el Player la aplica con
##     vida llena y skills en 1;
## (b) 8 skills en orden que se lanzan de verdad (daño/aoe/debuff/buff
##     contra un dummy, con cooldowns y gasto de maná);
## (c) 3 talentos en orden que suben y aplican mods (asesino de críticos).
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase40_daguero.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const CDB: GDScript = preload("res://scripts/player/clase_db.gd")
const SDB: GDScript = preload("res://scripts/skills/skill_db.gd")
const TDB: GDScript = preload("res://scripts/skills/talento_db.gd")
const TAL: GDScript = preload("res://scripts/skills/talentos.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")

const ORDEN: Array[String] = ["punalada", "golpe_bajo", "filo_venenoso",
	"danza_dagas", "evasion_sombra", "instinto_asesino", "golpe_gracia",
	"paso_sombra"]

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []
var _usadas: Array[String] = []


func _init() -> void:
	print("[TEST] Fase 40 — daguero jugable")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_clase()
	_test_skills()
	_test_talentos()
	print("[TEST] fase40_daguero: %d ok, %d fallos" % [_ok, _fallos])
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


func _player() -> Player:
	var p: Player = PL.new()
	p.clase_id = "daguero"
	root.add_child(p)
	_basura.append(p)
	return p


func _dummy() -> Enemy:
	var e: Enemy = EN.new()
	e.add_to_group("enemigos")
	root.add_child(e)
	_basura.append(e)
	e.configurar({
		"nombre": "Dummy", "fuerza": 40.0, "destreza": 5.0,
		"inteligencia": 5.0, "color": [0.5, 0.5, 0.5],
	})
	return e


## (a) Clase y derivados.
func _test_clase() -> void:
	_chk(CDB.es_jugable("daguero"), "a: daguero jugable")
	var base: Dictionary = CDB.stats_base("daguero")
	_chk(float(base.get("fuerza", -1.0)) == 15.0
			and float(base.get("aguante", -1.0)) == 15.0
			and float(base.get("destreza", -1.0)) == 45.0
			and float(base.get("inteligencia", -1.0)) == 15.0,
		"a: base 15/15/45/15", str(base))
	var s: StatBlock = SB.new(15.0, 15.0, 45.0, 15.0)
	_chk(is_equal_approx(s.ataque, 35.0), "a: ataque 35", str(s.ataque))
	_chk(is_equal_approx(s.vida_max, 625.0), "a: vida 625", str(s.vida_max))
	_chk(is_equal_approx(s.mana_max, 275.0), "a: maná 275", str(s.mana_max))
	_chk(is_equal_approx(s.crit_prob, 0.23), "a: crit 23%", str(s.crit_prob))
	_chk(is_equal_approx(s.crit_dmg, 1.95), "a: crit ×1.95", str(s.crit_dmg))
	_chk(is_equal_approx(s.vel_ataque, 1.36), "a: vel.atq 1.36",
		str(s.vel_ataque))
	var p: Player = _player()
	p.fijar_identidad("Sombra", "daguero")
	p.aplicar_clase("daguero")
	_chk(is_equal_approx(p.vida_actual, 625.0), "a: player nace lleno")
	_chk(p.skills.nivel_de("punalada") == 1, "a: skills en 1")


## (b) Las 8 skills se lanzan de verdad.
func _test_skills() -> void:
	_chk(SDB.skills_por_clase("daguero") == ORDEN,
		"b: 8 skills en orden", str(SDB.skills_por_clase("daguero")))
	var p: Player = _player()
	var e: Enemy = _dummy()
	p.seleccionar(e)
	p.mana_actual = 9999.0
	_usadas.clear()
	p.skills.skill_usada.connect(func(sid: String) -> void: _usadas.append(sid))
	var vida0: float = e.vida_actual
	for i in range(ORDEN.size()):
		p.lanzar_skill(i)
	for sid in ORDEN:
		_chk(_usadas.has(sid), "b: se lanzó " + sid, str(_usadas))
		_chk(p.skills.cooldown_restante(sid) > 0.0,
			"b: cooldown en " + sid)
	_chk(e.vida_actual < vida0, "b: el dummy sangra",
		"%f -> %f" % [vida0, e.vida_actual])
	_chk(e.vida_actual > 0.0, "b: el dummy sobrevive (900 HP)")


## (c) Talentos del daguero.
func _test_talentos() -> void:
	_chk(TDB.talentos_por_clase("daguero") == ["sangre_fria", "paso_letal",
		"danza_mortal"], "c: 3 en orden",
		str(TDB.talentos_por_clase("daguero")))
	var t: Talentos = TAL.new()
	_basura.append(t)
	var s: StatBlock = SB.new(15.0, 15.0, 45.0, 15.0)
	var crit0: float = s.crit_prob
	t.puntos = 3
	_chk(t.subir("sangre_fria", s, 5, "daguero") == "ok", "c: subir ok")
	_chk(is_equal_approx(s.crit_prob, crit0 + 0.02),
		"c: +2% crit por rango", str(s.crit_prob))
	_chk(t.subir("filo_pesado", s, 5, "daguero") == "clase",
		"c: talento ajeno no")
	_chk(t.subir("sangre_fria", s, 5, "mago") == "clase",
		"c: clase mandona no")
