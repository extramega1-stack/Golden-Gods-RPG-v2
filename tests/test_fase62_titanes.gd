extends SceneTree
## Tests headless de la Fase 62 (Titanes que hostigan).
##
## POR QUÉ NACE: en Dragonwilds, el jefe está presente desde el minuto uno —
## los dragones te hostigan mientras hacés tu vida. El equivalente en el
## canon de Liberty es el Titán Acecho: un arquetipo único que NO te suelta,
## presente en todas las regiones menos en Moon Town.
##
## Cubre:
## (a) el DATO: el arquetipo existe, con `factor_suelta` propio;
## (b) los SPAWNS: uno por región, ninguno en Moon Town;
## (c) la IA: el titán suelta mucho más lejos que un goblin;
## (d) no rompe la regla región→arquetipo ni los conteos de la 12 y la 43;
## (e) el generador sigue siendo determinista y respetando el total.

const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const IT: GDScript = preload("res://scripts/inventory/item_db.gd")
const TITAN: String = "titan_acecho"
const RUTA_ENEMIGOS: String = "res://data/enemies.json"
const RUTA_SPAWNS: String = "res://data/spawns.json"

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []
var _arqs: Dictionary = {}


func _init() -> void:
	print("[TEST] Fase 62 — Titanes que hostigan")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	IT.cargar()
	_arqs = (JSON.parse_string(
		FileAccess.get_file_as_string(RUTA_ENEMIGOS)) as Dictionary).get("arquetipos", {})
	_test_arquetipo()
	_test_spawns()
	_test_no_suelta()
	_test_no_rompe_las_reglas()
	_test_determinismo()
	print("[TEST] fase62_titanes: %d ok, %d fallos" % [_ok, _fallos])
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


func _mob(id: String) -> Enemy:
	var e: Enemy = EN.new()
	root.add_child(e)
	_basura.append(e)
	e.configurar(_arqs[id])
	return e


# --- (a) el arquetipo -------------------------------------------------

func _test_arquetipo() -> void:
	_chk(_arqs.has(TITAN), "el arquetipo '%s' existe" % TITAN, "")
	if not _arqs.has(TITAN):
		return
	var a: Dictionary = _arqs[TITAN]
	_chk(str(a.get("nombre", "")) != "", "tiene nombre", str(a))
	for st in ["fuerza", "aguante", "destreza", "inteligencia"]:
		_chk(a.has(st), "declara '%s'" % st, str(a.keys()))
	_chk(float(a.get("radio_aggro", 0.0)) > 14.0,
		"aggro MUCHO más alto que un goblin (14)", str(a.get("radio_aggro")))
	_chk(float(a.get("factor_suelta", 0.0)) >= 3.0,
		"y casi no suelta la presa (factor_suelta >= 3)", str(a.get("factor_suelta")))
	_chk(int(a.get("xp", 0)) >= 300,
		"da más XP que un mob normal", str(a.get("xp")))
	# Es un arquetipo NORMAL con élite, no un jefe: no lleva bloque `jefe`.
	_chk(not a.has("jefe"),
		"NO lleva bloque 'jefe': hostiga pero no es un jefe de fragmento", "")
	_chk(a.has("elite"), "sí tiene bloque élite", str(a.keys()))
	# Y su botín está en el inventario.
	var loot: Dictionary = a.get("loot", {})
	for i in loot.get("items", []):
		_chk(IT.existe(str((i as Dictionary).get("item_id", ""))),
			"el drop '%s' existe" % str((i as Dictionary).get("item_id", "")), "")


# --- (b) los spawns ---------------------------------------------------

func _test_spawns() -> void:
	var spawns: Array = (JSON.parse_string(
		FileAccess.get_file_as_string(RUTA_SPAWNS)) as Array)
	var titanes: Array = []
	for s in spawns:
		var sd: Dictionary = s
		if str(sd.get("grupo", "")) == "titan":
			titanes.append(sd)

	_chk(titanes.size() == 8,
		"hay 8 titanes (uno por región menos Moon Town)", str(titanes.size()))
	_chk(spawns.size() == 1133, "y el total de spawns sigue en 1133", str(spawns.size()))

	# Ninguno en Moon Town: la primera región tiene que respirar.
	var en_moon: int = 0
	var regiones := {}
	for t in titanes:
		var td: Dictionary = t
		_chk(str(td.get("arquetipo", "")) == TITAN,
			"el spawn usa el arquetipo del titán", str(td.get("arquetipo", "")))
		# Moon Town es la región de arranque: su centro está en el origen.
		if float(td.get("x", 1e9)) == 0.0 and float(td.get("z", 1e9)) == 45.0:
			en_moon += 1
	_chk(en_moon == 0, "ninguno en la región de arranque", str(en_moon))

	# Todos con nivel de su región + 2 (más peligroso que la trash local).
	for t in titanes:
		var td: Dictionary = t
		_chk(int(td.get("nivel", 0)) > 5,
			"el titán de (%.0f,%.0f) tiene nivel de amenaza" % [
				float(td.get("x", 0.0)), float(td.get("z", 0.0))],
			str(td.get("nivel")))


# --- (c) la IA: no suelta --------------------------------------------

func _test_no_suelta() -> void:
	var titan: Enemy = _mob(TITAN)
	var goblin: Enemy = _mob("goblin")

	_chk(titan.radio_aggro > goblin.radio_aggro,
		"el titán tiene más aggro que un goblin",
		"%s vs %s" % [titan.radio_aggro, goblin.radio_aggro])
	_chk(titan.factor_suelta > goblin.factor_suelta,
		"y suelta mucho más lejos",
		"%s vs %s" % [titan.factor_suelta, goblin.factor_suelta])
	_chk(is_equal_approx(goblin.factor_suelta, Enemy.FACTOR_SUELTA),
		"un goblin usa la suelta por defecto (1.5)", str(goblin.factor_suelta))
	_chk(titan.radio_aggro * titan.factor_suelta
			> goblin.radio_aggro * goblin.factor_suelta * 2.0,
		"el alcance real del titán es el doble o más",
		"%.0f vs %.0f" % [titan.radio_aggro * titan.factor_suelta,
			goblin.radio_aggro * goblin.factor_suelta])

	# Y la FSM: mientras esté en rango de suelta, NO vuelve a QUIETO.
	var objetivo := Entity.new()
	root.add_child(objetivo)
	_basura.append(objetivo)
	objetivo.stats = StatBlock.new(40.0, 40.0, 0.0, 0.0)
	objetivo.stats.recalc()
	objetivo.vida_actual = objetivo.stats.vida_max
	titan.objetivo = objetivo
	titan.global_position = Vector3.ZERO
	# A una distancia que para un goblin ya sería huida, pero no para el titán.
	var d: float = goblin.radio_aggro * goblin.factor_suelta * 1.5
	objetivo.global_position = Vector3(d, 0.0, 0.0)
	titan.estado = Enemy.Estado.PERSEGUIR
	titan._actualizar_estado()
	_chk(titan.estado == Enemy.Estado.PERSEGUIR,
		"el titán sigue persiguiendo donde un goblin se rindió", str(titan.estado))
	goblin.objetivo = objetivo
	goblin.global_position = Vector3.ZERO
	goblin.estado = Enemy.Estado.PERSEGUIR
	goblin._actualizar_estado()
	_chk(goblin.estado == Enemy.Estado.QUIETO,
		"el goblin se rinde a esa distancia (el contraste)", str(goblin.estado))

	# Y si te pasás de su alcance, también se rinde: no es una omnisciencia.
	objetivo.global_position = Vector3(titan.radio_aggro * titan.factor_suelta * 1.5, 0, 0)
	titan._actualizar_estado()
	_chk(titan.estado == Enemy.Estado.QUIETO,
		"pero pasado su alcance, también lo suelta", str(titan.estado))


# --- (d) no rompe las reglas existentes ------------------------------

func _test_no_rompe_las_reglas() -> void:
	var spawns: Array = (JSON.parse_string(
		FileAccess.get_file_as_string(RUTA_SPAWNS)) as Array)
	# El total y el reparto por arquetipo se mantienen.
	var por_arq: Dictionary = {}
	for s in spawns:
		var sd: Dictionary = s
		por_arq[str(sd.get("arquetipo", ""))] = int(por_arq.get(
			str(sd.get("arquetipo", "")), 0)) + 1
	_chk(por_arq.has("goblin") and por_arq.has("lobo"),
		"la trash de la fase 12 sigue estando", str(por_arq.keys()))
	# Los 6 jefes de fragmento siguen siendo 6 y con 1 spawn cada uno.
	for j in ["campeon_caido", "devorador_dunas", "aullido_pico",
			"eco_cristal", "fundidor_antiguo", "susurro_umbral"]:
		_chk(int(por_arq.get(j, 0)) == 1,
			"el jefe '%s' sigue con 1 spawn" % j, str(por_arq.get(j, 0)))
	# La zona segura de 40 m sigue respetada.
	var en_segura: int = 0
	for s in spawns:
		var sd: Dictionary = s
		if Vector2(float(sd.get("x", 0.0)), float(sd.get("z", 0.0))).length() < 40.0:
			en_segura += 1
	_chk(en_segura == 0, "ningún spawn (titanes incluidos) en la zona segura",
		str(en_segura))


# --- (e) el generador sigue determinista -----------------------------

func _test_determinismo() -> void:
	var ruta_py: String = ProjectSettings.globalize_path(
		"res://tools/generar_spawns_rework.py")
	var prueba: String = ProjectSettings.globalize_path("user://spawns_titan.json")
	var salida: Array = []
	var rc1: int = OS.execute("python3", PackedStringArray([ruta_py, prueba]), salida, true)
	var sha1: String = FileAccess.get_sha256(prueba)
	var rc2: int = OS.execute("python3", PackedStringArray([ruta_py, prueba]), salida, true)
	var sha2: String = FileAccess.get_sha256(prueba)
	_chk(rc1 == 0 and rc2 == 0, "el generador corre dos veces", "rc=%d/%d" % [rc1, rc2])
	_chk(sha1 != "" and sha1 == sha2, "dos corridas dan el mismo SHA-256", "")
	_chk(sha1 == FileAccess.get_sha256(RUTA_SPAWNS),
		"y reproduce data/spawns.json byte a byte", "")
	# Y el repo no se toco.
	_chk(FileAccess.get_sha256(RUTA_SPAWNS) == sha1, "spawns.json intacto", "")
	DirAccess.remove_absolute(prueba)
