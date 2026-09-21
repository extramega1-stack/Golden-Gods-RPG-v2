extends SceneTree
## Tests headless de la Fase 2 (entidad base única: Entity).
##
## Cómo correrlos (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_entity.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const EN: GDScript = preload("res://scripts/core/entity.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const FM: GDScript = preload("res://scripts/core/formulas.gd")

var _ok: int = 0
var _fallos: int = 0
## Entidades creadas en los tests (viven fuera del árbol; se liberan al final
## para que la salida no muestre leaks de ObjectDB al salir).
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 2 — entidad base")
	_t_nueva_entidad()
	_t_dano_y_senales()
	_t_dano_letal_una_vez()
	_t_heal()
	_t_mana()
	_t_xp_un_nivel()
	_t_xp_varios_niveles()
	_t_dano_sin_fuente()
	_t_guardado()
	_t_guardado_muerto()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).free()
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


## Entidad de referencia: fuerza=10 → vida_max 300; inteligencia=4 → mana_max 110.
func _nueva_ref() -> Entity:
	var sb: StatBlock = SB.new(10.0, 8.0, 6.0, 4.0)
	var e: Entity = EN.new(sb)
	_basura.append(e)
	return e


## from_dict que registra la entidad para liberarla al final.
func _desde_dict(d: Dictionary) -> Entity:
	var e: Entity = EN.from_dict(d)
	_basura.append(e)
	return e


func _t_nueva_entidad() -> void:
	var e: Entity = _nueva_ref()
	_check(e.esta_vivo(), "nueva entidad viva", "")
	_check(is_equal_approx(e.vida_actual, 300.0), "vida_actual = vida_max", str(e.vida_actual))
	_check(is_equal_approx(e.mana_actual, 110.0), "mana_actual = mana_max", str(e.mana_actual))
	_check(e.nivel == 1, "nivel 1", str(e.nivel))
	_check(e.xp_actual == 0, "xp 0", str(e.xp_actual))


func _t_dano_y_senales() -> void:
	var e: Entity = _nueva_ref()
	var fuente: Entity = _nueva_ref()
	var danios: Array = []
	var vidas: Array = []
	e.daniado.connect(func(c, f): danios.append([c, f]))
	e.vida_cambiada.connect(func(v, m): vidas.append([v, m]))
	e.take_damage(30.0, fuente)
	_check(is_equal_approx(e.vida_actual, 270.0), "vida 300-30=270", str(e.vida_actual))
	_check(danios.size() == 1, "senal daniado x1", str(danios.size()))
	_check(is_equal_approx(float(danios[0][0]), 30.0), "daniado con cantidad 30", str(danios[0][0]))
	_check(danios[0][1] == fuente, "daniado con la fuente correcta", "")
	_check(vidas.size() == 1, "senal vida_cambiada x1", str(vidas.size()))
	var vc: bool = is_equal_approx(float(vidas[0][0]), 270.0) and is_equal_approx(float(vidas[0][1]), 300.0)
	_check(vc, "vida_cambiada(270, 300)", str(vidas[0]))
	_check(e.esta_vivo(), "sigue viva", "")


func _t_dano_letal_una_vez() -> void:
	var e: Entity = _nueva_ref()
	var muertes: Array = []
	e.murio.connect(func(_f): muertes.append(1))
	e.take_damage(9999.0, null)
	_check(is_equal_approx(e.vida_actual, 0.0), "vida en 0, nunca bajo 0", str(e.vida_actual))
	_check(not e.esta_vivo(), "muerta tras daño letal", "")
	_check(muertes.size() == 1, "murio x1", str(muertes.size()))
	e.take_damage(50.0, null) # a un muerto no le entra más daño
	e.die() # die() idempotente
	_check(muertes.size() == 1, "murio sigue x1 tras daño extra y die()", str(muertes.size()))
	_check(is_equal_approx(e.vida_actual, 0.0), "vida sigue en 0", str(e.vida_actual))


func _t_heal() -> void:
	var e: Entity = _nueva_ref()
	e.take_damage(100.0, null)
	e.heal(40.0)
	_check(is_equal_approx(e.vida_actual, 240.0), "heal 200+40=240", str(e.vida_actual))
	e.heal(999.0)
	_check(is_equal_approx(e.vida_actual, 300.0), "heal no pasa del max", str(e.vida_actual))
	var m: Entity = _nueva_ref()
	m.take_damage(9999.0, null)
	m.heal(100.0)
	_check(not m.esta_vivo() and is_equal_approx(m.vida_actual, 0.0), "heal no revive muertos", str(m.vida_actual))


func _t_mana() -> void:
	var e: Entity = _nueva_ref() # mana_max 110
	var cambios: Array = []
	e.mana_cambiado.connect(func(v, m): cambios.append([v, m]))
	_check(e.gastar_mana(30.0), "gastar 30 de 110", "")
	_check(is_equal_approx(e.mana_actual, 80.0), "mana 80", str(e.mana_actual))
	_check(not e.gastar_mana(999.0), "no gasta sin mana suficiente", "")
	_check(is_equal_approx(e.mana_actual, 80.0), "mana intacto tras gasto fallido", str(e.mana_actual))
	e.restaurar_mana(999.0)
	_check(is_equal_approx(e.mana_actual, 110.0), "restaurar no pasa del max", str(e.mana_actual))
	_check(cambios.size() == 2, "mana_cambiado x2 (gasto+restaura)", str(cambios.size()))


func _t_xp_un_nivel() -> void:
	var e: Entity = _nueva_ref()
	e.take_damage(100.0, null) # vida 200/300
	var niveles: Array = []
	var xps: Array = []
	e.subio_nivel.connect(func(n): niveles.append(n))
	e.xp_cambiada.connect(func(x, s): xps.append([x, s]))
	e.gain_xp(100) # xp_for_level(2) = 100
	_check(e.nivel == 2, "nivel 2", str(e.nivel))
	_check(e.xp_actual == 100, "xp 100", str(e.xp_actual))
	_check(niveles == [2], "subio_nivel(2) x1", str(niveles))
	_check(xps.size() == 1, "xp_cambiada x1", str(xps.size()))
	_check(int(xps[0][0]) == 100, "xp_cambiada con xp 100", str(xps[0][0]))
	_check(int(xps[0][1]) == FM.xp_for_level(3), "xp_cambiada con xp del siguiente nivel", str(xps[0][1]))
	_check(is_equal_approx(e.vida_actual, 300.0), "al subir de nivel se rellena la vida", str(e.vida_actual))


func _t_xp_varios_niveles() -> void:
	var e: Entity = _nueva_ref()
	var niveles: Array = []
	e.subio_nivel.connect(func(n): niveles.append(n))
	var total_xp: int = 1000000
	e.gain_xp(total_xp)
	var esperado: int = 1
	while total_xp >= FM.xp_for_level(esperado + 1):
		esperado += 1
	_check(e.nivel == esperado, "varios niveles de una vez (nivel %d)" % esperado, str(e.nivel))
	_check(niveles.size() == esperado - 1, "subio_nivel una vez por nivel", str(niveles.size()))
	var orden: bool = true
	for i in range(1, niveles.size()):
		if int(niveles[i]) != int(niveles[i - 1]) + 1:
			orden = false
	_check(orden, "niveles emitidos en orden 2..N", "")
	_check(int(niveles[niveles.size() - 1]) == esperado, "ultimo nivel emitido = nivel final", "")


func _t_dano_sin_fuente() -> void:
	var e: Entity = _nueva_ref()
	var danios: Array = []
	e.daniado.connect(func(c, f): danios.append(f))
	e.take_damage(10.0, null) # daño ambiental
	_check(is_equal_approx(e.vida_actual, 290.0), "daño sin fuente reduce vida", str(e.vida_actual))
	_check(danios.size() == 1 and danios[0] == null, "fuente null en la señal", "")


func _t_guardado() -> void:
	var e: Entity = _nueva_ref()
	e.stats.add_mod("espada", "ataque", SB.ModKind.PLANO, 10.0)
	e.take_damage(50.0, null) # vida 250 (sin subir de nivel)
	e.gain_xp(50) # no alcanza nivel 2 (necesita 100)
	var d: Dictionary = e.to_dict()
	var e2: Entity = _desde_dict(d)
	_check(int(d.get("version", 0)) == 2, "version de guardado = 2", str(d.get("version", 0)))
	_check(e2.nivel == e.nivel, "round-trip: nivel", str(e2.nivel))
	_check(e2.xp_actual == e.xp_actual, "round-trip: xp", str(e2.xp_actual))
	_check(is_equal_approx(e2.vida_actual, e.vida_actual), "round-trip: vida", str(e2.vida_actual))
	_check(is_equal_approx(e2.stats.ataque, 39.0), "round-trip: mods de stats", str(e2.stats.ataque))
	_check(e2.esta_vivo(), "round-trip: sigue viva", "")


func _t_guardado_muerto() -> void:
	var e: Entity = _nueva_ref()
	e.take_damage(9999.0, null)
	var muertes: Array = []
	var e2: Entity = _desde_dict(e.to_dict())
	e2.murio.connect(func(_f): muertes.append(1))
	_check(not e2.esta_vivo(), "se guardo muerta: carga muerta", "")
	_check(is_equal_approx(e2.vida_actual, 0.0), "vida 0 al cargar", str(e2.vida_actual))
	_check(muertes.size() == 0, "cargar no re-emite murio", str(muertes.size()))
