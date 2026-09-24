class_name AudioJuego
extends Node
## Manager de sonido del juego (fase 20, P1 audio).
##
## Buses propios (SFX/Ambiente/Musica colgando de Master) + pool de 8
## AudioStreamPlayer + recetas de `data/sonidos.json` sintetizadas UNA vez
## al arrancar (sin IO ni allocs en caliente). API estática segura sin
## instancia (patrón GameFeel: los tests headless sin escena no truenan).
##
## Uso desde la demo (scaffolding, como el pool):
##   var audio := AudioJuego.new()
##   audio.name = "AudioJuego"
##   add_child(audio)
## Uso desde sistemas: `AudioJuego.reproducir("moneda")`,
## `AudioJuego.al_impacto(crit)`, `AudioJuego.al_skill("curar")`, etc.

static var inst: AudioJuego = null

const RUTA_DATOS: String = "res://data/sonidos.json"
## Voces simultáneas del pool (round-robin; si se agota, roba la más vieja).
const POOL_SFX: int = 8
## true = rutea voces sin `play()` (tests headless: el driver dummy pierde
## playbacks al salir y ensucia la salida con leaks).
static var modo_prueba: bool = false

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _idx: int = 0
var _avisados: Dictionary = {}


func _ready() -> void:
	inst = self
	_crear_buses()
	_construir_pool()
	_cargar_y_sintetizar()


func _exit_tree() -> void:
	if inst == self:
		inst = null


## Reproduce un SFX por id. Seguro sin instancia; id desconocido = warning
## una sola vez (no spam por frame).
static func reproducir(sonido_id: String) -> void:
	if inst == null:
		return
	inst._reproducir(sonido_id)


## Impacto de combate (golpe normal o crítico).
static func al_impacto(es_critico: bool) -> void:
	reproducir("critico" if es_critico else "golpe")


## Muerte de un enemigo.
static func al_morir() -> void:
	reproducir("muerte")


## Botín recogido ("oro" = moneda, lo demás = recoger).
static func al_recoger(tipo: String) -> void:
	reproducir("moneda" if tipo == "oro" else "recoger")


## Skill lanzada por tipo de efecto (dano/curar/aoe/buff/debuff).
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
			reproducir("skill_dano")


## ¿Existe el stream sintetizado? (tests/UI).
func tiene_sonido(sonido_id: String) -> bool:
	return _streams.has(sonido_id)


## Ids disponibles (tests/UI).
func ids() -> Array:
	return _streams.keys()


func _reproducir(sonido_id: String) -> void:
	var p: AudioStreamPlayer = _voz_para(sonido_id)
	if p != null and not modo_prueba:
		p.play()


## Elige la voz round-robin para un id y le asigna el stream. Retorna null
## si el id es desconocido o no hay pool. Separado de `play()` para
## testear el ruteo sin reproducir (el driver dummy pierde playbacks).
func _voz_para(sonido_id: String) -> AudioStreamPlayer:
	if not _streams.has(sonido_id):
		if not _avisados.has(sonido_id):
			_avisados[sonido_id] = true
			push_warning("[AudioJuego] sonido desconocido: '%s'" % sonido_id)
		return null
	if _players.is_empty():
		return null
	var p: AudioStreamPlayer = _players[_idx]
	_idx = (_idx + 1) % _players.size()
	p.stream = _streams[sonido_id] as AudioStreamWAV
	return p


## Buses SFX/Ambiente/Musica (idempotente: si existen, no duplica).
func _crear_buses() -> void:
	_asegurar_bus("SFX")
	_asegurar_bus("Ambiente")
	_asegurar_bus("Musica")


func _asegurar_bus(nombre: String) -> void:
	if AudioServer.bus_count <= 0:
		return
	if AudioServer.get_bus_index(nombre) >= 0:
		return
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, nombre)
	AudioServer.set_bus_send(idx, "Master")


func _construir_pool() -> void:
	for i in POOL_SFX:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)


func _cargar_y_sintetizar() -> void:
	var recetas: Dictionary = _leer_recetas()
	for sonido_id in recetas:
		var r: Dictionary = recetas[sonido_id]
		if r is Dictionary:
			_streams[str(sonido_id)] = Sintetizador.generar(r)


static var _datos_cache: Dictionary = {}


## Lee el JSON UNA vez (estático cacheado, patrón de los DBs).
static func _leer_recetas() -> Dictionary:
	if not _datos_cache.is_empty():
		return _datos_cache.get("sonidos", {})
	var texto: String = FileAccess.get_file_as_string(RUTA_DATOS)
	if texto == "":
		push_warning("[AudioJuego] no se pudo leer %s" % RUTA_DATOS)
		return {}
	# parse_string retorna Variant: NUNCA `:=` aquí (warning como error).
	var crudo = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[AudioJuego] %s no es un diccionario JSON válido" % RUTA_DATOS)
		return {}
	_datos_cache = crudo
	return _datos_cache.get("sonidos", {})
