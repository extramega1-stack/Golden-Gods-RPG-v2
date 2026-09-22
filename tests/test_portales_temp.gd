extends SceneTree
## Tests headless de la Fase 14.1 (portales TEMPORALES de inspección).
##
## (a) `data/portales_temp.json`: existe, trae >= 10 destinos con
##     {id, nombre, x, z}; todos dentro del mundo (|x|,|z| <= 18432);
##     ids únicos; incluye moon_town + las 8 ciudades futuras + un hito.
## (b) `PortalTemporal`: al configurar construye el visual (anillo +
##     Label3D con el nombre del destino, billboard activado); sin destino
##     no construye nada.
## (c) `jugador_distancia` / `portal_cercano`: puros — el más cercano
##     dentro del radio gana; fuera del radio no hay portal; null sin
##     portales.
## (d) `punto_destino(terreno)`: cae en (x, z) del destino y a la altura
##     del terreno + margen (no enterrado).
## (e) Aislamiento TEMPORAL: con ruta inexistente `cargar_destinos`
##     devuelve vacío con warning (la demo no revienta sin el JSON).
##
## Cómo correrlo (un solo comando):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_portales_temp.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.

const PT: GDScript = preload("res://scripts/mundo/portal_temporal.gd")
const TG: GDScript = preload("res://scripts/mundo/terreno.gd")

const RUTA: String = "res://data/portales_temp.json"
const LIMITE: float = 18432.0

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 14.1 - portales temporales de inspección")


## El árbol existe recién en el primer _process (lección 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_json()
	_t_visual()
	_t_cercania()
	_t_destino_terreno()
	_t_aislamiento()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
	return true


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


func _t_json() -> void:
	var destinos: Array = PT.cargar_destinos(RUTA)
	_check(destinos.size() >= 10, "json: >= 10 destinos",
		"n=%d" % destinos.size())
	var ids: Dictionary = {}
	var tiene_luna: bool = false
	var ciudades: int = 0
	for d in destinos:
		var dd: Dictionary = d
		var id: String = str(dd.get("id", ""))
		var nombre: String = str(dd.get("nombre", ""))
		var x: float = float(dd.get("x", 999999.0))
		var z: float = float(dd.get("z", 999999.0))
		_check(id != "" and nombre != "", "json: destino con id y nombre",
			"id='%s'" % id)
		_check(not ids.has(id), "json: id único '%s'" % id, id)
		ids[id] = true
		_check(absf(x) <= LIMITE and absf(z) <= LIMITE,
			"json: '%s' dentro del mundo" % id, "(%f, %f)" % [x, z])
		if id == "moon_town":
			tiene_luna = true
		if id.ends_with("_town"):
			ciudades += 1
	_check(tiene_luna, "json: incluye moon_town (retorno)")
	_check(ciudades >= 9, "json: moon + 8 ciudades futuras", "n=%d" % ciudades)


func _portal_con(dest: Dictionary) -> PortalTemporal:
	var p: PortalTemporal = PT.new()
	_basura.append(p)
	p.configurar(dest)
	root.add_child(p)
	return p


func _t_visual() -> void:
	var dest: Dictionary = {"id": "x", "nombre": "Desert Town (futura)",
		"x": 9966.0, "z": 0.0}
	var p: PortalTemporal = _portal_con(dest)
	var etiquetas: Array = p.find_children("*", "Label3D", true, false)
	_check(etiquetas.size() == 1, "visual: un Label3D con el nombre")
	if etiquetas.size() == 1:
		var lb: Label3D = etiquetas[0] as Label3D
		_check(lb.text == "Desert Town (futura)", "visual: texto = destino")
		_check(lb.billboard == BaseMaterial3D.BILLBOARD_ENABLED,
			"visual: billboard activado (legible)")
		_check(lb.global_position.y > 10.0, "visual: etiqueta arriba",
			"y=%f" % lb.global_position.y)
	var anillos: int = 0
	for c in p.get_children():
		if c is MeshInstance3D:
			anillos += 1
	_check(anillos >= 2, "visual: anillo + base/disco", "n=%d" % anillos)
	# Sin destino no construye nada.
	var vacio: PortalTemporal = PT.new()
	_basura.append(vacio)
	root.add_child(vacio)
	_check(vacio.get_child_count() == 0, "visual: sin destino no construye")


func _t_cercania() -> void:
	var a: PortalTemporal = _portal_con({"id": "a", "nombre": "A",
		"x": 0.0, "z": 0.0})
	var b: PortalTemporal = _portal_con({"id": "b", "nombre": "B",
		"x": 100.0, "z": 0.0})
	a.position = Vector3.ZERO
	b.position = Vector3(100, 0, 0)
	_check(a.jugador_distancia(Vector3(3, 0, 4)) <= 5.01,
		"cercanía: distancia horizontal (ignora Y)")
	var cerca: PortalTemporal = PT.portal_cercano([a, b], Vector3(4, 0, 0))
	_check(cerca == a, "cercanía: el más próximo gana")
	var lejos: PortalTemporal = PT.portal_cercano([a, b], Vector3(500, 0, 0))
	_check(lejos == null, "cercanía: fuera del radio no hay portal")
	var vacio: PortalTemporal = PT.portal_cercano([], Vector3.ZERO)
	_check(vacio == null, "cercanía: sin portales no hay portal")
	var borde: PortalTemporal = PT.portal_cercano([a], Vector3(6, 0, 0), 6.0)
	_check(borde == a, "cercanía: en el borde del radio vale")


func _t_destino_terreno() -> void:
	var t: Terreno = TG.new()
	_basura.append(t)
	root.add_child(t)
	var p: PortalTemporal = _portal_con({"id": "m", "nombre": "Montaña",
		"x": 0.0, "z": -13824.0})
	var punto: Vector3 = p.punto_destino(t)
	_check(absf(punto.x - 0.0) < 0.01 and absf(punto.z + 13824.0) < 0.01,
		"destino: cae en (x, z) del destino", str(punto))
	var esperado: float = t.altura_en(0.0, -13824.0) + 1.5
	_check(absf(punto.y - esperado) < 0.01,
		"destino: sobre el terreno + margen (no enterrado)",
		"y=%f esperado=%f" % [punto.y, esperado])


func _t_aislamiento() -> void:
	# Sin JSON (o roto) no hay portales pero tampoco crash: la demo sigue.
	var nada: Array = PT.cargar_destinos("res://data/no_existe_temp.json")
	_check(nada.is_empty(), "aislamiento: ruta inexistente -> vacío")
