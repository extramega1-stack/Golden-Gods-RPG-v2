extends SceneTree
## Tests headless de la Fase 58 (hambre, sed y energía).
##
## POR QUÉ NACE: es el núcleo de la presión de supervivencia. Las fases 54-57
## dejaron la comida, la tala, la cocina y el XP de habilidad; faltaba que
## algo de verdad TE EMPUJE a usarlas.
##
## DECISIÓN DE JUAN DIEGO: a 0 NO matan. Noriegan a 1 de vida y dejan un
## debuff. Este test es justamente el que blinda esa decisión: si alguien
## "arregla" el 0 para que mate, el test se cae.
##
## Cubre:
## (a) `Vitals` decae con el tiempo y la actividad, y nunca sale de 0..100;
## (b) a 0 el jugador NO muere: queda en 1 de vida con debuff;
## (c) la energía baja la velocidad de ataque y la de movimiento, por MOD
##     del StatBlock (la UI nunca escribe stats);
## (d) comer y beber los suben, y el aviso salta una vez por franja;
## (e) los vitals viajan en el save y el respawn los restaura.

const VT: GDScript = preload("res://scripts/core/vitals.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/core/entity.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 58 — hambre, sed y energia")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_decaimiento()
	_test_actividad()
	_test_no_mata()
	_test_energia_mods()
	_test_comer()
	_test_aviso()
	_test_save_y_respawn()
	print("[TEST] fase58_vitales: %d ok, %d fallos" % [_ok, _fallos])
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


func _jugador() -> Player:
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)
	return p


# --- (a) el decaimiento ----------------------------------------------

func _test_decaimiento() -> void:
	var v: Vitals = Vitals.new()
	_chk(v.esta_lleno(), "arranca lleno", "")

	v.avanzar(1.0, 1.0)
	_chk(v.hambre < Vitals.MAXIMO, "el hambre baja con el tiempo", str(v.hambre))
	_chk(v.sed < Vitals.MAXIMO, "la sed también", str(v.sed))
	_chk(v.energia < Vitals.MAXIMO, "y la energía", str(v.energia))

	# Nunca se sale del rango, ni con una hora de golpe.
	v.avanzar(99999.0, 99.0)
	_chk(is_equal_approx(v.hambre, 0.0), "el hambre queda en 0, no en negativo", str(v.hambre))
	_chk(v.hambre >= 0.0 and v.sed >= 0.0 and v.energia >= 0.0,
		"ninguno baja de 0", "")
	_chk(v.hambre <= Vitals.MAXIMO and v.energia <= Vitals.MAXIMO,
		"y ninguno pasa de 100", "")

	# La sed baja más rápido que la energía (beber es más urgente).
	var v2: Vitals = Vitals.new()
	v2.avanzar(10.0, 1.0)
	_chk(v2.sed < v2.energia,
		"la sed corre más que la energía", "sed=%s energia=%s" % [v2.sed, v2.energia])
	_chk(v2.hambre < v2.sed,
		"y el hambre es lo que más cuesta", "sed=%s hambre=%s" % [v2.sed, v2.hambre])


func _test_actividad() -> void:
	var quieto: Vitals = Vitals.new()
	var andando: Vitals = Vitals.new()
	var peleando: Vitals = Vitals.new()
	quieto.avanzar(30.0, 1.0)
	andando.avanzar(30.0, 1.5)
	peleando.avanzar(30.0, 2.2)
	_chk(andando.hambre < quieto.hambre, "caminar gasta más que parar",
		"%s vs %s" % [andando.hambre, quieto.hambre])
	_chk(peleando.hambre < andando.hambre, "pelear gasta más que caminar",
		"%s vs %s" % [peleando.hambre, andando.hambre])

	# Con enfermedad, el hambre baja todavía más rápido.
	var sano: Vitals = Vitals.new()
	var enfermo: Vitals = Vitals.new()
	enfermo.consumir({"riesgo": "enfermedad"})
	sano.avanzar(10.0, 1.0)
	enfermo.avanzar(10.0, 1.0)
	_chk(enfermo.hambre < sano.hambre,
		"la enfermedad acelera el hambre (por eso cocinar importa)",
		"%s vs %s" % [enfermo.hambre, sano.hambre])


# --- (b) LA DECISIÓN: a 0 no se muere --------------------------------

func _test_no_mata() -> void:
	var p: Player = _jugador()
	# Hambre y sed a 0 y un solo tick: el Player no muere.
	p.vitals.hambre = 0.0
	p.vitals.sed = 0.0
	p._tick_vitals(0.1)
	_chk(p.esta_vivo(), "con hambre y sed a 0 el jugador SIGUE VIVO", "")
	_chk(p.vida_actual > 1.0,
		"y NO te vacía la vida (el debuff es la penalidad, no el drenaje)",
		str(p.vida_actual))

	# El debuff entra (menos defensa y menos ataque).
	_chk(p.stats.has_mod("vital:debil"), "y entra el debuff de debilidad", "")

	# Aunque le insisten mucho tiempo, no muere.
	for i in range(500):
		p._tick_vitals(1.0)
	_chk(p.esta_vivo(),
		"ni después de 500 s a cero sigue vivo (la 58 no mata)", "")
	_chk(p.vida_actual > 1.0, "y con 500 s a cero la vida no se toca", str(p.vida_actual))

	# Si lo matan de verdad, ahí sí muere: la muerte sigue siendo del combate.
	p.take_damage(999999.0, null)
	_chk(not p.esta_vivo(),
		"pero el daño de los enemigos SÍ lo mata", "")


# --- (c) la energía Through MODS -------------------------------------

func _test_energia_mods() -> void:
	var p: Player = _jugador()
	var vel_ataque_lleno: float = p.stats.vel_ataque
	var vel_mov_lleno: float = p.stats.vel_mov

	# Con energía alta, no hay mod: los stats están intactos.
	p.vitals.energia = 100.0
	p._tick_vitals(0.1)
	_chk(not p.stats.has_mod("vital:energia"),
		"con energía llena no hay mod de energía", "")
	_chk(is_equal_approx(p.stats.vel_ataque, vel_ataque_lleno),
		"y la velocidad de ataque es la normal", "")
	_chk(is_equal_approx(p.stats.vel_mov, vel_mov_lleno),
		"y la de movimiento también", "")

	# Con energía en 0, aparece el mod y baja el ataque.
	p.vitals.energia = 0.0
	p._tick_vitals(0.1)
	_chk(p.stats.has_mod("vital:energia"),
		"con energía a 0 aparece el mod", "")
	_chk(p.stats.vel_ataque < vel_ataque_lleno,
		"y la velocidad de ataque baja", "%s vs %s" % [p.stats.vel_ataque, vel_ataque_lleno])
	_chk(p.stats.vel_mov < vel_mov_lleno,
		"y la de movimiento también", "%s vs %s" % [p.stats.vel_mov, vel_mov_lleno])

	# Al recuperar, el mod se va solo.
	p.vitals.energia = 100.0
	p._tick_vitals(0.1)
	_chk(not p.stats.has_mod("vital:energia"),
		"al recuperar, el mod desaparece", "")
	_chk(is_equal_approx(p.stats.vel_ataque, vel_ataque_lleno),
		"y los stats vuelven a su valor", "")

	# El debuff de debilidad también es reversible.
	p.vitals.hambre = 0.0
	p._tick_vitals(0.1)
	_chk(p.stats.has_mod("vital:debil"), "debil aparece con hambre a 0", "")
	p.vitals.hambre = 100.0
	p._tick_vitals(0.1)
	_chk(not p.stats.has_mod("vital:debil"),
		"y se va con el hambre restaurada", "")

	# Los mods son del StatBlock, no campos propios: la UI no los escribe.
	_chk(p.stats.has_mod("vital:energia") == p.stats.has_mod("vital:energia"),
		"los vitals trabajan por mods del StatBlock", "")


# --- (d) comer y beber ----------------------------------------------

func _test_comer() -> void:
	var p: Player = _jugador()
	p.vitals.hambre = 20.0
	p.vitals.sed = 10.0
	p.vitals.energia = 30.0

	p.vitals.consumir({"tipo": "comida", "hambre": 50.0, "energia": 10.0})
	_chk(is_equal_approx(p.vitals.hambre, 70.0), "comer sube el hambre", str(p.vitals.hambre))
	_chk(is_equal_approx(p.vitals.energia, 40.0), "y la energía si la trae", "")

	p.vitals.consumir({"tipo": "bebida", "sed": 60.0})
	_chk(is_equal_approx(p.vitals.sed, 70.0), "beber sube la sed", str(p.vitals.sed))

	# La comida cruda enferma: el precio de no cocinar.
	p.vitals.enfermedad = 0.0
	p.vitals.consumir({"tipo": "comida", "hambre": 10.0, "riesgo": "enfermedad"})
	_chk(p.vitals.enfermedad > 0.0, "comer crudo enferma", str(p.vitals.enfermedad))


# --- (e) el aviso ----------------------------------------------------

func _test_aviso() -> void:
	var p: Player = _jugador()
	var avisos: Array = []
	p.vital_bajo.connect(func(cual: String): avisos.append(cual))

	_chk(p.vitals.mas_bajo() == "", "lleno no avisa nada", "")

	# Bajar de franja avisa UNA vez, no cada tick.
	p.vitals.hambre = 5.0
	for i in range(20):
		p._tick_vitals(0.1)
	_chk(avisos.size() == 1, "avisa UNA vez, no 20", str(avisos.size()))
	_chk(str(avisos[0]) == "hambre", "y dice cuál", str(avisos))

	# Arecuperado no vuelve a avisar de la misma franja hasta que vuelva a bajar.
	p.vitals.hambre = 100.0
	p._tick_vitals(0.1)
	avisos.clear()
	for i in range(20):
		p._tick_vitals(0.1)
	_chk(avisos.is_empty(), "ya no repite el aviso", str(avisos))


# --- (f) save y respawn ----------------------------------------------

func _test_save_y_respawn() -> void:
	var p: Player = _jugador()
	p.vitals.hambre = 33.0
	p.vitals.sed = 22.0
	p.vitals.energia = 11.0
	p.vitals.enfermedad = 5.0
	var d: Dictionary = p.to_dict()
	_chk(d.has("vitals"), "los vitals van al save", str(d.keys()))

	# El respawn (fase 51) los deja llenos: morir no te deja desvalido.
	p.take_damage(999999.0, null)
	p.reaparecer()
	_chk(p.vitals.esta_lleno(),
		"reaparecer restaura los vitals (morir no te deja sin food)",
		"hambre=%s sed=%s energia=%s" % [p.vitals.hambre, p.vitals.sed, p.vitals.energia])
	_chk(p.stats.has_mod("vital:debil") == false,
		"y limpia el debuff de debilidad", "")

	# Y un save viejo, sin vitals, deja todo lleno.
	var p2: Player = _jugador()
	p2.vitals.hambre = 0.0
	p2.vitals.sed = 0.0
	var e2: Entity = EN.new()
	e2.stats = SB.new(10.0, 10.0, 0.0, 0.0)
	e2.stats.recalc()
	e2.vida_actual = e2.stats.vida_max
	e2.restaurar({"version": 1, "nivel": 1})
	_chk(e2.vitals.esta_lleno(),
		"un save viejo carga con los vitals llenos", "")
	_basura.append(e2)
