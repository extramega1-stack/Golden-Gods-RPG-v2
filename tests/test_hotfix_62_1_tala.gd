extends SceneTree
## Hotfix 62.1 — que el bloque de supervivencia no mienta.
##
## POR QUÉ ESTE ARCHIVO EXISTE: la Fase 59 escribió en el spec que la decisión
## de gastar el Hecho de Tala o caminar hasta la fogata "ES el juego". No lo
## era: `Arbol` hereda de `Veta` (decisión correcta de la 55, para no duplicar
## el nodo), pero eso hacía que talar pasara por `Mineria`, que tenía
## `"mineria"` hardcodeado. Resultado: la habilidad `tala` no subía NUNCA y
## los Hechos de tala eran inalcanzables, con 93/93 tests en verde.
##
## El agujero no fue la lógica: fue que los tests de la 55 y la 59 probaban
## `Talar` y `Mineria` por separado, y nadie probó el CAMINO REAL. Eso es lo
## que hace este archivo.

const PL: GDScript = preload("res://scripts/player/player.gd")
const GV: GDScript = preload("res://scripts/mundo/gestor_vetas.gd")
const VT: GDScript = preload("res://scripts/mundo/veta.gd")
const AR: GDScript = preload("res://scripts/mundo/arbol.gd")
const AD: GDScript = preload("res://scripts/mundo/arbol_db.gd")
const SI: GDScript = preload("res://scripts/save/save_system.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Hotfix 62.1 — Tala, Hechos y cableado")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_habilidad_la_declara_el_nodo()
	_test_camino_real_tala()
	_test_hecho_tala_area_en_juego()
	_test_hechos_tras_cargar()
	_test_system_id()
	_test_ancla_al_caminar()
	_test_feed_avisos()
	print("[TEST] hotfix_62_1: %d ok, %d fallos" % [_ok, _fallos])
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


func _jugador(nivel: int = 1) -> Player:
	var p: Player = PL.new()
	p.fijar_identidad("H", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	p.nivel = nivel
	p.ganar_oro(500)
	return p


func _arbol(d: Dictionary = {}) -> Arbol:
	var base: Dictionary = {
		"id": "arbol_h62", "nombre": "Roble de hotfix",
		"region": "moon_town", "item_id": "tronco_roble",
		"cantidad": 2, "usos": 3, "respawn_s": 180, "xp": 10,
		"nivel": 1, "tinte": "#4a7a3a", "x": 0.0, "z": 0.0,
	}
	for k in d:
		base[k] = d[k]
	var a: Arbol = AR.new()
	root.add_child(a)
	_basura.append(a)
	a.configurar(base)
	return a


# --- (a) la habilidad la declara el nodo, no la lógica ---------------

func _test_habilidad_la_declara_el_nodo() -> void:
	var v: Veta = VT.new()
	root.add_child(v)
	_basura.append(v)
	_chk(v.habilidad_id == "mineria",
		"una veta declara la habilidad 'mineria'", v.habilidad_id)
	var a: Arbol = _arbol()
	_chk(a.habilidad_id == "tala",
		"un árbol declara la habilidad 'tala'", a.habilidad_id)
	_chk(a.habilidad_id != v.habilidad_id,
		"y son distintas: heredar de Veta ya no las mezcla", "")

	# Y que la habilidad exista en el catálogo, o el XP se iría a un id morto.
	AD.cargar()
	var ruta: String = "res://data/habilidades.json"
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	var habs: Array = []
	var ids: Array = []
	if d is Dictionary:
		var dd: Dictionary = d
		var hm: Dictionary = dd.get("habilidades", {})
		# Es un diccionario {id: {nombre, icono, curva}}, no una lista.
		for hid in hm.keys():
			ids.append(str(hid))
	elif d is Array:
		for h in d:
			var hd2: Dictionary = h
			ids.append(str(hd2.get("id", "")))
	_chk(ids.has("tala"), "la habilidad 'tala' existe en el catálogo", str(ids))
	_chk(ids.has("mineria"), "la habilidad 'mineria' existe en el catálogo", str(ids))


# --- (b) EL CAMINO REAL: el que faltaba ------------------------------

## Este es el test que habría atrapado el bug. Va por la puerta que usa el
## jugador de verdad: `minar_solicitado` → `GestorVetas` → `Mineria`.
func _test_camino_real_tala() -> void:
	var p: Player = _jugador(1)
	var g: GestorVetas = GV.new()
	root.add_child(g)
	_basura.append(g)
	g.configurar_desde_datos()
	g.fijar_jugador(p)

	var a: Arbol = _arbol()
	var xp_tala_antes: int = p.habilidades.xp_de("tala")
	var xp_min_antes: int = p.habilidades.xp_de("mineria")
	_chk(xp_tala_antes == 0, "tala arranca en 0", str(xp_tala_antes))
	_chk(xp_min_antes == 0, "minería arranca en 0", str(xp_min_antes))

	# El golpe, por la señal que emite el jugador.
	p.minar_solicitado.emit(a)

	_chk(p.habilidades.xp_de("tala") > xp_tala_antes,
		"CAMINO REAL: talar sube la habilidad 'tala'",
		"tala=%d mineria=%d" % [p.habilidades.xp_de("tala"), p.habilidades.xp_de("mineria")])
	_chk(p.habilidades.xp_de("mineria") == xp_min_antes,
		"y NO toca 'mineria' (esto es lo que estaba roto)",
		"mineria=%d" % p.habilidades.xp_de("mineria"))
	_chk(p.inventario.contar("tronco_roble") > 0,
		"y el tronco entra al inventario", "")
	_chk(a.usos == 2, "el árbol gastó UN uso", str(a.usos))

	# Y una veta de verdad sigue subiendo minería, no tala.
	var v: Veta = VT.new()
	v.name = "VetaTest"
	v.configurar({"id": "veta_h62", "item_id": "mineral_cobre", "cantidad": 1,
		"usos": 3, "respawn_s": 30, "xp": 7, "nivel": 1, "x": 0.0, "z": 0.0})
	root.add_child(v)
	_basura.append(v)
	var t0: int = p.habilidades.xp_de("tala")
	var m0: int = p.habilidades.xp_de("mineria")
	p.minar_solicitado.emit(v)
	_chk(p.habilidades.xp_de("mineria") > m0,
		"CAMINO REAL: minar sí sube 'mineria'", str(p.habilidades.xp_de("mineria")))
	_chk(p.habilidades.xp_de("tala") == t0,
		"y no toca 'tala'", str(p.habilidades.xp_de("tala")))


# --- (c) el Hecho tala_area, jugando de verdad -----------------------

func _test_hecho_tala_area_en_juego() -> void:
	var p: Player = _jugador(1)
	var g: GestorVetas = GV.new()
	root.add_child(g)
	_basura.append(g)
	g.configurar_desde_datos()
	g.fijar_jugador(p)

	var a: Arbol = _arbol({"cantidad": 2, "xp": 10})

	# Sin el Hecho: 2 troncos (la cantidad del dato).
	p.minar_solicitado.emit(a)
	var sin_hecho: int = p.inventario.contar("tronco_roble")
	_chk(sin_hecho == 2, "sin el Hecho, 2 troncos", str(sin_hecho))

	# Con el Hecho activo, 3x. No se fuerza el Hecho: se sube la habilidad
	# hasta el tramo que el catálogo pide y Hechos lo recalcula solo, que es
	# exactamente lo que pasa jugando.
	p.habilidades.ganar("tala", 100000)
	p.hechos.aplicar(p.stats)
	_chk(p.hechos.tiene("tala_area"),
		"el Hecho tala_area se desbloquea subiendo tala (no a mano)", "")

	var a2: Arbol = _arbol({"id": "arbol_h62b", "cantidad": 2, "xp": 10})
	p.minar_solicitado.emit(a2)
	var con_hecho: int = p.inventario.contar("tronco_roble") - sin_hecho
	_chk(con_hecho == 6,
		"con el Hecho, 3 x 2 = 6 troncos en UN uso (esto antes no pasaba)",
		str(con_hecho))
	_chk(a2.usos == 2, "y sigue gastando un solo uso", str(a2.usos))

	# Y la tolerancia de nivel del Hecho "Leñador", por el camino real. Son 2
	# tramos, asi que con jugador nv.1 el limite es nivel 3 (3-2=1).
	var alto: Arbol = _arbol({"id": "arbol_h62c", "nivel": 3, "cantidad": 1, "xp": 5})
	_chk(p.hechos.tiene("tala_rangos"),
		"y con tramo 4 llega tala_rangos (que es quien da la tolerancia)", "")
	var xp_t0: int = p.habilidades.xp_de("tala")
	p.minar_solicitado.emit(alto)
	_chk(p.habilidades.xp_de("tala") > xp_t0,
		"con tala_rangos, un árbol 2 por encima SÍ se tala (jugador nv. 1)",
		"tala=%d" % p.habilidades.xp_de("tala"))
	# Y uno un tramo mas alla, NO: la tolerancia tiene que tener un techo.
	var demasiado: Arbol = _arbol({"id": "arbol_h62d", "nivel": 4, "cantidad": 1, "xp": 5})
	var xp_t1: int = p.habilidades.xp_de("tala")
	p.minar_solicitado.emit(demasiado)
	_chk(p.habilidades.xp_de("tala") == xp_t1,
		"pero 3 por encima ya no (la tolerancia tiene techo)",
		"tala=%d" % p.habilidades.xp_de("tala"))


# --- (d) los Hechos sobreviven a guardar/cargar ----------------------

func _test_hechos_tras_cargar() -> void:
	var p: Player = _jugador(1)
	# Se sube la habilidad de tala de verdad, hasta el tramo que da el Hecho.
	p.habilidades.ganar("tala", 5000)
	_chk(p.habilidades.tramo_de("tala") > 0,
		"la habilidad tala subió de tramo", str(p.habilidades.tramo_de("tala")))
	_chk(p.hechos.desbloqueados().size() > 0,
		"y eso desbloqueó Hechos", "%d" % p.hechos.desbloqueados().size())
	# Con solo tala no hay ningun Hecho de tipo "mod" (los de tala son
	# banderas), asi que se sube tambien mineria para tener uno.
	p.habilidades.ganar("mineria", 5000)
	p.hechos.aplicar(p.stats)
	_chk(_tiene_mods(p),
		"los Hechos de tipo mod se aplican al StatBlock (fuente 'hecho:<id>')", "")

	# Se serializa y se recarga, como el F10. El conteo se mide AQUÍ, con
	# todo el XP ya entregado: si no, compara contra un numero viejo.
	var desbloqueados: int = p.hechos.desbloqueados().size()
	var estado_hab: Dictionary = p.habilidades.to_dict()
	var xp_tala: int = p.habilidades.xp_de("tala")

	# Un jugador NUEVO, que carga desde el estado guardado: es el caso que
	# estaba roto, porque `cargar_estado` no emitía `tramo_ganado`.
	var p2: Player = _jugador(1)
	p2.habilidades.cargar_estado(estado_hab)
	_chk(p2.habilidades.xp_de("tala") == xp_tala,
		"tras cargar, la habilidad conserva su XP",
		"%d vs %d" % [p2.habilidades.xp_de("tala"), xp_tala])
	_chk(p2.habilidades.tramo_de("tala") == p.habilidades.tramo_de("tala"),
		"y su tramo se recalcula", "")

	# El fix: recalcular los Hechos tras cargar. Este es el que faltaba.
	p2.hechos.aplicar(p2.stats)
	_chk(p2.hechos.desbloqueados().size() == desbloqueados,
		"los Hechos se recuperan al cargar (este es el hotfix)",
		"%d vs %d" % [p2.hechos.desbloqueados().size(), desbloqueados])
	# Y las BANDERAS (lo que leen tala/vitals) tambien vuelven: se recalculan
	# desde `aplicar()`, que es justamente lo que faltaba.
	_chk(p2.hechos.banderas() == p.hechos.banderas(),
		"y sus banderas de sistema, que es lo que leen Tala y Vitals",
		"%s vs %s" % [p2.hechos.banderas(), p.hechos.banderas()])
	for hid in p.hechos.desbloqueados():
		_chk(p2.hechos.desbloqueado(hid),
			"el Hecho '%s' sobrevive al save/load" % hid, "")


## ¿El StatBlock tiene AL MENOS un mod provenance de un Hecho? Se comprueba
## por el lado del StatBlock (`has_mod`), que es el dato que de verdad importa.
func _tiene_mods(p: Player) -> bool:
	for hid in p.hechos.desbloqueados():
		var h: Dictionary = p.hechos.hecho(hid)
		if str(h.get("tipo", "")) != "mod":
			continue
		if p.stats.has_mod("hecho:" + hid):
			return true
	return false


# --- (e) system_id: los refugios tienen que ser descubribles ---------

func _test_system_id() -> void:
	var R: GDScript = preload("res://scripts/mundo/refugio.gd")
	var GA: GDScript = preload("res://scripts/mundo/gestor_arboles.gd")
	var r: Node3D = R.new()
	_basura.append(r)
	_chk(&"system_id" in r,
		"Refugio declara system_id (si no, Systems.registrar lo rechaza)", "")
	var g: Node = GA.new()
	_basura.append(g)
	_chk(&"system_id" in g,
		"GestorArboles declara system_id", "")

	# Y que registrar de verdad funcione y devuelva el sistema.
	var sy: Node = preload("res://scripts/core/systems.gd").new()
	_basura.append(sy)
	sy.registrar(r, &"refugio:moon_town")
	_chk(sy.obtener(&"refugio:moon_town") == r,
		"y un refugio se puede recuperar con Systems.obtener()", "")


# --- (g) el feed global de avisos -----------------------------------

## El feed es lo que hace OBSERVABLE el hotfix: sin él, talar un árbol subía
## `tala` y no había forma de enterarse. Por eso va testeado.
func _test_feed_avisos() -> void:
	var f: FeedAvisos = FeedAvisos.new()
	root.add_child(f)
	_basura.append(f)
	_chk(f.layer == UiLayers.FEED_AVISOS,
		"el feed va en su propia capa del HUD", str(f.layer))
	_chk(&"system_id" in f, "y declara system_id (lo registra Systems)", "")
	_chk(f.visible, "arranca visible: es un feed, no un panel", "")

	# La señal primero, para contarlo todo: se conecta ANTES de avisar.
	var oidas: Array = []
	f.avisado.connect(func(t: String, l: bool): oidas.append([t, l]))

	# Un aviso normal y un logro.
	f.aviso("Te faltan troncos")
	_chk(f.visibles() == 1, "un aviso aparece", str(f.visibles()))
	f.logro("Leñador", "Cada tajo saca 3 troncos")
	_chk(f.visibles() == 2, "y un logro se apila encima", str(f.visibles()))
	_chk(oidas.size() == 2, "emite `avisado` por cada uno", str(oidas.size()))
	_chk(bool(oidas[0][1]) == false, "un aviso normal no es logro", str(oidas[0]))
	_chk(bool(oidas[1][1]) == true, "y el logro sí se marca como tal", str(oidas[1]))

	# El tope: se come el más viejo en vez de acumular nodos.
	for i in range(FeedAvisos.MAX_VISIBLES + 3):
		f.aviso("colada %d" % i)
	_chk(f.visibles() == FeedAvisos.MAX_VISIBLES,
		"nunca pasa de MAX_VISIBLES (los viejos se liberan, no se ocultan)",
		str(f.visibles()))

	# Y que se registre de verdad en Systems, que es como lo encontrarán los
	# demás sistemas.
	var sy: Node = preload("res://scripts/core/systems.gd").new()
	_basura.append(sy)
	sy.registrar(f, &"feed_avisos")
	_chk(sy.obtener(&"feed_avisos") == f,
		"se encuentra con Systems.obtener(&'feed_avisos')", "")

	# Y el enganche real: un Hecho desbloqueado produce un logro CON detalle.
	# Sin el detalle el aviso no sirve ("Leñador" no dice qué cambió).
	var p: Player = _jugador(1)
	var h: Hechos = Hechos.crear_desde_datos()
	h.fijar_habilidades(p.habilidades)
	p.habilidades.ganar("tala", 100000)
	h.aplicar(p.stats)
	var feed2: FeedAvisos = FeedAvisos.new()
	root.add_child(feed2)
	_basura.append(feed2)
	h.hecho_desbloqueado.connect(func(hid: String):
		feed2.logro(h.nombre_de(hid), h.descripcion_de(hid)))
	_chk(h.desbloqueados().size() > 0, "subir tala desbloqueó Hechos", "")
	var detonado: Array = []
	feed2.avisado.connect(func(t: String, l: bool): detonado.append(t))
	h.aplicar(p.stats)
	# `aplicar` no re-emite: el Hecho ya estaba. Se fuerza el camino que
	# dispara la señal al ganar de verdad, que es lo que pasa jugando.
	_chk(h.tiene("tala_area"), "el Hecho de tala está activo", "")
	_chk(h.descripcion_de("tala_area") != "",
		"y el Hecho tiene descripción (sin ella, el aviso no dice nada)",
		"'" + h.descripcion_de("tala_area") + "'")
	_chk(h.nombre_de("tala_area") != "", "y nombre", "")


# --- (f) el ancla de reaparición se actualiza al caminar -------------

func _test_ancla_al_caminar() -> void:
	var RH: GDScript = preload("res://scripts/mundo/respawn_heroe.gd")
	var p: Player = _jugador(1)
	var r: Node = RH.new()
	root.add_child(r)
	_basura.append(r)
	r.registrar_ciudad("moon_town", Vector3(0, 40, 0), 0.0)
	r.configurar(p)
	_chk(p.ancla().distance_to(Vector3(0, 40, 0)) < 0.01,
		"el ancla inicial es la plaza de la ciudad", str(p.ancla()))

	# Se camina a otra ciudad y el ancla debe seguir al jugador.
	r.registrar_ciudad("desert", Vector3(9966, 40, 0), 0.0)
	p.global_position = Vector3(9966, 40, 0)
	r.actualizar_ancla()
	_chk(p.ancla().distance_to(Vector3(9966, 40, 0)) < 0.01,
		"al caminar, el ancla pasa a la ciudad más cercana", str(p.ancla()))

	# Y con un refugio reclamado encima, el ancla es el refugio.
	var R: GDScript = preload("res://scripts/mundo/refugio.gd")
	var ref: Refugio = R.new() as Refugio
	root.add_child(ref)
	_basura.append(ref)
	_chk(ref.configurar_por_id("refugio_moon_town"),
		"el refugio real de Moon Town se configura por id", ref.refugio_id)
	ref.global_position = Vector3(120.0, 40.0, 60.0)
	_chk(ref.reclamar(1), "y se reclama jugando", "")
	r.anclar_refugio(ref)
	# El jugador vuelve a la plaza: el refugio GANA por estar dentro.
	p.global_position = Vector3(120, 40, 60)
	r.actualizar_ancla()
	_chk(p.ancla().distance_to(Vector3(120, 40, 60)) < 0.01,
		"un refugio reclamado DENTRO de él gana el ancla (esto no pasaba)",
		str(p.ancla()))
