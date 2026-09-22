class_name SpawnerMobs
extends Node
## Respawn de mobs data-driven (fase 9): vigila enemigos y, ante la señal
## `murio`, programa su reaparición tras `respawn_seg` en su punto de
## origen (con pequeña variación aleatoria de posición).
##
## - `configurar_arquetipos(d)`: diccionario de arquetipos
##   (data/enemies.json); cada uno puede declarar `respawn_seg`. Si falta,
##   se usa `RESPAWN_DEFAULT_SEG` (20 s; constante con nombre, no magia).
## - `fijar_factory(f)`: `Callable(arquetipo_id: String, posicion: Vector3)
##   -> Enemy`. El spawner NO conoce rutas de escenas; la demo la inyecta.
## - `vigilar(e)`: registra un Enemy (su `arquetipo_id` y su posición de
##   origen). Solo acepta `Enemy` (los NPCs no mueren y no entran aquí).
## - `avanzar(dt)`: descuenta los timers pendientes; al cumplirse,
##   reinstancia con el mismo arquetipo, la auto-vigila y emite
##   `reaparecido(nuevo)`. Los tests llaman a `avanzar` con tiempo
##   simulado; `_process` lo llama con tiempo real.
## - El respawn es RUNTIME: el timer no se guarda. El SaveSystem guarda los
##   enemigos vivos como siempre; un muerto pendiente de respawn
##   simplemente no está en la lista.

signal reaparecido(nuevo: Enemy)

## Segundos de espera si el arquetipo no declara `respawn_seg`.
const RESPAWN_DEFAULT_SEG: float = 20.0
## Variación aleatoria (m) alrededor del punto de origen al reaparecer.
const RADIO_VARIACION: float = 2.0
## Fase 12.1: si la puerta de reaparición niega, el pendiente se reprograma
## y se reintenta tras estos segundos (no se pierde el respawn).
const REINTENTO_PUERTA_SEG: float = 5.0

## Fase 12.1 — puerta opcional de reaparición:
## `Callable(arquetipo: String, origen: Vector3) -> bool`.
## El streaming de mobs la usa para vetar reapariciones lejos del jugador
## (el mob reaparece cuando te acercas, no antes). Sin puerta (invalida),
## el comportamiento es el de siempre: reaparecer al cumplirse el timer.
var puerta_reaparicion: Callable = Callable()

var _arquetipos: Dictionary = {}
var _factory: Callable = Callable()
## Orígenes por instance_id (la posición donde se vigiló al enemigo;
## al morir puede estar lejos, persiguiendo al jugador).
var _origenes: Dictionary = {}
## Pendientes: Array de {arquetipo: String, origen: Vector3, tiempo: float}.
var _pendientes: Array = []


func configurar_arquetipos(arqs: Dictionary) -> void:
	_arquetipos = arqs


func fijar_factory(f: Callable) -> void:
	_factory = f


## Cuántos respawns hay programados (útil para tests y depuración).
func pendientes() -> int:
	return _pendientes.size()


## Registra un enemigo: guarda su punto de origen y conecta su `murio`.
func vigilar(e: Enemy) -> void:
	if e == null:
		return
	_origenes[e.get_instance_id()] = e.global_position
	if not e.murio.is_connected(_al_morir):
		e.murio.connect(_al_morir.bind(e))


## Fase 12.1: deja de vigilar un enemigo sin matarlo (el streaming lo usa
## al liberar un mob lejano: su respawn pendiente, si lo hay, sigue
## programado con su propio origen).
func olvidar(e: Enemy) -> void:
	if e == null:
		return
	_origenes.erase(e.get_instance_id())
	if e.murio.is_connected(_al_morir):
		e.murio.disconnect(_al_morir)


func _process(delta: float) -> void:
	avanzar(delta)


## Descuenta `dt` de cada timer pendiente y reaparece los cumplidos.
## Pública para que los tests la llamen con tiempo simulado.
func avanzar(dt: float) -> void:
	if dt <= 0.0:
		return
	var i: int = _pendientes.size() - 1
	while i >= 0:
		var p: Dictionary = _pendientes[i]
		p["tiempo"] = float(p["tiempo"]) - dt
		if float(p["tiempo"]) <= 0.0:
			_pendientes.remove_at(i)
			_reaparecer(p)
		i -= 1


func _al_morir(_fuente: Entity, e: Enemy) -> void:
	if e == null:
		return
	var iid: int = e.get_instance_id()
	var origen: Vector3 = _origenes.get(iid, e.global_position)
	_origenes.erase(iid)
	var arq: Dictionary = _arquetipos.get(e.arquetipo_id, {})
	var seg: float = float(arq.get("respawn_seg", RESPAWN_DEFAULT_SEG))
	if seg <= 0.0:
		seg = RESPAWN_DEFAULT_SEG
	_pendientes.append({
		"arquetipo": e.arquetipo_id,
		"origen": origen,
		"tiempo": seg,
	})


func _reaparecer(p: Dictionary) -> void:
	if not _factory.is_valid():
		push_warning("[SpawnerMobs] sin factory: no se puede reaparecer '%s'" % str(p.get("arquetipo", "")))
		return
	# Fase 12.1: la puerta puede vetar la reaparición (mob lejos del
	# jugador); el pendiente NO se pierde: se reprograma el reintento.
	if puerta_reaparicion.is_valid():
		var ok: Variant = puerta_reaparicion.call(str(p.get("arquetipo", "")), p["origen"])
		if not bool(ok):
			p["tiempo"] = REINTENTO_PUERTA_SEG
			_pendientes.append(p)
			return
	var origen: Vector3 = p["origen"]
	# randf_range, no randf(a, b) (lección 12).
	var pos: Vector3 = origen + Vector3(
		randf_range(-RADIO_VARIACION, RADIO_VARIACION),
		0.0,
		randf_range(-RADIO_VARIACION, RADIO_VARIACION))
	var nuevo: Variant = _factory.call(str(p["arquetipo"]), pos)
	var en: Enemy = nuevo as Enemy
	if en == null:
		push_warning("[SpawnerMobs] la factory no devolvió un Enemy para '%s'" % str(p["arquetipo"]))
		return
	# La factory puede devolver el enemigo ya emparentado (la demo lo
	# añade a la escena) o huérfano: solo se emparenta si hace falta.
	if en.get_parent() == null:
		if is_inside_tree() and get_parent() != null:
			get_parent().add_child(en)
		else:
			add_child(en)
	en.global_position = pos
	# El reaparecido también se vigila: sus muertes futuras respawnean.
	vigilar(en)
	reaparecido.emit(en)
