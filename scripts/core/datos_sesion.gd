class_name DatosSesion
extends RefCounted
## Holder estático de la identidad del héroe entre cambios de escena (sin
## autoload): la pantalla de título y la creación de personaje la escriben;
## la demo de juego la lee al arrancar y la limpia.
##
## Flujo fase 11:
## - "Nueva partida" (título) → creación de personaje → `nueva_partida()`
##   → escena de juego → `aplicar_a(jugador)` → `limpiar()`.
## - "Continuar" (título) → `pedir_continuar()` → escena de juego → la
##   carga del save restaura la identidad (aplicar_a no toca nada) →
##   `limpiar()`.

static var nombre: String = ""
static var clase_id: String = "guerrero"
static var continuar: bool = false


## Nueva partida con el nombre y la clase elegidos en la creación.
## Una clase desconocida cae a "guerrero" (tolerante).
static func nueva_partida(p_nombre: String, p_clase_id: String) -> void:
	nombre = p_nombre
	if ClaseDB.existe(p_clase_id):
		clase_id = p_clase_id
	else:
		clase_id = "guerrero"
	continuar = false


## El jugador eligió "Continuar": la identidad la restaura la carga.
static func pedir_continuar() -> void:
	continuar = true


## Limpia la sesión (la demo lo llama tras aplicarla: nada persiste entre
## partidas).
static func limpiar() -> void:
	nombre = ""
	clase_id = "guerrero"
	continuar = false


## Aplica la identidad al jugador recién instanciado (nueva partida).
## Con `j == null` no hace nada; con `continuar == true` tampoco toca nada
## (la carga del save restaura nombre/clase/stats). La UI solo lee después.
static func aplicar_a(j: Player) -> void:
	if j == null:
		return
	if continuar:
		return
	j.fijar_identidad(nombre, clase_id)
	j.aplicar_clase(clase_id)
