extends SceneTree
## Tests headless de la Fase 31 (inventario estilo FlyFF).
##
## Cubre:
## (a) filtrado lógico por pestaña sobre los tipos del JSON:
##     Todos=27, Equipo=18, Consumibles=2, Materiales=7, Misión=0;
## (b) 10 piezas nuevas con slot válido (escudo, casco, guantes, botas,
##     collar, 2 pendientes, 2 anillos, amuleto);
## (c) panel: 5 pestañas con rejilla de 6 columnas; clic en celda
##     selecciona y la barra ofrece Usar/Equipar; Equipar mueve al equipo;
## (d) los tres paneles (inventario, equipo, habilidades) arrancan
##     ocultos: solo el visible intercepta ratón.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase31_inventario.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const PI: GDScript = preload("res://scripts/ui/panel_inventario.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 31 — inventario FlyFF")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	ItemDB.cargar()
	_test_filtro()
	_test_piezas()
	_test_panel()
	_test_ocultos()
	print("[TEST] fase31_inventario: %d ok, %d fallos" % [_ok, _fallos])
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


func _todos_items() -> Array:
	var items: Array = []
	for iid in ItemDB.ids():
		items.append(ItemDB.obtener(iid))
	return items


## (a) Filtrado lógico por pestaña.
func _test_filtro() -> void:
	var items: Array = _todos_items()
	# Fase 43: +10 materiales regionales; Fase 44: +10 piezas forjadas (47).
	var esperados: Dictionary = {"Todos": 47, "Equipo": 28, "Consumibles": 2,
		"Materiales": 17, "Misión": 0}
	for pestana in PanelInventario.PESTANAS:
		var n: int = 0
		for item in items:
			if PanelInventario.pasa_filtro(item, pestana):
				n += 1
		_chk(n == int(esperados.get(pestana, -1)),
			"a: pestaña %s = %d" % [pestana, int(esperados.get(pestana, -1))],
			"n=%d" % n)


## (b) Las 10 piezas nuevas con slot válido.
func _test_piezas() -> void:
	var esperados: Dictionary = {
		"escudo_madera": "escudo", "casco_cuero": "casco",
		"guantes_cuero": "guantes", "botas_cuero": "botas",
		"collar_cobre": "collar", "pendiente_luna": "pendiente",
		"pendiente_sol": "pendiente", "anillo_poder": "anillo",
		"anillo_sabio": "anillo", "amuleto_guardian": "amuleto",
	}
	for iid in esperados:
		_chk(ItemDB.existe(iid), "b: existe " + iid)
		_chk(str(ItemDB.obtener(iid).get("slot", "")) == str(esperados[iid]),
			"b: slot de " + iid, str(ItemDB.obtener(iid).get("slot", "")))
		_chk(Equipo.es_equipable(iid), "b: equipable " + iid)


## (c) Panel: pestañas, rejilla, selección y Equipar.
func _test_panel() -> void:
	var p: Player = PL.new()
	p.nombre = "Test"
	p.clase_id = "guerrero"
	root.add_child(p)
	_basura.append(p)
	p.inventario.agregar("escudo_madera", 1)
	p.inventario.agregar("pocion_vida", 3)
	p.inventario.agregar("colmillo", 2)
	var panel: PanelInventario = PI.new()
	root.add_child(panel)
	_basura.append(panel)
	_chk(panel._rejillas.size() == 5, "c: 5 pestañas",
		str(panel._rejillas.size()))
	for pestana in PanelInventario.PESTANAS:
		var rejilla: GridContainer = panel._rejillas.get(pestana)
		_chk(rejilla != null and rejilla.columns == 6,
			"c: rejilla 6 columnas en " + pestana)
	panel.conectar(p)
	var todos: GridContainer = panel._rejillas.get("Todos")
	_chk(todos.get_child_count() == 3, "c: 3 celdas en Todos",
		str(todos.get_child_count()))
	var equipo_g: GridContainer = panel._rejillas.get("Equipo")
	_chk(equipo_g.get_child_count() == 1, "c: 1 celda en Equipo",
		str(equipo_g.get_child_count()))
	# Clic en la celda del escudo → selecciona y ofrece Equipar.
	var btn: Button = null
	for h in todos.get_children():
		var b: Button = h as Button
		if b != null and not b.is_queued_for_deletion() \
				and str(b.tooltip_text).contains("Escudo"):
			btn = b
			break
	_chk(btn != null, "c: celda del escudo existe")
	btn.pressed.emit()
	_chk(panel._sel_id == "escudo_madera", "c: clic selecciona el escudo")
	_chk(not panel._btn_equipar.disabled, "c: Equipar activo en escudo")
	_chk(panel._btn_usar.disabled, "c: Usar inactivo en escudo")
	panel._btn_equipar.pressed.emit()
	_chk(p.equipo.equipado_en("escudo") == "escudo_madera",
		"c: Equipar mueve al equipo")
	_chk(p.inventario.contar("escudo_madera") == 0,
		"c: escudo sale del inventario")
	# La poción ofrece Usar.
	for h in panel._rejillas.get("Consumibles").get_children():
		var b: Button = h as Button
		if b != null and not b.is_queued_for_deletion():
			b.pressed.emit()
			break
	_chk(panel._sel_id == "pocion_vida", "c: clic selecciona la poción")
	_chk(not panel._btn_usar.disabled, "c: Usar activo en poción")
	_chk(panel._btn_equipar.disabled, "c: Equipar inactivo en poción")


## (d) Los paneles arrancan ocultos.
func _test_ocultos() -> void:
	_chk(PanelInventario.new().visible == false,
		"d: inventario arranca oculto")
	_chk(PanelEquipo.new().visible == false, "d: equipo arranca oculto")
	_chk(PanelHabilidades.new().visible == false,
		"d: habilidades arranca oculto")
