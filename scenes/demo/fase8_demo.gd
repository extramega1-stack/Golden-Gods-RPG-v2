extends Node3D
## Demo de la fase 8: lo mismo que la fase 7, más las misiones:
## - `QuestLog` (lógica pura) + `data/quests.json` (3 misiones: goblins,
##   colmillos y el mensaje de Sira).
## - Hablar con un NPC (E) abre el diálogo como antes, pero además:
##   registra el diálogo en el QuestLog (objetivos "hablar") y refresca el
##   botón de misión según `oferta_para_npc` ("¡Misión disponible!" o
##   "Entregar misión"; sin oferta no hay botón — fase 6/7 intactas).
## - Pulsar el botón de misión NO cierra el diálogo: acepta o entrega la
##   misión y muestra un toast ("Misión aceptada: X" / "Misión completada:
##   +N oro, +M XP").
## - Las muertes avanzan los objetivos "matar" (`registrar_muerte`); los
##   pickups y las compras/ventas sincronizan los "recolectar"
##   (`sincronizar_recoleccion` con el inventario real).
## - Panel de misiones con J (capa 27; arranca oculto; ESC cierra):
##   misiones en curso con progreso "x/y" y "¡Lista para entregar!".
## - Guardado v5 (F9): incluye las misiones (estados + progreso);
##   cargar (F10) las restaura en sitio (las partidas v4 sin misiones
##   cargan con el QuestLog vacío).
## Es scaffolding de demo, no un sistema del juego.

const ENEMIES_JSON: String = "res://data/enemies.json"
const NPC_ESCENA: String = "res://scenes/npc/npc.tscn"

@onready var _jugador: Player = $Player
@onready var _rig: CameraRig = $CameraRig
@onready var _hud: HUD = $HUD
@onready var _barra: BarraAcciones = $BarraAcciones
@onready var _indicador: IndicadorSeleccion = $IndicadorSeleccion
@onready var _dialogo: VentanaDialogo = $VentanaDialogo
@onready var _panel_inv: PanelInventario = $PanelInventario
@onready var _panel_eq: PanelEquipo = $PanelEquipo
@onready var _panel_tienda: PanelTienda = $PanelTienda
@onready var _panel_misiones: PanelMisiones = $PanelMisiones

var _guardado: SaveSystem = null
var _arquetipos: Dictionary = {}
## Fase 7: la tienda viva de la demo (se guarda/carga con el SaveSystem).
var _tienda: Tienda = null
## Fase 8: las misiones de la demo (se guardan/cargan con el SaveSystem).
var _misiones: QuestLog = null


func _ready() -> void:
	_cargar_datos()
	var lista: Array = []
	for n in get_tree().get_nodes_in_group("enemigos"):
		var e: Enemy = n as Enemy
		if e == null:
			continue
		var id: String = e.arquetipo_id
		if not _arquetipos.has(id):
			push_warning("[Fase8] arquetipo desconocido: '%s'" % id)
			continue
		e.configurar(_arquetipos[id])
		e.botin_generado.connect(_al_botin_generado)
		e.murio.connect(_al_morir_enemigo.bind(e))
		lista.append(e)
	var lista_npcs: Array = _crear_npcs()
	_hud.conectar(_jugador)
	_barra.conectar(_jugador)
	_indicador.conectar(_jugador)
	# Fase 8: hablar abre el diálogo Y registra el diálogo en las misiones
	# (objetivos "hablar") y refresca el botón de misión.
	_misiones = QuestLog.new()
	_jugador.hablar_con.connect(_al_hablar_con)
	_dialogo.mision_solicitada.connect(_al_mision_dialogo)
	_panel_misiones.conectar(_jugador, _misiones)
	# Fase 7: "Comerciar" en el diálogo abre el panel de la tienda.
	_tienda = Tienda.new()
	_dialogo.comerciar_solicitado.connect(_al_comerciar)
	_panel_tienda.conectar(_jugador)
	# Fase 8: comprar/vender también mueve el inventario (los objetivos
	# "recolectar" se sincronizan solos, ida y vuelta).
	_tienda.cambiada.connect(_al_tienda_cambiada)
	# Oro inicial para probar las compras (demo).
	_jugador.ganar_oro(200)
	_panel_inv.conectar(_jugador)
	_panel_eq.conectar(_jugador)
	_guardado = SaveSystem.new()
	_guardado.jugador = _jugador
	_guardado.enemigos = lista
	_guardado.npcs = lista_npcs
	_guardado.tienda = _tienda
	_guardado.misiones = _misiones
	# Pickups de prueba junto al spawn (el jugador arranca en el origen).
	_colocar_pickup("espada_corta", Vector3(2.0, 0.0, 2.0))
	_colocar_pickup("pocion_vida", Vector3(-2.0, 0.0, 2.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("guardar_partida"):
		if _guardado.guardar():
			print("[Fase8] partida guardada")
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cargar_partida"):
		if _guardado.cargar():
			# La cámara persigue con damping; al cargar se coloca de golpe
			# para no "deslizar" desde la posición vieja.
			_rig.global_position = _jugador.global_position
			# Cargar reemplaza las instancias de Inventario/Equipo: los
			# paneles se reconectan a las nuevas y el HUD se refresca.
			# (El QuestLog se restaura en sitio: no hay que reconectar
			# señales, pero el panel se refresca por si estaba abierto.)
			_panel_inv.conectar(_jugador)
			_panel_eq.conectar(_jugador)
			_panel_tienda.conectar(_jugador)
			_panel_misiones.conectar(_jugador, _misiones)
			_hud.refrescar()
			print("[Fase8] partida cargada")
			get_viewport().set_input_as_handled()


## Fase 7: el diálogo pidió comerciar con un NPC vendedor.
func _al_comerciar(npc: NPC) -> void:
	_panel_tienda.mostrar(_tienda, npc)


## Fase 8: hablar con un NPC abre el diálogo, registra el diálogo en las
## misiones (objetivos "hablar") y refresca el botón de misión.
func _al_hablar_con(npc: NPC) -> void:
	_dialogo.mostrar(npc)
	_misiones.registrar_dialogo(npc.npc_id)
	_refrescar_boton_mision(npc)


## Fase 8: pregunta al QuestLog qué ofrecer para este NPC y lo pinta en
## el diálogo ("" = ocultar, el comportamiento de fase 6/7 no cambia).
func _refrescar_boton_mision(npc: NPC) -> void:
	var oferta: Dictionary = _misiones.oferta_para_npc(npc.npc_id)
	if oferta.is_empty():
		_dialogo.mostrar_mision("", "", "")
	else:
		_dialogo.mostrar_mision(
			str(oferta.get("modo", "")),
			str(oferta.get("nombre", "")),
			str(oferta.get("descripcion", "")))


## Fase 8: el jugador pulsó el botón de misión en el diálogo (el diálogo
## sigue abierto). Acepta o entrega según el modo y muestra un toast.
func _al_mision_dialogo(npc: NPC) -> void:
	var oferta: Dictionary = _misiones.oferta_para_npc(npc.npc_id)
	if oferta.is_empty():
		return
	var qid: String = str(oferta.get("quest_id", ""))
	var modo: String = str(oferta.get("modo", ""))
	if modo == "disponible":
		if _misiones.aceptar(qid) == "ok":
			_panel_misiones.toast("Misión aceptada: %s" % str(oferta.get("nombre", "")))
	elif modo == "entregar":
		var res: Dictionary = _misiones.entregar(qid, _jugador)
		if str(res.get("resultado", "")) == "ok":
			_panel_misiones.toast("Misión completada: +%d oro, +%d XP" % [
				int(res.get("oro", 0)), int(res.get("xp", 0))])
	_refrescar_boton_mision(npc)


## Fase 8: comprar/vender mueve el inventario → se sincronizan los
## objetivos "recolectar" (ida y vuelta: vender colmillos resta progreso).
func _al_tienda_cambiada() -> void:
	_misiones.sincronizar_recoleccion(_jugador.inventario)


func _cargar_datos() -> void:
	var texto: String = FileAccess.get_file_as_string(ENEMIES_JSON)
	if texto.is_empty():
		push_error("[Fase8] no se pudo leer " + ENEMIES_JSON)
		return
	var crudo: Variant = JSON.parse_string(texto)
	if crudo is Dictionary:
		_arquetipos = (crudo as Dictionary).get("arquetipos", {})
	else:
		push_error("[Fase8] JSON inválido en " + ENEMIES_JSON)


## Instancia los NPCs de NpcDB (grupo "npcs", no combatibles). Retorna la
## lista para el guardado.
func _crear_npcs() -> Array:
	var escena: PackedScene = load(NPC_ESCENA) as PackedScene
	if escena == null:
		push_warning("[Fase8] no se pudo cargar " + NPC_ESCENA)
		return []
	var lista: Array = []
	for npc_id in NpcDB.ids():
		var datos: Dictionary = NpcDB.obtener(npc_id)
		var npc: NPC = escena.instantiate() as NPC
		if npc == null:
			continue
		var pos: Array = datos.get("posicion", [0.0, 0.0, 0.0])
		npc.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		add_child(npc)
		npc.configurar(datos)
		lista.append(npc)
		print("[Fase8] NPC: %s (%s)" % [npc.nombre_mostrado, npc.npc_id])
	return lista


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
	# Fase 8: recoger mueve el inventario → se sincronizan los objetivos
	# "recolectar".
	_misiones.sincronizar_recoleccion(_jugador.inventario)


func _al_morir_enemigo(_fuente: Entity, e: Enemy) -> void:
	e.ocultar_cuerpo()
	# Fase 8: las muertes avanzan los objetivos "matar".
	_misiones.registrar_muerte(e.arquetipo_id)
