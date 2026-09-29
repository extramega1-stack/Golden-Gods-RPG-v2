extends SceneTree
## Tests headless de la Fase 33 (élites data-driven + loot raro).
##
## Cubre:
## (a) datos: 3 de basura con bloque élite válido (loot_extra existe en
##     ItemDB); los 6 jefes sin bloque;
## (b) prob_elite(): 0 sin bloque, clamp a [0, 1];
## (c) hacer_elite(): ×fuerza/vida llena/×5 XP/oro, "X élite", escala 1.3,
##     tinte dorado, loot extra añadido SIN mutar el JSON, idempotente;
## (d) configurar() resetea élite (reutilización del pool);
## (e) sortear_elite(): prob 1 → élite, sin bloque → nunca;
## (f) die() de élite suelta el loot raro + oro multiplicado;
## (g) el save conserva los stats del élite (round-trip por stats).
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase33_elites.gd

const EN: GDScript = preload("res://scripts/enemy/enemy.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []
var _drops: Array = []


func _init() -> void:
	print("[TEST] Fase 33 — élites + loot raro")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_datos()
	_test_prob()
	_test_hacer_elite()
	_test_reset()
	_test_sorteo()
	_test_botin_elite()
	_test_save_stats()
	print("[TEST] fase33_elites: %d ok, %d fallos" % [_ok, _fallos])
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


func _enemigo(aq: Dictionary) -> Enemy:
	var e: Enemy = EN.new()
	var cuerpo := MeshInstance3D.new()
	cuerpo.name = "Cuerpo"
	e.add_child(cuerpo)
	root.add_child(e)
	_basura.append(e)
	e.configurar(aq)
	return e


## (a) Datos.
func _test_datos() -> void:
	var aqs: Dictionary = _arquetipos()
	# Fase 62: +1 (titan_acecho). 20 en total.
	_chk(aqs.size() == 20, "a: 20 arquetipos (fase 43: +10 regionales, 62: +1 titan)",
		str(aqs.size()))
	for k in ["goblin", "lobo", "ogro"]:
		var b: Dictionary = (aqs.get(k, {}) as Dictionary).get("elite", {})
		_chk(not b.is_empty(), "a: %s con bloque élite" % k)
		_chk(float(b.get("prob", 0.0)) > 0.0 and float(b.get("prob", 0.0)) < 1.0,
			"a: prob de %s en (0,1)" % k, str(b.get("prob")))
		_chk(float(b.get("mult_fuerza", 0.0)) > 1.0, "a: %s mult_fuerza > 1" % k)
		_chk(float(b.get("mult_xp", 0.0)) == 5.0, "a: %s ×5 XP" % k)
		_chk((b.get("tinte", []) as Array).size() == 3, "a: %s tinte rgb" % k)
		var extras: Array = b.get("loot_extra", [])
		_chk(not extras.is_empty(), "a: %s con loot raro" % k)
		for x in extras:
			_chk(ItemDB.existe(str((x as Dictionary).get("item_id", ""))),
				"a: extra existe en ItemDB", str((x as Dictionary).get("item_id")))
	for k in ["aullido_pico", "campeon_caido", "devorador_dunas",
			"eco_cristal", "fundidor_antiguo", "susurro_umbral"]:
		_chk(not ((aqs.get(k, {}) as Dictionary).has("elite")),
			"a: el jefe %s nunca es élite" % k)


## (b) Probabilidad con clamp.
func _test_prob() -> void:
	_chk(Enemy.prob_elite({}) == 0.0, "b: sin bloque prob 0")
	_chk(Enemy.prob_elite({"elite": {"prob": 0.06}}) == 0.06, "b: lee prob")
	_chk(Enemy.prob_elite({"elite": {"prob": 2.0}}) == 1.0, "b: clamp a 1")
	_chk(Enemy.prob_elite({"elite": {"prob": -1.0}}) == 0.0, "b: clamp a 0")


## (c) Conversión a élite.
func _test_hacer_elite() -> void:
	var aqs: Dictionary = _arquetipos()
	var aq: Dictionary = (aqs.get("goblin", {}) as Dictionary).duplicate(true)
	var base_items: int = ((aq.get("loot", {}) as Dictionary).get("items", []) as Array).size()
	var e: Enemy = _enemigo(aq)
	var f0: float = e.stats.fuerza
	var xp0: int = e.xp_recompensa
	e.hacer_elite(aq.get("elite", {}))
	_chk(e.es_elite, "c: marca es_elite")
	_chk(absf(e.stats.fuerza - f0 * 1.5) < 0.01, "c: ×1.5 fuerza")
	_chk(absf(e.vida_actual - e.stats.vida_max) < 0.01, "c: vida llena")
	_chk(e.xp_recompensa == xp0 * 5, "c: ×5 XP", str(e.xp_recompensa))
	_chk(e.nombre_mostrado == "Goblin élite", "c: nombre con sufijo", e.nombre_mostrado)
	_chk(e.scale == Vector3.ONE * Enemy.ESCALA_ELITE, "c: escala 1.3")
	var mat: StandardMaterial3D = (e.get_node("Cuerpo") as MeshInstance3D).material_override as StandardMaterial3D
	_chk(mat != null and mat.albedo_color == Color(1.0, 0.62, 0.12), "c: tinte dorado")
	var items: Array = e._tabla_loot.get("items", [])
	_chk(items.size() == base_items + 2, "c: loot extra añadido", str(items.size()))
	# El JSON cacheado no se mutó.
	_chk(((aq.get("loot", {}) as Dictionary).get("items", []) as Array).size() == base_items,
		"c: el arquetipo original intacto")
	# Idempotente.
	e.hacer_elite(aq.get("elite", {}))
	_chk(absf(e.stats.fuerza - f0 * 1.5) < 0.01 and e._tabla_loot.get("items", []).size() == base_items + 2,
		"c: segunda llamada no duplica")


## (d) configurar() resetea (pool).
func _test_reset() -> void:
	var aqs: Dictionary = _arquetipos()
	var e: Enemy = _enemigo((aqs.get("ogro", {}) as Dictionary).duplicate(true))
	e.hacer_elite((aqs.get("ogro", {}) as Dictionary).get("elite", {}))
	_chk(e.es_elite, "d: setup élite")
	e.configurar((aqs.get("ogro", {}) as Dictionary).duplicate(true))
	_chk(not e.es_elite, "d: configurar apaga es_elite")
	_chk(e.scale == Vector3.ONE, "d: configurar restaura escala")
	_chk(e.nombre_mostrado == "Ogro", "d: configurar restaura nombre")


## (e) Sorteo determinista en los bordes.
func _test_sorteo() -> void:
	var e: Enemy = _enemigo({"nombre": "Test", "elite": {"prob": 1.0}})
	_chk(e.sortear_elite({"nombre": "Test", "elite": {"prob": 1.0}}), "e: prob 1 → élite")
	_chk(e.es_elite, "e: quedó élite")
	var e2: Enemy = _enemigo({"nombre": "Test"})
	_chk(not e2.sortear_elite({"nombre": "Test"}), "e: sin bloque nunca")


## (f) El botín del élite trae lo raro.
func _test_botin_elite() -> void:
	var aq: Dictionary = {"nombre": "Test", "fuerza": 10.0, "oro_min": 5,
		"oro_max": 10, "xp": 40,
		"elite": {"prob": 1.0, "loot_extra": [
			{"item_id": "anillo_poder", "nombre": "Anillo de poder",
				"prob": 1.0, "min": 1, "max": 1}]}}
	var e: Enemy = _enemigo(aq)
	e.sortear_elite(aq)
	_drops = []
	e.botin_generado.connect(_al_botin)
	e.take_damage(999999.0, null)
	_chk(_drops.size() > 0, "f: el élite suelta botín")
	var raro: bool = false
	var oro_ok: bool = false
	for d in _drops:
		var dd: Dictionary = d
		if str(dd.get("item_id", "")) == "anillo_poder":
			raro = true
		if str(dd.get("tipo", "")) == "oro" and int(dd.get("cantidad", 0)) >= 25:
			oro_ok = true
	_chk(raro, "f: cae el loot raro")
	_chk(oro_ok, "f: oro ×5 (mín 25)")


func _al_botin(drops: Array, _pos: Vector3) -> void:
	_drops = drops


## (g) El save conserva al élite vía stats (sin bump de versión).
func _test_save_stats() -> void:
	var aqs: Dictionary = _arquetipos()
	var e: Enemy = _enemigo((aqs.get("lobo", {}) as Dictionary).duplicate(true))
	e.hacer_elite((aqs.get("lobo", {}) as Dictionary).get("elite", {}))
	var e2: Enemy = EN.new()
	root.add_child(e2)
	_basura.append(e2)
	e2.restaurar(e.to_dict())
	_chk(absf(e2.stats.vida_max - e.stats.vida_max) < 0.01,
		"g: vida_max del élite sobrevive al save", str(e2.stats.vida_max))
	_chk(absf(e2.stats.fuerza - e.stats.fuerza) < 0.01,
		"g: fuerza del élite sobrevive al save")
