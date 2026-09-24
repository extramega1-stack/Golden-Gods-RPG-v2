class_name Arena
extends Node
## Arena PvE por oleadas (fase 41): 10 oleadas data-driven (`data/arena.json`)
## en un campo remoto, con recompensas escaladas y trofeos locales.
##
## Flujo: iniciar() → oleada N (spawns en anillo vía factory inyectada) →
## al caer todos: recompensa (oro + XP extra) → descanso → N+1 … → victoria
## al superar la 10. Derrota si el jugador muere. `detener()` limpia (los
## mobs vuelven al pool) e `iniciar()` lo llama primero (idempotente).
## Los mobs dan su XP/loot normal (la demo conecta botín y muertes de
## misión); la recompensa de oleada es EXTRA. Trofeos: mejor_oleada y
## victorias (bloque "arena" del save, v12).

const SAVE_VERSION_ARENA: int = 1
const RADIO_SPAWN: float = 25.0

signal oleada_iniciada(n: int)
signal oleada_superada(n: int, oro: int, xp: int)
signal arena_terminada(victoria: bool, oleada: int)

var _jugador: Player = null
var _factory: Callable = Callable()
var _pool: PoolMobs = null
var _arquetipos: Dictionary = {}
var _oleadas: Array = []
var _centro: Vector2 = Vector2.ZERO
var _radio: float = 40.0
var _descanso_seg: float = 8.0
var _oro_base: int = 25
var _xp_base: int = 30

var _activa: bool = false
var _oleada: int = 0
var _vivos: Array[Enemy] = []
var _espera: float = 0.0

var mejor_oleada: int = 0
var victorias: int = 0


## Carga el JSON (datos crudos, sin validar de más: la demo los trae).
func configurar(datos: Dictionary) -> void:
	_oleadas = datos.get("oleadas", [])
	var c: Array = datos.get("centro", [0.0, 0.0])
	_centro = Vector2(float(c[0]), float(c[1])) if c.size() >= 2 else Vector2.ZERO
	_radio = float(datos.get("radio", 40.0))
	_descanso_seg = float(datos.get("descanso_seg", 8.0))
	_oro_base = int(datos.get("oro_base", 25))
	_xp_base = int(datos.get("xp_base", 30))


func fijar_factory(f: Callable) -> void:
	_factory = f


## Pool para devolver los mobs al detener (reciclaje fase 20).
func fijar_pool(p: PoolMobs) -> void:
	_pool = p


## Arquetipos para el bloque élite de cada oleada.
func fijar_arquetipos(arqs: Dictionary) -> void:
	_arquetipos = arqs


func fijar_jugador(j: Player) -> void:
	if _jugador != null and is_instance_valid(_jugador):
		if _jugador.murio.is_connected(_al_morir_jugador):
			_jugador.murio.disconnect(_al_morir_jugador)
	_jugador = j
	if _jugador != null:
		_jugador.murio.connect(_al_morir_jugador)


## ¿Hay una arena en curso? Pública para demo y tests.
func activa() -> bool:
	return _activa


## Oleada actual (0 = inactiva). Pública para tests.
func oleada() -> int:
	return _oleada if _activa else 0


## Vivos de la oleada actual (limpia liberados). Pública para tests.
func vivos() -> int:
	var quedan: Array[Enemy] = []
	for e in _vivos:
		if is_instance_valid(e):
			quedan.append(e)
	_vivos = quedan
	return _vivos.size()


## Arranca (limpia antes si había una en curso). Sin jugador/factory/datos
## no hace nada.
func iniciar() -> void:
	detener()
	if _jugador == null or not _factory.is_valid() or _oleadas.is_empty():
		push_warning("[Arena] sin jugador, factory u oleadas: no inicia")
		return
	_activa = true
	_oleada = 0
	_siguiente()


## Limpia mobs (de vuelta al pool) y apaga. Idempotente.
func detener() -> void:
	if _pool != null:
		for e in _vivos:
			if is_instance_valid(e):
				_pool.devolver(e)
	_vivos.clear()
	_activa = false
	_oleada = 0
	_espera = 0.0


func _process(delta: float) -> void:
	avanzar(delta)


## Descuenta el descanso y lanza la siguiente. Pública para tests.
func avanzar(dt: float) -> void:
	if not _activa or dt <= 0.0:
		return
	if not _vivos.is_empty() or _espera <= 0.0:
		return
	_espera -= dt
	if _espera <= 0.0:
		_siguiente()


func _siguiente() -> void:
	_oleada += 1
	if _oleada > _oleadas.size():
		_terminar(true)
		return
	_generar(_oleadas[_oleada - 1])
	oleada_iniciada.emit(_oleada)


func _generar(wave: Dictionary) -> void:
	_vivos.clear()
	var mobs: Dictionary = wave.get("mobs", {})
	var lista: Array[Enemy] = []
	for arq_id in mobs:
		for k in range(maxi(0, int(mobs.get(arq_id, 0)))):
			var ang: float = randf() * TAU
			var pos := Vector3(
				_centro.x + cos(ang) * (RADIO_SPAWN + randf_range(-5.0, 5.0)),
				0.0,
				_centro.y + sin(ang) * (RADIO_SPAWN + randf_range(-5.0, 5.0)))
			var e: Enemy = _factory.call(str(arq_id), pos) as Enemy
			if e != null:
				lista.append(e)
	# Élites al azar de la oleada (con su bloque de datos).
	var elite_n: int = maxi(0, int(wave.get("elite", 0)))
	lista.shuffle()
	for e in lista.slice(0, elite_n):
		var bloque: Dictionary = _bloque_elite(e.arquetipo_id)
		if not bloque.is_empty():
			e.hacer_elite(bloque)
	for e in lista:
		if not e.murio.is_connected(_al_muerte.bind(e)):
			e.murio.connect(_al_muerte.bind(e))
		_vivos.append(e)


## Bloque élite del arquetipo ({} si no tiene). El sorteo de respawn no
## aplica aquí: la oleada fuerza los élites que declara.
func _bloque_elite(arquetipo_id: String) -> Dictionary:
	var arq: Dictionary = _arquetipos.get(arquetipo_id, {})
	return arq.get("elite", {})


## Una muerte de la oleada: si no quedan vivos, recompensa y descanso.
func _al_muerte(_fuente: Entity, e: Enemy) -> void:
	if not _activa:
		return
	_vivos.erase(e)
	if _vivos.is_empty():
		var oro: int = _oro_base * _oleada
		var xp: int = _xp_base * _oleada
		if _jugador != null and is_instance_valid(_jugador):
			_jugador.ganar_oro(oro)
			_jugador.gain_xp(xp)
		mejor_oleada = maxi(mejor_oleada, _oleada)
		oleada_superada.emit(_oleada, oro, xp)
		_espera = _descanso_seg


func _al_morir_jugador(_fuente: Entity) -> void:
	if _activa:
		_terminar(false)


func _terminar(victoria: bool) -> void:
	var n: int = _oleada
	if victoria:
		victorias += 1
		mejor_oleada = maxi(mejor_oleada, int(_oleadas.size()))
	_activa = false
	_oleada = 0
	_vivos.clear()
	_espera = 0.0
	arena_terminada.emit(victoria, n)


## ¿Es este NPC el Maestro de arena? (flag `arena` en data/npcs.json).
## La VentanaDialogo lo usa para mostrar "Entrenar".
static func es_maestro(npc_id: String) -> bool:
	return bool(NpcDB.obtener(npc_id).get("arena", false))


## Centro del campo (para el teletransporte de la demo). Sin configurar → origen.
func centro_campo() -> Vector3:
	return Vector3(_centro.x, 0.0, _centro.y)


## Serialización versionada (bloque "arena" del save, v12).
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION_ARENA,
		"mejor_oleada": mejor_oleada,
		"victorias": victorias,
	}


func cargar_estado(d: Dictionary) -> void:
	mejor_oleada = maxi(0, int(d.get("mejor_oleada", 0)))
	victorias = maxi(0, int(d.get("victorias", 0)))
