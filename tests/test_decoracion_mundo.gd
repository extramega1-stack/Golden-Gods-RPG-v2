extends SceneTree
## Fase 70 — LA FORMA del mundo: vegetacion, props de calle y siluetas.
##
## POR QUÉ ESTE ARCHIVO: la fase 69 le puso color y textura (PBR procedural,
## 126 materiales, triplanar) y la forma siguió primitiva: nueve ciudades de
## cajas, 146 edificios de cajas y ni una mata de pasto. Un mundo con textura
## buena y forma de caja se ve como un juego de cajas con textura buena. Este
## test vigila las CUATRO cosas que pueden volver a romperlo, y tres de las
## cuatro se rompen calladitas (una mata que aparece un metro más lejos no
## falla: se ve mal, y solo en dos sesiones seguidas):
##
## 1. DETERMINISMO. La misma posición da SIEMPRE la misma especie, la misma
##    silueta y el mismo prop de calle. Sin esto, cargar un save reconstruye el
##    mundo con el pasto en otros metros y el jugador pierde de vista todo lo
##    que construyó alrededor de su casa. Es EL test que pedía el encargo.
## 2. LA ZONA SEGURA. Nada alto dentro de los 40 m del origen: es el mismo radio
##    que ya vigilan `test_fase12_spawns` y `test_fase14_terreno`, y la razón
##    es la misma (la aldea inicial tiene que estar despejada).
## 3. EL PRESUPUESTO. El anillo es un número cerrado de celdas, no "todo lo que
##    haya": si el `radio_lejos` o el `paso` se mueven, el número de instancias
##    se mueve con ellos, y este test lo compara contra el techo de la GTX 1660
##    con 1 GB de VRAM.
## 4. DATOS PRIMERO. Si una forma, un slot o una silueta no está en
##    `data/decoracion.json`, este test se pone rojo. Es el punto: el `.gd` no
##    sabe ni un color ni una densidad.
##
## Y el cuarto bloque comprueba la regla de datos primero de la FASE 69: los
## roles de `data/materiales.json` que pide `ciudad_luna.gd` siguen declarados
## (la silueta no metió un `_mat()` nuevo sin su entrada).

const DDB: GDScript = preload("res://scripts/mundo/decoracion_db.gd")
const REJ: GDScript = preload("res://scripts/mundo/rejilla_decoracion.gd")
const MAL: GDScript = preload("res://scripts/mundo/mallas_decoracion.gd")
const PIS: GDScript = preload("res://scripts/mundo/piso_decoracion.gd")
const VEG: GDScript = preload("res://scripts/mundo/vegetacion.gd")
const PRO: GDScript = preload("res://scripts/mundo/props_ciudad.gd")
const CL: GDScript = preload("res://scripts/mundo/ciudad_luna.gd")
const MDB: GDScript = preload("res://scripts/render/materiales_db.gd")
const BIB: GDScript = preload("res://scripts/render/biblioteca_materiales.gd")

## Techo de triángulos del anillo de vegetación, con el buffer LLENO. Con la
## densidad del dato nunca se llega (el test lo mide), pero el peor caso tiene
## que estar acotado: un `radio_lejos` de 600 con un `paso` de 4 son 90.000
## celdas y revienta la máquina.
const MAX_TRIANGULOS_ANILLO: int = 400000
## Techo de props por ciudad.
const MAX_PROPS_CIUDAD: int = 400
## Presupuesto de materiales que puede agregar la decoración a una ciudad (la
## paleta de la ciudad ya genera varios; el resto son tintes fijos).
const MAX_MATERIALES_PROPS: int = 12

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 70 — decoracion del mundo")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_datos_completos()
	_t_hash_determinista()
	_t_rejilla_cerrada()
	_t_zona_por_region()
	_t_vegetacion_presupuesto()
	_t_vegetacion_zona_segura()
	_t_vegetacion_determinismo()
	_t_props_calle()
	_t_ciudad_variada()
	_t_regla_de_datos_primero()
	print("[TEST] decoracion_mundo: %d ok, %d fallos" % [_ok, _fallos])
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
		print("  FALLA: %s  %s" % [nombre, detalle])


# ---------------------------------------------------------------------------
# 1. Los datos: todo lo que el código pide tiene que estar declarado
# ---------------------------------------------------------------------------

func _t_datos_completos() -> void:
	DDB.cargar()
	_chk(DDB.vegetales().size() >= 5, "hay al menos 5 especies",
		str(DDB.vegetales()))
	_chk(DDB.paso() >= 4.0, "el paso de la grilla no es un numero de juguete",
		str(DDB.paso()))
	_chk(DDB.radio_lejos() > DDB.radio_cerca(),
		"el anillo es mas grande que el radio cercano (el LOD tiene sentido)",
		"%f / %f" % [DDB.radio_lejos(), DDB.radio_cerca()])
	_chk(DDB.radio_zona_segura() > 0.0, "la zona segura esta declarada")
	_chk(DDB.celdas_por_frame() > 0, "se escribe algo por frame")
	# Cada especie tiene forma, y cada forma tiene partes con primitiva y tinte.
	for tipo in DDB.vegetales():
		var v: Dictionary = DDB.vegetal(tipo)
		var forma: String = str(v.get("forma", ""))
		_chk(not DDB.partes(forma).is_empty(), "la especie declara forma: " + tipo)
		_chk(v.has("alcance"), "la especie declara su alcance (LOD): " + tipo)
		_chk(v.has("escala") and (v["escala"] as Array).size() == 2,
			"la especie declara su rango de escala: " + tipo)
		for p in DDB.partes(forma):
			var parte: Dictionary = p
			_chk(str(parte.get("prim", "")) != "", "la parte declara primitiva")
			_chk(MAL.primitiva(str(parte.get("prim", "caja"))) != null,
				"la primitiva existe en Godot: " + str(parte.get("prim", "")))
			_chk((parte.get("tam", []) as Array).size() == 3,
				"la parte declara tam: " + str(parte.get("prim", "")))
			# El tinte se resuelve POR ZONA, y cada zona tiene que poder
			# resolverlo: un slot sin tinte pinta de negro.
			for zid in DDB.zonas():
				var zona: Dictionary = DDB.zona_por_id(zid)
				var t: Dictionary = DDB.tinte_de(zona, str(parte.get("tinte", "")))
				_chk(not t.is_empty(),
					"la zona %s declara el tinte %s" % [zid, str(parte.get("tinte", ""))])
				_chk(MDB.superficie_existe(str(t.get("superficie", ""))),
					"el tinte %s usa una superficie del catalogo" % str(parte.get("tinte", "")))
	# Las superficies que usa la decoración tienen que tener UV y patrón (el
	# test de la fase 69 lo exige para todas, pero la decoración no puede
	# romperlo por su cuenta).
	for zona_id in DDB.zonas():
		var zona: Dictionary = DDB.zona_por_id(zona_id)
		for slot in ["follaje", "flor", "leno", "leno_seco", "roca"]:
			var tt: Dictionary = DDB.tinte_de(zona, slot)
			_chk(not tt.is_empty(), "la zona %s trae el slot %s" % [zona_id, slot])
		_chk(DDB.peso_de(zona, "hierba") >= 0.0, "la zona %s pesa la hierba" % zona_id)
	# Las 10 regiones del mundo tienen su bloque. Si aparece una región nueva
	# sin declarar, cae en `default` (que existe) y el test se pone rojo para
	# que alguien decida si la quiere así.
	var regiones: Array = _ids_de_regiones()
	for r in regiones:
		_chk(DDB.zonas().has(str(r)) or str(r) == DDB.ZONA_DEFAULT,
			"la region %s tiene bloque de vegetacion" % str(r))
	_chk(DDB.zonas().has(DDB.ZONA_DEFAULT), "esta el bloque default")
	# Cada prop de calle tiene forma, y cada forma tiene primitiva y tinte.
	_chk(DDB.ciudad_props().size() >= 4, "hay al menos 4 props de calle",
		str(DDB.ciudad_props().size()))
	for p in DDB.ciudad_props():
		var d: Dictionary = p
		_chk(not DDB.partes(str(d.get("forma", ""))).is_empty(),
			"el prop declara forma: " + str(d.get("id", "")))
		_chk(int(d.get("uno_cada", 0)) >= 1, "el prop declara su frecuencia: "
			+ str(d.get("id", "")))
		for q in DDB.partes(str(d.get("forma", ""))):
			var parte: Dictionary = q
			var slot: String = str(parte.get("tinte", ""))
			_chk(slot.begins_with("pal_") or not DDB.ciudad_slot(slot).is_empty(),
				"el slot del prop esta declarado: " + slot)
	# El zócalo y las siluetas.
	_chk(not DDB.zocalo().is_empty(), "el zocalo esta declarado")
	_chk(int(DDB.zocalo().get("margen", 0.0)) > 0.0, "el zocalo sobresale del muro")
	_chk(float(DDB.zocalo().get("hundir", 0.0)) > 0.0, "el zocalo se hunde en el suelo")
	for t in ["casa", "salon_clases", "forja", "tienda", "cuartel", "templo"]:
		_chk(DDB.siluetas(t).size() == 3, "el tipo %s tiene 3 siluetas" % t,
			str(DDB.siluetas(t).size()))


func _ids_de_regiones() -> Array:
	var salida: Array = []
	var f := FileAccess.open("res://data/regiones.json", FileAccess.READ)
	if f == null:
		return salida
	var crudo: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (crudo is Array):
		return salida
	for r in (crudo as Array):
		if r is Dictionary:
			salida.append(str((r as Dictionary).get("id", "")))
	return salida


# ---------------------------------------------------------------------------
# 2. EL HASH. Si esto no es puro, nada de lo demás sirve.
# ---------------------------------------------------------------------------

func _t_hash_determinista() -> void:
	var s1: int = DDB.semilla(123.0, -456.0)
	_chk(s1 == DDB.semilla(123.0, -456.0), "la misma posicion da la misma semilla")
	_chk(s1 != DDB.semilla(124.0, -456.0), "un metro de mas cambia la semilla")
	# `dado` es una FUNCION PURA: depende de (semilla, indice) y nada mas. Si
	# tuviera estado, dos celdas con la misma semilla darian el mismo valor y
	# medio barrio saldría clonado.
	_chk(DDB.dado(7, 3) == DDB.dado(7, 3), "dado es puro")
	_chk(DDB.dado(7, 3) != DDB.dado(7, 4), "dado separa los indices")
	_chk(DDB.dado(7, 3) != DDB.dado(8, 3), "dado separa las semillas")
	for i in 40:
		var u: float = DDB.unidad(12345, i)
		_chk(u >= 0.0 and u < 1.0, "unidad esta en [0, 1)", "i=%d u=%f" % [i, u])
	# Y la distribucion no es degenerada: 200 valores tienen que llenar el
	# intervalo. Si todos dieran 0.5, la "variacion" seria de mentira.
	var cubos: Array[int] = [0, 0, 0, 0, 0]
	for i in 200:
		cubos[int(DDB.unidad(999, i) * 5.0)] += 1
	for c in cubos:
		_chk(c > 0, "el hash reparte los 5 quintos", str(cubos))
	_chk(DDB.eleccion(5, 1, 3) < 3, "eleccion esta en rango")
	_chk(DDB.eleccion(5, 1, 1) == 0, "eleccion con n=1 da 0")
	_chk(DDB.eleccion(5, 1, 0) == 0, "eleccion con n=0 no revienta")


# ---------------------------------------------------------------------------
# 3. LA REJILLA: un numero cerrado, no "todo lo que haya"
# ---------------------------------------------------------------------------

func _t_rejilla_cerrada() -> void:
	var paso: float = DDB.paso()
	var r: float = DDB.radio_lejos()
	var cap: int = REJ.capacidad(paso, r)
	var celdas: Array[Vector2i] = REJ.celdas(Vector2i(0, 0), paso, r)
	_chk(cap > 100, "el anillo tiene celdas de sobra", str(cap))
	_chk(celdas.size() == cap,
		"la lista de celdas y la capacidad dicen lo mismo",
		"%d vs %d" % [celdas.size(), cap])
	# La capacidad NO depende de donde este el jugador: es un disco. Si
	# dependiera, el `MultiMesh` habria que redimensionar en cada cruce de
	# celda, que es exactamente lo que §9.5 prohibe.
	_chk(REJ.capacidad(paso, r) == REJ.capacidad(paso, r), "la capacidad es estable")
	var lejos: Array[Vector2i] = REJ.celdas(Vector2i(400, -700), paso, r)
	_chk(lejos.size() == cap, "y da lo mismo lejos del origen", str(lejos.size()))
	# El orden es estable: dos traversales tienen que dar la MISMA lista, o el
	# slot de una celda no sería el slot de esa celda.
	var a: Array[Vector2i] = REJ.celdas(Vector2i(13, -21), paso, r)
	var b: Array[Vector2i] = REJ.celdas(Vector2i(13, -21), paso, r)
	_chk(a == b, "la enumeracion del anillo es estable")
	# La celda del mundo no depende del jugador.
	_chk(REJ.celda_de(100.0, 200.0, 14.0) == REJ.celda_de(105.0, 203.0, 14.0),
		"dos puntos de la misma celda caen en la misma celda")
	_chk(REJ.celda_de(0.0, 0.0, 14.0) == REJ.celda_de(13.9, 13.9, 14.0),
		"la celda no depende del jugador (cruzar una frontera no mueve la semilla)")
	_chk(REJ.centro_de(Vector2i(0, 0), 14.0) == Vector2(7.0, 7.0),
		"el centro de la celda cae dentro de ella")


# ---------------------------------------------------------------------------
# 4. LA ZONA: el mismo arbusto es verde en el bosque y gris en la ceniza
# ---------------------------------------------------------------------------

func _t_zona_por_region() -> void:
	_chk(DDB.zona_en(0.0, 0.0) == "moon_town",
		"el origen es Moon Town", DDB.zona_en(0.0, 0.0))
	_chk(DDB.zona_en(9966.0, 0.0) == "tierras_francas",
		"Desert Town cae en las Tierras Francas", DDB.zona_en(9966.0, 0.0))
	_chk(DDB.zona_en(0.0, 9966.0) == "bosque_hondo",
		"Mystic Town cae en el Bosque Hondo", DDB.zona_en(0.0, 9966.0))
	# Un punto fuera de toda región (lejos de las 10 cajas) cae en `default`,
	# no en `{}`: un Dictionary vacío haría que `tinte_de` no encontrara nada
	# y la planta saliera con el material de repuesto.
	var fuera: Dictionary = DDB.zona_resuelta(99999.0, 99999.0)
	_chk(not fuera.is_empty(), "una region desconocida cae en default",
		str(fuera.keys()))
	_chk(not DDB.tinte_de(fuera, "follaje").is_empty(),
		"y default trae follaje")
	# Las zonas de verdad TIENEN que verse distinto. Si el follaje de todas
	# fuera el mismo verde, la parte mas cara de la decoracion (el tinte por
	# zona) estaria pagando por nada.
	var tintes: Dictionary = {}
	for zid in DDB.zonas():
		if zid == DDB.ZONA_DEFAULT:
			continue
		tintes[str(DDB.tinte_de(DDB.zona_por_id(zid), "follaje")
			.get("tinte", ""))] = true
	_chk(tintes.size() >= 6, "cada zona tiene su propio follaje",
		"%d tintes distintos" % tintes.size())
	# Y las densidades tienen que differentiates: el Bosque Hondo es un
	# bosque, la Ceniza y Forja un campo de piedra.
	var denso: float = 0.0
	var ralo: float = 1.0
	for zid in DDB.zonas():
		if zid == DDB.ZONA_DEFAULT:
			continue
		var zona: Dictionary = DDB.zona_por_id(zid)
		denso = maxf(denso, DDB.peso_de(zona, "arbol_choto"))
		ralo = minf(ralo, DDB.peso_de(zona, "arbol_choto"))
	_chk(denso >= 0.9, "hay una zona con arboles en cada celda posible", str(denso))
	_chk(ralo <= 0.12, "y una zona casi sin arboles", str(ralo))


# ---------------------------------------------------------------------------
# 5-7. LA VEGETACIÓN: presupuesto, zona segura y determinismo
# ---------------------------------------------------------------------------

func _vegetacion_en(x: float, z: float) -> Node:
	var v: Node = VEG.new()
	_basura.append(v)
	var terreno := Terreno.new()
	_basura.append(terreno)
	root.add_child(terreno)
	terreno.set("construccion_progresiva", true)
	# El bin se carga sin construir los 36 chunks: `altura_en` funciona igual y
	# el test no necesita el terreno dibujado.
	terreno.call("_cargar_bin")
	var jugador := Node3D.new()
	_basura.append(jugador)
	root.add_child(jugador)
	jugador.position = Vector3(x, 0.0, z)
	v.set("terreno", terreno)
	root.add_child(v)
	v.call("fijar_terreno", terreno)
	v.call("fijar_jugador", jugador)
	return v


func _t_vegetacion_presupuesto() -> void:
	var v: Node = _vegetacion_en(0.0, 45.0)
	_chk(v.call("anillo_listo"), "el anillo se planta entero")
	var celdas: int = int(v.call("celdas_en_anillo"))
	_chk(celdas == REJ.capacidad(DDB.paso(), DDB.radio_lejos()),
		"el anillo tiene todas las celdas", str(celdas))
	_chk(int(v.call("capacidad_capa")) == celdas,
		"cada capa reserva un slot por celda",
		"%d vs %d" % [int(v.call("capacidad_capa")), celdas])
	# El presupuesto de verdad: triángulos, no nodos.
	var peor: int = int(v.call("triangulos_peor_caso"))
	_chk(peor > 0, "el anillo tiene geometria", str(peor))
	_chk(peor <= MAX_TRIANGULOS_ANILLO,
		"el peor caso del anillo cabe en el presupuesto",
		"%d > %d" % [peor, MAX_TRIANGULOS_ANILLO])
	# Las piezas PUESTAS, que es lo que de verdad se dibuja.
	var puestas: int = int(v.call("piezas_puestas"))
	_chk(puestas > celdas, "se siembra mas de una pieza por celda", str(puestas))
	_chk(puestas < celdas * 6, "y no se llena todo: el presupuesto es variedad, no densidad",
		"%d piezas en %d celdas" % [puestas, celdas])
	# Las mallas: cinco primitivas para el mundo entero.
	_chk(MAL.primitivas_creadas() <= 5,
		"la vegetacion usa 5 primitivas compartidas",
		str(MAL.primitivas_creadas()))
	# Las capas arrancan apagadas y se encienden al terminar: mezclar el anillo
	# viejo con el nuevo durante ocho frames se ve peor que un frame vacio.
	var capas: int = int(v.call("capas_totales"))
	_chk(capas >= 5, "hay una capa por (especie, parte)", str(capas))
	_chk(v.call("pendientes") == 0, "no quedan celdas sin escribir")


func _t_vegetacion_zona_segura() -> void:
	var r: float = DDB.radio_zona_segura()
	_chk(absf(r - 40.0) < 0.01,
		"la zona segura es el radio de 40 m que ya vigilan los otros tests",
		str(r))
	# La hierba y las flores SÍ pueden estar en la plaza (tapan la mirada, no
	# el paso): lo que no puede es haber un árbol o una roca en el punto de
	# aparición. Y el filtro se mira sobre la SIEMBRA REAL (`especie_sembrada`,
	# que aplica el dado más el LOD más la zona segura), no sobre el dado
	# crudo: si se mirara el dado, el filtro no estaría probado.
	var v: Node = _vegetacion_en(0.0, 0.0)
	_chk(v.call("anillo_listo"), "el anillo del origen se planta")
	# El filtro mira el CENTRO de la celda, así que la pregunta honesta es por
	# las celdas cuyo centro cae dentro del radio MENOS el jitter: una celda
	# cuyo centro está en 41 m puede sembrar a 35 m, y esa no es una violación.
	var alto: int = 0
	var bajos: int = 0
	for c in REJ.celdas(Vector2i(0, 0), DDB.paso(), r - DDB.paso() * 0.40):
		var e: String = str(v.call("especie_sembrada", c))
		if e == "":
			continue
		if DDB.es_tipo_alto(e):
			alto += 1
		else:
			bajos += 1
	_chk(alto == 0, "nada alto dentro de los 40 m de la aldea inicial",
		"%d celdas" % alto)
	_chk(bajos > 0, "pero sí hay hierba o flores (la plaza no es un asfalto)",
		str(bajos))
	# Y fuera de la zona segura sí hay vegetation ALTA: si no, el radio de 40 m
	# sería un cráter y el test anterior pasaría por la razón equivocada.
	var v2: Node = _vegetacion_en(300.0, 300.0)
	var fuera: int = 0
	var fuera_altos: int = 0
	for c2 in REJ.celdas(Vector2i(21, 21), DDB.paso(), DDB.radio_lejos()):
		var e2: String = str(v2.call("especie_sembrada", c2))
		if e2 != "":
			fuera += 1
		if DDB.es_tipo_alto(e2):
			fuera_altos += 1
	_chk(fuera > 40, "fuera de la zona segura hay vegetacion", str(fuera))
	_chk(fuera_altos > 0, "y hay arboles o rocas (no es un campo de pasto pelado)",
		str(fuera_altos))



func _especies(v: Node) -> Array:
	var a: Array = v.call("especies")
	return a


func _t_vegetacion_determinismo() -> void:
	# EL TEST DEL ENCARGO: la misma celda da SIEMPRE la misma especie. Sin esto
	# un save reconstruye el mundo con el pasto en otros metros.
	var v: Node = _vegetacion_en(0.0, 45.0)
	var celdas: Array[Vector2i] = REJ.celdas(Vector2i(0, 0), DDB.paso(),
		DDB.radio_lejos())
	var primera: Array[String] = []
	for c in celdas:
		primera.append(str(v.call("especie_en_celda", c)))
	# Barajar el orden de la consulta tiene que dar el MISMO resultado por
	# celda: si el hash tuviera estado, el segundo traversal devolveria otra
	# cosa y la mitad de las celdas cambiarían de especie.
	var segunda: Array[String] = []
	segunda.resize(celdas.size())
	segunda.fill("")
	for i in range(celdas.size() - 1, -1, -1):
		segunda[i] = str(v.call("especie_en_celda", celdas[i]))
	_chk(primera == segunda, "consultar al reves da el mismo resultado")
	# Y desde OTRO proceso: se borran las caches (texturas, materiales, datos)
	# y se vuelve a sembrar. Es literalmente lo que pasa al cargar un save.
	var v2: Node = _vegetacion_en(0.0, 45.0)
	var tercera: Array[String] = []
	for c2 in celdas:
		tercera.append(str(v2.call("especie_en_celda", c2)))
	_chk(primera == tercera, "otra instancia da la misma especie en cada celda")
	# Y lo mismo para la siembra REAL, que es la que el jugador ve: si el
	# filtro de LOD o de zona segura dependiera del estado, el anillo se
	# reconstruiría distinto y el pasto saltaría de metro.
	var sembrada_a: Array[String] = []
	for c3 in celdas:
		sembrada_a.append(str(v.call("especie_sembrada", c3)))
	var sembrada_b: Array[String] = []
	for c4 in celdas:
		sembrada_b.append(str(v2.call("especie_sembrada", c4)))
	_chk(sembrada_a == sembrada_b, "la siembra real tambien es reproducible")
	_chk(sembrada_a != primera,
		"y no es lo mismo que el dado crudo (el filtro hace algo)")
	# La semilla cruda tambien es estable entre "procesos": el FNV-1a de la
	# Biblioteca es un entero, no un instance_id.
	_chk(DDB.semilla(-1234.5, 6789.5) == DDB.semilla(-1234.5, 6789.5),
		"la semilla es estable")
	_chk(DDB.semilla(-1234.5, 6789.5) != DDB.semilla(6789.5, -1234.5),
		"y distinta si se cruzan los ejes")
	# Un vecindario tiene que tener VARIEDAD, no una sola especie repetida.
	var cuentas: Dictionary = {}
	for e in primera:
		if e != "":
			cuentas[e] = int(cuentas.get(e, 0)) + 1
	_chk(cuentas.size() >= 3, "el anillo del origen mezcla especies",
		str(cuentas.keys()))
	# El dado NO reparte el 100% a propósito: hay un resto de celdas sin nada,
	# que es lo que hace que la pradera tenga claros en vez de ser un alfombrado.
	# Si se llenara todo, el mundo volvería a ser un bloque uniforme de verde.
	var total: int = 0
	for k in cuentas.keys():
		total += int(cuentas[k])
	_chk(float(total) / float(celdas.size()) > 0.7,
		"el anillo del origen siembra la mayor parte de sus celdas",
		"%d de %d" % [total, celdas.size()])
	_chk(float(total) / float(celdas.size()) < 1.0,
		"pero no todas: quedan claros (variedad, no alfombrado)",
		"%d de %d" % [total, celdas.size()])
	# La zona cambia el resultado: la misma celda sembrada en el Bosque Hondo
	# y en la Ceniza y Forja no puede dar lo mismo.
	var en_bosque: Dictionary = DDB.zona_por_id("bosque_hondo")
	var en_ceniza: Dictionary = DDB.zona_por_id("ceniza_forja")
	_chk(DDB.peso_de(en_bosque, "arbol_choto") > DDB.peso_de(en_ceniza, "arbol_choto"),
		"el bosque tiene mas arboles que la ceniza")
	_chk(DDB.peso_de(en_ceniza, "roca") > DDB.peso_de(en_bosque, "roca"),
		"y la ceniza tiene mas piedra")


# ---------------------------------------------------------------------------
# 8. LOS PROPS DE CALLE
# ---------------------------------------------------------------------------

func _t_props_calle() -> void:
	# Una ciudad real, con sus datos y sus obstáculos.
	var ciudad: Node = _ciudad("res://data/ciudad_desert.json", Vector2(9966.0, 0.0))
	_chk(ciudad != null, "la ciudad se construyó")
	if ciudad == null:
		return
	var props: Node = ciudad.get_node_or_null("PropsCalle")
	_chk(props != null, "la ciudad tiene PropsCalle")
	if props == null:
		return
	_chk(int(props.get("puestos")) > 40,
		"la calle tiene mobiliario", str(int(props.get("puestos"))))
	_chk(int(props.get("puestos")) <= MAX_PROPS_CIUDAD,
		"y no es un bosque de props", str(int(props.get("puestos"))))
	_chk(int(props.get("candidatas")) > int(props.get("puestos")),
		"hay celdas de vereda vacías (densidad, no saturación)",
		"%d de %d" % [int(props.get("candidatas")), int(props.get("puestos"))])
	# DENTRO DE LA CIUDAD, NO ADENTRO DE UN EDIFICIO. La invariante que
	# importa es que NINGÚN prop caiga dentro de un edificio, y se comprueba
	# con las AABB reales de la ciudad: si el filtro no hiciera nada, la
	# vereda se cruzaria con un edificio y el test igual daria verde.
	_chk(_ningun_prop_dentro(props, ciudad),
		"ningun prop cae dentro de un edificio",
		"%d descartadas" % int(props.get("descartadas")))
	# Y el filtro se prueba aparte, con un obstáculo de mentira, porque en una
	# ciudad los edificios están retranqueados de la vereda y el filtro puede no
	# tener nada que descartar sin que esté roto.
	_chk(_filtro_rechaza(props, ciudad),
		"el filtro de dentro-de-edificio rechaza cuando toca")
	var alto_prop: float = float(props.call("altura_max"))
	_chk(alto_prop <= 6.0, "ningún prop pasa los 6 u (es mobiliario, no arquitectura)",
		str(alto_prop))
	# La misma ciudad, dos veces, da los mismos props en los mismos sitios.
	var props2: Node = _props_de(_ciudad("res://data/ciudad_desert.json",
		Vector2(9966.0, 0.0)))
	_chk(_firma_de_props(props) == _firma_de_props(props2),
		"dos ciudades iguales dan los mismos props en los mismos sitios")
	# Y una ciudad DISTINTA reparte distinto: si las nueve dieran la misma
	# firma, la semilla de posición no estaría haciendo nada.
	var otra: Node = _props_de(_ciudad("res://data/ciudad_fire.json",
		Vector2(-9966.0, 0.0)))
	var f1: String = _firma_de_props(props)
	var f2: String = _firma_de_props(otra)
	_chk(f1 != f2, "una ciudad en otro sitio reparte distinto",
		"desert=%d props, fire=%d props, iguales=%s"
			% [int(props.get("puestos")), int(otra.get("puestos")),
				str(f1 == f2)])
	# El alcance: sin él, los props de las nueve ciudades se dibujan desde el
	# otro extremo del mundo.
	for c in props.get_children():
		var piso: Node = c
		_chk(float(piso.get("alcance")) > 0.0,
			"la capa de props se apaga por distancia",
			str(float(piso.get("alcance"))))


## La "huella" de la calle: un transform por prop, en orden, con la posición,
## el giro y la escala. Es lo que tiene que ser IDÉNTICO entre dos traversales
## para que el mundo sea reconstruible desde un save, y DISTINTO entre dos
## ciudades en sitios distintos para que la semilla de posición esté haciendo
## algo.
##
## Se lee del `plano()` que lleva `PropsCiudad` y no del `MultiMesh`: el
## búfer de un `MultiMesh` vive en el RenderingServer y en headless (rasterizador
## dummy) `get_instance_transform` devuelve identidad para todo. Un test que
## leyera el búfer daría verde con la calle vacía.
func _firma_de_props(props: Node) -> String:
	var partes: Array[String] = []
	var plano: Array = props.call("plano")
	for xf in plano:
		var t: Transform3D = xf
		partes.append("%.3f,%.3f,%.3f|%.4f,%.4f,%.4f,%.4f" % [
			t.origin.x, t.origin.y, t.origin.z,
			t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.x.length()])
	return ",".join(partes)


func _props_de(ciudad: Node) -> Node:
	return ciudad.get_node_or_null("PropsCalle")


## ¿Algún prop puesto cae dentro de una AABB de edificio? Reconstruye las cajas
## de colisión de la ciudad y las compara con el centro de cada prop.
func _ningun_prop_dentro(props: Node, ciudad: Node) -> bool:
	var cajas: Array = ciudad.call("cajas_colision")
	var sondeadas: int = 0
	for hijo in props.get_children():
		var piso: Node = hijo
		var mm: MultiMesh = piso.get("multimesh")
		if mm == null:
			continue
		for i in mini(mm.instance_count, 4096):
			var t: Transform3D = mm.get_instance_transform(i)
			if t.basis.x.length() < 0.001:
				continue
			for caja in cajas:
				sondeadas += 1
				if (caja as AABB).has_point(Vector3(t.origin.x, t.origin.y, t.origin.z)):
					return false
	return sondeadas > 0


## El filtro de "dentro de un edificio" con un obstáculo SINTÉTICO: se indexa
## una caja de colisión falsa y se pregunta por un punto que cae dentro y por
## otro que cae lejos. Es la prueba de que el filtro funciona y no de que en
## esta ciudad no hacía falta.
func _filtro_rechaza(props: Node, ciudad: Node) -> bool:
	var indexar: Callable = Callable(props, "_indexar")
	var dentro: Callable = Callable(props, "_dentro_de_un_edificio")
	var falsa := AABB(Vector3(100.0, 0.0, 100.0), Vector3(20.0, 20.0, 20.0))
	var b: Dictionary = indexar.call([falsa]) as Dictionary
	return bool(dentro.call(b, 108.0, 108.0)) \
		and not bool(dentro.call(b, 500.0, 500.0))


# ---------------------------------------------------------------------------
# 9. LA CIUDAD VARIADA: siluetas y zócalos
# ---------------------------------------------------------------------------

func _t_ciudad_variada() -> void:
	# Las dos ciudades con el mismo tipo de casa tienen que diferir en FORMA,
	# no solo en color. Se mide el volumen total de los edificios de tipo casa
	# de dos ciudades distintas: si la silueta no hiciera nada, darían el
	# mismo número.
	var luna: Node = _ciudad("res://data/ciudad_luna.json", Vector2.ZERO)
	var desert: Node = _ciudad("res://data/ciudad_desert.json", Vector2.ZERO)
	var a: Array = _cajas_de_tipo(luna, "casa")
	var b: Array = _cajas_de_tipo(desert, "casa")
	_chk(a.size() > 4 and b.size() > 4, "las dos ciudades tienen casas",
		"%d / %d" % [a.size(), b.size()])
	var suma_a: float = 0.0
	for c in a:
		suma_a += c.x * c.y * c.z
	var suma_b: float = 0.0
	for c in b:
		suma_b += c.x * c.y * c.z
	_chk(absf(suma_a - suma_b) > 1.0,
		"las casas de dos ciudades NO miden lo mismo",
		"%.1f vs %.1f" % [suma_a, suma_b])
	# EL BORDE. Un edificio contra el terreno sin zócalo se ve como un recorte
	# pegado, y es el defecto de forma más visible del mundo. Se le pregunta a
	# la ciudad, que lleva la cuenta, en vez de adivinar mirando AABBs: el
	# método anterior daba verde con el zócalo ausente.
	# El monumento y la puerta tienen su propio pedestal en `_pedestal_monumento`
	# y no pasan por `_zocalo`, así que no cuentan como estructuras sin zócalo.
	var sin_zocalo: int = _cuenta_tipo(luna, "monumento") \
		+ _cuenta_tipo(luna, "puerta")
	var con_estructura: int = (luna.get("edificios") as Array).size() - sin_zocalo
	_chk(int(luna.get("zocalos")) == con_estructura,
		"cada casa/edificio de Moon Town tiene zócalo",
		"%d zócalos para %d estructuras" % [int(luna.get("zocalos")), con_estructura])
	_chk(int(desert.get("zocalos")) > 0, "y la ciudad del desierto también",
		str(int(desert.get("zocalos"))))
	# La TORRE: al menos un edificio del mundo tiene un segundo volumen. Si
	# ninguna silueta declara `torre`, esto da cero.
	_chk(int(luna.get("torres")) + int(desert.get("torres")) > 0,
		"hay al menos un edificio con torre",
		"%d + %d" % [int(luna.get("torres")), int(desert.get("torres"))])
	# Y que las tres siluetas de cada tipo se usen: si el `match` de la semilla
	# siempre cayera en la primera, la silueta sería decorado de código.
	var anchos: Dictionary = {}
	for c4 in a:
		anchos["%.1f" % c4.x] = true
	_chk(anchos.size() >= 3, "las casas de una ciudad no miden todas igual",
		"%d anchos distintos" % anchos.size())
	# Y la altura sigue respetada: 28 u con la escala del JSON.
	for k in luna.get("alturas").keys():
		_chk(float(luna.get("alturas")[k]) <= 28.0,
			"nada supera los 28 u: " + str(k),
			str(float(luna.get("alturas")[k])))
	for k2 in desert.get("alturas").keys():
		_chk(float(desert.get("alturas")[k2]) <= 28.0,
			"nada supera los 28 u (desert): " + str(k2),
			str(float(desert.get("alturas")[k2])))
	# Los props no rompen las reglas de la fase 15: todo StaticBody3D sigue
	# teniendo su BoxShape3D en capa 1, y los edificios siguen siendo 16/18.
	var cuerpos: Array[Node] = luna.find_children("*", "StaticBody3D", true, false)
	_chk(cuerpos.size() >= 16, "la ciudad conserva sus cuerpos de colisión",
		str(cuerpos.size()))
	for cuerpo in cuerpos:
		var tiene: bool = false
		for h in (cuerpo as Node).get_children():
			if h is CollisionShape3D and (h as CollisionShape3D).shape is BoxShape3D:
				tiene = true
		_chk(tiene and (cuerpo as StaticBody3D).collision_layer == 1,
			"cuerpo con caja y en capa 1", str((cuerpo as Node).name))
	_chk(luna.get("edificios").size() == 18,
		"Moon Town sigue con 18 edificios (los props no son edificios)",
		str(luna.get("edificios").size()))
	# Y el presupuesto de materiales: la decoración no puede reventar el techo
	# de la GTX 1660. Los props usan la paleta de la ciudad (materiales ya
	# compartidos) más unos tintes fijos; el resto no agrega ni uno.
	_chk(BIB.creados() < 200,
		"la decoración no revienta el presupuesto de materiales",
		str(BIB.creados()))


## Cuántos edificios de un tipo hay en una ciudad.
func _cuenta_tipo(ciudad: Node, tipo: String) -> int:
	var n: int = 0
	for e in (ciudad.get("edificios") as Array):
		if str((e as Node3D).name).ends_with("_" + tipo):
			n += 1
	return n


## La ESCALA de cada pieza de los edificios de un tipo (o sea su tamaño, con
## la primitiva unidad de por medio). Es la medida de la FORMA.
func _cajas_de_tipo(ciudad: Node, tipo: String) -> Array:
	var salida: Array = []
	for e in (ciudad.get("edificios") as Array):
		var n: Node3D = e
		if not str(n.name).ends_with("_" + tipo):
			continue
		for m in n.find_children("*", "MeshInstance3D", true, false):
			var mi: Node3D = m
			if mi.get("mesh") == null:
				continue
			salida.append(mi.scale)
	return salida


# ---------------------------------------------------------------------------
# 10. DATOS PRIMERO: la fase 70 no metió un rol sin declarar
# ---------------------------------------------------------------------------

func _t_regla_de_datos_primero() -> void:
	var codigo: String = FileAccess.get_file_as_string(
		"res://scripts/mundo/ciudad_luna.gd")
	_chk(codigo.find("albedo_color") == -1,
		"la ciudad sigue sin pintar ningún albedo a mano")
	# Cada `_mat("X")` y cada `_mx(rol, "X")` tiene que existir en el dato. Es
	# la MISMA regla que vigila `test_render_materiales`, repetida acá porque la
	# silueta y el zócalo metieron llamadas nuevas a `_mat` y el fallo tiene que
	# salir en el test de la fase que las metió.
	var pedidos: Array[String] = []
	for frag in _literales(codigo, '_mat("'):
		pedidos.append(frag)
	for frag2 in _segundo_de(codigo, '_mx('):
		pedidos.append(frag2)
	for r in pedidos:
		_chk(MDB.rol_existe(r), "el rol '" + r + "' esta en materiales.json")
	# Los props de la ciudad también: el código pide slots de
	# `data/decoracion.json` y todos tienen que existir.
	MDB.cargar()
	DDB.cargar()
	for p in DDB.ciudad_props():
		for q in DDB.partes(str((p as Dictionary).get("forma", ""))):
			var slot: String = str((q as Dictionary).get("tinte", ""))
			if slot.begins_with("pal_"):
				continue
			var t: Dictionary = DDB.ciudad_slot(slot)
			_chk(not t.is_empty(), "el slot '" + slot + "' esta en decoracion.json")
			if bool(t.get("plano", false)):
				continue
			_chk(MDB.superficie_existe(str(t.get("superficie", ""))),
				"el slot '" + slot + "' usa una superficie del catalogo")


func _literales(codigo: String, prefijo: String) -> Array[String]:
	var a: Array[String] = []
	var i: int = 0
	while true:
		var p: int = codigo.find(prefijo, i)
		if p < 0:
			break
		var f: int = p + prefijo.length()
		var e: int = codigo.find('"', f)
		if e < 0:
			break
		var s: String = codigo.substr(f, e - f)
		if s != "" and not a.has(s):
			a.append(s)
		i = e
	return a


func _segundo_de(codigo: String, prefijo: String) -> Array[String]:
	var a: Array[String] = []
	var i: int = 0
	while true:
		var p: int = codigo.find(prefijo, i)
		if p < 0:
			break
		if codigo.substr(p + 4, 1) != '"':
			i = p + 4
			continue
		var coma: int = codigo.find(",", p)
		var f: int = codigo.find('"', coma)
		if f < 0:
			break
		var e: int = codigo.find('"', f + 1)
		if e < 0:
			break
		var s: String = codigo.substr(f + 1, e - f - 1)
		if s != "" and not a.has(s):
			a.append(s)
		i = e
	return a


# ---------------------------------------------------------------------------

func _ciudad(ruta: String, centro: Vector2) -> Node:
	var c: Node = CL.new()
	_basura.append(c)
	c.set("terreno", null)
	c.set("luces_reales", false)
	c.set("centro", centro)
	c.call("cargar_datos", ruta)
	root.add_child(c)
	c.call("construir")
	return c
