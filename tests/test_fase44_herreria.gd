extends SceneTree
## Tests headless de la Fase 44 (herrería).
##
## (a) Datos: 10 recetas, 2 herreros, materiales/resultados existen, niveles
##     y oro con orden de valor creciente por rareza.
## (b) Lógica: puede_forjar (sin materiales / sin oro / nivel / ok),
##     forjar consume materiales + oro, entrega el item, es idempotente
##     (no reg材料 gratis) y NO toca stats.
## (c) NPC: Bram y Durnan son herreros con su set de recetas; la ventana de
##     diálogo muestra el botón Forjar solo a ellos.
## (d) Panel: filtra por herrero, muestra "x/y" de materiales y el botón
##     bloqueado cuando falta algo; forja desde el panel.
## (e).Save: lo forjado sobrevive (inventario, sin bloque nuevo).
## (f) Balance: ninguna pieza forjada supera al verdugo_eco del élite en
##     TODOS los stats a la vez (es un sidegrade, no un mejor item).
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase44_herreria.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const HR: GDScript = preload("res://scripts/inventory/herreria.gd")
const RDB: GDScript = preload("res://scripts/inventory/recetas_db.gd")
const IDB: GDScript = preload("res://scripts/inventory/item_db.gd")
const PH: GDScript = preload("res://scripts/ui/panel_herreria.gd")
const VD: GDScript = preload("res://scripts/ui/ventana_dialogo.gd")
const NPC: GDScript = preload("res://scripts/npc/npc.gd")
const EQ: GDScript = preload("res://scripts/inventory/equipment.gd")

const BRAM: Array[String] = ["daga_carina", "lanza_hielo", "daga_seda",
	"guantes_umbral", "amuleto_perla", "botas_lamento", "foco_vacio"]
const DURNAN: Array[String] = ["hoja_ascua", "martillo_golem", "coraza_centinela"]

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []
var _forjados: Array[String] = []


func _init() -> void:
	print("[TEST] Fase 44 — herrería")
	ItemDB.cargar()
	RecetasDB.cargar()
	NpcDB.cargar()


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_datos()
	_test_logica()
	_test_npc()
	_test_panel()
	_test_save()
	_test_balance()
	print("[TEST] fase44_herreria: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		if is_instance_valid(n):
			(n as Node).free()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _jugador(nivel: int = 30) -> Player:
	var p: Player = PL.new()
	p.fijar_identidad("H", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	p.nivel = nivel
	p.gastar_oro(0)
	return p


func _con_materials(p: Player, receta_id: String) -> void:
	for m in (RDB.obtener(receta_id).get("materiales", []) as Array):
		var md: Dictionary = m
		p.inventario.agregar(str(md.get("item_id", "")), int(md.get("cantidad", 0)))


## (a) Datos.
func _test_datos() -> void:
	_chk(RDB.ids().size() == 10, "a: 10 recetas", str(RDB.ids().size()))
	_chk(RDB.recetas_de_herrero("bram") == BRAM, "a: Bram tiene su set",
		str(RDB.recetas_de_herrero("bram")))
	_chk(RDB.recetas_de_herrero("durnan") == DURNAN, "a: Durnan tiene el suyo",
		str(RDB.recetas_de_herrero("durnan")))
	for rid in RDB.ids():
		var r: Dictionary = RDB.obtener(rid)
		_chk(not (r.get("materiales", []) as Array).is_empty(), "a: " + rid + " tiene materiales")
		_chk(int(r.get("oro", 0)) > 0, "a: " + rid + " cuesta oro")
		_chk(int(r.get("nivel", 0)) >= 1, "a: " + rid + " tiene nivel")
		var res_id: String = str((r.get("resultado", {}) as Dictionary).get("item_id", ""))
		_chk(IDB.existe(res_id), "a: el resultado de " + rid + " existe")
		_chk(EQ.es_equipable(res_id), "a: " + res_id + " es equipable")
		for m in (r.get("materiales", []) as Array):
			var md: Dictionary = m
			var mid: String = str(md.get("item_id", ""))
			_chk(ItemDB.existe(mid), "a: material " + mid + " existe")
			_chk(str(ItemDB.obtener(mid).get("tipo", "")) == "material",
				"a: " + mid + " es material")


## (b) Lógica de forja.
func _test_logica() -> void:
	var h: Herreria = HR.new()
	var p: Player = _jugador(30)
	# Sin materiales ni oro.
	_chk(h.puede_forjar("daga_carina", p) == "oro" or
		h.puede_forjar("daga_carina", p) == "materiales",
		"b: sin recursos no se puede", h.puede_forjar("daga_carina", p))
	_chk(h.forjar("daga_carina", p) != "ok", "b: forjar sin recursos falla")
	_chk(p.inventario.contar("daga_carina") == 0, "b: no hay item gratis")
	# Nivel insuficiente.
	var p1: Player = _jugador(1)
	_con_materials(p1, "daga_carina")
	p1.ganar_oro(1000)
	_chk(h.puede_forjar("daga_carina", p1) == "nivel", "b: nivel insuficiente",
		h.puede_forjar("daga_carina", p1))
	# Materiales + oro: forja.
	var p2: Player = _jugador(30)
	_con_materials(p2, "daga_carina")
	p2.ganar_oro(1000)
	var oro0: int = p2.oro
	var atk0: float = p2.stats.ataque
	_chk(h.puede_forjar("daga_carina", p2) == "ok", "b: con recursos, ok",
		h.puede_forjar("daga_carina", p2))
	_chk(h.forjar("daga_carina", p2) == "ok", "b: forja")
	_chk(p2.inventario.contar("daga_carina") == 1, "b: entrega el item")
	_chk(p2.inventario.contar("escorpion_carina") == 0, "b: consume el material")
	_chk(p2.oro == oro0 - 120, "b: consume el oro", "%d vs %d" % [p2.oro, oro0 - 120])
	_chk(is_equal_approx(p2.stats.ataque, atk0), "b: forjar NO toca stats")
	# Idempotencia: sin materiales, no repite.
	_chk(h.forjar("daga_carina", p2) == "materiales", "b: no se puede repetir gratis")
	_chk(p2.inventario.contar("daga_carina") == 1, "b: sigue 1 daga")
	# Desconocida.
	_chk(h.puede_forjar("no_existe", p2) == "desconocida", "b: receta desconocida")
	# Estado de materiales para el panel.
	var est: Array[Dictionary] = h.estado_materiales("daga_carina", p2)
	_chk(est.size() == 2, "b: estado_materiales lista los 2 materiales", str(est.size()))
	_chk(int((est[0] as Dictionary).get("falta", 0)) == 3, "b: falta = 3 tras forjar",
		str((est[0] as Dictionary).get("falta", 0)))
	_chk(Herreria.texto_materiales(est) == "0/3 · 0/1", "b: texto x/y",
		Herreria.texto_materiales(est))


## (c) NPCs y botón de diálogo.
func _test_npc() -> void:
	_chk(str(NpcDB.obtener("bram").get("herrero", "")) == "bram", "c: Bram es herrero")
	_chk(str(NpcDB.obtener("durnan").get("herrero", "")) == "durnan", "c: Durnan es herrero")
	_chk(str(NpcDB.obtener("ilya").get("herrero", "")) == "", "c: Ilya no")
	var d: VentanaDialogo = VD.new()
	root.add_child(d)
	_basura.append(d)
	var bram: NPC = NPC.new()
	_basura.append(bram)
	bram.npc_id = "bram"
	bram.nombre_mostrado = "Herrero Bram"
	bram.lineas_dialogo = ["Forja algo."]
	d.mostrar(bram)
	var b: Button = d.get("_boton_forjar") as Button
	_chk(b != null and b.visible, "c: Bram ve el botón Forjar")
	d.cerrar()
	var ilya: NPC = NPC.new()
	_basura.append(ilya)
	ilya.npc_id = "ilya"
	ilya.lineas_dialogo = ["Hola."]
	d.mostrar(ilya)
	_chk(not b.visible, "c: Ilya no ve Forjar")


## (d) Panel.
func _test_panel() -> void:
	var p: Player = _jugador(30)
	_con_materials(p, "daga_carina")
	p.ganar_oro(1000)
	var panel: PanelHerreria = PH.new()
	root.add_child(panel)
	_basura.append(panel)
	panel.conectar(p)
	panel.mostrar("bram")
	_chk(panel.esta_abierta(), "d: abre")
	_chk(panel.herrero_id_actual() == "bram", "d: recuerda el herrero")
	_chk(panel.recetas_visibles() == BRAM, "d: lista las recetas de Bram",
		str(panel.recetas_visibles()))
	var botones: int = 0
	var bloqueados: int = 0
	for c in panel._lista.get_children():
		for b in c.get_children():
			if b is Button:
				botones += 1
				if (b as Button).disabled:
					bloqueados += 1
	_chk(botones == BRAM.size(), "d: un botón por receta", str(botones))
	_chk(bloqueados == BRAM.size() - 1, "d: solo la que puedes forjar está activa",
		"%d bloqueados" % bloqueados)
	# Forja desde el panel.
	panel._al_forjar("daga_carina")
	_chk(p.inventario.contar("daga_carina") == 1, "d: forja desde el panel")
	_chk(panel.esta_abierta(), "d: sigue abierto tras forjar")
	panel.cerrar_panel()
	_chk(not panel.esta_abierta(), "d: cierra")
	panel.mostrar("durnan")
	_chk(panel.recetas_visibles() == DURNAN, "d: Durnan muestra su set")


## (e) Save: lo forjado sobrevive (inventario).
func _test_save() -> void:
	var p: Player = _jugador(30)
	var h: Herreria = HR.new()
	_con_materials(p, "daga_carina")
	p.ganar_oro(1000)
	h.forjar("daga_carina", p)
	var d: Dictionary = p.inventario.to_dict()
	var p2: Player = _jugador(30)
	p2.inventario = Inventario.from_dict(d)
	_chk(p2.inventario.contar("daga_carina") == 1,
		"e: la pieza forjada sobrevive al save sin bloque nuevo")
	_chk(p2.inventario.contar("escorpion_carina") == 0, "e: los materiales se consumieron")


## (f) Balance: sidegrade, no mejor item absoluto.
func _test_balance() -> void:
	var verdugo: Dictionary = ItemDB.obtener("verdugo_eco")
	var v_ataque: float = 0.0
	var v_crit: float = 0.0
	for m in (verdugo.get("mods", []) as Array):
		var md: Dictionary = m
		if str(md.get("stat", "")) == "ataque":
			v_ataque = float(md.get("valor", 0.0))
		if str(md.get("stat", "")) == "crit_prob":
			v_crit = float(md.get("valor", 0.0))
	for rid in RDB.ids():
		var item: Dictionary = ItemDB.obtener(str(
			(RDB.obtener(rid).get("resultado", {}) as Dictionary).get("item_id", "")))
		var atk: float = 0.0
		var crit: float = 0.0
		for m in (item.get("mods", []) as Array):
			var md: Dictionary = m
			if str(md.get("stat", "")) == "ataque":
				atk += float(md.get("valor", 0.0))
			if str(md.get("stat", "")) == "crit_prob":
				crit += float(md.get("valor", 0.0))
		var mejor_o_igual: bool = atk > v_ataque and crit > v_crit
		_chk(not mejor_o_igual,
			"f: " + str(item.get("nombre", rid)) + " no supera al verdugo_eco en todo",
			"atk=%f vs %f" % [atk, v_ataque])
	# Y el arma más fuerte forjada sigue por debajo del verdugo_eco en ataque.
	var hoja: Dictionary = ItemDB.obtener("hoja_ascua")
	var h_atk: float = 0.0
	for m in (hoja.get("mods", []) as Array):
		var md: Dictionary = m
		if str(md.get("stat", "")) == "ataque" and int(md.get("kind", 0)) == 0:
			h_atk = float(md.get("valor", 0.0))
	_chk(h_atk < v_ataque, "f: la hoja de ascua no tiene más ataque plano que el verdugo",
		"%f vs %f" % [h_atk, v_ataque])
