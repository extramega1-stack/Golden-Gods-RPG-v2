extends SceneTree
## Tests headless de la Fase 14: ciudad principal "Moon Town" reimaginada 2026.
##
## (a) Datos: `data/ciudad_luna.json` carga (nombre, 18 edificios, 8 tipos,
##     3 NPCs, punto de aparicion); ruta inexistente -> false sin reventar.
## (b) Construccion: `CiudadLuna` emite `ciudad_lista`; crea un nodo raiz
##     por entrada de datos (18), cada uno con StaticBody3D en capa 1 con
##     BoxShape3D; existen las 4 puertas y la muralla (>= 40 tramos).
## (c) NPCs: `puntos_npc` trae ilya/bram/sira; `npc_spawn()` los devuelve;
##     id desconocido -> punto de aparicion; todos dentro del radio 800 y
##     fuera de cualquier caja de colision.
## (d) Aparicion: en la plaza (<= 60 u del centro), sobre el terreno
##     (|y - altura_en| <= 1.0) y mirando al monumento.
## (e) Alturas: ninguna estructura supera 28 u (camara L2/MU).
## (f) Calles y plaza libres de colisiones invisibles (muestreo de puntos).
## (g) >= 35 antorchas (reutilizan `Antorcha`) y monumento con luna creciente.
##
## Cómo correrlos (un solo comando):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase14_ciudad.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.

const CL: GDScript = preload("res://scripts/mundo/ciudad_luna.gd")
const TG: GDScript = preload("res://scripts/mundo/terreno.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []
var _lista_emitida: bool = false


func _init() -> void:
	print("[TEST] Fase 14 - ciudad principal (Moon Town reimaginada 2026)")


var _empezo: bool = false


## El arbol existe recien en el primer _process (leccion 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_datos()
	var ciudad: CiudadLuna = _construir_ciudad()
	if ciudad != null:
		_t_edificios(ciudad)
		_t_colisiones(ciudad)
		_t_puertas_muralla(ciudad)
		_t_npcs(ciudad)
		_t_aparicion(ciudad)
		_t_alturas(ciudad)
		_t_calles_libres(ciudad)
		_t_antorchas_monumento(ciudad)
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


func _t_datos() -> void:
	var c: CiudadLuna = CL.new()
	_basura.append(c)
	_check(c.cargar_datos("res://data/ciudad_luna.json"), "datos: ciudad_luna.json carga")
	_check(not c.cargar_datos("res://data/no_existe.json"),
		"datos: ruta inexistente -> false sin reventar")
	_check(str(c._datos.get("nombre", "")) == "Moon Town", "datos: nombre Moon Town")
	var lista: Array = c._datos.get("edificios", [])
	_check(lista.size() == 18, "datos: 18 edificios", str(lista.size()))
	var tipos: Dictionary = {}
	for e in lista:
		if e is Dictionary:
			tipos[str((e as Dictionary).get("tipo", ""))] = true
	for t in ["monumento", "salon_clases", "forja", "tienda", "cuartel", "templo",
			"casa", "puerta"]:
		_check(tipos.has(t), "datos: tipo presente: " + t)
	var n_casas: int = 0
	for e in lista:
		if e is Dictionary and str((e as Dictionary).get("tipo", "")) == "casa":
			n_casas += 1
	_check(n_casas >= 6 and n_casas <= 10, "datos: 6-10 casas", str(n_casas))
	var npcs: Dictionary = c._datos.get("npcs", {})
	for nid in ["ilya", "bram", "sira"]:
		_check(npcs.has(nid), "datos: npc en datos: " + nid)


func _construir_ciudad() -> CiudadLuna:
	var t: Terreno = TG.new()
	root.add_child(t)
	_basura.append(t)
	var ciudad: CiudadLuna = CL.new()
	ciudad.terreno = t
	ciudad.ciudad_lista.connect(_al_lista)
	root.add_child(ciudad)
	_basura.append(ciudad)
	_check(_lista_emitida, "build: senal ciudad_lista emitida")
	return ciudad


func _al_lista() -> void:
	_lista_emitida = true


func _t_edificios(ciudad: CiudadLuna) -> void:
	_check(ciudad.edificios.size() == 18, "build: 18 nodos raiz de edificios",
		str(ciudad.edificios.size()))
	var vistos: Dictionary = {}
	for b in ciudad.edificios:
		var n: String = str((b as Node3D).name)
		vistos[n] = true
	_check(vistos.has("Edificio_00_monumento"), "build: monumento es Edificio_00")
	var n_puertas: int = 0
	for k in vistos.keys():
		if str(k).ends_with("_puerta"):
			n_puertas += 1
	_check(n_puertas == 4, "build: 4 puertas data-driven", str(n_puertas))


func _t_colisiones(ciudad: CiudadLuna) -> void:
	var cuerpos: Array[Node] = ciudad.find_children("*", "StaticBody3D", true, false)
	_check(cuerpos.size() >= 18, "colision: >= 18 StaticBody3D", str(cuerpos.size()))
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
	_check(sin_caja == 0, "colision: todo cuerpo con BoxShape3D", str(sin_caja))
	_check(capa_mala == 0, "colision: todos en capa 1", str(capa_mala))
	# Cada edificio de datos tiene al menos un cuerpo colisionable.
	var sin_cuerpo: int = 0
	for b in ciudad.edificios:
		var bb: Array[Node] = (b as Node3D).find_children("*", "StaticBody3D", true, false)
		if bb.is_empty():
			sin_cuerpo += 1
	_check(sin_cuerpo == 0, "colision: cada edificio colisionable", str(sin_cuerpo))


func _t_puertas_muralla(ciudad: CiudadLuna) -> void:
	var muralla: Node = ciudad.get_node_or_null("Muralla")
	_check(muralla != null, "muralla: nodo Muralla existe")
	var tramos: int = 0
	if muralla != null:
		for h in (muralla as Node).get_children():
			if str(h.name).begins_with("Tramo_"):
				tramos += 1
	_check(tramos >= 40, "muralla: >= 40 tramos entre puertas", str(tramos))
	var torres: int = 0
	for b in ciudad.edificios:
		if str((b as Node3D).name).ends_with("_puerta"):
			for h in (b as Node3D).find_children("*", "StaticBody3D", true, false):
				torres += 1
	_check(torres >= 12, "puertas: postes+torres colisionables", str(torres))


func _t_npcs(ciudad: CiudadLuna) -> void:
	for nid in ["ilya", "bram", "sira"]:
		_check(ciudad.puntos_npc.has(nid), "npc: punto para " + nid)
		var p: Vector3 = ciudad.npc_spawn(nid)
		var q: Vector3 = ciudad.puntos_npc[nid]
		_check(p.is_equal_approx(q), "npc: npc_spawn(%s) == puntos_npc" % nid)
		var plano: Vector2 = Vector2(p.x, p.z)
		_check(plano.length() <= 800.0, "npc: %s dentro del radio 800" % nid,
			str(plano.length()))
	_check(ciudad.npc_spawn("nadie") == ciudad.punto_aparicion_jugador(),
		"npc: id desconocido -> punto de aparicion")
	# Ningun NPC dentro de una caja de colision.
	var cajas: Array = ciudad.cajas_colision()
	var dentro: int = 0
	for nid in ["ilya", "bram", "sira"]:
		var p: Vector3 = ciudad.npc_spawn(nid)
		for cj in cajas:
			if (cj as AABB).has_point(p):
				dentro += 1
	_check(dentro == 0, "npc: spawns fuera de colisiones", str(dentro))


func _t_aparicion(ciudad: CiudadLuna) -> void:
	var p: Vector3 = ciudad.punto_aparicion_jugador()
	_check(Vector2(p.x, p.z).length() <= 60.0, "spawn: en la plaza (<= 60 u)",
		str(Vector2(p.x, p.z).length()))
	var h_terr: float = ciudad.terreno.altura_en(p.x, p.z)
	_check(absf(p.y - h_terr) <= 1.0, "spawn: sobre el terreno",
		"y=%f terr=%f" % [p.y, h_terr])
	# Mira al monumento (origen): forward(yaw) . dir > 0.99.
	var yaw: float = ciudad.yaw_aparicion()
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var dir: Vector3 = Vector3(-p.x, 0, -p.z).normalized()
	_check(fwd.dot(dir) > 0.99, "spawn: mira al monumento",
		"dot=%f yaw=%f" % [fwd.dot(dir), yaw])
	# El propio spawn no esta dentro de una colision.
	var cajas: Array = ciudad.cajas_colision()
	var dentro: bool = false
	for cj in cajas:
		if (cj as AABB).has_point(p):
			dentro = true
	_check(not dentro, "spawn: fuera de colisiones")


func _t_alturas(ciudad: CiudadLuna) -> void:
	_check(ciudad.alturas.size() >= 29, "alturas: registro completo",
		str(ciudad.alturas.size()))
	var altas: int = 0
	var max_h: float = 0.0
	for k in ciudad.alturas.keys():
		var h: float = float(ciudad.alturas[k])
		max_h = maxf(max_h, h)
		if h > 28.0:
			altas += 1
	_check(altas == 0, "alturas: nada supera 28 u", "max=%f" % max_h)
	_check(max_h > 10.0, "alturas: hay estructuras altas", str(max_h))


func _t_calles_libres(ciudad: CiudadLuna) -> void:
	var cajas: Array = ciudad.cajas_colision()
	var bloqueos: int = 0
	# 4 calles radiales: linea central de r=70 a r=690.
	for g in range(4):
		var ang: float = float(g) * PI * 0.5
		var dir := Vector3(sin(ang), 0, -cos(ang))
		var r: float = 70.0
		while r <= 690.0:
			var p: Vector3 = dir * r
			p.y = ciudad.terreno.altura_en(p.x, p.z) + 1.0
			for cj in cajas:
				if (cj as AABB).has_point(p):
					bloqueos += 1
			r += 20.0
	# Plaza: anillo r=20..50, 8 angulos (r=20 evita el pedestal del monumento,
	# que SI tiene colision visible e intencional).
	for ri in range(2, 6):
		var r2: float = float(ri) * 10.0
		for k in range(8):
			var ang2: float = float(k) * PI * 0.25
			var p2 := Vector3(r2 * cos(ang2), 0, r2 * sin(ang2))
			p2.y = ciudad.terreno.altura_en(p2.x, p2.z) + 1.0
			for cj in cajas:
				if (cj as AABB).has_point(p2):
					bloqueos += 1
	_check(bloqueos == 0, "calles: plaza y calles sin colisiones", str(bloqueos))


func _t_antorchas_monumento(ciudad: CiudadLuna) -> void:
	var luces: Array[Node] = ciudad.find_children("*", "Antorcha", true, false)
	_check(luces.size() >= 35, "antorchas: >= 35 reutilizando Antorcha",
		str(luces.size()))
	var monumento: Node3D = null
	for b in ciudad.edificios:
		if str((b as Node3D).name).ends_with("_monumento"):
			monumento = b
	_check(monumento != null, "monumento: existe")
	var tiene_luna: bool = false
	if monumento != null:
		var csgs: Array[Node] = monumento.find_children("*", "CSGCombiner3D", true, false)
		tiene_luna = not csgs.is_empty()
	_check(tiene_luna, "monumento: luna creciente (CSG)")
