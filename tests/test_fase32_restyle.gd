extends SceneTree
## Tests headless de la Fase 32 (restyle visual FlyFF, solo cromo).
##
## Cubre:
## (a) TemaFlyFF: paleta (HP/MP/XP distintos) + fábricas (marco dorado,
##     relleno del color pedido, etiqueta sin ratón);
## (b) HUD: valores "actual/máx" en HP/MP, retrato integrado, todo dentro
##     del viewport 1920x1080;
## (c) Minimapa: constantes y transformaciones intactas, etiqueta con fondo;
## (d) Inventario: pestañas/columnas intactas, celdas con tooltip y celda
##     seleccionada con borde dorado;
## (e) Barra: 8 slots y libro con 8 chips (lógica intacta).
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase32_restyle.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const HUDS: GDScript = preload("res://scripts/ui/hud.gd")
const MMS: GDScript = preload("res://scripts/ui/barra_acciones.gd")
const MM: GDScript = preload("res://scripts/ui/minimapa.gd")
const PINV: GDScript = preload("res://scripts/ui/panel_inventario.gd")

var _ok: int = 0
var _fallos: int = 0
var _frame: int = 0
var _basura: Array = []
var _hud: HUD = null
var _jugador: Player = null


func _init() -> void:
	print("[TEST] Fase 32 — restyle visual FlyFF")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_preparar()
	elif _frame == 3:
		_test_hud_layout()
		_test_minimapa()
		_test_inventario()
		_test_barra()
		print("[TEST] fase32_restyle: %d ok, %d fallos" % [_ok, _fallos])
		for n in _basura:
			var nd: Node = n as Node
			if nd != null and is_instance_valid(nd):
				nd.queue_free()
		quit(_fallos)
		return true
	return false


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _preparar() -> void:
	root.size = Vector2i(1920, 1080)
	_test_tema()
	_jugador = PL.new()
	_jugador.fijar_identidad("Test", "guerrero")
	_jugador.aplicar_clase("guerrero")
	root.add_child(_jugador)
	_basura.append(_jugador)
	_hud = HUDS.new()
	root.add_child(_hud)
	_basura.append(_hud)
	_hud.conectar(_jugador)
	_test_hud_valores()


## (a) Paleta y fábricas (puras, sin árbol).
func _test_tema() -> void:
	_chk(TemaFlyFF.HP != TemaFlyFF.MP, "a: HP y MP distintos")
	_chk(TemaFlyFF.XP != TemaFlyFF.HP, "a: XP distinto de HP")
	var marco: StyleBoxFlat = TemaFlyFF.marco()
	_chk(marco.border_color == TemaFlyFF.DORADO, "a: marco dorado")
	_chk(marco.get_border_width_all() == 2, "a: marco borde 2")
	_chk(marco.get_corner_radius_top_right() == 6, "a: marco esquinas 6")
	var rel: StyleBoxFlat = TemaFlyFF.relleno(TemaFlyFF.HP)
	_chk(rel.bg_color == TemaFlyFF.HP, "a: relleno del color pedido")
	var et: Label = TemaFlyFF.etiqueta("hola", 14)
	_chk(et.mouse_filter == Control.MOUSE_FILTER_IGNORE, "a: etiqueta sin ratón")
	_basura.append(et)


## (b1) Valores "actual/máx" (frame 1, sin layout).
func _test_hud_valores() -> void:
	_chk(_hud._barra_vida.max_value == _jugador.stats.vida_max, "b: barra HP al máximo")
	_chk(_hud._valor_vida.text == "%d/%d" % [int(_jugador.vida_actual), int(_jugador.stats.vida_max)],
		"b: valor HP actual/máx", _hud._valor_vida.text)
	_jugador.take_damage(30.0, null, false)
	_chk(_hud._barra_vida.value == _jugador.vida_actual, "b: la barra sigue al daño")
	_chk(_hud._valor_vida.text.begins_with(str(int(_jugador.vida_actual))),
		"b: el valor sigue al daño", _hud._valor_vida.text)
	var n_ret: int = 0
	for h in _controles(_hud):
		if h is RetratoHeroe:
			n_ret += 1
	_chk(n_ret == 1, "b: retrato integrado")


## (b2) Todo el HUD dentro del viewport (frame 3, layout asentado).
func _test_hud_layout() -> void:
	var vp: Rect2 = Rect2(Vector2.ZERO, Vector2(root.size))
	for c in _controles(_hud):
		var rc: Rect2 = (c as Control).get_global_rect()
		_chk(vp.encloses(rc), "b: HUD dentro del viewport", "rect=%s" % rc)


func _controles(n: Node) -> Array:
	var res: Array = []
	for h in n.get_children():
		if h is Control:
			res.append(h)
			res.append_array(_controles(h))
	return res


## (c) Minimapa intacto + etiqueta con fondo.
func _test_minimapa() -> void:
	_chk(Minimapa.TAM_MAPA == 200.0, "c: tamaño 200")
	var mm: Minimapa = MM.new()
	root.add_child(mm)
	_basura.append(mm)
	var w := Vector2(123.0, -456.0)
	var redondo: Vector3 = mm.mapa_a_mundo(mm.mundo_a_mapa(w))
	_chk(absf(redondo.x - w.x) < 1.0 and absf(redondo.z - w.y) < 1.0,
		"c: transformaciones redondas")
	_chk(mm._etiqueta != null and mm._etiqueta.has_theme_stylebox_override("normal"),
		"c: etiqueta con pastilla de fondo")


## (d) Inventario intacto + cromo de celdas.
func _test_inventario() -> void:
	_chk(PanelInventario.PESTANAS.size() == 5, "d: 5 pestañas")
	_chk(PanelInventario.COLUMNAS == 6, "d: 6 columnas")
	var panel: PanelInventario = PINV.new()
	root.add_child(panel)
	_basura.append(panel)
	_jugador.inventario.agregar("pocion_vida", 2)
	panel.conectar(_jugador)
	_chk(panel._rejillas.size() == 5, "d: 5 rejillas")
	_chk((panel._rejillas.get("Todos") as GridContainer).get_child_count() >= 1,
		"d: la rejilla muestra el item")
	var item: Dictionary = ItemDB.obtener("pocion_vida")
	var celda: Button = panel._celda({"id": "pocion_vida", "cantidad": 2}, item)
	_basura.append(celda)
	_chk(str(celda.tooltip_text).contains("x2"), "d: tooltip con cantidad",
		celda.tooltip_text)
	panel._sel_id = "pocion_vida"
	var sel: Button = panel._celda({"id": "pocion_vida", "cantidad": 1}, item)
	_basura.append(sel)
	var sb: StyleBoxFlat = sel.get_theme_stylebox("normal") as StyleBoxFlat
	_chk(sb != null and sb.border_color == TemaFlyFF.DORADO_CLARO,
		"d: seleccionada con borde dorado")


## (e) Barra intacta.
func _test_barra() -> void:
	_chk(BarraAcciones.NUM_SLOTS == 8, "e: 8 slots")
	var b: BarraAcciones = MMS.new()
	root.add_child(b)
	_basura.append(b)
	b.conectar(_jugador)
	var chips: int = 0
	var pila: Array = [b._libro_caja]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is BarraAcciones.ChipArrastre:
			chips += 1
		for h in n.get_children():
			pila.append(h)
	_chk(chips == 8, "e: libro con 8 chips", str(chips))
