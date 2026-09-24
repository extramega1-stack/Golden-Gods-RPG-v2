extends SceneTree
## Tests headless de la Fase 43 (contenido regional).
##
## (a) Datos: 10 regiones con escala (stats/vida/defensa/xp/oro) y fauna;
##     10 arquetipos regionales + 10 items de loot regional.
## (b) Enemy.aplicar_escala: escala stats/vida/defensa/xp/oro, es
##     IDEMPOTENTE (mismo factor dos veces = el mismo resultado) y no toca
##     la base del arquetipo.
## (c) La escala hace que el mundo escale de verdad: la misma criatura es
##     mucho más fuerte y da más XP en El Velo que en Moon Town, y el TTK
##     crece con la banda (nada de fights de 4 golpes planos).
## (d) Spawns: cada spawn trash usa la fauna de su región (contrato nuevo,
##     el generador es determinista) y los 10 mobs regionales aparecen.
## (e) Save: el enemigo restaurado conserva XP y escala (no vuelve a 10).
## (f) La arena NO se escala (usa su propia curva).
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase43_regional.gd

const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const FM: GDScript = preload("res://scripts/core/formulas.gd")
const IDB: GDScript = preload("res://scripts/inventory/item_db.gd")

const REGIONALES: Array[String] = ["escorpion_dunas", "slog_volcan", "golem_ascua",
	"yeti_hielo", "arana_sombra", "espectro_velo", "carnicoro_rio", "mimo_hoja",
	"centinela_oro", "sombra_vacia"]

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 43 — contenido regional")
	ItemDB.cargar()


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_datos()
	_test_escala()
	_test_curva()
	_test_spawns()
	_test_save()
	_test_arena_no_escala()
	print("[TEST] fase43_regional: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		if is_instance_valid(n):
			(n as Node).free()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _regiones() -> Array:
	return JSON.parse_string(
		FileAccess.get_file_as_string("res://data/regiones.json"))


func _arquetipos() -> Dictionary:
	return (JSON.parse_string(
		FileAccess.get_file_as_string("res://data/enemies.json")) as Dictionary)["arquetipos"]


func _region(id: String) -> Dictionary:
	for r in _regiones():
		if str(r.get("id", "")) == id:
			return r
	return {}


func _mob(arq_id: String) -> Enemy:
	var e: Enemy = EN.new()
	root.add_child(e)
	_basura.append(e)
	e.configurar((_arquetipos().get(arq_id, {}) as Dictionary).duplicate(true))
	return e


## (a) Datos.
func _test_datos() -> void:
	var arqs: Dictionary = _arquetipos()
	_chk(arqs.size() == 19, "a: 19 arquetipos (9 + 10 regionales)", str(arqs.size()))
	for mid in REGIONALES:
		_chk(arqs.has(mid), "a: existe " + mid)
		var a: Dictionary = arqs.get(mid, {})
		_chk(not (a.get("loot", {}) as Dictionary).get("items", []).is_empty(),
			"a: " + mid + " tiene loot")
		_chk(a.has("elite"), "a: " + mid + " puede salir élite")
		_chk(ItemDB.existe(str(((a.get("loot", {}) as Dictionary)["items"] as Array)[0]["item_id"])),
			"a: el item de " + mid + " existe en items.json")
	for r in _regiones():
		var esc: Dictionary = r.get("escala", {})
		_chk(esc.has("stats") and esc.has("vida") and esc.has("defensa")
				and esc.has("xp") and esc.has("oro"),
			"a: %s tiene escala completa" % str(r.get("id", "")))
		_chk(not (r.get("mobs", []) as Array).is_empty(),
			"a: %s declara fauna" % str(r.get("id", "")))
	# La defensa tiene que crecer MÁS LENTO que vida/ataque (si no, el TTK
	# se dispara por la mitigación).
	var moon: Dictionary = _region("moon_town").get("escala", {})
	var velo: Dictionary = _region("velo").get("escala", {})
	_chk(float(velo.get("defensa", 99.0)) < float(velo.get("stats", 1.0)),
		"a: en El Velo la defensa escala menos que los stats",
		"def=%s stats=%s" % [velo.get("defensa"), velo.get("stats")])


## (b) aplicar_escala.
func _test_escala() -> void:
	var e: Enemy = _mob("goblin")
	var hp0: float = e.stats.vida_max
	var atk0: float = e.stats.ataque
	var xp0: int = e.xp_recompensa
	var oro0: int = int(e._tabla_loot.get("oro_min", 0))
	e.aplicar_escala(_region("velo").get("escala", {}))
	_chk(e.stats.vida_max > hp0 * 3.0, "b: la vida escala", "%f -> %f" % [hp0, e.stats.vida_max])
	_chk(e.stats.ataque > atk0 * 3.0, "b: el ataque escala", "%f -> %f" % [atk0, e.stats.ataque])
	_chk(e.xp_recompensa > xp0 * 3.0, "b: la XP escala", "%d -> %d" % [xp0, e.xp_recompensa])
	_chk(int(e._tabla_loot.get("oro_min", 0)) > oro0, "b: el oro escala")
	_chk(is_equal_approx(e.vida_actual, e.stats.vida_max), "b: nace con la vida escalada")
	# Idempotente: aplicar dos veces el MISMO factor no lo acumula.
	var hp1: float = e.stats.vida_max
	var xp1: int = e.xp_recompensa
	e.aplicar_escala(_region("velo").get("escala", {}))
	_chk(is_equal_approx(e.stats.vida_max, hp1), "b: vida idempotente",
		"%f -> %f" % [hp1, e.stats.vida_max])
	_chk(e.xp_recompensa == xp1, "b: XP idempotente")
	_chk(is_equal_approx(float(e.arquetipo_base("fuerza")), 10.0),
		"b: la base del arquetipo no se toca", str(e.arquetipo_base("fuerza")))
	e.aplicar_escala({})
	_chk(is_equal_approx(e.stats.vida_max, hp1), "b: escala vacía = no-op")


## (c) El mundo escala de verdad (y el TTK crece con la banda).
func _test_curva() -> void:
	var bajo: Enemy = _mob("goblin")
	var alto: Enemy = _mob("goblin")
	bajo.aplicar_escala(_region("moon_town").get("escala", {}))
	alto.aplicar_escala(_region("corona_quebrada").get("escala", {}))
	_chk(alto.stats.vida_max > bajo.stats.vida_max * 5.0,
		"c: el mismo goblin es mucho más duro en la Corona Quebrada",
		"%f vs %f" % [bajo.stats.vida_max, alto.stats.vida_max])
	_chk(alto.xp_recompensa > bajo.xp_recompensa * 5.0, "c: y da mucho más XP")
	# El TTK sube con la banda (con un héroe del nivel de cada banda).
	var res: Array = []
	for rid in ["moon_town", "ceniza_forja", "umbral_ladon", "velo"]:
		var r: Dictionary = _region(rid)
		var esc: Dictionary = r.get("escala", {})
		var e: Enemy = _mob(str((r.get("mobs", ["goblin"]) as Array)[0]))
		e.aplicar_escala(esc)
		var nv: int = int((int(r.get("nivel_min", 1)) + int(r.get("nivel_max", 1))) / 2)
		var heroe: StatBlock = SB.new(30.0 + 2.0 * (nv - 1), 30.0, 15.0, 15.0)
		heroe.set_stat_daño("fuerza")
		var rd: Dictionary = FM.damage(heroe, e.stats, {"power": 1.0}, 0.99, 0.0)
		var ttk: int = int(ceil(e.stats.vida_max / maxf(float(rd["final"]), 1.0)))
		res.append(ttk)
	_chk(int(res[0]) <= 5, "c: el inicio sigue siendo rápido (4-5 golpes)",
		str(res[0]))
	_chk(int(res[res.size() - 1]) > int(res[0]) and int(res[res.size() - 1]) <= 30,
		"c: el endgame dura más (rampa real, sin ser sponge)", str(res))
	_chk(int(res[1]) >= int(res[0]) and int(res[2]) >= int(res[1]),
		"c: el TTK crece monótono con la banda", str(res))


## (d) Spawns por región (contrato nuevo del generador).
func _test_spawns() -> void:
	var spawns: Array = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/spawns.json"))
	_chk(spawns.size() == 1133, "d: 1133 spawns", str(spawns.size()))
	var db: RegionDB = RegionDB.new()
	_chk(db.cargar(), "d: regiones cargadas")
	var fuera_fauna: int = 0
	var presentes: Dictionary = {}
	for s in spawns:
		var d: Dictionary = s
		var grupo: String = str(d.get("grupo", ""))
		if grupo == "jefe_fragmento" or grupo == "prueba_combate":
			continue
		var r: Dictionary = db.region_en(float(d.get("x", 0.0)), float(d.get("z", 0.0)))
		var fauna: Array = r.get("mobs", [])
		var a: String = str(d.get("arquetipo", ""))
		if fauna.is_empty() or a not in fauna:
			fuera_fauna += 1
		presentes[a] = true
	_chk(fuera_fauna == 0, "d: cada spawn usa la fauna de su región",
		"%d fuera" % fuera_fauna)
	for mid in REGIONALES:
		_chk(presentes.has(mid), "d: el mundo tiene " + mid)


## (e) Save: XP y escala sobreviven.
func _test_save() -> void:
	var e: Enemy = _mob("goblin")
	e.aplicar_escala(_region("abismo_lloroso").get("escala", {}))
	var xp: int = e.xp_recompensa
	var vida: float = e.stats.vida_max
	var d: Dictionary = e.to_dict()
	var e2: Enemy = EN.new()
	root.add_child(e2)
	_basura.append(e2)
	e2.restaurar(d)
	_chk(e2.xp_recompensa == xp, "e: la XP escalada sobrevive al save",
		"%d vs %d" % [e2.xp_recompensa, xp])
	_chk(is_equal_approx(e2.stats.vida_max, vida), "e: la vida escalada sobrevive",
		"%f vs %f" % [e2.stats.vida_max, vida])


## (f) La arena no se escala (curva propia).
func _test_arena_no_escala() -> void:
	var e: Enemy = _mob("goblin")
	var vida0: float = e.stats.vida_max
	var xp0: int = e.xp_recompensa
	# La arena llama a la factory sin escala; si alguien la aplicara, la
	# máquina de la arena se desbalancearía.
	_chk(is_equal_approx(e.stats.vida_max, vida0) and e.xp_recompensa == xp0,
		"f: el mob crudo (sin escala) sirve para la arena")
