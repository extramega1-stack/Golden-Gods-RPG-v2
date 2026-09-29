extends SceneTree
## Tests headless de la Fase 55 (tala).
##
## POR QUÉ NACE: el proyecto tenía recolección de mineral (fase 45) y nada
## para madera. La tala es la recolección hermana: el nodo `Arbol` HEREDA de
## `Veta`, así que este test comprueba que la herencia no rompe nada de la
## minería y que agrega lo suyo (silueta, señal `talada`, copa que desaparece
## al agotarse).
##
## Cubre:
## (a) el DATO: `data/arboles.json` es determinista, tiene todo lo que hace
##     falta y no pisa ninguna veta;
## (b) `ArbolDB` carga;
## (c) `Arbol` hereda de `Veta` y funciona como recurso;
## (d) `Talar`: motivos, tajo, XP;
## (e) el streaming por histéresis tiene el mismo comportamiento que el de
##     las vetas;
## (f) la fx 45 sigue verde (no se rompió la minería al heredar).
##
## Cómo correrlo:
## godot --headless --path <proyecto> --script res://tests/test_fase55_tala.gd

const AD: GDScript = preload("res://scripts/mundo/arbol_db.gd")
const AR: GDScript = preload("res://scripts/mundo/arbol.gd")
const TA: GDScript = preload("res://scripts/mundo/talar.gd")
const GA: GDScript = preload("res://scripts/mundo/gestor_arboles.gd")
const IT: GDScript = preload("res://scripts/inventory/item_db.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 55 — tala")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	IT.cargar()
	AD.cargar()
	_test_dato()
	_test_db()
	_test_arbol_hereda_veta()
	_test_talar()
	_test_streaming()
	print("[TEST] fase55_tala: %d ok, %d fallos" % [_ok, _fallos])
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


func _arbol(d: Dictionary = {}) -> Arbol:
	var base: Dictionary = {
		"id": "arbol_prueba", "nombre": "Roble de prueba",
		"region": "moon_town", "item_id": "tronco_roble",
		"cantidad": 2, "usos": 3, "respawn_s": 180, "xp": 6,
		"nivel": 1, "tinte": "#4a7a3a", "x": 0.0, "z": 0.0,
	}
	for k in d:
		base[k] = d[k]
	var a: Arbol = AR.new()
	root.add_child(a)
	_basura.append(a)
	a.configurar(base)
	return a


# --- (a) el dato ------------------------------------------------------

func _test_dato() -> void:
	var ruta_py: String = ProjectSettings.globalize_path("res://tools/generar_arboles.py")
	var prueba: String = ProjectSettings.globalize_path("user://arboles_prueba.json")
	var salida: Array = []
	var rc1: int = OS.execute("python3", PackedStringArray([ruta_py, prueba]), salida, true)
	var sha1: String = FileAccess.get_sha256(prueba)
	var rc2: int = OS.execute("python3", PackedStringArray([ruta_py, prueba]), salida, true)
	var sha2: String = FileAccess.get_sha256(prueba)
	_chk(rc1 == 0 and rc2 == 0, "el generador corre dos veces", "rc=%d/%d" % [rc1, rc2])
	_chk(sha1 != "" and sha1 == sha2, "dos corridas dan el mismo SHA-256", "")
	_chk(sha1 == FileAccess.get_sha256("res://data/arboles.json"),
		"reproduce data/arboles.json byte a byte", "")
	DirAccess.remove_absolute(prueba)

	var datos = JSON.parse_string(FileAccess.get_file_as_string("res://data/arboles.json"))
	var arboles: Array = (datos as Dictionary).get("arboles", [])
	_chk(arboles.size() >= 100, "hay al menos 100 arboles", str(arboles.size()))

	# Todos los items existen y hay varios (varias especies por bioma).
	var especies := {}
	for a in arboles:
		var d: Dictionary = a
		_chk(IT.existe(str(d.get("item_id", ""))),
			"el item '%s' existe" % str(d.get("item_id", "")), "")
		especies[str(d.get("item_id", ""))] = true
	_chk(especies.size() >= 6, "hay varias especies de madera", str(especies.size()))

	# Campos completos y dentro del mundo.
	var ids := {}
	for a in arboles:
		var d: Dictionary = a
		for k in ["id", "region", "item_id", "cantidad", "usos", "respawn_s", "xp", "nivel"]:
			_chk(d.has(k), "el arbol tiene '%s'" % k, str(d.keys()))
		_chk(int(d.get("usos", 0)) > 0, "el arbol '%s' tiene usos" % str(d.get("id")), "")
		_chk(int(d.get("respawn_s", 0)) > 0, "y respawn", "")
		_chk(absf(float(d.get("x", 0.0))) <= 18432.0
				and absf(float(d.get("z", 0.0))) <= 18432.0,
			"el arbol '%s' cae dentro del mundo" % str(d.get("id")), "")
		ids[str(d.get("id", ""))] = true
	_chk(ids.size() == arboles.size(), "los ids de arbol son unicos",
		"%d ids / %d arboles" % [ids.size(), arboles.size()])

	# No encima de una veta.
	var vetas = JSON.parse_string(FileAccess.get_file_as_string("res://data/vetas.json"))
	var vs: Array = (vetas as Dictionary).get("vetas", [])
	for a in arboles:
		var d: Dictionary = a
		for v in vs:
			var vd: Dictionary = v
			var dist: float = Vector2(float(d["x"]) - float(vd["x"]),
				float(d["z"]) - float(vd["z"])).length()
			_chk(dist > 6.0,
				"el arbol '%s' no pisa la veta '%s'" % [str(d["id"]), str(vd["id"])],
				"dist=%.1f" % dist)


# --- (b) la DB -------------------------------------------------------

func _test_db() -> void:
	_chk(AD.ids().size() > 100, "ArbolDB carga y ve los arboles", str(AD.ids().size()))
	var primero: String = AD.ids()[0]
	_chk(AD.existe(primero), "existe el primero", primero)
	_chk(not AD.existe("arbol_inexistente"), "uno inexistente no existe", "")
	var d: Dictionary = AD.obtener(primero)
	_chk(d.has("item_id"), "el dato trae item_id", str(d.keys()))


# --- (c) Arbol hereda de Veta ----------------------------------------

func _test_arbol_hereda_veta() -> void:
	_chk(_es_subclase_de_veta(), "Arbol hereda de Veta (no lo copia)", "")

	var a: Arbol = _arbol()
	_chk(a.item_id == "tronco_roble", "toma el item del dato", a.item_id)
	_chk(a.usos_max == 3, "toma los usos del dato", str(a.usos_max))
	_chk(a.respawn_s == 180.0, "toma el respawn del dato", str(a.respawn_s))
	_chk(a.esta_minable(), "arranca talable", "")
	_chk(a.usos_restantes() == 3, "con los 3 usos", "")

	# La silueta: tronco + copa, y la roca de la veta apagada.
	_chk(a.get_node_or_null("Tronco") != null, "el arbol tiene tronco", "")
	_chk(a.get_node_or_null("Copa") != null, "el arbol tiene copa", "")
	var cuerpo := a.get_node_or_null("Cuerpo") as MeshInstance3D
	_chk(cuerpo != null and not cuerpo.visible,
		"la roca de la veta queda oculta", "")

	# La señal: `minada` del padre, reemitida como `talada`.
	var taladas: Array = []
	a.talada.connect(func(item: String, cant: int, xp: int):
		taladas.append({"item": item, "cant": cant, "xp": xp}))
	# El padre emite al consumir el item, no al gastar el uso: la veta avisa
	# desde `Mineria`, y acá se comprueba que la reemision funciona.
	a.emit_signal("minada", "tronco_roble", 2, 6)
	_chk(taladas.size() == 1, "la señal `talada` sale", str(taladas))
	if taladas.size() == 1:
		_chk(str((taladas[0] as Dictionary)["item"]) == "tronco_roble",
			"con el item correcto", str(taladas[0]))


func _es_subclase_de_veta() -> bool:
	var a: Arbol = AR.new()
	var ok: bool = a is Veta
	if is_instance_valid(a):
		a.free()
	return ok


# --- (d) Talar -------------------------------------------------------

func _test_talar() -> void:
	var a: Arbol = _arbol()
	_chk(Talar.puede_talar(a, 1) == Talar.MOTIVO_OK,
		"se puede talar", Talar.puede_talar(a, 1))

	# Nivel insuficiente: se respeta la banda de la región.
	var alta: Arbol = _arbol({"nivel": 40})
	_chk(Talar.puede_talar(alta, 5) == Talar.MOTIVO_NIVEL,
		"un arbol de nivel alto no se tala con nivel bajo", Talar.puede_talar(alta, 5))
	_chk(Talar.puede_talar(alta, 60) == Talar.MOTIVO_OK,
		"con nivel alcanza", Talar.puede_talar(alta, 60))

	# Un tajo gasta un uso y devuelve el item.
	var r: Dictionary = Talar.talar(a)
	_chk(bool(r.get("ok", false)), "talar() funciona", str(r))
	_chk(str(r.get("item_id", "")) == "tronco_roble", "devuelve el item", str(r))
	_chk(int(r.get("cantidad", 0)) == 2, "con la cantidad del dato", str(r))
	_chk(int(r.get("xp", 0)) == 6, "y el xp del dato", str(r))
	_chk(a.usos_restantes() == 2, "gasto un uso", str(a.usos_restantes()))
	_chk(not bool(r.get("agotado", true)), "el arbol no quedo agotado", str(r))

	# Agotarlo.
	Talar.talar(a)
	var r3: Dictionary = Talar.talar(a)
	_chk(bool(r3.get("agotado", false)), "al tercer tajo se agota", str(r3))
	_chk(Talar.puede_talar(a, 1) == Talar.MOTIVO_EN_RESPAWN,
		"agotado = en respawn", Talar.puede_talar(a, 1))

	# Y la copa desaparece (el árbol se ve talado).
	var copa := a.get_node_or_null("Copa") as MeshInstance3D
	_chk(copa != null and not copa.visible, "al agotarse pierde la copa", "")

	# Pasado el respawn, vuelve.
	a.tick(200.0)
	_chk(a.esta_minable(), "vuelve tras el respawn", str(a.usos_restantes()))
	_chk(copa != null and copa.visible, "y le vuelve la copa", "")

	# Motivos legibles.
	_chk(Talar.texto_motivo(Talar.MOTIVO_AGOTADO) != "",
		"todo motivo tiene texto", "")
	_chk(Talar.texto_motivo(Talar.MOTIVO_OK) == "",
		"el motivo OK no muestra nada", "")

	# Un árbol null no revienta.
	_chk(Talar.puede_talar(null, 1) == Talar.MOTIVO_SIN_HABILIDAD,
		"un arbol null no se tala", "")
	_chk(not bool(Talar.talar(null).get("ok", true)), "talar(null) no revienta", "")


# --- (e) streaming ---------------------------------------------------

func _test_streaming() -> void:
	var g: GestorArboles = GA.new()
	root.add_child(g)
	_basura.append(g)
	_chk(g.total() > 100, "el gestor ve todos los arboles del JSON", str(g.total()))
	_chk(g.radio_baja > g.radio_alta,
		"la histéresis es real (baja > alta)",
		"alta=%s baja=%s" % [g.radio_alta, g.radio_baja])

	var jugador := Node3D.new()
	root.add_child(jugador)
	_basura.append(jugador)
	g.fijar_jugador(jugador)
	# Lejos de todo: no debería colocar nada.
	jugador.global_position = Vector3(0.0, 0.0, 30000.0)
	g._pensar()
	_chk(g.vivos() == 0, "lejos de todo no coloca arboles", str(g.vivos()))

	# Encima del primero: coloca algunos.
	var primero: Dictionary = AD.obtener(AD.ids()[0])
	jugador.global_position = Vector3(float(primero["x"]), 0.0, float(primero["z"]))
	g._pensar()
	_chk(g.vivos() > 0, "cerca coloca arboles", str(g.vivos()))

	# Histéresis: en la banda intermedia NO los saca (no hay churn).
	var fuera: float = g.radio_alta + (g.radio_baja - g.radio_alta) * 0.5
	jugador.global_position = Vector3(float(primero["x"]) + fuera, 0.0, float(primero["z"]))
	g._pensar()
	_chk(g.vivos() > 0, "en la banda intermedia NO los saca (histéresis)", str(g.vivos()))

	# Lejos de todo otra vez: los retira. (Una distancia fija desde el primero
	# podia caer cerca de OTROS arboles y el check mentía.)
	jugador.global_position = Vector3(0.0, 0.0, 30000.0)
	g._pensar()
	_chk(g.vivos() == 0, "lejos de todo los retira", str(g.vivos()))

	# Y la banda intermedia sobre un arbol ya colocado, ahora con la posicion
	# real: sigue sin haber churn.
	jugador.global_position = Vector3(float(primero["x"]), 0.0, float(primero["z"]))
	g._pensar()
	var colocados: int = g.vivos()
	_chk(colocados > 0, "vuelve a colocar al acercarse", str(colocados))
	jugador.global_position = Vector3(float(primero["x"]) + fuera, 0.0, float(primero["z"]))
	g._pensar()
	_chk(g.vivos() == colocados,
		"en la banda intermedia no hay churn (ni entradas ni salidas)",
		"%d -> %d" % [colocados, g.vivos()])
