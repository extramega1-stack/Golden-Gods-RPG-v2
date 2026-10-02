class_name RespawnHeros
extends Node
## Fase 51: el héroe que muere vuelve a la última ciudad visitada.
##
## POR QUÉ EXISTE: `Entity.die()` apaga `_process`/`_physics_process` y pone
## `collision_layer = 0`. Hasta la fase 51, `Player.murio` solo estaba
## conectado en `arena.gd`: morirse FUERA de la arena congelaba el juego
## para siempre, sin input, sin física y sin forma de revivir. El único
## escape era F10 (cargar partida). Con 6 jefes de nivel 70 en el mapa no
## era un bug, era un muro.
##
## Decisión de Juan Diego: sin penalidad. No se pierde XP ni oro, la vida y
## el maná vuelven al máximo y los cooldowns se limpian.
##
## - Escucha `jugador.murio` y llama a `Player.reaparecer()`.
## - Mantiene el "punto seguro": la plaza de la última ciudad en la que el
##   jugador estuvo. La fuente es `CiudadLuna.punto_aparicion_jugador()`,
##   NO `data/viaje_rapido.json`: esas plazas traen `y = 45.0` constante y
##   la altura real del terreno llega a 220 u (hasta 175 u de descuadre en
##   `rage`), así que respawnear ahí te tiraba al suelo desde el aire.
## - Si la `Arena` está activa NO hace nada: la arena ya gestiona la muerte
##   del jugador para su derrota (`arena.gd` conecta `murio`). Sin esta
##   guarda los dos sistemas se pelean por el mismo telegraph.

## Emitida cuando el héroe reaparece. La usan la UI y el streaming.
signal reaparecido(posicion: Vector3)

var _jugador: Player = null
var _arena: Arena = null
## Fase 51: puesta a punto explícita mientras hay una partida de arena en
## curso. La pone `Arena` con `suspender()`.
##
## Hace falta porque NO alcanza con mirar `arena.activa()` en el instante de
## morir: la arena se conecta a `jugador.murio` antes que este sistema (la
## configuran primero que el respawn), así que su handler se ejecuta PRIMERO,
## termina la derrota y pone `_activa = false`. Para cuando llega esta
## señal, la arena ya parece inactiva y el respawn expulsaría al jugador del
## campo a media partida. Con la puesta explícita da igual el orden.
var _suspendido: bool = false
## Radio en el que se considera que el jugador está "en ciudad" y, por lo
## tanto, que su punto seguro pasa a ser esta plaza.
var radio_ancla: float = 120.0
## Las plazas candidatas, ya resueltas a Vector3 (con y real). Las mete
## `registrar_ciudad`.
var _plazas: Array = []
## Hotfix 62.1: los refugios RECLAMADOS. Un refugio ganado pisa a la plaza de
## la ciudad si el jugador está dentro de su radio: es el punto seguro que el
## jugador compró, así que tiene que valer más que la plaza pública. Los mete
## `anclar_refugio`, que es a quien escucha `Refugio.reclamado`.
var _refugios: Array = []
## Hotfix 62.1: el ancla se reevalúa al caminar, que es lo que el docstring de
## `actualizar_ancla` prometía desde la fase 51 y que nadie llamaba. Antes el
## punto seguro solo se refrescaba al morir o al viajar rápido, así que si te
## ibas caminando a otra ciudad y morías lejos, volvías a la anterior.
const INTERVALO_ANCLA: float = 0.5
var _ancla_timer: float = 0.0


func _ready() -> void:
	# El grupo es la puerta de la fase 51.1 (§9.1). `system_id` permite
	# distinguirlo de cualquier otro sistema del grupo.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Hotfix 62.1: el ancla se refresca solo, sin esperar a morir o a viajar. Con
## esto no hay allocs (solo compara floats) y el timer hace que no se llame en
## cada frame.
func _process(delta: float) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	_ancla_timer -= delta
	if _ancla_timer > 0.0:
		return
	_ancla_timer = INTERVALO_ANCLA
	actualizar_ancla()


## ¿Está puesto a punto? Lo consulta `_al_morir`; lo pone la Arena.
func suspendido() -> bool:
	return _suspendido


## Fase 51: puesta/quitada del respawn mientras dura una partida de arena.
## La llama `Arena` en `iniciar()` y al terminar.
func suspender(activo: bool) -> void:
	_suspendido = activo


## Registra la plaza de aparición de una ciudad. `pos` tiene que venir de
## `CiudadLuna.punto_aparicion_jugador()`, que ya consulta el terreno.
func registrar_ciudad(id: String, pos: Vector3, yaw: float = 0.0) -> void:
	_plazas.append({"id": id, "pos": pos, "yaw": yaw})


## Inyecta las dependencias. `arena` puede ser null: la guarda de arena
## simplemente nunca dispara.
func configurar(jugador: Player, arena: Arena = null) -> void:
	desconectar()
	_jugador = jugador
	_arena = arena
	if _jugador == null or not is_instance_valid(_jugador):
		return
	if not _jugador.murio.is_connected(_al_morir):
		_jugador.murio.connect(_al_morir)
	# El punto seguro arranca en donde esté el jugador: si morís antes de
	# pisar ninguna ciudad, reapareces donde estabas y no en el origen del
	# mundo, que es un disco urbano a 40 m con el nivel equivocado.
	actualizar_ancla()


func desconectar() -> void:
	if _jugador != null and is_instance_valid(_jugador):
		if _jugador.murio.is_connected(_al_morir):
			_jugador.murio.disconnect(_al_morir)
	_jugador = null


## ¿Cuántas plazas conoce? Sirve de check en los tests.
func plazas() -> int:
	return _plazas.size()


## Plaza más cercana al jugador dentro de `radio_ancla`, o la más cercana en
## general si está fuera de todas. Devuelve "" si no conoce ninguna.
func plaza_actual() -> String:
	if _plazas.is_empty() or _jugador == null or not is_instance_valid(_jugador):
		return ""
	var pos: Vector3 = _jugador.global_position
	var mejor: String = ""
	var mejor_d: float = INF
	for p in _plazas:
		var d: float = pos.distance_to(p["pos"])
		if d < mejor_d:
			mejor_d = d
			mejor = str(p["id"])
	# Dentro del radio, la más cercana gana. Fuera, la más cercana también:
	# es el mejor fallback disponible.
	return mejor


## Si el jugador está en una plaza (dentro de `radio_ancla`), la vuelve su
## punto seguro. La llama el sistema al caminar; también se puede llamar a
## mano al viajar.
func actualizar_ancla() -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var pos: Vector3 = _jugador.global_position
	# Hotfix 62.1: primero los refugios. Un refugio reclamado del que estás
	# parado es un punto seguro mejor que la plaza de la ciudad, y es lo que
	# el jugador compró con la fase 60.
	for r in _refugios:
		var ref: Refugio = r as Refugio
		if ref == null or not is_instance_valid(ref):
			continue
		# Solo un refugio RECLAMADO es punto seguro, y solo si estás dentro.
		if not ref.esta_reclamado():
			continue
		if not ref.contiene(pos):
			continue
		_jugador.anclar_en_ciudad(pos, 0.0)
		return
	if _plazas.is_empty():
		return
	for p in _plazas:
		if pos.distance_to(p["pos"]) <= radio_ancla:
			_jugador.anclar_en_ciudad(p["pos"], float(p["yaw"]))
			return


## Hotfix 62.1: registra un refugio como candidato a punto seguro. Lo llama la
## UI al reclamarlo (fase 64), no el constructor: el refugio no se registra
## solo para que uno sin reclamar no pueda ser ancla nunca.
func anclar_refugio(ref: Refugio) -> void:
	if ref == null or not is_instance_valid(ref):
		return
	for r in _refugios:
		if r == ref:
			return
	_refugios.append(ref)


func _al_morir(_fuente: Entity) -> void:
	# Hay partida de arena en curso: la arena resuelve su propia derrota. Si
	# teletransportásemos, el jugador se iría del campo a media partida.
	# Se mira la puesta explícita Y `activa()`, para que aguante aunque
	# alguien cablee una cosa y no la otra.
	if _suspendido:
		return
	if _arena != null and is_instance_valid(_arena) and _arena.activa():
		return
	if _jugador == null or not is_instance_valid(_jugador):
		return

	# Fase 72: la muerte del jugador suena AQUÍ y no en `Entity.die()`. Este
	# es el sistema de mundo que reacciona a `jugador.murio`, y ponerlo acá
	# garantiza que suene una vez y solo en la partida (en la arena la resuelve
	# la arena). Es distinto del `muerte` de los mobs: caída larga y grave.
	AudioJuego.al_morir_jugador()

	# El ancla pudo venir de `data/viaje_rapido.json` (nunca: ver arriba) o
	# de una llamada manual. En cualquier caso se refresca contra las plazas
	# conocidas, y si no hay ninguna se usa la del jugador.
	actualizar_ancla()

	_jugador.reaparecer()
	reaparecido.emit(_jugador.ancla())
