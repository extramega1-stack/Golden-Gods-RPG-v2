extends Node3D
## Demo de la fase 5: cableado mínimo del loop jugable.
##
## Igual que la fase 4 (enemigos data-driven, botín → pickups, F9/F10), más:
## - Conecta la barra de skills y los paneles de inventario/equipo al jugador.
## - El botín de items va al Inventario real (ya no hay inventario_simple).
## - Dos pickups pre-colocados cerca del spawn (espada_corta, pocion_vida)
##   para probar recoger/equipar/usar sin matar nada.
## - Teclas 1-5 lanzan skills; I abre el inventario; C abre el equipo.
## Es scaffolding de demo, no un sistema del juego.

const ENEMIES_JSON: String = "res://data/enemies.json"

@onready var _jugador: Player = $Player
@onready var _rig: CameraRig = $CameraRig
@onready var _hud: HUD = $HUD
@onready var _barra: BarraSkills = $BarraSkills
@onready var _panel_inv: PanelInventario = $PanelInventario
@onready var _panel_eq: PanelEquipo = $PanelEquipo

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
			push_warning("[Fase5] arquetipo desconocido: '%s'" % id)
			continue
		e.configurar(_arquetipos[id])
		e.botin_generado.connect(_al_botin_generado)
		e.murio.connect(_al_morir_enemigo.bind(e))
		lista.append(e)
	_hud.conectar(_jugador)
	_barra.conectar(_jugador)
	_panel_inv.conectar(_jugador)
	_panel_eq.conectar(_jugador)
	_guardado = SaveSystem.new()
	_guardado.jugador = _jugador
	_guardado.enemigos = lista
	# Pickups de prueba junto al spawn (el jugador arranca en el origen).
	_colocar_pickup("espada_corta", Vector3(2.0, 0.0, 2.0))
	_colocar_pickup("pocion_vida", Vector3(-2.0, 0.0, 2.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("guardar_partida"):
		if _guardado.guardar():
			print("[Fase5] partida guardada")
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cargar_partida"):
		if _guardado.cargar():
			# La cámara persigue con damping; al cargar se coloca de golpe
			# para no "deslizar" desde la posición vieja.
			_rig.global_position = _jugador.global_position
			# Cargar reemplaza las instancias de Inventario/Equipo: los
			# paneles se reconectan a las nuevas y el HUD se refresca.
			_panel_inv.conectar(_jugador)
			_panel_eq.conectar(_jugador)
			_hud.refrescar()
			print("[Fase5] partida cargada")
			get_viewport().set_input_as_handled()


func _cargar_datos() -> void:
	var texto: String = FileAccess.get_file_as_string(ENEMIES_JSON)
	if texto.is_empty():
		push_error("[Fase5] no se pudo leer " + ENEMIES_JSON)
		return
	var crudo: Variant = JSON.parse_string(texto)
	if crudo is Dictionary:
		_arquetipos = (crudo as Dictionary).get("arquetipos", {})
	else:
		push_error("[Fase5] JSON inválido en " + ENEMIES_JSON)


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


func _colocar_pickup(item_id: String, pos: Vector3) -> void:
	var p: Pickup = Pickup.new()
	p.drop = {"tipo": "item", "item_id": item_id, "cantidad": 1}
	p.position = pos + Vector3(0, 0.4, 0)
	p.recogido.connect(_al_recoger_botin)
	add_child(p)


func _al_recoger_botin(drop: Dictionary) -> void:
	if str(drop.get("tipo", "")) == "oro":
		_jugador.ganar_oro(int(drop.get("cantidad", 0)))
	else:
		_jugador.inventario.agregar(
			str(drop.get("item_id", "")), maxi(1, int(drop.get("cantidad", 1))))


func _al_morir_enemigo(_fuente: Entity, e: Enemy) -> void:
	e.ocultar_cuerpo()
