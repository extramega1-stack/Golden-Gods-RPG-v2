class_name Movimiento
extends RefCounted
## Matemática de movimiento del jugador: funciones PURAS y estáticas.
##
## Todo lo que se puede probar sin escena vive aquí: convertir el input
## (relativo a la cámara) en dirección de mundo, calcular la velocidad
## objetivo con llegada suave, y suavizar la velocidad actual hacia ella.
## Player solo las llama; la lógica de feel se testea headless en 2 segundos.
##
## Convención de yaw: rotation.y del CameraRig. Adelante de cámara = -Z
## rotado por el yaw: forward = (-sin(yaw), 0, -cos(yaw)).


## Dirección de mundo (plano XZ) desde el input WASD y el yaw de la cámara.
## move.x: +1 derecha, -1 izquierda. move.y: +1 atrás, -1 adelante.
## Retorna Vector3.ZERO si no hay input.
static func direccion_relativa_camara(move: Vector2, yaw: float) -> Vector3:
	if move.length() < 0.01:
		return Vector3.ZERO
	var sy: float = sin(yaw)
	var cy: float = cos(yaw)
	# forward = (-sy, 0, -cy) ; right = (cy, 0, -sy)
	var dir: Vector3 = Vector3(
		cy * move.x + (-sy) * (-move.y),
		0.0,
		(-sy) * move.x + (-cy) * (-move.y)
	)
	if dir.length() < 0.01:
		return Vector3.ZERO
	return dir.normalized()


## Velocidad objetivo hacia un destino con llegada suave.
## Fuera del radio de frenado: velocidad máxima. Dentro: rampa lineal
## hasta el radio de llegada. Dentro del radio de llegada: cero (quieto).
static func velocidad_meta(
	dir: Vector3, dist: float, vel_max: float,
	radio_llegada: float, radio_frenado: float
) -> Vector3:
	if dist <= radio_llegada:
		return Vector3.ZERO
	var tramo: float = maxf(radio_frenado - radio_llegada, 0.001)
	var factor: float = clampf((dist - radio_llegada) / tramo, 0.0, 1.0)
	return dir * vel_max * factor


## Suavizado exponencial de la velocidad actual hacia la objetivo.
## tasa alta = respuesta inmediata; tasa baja = arranque/frenado pesado.
## Estable para cualquier delta (nunca sobrepasa la meta).
static func suavizar(actual: Vector3, meta: Vector3, delta: float, tasa: float) -> Vector3:
	var t: float = 1.0 - exp(-maxf(tasa, 0.0) * maxf(delta, 0.0))
	return actual.lerp(meta, t)


## Yaw (rotation.y) para que el -Z del cuerpo mire hacia `vel`.
static func yaw_hacia(vel: Vector3) -> float:
	return atan2(-vel.x, -vel.z)
