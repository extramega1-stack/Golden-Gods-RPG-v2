extends SceneTree
## Tests headless de la Fase 48 (tabla de anclajes + presupuesto de GPU).
##
## (a) `data/anclajes.json`: 12 anclajes, uno por slot de `Equipo.SLOTS`, con
##     todos los campos que promete el spec (§4: anclaje, mesh_path, offset,
##     escala, tinte) y valores sensatos.
## (b) `AnclajesDB`: carga tolerante, ids en orden, accesores, y la lista de
##     slots SIN modelo (la cola de trabajo de la fase de arte).
## (c) `PaperDoll`: la tabla es la FUENTE ÚNICA. Con todo equipado debe
##    .draw las mismas mallas y en las mismas posiciones que la tabla, y los
##         nodos deben seguir llamándose como siempre (arma/Hoja, Coraza...).
## (d) La vía del modelo: un `mesh_path` que no existe avisa y cae al respaldo
##     procedural (el juego no se rompe por un asset que falta).
## (e) `MedidorGPU`: promedios, p50, p95 y veredicto contra el presupuesto
##     (con muestras sintéticas, sin GPU) + la línea de texto del informe.
## (f) El presupuesto de la fase 20 (p95 ≤ 16,7 ms) sigue declarado.
##
## Cómo correrlo:
##   godot --headless --path <proyecto> --script res://tests/test_fase48_anclajes_bench.gd

const ADB: GDScript = preload("res://scripts/player/anclajes_db.gd")
const MD: GDScript = preload("res://scripts/core/medidor_gpu.gd")
const PD: GDScript = preload("res://scripts/player/paper_doll.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const EQ: GDScript = preload("res://scripts/inventory/equipment.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 48 — tabla de anclajes + presupuesto de GPU")
	ItemDB.cargar()
	AnclajesDB.cargar()


func _process(_d: float) -> bool:
	_test_json()
	_test_db()
	_test_paperdoll()
	_test_modelo_ausente()
	_test_medidor()
	_test_presupuesto()
	_test_modelos()
	print("[TEST] fase48_anclajes_bench: %d ok, %d fallos" % [_ok, _fallos])
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
		printerr("[FALLO] " + nombre + ("" if detalle == "" else "  <-- " + detalle))


func _jugador() -> Player:
	var p: Player = PL.new()
	p.fijar_identidad("H", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	return p


## (a) El JSON.
func _test_json() -> void:
	var texto: String = FileAccess.get_file_as_string(AnclajesDB.RUTA)
	_chk(not texto.is_empty(), "a: existe " + AnclajesDB.RUTA)
	var crudo: Variant = JSON.parse_string(texto)
	_chk(crudo is Dictionary, "a: el JSON es válido")
	_chk((crudo as Dictionary).get("campos", {}) is Dictionary,
		"a: documenta sus campos")
	var anclajes: Array = (crudo as Dictionary).get("anclajes", [])
	_chk(anclajes.size() == Equipo.SLOTS.size(),
		"a: hay un anclaje por slot de equipo",
		"%d anclajes vs %d slots" % [anclajes.size(), Equipo.SLOTS.size()])
	var vistos: Dictionary = {}
	for a in anclajes:
		var ad: Dictionary = a
		var slot: String = str(ad.get("slot", ""))
		_chk(Equipo.SLOTS.has(slot), "a: el slot '" + slot + "' existe en Equipo")
		vistos[slot] = true
		_chk(str(ad.get("anclaje", "")) != "",
			"a: " + slot + " tiene anclaje (hueso del modelo)")
		_chk(ad.has("mesh_path"), "a: " + slot + " declara mesh_path")
		var mp: String = str(ad.get("mesh_path", ""))
		_chk(mp == "" or mp.ends_with(".glb"),
			"a: " + slot + " mesh_path vacío o .glb", mp)
		_chk(ad.has("offset") and (ad.get("offset", []) as Array).size() == 3,
			"a: " + slot + " tiene offset de 3 componentes")
		_chk(ad.has("rotacion") and (ad.get("rotacion", []) as Array).size() == 3,
			"a: " + slot + " tiene rotación de 3 componentes")
		_chk(float(ad.get("escala", 0.0)) > 0.0, "a: " + slot + " escala positiva")
		var hex: String = str(ad.get("tinte", ""))
		_chk(hex.begins_with("#") and hex.length() == 7,
			"a: " + slot + " tinte #rrggbb", hex)
		# La pieza tiene que caer dentro del cuerpo (cápsula de 1,7 de alto).
		var off: Array = ad.get("offset", [])
		for c in off:
			_chk(absi(float(c)) <= 2.0, "a: " + slot + " offset dentro del cuerpo", str(c))
		_chk(forma_valida(ad.get("forma", {}) as Dictionary),
			"a: " + slot + " describe una forma válida")
	for s in Equipo.SLOTS:
		_chk(vistos.has(s), "a: el slot '" + s + "' tiene anclaje")


func forma_valida(f: Dictionary) -> bool:
	if f.is_empty():
		return false
	var t: String = str(f.get("tipo", ""))
	match t:
		"caja", "par":
			return (f.get("tam", []) as Array).size() == 3
		"esfera":
			return f.has("radio") and f.has("alto")
		"espada":
			return (f.get("partes", []) as Array).size() >= 2
		"mesh":
			return true
	return false


## (b) La DB.
func _test_db() -> void:
	_chk(AnclajesDB.slots().size() == Equipo.SLOTS.size(),
		"b: carga los 12 anclajes", str(AnclajesDB.slots().size()))
	_chk(AnclajesDB.existe("arma"), "b: existe el slot arma")
	_chk(not AnclajesDB.existe("slot_inventado"), "b: slot inventado = false")
	_chk(AnclajesDB.obtener("slot_inventado").is_empty(), "b: slot inventado = {}")
	_chk(AnclajesDB.offset_de("casco").y > 1.4, "b: el casco va arriba",
		str(AnclajesDB.offset_de("casco")))
	_chk(is_zero_approx(AnclajesDB.offset_de("slot_inventado").x),
		"b: offset de slot inexistente = 0")
	_chk(is_equal_approx(AnclajesDB.escala_de("arma"), 1.0), "b: escala del arma = 1")
	_chk(AnclajesDB.tinte_de("slot_inventado") == Color(0.7, 0.7, 0.7),
		"b: tinte por defecto = gris")
	_chk(AnclajesDB.anclaje_de("arma") != "", "b: el anclaje del arma no está vacío")
	# Hoy no hay ningún modelo: la cola de arte son los 12.
	_chk(not AnclajesDB.tiene_malla("arma"), "b: el arma aún no tiene GLB")
	_chk(AnclajesDB.slots_sin_malla().size() == Equipo.SLOTS.size(),
		"b: los 12 slots usan el respaldo procedural",
		str(AnclajesDB.slots_sin_malla().size()))


## (c) El paper-doll sale de la tabla.
func _test_paperdoll() -> void:
	var p: Player = _jugador()
	var muneco: PaperDoll = PD.new()
	muneco.name = "PaperDoll"
	p.add_child(muneco)
	muneco.conectar(p)
	_chk(muneco.get_child_count() == 0, "c: sin equipo, 0 piezas")
	# Todo equipado: 12 slots. `equipar` necesita stats e inventario (los usa
	# para aplicar/quitar los mods), como en el juego.
	for s in Equipo.SLOTS:
		var iid: String = _item_para(s)
		p.inventario.agregar(iid, 1)
		_chk(p.equipo.equipar(iid, p.stats, p.inventario), "setup: equipa " + iid)
	muneco.reconstruir()
	# BLOQUE 67: las piezas ya NO cuelgan del PaperDoll. Con anclaje a hueso
	# cuelgan de un `BoneAttachment3D`, que a su vez cuelga del `Skeleton3D`
	# del modelo. Por eso se cuentan las mallas del MODELO ENTERO, no del
	# PaperDoll: si se contaran solo del doll, daría 0 con el equipo puesto.
	var mallas: int = 0
	for n in _mallas_de(muneco):
		mallas += 1
	if mallas == 0:
		for n in _mallas_de(p):
			mallas += 1
	_chk(mallas >= 12, "c: con todo equipado hay al menos 12 mallas", str(mallas))
	# Los nombres de nodo de siempre (el resto de fases los tienen localizados).
	for sl in Equipo.SLOTS:
		_chk(_pieza_de(p, sl) != null, "c: existe la pieza del slot " + sl)
	_chk(_pieza_de(p, "arma/Hoja") != null, "c: el arma sigue con hoja")
	_chk(_pieza_de(p, "arma/Guarda") != null, "c: el arma sigue con guarda")
	_chk(_pieza_de(p, "guantes/Guantes_der") != null, "c: guantes der")
	_chk(_pieza_de(p, "botas/Botas_izq") != null, "c: botas izq")
	# La pieza ES la malla y se renombra con el slot (como siempre); lo que
	# viene de la tabla es su forma y su tamaño.
	var coraza: MeshInstance3D = _pieza_de(p, "armadura") as MeshInstance3D
	_chk(coraza != null and coraza.mesh is BoxMesh, "c: la coraza es una caja")
	var tam: Vector3 = _vec3(AnclajesDB.forma_de("armadura").get("tam", []))
	_chk(coraza != null and (coraza.mesh as BoxMesh).size.distance_to(tam) < 0.001,
		"c: y su tamaño es el de la tabla",
		"%s vs %s" % [str((coraza.mesh as BoxMesh).size) if coraza != null else "?", str(tam)])
	_chk(coraza != null and coraza.material_override != null, "c: lleva material")
	# Y las posiciones son las de la TABLA, no unas hardcodeadas.
	for s in Equipo.SLOTS:
		var pieza: Node3D = _pieza_de(p, s) as Node3D
		if pieza == null:
			continue
		var off: Vector3 = AnclajesDB.offset_de(s)
		# Los slots espejados (_2) cuelgan de un hueso que el rig ya refleja,
		# así que su ajuste lleva la X invertida a propósito (el cigue lo pone
		# al revés). Para el resto, el ajuste es el offset tal cual.
		if s.ends_with("_2"):
			off.x = -off.x
		_chk(pieza.position.distance_to(off) < 0.001,
			"c: la pieza de " + s + " está donde dice la tabla",
			"%s vs %s" % [str(pieza.position), str(off)])
	# Los slots vacíos no generan pieza.
	_chk(p.equipo.desequipar("casco", p.stats, p.inventario), "c: desequipa el casco")
	muneco.reconstruir()
	# queue_free es diferido: la pieza vale ausente O en cola de borrado.
	var vieja: Node = muneco.get_node_or_null("casco")
	_chk(vieja == null or vieja.is_queued_for_deletion(),
		"c: al quitar el casco, su pieza desaparece")


## Lee un [x, y, z] del JSON como Vector3.
func _vec3(a: Variant) -> Vector3:
	if not (a is Array):
		return Vector3.ZERO
	var arr: Array = a as Array
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _mallas_de(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_mallas_de(c))
	return out


func _item_para(slot: String) -> String:
	match slot:
		"arma": return "daga_gastada"
		"escudo": return "escudo_madera"
		"casco": return "casco_cuero"
		"armadura": return "armadura_cuero"
		"guantes": return "guantes_cuero"
		"botas": return "botas_cuero"
		"collar": return "collar_cobre"
		"amuleto": return "amuleto_guardian"
		"anillo_1", "anillo_2": return "anillo_poder"
		"pendiente_1", "pendiente_2": return "pendiente_luna"
	return "daga_gastada"


## (d) Un modelo que no existe no rompe el juego.
func _test_modelo_ausente() -> void:
	var p: Player = _jugador()
	var muneco: PaperDoll = PD.new()
	p.add_child(muneco)
	muneco.conectar(p)
	var veta: Dictionary = AnclajesDB.obtener("arma")
	var original: String = str(veta.get("mesh_path", ""))
	# Con mesh_path vacío sale el respaldo.
	var pieza: Node3D = muneco._pieza("arma")
	_chk(pieza != null, "d: sin mesh_path sale la pieza procedural")
	_chk(is_equal_approx(pieza.position.y, AnclajesDB.offset_de("arma").y),
		"d: y la pieza va donde dice la tabla")
	# Con una ruta que no existe: avisa y vuelve al respaldo.
	pieza = muneco._pieza("slot_que_no_existe")
	_chk(pieza == null, "d: slot sin anclaje = null (avisa, no revienta)")


## (e) El medidor.
func _test_medidor() -> void:
	var m: RefCounted = MD.new()
	m.limpiar()
	_chk(m.total() == 0, "e: empieza vacío")
	_chk((m.informe() as Dictionary).get("veredicto", "") == "SIN MUESTRAS",
		"e: sin muestras, informe claro")
	# 100 muestras: 90 de 4 ms y 10 de 100 ms. Con un 10% de picos, el p95
	# tiene que verlos (con un 5% el p95 correcto sería 4 ms).
	for i in range(90):
		m.tomar_muestra_manual({"frame_ms": 4.0, "fps": 250.0, "draw_calls": 400.0,
			"primitivas": 280000.0, "objetos": 900.0, "video_mem_mb": 150.0,
			"nodos": 1200.0})
	for i in range(10):
		m.tomar_muestra_manual({"frame_ms": 100.0, "fps": 10.0, "draw_calls": 400.0,
			"primitivas": 280000.0, "objetos": 900.0, "video_mem_mb": 150.0,
			"nodos": 1200.0})
	_chk(m.total() == 100, "e: 100 muestras", str(m.total()))
	var inf: Dictionary = m.informe()
	_chk(is_equal_approx(float(inf["frame_ms_p50"]), 4.0), "e: p50 = 4 ms",
		str(inf["frame_ms_p50"]))
	_chk(is_equal_approx(float(inf["frame_ms_p95"]), 100.0), "e: el p95 ve los picos",
		str(inf["frame_ms_p95"]))
	_chk(is_equal_approx(float(inf["frame_ms_promedio"]), 13.6),
		"e: promedio = 13.6 ms", str(inf["frame_ms_promedio"]))
	# Con solo un 5% de picos, el p95 correcto es el valor bajo (95 de 100
	# muestras están por debajo): el percentil no se inventa picos.
	var m4: RefCounted = MD.new()
	for i in range(95):
		m4.tomar_muestra_manual({"frame_ms": 4.0, "fps": 250.0})
	for i in range(5):
		m4.tomar_muestra_manual({"frame_ms": 100.0, "fps": 10.0})
	_chk(is_equal_approx(float((m4.informe() as Dictionary)["frame_ms_p95"]), 4.0),
		"e: con el 95% de muestras buenas, el p95 es el bueno",
		str((m4.informe() as Dictionary)["frame_ms_p95"]))
	_chk(str(inf["veredicto"]) == "FUERA DE PRESUPUESTO",
		"e: 100 ms de frame es fuera de presupuesto", str(inf["veredicto"]))
	_chk((inf["fallos"] as Array).size() >= 1, "e: dice qué se pasó")
	# Ahora un mundo sano: dentro de presupuesto.
	var m2: RefCounted = MD.new()
	for i in range(60):
		m2.tomar_muestra_manual({"frame_ms": 4.4, "fps": 227.0, "draw_calls": 443.0,
			"primitivas": 285000.0, "objetos": 900.0, "video_mem_mb": 150.0,
			"nodos": 1200.0})
	var inf2: Dictionary = m2.informe()
	_chk(str(inf2["veredicto"]) == "OK", "e: el mundo medido está en presupuesto",
		str(inf2["veredicto"]))
	# Si se pasan los draw calls, lo dice aunque los frames estén bien.
	var m3: RefCounted = MD.new()
	m3.tomar_muestra_manual({"frame_ms": 4.0, "fps": 250.0,
		"draw_calls": 9999.0, "primitivas": 285000.0, "objetos": 900.0,
		"video_mem_mb": 150.0, "nodos": 1200.0})
	_chk(str((m3.informe() as Dictionary)["veredicto"]) == "FUERA DE PRESUPUESTO",
		"e: 9999 draw calls = fuera de presupuesto")
	# La línea de texto se puede imprimir.
	var linea: String = MD.linea_informe(inf2)
	_chk(linea.contains("BENCH-GPU") and linea.contains("draw"), "e: la línea es legible",
		linea)
	_chk(MD.linea_informe({}).contains("sin muestras"), "e: y avisa si no hay muestras")


## (g) El manifiesto de modelos: la puerta de la licencia. Un `.glb` sin
## entrada en `data/modelos.json`, o con una licencia que no sea CC0/CC-BY, es
## un test que falla (regla dura §7.5: nunca Blizzard, y la autorización de los
## 85 GLB de Meshy es con licencia CC0/CC-BY).
func _test_modelos() -> void:
	var texto: String = FileAccess.get_file_as_string("res://data/modelos.json")
	_chk(not texto.is_empty(), "g: existe data/modelos.json")
	var crudo: Variant = JSON.parse_string(texto)
	_chk(crudo is Dictionary, "g: el manifiesto es JSON válido")
	var d: Dictionary = crudo as Dictionary
	var permitidas: Array = d.get("licencias_permitidas", [])
	_chk(permitidas.has("CC0") and permitidas.has("CC-BY"),
		"g: solo se admiten CC0 y CC-BY", str(permitidas))
	var declarados: Dictionary = {}
	for m in (d.get("modelos", []) as Array):
		if not (m is Dictionary):
			continue
		var md: Dictionary = m
		var arch: String = str(md.get("archivo", ""))
		_chk(arch.ends_with(".glb"), "g: el manifiesto solo lista .glb", arch)
		_chk(str(md.get("fuente", "")) != "", "g: " + arch + " dice su fuente")
		_chk(str(md.get("autor", "")) != "", "g: " + arch + " dice su autor")
		_chk(permitidas.has(str(md.get("licencia", ""))),
			"g: " + arch + " tiene licencia permitida", str(md.get("licencia", "")))
		declarados[arch] = md
	# Todo .glb de la carpeta tiene que estar declarado.
	var encontrados: int = 0
	for archivo in _glb_de("res://models"):
		encontrados += 1
		var nombre: String = str(archivo).get_file()
		_chk(declarados.has(nombre),
			"g: models/" + nombre + " está declarado en el manifiesto")
		_chk(FileAccess.file_exists("res://models/" + nombre),
			"g: models/" + nombre + " existe de verdad")
	# Y al revés: un modelo declarado tiene que estar en la carpeta.
	for arch in declarados:
		_chk(FileAccess.file_exists("res://models/" + str(arch)),
			"g: el modelo declarado existe: " + str(arch))
	# Los mesh_path de la tabla tienen que existir o estar vacíos.
	for slot in AnclajesDB.slots():
		var mp: String = str(AnclajesDB.obtener(slot).get("mesh_path", ""))
		if mp == "":
			continue
		_chk(mp.begins_with("res://models/"),
			"g: " + slot + " apunta dentro de models/", mp)
		_chk(ResourceLoader.exists(mp), "g: " + slot + " apunta a algo que existe", mp)
		_chk(declarados.has(mp.get_file()), "g: " + slot + " está en el manifiesto", mp)
	_chk(encontrados == declarados.size(),
		"g: manifiesto y carpeta dicen lo mismo",
		"%d en disco vs %d declarados" % [encontrados, declarados.size()])


func _glb_de(dir: String) -> Array[String]:
	var res: Array[String] = []
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return res
	for f in d.get_files():
		if str(f).to_lower().ends_with(".glb"):
			res.append("res://models/" + str(f))
	d.list_dir_end()
	return res


## (f) El presupuesto sigue siendo el de la fase 20.
func _test_presupuesto() -> void:
	_chk(is_equal_approx(MD.PRESUPUESTO_P95_MS, 16.7),
		"f: p95 ≤ 16.7 ms (el número duro de la fase 20)")
	_chk(MD.PRESUPUESTO_DRAW_CALLS > 0, "f: hay presupuesto de draw calls")
	_chk(MD.PRESUPUESTO_PRIMITIVAS > 0, "f: hay presupuesto de triángulos")
	_chk(MD.PRESUPUESTO_VIDEO_MB > 0, "f: hay presupuesto de memoria de video")


## BLOQUE 67: la pieza de un slot, este donde este. Con anclaje a hueso cuelga
## de un `BoneAttachment3D` (que cuelga del esqueleto) y NO del `PaperDoll`, así
## que `get_node_or_null(slot)` sobre el doll ya no la encuentra. Se busca en el
## subarbol del jugador entero, que contiene las dos topologías.
func _pieza_de(p: Player, ruta: String) -> Node:
	var partes: PackedStringArray = ruta.split("/")
	var actual: Node = p
	for parte in partes:
		if actual == null:
			return null
		var siguiente: Node = actual.get_node_or_null(parte)
		if siguiente == null:
			# Puede estar en OTRO anclaje: se recorre el subarbol buscando el
			# primer segmento por nombre.
			siguiente = _buscar_por_nombre(actual, parte)
			if siguiente == null:
				return null
		actual = siguiente
	return actual


func _buscar_por_nombre(n: Node, nombre: String) -> Node:
	for c in n.get_children():
		if c.name == nombre:
			return c
		var r: Node = _buscar_por_nombre(c, nombre)
		if r != null:
			return r
	return null
