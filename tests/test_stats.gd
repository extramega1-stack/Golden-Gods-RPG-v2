extends SceneTree
## Tests headless de la Fase 1 (datos puros: StatBlock + Formulas).
##
## Cómo correrlos (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_stats.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.

const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const FM: GDScript = preload("res://scripts/core/formulas.gd")

var _ok: int = 0
var _fallos: int = 0


func _init() -> void:
	print("[TEST] Fase 1 — datos puros")
	_t_derivados()
	_t_modificadores()
	_t_dano_normal()
	_t_dano_critico()
	_t_dano_varianza_y_magia()
	_t_dano_defensa_alta()
	_t_mitigacion()
	_t_xp()
	_t_pureza()
	_t_guardado()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


## Bloque de referencia: fuerza=10, agilidad=8, destreza=6, inteligencia=4.
func _nuevo_ref() -> StatBlock:
	var sb: StatBlock = SB.new(10.0, 8.0, 6.0, 4.0)
	return sb


func _t_derivados() -> void:
	var sb: StatBlock = _nuevo_ref()
	_check(is_equal_approx(sb.vida_max, 300.0), "vida_max = 100 + 10*20", str(sb.vida_max))
	_check(is_equal_approx(sb.mana_max, 110.0), "mana_max = 50 + 4*15", str(sb.mana_max))
	_check(is_equal_approx(sb.ataque, 29.0), "ataque = 5 + 10*2 + 8*0.5", str(sb.ataque))
	_check(is_equal_approx(sb.poder, 15.0), "poder = 5 + 4*2.5", str(sb.poder))
	_check(is_equal_approx(sb.defensa, 17.0), "defensa = 10*0.5 + 8*1.5", str(sb.defensa))
	_check(is_equal_approx(sb.crit_prob, 0.074), "crit_prob = 0.05 + 6*0.004", str(sb.crit_prob))
	_check(is_equal_approx(sb.crit_dmg, 1.56), "crit_dmg = 1.5 + 6*0.01", str(sb.crit_dmg))
	_check(is_equal_approx(sb.vel_ataque, 1.064), "vel_ataque = 1 + 8*0.008", str(sb.vel_ataque))
	_check(is_equal_approx(sb.vel_mov, 6.4), "vel_mov = 6 + 8*0.05", str(sb.vel_mov))
	_check(is_equal_approx(sb.get_stat("ataque"), 29.0), "get_stat('ataque')", str(sb.get_stat("ataque")))
	var tope: StatBlock = SB.new(0.0, 0.0, 200.0, 0.0)
	_check(is_equal_approx(tope.crit_prob, 0.60), "crit_prob con tope 0.60", str(tope.crit_prob))


func _t_modificadores() -> void:
	var sb: StatBlock = _nuevo_ref() # ataque base 29
	sb.add_mod("espada", "ataque", SB.ModKind.PLANO, 10.0)
	_check(is_equal_approx(sb.ataque, 39.0), "mod plano +10", str(sb.ataque))
	sb.add_mod("bendicion", "ataque", SB.ModKind.PORCENTUAL, 0.10)
	_check(is_equal_approx(sb.ataque, 42.9), "mod pct +10% sobre (29+10)", str(sb.ataque))
	_check(sb.has_mod("espada"), "has_mod('espada')", "")
	sb.remove_mod("espada")
	_check(is_equal_approx(sb.ataque, 31.9), "quitar mod por fuente", str(sb.ataque))
	sb.clear_mods()
	_check(is_equal_approx(sb.ataque, 29.0), "limpiar mods vuelve a base", str(sb.ataque))


func _defensa_17() -> StatBlock:
	var d: StatBlock = SB.new()
	d.set_base("fuerza", 10.0)
	d.set_base("agilidad", 8.0) # defensa = 10*0.5 + 8*1.5 = 17
	return d


func _skill_fisica() -> Dictionary:
	return {"power": 1.0, "magica": false, "bonus_crit": 0.0, "varianza": 0.0}


func _t_dano_normal() -> void:
	var atk: StatBlock = _nuevo_ref() # ataque 29, crit 0.074
	var defe: StatBlock = _defensa_17()
	var r: Dictionary = FM.damage(atk, defe, _skill_fisica(), 0.99, 0.0)
	# base 29, mitig 100/117, mitigado ≈ 24.786 → final 25, sin crítico.
	_check(not bool(r["crit"]), "sin critico con roll 0.99", str(r["crit"]))
	_check(is_equal_approx(float(r["base"]), 29.0), "dano base 29", str(r["base"]))
	_check(int(r["final"]) == 25, "dano final 25", str(r["final"]))


func _t_dano_critico() -> void:
	var atk: StatBlock = _nuevo_ref()
	var defe: StatBlock = _defensa_17()
	var r: Dictionary = FM.damage(atk, defe, _skill_fisica(), 0.0, 0.0)
	# 24.786 * 1.56 (crit_dmg) ≈ 38.667 → 39.
	_check(bool(r["crit"]), "critico con roll 0.0", str(r["crit"]))
	_check(int(r["final"]) == 39, "dano critico 39", str(r["final"]))


func _t_dano_varianza_y_magia() -> void:
	var atk: StatBlock = _nuevo_ref()
	var defe: StatBlock = _defensa_17()
	var rv: Dictionary = FM.damage(atk, defe, {"power": 1.0, "magica": false, "bonus_crit": 0.0, "varianza": 0.10}, 0.99, 1.0)
	# 24.786 * 1.10 ≈ 27.265 → 27.
	_check(int(rv["final"]) == 27, "varianza +10% inyectada", str(rv["final"]))
	var rm: Dictionary = FM.damage(atk, defe, {"power": 1.0, "magica": true, "bonus_crit": 0.0, "varianza": 0.0}, 0.99, 0.0)
	# poder 15 * 100/117 ≈ 12.82 → 13.
	_check(int(rm["final"]) == 13, "dano magico usa poder", str(rm["final"]))


func _t_dano_defensa_alta() -> void:
	var atk: StatBlock = _nuevo_ref()
	var muro: StatBlock = SB.new()
	muro.add_mod("muro", "defensa", SB.ModKind.PLANO, 10000.0)
	var r: Dictionary = FM.damage(atk, muro, _skill_fisica(), 0.99, 0.0)
	_check(int(r["final"]) == 1, "dano minimo 1 ante defensa enorme", str(r["final"]))


func _t_mitigacion() -> void:
	_check(is_equal_approx(FM.mitigation(0.0), 1.0), "mitigacion(0) = 1.0", str(FM.mitigation(0.0)))
	_check(is_equal_approx(FM.mitigation(100.0), 0.5), "mitigacion(100) = 0.5", str(FM.mitigation(100.0)))
	var m: float = FM.mitigation(17.0)
	_check(m > 0.0 and m < 1.0, "mitigacion(17) en (0,1)", str(m))


func _t_xp() -> void:
	_check(FM.xp_for_level(1) == 0, "xp_for_level(1) = 0", str(FM.xp_for_level(1)))
	_check(FM.xp_for_level(2) == 100, "xp_for_level(2) = 100", str(FM.xp_for_level(2)))
	var mono: bool = true
	var prev: int = FM.xp_for_level(1)
	for n in range(2, 101):
		var cur: int = FM.xp_for_level(n)
		if cur <= prev:
			mono = false
		prev = cur
	_check(mono, "curva de XP estrictamente creciente (1..100)", "")


func _t_pureza() -> void:
	var atk: StatBlock = _nuevo_ref()
	var defe: StatBlock = _defensa_17()
	var a: Dictionary = FM.damage(atk, defe, _skill_fisica(), 0.5, 0.0)
	var b: Dictionary = FM.damage(atk, defe, _skill_fisica(), 0.5, 0.0)
	_check(int(a["final"]) == int(b["final"]) and bool(a["crit"]) == bool(b["crit"]), "damage pura: mismas entradas, misma salida", "")


func _t_guardado() -> void:
	var sb: StatBlock = _nuevo_ref()
	sb.add_mod("espada", "ataque", SB.ModKind.PLANO, 10.0)
	var d: Dictionary = sb.to_dict()
	var sb2: StatBlock = SB.from_dict(d)
	_check(is_equal_approx(sb2.fuerza, 10.0), "round-trip: base", str(sb2.fuerza))
	_check(is_equal_approx(sb2.ataque, 39.0), "round-trip: mods", str(sb2.ataque))
