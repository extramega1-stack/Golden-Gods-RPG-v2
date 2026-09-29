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
## OJO (bloque 65): estas constantes son los VALORES POR DEFECTO y la
## referencia de diseño, pero ya no mandan. Lo que manda es `Opciones`
## (`user://opciones.json`): la sensibilidad, la distancia de cámara, el FOV y
## el invertir-Y son ajustables por el jugador. Se leen por getters, no por
## estas constantes, para que cambiar un ajuste se oiga y se vea al instante.
const SENSIBILIDAD: float = 0.0042 ## Radianes por píxel de drag (default).
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
	# Bloque 65: la distancia de arranque sale de la opción del jugador.
	_dist_obj = DIST_INICIAL * Opciones.escala_camara()
	_pitch.position.y = ALTURA
	_pitch.rotation.x = PITCH_INICIAL
	_brazo.spring_length = _dist_obj
	_aplicar_fov()
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


## Fase 51: reposiciona la cámara SIN interpolar. Necesario tras el
## teletransporte del respawn: el lerp de `_process` cruzaría el mapa entero
## (el ancla puede estar a 10 km) y durante un rato se vería la cámara
## volando sobre el mundo.
##
## Mismo criterio que `_ready()`: pega la cámara al objetivo de golpe.
func snap_seguimiento() -> void:
	if _objetivo == null or not is_instance_valid(_objetivo):
		return
	global_position = _objetivo.global_position
	# El trauma moría con el jugador; dejarlo a medias daría un shake suelto.
	trauma = 0.0
	if _camara != null and is_instance_valid(_camara):
		_camara.h_offset = 0.0
		_camara.v_offset = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_arrastrando = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-PASO_ZOOM)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(PASO_ZOOM)
	elif event is InputEventMouseMotion:
		if _arrastrando:
			var mm: InputEventMouseMotion = event
			var sens: float = _sensibilidad()
			_yaw_obj -= mm.relative.x * sens
			# El invertir-Y va en la escritura del pitch, no en el clamp: así el
			# rango del ángulo es el mismo en las dos direcciones y no hay que
			# tocar PITCH_MIN/PITCH_MAX.
			var dp: float = mm.relative.y * sens
			_pitch_obj = clampf(
				_pitch_obj + (dp if Opciones.booleano("invertir_y") else -dp),
				PITCH_MIN, PITCH_MAX
			)


## Bloque 65: el zoom usa el rango del jugador, escalado por su factor de
## distancia. Con `escala_camara = 0.7` el rango entero se acerca un 30 %.
func _zoom(delta: float) -> void:
	var e: float = Opciones.escala_camara()
	_dist_obj = clampf(_dist_obj + delta * e, DIST_MIN * e, DIST_MAX * e)


func _sensibilidad() -> float:
	var s: float = Opciones.flotante("sensibilidad", SENSIBILIDAD)
	return maxf(s, 0.0001)


## Bloque 65: FOV ajustable. Se aplica al arrancar y cuando el panel de
## opciones cambia el valor.
func _aplicar_fov() -> void:
	if _camara != null and is_instance_valid(_camara):
		_camara.fov = Opciones.flotante("fov", 65.0)


## El panel de opciones llama a esto para que el cambio se vea sin reabrir.
func reponer_opciones() -> void:
	_aplicar_fov()
	_zoom(0.0)
