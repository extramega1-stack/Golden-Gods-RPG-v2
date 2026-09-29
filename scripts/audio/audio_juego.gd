class_name AudioJuego
extends Node
## Bloque 66: el sistema de audio del juego.
##
## QUÉ ARREGLA (esta es la fase que más se nota de todo el bloque):
##
## El de la fase 20 tenía un pool de 8 `AudioStreamPlayer` (2D, sin posición),
## 13 sonidos, sintetizados a 8 bits / 22050 Hz, y CUATRO call sites en todo
## el repo. El juego era essentially mudo: sin música (el bus `Musica` se
## creaba y nunca se le asignaba nada), sin ambiente, sin pisadas, sin sonidos
## de interfaz, y un goblin a 200 m sonaba igual que uno encima.
##
## - POOL DE 2D Y DE 3D. `reproducir()` para UI y jugador (no posicional: el
##   sonido de "recogiste" es del jugador, no del mundo), `reproducir_en()` para
##   el mundo (posicional, con atenuación por distancia).
## - VARIACIÓN: cada sonido tiene N variantes y cada reproducción elige una al
##   azar. Es lo que separa un impacto de un pitido.
## - SINTETIZA al arrancar, no al vuelo. Un `AudioStreamWAV` de 0,1 s a 44,1
##   kHz estéreo son 17 KB: sintetizarlo en el primer golpe provocaría un
##   tirón, y sintetizarlo siempre es tirar CPU.
## - Sonidos nuevos cableados: UI, pisadas, supervivencia, construcción.
##
## Sigue siendo data-driven: todo sale de `data/sonidos.json`.

const RUTA_DATOS: String = "res://data/sonidos.json"
## Pool 2D (interfaz, jugador, cosas no posicionales). 12 porque la UI dispara
## varios seguidos (abrir panel + clic + confirmar).
const POOL_SFX: int = 12
## Pool 3D (el mundo). 16 es suficiente para 4-5 mobs golpeando a la vez.
const POOL_MUNDO: int = 16
## A qué distancia un sonido 3D deja de oírse. 60 m: más allá, en este
## mundo con poca vegetation, no se distingue.
const DISTANCIA_MAX: float = 60.0
## Cuántas veces seguidas puede sonar el MISMO sonido antes de que se corte
## (anti-spam: 30 clicks en un frame no son 30 sonidos).
const ANTIREPETICION: float = 0.03

## Emitido cuando algo pide un sonido que no existe (test y depuración).
signal sonido_desconocido(id: String)

var _streams: Dictionary = {}
var _recetas: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _players_mundo: Array[AudioStreamPlayer3D] = []
var _idx: int = 0
var _idx_mundo: int = 0
var _ultimo: Dictionary = {}
var _siguiente_indice: Dictionary = {}


func _ready() -> void:
	_crear_buses()
	_cargar_recetas()
	_sintetizar_todo()
	_construir_pool()
	_construir_pool_mundo()


func _exit_tree() -> void:
	# Los players cuelgan de este nodo; se liberan solos. Los listeners
	# estáticos no se registran aquí, se conectan por señal (que es la
	# diferencia entre un sistema y un global colgado).
	pass


# --- API estática (los sistemas llaman por aquí) ---

static func reproducir(sonido_id: String, variacion: int = -1) -> void:
	var a: AudioJuego = _instancia()
	if a != null:
		a._reproducir(sonido_id, variacion)


## Bloque 66: sonido POSICIONAL. Para golpes, explosions, pisadas de mob. El
## `nodo` es la fuente: el sonido sale de ahí y se atenúa con la distancia.
static func reproducir_en(nodo: Node3D, sonido_id: String, variacion: int = -1,
		pitch: float = 1.0) -> void:
	var a: AudioJuego = _instancia()
	if a != null:
		a._reproducir_en(nodo, sonido_id, variacion, pitch)


static func al_impacto(es_critico: bool) -> void:
	reproducir("critico" if es_critico else "golpe")


static func al_morir() -> void:
	reproducir("muerte")


static func al_recoger(tipo: String) -> void:
	reproducir("recoger" if tipo != "oro" else "moneda")


static func al_skill(tipo_efecto: String) -> void:
	match tipo_efecto:
		"dano":
			reproducir("skill_dano")
		"curar":
			reproducir("skill_curar")
		"aoe":
			reproducir("skill_aoe")
		"buff":
			reproducir("skill_buff")
		"debuff":
			reproducir("skill_debuff")
		_:
			reproducir("clic")


## El nombre del sonido de pisada según el bioma. El terreno ya sabe su
## región; esto traduce región a material, que es lo que el oído espera.
static func paso_de_region(region_id: String) -> String:
	match region_id:
		"piedraceniza", "ceniza_forja", "el_velo":
			return "paso_piedra"
		"desert", "dunas":
			return "paso_arena"
		"costa":
			return "paso_arena"
		"bosque", "lloroso":
			return "paso_hierba"
		_:
			return "paso_tierra"


static var _inst: AudioJuego = null
static func _instancia() -> AudioJuego:
	return _inst


func _enter_tree() -> void:
	_inst = self


# --- datos y síntesis ---

func _cargar_recetas() -> void:
	var texto: String = FileAccess.get_file_as_string(RUTA_DATOS)
	var d: Variant = JSON.parse_string(texto)
	if d is Dictionary:
		var dd: Dictionary = d
		_recetas = dd.get("sonidos", {})


func _sintetizar_todo() -> void:
	for id in _recetas.keys():
		var sid: String = str(id)
		var receta: Dictionary = _recetas[sid]
		var n: int = Sintetizador.variantes_de(receta)
		var lista: Array = []
		for v in range(n):
			lista.append(Sintetizador.generar(receta, v))
		_streams[sid] = lista


func tiene_sonido(sonido_id: String) -> bool:
	return _streams.has(sonido_id)


func ids() -> Array:
	return _streams.keys()


# --- reproducción ---

func _reproducir(sonido_id: String, variacion: int = -1) -> void:
	if not _streams.has(sonido_id):
		sonido_desconocido.emit(sonido_id)
		return
	if _en_antirepeticion(sonido_id):
		return
	var lista: Array = _streams[sonido_id]
	var v: int = variacion if variacion >= 0 else randi() % lista.size()
	v = clampi(v, 0, lista.size() - 1)
	var p: AudioStreamPlayer = _voz_libre()
	if p == null:
		return
	p.stream = lista[v]
	p.bus = "SFX"
	p.play()
	_ultimo[sonido_id] = Time.get_ticks_msec() / 1000.0


func _reproducir_en(nodo: Node3D, sonido_id: String, variacion: int, pitch: float) -> void:
	if nodo == null or not is_instance_valid(nodo):
		return
	if not _streams.has(sonido_id):
		sonido_desconocido.emit(sonido_id)
		return
	var lista: Array = _streams[sonido_id]
	var v: int = variacion if variacion >= 0 else randi() % lista.size()
	v = clampi(v, 0, lista.size() - 1)
	var p: AudioStreamPlayer3D = _voz_mundo_libre()
	if p == null:
		return
	# La voz se reubica en el nodo que suena. Es un truco viejo y correcto:
	# en vez de un player por mobs (que serían miles), hay 16 que se mueven.
	p.global_position = nodo.global_position
	p.stream = lista[v]
	p.pitch_scale = clampf(pitch, 0.5, 2.0)
	p.bus = "SFX"
	p.max_distance = DISTANCIA_MAX
	p.play()


func _en_antirepeticion(sonido_id: String) -> bool:
	var t: float = Time.get_ticks_msec() / 1000.0
	if _ultimo.has(sonido_id) and t - float(_ultimo[sonido_id]) < ANTIREPETICION:
		return true
	return false


func _voz_libre() -> AudioStreamPlayer:
	for i in range(_players.size()):
		var idx: int = (_idx + i) % _players.size()
		if not _players[idx].playing:
			_idx = (idx + 1) % _players.size()
			return _players[idx]
	# Todas ocupadas: se roba la más antigua (round-robin). Perder un sonido es
	# mejor que cortar el audio entero.
	var p: AudioStreamPlayer = _players[_idx]
	_idx = (_idx + 1) % _players.size()
	return p


func _voz_mundo_libre() -> AudioStreamPlayer3D:
	for i in range(_players_mundo.size()):
		var idx: int = (_idx_mundo + i) % _players_mundo.size()
		if not _players_mundo[idx].playing:
			_idx_mundo = (idx + 1) % _players_mundo.size()
			return _players_mundo[idx]
	var p: AudioStreamPlayer3D = _players_mundo[_idx_mundo]
	_idx_mundo = (_idx_mundo + 1) % _players_mundo.size()
	return p


# --- pools y buses ---

func _crear_buses() -> void:
	_asegurar_bus("SFX")
	_asegurar_bus("Ambiente")
	_asegurar_bus("Musica")


func _asegurar_bus(nombre: String) -> void:
	for i in range(AudioServer.get_bus_count()):
		if AudioServer.get_bus_name(i) == nombre:
			return
	var idx: int = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, nombre)
	AudioServer.set_bus_send(idx, "Master")


func _construir_pool() -> void:
	for i in range(POOL_SFX):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)


func _construir_pool_mundo() -> void:
	for i in range(POOL_MUNDO):
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 6.0
		p.max_db = 0.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_players_mundo.append(p)
