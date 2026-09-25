extends SceneTree
## Tests headless de la Fase 45 (minería).
##
## (a) Datos: 12 vetas generadas, 6 minerales en el catálogo, las 10 regiones
##     cubiertas, dentro del mundo y fuera de las ciudades, usos/respawn/xp
##     dentro de los valores decididos.
## (b) Veta: 3 usos, se agota y oculta (cuerpo + colisión), reaparece a los
##     180 s, aviso flotante, no combatible (REGLA DURA fase 5.1).
## (c) Lógica `Mineria`: motivos de `puede_minar`, entrega mineral + XP,
##     consume un uso, NO da oro y NO toca stats, sin materiales gratis.
## (d) Jugador: clic selecciona, segundo clic → MINAR, lejos queda minado
##     pendiente y al llegar mina, E mina, la veta nunca es objetivo de ataque.
## (e) `GestorVetas`: colocación por radio con histéresis, estado de las vetas
##     leanas, señales.
## (f) Save: bloque `mineria` (v13) conserva usos y respawn; una partida vieja
##     (sin bloque) deja las vetas intactas.
## (g) Rendimiento: la veta en reposo no se procesa y comparte mallas y
##     materiales entre vetas del mismo mineral.
##
## Cómo correrlo:
##   godot --headless --path <proyecto> --script res://tests/test_fase45_mineria.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const VT: GDScript = preload("res://scripts/mundo/veta.gd")
const MN: GDScript = preload("res://scripts/mundo/mineria.gd")
const GV: GDScript = preload("res://scripts/mundo/gestor_vetas.gd")
const SS: GDScript = preload("res://scripts/save/save_system.gd")
const TR: GDScript = preload("res://scripts/mundo/terreno.gd")

const TOTAL_VETAS: int = 12
const MINERALES: Array[String] = ["mineral_cobre", "mineral_hierro",
	"mineral_plata", "mineral_obsidiana", "mineral_cristal", "mineral_esmeralda"]
## Centros de las 9 ciudades (los mismos que tools/generar_vetas.py).
const CIUDADES: Array[Vector2] = [Vector2(0, 0), Vector2(9966, 0),
	Vector2(-9966, 0), Vector2(0, -5358), Vector2(0, 9966), Vector2(9966, -9966),
	Vector2(-9966, -9966), Vector2(-9966, 9966), Vector2(9966, 9966)]
const R_MIN_CIUDAD: float = 900.0
const MEDIO_MUNDO: float = 18432.0

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 45 — minería")
	ItemDB.cargar()
	VetaDB.cargar()


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_datos()
	_test_veta()
	_test_logica()
	_test_jugador()
	_test_gestor()
	_test_save()
	_test_rendimiento()
	print("[TEST] fase45_mineria: %d ok, %d fallos" % [_ok, _fallos])
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


func _jugador(nivel: int = 1) -> Player:
	var p: Player = PL.new()
	p.fijar_identidad("H", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	p.nivel = nivel
	p.gastar_oro(0)
	p.ganar_oro(500)
	return p


## Veta de un id real del JSON, en el árbol (para que `_ready` la construya).
func _veta(veta_id: String) -> Veta:
	var v: Veta = VT.new()
	v.name = "VetaTest"
	v.configurar(VetaDB.obtener(veta_id))
	root.add_child(v)
	_basura.append(v)
	return v


func _gestor(p: Player) -> GestorVetas:
	var g: GestorVetas = GV.new()
	g.name = "GestorVetasTest"
	root.add_child(g)
	_basura.append(g)
	g.configurar_desde_datos()
	g.fijar_jugador(p)
	return g


## Distancia de un punto al centro de ciudad más cercano (los 9 centros,
## los mismos que tools/generar_vetas.py).
func d_ciudad_a(p: Vector2) -> float:
	var d: float = INF
	for c in CIUDADES:
		d = minf(d, p.distance_to(c))
	return d


## (a) Datos: el generador y el catálogo.
func _test_datos() -> void:
	_chk(VetaDB.ids().size() == TOTAL_VETAS + 1,
		"a: hay 12 vetas de distribución + 1 de prueba",
		"hay %d" % VetaDB.ids().size())
	var regiones: Dictionary = {}
	var minerales: Dictionary = {}
	var prueba: int = 0
	var distribucion: int = 0
	for vid in VetaDB.ids():
		var v: Dictionary = VetaDB.obtener(vid)
		_chk(not v.is_empty(), "a: la veta " + vid + " existe en el JSON")
		_chk(int(v.get("usos", 0)) == 3, "a: " + vid + " tiene 3 usos")
		_chk(is_equal_approx(float(v.get("respawn_s", 0.0)), 180.0),
			"a: " + vid + " reaparece a los 180 s")
		var xp: int = int(v.get("xp", 0))
		_chk(xp >= 5 and xp <= 12, "a: " + vid + " da XP 5-12", "xp=%d" % xp)
		_chk(int(v.get("cantidad", 0)) >= 1 and int(v.get("cantidad", 0)) <= 3,
			"a: " + vid + " entrega 1-3 minerales")
		_chk(int(v.get("nivel", 0)) >= 1, "a: " + vid + " tiene gate de nivel")
		_chk(str(v.get("nombre", "")) != "", "a: " + vid + " tiene nombre")
		var iid: String = str(v.get("item_id", ""))
		minerales[iid] = true
		_chk(ItemDB.existe(iid), "a: el mineral " + iid + " está en el catálogo")
		var it: Dictionary = ItemDB.obtener(iid)
		_chk(str(it.get("tipo", "")) == "material",
			"a: " + iid + " es tipo material")
		_chk(bool(it.get("apilable", false)),
			"a: " + iid + " apila (si no, la mochila se llena minando)")
		var x: float = float(v.get("x", 0.0))
		var z: float = float(v.get("z", 0.0))
		_chk(absi(x) <= MEDIO_MUNDO and absi(z) <= MEDIO_MUNDO,
			"a: " + vid + " está dentro del mundo 36.864 u")
		# La veta de prueba de la plaza está DENTRO de la ciudad a propósito
		# (fase 45.1, como el pack de mobs de prueba): se exime de la regla
		# de distribución, igual que aquel.
		if str(v.get("grupo", "")) == "prueba_mineria":
			prueba += 1
			_chk(d_ciudad_a(Vector2(x, z)) < R_MIN_CIUDAD,
				"a: la veta de prueba sí está en la plaza (para verla al abrir)")
			_chk(int(v.get("nivel", 0)) == 1, "a: la veta de prueba es de nivel 1")
		else:
			distribucion += 1
			_chk(d_ciudad_a(Vector2(x, z)) >= R_MIN_CIUDAD,
				"a: " + vid + " no está dentro de una ciudad")
		regiones[str(v.get("region", ""))] = true
	_chk(regiones.size() == 10, "a: las 10 regiones tienen veta",
		"hay %d" % regiones.size())
	_chk(distribucion == TOTAL_VETAS, "a: 12 vetas de distribución",
		"hay %d" % distribucion)
	_chk(prueba == 1, "a: 1 veta de prueba en la plaza")
	_chk(minerales.size() == MINERALES.size(),
		"a: 6 minerales distintos", "hay %d" % minerales.size())
	for m in MINERALES:
		_chk(minerales.has(m), "a: está el mineral " + m)
	_chk(VetaDB.existe("veta_inexistente") == false, "a: id inexistente = false")
	_chk(VetaDB.obtener("veta_inexistente").is_empty(), "a: id inexistente = {}")
	_chk(VetaDB.vetas_de_region("velo").size() == 1, "a: el Velo tiene 1 veta")
	_chk(VetaDB.vetas_de_region("").size() == TOTAL_VETAS + 1, "a: region \"\" = todas")
	# Posiciones del JSON = posiciones de la DB (contrato con el generador).
	var pos: Vector3 = VetaDB.posicion_de("veta_moon_town_mineral_cobre")
	var d: Dictionary = VetaDB.obtener("veta_moon_town_mineral_cobre")
	_chk(is_equal_approx(pos.x, float(d.get("x", 0.0)))
		and is_equal_approx(pos.z, float(d.get("z", 0.0)))
		and is_zero_approx(pos.y), "a: posicion_de devuelve (x, 0, z) del JSON")


## (b) La veta como nodo: usos, agotamiento, respawn, aviso, no combatible.
func _test_veta() -> void:
	var v: Veta = _veta("veta_moon_town_mineral_cobre")
	_chk(v.veta_id == "veta_moon_town_mineral_cobre", "b: la veta toma su id")
	_chk(v.item_id == "mineral_cobre", "b: entrega cobre")
	_chk(v.cantidad == 1, "b: el cobre de Moon Town da 1 por golpe")
	_chk(v.xp == 5, "b: el cobre de Moon Town da 5 XP")
	_chk(v.usos == 3 and v.usos_max == 3, "b: empieza con 3 usos")
	_chk(v.esta_minable(), "b: recién construida es minable")
	_chk(v.esta_vivo(), "b: una veta nunca muere (no es Entity en combate)")
	_chk(v.combatible == false, "b: REGLA DURA: la veta no es combatible")
	_chk(v.get_node_or_null("Cuerpo") != null, "b: tiene nodo Cuerpo (para GLB)")
	_chk(v.get_node_or_null("Colision") != null, "b: tiene nodo Colision")
	_chk(v.get_node_or_null("Aviso") != null, "b: tiene nodo Aviso")
	_chk(v.collision_layer == Veta.CAPA, "b: capa 4 = la que ve el raycast del clic")
	_chk(v.is_in_group("vetas"), "b: está en el grupo vetas")
	# Ignora el daño por completo (como los NPCs, fase 5.1).
	var vida0: float = v.vida_actual
	v.take_damage(999.0, null)
	_chk(is_equal_approx(v.vida_actual, vida0), "b: no recibe daño")
	_chk(v.esta_vivo(), "b: no se muere por daño")
	# Agotamiento: 3 usos y el cuerpo + la colisión se apagan.
	v.consumir_uso()
	_chk(v.usos_restantes() == 2, "b: queda 1 uso menos", "usos=%d" % v.usos)
	_chk(v.esta_minable(), "b: sigue minable con usos")
	_chk(v.visible, "b: con usos sigue visible")
	v.consumir_uso()
	v.consumir_uso()
	_chk(not v.esta_minable(), "b: a los 3 usos se agota")
	_chk(v.usos_restantes() == 0, "b: 0 usos")
	_chk(v.visible == false, "b: agotada = cuerpo oculto")
	_chk(not v.colision_activa(),
		"b: agotada = sin colisión (el clic no la encuentra)")
	_chk(is_equal_approx(v.segundos_para_reaparecer(), 180.0),
		"b: arranca la cuenta atrás de 180 s")
	# Respawn: ni antes ni un frame de más.
	v.tick(179.0)
	_chk(not v.esta_minable(), "b: a los 179 s sigue agotada")
	_chk(is_equal_approx(v.segundos_para_reaparecer(), 1.0),
		"b: le queda 1 s")
	v.tick(1.0)
	_chk(v.esta_minable(), "b: a los 180 s vuelve")
	_chk(v.usos_restantes() == 3, "b: vuelve con los 3 usos")
	_chk(v.segundos_para_reaparecer() == 0.0, "b: reloj a cero")
	_chk(v.visible, "b: vuelve a verse")
	# Aviso flotante: se crea una vez y se oculta solo.
	v.mostrar_aviso("+1 Mineral de Cobre (+5 XP)")
	_chk(v.aviso_actual() == "+1 Mineral de Cobre (+5 XP)", "b: el aviso se muestra")
	_chk((v.get_node("Aviso") as Label3D).visible, "b: el Label3D es visible")
	v.tick(Veta.AVISO_DURACION + 0.1)
	_chk(v.aviso_actual() == "", "b: el aviso se oculta solo")
	_chk((v.get_node("Aviso") as Label3D).visible == false, "b: Label3D oculto")
	# Señales de la veta.
	var visto_agotada: Array[String] = []
	var visto_reaparecida: Array[String] = []
	v.agotada.connect(func(id: String) -> void: visto_agotada.append(id))
	v.reaparecida.connect(func(id: String) -> void: visto_reaparecida.append(id))
	for i in range(3):
		v.consumir_uso()
	v.tick(180.0)
	_chk(visto_agotada.size() == 1, "b: emite `agotada` una sola vez")
	_chk(visto_reaparecida.size() == 1, "b: emite `reaparecida`")
	# Idempotencia: se vuelve a agotar (2a vez) y consumir SIN usos ya no hace
	# nada ni re-emite señales.
	for i in range(3):
		v.consumir_uso()
	_chk(v.usos_restantes() == 0, "b: se vuelve a agotar")
	_chk(visto_agotada.size() == 2, "b: `agotada` se emite una vez por agotamiento",
		"emitida %d veces" % visto_agotada.size())
	v.consumir_uso()
	_chk(v.usos_restantes() == 0, "b: consumir sin usos es inocuo")
	_chk(visto_agotada.size() == 2, "b: no re-emite `agotada`")
	# Guardado de la veta (bloque de la partida).
	v.tick(180.0)
	_chk(v.usos_restantes() == 3, "b: repuesta antes de probar el guardado")
	v.consumir_uso()
	v.consumir_uso()
	var d: Dictionary = v.to_dict()
	_chk(str(d.get("veta_id", "")) == v.veta_id, "b: to_dict guarda el id")
	_chk(int(d.get("usos", -1)) == 1, "b: to_dict guarda los usos")
	# Instanciar por id (la vía que usa el gestor).
	var v2: Veta = VT.new()
	_basura.append(v2)
	_chk(v2.configurar_por_id("veta_velo_mineral_cristal_2"), "b: configurar_por_id ok")
	root.add_child(v2)
	_chk(v2.veta_id == "veta_velo_mineral_cristal_2", "b: tomó el id pedido")
	_chk(v2.configurar_por_id("veta_inexistente") == false, "b: id inexistente = false")


## (c) `Mineria`: las reglas.
func _test_logica() -> void:
	var p: Player = _jugador(30)
	var m: Mineria = MN.new()
	var v: Veta = _veta("veta_moon_town_mineral_cobre")
	var minados: Array = []
	m.minado.connect(func(vid: String, iid: String, cant: int, xp: int) -> void:
		minados.append([vid, iid, cant, xp]))
	_chk(m.puede_minar(v, p) == "ok", "c: puede_minar = ok")
	_chk(m.puede_minar(null, p) == "veta_nula", "c: veta nula")
	_chk(m.puede_minar(v, null) == "veta_nula", "c: jugador nulo")
	# Gate de nivel: la veta de nivel 45 con un herrero de nivel 1.
	var v_velo: Veta = _veta("veta_velo_mineral_cristal_2")
	_chk(v_velo.nivel_min >= 45, "c: la veta del Velo pide nivel 45",
		"nivel=%d" % v_velo.nivel_min)
	_chk(m.puede_minar(v_velo, p) == "nivel", "c: nivel insuficiente")
	var p1: Player = _jugador(1)
	_chk(m.puede_minar(v_velo, p1) == "nivel", "c: nivel 1 no puede en el Velo")
	_chk(m.puede_minar(v, p1) == "ok", "c: nivel 1 sí puede en Moon Town")
	# Minar: entrega mineral + XP y gasta un uso.
	var xp0: int = p.xp_actual
	var oro0: int = p.oro
	var atk0: float = p.stats.ataque
	var vida_max0: float = p.stats.vida_max
	_chk(m.minar(v, p) == "ok", "c: minar = ok")
	_chk(p.inventario.contar("mineral_cobre") == 1, "c: entra 1 mineral")
	_chk(p.xp_actual == xp0 + 5, "c: +5 XP", "xp=%d" % p.xp_actual)
	_chk(p.oro == oro0, "c: minar NO da oro (el oro es de las recetas)")
	_chk(is_equal_approx(p.stats.ataque, atk0), "c: minar NO toca stats")
	_chk(is_equal_approx(p.stats.vida_max, vida_max0), "c: NO cambia vida_max")
	_chk(v.usos_restantes() == 2, "c: gastó 1 uso")
	_chk(v.aviso_actual() == "+1 Mineral de Cobre (+5 XP)", "c: aviso con item y XP")
	_chk(minados.size() == 1, "c: emite `minado`")
	_chk(str((minados[0] as Array)[1]) == "mineral_cobre", "c: el evento lleva el item")
	# Acumula: el mineral es apilable, entra en la misma pila.
	m.minar(v, p)
	_chk(p.inventario.contar("mineral_cobre") == 2, "c: el mineral apila")
	_chk(p.inventario.slots_usados() == 1, "c: 2 minerales = 1 solo slot")
	# Agotar: el tercer golpe la deja sin usos y no se puede seguir.
	m.minar(v, p)
	_chk(not v.esta_minable(), "c: se agotó al tercer golpe")
	_chk(m.puede_minar(v, p) == "agotada", "c: agotada")
	_chk(m.minar(v, p) == "agotada", "c: no se puede minar agotada")
	_chk(p.inventario.contar("mineral_cobre") == 3, "c: 3 minerales (nada gratis de más)")
	_chk(m.puede_minar(v, p1) == "agotada", "c: la veta agotada gana al nivel")
	# Inventario lleno: no se gasta el uso.
	var p_lleno: Player = _jugador(30)
	# Un item DISTINTO por slot (los apilables también ocupan uno la primera
	# vez): 19 slots de los 20 = "inventario_lleno".
	var relleno: Array[String] = ["daga_gastada", "espada_corta", "espada_hierro",
		"armadura_tela", "armadura_cuero", "cota_malla", "maza_ogro",
		"verdugo_eco", "escudo_madera", "casco_cuero", "guantes_cuero",
		"botas_cuero", "collar_cobre", "pendiente_luna", "pendiente_sol",
		"anillo_poder", "anillo_sabio", "amuleto_guardian", "pocion_vida"]
	for iid in relleno:
		p_lleno.inventario.agregar(iid, 1)
	_chk(p_lleno.inventario.slots_usados() == 19, "c: 19 de 20 slots usados",
		"usados=%d" % p_lleno.inventario.slots_usados())
	var v2: Veta = _veta("veta_moon_town_mineral_hierro")
	_chk(m.puede_minar(v2, p_lleno) == "inventario_lleno", "c: mochila llena = no")
	_chk(m.minar(v2, p_lleno) == "inventario_lleno", "c: no entra con la mochila llena")
	_chk(v2.usos_restantes() == 3, "c: no gasta el uso si no puede entregar")
	_chk(p_lleno.inventario.contar("mineral_hierro") == 0, "c: no entra el mineral")
	# Con 3 slots libres sí entra (el umbral).
	p_lleno.inventario.quitar("pocion_vida", 1)
	p_lleno.inventario.quitar("pendiente_sol", 1)
	p_lleno.inventario.quitar("anillo_sabio", 1)
	_chk(p_lleno.inventario.slots_usados() == 16, "c: 16 de 20 slots usados",
		"usados=%d" % p_lleno.inventario.slots_usados())
	_chk(m.puede_minar(v2, p_lleno) == "ok", "c: con hueco vuelve a poder")
	# Textos de motivo (los muestra el mundo).
	_chk(Mineria.texto_motivo("agotada") == "La veta está agotada", "c: texto agotada")
	_chk(Mineria.texto_motivo("ok") == "Puedes minar", "c: texto ok")
	_chk(Mineria.texto_minado("mineral_cobre", 2, 9) == "+2 Mineral de Cobre (+9 XP)",
		"c: texto del minado")
	_chk(Mineria.texto_minado("mineral_cobre", 1, 0) == "+1 Mineral de Cobre",
		"c: sin XP no lo pone")


## (d) El jugador: seleccionar, caminar y minar con el mismo idioma que los NPCs.
func _test_jugador() -> void:
	var p: Player = _jugador(30)
	var v: Veta = _veta("veta_moon_town_mineral_cobre")
	v.global_position = p.global_position + Vector3(50.0, 0.0, 0.0)
	var minados: Array = []
	p.minar_solicitado.connect(func(vt: Veta) -> void: minados.append(vt))
	# Primer clic: seleccionar (igual que un mob o un NPC).
	_chk(p._resolver_clic_entidad(v) == Player.AccionClic.SELECCIONAR,
		"d: primer clic en la veta = SELECCIONAR")
	p._aplicar_clic(v, p._resolver_clic_entidad(v))
	_chk(p.seleccion == v, "d: queda seleccionada")
	_chk(p.objetivo_ataque == null, "d: seleccionar no fija objetivo de ataque")
	# Segundo clic estando lejos: minado pendiente y camina hacia ella.
	_chk(p._resolver_clic_entidad(v) == Player.AccionClic.MINAR,
		"d: segundo clic = MINAR")
	p._aplicar_clic(v, p._resolver_clic_entidad(v))
	_chk(p.tiene_minado_pendiente(), "d: con la veta lejos queda pendiente")
	_chk(minados.is_empty(), "d: todavía no mina (está lejos)")
	_chk(p._tiene_destino, "d: camina hacia la veta")
	_chk(p.objetivo_ataque == null, "d: minar NUNCA fija objetivo de ataque")
	# Al llegar (la movemos al lado) dispara el minado pendiente.
	v.global_position = p.global_position + Vector3(1.0, 0.0, 0.0)
	p._actualizar_minado_pendiente()
	_chk(minados.size() == 1, "d: al llegar mina solo", "minados=%d" % minados.size())
	_chk(not p.tiene_minado_pendiente(), "d: el pendiente se limpia")
	# Cerca: el segundo clic mina al instante.
	p.deseleccionar()
	_chk(p._resolver_clic_entidad(v) == Player.AccionClic.SELECCIONAR,
		"d: tras deseleccionar vuelve a SELECCIONAR")
	p.seleccionar(v)
	_chk(p._resolver_clic_entidad(v) == Player.AccionClic.MINAR, "d: MINAR de nuevo")
	p._aplicar_clic(v, p._resolver_clic_entidad(v))
	_chk(minados.size() == 2, "d: cerca mina directo")
	_chk(not p.tiene_minado_pendiente(), "d: cerca no queda pendiente")
	# La tecla E con la veta seleccionada mina (no habla).
	var hablado: Array = []
	p.hablar_con.connect(func(n: NPC) -> void: hablado.append(n))
	p.interactuar()
	_chk(minados.size() == 3, "d: E mina la veta")
	_chk(hablado.is_empty(), "d: E en una veta NO habla")
	# E con un NPC sigue hablando (no se rompió la fase 9).
	var npc: NPC = preload("res://scripts/npc/npc.gd").new()
	root.add_child(npc)
	_basura.append(npc)
	npc.configurar({"id": "bram", "nombre": "Bram"})
	npc.global_position = p.global_position + Vector3(1.0, 0.0, 0.0)
	p.seleccionar(npc)
	p.interactuar()
	_chk(hablado.size() == 1, "d: E en un NPC sigue hablando")
	_chk(not p.tiene_minado_pendiente(), "d: un NPC no genera minado pendiente")
	# Nunca es objetivo de ataque (ni con T ni con un skill hostil).
	p.seleccionar(v)
	p.solicitar_ataque()
	_chk(p.objetivo_ataque == null, "d: una veta nunca es objetivo de ataque")
	_chk(p._foco_combate() == null, "d: la veta no es foco de combate")
	var skills: Array[String] = SkillDB.lista()
	if not skills.is_empty():
		p.lanzar_skill_id(skills[0])
	_chk(p.objetivo_ataque == null, "d: un skill no fija la veta como objetivo")
	# Veta agotada: no se puede minar y el jugador la suelta solo.
	for i in range(3):
		v.consumir_uso()
	_chk(p._resolver_clic_entidad(v) == Player.AccionClic.NADA,
		"d: veta agotada = NADA (ni hablar ni minar)")
	p.interactuar()
	_chk(minados.size() == 3, "d: E en una veta agotada no mina")
	# Cancelaciones del minado pendiente.
	var v3: Veta = _veta("veta_moon_town_mineral_hierro")
	v3.global_position = p.global_position + Vector3(80.0, 0.0, 0.0)
	p.deseleccionar()
	p.seleccionar(v3)
	p._acercarse_a_veta(v3)
	_chk(p.tiene_minado_pendiente(), "d: pendiente de nuevo")
	p.deseleccionar()
	_chk(not p.tiene_minado_pendiente(), "d: ESC cancela el minado pendiente")
	p.seleccionar(v3)
	p._acercarse_a_veta(v3)
	_chk(p.tiene_minado_pendiente(), "d: pendiente otra vez")
	Input.action_press("mover_adelante")
	p._construir_intent()
	Input.action_release("mover_adelante")
	_chk(not p.tiene_minado_pendiente(), "d: el WASD cancela el minado pendiente")
	_chk(not p._tiene_destino, "d: el WASD también suelta la orden de caminar")
	# Veta liberada (queue_free) con un pendiente vivo: no revienta.
	p.seleccionar(v3)
	p._acercarse_a_veta(v3)
	v3.free()
	_basura.erase(v3)
	_chk(not p.tiene_minado_pendiente(),
		"d: la veta liberada se lee como null: el pendiente se limpia solo")
	p._actualizar_minado_pendiente()
	_chk(not p.tiene_minado_pendiente(), "d: y no vuelve a aparecer")
	_chk(minados.size() == 3, "d: no minó ninguna vez más")


## (e) `GestorVetas`: colocación, estado y señales.
func _test_gestor() -> void:
	var p: Player = _jugador(30)
	var g: GestorVetas = _gestor(p)
	_chk(g.conteo_registros() == TOTAL_VETAS + 1, "e: registra las 13 vetas",
		"hay %d" % g.conteo_registros())
	_chk(g.conteo_vetas() == 0, "e: sin instanciar, 0 nodos")
	# En la plaza de Moon Town solo aparece la veta de prueba (fase 45.1).
	p.global_position = Vector3(0.0, 0.0, 45.0)
	g.actualizar()
	_chk(g.conteo_vetas() == 1, "e: en la plaza, 1 veta (la de prueba)",
		"hay %d" % g.conteo_vetas())
	_chk(g.veta("veta_prueba_cobre") != null, "e: es la de prueba de la plaza")
	# Lejos de toda veta: ninguna entra en el mapa.
	p.global_position = Vector3(5000.0, 0.0, 0.0)
	g.actualizar()
	_chk(g.conteo_vetas() == 0, "e: sin vetas cerca, 0 nodos")
	# Junto a la veta de cobre de Moon Town: solo esa.
	var d: Dictionary = VetaDB.obtener("veta_moon_town_mineral_cobre")
	p.global_position = Vector3(float(d.get("x", 0.0)), 0.0, float(d.get("z", 0.0)))
	g.actualizar()
	_chk(g.conteo_vetas() == 1, "e: 1 veta en el mapa", "hay %d" % g.conteo_vetas())
	var v: Veta = g.veta("veta_moon_town_mineral_cobre")
	_chk(v != null, "e: el nodo existe")
	_chk(v.get_parent() == g, "e: el nodo cuelga del gestor")
	# La Y sale del terreno, no del JSON (aquí sin terreno: y = 0).
	_chk(is_equal_approx(v.global_position.y, 0.0), "e: sin terreno, y = 0")
	# Con terreno: la veta se pega al suelo.
	var terreno: Terreno = TR.new()
	root.add_child(terreno)
	_basura.append(terreno)
	terreno.cargar_datos()
	g.fijar_terreno(terreno)
	g.actualizar()
	var v2: Veta = g.veta("veta_moon_town_mineral_cobre")
	_chk(is_equal_approx(v2.global_position.y, terreno.altura_en(v2.global_position.x, v2.global_position.z)),
		"e: con terreno, la veta se pega al suelo", "y=%f" % v2.global_position.y)
	# Minar por id (la vía del mundo y de los tests).
	var m: Mineria = MN.new()
	_chk(m.puede_minar(v2, p) == "ok", "e: la veta del gestor es minable")
	_chk(g.minar("veta_moon_town_mineral_cobre", p) == "ok", "e: minar por id")
	_chk(p.inventario.contar("mineral_cobre") == 1, "e: el mineral llega")
	_chk(g.minar("veta_inexistente", p) == "veta_nula", "e: id inexistente = veta_nula")
	# Señales del gestor.
	var eventos: Array = []
	g.minado.connect(func(vid: String, iid: String, cant: int, xp: int) -> void:
		eventos.append(["minado", vid]))
	g.veta_agotada.connect(func(vid: String) -> void: eventos.append(["agotada", vid]))
	g.veta_reaparecida.connect(func(vid: String) -> void: eventos.append(["reaparecida", vid]))
	g.minar("veta_moon_town_mineral_cobre", p)
	g.minar("veta_moon_town_mineral_cobre", p)
	_chk(eventos.size() == 2, "e: dos minados", "hay %d" % eventos.size())
	g.minar("veta_moon_town_mineral_cobre", p)
	_chk(str((eventos[2] as Array)[0]) == "agotada", "e: al tercero se agota")
	_chk(str((eventos[2] as Array)[1]) == "veta_moon_town_mineral_cobre", "e: id correcto")
	v2.tick(180.0)
	_chk(str((eventos[3] as Array)[0]) == "reaparecida", "e: a los 180 s reaparece")
	# La veta más cercana.
	_chk(g.veta_minable_mas_cercana() == "veta_moon_town_mineral_cobre",
		"e: veta_minable_mas_cercana")
	var agotada: Veta = g.veta("veta_moon_town_mineral_cobre")
	agotada.consumir_uso()
	agotada.consumir_uso()
	agotada.consumir_uso()
	_chk(g.veta_minable_mas_cercana() == "", "e: agotada no es candidata")
	# Histéresis: sale a más de RADIO_BAJA (no a RADIO_ALTA).
	p.global_position = Vector3(0.0, 0.0, 0.0)
	p.global_position = Vector3(0.0, 0.0, 0.0) + Vector3(GestorVetas.RADIO_ALTA + 10.0, 0.0, 0.0)
	g.actualizar()
	_chk(g.conteo_vetas() == 1, "e: entre ALTA y BAJA sigue en el mapa (histéresis)")
	p.global_position = Vector3(GestorVetas.RADIO_BAJA + 50.0, 0.0, 0.0)
	g.actualizar()
	_chk(g.conteo_vetas() == 0, "e: más allá de BAJA se libera")
	_chk(g.veta("veta_moon_town_mineral_cobre") == null, "e: el nodo ya no está")


## (f) Save v13: el bloque `mineria` conserva usos y respawn.
func _test_save() -> void:
	_chk(SaveSystem.SAVE_VERSION == 13, "f: save v13", "es v%d" % SaveSystem.SAVE_VERSION)
	var p: Player = _jugador(30)
	var g: GestorVetas = _gestor(p)
	p.global_position = Vector3(0.0, 0.0, 0.0)
	var d: Dictionary = VetaDB.obtener("veta_moon_town_mineral_cobre")
	p.global_position = Vector3(float(d.get("x", 0.0)), 0.0, float(d.get("z", 0.0)))
	g.actualizar()
	_chk(g.conteo_vetas() == 1, "f: la veta está en el mapa")
	# Agota la veta a un uso del final y deja una cuenta atrás corriendo.
	var v: Veta = g.veta("veta_moon_town_mineral_cobre")
	g.minar("veta_moon_town_mineral_cobre", p)
	g.minar("veta_moon_town_mineral_cobre", p)
	_chk(v.usos_restantes() == 1, "f: queda 1 uso")
	var ss: SaveSystem = SS.new()
	ss.jugador = p
	ss.mineria = g
	var estado: Dictionary = g.estado_para_guardar()
	_chk(int(estado.get("version", 0)) == GestorVetas.SAVE_VERSION, "f: bloque versionado")
	var vetas: Dictionary = estado.get("vetas", {})
	# Guardado mínimo: solo lo que se ha tocado. Una veta sin usar está en
	# sus 3 usos por definición y `data/vetas.json` ya la describe.
	_chk(vetas.size() == 1, "f: guarda solo la veta minada (guardado mínimo)",
		"hay %d" % vetas.size())
	_chk(vetas.has("veta_moon_town_mineral_cobre"), "f: guarda la veta correcta")
	_chk(int((vetas["veta_moon_town_mineral_cobre"] as Dictionary).get("usos", -1)) == 1,
		"f: guarda los usos que quedan")
	_chk(ss.guardar(), "f: guardar() devuelve true")
	# Nueva partida: la veta vuelve con 1 uso.
	var p2: Player = _jugador(30)
	var g2: GestorVetas = _gestor(p2)
	p2.global_position = p.global_position
	g2.actualizar()
	var ss2: SaveSystem = SS.new()
	ss2.jugador = p2
	ss2.mineria = g2
	_chk(ss2.cargar(), "f: cargar() devuelve true")
	var v2: Veta = g2.veta("veta_moon_town_mineral_cobre")
	_chk(v2.usos_restantes() == 1, "f: la veta vuelve con 1 uso",
		"usos=%d" % v2.usos_restantes())
	_chk(v2.esta_minable(), "f: sigue minable")
	# Agotada a mitad de respawn: la cuenta atrás también viaja.
	for i in range(1):
		g2.minar("veta_moon_town_mineral_cobre", p2)
	_chk(not v2.esta_minable(), "f: se agotó")
	_chk(is_equal_approx(v2.segundos_para_reaparecer(), 180.0), "f: respawn a 180 s")
	v2.tick(60.0)
	_chk(is_equal_approx(v2.segundos_para_reaparecer(), 120.0), "f: quedan 120 s")
	ss2.guardar()
	var p3: Player = _jugador(30)
	var g3: GestorVetas = _gestor(p3)
	p3.global_position = p.global_position
	g3.actualizar()
	var ss3: SaveSystem = SS.new()
	ss3.jugador = p3
	ss3.mineria = g3
	ss3.cargar()
	var v3: Veta = g3.veta("veta_moon_town_mineral_cobre")
	_chk(not v3.esta_minable(), "f: la veta agotada sigue agotada al cargar")
	_chk(is_equal_approx(v3.segundos_para_reaparecer(), 120.0),
		"f: la cuenta atrás sigue donde estaba", "quedan %.1f" % v3.segundos_para_reaparecer())
	_chk(v3.visible == false, "f: agotada = oculta al cargar")
	_chk(not v3.colision_activa(), "f: agotada = sin colisión al cargar")
	v3.tick(120.0)
	_chk(v3.esta_minable(), "f: y vuelve a los 180 s exactos")
	# Veta lejana (sin nodo): su estado no se pierde al alejarse y al volver.
	var pos_veta: Vector3 = g.veta("veta_moon_town_mineral_cobre").global_position
	p.global_position = pos_veta + Vector3(GestorVetas.RADIO_BAJA + 50.0, 0.0, 0.0)
	g.actualizar()
	_chk(g.conteo_vetas() == 0, "f: la veta se liberó")
	_chk((g.estado_para_guardar().get("vetas", {}) as Dictionary)
		.has("veta_moon_town_mineral_cobre"),
		"f: la veta lejana también se guarda (en _lejanas)")
	var g4: GestorVetas = _gestor(p)
	p.global_position = pos_veta + Vector3(0.0, 0.0, 4000.0)
	g4.actualizar()
	_chk(g4.conteo_vetas() == 0, "f: lejos de la veta no hay nodo")
	g4.cargar_estado(g.estado_para_guardar())
	p.global_position = pos_veta
	g4.actualizar()
	var v4: Veta = g4.veta("veta_moon_town_mineral_cobre")
	_chk(v4 != null, "f: la veta vuelve al mapa")
	_chk(v4.usos_restantes() == 1, "f: y conserva los usos que le quedaban",
		"usos=%d" % v4.usos_restantes())
	# Partida vieja (v12, sin bloque "mineria"): las vetas quedan intactas.
	var p_viejo: Player = _jugador(30)
	var g_viejo: GestorVetas = _gestor(p_viejo)
	p_viejo.global_position = p.global_position
	g_viejo.actualizar()
	_chk(g_viejo.conteo_vetas() == 1, "f: la veta está en el mapa de la partida vieja")
	var ss_viejo: SaveSystem = SS.new()
	ss_viejo.jugador = p_viejo
	ss_viejo.mineria = g_viejo
	escribir_guardado_viejo(p_viejo)
	_chk(ss_viejo.cargar(), "f: una partida v12 (sin bloque) carga igual")
	var v_viejo: Veta = g_viejo.veta("veta_moon_town_mineral_cobre")
	_chk(v_viejo.usos_restantes() == 3,
		"f: sin bloque, la veta conserva sus 3 usos", "usos=%d" % v_viejo.usos_restantes())
	_chk(v_viejo.esta_minable(), "f: y sigue minable")
	# Sistema sin asignar: avisa, no revienta.
	var ss_sin: SaveSystem = SS.new()
	ss_sin.jugador = _jugador(30)
	_chk(ss_sin.guardar(), "f: guardar sin gestor de vetas no revienta")
	var ss_leer: SaveSystem = SS.new()
	ss_leer.jugador = _jugador(30)
	_chk(ss_leer.cargar(), "f: cargar sin gestor de vetas no revienta")
	borrar_partida()


## Escribe una partida con versión 12 y SIN bloque "mineria" (como las de
## antes de la fase 45), para comprobar que la carga las tolera.
func escribir_guardado_viejo(p: Player) -> void:
	var f: FileAccess = FileAccess.open(SaveSystem.RUTA, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"version": 12,
		"jugador": {
			"entidad": p.to_dict(),
			"oro": p.oro,
			"nombre": p.nombre,
			"clase_id": p.clase_id,
			"inventario": p.inventario.to_dict(),
			"equipo": p.equipo.to_dict(),
			"talentos": p.talentos.to_dict(),
			"puntos_atributo": p.puntos_atributo,
			"skills": p.skills.to_dict(),
			"pos": [p.global_position.x, p.global_position.y, p.global_position.z],
		},
		"enemigos": [],
		"npcs": [],
	}))
	f.close()


func borrar_partida() -> void:
	if FileAccess.file_exists(SaveSystem.RUTA):
		DirAccess.remove_absolute(SaveSystem.RUTA)


## (g) Rendimiento: reposo sin procesar y mallas/materiales compartidos.
func _test_rendimiento() -> void:
	# El cache de materiales es estático (vive entre tests): se aísla aquí.
	Veta._materiales.clear()
	var a: Veta = _veta("veta_moon_town_mineral_hierro")
	_chk(a.is_processing() == false, "g: una veta minable NO se procesa")
	a.consumir_uso()
	a.consumir_uso()
	a.consumir_uso()
	_chk(a.is_processing(), "g: agotada SÍ se procesa (cuenta atrás)")
	a.mostrar_aviso("+1")
	a.tick(Veta.AVISO_DURACION + 0.1)
	a.tick(180.0)
	_chk(a.is_processing() == false, "g: repuesta = vuelve a dormirse")
	# Mallas compartidas: dos vetas del mismo mineral, un solo material.
	var b: Veta = _veta("veta_tierras_francas_mineral_hierro_2")
	var c1: MeshInstance3D = a.get_node("Cuerpo") as MeshInstance3D
	var c2: MeshInstance3D = b.get_node("Cuerpo") as MeshInstance3D
	_chk(c1.mesh == c2.mesh, "g: las vetas comparten la malla de la roca")
	_chk(c1.material_override == c2.material_override,
		"g: las vetas del mismo mineral comparten material")
	_chk(Veta._materiales.size() == 1, "g: un material por mineral, no por veta",
		"hay %d" % Veta._materiales.size())
	# Otro mineral = otro material, pero las mallas siguen siendo las mismas.
	var c: Veta = _veta("veta_ceniza_forja_mineral_obsidiana")
	var c3: MeshInstance3D = c.get_node("Cuerpo") as MeshInstance3D
	_chk(c3.mesh == c1.mesh, "g: otro mineral, misma malla compartida")
	_chk(c3.material_override != c1.material_override, "g: otro mineral, otro material")
	_chk(Veta._materiales.size() == 2, "g: 2 materiales para 2 minerales",
		"hay %d" % Veta._materiales.size())
	# Los cristales también son mallas compartidas.
	_chk((a.get_node("Cristal0") as MeshInstance3D).mesh
		== (b.get_node("Cristal0") as MeshInstance3D).mesh,
		"g: los cristales también se comparten")
	# Geometría acotada y contada: roca + 3 cristales + colisión + aviso.
	_chk(a.get_child_count() == 6, "g: 1 roca + 3 cristales + colisión + aviso = 6",
		"hijos=%d" % a.get_child_count())
	# Colisión: esfera compartida, no una por veta.
	_chk((a.get_node("Colision") as CollisionShape3D).shape
		== (b.get_node("Colision") as CollisionShape3D).shape,
		"g: la esfera de colisión también se comparte")
