class_name Veta
extends Entity
## Veta minera (fase 45): un nodo de mineral clavado en el terreno.
##
## REGLA DURA: una veta NO es un enemigo. Es `Entity` solo para reusar el
## idioma del mundo (el raycast del clic ya resuelve contra `Entity`, así que
## la veta se selecciona, se camina hasta ella y se mina con E igual que un
## NPC) — pero `combatible = false`: nunca entra en el foco de combate, nunca
## recibe daño y nunca es objetivo de ataque (igual que los NPCs, fase 5.1).
##
## Nodo de estado + visual, sin reglas: quién puede minar y qué entrega lo
## decide `Mineria` (lógica pura). Aquí viven los usos, la cuenta atrás de
## respawn, el aviso flotante y el guardado.
##
## Diseño de nodos (mismo idioma que `enemigo.tscn`/`npc.tscn`, para que el
## cambio a modelos GLB de la fase 47 sea un swap y no una reescritura):
##   Veta (esta Entity, CharacterBody3D, capa 4 = la que ve el raycast del clic)
##   ├── Colision (CollisionShape3D, esfera)
##   ├── Cuerpo (MeshInstance3D, roca + cristales, tinte del mineral)
##   └── Aviso (Label3D, texto flotante del minado)
##
## REGLA de rendimiento: la veta solo se procesa cuando tiene algo que
## contar (respawn en curso o aviso visible). En reposo, `set_process(false)`.

## Fase 45: la veta comparte capa de colisión con enemigos y NPCs (4) para que
## el raycast del clic la encuentre sin tocar el jugador.
const CAPA: int = 4
## Radio de la esfera de colisión (bastante generosa: es un punto de interés,
## no una obstacle: el jugador solo tiene que llegar cerca para minar).
const RADIO_COLISION: float = 1.8
## Altura del centro de la roca sobre el suelo.
const ALTO_CUERPO: float = 0.7
## Altura del aviso flotante sobre el suelo.
const ALTO_AVISO: float = 3.0
## Segundos que dura el texto flotante tras minar.
const AVISO_DURACION: float = 1.8
## Semillas del cristalado (giros fijos: la veta se ve igual cada vez).
const GIROS: Array[float] = [0.4, 2.3, 4.5]

## Id de veta (clave de `data/vetas.json` y del guardado).
var veta_id: String = ""
## Nombre legible ("Veta de Cobre — Moon Town").
var nombre: String = "Veta"
## Item que entrega (`data/items.json`).
var item_id: String = ""
## Minerales por golpe minado.
var cantidad: int = 1
## XP por golpe minado (data-driven: 5 al principio, 12 en endgame).
var xp: int = 0
## Nivel mínimo para poder minarla (gate de progresión por región). Se llama
## `nivel_min` y no `nivel` porque `nivel` ya es el nivel de la Entity.
var nivel_min: int = 1
## Usos que aguanta antes de agotarse (3, decided en la fase 45).
var usos_max: int = 3
## Usos que le quedan. 0 = agotada (no se puede minar).
var usos: int = 3
## Segundos que tarda la veta en reponerse una vez agotada (180).
var respawn_s: float = 180.0
## Segundos que le quedan de respawn. >0 = agotada y contando.
var respawn_restante: float = 0.0
## Tinte del mineral (viene del JSON; el material se comparte por mineral).
var tinte: Color = Color(0.7, 0.7, 0.7)

## Se	minó un golpe con éxito (la UI/los tests lo escuchan).
signal minada(item_id: String, cantidad: int, xp: int)
## La veta se agotó y empezó su cuenta atrás.
signal agotada(veta_id: String)
## La veta volvió a estar minable.
signal reaparecida(veta_id: String)

var _cuerpo: MeshInstance3D = null
var _aviso: Label3D = null
var _aviso_restante: float = 0.0
## Capa de colisión que la veta tiene puesta (la real se aplica diferida).
var _capa: int = CAPA
## Mallas compartidas por TODAS las vetas (una roca, un prisma): los 12 nodos
## del mundo no crean geometría propia.
static var _malla_roca: SphereMesh = null
static var _malla_prisma: PrismMesh = null
## Esfera de colisión compartida (una sola para las 12 vetas).
static var _forma_colision: SphereShape3D = null
## Un material por mineral (no uno por veta): §9.5, materiales compartidos.
static var _materiales: Dictionary = {}


## Fase 5.1: no combatible desde el mismo instante en que existe (igual que
## NPC): `take_damage` lo ignora y el jugador nunca la fija como objetivo.
func _init(p_stats: StatBlock = null) -> void:
	super._init(p_stats)
	combatible = false


func _ready() -> void:
	add_to_group("vetas")
	collision_layer = CAPA
	collision_mask = 0
	_construir_cuerpo()
	_construir_aviso()
	# En reposo no se procesa: nada que contar hasta que se agote o se mine.
	set_process(respawn_restante > 0.0)


## Carga la veta desde su dict de `data/vetas.json` (VetaDB). Idempotente:
## recargar no pisa los usos que le quedan a una veta ya minada.
##
## ORDEN: llámalo ANTES de `add_child` (el cuerpo se construye en `_ready` con
## el tinte del mineral). Si se llama después, `_aplicar_tinte` lo corrige.
func configurar(d: Dictionary) -> void:
	if d.is_empty():
		return
	veta_id = str(d.get("id", veta_id))
	nombre = str(d.get("nombre", nombre))
	item_id = str(d.get("item_id", item_id))
	cantidad = maxi(1, int(d.get("cantidad", 1)))
	xp = maxi(0, int(d.get("xp", 0)))
	nivel_min = maxi(1, int(d.get("nivel", 1)))
	usos_max = maxi(1, int(d.get("usos", 3)))
	respawn_s = maxf(float(d.get("respawn_s", 180.0)), 1.0)
	usos = usos_max
	respawn_restante = 0.0
	tinte = _color_de(str(d.get("tinte", "")))
	if is_inside_tree():
		_aplicar_tinte()


## Configura la veta desde su id (la busca en `VetaDB`). false si no existe.
func configurar_por_id(id: String) -> bool:
	if not VetaDB.existe(id):
		return false
	configurar(VetaDB.obtener(id))
	return true


## ¿Se puede minar ahora? (quedan usos y no está en respawn).
func esta_minable() -> bool:
	return usos > 0


func usos_restantes() -> int:
	return maxi(0, usos)


## Tiempo que le falta para reponerse (0 si está minable).
func segundos_para_reaparecer() -> float:
	return respawn_restante


## Un golpe de minado: gasta un uso. Si se agota, la oculta y arranca la
## cuenta atrás. Lo llama `Mineria` (nadie más debe tocar `usos`).
func consumir_uso() -> void:
	if usos <= 0:
		return
	usos -= 1
	if usos > 0:
		return
	respawn_restante = respawn_s
	ocultar_cuerpo()
	set_process(true)
	agotada.emit(veta_id)


## Texto flotante sobre la veta (ej. "+2 Mineral de Cobre (+9 XP)"). Se
## reutiliza el mismo Label3D: nunca se crea ni se destruye en caliente.
func mostrar_aviso(texto: String) -> void:
	if _aviso == null:
		return
	_aviso.text = texto
	_aviso.visible = true
	_aviso_restante = AVISO_DURACION
	set_process(true)


## Texto del aviso ahora mismo ("" si no hay aviso visible; para tests).
func aviso_actual() -> String:
	if _aviso == null or not _aviso.visible:
		return ""
	return _aviso.text


## Avanza el reloj de la veta: cuenta atrás del respawn y del aviso. Lo llama
## `_process` y también los tests (sin necesidad de frames ni de escena).
func tick(delta: float) -> void:
	if _aviso_restante > 0.0:
		_aviso_restante = maxf(_aviso_restante - delta, 0.0)
		if _aviso_restante <= 0.0 and _aviso != null:
			_aviso.visible = false
	if respawn_restante <= 0.0:
		if _aviso_restante <= 0.0:
			set_process(false)
		return
	respawn_restante = maxf(respawn_restante - delta, 0.0)
	if respawn_restante <= 0.0:
		respawn_restante = 0.0
		usos = usos_max
		mostrar_cuerpo()
		set_process(_aviso_restante > 0.0)
		reaparecida.emit(veta_id)


func _process(delta: float) -> void:
	# El flash de Entity no se usa en una veta (nunca recibe daño), pero su
	# decaimiento se mantiene por si acaso.
	super._process(delta)
	tick(delta)


## Muestra/oculta el cuerpo Y la colisión. Sin esto una veta agotada seguiría
## Tapaba el raycast del clic (un CharacterBody3D invisible colisiona igual).
func mostrar_cuerpo() -> void:
	_capa = CAPA
	visible = true
	set_deferred("collision_layer", CAPA)


func ocultar_cuerpo() -> void:
	_capa = 0
	visible = false
	set_deferred("collision_layer", 0)


## ¿La veta tiene colisión puesta? El cambio de capa es diferido
## (`set_deferred`, igual que `Entity.die`, porque puede venir de un callback
## físico): esto es la intención, legible sin esperar un frame.
func colision_activa() -> bool:
	return _capa == CAPA


## Bloque de guardado: solo lo que no se puede recuperar de `data/vetas.json`.
func to_dict() -> Dictionary:
	return {
		"veta_id": veta_id,
		"usos": usos,
		"respawn_restante": respawn_restante,
	}


## Restaura usos y cuenta atrás (fase 45: el guardado de la partida). Si el
## save la dejó a medias de respawn, arranca el reloj desde donde estaba y el
## cuerpo sigue oculto.
func restaurar(d: Dictionary) -> void:
	if d.is_empty():
		return
	usos = clampi(int(d.get("usos", usos_max)), 0, usos_max)
	respawn_restante = maxf(float(d.get("respawn_restante", 0.0)), 0.0)
	if esta_minable() and respawn_restante <= 0.0:
		mostrar_cuerpo()
	else:
		ocultar_cuerpo()
	set_process(respawn_restante > 0.0)


func _construir_cuerpo() -> void:
	_colision()
	_cuerpo = MeshInstance3D.new()
	_cuerpo.name = "Cuerpo"
	_cuerpo.mesh = _roca()
	_cuerpo.scale = Vector3(1.6, 0.8, 1.6)
	_cuerpo.position = Vector3(0.0, ALTO_CUERPO, 0.0)
	add_child(_cuerpo)
	# Tres cristales alrededor de la roca: el mismo material (barato) y las
	# mallas compartidas por todas las vetas.
	for i in range(GIROS.size()):
		var p: MeshInstance3D = MeshInstance3D.new()
		p.name = "Cristal%d" % i
		p.mesh = _prisma()
		var giro: float = GIROS[i]
		p.rotation = Vector3(0.0, giro, 0.22 * float(i + 1))
		p.position = Vector3(cos(giro) * 0.7, ALTO_CUERPO + 0.5, sin(giro) * 0.7)
		p.scale = Vector3(0.4, 0.9 + 0.25 * float(i), 0.4)
		add_child(p)
	_aplicar_tinte()


## Pone el material del mineral a la roca y a los cristales (compartido por
## mineral, nunca uno por veta). Se puede volver a llamar tras `configurar`.
func _aplicar_tinte() -> void:
	var mat: StandardMaterial3D = _material_de(tinte)
	if _cuerpo != null:
		_cuerpo.material_override = mat
	for i in range(GIROS.size()):
		var c: MeshInstance3D = get_node_or_null("Cristal%d" % i) as MeshInstance3D
		if c != null:
			c.material_override = mat


func _colision() -> void:
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "Colision"
	col.shape = _forma()
	col.position = Vector3(0.0, ALTO_CUERPO, 0.0)
	add_child(col)


## Esfera de colisión compartida por todas las vetas (mismo radio).
static func _forma() -> SphereShape3D:
	if _forma_colision == null:
		var s: SphereShape3D = SphereShape3D.new()
		s.radius = RADIO_COLISION
		_forma_colision = s
	return _forma_colision


func _construir_aviso() -> void:
	_aviso = Label3D.new()
	_aviso.name = "Aviso"
	_aviso.text = ""
	_aviso.visible = false
	_aviso.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_aviso.font_size = 48
	_aviso.outline_size = 14
	_aviso.pixel_size = 0.01
	_aviso.position = Vector3(0.0, ALTO_AVISO, 0.0)
	_aviso.modulate = Color(1.0, 0.92, 0.6)
	_aviso.no_depth_test = true
	add_child(_aviso)


## Malla de roca compartida por todas las vetas.
static func _roca() -> SphereMesh:
	if _malla_roca == null:
		var m: SphereMesh = SphereMesh.new()
		m.radius = 1.0
		m.height = 1.2
		m.radial_segments = 8
		m.rings = 4
		_malla_roca = m
	return _malla_roca


## Malla de cristal compartida por todas las vetas.
static func _prisma() -> PrismMesh:
	if _malla_prisma == null:
		var m: PrismMesh = PrismMesh.new()
		m.size = Vector3(0.5, 1.6, 0.5)
		_malla_prisma = m
	return _malla_prisma


## Un material por mineral (cacheado por tinte): 6 vetas de cobre comparten
## el mismo StandardMaterial3D, no crean 12.
static func _material_de(color: Color) -> StandardMaterial3D:
	var clave: String = color.to_html(false)
	if _materiales.has(clave):
		return _materiales[clave]
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.35
	mat.metallic = 0.55
	mat.emission_enabled = true
	mat.emission = color * 0.18
	_materiales[clave] = mat
	return mat


## "#rrggbb" -> Color. Vacío o inválido -> gris.
static func _color_de(hex: String) -> Color:
	if hex == "":
		return Color(0.7, 0.7, 0.7)
	return Color.from_string(hex, Color(0.7, 0.7, 0.7))
