extends SceneTree
## Fase 69 — que el mundo deje de ser color plano: materiales procedurales.
##
## POR QUÉ ESTE ARCHIVO: el mundo tenía 9 ciudades y 146 edificios hechos de
## primitivas con `albedo_color` plano, 58 veces en el mismo archivo. Este test
## vigila las TRES cosas que pueden volver a romperlo, y las tres se rompen
## calladitas (una textura que no tilea se ve mal, no falla):
##
## 1. DATOS PRIMERO. Si aparece un `_mat("nuevo")` en el código sin su entrada
##    en `data/materiales.json`, este test se pone rojo. Ese es el punto: el
##    color dejó de estar en el `.gd`.
## 2. CACHÉ. La segunda llamada tiene que devolver LA MISMA textura. Si
##    hornea por demanda en el bucle caliente, esto se pone rojo (y §9.5 con
##    él): es un tiron de frame por edificio, no un error visible.
## 3. DETERMINISMO. Misma posición -> mismo material, siempre. Un save que
##    reconstruye el mundo desde cero tiene que devolver la misma casa con la
##    misma veta; si la semilla fuera un contador o un `rand`, la calle
##    cambiaría de color entre sesiones y no se notaría hasta que dos sesiones
##    seguidas se ven distintas.

const MDB: GDScript = preload("res://scripts/render/materiales_db.gd")
const GEN: GDScript = preload("res://scripts/render/generador_texturas.gd")
const BIB: GDScript = preload("res://scripts/render/biblioteca_materiales.gd")
const CL: GDScript = preload("res://scripts/mundo/ciudad_luna.gd")

const RUTA_CIUDAD: String = "res://scripts/mundo/ciudad_luna.gd"
## Las 8 superficies del catálogo, resueltas una vez por test.
var _texturas: Array[String] = []

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 69 — materiales procedurales")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_catalogo()
	_test_texturas_tamano()
	_test_cache_de_texturas()
	_test_cache_de_materiales()
	_test_triplanar()
	_test_tilable()
	_test_patrones_en_el_mapa()
	_test_variacion()
	_test_determinismo()
	_test_reconstruccion()
	_test_ciudad_completa()
	print("[TEST] render_materiales: %d ok, %d fallos" % [_ok, _fallos])
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

## 1. El catálogo: las 8 superficies, con presupuesto de VRAM declarado.
func _test_catalogo() -> void:
	MDB.limpiar()
	MDB.cargar()
	var sups: Array[String] = MDB.superficies()
	_chk(sups.size() >= 7, "hay 7 superficies de superficie", str(sups))
	for id in ["piedra", "madera", "yeso", "teja", "tierra", "pasto", "metal"]:
		_chk(MDB.superficie_existe(id), "superficie declarada: " + id)
	var px: int = MDB.textura_px()
	_chk(px >= 32 and px <= 512, "textura_px razonable", str(px))
	_chk(MDB.variantes() >= 2, "hay al menos 2 variantes para variar", str(MDB.variantes()))
	_chk(MDB.rol_existe("muro_a"), "el rol muro_a existe")
	_chk(MDB.rol_existe("ventana"), "el rol ventana existe")
	# Presupuesto de VRAM (§9.5): el total sale del dato, y se avisa si se
	# dispara. 8 sup x 4 var x 3 mapas x 128² x 4 B = 6,3 MB con mipmaps.
	var bytes_tex: int = sups.size() * MDB.variantes() * 3 * px * px * 4
	var mb: float = float(bytes_tex) * 1.34 / 1048576.0
	_chk(mb <= 24.0, "el horneado cabe en el presupuesto de VRAM", "%.1f MB" % mb)
	for id in sups:
		var s: Dictionary = MDB.superficie(id)
		_chk(s.has("escala_uv") and float(s.get("escala_uv", 0.0)) > 0.0,
			"la superficie declara escala_uv: " + id)
		_chk(str(s.get("patron", {}).get("tipo", "")) != "",
			"la superficie declara patron: " + id)


## 2. Dos materiales DISTINTOS, con el tamaño correcto.
func _test_texturas_tamano() -> void:
	GEN.limpiar()
	var px: int = MDB.textura_px()
	for id in ["piedra", "madera"]:
		var c: Dictionary = GEN.conjunto(id, 0)
		_chk(not c.is_empty(), "conjunto horneado: " + id)
		for clave in [GEN.CLAVE_ALBEDO, GEN.CLAVE_NORMAL, GEN.CLAVE_ORM]:
			var t: Texture2D = c[clave] as Texture2D
			_chk(t != null, "%s de %s existe" % [clave, id])
			if t != null:
				_chk(t.get_width() == px and t.get_height() == px,
					"%s de %s mide %d" % [clave, id, px], str(t.get_size()))
	# Dos superficies distintas no pueden compartir el mismo mapa de normal: si
	# lo compartieran, la piedra y la madera tendrían el mismo relieve.
	var a: Dictionary = GEN.conjunto("piedra", 0)
	var b: Dictionary = GEN.conjunto("madera", 0)
	_chk(a[GEN.CLAVE_NORMAL] != b[GEN.CLAVE_NORMAL],
		"piedra y madera no comparten normal map")
	_chk(a[GEN.CLAVE_ALBEDO] != b[GEN.CLAVE_ALBEDO],
		"piedra y madera no comparten albedo")
	# Y la ORM tiene que traer los tres canales: si el B (metalicidad) fuera
	# cero en metal, el metal del mundo salía como plástico.
	var om: Texture2D = GEN.conjunto("metal", 0)[GEN.CLAVE_ORM] as Texture2D
	var om2: Texture2D = GEN.conjunto("piedra", 0)[GEN.CLAVE_ORM] as Texture2D
	_chk(_canal(om, 2) > 0.75, "la ORM del metal trae metallicidad en B",
		str(_canal(om, 2)))
	_chk(_canal(om2, 2) < 0.2, "la ORM de la piedra no trae metallicidad",
		str(_canal(om2, 2)))
	# El canal R tiene que traer oclusion de verdad, no un 1 plano: una
	# "oclusion" constante es una linea de codigo que no hace nada.
	_chk(_canal(om2, 0) < 0.98, "la ORM trae oclusion horneada en R",
		str(_canal(om2, 0)))


## 3. La segunda llamada NO hornea nada: es la regla de "cero allocs en la
##    caliente". Este es el test que caza un `Image.new()` por fotograma.
func _test_cache_de_texturas() -> void:
	GEN.limpiar()
	var antes: int = GEN.horneadas()
	var p1: Dictionary = GEN.conjunto("teja", 1)
	var medio: int = GEN.horneadas()
	_chk(medio == antes + 1, "la primera llamada hornea 1", "%d -> %d" % [antes, medio])
	for _i in 20:
		var p2: Dictionary = GEN.conjunto("teja", 1)
		_chk(p1[GEN.CLAVE_ALBEDO] == p2[GEN.CLAVE_ALBEDO], "misma instancia de albedo")
		_chk(p1[GEN.CLAVE_NORMAL] == p2[GEN.CLAVE_NORMAL], "misma instancia de normal")
		_chk(p1[GEN.CLAVE_ORM] == p2[GEN.CLAVE_ORM], "misma instancia de ORM")
	_chk(GEN.horneadas() == medio, "20 llamadas más no hornean nada más",
		"%d -> %d" % [medio, GEN.horneadas()])
	_chk(GEN.claves().size() == 1, "una sola clave en el cache", str(GEN.claves()))
	# Variante distinta -> textura distinta (si no, la variación no variation).
	var v2: Dictionary = GEN.conjunto("teja", 2)
	_chk(p1[GEN.CLAVE_ALBEDO] != v2[GEN.CLAVE_ALBEDO],
		"la variante 2 no es la variante 1")


## 4. Dos materiales con el MISMO tinte y la MISMA superficie son la misma
##    instancia; los distintos no. Y el color sale del dato.
func _test_cache_de_materiales() -> void:
	BIB.limpiar()
	var antes: int = BIB.creados()
	var m1: StandardMaterial3D = BIB.material("piedra", "#b89e80", 0, false)
	var m2: StandardMaterial3D = BIB.material("piedra", "#b89e80", 0, false)
	_chk(m1 == m2, "el mismo rol devuelve el MISMO material")
	_chk(BIB.creados() == antes + 1, "crear el mismo rol no crea un material",
		"%d -> %d" % [antes, BIB.creados()])
	var m3: StandardMaterial3D = BIB.material("madera", "#b89e80", 0, false)
	_chk(m1 != m3, "otra superficie es otro material")
	_chk(m1.albedo_texture == m3.albedo_texture == false,
		"y con texturas propias")
	var m4: StandardMaterial3D = BIB.material("piedra", "#000000", 0, false)
	_chk(m1 != m4, "otro tinte es otro material")
	# Dos tintes de la MISMA superficie y variante comparten la textura: es lo
	# que hace que 146 edificios no cuesten 146 juegos de texturas.
	_chk(m1.albedo_texture == m4.albedo_texture,
		"el tinte no paga la textura: se comparte")
	# El color viene del dato, no del código.
	var esperado: Color = Color.html("#b89e80")
	var luz: float = esperado.get_luminance()
	_chk(absf(m1.albedo_color.get_luminance() - luz) < 0.25,
		"el albedo sale del tinte del dato",
		"%s vs %s" % [str(m1.albedo_color), str(esperado)])
	_chk(m1.albedo_color.r > m1.albedo_color.b, "el tinte #b89e80 es cálido")


## 5. El TRIPLANAR: sin esto una caja de 24 m muestra la textura estirada,
##    que es el defecto exacto que se vino a tapar.
func _test_triplanar() -> void:
	BIB.limpiar()
	var m: StandardMaterial3D = BIB.material("piedra", "#8d877f", 0, false)
	_chk(m.uv1_triplanar, "uv1_triplanar activo")
	_chk(m.uv1_world_triplanar, "uv1_world_triplanar activo (proyección en mundo)")
	_chk(m.texture_repeat, "las texturas repiten (si no, el triplanar se apaga)")
	# uv1_scale multiplica la posición de mundo: 1/escala_uv = un tile cada N m.
	var esc: float = float(MDB.superficie("piedra").get("escala_uv", 3.0))
	var jitter: float = float(MDB.variacion().get("uv_escala", 0.0))
	var lo: float = 1.0 / esc * (1.0 - jitter) - 0.001
	var hi: float = 1.0 / esc * (1.0 + jitter) + 0.001
	_chk(m.uv1_scale.x >= lo and m.uv1_scale.x <= hi,
		"la escala del triplanar sale de la superficie (+- el jitter del dato)",
		"%s fuera de [%f, %f]" % [str(m.uv1_scale), lo, hi])
	_chk(absf(m.uv1_scale.x - 1.0 / esc) < 0.3 / esc,
		"y no se va de madre: un tile cada ~%d m" % int(esc))
	_chk(m.normal_enabled and m.normal_texture != null, "el normal map está puesto")
	_chk(m.roughness_texture != null, "la ORM está puesta")
	_chk(m.roughness_texture == m.metallic_texture,
		"rugosidad y metallicidad leen el MISMO archivo (ORM)")
	_chk(m.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN,
		"la rugosidad lee el canal G",
		str(m.roughness_texture_channel))
	_chk(m.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE,
		"la metallicidad lee el canal B", str(m.metallic_texture_channel))


## 6. El tile TIENQUE ENVOLVER. Es el test que hace falta porque una textura
##    que no tilea no falla: se ve mal, y solo se nota de lejos.
func _test_tilable() -> void:
	GEN.limpiar()
	var px: int = MDB.textura_px()
	for id in ["piedra", "teja", "tierra"]:
		var img: Image = (GEN.conjunto(id, 0)[GEN.CLAVE_ALBEDO] as Texture2D).get_image()
		var dentro: float = 0.0
		var vuelta: float = 0.0
		for i in px:
			var a: Color = img.get_pixel(px - 1, i)
			var b: Color = img.get_pixel(0, i)
			vuelta += absf(a.v - b.v)
			var c2: Color = img.get_pixel(0, i)
			var d: Color = img.get_pixel(1, i)
			dentro += absf(c2.v - d.v)
		var dv: float = vuelta / float(px)
		var dd: float = dentro / float(px)
		# El salto del borde (última -> primera columna) tiene que ser del
		# mismo orden que un salto normal. Si no envuelve, `vuelta` >> `dentro`.
		_chk(dv <= dd * 3.0 + 0.02, "la textura de " + id + " envuelve",
			"borde=%.4f interior=%.4f" % [dv, dd])


## 7. El PATRÓN está en el mapa, no solo en el color: la piedra tiene
##    sillares y la madera vetas, y eso se ve como contraste local.
func _test_patrones_en_el_mapa() -> void:
	GEN.limpiar()
	MDB.limpiar()
	MDB.cargar()
	_texturas = MDB.superficies()
	# El PATRÓN (sillares, hiladas de teja, urdimbre) vive en el relieve, así
	# que se mide en el NORMAL y no en el albedo: el albedo lo domina el grano
	# fino, que es el mismo en todas las superficies y no probaría nada.
	var s_piedra: float = _relieve(GEN.conjunto("piedra", 0)[GEN.CLAVE_NORMAL])
	var s_yeso: float = _relieve(GEN.conjunto("yeso", 0)[GEN.CLAVE_NORMAL])
	var s_teja: float = _relieve(GEN.conjunto("teja", 0)[GEN.CLAVE_NORMAL])
	var s_tela: float = _relieve(GEN.conjunto("tela", 0)[GEN.CLAVE_NORMAL])
	_chk(s_piedra > s_yeso * 1.5,
		"la piedra (sillares) tiene mas relieve que el yeso (sin patron)",
		"piedra=%.4f yeso=%.4f" % [s_piedra, s_yeso])
	_chk(s_teja > s_yeso * 1.5, "la teja (hiladas) tiene mas relieve que el yeso",
		"teja=%.4f yeso=%.4f" % [s_teja, s_yeso])
	_chk(s_tela > s_yeso * 1.5, "la tela (urdimbre) tiene mas relieve que el yeso",
		"tela=%.4f yeso=%.4f" % [s_tela, s_yeso])
	_chk(s_piedra > 0.05, "el normal map de la piedra NO es plano", str(s_piedra))
	for id in _texturas:
		_chk(_desviacion(GEN.conjunto(id, 0)[GEN.CLAVE_ALBEDO]) > 0.02,
			"el albedo de " + id + " no es plano")


## 8. La VARIACIÓN: dos edificios del mismo tipo en distinta posición NO se
##    ven idénticos, y el que no declara `variar` no cambia nunca.
func _test_variacion() -> void:
	BIB.limpiar()
	var n_var: int = MDB.variantes()
	var tintes: Dictionary = {}
	for v in n_var:
		var m: StandardMaterial3D = BIB.material("yeso", "#b89e80", v, true)
		tintes[m.albedo_color] = true
	_chk(tintes.size() > 1, "cada variante cambia el tinte", str(tintes.size()))
	var fases: Dictionary = {}
	for v in n_var:
		fases[BIB.material("yeso", "#b89e80", v, true).uv1_offset] = true
	_chk(fases.size() == n_var, "cada variante cambia la fase del grano",
		"%d de %d" % [fases.size(), n_var])
	# Sin `variar`, la semilla se ignora: un remache no cambia de tono por calle.
	var a: StandardMaterial3D = BIB.material("piedra", "#4e505a", 0, false)
	var b: StandardMaterial3D = BIB.material("piedra", "#4e505a", 999, false)
	_chk(a == b, "un rol que no varia ignora la semilla")
	# Un barrio de 20 casas reparte el grano: si las 20 salieran en la misma
	# variante, el barrio sería una fotocopia.
	BIB.limpiar()
	var usadas: Dictionary = {}
	for i in 20:
		var s: int = BIB.semilla_de(float(i) * 37.0, float(i) * 17.0)
		usadas[posmod(s, n_var)] = true
	_chk(usadas.size() >= mini(3, n_var), "un barrio de 20 reparte las variantes",
		str(usadas.keys()))


## 9. DETERMINISMO de la semilla. Sin esto un save deja de poder reconstruir
##    el mundo: las casas cambiarían de color entre sesiones.
func _test_determinismo() -> void:
	var s1: int = BIB.semilla_de(123.0, -456.0)
	var s2: int = BIB.semilla_de(123.0, -456.0)
	_chk(s1 == s2, "la misma posicion da la misma semilla")
	_chk(s1 >= 0, "la semilla es positiva", str(s1))
	_chk(BIB.semilla_de(123.0, -456.0) == s1, "y no cambia entre llamadas")
	_chk(BIB.semilla_de(124.0, -456.0) != s1, "un metro de mas cambia la semilla")
	_chk(BIB.semilla_de(123.0, -455.0) != s1, "un metro de z cambia la semilla")
	# Fracción sub-metro: el snapping de la construcción no debe notarse.
	_chk(BIB.semilla_de(123.4, 456.7) == BIB.semilla_de(123.0, 456.0),
		"la semilla es por celda entera, no por metro exacto")
	# Reconstruir desde cero: mismo tinte, misma fase, mismo material.
	BIB.limpiar()
	var antes: StandardMaterial3D = BIB.material("yeso", "#b89e80", s1, true)
	var color: Color = antes.albedo_color
	var fase: Vector3 = antes.uv1_offset
	var escala: Vector3 = antes.uv1_scale
	BIB.limpiar()
	GEN.limpiar()
	var despues: StandardMaterial3D = BIB.material("yeso", "#b89e80",
		BIB.semilla_de(123.0, -456.0), true)
	_chk(despues.albedo_color == color, "tras borrar el cache, el tinte es el mismo",
		"%s vs %s" % [str(despues.albedo_color), str(color)])
	_chk(despues.uv1_offset == fase, "y la fase del grano tambien",
		"%s vs %s" % [str(despues.uv1_offset), str(fase)])
	_chk(despues.uv1_scale == escala, "y la escala del triplanar tambien")


## 10. La prueba de fuego: dos ciudades iguales dan los mismos materiales, y
##     una ciudad con N edificios no crea N materiales.
func _test_reconstruccion() -> void:
	BIB.limpiar()
	GEN.limpiar()
	# La ciudad llama a `precalentar()` en su `_ready`; acá se llama a mano
	# para que los dos traversales arranquen del MISMO estado y la comparación
	# sea de la ciudad y no de si el horneado anticipado corrió o no.
	BIB.precalentar()
	var firma1: Array[String] = _firma_de_ciudad()
	var tex1: String = ",".join(GEN.claves())
	BIB.limpiar()
	GEN.limpiar()
	BIB.precalentar()
	var firma2: Array[String] = _firma_de_ciudad()
	var tex2: String = ",".join(GEN.claves())
	_chk(firma1 == firma2, "la ciudad se reconstruye identica desde el save",
		"%d vs %d entradas; distinta en %s" % [firma1.size(), firma2.size(),
			str(_primera_diferencia(firma1, firma2))])
	_chk(tex1 == tex2 and not tex1.is_empty(),
		"y hornea exactamente el mismo juego de texturas")
	_chk(firma1.size() > 0, "la firma no esta vacia")
	# Y el presupuesto: 146 edificios no pueden crear 146 materiales.
	BIB.limpiar()
	GEN.limpiar()
	_construir_ciudad()
	var creados: int = BIB.creados()
	_chk(creados < 200, "una ciudad completa no revienta el presupuesto de materiales",
		str(creados))
	_chk(GEN.horneadas() <= 40, "y no hornea mas texturas de las del catalogo",
		str(GEN.horneadas()))


## 11. Regla de datos primero, vigilada: si el codigo pide un rol que el dato
##     no declara, este test se pone rojo.
func _test_ciudad_completa() -> void:
	var codigo: String = FileAccess.get_file_as_string(RUTA_CIUDAD)
	_chk(not codigo.is_empty(), "se pudo leer " + RUTA_CIUDAD)
	_chk(codigo.find("albedo_color") == -1,
		"el codigo de la ciudad no pinta ningun albedo a mano")
	_chk(not codigo.contains("COLORES"),
		"y no lleva su propia tabla de colores")
	# Cada `_mat("X")` y cada `_mx(rol, "X")` tiene que existir en el dato.
	var pedidos: Array[String] = []
	for frag in _literales(codigo, '_mat("'):
		pedidos.append(frag)
	# De `_mx(rol, defecto)` el que se pide a la Biblioteca es el SEGUNDO
	# argumento (el nombre del rol), no el primero (la clave de paleta).
	for frag in _segundo_de(codigo, '_mx('):
		pedidos.append(frag)
	_chk(pedidos.size() >= 26, "se detectan los roles que pide el codigo",
		str(pedidos.size()))
	for r in pedidos:
		_chk(MDB.rol_existe(r), "el rol '" + r + "' esta en materiales.json")
	# Y a la inversa, ningún rol del catálogo sin usar: un rol muerto es un
	# color que alguien estuvo a punto de borrar.
	for r in MDB.roles():
		_chk(pedidos.has(r) or r == "tormenta",
			"el rol '" + r + "' lo usa alguien", str(r))


# ---------------------------------------------------------------------------

## Los materiales que una ciudad puts en sus edificios, en orden. Es la
## "huella digital" de la construcción: si dos traversales dan la misma, el
## mundo es reconstruible.
func _firma_de_ciudad() -> Array[String]:
	var c: Node = _construir_ciudad()
	var firma: Array[String] = []
	var mallas: Array[MeshInstance3D] = []
	_recolectar(c, mallas)
	for m in mallas:
		var mat: Material = m.material_override
		if mat is StandardMaterial3D:
			var sm: StandardMaterial3D = mat as StandardMaterial3D
			# OJO: acá NO va `str(texture)`: es un instance_id que cambia entre
			# procesos, y la firma compararía dos enteros que nunca coinciden.
			# La identidad de las texturas se comprueba aparte, con las claves
			# del cache, que sí son estables.
			firma.append("%s|%.5f|%.5f|%.5f|%.4f|%.3f" % [str(sm.albedo_color),
				sm.uv1_offset.x, sm.uv1_offset.y, sm.uv1_scale.x, sm.roughness,
				sm.metallic])
	return firma


func _construir_ciudad() -> Node:
	var c: Node = CL.new()
	c.set("terreno", null)
	c.set("luces_reales", false)
	c.call("cargar_datos", "res://data/ciudad_desert.json")
	_basura.append(c)
	# Al arbol: hay piezas (antorchas, banderas) que leen su transform global.
	root.add_child(c)
	c.call("construir")
	return c


func _recolectar(n: Node, fuera: Array[MeshInstance3D]) -> void:
	for hijo in n.get_children():
		if hijo is MeshInstance3D:
			fuera.append(hijo as MeshInstance3D)
		_recolectar(hijo, fuera)


## Los identificadores que siguen a un prefijo en el código: `_mat("piedra"`
## -> ["piedra", ...]. Es un chequeo de datos primero hecho sobre el `.gd`.
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


func _primera_diferencia(a: Array[String], b: Array[String]) -> String:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return "#%d %s != %s" % [i, a[i], b[i]]
	return "(solo cambia el tamano)"


## La segunda cadena de `_mx(`: `_mx("muro", "muro_a")` -> "muro_a".
func _segundo_de(codigo: String, prefijo: String) -> Array[String]:
	var a: Array[String] = []
	var i: int = 0
	while true:
		var p: int = codigo.find(prefijo, i)
		if p < 0:
			break
		# Solo llamadas de verdad: `_mx(` seguido de comilla. Sin este filtro
		# se cuela el `_mx()` de un comentario y el `_mx(rol: String,` de la
		# firma, y el chequeo de datos primero empieza a dar basura.
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


## El relieve del normal map: cuánto se aparta el canal verde de "plano"
## (0.5). Un normal map que no hace nada da 0.
func _relieve(t: Texture2D) -> float:
	var img: Image = t.get_image()
	var suma: float = 0.0
	var n: int = 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			suma += absf(img.get_pixel(x, y).g - 0.5)
			n += 1
	return suma / maxf(1.0, float(n))


func _canal(t: Texture2D, c: int) -> float:
	var img: Image = t.get_image()
	var total: float = 0.0
	var n: int = 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var col: Color = img.get_pixel(x, y)
			total += col.r if c == 0 else (col.g if c == 1 else col.b)
			n += 1
	return total / maxf(1.0, float(n))


func _desviacion(t: Texture2D) -> float:
	var img: Image = t.get_image()
	var suma: float = 0.0
	var suma2: float = 0.0
	var n: int = 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var v: float = img.get_pixel(x, y).v
			suma += v
			suma2 += v * v
			n += 1
	var m: float = suma / maxf(1.0, float(n))
	return sqrt(maxf(0.0, suma2 / maxf(1.0, float(n)) - m * m))
