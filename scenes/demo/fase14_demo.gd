extends "res://scenes/demo/fase12_demo.gd"
## Demo de la fase 14: rework 2026 del mapa — ciudad principal "Moon Town".
##
## Hereda TODO de fase12_demo (mundo abierto, streaming de mobs, regiones +
## banner, ciclo día/noche, minimapa + brújula, flujo título → creación →
## juego con Continuar y F9/F10) y añade la ciudad:
## - `CiudadLuna` se crea con el terreno asignado ANTES del add_child
##   (contrato de su API); su `_ready` construye los 18 edificios y emite
##   `ciudad_lista`. El ciclo día/noche también se asigna antes (modula las
##   antorchas de la ciudad).
## - El jugador aparece en `punto_aparicion_jugador()` (plaza, sobre el
##   terreno) mirando con `yaw_aparicion()`.
## - Los NPCs Ilya/Bram/Sira se recolocan en `npc_spawn(id)` (data-driven).
## Es scaffolding de demo, no un sistema del juego.

## La ciudad construida (data/ciudad_luna.json: 18 edificios procedurales).
var _ciudad: CiudadLuna = null


func _ready() -> void:
	# La API de CiudadLuna exige `terreno` asignado ANTES del add_child.
	# Se crea primero para que el mundo exista cuando super._ready() pegue
	# al terreno, arranque el streaming y levante la orientación.
	_ciudad = CiudadLuna.new()
	_ciudad.name = "CiudadLuna"
	_ciudad.terreno = $Terreno as Terreno
	_ciudad.ciclo = $CicloDia as CicloDia
	add_child(_ciudad)
	super._ready()
	# Jugador y NPCs a sus puntos data-driven de Moon Town.
	_colocar_en_ciudad()


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
		npc.position = _ciudad.npc_spawn(npc.npc_id)
		npc._pegar_al_terreno()
	# La cámara persigue con damping: colocarla de golpe en el spawn para
	# que no "deslice" desde la posición vieja (mismo truco que el F10).
	if _rig != null:
		_rig.global_position = _jugador.global_position
	print("[Fase14] Moon Town: jugador en %s, %d NPCs recolocados"
		% [_ciudad.punto_aparicion_jugador(), _lista_npcs.size()])
