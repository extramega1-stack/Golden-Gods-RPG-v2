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

## --- Game feel: screen shake (fase 19) ---
const TRAUMA_DECAIMIENTO: float = 1.8 ## Cuánto trauma se pierde por segundo.
const SHAKE_MAX: float = 0.35         ## Offset máximo de cámara a trauma 1.
## Trauma actual (0 = quieta, 1 = sacudida máxima). Crece con
## `agregar_trauma()` y decae solo; el offset usa trauma².
var trauma: float = 0.0

## Ruta al nodo que sigue (el Player; se asigna en el .tscn).
@export var ruta_objetivo: NodePath

var _objetivo: Node3D = null
var _yaw_obj: float = 0.0
var _pitch_obj: float = PITCH_INICIAL
var _dist_obj: float = DIST_INICIAL
var _arrastrando: bool = false

@onready var _pitch: Node3D = $Pitch
@onready var _brazo: SpringArm3D = $Pitch/SpringArm3D
@onready var _camara: Camera3D = $Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	add_to_group("camera_rig")
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
	# Fase 19 — screen shake: el trauma decae solo y el offset (h/v_offset
	# de la cámara) usa trauma² para un decaimiento con pegada.
	if trauma > 0.0:
		trauma = maxf(trauma - TRAUMA_DECAIMIENTO * delta, 0.0)
		var sh: float = trauma * trauma * SHAKE_MAX
		_camara.h_offset = randf_range(-sh, sh)
		_camara.v_offset = randf_range(-sh, sh)
	elif _camara.h_offset != 0.0 or _camara.v_offset != 0.0:
		_camara.h_offset = 0.0
		_camara.v_offset = 0.0


## Suma trauma de screen shake (0..1). La llama GameFeel.
func agregar_trauma(cantidad: float) -> void:
	trauma = minf(trauma + cantidad, 1.0)


## Yaw actual de la cámara (radianes). Lo lee la brújula de la fase 13.
func yaw() -> float:
	return rotation.y


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
