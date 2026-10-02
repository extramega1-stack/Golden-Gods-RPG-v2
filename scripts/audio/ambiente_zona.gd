class_name AmbienteZona
extends Node3D
## Fase 72: el ambiente POR ZONA, que era el hueco más visible de los tres.
##
## EL HECHO QUE ARREGLA: `audio_juego.gd` crea el bus `Ambiente` desde el
## bloque 66 y `Opciones` le pone el volumen… y no hay NI UN SOLO player en
## ese bus. Cero viento, cero agua. El spec (MASTER_SPEC.md §9.5) lo pedía y
## no existía: el juego tiene 37 sonidos de un solo golpe y ni una capa de
## fondo, que es lo que hace que un mundo suene a LUGAR y no a una caja de
## efectos.
##
## - CAPAS, no un loop: viento y agua son beds que se cruzan. Caminando de
##   Moon Town al bosque el viento entra y el agua sale, y ese cruce es lo que
##   el oído lee como "cambié de zona" sin que nadie mire el mapa.
## - GENERADO, no asset: se sintetiza al arrancar desde `data/ambiente.json`.
##   Un loop de viento de 6 s a 44,1 kHz estéreo son 2,1 MB en RAM; generarlo
##   es lo que evita meter un WAV en el repo.
## - POSICIONAL y con ATENUACIÓN: los players se anclan a la posición del
##   jugador, no a la del nodo, porque el viento no está en un punto: está en
##   la región. Es el mismo criterio de distancia que el pool 3D de
##   `AudioJuego` (`DISTANCIA_MAX` + `ATTENUATION_INVERSE_DISTANCE`).
##
## Por qué NO va dentro de `AudioJuego`: ese nodo es el pool de one-shots y
## su API es estática y sin estado. El ambiente tiene estado (qué capas
## suenan, con qué mezcla) y ciclo de vida propio: un nodo, una
## responsabilidad (§9.1).
##
## Data-driven: `data/ambiente.json` dice qué capas existen y qué mezcla lleva
## cada región. Añadir un bioma es una entrada de JSON, no un `if`.

const RUTA_DATOS: String = "res://data/ambiente.json"
## Radio en el que una capa deja de oírse. Más corto que el de los one-shots
## (60 m) porque el ambiente es un fondo: si el viento se oye a 80 m suena a
## efecto, no a lugar.
const DISTANCIA_MAX: float = 45.0
## Segundos de fundido al cambiar de zona. 1,5 s es lo que tarda el oído en
## dejar de notar la transición; más corto se oye como un corte.
const FUNDIDO: float = 1.5
## dB de "silencio": el piso de Godot. Abajo ya no hay señal.
const DB_SILENCIO: float = -60.0
## Cada cuánto se mira la zona. 0,5 s va sobrado: la zona no cambia más
## rápido que un paso, y esto corre en `_process`.
const INTERVALO_SEG: float = 0.5
## Segundos que dura un loop antes de repetirse. 6 s es el punto en el que la
## repetición deja de notarse con ruido filtrado.
const DURACION_LOOP: float = 6.0
## Tope de capas. 4 es un fondo, no una orquesta: son 4 AudioStreamPlayer3D
## vivos y 4 tweens por cambio de zona (§9.5).
const MAX_CAPAS: int = 4

## Emitida al cambiar de zona. La usan el test y quien quiera enterarse.
signal zona_cambiada(region_id: String)

## §9.1
var system_id: StringName = &"ambiente_zona"

## id de capa -> receta. El ORDEN de claves decide el índice del player, así
## que se cachea aparte: si el índice y el id se recalcularan por separado,
## un cambio en el JSON podría mandar la mezcla de "agua" al player de
## "viento" sin que nada avisara.
var _recetas: Dictionary = {}
var _orden: Array[String] = []
var _mezclas: Dictionary = {}
var _players: Array[AudioStreamPlayer3D] = []
var _streams: Dictionary = {}
## dB al que cada capa va a llegar. Es el destino del fundido, no el valor
## del player: sirve para poder preguntar "hacia dónde va" sin esperar 1,5 s.
var _destinos: Array[float] = []
var _jugador: Node3D = null
var _zona_actual: String = ""
var _acum: float = 0.0
## `RegionDB` es un RefCounted que reparsea el JSON en `cargar()`. Es el mismo
## para todos los que lo necesitan (lo hace `DecoracionDB`), y una copia por
## sistema sería parsear `regiones.json` cinco veces al arrancar.
static var _regiones: RegionDB = null


func _ready() -> void:
	if not is_in_group(Systems.GRUPO):
		add_to_group(Systems.GRUPO)
	_cargar()
	_construir_players()
	set_process(true)


func _exit_tree() -> void:
	# Los players cuelgan de este nodo y se liberan solos. Lo que hay que
	# soltar es el JUGADOR: si este nodo sobrevive un frame al cambio de
	# escena, `_jugador` sería una referencia liberada y `_process` reventaría.
	_jugador = null


## El jugador cuyo entorno se escucha. Sin él el nodo no hace nada: eso es lo
## que permite que el mismo sistema sirva en la demo y en un test.
func vigilar(j: Node3D) -> void:
	_jugador = j
	_acum = 0.0
	if j != null and is_instance_valid(j):
		_evaluar_zona()


func zona_actual() -> String:
	return _zona_actual


## Fija la mezcla A MANO, sin jugador. Lo usa el menú (fase 72): el título no
## tiene un jugador al que vigilar, pero sí puede tener un fondo —y un menú
## mudo con un 3D girando alrededor es la primera impresión del juego.
func fijar_zona(region_id: String) -> void:
	if region_id == _zona_actual:
		return
	_zona_actual = region_id
	_aplicar_mezcla(region_id)
	zona_cambiada.emit(region_id)


## Las capas cuyo player está sonando (para el test y para depurar).
## "Sonando" es `playing`, no "audible": durante el fundido una capa entra
## sonando y todavía está a -60 dB, y esa es justo la diferencia entre un
## fondo que aparece y un golpe.
func capas_activas() -> Array[String]:
	var out: Array[String] = []
	for i in range(_players.size()):
		if _players[i].playing:
			out.append(_orden[i])
	return out


## Los ids de capa, en orden. El test los usa para saber qué existe.
func capas_disponibles() -> Array[String]:
	return _orden.duplicate()


## El dB al que queda una capa ahora mismo. El test lo lee para comprobar
## que el fundido va a la mezcla del JSON y no a un valor inventado.
func volumen_de(id_capa: String) -> float:
	var i: int = _orden.find(id_capa)
	if i < 0 or i >= _players.size():
		return DB_SILENCIO
	return _players[i].volume_db


## El dB al que la capa va a LLEGAR (el destino del fundido). Se separa del
## volumen actual porque el fundido tarda 1,5 s: un test que lo esperara
## midiendo frames depende de la velocidad de la máquina, y uno que mirara
## `volume_db` al principio vería el valor viejo y creería que está roto.
func destino_de(id_capa: String) -> float:
	var i: int = _orden.find(id_capa)
	if i < 0 or i >= _destinos.size():
		return DB_SILENCIO
	return _destinos[i]


func _process(delta: float) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	_acum += delta
	if _acum < INTERVALO_SEG:
		return
	_acum = 0.0
	_evaluar_zona()


## Qué región es esta. Del dato (`RegionDB`), no de una constante ni de una
## ruta de nodo (§9.1): el proyecto tiene una cadena de demos de seis niveles
## con 12 rutas `$Terreno` hardcodeadas, y una más sería la séptima.
func _evaluar_zona() -> void:
	var region_id: String = _region_de(_jugador.global_position)
	if region_id == _zona_actual:
		return
	_zona_actual = region_id
	_aplicar_mezcla(region_id)
	zona_cambiada.emit(region_id)


func _region_de(pos: Vector3) -> String:
	if _regiones == null:
		_regiones = RegionDB.new()
		if not _regiones.cargar():
			push_warning("[AmbienteZona] no se pudo cargar regiones.json")
			return ""
	var r: Dictionary = _regiones.region_en(pos.x, pos.z)
	return str(r.get("id", ""))


# --- datos y generación -----------------------------------------------

func _cargar() -> void:
	var texto: String = FileAccess.get_file_as_string(RUTA_DATOS)
	if texto == "":
		push_warning("[AmbienteZona] no se pudo leer " + RUTA_DATOS)
		return
	var d: Variant = JSON.parse_string(texto)
	if not (d is Dictionary):
		push_warning("[AmbienteZona] JSON inválido: " + RUTA_DATOS)
		return
	var cfg: Dictionary = d
	var capas: Variant = cfg.get("capas", {})
	if not (capas is Dictionary):
		push_warning("[AmbienteZona] 'capas' no es un objeto")
		return
	var cd: Dictionary = capas
	for k in cd.keys():
		if _orden.size() >= MAX_CAPAS:
			push_warning("[AmbienteZona] más de %d capas: se ignoran las demás"
				% MAX_CAPAS)
			break
		var id_capa: String = str(k)
		_orden.append(id_capa)
		_recetas[id_capa] = cd[id_capa]
	var mezclas: Variant = cfg.get("mezclas", {})
	if mezclas is Dictionary:
		_mezclas = mezclas


## Los loops se generan UNA vez al arrancar, no por cambio de zona:
## generarlos en el momento del cambio costaría medio frame de CPU y sonaría
## a un clic.
func _construir_players() -> void:
	for id_capa in _orden:
		var p := AudioStreamPlayer3D.new()
		p.name = "Ambiente_" + id_capa
		p.bus = "Ambiente"
		# Mismo criterio que el pool 3D de `AudioJuego`: distancia máxima y
		# atenuación inversa. Sin esto el viento se oye igual a 200 m.
		p.unit_size = 8.0
		p.max_distance = DISTANCIA_MAX
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		# Arranca muda: una capa que entra con su volumen final se oye como un
		# golpe, no como un fondo que ya estaba ahí.
		p.volume_db = DB_SILENCIO
		add_child(p)
		_players.append(p)
		_destinos.append(DB_SILENCIO)
		var receta: Dictionary = _recetas[id_capa]
		var stream := Sintetizador.generar_bucle(receta, DURACION_LOOP)
		_streams[id_capa] = stream
		# El stream se pone YA, no en el primer cambio de zona: un player con
		# `stream == null` no suena aunque se le pida `play()`, y la capa
		# arrancaría muda para siempre en vez de en el fundido.
		p.stream = stream


## La mezcla de una región: qué capas y a qué dB. Sale del JSON, con
## `default` como red de seguridad para una región sin entrada.
func _aplicar_mezcla(region_id: String) -> void:
	var m: Variant = _mezclas.get(region_id, _mezclas.get("default", {}))
	var niveles: Dictionary = m if m is Dictionary else {}
	for i in range(_orden.size()):
		var id_capa: String = _orden[i]
		_deslizar(i, float(niveles.get(id_capa, DB_SILENCIO)), id_capa)
	_anclar()


func _deslizar(idx: int, destino_db: float, id_capa: String) -> void:
	if idx < 0 or idx >= _players.size():
		return
	var p: AudioStreamPlayer3D = _players[idx]
	var stream: Variant = _streams.get(id_capa)
	if stream == null:
		p.volume_db = DB_SILENCIO
		p.stop()
		return
	if p.stream != stream:
		p.stream = stream
	if idx < _destinos.size():
		_destinos[idx] = destino_db
	if destino_db > DB_SILENCIO + 0.5:
		if not p.playing:
			p.play()
	elif p.playing:
		p.stop()
	# El tween ES el fundido: cambiar el volumen de golpe al cruzar de región
	# suena a que arrancaron una radio.
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(p, "volume_db", destino_db, FUNDIDO)


## El ambiente sigue al JUGADOR, no al nodo: el viento no está clavado en un
## punto del mapa, está en la región entera. Sin esto, alejarse 100 m del
## punto donde se instanció lo deja en silencio.
func _anclar() -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var pos: Vector3 = _jugador.global_position
	for p in _players:
		p.global_position = pos