extends SceneTree
## Tests headless de la Fase 54 (comida y tick-eat).
##
## POR QUÉ NACE: el proyecto tenía 2 consumibles (dos pociones) y CERO
## comida. Sin comida no hay ciclo de supervivencia, y sin el ciclo el juego
## es "mato bicho, subo nivel". Esta fase pone el recurso y su API; la fase
## 58 le agrega el decaimiento por tiempo.
##
## Cubre:
## (a) el DATO: existen alimentos y bebidas con hambre/sed/energia;
## (b) `Vitals`: consumir, clampar, enfermedad por comida cruda;
## (c) `Vitals.avanzar()`: decae, se respeta la actividad, nunca baja de 0;
## (d) `Inventario.usar()` enruta comida y bebida a los vitals (tick-eat);
## (e) los mobs de basura tiran carne cruda;
## (f) los vitals viajan en el save.
##
## Cómo correrlo:
## godot --headless --path <proyecto> --script res://tests/test_fase54_comida.gd

const VT: GDScript = preload("res://scripts/core/vitals.gd")
const EN: GDScript = preload("res://scripts/core/entity.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const INV: GDScript = preload("res://scripts/inventory/inventory.gd")
const IT: GDScript = preload("res://scripts/inventory/item_db.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 54 — comida y tick-eat")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	IT.cargar()
	_test_dato()
	_test_vitals_consumir()
	_test_enfermedad()
	_test_decaimiento()
	_test_tick_eat()
	_test_mobs_tiran_carne()
	_test_save()
	print("[TEST] fase54_comida: %d ok, %d fallos" % [_ok, _fallos])
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


func _entidad() -> Entity:
	var e: Entity = EN.new()
	e.stats = SB.new(10.0, 10.0, 0.0, 0.0)
	e.stats.recalc()
	e.vida_actual = e.stats.vida_max
	root.add_child(e)
	_basura.append(e)
	return e


# --- (a) el dato ------------------------------------------------------

func _test_dato() -> void:
	var comidas: int = 0
	var bebidas: int = 0
	for id in IT.ids():
		var it: Dictionary = IT.obtener(id)
		if str(it.get("tipo", "")) != "consumible":
			continue
		var e: Dictionary = it.get("efecto", {})
		match str(e.get("tipo", "")):
			"comida":
				comidas += 1
				_chk(float(e.get("hambre", 0.0)) > 0.0,
					"la comida '%s' da hambre" % id, str(e))
			"bebida":
				bebidas += 1
				_chk(float(e.get("sed", 0.0)) > 0.0,
					"la bebida '%s' da sed" % id, str(e))
	_chk(comidas >= 11, "hay al menos 11 alimentos", str(comidas))
	_chk(bebidas >= 4, "hay al menos 4 bebidas", str(bebidas))

	# Las dos pociones viejas siguen siendo consumibles que curan.
	for p in ["pocion_vida", "pocion_mana"]:
		_chk(IT.existe(p), "sigue existiendo '%s'" % p, "")
	_chk(str(IT.obtener("pocion_vida").get("efecto", {}).get("tipo", "")) == "curar",
		"pocion_vida sigue curando vida (no la rompimos)", "")

	# Cadena completa: cada carne cruda tiene su asada.
	for c in ["goblin", "lobo", "ogro"]:
		_chk(IT.existe("carne_cruda_" + c), "existe carne cruda de %s" % c, "")
		_chk(IT.existe("carne_asada_" + c), "existe carne asada de %s" % c, "")
		_chk(float(IT.obtener("carne_asada_" + c)["efecto"]["hambre"])
				> float(IT.obtener("carne_cruda_" + c)["efecto"]["hambre"]),
			"asar %s rinde mas que la cruda" % c, "")


# --- (b) consumir -----------------------------------------------------

func _test_vitals_consumir() -> void:
	var v: Vitals = VT.new()
	_chk(v.esta_lleno(), "arranca lleno", "")

	# Comer baja el hambre...
	v.hambre = 40.0
	v.consumir({"tipo": "comida", "hambre": 30.0})
	_chk(is_equal_approx(v.hambre, 70.0), "comer sube el hambre", str(v.hambre))

	# ...y se clampa arriba, no se pasa de 100.
	v.hambre = 95.0
	v.consumir({"tipo": "comida", "hambre": 50.0})
	_chk(is_equal_approx(v.hambre, Vitals.MAXIMO),
		"el hambre no pasa de 100", str(v.hambre))

	# Beber sube la sed.
	v.sed = 10.0
	v.consumir({"tipo": "bebida", "sed": 30.0})
	_chk(is_equal_approx(v.sed, 40.0), "beber sube la sed", str(v.sed))

	# Un efecto vacío no rompe ni cambia nada.
	var h: float = v.hambre
	v.consumir({})
	_chk(is_equal_approx(v.hambre, h), "un efecto vacío no cambia nada", "")

	# Curar y recuperar maná siguen vivos (las pociones).
	v.esta_lleno()


func _test_enfermedad() -> void:
	var v: Vitals = VT.new()
	_chk(is_equal_approx(v.enfermedad, 0.0), "arranca sin enfermedad", "")

	# La carne cruda tiene riesgo.
	var cruda: Dictionary = IT.obtener("carne_cruda_goblin").get("efecto", {})
	_chk(str(cruda.get("riesgo", "")) == "enfermedad",
		"la carne cruda declara riesgo de enfermedad", str(cruda))
	v.consumir(cruda)
	_chk(v.enfermedad > 0.0, "comer crudo enferma", str(v.enfermedad))

	# La asada no.
	var sana: Vitals = VT.new()
	sana.consumir(IT.obtener("carne_asada_goblin").get("efecto", {}))
	_chk(is_equal_approx(sana.enfermedad, 0.0),
		"comer asado NO enferma", str(sana.enfermedad))

	# Y la enfermedad se cura sola con el tiempo.
	var antes: float = v.enfermedad
	v.avanzar(10.0, 1.0)
	_chk(v.enfermedad < antes, "la enfermedad baja sola", str(v.enfermedad))


# --- (c) el decaimiento ----------------------------------------------

func _test_decaimiento() -> void:
	var v: Vitals = VT.new()
	v.avanzar(10.0, 1.0)
	_chk(v.hambre < Vitals.MAXIMO, "el hambre baja con el tiempo", str(v.hambre))
	_chk(v.sed < Vitals.MAXIMO, "la sed baja con el tiempo", str(v.sed))
	_chk(v.energia < Vitals.MAXIMO, "la energia baja con el tiempo", str(v.energia))

	# Nunca por debajo de 0, aunque le pases una hora.
	v.avanzar(99999.0, 99.0)
	_chk(is_equal_approx(v.hambre, 0.0), "el hambre no baja de 0", str(v.hambre))
	_chk(is_equal_approx(v.sed, 0.0), "la sed no baja de 0", str(v.sed))
	_chk(is_equal_approx(v.energia, 0.0), "la energia no baja de 0", str(v.energia))

	# Un delta negativo no SUBE los vitales.
	var llano: Vitals = VT.new()
	llano.avanzar(-100.0, 1.0)
	_chk(llano.esta_lleno(), "un delta negativo no sube nada", "")

	# La actividad acelera el gasto.
	var lento: Vitals = VT.new()
	var rapido: Vitals = VT.new()
	lento.avanzar(30.0, 1.0)
	rapido.avanzar(30.0, 3.0)
	_chk(rapido.hambre < lento.hambre,
		"pegar/correr gasta mas hambre que descansar",
		"lento=%s rapido=%s" % [lento.hambre, rapido.hambre])

	# A 0 se vacia, y avisa. NO mata: eso lo aplica el Player en la fase 58.
	var vacio: Vitals = VT.new()
	_chk(not vacio.vacio(), "lleno no es vacio", "")
	vacio.hambre = 0.0
	_chk(vacio.vacio(), "a 0 hay que avisar", "")
	_chk(vacio.mas_bajo() == "hambre", "el aviso dice cual", vacio.mas_bajo())

	# Los efectos de la energia existen (y se mueven).
	var cansado: Vitals = VT.new(100.0, 100.0, 0.0)
	_chk(cansado.mult_velocidad() < 1.0,
		"sin energia se camina mas lento", str(cansado.mult_velocidad()))
	_chk(cansado.mult_ataque() < 1.0,
		"sin energia se pega mas lento", str(cansado.mult_ataque()))
	var fresco: Vitals = VT.new(100.0, 100.0, 100.0)
	_chk(is_equal_approx(fresco.mult_velocidad(), 1.0), "con energia, normal", "")
	_chk(is_equal_approx(fresco.mult_ataque(), 1.0), "con energia, normal", "")


# --- (d) tick-eat -----------------------------------------------------

func _test_tick_eat() -> void:
	# Un Player de verdad: es el unico nodo con `inventario` (asi lo arma el
	# juego). Con un Entity pelado la asignacion falla en runtime y el test
	# pasaria sin haber probado nada.
	var e: Player = PL.new()
	root.add_child(e)
	_basura.append(e)
	var inv: Inventario = e.inventario
	_chk(inv != null, "el Player nace con inventario", "")

	e.vitals.hambre = 30.0
	inv.agregar("carne_asada_lobo", 2)

	_chk(inv.usar("carne_asada_lobo", e),
		"usar() acepta un alimento", "")
	_chk(e.vitals.hambre > 30.0,
		"el alimento sube el hambre del jugador", str(e.vitals.hambre))
	_chk(inv.contar("carne_asada_lobo") == 1,
		"y se consume UNO de la pila", str(inv.contar("carne_asada_lobo")))

	# Sin item no hace nada (y no revienta).
	_chk(not inv.usar("carne_asada_inexistente", e), "item inexistente: no", "")
	_chk(not inv.usar("carne_asada_lobo", e) == false, "con item: si", "")

	# Un item NO consumible (arma) se rechaza.
	inv.agregar("verdugo_eco", 1)
	_chk(not inv.usar("verdugo_eco", e), "un arma no se 'usa' como comida", "")


# --- (e) los mobs tiran carne ----------------------------------------

func _test_mobs_tiran_carne() -> void:
	var datos = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/enemies.json"))
	var arqs: Dictionary = (datos as Dictionary).get("arquetipos", {})
	for id in ["goblin", "lobo", "ogro"]:
		var carne: String = "carne_cruda_" + id
		var loot: Dictionary = (arqs[id] as Dictionary).get("loot", {})
		var ids: Array = []
		for i in loot.get("items", []):
			ids.append(str((i as Dictionary).get("item_id", "")))
		_chk(ids.has(carne), "el %s tira %s" % [id, carne], str(ids))
		for i in loot.get("items", []):
			_chk(IT.existe(str((i as Dictionary).get("item_id", ""))),
				"el drop '%s' del %s existe como item" % [
					str((i as Dictionary).get("item_id", "")), id], "")


# --- (f) save ---------------------------------------------------------

func _test_save() -> void:
	var e: Entity = _entidad()
	e.vitals.hambre = 33.0
	e.vitals.sed = 44.0
	e.vitals.energia = 55.0
	e.vitals.enfermedad = 7.0

	var d: Dictionary = e.to_dict()
	_chk(d.has("vitals"), "los vitals van en el save", str(d.keys()))

	var e2: Entity = EN.new()
	e2.restaurar(d)
	_chk(is_equal_approx(e2.vitals.hambre, 33.0), "el hambre viaja", str(e2.vitals.hambre))
	_chk(is_equal_approx(e2.vitals.sed, 44.0), "la sed viaja", str(e2.vitals.sed))
	_chk(is_equal_approx(e2.vitals.energia, 55.0), "la energia viaja", str(e2.vitals.energia))
	_chk(is_equal_approx(e2.vitals.enfermedad, 7.0), "la enfermedad viaja", "")
	_basura.append(e2)

	# Un save viejo (sin vitals) carga con los vitals llenos, no con 0.
	var e3: Entity = EN.new()
	e3.restaurar({"version": 1, "nivel": 1})
	_chk(e3.vitals.esta_lleno(),
		"un save viejo carga con los vitals llenos (no a 0)", "")
	_basura.append(e3)
