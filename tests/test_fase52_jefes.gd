extends SceneTree
## Tests headless de la Fase 52 (jefes de verdad).
##
## POR QUÉ NACE: los 6 jefes de fragmento (`campeon_caido`,
## `devorador_dunas`, `aullido_pico`, `eco_cristal`, `fundidor_antiguo`,
## `susurro_umbral`) eran `Enemy` con más vida. En `data/enemies.json` no
## había NINGÚN campo que los distinguiera de un goblin: se reconocían solo
## por tener XP >= 400. Sin telegrafía, sin fases, sin enrage y sin barra.
##
## Cubre:
## (a) el DATO: los 6 tienen el bloque `jefe` completo y ningún otro lo tiene;
## (b) la vida del jefe sale del bloque (no está hardcodeada en el FSM);
## (c) la FSM entra en PREPARANDO y sale a ATACAR;
## (d) las fases cambian al cruzar el umbral de vida;
## (e) el enrage baja solo y sube el daño;
## (f) un arquetipo normal NO cambia de comportamiento.
##
## Cómo correrlo:
## godot --headless --path <proyecto> --script res://tests/test_fase52_jefes.gd

const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const RUTA: String = "res://data/enemies.json"
const JEFES: Array[String] = ["campeon_caido", "devorador_dunas",
	"aullido_pico", "eco_cristal", "fundidor_antiguo", "susurro_umbral"]

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []
var _arqs: Dictionary = {}


func _init() -> void:
	print("[TEST] Fase 52 — jefes de verdad")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_dato()
	_test_no_jefes()
	_test_vida_del_jefe()
	_test_telegrafia()
	_test_fases()
	_test_enrage()
	_test_normal_no_afectado()
	print("[TEST] fase52_jefes: %d ok, %d fallos" % [_ok, _fallos])
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


func _cargar() -> void:
	var texto: String = FileAccess.get_file_as_string(RUTA)
	var datos = JSON.parse_string(texto)
	_arqs = (datos as Dictionary).get("arquetipos", {})


func _jefe(id: String) -> Enemy:
	var e: Enemy = EN.new()
	root.add_child(e)
	_basura.append(e)
	e.configurar(_arqs[id])
	# Objetivo de mentira en rango, para que la FSM quiera pegar.
	var objetivo := Entity.new()
	root.add_child(objetivo)
	_basura.append(objetivo)
	objetivo.stats = StatBlock.new(40.0, 40.0, 0.0, 0.0)
	objetivo.stats.recalc()
	objetivo.vida_actual = objetivo.stats.vida_max
	e.objetivo = objetivo
	e.global_position = Vector3.ZERO
	objetivo.global_position = Vector3(e.rango_ataque * 0.5, 0.0, 0.0)
	return e


# --- (a) el dato ------------------------------------------------------

func _test_dato() -> void:
	_cargar()
	_chk(not _arqs.is_empty(), "enemies.json tiene arquetipos", str(_arqs.size()))

	for id in JEFES:
		_chk(_arqs.has(id), "existe el arquetipo '%s'" % id, str(_arqs.keys()))
		if not _arqs.has(id):
			continue
		var b: Dictionary = _arqs[id].get("jefe", {})
		_chk(not b.is_empty(), "'%s' tiene bloque jefe" % id, str(_arqs[id].keys()))
		if b.is_empty():
			continue
		_chk(float(b.get("vida_mult", 1.0)) > 1.0,
			"'%s' multiplica la vida" % id, str(b.get("vida_mult")))
		_chk(float(b.get("telegrafia_seg", 0.0)) > 0.0,
			"'%s' telegrafia" % id, str(b.get("telegrafia_seg")))
		_chk(float(b.get("enrage_seg", 0.0)) > 0.0,
			"'%s' tiene enrage" % id, str(b.get("enrage_seg")))
		var fases: Array = b.get("fases", [])
		_chk(fases.size() == 3,
			"'%s' tiene 3 fases" % id, str(fases.size()))
		# Los umbrales tienen que ir de 1.0 hacia abajo.
		if fases.size() == 3:
			_chk(float(fases[0]["hasta"]) > float(fases[1]["hasta"])
					and float(fases[1]["hasta"]) > float(fases[2]["hasta"]),
				"'%s': los umbrales de fase bajan" % id,
				"%s %s %s" % [fases[0]["hasta"], fases[1]["hasta"], fases[2]["hasta"]])
			_chk(is_equal_approx(float(fases[2]["hasta"]), 0.33),
				"'%s' llega a la fase 3 al 33%%" % id, str(fases[2]["hasta"]))


# --- (b) solo los jefes tienen el bloque ------------------------------

func _test_no_jefes() -> void:
	var con_bloque := 0
	for id in _arqs.keys():
		if not (_arqs[id] as Dictionary).get("jefe", {}).is_empty():
			con_bloque += 1
	_chk(con_bloque == JEFES.size(),
		"solo los 6 jefes tienen bloque 'jefe'", "%d con bloque" % con_bloque)


# --- (b2) la vida sale del dato ---------------------------------------

func _test_vida_del_jefe() -> void:
	var arq: Dictionary = _arqs["campeon_caido"]
	var mult: float = float(arq["jefe"]["vida_mult"])

	var e: Enemy = _jefe("campeon_caido")
	_chk(e.es_jefe, "campeon_caido se reconoce como jefe", "")

	# La vida base del arquetipo, calculada con la MISMA derivación que usa
	# StatBlock: 100 + fuerza*20 + aguante*15. Si el jefe NO aplicase el
	# multiplicador del dato, su vida_max sería esta y no el doble.
	var base := StatBlock.new(
		float(arq["fuerza"]), float(arq.get("aguante", 0.0)),
		float(arq["destreza"]), float(arq["inteligencia"]))
	base.recalc()
	_chk(is_equal_approx(e.stats.vida_max, base.vida_max * mult),
		"la vida sale del bloque del dato (vida_base x vida_mult)",
		"jefe=%s base=%s mult=%s" % [e.stats.vida_max, base.vida_max, mult])
	_chk(e.vida_actual == e.stats.vida_max,
		"el jefe arranca con la vida llena", str(e.vida_actual))
	_chk(e.vida_actual > base.vida_max,
		"el jefe tiene MÁS vida que su arquetipo base",
		"jefe=%s base=%s" % [e.vida_actual, base.vida_max])


# --- (c) la FSM telegrafía --------------------------------------------

func _test_telegrafia() -> void:
	var e: Enemy = _jefe("campeon_caido")
	_chk(is_equal_approx(e.telegrafia_seg(),
			float(_arqs["campeon_caido"]["jefe"]["telegrafia_seg"])),
		"telegrafia_seg sale del dato", str(e.telegrafia_seg()))

	# Llevarlo a ATACAR y pensar: tiene que entrar en PREPARANDO.
	e.estado = Enemy.Estado.ATACAR
	e._actualizar_estado()
	_chk(e.estado == Enemy.Estado.PREPARANDO,
		"el jefe telegrafia antes de pegar (ATACAR -> PREPARANDO)", str(e.estado))

	# Agotar la telegrafía: vuelve a ATACAR.
	e._telegrafia = 0.0
	e._actualizar_estado()
	_chk(e.estado == Enemy.Estado.ATACAR,
		"agotada la telegrafia vuelve a ATACAR", str(e.estado))

	# Si se aleja en medio de la telegrafía, se rinde (no pega al aire).
	e._telegrafia = 2.0
	e.estado = Enemy.Estado.PREPARANDO
	e.objetivo.global_position = Vector3(999.0, 0.0, 0.0)
	e._actualizar_estado()
	_chk(e.estado == Enemy.Estado.QUIETO,
		"el jefe cancela la telegrafia si el objetivo se va", str(e.estado))

	# Y el estado nuevo tiene clip: si no, el jefe se quedaría en T-pose
	# congelado durante la telegrafía.
	_chk(Enemy.Estado.PREPARANDO in Enemy.CLIP_POR_ESTADO,
		"PREPARANDO tiene clip en CLIP_POR_ESTADO", str(Enemy.CLIP_POR_ESTADO.keys()))


# --- (d) las fases ----------------------------------------------------

func _test_fases() -> void:
	var e: Enemy = _jefe("campeon_caido")
	_chk(e.fase() == 0, "arranca en fase 1", str(e.fase()))
	_chk(e.fases_totales() == 3, "tiene 3 fases", str(e.fases_totales()))

	# Baja al 60% -> fase 2 (umbral 0.66).
	e.vida_actual = e.stats.vida_max * 0.60
	e._revisar_fase()
	_chk(e.fase() == 1, "al 60% pasa a la fase 2", str(e.fase()))

	# Al 30% -> fase 3 (umbral 0.33).
	e.vida_actual = e.stats.vida_max * 0.30
	e._revisar_fase()
	_chk(e.fase() == 2, "al 30% pasa a la fase 3", str(e.fase()))

	# Volver arriba NO debe retroceder de fase.
	e.vida_actual = e.stats.vida_max
	e._revisar_fase()
	_chk(e.fase() == 2, "la fase no retrocede si le curan", str(e.fase()))

	# Cada fase pega más: es la propiedad que hace legible la escalada.
	var e2: Enemy = _jefe("campeon_caido")
	var d1: float = e2._mult_dano
	e2.vida_actual = e2.stats.vida_max * 0.30
	e2._revisar_fase()
	_chk(e2._mult_dano > d1,
		"la fase 3 pega más que la fase 1", "%s -> %s" % [d1, e2._mult_dano])
	_chk(e2._mult_vel >= 1.0,
		"la velocidad del jefe no baja de 1.0 en la ultima fase", str(e2._mult_vel))


# --- (e) el enrage ----------------------------------------------------

func _test_enrage() -> void:
	var e: Enemy = _jefe("campeon_caido")
	var seg: float = float(_arqs["campeon_caido"]["jefe"]["enrage_seg"])
	_chk(is_equal_approx(e._enrage, seg), "el enrage arranca con el reloj lleno",
		"%s vs %s" % [e._enrage, seg])
	_chk(not e.en_rage(), "al empezar NO esta en rage", "")

	# Correr el reloj.
	e._tick_jefe(seg * 0.5)
	_chk(not e.en_rage(), "a mitad de camino todavia no", "")
	e._tick_jefe(seg * 0.6)
	_chk(e.en_rage(), "agotado el reloj entra en rage", "")

	# Y no se vuelve negativo ni se reinicia solo.
	e._tick_jefe(999.0)
	_chk(is_equal_approx(e._enrage, 0.0), "el enrage no baja de 0", str(e._enrage))
	e._tick_jefe(999.0)
	_chk(e.en_rage(), "sigue en rage (no se apaga solo)", "")


# --- (f) un mob normal no cambia -------------------------------------

func _test_normal_no_afectado() -> void:
	var e: Enemy = _jefe("goblin")
	_chk(not e.es_jefe, "un goblin no es jefe", "")
	_chk(e.telegrafia_seg() == 0.0, "un goblin no telegrafia", str(e.telegrafia_seg()))
	_chk(e.fase() == 0, "un goblin no tiene fases", str(e.fase()))

	# Y su FSM es la de siempre: quieto -> perseguir -> atacar, sin pasar
	# por PREPARANDO nunca.
	e.estado = Enemy.Estado.QUIETO
	e._actualizar_estado()
	_chk(e.estado == Enemy.Estado.PERSEGUIR,
		"el goblin sigue la IA de siempre (QUIETO -> PERSEGUIR)", str(e.estado))
	e.objetivo.global_position = Vector3(0.0, 0.0, 0.0)  # dentro de rango
	e.estado = Enemy.Estado.PERSEGUIR
	e._actualizar_estado()
	_chk(e.estado == Enemy.Estado.ATACAR,
		"el goblin ataca sin telegrafia (PERSEGUIR -> ATACAR)", str(e.estado))
	e._actualizar_estado()
	_chk(e.estado == Enemy.Estado.ATACAR,
		"el goblin NO entra en PREPARANDO nunca", str(e.estado))
