class_name Refugio
extends Node3D
## Fase 60: el Refugio del Verdugo. Punto reclamable que da un ancla de
## respawn, un nodo de viaje rápido sin costo y un presupuesto de piezas
## construibles (fase 61).
##
## YA ERA CANON: el spec §6 Dominio 7 lo lista como "refugio del Verdugo
## (Piedraceniza, 4 módulos, sala de trofeos)". Esta fase es la primera vez
## que se construye.
##
## DÓNDE SE ANCLA EL RESPAWN: el `RespawnHeros` de la fase 51 toma su punto
## seguro de `CiudadLuna.punto_aparicion_jugador()`. Cuando el jugador
## RECLAMA un refugio, ese refugio pasa a ser su punto seguro: se cambia el
## ancla del Player y la del respawn. Morir lejos de casa y reaparecer en el
## refugio es la decisión que hace que un refugio valga la pena.
##
## La altura NUNCA sale del dato: `data/refugios.json` tiene [x, z] y la y la
## consulta el terreno (mismo criterio que la fase 55, tras el hallazgo de
## que las plazas de `viaje_rapido.json` tienen un `y` desfasado hasta 175 u).

const DEFAULT_PIEZAS_MAX: int = 24

## Emitida al reclamar. La UI y el sistema de respawn la escuchan.
signal reclamado(refugio_id: String)
## Emitida al colocar la primera pieza (fase 61).
signal pieza_colocada(pieza_id: String, total: int)

var refugio_id: String = ""
var nombre: String = "Refugio"
var ciudad: String = ""
## Radio en el que se considera que el jugador está "en casa".
var radio: float = 40.0
## Techo de piezas. Sale del dato (es presupuesto de VRAM, §9.5).
var piezas_max: int = DEFAULT_PIEZAS_MAX
## Las piezas colocadas: un array de {tipo, x, z, rot}. NUNCA nodos.
var _piezas: Array = []

var _reclamado: bool = false
var _marca: MeshInstance3D = null


## Configura desde el id de `data/refugios.json`. La altura se resuelve
## DESPUÉS: la fija el Player con el terreno, o queda en 0.
func configurar_por_id(id: String) -> bool:
	if not RefugioDB.existe(id):
		return false
	var d: Dictionary = RefugioDB.obtener(id)
	refugio_id = id
	nombre = RefugioDB.nombre_de(id)
	ciudad = RefugioDB.ciudad_de(id)
	radio = RefugioDB.radio(id)
	piezas_max = RefugioDB.piezas_max(id)
	global_position = Vector3(float(d.get("x", 0.0)), 0.0, float(d.get("z", 0.0)))
	return true


func esta_reclamado() -> bool:
	return _reclamado


## Reclamar. Idempotente. Devuelve false si el nivel no alcanza.
func reclamar(jugador_nivel: int) -> bool:
	if _reclamado:
		return false
	if jugador_nivel < nivel_minimo():
		return false
	_reclamado = true
	_construir_marca()
	reclamado.emit(refugio_id)
	return true


func nivel_minimo() -> int:
	return int(RefugioDB.obtener(refugio_id).get("nivel_min", 1))


## Libera el refugio para otro jugador (no pasa nada en single-player, pero
## deja el sistema honesto si algún día el guardado se migra).
func liberar() -> void:
	_reclamado = false
	_piezas.clear()
	if _marca != null and is_instance_valid(_marca):
		_marca.queue_free()
		_marca = null


# --- piezas (fase 61) --------------------------------------------------

## Cuántas piezas hay colocadas.
func piezas() -> int:
	return _piezas.size()


func piezas_restantes() -> int:
	return maxi(0, piezas_max - _piezas.size())


func puede_colocar() -> bool:
	return _reclamado and _piezas.size() < piezas_max


## Coloca una pieza. Devuelve false si no está reclamado o se pasó del
## presupuesto de VRAM.
func colocar(tipo: String, offset: Vector3, rot: float) -> bool:
	if not puede_colocar():
		return false
	_piezas.append({"tipo": tipo, "x": offset.x, "z": offset.z, "rot": rot})
	pieza_colocada.emit(tipo, _piezas.size())
	return true


## Quita la última pieza colocada (deshacer).
func quitar_ultima() -> bool:
	if _piezas.is_empty():
		return false
	_piezas.pop_back()
	return true


## Las piezas, para que la fase 61 las instancien.
func piezas_lista() -> Array:
	return _piezas.duplicate()


func cargar_piezas(lista: Array) -> void:
	_piezas = lista.duplicate()
	# Un save viejo o manipulado no puede meter más piezas que el techo.
	while _piezas.size() > piezas_max:
		_piezas.pop_back()


# ---Jugador dentro ----------------------------------------------------

func contiene(pos: Vector3) -> bool:
	return Vector2(pos.x - global_position.x, pos.z - global_position.z).length() <= radio


# --- visual -----------------------------------------------------------

func _ready() -> void:
	add_to_group(&"refugios")


func _construir_marca() -> void:
	# Un anillo dorado en el suelo: la marca del que lo reclamó.
	_marca = MeshInstance3D.new()
	var toro := TorusMesh.new()
	toro.inner_radius = 3.4
	toro.outer_radius = 3.8
	_marca.mesh = toro
	_marca.position = Vector3(0.0, 0.2, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.68, 0.25)
	m.emission_enabled = true
	m.emission = Color(0.9, 0.7, 0.2)
	m.emission_energy_multiplier = 1.2
	_marca.material_override = m
	add_child(_marca)


# --- save -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"id": refugio_id,
		"reclamado": _reclamado,
		"piezas": _piezas.duplicate(),
	}


func cargar_estado(d: Dictionary) -> void:
	_reclamado = bool(d.get("reclamado", false))
	cargar_piezas(d.get("piezas", []))
	if _reclamado:
		_construir_marca()
