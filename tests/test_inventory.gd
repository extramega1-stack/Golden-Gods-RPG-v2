extends SceneTree
## Tests headless de la Fase 5 (datos + inventario: ItemDB, Inventario, Equipo).
##
## Cómo correrlos (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_inventory.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const IDB: GDScript = preload("res://scripts/inventory/item_db.gd")
const INV: GDScript = preload("res://scripts/inventory/inventory.gd")
const EQ: GDScript = preload("res://scripts/inventory/equipment.gd")
const EN: GDScript = preload("res://scripts/core/entity.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")

var _ok: int = 0
var _fallos: int = 0


func _init() -> void:
	print("[TEST] Fase 5 — datos + inventario")
	_t_itemdb()
	_t_agregar_apilar()
	_t_capacidad()
	_t_quitar_contar()
	_t_usar()
	_t_equipo()
	_t_roundtrip()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


func _nueva_entidad() -> Entity:
	return EN.new(SB.new(10.0, 10.0, 10.0, 10.0))


func _t_itemdb() -> void:
	IDB.cargar()
	# Fase 22: 16 = 10 + 6 fragmentos de jefe.
	_check(IDB.ids().size() == 53, "ItemDB carga 53 items (16 + Eco + 10 f31 + 10 regionales + 10 forjadas + 6 minerales)", str(IDB.ids().size()))
	_check(IDB.existe("pocion_vida"), "existe pocion_vida (drop de enemies.json)")
	_check(IDB.existe("daga_gastada"), "existe daga_gastada (drop de enemies.json)")
	_check(IDB.existe("colmillo"), "existe colmillo (drop de enemies.json)")
	_check(IDB.existe("maza_ogro"), "existe maza_ogro (drop de enemies.json)")
	_check(IDB.obtener("x") == {}, "obtener('x') retorna {}")
	var pv: Dictionary = IDB.obtener("pocion_vida")
	_check(str(pv.get("tipo", "")) == "consumible", "pocion_vida es consumible")
	var mg: Dictionary = IDB.obtener("maza_ogro")
	_check(str(mg.get("rareza", "")) == "raro", "maza_ogro es rara")


func _t_agregar_apilar() -> void:
	var inv: Inventario = INV.new()
	var sobra: int = inv.agregar("pocion_vida", 3)
	_check(sobra == 0, "agregar 3 pociones: todo entra")
	_check(inv.contar("pocion_vida") == 3, "contar pociones = 3")
	sobra = inv.agregar("pocion_vida", 2)
	_check(sobra == 0 and inv.contar("pocion_vida") == 5, "apilar: 3 + 2 = 5")
	_check(inv.entradas.size() == 1, "apilable ocupa 1 slot", str(inv.entradas.size()))
	sobra = inv.agregar("no_existe", 4)
	_check(sobra == 4 and inv.contar("no_existe") == 0, "id desconocido: retorna cantidad intacta")


func _t_capacidad() -> void:
	# Items sintéticos no-apilables para llenar los 20 slots (simulan loot de mod).
	for i in 21:
		var iid: String = "prueba_%d" % i
		IDB._cache[iid] = {"id": iid, "apilable": false}
	var inv: Inventario = INV.new()
	var todo_cupo: bool = true
	for i in 20:
		if inv.agregar("prueba_%d" % i, 1) != 0:
			todo_cupo = false
	_check(todo_cupo, "20 no-apilables distintos ocupan 20 slots")
	_check(inv.entradas.size() == 20, "slots_usados = 20")
	var sobra: int = inv.agregar("prueba_20", 1)
	_check(sobra == 1, "el 21º deja leftover = 1")
	_check(inv.contar("prueba_20") == 0, "el 21º no entró al inventario")


func _t_quitar_contar() -> void:
	var inv: Inventario = INV.new()
	inv.agregar("pocion_vida", 5)
	_check(inv.quitar("pocion_vida", 2), "quitar 2 pociones")
	_check(inv.contar("pocion_vida") == 3, "quedan 3 pociones")
	_check(not inv.quitar("pocion_vida", 99), "quitar más del stock → false")
	_check(inv.contar("pocion_vida") == 3, "stock intacto tras quitar fallido")
	_check(not inv.quitar("pocion_mana", 1), "quitar sin stock → false")
	inv.quitar("pocion_vida", 3)
	_check(inv.entradas.is_empty(), "entrada apilada se elimina al llegar a 0")


func _t_usar() -> void:
	var e: Entity = _nueva_entidad()
	var inv: Inventario = INV.new()
	inv.agregar("pocion_vida", 2)
	inv.agregar("pocion_mana", 1)
	inv.agregar("daga_gastada", 1)
	e.take_damage(100.0, null)  # vida: 450 → 350
	_check(inv.usar("pocion_vida", e), "usar pocion_vida")
	_check(is_equal_approx(e.vida_actual, 410.0), "cura 60 (350 → 410)", str(e.vida_actual))
	_check(inv.contar("pocion_vida") == 1, "descuenta 1 pocion")
	e.gastar_mana(30.0)  # maná: 200 → 170
	_check(inv.usar("pocion_mana", e), "usar pocion_mana")
	_check(is_equal_approx(e.mana_actual, 200.0), "restaura maná (170 + 40, tope 200)", str(e.mana_actual))
	_check(not inv.usar("daga_gastada", e), "usar('daga_gastada') = false (no consumible)")
	_check(inv.contar("daga_gastada") == 1, "no consumible no se descuenta")
	inv.quitar("pocion_vida", 1)
	_check(not inv.usar("pocion_vida", e), "usar sin stock = false")
	_check(not inv.usar("no_existe", e), "usar id desconocido = false")


func _t_equipo() -> void:
	var e: Entity = _nueva_entidad()
	var stats: StatBlock = e.stats
	var inv: Inventario = INV.new()
	var eq: Equipo = EQ.new()
	var base_ataque: float = stats.ataque  # 5 + 10*2 + 10*0.5 = 30
	var base_defensa: float = stats.defensa  # 10*0.5 + 10*1.5 = 20
	_check(not eq.equipar("pocion_vida", stats, inv), "equipar consumible = false")
	_check(not eq.equipar("no_existe", stats, inv), "equipar id desconocido = false")
	_check(not eq.equipar("maza_ogro", stats, inv), "equipar sin stock = false")
	inv.agregar("espada_corta", 1)
	_check(eq.equipar("espada_corta", stats, inv), "equipar espada_corta")
	_check(is_equal_approx(stats.ataque, base_ataque + 9.0), "ataque +9 plano", str(stats.ataque))
	_check(is_equal_approx(stats.fuerza, 10.0), "NO toca stats base (fuerza)", str(stats.fuerza))
	_check(inv.contar("espada_corta") == 0, "espada sale del inventario")
	inv.agregar("armadura_cuero", 1)
	_check(eq.equipar("armadura_cuero", stats, inv), "equipar armadura_cuero")
	_check(is_equal_approx(stats.defensa, base_defensa + 12.0), "defensa +12 plano", str(stats.defensa))
	_check(is_equal_approx(stats.vida_max, 450.0 + 20.0), "vida_max +20 plano", str(stats.vida_max))
	# Otra arma en el mismo slot: devuelve la anterior y quita sus mods.
	inv.agregar("espada_hierro", 1)
	_check(eq.equipar("espada_hierro", stats, inv), "equipar segunda arma (reemplaza)")
	_check(inv.contar("espada_corta") == 1, "arma anterior vuelve al inventario")
	_check(is_equal_approx(stats.ataque, base_ataque + 14.0), "mods viejos quitados: ataque = base + 14", str(stats.ataque))
	_check(is_equal_approx(stats.crit_prob, 0.09 + 0.02), "crit_prob +0.02 plano", str(stats.crit_prob))
	_check(eq.equipado_en("arma") == "espada_hierro", "slot arma = espada_hierro")
	# Desequipar: quita mods y devuelve al inventario.
	_check(eq.desequipar("arma", stats, inv), "desequipar arma")
	_check(is_equal_approx(stats.ataque, base_ataque), "ataque vuelve a base", str(stats.ataque))
	_check(is_equal_approx(stats.crit_prob, 0.09), "crit_prob vuelve a base", str(stats.crit_prob))
	_check(inv.contar("espada_hierro") == 1, "arma desequipada vuelve al inventario")
	_check(eq.equipado_en("arma") == "", "slot arma vacío")
	_check(not eq.desequipar("arma", stats, inv), "desequipar slot vacío = false")
	_check(not eq.desequipar("casco", stats, inv), "desequipar slot inválido = false")


func _t_roundtrip() -> void:
	# Inventario: to_dict → from_dict conserva todo.
	var inv: Inventario = INV.new()
	inv.agregar("pocion_vida", 5)
	inv.agregar("cota_malla", 1)
	var d: Dictionary = inv.to_dict()
	_check(int(d.get("version", 0)) == 1, "inventario to_dict versionada")
	var inv2: Inventario = INV.from_dict(d)
	_check(inv2.contar("pocion_vida") == 5, "round-trip inventario: pociones", str(inv2.contar("pocion_vida")))
	_check(inv2.contar("cota_malla") == 1, "round-trip inventario: cota", str(inv2.contar("cota_malla")))
	_check(inv2.entradas.size() == 2, "round-trip inventario: 2 slots", str(inv2.entradas.size()))
	var vacio: Inventario = INV.from_dict({})
	_check(vacio.entradas.is_empty(), "from_dict({}) tolera campos ausentes")
	# Equipo: from_dict reaplica los mods al StatBlock.
	var e: Entity = _nueva_entidad()
	var inv3: Inventario = INV.new()
	var eq: Equipo = EQ.new()
	inv3.agregar("espada_hierro", 1)
	inv3.agregar("cota_malla", 1)
	eq.equipar("espada_hierro", e.stats, inv3)
	eq.equipar("cota_malla", e.stats, inv3)
	var deq: Dictionary = eq.to_dict()
	var stats2: StatBlock = SB.new(10.0, 10.0, 10.0, 10.0)
	var eq2: Equipo = EQ.from_dict(deq, stats2)
	_check(eq2.equipado_en("arma") == "espada_hierro", "round-trip equipo: arma", eq2.equipado_en("arma"))
	_check(eq2.equipado_en("armadura") == "cota_malla", "round-trip equipo: armadura", eq2.equipado_en("armadura"))
	_check(is_equal_approx(stats2.ataque, 25.0 + 14.0), "round-trip equipo: mods reaplicados", str(stats2.ataque))
	var eq3: Equipo = EQ.from_dict({}, stats2)
	_check(eq3.equipado_en("arma") == "", "equipo from_dict({}) = vacío")
