extends Node3D
## Demo de la fase 4: cableado mínimo del loop jugable.
##
## - Carga data/enemies.json y configura los 3 enemigos instanciados en la
##   escena (data-driven: el .tscn solo dice el arquetipo_id).
## - Conecta el botín de cada enemigo → crea Pickups → el oro va al jugador.
## - Al morir un enemigo se oculta su cuerpo (el nodo se conserva para el
##   save/load, que guarda vivos/muertos por índice).
## - F9 = guardar partida, F10 = cargar partida (InputMap, sin hardcodear).
## Es scaffolding de demo, no un sistema del juego.

const ENEMIES_JSON: String = "res://data/enemies.json"

@onready var _jugador: Player = $Player
@onready var _rig: CameraRig = $CameraRig
@onready var _hud: HUD = $HUD

var _guardado: SaveSystem = null
var _arquetipos: Dictionary = {}


func _ready() -> void:
	_cargar_datos()
	var lista: Array = []
	for n in get_tree().get_nodes_in_group("enemigos"):
		var e: Enemy = n as Enemy
		if e == null:
			continue
		var id: String = e.arquetipo_id
		if not _arquetipos.has(id):
			push_warning("[Fase4] arquetipo desconocido: '%s'" % id)
			continue
		e.configurar(_arquetipos[id])
		e.botin_generado.connect(_al_botin_generado)
		e.murio.connect(_al_morir_enemigo.bind(e))
		lista.append(e)
	_hud.conectar(_jugador)
	_guardado = SaveSystem.new()
	_guardado.jugador = _jugador
	_guardado.enemigos = lista


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("guardar_partida"):
		if _guardado.guardar():
			print("[Fase4] partida guardada")
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cargar_partida"):
		if _guardado.cargar():
			# La cámara persigue con damping; al cargar se coloca de golpe
			# para no "deslizar" desde la posición vieja.
			_rig.global_position = _jugador.global_position
			print("[Fase4] partida cargada")
			get_viewport().set_input_as_handled()


func _cargar_datos() -> void:
	var texto: String = FileAccess.get_file_as_string(ENEMIES_JSON)
	if texto.is_empty():
		push_error("[Fase4] no se pudo leer " + ENEMIES_JSON)
		return
	var crudo: Variant = JSON.parse_string(texto)
	if crudo is Dictionary:
		_arquetipos = (crudo as Dictionary).get("arquetipos", {})
	else:
		push_error("[Fase4] JSON inválido en " + ENEMIES_JSON)


func _al_botin_generado(drops: Array, pos: Vector3) -> void:
	for d in drops:
		var dd: Dictionary = d
		var p: Pickup = Pickup.new()
		p.drop = dd
		var ang: float = randf() * TAU
		var radio: float = randf_range(0.8, 1.6)
		p.position = pos + Vector3(cos(ang) * radio, 0.4, sin(ang) * radio)
		p.recogido.connect(_al_recoger_botin)
		add_child(p)


func _al_recoger_botin(drop: Dictionary) -> void:
	if str(drop.get("tipo", "")) == "oro":
		_jugador.ganar_oro(int(drop.get("cantidad", 0)))
	else:
		_jugador.guardar_item(drop)


func _al_morir_enemigo(_fuente: Entity, e: Enemy) -> void:
	e.ocultar_cuerpo()
