class_name Pickup
extends Node3D
## Botín en el suelo (oro o item): visual placeholder + recogida por proximidad.
##
## Emite `recogido(drop)` cuando el jugador se acerca lo suficiente; quien
## conecta la señal decide el efecto (el oro lo suma el Player, los items
## quedan como datos para el inventario de la fase 5). Sin referencias a
## otros sistemas: el jugador se busca por el grupo "jugador".

signal recogido(drop: Dictionary)

const RADIO_RECOGIDA: float = 1.6
const ALTURA_FLOTE: float = 0.5

var drop: Dictionary = {}

var _t: float = 0.0
var _malla: MeshInstance3D = null


func _ready() -> void:
	_malla = MeshInstance3D.new()
	var esfera: SphereMesh = SphereMesh.new()
	esfera.radius = 0.28
	esfera.height = 0.56
	_malla.mesh = esfera
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	if str(drop.get("tipo", "")) == "oro":
		mat.albedo_color = Color(1.0, 0.78, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.65, 0.1)
		mat.emission_energy_multiplier = 1.5
	else:
		mat.albedo_color = Color(0.45, 0.6, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.35, 0.9)
		mat.emission_energy_multiplier = 0.8
	_malla.material_override = mat
	_malla.position.y = ALTURA_FLOTE
	add_child(_malla)
	_t = randf() * TAU


func _process(delta: float) -> void:
	_t += delta
	if _malla != null:
		_malla.position.y = ALTURA_FLOTE + sin(_t * 2.5) * 0.12
		_malla.rotation.y += delta * 1.5
	_revisar_recogida()


## ¿El jugador está encima? Emite y se destruye. Pública para tests.
func _revisar_recogida() -> void:
	var arbol: SceneTree = get_tree()
	if arbol == null:
		return
	var j: Node3D = arbol.get_first_node_in_group("jugador") as Node3D
	if j == null:
		return
	var d: Vector3 = j.global_position - global_position
	d.y = 0.0
	if d.length() <= RADIO_RECOGIDA:
		recogido.emit(drop)
		queue_free()
