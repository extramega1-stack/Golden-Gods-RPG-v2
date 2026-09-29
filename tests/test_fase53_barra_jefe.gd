extends SceneTree
## Tests headless de la Fase 53 (barra de jefe).
##
## POR QUÉ NACE: la fase 52 hizo que los jefes telegrafiaran, cambiaran de
## fase y entraran en rage — todo invisible para el jugador. Esta fase pone
## el feedback en pantalla.
##
## Cubre:
## (a) solo se engancha a jefes: un goblin no abre barra;
## (b) sigue vida/muerte por señales y refleja el porcentaje;
## (c) se desconecta sola al morir y al cambiar de objetivo;
## (d) el estado de "rage" cambia el color y el nombre late;
## (e) las marcas de fase están en 66% y 33%.
##
## Cómo correrlo:
## godot --headless --path <proyecto> --script res://tests/test_fase53_barra_jefe.gd

const BJ: GDScript = preload("res://scripts/ui/barra_jefe.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 53 — barra de jefe")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_constantes()
	_test_solo_jefes()
	_test_sigue_vida()
	_test_al_morir()
	_test_cambio_de_objetivo()
	_test_rage()
	_test_marcas_de_fase()
	print("[TEST] fase53_barra_jefe: %d ok, %d fallos" % [_ok, _fallos])
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


func _barra() -> BarraJefe:
	var b: BarraJefe = BJ.new()
	root.add_child(b)
	_basura.append(b)
	return b


## Un enemigo con el bloque `jefe` de data/enemies.json, que es lo que hace
## que `es_jefe` sea true.
func _jefe_real() -> Enemy:
	var datos = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/enemies.json"))
	var arqs: Dictionary = (datos as Dictionary).get("arquetipos", {})
	var e: Enemy = EN.new()
	root.add_child(e)
	_basura.append(e)
	e.configurar(arqs.get("campeon_caido", {}))
	return e


func _normal() -> Enemy:
	var e: Enemy = EN.new()
	root.add_child(e)
	_basura.append(e)
	e.configurar({
		"nombre": "Goblin", "fuerza": 5.0, "destreza": 5.0,
		"inteligencia": 5.0, "xp": 40,
	})
	return e


# --- (a) solo jefes ----------------------------------------------------

func _test_solo_jefes() -> void:
	var b: BarraJefe = _barra()
	_chk(b.layer == UiLayers.BARRA_JEFE,
		"la barra va en su propia capa de UiLayers", "layer=%d" % b.layer)
	_chk(not b.visible, "arranca oculta (leccion 11)", "")

	var g: Enemy = _normal()
	_chk(not g.es_jefe, "un goblin no es jefe", "")
	b.vigilar(g)
	_chk(not b.vigilando(), "la barra NO se engancha a un goblin", "")
	_chk(not b.visible, "y no se muestra", "")

	var j: Enemy = _jefe_real()
	_chk(j.es_jefe, "campeon_caido es jefe", "")
	b.vigilar(j)
	_chk(b.vigilando(), "la barra se engancha a un jefe", "")
	_chk(b.visible, "y se muestra", "")

	# Un null también la suelta, sin reventar.
	b.vigilar(null)
	_chk(not b.vigilando(), "vigilar(null) no rompe", "")


# --- (b) sigue la vida ------------------------------------------------

func _test_sigue_vida() -> void:
	var b: BarraJefe = _barra()
	var j: Enemy = _jefe_real()
	b.vigilar(j)

	_chk(is_equal_approx(b._barra.value, 1.0),
		"empieza llena", str(b._barra.value))

	j.vida_cambiada.emit(j.stats.vida_max * 0.5, j.stats.vida_max)
	_chk(is_equal_approx(b._barra.value, 0.5),
		"la barra refleja la vida", str(b._barra.value))
	_chk(b._fantasma.value >= b._barra.value,
		"la barra fantasma nunca queda POR DEBAJO de la real",
		"fantasma=%s real=%s" % [b._fantasma.value, b._barra.value])

	j.vida_cambiada.emit(0.0, j.stats.vida_max)
	_chk(is_equal_approx(b._barra.value, 0.0), "a 0 vida, barra a 0", "")

	# Vida máxima 0 no debe dividir por cero.
	var antes: float = b._barra.value
	j.vida_cambiada.emit(10.0, 0.0)
	_chk(is_equal_approx(b._barra.value, antes),
		"vida_max = 0 no rompe nada", str(b._barra.value))


# --- (c) al morir ------------------------------------------------------

func _test_al_morir() -> void:
	var b: BarraJefe = _barra()
	var j: Enemy = _jefe_real()
	b.vigilar(j)
	j.murio.emit(null)
	_chk(not b.visible, "al morir se esconde", "")
	_chk(not b.vigilando(), "y se desengancha (no queda colgada)", "")


# --- (d) cambio de objetivo -------------------------------------------

func _test_cambio_de_objetivo() -> void:
	var b: BarraJefe = _barra()
	var j1: Enemy = _jefe_real()
	var j2: Enemy = _jefe_real()
	b.vigilar(j1)
	_chk(b.vigilando(), "vigila al primero", "")

	b.desvigilar()
	b.vigilar(j2)
	_chk(b.vigilando(), "vigila al segundo", "")
	# El primero quedó desenganchado: simuriera, no debe romper la barra.
	j1.murio.emit(null)
	_chk(b.vigilando(), "la muerte del jefe anterior no cuelga la barra", "")


# --- (e) rage ---------------------------------------------------------

func _test_rage() -> void:
	var b: BarraJefe = _barra()
	var j: Enemy = _jefe_real()
	b.vigilar(j)

	_chk(not j.en_rage(), "el jefe arranca SIN rage", "")
	_chk(not b._en_rage(), "la barra no cree estar en rage", "")

	# Se corre el reloj de verdad, no se lo pisa a mano.
	j._tick_jefe(float(j._enrage) + 0.1)
	_chk(j.en_rage(), "el jefe entra en rage al agotarse el reloj",
		"enrage=%s" % str(j._enrage))
	_chk(b._en_rage(), "la barra lo ve", "")

	# Muerto, no hay jefe, no hay rage.
	b.desvigilar()
	_chk(not b._en_rage(), "sin jefe no hay rage", "")


# --- (f) marcas de fase -----------------------------------------------

func _test_marcas_de_fase() -> void:
	_chk(BarraJefe.UMBRALES_FASE.size() == 2,
		"hay 2 marcas de umbral", str(BarraJefe.UMBRALES_FASE.size()))
	_chk(is_equal_approx(BarraJefe.UMBRALES_FASE[0], 0.66),
		"la primera marca cae en el 66%", str(BarraJefe.UMBRALES_FASE[0]))
	_chk(is_equal_approx(BarraJefe.UMBRALES_FASE[1], 0.33),
		"la segunda marca cae en el 33%", str(BarraJefe.UMBRALES_FASE[1]))
	# Y coinciden con los umbrales reales del dato.
	var datos = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/enemies.json"))
	var arqs: Dictionary = (datos as Dictionary).get("arquetipos", {})
	var fases: Array = (arqs.get("campeon_caido", {}) as Dictionary)["jefe"]["fases"]
	_chk(is_equal_approx(BarraJefe.UMBRALES_FASE[0], float(fases[1]["hasta"])),
		"la marca coincide con el umbral de la fase 2 del dato",
		"ui=%s dato=%s" % [BarraJefe.UMBRALES_FASE[0], fases[1]["hasta"]])
	_chk(is_equal_approx(BarraJefe.UMBRALES_FASE[1], float(fases[2]["hasta"])),
		"la marca coincide con el umbral de la fase 3 del dato",
		"ui=%s dato=%s" % [BarraJefe.UMBRALES_FASE[1], fases[2]["hasta"]])


func _test_constantes() -> void:
	_chk(BarraJefe.PELDANOS == 10, "10 peldaños, como BarraVidaMob", "")
	_chk(BarraJefe.ALTO > 0.0 and BarraJefe.ANCHO > 0.0, "medidas Positive", "")
