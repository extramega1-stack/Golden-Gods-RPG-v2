class_name VigiaRegion
extends Node
## Vigía de descubrimiento de regiones (Fase 12).
##
## Sondea la posición de `jugador` cada 0.5 s y emite `descubierta` UNA vez
## por región por sesión. `region_actual()` devuelve la última región donde
## se vio al jugador ({} si aún no se ha sondeado ninguna).

signal descubierta(region: Dictionary)

const INTERVALO: float = 0.5

var jugador: Node3D
var region_db: RegionDB

var _descubiertas: Dictionary = {}
var _actual: Dictionary = {}
var _acumulado: float = 0.0


func _process(delta: float) -> void:
	if jugador == null or region_db == null:
		return
	_acumulado += delta
	if _acumulado < INTERVALO:
		return
	_acumulado = 0.0
	# global_position en un Node3D tipado: acceso seguro, tipo explícito.
	var pos: Vector3 = jugador.global_position
	var r: Dictionary = region_db.region_en(pos.x, pos.z)
	if r.is_empty():
		return
	_actual = r
	var rid: String = str(r.get("id", ""))
	if rid == "" or _descubiertas.has(rid):
		return
	_descubiertas[rid] = true
	descubierta.emit(r)


## Última región sondeada ({} si ninguna todavía).
func region_actual() -> Dictionary:
	return _actual


## Olvida los descubrimientos (p.ej. al empezar una partida nueva).
func reiniciar_descubrimientos() -> void:
	_descubiertas.clear()
