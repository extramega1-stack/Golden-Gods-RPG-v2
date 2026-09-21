class_name Intent
extends RefCounted
## Intención del jugador para UN frame: datos puros, sin lógica.
##
## Principio de la rebuild (directriz de Juan Diego): el input genera
## INTENCIONES, no ejecuta acciones. Player construye un Intent cada
## physics frame y luego lo consume para moverse; el segundo clic sobre
## el enemigo seleccionado genera intención de atacar (señal), que los
## sistemas futuros ejecutarán.
## Sin nodos, sin escena, sin estado global. Es solo DATOS.

## Movimiento WASD normalizado: x = derecha(+)/izquierda(-),
## y = atrás(+)/adelante(-), relativo al yaw de la cámara.
var move_dir: Vector2 = Vector2.ZERO
## Orden de clic izquierdo: moverse a un punto del mundo.
var tiene_destino: bool = false
var destino: Vector3 = Vector3.ZERO
## Segundo clic sobre el enemigo seleccionado: intención de atacar
## (no se ejecuta aquí).
var quiere_atacar: bool = false
## Objetivo del ataque (null por ahora: no hay enemigos en fase 3).
var objetivo: Entity = null


## Limpia la intención para reutilizar el objeto entre frames.
func limpiar() -> void:
	move_dir = Vector2.ZERO
	tiene_destino = false
	destino = Vector3.ZERO
	quiere_atacar = false
	objetivo = null
