class_name Musica
extends Node
## Bloque 66: la música, por capas que se mezclan según el estado del juego.
##
## POR QUÉ CAPAS Y NO UNA PISTA: un loop único de "música de RPG" se vuelve
## ruido de fondo a los 5 minutos, porque el oído aprende la melodía y deja de
## oírla. Lo que hacen los juegos que se sostienen son CAPAS: una base siempre
## presente (percusión lenta) y encima melodía o coros que SOLO entran en
## combate, en exploración tranquila, o contra un jefe. El jugador oye la
## diferencia sin darse cuenta, y por eso sigue oyendo la música una hora
## después en lugar de apagarla.
##
## - Cuatro capas, cada una un `AudioStreamPlayer` del bus `Musica`.
## - DUCKING: cuando entra `combate`, la capa `base` BAJA en vez de que la
##   nueva suba encima. Es lo que hacen los juegos de producción y lo que evita
##   que entrar en combate suene como un portazo durante 2 segundos.
## - Sin assets: las capas se GENERAN, no se cargan de archivos. Cada una es un
##   bucle de N compases (`loop_mode = LOOP_FORWARD`) construido con un pad
##   armónico, una fundamental que se mueve por un `raiz` de acordes, y
##   percusión. La diferencia entre exploración y combate está en la escala, el
##   tempo y la percusión, no en un archivo.
##
## Data-driven: `data/musica.json` describe los temas y qué capas usa cada uno.

const RUTA: String = "res://data/musica.json"

const CAPA_BASE: int = 0
const CAPA_EXPLORACION: int = 1
const CAPA_COMBATE: int = 2
const CAPA_JEFE: int = 3
## Segundos de fundido al cambiar de estado. Corto a propósito: si dura más de
## un segundo y medio, el cambio se siente como un fallo y no como una música.
const FUNDIDO: float = 1.2
## Volumen de cada capa en dB. La base está más abajo porque es la que está
## siempre; la de jefe, arriba, porque es la que tiene que dominar.
const DB_CAPA: Array[float] = [-8.0, -11.0, -7.0, -3.0]
## dB de "silencio": -60 es el piso de Godot, más abajo ya no se oye.
const DB_SILENCIO: float = -60.0

## Cambiar de estado emite esto. Lo usan los tests y, si algún día, la UI.
signal estado_cambiado(estado: int)

var _streams: Dictionary = {}
var _temas: Dictionary = {}
## Estado → tema → capas. Del dato, no hardcodeado: cambiar qué capas entran en
## combate es tocar el JSON, no el código.
var _estados: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _estado: int = -1


func _ready() -> void:
	_crear_bus()
	_construir_capas()
	_cargar()


# --- buses y capas ---------------------------------------------------

func _crear_bus() -> void:
	for i in range(AudioServer.get_bus_count()):
		if AudioServer.get_bus_name(i) == "Musica":
			return
	var idx: int = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Musica")
	AudioServer.set_bus_send(idx, "Master")


func _construir_capas() -> void:
	for i in range(DB_CAPA.size()):
		var p := AudioStreamPlayer.new()
		p.bus = "Musica"
		# Arranca muda: una capa que entra con su volumen final se oye como un
		# golpe, no como una música que ya estaba.
		p.volume_db = DB_SILENCIO
		add_child(p)
		_players.append(p)


# --- datos -----------------------------------------------------------

## Genera cada tema UNA vez al arrancar y arranca en exploración. Generar en el
## primer cambio de estado costaría medio segundo de CPU, que es justo lo que
## pasa si el jugador entra en combate durante el primer minuto.
func _cargar() -> void:
	var texto: String = FileAccess.get_file_as_string(RUTA)
	var d: Variant = JSON.parse_string(texto)
	if not (d is Dictionary):
		push_warning("[Musica] no se pudo leer " + RUTA)
		return
	var cfg: Dictionary = d
	_temas = cfg.get("temas", {})
	_estados = cfg.get("estados", {})
	for nombre in _temas.keys():
		var t: Dictionary = _temas[nombre]
		_streams[str(nombre)] = _generar_capa(t)
	cambiar_estado(CAPA_EXPLORACION)


func tema_ids() -> Array:
	return _streams.keys()


# --- generación ------------------------------------------------------

## Construye el WAV de un tema: un bucle de `compases` compases.
##
## Lo que hace que no suene a un zumbido:
## - la fundamental se MUEVE por el `raiz` de acordes, compás a compás, así que
##   el bucle tiene dirección armónica y no se siente estático;
## - el pad es un acorde (varias notas a la vez), no una nota, y por eso tiene
##   cuerpo;
## - la percusión tiene un barrido descendente y caída rápida, que es lo que
##   separa un golpe percusivo de un clic.
func _generar_capa(cfg: Dictionary) -> AudioStreamWAV:
	var compases: int = maxi(1, int(cfg.get("compases", 4)))
	var bpm: float = maxf(20.0, float(cfg.get("bpm", 90.0)))
	var escala: Array = cfg.get("escala", [0, 2, 4, 5, 7, 9, 11])
	var tonalidad: float = float(cfg.get("tonalidad", 220.0))
	var raiz: Array = cfg.get("raiz", [0, 4, 7, 12, 7, 4])
	var percusion: String = str(cfg.get("percusion", "suave"))
	var tipo: String = str(cfg.get("tipo", "pad"))

	var seg_compas: float = 60.0 / bpm
	var n: int = int(Sintetizador.TASA * seg_compas * float(compases))
	if n < Sintetizador.TASA:
		n = Sintetizador.TASA  # al menos un segundo, si no el bucle es un clic
	var datos := PackedByteArray()
	datos.resize(n * 4)  # 16 bits x 2 canales

	var indice_raiz: int = 0
	for i in range(n):
		var t: float = float(i) / float(Sintetizador.TASA)
		var comp: int = int(fmod(t / seg_compas, float(compases)))
		# Cada compás, la fundamental avanza un grado del `raiz`.
		if indice_raiz < comp and indice_raiz < raiz.size():
			indice_raiz += 1
		var fundamental: float = tonalidad \
			* pow(2.0, float(int(raiz[indice_raiz % maxi(1, raiz.size())])) / 12.0)

		# --- pad: el cuerpo armónico ---
		var pad: float = 0.0
		match tipo:
			"arpa", "melodia":
				# Una nota de la escala cada medio compás: es lo que da la
				# sensación de "melodía" sin llegar a ser una melodía real.
				var idx: int = int(t / (seg_compas / 4.0)) % maxi(1, escala.size())
				var f_mel: float = fundamental \
					* pow(2.0, float(int(escala[idx])) / 12.0)
				# El semiperíodo hace que cada nota "corte" en vez de
				# solaparse: es un arpegio, no un drone.
				var local: float = fmod(t, seg_compas / 4.0)
				var dur_nota: float = seg_compas / 4.0
				var env_nota: float = pow(1.0 - local / dur_nota, 1.8)
				pad = (sin(TAU * f_mel * t) * 0.7
					+ sin(TAU * f_mel * 2.0 * t) * 0.2) * env_nota
			"coro":
				for g in escala:
					pad += sin(TAU * fundamental
						* pow(2.0, float(int(g)) / 12.0) * t + 0.3)
				pad /= float(maxi(1, escala.size()))
			_:
				for g in escala:
					pad += sin(TAU * fundamental
						* pow(2.0, float(int(g)) / 12.0) * t)
				pad /= float(maxi(1, escala.size()))

		# --- percusión: el pulso, que es lo que ancla el bucle al tiempo ---
		var perc: float = 0.0
		match percusion:
			"fuerte":
				perc = _golpe_en(t, seg_compas / 2.0, 120.0, 0.06) * 0.9
			"corchea":
				perc = _golpe_en(t, seg_compas / 4.0, 110.0, 0.04) * 0.6
			_:
				perc = _golpe_en(t, seg_compas, 90.0, 0.09) * 0.5

		var s: float = (pad * 0.55 + perc) * 0.55
		# La percusión un poco desplazada al canal derecho: separa el pulso
		# del cuerpo sin necesidad de un bus de percusión.
		Sintetizador._escribir(datos, i, s, pad * 0.55 + perc * 0.7)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = Sintetizador.TASA
	stream.stereo = true
	stream.data = datos
	# El bucle ES el punto: sin esto cada compás se oye reiniciado.
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = n
	return stream


## Un golpe percusivo: seno con barrido descendente y caída rápida. Pura:
## recibe el instante absoluto y decide por su cuenta si cae dentro del golpe.
func _golpe_en(t_absoluto: float, periodo: float, freq: float, dur: float) -> float:
	var f: float = fmod(t_absoluto, periodo)
	if f >= dur:
		return 0.0
	var x: float = f / dur
	return sin(TAU * lerpf(freq, freq * 0.4, x) * f) * pow(1.0 - x, 3.0)


# --- control de estado -----------------------------------------------

func estado() -> int:
	return _estado


## Cambia de "escena" musical. Es lo que hace la música adaptativa: el juego
## va cambiando de estado (explorando, luchando, en un jefe) y la música sigue.
func cambiar_estado(estado: int) -> void:
	if estado == _estado:
		return
	_estado = estado
	var tema: String = _tema_de(estado)
	# Las capas de cada estado salen del JSON, no de un if en el código.
	var ecfg: Dictionary = _estados.get(tema, {})
	var activas: Array = ecfg.get("capas", [])
	# El "padre" es el stream que suena en esa capa: normalmente el propio
	# tema; permite que una capa reuse el stream de otra.
	var padre: String = str(ecfg.get("capa_padre", ""))
	for i in range(_players.size()):
		# La base (0) está siempre: es la que sostiene el ritmo. Las demás
		# entran y salen.
		var debe: bool = i == 0 or activas.has(i)
		_deslizar(i, DB_CAPA[i] if debe else DB_SILENCIO, padre)
	estado_cambiado.emit(estado)


func _tema_de(estado: int) -> String:
	match estado:
		CAPA_BASE:
			return "pueblo"
		CAPA_EXPLORACION:
			return "exploracion"
		CAPA_COMBATE:
			return "combate"
		CAPA_JEFE:
			return "jefe"
	return "exploracion"


## El stream que suena en una capa. `padre` permite que varias capas del MISMO
## tema compartan un stream (combate y jefe comparten percusión, por ejemplo).
func _stream_de(i: int, padre: String) -> AudioStreamWAV:
	if padre != "" and _streams.has(padre):
		return _streams[padre]
	var nombre: String = _tema_de(i)
	if _streams.has(nombre):
		return _streams[nombre]
	return null


func _deslizar(capa: int, destino: float, padre: String) -> void:
	if capa >= _players.size():
		return
	var stream: AudioStreamWAV = _stream_de(capa, padre)
	var p: AudioStreamPlayer = _players[capa]
	if stream == null:
		# Sin stream no hay nada que tocar: se silencia y listo.
		p.volume_db = DB_SILENCIO
		return
	if p.stream != stream:
		p.stream = stream
		if not p.playing:
			p.play()
	# El tween ES la transición. Cambiar el volumen de golpe al entrar en
	# combate sonaría como un portazo.
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(p, "volume_db", destino, FUNDIDO)
