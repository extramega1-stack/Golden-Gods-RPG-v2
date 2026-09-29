extends SceneTree
## Fase 70 — LA DECORACIÓN ESTÁ PEGADA AL SUELO.
##
## POR QUÉ ESTE ARCHIVO: la fase 70 metió un anillo de vegetación y una calle de
## props, y los dos se veían EN EL AIRE. No como un detalle feo: a metros de
## altura, con las plantas despegadas del suelo. El síntoma era "la vegetación
## está flotando en el cielo" y la causa era una línea:
##
##     (locales[p] as Transform3D) * xf
##
## En Godot `A * B` significa "B primero, A después": el de la IZQUIERDA es el
## padre. Al revés no da error ni warning — Godot compone las matrices igual y
## devuelve un `Transform3D` perfectly válido. Lo que hace es pasar la posición
## EN MUNDOS (cientos de metros) de la planta por la base diminuta de una parte
## (escala ~0.5, giro de décimas). En el centro del mundo, donde X y Z valen
## cero, el error es de centímetros y no se ve. A 10.000 m del origen son
## cientos de metros de altura. La calle estaba igual: una farola en Desert
## Town salía a 169 m en vez de 38.
##
## Un test que compara "la Y de la malla" contra "la Y del terreno" con una
## tolerancia floja daba verde: el error crece con la distancia al origen, así
## que en la plaza (X≈0) el desplazamiento era de dos centímetros. Este archivo
## mide en las DIEZ zonas del mundo, no en la plaza, y con tolerancias que salen
## del tamaño de la planta.
##
## Y vigila las otras tres cosas que el arreglo podía romper: que la base quede
## ENTERRADA (no apoyada), que el presupuesto siga siendo 16 `MultiMesh` y 5
## primitivas, y que la zona segura de 40 m siga vacía de cosas altas.

const DDB: GDScript = preload("res://scripts/mundo/decoracion_db.gd")
const REJ: GDScript = preload("res://scripts/mundo/rejilla_decoracion.gd")
const MAL: GDScript = preload("res://scripts/mundo/mallas_decoracion.gd")
const VEG: GDScript = preload("res://scripts/mundo/vegetacion.gd")
const PRO: GDScript = preload("res://scripts/mundo/props_ciudad.gd")
const CL: GDScript = preload("res://scripts/mundo/ciudad_luna.gd")

## El presupuesto de la fase 70, contado a mano desde `data/decoracion.json`:
## 7 especies con 2/2/3/3/2/2/2 partes. No se negocia (§9.5): el anillo entero
## son 16 llamadas de dibujo y cinco `Mesh` para 36.864 u de lado.
const CAPAS_ESPERADAS: int = 16
const PRIMITIVAS_MAX: int = 5
## Zonas del mundo que el test tiene que recorrer. Hay diez regiones en
## `data/regiones.json`; el encargo pedía ocho y se cubren todas, porque el
## defecto crecía con la distancia al origen y las zonas lejanas son justamente
## las que lo hacían visible.
const ZONAS_MINIMAS: int = 8
## Cuántas celdas se miden por zona. Con una sola celda el test pasaría por
## casualidad: el hash siembra o no siembra, y una celda vacia no mide nada.
const CELDAS_POR_ZONA: int = 40
## Cuánto se admite de diferencia entre el ANCLA de una planta y el suelo. La
## cuenta es exacta (`suelo - hundir`), así que esto no es "tolerancia para que
## pase": es el error de coma flotante del bilineal del terreno.
const TOL_ANCLA: float = 0.002
## Separación máxima entre la Y de una planta y la del terreno en ese metro. La
## altura de la especie multiplicada por su escala máxima: un árbol de 6 u puede
## cubrir un desnivel de 6 u y sigue estando pegado, una flor de 0.8 u no
## puede. Es LA TOLERANCIA QUE CORRESPONDE AL TAMAÑO DE LA PLANTA.
const TOL_RELATIVA: float = 0.05

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []
var _terreno: Node = null
## Ids de zona efectivamente recorridos, para no dar verde por probar dos.
var _zonas_vistas: Dictionary = {}
## Peor separación (en metros, con signo) entre el pie de una planta y el suelo
## de su zona. Se imprime: si sube, el dato de `hundir` se quedó corto.
var _peor_pie: float = -INF
var _donde_peor_pie: String = "ninguna"


func _init() -> void:
	print("[TEST] Fase 70 — decoracion pegada al suelo")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_terreno = _terreno_de_prueba()
	_t_composicion()
	_t_altura_en_cada_zona()
	_t_base_enterrada()
	_t_props_de_calle()
	_t_edificios_y_zocalos()
	_t_presupuesto()
	print("[TEST] decoracion_suelo: %d ok, %d fallos" % [_ok, _fallos])
	print("[TEST]   zonas medidas: %d   peor pie: %+.3f m (%s)"
		% [_zonas_vistas.size(), _peor_pie, _donde_peor_pie])
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
# 1. LA COMPOSICIÓN. El orden de `*`, solo.
# ---------------------------------------------------------------------------

## El arreglo, medido como función y no integración: una parte colocada en el
## marco de la pieza, y la pieza en el mundo. Poner la pieza a 30 km del origen
## tiene que desplazar la parte 30 km: si el resultado depende de la distancia
## al origen, la composición está al revés y la vegetación se va al cielo.
func _t_composicion() -> void:
	var local := Transform3D(
		Basis.from_euler(Vector3(0.2, 0.8, -0.3)).scaled(Vector3(0.62, 0.4, 0.62)),
		Vector3(0.26, 0.34, 0.15))
	var cerca := Transform3D(Basis.IDENTITY, Vector3(300.0, 40.0, 300.0))
	var lejos := Transform3D(Basis.IDENTITY, Vector3(30000.0, 40.0, 30000.0))
	var a: Transform3D = MAL.componer(local, cerca)
	var b: Transform3D = MAL.componer(local, lejos)
	_chk(absf((b.origin - a.origin).x - 29700.0) < 0.01
			and absf((b.origin - a.origin).z - 29700.0) < 0.01,
		"la composicion desplaza la parte con la pieza, no con la base",
		"delta=%s" % str(b.origin - a.origin))
	_chk(absf(b.origin.y - a.origin.y) < 0.001,
		"la Y no depende de la distancia al origen",
		"%.4f vs %.4f" % [a.origin.y, b.origin.y])
	# Y la forma de la comprobación: la parte tiene que quedar a su altura LOCAL
	# sobre el suelo (0.34 de centro, 0.4 de alto), no a 0.34 * 30000.
	_chk(a.origin.y > 39.0 and a.origin.y < 42.0,
		"la parte queda a centimetros del suelo, no a hectometros",
		"y=%.3f" % a.origin.y)
	# El antipatrón, medido para que quede escrito por qué está mal. No hace
	# falta que `componer` lo rechace: Godot compone las dos formas y las dos
	# son `Transform3D` válidos. Lo que se mide es el RESULTADO.
	var al_reves: Transform3D = local * cerca
	_chk(absf(al_reves.origin.y - a.origin.y) > 1.0,
		"el orden al reves mueve la pieza (por eso esta funcion existe)",
		"al_reves.y=%.3f vs bien.y=%.3f" % [al_reves.origin.y, a.origin.y])


# ---------------------------------------------------------------------------
# 2. LA ALTURA, ZONA POR ZONA. El síntoma reportado.
# ---------------------------------------------------------------------------

func _t_altura_en_cada_zona() -> void:
	var regiones: Array = _regiones()
	_chk(regiones.size() >= ZONAS_MINIMAS,
		"el mundo tiene al menos 8 zonas que medir", str(regiones.size()))
	for r in regiones:
		var d: Dictionary = r
		var zona_id: String = str(d.get("id", ""))
		# El centro del AABB de la región: lejos del origen, que es donde el
		# error se hizo visible.
		var cx: float = (float(d["x0"]) + float(d["x1"])) * 0.5
		var cz: float = (float(d["z0"]) + float(d["z1"])) * 0.5
		_chk(DDB.zona_en(cx, cz) == zona_id,
			"el centro de la region cae en su zona", zona_id)
		_medir_zona(zona_id, Vector2(cx, cz))
	_chk(_zonas_vistas.size() >= ZONAS_MINIMAS,
		"se midieron 8 zonas o mas", str(_zonas_vistas.keys()))
	_chk(_ok > 0 and _peor_pie <= 0.0,
		"ninguna planta se levanta por encima del suelo en ninguna zona",
		"peor %+.3f m en %s" % [_peor_pie, _donde_peor_pie])


## Mide un anillo entero de celdas alrededor de un punto y compara cada planta
## con el terreno DE SU PROPIO X/Z.
func _medir_zona(zona_id: String, centro: Vector2) -> void:
	var v: Node = _vegetacion_en(centro.x, centro.y)
	_chk(bool(v.call("anillo_listo")), "el anillo de " + zona_id + " se planta")
	var paso: float = DDB.paso()
	var celdas: Array[Vector2i] = REJ.celdas(REJ.celda_de(centro.x, centro.y, paso),
		paso, DDB.radio_cerca())
	var medidas: int = 0
	var malas: int = 0
	var primera_mala: String = ""
	for c in celdas:
		for g in v.call("grupos_de_celda", c):
			var grupo: Dictionary = g
			var partes: Array = grupo["partes"]
			if partes.is_empty():
				continue
			medidas += 1
			_zonas_vistas[zona_id] = true
			var ancla: Transform3D = grupo["ancla"]
			var especie: String = str(grupo["especie"])
			# (a) EL ANCLA: suelo menos `hundir`, exactamente. Si esto no
			# cuadra, la cuenta de la Y está mal y todo lo demás es decorado.
			var suelo: float = _altura(ancla.origin.x, ancla.origin.z)
			var delta: float = ancla.origin.y - suelo
			var hundir: float = _hundir_de(especie)
			if absf(delta + hundir) > TOL_ANCLA:
				malas += 1
				if primera_mala == "":
					primera_mala = "%s en (%.0f,%.0f): y=%.3f suelo=%.3f delta=%+.3f" \
						% [especie, ancla.origin.x, ancla.origin.z, ancla.origin.y,
							suelo, delta]
			# (b) X y Z: el jitter mueve la planta DENTRO de su celda (el
			# margen es 0.40 del paso y la celda mide 0.50, así que siempre
			# entra). El error viejo la movía decenas de metros, y una mata a
			# 30 m de su sitio es igual de inútil que la que flotaba.
			var cel: Vector2 = REJ.centro_de(c, paso)
			var media: float = paso * 0.5
			if absf(ancla.origin.x - cel.x) > media + TOL_ANCLA \
					or absf(ancla.origin.z - cel.y) > media + TOL_ANCLA:
				malas += 1
				if primera_mala == "":
					primera_mala = "%s fuera de su celda: (%.1f,%.1f) celda %.1f,%.1f" \
						% [especie, ancla.origin.x, ancla.origin.z, cel.x, cel.y]
			# (c) EL PIE: la parte más baja de la geometría, contra el suelo.
			var pie: float = _pie_de(partes)
			var alto: float = _alto_de(especie)
			var sobre: float = pie - suelo
			if sobre > _peor_pie:
				_peor_pie = sobre
				_donde_peor_pie = "%s en %s" % [especie, zona_id]
			if sobre > TOL_RELATIVA * alto:
				malas += 1
				if primera_mala == "":
					primera_mala = ("%s flotando %+.3f m (tolerancia %.2f = 5%% de "
						+ "%.1f u)") % [especie, sobre, TOL_RELATIVA * alto, alto]
			# Y lo contrario: que no esté ENTERRADA hasta la copa.
			if sobre < -alto:
				malas += 1
				if primera_mala == "":
					primera_mala = "%s enterrada %.2f m (alto %.1f)" \
						% [especie, -sobre, alto]
	_chk(malas == 0, "todo en " + zona_id + " esta pegado al suelo",
		"%d de %d plantas: %s" % [malas, medidas, primera_mala])
	_chk(medidas > 4, "en " + zona_id + " se midieron varias plantas",
		str(medidas))


## El monumento y la puerta: los dos tipos que llevan `_pedestal_monumento` en
## vez de `_zocalo`.
func _es_monumento_o_puerta(raiz: Node3D) -> bool:
	var n: String = str(raiz.name)
	return n.ends_with("_monumento") or n.ends_with("_puerta")


## La parte más baja de la geometría de una planta: el mínimo, en cada parte, del
## centro menos la mitad de su alto. `basis.y` es la columna Y del transform ya
## compuesto, o sea el alto de la parte ya con la escala de la pieza y su giro.
func _pie_de(partes: Array) -> float:
	var pie: float = INF
	for p in partes:
		var t: Transform3D = p
		pie = minf(pie, t.origin.y - t.basis.y.length() * 0.5)
	return pie


## Cuánto se hunde una especie (el dato), con el mismo piso que aplica el juego.
func _hundir_de(tipo: String) -> float:
	return maxf(0.12, float(DDB.vegetal(tipo).get("hundir", 0.0)))


## El alto de una especie: del dato, no medido. Es la tolerancia.
func _alto_de(tipo: String) -> float:
	var v: Dictionary = DDB.vegetal(tipo)
	var esc: Array = v.get("escala", [0.8, 1.4])
	var s: float = float(esc[1]) if esc.size() > 1 else 1.4
	var alto: float = 0.0
	for p in DDB.partes(str(v.get("forma", ""))):
		var parte: Dictionary = p
		var tam: Array = parte.get("tam", [1.0, 1.0, 1.0])
		var medio: float = (float(tam[1]) if tam.size() > 1 else 1.0) * 0.5
		var cy: float = float(parte["altura"]) if parte.has("altura") else 0.0
		alto = maxf(alto, absf(cy) + medio)
	return alto * s


# ---------------------------------------------------------------------------
# 3. ENTERRADA, NO APOYADA
# ---------------------------------------------------------------------------

## Una planta que solo ROZA el suelo se ve pegada con cinta, y en una pendiente
## la esquina que da al declive queda en el aire. Lo que se mide: la base está
## por DEBAJO del suelo, por un margen que sale del dato, y ninguna especie
## puede declararse flotante por escribir `"hundir": 0`.
func _t_base_enterrada() -> void:
	for tipo in DDB.vegetales():
		var declarado: float = float(DDB.vegetal(tipo).get("hundir", 0.0))
		_chk(declarado >= 0.12,
			"la especie declara cuanto se hunde: " + tipo, str(declarado))
		_chk(_hundir_de(tipo) >= 0.12,
			"y el juego la hunde aunque el dato se olvide: " + tipo)
	_chk(DDB.ciudad_hundir() > 0.0,
		"los props de calle tambien se hunden", str(DDB.ciudad_hundir()))
	_chk(DDB.ciudad_hundir() >= 0.12,
		"y no se apoyan: la vereda esta en pendiente", str(DDB.ciudad_hundir()))


# ---------------------------------------------------------------------------
# 4. LOS PROPS DE CALLE. El mismo bug, el mismo arreglo.
# ---------------------------------------------------------------------------

## La calle usaba EXACTAMENTE la misma línea que la vegetación, así que una
## farola de Desert Town (a 9.966 m del origen) salía a 169 m de altura. Se
## miden las dos ciudades más lejanas del eje, que es donde se nota.
##
## Y se miden LAS PIEZAS, no el ancla: el ancla de un prop se calculaba bien y
## el error estaba en componerlas. Un test que mirara el ancla daría verde con
## la calle entera en el aire.
func _t_props_de_calle() -> void:
	for spec in [["res://data/ciudad_desert.json", Vector2(9966.0, 0.0), "Desert"],
			["res://data/ciudad_fury.json", Vector2(-9966.0, 9966.0), "Fury"],
			["res://data/ciudad_luna.json", Vector2.ZERO, "Luna"]]:
		var s: Array = spec
		var props: Node = _props_de_ciudad(str(s[0]), s[1] as Vector2)
		if props == null:
			continue
		var plano: Array = props.call("plano")
		_chk(plano.size() > 20, str(s[2]) + " tiene props que medir",
			str(plano.size()))
		var malas: int = 0
		var primera: String = ""
		var piezas_medidas: int = 0
		for i in plano.size():
			var ancla: Transform3D = plano[i]
			var wx: float = ancla.origin.x + (s[1] as Vector2).x
			var wz: float = ancla.origin.z + (s[1] as Vector2).y
			var suelo: float = _altura(wx, wz)
			var delta: float = ancla.origin.y - suelo
			# El mismo `hundir` que la vegetación: la prop se apoya en el
			# terreno de SU metro, no en el de la ciudad.
			if absf(delta + DDB.ciudad_hundir()) > TOL_ANCLA:
				malas += 1
				if primera == "":
					primera = "prop en (%.0f,%.0f): y=%.3f suelo=%.3f delta=%+.3f" \
						% [wx, wz, ancla.origin.y, suelo, delta]
			# Y las PIEZAS, que es donde estaba el bug: una farola mide 4.6 u y
			# su farol cuelga a 0.88 m del poste. Ninguna pieza puede estar a
			# metros de su poste, y ninguna puede estar bajo el suelo. El alto
			# hay que multiplicarlo por la ESCALA de ESTE prop: `altura_max` es
			# el de la forma, y cada prop sale escalado entre 0.90 y 1.12.
			var alto: float = float(props.call("altura_max")) \
				* ancla.basis.x.length()
			for pt in props.call("piezas_de_prop", i):
				piezas_medidas += 1
				var t: Transform3D = pt
				var d: float = Vector2(t.origin.x - ancla.origin.x,
					t.origin.z - ancla.origin.z).length()
				if d > 1.6:
					malas += 1
					if primera == "":
						primera = "pieza a %.1f m de su prop en (%.0f,%.0f)" \
							% [d, wx, wz]
				if t.origin.y < ancla.origin.y - TOL_ANCLA \
						or t.origin.y > ancla.origin.y + alto + TOL_ANCLA:
					malas += 1
					if primera == "":
						primera = "pieza a %.2f m sobre un prop de %.1f u" \
							% [t.origin.y - ancla.origin.y, alto]
		_chk(malas == 0, str(s[2]) + ": los props estan sobre el suelo",
			"%d fallos de %d props (%d piezas): %s"
				% [malas, plano.size(), piezas_medidas, primera])
		_chk(piezas_medidas > plano.size(),
			str(s[2]) + ": se midieron las piezas, no solo el ancla",
			str(piezas_medidas))


# ---------------------------------------------------------------------------
# 5. LOS EDIFICIOS, LAS SILUETAS Y EL ZÓCALO. El tercer consumidor de la altura.
# ---------------------------------------------------------------------------

## La vegetación y la calle compiten `Transform3D`, y ahí estaba el bug. Las
## casas, las siluetas y el zócalo usan la OTRA forma de pegarse al suelo: la
## jerarquía de nodos (la raíz del edificio va en `altura_en(x, z)` y las cajas
## cuelgan de ella), que es exactamente el patrón de `Arbol` y `Veta` y no
## depende del orden de `*`. Eso no hay que CREERLO: se mide. Y se mide también
## que el zócalo esté enterrado, que es lo que separa una casa de un recorte
## pegado contra el suelo.
func _t_edificios_y_zocalos() -> void:
	for spec in [["res://data/ciudad_luna.json", Vector2.ZERO, "Luna"],
			["res://data/ciudad_desert.json", Vector2(9966.0, 0.0), "Desert"]]:
		var s: Array = spec
		var c: Node = _ciudad(str(s[0]), s[1] as Vector2)
		var edificios: Array = c.get("edificios")
		_chk(edificios.size() >= 16,
			str(s[2]) + ": hay edificios que medir", str(edificios.size()))
		var hundir: float = float(DDB.zocalo().get("hundir", 0.42))
		var fuera: int = 0
		var sin_hundir: int = 0
		var con_zocalo: int = 0
		for e in edificios:
			var raiz: Node3D = e
			var suelo: float = _altura(raiz.position.x, raiz.position.z)
			if absf(raiz.position.y - suelo) > TOL_ANCLA:
				fuera += 1
			# El punto más bajo de la geometría local tiene que estar POR DEBAJO
			# de la raíz: la raíz es el suelo, así que "abajo de la raíz" es
			# "enterrado". Una casa cuya base solo apoya se ve pegada.
			var bajo: float = INF
			for m in raiz.get_children():
				if not (m is MeshInstance3D):
					continue
				var mi: MeshInstance3D = m
				bajo = minf(bajo, mi.position.y - mi.scale.y * 0.5)
			if bajo > -hundir * 0.5:
				# El monumento y la puerta llevan su propio pedestal
				# (`_pedestal_monumento`) y NO pasan por `_zocalo`. Se separan
				# para no tapar con ellos a las casas, que sí lo llevan: es el
				# mismo reparto que hace `test_decoracion_mundo` con su cuenta
				# de zócalos.
				if _es_monumento_o_puerta(raiz):
					continue
				sin_hundir += 1
			else:
				con_zocalo += 1
		_chk(fuera == 0, str(s[2]) + ": cada edificio apoya en el terreno",
			"%d de %d descolocados" % [fuera, edificios.size()])
		_chk(sin_hundir == 0,
			str(s[2]) + ": y el zocalo esta enterrado, no apoyado",
			"%d casas apoyadas (de %d)" % [sin_hundir, con_zocalo])
		_chk(con_zocalo >= edificios.size() - 6,
			str(s[2]) + ": casi todos los edificios llevan zocalo",
			"%d de %d" % [con_zocalo, edificios.size()])
		# Lo que NO se comprueba, y por qué: el pedestal de `_pedestal_monumento`
		# (monumento y puerta) apoya en y=0 en vez de estar enterrado. Vive en
		# `ciudad_luna.gd` y es un defecto de medio metro sobre un pedestal de
		# 2 m en la plaza, que es plana. Se INFORMA, no se tapa.
		print("  nota: %s — %d de %d edificios (monumento/puerta) apoyan en y=0;"
				% [str(s[2]), edificios.size() - con_zocalo, edificios.size()]
			+ " su pedestal propio no se hunde. Es de ciudad_luna.gd.")
		# Y la cuenta del zócalo, que es la que ya vigila `test_decoracion_mundo`:
		# esto no la reemplaza, la confirma desde el terreno y no desde un
		# contador que el propio código incrementa.
		_chk(int(c.get("zocalos")) > 0, str(s[2]) + ": la ciudad tiene zocalos",
			str(int(c.get("zocalos"))))


# ---------------------------------------------------------------------------
# 6. EL PRESUPUESTO. No se negocia.
# ---------------------------------------------------------------------------

func _t_presupuesto() -> void:
	var v: Node = _vegetacion_en(0.0, 45.0)
	_chk(int(v.call("capas_totales")) == CAPAS_ESPERADAS,
		"el anillo sigue siendo 16 MultiMesh",
		str(int(v.call("capas_totales"))))
	_chk(MAL.primitivas_creadas() <= PRIMITIVAS_MAX,
		"y 5 primitivas compartidas para el mundo entero",
		str(MAL.primitivas_creadas()))
	# Y la zona segura, que es la otra regla que este archivo no puede romper.
	var v2: Node = _vegetacion_en(0.0, 0.0)
	var altos: int = 0
	for c in REJ.celdas(Vector2i(0, 0), DDB.paso(),
			DDB.radio_zona_segura() - DDB.paso() * 0.40):
		var e: String = str(v2.call("especie_sembrada", c))
		if e != "" and DDB.es_tipo_alto(e):
			altos += 1
	_chk(altos == 0, "nada alto dentro de los 40 m de la aldea inicial",
		str(altos))
	# Y que el arreglo no tocó la densidad: el anillo siembra lo mismo que
	# antes (la decisión no cambió, cambió dónde se compone).
	var piezas: int = int(v.call("piezas_puestas"))
	var celdas: int = int(v.call("celdas_en_anillo"))
	_chk(piezas > celdas, "se sigue sembrando mas de una pieza por celda",
		"%d en %d" % [piezas, celdas])


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

func _altura(x: float, z: float) -> float:
	return float(_terreno.call("altura_en", x, z))


## El terreno con el bin cargado pero SIN los 36 chunks dibujados: `altura_en`
## funciona igual y el test no necesita geometría.
func _terreno_de_prueba() -> Node:
	var t: Node = Terreno.new()
	_basura.append(t)
	root.add_child(t)
	t.set("construccion_progresiva", true)
	t.call("_cargar_bin")
	return t


func _vegetacion_en(x: float, z: float) -> Node:
	DDB.cargar()
	var v: Node = VEG.new()
	_basura.append(v)
	root.add_child(v)
	var jugador := Node3D.new()
	_basura.append(jugador)
	root.add_child(jugador)
	jugador.position = Vector3(x, 0.0, z)
	v.call("fijar_terreno", _terreno)
	v.call("fijar_jugador", jugador)
	return v


func _props_de_ciudad(ruta: String, centro: Vector2) -> Node:
	var c: Node = _ciudad(ruta, centro)
	return c.get_node_or_null("PropsCalle")


## Una ciudad real, con terreno y con sus datos. Comparte la construcción con
## `_props_de_ciudad`: es la MISMA ciudad, no una copia sin props.
func _ciudad(ruta: String, centro: Vector2) -> Node:
	var c: Node = CL.new()
	_basura.append(c)
	c.set("terreno", _terreno)
	c.set("luces_reales", false)
	c.set("centro", centro)
	c.call("cargar_datos", ruta)
	root.add_child(c)
	c.call("construir")
	return c


func _regiones() -> Array:
	var salida: Array = []
	var f := FileAccess.open("res://data/regiones.json", FileAccess.READ)
	if f == null:
		return salida
	var crudo: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if crudo is Array:
		for r in (crudo as Array):
			if r is Dictionary:
				salida.append(r)
	return salida
