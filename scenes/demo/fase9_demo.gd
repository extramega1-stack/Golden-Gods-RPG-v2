extends Node3D
## Demo de la fase 9: lo mismo que la fase 8, más:
## - Sub-ventana de detalle de misión: en el PanelMisiones (J) el nombre
##   de cada misión en curso es un botón que abre la sub-ventana (capa 28)
##   con nombre, lore, objetivos con progreso "x/y" y recompensas.
## - Respawn de mobs: `SpawnerMobs` vigila a los enemigos; al morir
##   reaparecen tras `respawn_seg` (data/enemies.json: goblin 15 s,
##   lobo 20 s, ogro 30 s; default 20 s) en su punto de origen con
##   variación aleatoria. El jugador puede matar 5 goblins para la misión
##   aunque los mate a todos: respawnean.
## Es scaffolding de demo, no un sistema del juego.
##
## Fase 9.1: "!" dorado sobre los NPCs con misión disponible para aceptar
## (pedido de Juan Diego); 5 mobs por arquetipo (15 en total) colocados
## fuera del aggro inicial del jugador; el segundo clic en un NPC
## seleccionado lejano camina hasta él y al llegar abre el diálogo.

const ENEMIES_JSON: String = "res://data/enemies.json"
const NPC_ESCENA: String = "res://scenes/npc/npc.tscn"
## La escena del enemigo la precarga el PoolMobs UNA vez (fase 20): aquí
## ya no se hace `load()` por cada spawn (era IO + parse en el tick).

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
## Fase 9: enemigos en escena (los reaparecidos reemplazan al cadáver en
## esta lista; el SaveSystem guarda los vivos como siempre).
var _lista_enemigos: Array = []
## Fase 9: el spawner de respawn (los timers son runtime, no se guardan).
var _spawner: SpawnerMobs = null
## Fase 31: panel de habilidades (nodo de la escena principal; null en demos
## viejas como fase9, que no lo traen).
var _panel_habilidades: PanelHabilidades = null
## Fase 30: ventana de personaje (igual que talentos).
var _panel_personaje: PanelPersonaje = null
## Fase 20: pool de enemigos (precarga la escena una vez y recicla nodos
## por arquetipo). Lo usan la factory del spawner/streaming y la
## liberación del cadáver; las demos hijas lo heredan.
var _pool: PoolMobs = null
## Fase 9.1: NPCs en escena (para refrescar los marcadores de misión).
var _lista_npcs: Array = []
## Fase 9.2: estados conocidos de misión (para detectar el paso
## activa→lista y mostrar el banner de completada una sola vez).
var _estados_mision: Dictionary = {}
## Fase 9.2: mientras se carga una partida se suprimen los banners (el
## progreso restaurado no es "recién completado").
var _suprimir_banners: bool = false


func _ready() -> void:
	_cargar_datos()
	for n in _mis_enemigos():
		var e: Enemy = n as Enemy
		if e == null:
			continue
		var id: String = e.arquetipo_id
		if not _arquetipos.has(id):
			push_warning("[Fase9] arquetipo desconocido: '%s'" % id)
			continue
		e.configurar(_arquetipos[id])
		e.botin_generado.connect(_al_botin_generado)
		e.murio.connect(_al_morir_enemigo.bind(e))
		_lista_enemigos.append(e)
	var lista_npcs: Array = _crear_npcs()
	# Fase 9.1: la demo refresca los "!" dorados de misión disponible cada
	# vez que cambia el QuestLog (aceptar/entregar), y una vez al arrancar.
	_lista_npcs = lista_npcs
	# Fase 9: el spawner vigila a los enemigos y los reaparece al morir.
	_spawner = SpawnerMobs.new()
	_spawner.name = "SpawnerMobs"
	_spawner.configurar_arquetipos(_arquetipos)
	_spawner.fijar_factory(_crear_enemigo)
	_spawner.reaparecido.connect(_al_reaparecer_enemigo)
	add_child(_spawner)
	# Fase 20: el pool vive junto al spawner y comparte sus arquetipos.
	_pool = PoolMobs.new()
	_pool.name = "PoolMobs"
	_pool.configurar_arquetipos(_arquetipos)
	add_child(_pool)
	# Fase 20 (P1 audio): manager de SFX (buses + pool + recetas).
	var audio := AudioJuego.new()
	audio.name = "AudioJuego"
	add_child(audio)
	# Fase 31: panel de habilidades (solo la escena principal lo trae).
	_panel_habilidades = get_node_or_null("PanelHabilidades") as PanelHabilidades
	if _panel_habilidades != null:
		_panel_habilidades.conectar(_jugador)
	# Fase 30: ventana de personaje (igual).
	_panel_personaje = get_node_or_null("PanelPersonaje") as PanelPersonaje
	if _panel_personaje != null:
		_panel_personaje.conectar(_jugador)
	for e in _lista_enemigos:
		_spawner.vigilar(e)
	_hud.conectar(_jugador)
	_barra.conectar(_jugador)
	_indicador.conectar(_jugador)
	# Fase 18: gancho visual del feedback de skills en el héroe (tinte
	# temporal que lee Entity.fx_color; hermano de DamageFlash).
	_jugador.add_child(SkillFX.new())
	# Fase 8: hablar abre el diálogo Y registra el diálogo en las misiones
	# (objetivos "hablar") y refresca el botón de misión.
	_misiones = QuestLog.new()
	for qid in QuestDB.ids():
		_estados_mision[qid] = _misiones.estado(qid)
	_misiones.cambiada.connect(_al_cambio_misiones)
	_al_cambio_misiones()
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
	_guardado.enemigos = _lista_enemigos
	_guardado.npcs = lista_npcs
	_guardado.tienda = _tienda
	_guardado.misiones = _misiones
	# Fase 17: las asignaciones de la barra de acciones se guardan/cargan.
	_guardado.barra_acciones = _barra
	# Pickups de prueba junto al spawn (el jugador arranca en el origen).
	_colocar_pickup("espada_corta", Vector3(2.0, 0.0, 2.0))
	_colocar_pickup("pocion_vida", Vector3(-2.0, 0.0, 2.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("guardar_partida"):
		if _guardado.guardar():
			print("[Fase9] partida guardada")
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cargar_partida"):
		# Fase 11: el cuerpo del branch vive en `_cargar_partida_guardada`
		# (lo reusa la demo hija para el flujo "Continuar" del título).
		if _cargar_partida_guardada():
			get_viewport().set_input_as_handled()


## Fase 11 — carga de partida extraída del branch `cargar_partida` de
## `_unhandled_input` (mismo comportamiento, sin duplicar lógica): la usa
## el F10 y la demo hija (`fase11_demo.gd`) al arrancar con
## `DatosSesion.continuar`.
## Suprime los banners durante la carga (fase 9.2: el progreso restaurado
## no es "recién completado"); recoloca la cámara de golpe (el damping la
## haría "deslizar" desde la posición vieja); reconecta los paneles a las
## instancias nuevas de Inventario/Equipo y refresca el HUD.
func _cargar_partida_guardada() -> bool:
	_suprimir_banners = true
	var cargo: bool = _guardado.cargar()
	_suprimir_banners = false
	if cargo:
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
		if _panel_habilidades != null and is_instance_valid(_panel_habilidades):
			_panel_habilidades.conectar(_jugador)
		if _panel_personaje != null and is_instance_valid(_panel_personaje):
			_panel_personaje.conectar(_jugador)
		_hud.refrescar()
		# Fase 18: la clase restaurada del save puede no ser la de la
		# conexión inicial; el libro se refiltra (los slots los trae el
		# save con cargar_estado).
		_barra.reconstruir_libro()
		print("[Fase9] partida cargada")
	return cargo


## Fase 9.1/9.2 — la señal `cambiada` del QuestLog: detecta las
## misiones que pasaron a "lista" (objetivos completos) y muestra el
## banner dorado de completada; luego refresca los marcadores de los NPCs.
func _al_cambio_misiones() -> void:
	if _misiones == null:
		return
	for qid in QuestDB.ids():
		var est: String = _misiones.estado(qid)
		var antes: String = str(_estados_mision.get(qid, ""))
		if antes == "activa" and est == "lista" and not _suprimir_banners:
			_mostrar_banner_completada(qid)
		_estados_mision[qid] = est
	_refrescar_marcadores_mision()


## Fase 9.2 — banner prominente: "¡Misión completada: <nombre>!
## Vuelve con <NPC>" (el NPC de origen, donde se entrega).
func _mostrar_banner_completada(qid: String) -> void:
	var datos: Dictionary = QuestDB.obtener(qid)
	var npc_id: String = str(datos.get("npc_origen", ""))
	var npc_nombre: String = npc_id
	if NpcDB.existe(npc_id):
		npc_nombre = str(NpcDB.obtener(npc_id).get("nombre", npc_id))
	_panel_misiones.toast_completada(str(datos.get("nombre", qid)), npc_nombre)


## Fase 9.1/9.2 — marcadores de misión sobre los NPCs: "!" dorado si hay
## misión disponible para aceptar (pedido de Juan Diego), "?" dorado si
## hay entrega pendiente. La "?" manda sobre el "!" (fase 9.2). Al
## aceptar/entregar, `QuestLog.cambiada` refresca: el marcador se apaga o
## cambia según lo que quede.
func _refrescar_marcadores_mision() -> void:
	for n in _lista_npcs:
		var npc: NPC = n as NPC
		if npc == null:
			continue
		npc.fijar_marcador(_tipo_marcador_para(npc.npc_id))


## ¿Qué marcador toca para este NPC? Se miran los estados del QuestLog:
## hay entrega pendiente ("lista") y/o misión disponible.
func _tipo_marcador_para(npc_id: String) -> int:
	if _misiones == null:
		return NPC.TipoMarcador.NINGUNO
	var entrega: bool = false
	var disponible: bool = false
	for qid in QuestDB.ids():
		var q: Dictionary = QuestDB.obtener(qid)
		if str(q.get("npc_origen", "")) != npc_id:
			continue
		var est: String = _misiones.estado(qid)
		if est == "lista":
			entrega = true
		elif est == "disponible":
			disponible = true
	return _prioridad_marcador(entrega, disponible)


## Fase 9.2 — regla de prioridad, pura y testeable: la "?" de entrega
## pendiente manda sobre el "!" de misión disponible.
static func _prioridad_marcador(entrega: bool, disponible: bool) -> int:
	if entrega:
		return NPC.TipoMarcador.ENTREGAR
	if disponible:
		return NPC.TipoMarcador.DISPONIBLE
	return NPC.TipoMarcador.NINGUNO


## Enemigos que cuelgan de esta demo. El grupo "enemigos" es global del
## árbol: si hubiera otra escena con enemigos en el mismo árbol (tests
## con dos demos instanciadas), no son los nuestros. El spawner también
## emparenta los reaparecidos aquí, así que el alcance sigue siendo este.
func _mis_enemigos() -> Array:
	var res: Array = []
	var pila: Array = [self]
	while not pila.is_empty():
		var actual: Node = pila.pop_back()
		for h in actual.get_children():
			if h is Enemy:
				res.append(h)
			pila.append(h)
	return res


## Fase 9: factory que el SpawnerMobs usa para reinstanciar enemigos.
## Fase 20: delega en el PoolMobs (escena precargada + reciclaje por
## arquetipo). Solo crea y configura; las señales de la demo se conectan en
## _al_reaparecer_enemigo (con guarda `is_connected`: el nodo puede ser
## reutilizado y traerlas ya conectadas de su vida anterior).
func _crear_enemigo(arquetipo_id: String, posicion: Vector3) -> Enemy:
	if _pool == null:
		push_warning("[Fase9] sin pool: no se puede crear '%s'" % arquetipo_id)
		return null
	var e: Enemy = _pool.obtener(arquetipo_id, posicion)
	if e == null:
		return null
	if _arquetipos.get(arquetipo_id, {}).is_empty():
		push_warning("[Fase9] arquetipo desconocido en respawn: '%s'" % arquetipo_id)
	return e


## Fase 9: el spawner reapareció un enemigo. Se conecta lo de la demo
## (botín, muerte) y el reaparecido reemplaza al cadáver en la lista del
## guardado. El cadáver viejo se libera: el save guarda los enemigos vivos
## como siempre y el timer de respawn (runtime) no se persiste.
func _al_reaparecer_enemigo(nuevo: Enemy) -> void:
	if nuevo == null:
		return
	# Fase 20: el reaparecido puede venir del pool con las señales ya
	# conectadas de su vida anterior (conectar dos veces duplicaría
	# pickups y muertes). Guarda con el mismo patrón del streaming.
	if not nuevo.botin_generado.is_connected(_al_botin_generado):
		nuevo.botin_generado.connect(_al_botin_generado)
	if not nuevo.murio.is_connected(_al_morir_enemigo.bind(nuevo)):
		nuevo.murio.connect(_al_morir_enemigo.bind(nuevo))
	# Fase 19.1: el cadáver a liberar es el muerto más cercano al punto de
	# reaparición (mismo criterio que StreamingMobs._al_reaparecido). Antes
	# se usaba _ultimo_muerto (una sola ranura): con 2+ muertes antes de un
	# respawn se liberaba el cadáver equivocado y el streaming se quedaba
	# con una referencia liberada ("Trying to cast a freed object" en cada
	# tick de actualizar, que abortaba el ciclo a la mitad).
	var idx: int = _indice_cadaver_cercano(nuevo.global_position)
	if idx >= 0:
		var crudo: Variant = _lista_enemigos[idx]
		_lista_enemigos[idx] = nuevo
		if is_instance_valid(crudo):
			var viejo: Enemy = crudo as Enemy
			if viejo != null and viejo != nuevo:
				# Fase 20: el cadáver se recicla en vez de liberarse.
				if _pool != null:
					_pool.devolver(viejo)
				else:
					viejo.queue_free()
	else:
		_lista_enemigos.append(nuevo)
	print("[Fase9] %s reapareció" % nuevo.nombre_mostrado)


## Índice en _lista_enemigos del cadáver (muerto, aún válido) más cercano a
## `pos`, dentro del margen de reaparición (8 m, igual que el streaming);
## -1 si no hay ninguno. Valida antes de castear: la lista puede contener
## referencias liberadas.
func _indice_cadaver_cercano(pos: Vector3) -> int:
	var mejor: int = -1
	var mejor_d: float = 8.0
	for i in _lista_enemigos.size():
		var crudo: Variant = _lista_enemigos[i]
		if not is_instance_valid(crudo):
			continue
		var c: Enemy = crudo as Enemy
		if c == null or c.esta_vivo():
			continue
		var dx: float = c.global_position.x - pos.x
		var dz: float = c.global_position.z - pos.z
		var d: float = sqrt(dx * dx + dz * dz)
		if d <= mejor_d:
			mejor_d = d
			mejor = i
	return mejor


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
		push_error("[Fase9] no se pudo leer " + ENEMIES_JSON)
		return
	var crudo: Variant = JSON.parse_string(texto)
	if crudo is Dictionary:
		_arquetipos = (crudo as Dictionary).get("arquetipos", {})
	else:
		push_error("[Fase9] JSON inválido en " + ENEMIES_JSON)


## Instancia los NPCs de NpcDB (grupo "npcs", no combatibles). Retorna la
## lista para el guardado.
func _crear_npcs() -> Array:
	var escena: PackedScene = load(NPC_ESCENA) as PackedScene
	if escena == null:
		push_warning("[Fase9] no se pudo cargar " + NPC_ESCENA)
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
		print("[Fase9] NPC: %s (%s)" % [npc.nombre_mostrado, npc.npc_id])
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
	# Fase 20: SFX de recogida (moneda para oro, blip para items).
	AudioJuego.al_recoger(str(drop.get("tipo", "")))
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
	# Fase 37: feedback de la recompensa (el loop Earn del RPG debe VERSE:
	# sin esto 15 kills a nivel alto se sienten como "no subo").
	if _fuente != null and _fuente == _jugador and _panel_misiones != null:
		_panel_misiones.toast("+%d XP" % e.xp_recompensa)
	# Fase 19.1: el cadáver se reemplaza en la lista cuando el spawner lo
	# reaparezca (se busca por cercanía en _al_reaparecer_enemigo).
	# Fase 8: las muertes avanzan los objetivos "matar".
	_misiones.registrar_muerte(e.arquetipo_id)
