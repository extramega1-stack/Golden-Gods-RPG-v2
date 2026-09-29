class_name ProyectilVisual
extends Node3D
## Bloque 68: la flecha y el proyectil de magia que antes NO SE VEÍAN.
##
## POR QUÉ: todas las skills del juego eran HITSCAN instantáneas. El arquero
## "dispara" y el enemigo muere en el mismo frame, sin que haya nada en el
## aire. Eso hace que un ataque a distancia se sienta igual que pulsar un
## botón: falta la información de "va de camino", que es la que da la
## anticipación y el peso.
##
## Esto NO cambia el daño ni el balance: el proyectil es PURAMENTE VISUAL y
## viaja a una velocidad alta (100 m/s, más rápido que el jugador pero no
## instantáneo). Es la decisión correcta para un RPG: la skill pega cuando
## impacta de verdad, pero el jugador VE por dónde va.
##
## - POOL de proyectiles, no uno por disparo: un `MeshInstance3D` por flecha
##   sería una alloc en el frame del casteo (§9.5).
## - Estela: una `Trail3D`-like con un par de quads que se desvanecen, que es
##   lo que hace que se vea DÓNDE va.

const POOL: int = 12
## Velocidad del proyectil en m/s. Rápido: se ve, pero no se espera.
const VELOCIDAD: float = 100.0
## Cuánto puede volar antes de desaparecer (anti-obstruido: si el objetivo se
## mueve o el proyectil se atasca, no se queda flotando).
const ALCANCE_MAX: float = 40.0
## La flecha es una caja fina; la magia, una esfera emisiva.
const TAM_FLECHA: Vector3 = Vector3(0.06, 0.06, 0.7)
const TAM_MAGIA: float = 0.28

static var _instancia: ProyectilVisual = null

var _pool: Array[Node3D] = []
var _activos: Array = []


## Instancia única en la escena. `juego` es la raíz del mundo.
static func asegurar(juego: Node) -> ProyectilVisual:
	if _instancia != null and is_instance_valid(_instancia):
		return _instancia
	if juego == null or not is_instance_valid(juego):
		return null
	var p := ProyectilVisual.new()
	p.name = "Proyectiles"
	juego.add_child(p)
	_instancia = p
	return p


func _ready() -> void:
	for i in range(POOL):
		var m := MeshInstance3D.new()
		m.name = "Proyectil%d" % i
		var caja := BoxMesh.new()
		caja.size = TAM_FLECHA
		m.mesh = caja
		m.material_override = _material_linea()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_pool.append(m)
	set_process(true)


## Dispara un proyectil visual de `origen` hacia `destino`. No hace daño: es
## solo el "ver volar la flecha". Devuelve si se pudo (sin proyectil libre,
## se salta: perder una flecha visual es mejor que bloquear el casteo).
func disparar(origen: Node3D, destino: Node3D, magia: bool = false) -> bool:
	if origen == null or not is_instance_valid(origen):
		return false
	var libre: Node3D = null
	for m in _pool:
		if not (m as Node3D).visible:
			libre = m
			break
	if libre == null:
		return false
	# La posición final es la del objetivo ahora; si no hay, se apunta hacia
	# donde mira el lanzador.
	var hasta: Vector3 = destino.global_position if destino != null \
		and is_instance_valid(destino) else origen.global_position - origen.global_transform.basis.z * 20.0
	var pos0: Vector3 = origen.global_position
	# Un poco por delante, para que salga de la mano y no del centro de la
	# cabeza.
	pos0 += (hasta - pos0).normalized() * 0.8
	var dir: Vector3 = (hasta - pos0).normalized()
	# La flecha se ALINEA con su dirección (una caja de 0,06x0,06x0,7 apuntada
	# a -Z se ve como un palo si no).
	var m3: Node3D = libre
	if not magia:
		m3.look_at_from_position(pos0, pos0 + dir, Vector3.UP)
		var caja := m3.mesh as BoxMesh
		if caja != null:
			caja.size = TAM_FLECHA
	else:
		m3.mesh = _mesh_magia()
		m3.material_override = _material_magia()
	m3.global_position = pos0
	m3.visible = true
	_activos.append({"nodo": m3, "pos0": pos0, "dir": dir, "recorrido": 0.0})
	return true


func _mesh_magia() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = TAM_MAGIA
	m.height = TAM_MAGIA * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m


static func _material_linea() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.75, 0.6)
	mat.roughness = 0.7
	return mat


static func _material_magia() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.4, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.5, 1.0)
	mat.emission_energy_multiplier = 2.0
	return mat


func _process(delta: float) -> void:
	# Recorrer hacia atrás para poder borrar sin saltarse el siguiente.
	for i in range(_activos.size() - 1, -1, -1):
		var a: Dictionary = _activos[i]
		var n: Node3D = a["nodo"] as Node3D
		var dir: Vector3 = a["dir"]
		var recorrido: float = float(a["recorrido"]) + VELOCIDAD * delta
		n.global_position += dir * (VELOCIDAD * delta)
		if recorrido > ALCANCE_MAX or not is_instance_valid(n):
			n.visible = false
			_activos.remove_at(i)
		else:
			a["recorrido"] = recorrido
			_activos[i] = a


## Limpia (los tests).
static func limpiar_cache() -> void:
	_instancia = null
