extends SceneTree
## Tests headless de la Fase 15: las 8 ciudades secundarias en 3D.
##
## (a) Datos: los 8 JSON cargan (nombre, 16 edificios, monumento con variante
##     distintiva, 4 puertas, 1 NPC ambiental, aparicion_jugador, _paleta);
##     ruta inexistente -> false sin reventar.
## (b) Construccion: cada ciudad se construye con `centro` asignado y
##     `luces_reales = false` (contrato de la demo); emite `ciudad_lista`;
##     16 nodos raiz; muralla con >= 40 tramos y 4 puertas.
## (c) Monumento distintivo por ciudad (oasis, volcan, pico_norte, cristal,
##     sombra, trofeo_guerra, tormenta, sol_dorado): contenido caracteristico
##     verificable dentro del subarbol del monumento.
## (d) Colisiones: StaticBody3D en capa 1 con BoxShape3D; cada edificio
##     colisionable; ninguna OmniLight3D en las secundarias (FalsaAntorcha).
## (e) Aparicion: `punto_aparicion_jugador()` en suelo valido
##     (|y - altura_en| <= 1.0), cerca del centro (<= 60 u) y fuera de
##     colisiones; el NPC ambiental en su punto, dentro del disco r=700 y
##     fuera de colisiones.
## (f) Alturas: ninguna estructura supera 28 u; plaza y calles libres.
## (g) Regresion Moon Town: se construye igual que en la fase 14
##     (18 edificios, monumento luna, 4 puertas, antorchas reales).
##
## Cómo correrlos (un solo comando):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase15_ciudades.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.

const CL: GDScript = preload("res://scripts/mundo/ciudad_luna.gd")
const TG: GDScript = preload("res://scripts/mundo/terreno.gd")

## id, ruta JSON, centro en el mundo, variante del monumento, npc, nombre.
const CIUDADES: Array = [
	["desert", "res://data/ciudad_desert.json", Vector2(9966, 0), "oasis", "yasmina", "Desert Town"],
	["fire", "res://data/ciudad_fire.json", Vector2(-9966, 0), "volcan", "durnan", "Fire Town"],
	["north", "res://data/ciudad_north.json", Vector2(0, -5358), "pico_norte", "sella", "North Town"],
	["mystic", "res://data/ciudad_mystic.json", Vector2(0, 9966), "cristal", "elthar", "Mystic Town"],
	["shadow", "res://data/ciudad_shadow.json", Vector2(9966, -9966), "sombra", "vex", "Shadow Town"],
	["rage", "res://data/ciudad_rage.json", Vector2(-9966, -9966), "trofeo_guerra", "karg", "Rage Town"],
	["fury", "res://data/ciudad_fury.json", Vector2(-9966, 9966), "tormenta", "maris", "Fury Town"],
	["golden", "res://data/ciudad_golden.json", Vector2(9966, 9966), "sol_dorado", "aurelio", "Golden Town"],
]

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []
var _emitidas: int = 0
var _terreno: Terreno = null
var _ciudades: Array = []


func _init() -> void:
	print("[TEST] Fase 15 - las 8 ciudades secundarias en 3D")


var _empezo: bool = false


## El arbol existe recien en el primer _process (leccion 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_datos()
	_construir_todo()
	for i in range(_ciudades.size()):
		var ciudad: CiudadLuna = _ciudades[i]
		var spec: Array = CIUDADES[i]
		_t_edificios(ciudad, spec)
		_t_colisiones(ciudad, spec)
		_t_monumento(ciudad, spec)
		_t_spawn_npc(ciudad, spec)
		_t_alturas_calles(ciudad, spec)
	_t_moon_regression()
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
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


# ---------------------------------------------------------------- datos ---

func _t_datos() -> void:
	var c: CiudadLuna = CL.new()
	_basura.append(c)
	_check(not c.cargar_datos("res://data/no_existe.json"),
		"datos: ruta inexistente -> false sin reventar")
	for spec in CIUDADES:
		var cc: CiudadLuna = CL.new()
		_basura.append(cc)
		var cid: String = str(spec[0])
		_check(cc.cargar_datos(str(spec[1])), "datos: %s carga" % cid)
		_check(str(cc._datos.get("nombre", "")) == str(spec[5]),
			"datos: %s nombre" % cid, str(cc._datos.get("nombre", "")))
		var lista: Array = cc._datos.get("edificios", [])
		_check(lista.size() == 16, "datos: %s 16 edificios" % cid, str(lista.size()))
		var variante: String = ""
		var n_puertas: int = 0
		for e in lista:
			if not (e is Dictionary):
				continue
			var ed: Dictionary = e
			if str(ed.get("tipo", "")) == "monumento":
				variante = str(ed.get("variante", ""))
			elif str(ed.get("tipo", "")) == "puerta":
				n_puertas += 1
		_check(variante == str(spec[3]), "datos: %s monumento %s" % [cid, variante])
		_check(n_puertas == 4, "datos: %s 4 puertas" % cid, str(n_puertas))
		var npcs: Dictionary = cc._datos.get("npcs", {})
		_check(npcs.has(str(spec[4])), "datos: %s npc %s" % [cid, str(spec[4])])
		_check((cc._datos.get("aparicion_jugador", {}) as Dictionary).has("x"),
			"datos: %s aparicion_jugador" % cid)
		_check(cc._tiene_paleta(), "datos: %s trae _paleta" % cid)


# ---------------------------------------------------------- construccion ---

func _construir_todo() -> void:
	_terreno = TG.new()
	root.add_child(_terreno)
	_basura.append(_terreno)
	for spec in CIUDADES:
		var ciudad: CiudadLuna = CL.new()
		ciudad.terreno = _terreno
		ciudad.centro = spec[2]
		ciudad.luces_reales = false
		ciudad.cargar_datos(str(spec[1]))
		ciudad.ciudad_lista.connect(_al_lista)
		ciudad.name = "Ciudad_%s" % str(spec[0])
		root.add_child(ciudad)  # al arbol como la demo (to_global OK)
		_basura.append(ciudad)
		_ciudades.append(ciudad)
	_check(_emitidas == 8, "build: ciudad_lista x8", str(_emitidas))


func _al_lista() -> void:
	_emitidas += 1


func _t_edificios(ciudad: CiudadLuna, spec: Array) -> void:
	var cid: String = str(spec[0])
	_check(ciudad.edificios.size() == 16, "build: %s 16 nodos raiz" % cid,
		str(ciudad.edificios.size()))
	_check(ciudad.edificios.size() >= 10, "build: %s >= 10 edificios" % cid)
	var muralla: Node = ciudad.get_node_or_null("Muralla")
	_check(muralla != null, "muralla: %s nodo Muralla existe" % cid)
	var tramos: int = 0
	if muralla != null:
		for h in (muralla as Node).get_children():
			if str(h.name).begins_with("Tramo_"):
				tramos += 1
	_check(tramos >= 40, "muralla: %s >= 40 tramos" % cid, str(tramos))
	var n_puertas: int = 0
	for b in ciudad.edificios:
		if str((b as Node3D).name).ends_with("_puerta"):
			n_puertas += 1
	_check(n_puertas == 4, "puertas: %s 4 data-driven" % cid, str(n_puertas))


func _t_colisiones(ciudad: CiudadLuna, spec: Array) -> void:
	var cid: String = str(spec[0])
	var cuerpos: Array[Node] = ciudad.find_children("*", "StaticBody3D", true, false)
	_check(cuerpos.size() >= 16, "colision: %s >= 16 StaticBody3D" % cid,
		str(cuerpos.size()))
	var sin_caja: int = 0
	var capa_mala: int = 0
	for cuerpo in cuerpos:
		var sb: StaticBody3D = cuerpo as StaticBody3D
		if sb.collision_layer != 1:
			capa_mala += 1
		var tiene: bool = false
		for h in sb.get_children():
			if h is CollisionShape3D \
					and (h as CollisionShape3D).shape is BoxShape3D:
				tiene = true
		if not tiene:
			sin_caja += 1
	_check(sin_caja == 0, "colision: %s todo cuerpo con BoxShape3D" % cid,
		str(sin_caja))
	_check(capa_mala == 0, "colision: %s todos en capa 1" % cid, str(capa_mala))
	var sin_cuerpo: int = 0
	for b in ciudad.edificios:
		var bb: Array[Node] = (b as Node3D).find_children("*", "StaticBody3D", true, false)
		if bb.is_empty():
			sin_cuerpo += 1
	_check(sin_cuerpo == 0, "colision: %s cada edificio colisionable" % cid,
		str(sin_cuerpo))
	# Fase 15: las secundarias usan FalsaAntorcha (sin luz dinamica).
	var omnis: Array[Node] = ciudad.find_children("*", "OmniLight3D", true, false)
	_check(omnis.is_empty(), "luces: %s sin OmniLight3D" % cid, str(omnis.size()))
	var falsas: Array[Node] = ciudad.find_children("*", "FalsaAntorcha", true, false)
	_check(falsas.size() >= 40, "luces: %s >= 40 FalsaAntorcha" % cid,
		str(falsas.size()))


# ------------------------------------------------------------ monumento ---

func _monumento_de(ciudad: CiudadLuna) -> Node3D:
	for b in ciudad.edificios:
		if str((b as Node3D).name).ends_with("_monumento"):
			return b
	return null


func _tiene_mat_en(mon: Node3D, ciudad: CiudadLuna, mat_nombre: String) -> bool:
	var m: Material = ciudad._mat(mat_nombre)
	for n in mon.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).material_override == m:
			return true
	return false


func _tiene_cilindro_lados(mon: Node3D, lados: int) -> bool:
	for n in mon.find_children("*", "MeshInstance3D", true, false):
		var cm: CylinderMesh = ((n as MeshInstance3D).mesh as CylinderMesh)
		if cm != null and cm.radial_segments == lados:
			return true
	return false


func _tiene_disco_sol(mon: Node3D) -> bool:
	# Ojo: las dimensiones de CylinderMesh son float32 (0.8 se guarda como
	# 0.8000000119): comparar con == falla; usar is_equal_approx.
	for n in mon.find_children("*", "MeshInstance3D", true, false):
		var cm: CylinderMesh = ((n as MeshInstance3D).mesh as CylinderMesh)
		if cm != null and is_equal_approx(cm.height, 0.8) \
				and is_equal_approx(cm.top_radius, 4.5) \
				and is_equal_approx(cm.bottom_radius, 4.5):
			return true
	return false


func _t_monumento(ciudad: CiudadLuna, spec: Array) -> void:
	var cid: String = str(spec[0])
	var variante: String = str(spec[3])
	var mon: Node3D = _monumento_de(ciudad)
	_check(mon != null, "monumento: %s existe" % cid)
	if mon == null:
		return
	var ok: bool = false
	match variante:
		"oasis":
			ok = _tiene_mat_en(mon, ciudad, "agua")
		"volcan":
			ok = not mon.find_children("*", "FalsaAntorcha", true, false).is_empty()
		"pico_norte":
			ok = _tiene_mat_en(mon, ciudad, "nieve")
		"cristal":
			ok = _tiene_mat_en(mon, ciudad, "cristal_arcano") \
				and not _tiene_mat_en(mon, ciudad, "nieve") \
				and not _tiene_cilindro_lados(mon, 4)
		"sombra":
			ok = _tiene_cilindro_lados(mon, 4)
		"trofeo_guerra":
			ok = _tiene_mat_en(mon, ciudad, "hueso")
		"tormenta":
			var anillos: int = 0
			for n in mon.find_children("*", "MeshInstance3D", true, false):
				if (n as MeshInstance3D).mesh is TorusMesh:
					anillos += 1
			ok = anillos >= 2
		"sol_dorado":
			ok = _tiene_disco_sol(mon)
	_check(ok, "monumento: %s distintivo (%s)" % [cid, variante])


# --------------------------------------------------------- spawn y NPCs ---

func _t_spawn_npc(ciudad: CiudadLuna, spec: Array) -> void:
	var cid: String = str(spec[0])
	var centro: Vector2 = spec[2]
	var cajas: Array = ciudad.cajas_colision()
	# Aparicion del jugador: suelo valido, cerca del centro, sin colisiones.
	var p: Vector3 = ciudad.punto_aparicion_jugador()
	var h_terr: float = _terreno.altura_en(p.x, p.z)
	_check(absf(p.y - h_terr) <= 1.0, "spawn: %s sobre terreno valido" % cid,
		"y=%f terr=%f" % [p.y, h_terr])
	_check(Vector2(p.x - centro.x, p.z - centro.y).length() <= 60.0,
		"spawn: %s en la plaza (<= 60 u del centro)" % cid)
	_check(not _dentro_de_cajas(p, cajas), "spawn: %s fuera de colisiones" % cid)
	# NPC ambiental: punto data-driven, dentro del disco r=700, sin colisiones.
	var nid: String = str(spec[4])
	_check(ciudad.puntos_npc.has(nid), "npc: %s punto para %s" % [cid, nid])
	if ciudad.puntos_npc.has(nid):
		var q: Vector3 = ciudad.npc_spawn(nid)
		_check(q.is_equal_approx(ciudad.puntos_npc[nid] as Vector3),
			"npc: %s npc_spawn(%s) == puntos_npc" % [cid, nid])
		_check(Vector2(q.x - centro.x, q.z - centro.y).length() <= 700.0,
			"npc: %s dentro del disco r=700" % cid)
		_check(not _dentro_de_cajas(q, cajas),
			"npc: %s fuera de colisiones" % cid)


func _dentro_de_cajas(p: Vector3, cajas: Array) -> bool:
	for cj in cajas:
		if (cj as AABB).has_point(p):
			return true
	return false


# ----------------------------------------------------- alturas y calles ---

func _t_alturas_calles(ciudad: CiudadLuna, spec: Array) -> void:
	var cid: String = str(spec[0])
	var max_h: float = 0.0
	var altas: int = 0
	for k in ciudad.alturas.keys():
		var h: float = float(ciudad.alturas[k])
		max_h = maxf(max_h, h)
		if h > 28.0:
			altas += 1
	_check(altas == 0, "alturas: %s nada supera 28 u" % cid, "max=%f" % max_h)
	# Calles radiales y plaza libres de colisiones invisibles (muestreo).
	var cajas: Array = ciudad.cajas_colision()
	var bloqueos: int = 0
	var r_mur: float = float(ciudad._datos.get("radio_muralla", 620.0)) - 10.0
	for g in range(4):
		var ang: float = float(g) * PI * 0.5
		var dir := Vector3(sin(ang), 0, -cos(ang))
		var r: float = 70.0
		while r <= r_mur:
			var wp := Vector3(ciudad.centro.x + dir.x * r, 0,
				ciudad.centro.y + dir.z * r)
			wp.y = _terreno.altura_en(wp.x, wp.z) + 1.0
			if _dentro_de_cajas(wp, cajas):
				bloqueos += 1
			r += 20.0
	for ri in range(2, 6):
		var r2: float = float(ri) * 10.0
		for k in range(8):
			var ang2: float = float(k) * PI * 0.25
			var wp2 := Vector3(ciudad.centro.x + r2 * cos(ang2), 0,
				ciudad.centro.y + r2 * sin(ang2))
			wp2.y = _terreno.altura_en(wp2.x, wp2.z) + 1.0
			if _dentro_de_cajas(wp2, cajas):
				bloqueos += 1
	_check(bloqueos == 0, "calles: %s plaza y calles libres" % cid,
		str(bloqueos))


# ------------------------------------------------- regresion Moon Town ---

func _t_moon_regression() -> void:
	# Moon Town con el codigo generalizado: igual que en la fase 14.
	var luna: CiudadLuna = CL.new()
	luna.terreno = _terreno
	luna.ciudad_lista.connect(_al_lista)
	root.add_child(luna)
	_basura.append(luna)
	_check(_emitidas == 9, "moon: ciudad_lista emitida", str(_emitidas))
	_check(luna.edificios.size() == 18, "moon: 18 edificios",
		str(luna.edificios.size()))
	var mon: Node3D = _monumento_de(luna)
	_check(mon != null, "moon: monumento existe")
	if mon != null:
		var csgs: Array[Node] = mon.find_children("*", "CSGCombiner3D", true, false)
		_check(not csgs.is_empty(), "moon: luna creciente (CSG, verbatim fase 14)")
	var n_puertas: int = 0
	for b in luna.edificios:
		if str((b as Node3D).name).ends_with("_puerta"):
			n_puertas += 1
	_check(n_puertas == 4, "moon: 4 puertas", str(n_puertas))
	var antorchas: Array[Node] = luna.find_children("*", "Antorcha", true, false)
	_check(antorchas.size() >= 35, "moon: >= 35 Antorcha reales",
		str(antorchas.size()))
	var omnis: Array[Node] = luna.find_children("*", "OmniLight3D", true, false)
	_check(not omnis.is_empty(), "moon: luces reales (OmniLight3D)",
		str(omnis.size()))
	_check(not luna._tiene_paleta(), "moon: sin _paleta (materiales clasicos)")
	var p: Vector3 = luna.punto_aparicion_jugador()
	_check(Vector2(p.x, p.z).length() <= 60.0, "moon: spawn en la plaza")
