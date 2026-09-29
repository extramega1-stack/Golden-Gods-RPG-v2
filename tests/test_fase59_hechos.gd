extends SceneTree
## Tests headless de la Fase 59 (Hechos de Habilidad).
##
## POR QUÉ NACE: la fase 58 pone hambre y sed. Sin esto, eso es un castigo.
## Con esto, cada vez que tenés hambre decidís si gastás tu Hecho de Tala
## para resolverla rápido o si caminás hasta la fogata. Esa decisión ES el
## juego, y es la idea que Dragonwilds hace mejor que nadie.
##
## Cubre:
## (a) el DATO: hechos con habilidad + tramo, de tipo `mod` o `bandera`;
## (b) se desbloquean con el XP de habilidad (fase 57), NO con el nivel;
## (c) los `mod` van al StatBlock y son reversibles si dejás de cumplir;
## (d) los `bandera` los leen los sistemas: tala, veta, vitals;
## (e) la reconnectividad: subir una habilidad abre el hecho solo.

const HC: GDScript = preload("res://scripts/skills/hechos.gd")
const HB: GDScript = preload("res://scripts/skills/habilidades.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const TA: GDScript = preload("res://scripts/mundo/talar.gd")
const VT: GDScript = preload("res://scripts/core/vitals.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 59 — Hechos de Habilidad")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_dato()
	_test_bloqueo()
	_test_mods()
	_test_banderas()
	_test_tala_transforma()
	_test_vitales_flags()
	_test_por_defecto_no_rompe()
	print("[TEST] fase59_hechos: %d ok, %d fallos" % [_ok, _fallos])
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


func _par(habilidades_tope: int) -> Array:
	"""[Player, Hechos] con `habilidades_tope` tramos de Tala ya abiertos."""
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)
	var h: Hechos = HC.crear_desde_datos()
	h.fijar_habilidades(p.habilidades)
	p.hechos = h
	p.habilidades.ganar("tala", habilidades_tope * 10_000)
	h.aplicar(p.stats)
	return [p, h]


func _test_dato() -> void:
	var p: Player = _jugador_plano()
	var h: Hechos = HC.crear_desde_datos()
	h.fijar_habilidades(p.habilidades)
	_chk(h.total() >= 8, "hay al menos 8 hechos", str(h.total()))

	var mods: int = 0
	var banderas: int = 0
	for id in h.ids():
		var d: Dictionary = h.hecho(id)
		_chk(str(d.get("habilidad", "")) != "",
			"'%s' declara de qué habilidad sale" % id, str(d))
		_chk(int(d.get("tramo", 0)) >= 1,
			"'%s' pide al menos el tramo 1" % id, str(d))
		_chk(h.descripcion_de(id) != "", "'%s' tiene descripción" % id, "")
		match str(d.get("tipo", "")):
			"mod":
				mods += 1
				_chk(str(d.get("stat", "")) != "", "'%s' dice qué stat" % id, str(d))
			"bandera":
				banderas += 1
				_chk(str(d.get("flag", "")) != "", "'%s' dice qué bandera" % id, str(d))
			_:
				_chk(false, "'%s' tiene un tipo conocido" % id, str(d.get("tipo", "")))
	_chk(mods >= 2, "hay hechos que suman stats", str(mods))
	_chk(banderas >= 5, "y hechos que TRANSFORMAN (banderas)", str(banderas))

	# Ninguna bandera repetida: si dos hechos comparten bandera, el segundo
	# pisa al primero y se pierde uno sin avisar.
	var vistas := {}
	for id in h.ids():
		var f: String = h.flag_de(id)
		if f == "":
			continue
		_chk(not vistas.has(f), "la bandera '%s' no se repite" % f, str(h.ids()))
		vistas[f] = id
	_basura.append(p)


func _jugador_plano() -> Player:
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)
	return p


func _test_bloqueo() -> void:
	var p: Player = _jugador_plano()
	var h: Hechos = HC.crear_desde_datos()
	h.fijar_habilidades(p.habilidades)
	_chk(h.desbloqueados().is_empty(),
		"sin XP de habilidad no hay hechos abiertos", str(h.desbloqueados()))

	# El nivel de personaje NO abre hechos: solo el XP de habilidad.
	p.gain_xp(100000)
	_chk(h.desbloqueados().is_empty(),
		"subir de NIVEL no abre hechos (solo el XP de habilidad)",
		str(h.desbloqueados()))

	# El XP de habilidad sí.
	p.habilidades.ganar("tala", 10_000)
	_chk(h.desbloqueados().size() > 0,
		"el XP de habilidad sí abre hechos", str(h.desbloqueados()))

	# Y solo los de Tala, no los de Minería.
	for id in h.desbloqueados():
		_chk(str(h.hecho(id).get("habilidad", "")) == "tala",
			"'%s' es de Tala" % id, "")
	_basura.append(p)


func _test_mods() -> void:
	var par: Array = _par(10)
	var p: Player = par[0]
	var h: Hechos = par[1]

	var vel: float = p.stats.vel_ataque
	var mov: float = p.stats.vel_mov
	_chk(p.stats.has_mod("hecho:mena_rapida") == false,
		"sin abrir Minería, su mod NO está aplicado", "")
	_chk(is_equal_approx(p.stats.vel_ataque, vel), "y los stats no se tocaron", "")

	# Abrimos Minería: el mod entra.
	p.habilidades.ganar("mineria", 100_000)
	h.aplicar(p.stats)
	_chk(p.stats.has_mod("hecho:mena_rapida"),
		"al abrir el tramo, el mod se aplica", "")
	_chk(p.stats.vel_ataque > vel, "y sube la velocidad de ataque",
		"%s vs %s" % [p.stats.vel_ataque, vel])
	_chk(is_equal_approx(p.stats.vel_mov, mov),
		"y la de movimiento NO cambia (saco_ligero es de Recolección, no de Minería)", "")
	p.habilidades.ganar("recoleccion", 100_000)
	h.aplicar(p.stats)
	_chk(p.stats.vel_mov > mov, "al abrir Recolección, sube la de movimiento (saco_ligero)",
		"%s vs %s" % [p.stats.vel_mov, mov])

	# La fuente del mod es `hecho:<id>`, distinta de los talentos de clase
	# (`talento:<id>`): si se cruzaran, quitar un talento borraría un hecho.
	_chk(Hechos.FUENTE == "hecho:", "la fuente es 'hecho:'", Hechos.FUENTE)


func _test_banderas() -> void:
	var par: Array = _par(10)
	var p: Player = par[0]
	var h: Hechos = par[1]
	_chk(h.tiene("tala_area"), "con Tala en tramo 2+, 'tala_area' está", "")
	_chk(h.tiene("tala_rangos"), "y en tramo 4+, 'tala_rangos'", "")
	_chk(not h.tiene("veta_persistente"),
		"pero 'veta_persistente' NO (es de Minería)", "")

	# El recargado limpio: si la habilidad pierde el tramo, la bandera se va.
	var p2: Player = _jugador_plano()
	var h2: Hechos = HC.crear_desde_datos()
	h2.fijar_habilidades(p2.habilidades)
	p2.habilidades.ganar("tala", 10_000)
	h2.aplicar(p2.stats)
	_chk(h2.tiene("tala_area"), "tala_area abierta", "")
	p2.habilidades._xp["tala"] = 0
	h2.aplicar(p2.stats)
	_chk(not h2.tiene("tala_area"),
		"si el tramo se pierde, la bandera se va", "")
	_basura.append(p2)


func _test_tala_transforma() -> void:
	var p: Player = _jugador_plano()
	var arbol := Veta.new()
	root.add_child(arbol)
	_basura.append(arbol)
	arbol.configurar({"id": "t", "item_id": "tronco_roble", "cantidad": 1,
		"usos": 5, "respawn_s": 180, "xp": 6, "nivel": 1, "tinte": "#fff",
		"x": 0, "z": 0})

	# Sin hechos: 1 tronco por tajo.
	var r1: Dictionary = Talar.talar(arbol, null)
	_chk(int(r1["cantidad"]) == 1, "sin hechos, 1 tronco", str(r1))

	# Con "tala_area": 3, pero gastando UN solo uso.
	var p2: Player = _jugador_plano()
	var h: Hechos = HC.crear_desde_datos()
	h.fijar_habilidades(p2.habilidades)
	p2.habilidades.ganar("tala", 10_000)
	h.aplicar(p2.stats)
	_chk(Talar.multiplicador(h) == 3, "el multiplicador es 3", "")
	var r2: Dictionary = Talar.talar(arbol, h)
	_chk(int(r2["cantidad"]) == 3, "con tala_area, 3 troncos", str(r2))
	_chk(int(r2["cantidad_base"]) == 1, "y el base sigue siendo 1", str(r2))
	_chk(arbol.usos_restantes() == 3, "pero gasta UN uso (4->3)", str(arbol.usos_restantes()))

	# El nivel: con "Leñador" se puede talar 2 tramos por encima.
	var alto := Veta.new()
	root.add_child(alto)
	_basura.append(alto)
	# Tolerancia de 2 tramos: un árbol de nivel 11 pide nivel 9.
	alto.configurar({"id": "alto", "item_id": "tronco_roble", "cantidad": 1,
		"usos": 3, "respawn_s": 180, "xp": 6, "nivel": 11, "tinte": "#fff",
		"x": 0, "z": 0})
	_chk(Talar.puede_talar(alto, 8, null) == Talar.MOTIVO_NIVEL,
		"sin el hecho, nivel 8 no alcanza un árbol de 11", "")
	# Con el hecho, la exigencia baja 2 tramos: 11 - 2 = 9, y nivel 10 pasa.
	_chk(Talar.puede_talar(alto, 10, h) == Talar.MOTIVO_OK,
		"con 'Leñador' (2 tramos), nivel 10 alcanza un árbol de 11",
		Talar.puede_talar(alto, 10, h))
	_chk(Talar.puede_talar(alto, 8, h) == Talar.MOTIVO_NIVEL,
		"pero nivel 8 sigue sin alcanzar (11-2=9 > 8)",
		Talar.puede_talar(alto, 8, h))


func _test_vitales_flags() -> void:
	# "Sed ausente": la sed tarda el doble. `Vitals` es puro y recibe el
	# multiplicador como número, no una referencia a Hechos.
	var v1: Vitals = Vitals.new()
	var v2: Vitals = Vitals.new()
	v2.mult_sed = 0.5
	v1.avanzar(10.0, 1.0)
	v2.avanzar(10.0, 1.0)
	_chk(v2.sed > v1.sed, "con 'sed ausente' la sed tarda más",
		"%s vs %s" % [v2.sed, v1.sed])
	_chk(is_equal_approx(v2.hambre, v1.hambre),
		"pero el hambre no cambia (solo la sed)", "")

	var v3: Vitals = Vitals.new()
	var v4: Vitals = Vitals.new()
	v4.mult_hambre = 0.5
	v3.avanzar(10.0, 1.0)
	v4.avanzar(10.0, 1.0)
	_chk(v4.hambre > v3.hambre, "y con 'hambre ausente' el hambre tarda más",
		"%s vs %s" % [v4.hambre, v3.hambre])


func _test_por_defecto_no_rompe() -> void:
	# Sin hechos, TODO debe comportarse como antes de la 59.
	var p: Player = _jugador_plano()
	_chk(p.hechos != null, "el Player nace con hechos", "")
	_chk(p.hechos.desbloqueados().is_empty(), "y ninguno abierto de entrada", "")
	_chk(Talar.multiplicador(p.hechos) == 1, "el multiplicador de tala es 1", "")
	_chk(Talar.tolerancia(p.hechos) == 0, "y la tolerancia de nivel es 0", "")
	_chk(p.vitals.mult_hambre == 1.0 and p.vitals.mult_sed == 1.0,
		"y los vitals decaen normal", "")
