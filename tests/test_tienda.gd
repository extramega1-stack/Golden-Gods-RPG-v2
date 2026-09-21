extends SceneTree
## Tests headless de la Fase 7 (Tienda / economía básica).
##
## Cubre: TiendaDB (2 tiendas desde data/tiendas.json: nombres, stock,
## precios; tienda_de_npc), comprar ("ok"/"sin_oro"/"sin_stock"/"sin_espacio"
## con oro revertido), vender ("ok" con precio_venta de datos, "equipado",
## "sin_stock", stacks de consumibles), round-trip to_dict/from_dict de
## Tienda, save v4 con tienda (stock restaurado; partida v3 sin bloque
## "tiendas" carga con stock completo), PanelTienda (arranca oculto;
## mostrar() con NPC sin tienda no revienta) y VentanaDialogo (flujo
## "Comerciar": señal emitida solo con NPC vendedor; sin tienda no hay
## botón — comportamiento fase 6 intacto).
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_tienda.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const NP: GDScript = preload("res://scripts/npc/npc.gd")
const NDB: GDScript = preload("res://scripts/npc/npc_db.gd")
const TDB: GDScript = preload("res://scripts/tienda/tienda_db.gd")
const T: GDScript = preload("res://scripts/tienda/tienda.gd")
const SV: GDScript = preload("res://scripts/save/save_system.gd")
const DLG: GDScript = preload("res://scripts/ui/ventana_dialogo.gd")
const PT: GDScript = preload("res://scripts/ui/panel_tienda.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _comerciados: Array = []


func _init() -> void:
	print("[TEST] Fase 7 — Tienda / economia basica")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b): todo lo que
## usa global_position o get_tree() corre aquí.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	NDB.cargar()
	TDB.cargar()
	_t_db()
	_t_comprar_sin_oro()
	_t_comprar_ok()
	_t_agotar_stock()
	_t_inventario_lleno()
	_t_vender()
	_t_vender_equipada()
	_t_roundtrip()
	_t_save_v4()
	_t_save_tolerante_v3()
	_t_panel()
	_t_dialogo_comerciar()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
	return true


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


func _al_comerciar(npc: NPC) -> void:
	_comerciados.append(npc)


func _player(pos: Vector3) -> Player:
	var p: Player = PL.new()
	p.add_to_group("jugador")
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


func _npc(id: String, pos: Vector3) -> NPC:
	var n: NPC = NP.new()
	n.add_to_group("npcs")
	root.add_child(n)
	n.global_position = pos
	n.configurar(NDB.obtener(id))
	_basura.append(n)
	return n


func _tienda() -> Tienda:
	return T.new()


func _stock_cantidad(t: Tienda, tienda_id: String, item_id: String) -> int:
	for f in t.stock_de(tienda_id):
		var fd: Dictionary = f
		if str(fd.get("item_id", "")) == item_id:
			return int(fd.get("cantidad", -1))
	return -1


## --- TiendaDB: datos puros ---


func _t_db() -> void:
	_check(TDB.existe("tienda_bram"), "db: existe tienda_bram")
	_check(TDB.existe("tienda_sira"), "db: existe tienda_sira")
	_check(not TDB.existe("tienda_fantasma"), "db: no existe id inventado")
	var bram: Dictionary = TDB.obtener("tienda_bram")
	_check(str(bram.get("nombre", "")) == "Forja de Bram",
		"db: nombre Forja de Bram")
	var sira: Dictionary = TDB.obtener("tienda_sira")
	_check(str(sira.get("nombre", "")) == "Botica de Sira",
		"db: nombre Botica de Sira")
	var ids: Array[String] = TDB.ids()
	_check(ids.size() == 2, "db: exactamente 2 tiendas", str(ids))
	_check(TDB.tienda_de_npc("bram") == "tienda_bram",
		"db: tienda_de_npc(bram)")
	_check(TDB.tienda_de_npc("sira") == "tienda_sira",
		"db: tienda_de_npc(sira)")
	_check(TDB.tienda_de_npc("ilya") == "",
		"db: ilya no vende")
	_check(TDB.tienda_de_npc("nadie") == "",
		"db: npc inexistente no vende")
	# Precios y stock de la forja (data/tiendas.json).
	var t: Tienda = _tienda()
	_check(t.precio_compra("tienda_bram", "espada_corta") == 120,
		"db: espada_corta compra 120")
	_check(t.precio_venta("espada_corta") == 60,
		"db: espada_corta venta 60 (explicito)")
	_check(t.precio_compra("tienda_bram", "maza_ogro") == 400,
		"db: maza_ogro compra 400")
	_check(_stock_cantidad(t, "tienda_bram", "espada_corta") == 3,
		"db: espada_corta stock 3")
	_check(_stock_cantidad(t, "tienda_bram", "maza_ogro") == 1,
		"db: maza_ogro stock 1")
	_check(t.precio_compra("tienda_sira", "pocion_vida") == 35,
		"db: pocion_vida compra 35")
	_check(_stock_cantidad(t, "tienda_sira", "pocion_vida") == 10,
		"db: pocion_vida stock 10")
	_check(t.precio_compra("tienda_que_no_existe", "espada_corta") == 0,
		"db: precio_compra en tienda desconocida = 0")


## --- comprar() ---


func _t_comprar_sin_oro() -> void:
	var t: Tienda = _tienda()
	var p: Player = _player(Vector3.ZERO)
	_check(t.comprar(p, "tienda_bram", "espada_corta") == "sin_oro",
		"comprar: sin oro -> sin_oro")
	_check(p.oro == 0, "comprar: sin_oro no toca el oro")
	_check(p.inventario.contar("espada_corta") == 0,
		"comprar: sin_oro no da el item")
	_check(_stock_cantidad(t, "tienda_bram", "espada_corta") == 3,
		"comprar: sin_oro no toca el stock")
	_check(t.comprar(p, "tienda_fantasma", "espada_corta") == "tienda_desconocida",
		"comprar: tienda desconocida")
	_check(t.comprar(p, "tienda_bram", "pocion_vida") == "item_desconocido",
		"comprar: item no vendido por esa tienda")


func _t_comprar_ok() -> void:
	var t: Tienda = _tienda()
	var p: Player = _player(Vector3.ZERO)
	p.ganar_oro(200)
	_check(t.comprar(p, "tienda_bram", "espada_corta") == "ok",
		"comprar: ok con oro")
	_check(p.oro == 80, "comprar: oro descontado exacto (200-120)",
		str(p.oro))
	_check(p.inventario.contar("espada_corta") == 1,
		"comprar: item en inventario")
	_check(_stock_cantidad(t, "tienda_bram", "espada_corta") == 2,
		"comprar: stock decrementado")


func _t_agotar_stock() -> void:
	var t: Tienda = _tienda()
	var p: Player = _player(Vector3.ZERO)
	p.ganar_oro(1000)
	_check(t.comprar(p, "tienda_bram", "maza_ogro") == "ok",
		"stock: primera maza_ogro ok (stock 1)")
	_check(_stock_cantidad(t, "tienda_bram", "maza_ogro") == 0,
		"stock: maza_ogro agotada")
	_check(p.oro == 600, "stock: oro descontado solo la 1a compra",
		str(p.oro))
	_check(t.comprar(p, "tienda_bram", "maza_ogro") == "sin_stock",
		"stock: segunda compra -> sin_stock")
	_check(p.oro == 600, "stock: sin_stock no toca el oro")
	_check(p.inventario.contar("maza_ogro") == 1,
		"stock: sin_stock no duplica el item")


func _t_inventario_lleno() -> void:
	var t: Tienda = _tienda()
	var p: Player = _player(Vector3.ZERO)
	# 20 dagas no apilables = inventario lleno (CAPACIDAD 20).
	for i in 20:
		p.inventario.agregar("daga_gastada")
	_check(p.inventario.slots_usados() == 20, "lleno: 20 slots ocupados")
	p.ganar_oro(100)
	_check(t.comprar(p, "tienda_sira", "pocion_vida") == "sin_espacio",
		"lleno: comprar -> sin_espacio")
	_check(p.oro == 100, "lleno: sin_espacio revierte el oro",
		str(p.oro))
	_check(p.inventario.contar("pocion_vida") == 0,
		"lleno: sin_espacio no da el item")
	_check(_stock_cantidad(t, "tienda_sira", "pocion_vida") == 10,
		"lleno: sin_espacio no toca el stock")


## --- vender() ---


func _t_vender() -> void:
	var t: Tienda = _tienda()
	var p: Player = _player(Vector3.ZERO)
	p.inventario.agregar("pocion_vida", 5)
	_check(t.vender(p, "pocion_vida", 1) == "ok", "vender: ok")
	_check(p.inventario.contar("pocion_vida") == 4,
		"vender: stack de x5 queda en x4")
	_check(p.oro == 17, "vender: oro sumado con precio_venta de datos (17)",
		str(p.oro))
	# Vender por default: colmillo tiene precio_venta explícito (4).
	p.inventario.agregar("colmillo", 2)
	_check(t.vender(p, "colmillo", 2) == "ok", "vender: 2 unidades ok")
	_check(p.oro == 17 + 8, "vender: 2 x 4 = 8 oro", str(p.oro))
	_check(p.inventario.contar("colmillo") == 0,
		"vender: stack vaciado desaparece")
	_check(t.vender(p, "colmillo") == "sin_stock",
		"vender: sin tenerlo -> sin_stock")
	_check(p.oro == 25, "vender: sin_stock no toca el oro")
	_check(t.vender(p, "item_que_no_existe") == "item_desconocido",
		"vender: item desconocido")


func _t_vender_equipada() -> void:
	var t: Tienda = _tienda()
	var p: Player = _player(Vector3.ZERO)
	p.inventario.agregar("espada_corta")
	_check(p.equipo.equipar("espada_corta", p.stats, p.inventario),
		"vender: equipar espada_corta")
	_check(t.vender(p, "espada_corta") == "equipado",
		"vender: equipada -> equipado (rechazada)")
	_check(p.oro == 0, "vender: equipada no suma oro")
	_check(p.equipo.equipado_en("arma") == "espada_corta",
		"vender: equipada sigue equipada")


## --- Serialización de Tienda ---


func _t_roundtrip() -> void:
	var t: Tienda = _tienda()
	var p: Player = _player(Vector3.ZERO)
	p.ganar_oro(500)
	t.comprar(p, "tienda_bram", "espada_corta")  # stock 3 -> 2
	t.comprar(p, "tienda_sira", "pocion_vida")   # stock 10 -> 9
	var d: Dictionary = t.to_dict()
	_check(int(d.get("version", 0)) == 1, "tienda dict: version 1")
	var t2: Tienda = T.from_dict(d)
	_check(_stock_cantidad(t2, "tienda_bram", "espada_corta") == 2,
		"tienda dict: espada_corta persistida en 2")
	_check(_stock_cantidad(t2, "tienda_sira", "pocion_vida") == 9,
		"tienda dict: pocion_vida persistida en 9")
	_check(_stock_cantidad(t2, "tienda_bram", "maza_ogro") == 1,
		"tienda dict: maza_ogro intacta")
	# Los precios de datos sobreviven al round-trip.
	_check(t2.precio_compra("tienda_bram", "espada_corta") == 120,
		"tienda dict: precio_compra intacto")
	# Tolerancia: tiendas/items desconocidos se ignoran con warning.
	var d2: Dictionary = t.to_dict()
	var tiendas: Dictionary = d2["tiendas"]
	tiendas["tienda_fantasma"] = {"espada_corta": 99}
	(tiendas["tienda_bram"] as Dictionary)["item_fantasma"] = 99
	var t3: Tienda = T.from_dict(d2)
	_check(not TDB.existe("tienda_fantasma"),
		"tienda dict: tienda desconocida ignorada")
	_check(_stock_cantidad(t3, "tienda_bram", "espada_corta") == 2,
		"tienda dict: lo conocido sobrevive a lo desconocido")


## --- Save v4: tienda persistida; v3 sin bloque carga con stock completo ---


func _t_save_v4() -> void:
	var s: SaveSystem = SV.new()
	var p: Player = _player(Vector3.ZERO)
	var t: Tienda = _tienda()
	s.jugador = p
	s.enemigos = []
	s.npcs = []
	s.tienda = t
	p.ganar_oro(500)
	_check(t.comprar(p, "tienda_bram", "espada_corta") == "ok",
		"save v4: compra antes de guardar")
	_check(s.guardar(), "save v4: guardar() true")
	# Cambiar el stock DESPUÉS de guardar: cargar debe restaurarlo.
	_check(t.comprar(p, "tienda_bram", "espada_corta") == "ok",
		"save v4: segunda compra post-guardado")
	_check(_stock_cantidad(t, "tienda_bram", "espada_corta") == 1,
		"save v4: stock en 1 antes de cargar")
	_check(s.cargar(), "save v4: cargar() true")
	_check(_stock_cantidad(t, "tienda_bram", "espada_corta") == 2,
		"save v4: stock restaurado a 2",
		str(_stock_cantidad(t, "tienda_bram", "espada_corta")))


func _t_save_tolerante_v3() -> void:
	# Partida vieja (v3): sin bloque "tiendas". Debe cargar igual y la
	# tienda queda con el stock completo desde los datos.
	var s: SaveSystem = SV.new()
	var p: Player = _player(Vector3.ZERO)
	var t: Tienda = _tienda()
	s.jugador = p
	s.enemigos = []
	s.npcs = []
	s.tienda = t
	_check(s.guardar(), "save v3: guardar v4 primero")
	var texto: String = FileAccess.get_file_as_string(SV.RUTA)
	var datos = JSON.parse_string(texto)
	_check(datos is Dictionary, "save v3: JSON legible")
	(datos as Dictionary).erase("tiendas")
	var f: FileAccess = FileAccess.open(SV.RUTA, FileAccess.WRITE)
	f.store_string(JSON.stringify(datos))
	f.close()
	# Agotar stock antes de cargar: la carga v3 lo debe restablecer.
	t.cargar_estado({"version": 1, "tiendas": {"tienda_bram": {"espada_corta": 0}}})
	_check(_stock_cantidad(t, "tienda_bram", "espada_corta") == 0,
		"save v3: stock forzado a 0")
	_check(s.cargar(), "save v3: cargar() true sin bloque tiendas")
	_check(_stock_cantidad(t, "tienda_bram", "espada_corta") == 3,
		"save v3: stock completo desde datos",
		str(_stock_cantidad(t, "tienda_bram", "espada_corta")))


## --- PanelTienda (UI): arranca oculto; mostrar() seguro ---


func _t_panel() -> void:
	var pt: PanelTienda = PT.new()
	root.add_child(pt)
	_basura.append(pt)
	_check(not pt.esta_abierta(), "panel: arranca oculto")
	pt.mostrar(null, null)
	_check(not pt.esta_abierta(), "panel: mostrar(null, null) no revienta")
	var t: Tienda = _tienda()
	var p: Player = _player(Vector3.ZERO)
	pt.conectar(p)
	# NPC sin tienda (ilya): no revienta y NO se abre.
	pt.mostrar(t, _npc("ilya", Vector3(5, 0, 5)))
	_check(not pt.esta_abierta(), "panel: npc sin tienda no abre")
	# NPC vendedor (bram): se abre con su tienda.
	var bram: NPC = _npc("bram", Vector3(-5, 0, 5))
	pt.mostrar(t, bram)
	_check(pt.esta_abierta(), "panel: bram abre su tienda")
	_check(pt.tienda_id_actual() == "tienda_bram",
		"panel: tienda_id_actual = tienda_bram")
	# ESC cierra (consumido en _input antes que el Player).
	var esc: InputEventAction = InputEventAction.new()
	esc.action = "cancelar_seleccion"
	esc.pressed = true
	pt._input(esc)
	_check(not pt.esta_abierta(), "panel: ESC cierra")


## --- VentanaDialogo: flujo "Comerciar" solo con NPC vendedor ---


func _t_dialogo_comerciar() -> void:
	# Con NPC vendedor: hay botón de comerciar y la señal se emite.
	var d: VentanaDialogo = DLG.new()
	root.add_child(d)
	_basura.append(d)
	var bram: NPC = _npc("bram", Vector3(-5, 0, 5))
	d.mostrar(bram)
	_check(d.tiene_comerciar(), "dialogo: bram muestra Comerciar")
	d.comerciar_solicitado.connect(_al_comerciar)
	d._al_comerciar()
	_check(_comerciados.size() == 1 and _comerciados[0] == bram,
		"dialogo: comerciar emite la señal con el npc")
	_check(not d.esta_abierta(), "dialogo: comerciar cierra el dialogo")
	# Con NPC no vendedor (ilya): sin botón de comerciar (fase 6 intacta).
	var d2: VentanaDialogo = DLG.new()
	root.add_child(d2)
	_basura.append(d2)
	d2.mostrar(_npc("ilya", Vector3(5, 0, 5)))
	_check(not d2.tiene_comerciar(), "dialogo: ilya sin boton Comerciar")
	_check(d2.titulo_texto() == "Mariscala Ilya Voss",
		"dialogo: ilya muestra su nombre (fase 6 intacta)")
	d2.cerrar()
