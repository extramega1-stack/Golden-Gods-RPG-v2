class_name PoolImpacto
extends Node3D
## Bloque 68: los efectos que hacen que un golpe se SIENTA.
##
## POR QUÉ EXISTE, Y POR QUÉ ES LO MÁS BARATO DEL BLOQUE: el game feel de la
## fase 19 tiene números de daño, hit-stop y screen shake, que es la mitad de
## lo que hace que un golpe se sienta. La otra mitad es que el mundo REACCIONE:
## que al golpe una roca salgan chispas, que el enemigo se empuje, que la flecha
## se vea volar. Con las tres, un golpe con 5 de daño se siente distinto de uno
## con 50, que es de lo que se trata.
##
## - POOL, no creación por golpe. 12 emisores de partículas y 6 de\n##   fragmentos, preasignados. Un `GPUParticles3D` por impacto es una
##   asignacion en el frame del golpe, que es el frame que no puede tirarse.
## - MATERIALES COMPARTIDOS: cuatro (chispa, sangre, polvo, hielo) para todo el
##   juego. Con materiales compartidos por arquetipo (§9.5), un material por
##   impacto habria sido 1.000 materiales.
## - El impacto es POSICIONAL y suena (bloque 66): una chispita en un mob a
##   30 m tiene que sonar a 30 m.

const CAPA: int = 16
## Emisores de partículas (chispas, sangre, polvo). Se reciclan.
const POOL_PARTICULAS: int = 12
## Fragmentos (trozos de roca, astillas): nodos con física, más caros.
const POOL_FRAGMENTOS: int = 8
## Segundos que vive un efecto antes de volver al pool.
const VIDA_EFECTO: float = 0.7

## Un pool por material, compartido. La clave evita crear un material por
## efecto.
static var _materiales: Dictionary = {}


func _ready() -> void:
	# El grupo es lo que permite encontrarlo desde cualquier sitio sin pasar
	# rutas de nodo ni depender del nombre: el patron es el de `Systems` de la
	# 51.1, creado exactamente para no atar nada a rutas de nodo.
	if not is_in_group(&"gg_system"):
		add_to_group(&"gg_system")
	for i in range(POOL_PARTICULAS):
		var p := GPUParticles3D.new()
		p.name = "Impacto%d" % i
		p.emitting = false
		p.amount = 12
		p.lifetime = 0.6
		p.one_shot = true
		p.explosiveness = 1.0
		p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		# Un material de partículas por tipo, en el propio emisor.
		p.draw_pass_1 = QuadMesh.new()
		(p.draw_pass_1 as QuadMesh).size = Vector2(0.12, 0.12)
		add_child(p)
	for i in range(POOL_FRAGMENTOS):
		var f := MeshInstance3D.new()
		f.name = "Fragmento%d" % i
		f.mesh = _mesh_cubo()
		f.visible = false
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(f)


static func _mesh_cubo() -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(0.08, 0.08, 0.08)
	return m


## §9.1
var system_id: StringName = &"pool_impacto"


## El pool de efectos, por grupo (§9.1). No por nombre de nodo: renombrar el
## nodo no puede romper el efecto del golpe.
static func de(_juego: Node) -> PoolImpacto:
	var arbol: SceneTree = Engine.get_main_loop() as SceneTree
	if arbol == null:
		return null
	for n in arbol.get_nodes_in_group(&"gg_system"):
		var p: PoolImpacto = n as PoolImpacto
		if p != null:
			return p
	return null


## Impacto de arma contra un cuerpo. `tipo` decide el color y la forma:
## "chispa" (metal), "sangre" (carne), "polvo" (tierra), "hielo".
func golpear(pos: Vector3, tipo: String = "chispa", cantidad: int = 1) -> void:
	var color: Color = _color_de(tipo)
	_emision(pos, color, cantidad)


## Un proyectil o un skill de area: mas chispas, mas grandes.
func explosive(pos: Vector3, radio: float = 1.0) -> void:
	_emision(pos, Color(1.0, 0.65, 0.2), int(clampf(radio * 20.0, 8.0, 32.0)))


func _color_de(tipo: String) -> Color:
	match tipo:
		"sangre":
			return Color(0.7, 0.08, 0.08)
		"polvo", "tierra":
			return Color(0.55, 0.45, 0.32)
		"hielo":
			return Color(0.7, 0.9, 1.0)
		"magia":
			return Color(0.6, 0.4, 1.0)
		_:
			return Color(1.0, 0.85, 0.4)  # chispa (metal)


func _emision(pos: Vector3, color: Color, cantidad: int) -> void:
	# Buscar un emisor libre; si no hay, robar el más viejo (perder un efecto
	# es mejor que cortar el frame).
	for p in get_children():
		var gp := p as GPUParticles3D
		if gp == null or not gp.emitting:
			if gp != null:
				_preparar(gp, pos, color, cantidad)
				gp.emitting = true
				return
	# Todos ocupados: robar el primero.
	var primero := get_child(0) as GPUParticles3D
	if primero != null:
		_preparar(primero, pos, color, cantidad)
		primero.emitting = true


func _preparar(gp: GPUParticles3D, pos: Vector3, color: Color, cantidad: int) -> void:
	gp.global_position = pos
	gp.amount = maxi(4, cantidad)
	gp.lifetime = 0.6
	# El material del proceso de partículas va por el `mesh`, no por
	# `material_override` (que es del mesh). Un StandardMaterial3D con
	# `billboard` + `vertex_color_use_as_albedo` hace el resto.
	var mat := _material_de(color)
	if gp.draw_pass_1 is QuadMesh:
		(gp.draw_pass_1 as QuadMesh).material = mat
	# Dirección: hacia arriba y hacia fuera, como un impacto real.
	var dir := Vector3(randf_range(-1, 1), randf_range(0.4, 1.4), randf_range(-1, 1)).normalized()
	var em := ParticleProcessMaterial.new()
	em.direction = dir
	em.spread = 35.0
	em.initial_velocity_min = 3.0
	em.initial_velocity_max = 7.0
	em.gravity = Vector3(0, -14, 0)  # cae: las chispas caen
	em.scale_min = 0.6
	em.scale_max = 1.4
	em.damping_min = 1.0
	em.damping_max = 3.0
	em.color = color
	gp.process_material = em


## Un material por COLOR, cacheado. El billboarding y el uso del color de
## partícula hacen que el mismo material sirva para chispas, sangre y polvo.
static func _material_de(color: Color) -> StandardMaterial3D:
	var clave: String = "%.2f_%.2f_%.2f" % [color.r, color.g, color.b]
	if _materiales.has(clave):
		return _materiales[clave]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # las chispas brillan
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	mat.disable_receive_shadows = true
	_materiales[clave] = mat
	return mat


## Limpia la caché de materiales (los tests).
static func limpiar_cache() -> void:
	_materiales.clear()
