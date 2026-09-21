class_name IndicadorSeleccion
extends Node3D
## Indicador de selección de la fase 5.1: anillo dorado bajo los pies de la
## entidad seleccionada (mob o NPC). Solo LEE: escucha la señal
## `seleccion_cambiada` del Player y sigue la posición del objetivo.
## Sin selección (o con el objetivo muerto), se oculta.

var _objetivo: Entity = null


func _ready() -> void:
	_construir_anillo()
	visible = false


func _construir_anillo() -> void:
	var toro: TorusMesh = TorusMesh.new()
	toro.inner_radius = 0.55
	toro.outer_radius = 0.78
	toro.rings = 40
	toro.ring_segments = 8
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.25)
	var anillo: MeshInstance3D = MeshInstance3D.new()
	anillo.name = "Anillo"
	anillo.mesh = toro
	anillo.material_override = mat
	add_child(anillo)


## Conecta al jugador (solo lectura de su señal).
func conectar(j: Player) -> void:
	if j == null:
		return
	if not j.seleccion_cambiada.is_connected(_al_seleccion):
		j.seleccion_cambiada.connect(_al_seleccion)
	_al_seleccion(j.seleccion)


## Objetivo actual (tests + UI futura).
func objetivo() -> Entity:
	return _objetivo


func _al_seleccion(e: Entity) -> void:
	_objetivo = e


func _process(_delta: float) -> void:
	if _objetivo == null or not _objetivo.esta_vivo():
		visible = false
		return
	visible = true
	var p: Vector3 = _objetivo.global_position
	global_position = Vector3(p.x, p.y + 0.08, p.z)
