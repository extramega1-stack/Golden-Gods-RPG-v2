extends SceneTree
## Tests headless de la Fase 61 (construir en el Refugio).
##
## POR QUÉ NACE: es la fase más cara del proyecto y la que más riesgo de
## romper el presupuesto de GPU. El mundo ya tenía 72 ArrayMesh y 36
## ConcavePolygonShape3D RESIDENTES (§9.5) antes de esto.
##
## Este test es, sobre todo, la PUERTA DE PRESUPUESTO: si alguien sube el
## tope o hace que la colocación se cuelgue, el test se cae.
##
## Cubre:
## (a) el DATO: piezas con costo, caja y acción;
## (b) el snapping a rejilla;
## (c) las rotaciones: 4 si la pieza admite, 1 si no;
## (d) no se solapan piezas, y hay holgura entre ellas;
## (e) el presupuesto de piezas se respeta y NO se puede pasar;
## (f) los materiales se cobran de verdad;
## (g) nada sale del radio del refugio.

const PB: GDScript = preload("res://scripts/mundo/piezas_db.gd")
const CO: GDScript = preload("res://scripts/mundo/constructor.gd")
const RF: GDScript = preload("res://scripts/mundo/refugio.gd")
const IT: GDScript = preload("res://scripts/inventory/item_db.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 61 — construir en el Refugio")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	IT.cargar()
	PB.cargar()
	_test_dato()
	_test_rejilla()
	_test_rotaciones()
	_test_solapes()
	_test_presupuesto()
	_test_materiales()
	_test_radio()
	print("[TEST] fase61_construccion: %d ok, %d fallos" % [_ok, _fallos])
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


func _refugio() -> Refugio:
	var r: Refugio = RF.new()
	root.add_child(r)
	_basura.append(r)
	r.configurar_por_id("refugio_moon_town")
	r.reclamar(50)
	return r


# --- (a) el dato ------------------------------------------------------

func _test_dato() -> void:
	_chk(PB.ids().size() >= 6, "hay al menos 6 piezas", str(PB.ids().size()))
	var con_accion: int = 0
	for id in PB.ids():
		var d: Dictionary = PB.pieza(id)
		_chk(str(d.get("nombre", "")) != "", "'%s' tiene nombre" % id, str(d))
		var costo: Dictionary = d.get("costo", {})
		_chk(not costo.is_empty(), "'%s' cuesta algo" % id, str(d))
		# Cada material de la pieza existe como item.
		for item in costo.keys():
			_chk(IT.existe(str(item)),
				"el material '%s' de '%s' existe" % [str(item), id], "")
		var caja: Vector3 = PB.caja(id)
		_chk(caja.x > 0.0 and caja.y > 0.0 and caja.z > 0.0,
			"'%s' ocupa caja positiva" % id, str(caja))
		if PB.accion(id) != "":
			con_accion += 1
	_chk(con_accion >= 3, "hay piezas interactivas (cocinar/forjar/dormir)", str(con_accion))
	_chk(PB.existe("fogata"), "la fogata está en el catálogo", "")
	_chk(not PB.existe("piece_inexistente"), "una pieza rara no existe", "")
	_chk(PB.pieza("nada").is_empty(), "y obtener() de algo raro es vacío", "")


# --- (b) la rejilla ---------------------------------------------------

func _test_rejilla() -> void:
	_chk(is_equal_approx(Constructor.REJILLA, 2.0), "la rejilla es de 2 u", "")
	var a := Constructor.ajustar(Vector3(3.1, 0.0, 5.2))
	_chk(is_equal_approx(a.x, 4.0), "x 3.1 -> 4", str(a.x))
	_chk(is_equal_approx(a.z, 6.0), "z 5.2 -> 6", str(a.z))
	_chk(is_equal_approx(a.y, 0.0), "la rejilla es plana (y = 0)", str(a.y))
	# Ajustar dos veces da lo mismo (idempotente: es lo que evita el drift).
	_chk(Constructor.ajustar(a) == a, "ajustar es idempotente", "")
	_chk(Constructor.ajustar(Vector3(-1.0, 0.0, -1.0)) == Vector3(-2.0, 0.0, -2.0),
		"y funciona con negativos", str(Constructor.ajustar(Vector3(-1.0, 0.0, -1.0))))


# --- (c) rotaciones ---------------------------------------------------

func _test_rotaciones() -> void:
	# Una pieza que NO admite rotación tiene una sola.
	_chk(Constructor.rotaciones("cofre").size() == 1,
		"una pieza sin rotación tiene 1 orientación", str(Constructor.rotaciones("cofre")))
	# Una que sí, tiene 4 (y no 360, que sería un editor de construcción).
	var r := Constructor.rotaciones("saco")
	_chk(r.size() == 4, "una pieza rotable tiene 4 orientaciones", str(r))
	for v in r:
		_chk(is_equal_approx(fposmod(v, 360.0), v) and v >= 0.0 and v < 360.0,
			"la rotación %s está normalizada" % str(v), "")

	# La caja girada intercambia X y Z en 90° y 270°.
	var caja: Vector3 = PB.caja("saco")
	var g0 := Constructor._caja_orientada("saco", 0.0)
	var g90 := Constructor._caja_orientada("saco", 90.0)
	_chk(is_equal_approx(g90.x, caja.z) and is_equal_approx(g90.z, caja.x),
		"a 90° la caja intercambia X y Z", "%s vs %s" % [g90, caja])
	_chk(is_equal_approx(Constructor._caja_orientada("saco", 180.0).x, g0.x),
		"a 180° vuelve a la original", "")
	_chk(is_equal_approx(Constructor._caja_orientada("saco", 450.0).x, g90.x),
		"450° es lo mismo que 90°", "")


# --- (d) solapes ------------------------------------------------------

func _test_solapes() -> void:
	var pie: Array = []
	# Dos cosas en el mismo lugar: se solapan.
	pie.append({"tipo": "fogata", "x": 4.0, "z": 0.0, "rot": 0.0})
	_chk(Constructor.se_solapa("fogata", Vector3(4.0, 0, 0), 0.0, pie),
		"dos piezas en el mismo sitio se solapan", "")
	# A dos casillas (2 u) con cajas de 1.6 queda 0.4 de hueco: NO se solapan.
	_chk(not Constructor.se_solapa("fogata", Vector3(6.0, 0, 0), 0.0, pie),
		"a dos casillas NO se solapan (caja 1.6 deja 0.4 de hueco)", "")
	_chk(Constructor.se_solapa("fogata", Vector3(4.0, 0, 1.0), 0.0, pie),
		"pero a una casilla y media, sí", "")
	_chk(not Constructor.se_solapa("fogata", Vector3(12.0, 0, 0), 0.0, pie),
		"pero bien lejos, no", "")

	# Una pieza alta (columna, 3 u) solapa en vertical aunque en el plano no.
	pie.clear()
	pie.append({"tipo": "columna", "x": 0.0, "z": 0.0, "rot": 0.0})
	_chk(Constructor.se_solapa("columna", Vector3(0.0, 0, 0), 0.0, pie),
		"dos columnas en el mismo sitio se solapan", "")

	# Una lista vacía nunca solapa.
	_chk(not Constructor.se_solapa("fogata", Vector3.ZERO, 0.0, []),
		"con nada puesto, no hay solape", "")


# --- (e) EL PRESUPUESTO ----------------------------------------------

func _test_presupuesto() -> void:
	var r: Refugio = _refugio()
	var inv: Dictionary = {"tronco_roble": 999, "tronco_pino": 999,
		"mineral_cobre": 999, "baya_roja": 999}

	# Llenar hasta el tope con una CUADRÍCULA, no en línea: el refugio es
	# circular de radio 42 y una fila se sale del círculo a los 10.
	var puestas: Array = []
	var centro: Vector3 = r.global_position
	var idx: int = 0
	while puestas.size() < r.piezas_max and idx < 200:
		# Espiral de 4 u alrededor del centro, en anillos de 4.
		var anillo: int = idx / 8
		var en_anillo: int = idx % 8
		var ang: float = TAU * float(en_anillo) / 8.0
		var d: float = 4.0 * float(anillo + 1)
		var pos := Vector3(centro.x + cos(ang) * d, 0.0, centro.z + sin(ang) * d)
		idx += 1
		if not Constructor.puede_colocar(r, "columna", pos, 0.0, puestas):
			continue
		Constructor.descontar("columna", inv)
		puestas.append({"tipo": "columna", "x": pos.x, "z": pos.z, "rot": 0.0})
	_chk(puestas.size() == r.piezas_max,
		"se llena hasta el tope (%d)" % r.piezas_max, str(puestas.size()))
	_chk(puestas.size() >= r.piezas_max, "y llegó al tope", str(puestas.size()))

	# LA PUERTA: una pieza más NO se puede colocar, aunque tenga materiales y
	# esté en un sitio libre. Esto es el presupuesto de VRAM.
	var libre := Vector3(r.global_position.x, 0.0, r.global_position.z)
	_chk(Constructor.tiene_materiales("columna", inv), "y con materiales de sobra", "")
	_chk(not Constructor.se_solapa("columna", libre, 0.0, puestas),
		"y en un sitio libre", "")
	_chk(not Constructor.puede_colocar(r, "columna", libre, 0.0, puestas),
		"pero NO se puede colocar: el refugio está lleno", "")
	_chk(puestas.size() - r.piezas_max == 0, "y no queda ningún hueco en el tope", "")
	_chk(r.piezas_restantes() == r.piezas_max - r.piezas(),
		"el Refugio sigue con su presupuesto entero (las piezas viven en la lista)", "")


# --- (f) materiales ---------------------------------------------------

func _test_materiales() -> void:
	var r: Refugio = _refugio()

	# Sin materiales no se construye.
	var vacio: Dictionary = {}
	_chk(not Constructor.tiene_materiales("fogata", vacio),
		"sin inventario no hay materiales", "")
	_chk(Constructor.materiales_faltantes("fogata", vacio).size() > 0,
		"y dice qué falta", "")
	var res := Constructor.descontar("fogata", vacio)
	_chk(not bool(res.get("ok", true)), "descontar sin materiales falla", str(res))
	_chk(str(res.get("motivo", "")) == "sin_materiales", "con el motivo", str(res))

	# Con lo justo, se descuenta de verdad.
	var inv: Dictionary = {"tronco_roble": 5}
	_chk(Constructor.tiene_materiales("fogata", inv), "con 5 troncos alcanza", "")
	var r2 := Constructor.descontar("fogata", inv)
	_chk(bool(r2.get("ok", false)), "descontar funciona", str(r2))
	_chk(int(inv.get("tronco_roble", 0)) == 3,
		"y descuenta el costo de la pieza", str(inv))

	# A cero, la pila se borra (no queda en 0).
	var justo: Dictionary = {"tronco_roble": 2}
	Constructor.descontar("fogata", justo)
	_chk(not justo.has("tronco_roble"), "la pila a 0 se borra", str(justo))

	# Parcial no alcanza: la fogata pide 2 troncos.
	var uno: Dictionary = {"tronco_roble": 1}
	_chk(not Constructor.tiene_materiales("fogata", uno), "con 1 tronco no alcanza", "")


# --- (g) el radio -----------------------------------------------------

func _test_radio() -> void:
	var r: Refugio = _refugio()
	# Justo adentro y bien afuera.
	_chk(Constructor.puede_colocar(r, "fogata",
			Vector3(4.0, 0.0, r.global_position.z), 0.0, []),
		"dentro del refugio sí", "")
	var lejos := Vector3(r.radio * 2.0, 0.0, r.global_position.z)
	_chk(not Constructor.puede_colocar(r, "fogata", lejos, 0.0, []),
		"muy afuera no", "")
	_chk(Constructor.texto_motivo("fuera_de_radio") != "",
		"y hay texto para el motivo", "")
	_chk(Constructor.texto_motivo("sin_materiales") != "", "", "")
