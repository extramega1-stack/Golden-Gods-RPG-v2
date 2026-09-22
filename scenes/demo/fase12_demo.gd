extends "res://scenes/demo/fase11_demo.gd"
## Demo de la fase 12: mundo abierto real.
##
## Hereda TODO de fase11_demo (título → creación → juego, NPCs, tiendas,
## misiones, respawn) y añade el mundo:
## - `Terreno` (heightmap del legado 1:1, 36.864 u, chunks con LOD): el
##   jugador, los NPCs y los creeps caminan pegados a él (`Entity.terreno`).
## - Spawns distribuidos desde `data/spawns.json` (1121 creeps del legado
##   mapeados a goblin/lobo/ogro por nivel): viven como DATOS en
##   `StreamingMobs` (fase 12.1) y solo se instancian como nodos los
##   cercanos al jugador (radio data-driven con histéresis); el respawn de
##   la fase 9 sigue funcionando y no reaparece mobs lejos (puerta).
## - `CicloDia` (día/noche data-driven) + antorchas en la aldea.
## - `RegionDB` + `VigiaRegion` + `BannerRegion`: al cruzar a una región
##   nueva aparece el banner "Has descubierto: X".
## Es scaffolding de demo, no un sistema del juego.

const SPAWNS_JSON: String = "res://data/spawns.json"

var _terreno: Terreno = null
var _ciclo: CicloDia = null
var _region_db: RegionDB = null
## Fase 12.1: streaming de mobs (los 1121 spawns como datos).
var _streaming: StreamingMobs = null


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
	# Fase 12.1: los creeps del mundo viven como datos en el streaming;
	# solo se instancian como nodos los cercanos al jugador.
	_iniciar_streaming()
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


## Fase 12.1: lee data/spawns.json y lo carga como REGISTROS en el
## streaming (no se instancia ningún nodo aquí). El streaming instancia
## solo los cercanos al jugador, con histéresis; el respawn de la fase 9
## sigue programando sus timers pero la puerta veta reaparecer lejos.
func _iniciar_streaming() -> void:
	var texto: String = FileAccess.get_file_as_string(SPAWNS_JSON)
	if texto.is_empty():
		push_warning("[Fase12] no se pudo leer " + SPAWNS_JSON)
		return
	var crudo: Variant = JSON.parse_string(texto)
	if not (crudo is Array):
		push_warning("[Fase12] JSON inválido en " + SPAWNS_JSON)
		return
	var registros: Array = []
	for s in (crudo as Array):
		if not (s is Dictionary):
			continue
		var sd: Dictionary = s
		var arq_id: String = str(sd.get("arquetipo", ""))
		if not _arquetipos.has(arq_id):
			push_warning("[Fase12] arquetipo desconocido en spawns: '%s'" % arq_id)
			continue
		registros.append({
			"arquetipo": arq_id,
			"origen": Vector3(float(sd.get("x", 0.0)), 0.0, float(sd.get("z", 0.0))),
		})
	_streaming = StreamingMobs.new()
	_streaming.name = "StreamingMobs"
	_streaming.configurar(registros)
	# La factory es la de la fase 9 (crea + configura con el arquetipo).
	_streaming.fijar_factory(_crear_enemigo)
	_streaming.fijar_jugador(_jugador)
	_streaming.fijar_spawner(_spawner)
	_streaming.mob_instanciado.connect(_al_mob_instanciado)
	_streaming.mob_liberado.connect(_al_mob_liberado)
	_spawner.puerta_reaparicion = _puerta_respawn
	# Los reaparecidos también caminan pegados al terreno (la factory de
	# la fase 9 no lo pone; antes del streaming tampoco lo tenían).
	_spawner.reaparecido.connect(_al_reaparecer_terreno)
	add_child(_streaming)
	_streaming.actualizar()
	print("[Fase12] streaming: %d registros, %d instanciados cerca"
			% [_streaming.conteo_registros(), _streaming.conteo_instanciados()])


## Fase 12.1: el streaming instanció un mob cercano: la misma configuración,
## señales y vigilancia que la fase 12 original por nodo.
func _al_mob_instanciado(e: Enemy) -> void:
	if e == null:
		return
	e.botin_generado.connect(_al_botin_generado)
	e.murio.connect(_al_morir_enemigo.bind(e))
	e.terreno = _terreno
	e._pegar_al_terreno()
	_lista_enemigos.append(e)
	_spawner.vigilar(e)


## Fase 12.1: el jugador se alejó y el nodo se libera. El registro, su
## posición de origen y su respawn pendiente sobreviven en datos; el save
## guarda la lista viva como siempre (los liberados no están en ella,
## igual que los muertos pendientes de respawn).
func _al_mob_liberado(e: Enemy) -> void:
	_lista_enemigos.erase(e)


## Fase 12.1: puerta del respawn — no reaparecer mobs lejos del jugador
## (el pendiente se reintenta al acercarse).
func _puerta_respawn(_arquetipo: String, origen: Vector3) -> bool:
	if _jugador == null or not is_instance_valid(_jugador):
		return true
	var ra: float = _streaming.radio_alta() if _streaming != null else 600.0
	var d: Vector3 = origen - _jugador.global_position
	d.y = 0.0
	return d.length() <= ra


## Fase 12.1: el reaparecido del spawner también va pegado al terreno.
func _al_reaparecer_terreno(nuevo: Enemy) -> void:
	if nuevo == null or not is_instance_valid(nuevo) or _terreno == null:
		return
	nuevo.terreno = _terreno
	nuevo._pegar_al_terreno()


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
