extends SceneTree
## Tests headless de la Fase 56 (cocina).
##
## POR QUÉ NACE: sin cocinar, la comida cruda es solo penalización. La fase
## 58 pone hambre; si no hubiera una forma de cocinar, el juego sería un
## castigo sin contrajuego. Esta fase cierra el círculo
## recolectar→cocinar→comer.
##
## Cubre:
## (a) el DATO: las recetas apuntan a items que existen;
## (b) `Cocina` es pura: motivos, gasto de ingrediente y leña;
## (c) la leña sale del tronco (la tala tiene consumidor);
## (d) `Fogata`: carga, gasta, se apaga sola, se relanza;
## (e) cocinar quita el riesgo de enfermedad (el motivo de la 58).
##
## Cómo correrlo:
## godot --headless --path <proyecto> --script res://tests/test_fase56_cocina.gd

const CO: GDScript = preload("res://scripts/mundo/cocina.gd")
const CD: GDScript = preload("res://scripts/mundo/recetas_cocina_db.gd")
const FG: GDScript = preload("res://scripts/mundo/fogata.gd")
const IT: GDScript = preload("res://scripts/inventory/item_db.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 56 — cocina")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	IT.cargar()
	CD.cargar()
	_test_dato()
	_test_motivos()
	_test_cocinar()
	_test_lena()
	_test_fogata()
	_test_cocinar_sana()
	print("[TEST] fase56_cocina: %d ok, %d fallos" % [_ok, _fallos])
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


func _fogata() -> Fogata:
	var f: Fogata = FG.new()
	root.add_child(f)
	_basura.append(f)
	return f


# --- (a) el dato ------------------------------------------------------

func _test_dato() -> void:
	_chk(CD.ids().size() >= 5, "hay al menos 5 recetas", str(CD.ids().size()))
	for ing in CD.ids():
		var r: Dictionary = CD.receta(ing)
		_chk(IT.existe(ing), "el ingrediente '%s' existe" % ing, "")
		var res: String = str(r.get("resultado", ""))
		_chk(IT.existe(res), "el resultado '%s' existe" % res, "")
		_chk(str(IT.obtener(res).get("tipo", "")) == "consumible",
			"'%s' es consumible" % res, "")
		_chk(float(r.get("lena", 0.0)) > 0.0, "'%s' gasta lena" % ing, str(r))
		_chk(float(r.get("segundos", 0.0)) > 0.0, "'%s' tarda algo" % ing, str(r))
	_chk(not CD.tiene("carne_cruda_inexistente"),
		"una receta inexistente no existe", "")
	_chk(CD.receta("nada").is_empty(), "obtener() de algo raro es vacío", "")

	# La cadena completa tiene que existir de punta a punta.
	for c in ["goblin", "lobo", "ogro"]:
		_chk(CD.tiene("carne_cruda_" + c), "hay receta para la carne cruda de %s" % c, "")
		_chk(CD.tiene("agua_sucia"), "se puede potabilizar el agua", "")


# --- (b) motivos ------------------------------------------------------

func _test_motivos() -> bool:
	var receta: Dictionary = CD.receta("carne_cruda_lobo")
	_chk(not receta.is_empty(), "hay receta de lobo", "")

	_chk(CO.puede_cocinar("carne_cruda_lobo", receta,
			{"carne_cruda_lobo": 1}, 99.0) == CO.MOTIVO_OK,
		"con ingrediente y lena, se puede", "")
	_chk(CO.puede_cocinar("carne_cruda_lobo", receta, {}, 99.0)
			== CO.MOTIVO_SIN_INGREDIENTE,
		"sin ingrediente, no", CO.puede_cocinar("carne_cruda_lobo", receta, {}, 99.0))
	_chk(CO.puede_cocinar("carne_cruda_lobo", receta, {"carne_cruda_lobo": 1}, 0.1)
			== CO.MOTIVO_SIN_LEÑA,
		"sin lena, no", CO.puede_cocinar("carne_cruda_lobo", receta, {"carne_cruda_lobo": 1}, 0.1))
	_chk(CO.puede_cocinar("nada", {}, {"x": 1}, 99.0) == CO.MOTIVO_SIN_RECETA,
		"sin receta, no", "")

	# Todo motivo tiene texto legible menos el OK.
	for m in [CO.MOTIVO_SIN_RECETA, CO.MOTIVO_SIN_INGREDIENTE,
			CO.MOTIVO_SIN_LEÑA, CO.MOTIVO_TIEMPO]:
		_chk(CO.texto_motivo(m) != "", "el motivo '%s' tiene texto" % m, "")
	_chk(CO.texto_motivo(CO.MOTIVO_OK) == "", "OK no muestra texto", "")
	return true


# --- (c) cocinar ------------------------------------------------------

func _test_cocinar() -> void:
	var receta: Dictionary = CD.receta("carne_cruda_lobo")
	var inv: Dictionary = {"carne_cruda_lobo": 2}
	var r: Dictionary = CO.cocinar("carne_cruda_lobo", receta, inv)

	_chk(bool(r.get("ok", false)), "cocinar funciona", str(r))
	_chk(str(r.get("item_id", "")) == "carne_asada_lobo", "devuelve el asado", str(r))
	_chk(int(r.get("cantidad", 0)) >= 1, "con cantidad", str(r))
	_chk(int(inv.get("carne_cruda_lobo", 0)) == 1,
		"gasta un ingrediente", str(inv))

	# Cocinar algo que no tenés no cambia el inventario.
	var inv2: Dictionary = {"otra_cosa": 5}
	var antes: Dictionary = inv2.duplicate()
	CO.cocinar("carne_cruda_lobo", receta, inv2)
	_chk(inv2 == antes, "cocinar sin ingrediente no toca el inventario", str(inv2))

	# Al tercer ingrediente la pila se borra (no queda en 0).
	var inv3: Dictionary = {"carne_cruda_lobo": 1}
	CO.cocinar("carne_cruda_lobo", receta, inv3)
	_chk(not inv3.has("carne_cruda_lobo"),
		"la pila a 0 se borra en vez de quedar en cero", str(inv3))


# --- (d) la leña viene de la tala ------------------------------------

func _test_lena() -> void:
	# Cada tronco da leña: es el consumidor de la fase 55.
	_chk(CO.LENA_POR_TRONCO > 0.0, "un tronco aporta lena", str(CO.LENA_POR_TRONCO))
	for t in ["tronco_roble", "tronco_pino", "tronco_frembo"]:
		_chk(IT.existe(t), "el tronco '%s' existe (de la 55)" % t, "")
		_chk(str(IT.obtener(t).get("tipo", "")) == "material",
			"'%s' es material, no comida" % t, "")

	# Cocinar gasta lena según la receta, y una receta más cara que la
	#Fogata no deja cocinar.
	var cara: Dictionary = CD.receta("carne_cruda_ogro")
	var receta: Dictionary = CD.receta("carne_cruda_lobo")
	_chk(float(cara.get("lena", 0.0)) >= float(receta.get("lena", 0.0)),
		"el ogro gasta mas lena que el lobo", "")
	_chk(CO.puede_cocinar("carne_cruda_ogro", cara, {"carne_cruda_ogro": 1}, 0.5)
			== CO.MOTIVO_SIN_LEÑA,
		"con menos lena de la que pide, no se cocina", "")


# --- (e) la fogata ---------------------------------------------------

func _test_fogata() -> void:
	var f: Fogata = _fogata()
	_chk(not f.encendida(), "arranca apagada", "")
	_chk(not f.puede_usar(), "y no se puede usar", "")

	f.cargar_lena(12.0)
	_chk(f.encendida(), "con lena se enciende", str(f.lena))
	_chk(f.puede_usar(), "y se puede usar", "")

	# Cargar acumula, con tope.
	f.cargar_lena(12.0)
	_chk(is_equal_approx(f.lena, 24.0), "cargar acumula", str(f.lena))
	f.cargar_lena(99999.0)
	_chk(f.lena <= 300.0, "pero no sin tope (una fogata no es un pozo)", str(f.lena))

	# Gastar hasta apagarla.
	var gastado: bool = f.gastar_lena(f.lena)
	_chk(gastado, "gastar la lena disponible funciona", "")
	_chk(is_equal_approx(f.lena, 0.0), "lena a 0", str(f.lena))
	_chk(not f.encendida(), "se apaga sin lena", "")
	_chk(not f.gastar_lena(1.0), "no se gasta lo que no hay", "")

	# Las piezas visuales: apagadas SIN leña, prendidas con leña. Esto va
	# ANTES de recargar, o el check de "apagada" miraría una fogata encendida.
	_chk(f.get_node_or_null("Luz") != null or f.get_child_count() >= 3,
		"la fogata tiene cuerpo visible", str(f.get_child_count()))
	_chk(not f._particulas.emitting,
		"sin lena, no emite brasas", "")
	_chk(f._fuego.light_energy <= 0.0,
		"ni luz real (no gasta la presupuesto de GPU)", str(f._fuego.light_energy))

	# Y se relanza.
	f.cargar_lena()
	_chk(f.encendida(), "se relanza al cargarle", "")
	_chk(f._particulas.emitting, "con lena, las brasas sí", "")
	_chk(f._fuego.light_energy > 0.0, "y la luz también", "")

	# La señal de leña la escucha la UI.
	var avisos: Array = []
	f.lena_cambiada.connect(func(_s: float): avisos.append(1))
	f.cargar_lena(5.0)
	f.gastar_lena(5.0)
	_chk(avisos.size() >= 2, "cada cambio de lena avisa", str(avisos.size()))


# --- (f) cocinar es lo que sanea -------------------------------------

func _test_cocinar_sana() -> void:
	var cruda: Dictionary = IT.obtener("carne_cruda_lobo").get("efecto", {})
	var asada: Dictionary = IT.obtener("carne_asada_lobo").get("efecto", {})
	_chk(str(cruda.get("riesgo", "")) == "enfermedad",
		"la cruda enferma", str(cruda))
	_chk(not asada.has("riesgo"),
		"la asada NO enferma: cocinar es la contrajuego", str(asada))
	_chk(float(asada.get("hambre", 0.0)) > float(cruda.get("hambre", 0.0)),
		"y además rinde más hambre que la cruda", "")
	_chk(float(asada.get("energia", 0.0)) > 0.0,
		"la asada da energía (la cruda, no)", "")
