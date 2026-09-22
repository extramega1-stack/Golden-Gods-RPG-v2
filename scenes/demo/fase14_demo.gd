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
const _NPC_CIUDAD_SEC: Dictionary = {
	"yasmina": 0, "durnan": 1, "sella": 2, "elthar": 3,
	"vex": 4, "karg": 5, "maris": 6, "aurelio": 7,
}

## TEMPORAL — Fase 14.1: portales de inspección para Juan Diego.
## QUITAR cuando lo pida: borrar data/portales_temp.json,
## scripts/mundo/portal_temporal.gd y este bloque.
var _portales_temp: Array = []


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
	_instalar_portales_temp()  # TEMPORAL 14.1


## TEMPORAL 14.1 — E cerca de un portal: teletransporta (salvo que haya un
## NPC seleccionado: E sigue siendo para hablar). El Player no consume el
## evento, así que este _unhandled_input también lo ve.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interactuar"):
		_usar_portal_temp_cercano()


## TEMPORAL 14.1 — instala los portales de inspección. Devuelve cuántos
## puso (0 si el JSON falta o está roto: no revienta la demo).
func _instalar_portales_temp(ruta: String = PortalTemporal.RUTA_DESTINOS) -> int:
	var destinos: Array = PortalTemporal.cargar_destinos(ruta)
	if destinos.is_empty():
		return 0
	var luna: Dictionary = {}
	var otros: Array = []
	for d in destinos:
		var dd: Dictionary = d
		if str(dd.get("id", "")) == "moon_town":
			luna = dd
		else:
			otros.append(dd)
	# Círculo en la plaza de Moon Town (r=55: fuera del alcance accidental
	# del punto de aparición del jugador).
	var n: int = 0
	var total: int = maxi(1, otros.size())
	for i in range(otros.size()):
		var dd2: Dictionary = otros[i]
		var ang: float = TAU * float(i) / float(total)
		_crear_portal_temp(dd2, 55.0 * sin(ang), 55.0 * cos(ang))
		n += 1
	# Un portal de vuelta a Moon Town en cada destino lejano.
	if not luna.is_empty():
		for d in otros:
			var dd3: Dictionary = d
			_crear_portal_temp(luna, float(dd3.get("x", 0.0)) + 12.0,
				float(dd3.get("z", 0.0)))
			n += 1
	print("[Fase14.1 TEMPORAL] %d portales instalados" % n)
	return n


## TEMPORAL 14.1 — crea un portal en (x, z) sobre el terreno.
func _crear_portal_temp(dest: Dictionary, x: float, z: float) -> void:
	var portal := PortalTemporal.new()
	portal.name = "PortalTemp_%s" % str(dest.get("id", "?"))
	portal.configurar(dest)
	var y: float = 40.0
	if _terreno != null:
		y = _terreno.altura_en(x, z)
	portal.position = Vector3(x, y, z)
	add_child(portal)
	_portales_temp.append(portal)


## TEMPORAL 14.1 — si hay un portal a ≤ RADIO_USO, teletransporta.
## Devuelve true si se usó un portal.
func _usar_portal_temp_cercano() -> bool:
	if _jugador == null or not _jugador.esta_vivo():
		return false
	if _jugador.seleccion is NPC:
		return false
	var portal: PortalTemporal = PortalTemporal.portal_cercano(
		_portales_temp, _jugador.global_position)
	if portal == null:
		return false
	_teletransportar_portal(portal)
	return true


## TEMPORAL 14.1 — mueve al jugador al destino del portal (sobre el
## terreno), limpia órdenes pendientes y pega la cámara (como el F10).
func _teletransportar_portal(portal: PortalTemporal) -> void:
	var punto: Vector3 = portal.punto_destino(_terreno)
	_jugador.deseleccionar()
	_jugador.global_position = punto
	_jugador._pegar_al_terreno()
	if _rig != null:
		_rig.global_position = _jugador.global_position
	print("[Fase14.1 TEMPORAL] teletransporte a %s" % str(portal.destino.get("nombre", "?")))


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
