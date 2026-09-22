class_name StreamingMobs
extends Node
## Streaming por distancia de los mobs del mundo abierto — Fase 12.1.
##
## El hotfix del "va super lageado": la fase 12 instanciaba los 1121 creeps
## de `data/spawns.json` de una vez como nodos `Enemy` completos (cada uno
## con `_physics_process`, `move_and_slide`, material propio y draw call).
## Ahora los spawns viven como DATOS (registros) y solo se instancian como
## nodos los cercanos al jugador; los lejanos se liberan. Con histéresis:
## se instancia dentro de `radio_alta` y se libera más allá de `radio_baja`
## (banda intermedia sin churn: el streaming es invisible).
##
## El respawn (SpawnerMobs, fase 9) sigue siendo la autoridad de los timers:
## el streaming solo decide dónde hay nodo. La puerta de reaparición del
## spawner veta reaparecer lejos del jugador (reintenta cada pocos segundos).
##
## API chica:
## - `configurar(registros)`: Array de `{arquetipo: String, origen: Vector3}`.
## - `fijar_factory(f)`: `Callable(arquetipo_id, posicion) -> Enemy`.
## - `fijar_jugador(j)`, `fijar_spawner(s)`.
## - `fijar_radios(alta, baja)`: override para tests (los datos mandan si no).
## - `actualizar()`: evaluación pura/testeable (la llama `_process`).
## - `conteo_instanciados()`, `conteo_registros()`: depuración y tests.
## Señales: `mob_instanciado(e)` (la demo conecta botín/muerte y vigila),
## `mob_liberado(e)` (la demo lo saca de su lista).

signal mob_instanciado(e: Enemy)
signal mob_liberado(e: Enemy)

const RUTA_DATOS: String = "res://data/streaming.json"
## Margen (m) para asociar un reaparecido del spawner con su registro.
const MARGEN_REAPARECIDO: float = 8.0

## Cada registro: {arquetipo: String, origen: Vector3,
##                 nodo: Enemy (o null), muerto: bool}.
var _registros: Array = []
var _factory: Callable = Callable()
var _jugador: Node3D = null
var _spawner: SpawnerMobs = null
var _radio_alta: float = 600.0
var _radio_baja: float = 800.0
var _intervalo_seg: float = 0.25
var _acum: float = 0.0
var _reparto_ia: int = 0
## Fase 12.1: si los radios se fijaron a mano (tests), los datos no los pisan.
var _radios_manual: bool = false


func _ready() -> void:
	var datos: Dictionary = _cargar_datos()
	if not _radios_manual:
		_radio_alta = float(datos.get("radio_alta", 600.0))
		_radio_baja = float(datos.get("radio_baja", 800.0))
		if _radio_baja < _radio_alta:
			_radio_baja = _radio_alta
	_intervalo_seg = float(datos.get("intervalo_seg", 0.25))
	if _intervalo_seg <= 0.0:
		_intervalo_seg = 0.25


static var _datos_cache: Dictionary = {}


## Lee el JSON UNA vez (estático cacheado, mismo patrón que los DBs).
static func _cargar_datos() -> Dictionary:
	if not _datos_cache.is_empty():
		return _datos_cache
	var texto: String = FileAccess.get_file_as_string(RUTA_DATOS)
	if texto == "":
		push_warning("[StreamingMobs] no se pudo leer %s; usando defaults" % RUTA_DATOS)
		return {}
	# parse_string retorna Variant: NUNCA `:=` aquí (warning como error).
	var crudo = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[StreamingMobs] %s no es un diccionario JSON válido" % RUTA_DATOS)
		return {}
	_datos_cache = crudo
	return _datos_cache


func configurar(registros: Array) -> void:
	_registros.clear()
	for r in registros:
		if not (r is Dictionary):
			continue
		var rd: Dictionary = r
		_registros.append({
			"arquetipo": str(rd.get("arquetipo", "")),
			"origen": rd.get("origen", Vector3.ZERO),
			"nodo": null,
			"muerto": false,
		})


func fijar_factory(f: Callable) -> void:
	_factory = f


func fijar_jugador(j: Node3D) -> void:
	_jugador = j


func fijar_spawner(s: SpawnerMobs) -> void:
	_spawner = s
	if _spawner != null and not _spawner.reaparecido.is_connected(_al_reaparecido):
		_spawner.reaparecido.connect(_al_reaparecido)


## Override de radios para tests (los datos mandan en el juego).
func fijar_radios(alta: float, baja: float) -> void:
	_radio_alta = alta
	_radio_baja = maxi(baja, alta)
	_radios_manual = true


func radio_alta() -> float:
	return _radio_alta


func conteo_registros() -> int:
	return _registros.size()


func conteo_instanciados() -> int:
	var n: int = 0
	for r in _registros:
		var rd: Dictionary = r
		var nodo: Enemy = rd["nodo"] as Enemy
		if nodo != null and is_instance_valid(nodo):
			n += 1
	return n


func _process(delta: float) -> void:
	_acum += delta
	if _acum < _intervalo_seg:
		return
	_acum = 0.0
	actualizar()


## Evalúa cada registro contra la posición del jugador: instancia los
## cercanos sin nodo (que no estén muertos pendientes de respawn) y libera
## los nodos más allá del radio de baja. Pública/testeable.
func actualizar() -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	if not _factory.is_valid():
		return
	var jp: Vector3 = _jugador.global_position
	for r in _registros:
		var rd: Dictionary = r
		var nodo: Enemy = rd["nodo"] as Enemy
		if nodo != null and not is_instance_valid(nodo):
			nodo = null
			rd["nodo"] = null
		var origen: Vector3 = rd["origen"]
		var d: float = _dist_plana(jp, origen)
		if nodo == null:
			# Sin nodo: instanciar solo si está cerca y no hay un respawn
			# pendiente del spawner para este registro.
			if d <= _radio_alta and not bool(rd["muerto"]):
				_instanciar(rd)
		elif d > _radio_baja:
			_liberar(rd)


static func _dist_plana(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


func _instanciar(rd: Dictionary) -> void:
	var nuevo: Variant = _factory.call(str(rd["arquetipo"]), rd["origen"])
	var e: Enemy = nuevo as Enemy
	if e == null or not is_instance_valid(e):
		push_warning("[StreamingMobs] la factory no devolvió un Enemy para '%s'"
				% str(rd["arquetipo"]))
		return
	# Fase 12.1: reparto del tick de IA para que no piensen todos a la vez.
	e.reparto = _reparto_ia % 8
	_reparto_ia += 1
	rd["nodo"] = e
	rd["muerto"] = false
	if not e.murio.is_connected(_al_murio_nodo):
		e.murio.connect(_al_murio_nodo.bind(e))
	mob_instanciado.emit(e)


func _liberar(rd: Dictionary) -> void:
	var nodo: Enemy = rd["nodo"] as Enemy
	rd["nodo"] = null
	if nodo == null or not is_instance_valid(nodo):
		return
	if _spawner != null:
		_spawner.olvidar(nodo)
	if nodo.murio.is_connected(_al_murio_nodo):
		nodo.murio.disconnect(_al_murio_nodo)
	# Se avisa ANTES de liberar: la demo lo saca de su lista de guardado.
	mob_liberado.emit(nodo)
	nodo.queue_free()


## Un nodo instanciado murió: el registro queda marcado hasta que el
## spawner lo reaparezca (el cadáver lo gestiona la demo como siempre).
func _al_murio_nodo(_fuente: Entity, e: Enemy) -> void:
	var rd: Dictionary = _registro_de(e)
	if rd.is_empty():
		return
	rd["muerto"] = true


## El spawner reapareció un mob: asociarlo a su registro (por cercanía al
## origen) para que el streaming lo conozca y no lo duplique.
func _al_reaparecido(nuevo: Enemy) -> void:
	if nuevo == null or not is_instance_valid(nuevo):
		return
	for r in _registros:
		var rd: Dictionary = r
		if not bool(rd["muerto"]):
			continue
		var origen: Vector3 = rd["origen"]
		if _dist_plana(origen, nuevo.global_position) <= MARGEN_REAPARECIDO:
			rd["muerto"] = false
			rd["nodo"] = nuevo
			nuevo.reparto = _reparto_ia % 8
			_reparto_ia += 1
			if not nuevo.murio.is_connected(_al_murio_nodo):
				nuevo.murio.connect(_al_murio_nodo.bind(nuevo))
			return


func _registro_de(e: Enemy) -> Dictionary:
	for r in _registros:
		var rd: Dictionary = r
		if rd["nodo"] == e:
			return rd
	return {}
