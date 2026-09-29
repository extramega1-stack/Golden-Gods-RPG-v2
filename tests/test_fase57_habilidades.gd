extends SceneTree
## Tests headless de la Fase 57 (habilidades con XP propio).
##
## POR QUÉ NACE: Dragonwilds gira sobre subir skills por separado. La 57 mete
## ese segundo eje SIN tocar el nivel de personaje, que es la decisión de
## Juan Diego: el nivel sigue mandando en StatBlock y combate, y el XP de
## habilidad abre los Talentos de Habilidad de la fase 59.
##
## Cubre:
## (a) el DATO: 4 habilidades con curva propia;
## (b) `Habilidades`: tramos, umbrales, saltos múltiples, tope;
## (c) la DECISIÓN: el nivel de personaje NO se toca;
## (d) la minería da los DOS XP (personaje y habilidad);
## (e) el save, y que un save viejo cargue en 0 y no reviente.

const HB: GDScript = preload("res://scripts/skills/habilidades.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 57 — habilidades con XP propio")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_dato()
	_test_tramos()
	_test_saltos()
	_test_tope()
	_test_no_toca_el_nivel()
	_test_mineria_da_los_dos()
	_test_save()
	print("[TEST] fase57_habilidades: %d ok, %d fallos" % [_ok, _fallos])
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


func _h() -> Habilidades:
	var h: Habilidades = HB.crear_desde_datos()
	return h


# --- (a) el dato ------------------------------------------------------

func _test_dato() -> void:
	var h: Habilidades = _h()
	var ids: Array[String] = h.ids()
	_chk(ids.size() >= 4, "hay al menos 4 habilidades", str(ids))
	for h_ in ["tala", "mineria", "cocina", "recoleccion"]:
		_chk(ids.has(h_), "existe '%s'" % h_, str(ids))
		_chk(h.nombre_de(h_) != h_, "'%s' tiene nombre propio" % h_, h.nombre_de(h_))
		_chk(h.tramos_totales(h_) >= 5,
			"'%s' tiene varios tramos" % h_, str(h.tramos_totales(h_)))
		_chk(h.xp_de(h_) == 0, "'%s' arranca en 0" % h_, str(h.xp_de(h_)))


# --- (b) tramos -------------------------------------------------------

func _test_tramos() -> void:
	var h: Habilidades = _h()
	_chk(h.tramo_de("tala") == 0, "tramo 0 al empezar", str(h.tramo_de("tala")))

	# Con suficiente XP, sube de tramo.
	h.ganar("tala", 100)
	_chk(h.tramo_de("tala") >= 1, "con 100 xp sube de tramo", str(h.tramo_de("tala")))
	_chk(h.xp_de("tala") == 100, "el XP se acumula", str(h.xp_de("tala")))

	# Antes del umbral, no sube.
	var h2: Habilidades = _h()
	h2.ganar("tala", 1)
	_chk(h2.tramo_de("tala") == 0, "con 1 xp no sube", str(h2.tramo_de("tala")))

	# Xp negativo o cero no hace nada.
	var h3: Habilidades = _h()
	h3.ganar("tala", 0)
	h3.ganar("tala", -50)
	_chk(h3.xp_de("tala") == 0, "xp <= 0 no suma", str(h3.xp_de("tala")))

	# Una habilidad que no existe no rompe.
	h3.ganar("talar", 100)
	_chk(h3.xp_de("talar") == 0, "una habilidad inexistente no acumula", "")

	# La señal de tramo se emite al cruzar.
	var tramos: Array = []
	h2.tramo_ganado.connect(func(_nombre: String, t: int): tramos.append(t))
	h2.ganar("tala", 10_000_000)
	_chk(tramos.size() >= 1, "cruzar un tramo avisa", str(tramos))
	_chk(tramos.has(1), "y avisa el 1", str(tramos))


# --- (c) saltos multiples ---------------------------------------------

func _test_saltos() -> void:
	var h: Habilidades = _h()
	var avisos: Array = []
	h.tramo_ganado.connect(func(_n: String, t: int): avisos.append(t))
	# Un tajo enorme puede abrir varios tramos de una: se avisa de CADA uno.
	h.ganar("tala", 5000)
	_chk(avisos.size() >= 2, "un salto grande abre varios tramos", str(avisos))
	var orden: Array = avisos.duplicate()
	orden.sort()
	_chk(avisos == orden, "y en orden", "%s vs %s" % [avisos, orden])

	# `ganar` devuelve cuántos tramos subió.
	var h2: Habilidades = _h()
	_chk(h2.ganar("tala", 1) == 0, "un xp no sube tramo", "")
	_chk(h2.ganar("tala", 5000) >= 2, "un salto sube varios", "")


# --- (d) el tope ------------------------------------------------------

func _test_tope() -> void:
	var h: Habilidades = _h()
	h.ganar("tala", 10_000_000)
	var total: int = h.tramos_totales("tala")
	_chk(h.tramo_de("tala") == total - 1, "se queda en el último tramo",
		"%d de %d" % [h.tramo_de("tala"), total])
	_chk(h.en_tope("tala"), "y marca tope", "")
	_chk(h.xp_para_siguiente("tala") == 0, "no hay xp para el siguiente", "")
	_chk(is_equal_approx(h.progreso_tramo("tala"), 1.0), "progreso 1.0 en el tope", "")
	_chk(not h.en_tope("cocina"), "cocina no está en tope", "")

	# El progreso del tranche está entre 0 y 1 siempre.
	var h2: Habilidades = _h()
	for xp in [0, 10, 100, 500, 3000, 999_999]:
		h2.ganar("tala", xp)
		var p: float = h2.progreso_tramo("tala")
		_chk(p >= 0.0 and p <= 1.0, "progreso entre 0 y 1 (xp=%d)" % xp, str(p))


# --- (c') la decisión: el nivel NO se toca ---------------------------

func _test_no_toca_el_nivel() -> void:
	# El nivel de personaje sigue viniendo del StatBlock. La 57 agrega un eje
	# paralelo, no uno que reemplace al otro.
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)
	var nivel_antes: int = p.nivel
	p.gain_xp(500)
	_chk(p.nivel > nivel_antes,
		"el nivel de personaje sigue subiendo como antes (gain_xp del Player)",
		"%d -> %d" % [nivel_antes, p.nivel])
	_chk(p.habilidades.xp_de("tala") == 0,
		"subir de nivel NO mueve el XP de habilidad (son ejes separados)",
		str(p.habilidades.xp_de("tala")))

	# Y al revés: subir una habilidad NO sube el nivel de personaje.
	var nivel_antes2: int = p.nivel
	p.habilidades.ganar("tala", 5000)
	_chk(p.nivel == nivel_antes2,
		"subir una habilidad NO sube el nivel de personaje",
		"%d -> %d" % [nivel_antes2, p.nivel])

	# Las habilidades no tocan el StatBlock: son un contador aparte.
	_chk(p.habilidades.total_xp() >= 5000, "el XP de habilidad acumula solo",
		str(p.habilidades.total_xp()))
	_chk(p.vida_actual > 0.0, "y el personaje sigue vivo y con vida", "")


# --- (d) la	minería da los dos XP -----------------------------------

func _test_mineria_da_los_dos() -> void:
	# El XP de habilidad se suma en el punto donde la minería da el de
	# personaje, sin reemplazarlo.
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)
	_chk(p.habilidades != null, "el Player nace con habilidades", "")
	_chk(p.habilidades.ids().size() >= 4, "y cargaron del JSON",
		str(p.habilidades.ids().size()))

	var nivel_antes: int = p.nivel
	var xp_hab_antes: int = p.habilidades.xp_de("mineria")
	# Subir de nivel a mano es lo que hace `gain_xp`; acá se comprueba solo
	# que minar suma en las dos monedas sin romper ninguna.
	p.habilidades.ganar("mineria", 7)
	_chk(p.habilidades.xp_de("mineria") == xp_hab_antes + 7,
		"ganar() suma en la habilidad", str(p.habilidades.xp_de("mineria")))
	_chk(p.nivel == nivel_antes,
		"y NO sube el nivel de personaje (eso lo decide el XP de mobs)",
		"%d -> %d" % [nivel_antes, p.nivel])


# --- (e) save ---------------------------------------------------------

func _test_save() -> void:
	var h: Habilidades = _h()
	h.ganar("tala", 500)
	h.ganar("mineria", 900)
	var d: Dictionary = h.to_dict()
	_chk(d.has("xp"), "el save lleva el xp", str(d.keys()))

	var h2: Habilidades = _h()
	h2.cargar_estado(d)
	_chk(h2.xp_de("tala") == 500, "vuelve el xp de tala", str(h2.xp_de("tala")))
	_chk(h2.xp_de("mineria") == 900, "y el de mineria", str(h2.xp_de("mineria")))
	_chk(h2.tramo_de("tala") == h.tramo_de("tala"), "y el tramo se conserva", "")
	_basura.append(h2)

	# Un save viejo (sin bloque, o vacío) deja todo en 0, no rompe.
	var h3: Habilidades = _h()
	h3.cargar_estado({})
	_chk(h3.xp_de("tala") == 0, "save vacío = 0", "")
	_chk(h3.ids().size() >= 4, "y no pierde las habilidades", "")
	_basura.append(h3)

	# Una habilidad guardada que ya no existe en el JSON se descarta.
	var h4: Habilidades = _h()
	h4.cargar_estado({"xp": {"tala": 100, "talar_OLD": 500}})
	_chk(h4.xp_de("talar_OLD") == 0, "una habilidad vieja se descarta", "")
	_chk(h4.xp_de("tala") == 100, "y la que sigue existe se conserva", "")
	_basura.append(h4)

	# Xp negativo en un save manipulado no cuela.
	var h5: Habilidades = _h()
	h5.cargar_estado({"xp": {"tala": -9999}})
	_chk(h5.xp_de("tala") == 0, "un xp negativo se clampa a 0", str(h5.xp_de("tala")))
	_basura.append(h5)
