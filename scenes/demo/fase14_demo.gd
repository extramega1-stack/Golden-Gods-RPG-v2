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


func _ready() -> void:
	# La API de CiudadLuna exige `terreno` asignado ANTES del add_child.
	# Se crea primero para que el mundo exista cuando super._ready() pegue
	# al terreno, arranque el streaming y levante la orientación.
	_ciudad = CiudadLuna.new()
	_ciudad.name = "CiudadLuna"
	_ciudad.terreno = $Terreno as Terreno
	_ciudad.ciclo = $CicloDia as CicloDia
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
		add_child(c)
		_ciudades_sec.append(c)
	super._ready()
	# Jugador y NPCs a sus puntos data-driven de Moon Town.
	_colocar_en_ciudad()
	# Fase 16: viaje rápido — "Viajar" en el diálogo del portero abre el
	# PanelViaje con la ciudad del portero como origen.
	_viaje = ViajeRapido.new()
	_viaje.cargar_datos()
	_dialogo.viaje_solicitado.connect(_al_viaje_dialogo)
	_panel_viaje.viaje_solicitado.connect(_al_destino_viaje)


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
