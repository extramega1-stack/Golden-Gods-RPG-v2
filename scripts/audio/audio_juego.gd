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

## Emitido CADA vez que un sonido sale de verdad (no cuando se descarta por
## antirrepeticion). Es el gancho que permite comprobar lo único que importa:
## que mover el dato MUEVA el sonido. Conectar una señal dentro de un test y
## ver que se emitió no prueba nada; hay que mover el vital, restar vida o
## ganar un nivel, y mirar esto.
signal sonido_reproducido(sonido_id: String)

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
	# POR QUE ESTA LINEA EXISTE (fase 72): el titulo crea su propio
	# `AudioJuego`, y al pasar a la partida el arbol entero se libera. `_inst`
	# es un estatico: sin esta guarda queda apuntando a un objeto liberado y
	# el SIGUIENTE `reproducir()` --el primero que dispara la partida-- llama
	# sobre un objeto muerto, y Godot no avisa.
	#
	# Con la guarda, el siguiente `reproducir()` ve `_inst == null`, no
	# instancia nada (los one-shots de la carga se pierden, que es lo
	# correcto: la partida todavia no tiene su nodo) y no revienta.
	if _inst == self:
		_inst = null


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


## Fase 72: la muerte del JUGADOR. Distinta de `muerte` a propósito: la del
## mob es un objeto que desaparece (sierra que cae), la del jugador es una
## caída larga y grave. Si compartieran receta, el oído no distinguiría
## "mataron a un goblin" de "me mataron".
static func al_morir_jugador() -> void:
	reproducir("murio_jugador")


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


# --- fase 72: los quince que NO se disparaban -------------------------
#
# Los quince sonidos que `data/sonidos.json` declaraba desde el bloque 66 y
# que ningun call site pedia. Cada uno tiene aqui su funcion y su unico
# lugar de llamada en la mecanica que le corresponde: la funcion ES el
# contrato, y el test comprueba que existe la funcion Y que se llama.

## Tala: el tajo. Posicional en el arbol, que es donde esta el sonido.
static func al_talar(nodo: Node3D) -> void:
	# Sin nodo (el mundo se liberó, o el streaming ya movió la cosa) el sonido
	# CAE a 2D en vez de perderse: `reproducir_en` con null no hace nada, y un
	# sonido que no suena es peor que uno que suena sin dirección.
	if nodo != null and is_instance_valid(nodo):
		reproducir_en(nodo, "talar")
	else:
		reproducir("talar")


## Minar: el pico. Posicional en la veta.
static func al_minar(nodo: Node3D) -> void:
	# Sin nodo (el mundo se liberó, o el streaming ya movió la cosa) el sonido
	# CAE a 2D en vez de perderse: `reproducir_en` con null no hace nada, y un
	# sonido que no suena es peor que uno que suena sin dirección.
	if nodo != null and is_instance_valid(nodo):
		reproducir_en(nodo, "minar")
	else:
		reproducir("minar")


## Romper: el nodo se agota (la veta se cierra, el arbol cae). El golpe que
## lo deja sin usos, no el que lo encuentra ya muerto.
static func al_romper(nodo: Node3D) -> void:
	# Sin nodo (el mundo se liberó, o el streaming ya movió la cosa) el sonido
	# CAE a 2D en vez de perderse: `reproducir_en` con null no hace nada, y un
	# sonido que no suena es peor que uno que suena sin dirección.
	if nodo != null and is_instance_valid(nodo):
		reproducir_en(nodo, "romper")
	else:
		reproducir("romper")


## Construir: una pieza colocada en el refugio. No posicional: el refugio
## suena entero, no desde elcorner donde se puso la pieza.
static func al_construir() -> void:
	reproducir("construir")


## Prender una fogata. Posicional: una fogata a 30 m tiene que sonar a 30 m.
static func al_fogata(nodo: Node3D) -> void:
	# Sin nodo (el mundo se liberó, o el streaming ya movió la cosa) el sonido
	# CAE a 2D en vez de perderse: `reproducir_en` con null no hace nada, y un
	# sonido que no suena es peor que uno que suena sin dirección.
	if nodo != null and is_instance_valid(nodo):
		reproducir_en(nodo, "fogata")
	else:
		reproducir("fogata")


## Comer y beber. Distintas porque el oído los distingue sin mirar nada:
## una comida es un crujido corto y una bebida un arrastre de medio segundo.
static func al_comer() -> void:
	reproducir("comer")


static func al_beber() -> void:
	reproducir("beber")


## El aviso de que un vital se cruzó. `cual` es el id de `Vitals.mas_bajo()`:
## "hambre", "sed" o "energia".
static func al_vital_bajo(cual: String) -> void:
	match cual:
		"hambre":
			reproducir("hambre")
		"sed":
			reproducir("sed")
		_:
			return


## La enfermedad aparece: comer crudo tiene que sonar a un aviso, no a una
##Mejora.
static func al_enfermo() -> void:
	reproducir("enfermo")


## Descansar:instalar el campamento en el refugio.
static func al_descansar() -> void:
	reproducir("descansar")


## Viaje rapido: el fundido de la transicion de ciudad.
static func al_viajar() -> void:
	reproducir("viajar")


## Descubrir una region: el mismo instante en que aparece el banner.
static func al_descubrir() -> void:
	reproducir("descubrir")


## El proyectil sale de la mano. Posicional en el lanzador: una flecha a 40 m
## tiene que sonar a 40 m.
static func al_proyectil(nodo: Node3D) -> void:
	# Sin nodo (el mundo se liberó, o el streaming ya movió la cosa) el sonido
	# CAE a 2D en vez de perderse: `reproducir_en` con null no hace nada, y un
	# sonido que no suena es peor que uno que suena sin dirección.
	if nodo != null and is_instance_valid(nodo):
		reproducir_en(nodo, "proyectil")
	else:
		reproducir("proyectil")


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
	sonido_reproducido.emit(sonido_id)


func _reproducir_en(nodo: Node3D, sonido_id: String, variacion: int, pitch: float) -> void:
	if nodo == null or not is_instance_valid(nodo):
		return
	if not _streams.has(sonido_id):
		sonido_desconocido.emit(sonido_id)
		return
	# Fase 72: el 3D ALSO pasa por el antirrepeticion. Antes solo lo pasaban
	# los one-shots 2D, y cuatro mobs golpeando en el mismo frame sonaban
	# cuatro golpes identicos: el oído lo lee como un fallo, no como cuatro
	# golpes. El criterio es el mismo (30 ms) por el mismo motivo.
	if _en_antirepeticion(sonido_id):
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
	# El antirrepeticion se marca TAMBIEN al final del camino 3D: si no, el
	# mismo golpe pedido por el 2D y por el 3D en el mismo frame sonaria dos
	# veces (el 2D no miraba la marca del 3D).
	_ultimo[sonido_id] = Time.get_ticks_msec() / 1000.0
	sonido_reproducido.emit(sonido_id)


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
