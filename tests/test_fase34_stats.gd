extends SceneTree
## Tests headless de la Fase 34 (modelo de stats STR/STA/DEX/INT sin
## agilidad) y de la Fase 45.1 (F5 entra directo al mundo).
##
## Por qué existe (Fase 50.4): la 34 reescribió el modelo entero de stats y
## NO tenía archivo de test propio — su único guardián era un bloque
## parcial de test_stats.gd. La 45.1 cambió `run/main_scene` y tampoco:
## `grep project.godot tests/` no daba nada, así que la puerta de entrada
## del juego no estaba vigilada.
##
## Cubre:
## (a) Fase 34: exactamente 4 atributos base, sin agilidad;
## (b) las fórmulas que la 34 fijó: ataque, defensa, vel_mov, vel_ataque;
## (c) vel_ataque sale de DESTREZA (la 34 movió AGI→DEX) y está acotada;
## (d) los mobs ya no bringan agilidad: `data/enemies.json` está migrado;
## (e) Fase 45.1: `run/main_scene` es la escena del mundo.
##
## Cómo correrlo:
## godot --headless --path <proyecto> --script res://tests/test_fase34_stats.gd

const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const RUTA_ENEMIGOS: String = "res://data/enemies.json"

## La 45.1 cambió la escena principal para que F5 entre directo al mundo.
const ESCENA_PRINCIPAL_ESPERADA: String = "res://scenes/demo/fase14_demo.tscn"

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 34 (stats sin agilidad) + 45.1 (escena principal)")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_atributos_base()
	_test_formulas()
	_test_vel_ataque_destreza()
	_test_enemigos_sin_agilidad()
	_test_escena_principal()
	print("[TEST] fase34_stats: %d ok, %d fallos" % [_ok, _fallos])
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


func _sb(f: float, a: float, d: float, i: float) -> StatBlock:
	return SB.new(f, a, d, i)


## (a) Fase 34: STR/STA/DEX/INT y nada más. La lista de nombres válidos es
## la fuente única (STATS_BASE), así que si alguien mete "agilidad" como
## atributo de nuevo, esta check lo detecta.
func _test_atributos_base() -> void:
	var base: Array[String] = SB.STATS_BASE
	_chk(base.size() == 4, "son 4 atributos base", "son %d" % base.size())
	_chk(base.has("fuerza") and base.has("aguante")
			and base.has("destreza") and base.has("inteligencia"),
		"los 4 son fuerza/aguante/destreza/inteligencia", str(base))
	_chk(not base.has("agilidad"),
		"NO existe agilidad como atributo (la 34 la eliminó)", str(base))

	# Un stat derivado que se llame agilidad tampoco debería colarse.
	for d in SB.STATS_DERIVADOS:
		_chk(str(d) != "agilidad", "ningún derivado se llama agilidad", str(d))


## (b) Las fórmulas que la fase 34 fijó y la 42 reajustó.
func _test_formulas() -> void:
	# Ataque: base 5 + coef del stat principal.
	var s_fuerza := _sb(10.0, 0.0, 0.0, 0.0)
	s_fuerza.recalc()
	_chk(is_equal_approx(s_fuerza.ataque, 5.0 + 10.0 * 2.0),
		"ataque (STR) = 5 + fuerza*2", str(s_fuerza.ataque))

	var s_dest := _sb(0.0, 0.0, 10.0, 0.0)
	s_dest.set_stat_daño("destreza")
	s_dest.recalc()
	_chk(is_equal_approx(s_dest.ataque, 5.0 + 10.0 * 1.75),
		"ataque (DEX) = 5 + destreza*1.75", str(s_dest.ataque))

	# Defensa: 0 + fuerza*0.5 + aguante*1.0 (DERIVACION).
	var s_def := _sb(10.0, 10.0, 0.0, 0.0)
	s_def.recalc()
	_chk(is_equal_approx(s_def.defensa, 10.0 * 0.5 + 10.0 * 1.0),
		"defensa = fuerza*0.5 + aguante*1.0", str(s_def.defensa))

	# Vida: 100 + fuerza*20 + aguante*15.
	_chk(is_equal_approx(s_def.vida_max, 100.0 + 10.0 * 20.0 + 10.0 * 15.0),
		"vida_max = 100 + fuerza*20 + aguante*15", str(s_def.vida_max))

	# vel_mov PLANA: 6.0 sin importar los atributos (la 34 la dejó fija).
	var plano := _sb(0.0, 0.0, 0.0, 0.0)
	plano.recalc()
	var pesado := _sb(999.0, 999.0, 999.0, 999.0)
	pesado.recalc()
	_chk(is_equal_approx(plano.vel_mov, 6.0),
		"vel_mov base = 6.0", str(plano.vel_mov))
	_chk(is_equal_approx(pesado.vel_mov, plano.vel_mov),
		"vel_mov NO escala con los atributos (es plana)",
		"plano=%s pesado=%s" % [plano.vel_mov, pesado.vel_mov])


## (c) La 34 movió la velocidad de ataque de AGI a DEX. Se verifica que
## sale de `destreza`, que es monótona creciente, y que respeta el tope.
func _test_vel_ataque_destreza() -> void:
	var bajo := _sb(0.0, 0.0, 0.0, 0.0)
	bajo.recalc()
	var medio := _sb(0.0, 0.0, 50.0, 0.0)
	medio.recalc()
	var tope := _sb(0.0, 0.0, 100000.0, 0.0)
	tope.recalc()

	_chk(is_equal_approx(bajo.vel_ataque, SB.VEL_ATAQUE_BASE),
		"vel_ataque sin destreza = base (1.0)", str(bajo.vel_ataque))
	_chk(medio.vel_ataque > bajo.vel_ataque,
		"vel_ataque crece con destreza", "%s -> %s" % [bajo.vel_ataque, medio.vel_ataque])
	_chk(is_equal_approx(medio.vel_ataque, 1.0 + 50.0 * 0.008),
		"vel_ataque = 1 + destreza*0.008", str(medio.vel_ataque))
	_chk(tope.vel_ataque <= SB.VEL_ATAQUE_MAX + 0.0001,
		"vel_ataque respeta el tope (2.0)", str(tope.vel_ataque))

	# Y que la inteligencia NO mueva la velocidad de ataque (era de AGI, y AGI
	# ya no existe; si alguien la colara por otra vía, esta check lo ve).
	var intel := _sb(0.0, 0.0, 0.0, 500.0)
	intel.recalc()
	_chk(is_equal_approx(intel.vel_ataque, SB.VEL_ATAQUE_BASE),
		"la inteligencia NO toca vel_ataque", str(intel.vel_ataque))


## (d) La fusión AGI→DEX de los mobs se hizo en los datos, no en el código:
## `enemies.json` ya no tiene `agilidad`. Si alguien reintroduce la clave,
## el arquetipo volvería a traer un quinto stat que `Enemy.configurar`
## descarta en silencio.
func _test_enemigos_sin_agilidad() -> void:
	var texto: String = FileAccess.get_file_as_string(RUTA_ENEMIGOS)
	_chk(texto != "", "data/enemies.json se lee", RUTA_ENEMIGOS)
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		_chk(false, "enemies.json es un Dictionary", str(typeof(datos)))
		return
	var arqs: Dictionary = (datos as Dictionary).get("arquetipos", {})
	_chk(not arqs.is_empty(), "tiene arquetipos", str(arqs.size()))

	# La invariante real: los arquetipos no pueden volver a traer un stat que
	# la 34 eliminó (u otro nombre de stat que no exista en STATS_BASE).
	# No se exige que los 4 estén: los mobs no declaran `aguante` y
	# Enemy.configurar() usa 0.0 por defecto, que es lo que hacen.
	var stats_nombrados := ["agilidad", "agi", "dexterity", "agility", "velocidad"]
	for id in arqs.keys():
		var arq: Dictionary = arqs[id]
		for k in stats_nombrados:
			_chk(not arq.has(k),
				"el arquetipo '%s' no declara '%s'" % [str(id), k], str(arq.keys()))

	# Y elEnemy no tira un quinto stat: con 4 números, no hay quinto.
	var e: Enemy = EN.new()
	_basura.append(e)
	e.configurar(arqs.get("goblin", {}))
	_chk(e.stats != null, "Enemy.configurar construye el StatBlock", "")
	_chk(is_equal_approx(e.stats.destreza,
			float(arqs.get("goblin", {}).get("destreza", 5.0))),
		"la destreza del arquetipo llega al StatBlock", str(e.stats.destreza))


## (e) Fase 45.1: F5 entra directo al mundo. Si `run/main_scene` vuelve a
## la pantalla de título, nadie se entera: no había check.
func _test_escena_principal() -> void:
	var escena: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	_chk(escena == ESCENA_PRINCIPAL_ESPERADA,
		"run/main_scene es la escena del mundo (fase 45.1)",
		"actual=%s esperado=%s" % [escena, ESCENA_PRINCIPAL_ESPERADA])
	_chk(ResourceLoader.exists(ESCENA_PRINCIPAL_ESPERADA),
		"la escena principal existe en disco", ESCENA_PRINCIPAL_ESPERADA)
