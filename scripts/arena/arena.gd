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
## Fase 42: si una oleada se atasca (un mob vivo al que no llegas, o te
## alejaste), los que quedan se teletransportan a tu lado tras este tiempo.
## Una oleada SIEMPRE se puede terminar: nunca se queda colgada.
const ESPERA_AYUDA_SEG: float = 12.0
const RADIO_AYUDA: float = 9.0

signal oleada_iniciada(n: int)
signal oleada_superada(n: int, oro: int, xp: int)
signal arena_terminada(victoria: bool, oleada: int)
## Fase 42: los mobs supervivientes se acercaron al jugador (anti-stuck).
signal ayuda_oleada(n: int)

## Fase 51.1 (§9.1): identidad del sistema para el contenedor `Systems`.
## El grupo `gg_system` + este `system_id` sustituyen a las rutas de nodo
## hardcodeadas que usaba la demo para encontrarlo.
var system_id: StringName = &"arena"
var _jugador: Player = null
## Fase 51: el sistema de respawn del heroe. Lo pone la demo con
## `fijar_respawn`; la arena lo suspende mientras corre la partida.
var _respawn: RespawnHeros = null
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
	## Fase 42: conexión de cada mob con _al_muerte (id → Callable) para
	## desconectar limpio al reciclar el cadáver al pool.
var _conectados: Dictionary = {}
var _espera: float = 0.0
var _tiempo_oleada: float = 0.0
## Fase 42: la recompensa de la oleada se paga UNA vez (desde _al_muerte o
## desde avanzar() si el último corpse se liberó sin pasar por die()).
var _oleada_pagada: bool = false

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


## Fase 51: inyecta el sistema de respawn del heroe.
func fijar_respawn(r: RespawnHeros) -> void:
	_respawn = r


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
	# Fase 51: mientras corre la partida, el respawn del heroe se pone a
	# punto. Sin esto, al morir el respawn lo teletransporta a la ciudad a
	# media partida: esta arena se conecta a `jugador.murio` antes que el
	# respawn, asi que su handler corre primero, termina la derrota y deja
	# `activa() = false` antes de que el respawn mire.
	if _respawn != null and is_instance_valid(_respawn):
		_respawn.suspender(true)
	_oleada = 0
	_siguiente()


## Limpia mobs (de vuelta al pool, desconectados) y apaga. Idempotente.
func detener() -> void:
	_activa = false
	# Fase 51: al apagar la arena se le devuelve el control al respawn.
	if _respawn != null and is_instance_valid(_respawn):
		_respawn.suspender(false)
	_oleada = 0
	_espera = 0.0
	_tiempo_oleada = 0.0
	_limpiar_vivos()


func _process(delta: float) -> void:
	avanzar(delta)


## Descuenta el descanso y lanza la siguiente. Pública para tests.
## Fase 42: poda referencias inválidas (un corpse liberado no puede dejar la
## oleada colgada) y ayuda anti-stuck si quedan mobs tras ESPERA_AYUDA_SEG.
func avanzar(dt: float) -> void:
	if not _activa or dt <= 0.0:
		return
	var n: int = vivos()
	if n > 0:
		_tiempo_oleada += dt
		if _tiempo_oleada >= ESPERA_AYUDA_SEG:
			_acercar_vivos()
			_tiempo_oleada = 0.0
		return
	# Fase 42: si no queda nadie vivo, la oleada se paga aquí aunque nadie
	# haya pasado por die() (un corpse liberado desde el streaming/pool
	# dejaba la arena colgada para siempre = "solo una oleada").
	if not _oleada_pagada and _oleada > 0:
		_pagar_oleada()
	if _espera <= 0.0:
		return
	_espera -= dt
	if _espera <= 0.0:
		_siguiente()


## Fase 42: recompensa de la oleada en un solo sitio e idempotente.
func _pagar_oleada() -> void:
	if _oleada_pagada:
		return
	_oleada_pagada = true
	var oro: int = _oro_base * _oleada
	var xp: int = _xp_base * _oleada
	if _jugador != null and is_instance_valid(_jugador):
		_jugador.ganar_oro(oro)
		_jugador.gain_xp(xp)
	mejor_oleada = maxi(mejor_oleada, _oleada)
	oleada_superada.emit(_oleada, oro, xp)
	_espera = _descanso_seg
	_tiempo_oleada = 0.0


## Fase 42: los mobs que quedan se teletransportan junto al jugador y le
## entran en aggro. Garantiza que la oleada se pueda cerrar.
func _acercar_vivos() -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var n: int = 0
	for i in _vivos.size():
		var e: Enemy = _vivos[i]
		if not is_instance_valid(e) or not e.esta_vivo():
			continue
		var ang: float = float(i) / float(maxi(_vivos.size(), 1)) * TAU
		var pos := _jugador.global_position + Vector3(
			cos(ang) * RADIO_AYUDA, 0.0, sin(ang) * RADIO_AYUDA)
		pos.y = _jugador.global_position.y
		e.global_position = pos
		e.velocity = Vector3.ZERO
		e._pegar_al_terreno()
		e.objetivo = _jugador
		e.estado = Enemy.Estado.PERSEGUIR
		n += 1
	if n > 0:
		ayuda_oleada.emit(n)


func _siguiente() -> void:
	_oleada += 1
	if _oleada > _oleadas.size():
		_terminar(true)
		return
	_tiempo_oleada = 0.0
	_oleada_pagada = false
	_generar(_oleadas[_oleada - 1])
	oleada_iniciada.emit(_oleada)


func _generar(wave: Dictionary) -> void:
	_limpiar_vivos()
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
		_conectar_muerte(e)
		_vivos.append(e)
	# Fase 42: una oleada que no logró spawnear NADA no puede dejar la arena
	# colgada esperando una muerte que no existe → pasa a la siguiente.
	if lista.is_empty():
		_espera = 0.001


## Conecta la muerte del mob guardando el Callable (id → Callable) para
## poder desconectar limpio cuando el cadáver vuelve al pool.
func _conectar_muerte(e: Enemy) -> void:
	var id: int = e.get_instance_id()
	if _conectados.has(id):
		return
	var c: Callable = _al_muerte.bind(e)
	e.murio.connect(c)
	_conectados[id] = c


## Desconecta y devuelve al pool los corpses de la oleada anterior (limpia el
## campo y evita que el recycled mob vine con una conexión vieja).
func _limpiar_vivos() -> void:
	for e in _vivos:
		if not is_instance_valid(e):
			continue
		var id: int = e.get_instance_id()
		if _conectados.has(id):
			var c: Callable = _conectados[id]
			if e.murio.is_connected(c):
				e.murio.disconnect(c)
			_conectados.erase(id)
		if _pool != null:
			_pool.devolver(e)
	_vivos.clear()


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
	_conectados.erase(e.get_instance_id())
	# Fase 42: `vivos()` poda referencias inválidas (no uses is_empty() aquí:
	# un corpse liberado dejaría la oleada colgada para siempre).
	if vivos() == 0:
		_pagar_oleada()


func _al_morir_jugador(_fuente: Entity) -> void:
	if _activa:
		_terminar(false)


func _terminar(victoria: bool) -> void:
	var n: int = _oleada
	if victoria:
		victorias += 1
		mejor_oleada = maxi(mejor_oleada, int(_oleadas.size()))
	_activa = false
	# OJO (fase 51): aquí NO se libera la puesta a punto del respawn. Esta
	# función corre DENTRO de la señal `jugador.murio`, antes de que
	# `RespawnHeros._al_morir` la mire: si se liberara acá, el respawn vería
	# `_suspendido = false` y expulsaría al héroe de la arena a media
	# partida. Quien libera es `detener()`, que se llama cuando el héroe ya
	# está de vuelta en el mundo y jugable.
	_oleada = 0
	_espera = 0.0
	_tiempo_oleada = 0.0
	_oleada_pagada = false
	_limpiar_vivos()
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
