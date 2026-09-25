extends "res://scenes/demo/fase12_demo.gd"
## Demo de la fase 14: rework 2026 del mapa — ciudad principal "Moon Town".
## Fase 15: ademas construye las 8 ciudades secundarias (desierto, volcan,
## norte, mistica, sombra, furia, tormenta, dorada) con el CiudadLuna
## generalizado (`centro` regional, `luces_reales = false`).
##
## Hereda TODO de fase12_demo (mundo abierto, streaming de mobs, regiones +
## banner, ciclo día/noche, minimapa + brújula, flujo título → creación →
## juego con Continuar y F9/F10) y añade las ciudades:
## - `CiudadLuna` se crea con el terreno asignado ANTES del add_child
##   (contrato de su API); su `_ready` construye los 18 edificios y emite
##   `ciudad_lista`. El ciclo día/noche también se asigna antes (modula las
##   antorchas de la ciudad). Las 8 secundarias (16 edificios c/u) usan
##   FalsaAntorcha en vez de OmniLight3D.
## - El jugador aparece en `punto_aparicion_jugador()` (plaza, sobre el
##   terreno) mirando con `yaw_aparicion()`.
## - Los NPCs Ilya/Bram/Sira se recolocan en `npc_spawn(id)` (data-driven);
##   los 8 ambientales van a su ciudad secundaria.
## Es scaffolding de demo, no un sistema del juego.

## La ciudad construida (data/ciudad_luna.json: 18 edificios procedurales).
var _ciudad: CiudadLuna = null

## Fase 15: las 8 ciudades secundarias (mismo CiudadLuna generalizado,
## con `luces_reales = false` y su `centro` regional). Se construyen en
## _ready() antes de super._ready(), igual que Moon Town.
var _ciudades_sec: Array = []

const _SECUNDARIAS: Array = [
	["CiudadDesert", "res://data/ciudad_desert.json", Vector2(9966, 0)],
	["CiudadFire", "res://data/ciudad_fire.json", Vector2(-9966, 0)],
	["CiudadNorth", "res://data/ciudad_north.json", Vector2(0, -5358)],
	["CiudadMystic", "res://data/ciudad_mystic.json", Vector2(0, 9966)],
	["CiudadShadow", "res://data/ciudad_shadow.json", Vector2(9966, -9966)],
	["CiudadRage", "res://data/ciudad_rage.json", Vector2(-9966, -9966)],
	["CiudadFury", "res://data/ciudad_fury.json", Vector2(-9966, 9966)],
	["CiudadGolden", "res://data/ciudad_golden.json", Vector2(9966, 9966)],
]

## Fase 15: a que ciudad secundaria pertenece cada NPC ambiental
## (indice en _ciudades_sec / _SECUNDARIAS). Ilya/Bram/Sira van a Moon Town.
## Fase 16: los 9 porteros de viaje rápido van a su ciudad (el de Moon Town
## cae a Moon Town por defecto, igual que Ilya/Bram/Sira).
const _NPC_CIUDAD_SEC: Dictionary = {
	"yasmina": 0, "durnan": 1, "sella": 2, "elthar": 3,
	"vex": 4, "karg": 5, "maris": 6, "aurelio": 7,
	"portero_desert": 0, "portero_fire": 1, "portero_north": 2,
	"portero_mystic": 3, "portero_shadow": 4, "portero_rage": 5,
	"portero_fury": 6, "portero_golden": 7,
}

## Fase 16: lógica del viaje rápido (sin UI; la UI solo lee).
var _viaje: ViajeRapido = null
@onready var _panel_viaje: PanelViaje = $PanelViaje
## Fase 41: arena PvE (manager de oleadas; los trofeos viajan en el save).
var _arena: Arena = null
## Punto de retorno al salir de la arena (plaza del Maestro).
var _retorno_arena: Vector3 = Vector3.ZERO
## Fase 45: minería (coloca las vetas de la región y las hace minar con E).
var _mineria: GestorVetas = null
## Fase 46: manual de ayuda (controles y mecánicas), con la tecla `?`.
var _ayuda: PanelAyuda = null
const ESCENA_AYUDA: PackedScene = preload("res://scenes/ui/panel_ayuda.tscn")


func _ready() -> void:
	# La API de CiudadLuna exige `terreno` asignado ANTES del add_child.
	# Se crea primero para que el mundo exista cuando super._ready() pegue
	# al terreno, arranque el streaming y levante la orientación.
	_ciudad = CiudadLuna.new()
	_ciudad.name = "CiudadLuna"
	_ciudad.terreno = $Terreno as Terreno
	_ciudad.ciclo = $CicloDia as CicloDia
	# Fase 20: las 9 ciudades se construyen por partes (pantalla de carga);
	# `npc_spawn`/recolocación esperan a `_al_mundo_listo()`.
	_ciudad.construccion_progresiva = true
	add_child(_ciudad)
	# Fase 15: las 8 ciudades secundarias (mismo contrato de API:
	# terreno/ciclo/centro/cargar_datos ANTES del add_child).
	for spec in _SECUNDARIAS:
		var c := CiudadLuna.new()
		c.name = str(spec[0])
		c.terreno = $Terreno as Terreno
		c.ciclo = $CicloDia as CicloDia
		c.centro = spec[2]
		c.luces_reales = false
		c.cargar_datos(str(spec[1]))
		c.construccion_progresiva = true
		add_child(c)
		_ciudades_sec.append(c)
	super._ready()


## Fase 20: el mundo terminó de construirse por partes. Aquí (y no en
## _ready) van los pasos que necesitan ciudades completas: recolocar al
## jugador/NPCs (`npc_spawn` se llena al final de construir) y el viaje.
func _al_mundo_listo() -> void:
	# Jugador y NPCs a sus puntos data-driven de Moon Town.
	_colocar_en_ciudad()
	# Fase 16: viaje rápido — "Viajar" en el diálogo del portero abre el
	# PanelViaje con la ciudad del portero como origen.
	_viaje = ViajeRapido.new()
	_viaje.cargar_datos()
	_dialogo.viaje_solicitado.connect(_al_viaje_dialogo)
	_panel_viaje.viaje_solicitado.connect(_al_destino_viaje)
	# Fase 41: arena — "Entrenar" con el Maestro teletransporta al campo
	# remoto y arranca las oleadas; los trofeos se guardan con la partida.
	_arena = Arena.new()
	_arena.name = "Arena"
	add_child(_arena)
	_arena.configurar(_cargar_arena_json())
	_arena.fijar_factory(_crear_enemigo_arena)
	_arena.fijar_pool(_pool)
	_arena.fijar_arquetipos(_arquetipos)
	_arena.fijar_jugador(_jugador)
	_arena.oleada_iniciada.connect(_al_arena_oleada)
	_arena.oleada_superada.connect(_al_arena_superada)
	_arena.arena_terminada.connect(_al_arena_terminada)
	_arena.ayuda_oleada.connect(_al_arena_ayuda)
	_dialogo.arena_solicitada.connect(_al_arena_dialogo)
	_guardado.arena = _arena
	# Fase 45: minería — 12 vetas de `data/vetas.json`, instanciadas por
	# región (histéresis 700/900 m). El jugador las mina con el segundo clic o
	# con E; el estado de cada veta (usos + respawn) viaja en el save.
	_mineria = GestorVetas.new()
	_mineria.name = "GestorVetas"
	add_child(_mineria)
	_mineria.configurar_desde_datos()
	_mineria.fijar_terreno($Terreno as Terreno)
	_mineria.fijar_jugador(_jugador)
	_mineria.minado.connect(_al_minado)
	_guardado.mineria = _mineria
	_mineria.actualizar()
	print("[Fase45] minería: %d vetas registradas, %d en el mapa cerca"
			% [_mineria.conteo_registros(), _mineria.conteo_vetas()])
	# Fase 46: el manual de ayuda. Se pone `abrir_al_arrancar = false` porque
	# en la ESCENA va en true (para poder correrla sola con F6 y revisarla).
	_ayuda = ESCENA_AYUDA.instantiate() as PanelAyuda
	_ayuda.abrir_al_arrancar = false
	add_child(_ayuda)
	super._al_mundo_listo()
	# Fase 45.2: con el mundo ya construido, la pantalla de carga fuera y el
	# jugador colocado en su punto, arranca el tutorial (nueva partida). Es el
	# primer momento en que sus avisos se ven de verdad.
	if _tutorial != null:
		_tutorial.empezar()


## Fase 20: el gate añade las 9 ciudades al terreno de la base.
func _construccion_lista() -> bool:
	if not super._construccion_lista():
		return false
	if _ciudad != null and is_instance_valid(_ciudad):
		if not _ciudad.construccion_terminada():
			return false
	for c in _ciudades_sec:
		var ci: CiudadLuna = c as CiudadLuna
		if ci == null or not is_instance_valid(ci):
			continue
		if not ci.construccion_terminada():
			return false
	return true


## Fase 20: 25% terreno + 75% media de las 9 ciudades.
func _fraccion_carga() -> float:
	var ft: float = super._fraccion_carga()
	return clampf(ft * 0.25 + _fraccion_ciudades() * 0.75, 0.0, 1.0)


func _fraccion_ciudades() -> float:
	var suma: float = 0.0
	var n: int = 0
	var todas: Array = [_ciudad] + _ciudades_sec
	for c in todas:
		var ci: CiudadLuna = c as CiudadLuna
		if ci == null or not is_instance_valid(ci):
			continue
		suma += ci.fraccion_construccion()
		n += 1
	if n <= 0:
		return 1.0
	return suma / float(n)


## Fase 45: se	minó un golpe. El aviso flotante de la veta ya lo dice en el
## mundo; aquí solo queda el registro para el playtest.
func _al_minado(veta_id: String, item_id: String, cantidad: int, xp: int) -> void:
	print("[Minería] %s → +%d %s (+%d XP)" % [veta_id, cantidad, item_id, xp])


## Fase 41 — entrada a la arena: guarda el retorno, teletransporta al
## campo remoto y arranca las oleadas.
func _al_arena_dialogo(_npc: NPC) -> void:
	if _arena == null or _jugador == null:
		return
	_retorno_arena = _jugador.global_position
	_teletransportar_arena(_arena.centro_campo())
	_arena.iniciar()
	_panel_misiones.toast("Arena: sobrevive a las 10 oleadas")


## Factory de la arena: como el streaming pero sin vigilancia de respawn
## (la arena cuenta sus muertes y limpia al detener).
func _crear_enemigo_arena(arquetipo_id: String, pos: Vector3) -> Enemy:
	var e: Enemy = _crear_enemigo(arquetipo_id, pos)
	if e == null:
		return null
	if not e.botin_generado.is_connected(_al_botin_generado):
		e.botin_generado.connect(_al_botin_generado)
	if not e.murio.is_connected(_al_morir_enemigo.bind(e)):
		e.murio.connect(_al_morir_enemigo.bind(e))
	e.terreno = _terreno
	e._pegar_al_terreno()
	return e


func _al_arena_oleada(n: int) -> void:
	# Fase 42: dice cuántos enemigos son (antes solo el número y el jugador
	# no sabía si quedaban vivos por los que no hadn't visto).
	_panel_misiones.toast("Oleada %d — %d enemigos" % [n, _arena.vivos() if _arena != null else 0])


func _al_arena_superada(n: int, oro: int, xp: int) -> void:
	var espera: int = int(round(_arena._descanso_seg)) if _arena != null else 0
	_panel_misiones.toast("Oleada %d superada! +%d oro, +%d XP — siguiente en %ds" % [
		n, oro, xp, espera])


## Fase 42: los mobs que quedaban se acercaron (la oleada no puede atascarse).
func _al_arena_ayuda(n: int) -> void:
	_panel_misiones.toast("Te acerco a los %d enemigos restantes" % n)


## Victoria → de vuelta con el Maestro. Derrota: el flujo de muerte sigue
## (el respawn existente devuelve al héroe; la arena ya registró el trofeo).
func _al_arena_terminada(victoria: bool, oleada: int) -> void:
	if victoria:
		_panel_misiones.toast("¡Campeón de la arena! Habla con Renn")
		_teletransportar_arena(_retorno_arena)
	else:
		_panel_misiones.toast("Caíste en la oleada %d — habla con Renn para repetir" % oleada)


## Teletransporte genérico (como el del viaje: sin damping de cámara).
func _teletransportar_arena(dest: Vector3) -> void:
	if _jugador == null:
		return
	var p := Vector3(dest.x, dest.y, dest.z)
	if _terreno != null:
		p.y = _terreno.altura_en(p.x, p.z)
	_jugador.deseleccionar()
	_jugador.global_position = p
	_jugador._pegar_al_terreno()
	if _rig != null:
		_rig.global_position = _jugador.global_position


func _cargar_arena_json() -> Dictionary:
	var texto: String = FileAccess.get_file_as_string("res://data/arena.json")
	if texto.is_empty():
		push_warning("[Fase14] no se pudo leer res://data/arena.json")
		return {}
	var crudo: Variant = JSON.parse_string(texto)
	if crudo is Dictionary:
		return crudo
	push_warning("[Fase14] JSON inválido en res://data/arena.json")
	return {}


## Cargar dentro del campo con la arena apagada te devolvía al vacío:
## al cargar se vuelve a la plaza de Moon Town (la arena se detiene).
func _cargar_partida_guardada() -> bool:
	var cargo: bool = super._cargar_partida_guardada()
	if cargo and _arena != null and _jugador != null:
		_arena.detener()
		var c: Vector3 = _arena.centro_campo()
		var d: Vector2 = Vector2(_jugador.global_position.x - c.x,
			_jugador.global_position.z - c.z)
		if d.length() < 200.0 and _ciudad != null:
			_jugador.global_position = _ciudad.punto_aparicion_jugador()
			_jugador._pegar_al_terreno()
			if _rig != null:
				_rig.global_position = _jugador.global_position
	return cargo


## Fase 16 — "Viajar" en el diálogo de un portero: abre el PanelViaje con
## el origen = ciudad del portero (campo `viaje_id` de data/npcs.json).
func _al_viaje_dialogo(npc: NPC) -> void:
	var origen: String = ViajeRapido.viaje_id_de_npc(npc.npc_id)
	if origen == "" or _panel_viaje == null:
		return
	_panel_viaje.mostrar(origen, _jugador)


## Fase 16 — destino elegido en el PanelViaje: valida, cobra y teletransporta.
func _al_destino_viaje(destino_id: String) -> void:
	if _viaje == null or _jugador == null or _panel_viaje == null:
		return
	var origen: String = _panel_viaje.origen_actual()
	var res: Dictionary = _viaje.viajar(_jugador, origen, destino_id)
	if not bool(res.get("ok", false)):
		# Pudo cambiar algo entre abrir el panel y pulsar (p. ej. entró en
		# combate): se informa sin cerrar.
		_panel_viaje.informar(ViajeRapido.texto_motivo(res))
		return
	_panel_viaje.cerrar_panel()
	var plaza: Vector2 = res.get("plaza", Vector2.ZERO)
	_teletransportar_viaje(plaza, str(res.get("destino", "")), int(res.get("costo", 0)))


## Fase 16 — teletransporte del viaje rápido: deselecciona, fija la
## posición en la plaza sobre el terreno y pega la cámara (como el F10).
func _teletransportar_viaje(plaza: Vector2, destino_id: String, costo: int) -> void:
	if _jugador == null:
		return
	var y: float = 0.0
	if _terreno != null:
		y = _terreno.altura_en(plaza.x, plaza.y)
	_jugador.deseleccionar()
	_jugador.global_position = Vector3(plaza.x, y, plaza.y)
	_jugador._pegar_al_terreno()
	if _rig != null:
		_rig.global_position = _jugador.global_position
	var nombre: String = _viaje.nombre_ciudad(destino_id) if _viaje != null else destino_id
	if _panel_misiones != null:
		_panel_misiones.toast("Viaje a %s (-%d oro)" % [nombre, costo])
	print("[Fase16] viaje rápido a %s (-%d oro)" % [nombre, costo])


## Recoloca al jugador y a los NPCs en los puntos de la ciudad.
## (Los NPCs nacen en fase9 con las posiciones viejas de NpcDB; aquí se
## mueven a los puntos data-driven de `data/ciudad_luna.json`.)
func _colocar_en_ciudad() -> void:
	if _ciudad == null or _jugador == null:
		return
	# Fase 20: el jugador como referencia del culling de antorchas (las
	# ~40 OmniLight3D de Moon Town solo alumbran cerca).
	_ciudad.fijar_jugador(_jugador)
	for c in _ciudades_sec:
		var ci: CiudadLuna = c as CiudadLuna
		if ci != null and is_instance_valid(ci):
			ci.fijar_jugador(_jugador)
	_jugador.position = _ciudad.punto_aparicion_jugador()
	_jugador.rotation.y = _ciudad.yaw_aparicion()
	_jugador._pegar_al_terreno()
	for n in _lista_npcs:
		var npc: NPC = n as NPC
		if npc == null:
			continue
		# Fase 15: los ambientales van a su ciudad secundaria; el resto a Moon.
		if _NPC_CIUDAD_SEC.has(npc.npc_id) and int(_NPC_CIUDAD_SEC[npc.npc_id]) < _ciudades_sec.size():
			var c2: CiudadLuna = _ciudades_sec[int(_NPC_CIUDAD_SEC[npc.npc_id])] as CiudadLuna
			npc.position = c2.npc_spawn(npc.npc_id)
		else:
			npc.position = _ciudad.npc_spawn(npc.npc_id)
		npc._pegar_al_terreno()
	# La cámara persigue con damping: colocarla de golpe en el spawn para
	# que no "deslice" desde la posición vieja (mismo truco que el F10).
	if _rig != null:
		_rig.global_position = _jugador.global_position
	print("[Fase14] Moon Town: jugador en %s, %d NPCs recolocados"
		% [_ciudad.punto_aparicion_jugador(), _lista_npcs.size()])
