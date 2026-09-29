class_name DirectorMusica
extends Node
## Bloque 66: decide en qué "escena musical" está el juego, y avisa a `Musica`.
##
## POR QUÉ EXISTE: `Musica` sabe tocar las capas, pero no sabe CUÁNDO. Sin
## este nodo la música se quedaría en "exploración" para siempre, y todo el
## trabajo de las capas de combate y jefe no se oiría nunca. Es la diferencia
## entre "tener música" y "tener música adaptativa", que es lo que hace que un
## juego suene vivo.
##
## Las reglas son LEGIBLES a propósito, porque afinarlas es la partePLICada de
## hacer que la música funcione:
## - Hay un jefe (mobsSelected es un jefe) → tema de jefe.
## - Hay enemigos cerca Y el jugador está en la lista de "en combate" → tema
##   de combate.
## - El jugador está en una ciudad (segura) → tema de pueblo.
## - Si no, → exploración.
##
## Con "hysteresis" (estabilidad): no se cambia de tema en cada frame. Se exige
## que la condición se cumpla durante `ESTABILIDAD` segundos seguidos antes de
## cambiar, para que al caminar junto a dos mobs no se vaya saltando entre
## exploración y combate. Esto es un detalle pequeño que se nota muchísimo.

const MUSICA_BUS_ID: StringName = &"musica"

## Segundos que una condición debe cumplirse antes de cambiar de tema.
const ESTABILIDAD: float = 2.0
## Radio en el que un enemigo cuenta como "cerca" para entrar en combate.
const RADIO_COMBATE: float = 25.0
## Radio de un jefe: más lejos cuenta, porque un jefe se oye desde lejos y
## que la música entre tarde es peor.
const RADIO_JEFE: float = 60.0

## §9.1
var system_id: StringName = &"director_musica"

var _musica: Musica = null
var _jugador: Player = null
var _enemigos: Array = []
var _destino: int = Musica.CAPA_EXPLORACION
var _candidato: int = Musica.CAPA_EXPLORACION
var _reloj: float = 0.0


func _ready() -> void:
	set_process(true)


func configurar(musica: Musica, jugador: Player, enemigos: Array) -> void:
	_musica = musica
	_jugador = jugador
	_enemigos = enemigos


func _process(delta: float) -> void:
	if _musica == null or _jugador == null or not is_instance_valid(_jugador):
		return
	var nuevo: int = _calcular_estado()
	if nuevo == _candidato:
		_reloj += delta
		# Solo se cambia tras ETABILIDAD: sin esto la música parpadea en el
		# borde de un mob.
		if _candidato != _destino and _reloj >= ESTABILIDAD:
			_destino = _candidato
			_musica.cambiar_estado(_destino)
	else:
		_candidato = nuevo
		_reloj = 0.0


func _calcular_estado() -> int:
	var pos: Vector3 = _jugador.global_position
	# ¿Jefe cerca? Gana a todo: contra un jefe no hay "exploración".
	if _jefe_cerca(pos, RADIO_JEFE):
		return Musica.CAPA_JEFE
	# ¿En combate? Enemigos vivos a tiro.
	if _enemigos_cerca(pos, RADIO_COMBATE):
		return Musica.CAPA_COMBATE
	# ¿En una ciudad? El mundo tiene zonas seguras; el jugador en la plaza de
	# Moon Town suena a pueblo, no a explores.
	if _en_plaza(pos):
		return Musica.CAPA_BASE
	return Musica.CAPA_EXPLORACION


func _jefe_cerca(pos: Vector3, radio: float) -> bool:
	for e in _enemigos_efectivos():
		var en: Enemy = e as Enemy
		if en == null or not is_instance_valid(en) or not en.esta_vivo():
			continue
		if en.es_jefe and en.global_position.distance_to(pos) <= radio:
			return true
	return false


func _enemigos_cerca(pos: Vector3, radio: float) -> bool:
	for e in _enemigos_efectivos():
		var en: Enemy = e as Enemy
		if en == null or not is_instance_valid(en) or not en.esta_vivo():
			continue
		if en.global_position.distance_to(pos) <= radio:
			return true
	return false


## En la plaza: la `ZONA_SEGURA` de la region. Reusa el mismo radio que usa el
## generador de spawns (40 m), para que "estoy en el pueblo" y "aquí no spawnean
## mobs" sean la misma cosa.
func _en_plaza(pos: Vector3) -> bool:
	return pos.length() <= 40.0


func _enemigos_efectivos() -> Array:
	# `_enemigos` puede ser la lista de la demo (que crece con el streaming) o
	# un array plano. Se toleran ambos sin comprobar el tipo cada vez.
	return _enemigos


## Para los tests: el estado que el director calcularía ahora, sin esperar la
## estabilidad.
func estado_calculado() -> int:
	return _calcular_estado()


func destino() -> int:
	return _destino
