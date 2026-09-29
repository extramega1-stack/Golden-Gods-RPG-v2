class_name CiudadLuna
extends Node3D
## Ciudad principal "Moon Town" reimaginada 2026 — Fase 14 (rework del mapa).
## Fase 15: generalizada para construir CUALQUIERA de las 9 ciudades
## (Moon Town + 8 secundarias). `centro` desplaza TODA la construccion
## (edificios, muralla, antorchas, banderas, NPCs, aparicion) y `cargar_datos`
## acepta cualquier JSON con el esquema de ciudad_luna.json (coordenadas
## RELATIVAS al centro). Con centro=(0,0) y data/ciudad_luna.json, Moon Town
## se construye EXACTAMENTE igual que en la fase 14.
##
## Data-driven: `data/ciudad_*.json` lista los edificios
## (tipo, x, z, rot, escala, variante). Anadir/mover un edificio = tocar datos.
## Este script solo sabe CONSTRUIR cada tipo de forma procedural y original
## (nada copiado de Blizzard): muros, tejados a dos aguas, puertas, ventanas
## con luz calida, muralla con 4 puertas, monumentos, etc.
##
## Direccion visual del proyecto: Lineage 2 + MU (metal oscuro acerado,
## dorado, gotico rojo sangre). Cada ciudad secundaria trae `_paleta` en su
## JSON (muros/techos/acentos/detalle en hex); sin `_paleta` se usan los
## materiales de Moon Town.
##
## La altura Y de TODO se consulta en runtime a `Terreno.altura_en(x, z)`:
## cada ciudad vive en su disco plano (r=800 Moon, r=700 las demas) que
## garantiza el worker de terreno; este script no hardcodea ninguna altura.
##
## Uso desde la demo:
##   var ciudad := CiudadLuna.new()
##   ciudad.terreno = terreno        # OBLIGATORIO antes de anadir al arbol
##   ciudad.ciclo = ciclo_dia        # opcional: modula las antorchas
##   ciudad.centro = Vector2(9966, 0)  # fase 15: ciudad secundaria
##   ciudad.luces_reales = false     # fase 15: antorchas sin OmniLight3D
##   ciudad.cargar_datos("res://data/ciudad_desert.json")
##   add_child(ciudad)               # _ready construye y emite ciudad_lista
##   var p: Vector3 = ciudad.punto_aparicion_jugador()
##   jugador.position = p
##   jugador.rotation.y = ciudad.yaw_aparicion()
##   npc_ilya.position = ciudad.npc_spawn("ilya")
##
## Reglas de diseno (spec fase 14/15):
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
## Fase 20 (P0-3): progreso de la construcción por partes (hechos, total).
signal progreso_ciudad(hechos: int, total: int)

## Terreno para consultar alturas. ASIGNAR ANTES de add_child.
var terreno: Terreno = null
## Ciclo dia/noche que modula el brillo de las antorchas (opcional).
var ciclo: CicloDia = null
## Fase 20 (P0-5): jugador de referencia para el culling de antorchas.
## Se propaga a las Antorcha reales vía `fijar_jugador()` (la demo lo llama
## al colocar; las construidas antes quedan cubiertas por el re-pase).
var jugador: Node3D = null
## Fase 15: centro del mundo de esta ciudad. Desplaza TODA la construccion
## (edificios, plaza, calles, muralla, antorchas, banderas, NPCs, aparicion).
## Las coordenadas del JSON son RELATIVAS a este centro. (0,0) = Moon Town.
var centro: Vector2 = Vector2.ZERO
## Fase 15: true = antorchas con OmniLight3D real (Moon Town, rendia bien);
## false = FalsaAntorcha (llama emissive sin luz dinamica) para las 8
## ciudades secundarias (~41 luces reales ahorradas por ciudad).
var luces_reales: bool = true

## Un nodo raiz por entrada de datos (en el mismo orden del JSON).
var edificios: Array[Node3D] = []
## id de NPC -> punto de aparicion (Vector3). La demo coloca los NPCs.
var puntos_npc: Dictionary = {}
## nombre de estructura -> altura total en u (para verificar ALTURA_MAX).
var alturas: Dictionary = {}

var _datos: Dictionary = {}
var _construida: bool = false
## Fase 69: la paleta de la ciudad ya NO es un `StandardMaterial3D` por rol
## sino la CRUD (superficie + tinte + multiplicadores) que resuelve
## `BibliotecaMateriales`. Vacía en Moon Town, que no trae `_paleta`.
var _pal: Dictionary = {}
## Fase 69: semilla de VARIACION del edificio que se esta construyendo. La
## pone `_colocar_edificio` con la posicion y la borra al terminar, asi solo
## los edificios varian: la muralla, la plaza y las antorchas van siempre en
## variante 0.
var _semilla: int = 0
var _caja_mesh: BoxMesh = null
## Fase 15: antorchas reales (Antorcha) o falsas (FalsaAntorcha).
var _luces: Array[Node3D] = []
var _n_antorchas: int = 0
## Fase 15: nodos que rotan lento (cristal del monumento mistico, etc.).
var _rotadores: Array[Node3D] = []
## Fase 20 (P0-3): construcción progresiva. `false` = todo en `_ready`
## (lo usan los tests). `true` = el `_ready` solo carga datos y encola
## pasos (plaza, calles, muralla, un paso por edificio, antorchas,
## banderas, npcs): `_process` ejecuta PASOS_POR_FRAME por frame emitiendo
## `progreso_ciudad` y `ciudad_lista` al terminar. La demo la activa antes
## del add_child (mismo contrato que `terreno`/`cargar_datos`).
@export var construccion_progresiva: bool = false
## Pasos de ciudad por frame en modo progresivo.
const PASOS_POR_FRAME: int = 3
## Cola de pasos pendientes (Array[Callable] sin argumentos).
var _cola_pasos: Array = []
var _pasos_hechos: int = 0
var _pasos_total: int = 0


## Fase 69: ya se horneó el set de texturas del mundo. Es idempotente y lo
## paga UNA vez por proceso, en la carga, no en el primer edificio (que en
## modo progresivo cae dentro de un `_process` y sería un tiron de frame).
static var _materiales_hornearon: bool = false

static func _hornear_materials() -> void:
	if _materiales_hornearon:
		return
	_materiales_hornearon = true
	BibliotecaMateriales.precalentar()


func _ready() -> void:
	_hornear_materials()
	if _datos.is_empty():
		if not cargar_datos(RUTA_DATOS):
			push_warning("[CiudadLuna] no se pudo cargar %s" % RUTA_DATOS)
	if construccion_progresiva:
		_iniciar_cola()
		return
	construir()
	ciudad_lista.emit()


## Fase 15: giro lento de los monumentos animados (cristal arcano, ...).
## Fase 20: en modo progresivo primero vacía la cola de construcción y
## después (o en modo síncrono con rotadores) gira los monumentos.
## Sin cola ni rotadores el proceso se desactiva.
func _process(delta: float) -> void:
	if not _cola_pasos.is_empty():
		avanzar_construccion(PASOS_POR_FRAME)
		return
	for r in _rotadores:
		if is_instance_valid(r):
			r.rotation.y += delta * 0.35


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
	_aplicar_paleta()  # fase 15: materiales de la ciudad (si el JSON trae _paleta)
	_construir_plaza()
	_construir_calles()
	_construir_muralla()
	var lista: Array = _datos.get("edificios", [])
	var idx: int = 0
	for e in lista:
		if not (e is Dictionary):
			continue
		idx = _colocar_edificio(e as Dictionary, idx)
	_construir_antorchas()
	_construir_banderas_puertas()
	_cargar_npcs()
	# Sin monumentos animados no hace falta _process (caso Moon Town).
	set_process(not _rotadores.is_empty())


## Coloca un edificio del JSON (extraído del loop de construir para
## reutilizarlo como paso progresivo). Retorna el siguiente índice.
func _colocar_edificio(d: Dictionary, idx: int) -> int:
	var tipo: String = str(d.get("tipo", ""))
	var x: float = float(d.get("x", 0.0))
	var z: float = float(d.get("z", 0.0))
	var rot: float = float(d.get("rot", 0.0))
	var escala: float = float(d.get("escala", 1.0))
	var variante: String = str(d.get("variante", ""))
	# Fase 15: las x/z del JSON son relativas a `centro`.
	var wx: float = x + centro.x
	var wz: float = z + centro.y
	# Fase 69: la semilla de VARIACION sale de la POSICION, no de un
	# contador. Es lo que garantiza que un barrio de 20 casas no sea 20 copias
	# y que un save reconstruya el mundo con el mismo grano.
	_semilla = BibliotecaMateriales.semilla_de(wx, wz)
	var raiz: Node3D = _construir_edificio(tipo, variante)
	_semilla = 0
	if raiz == null:
		push_warning("[CiudadLuna] tipo desconocido: %s" % tipo)
		return idx
	raiz.position = Vector3(wx, _altura(wx, wz), wz)
	raiz.rotation.y = rot
	raiz.scale = Vector3.ONE * escala
	raiz.name = "Edificio_%02d_%s" % [idx, tipo]
	add_child(raiz)
	edificios.append(raiz)
	var h_local: float = float(raiz.get_meta("altura", 0.0))
	alturas[str(raiz.name)] = h_local * escala
	return idx + 1


## Encola los pasos de construcción (modo progresivo). El orden es el
## mismo que construir(): paleta, plaza, calles, muralla, un paso por
## edificio, antorchas, banderas, npcs.
func _iniciar_cola() -> void:
	_cola_pasos.clear()
	_cola_pasos.append(_aplicar_paleta)
	_cola_pasos.append(_construir_plaza)
	_cola_pasos.append(_construir_calles)
	_cola_pasos.append(_construir_muralla)
	var lista: Array = _datos.get("edificios", [])
	var idx: int = 0
	for e in lista:
		if not (e is Dictionary):
			continue
		_cola_pasos.append(_colocar_edificio.bind(e as Dictionary, idx))
		idx += 1
	_cola_pasos.append(_construir_antorchas)
	_cola_pasos.append(_construir_banderas_puertas)
	_cola_pasos.append(_cargar_npcs)
	_pasos_hechos = 0
	_pasos_total = _cola_pasos.size()
	set_process(true)


## Ejecuta hasta `max_pasos` pendientes; emite progreso y, al vaciar la
## cola, finaliza como construir() (rotadores, `_construida`,
## `ciudad_lista`). Pública/testeable. Retorna true si ya terminó todo.
func avanzar_construccion(max_pasos: int) -> bool:
	if _cola_pasos.is_empty():
		return true
	var n: int = mini(maxi(max_pasos, 1), _cola_pasos.size())
	for i in range(n):
		var paso: Callable = _cola_pasos.pop_front()
		paso.call()
		_pasos_hechos += 1
	progreso_ciudad.emit(_pasos_hechos, _pasos_total)
	if _cola_pasos.is_empty():
		_construida = true
		# Sin monumentos animados no hace falta _process (caso Moon Town).
		set_process(not _rotadores.is_empty())
		ciudad_lista.emit()
		return true
	return false


## ¿Terminó la construcción? En modo síncrono es true tras _ready.
func construccion_terminada() -> bool:
	if not construccion_progresiva:
		return _construida
	return _construida and _cola_pasos.is_empty()


## Fracción 0..1 construida (para la pantalla de carga).
func fraccion_construccion() -> float:
	if not construccion_progresiva:
		return 1.0
	if _pasos_total <= 0:
		return 0.0
	return float(_pasos_hechos) / float(_pasos_total)


## Punto de aparicion del jugador: centro de la plaza, sobre el terreno.
## Fase 15: las x/z del JSON son relativas a `centro`.
func punto_aparicion_jugador() -> Vector3:
	var ap: Dictionary = _datos.get("aparicion_jugador", {})
	var x: float = float(ap.get("x", 0.0)) + centro.x
	var z: float = float(ap.get("z", 45.0)) + centro.y
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


## Fija (o cambia) el ciclo dia/noche y lo propaga a las antorchas
## (reales o falsas, fase 15).
func fijar_ciclo(c: CicloDia) -> void:
	ciclo = c
	for a in _luces:
		if a is Antorcha:
			(a as Antorcha).ciclo = c
		elif a is FalsaAntorcha:
			(a as FalsaAntorcha).ciclo = c


## Fija (o cambia) el jugador de referencia y lo propaga a las antorchas
## reales para el culling por distancia (fase 20, P0-5). Cubre las ya
## construidas y las futuras (vía `_colocar_antorcha`).
func fijar_jugador(j: Node3D) -> void:
	jugador = j
	for a in _luces:
		if a is Antorcha:
			(a as Antorcha).jugador = j


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
		# Fase 15: x/z relativas a `centro` -> puntos en coordenadas de mundo.
		var x: float = float(dd.get("x", 0.0)) + centro.x
		var z: float = float(dd.get("z", 0.0)) + centro.y
		puntos_npc[str(id)] = Vector3(x, _altura(x, z), z)


func _construir_edificio(tipo: String, variante: String) -> Node3D:
	match tipo:
		"casa":
			return _casa(variante)
		"salon_clases":
			return _salon(variante)
		"forja":
			return _forja(variante)
		"tienda":
			return _tienda(variante)
		"cuartel":
			return _cuartel(variante)
		"templo":
			return _templo(variante)
		"monumento":
			return _monumento(variante)
		"puerta":
			return _puerta(variante)
	return null


# ---------------------------------------------------------------------------
# Paleta por ciudad (fase 15)
# ---------------------------------------------------------------------------

## ¿El JSON trae `_paleta`? Las 8 ciudades secundarias si; Moon Town no.
func _tiene_paleta() -> bool:
	var pal: Variant = _datos.get("_paleta", {})
	return pal is Dictionary and not (pal as Dictionary).is_empty()


func _aplicar_paleta() -> void:
	_pal.clear()
	var pal: Dictionary = _datos.get("_paleta", {})
	if pal.is_empty():
		return
	# `_pal` mapea "pal_muro" -> {superficie, tinte, rel...}. Ya NO es un
	# StandardMaterial3D: es la CRUD de la Biblioteca, que es donde viven las
	# texturas. El nombre sigue siendo "pal_muro" para que los 147 `_mat(...)`
	# del archivo no cambien y `_mx()` siga siendo un alias.
	for clave in MaterialesDB.paleta_claves():
		if not pal.has(clave):
			continue
		var base: Dictionary = MaterialesDB.paleta_rol(clave)
		_pal[str(base.get("material", "pal_" + clave))] = {
			"superficie": str(base.get("superficie", "piedra")),
			"tinte": str(pal[clave]),
			"variar": bool(base.get("variar", false)),
			"rugosidad_rel": float(base.get("rugosidad_rel", 1.0)),
			"metalicidad_rel": float(base.get("metalicidad_rel", 0.0)),
		}
	# El 5o color varia por ciudad: toldos/braseros/cristales/estandartes/
	# empalizadas/velas/dorado. Cada uno es una superficie DISTINTA (el dorado
	# de Golden Tower es metal y su brasero tambien; un toldo es tela), asi
	# que se resuelve por la clave que la ciudad uso. Sin ninguna de esas
	# claves, `pal_extra` se queda con el rol generico y blanco.
	var clave_extra: String = ""
	for cand in MaterialesDB.CANDIDATOS_EXTRA:
		if pal.has(cand):
			clave_extra = cand
			break
	var ex: Dictionary = MaterialesDB.paleta_extra(clave_extra)
	_pal[str(ex.get("material", "pal_extra"))] = {
		"superficie": str(ex.get("superficie", "piedra")),
		"tinte": str(pal.get(clave_extra, "#ffffff")),
		"variar": false,
		"rugosidad_rel": float(ex.get("rugosidad_rel", 0.95)),
		"metalicidad_rel": float(ex.get("metalicidad_rel", 0.0)),
	}


## Nombre de material para un rol: paleta de la ciudad si existe,
## material original de Moon Town si no. Garantiza Moon Town identica.
func _mx(rol: String, defecto: String) -> String:
	if not _tiene_paleta():
		return defecto
	match rol:
		"muro":
			return "pal_muro"
		"techo":
			return "pal_techo"
		"acento":
			return "pal_acento"
		"detalle":
			return "pal_detalle"
		"extra":
			return "pal_extra"
	return defecto


## El material de un ROL. NO lleva ningun color: el rol se busca en
## `data/materiales.json`, y de ahi sale la superficie (y con ella las
## texturas PBR), el tinte y la rugosidad. Moon Town no trae `_paleta`, asi
## que sus muros son los roles `muro_a`/`muro_b`/`muro_c` del catalogo, igual
## que antes: lo unico que cambio es de donde salen los numeros.
##
## La VARIACION sale de `_semilla`, que `_colocar_edificio` fija con la
## posicion del edificio. Fuera de un edificio (plaza, calles, muralla,
## antorchas) `_semilla` es 0 y todo va en variante 0: una muralla que
## cambiara de tono cada 6 m seria peor que una muralla lisa.
func _mat(nombre: String) -> StandardMaterial3D:
	if _pal.has(nombre):
		var p: Dictionary = _pal[nombre]
		return BibliotecaMateriales.material(str(p.get("superficie", "piedra")),
			str(p.get("tinte", "#808080")), _semilla, bool(p.get("variar", false)),
			float(p.get("rugosidad_rel", 1.0)),
			float(p.get("metalicidad_rel", 0.0)))
	if not MaterialesDB.rol_existe(nombre):
		push_warning("[CiudadLuna] rol sin declarar en materiales.json: " + nombre)
		return BibliotecaMateriales.material("piedra", "#808080", 0, false)
	return BibliotecaMateriales.de_rol(MaterialesDB.rol(nombre), _semilla)


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


## Estandarte: mastil + pano colgando ("oro", "rojo" o "sombra" fase 15).
func _estandarte_en(local: Vector3, color: String, padre: Node3D) -> void:
	var e := Node3D.new()
	e.position = local
	padre.add_child(e)
	_caja(Vector3(0.7, 9.0, 0.7), _mat("madera_oscura"), Vector3(0, 4.5, 0), e)
	_caja(Vector3(4.0, 0.5, 0.5), _mat("madera_oscura"), Vector3(1.6, 8.6, 0), e)
	var tela: String = "tela_oro" if color == "oro" else "tela_roja"
	if color == "sombra":
		tela = "tela_sombra"
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
	# Fase 15: raiz desplazada a `centro`; el interior queda en local
	# (con centro=(0,0) es identico a la fase 14).
	raiz.position = Vector3(centro.x, 0.0, centro.y)
	var r: float = float(_datos.get("plaza_radio", 60.0))
	var h0: float = _altura(centro.x, centro.y)
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
	raiz.position = Vector3(centro.x, 0.0, centro.y)
	var r0: float = float(_datos.get("plaza_radio", 60.0)) - 5.0
	var r1: float = float(_datos.get("radio_muralla", 700.0)) - 5.0
	var largo: float = r1 - r0
	var medio: float = (r0 + r1) * 0.5
	for g in range(4):
		var ang: float = float(g) * PI * 0.5
		var dir := Vector3(sin(ang), 0, -cos(ang))
		var centro_calle: Vector3 = dir * medio
		var h0: float = _altura(centro.x + centro_calle.x, centro.y + centro_calle.z)
		var mi := MeshInstance3D.new()
		if _caja_mesh == null:
			_caja_mesh = BoxMesh.new()
			_caja_mesh.size = Vector3.ONE
		mi.mesh = _caja_mesh
		mi.scale = Vector3(ANCHO_CALLE, 0.5, largo)
		mi.rotation.y = ang
		mi.position = Vector3(centro_calle.x, h0 - 0.1, centro_calle.z)  # cara sup. h0+0.15
		mi.material_override = _mat("calle")
		raiz.add_child(mi)
	add_child(raiz)
	alturas["Calles"] = 0.5


func _construir_muralla() -> void:
	var raiz := Node3D.new()
	raiz.name = "Muralla"
	raiz.position = Vector3(centro.x, 0.0, centro.y)
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
			seg.position = Vector3(px, _altura(centro.x + px, centro.y + pz), pz)
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

## Casa procedural: despacha a la clasica (a/b/c, Moon Town) o a la
## tematica de fase 15 (paleta de la ciudad + decoracion regional).
func _casa(variante: String) -> Node3D:
	match variante:
		"a", "b", "c":
			return _casa_clasica(variante)
		"desierto_a", "desierto_b", "volcan_a", "volcan_b", \
		"nortena_a", "nortena_b", "mistica_a", "mistica_b", \
		"sombria_a", "sombria_b", "empalizada_a", "empalizada_b", \
		"puerto_a", "puerto_b", "dorada_a", "dorada_b":
			var tam: String = "b" if variante.ends_with("_b") else "a"
			return _casa_tematica(variante, tam)
	# Variante desconocida: como la "a" (comportamiento historico).
	return _casa_clasica(variante)


## Toldo rectangular inclinado (fase 15: desierto, mercados).
func _toldo(padre: Node3D, pos: Vector3, ancho: float, prof: float, mat: String) -> void:
	var t := MeshInstance3D.new()
	if _caja_mesh == null:
		_caja_mesh = BoxMesh.new()
		_caja_mesh.size = Vector3.ONE
	t.mesh = _caja_mesh
	t.scale = Vector3(ancho, 0.6, prof)
	t.rotation.x = -0.35
	t.position = pos
	t.material_override = _mat(mat)
	padre.add_child(t)


## Casa tematica fase 15: misma planta que la clasica, paleta de la ciudad
## (`_mx`) + un extra regional por variante. Nada supera 19 u.
func _casa_tematica(variante: String, tam: String) -> Node3D:
	var raiz := Node3D.new()
	var w: float = 24.0
	var d: float = 20.0
	var mh: float = 10.0
	var rh: float = 6.0
	if tam == "b":
		w = 28.0
		d = 22.0
		mh = 12.0
		rh = 7.0
	var m_muro: String = _mx("muro", "muro_a")
	var m_techo: String = _mx("techo", "tejado_pizarra")
	_caja(Vector3(w + 0.6, 1.2, d + 0.6), _mat("piedra"), Vector3(0, 0.6, 0), raiz)
	_caja(Vector3(w, mh, d), _mat(m_muro), Vector3(0, mh * 0.5, 0), raiz)
	_tejado(w, rh, d, _mat(m_techo), mh, raiz)
	_caja(Vector3(4.0, 6.5, 0.6), _mat("puerta_madera"),
		Vector3(0, 3.25, d * 0.5 + 0.05), raiz)
	_caja(Vector3(5.0, 0.8, 0.8), _mat("oro"), Vector3(0, 7.0, d * 0.5 + 0.1), raiz)
	var vm: StandardMaterial3D = _mat("ventana")
	_caja(Vector3(3.0, 3.0, 0.5), vm, Vector3(-w * 0.28, 5.5, d * 0.5 + 0.05), raiz)
	_caja(Vector3(3.0, 3.0, 0.5), vm, Vector3(w * 0.28, 5.5, d * 0.5 + 0.05), raiz)
	match variante:
		"desierto_a", "desierto_b":
			# Toldo de colores sobre el frente + tinaja de barro.
			_toldo(raiz, Vector3(0, 9.0, d * 0.5 + 5.0), 16.0, 10.0, _mx("extra", "tela_roja"))
			var tin := CylinderMesh.new()
			tin.top_radius = 1.6
			tin.bottom_radius = 1.2
			tin.height = 3.0
			var tmi := MeshInstance3D.new()
			tmi.mesh = tin
			tmi.material_override = _mat(_mx("acento", "muro_b"))
			tmi.position = Vector3(w * 0.35, 1.5, d * 0.5 + 3.0)
			raiz.add_child(tmi)
		"volcan_a", "volcan_b":
			# Grietas de lava al pie del muro.
			for i in range(3):
				_caja(Vector3(4.0, 0.4, 0.8), _mat("lava"),
					Vector3(-w * 0.3 + float(i) * w * 0.3, 0.4, d * 0.5 + 0.6), raiz)
		"nortena_a", "nortena_b":
			# Capa de nieve sobre el tejado + lena apilada.
			_tejado(w + 1.0, rh * 0.45, d + 1.0, _mat("nieve"), mh + rh * 0.55, raiz)
			for i in range(3):
				_caja(Vector3(1.2, 1.2, 6.0), _mat("madera_oscura"),
					Vector3(-w * 0.5 - 2.0, 0.6 + float(i) * 1.2, d * 0.3), raiz)
		"mistica_a", "mistica_b":
			# Cristales arcanos junto a la puerta.
			for i in range(2):
				_caja(Vector3(1.2, 3.0 + float(i), 1.2), _mat("cristal_arcano"),
					Vector3(5.0 + float(i) * 2.5, 1.5 + float(i) * 0.5, d * 0.5 + 2.5), raiz)
		"sombria_a", "sombria_b":
			# Estandarte oscuro junto a la puerta.
			_estandarte_en(Vector3(-6.0, 0, d * 0.5 + 3.0), "sombra", raiz)
		"empalizada_a", "empalizada_b":
			# Postes de empalizada alrededor del muro.
			var n: int = 7
			for i in range(n):
				var fx: float = -w * 0.5 + float(i) * w / float(n - 1)
				_caja(Vector3(1.4, mh + 2.0, 1.4), _mat(_mx("extra", "madera_oscura")),
					Vector3(fx, (mh + 2.0) * 0.5, d * 0.5 + 0.9), raiz)
				_caja(Vector3(1.4, mh + 2.0, 1.4), _mat(_mx("extra", "madera_oscura")),
					Vector3(fx, (mh + 2.0) * 0.5, -d * 0.5 - 0.9), raiz)
		"puerto_a", "puerto_b":
			# Rollo de cuerda + barril de puerto.
			var aro := TorusMesh.new()
			aro.inner_radius = 1.2
			aro.outer_radius = 2.0
			aro.rings = 16
			aro.ring_segments = 8
			var ami := MeshInstance3D.new()
			ami.mesh = aro
			ami.material_override = _mat(_mx("detalle", "madera"))
			ami.position = Vector3(-w * 0.35, 1.0, d * 0.5 + 3.0)
			raiz.add_child(ami)
			var barril := CylinderMesh.new()
			barril.top_radius = 2.0
			barril.bottom_radius = 2.0
			barril.height = 4.0
			var bmi := MeshInstance3D.new()
			bmi.mesh = barril
			bmi.material_override = _mat("madera_oscura")
			bmi.position = Vector3(w * 0.35, 2.0, d * 0.5 + 3.0)
			raiz.add_child(bmi)
		"dorada_a", "dorada_b":
			# Esquinas doradas + dintel ancho de oro.
			for sx in [-1.0, 1.0]:
				_caja(Vector3(1.2, mh, 1.2), _mat("oro"),
					Vector3(sx * (w * 0.5 - 0.6), mh * 0.5, d * 0.5 - 0.6), raiz)
	_colision(raiz, Vector3(w, mh, d), Vector3(0, mh * 0.5, 0))
	raiz.set_meta("altura", mh + rh + 2.0)
	return raiz


## Casa clasica de Moon Town (variantes a/b/c). VERBATIM fase 14.
func _casa_clasica(variante: String) -> Node3D:
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
## Fase 15: `variante` re-paleta (via `_mx`) + decorado regional.
func _salon(variante: String) -> Node3D:
	var raiz := Node3D.new()
	var w: float = 84.0
	var h: float = 22.0
	var d: float = 56.0
	var m_muro: String = _mx("muro", "piedra_clara")
	var m_piedra: String = _mx("detalle", "piedra")
	var m_oro: String = _mx("acento", "oro")
	_caja(Vector3(w, h, d), _mat(m_muro), Vector3(0, h * 0.5, 0), raiz)
	for i in range(4):
		var cx: float = -30.0 + float(i) * 20.0
		_caja(Vector3(3.0, 18.0, 3.0), _mat(m_piedra),
			Vector3(cx, 9.0, d * 0.5 + 6.0), raiz)
	_caja(Vector3(w * 0.9, 2.0, 12.0), _mat(m_piedra),
		Vector3(0, 19.0, d * 0.5 + 6.0), raiz)
	_caja(Vector3(w + 2.0, 1.5, d + 2.0), _mat(m_oro), Vector3(0, h + 0.75, 0), raiz)
	_caja(Vector3(16.0, 13.0, 0.8), _mat("puerta_madera"),
		Vector3(0, 6.5, d * 0.5 + 0.1), raiz)
	_caja(Vector3(18.0, 1.2, 1.0), _mat(m_oro), Vector3(0, 13.8, d * 0.5 + 0.15), raiz)
	for i in range(5):
		var wx: float = -32.0 + float(i) * 16.0
		_caja(Vector3(4.0, 6.0, 0.6), _mat("ventana"),
			Vector3(wx, 12.0, d * 0.5 + 0.05), raiz)
	_estandarte_en(Vector3(-13.0, 0, d * 0.5 + 4.0), "oro", raiz)
	_estandarte_en(Vector3(13.0, 0, d * 0.5 + 4.0), "oro", raiz)
	var h_extra: float = 0.0
	match variante:
		"arcana":
			# Cristales arcanos flotando en las esquinas (bajo las 28 u
			# aun con la escala 1.1 de su JSON).
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_caja(Vector3(1.5, 4.0, 1.5), _mat("cristal_arcano"),
						Vector3(sx * (w * 0.5 + 4.0), h + 0.5, sz * (d * 0.5 + 4.0)), raiz)
			h_extra = 1.0
		"aureo":
			# Soles dorados sobre la cornisa.
			for i in range(3):
				var sol := CylinderMesh.new()
				sol.top_radius = 2.5
				sol.bottom_radius = 2.5
				sol.height = 0.8
				var smi := MeshInstance3D.new()
				smi.mesh = sol
				smi.material_override = _mat("oro")
				smi.rotation.x = PI * 0.5
				smi.position = Vector3(-20.0 + float(i) * 20.0, h + 2.5, d * 0.5 + 1.0)
				raiz.add_child(smi)
			h_extra = 3.5
		"norte":
			# Nieve sobre la cubierta.
			_caja(Vector3(w + 3.0, 1.0, d + 3.0), _mat("nieve"),
				Vector3(0, h + 1.7, 0), raiz)
			h_extra = 2.2
	_colision(raiz, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	_colision(raiz, Vector3(w * 0.9, 18.0, 12.0), Vector3(0, 9.0, d * 0.5 + 6.0))
	raiz.set_meta("altura", h + 1.5 + h_extra)
	return raiz


## Forja de Bram: chimenea y brasero exterior con antorcha.
## Fase 15: `variante` re-paleta + decorado; el brasero usa FalsaAntorcha
## cuando `luces_reales` es false (ciudades secundarias).
func _forja(variante: String) -> Node3D:
	var raiz := Node3D.new()
	var w: float = 44.0
	var h: float = 14.0
	var d: float = 32.0
	var m_muro: String = _mx("muro", "muro_b")
	var m_techo: String = _mx("techo", "tejado_madera")
	var m_piedra: String = _mx("detalle", "piedra")
	_caja(Vector3(w, h, d), _mat(m_muro), Vector3(0, h * 0.5, 0), raiz)
	_tejado(w, 7.0, d, _mat(m_techo), h, raiz)
	# Fase 15: la forja volcanica (escala 1.15 en su JSON) usa chimenea
	# corta para no superar las 28 u reales.
	var chim_h: float = 14.0
	if variante == "volcanica":
		chim_h = 9.0
	_caja(Vector3(5.0, chim_h, 5.0), _mat(m_piedra),
		Vector3(w * 0.3, h + chim_h * 0.5 - 2.0, -d * 0.25), raiz)
	_caja(Vector3(6.5, 1.5, 6.5), _mat(m_piedra),
		Vector3(w * 0.3, h + chim_h - 2.0, -d * 0.25), raiz)
	_caja(Vector3(6.0, 8.0, 0.6), _mat("puerta_madera"),
		Vector3(0, 4.0, d * 0.5 + 0.05), raiz)
	_caja(Vector3(4.0, 4.0, 0.5), _mat("ventana"),
		Vector3(-w * 0.3, 7.0, d * 0.5 + 0.05), raiz)
	# Yunque junto a la puerta.
	_caja(Vector3(3.0, 2.0, 1.5), _mat("acero"), Vector3(8.0, 1.0, d * 0.5 + 3.0), raiz)
	# Brasero exterior: base de piedra + antorcha (real o falsa).
	var b := Node3D.new()
	b.position = Vector3(-w * 0.5 - 8.0, 0, d * 0.5 - 4.0)
	raiz.add_child(b)
	var copa := CylinderMesh.new()
	copa.top_radius = 3.0
	copa.bottom_radius = 1.8
	copa.height = 2.0
	var cmi := MeshInstance3D.new()
	cmi.mesh = copa
	cmi.material_override = _mat(m_piedra)
	cmi.position = Vector3(0, 1.0, 0)
	b.add_child(cmi)
	var brasa: Node3D
	if luces_reales:
		var real := Antorcha.new()
		real.ciclo = ciclo
		brasa = real
	else:
		var falsa := FalsaAntorcha.new()
		falsa.ciclo = ciclo
		brasa = falsa
	brasa.position = Vector3(0, 3.4, 0)
	b.add_child(brasa)
	_luces.append(brasa)
	var h_extra: float = 0.0
	match variante:
		"fragua_sol", "solar":
			# Disco solar sobre la puerta (queda bajo la chimenea).
			_sol_dorado_en(raiz, Vector3(0, 12.0, d * 0.5 + 0.6), 3.5)
		"volcanica":
			# Grietas de lava en el muro frontal.
			for i in range(3):
				_caja(Vector3(0.6, 6.0, 0.6), _mat("lava"),
					Vector3(-12.0 + float(i) * 12.0, 4.0, d * 0.5 + 0.3), raiz)
		"runica":
			# Runas brillantes en el dintel.
			for i in range(4):
				_caja(Vector3(1.0, 2.0, 0.4), _mat("cristal_arcano"),
					Vector3(-9.0 + float(i) * 6.0, 10.5, d * 0.5 + 0.3), raiz)
		"sombra":
			# Acentos violaceos sombrios.
			for i in range(2):
				_caja(Vector3(1.0, 5.0, 0.4), _mat("cristal_arcano"),
					Vector3(-6.0 + float(i) * 12.0, 3.5, d * 0.5 + 0.3), raiz)
		"guerra":
			# Colmillos cruzados sobre la puerta (bajo la chimenea).
			_colmillo_en(raiz, Vector3(-3.0, 11.0, d * 0.5 + 0.5), 0.5)
			_colmillo_en(raiz, Vector3(3.0, 11.0, d * 0.5 + 0.5), -0.5)
	_colision(raiz, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	_colision(b, Vector3(4.0, 2.0, 4.0), Vector3(0, 1.0, 0))
	# La cima real es la chimenea (clasica 26.75, volcanica 21.75); el disco
	# solar y los colmillos quedan por debajo.
	raiz.set_meta("altura", h + chim_h - 2.0 + 0.75 + h_extra)
	return raiz


## Disco solar dorado (fase 15): decoracion para fraguas/templos del sol.
func _sol_dorado_en(padre: Node3D, pos: Vector3, radio: float) -> void:
	var disco := CylinderMesh.new()
	disco.top_radius = radio
	disco.bottom_radius = radio
	disco.height = 0.8
	disco.radial_segments = 24
	var dmi := MeshInstance3D.new()
	dmi.mesh = disco
	dmi.material_override = _mat("oro")
	dmi.rotation.x = PI * 0.5
	dmi.position = pos
	padre.add_child(dmi)


## Colmillo/trofeo de hueso inclinado (fase 15): decoracion de guerra.
func _colmillo_en(padre: Node3D, pos: Vector3, inclinacion: float) -> void:
	var cono := CylinderMesh.new()
	cono.top_radius = 0.15
	cono.bottom_radius = 0.9
	cono.height = 5.0
	cono.radial_segments = 8
	var cmi := MeshInstance3D.new()
	cmi.mesh = cono
	cmi.material_override = _mat("hueso")
	cmi.rotation.z = inclinacion
	cmi.position = pos
	padre.add_child(cmi)


## Tienda/alquimia de Sira: toldo, cajones y barriles. Frente en +Z.
## Fase 15: `variante` re-paleta + decorado de mercado regional.
func _tienda(variante: String) -> Node3D:
	var raiz := Node3D.new()
	var w: float = 38.0
	var h: float = 12.0
	var d: float = 30.0
	var m_muro: String = _mx("muro", "muro_a")
	var m_techo: String = _mx("techo", "tejado_rojo")
	var m_toldo: String = _mx("extra", "tela_roja")
	_caja(Vector3(w, h, d), _mat(m_muro), Vector3(0, h * 0.5, 0), raiz)
	_tejado(w, 6.0, d, _mat(m_techo), h, raiz)
	# Toldo inclinado sobre el frente.
	_toldo(raiz, Vector3(0, 9.5, d * 0.5 + 5.0), 22.0, 12.0, m_toldo)
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
	var h_extra: float = 0.0
	match variante:
		"toldos":
			# Mercado: toldos extra a los lados.
			_toldo(raiz, Vector3(-w * 0.5 - 8.0, 8.0, d * 0.3), 14.0, 10.0, m_toldo)
			_toldo(raiz, Vector3(w * 0.5 + 8.0, 8.0, d * 0.3), 14.0, 10.0, _mx("acento", "tela_oro"))
			h_extra = 2.0
		"carbon":
			# Pilas de carbon.
			for i in range(3):
				var pila := SphereMesh.new()
				pila.radius = 1.8
				pila.height = 3.0
				var pmi := MeshInstance3D.new()
				pmi.mesh = pila
				pmi.material_override = _mat("carbon")
				pmi.position = Vector3(-16.0 + float(i) * 5.0, 1.2, d * 0.5 + 8.0)
				raiz.add_child(pmi)
		"pieles":
			# Pieles tendidas en un bastidor.
			_caja(Vector3(10.0, 0.8, 0.8), _mat("madera_oscura"),
				Vector3(12.0, 5.0, d * 0.5 + 6.0), raiz)
			for i in range(3):
				_caja(Vector3(2.4, 3.6, 0.4), _mat("madera"),
					Vector3(8.5 + float(i) * 3.5, 3.0, d * 0.5 + 6.0), raiz)
			h_extra = 1.0
		"runas":
			# Piedras rúnicas junto a la puerta.
			for i in range(2):
				_caja(Vector3(1.4, 3.4, 1.4), _mat("cristal_arcano"),
					Vector3(-12.0 + float(i) * 24.0, 1.7, d * 0.5 + 3.0), raiz)
		"umbral":
			# Cortinajes oscuros en el frente.
			for i in range(3):
				_caja(Vector3(2.0, 6.0, 0.3), _mat("tela_sombra"),
					Vector3(-8.0 + float(i) * 8.0, 8.0, d * 0.5 + 0.4), raiz)
		"botin":
			# Botin extra: mas cajones y un cofre.
			_caja(Vector3(3.5, 3.5, 3.5), _mat("madera"), Vector3(16.0, 1.75, d * 0.5 + 7.0), raiz)
			_caja(Vector3(4.0, 2.5, 2.5), _mat(_mx("acento", "oro")), Vector3(-18.0, 1.25, d * 0.5 + 7.0), raiz)
		"mareas":
			# Redes y cabos de puerto.
			var red := TorusMesh.new()
			red.inner_radius = 2.0
			red.outer_radius = 3.2
			red.rings = 16
			red.ring_segments = 8
			var rmi := MeshInstance3D.new()
			rmi.mesh = red
			rmi.material_override = _mat(_mx("detalle", "madera"))
			rmi.position = Vector3(-14.0, 1.0, d * 0.5 + 7.0)
			raiz.add_child(rmi)
		"dorada":
			# Cartel dorado grande.
			_caja(Vector3(10.0, 4.0, 0.6), _mat("oro"), Vector3(0, 9.5, d * 0.5 + 8.0), raiz)
			h_extra = 3.5
	_colision(raiz, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	raiz.set_meta("altura", h + 6.0 + h_extra)
	return raiz


## Cuartel de Ilya: torres y estandartes rojo sangre. Frente en +Z.
## Fase 15: `variante` re-paleta + decorado de fortaleza regional.
func _cuartel(variante: String) -> Node3D:
	var raiz := Node3D.new()
	var w: float = 64.0
	var h: float = 20.0
	var d: float = 48.0
	var m_muro: String = _mx("muro", "piedra")
	var m_torre: String = _mx("detalle", "piedra_clara")
	var m_oro: String = _mx("acento", "oro")
	var m_cubierta: String = _mx("techo", "acero")
	var color_banderas: String = "rojo"
	if variante == "sombrio":
		color_banderas = "sombra"
	# Fase 15: la fortaleza (escala 1.2 en su JSON) usa torres achaparradas
	# y el cuartel sombrio (escala 1.1) remate fino: nada sobre 28 u reales.
	var torre_h: float = 24.0
	var trim_grosor: float = 1.5
	var trim_y: float = 24.75
	if variante == "fortaleza":
		torre_h = 15.0
		trim_y = torre_h + 0.75
	if variante == "sombrio":
		trim_grosor = 1.0
		trim_y = 24.5
	_caja(Vector3(w, h, d), _mat(m_muro), Vector3(0, h * 0.5, 0), raiz)
	_caja(Vector3(w + 2.0, 1.5, d + 2.0), _mat(m_cubierta), Vector3(0, h + 0.75, 0), raiz)
	for sx in [-1.0, 1.0]:
		var tx: float = (w * 0.5 - 5.0) * sx
		var tz: float = d * 0.5 - 5.0
		_caja(Vector3(10.0, torre_h, 10.0), _mat(m_torre),
			Vector3(tx, torre_h * 0.5, tz), raiz)
		_caja(Vector3(11.0, trim_grosor, 11.0), _mat(m_oro), Vector3(tx, trim_y, tz), raiz)
		_colision(raiz, Vector3(10.0, torre_h, 10.0), Vector3(tx, torre_h * 0.5, tz))
	_caja(Vector3(8.0, 10.0, 0.8), _mat("puerta_madera"),
		Vector3(0, 5.0, d * 0.5 + 0.1), raiz)
	_caja(Vector3(10.0, 1.2, 1.0), _mat(m_oro), Vector3(0, 10.8, d * 0.5 + 0.15), raiz)
	for i in range(4):
		var wx: float = -24.0 + float(i) * 16.0
		_caja(Vector3(3.0, 4.0, 0.6), _mat("ventana"),
			Vector3(wx, 11.0, d * 0.5 + 0.05), raiz)
	for i in range(3):
		var bx: float = -20.0 + float(i) * 20.0
		_estandarte_en(Vector3(bx, 0, d * 0.5 + 5.0), color_banderas, raiz)
	var h_extra: float = 0.0
	match variante:
		"arena":
			# Dunas de arena contra el muro.
			for i in range(3):
				_caja(Vector3(10.0, 2.0, 4.0), _mat(_mx("detalle", "muro_b")),
					Vector3(-20.0 + float(i) * 20.0, 1.0, d * 0.5 + 3.0), raiz)
		"ceniza":
			# Monticulos de ceniza gris.
			for i in range(3):
				_caja(Vector3(8.0, 1.6, 5.0), _mat(_mx("detalle", "piedra_clara")),
					Vector3(-18.0 + float(i) * 18.0, 0.8, -d * 0.5 - 3.0), raiz)
		"norte":
			# Nieve en la cubierta y ventisqueros.
			_caja(Vector3(w + 3.0, 1.0, d + 3.0), _mat("nieve"),
				Vector3(0, h + 1.7, 0), raiz)
			h_extra = 2.2
		"arcano":
			# Cristales en lo alto de las torres (bajos: nada sobre 28 u).
			for sx in [-1.0, 1.0]:
				_caja(Vector3(1.6, 1.8, 1.6), _mat("cristal_arcano"),
					Vector3((w * 0.5 - 5.0) * sx, trim_y + 0.9, d * 0.5 - 5.0), raiz)
			h_extra = 1.1
		"fortaleza":
			# Doble empalizada al frente.
			for i in range(9):
				var fx: float = -w * 0.5 - 4.0 + float(i) * (w + 8.0) / 8.0
				_caja(Vector3(1.6, 9.0, 1.6), _mat(_mx("extra", "madera_oscura")),
					Vector3(fx, 4.5, d * 0.5 + 10.0), raiz)
		"acantilado":
			# Cabos enrollados de puerto fortificado.
			for i in range(2):
				var aro := TorusMesh.new()
				aro.inner_radius = 1.2
				aro.outer_radius = 2.0
				aro.rings = 16
				aro.ring_segments = 8
				var ami := MeshInstance3D.new()
				ami.mesh = aro
				ami.material_override = _mat(_mx("detalle", "madera"))
				ami.position = Vector3(-24.0 + float(i) * 48.0, 1.0, d * 0.5 + 6.0)
				raiz.add_child(ami)
	_colision(raiz, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	# La cima real: torres+remate (clasico 25.5, sombrio 25.0) o la cubierta
	# del bloque en la fortaleza achaparrada (21.5).
	var tope: float = trim_y + trim_grosor * 0.5
	if variante == "fortaleza":
		tope = h + 1.5
	raiz.set_meta("altura", tope + h_extra)
	return raiz


## Templo menor: columnas y cupula de bronce. Frente en +Z.
## Fase 15: `variante` re-paleta + decorado de culto regional.
func _templo(variante: String) -> Node3D:
	var raiz := Node3D.new()
	var w: float = 30.0
	var h: float = 16.0
	var d: float = 30.0
	var m_muro: String = _mx("muro", "piedra_clara")
	var m_piedra: String = _mx("detalle", "piedra")
	var m_cupula: String = _mx("acento", "bronce")
	_caja(Vector3(w + 4.0, 2.0, d + 4.0), _mat(m_piedra), Vector3(0, 1.0, 0), raiz)
	_caja(Vector3(w, h, d), _mat(m_muro), Vector3(0, h * 0.5 + 1.0, 0), raiz)
	for i in range(4):
		var cx: float = -10.5 + float(i) * 7.0
		_caja(Vector3(2.2, 14.0, 2.2), _mat(m_piedra),
			Vector3(cx, 8.0, d * 0.5 + 4.0), raiz)
	_caja(Vector3(w * 0.8, 1.6, 8.0), _mat(m_piedra),
		Vector3(0, 15.8, d * 0.5 + 4.0), raiz)
	var cupula := SphereMesh.new()
	cupula.radius = 10.0
	cupula.height = 20.0
	cupula.radial_segments = 24
	cupula.rings = 12
	var umi := MeshInstance3D.new()
	umi.mesh = cupula
	umi.scale = Vector3(1, 0.6, 1)
	umi.material_override = _mat(m_cupula)
	umi.position = Vector3(0, h + 1.0, 0)
	raiz.add_child(umi)
	_caja(Vector3(5.0, 8.0, 0.6), _mat("puerta_madera"),
		Vector3(0, 5.0, d * 0.5 + 0.05), raiz)
	_caja(Vector3(3.0, 5.0, 0.5), _mat("ventana"), Vector3(-9.0, 9.0, d * 0.5 + 0.05), raiz)
	_caja(Vector3(3.0, 5.0, 0.5), _mat("ventana"), Vector3(9.0, 9.0, d * 0.5 + 0.05), raiz)
	_estandarte_en(Vector3(-8.0, 0, d * 0.5 + 3.0), "oro", raiz)
	_estandarte_en(Vector3(8.0, 0, d * 0.5 + 3.0), "oro", raiz)
	var h_extra: float = 0.0
	match variante:
		"arena":
			# Disco solar sobre la puerta.
			_sol_dorado_en(raiz, Vector3(0, 13.0, d * 0.5 + 0.6), 3.0)
			h_extra = 3.0
		"llama":
			# Braseros a los lados de la puerta (falsas antorchas, sin luz).
			for sx in [-1.0, 1.0]:
				var poste := Node3D.new()
				poste.position = Vector3(sx * 7.0, 0, d * 0.5 + 4.0)
				raiz.add_child(poste)
				_caja(Vector3(1.0, 4.0, 1.0), _mat("madera_oscura"),
					Vector3(0, 2.0, 0), poste)
				var fa := FalsaAntorcha.new()
				fa.ciclo = ciclo
				fa.color_llama = Color(1.0, 0.45, 0.1)
				fa.position = Vector3(0, 4.6, 0)
				poste.add_child(fa)
				_luces.append(fa)
			h_extra = 2.0
		"nieve":
			# Cupula nevada.
			var gorro := SphereMesh.new()
			gorro.radius = 10.4
			gorro.height = 20.8
			gorro.radial_segments = 24
			gorro.rings = 8
			var gmi := MeshInstance3D.new()
			gmi.mesh = gorro
			gmi.scale = Vector3(1, 0.35, 1)
			gmi.material_override = _mat("nieve")
			gmi.position = Vector3(0, h + 4.5, 0)
			raiz.add_child(gmi)
			h_extra = 2.0
		"arcano":
			# Aguja de cristal sobre la cupula.
			_aguja_cristal(raiz, Vector3(0, h + 6.0, 0), 2.0, 5.0)
			h_extra = 5.0
		"velo":
			# Velos oscuros entre las columnas.
			for i in range(3):
				_caja(Vector3(2.6, 10.0, 0.3), _mat("tela_sombra"),
					Vector3(-7.0 + float(i) * 7.0, 6.0, d * 0.5 + 4.0), raiz)
		"colmillos":
			# Arco de colmillos ante la puerta.
			_colmillo_en(raiz, Vector3(-4.5, 10.0, d * 0.5 + 2.0), 0.45)
			_colmillo_en(raiz, Vector3(4.5, 10.0, d * 0.5 + 2.0), -0.45)
			_caja(Vector3(12.0, 1.2, 1.2), _mat("hueso"),
				Vector3(0, 13.5, d * 0.5 + 2.0), raiz)
			h_extra = 2.0
		"marea":
			# Olas esculpidas en el frente.
			for i in range(2):
				var ola := TorusMesh.new()
				ola.inner_radius = 2.2
				ola.outer_radius = 3.4
				ola.rings = 20
				ola.ring_segments = 8
				var omi := MeshInstance3D.new()
				omi.mesh = ola
				omi.material_override = _mat("agua")
				omi.position = Vector3(-8.0 + float(i) * 16.0, 12.0, d * 0.5 + 0.8)
				raiz.add_child(omi)
			h_extra = 3.5
		"dorado":
			# Remate dorado sobre la cupula (bajo las 28 u con escala 1.1).
			var remate := SphereMesh.new()
			remate.radius = 1.5
			remate.height = 3.0
			var remi := MeshInstance3D.new()
			remi.mesh = remate
			remi.material_override = _mat("oro")
			remi.position = Vector3(0, h + 7.0, 0)
			raiz.add_child(remi)
			h_extra = 1.5
	_colision(raiz, Vector3(w, h + 1.0, d), Vector3(0, (h + 1.0) * 0.5, 0))
	raiz.set_meta("altura", h + 1.0 + 6.0 + h_extra)
	return raiz


## Aguja de cristal arcano (fase 15): bipyramid emissiva.
func _aguja_cristal(padre: Node3D, pos: Vector3, radio: float, alto: float) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	padre.add_child(n)
	for f in [-1.0, 1.0]:
		var pir := CylinderMesh.new()
		pir.top_radius = radio if f < 0.0 else 0.05
		pir.bottom_radius = 0.05 if f < 0.0 else radio
		pir.height = alto * 0.5
		pir.radial_segments = 6
		var pmi := MeshInstance3D.new()
		pmi.mesh = pir
		pmi.material_override = _mat("cristal_arcano")
		pmi.position = Vector3(0, f * alto * 0.25, 0)
		n.add_child(pmi)
	return n


## Monumento de la plaza. Fase 15: 8 variantes nuevas (oasis, volcan,
## pico_norte, cristal, sombra, trofeo_guerra, tormenta, sol_dorado),
## todas procedurales y de <= 28 u. "luna" = clasico de Moon Town (verbatim).
func _monumento(variante: String) -> Node3D:
	match variante:
		"oasis":
			return _monumento_oasis()
		"volcan":
			return _monumento_volcan()
		"pico_norte":
			return _monumento_pico_norte()
		"cristal":
			return _monumento_cristal()
		"sombra":
			return _monumento_sombra()
		"trofeo_guerra":
			return _monumento_trofeo()
		"tormenta":
			return _monumento_tormenta()
		"sol_dorado":
			return _monumento_sol()
	return _monumento_luna()


## Pedestal escalonado comun de los monumentos fase 15 (10 u de alto).
func _pedestal_monumento() -> Node3D:
	var raiz := Node3D.new()
	_caja(Vector3(16.0, 2.0, 16.0), _mat(_mx("muro", "piedra")), Vector3(0, 1.0, 0), raiz)
	_caja(Vector3(12.0, 3.0, 12.0), _mat(_mx("detalle", "piedra_clara")), Vector3(0, 3.5, 0), raiz)
	_caja(Vector3(8.0, 5.0, 8.0), _mat(_mx("muro", "piedra")), Vector3(0, 7.5, 0), raiz)
	_caja(Vector3(9.0, 1.0, 9.0), _mat(_mx("acento", "oro")), Vector3(0, 10.5, 0), raiz)
	_colision(raiz, Vector3(16.0, 12.0, 16.0), Vector3(0, 6.0, 0))
	return raiz


## Oasis del desierto: pileta de agua y palmeras.
func _monumento_oasis() -> Node3D:
	var raiz := _pedestal_monumento()
	var pileta := CylinderMesh.new()
	pileta.top_radius = 5.5
	pileta.bottom_radius = 5.5
	pileta.height = 0.8
	pileta.radial_segments = 24
	var pmi := MeshInstance3D.new()
	pmi.mesh = pileta
	pmi.material_override = _mat("agua")
	pmi.position = Vector3(0, 11.2, 0)
	raiz.add_child(pmi)
	# Brocal de piedra arenisca.
	for i in range(8):
		var ang: float = TAU * float(i) / 8.0
		_caja(Vector3(2.2, 1.6, 2.2), _mat(_mx("detalle", "piedra_clara")),
			Vector3(6.4 * cos(ang), 11.0, 6.4 * sin(ang)), raiz)
	# Tres palmeras (tronco + hojas).
	for i in range(3):
		var ang2: float = TAU * float(i) / 3.0 + 0.5
		var px: float = 11.0 * cos(ang2)
		var pz: float = 11.0 * sin(ang2)
		var tronco := CylinderMesh.new()
		tronco.top_radius = 0.5
		tronco.bottom_radius = 0.8
		tronco.height = 11.0
		tronco.radial_segments = 8
		var tmi := MeshInstance3D.new()
		tmi.mesh = tronco
		tmi.material_override = _mat("madera")
		tmi.rotation.z = 0.12 * (1.0 if i % 2 == 0 else -1.0)
		tmi.position = Vector3(px, 5.5, pz)
		raiz.add_child(tmi)
		for j in range(5):
			var hoja := MeshInstance3D.new()
			if _caja_mesh == null:
				_caja_mesh = BoxMesh.new()
				_caja_mesh.size = Vector3.ONE
			hoja.mesh = _caja_mesh
			hoja.scale = Vector3(6.5, 0.3, 2.2)
			hoja.material_override = _mat("hoja")
			var ha: float = TAU * float(j) / 5.0
			hoja.position = Vector3(px + 2.6 * cos(ha), 11.3, pz + 2.6 * sin(ha))
			hoja.rotation.y = -ha
			hoja.rotation.z = 0.35
			raiz.add_child(hoja)
	raiz.set_meta("altura", 13.0)
	return raiz


## Volcan de la forja: cono de piedra oscura con brasero (falsa antorcha).
func _monumento_volcan() -> Node3D:
	var raiz := _pedestal_monumento()
	var cono := CylinderMesh.new()
	cono.top_radius = 3.0
	cono.bottom_radius = 8.5
	cono.height = 13.0
	cono.radial_segments = 12
	var cmi := MeshInstance3D.new()
	cmi.mesh = cono
	cmi.material_override = _mat("piedra_volcanica")
	cmi.position = Vector3(0, 17.5, 0)
	raiz.add_child(cmi)
	# Grietas de lava en el cono.
	for i in range(4):
		var ang: float = TAU * float(i) / 4.0 + 0.4
		_caja(Vector3(0.7, 7.0, 0.7), _mat("lava"),
			Vector3(5.6 * cos(ang), 15.0, 5.6 * sin(ang)), raiz)
	# Brasero en el crater (sin luz dinamica).
	var fa := FalsaAntorcha.new()
	fa.ciclo = ciclo
	fa.color_llama = Color(1.0, 0.4, 0.08)
	fa.position = Vector3(0, 24.6, 0)
	raiz.add_child(fa)
	_luces.append(fa)
	raiz.set_meta("altura", 27.0)
	return raiz


## Pico del norte: menhir de piedra con nieve.
func _monumento_pico_norte() -> Node3D:
	var raiz := _pedestal_monumento()
	var menhir := CylinderMesh.new()
	menhir.top_radius = 1.6
	menhir.bottom_radius = 2.6
	menhir.height = 13.0
	menhir.radial_segments = 6
	var mmi := MeshInstance3D.new()
	mmi.mesh = menhir
	mmi.material_override = _mat(_mx("muro", "piedra"))
	mmi.position = Vector3(0, 17.5, 0)
	raiz.add_child(mmi)
	# Nieve en la cima.
	var cima := CylinderMesh.new()
	cima.top_radius = 0.4
	cima.bottom_radius = 1.9
	cima.height = 2.6
	cima.radial_segments = 6
	var cmi := MeshInstance3D.new()
	cmi.mesh = cima
	cmi.material_override = _mat("nieve")
	cmi.position = Vector3(0, 24.6, 0)
	raiz.add_child(cmi)
	# Runas talladas (brillo frio).
	for i in range(3):
		_caja(Vector3(0.5, 2.4, 0.5), _mat("cristal_arcano"),
			Vector3(2.2 * cos(TAU * float(i) / 3.0), 16.0, 2.2 * sin(TAU * float(i) / 3.0)), raiz)
	raiz.set_meta("altura", 26.0)
	return raiz


## Cristal arcano: gran cristal flotante que rota lento.
func _monumento_cristal() -> Node3D:
	var raiz := _pedestal_monumento()
	var cristal := _aguja_cristal(raiz, Vector3(0, 18.0, 0), 3.2, 11.0)
	_rotadores.append(cristal)
	# Fragmentos pequenos alrededor del pedestal.
	for i in range(4):
		var ang: float = TAU * float(i) / 4.0 + 0.3
		_caja(Vector3(1.0, 2.4, 1.0), _mat("cristal_arcano"),
			Vector3(9.5 * cos(ang), 1.2, 9.5 * sin(ang)), raiz)
	raiz.set_meta("altura", 24.0)
	return raiz


## Pilar de sombra: obelisco oscuro con estandartes.
func _monumento_sombra() -> Node3D:
	var raiz := _pedestal_monumento()
	var obe := CylinderMesh.new()
	obe.top_radius = 1.4
	obe.bottom_radius = 3.0
	obe.height = 14.0
	obe.radial_segments = 4
	var omi := MeshInstance3D.new()
	omi.mesh = obe
	omi.material_override = _mat(_mx("muro", "piedra"))
	omi.rotation.y = PI * 0.25
	omi.position = Vector3(0, 18.0, 0)
	raiz.add_child(omi)
	# Punta emissiva violacea.
	var punta := CylinderMesh.new()
	punta.top_radius = 0.05
	punta.bottom_radius = 1.5
	punta.height = 2.4
	punta.radial_segments = 4
	var pmi := MeshInstance3D.new()
	pmi.mesh = punta
	pmi.material_override = _mat("cristal_arcano")
	pmi.rotation.y = PI * 0.25
	pmi.position = Vector3(0, 26.2, 0)
	raiz.add_child(pmi)
	_estandarte_en(Vector3(-9.0, 0, 6.0), "sombra", raiz)
	_estandarte_en(Vector3(9.0, 0, 6.0), "sombra", raiz)
	raiz.set_meta("altura", 27.5)
	return raiz


## Trofeo de guerra: totem de madera con colmillos y trofeos.
func _monumento_trofeo() -> Node3D:
	var raiz := _pedestal_monumento()
	var poste := CylinderMesh.new()
	poste.top_radius = 1.4
	poste.bottom_radius = 1.8
	poste.height = 14.0
	poste.radial_segments = 10
	var pmi := MeshInstance3D.new()
	pmi.mesh = poste
	pmi.material_override = _mat("madera_oscura")
	pmi.position = Vector3(0, 18.0, 0)
	raiz.add_child(pmi)
	# Trofeos apilados (cajas decrecientes) y calaveras de hueso.
	var w: float = 6.0
	for i in range(3):
		_caja(Vector3(w, 2.2, w), _mat("madera"),
			Vector3(0, 13.0 + float(i) * 2.6, 0), raiz)
		_caja(Vector3(1.6, 1.6, 1.6), _mat("hueso"),
			Vector3(w * 0.5 + 1.2, 13.0 + float(i) * 2.6, 0), raiz)
		w -= 1.6
	# Colmillos cruzados en la cima.
	for i in range(4):
		var ang: float = TAU * float(i) / 4.0
		var cono := CylinderMesh.new()
		cono.top_radius = 0.12
		cono.bottom_radius = 0.7
		cono.height = 4.5
		cono.radial_segments = 8
		var cmi := MeshInstance3D.new()
		cmi.mesh = cono
		cmi.material_override = _mat("hueso")
		cmi.position = Vector3(3.4 * cos(ang), 24.5, 3.4 * sin(ang))
		cmi.rotation.z = 0.7 * cos(ang)
		cmi.rotation.x = -0.7 * sin(ang)
		raiz.add_child(cmi)
	raiz.set_meta("altura", 27.0)
	return raiz


## Tormenta esculpida: mastil con esfera de tormenta y anillos.
func _monumento_tormenta() -> Node3D:
	var raiz := _pedestal_monumento()
	var mastil := CylinderMesh.new()
	mastil.top_radius = 0.8
	mastil.bottom_radius = 1.2
	mastil.height = 10.0
	mastil.radial_segments = 10
	var mmi := MeshInstance3D.new()
	mmi.mesh = mastil
	mmi.material_override = _mat("madera_oscura")
	mmi.position = Vector3(0, 16.0, 0)
	raiz.add_child(mmi)
	# Esfera de tormenta (emissive fria).
	var esfera := SphereMesh.new()
	esfera.radius = 3.0
	esfera.height = 6.0
	esfera.radial_segments = 20
	esfera.rings = 12
	var 	emi := MeshInstance3D.new()
	emi.mesh = esfera
	emi.material_override = _mat("tormenta")
	emi.position = Vector3(0, 23.5, 0)
	raiz.add_child(emi)
	_rotadores.append(emi)
	# Dos anillos metalicos inclinados.
	for i in range(2):
		var aro := TorusMesh.new()
		aro.inner_radius = 3.6
		aro.outer_radius = 4.0
		aro.rings = 32
		aro.ring_segments = 8
		var ami := MeshInstance3D.new()
		ami.mesh = aro
		ami.material_override = _mat("acero")
		ami.position = Vector3(0, 23.5, 0)
		ami.rotation.x = PI * 0.5 + float(i) * 0.5
		raiz.add_child(ami)
	raiz.set_meta("altura", 27.5)
	return raiz


## Sol dorado: disco solar con rayos sobre pedestal.
func _monumento_sol() -> Node3D:
	var raiz := _pedestal_monumento()
	# Columna que sostiene el disco.
	_caja(Vector3(2.5, 8.0, 2.5), _mat(_mx("detalle", "piedra_clara")),
		Vector3(0, 15.0, 0), raiz)
	_sol_dorado_en(raiz, Vector3(0, 20.5, 0), 4.5)
	# Rayos radiales alrededor del disco (eje largo radial).
	for i in range(8):
		var ang: float = TAU * float(i) / 8.0
		var rayo := MeshInstance3D.new()
		if _caja_mesh == null:
			_caja_mesh = BoxMesh.new()
			_caja_mesh.size = Vector3.ONE
		rayo.mesh = _caja_mesh
		rayo.scale = Vector3(0.9, 2.8, 0.9)
		rayo.material_override = _mat("oro")
		rayo.position = Vector3(5.6 * cos(ang), 20.5 + 5.6 * sin(ang), 0)
		rayo.rotation.z = ang - PI * 0.5
		raiz.add_child(rayo)
	raiz.set_meta("altura", 27.5)
	return raiz


## Monumento: pedestal escalonado + luna creciente dorada (simbolo de la ciudad).
## VERBATIM fase 14 (Moon Town).
func _monumento_luna() -> Node3D:
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
## Fase 15: re-paleta leve con los materiales de la ciudad.
func _puerta(variante: String) -> Node3D:
	var raiz := Node3D.new()
	var m_piedra: String = _mx("muro", "piedra")
	var m_clara: String = _mx("detalle", "piedra_clara")
	var m_oro: String = _mx("acento", "oro")
	for sx in [-1.0, 1.0]:
		var px: float = 18.0 * sx
		_caja(Vector3(6.0, 14.0, 6.0), _mat(m_piedra), Vector3(px, 7.0, 0), raiz)
		_colision(raiz, Vector3(6.0, 14.0, 6.0), Vector3(px, 7.0, 0))
		var tx: float = 30.0 * sx
		_caja(Vector3(10.0, 22.0, 10.0), _mat(m_piedra), Vector3(tx, 11.0, 0), raiz)
		_caja(Vector3(11.0, 1.5, 11.0), _mat(m_oro), Vector3(tx, 22.75, 0), raiz)
		_colision(raiz, Vector3(10.0, 22.0, 10.0), Vector3(tx, 11.0, 0))
		_estandarte_en(Vector3(tx, 0, 6.5), "oro", raiz)
	# Dintel alto: no bloquea el paso (apertura util de 30 u).
	_caja(Vector3(42.0, 4.0, 8.0), _mat(m_clara), Vector3(0, 16.0, 0), raiz)
	_caja(Vector3(28.0, 3.0, 1.0), _mat("acero"), Vector3(0, 13.0, 0), raiz)
	raiz.set_meta("altura", 23.5)
	return raiz


# ---------------------------------------------------------------------------
# Antorchas y banderas
# ---------------------------------------------------------------------------

func _colocar_antorcha(x: float, z: float, padre: Node3D) -> void:
	# Fase 15: x/z son locales a la ciudad; la altura se consulta en mundo.
	var wx: float = x + centro.x
	var wz: float = z + centro.y
	var holder := Node3D.new()
	holder.position = Vector3(x, _altura(wx, wz), z)
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
	# Fase 15: Moon Town conserva la Antorcha real (OmniLight3D); las 8
	# ciudades usan FalsaAntorcha (llama emissive, sin luz dinamica).
	var llama: Node3D
	if luces_reales:
		var real := Antorcha.new()
		real.ciclo = ciclo
		real.jugador = jugador
		llama = real
	else:
		var falsa := FalsaAntorcha.new()
		falsa.ciclo = ciclo
		llama = falsa
	llama.position = Vector3(0, 6.0, 0)
	holder.add_child(llama)
	_luces.append(llama)
	padre.add_child(holder)
	_n_antorchas += 1
	alturas[str(holder.name)] = 6.5


func _construir_antorchas() -> void:
	var raiz := Node3D.new()
	raiz.name = "Antorchas"
	raiz.position = Vector3(centro.x, 0.0, centro.y)
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
	raiz.position = Vector3(centro.x, 0.0, centro.y)
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
		e.position = Vector3(v.x, _altura(centro.x + v.x, centro.y + v.z), v.z)
		raiz.add_child(e)
		_caja(Vector3(1.0, 12.0, 1.0), _mat("madera_oscura"), Vector3(0, 6.0, 0), e)
		_caja(Vector3(5.0, 0.7, 0.7), _mat("madera_oscura"), Vector3(2.1, 11.4, 0), e)
		_caja(Vector3(4.0, 7.5, 0.3), _mat("tela_oro"), Vector3(2.2, 7.4, 0), e)
		alturas["BanderaPuerta_%d" % n_ban] = 12.0
		n_ban += 1
