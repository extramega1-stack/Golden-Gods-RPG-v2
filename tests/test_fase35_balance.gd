extends SceneTree
## Tests headless de la Fase 35 (balance: HP de basura + curas por poder).
##
## Cubre (skill `rpg`: fórmula deliberada, números acotados, datos no código):
## (a) datos: basura con mult_vida 0.8; jefes sin ajuste (default 1.0);
## (b) configurar() aplica el mult vía MOD reversible (240/300) y llena;
##     sin clave la vida queda intacta; el pool lo re-aplica al reiniciar;
## (c) TTK determinista: guerrero fresco mata goblin en 4 golpes (el ritmo
##     previo a la fase 34), sin críticos ni varianza;
## (d) bono_curacion(): 1.0 con poder 0, 1.4 con poder 80, monótono y
##     acotado (poder 300 → ×2.5);
## (e) lanzar curación e2e escala con poder y respeta el tope de vida;
## (f) el save conserva el mod de balance (round-trip 240).
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase35_balance.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const SS: GDScript = preload("res://scripts/skills/skill_system.gd")
const FM: GDScript = preload("res://scripts/core/formulas.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 35 — balance HP + curas por poder")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_datos()
	_test_configurar()
	_test_ttk()
	_test_bono()
	_test_cura_e2e()
	_test_save()
	print("[TEST] fase35_balance: %d ok, %d fallos" % [_ok, _fallos])
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


func _arquetipos() -> Dictionary:
	var datos: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/enemies.json"))
	return (datos as Dictionary).get("arquetipos", {})


func _guerrero() -> Player:
	var p: Player = PL.new()
	p.fijar_identidad("T", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	return p


func _mob(aq: Dictionary) -> Enemy:
	var e: Enemy = EN.new()
	root.add_child(e)
	_basura.append(e)
	e.configurar(aq)
	return e


## Golpes sin crítico ni varianza para matar al mob (determinista).
func _hits_para_matar(atacante: Player, objetivo: Enemy) -> int:
	var r: Dictionary = FM.damage(atacante.stats, objetivo.stats,
		{"power": 1.0, "magica": false, "bonus_crit": 0.0, "varianza": 0.0},
		0.99, 0.0)
	return int(ceil(objetivo.stats.vida_max / maxf(float(r["final"]), 1.0)))


## (a) Datos.
func _test_datos() -> void:
	var aqs: Dictionary = _arquetipos()
	for k in ["goblin", "lobo", "ogro"]:
		_chk(float((aqs.get(k, {}) as Dictionary).get("mult_vida", 0.0)) == 0.8,
			"a: %s mult_vida 0.8" % k)
	for k in ["aullido_pico", "campeon_caido", "devorador_dunas",
			"eco_cristal", "fundidor_antiguo", "susurro_umbral"]:
		_chk(not ((aqs.get(k, {}) as Dictionary).has("mult_vida")),
			"a: el jefe %s sin ajuste" % k)


## (b) configurar() aplica el mult.
func _test_configurar() -> void:
	var aqs: Dictionary = _arquetipos()
	var g: Enemy = _mob((aqs.get("goblin", {}) as Dictionary).duplicate(true))
	_chk(is_equal_approx(g.stats.vida_max, 240.0),
		"b: goblin 300 × 0.8 = 240", str(g.stats.vida_max))
	_chk(is_equal_approx(g.vida_actual, 240.0), "b: nace lleno")
	_chk(g.stats.has_mod("balance:vida"), "b: vía MOD reversible")
	var j: Enemy = _mob((aqs.get("aullido_pico", {}) as Dictionary).duplicate(true))
	_chk(not j.stats.has_mod("balance:vida"), "b: el jefe sin mod")
	_chk(is_equal_approx(j.stats.vida_max, 100.0 + 26.0 * 20.0),
		"b: vida del jefe intacta", str(j.stats.vida_max))
	# El pool re-aplica al reiniciar (configurar fresco, sin mods viejos).
	g.stats.add_mod("externo", "ataque", StatBlock.ModKind.PLANO, 99.0)
	g.reiniciar((aqs.get("goblin", {}) as Dictionary).duplicate(true))
	_chk(is_equal_approx(g.stats.vida_max, 240.0)
			and not g.stats.has_mod("externo"),
		"b: reiniciar re-aplica limpio")


## (c) TTK del ritmo previo a la fase 34.
func _test_ttk() -> void:
	var aqs: Dictionary = _arquetipos()
	var p: Player = _guerrero()
	for k in ["goblin", "lobo", "ogro"]:
		var e: Enemy = _mob((aqs.get(k, {}) as Dictionary).duplicate(true))
		_chk(_hits_para_matar(p, e) == 4,
			"c: guerrero mata %s en 4 golpes" % k)


## (d) Bono de curación puro.
func _test_bono() -> void:
	_chk(is_equal_approx(SS.bono_curacion(0.0), 1.0), "d: poder 0 → ×1.0")
	_chk(is_equal_approx(SS.bono_curacion(80.0), 1.4), "d: poder 80 → ×1.4")
	_chk(SS.bono_curacion(200.0) > SS.bono_curacion(80.0), "d: monótono")
	_chk(is_equal_approx(SS.bono_curacion(300.0), 2.5), "d: acotado ×2.5")
	_chk(is_equal_approx(SS.bono_curacion(-50.0), 1.0), "d: poder negativo → ×1.0")


## (e) Curación e2e con poder y tope.
func _test_cura_e2e() -> void:
	var p: Player = PL.new()
	p.fijar_identidad("C", "clerigo")
	p.aplicar_clase("clerigo")
	root.add_child(p)
	_basura.append(p)
	_chk(is_equal_approx(p.stats.poder, 80.0), "e: poder del clérigo 80",
		str(p.stats.poder))
	p.take_damage(200.0, null)
	var vida0: float = p.vida_actual
	_chk(p.skills.lanzar("curacion_menor", p, null), "e: se lanza")
	_chk(is_equal_approx(p.vida_actual, vida0 + 112.0),
		"e: cura 80 × 1.4 = 112", str(p.vida_actual))
	p.heal(99999.0)
	_chk(is_equal_approx(p.vida_actual, p.stats.vida_max), "e: respeta el tope")


## (f) El save conserva el ajuste.
func _test_save() -> void:
	var aqs: Dictionary = _arquetipos()
	var e: Enemy = _mob((aqs.get("lobo", {}) as Dictionary).duplicate(true))
	var e2: Enemy = EN.new()
	root.add_child(e2)
	_basura.append(e2)
	e2.restaurar(e.to_dict())
	_chk(is_equal_approx(e2.stats.vida_max, 240.0),
		"f: el ajuste sobrevive al save", str(e2.stats.vida_max))
