extends SceneTree
## Tests headless de la Fase 31 (equipo paperdoll 12 slots estilo FlyFF).
##
## Cubre:
## (a) es_equipable por "slot" (no por tipo): las 10 piezas nuevas + las
##     8 viejas equipan; consumibles/materiales no;
## (b) resolver_slot: pendiente/anillo van al primer libre del par; par
##     lleno → reemplaza el primero (determinista); slot directo intacto;
## (c) equipar/desequipar: aplica y quita mods, mueve stock al inventario;
## (d) to_dict/from_dict genérico en los 12 slots; la joyería guardada en
##     pendiente_1/anillo_2 se acepta aunque su slot sea genérico;
## (e) save/load: los 12 slots viajan en disco y los mods se reaplican.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase31_equipo.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const EQ: GDScript = preload("res://scripts/inventory/equipment.gd")
const INV: GDScript = preload("res://scripts/inventory/inventory.gd")
const SV: GDScript = preload("res://scripts/save/save_system.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 31 — equipo paperdoll 12 slots")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	ItemDB.cargar()
	_test_equipable()
	_test_resolver()
	_test_equipar()
	_test_dict()
	_test_save()
	print("[TEST] fase31_equipo: %d ok, %d fallos" % [_ok, _fallos])
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	for n in _basura:
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _kit() -> Array:
	var st: StatBlock = SB.new()
	var inv: Inventario = INV.new()
	var eq: Equipo = EQ.new()
	return [st, inv, eq]


## (a) Criterio de equipable = campo "slot" válido.
func _test_equipable() -> void:
	for iid in ["espada_corta", "armadura_cuero", "escudo_madera", "casco_cuero",
			"guantes_cuero", "botas_cuero", "pendiente_luna", "pendiente_sol",
			"collar_cobre", "anillo_poder", "anillo_sabio", "amuleto_guardian"]:
		_chk(Equipo.es_equipable(iid), "a: equipable " + iid)
	for iid in ["pocion_vida", "colmillo", "fragmento_duna"]:
		_chk(not Equipo.es_equipable(iid), "a: no equipable " + iid)
	_chk(not Equipo.es_equipable("no_existe"), "a: id desconocido no equipable")


## (b) Resolución de slots de joyería.
func _test_resolver() -> void:
	var anillo: Dictionary = ItemDB.obtener("anillo_poder")
	_chk(Equipo.resolver_slot(anillo, {}) == "anillo_1",
		"b: par vacío → anillo_1")
	_chk(Equipo.resolver_slot(anillo, {"anillo_1": "anillo_poder"}) == "anillo_2",
		"b: primer libre → anillo_2")
	_chk(Equipo.resolver_slot(anillo,
			{"anillo_1": "anillo_poder", "anillo_2": "anillo_sabio"}) == "anillo_1",
		"b: par lleno → reemplaza anillo_1")
	var pend: Dictionary = ItemDB.obtener("pendiente_luna")
	_chk(Equipo.resolver_slot(pend, {"pendiente_1": "x"}) == "pendiente_2",
		"b: pendiente libre → pendiente_2")
	var arma: Dictionary = ItemDB.obtener("espada_corta")
	_chk(Equipo.resolver_slot(arma, {}) == "arma", "b: slot directo intacto")
	_chk(Equipo.slot_valido_para("pendiente", "pendiente_2"),
		"b: genérico válido en el par")
	_chk(not Equipo.slot_valido_para("pendiente", "anillo_1"),
		"b: genérico inválido fuera del par")


## (c) Equipar/desequipar: mods + stock.
func _test_equipar() -> void:
	var kit: Array = _kit()
	var st: StatBlock = kit[0]
	var inv: Inventario = kit[1]
	var eq: Equipo = kit[2]
	var def0: float = st.defensa
	inv.agregar("escudo_madera", 1)
	_chk(eq.equipar("escudo_madera", st, inv), "c: equipar escudo")
	_chk(eq.equipado_en("escudo") == "escudo_madera", "c: escudo equipado")
	_chk(inv.contar("escudo_madera") == 0, "c: sale del inventario")
	_chk(is_equal_approx(st.defensa, def0 + 8.0),
		"c: defensa +8 del escudo", str(st.defensa))
	_chk(st.has_mod("equipo:escudo:defensa"), "c: fuente equipo:escudo:defensa")
	# Reemplazo: otro escudo no existe; se usa casco para probar slot directo.
	inv.agregar("casco_cuero", 1)
	_chk(eq.equipar("casco_cuero", st, inv), "c: equipar casco")
	_chk(eq.equipado_en("casco") == "casco_cuero", "c: casco equipado")
	# Joyería: dos pendientes ocupan el par.
	inv.agregar("pendiente_luna", 1)
	inv.agregar("pendiente_sol", 1)
	_chk(eq.equipar("pendiente_luna", st, inv)
		and eq.equipar("pendiente_sol", st, inv), "c: dos pendientes equipan")
	_chk(eq.equipado_en("pendiente_1") == "pendiente_luna"
		and eq.equipado_en("pendiente_2") == "pendiente_sol",
		"c: pendientes en su par")
	# Desequipar devuelve al inventario y quita los mods.
	_chk(eq.desequipar("escudo", st, inv), "c: desequipar escudo")
	_chk(eq.equipado_en("escudo") == "", "c: escudo vacío")
	_chk(inv.contar("escudo_madera") == 1, "c: escudo vuelve al inventario")
	_chk(is_equal_approx(st.defensa, def0 + 6.0),
		"c: defensa sin escudo (casco +6)", str(st.defensa))
	_chk(not st.has_mod("equipo:escudo:defensa"), "c: fuente del escudo fuera")
	# Sin stock no equipa.
	_chk(not eq.equipar("botas_cuero", st, inv), "c: sin stock no equipa")
	# Consumible no equipa.
	inv.agregar("pocion_vida", 1)
	_chk(not eq.equipar("pocion_vida", st, inv), "c: consumible no equipa")


## (d) Serialización genérica de los 12 slots.
func _test_dict() -> void:
	var kit: Array = _kit()
	var st: StatBlock = kit[0]
	var inv: Inventario = kit[1]
	var eq: Equipo = kit[2]
	for iid in ["escudo_madera", "casco_cuero", "pendiente_luna", "anillo_poder"]:
		inv.agregar(iid, 1)
		eq.equipar(iid, st, inv)
	var d: Dictionary = eq.to_dict()
	_chk(int(d.get("version", 0)) == 1, "d: version 1")
	var slots: Dictionary = d.get("slots", {})
	_chk(slots.size() == 12, "d: 12 slots serializados", str(slots.size()))
	_chk(str(slots.get("pendiente_1", "")) == "pendiente_luna",
		"d: pendiente_1 en disco")
	var st2: StatBlock = SB.new()
	var eq2: Equipo = Equipo.from_dict(d, st2)
	_chk(eq2.equipado_en("escudo") == "escudo_madera", "d: from_dict escudo")
	_chk(eq2.equipado_en("pendiente_1") == "pendiente_luna",
		"d: from_dict acepta genérico en pendiente_1")
	_chk(is_equal_approx(st2.defensa, st.defensa),
		"d: mods reaplicados", "%s vs %s" % [str(st2.defensa), str(st.defensa)])
	# Id inválido se ignora sin reventar.
	var mala: Dictionary = {"version": 1, "slots": {"arma": "no_existe", "casco": ""}}
	var eq3: Equipo = Equipo.from_dict(mala, SB.new())
	_chk(eq3.equipado_en("arma") == "", "d: id inválido ignorado")


## (e) Save/load con los 12 slots.
func _test_save() -> void:
	DirAccess.remove_absolute("user://partida.json")
	var p: Player = PL.new()
	p.nombre = "Test"
	p.clase_id = "guerrero"
	root.add_child(p)
	_basura.append(p)
	p.inventario.agregar("escudo_madera", 1)
	p.inventario.agregar("pendiente_sol", 1)
	_chk(p.equipo.equipar("escudo_madera", p.stats, p.inventario),
		"e: equipar escudo al player")
	_chk(p.equipo.equipar("pendiente_sol", p.stats, p.inventario),
		"e: equipar pendiente al player")
	var def_con: float = p.stats.defensa
	var s: SaveSystem = SV.new()
	s.jugador = p
	s.enemigos = []
	s.npcs = []
	s.tienda = null
	s.misiones = null
	s.barra_acciones = null
	_chk(s.guardar(), "e: guardar() true")
	var crudo: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.RUTA))
	var eqd: Dictionary = ((crudo as Dictionary).get("jugador", {}) as Dictionary).get("equipo", {})
	var slots: Dictionary = eqd.get("slots", {})
	_chk(str(slots.get("escudo", "")) == "escudo_madera", "e: escudo en disco")
	_chk(str(slots.get("pendiente_1", "")) == "pendiente_sol",
		"e: pendiente_1 en disco")
	var p2: Player = PL.new()
	var s2: SaveSystem = SV.new()
	s2.jugador = p2
	_chk(s2.cargar(), "e: cargar() true")
	_chk(p2.equipo.equipado_en("escudo") == "escudo_madera",
		"e: escudo restaurado")
	_chk(p2.equipo.equipado_en("pendiente_1") == "pendiente_sol",
		"e: pendiente restaurada")
	_chk(is_equal_approx(p2.stats.defensa, def_con),
		"e: defensa con mods restaurada", str(p2.stats.defensa))
	DirAccess.remove_absolute("user://partida.json")
