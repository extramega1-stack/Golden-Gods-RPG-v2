extends "res://scenes/demo/fase11_demo.gd"
## Demo de la fase 12: mundo abierto real.
##
## Hereda TODO de fase11_demo (título → creación → juego, NPCs, tiendas,
## misiones, respawn) y añade el mundo:
## - `Terreno` (heightmap del legado 1:1, 36.864 u, chunks con LOD): el
##   jugador, los NPCs y los creeps caminan pegados a él (`Entity.terreno`).
## - Spawns distribuidos desde `data/spawns.json` (1121 creeps del legado
##   mapeados a goblin/lobo/ogro por nivel): se instancian con la factory
##   existente y entran al SpawnerMobs como siempre (respawn intacto).
## - `CicloDia` (día/noche data-driven) + antorchas en la aldea.
## - `RegionDB` + `VigiaRegion` + `BannerRegion`: al cruzar a una región
##   nueva aparece el banner "Has descubierto: X".
## Es scaffolding de demo, no un sistema del juego.

const SPAWNS_JSON: String = "res://data/spawns.json"

var _terreno: Terreno = null
var _ciclo: CicloDia = null
var _region_db: RegionDB = null


func _ready() -> void:
	super._ready()
	_terreno = $Terreno as Terreno
	_ciclo = $CicloDia as CicloDia
	# Pegar al terreno: héroe, NPCs y pickups cercanos a la aldea.
	_jugador.terreno = _terreno
	_jugador._pegar_al_terreno()
	for n in _lista_npcs:
		var npc: NPC = n as NPC
		if npc == null:
			continue
		npc.terreno = _terreno
		npc._pegar_al_terreno()
	# Los creeps del mundo: instanciar, configurar, conectar y vigilar.
	_instanciar_spawns()
	# Regiones: el vigía observa al jugador y el banner anuncia descubrimientos.
	_region_db = RegionDB.new()
	if not _region_db.cargar():
		push_warning("[Fase12] no se pudo cargar data/regiones.json")
	var vigia: VigiaRegion = $VigiaRegion as VigiaRegion
	vigia.region_db = _region_db
	vigia.jugador = _jugador
	vigia.descubierta.connect(_al_descubrir_region)
	# Antorchas de la aldea: luz cálida que crece de noche.
	for a in _mis_antorchas():
		var ant: Antorcha = a as Antorcha
		if ant == null:
			continue
		ant.ciclo = _ciclo
		if _terreno != null:
			var p: Vector3 = ant.position
			p.y = _terreno.altura_en(p.x, p.z)
			ant.position = p


## Lee data/spawns.json e instancia cada creep con la factory de la fase 9
## (misma configuración, mismas señales, mismo respawn).
func _instanciar_spawns() -> void:
	var texto: String = FileAccess.get_file_as_string(SPAWNS_JSON)
	if texto.is_empty():
		push_warning("[Fase12] no se pudo leer " + SPAWNS_JSON)
		return
	var crudo: Variant = JSON.parse_string(texto)
	if not (crudo is Array):
		push_warning("[Fase12] JSON inválido en " + SPAWNS_JSON)
		return
	var t0: int = Time.get_ticks_msec()
	var n: int = 0
	for s in (crudo as Array):
		if not (s is Dictionary):
			continue
		var sd: Dictionary = s
		var arq_id: String = str(sd.get("arquetipo", ""))
		if not _arquetipos.has(arq_id):
			push_warning("[Fase12] arquetipo desconocido en spawns: '%s'" % arq_id)
			continue
		var pos := Vector3(float(sd.get("x", 0.0)), 0.0, float(sd.get("z", 0.0)))
		var e: Enemy = _crear_enemigo(arq_id, pos)
		if e == null:
			continue
		e.configurar(_arquetipos[arq_id])
		e.botin_generado.connect(_al_botin_generado)
		e.murio.connect(_al_morir_enemigo.bind(e))
		e.terreno = _terreno
		e._pegar_al_terreno()
		_lista_enemigos.append(e)
		_spawner.vigilar(e)
		n += 1
	print("[Fase12] %d creeps instanciados en %d ms" % [n, Time.get_ticks_msec() - t0])


## Antorchas colocadas en la escena (grupo propio para no mezclar con NPCs).
func _mis_antorchas() -> Array:
	var res: Array = []
	var pila: Array = [self]
	while not pila.is_empty():
		var actual: Node = pila.pop_back()
		for h in actual.get_children():
			if h is Antorcha:
				res.append(h)
			pila.append(h)
	return res


## El vigía detectó una región nueva: banner discreto con su nombre y banda.
func _al_descubrir_region(region: Dictionary) -> void:
	var banner: BannerRegion = $CapaBanner/BannerRegion as BannerRegion
	if banner == null:
		return
	var nombre: String = str(region.get("nombre", "???"))
	var sub: String = "Nivel recomendado %d–%d" % [
		int(region.get("nivel_min", 1)), int(region.get("nivel_max", 99))]
	banner.mostrar(nombre, sub)
