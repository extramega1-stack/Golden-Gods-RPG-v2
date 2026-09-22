class_name CiudadLuna
extends Node3D
## Ciudad principal "Moon Town" reimaginada 2026 — Fase 14 (rework del mapa).
##
## Data-driven: `data/ciudad_luna.json` lista los edificios
## (tipo, x, z, rot, escala, variante). Anadir/mover un edificio = tocar datos.
## Este script solo sabe CONSTRUIR cada tipo de forma procedural y original
## (nada copiado de Blizzard): muros, tejados a dos aguas, puertas, ventanas
## con luz calida, muralla con 4 puertas, monumento de la luna creciente, etc.
##
## Direccion visual del proyecto: Lineage 2 + MU (metal oscuro acerado,
## dorado, gotico rojo sangre).
##
## La altura Y de TODO se consulta en runtime a `Terreno.altura_en(x, z)`:
## la ciudad vive en el disco plano (radio 800, centro 0,0) que garantiza el
## worker de terreno; este script no hardcodea ninguna altura.
##
## Uso desde la demo:
##   var ciudad := CiudadLuna.new()
##   ciudad.terreno = terreno        # OBLIGATORIO antes de anadir al arbol
##   ciudad.ciclo = ciclo_dia        # opcional: modula las antorchas
##   add_child(ciudad)               # _ready construye y emite ciudad_lista
##   var p: Vector3 = ciudad.punto_aparicion_jugador()
##   jugador.position = p
##   jugador.rotation.y = ciudad.yaw_aparicion()
##   npc_ilya.position = ciudad.npc_spawn("ilya")
##
## Reglas de diseno (spec fase 14):
## - Cada edificio lleva StaticBody3D en capa 1 con cajas simples.
## - Calles de 40 u (>= 30 u); edificios de <= 28 u de alto.
## - La plaza y las calles quedan libres de colisiones invisibles.

## Ruta por defecto de los datos.
const RUTA_DATOS: String = "res://data/ciudad_luna.json"
## Radio del disco urbano garantizado por el terreno (centro 0,0).
const RADIO: float = 800.0
## Altura maxima permitida para cualquier estructura (camara L2/MU).
const ALTURA_MAX: float = 28.0
## Ancho de las calles radiales (>= 30 por spec).
const ANCHO_CALLE: float = 40.0

## Se emite al terminar de construir (en _ready, sincronico al add_child).
signal ciudad_lista

## Terreno para consultar alturas. ASIGNAR ANTES de add_child.
var terreno: Terreno = null
## Ciclo dia/noche que modula el brillo de las antorchas (opcional).
var ciclo: CicloDia = null

## Un nodo raiz por entrada de datos (en el mismo orden del JSON).
var edificios: Array[Node3D] = []
## id de NPC -> punto de aparicion (Vector3). La demo coloca los NPCs.
var puntos_npc: Dictionary = {}
## nombre de estructura -> altura total en u (para verificar ALTURA_MAX).
var alturas: Dictionary = {}

var _datos: Dictionary = {}
var _construida: bool = false
var _mats: Dictionary = {}
var _caja_mesh: BoxMesh = null
var _luces: Array[Antorcha] = []
var _n_antorchas: int = 0


func _ready() -> void:
	if _datos.is_empty():
		if not cargar_datos(RUTA_DATOS):
			push_warning("[CiudadLuna] no se pudo cargar %s" % RUTA_DATOS)
	construir()
	ciudad_lista.emit()


## Carga el JSON de datos. Devuelve false si no existe o no parsea.
func cargar_datos(ruta: String) -> bool:
	if not FileAccess.file_exists(ruta):
		return false
	var texto: String = FileAccess.get_file_as_string(ruta)
	var parsed: Variant = JSON.parse_string(texto)
	if not (parsed is Dictionary):
		return false
	_datos = parsed as Dictionary
	return true


## Construye la ciudad completa. Idempotente.
func construir() -> void:
	if _construida:
		return
	_construida = true
	if _datos.is_empty():
		cargar_datos(RUTA_DATOS)
	if terreno == null:
		push_warning("[CiudadLuna] sin terreno: alturas a 0.0")
	_construir_plaza()
	_construir_calles()
	_construir_muralla()
	var lista: Array = _datos.get("edificios", [])
	var idx: int = 0
	for e in lista:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		var tipo: String = str(d.get("tipo", ""))
		var x: float = float(d.get("x", 0.0))
		var z: float = float(d.get("z", 0.0))
		var rot: float = float(d.get("rot", 0.0))
		var escala: float = float(d.get("escala", 1.0))
		var variante: String = str(d.get("variante", ""))
		var raiz: Node3D = _construir_edificio(tipo, variante)
		if raiz == null:
			push_warning("[CiudadLuna] tipo desconocido: %s" % tipo)
			continue
		raiz.position = Vector3(x, _altura(x, z), z)
		raiz.rotation.y = rot
		raiz.scale = Vector3.ONE * escala
		raiz.name = "Edificio_%02d_%s" % [idx, tipo]
		add_child(raiz)
		edificios.append(raiz)
		var h_local: float = float(raiz.get_meta("altura", 0.0))
		alturas[str(raiz.name)] = h_local * escala
		idx += 1
	_construir_antorchas()
	_construir_banderas_puertas()
	_cargar_npcs()


## Punto de aparicion del jugador: centro de la plaza, sobre el terreno.
func punto_aparicion_jugador() -> Vector3:
	var ap: Dictionary = _datos.get("aparicion_jugador", {})
	var x: float = float(ap.get("x", 0.0))
	var z: float = float(ap.get("z", 45.0))
	return Vector3(x, _altura(x, z), z)


## Yaw para mirar al monumento desde el punto de aparicion.
func yaw_aparicion() -> float:
	var ap: Dictionary = _datos.get("aparicion_jugador", {})
	return float(ap.get("yaw", 0.0))


## Punto de spawn de un NPC ("ilya", "bram", "sira").
## Un id desconocido devuelve el punto de aparicion del jugador.
func npc_spawn(npc_id: String) -> Vector3:
	if puntos_npc.has(npc_id):
		var v: Vector3 = puntos_npc[npc_id]
		return v
	return punto_aparicion_jugador()


## Fija (o cambia) el ciclo dia/noche y lo propaga a las antorchas.
func fijar_ciclo(c: CicloDia) -> void:
	ciclo = c
	for a in _luces:
		(a as Antorcha).ciclo = c


## AABBs globales de todas las cajas de colision (util para tests).
func cajas_colision() -> Array:
	var cajas: Array = []
	var cuerpos: Array[Node] = find_children("*", "StaticBody3D", true, false)
	for cuerpo in cuerpos:
		var sb: StaticBody3D = cuerpo as StaticBody3D
		for h in sb.get_children():
			if not (h is CollisionShape3D):
				continue
			var cs: CollisionShape3D = h
			var bs: BoxShape3D = cs.shape as BoxShape3D
			if bs == null:
				continue
			var ext: Vector3 = bs.size * 0.5
			var gt: Transform3D = cs.global_transform
			var mn := Vector3(INF, INF, INF)
			var mx := Vector3(-INF, -INF, -INF)
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var p: Vector3 = gt * (ext * Vector3(sx, sy, sz))
						mn.x = minf(mn.x, p.x)
						mn.y = minf(mn.y, p.y)
						mn.z = minf(mn.z, p.z)
						mx.x = maxf(mx.x, p.x)
						mx.y = maxf(mx.y, p.y)
						mx.z = maxf(mx.z, p.z)
			cajas.append(AABB(mn, mx - mn).abs())
	return cajas


# ---------------------------------------------------------------------------
# Internos
# ---------------------------------------------------------------------------

## Altura del terreno en (x, z); 0.0 si aun no hay terreno asignado.
func _altura(x: float, z: float) -> float:
	if terreno == null:
		return 0.0
	return terreno.altura_en(x, z)


func _cargar_npcs() -> void:
	puntos_npc.clear()
	var nd: Dictionary = _datos.get("npcs", {})
	for id in nd.keys():
		var e: Variant = nd[id]
		if not (e is Dictionary):
			continue
		var dd: Dictionary = e
		var x: float = float(dd.get("x", 0.0))
		var z: float = float(dd.get("z", 0.0))
		puntos_npc[str(id)] = Vector3(x, _altura(x, z), z)


func _construir_edificio(tipo: String, variante: String) -> Node3D:
	match tipo:
		"casa":
			return _casa(variante)
		"salon_clases":
			return _salon()
		"forja":
			return _forja()
		"tienda":
			return _tienda()
		"cuartel":
			return _cuartel()
		"templo":
			return _templo()
		"monumento":
			return _monumento()
		"puerta":
			return _puerta()
	return null


## Material cacheado por nombre (direccion L2/MU: acero oscuro + oro + rojo).
func _mat(nombre: String) -> StandardMaterial3D:
	if _mats.has(nombre):
		return _mats[nombre] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	match nombre:
		"piedra":
			m.albedo_color = Color(0.30, 0.31, 0.35)
			m.roughness = 0.95
		"piedra_clara":
			m.albedo_color = Color(0.55, 0.53, 0.50)
			m.roughness = 0.9
		"plaza":
			m.albedo_color = Color(0.42, 0.40, 0.38)
			m.roughness = 0.95
		"calle":
			m.albedo_color = Color(0.24, 0.24, 0.27)
			m.roughness = 0.95
		"madera":
			m.albedo_color = Color(0.38, 0.24, 0.14)
			m.roughness = 0.85
		"madera_oscura":
			m.albedo_color = Color(0.22, 0.14, 0.09)
			m.roughness = 0.9
		"puerta_madera":
			m.albedo_color = Color(0.16, 0.10, 0.06)
			m.roughness = 0.9
		"oro":
			m.albedo_color = Color(0.85, 0.62, 0.22)
			m.metallic = 0.85
			m.roughness = 0.35
		"acero":
			m.albedo_color = Color(0.35, 0.37, 0.42)
			m.metallic = 0.7
			m.roughness = 0.5
		"bronce":
			m.albedo_color = Color(0.55, 0.38, 0.18)
			m.metallic = 0.8
			m.roughness = 0.45
		"tejado_pizarra":
			m.albedo_color = Color(0.25, 0.28, 0.35)
			m.roughness = 0.9
		"tejado_rojo":
			m.albedo_color = Color(0.42, 0.12, 0.10)
			m.roughness = 0.9
		"tejado_madera":
			m.albedo_color = Color(0.30, 0.20, 0.12)
			m.roughness = 0.9
		"muro_a":
			m.albedo_color = Color(0.72, 0.62, 0.50)
			m.roughness = 0.95
		"muro_b":
			m.albedo_color = Color(0.50, 0.28, 0.20)
			m.roughness = 0.95
		"muro_c":
			m.albedo_color = Color(0.42, 0.30, 0.18)
			m.roughness = 0.9
		"ventana":
			m.albedo_color = Color(1.0, 0.75, 0.40)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.62, 0.25)
			m.emission_energy_multiplier = 1.5
		"tela_roja":
			m.albedo_color = Color(0.48, 0.06, 0.09)
			m.roughness = 0.85
		"tela_oro":
			m.albedo_color = Color(0.78, 0.58, 0.22)
			m.roughness = 0.8
		_:
			m.albedo_color = Color(0.5, 0.5, 0.5)
			m.roughness = 0.9
	_mats[nombre] = m
	return m


## Caja mesh compartida (unidad) escalada por nodo: menos recursos.
func _caja(tam: Vector3, mat: Material, pos: Vector3, padre: Node3D) -> MeshInstance3D:
	if _caja_mesh == null:
		_caja_mesh = BoxMesh.new()
		_caja_mesh.size = Vector3.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = _caja_mesh
	mi.scale = tam
	mi.position = pos
	if mat != null:
		mi.material_override = mat
	padre.add_child(mi)
	return mi


## Cuerpo estatico en capa 1 con una caja de colision.
func _colision(padre: Node3D, tam: Vector3, centro: Vector3) -> StaticBody3D:
	var cuerpo := StaticBody3D.new()
	cuerpo.collision_layer = 1
	cuerpo.collision_mask = 0
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = tam
	forma.shape = caja
	forma.position = centro
	cuerpo.add_child(forma)
	padre.add_child(cuerpo)
	return cuerpo


## Tejado a dos aguas con cumbrera en Z (PrismMesh: cumbrera en Z, centrada).
func _tejado(w: float, rh: float, d: float, mat: Material, y_base: float,
		padre: Node3D) -> void:
	var tej := PrismMesh.new()
	tej.size = Vector3(w + 2.0, rh, d + 2.0)
	tej.left_to_right = 0.5
	var tmi := MeshInstance3D.new()
	tmi.mesh = tej
	tmi.material_override = mat
	tmi.position = Vector3(0.0, y_base + rh * 0.5 - 0.2, 0.0)
	padre.add_child(tmi)


## Estandarte: mastil + pano colgando ("oro" o "rojo").
func _estandarte_en(local: Vector3, color: String, padre: Node3D) -> void:
	var e := Node3D.new()
	e.position = local
	padre.add_child(e)
	_caja(Vector3(0.7, 9.0, 0.7), _mat("madera_oscura"), Vector3(0, 4.5, 0), e)
	_caja(Vector3(4.0, 0.5, 0.5), _mat("madera_oscura"), Vector3(1.6, 8.6, 0), e)
	var tela: String = "tela_oro" if color == "oro" else "tela_roja"
	_caja(Vector3(3.0, 5.5, 0.25), _mat(tela), Vector3(1.7, 5.6, 0), e)
	var pomo := SphereMesh.new()
	pomo.radius = 0.55
	pomo.height = 1.1
	var pmi := MeshInstance3D.new()
	pmi.mesh = pomo
	pmi.material_override = _mat("oro")
	pmi.position = Vector3(0, 9.2, 0)
	e.add_child(pmi)


# ---------------------------------------------------------------------------
# Plaza, calles, muralla
# ---------------------------------------------------------------------------

func _construir_plaza() -> void:
	var raiz := Node3D.new()
	raiz.name = "Plaza"
	var r: float = float(_datos.get("plaza_radio", 60.0))
	var h0: float = _altura(0.0, 0.0)
	var disco := CylinderMesh.new()
	disco.top_radius = r
	disco.bottom_radius = r
	disco.height = 0.6
	disco.radial_segments = 48
	var mi := MeshInstance3D.new()
	mi.mesh = disco
	mi.material_override = _mat("plaza")
	mi.position = Vector3(0, h0, 0)  # cara superior en h0 + 0.3
	raiz.add_child(mi)
	# Anillo dorado incrustado (simbolo lunar de la ciudad).
	var anillo := TorusMesh.new()
	anillo.inner_radius = r - 9.0
	anillo.outer_radius = r - 7.0
	anillo.rings = 64
	anillo.ring_segments = 8
	var ami := MeshInstance3D.new()
	ami.mesh = anillo
	ami.material_override = _mat("oro")
	ami.scale = Vector3(1, 0.25, 1)
	ami.position = Vector3(0, h0 + 0.32, 0)
	raiz.add_child(ami)
	add_child(raiz)
	alturas["Plaza"] = 0.6


func _construir_calles() -> void:
	var raiz := Node3D.new()
	raiz.name = "Calles"
	var r0: float = float(_datos.get("plaza_radio", 60.0)) - 5.0
	var r1: float = float(_datos.get("radio_muralla", 700.0)) - 5.0
	var largo: float = r1 - r0
	var medio: float = (r0 + r1) * 0.5
	for g in range(4):
		var ang: float = float(g) * PI * 0.5
		var dir := Vector3(sin(ang), 0, -cos(ang))
		var centro: Vector3 = dir * medio
		var h0: float = _altura(centro.x, centro.z)
		var mi := MeshInstance3D.new()
		if _caja_mesh == null:
			_caja_mesh = BoxMesh.new()
			_caja_mesh.size = Vector3.ONE
		mi.mesh = _caja_mesh
		mi.scale = Vector3(ANCHO_CALLE, 0.5, largo)
		mi.rotation.y = ang
		mi.position = Vector3(centro.x, h0 - 0.1, centro.z)  # cara sup. h0+0.15
		mi.material_override = _mat("calle")
		raiz.add_child(mi)
	add_child(raiz)
	alturas["Calles"] = 0.5


func _construir_muralla() -> void:
	var raiz := Node3D.new()
	raiz.name = "Muralla"
	var r: float = float(_datos.get("radio_muralla", 700.0))
	var h: float = 10.0
	var grueso: float = 6.0
	var abertura: float = 17.0 / r  # medio angulo de cada puerta
	var paso: float = 0.14
	var total: int = 0
	for g in range(4):
		var a0: float = float(g) * PI * 0.5 + abertura
		var a1: float = float(g + 1) * PI * 0.5 - abertura
		var n: int = maxi(1, int(ceil((a1 - a0) / paso)))
		for i in range(n):
			var tm: float = a0 + (float(i) + 0.5) * (a1 - a0) / float(n)
			var dt: float = (a1 - a0) / float(n)
			var largo: float = 2.0 * r * sin(dt * 0.5) + 0.8
			var px: float = r * sin(tm)
			var pz: float = -r * cos(tm)
			var seg := Node3D.new()
			seg.name = "Tramo_%d_%02d" % [g, i]
			seg.position = Vector3(px, _altura(px, pz), pz)
			seg.rotation.y = -tm
			_caja(Vector3(largo, h, grueso), _mat("piedra"), Vector3(0, h * 0.5, 0), seg)
			_caja(Vector3(largo, 1.2, grueso + 0.8), _mat("piedra_clara"),
				Vector3(0, h + 0.6, 0), seg)
			_colision(seg, Vector3(largo, h, grueso), Vector3(0, h * 0.5, 0))
			raiz.add_child(seg)
			total += 1
	add_child(raiz)
	alturas["Muralla"] = h + 1.2


# ---------------------------------------------------------------------------
# Edificios
# ---------------------------------------------------------------------------

## Casa procedural (3 variantes: a/b/c): muros, tejado a dos aguas, puerta,
## ventanas con luz calida. Frente en +Z.
func _casa(variante: String) -> Node3D:
	var raiz := Node3D.new()
	var w: float = 24.0
	var d: float = 20.0
	var mh: float = 10.0
	var rh: float = 6.0
	var muro: StandardMaterial3D = _mat("muro_a")
	var tej: StandardMaterial3D = _mat("tejado_pizarra")
	match variante:
		"b":
			w = 28.0
			d = 22.0
			mh = 12.0
			rh = 7.0
			muro = _mat("muro_b")
			tej = _mat("tejado_rojo")
		"c":
			w = 20.0
			d = 18.0
			mh = 9.0
			rh = 5.0
			muro = _mat("muro_c")
			tej = _mat("tejado_madera")
	_caja(Vector3(w + 0.6, 1.2, d + 0.6), _mat("piedra"), Vector3(0, 0.6, 0), raiz)
	_caja(Vector3(w, mh, d), muro, Vector3(0, mh * 0.5, 0), raiz)
	_tejado(w, rh, d, tej, mh, raiz)
	_caja(Vector3(4.0, 6.5, 0.6), _mat("puerta_madera"),
		Vector3(0, 3.25, d * 0.5 + 0.05), raiz)
	_caja(Vector3(5.0, 0.8, 0.8), _mat("oro"), Vector3(0, 7.0, d * 0.5 + 0.1), raiz)
	var vm: StandardMaterial3D = _mat("ventana")
	_caja(Vector3(3.0, 3.0, 0.5), vm, Vector3(-w * 0.28, 5.5, d * 0.5 + 0.05), raiz)
	_caja(Vector3(3.0, 3.0, 0.5), vm, Vector3(w * 0.28, 5.5, d * 0.5 + 0.05), raiz)
	_caja(Vector3(0.5, 3.0, 3.0), vm, Vector3(w * 0.5 + 0.05, 5.5, 0), raiz)
	_caja(Vector3(0.5, 3.0, 3.0), vm, Vector3(-w * 0.5 - 0.05, 5.5, 0), raiz)
	if variante != "c":
		_caja(Vector3(2.5, 7.0, 2.5), _mat("piedra"),
			Vector3(w * 0.28, mh + 2.0, -d * 0.22), raiz)
	_colision(raiz, Vector3(w, mh, d), Vector3(0, mh * 0.5, 0))
	raiz.set_meta("altura", mh + rh)
	return raiz


## Salon de Clases: edificio grande con puerta ancha.
## Guino a "Vuelve a Moon y Pide una Clase". Frente en +Z.
func _salon() -> Node3D:
	var raiz := Node3D.new()
	var w: float = 84.0
	var h: float = 22.0
	var d: float = 56.0
	_caja(Vector3(w, h, d), _mat("piedra_clara"), Vector3(0, h * 0.5, 0), raiz)
	for i in range(4):
		var cx: float = -30.0 + float(i) * 20.0
		_caja(Vector3(3.0, 18.0, 3.0), _mat("piedra"),
			Vector3(cx, 9.0, d * 0.5 + 6.0), raiz)
	_caja(Vector3(w * 0.9, 2.0, 12.0), _mat("piedra"),
		Vector3(0, 19.0, d * 0.5 + 6.0), raiz)
	_caja(Vector3(w + 2.0, 1.5, d + 2.0), _mat("oro"), Vector3(0, h + 0.75, 0), raiz)
	_caja(Vector3(16.0, 13.0, 0.8), _mat("puerta_madera"),
		Vector3(0, 6.5, d * 0.5 + 0.1), raiz)
	_caja(Vector3(18.0, 1.2, 1.0), _mat("oro"), Vector3(0, 13.8, d * 0.5 + 0.15), raiz)
	for i in range(5):
		var wx: float = -32.0 + float(i) * 16.0
		_caja(Vector3(4.0, 6.0, 0.6), _mat("ventana"),
			Vector3(wx, 12.0, d * 0.5 + 0.05), raiz)
	_estandarte_en(Vector3(-13.0, 0, d * 0.5 + 4.0), "oro", raiz)
	_estandarte_en(Vector3(13.0, 0, d * 0.5 + 4.0), "oro", raiz)
	_colision(raiz, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	_colision(raiz, Vector3(w * 0.9, 18.0, 12.0), Vector3(0, 9.0, d * 0.5 + 6.0))
	raiz.set_meta("altura", h + 1.5)
	return raiz


## Forja de Bram: chimenea y brasero exterior con antorcha real.
func _forja() -> Node3D:
	var raiz := Node3D.new()
	var w: float = 44.0
	var h: float = 14.0
	var d: float = 32.0
	_caja(Vector3(w, h, d), _mat("muro_b"), Vector3(0, h * 0.5, 0), raiz)
	_tejado(w, 7.0, d, _mat("tejado_madera"), h, raiz)
	_caja(Vector3(5.0, 14.0, 5.0), _mat("piedra"),
		Vector3(w * 0.3, h + 5.0, -d * 0.25), raiz)
	_caja(Vector3(6.5, 1.5, 6.5), _mat("piedra"),
		Vector3(w * 0.3, h + 12.0, -d * 0.25), raiz)
	_caja(Vector3(6.0, 8.0, 0.6), _mat("puerta_madera"),
		Vector3(0, 4.0, d * 0.5 + 0.05), raiz)
	_caja(Vector3(4.0, 4.0, 0.5), _mat("ventana"),
		Vector3(-w * 0.3, 7.0, d * 0.5 + 0.05), raiz)
	# Yunque junto a la puerta.
	_caja(Vector3(3.0, 2.0, 1.5), _mat("acero"), Vector3(8.0, 1.0, d * 0.5 + 3.0), raiz)
	# Brasero exterior: base de piedra + Antorcha reutilizada.
	var b := Node3D.new()
	b.position = Vector3(-w * 0.5 - 8.0, 0, d * 0.5 - 4.0)
	raiz.add_child(b)
	var copa := CylinderMesh.new()
	copa.top_radius = 3.0
	copa.bottom_radius = 1.8
	copa.height = 2.0
	var cmi := MeshInstance3D.new()
	cmi.mesh = copa
	cmi.material_override = _mat("piedra")
	cmi.position = Vector3(0, 1.0, 0)
	b.add_child(cmi)
	var ant := Antorcha.new()
	ant.ciclo = ciclo
	ant.position = Vector3(0, 3.4, 0)
	b.add_child(ant)
	_luces.append(ant)
	_colision(raiz, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	_colision(b, Vector3(4.0, 2.0, 4.0), Vector3(0, 1.0, 0))
	raiz.set_meta("altura", h + 12.75)
	return raiz


## Tienda/alquimia de Sira: toldo, cajones y barriles. Frente en +Z.
func _tienda() -> Node3D:
	var raiz := Node3D.new()
	var w: float = 38.0
	var h: float = 12.0
	var d: float = 30.0
	_caja(Vector3(w, h, d), _mat("muro_a"), Vector3(0, h * 0.5, 0), raiz)
	_tejado(w, 6.0, d, _mat("tejado_rojo"), h, raiz)
	# Toldo inclinado sobre el frente.
	var toldo := MeshInstance3D.new()
	if _caja_mesh == null:
		_caja_mesh = BoxMesh.new()
		_caja_mesh.size = Vector3.ONE
	toldo.mesh = _caja_mesh
	toldo.scale = Vector3(22.0, 0.6, 12.0)
	toldo.rotation.x = -0.35
	toldo.position = Vector3(0, 9.5, d * 0.5 + 5.0)
	toldo.material_override = _mat("tela_roja")
	raiz.add_child(toldo)
	_caja(Vector3(5.0, 7.0, 0.6), _mat("puerta_madera"),
		Vector3(-8.0, 3.5, d * 0.5 + 0.05), raiz)
	var vm: StandardMaterial3D = _mat("ventana")
	_caja(Vector3(3.5, 3.5, 0.5), vm, Vector3(8.0, 6.0, d * 0.5 + 0.05), raiz)
	_caja(Vector3(0.5, 3.5, 3.5), vm, Vector3(w * 0.5 + 0.05, 6.0, 0), raiz)
	# Mercancia fuera: cajones y barriles.
	_caja(Vector3(3.0, 3.0, 3.0), _mat("madera"), Vector3(-14.0, 1.5, d * 0.5 + 4.0), raiz)
	_caja(Vector3(2.5, 2.5, 2.5), _mat("madera"), Vector3(-11.0, 1.25, d * 0.5 + 5.0), raiz)
	for i in range(2):
		var barril := CylinderMesh.new()
		barril.top_radius = 2.0
		barril.bottom_radius = 2.0
		barril.height = 4.0
		var bmi := MeshInstance3D.new()
		bmi.mesh = barril
		bmi.material_override = _mat("madera_oscura")
		bmi.position = Vector3(13.0 + float(i) * 5.0, 2.0, d * 0.5 + 4.0)
		raiz.add_child(bmi)
	# Cartel dorado.
	_caja(Vector3(0.6, 7.0, 0.6), _mat("madera_oscura"), Vector3(0, 3.5, d * 0.5 + 8.0), raiz)
	_caja(Vector3(7.0, 3.0, 0.5), _mat("oro"), Vector3(0, 6.5, d * 0.5 + 8.0), raiz)
	_colision(raiz, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	raiz.set_meta("altura", h + 6.0)
	return raiz


## Cuartel de Ilya: torres y estandartes rojo sangre. Frente en +Z.
func _cuartel() -> Node3D:
	var raiz := Node3D.new()
	var w: float = 64.0
	var h: float = 20.0
	var d: float = 48.0
	_caja(Vector3(w, h, d), _mat("piedra"), Vector3(0, h * 0.5, 0), raiz)
	_caja(Vector3(w + 2.0, 1.5, d + 2.0), _mat("acero"), Vector3(0, h + 0.75, 0), raiz)
	for sx in [-1.0, 1.0]:
		var tx: float = (w * 0.5 - 5.0) * sx
		var tz: float = d * 0.5 - 5.0
		_caja(Vector3(10.0, 24.0, 10.0), _mat("piedra_clara"),
			Vector3(tx, 12.0, tz), raiz)
		_caja(Vector3(11.0, 1.5, 11.0), _mat("oro"), Vector3(tx, 24.75, tz), raiz)
		_colision(raiz, Vector3(10.0, 24.0, 10.0), Vector3(tx, 12.0, tz))
	_caja(Vector3(8.0, 10.0, 0.8), _mat("puerta_madera"),
		Vector3(0, 5.0, d * 0.5 + 0.1), raiz)
	_caja(Vector3(10.0, 1.2, 1.0), _mat("oro"), Vector3(0, 10.8, d * 0.5 + 0.15), raiz)
	for i in range(4):
		var wx: float = -24.0 + float(i) * 16.0
		_caja(Vector3(3.0, 4.0, 0.6), _mat("ventana"),
			Vector3(wx, 11.0, d * 0.5 + 0.05), raiz)
	for i in range(3):
		var bx: float = -20.0 + float(i) * 20.0
		_estandarte_en(Vector3(bx, 0, d * 0.5 + 5.0), "rojo", raiz)
	_colision(raiz, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	raiz.set_meta("altura", 25.5)
	return raiz


## Templo menor: columnas y cupula de bronce. Frente en +Z.
func _templo() -> Node3D:
	var raiz := Node3D.new()
	var w: float = 30.0
	var h: float = 16.0
	var d: float = 30.0
	_caja(Vector3(w + 4.0, 2.0, d + 4.0), _mat("piedra"), Vector3(0, 1.0, 0), raiz)
	_caja(Vector3(w, h, d), _mat("piedra_clara"), Vector3(0, h * 0.5 + 1.0, 0), raiz)
	for i in range(4):
		var cx: float = -10.5 + float(i) * 7.0
		_caja(Vector3(2.2, 14.0, 2.2), _mat("piedra"),
			Vector3(cx, 8.0, d * 0.5 + 4.0), raiz)
	_caja(Vector3(w * 0.8, 1.6, 8.0), _mat("piedra"),
		Vector3(0, 15.8, d * 0.5 + 4.0), raiz)
	var cupula := SphereMesh.new()
	cupula.radius = 10.0
	cupula.height = 20.0
	cupula.radial_segments = 24
	cupula.rings = 12
	var umi := MeshInstance3D.new()
	umi.mesh = cupula
	umi.scale = Vector3(1, 0.6, 1)
	umi.material_override = _mat("bronce")
	umi.position = Vector3(0, h + 1.0, 0)
	raiz.add_child(umi)
	_caja(Vector3(5.0, 8.0, 0.6), _mat("puerta_madera"),
		Vector3(0, 5.0, d * 0.5 + 0.05), raiz)
	_caja(Vector3(3.0, 5.0, 0.5), _mat("ventana"), Vector3(-9.0, 9.0, d * 0.5 + 0.05), raiz)
	_caja(Vector3(3.0, 5.0, 0.5), _mat("ventana"), Vector3(9.0, 9.0, d * 0.5 + 0.05), raiz)
	_estandarte_en(Vector3(-8.0, 0, d * 0.5 + 3.0), "oro", raiz)
	_estandarte_en(Vector3(8.0, 0, d * 0.5 + 3.0), "oro", raiz)
	_colision(raiz, Vector3(w, h + 1.0, d), Vector3(0, (h + 1.0) * 0.5, 0))
	raiz.set_meta("altura", h + 1.0 + 6.0)
	return raiz


## Monumento: pedestal escalonado + luna creciente dorada (simbolo de la ciudad).
func _monumento() -> Node3D:
	var raiz := Node3D.new()
	_caja(Vector3(16.0, 2.0, 16.0), _mat("piedra"), Vector3(0, 1.0, 0), raiz)
	_caja(Vector3(12.0, 3.0, 12.0), _mat("piedra_clara"), Vector3(0, 3.5, 0), raiz)
	_caja(Vector3(8.0, 5.0, 8.0), _mat("piedra"), Vector3(0, 7.5, 0), raiz)
	_caja(Vector3(9.0, 1.0, 9.0), _mat("oro"), Vector3(0, 10.5, 0), raiz)
	var comb := CSGCombiner3D.new()
	comb.position = Vector3(0, 19.0, 0)
	var luna := CSGSphere3D.new()
	luna.radius = 7.0
	luna.radial_segments = 32
	luna.rings = 16
	luna.material = _mat("oro")
	var sombra := CSGSphere3D.new()
	sombra.operation = CSGShape3D.OPERATION_SUBTRACTION
	sombra.radius = 6.0
	sombra.radial_segments = 32
	sombra.rings = 16
	sombra.position = Vector3(3.2, 1.6, 0)
	sombra.material = _mat("oro")
	comb.add_child(luna)
	comb.add_child(sombra)
	raiz.add_child(comb)
	# Luz calida que bana el monumento de noche.
	var halo := OmniLight3D.new()
	halo.light_color = Color(1.0, 0.75, 0.4)
	halo.light_energy = 1.2
	halo.omni_range = 30.0
	halo.shadow_enabled = false
	halo.position = Vector3(0, 19.0, 0)
	raiz.add_child(halo)
	_colision(raiz, Vector3(16.0, 12.0, 16.0), Vector3(0, 6.0, 0))
	raiz.set_meta("altura", 26.0)
	return raiz


## Puerta de la muralla (local: muralla en X, apertura al centro, exterior +Z).
func _puerta() -> Node3D:
	var raiz := Node3D.new()
	for sx in [-1.0, 1.0]:
		var px: float = 18.0 * sx
		_caja(Vector3(6.0, 14.0, 6.0), _mat("piedra"), Vector3(px, 7.0, 0), raiz)
		_colision(raiz, Vector3(6.0, 14.0, 6.0), Vector3(px, 7.0, 0))
		var tx: float = 30.0 * sx
		_caja(Vector3(10.0, 22.0, 10.0), _mat("piedra"), Vector3(tx, 11.0, 0), raiz)
		_caja(Vector3(11.0, 1.5, 11.0), _mat("oro"), Vector3(tx, 22.75, 0), raiz)
		_colision(raiz, Vector3(10.0, 22.0, 10.0), Vector3(tx, 11.0, 0))
		_estandarte_en(Vector3(tx, 0, 6.5), "oro", raiz)
	# Dintel alto: no bloquea el paso (apertura util de 30 u).
	_caja(Vector3(42.0, 4.0, 8.0), _mat("piedra_clara"), Vector3(0, 16.0, 0), raiz)
	_caja(Vector3(28.0, 3.0, 1.0), _mat("acero"), Vector3(0, 13.0, 0), raiz)
	raiz.set_meta("altura", 23.5)
	return raiz


# ---------------------------------------------------------------------------
# Antorchas y banderas
# ---------------------------------------------------------------------------

func _colocar_antorcha(x: float, z: float, padre: Node3D) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(x, _altura(x, z), z)
	holder.name = "Antorcha_%02d" % _n_antorchas
	var poste := CylinderMesh.new()
	poste.top_radius = 0.4
	poste.bottom_radius = 0.55
	poste.height = 5.0
	var pmi := MeshInstance3D.new()
	pmi.mesh = poste
	pmi.material_override = _mat("madera_oscura")
	pmi.position = Vector3(0, 2.5, 0)
	holder.add_child(pmi)
	var copa := CylinderMesh.new()
	copa.top_radius = 1.4
	copa.bottom_radius = 0.8
	copa.height = 1.0
	var cmi := MeshInstance3D.new()
	cmi.mesh = copa
	cmi.material_override = _mat("acero")
	cmi.position = Vector3(0, 5.2, 0)
	holder.add_child(cmi)
	var a := Antorcha.new()
	a.ciclo = ciclo
	a.position = Vector3(0, 6.0, 0)
	holder.add_child(a)
	_luces.append(a)
	padre.add_child(holder)
	_n_antorchas += 1
	alturas[str(holder.name)] = 6.5


func _construir_antorchas() -> void:
	var raiz := Node3D.new()
	raiz.name = "Antorchas"
	add_child(raiz)
	# Anillo de la plaza (entre las calles).
	for k in range(6):
		var ang: float = deg_to_rad(45.0 + float(k) * 60.0)
		_colocar_antorcha(50.0 * cos(ang), 50.0 * sin(ang), raiz)
	# Calles radiales: 5 por calle, lados alternos.
	var radios: Array = [150.0, 275.0, 400.0, 525.0, 650.0]
	for g in range(4):
		var ang: float = float(g) * PI * 0.5
		var dir := Vector3(sin(ang), 0, -cos(ang))
		var perp := Vector3(cos(ang), 0, sin(ang))
		for i in range(radios.size()):
			var r: float = radios[i]
			var lado: float = 1.0 if i % 2 == 0 else -1.0
			var p: Vector3 = dir * r + perp * (ANCHO_CALLE * 0.5 + 4.0) * lado
			_colocar_antorcha(p.x, p.z, raiz)
	# Puertas: una a cada lado de la apertura.
	var r_mur: float = float(_datos.get("radio_muralla", 700.0))
	_colocar_antorcha(24.0, -r_mur - 2.0, raiz)
	_colocar_antorcha(-24.0, -r_mur - 2.0, raiz)
	_colocar_antorcha(24.0, r_mur + 2.0, raiz)
	_colocar_antorcha(-24.0, r_mur + 2.0, raiz)
	_colocar_antorcha(r_mur + 2.0, 24.0, raiz)
	_colocar_antorcha(r_mur + 2.0, -24.0, raiz)
	_colocar_antorcha(-r_mur - 2.0, 24.0, raiz)
	_colocar_antorcha(-r_mur - 2.0, -24.0, raiz)
	# Frentes de edificios principales: se colocan con el transform del
	# edificio (robusto ante rotacion/posicion de datos).
	_antorcha_frente("salon_clases", Vector3(-14.0, 0, 36.0), raiz)
	_antorcha_frente("salon_clases", Vector3(14.0, 0, 36.0), raiz)
	_antorcha_frente("cuartel", Vector3(-20.0, 0, 30.0), raiz)
	_antorcha_frente("cuartel", Vector3(20.0, 0, 30.0), raiz)
	_antorcha_frente("templo", Vector3(-10.0, 0, 22.0), raiz)
	_antorcha_frente("templo", Vector3(10.0, 0, 22.0), raiz)
	_antorcha_frente("tienda", Vector3(19.0, 0, 20.0), raiz)


## Antorcha frente a un edificio de datos, en coordenadas locales de este.
func _antorcha_frente(tipo: String, local: Vector3, padre: Node3D) -> void:
	for b in edificios:
		if str((b as Node3D).name).ends_with("_" + tipo):
			var mundo: Vector3 = (b as Node3D).to_global(local)
			_colocar_antorcha(mundo.x, mundo.z, padre)
			return
	push_warning("[CiudadLuna] sin edificio para antorcha: %s" % tipo)


func _construir_banderas_puertas() -> void:
	# Estandartes monumentales junto a cada puerta (oro, 12 u).
	var raiz := Node3D.new()
	raiz.name = "BanderasPuertas"
	add_child(raiz)
	var r_mur: float = float(_datos.get("radio_muralla", 700.0))
	var sitios: Array = [
		Vector3(40.0, 0, -r_mur - 6.0), Vector3(-40.0, 0, -r_mur - 6.0),
		Vector3(40.0, 0, r_mur + 6.0), Vector3(-40.0, 0, r_mur + 6.0),
		Vector3(r_mur + 6.0, 0, 40.0), Vector3(r_mur + 6.0, 0, -40.0),
		Vector3(-r_mur - 6.0, 0, 40.0), Vector3(-r_mur - 6.0, 0, -40.0),
	]
	var n_ban: int = 0
	for s in sitios:
		var v: Vector3 = s
		var e := Node3D.new()
		e.position = Vector3(v.x, _altura(v.x, v.z), v.z)
		raiz.add_child(e)
		_caja(Vector3(1.0, 12.0, 1.0), _mat("madera_oscura"), Vector3(0, 6.0, 0), e)
		_caja(Vector3(5.0, 0.7, 0.7), _mat("madera_oscura"), Vector3(2.1, 11.4, 0), e)
		_caja(Vector3(4.0, 7.5, 0.3), _mat("tela_oro"), Vector3(2.2, 7.4, 0), e)
		alturas["BanderaPuerta_%d" % n_ban] = 12.0
		n_ban += 1
