class_name CameraRig
extends Node3D
## Cámara en tercera persona baja detrás del héroe (estilo L2/MU).
##
## El drag con botón derecho y la rueda escriben OBJETIVOS (yaw/pitch/
## distancia); la cámara los persigue con amortiguamiento, así el giro
## se siente suave y al soltar "desliza" un poco. El input nunca mueve
## la cámara directamente.
## Estructura esperada en la escena: CameraRig → Pitch (Node3D) →
## SpringArm3D → Camera3D. El SpringArm3D evita que la cámara atraviese
## paredes (anti-clip del motor).
## Sin referencias a UI ni a ningún otro sistema.

## --- Game feel: todos los tunables en un solo sitio ---
const SENSIBILIDAD: float = 0.0042 ## Radianes por píxel de drag.
const K_ROT: float = 12.0          ## Qué tan rápido persigue yaw/pitch.
const K_POS: float = 9.0           ## Qué tan rápido sigue al jugador.
const K_ZOOM: float = 10.0         ## Qué tan rápido responde el zoom.
const DIST_INICIAL: float = 7.0    ## Distancia cámara↔héroe al arrancar.
const DIST_MIN: float = 3.5        ## Zoom mínimo (rueda).
const DIST_MAX: float = 13.0       ## Zoom máximo (rueda).
const PASO_ZOOM: float = 1.0       ## Cuánto acerca/aleja cada tick de rueda.
const PITCH_INICIAL: float = -0.38 ## Ángulo inicial (~-22°: baja, detrás).
const PITCH_MIN: float = -1.05     ## Límite mirando hacia abajo.
const PITCH_MAX: float = 0.30      ## Límite mirando hacia arriba.
const ALTURA: float = 1.5          ## Altura del pivote sobre los pies.

## Ruta al nodo que sigue (el Player; se asigna en el .tscn).
@export var ruta_objetivo: NodePath

var _objetivo: Node3D = null
var _yaw_obj: float = 0.0
var _pitch_obj: float = PITCH_INICIAL
var _dist_obj: float = DIST_INICIAL
var _arrastrando: bool = false

@onready var _pitch: Node3D = $Pitch
@onready var _brazo: SpringArm3D = $Pitch/SpringArm3D


func _ready() -> void:
	if ruta_objetivo != NodePath(""):
		_objetivo = get_node_or_null(ruta_objetivo) as Node3D
	_yaw_obj = rotation.y
	_pitch_obj = PITCH_INICIAL
	_dist_obj = DIST_INICIAL
	_pitch.position.y = ALTURA
	_pitch.rotation.x = PITCH_INICIAL
	_brazo.spring_length = DIST_INICIAL
	if _objetivo != null:
		global_position = _objetivo.global_position


func _process(delta: float) -> void:
	if _objetivo != null:
		var tp: float = 1.0 - exp(-K_POS * delta)
		global_position = global_position.lerp(_objetivo.global_position, tp)
	var tr: float = 1.0 - exp(-K_ROT * delta)
	rotation.y = lerp_angle(rotation.y, _yaw_obj, tr)
	_pitch.rotation.x = lerp_angle(_pitch.rotation.x, _pitch_obj, tr)
	var tz: float = 1.0 - exp(-K_ZOOM * delta)
	_brazo.spring_length = lerpf(_brazo.spring_length, _dist_obj, tz)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_arrastrando = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist_obj = clampf(_dist_obj - PASO_ZOOM, DIST_MIN, DIST_MAX)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist_obj = clampf(_dist_obj + PASO_ZOOM, DIST_MIN, DIST_MAX)
	elif event is InputEventMouseMotion:
		if _arrastrando:
			var mm: InputEventMouseMotion = event
			_yaw_obj -= mm.relative.x * SENSIBILIDAD
			_pitch_obj = clampf(
				_pitch_obj - mm.relative.y * SENSIBILIDAD, PITCH_MIN, PITCH_MAX
			)
