class_name AvisosJugador
extends Node
## Fase 72: los avisos que son del JUGADOR, en un solo nodo.
##
## POR QUÉ UN NODO Y NO LLAMADAS SUELTAS EN `player.gd`: cuatro de los quince
## huecos (subir de nivel, desbloquear un Hecho, hambre, sed, enfermo) y el
## aviso de daño propio pasan por SEÑALES de la sesión, y el lugar que las
## emite es `player.gd`, que esta fase no puede tocar (lo tiene otra). Un
## sistema que se SUSCRIBE es la forma que el proyecto ya usa para todo lo
## demás (`IndicadorVitales` escuchando a `Vitals`, `SaveSystem` escuchando a
## `murio`), así que esto no es un invento: es el patrón del repo aplicado a
## lo que faltaba.
##
## Lo importante es que NO es un simulacro: este nodo escucha las señales
## reales de la sesión real y dispara el sonido real. Mover el dato mueve el
## sonido, y el test lo comprueba así (no mirando el código).
##
## CADA AVISO TIENE UMBRAL, PORQUE UNO POR FRAME ES UN RUIDO:
## - `subio_nivel` dispara una vez por nivel ganado: no hay umbral posible.
## - `tramo_ganado` dispara cuando una habilidad sube de tramo, y eso NO es
##   un Hecho nuevo: solo lo es si la cuenta de `desbloqueados()` sube. Por
##   eso se compara antes y después en vez de sonar siempre.
## - `hambre`/`sed` cruzan `Vitals.UMBRAL_VACIO`: se avisa al BAJAR y no se
##   vuelve a avisar hasta que el vital vuelva a subir. Sin esa memoria el
##   stomach growl sonaría 60 veces por segundo durante todo el decaimiento.

## Cada cuánto se revisa que lo que se escuchaba siga siendo lo mismo. 0,5 s
## como `GestorVetas`: es una comparación de referencias, y una comparación por
## frame no cuesta nada pero tampoco hace falta.
const INTERVALO_SEG: float = 0.5

## §9.1
var system_id: StringName = &"avisos_jugador"

var _jugador: Player = null
## Lo que se está escuchando AHORA. No es lo mismo que lo que había al
## conectar: `Player.reaparecer()` REEMPLAZA el `Vitals` por uno nuevo (para
## vaciar el estómago y quitar los mods al morir), y sin esto el sistema
## seguiría escuchando al viejo: el aviso de hambre, el de sed y el de
## enfermedad se dead-silenciaban para siempre después de la primera muerte.
var _vitals_vistos: Vitals = null
## Cuántos Hechos había desbloqueados la última vez que se miró. Lo que
## importa es la DIFERENCIA, no el número.
var _hechos_vistos: int = 0
## Vitales que ya están avisados, para no repetir en cada tick.
var _bajo: Dictionary = {"hambre": false, "sed": false}
var _acum: float = 0.0


## Escucha a una sesión. Idempotente por sesión: volver a vigilar a la misma
## no duplica conexiones (y una duplicada sonaría el doble).
func vigilar(j: Player) -> void:
	if j == null or not is_instance_valid(j):
		return
	if _jugador == j:
		return
	_desconectar()
	_jugador = j
	_conectar(j)
	_hechos_vistos = _hechos_abiertos()
	_bajo["hambre"] = false
	_bajo["sed"] = false
	# El arranque NO recibe un `vital_cambiado`: `Vitals` solo emite cuando un
	# valor se movió, y al empezar nada se movió. Sin esta lectura inicial, un
	# jugador que carga una partida con el hambre a 5 no oye el aviso hasta
	# que le baja otro medio punto.
	releer_vitales()


func _conectar(j: Player) -> void:
	if not j.subio_nivel.is_connected(_al_subir_nivel):
		j.subio_nivel.connect(_al_subir_nivel)
	if not j.daniado.is_connected(_al_danio):
		j.daniado.connect(_al_danio)
	if j.habilidades != null \
			and not j.habilidades.tramo_ganado.is_connected(_al_subir_tramo):
		j.habilidades.tramo_ganado.connect(_al_subir_tramo)
	_vitals_vistos = j.vitals
	_conectar_vitals(j.vitals)


func _conectar_vitals(v: Vitals) -> void:
	if v == null:
		return
	if not v.vital_cambiado.is_connected(_al_vital_cambiado):
		v.vital_cambiado.connect(_al_vital_cambiado)
	if not v.enfermedad_cambiada.is_connected(_al_enfermedad):
		v.enfermedad_cambiada.connect(_al_enfermedad)


func _desconectar() -> void:
	_desconectar_vitals(_vitals_vistos)
	_vitals_vistos = null
	if _jugador == null or not is_instance_valid(_jugador):
		_jugador = null
		return
	if _jugador.subio_nivel.is_connected(_al_subir_nivel):
		_jugador.subio_nivel.disconnect(_al_subir_nivel)
	if _jugador.daniado.is_connected(_al_danio):
		_jugador.daniado.disconnect(_al_danio)
	if _jugador.habilidades != null \
			and _jugador.habilidades.tramo_ganado.is_connected(_al_subir_tramo):
		_jugador.habilidades.tramo_ganado.disconnect(_al_subir_tramo)
	_jugador = null


func _desconectar_vitals(v: Vitals) -> void:
	if v == null:
		return
	if v.vital_cambiado.is_connected(_al_vital_cambiado):
		v.vital_cambiado.disconnect(_al_vital_cambiado)
	if v.enfermedad_cambiada.is_connected(_al_enfermedad):
		v.enfermedad_cambiada.disconnect(_al_enfermedad)


## La revisión periódica. Una comparación de referencias cada medio segundo
## para que el sistema no se quede escuchando un `Vitals` que ya no es el del
## jugador (ver `_vitals_vistos`).
func _process(delta: float) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	_acum += delta
	if _acum < INTERVALO_SEG:
		return
	_acum = 0.0
	_revisar_enlaces()


func _revisar_enlaces() -> void:
	var j: Player = _jugador
	if j == null or not is_instance_valid(j):
		return
	if j.vitals != _vitals_vistos:
		_desconectar_vitals(_vitals_vistos)
		_vitals_vistos = j.vitals
		_bajo["hambre"] = false
		_bajo["sed"] = false
		_conectar_vitals(j.vitals)
		releer_vitales()
	if j.habilidades != null \
			and not j.habilidades.tramo_ganado.is_connected(_al_subir_tramo):
		j.habilidades.tramo_ganado.connect(_al_subir_tramo)


func _exit_tree() -> void:
	_desconectar()


# --- los avisos ------------------------------------------------------

func _al_subir_nivel(_nivel: int) -> void:
	SonidoUI.nivel()


func _al_danio(_dano: float, _fuente: Entity) -> void:
	SonidoUI.jugador_danio()


## Un tramo de habilidad alcanzado NO es un Hecho nuevo: un Hecho se abre
## cuando la cuenta de desbloqueados sube. Comparar antes y después es lo que
## evita que cada punto de XP suene a logro.
func _al_subir_tramo(_hab: String, _tramo: int) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var ahora: int = _hechos_abiertos()
	if ahora > _hechos_vistos:
		_hechos_vistos = ahora
		SonidoUI.hecho()


func _hechos_abiertos() -> int:
	if _jugador == null or not is_instance_valid(_jugador) or _jugador.hechos == null:
		return 0
	return _jugador.hechos.desbloqueados().size()


func _al_vital_cambiado(hambre: float, sed: float, _energia: float,
		_enfermedad: float) -> void:
	_avisar_si_cruza("hambre", hambre)
	_avisar_si_cruza("sed", sed)


## El umbral es el del propio `Vitals` (15), no un número repetido acá: si
## suben el umbral, el aviso sube con él.
func _avisar_si_cruza(cual: String, valor: float) -> void:
	var bajo: bool = valor < Vitals.UMBRAL_VACIO
	var ya: bool = bool(_bajo.get(cual, false))
	if bajo and not ya:
		_bajo[cual] = true
		AudioJuego.al_vital_bajo(cual)
	elif not bajo and ya:
		_bajo[cual] = false


func _al_enfermedad(activa: bool) -> void:
	if activa:
		AudioJuego.al_enfermo()


## Estado del aviso de un vital (para el test: "mover el dato mueve el
## sonido" necesita poder mirar qué se pidió).
func aviso_de(cual: String) -> bool:
	return bool(_bajo.get(cual, false))


## Los Hechos que este nodo lleva contados. Si el test ve esto subir sin que
## suene, el sistema está desconectado.
func hechos_vistos() -> int:
	return _hechos_vistos


## Fuerza una relectura de los vitales. El arranque no los recibe: `vigilar`
## los mira una vez, y sin esto el test no podría provocar el primer aviso.
func releer_vitales() -> void:
	if _jugador == null or not is_instance_valid(_jugador) or _jugador.vitals == null:
		return
	_revisar_vitales(_jugador.vitals)


func _revisar_vitales(v: Vitals) -> void:
	if v == null:
		return
	_al_vital_cambiado(v.hambre, v.sed, v.energia, v.enfermedad)