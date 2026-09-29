extends SceneTree
## Tests headless de la Fase 14 (REWORK 2026 del terreno).
##
## (a) Bin nuevo: cabecera 289x289, tamano exacto
##     8+12+289^2*4+289^2*3 bytes; alturas coherentes (min >= 2.0: sin agua
##     profunda incaminable; max < 800).
## (b) Disco de Moon Town: el disco centrado en (0,0) de radio 800 u esta
##     perfectamente plano a H = 40.0 (altura_en == 40.0 en puntos con
##     r <= 750, incluido el centro).
## (c) Regiones (data/regiones.json): 10 rectangulos con los ids Liberty del
##     rework; moon_town [-1500,1500]^2 niveles 1-5; cobertura total del mapa
##     por muestreo (cada punto en exactamente 1 region, sin huecos ni
##     solapes); las 4 esquinas del mundo cubiertas.
## (d) Spawns (data/spawns.json): 1133 entradas {arquetipo, x, z, nivel};
##     todos dentro del terreno; ninguno en la zona segura de 40 m de (0,0);
##     fase 43: el arquetipo pertenece a la fauna de su region (mobs de
##     data/regiones.json), exentos los packs de prueba y los jefes;
##     cumple en cada entrada; cada spawn cae en una region y su nivel esta
##     dentro de la banda de esa region; los spawns de moon_town estan fuera
##     del disco de la ciudad (r >= 800).
## (e) API Terreno intacta: altura_en y color_en redondos contra el bin
##     (verificacion cruzada independiente).
##
## Los datos los generan (deterministas, semilla fija):
##   tools/generar_terreno_rework.py -> data/terreno.bin
##   tools/generar_spawns_rework.py   -> data/spawns.json
##
## Cómo correrlo (un solo comando):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase14_terreno.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.

const TG: GDScript = preload("res://scripts/mundo/terreno.gd")

const RUTA_BIN: String = "res://data/terreno.bin"
const RUTA_SPAWNS: String = "res://data/spawns.json"
## Altura aplanada del disco de Moon Town (ver tools/generar_terreno_rework.py).
const H_CIUDAD: float = 40.0
const R_DISCO: float = 800.0
const RADIO_SEGURO: float = 40.0
const LIMITE: float = 18432.0
const IDS_ESPERADOS: Array[String] = [
	"moon_town", "tierras_francas", "ceniza_forja", "tierras_trueno",
	"bosque_hondo", "umbral_ladon", "abismo_lloroso", "costa_lamento",
	"corona_quebrada", "velo",
]

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []
var _alturas: PackedFloat32Array = PackedFloat32Array()
var _colores: PackedColorArray = PackedColorArray()


func _init() -> void:
	print("[TEST] Fase 14 - rework del terreno: bin, disco de ciudad, regiones, spawns")


var _empezo: bool = false


## El arbol existe recien en el primer _process (leccion 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_leer_bin()
	_t_bin()
	var t: Terreno = TG.new()
	_basura.append(t)
	root.add_child(t)
	_t_disco(t)
	_t_alturas_coherentes(t)
	_t_colores(t)
	_t_regiones()
	_t_spawns()
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


## Lee el bin de forma independiente (verificacion cruzada).
func _leer_bin() -> void:
	var datos: PackedByteArray = FileAccess.get_file_as_bytes(RUTA_BIN)
	_check(datos.size() > 0, "bin: existe y no esta vacio")
	if datos.size() == 0:
		return
	var vw: int = int(datos.decode_u32(0))
	var vh: int = int(datos.decode_u32(4))
	_check(vw == 289 and vh == 289, "bin: cabecera 289x289",
		"vw=%d vh=%d" % [vw, vh])
	var n: int = 289 * 289
	_check(datos.size() == 8 + 12 + n * 4 + n * 3,
		"bin: tamano exacto del formato",
		"size=%d esperado=%d" % [datos.size(), 8 + 12 + n * 4 + n * 3])
	_alturas = PackedFloat32Array()
	_alturas.resize(n)
	var off: int = 8 + 12
	for i in range(n):
		_alturas[i] = datos.decode_float(off + i * 4)
	var coff: int = off + n * 4
	_colores = PackedColorArray()
	_colores.resize(n)
	for i in range(n):
		var b: int = coff + i * 3
		_colores[i] = Color(
			float(datos[b]) / 255.0,
			float(datos[b + 1]) / 255.0,
			float(datos[b + 2]) / 255.0)


func _t_bin() -> void:
	if _alturas.is_empty():
		_check(false, "bin: alturas leidas", "el bin no se pudo leer")
		return
	var hmin: float = 1e30
	var hmax: float = -1e30
	for h in _alturas:
		hmin = minf(hmin, h)
		hmax = maxf(hmax, h)
	_check(hmin >= 2.0, "bin: sin agua profunda (min >= 2.0)",
		"min=%f" % hmin)
	_check(hmax < 800.0, "bin: max razonable (< 800)",
		"max=%f" % hmax)
	_check(hmax > 400.0, "bin: hay relieve alto (picos con nieve)",
		"max=%f" % hmax)


func _t_disco(t: Terreno) -> void:
	# 25 puntos con r <= 750 (dentro del disco): altura_en == H exacta.
	var mal: int = 0
	var peor: float = 0.0
	var radios: Array = [0.0, 128.0, 256.0, 384.0, 512.0, 640.0, 750.0]
	for r in radios:
		var rf: float = r
		var pasos: int = 1 if rf == 0.0 else 6
		for k in range(pasos):
			var ang: float = TAU * float(k) / float(pasos)
			var x: float = rf * cos(ang)
			var z: float = rf * sin(ang)
			var h: float = t.altura_en(x, z)
			peor = maxf(peor, absf(h - H_CIUDAD))
			if absf(h - H_CIUDAD) > 0.001:
				mal += 1
	_check(mal == 0, "disco: plano a H=40 en r<=750 (25 puntos)",
		"mal=%d peor_desvio=%f" % [mal, peor])
	# Los vertices del bin dentro del disco tambien valen H exacto.
	var malv: int = 0
	for iz in range(289):
		for ix in range(289):
			var x: float = Terreno.X0 + float(ix) * Terreno.PASO
			var z: float = Terreno.Z0 + float(iz) * Terreno.PASO
			if x * x + z * z < R_DISCO * R_DISCO:
				if absf(_alturas[iz * 289 + ix] - H_CIUDAD) > 0.0001:
					malv += 1
	_check(malv == 0, "disco: vertices del bin a H exacto",
		"mal=%d" % malv)
	# Fuera del disco el terreno sigue vivo (no todo aplanado).
	var h_fuera: float = t.altura_en(1500.0, 0.0)
	_check(absf(h_fuera - H_CIUDAD) > 0.5, "disco: fuera de r=800 hay relieve",
		"h(1500,0)=%f" % h_fuera)


func _t_alturas_coherentes(t: Terreno) -> void:
	# Puntos exactos de la grilla: altura_en == bin (tolerancia 0.01).
	var casos: Array = [[0, 0], [288, 0], [0, 288], [288, 288], [144, 144]]
	var mal: int = 0
	for c in casos:
		var ix: int = c[0]
		var iz: int = c[1]
		var x: float = Terreno.X0 + float(ix) * Terreno.PASO
		var z: float = Terreno.Z0 + float(iz) * Terreno.PASO
		if absf(t.altura_en(x, z) - _alturas[iz * 289 + ix]) > 0.01:
			mal += 1
	_check(mal == 0, "altura_en: grilla == bin", "mal=%d" % mal)
	# Punto medio entre 4 vertices: promedio bilineal.
	var ix: int = 100
	var iz: int = 100
	var x: float = Terreno.X0 + (float(ix) + 0.5) * Terreno.PASO
	var z: float = Terreno.Z0 + (float(iz) + 0.5) * Terreno.PASO
	var prom: float = (_alturas[iz * 289 + ix] + _alturas[iz * 289 + ix + 1]
		+ _alturas[(iz + 1) * 289 + ix]
		+ _alturas[(iz + 1) * 289 + ix + 1]) / 4.0
	_check(absf(t.altura_en(x, z) - prom) <= 0.01,
		"altura_en: punto medio == promedio bilineal",
		"got=%f prom=%f" % [t.altura_en(x, z), prom])


func _t_colores(t: Terreno) -> void:
	# color_en devuelve el vertice mas cercano del bin.
	var mal: int = 0
	var casos: Array = [[0, 0], [288, 288], [144, 100], [37, 200], [200, 37]]
	for c in casos:
		var ix: int = c[0]
		var iz: int = c[1]
		var x: float = Terreno.X0 + float(ix) * Terreno.PASO
		var z: float = Terreno.Z0 + float(iz) * Terreno.PASO
		var got: Color = t.color_en(x, z)
		var esp: Color = _colores[iz * 289 + ix]
		if absf(got.r - esp.r) > 0.01 or absf(got.g - esp.g) > 0.01 \
				or absf(got.b - esp.b) > 0.01:
			mal += 1
	_check(mal == 0, "color_en: vertice mas cercano == bin", "mal=%d" % mal)


func _region_id(db: RegionDB, x: float, z: float) -> String:
	return str((db.region_en(x, z) as Dictionary).get("id", ""))


func _t_regiones() -> void:
	var db := RegionDB.new()
	_check(db.cargar(), "regiones: RegionDB.cargar()")
	var todas: Array = db.todas()
	_check(todas.size() == 10, "regiones: 10 rectangulos",
		"hay %d" % todas.size())
	var ids: Array = []
	for r in todas:
		ids.append(str((r as Dictionary).get("id", "")))
	var ids_t: Array[String] = []
	ids_t.assign(ids)
	_check(ids_t == IDS_ESPERADOS, "regiones: ids Liberty del rework en orden",
		str(ids_t))
	var moon: Dictionary = db.por_id("moon_town")
	_check(not moon.is_empty(), "regiones: existe moon_town")
	_check(str(moon.get("nombre", "")) == "Moon Town",
		"regiones: moon_town se llama 'Moon Town'")
	_check(float(moon.get("x0", 0.0)) == -1500.0
		and float(moon.get("x1", 0.0)) == 1500.0
		and float(moon.get("z0", 0.0)) == -1500.0
		and float(moon.get("z1", 0.0)) == 1500.0,
		"regiones: moon_town [-1500,1500]^2")
	_check(int(moon.get("nivel_min", 0)) == 1 and int(moon.get("nivel_max", 0)) == 5,
		"regiones: moon_town banda 1-5")
	# Cobertura total por muestreo: cada punto en exactamente 1 region.
	var sin_cobertura: int = 0
	var doble: int = 0
	var n: int = 31
	for i in range(n):
		for j in range(n):
			var x: float = -LIMITE + 2.0 * LIMITE * float(i) / float(n - 1)
			var z: float = -LIMITE + 2.0 * LIMITE * float(j) / float(n - 1)
			var cuenta: int = 0
			for r in todas:
				var rd: Dictionary = r
				var x0: float = float(rd.get("x0", 0.0))
				var x1: float = float(rd.get("x1", 0.0))
				var z0: float = float(rd.get("z0", 0.0))
				var z1: float = float(rd.get("z1", 0.0))
				var dx: bool = x >= x0 and (x < x1 or x1 >= LIMITE and x <= LIMITE)
				var dz: bool = z >= z0 and (z < z1 or z1 >= LIMITE and z <= LIMITE)
				if dx and dz:
					cuenta += 1
			if cuenta == 0:
				sin_cobertura += 1
			elif cuenta > 1:
				doble += 1
	_check(sin_cobertura == 0, "regiones: sin huecos (961 puntos)",
		"huecos=%d" % sin_cobertura)
	_check(doble == 0, "regiones: sin solapes (961 puntos)",
		"solapes=%d" % doble)
	# Las 4 esquinas del mundo estan cubiertas.
	var esquinas: Array = [
		[-LIMITE, -LIMITE], [LIMITE, -LIMITE],
		[-LIMITE, LIMITE], [LIMITE, LIMITE],
	]
	var mal: int = 0
	for e in esquinas:
		if _region_id(db, e[0], e[1]) == "":
			mal += 1
	_check(mal == 0, "regiones: 4 esquinas cubiertas", "mal=%d" % mal)
	_check(_region_id(db, 0.0, 0.0) == "moon_town",
		"regiones: (0,0) en Moon Town")
	# Bandas crecen hacia afuera: el max de la region mas lejana > 40.
	var velo: Dictionary = db.por_id("velo")
	_check(int(velo.get("nivel_max", 0)) >= 60,
		"regiones: el Velo (norte profundo) llega a 60+",
		"max=%s" % str(velo.get("nivel_max", "?")))


func _arquetipo_esperado(nivel: int) -> String:
	if nivel <= 30:
		return "goblin"
	if nivel <= 200:
		return "lobo"
	return "ogro"


func _t_spawns() -> void:
	var texto: String = FileAccess.get_file_as_string(RUTA_SPAWNS)
	_check(not texto.is_empty(), "spawns: JSON legible")
	# parse_string retorna Variant: NUNCA `:=` aqui.
	var crudo = JSON.parse_string(texto)
	_check(crudo is Array, "spawns: es un array")
	if not (crudo is Array):
		return
	var lista: Array = crudo
	_check(lista.size() == 1133, "spawns: 1133 entradas (1121 + 6 pack + 6 jefes fase 22)",
		"hay %d" % lista.size())
	var db := RegionDB.new()
	_check(db.cargar(), "spawns: regiones cargadas")
	var fuera: int = 0
	var en_segura: int = 0
	var mal_arq: int = 0
	var sin_region: int = 0
	var fuera_banda: int = 0
	var moon_en_disco: int = 0
	for s in lista:
		var sd: Dictionary = s
		var x: float = float(sd.get("x", 0.0))
		var z: float = float(sd.get("z", 0.0))
		var nivel: int = int(sd.get("nivel", 0))
		var arq: String = str(sd.get("arquetipo", ""))
		# Fase 18.2+: el pack de prueba de combate ("grupo": "prueba_combate")
		# es colocacion a mano pedida por Juan Diego: se exime de las reglas
		# de DISTRIBUCION (disco de la ciudad y banda de nivel de region),
		# pero sigue cumpliendo arquetipo valido y regla nivel->arquetipo.
		# Fase 22: los jefes ("grupo": "jefe_fragmento") tambien son
		# colocacion a mano y se eximen de distribucion Y de la regla
		# nivel->arquetipo (arquetipos unicos; su "nivel" es dificultad).
		var es_prueba: bool = str(sd.get("grupo", "")) == "prueba_combate"
		var es_jefe: bool = str(sd.get("grupo", "")) == "jefe_fragmento"
		# Fase 62: el Titán Acecho es igual: arquetipo único a mano, y su
		# "nivel" es dificultad, no banda de región.
		var es_titan: bool = str(sd.get("grupo", "")) == "titan"
		if x < -LIMITE or x > LIMITE or z < -LIMITE or z > LIMITE:
			fuera += 1
		if Vector2(x, z).length() < RADIO_SEGURO:
			en_segura += 1
		# Fase 43: el arquetipo viene de la fauna de la REGIÓN (no del nivel).
		var r: Dictionary = db.region_en(x, z)
		var fauna: Array = r.get("mobs", [])
		if not es_jefe and not es_prueba and not es_titan \
				and (fauna.is_empty() or arq not in fauna):
			mal_arq += 1
		if r.is_empty():
			sin_region += 1
		else:
			var nmin: int = int(r.get("nivel_min", 0))
			var nmax: int = int(r.get("nivel_max", 0))
			if not es_prueba and not es_jefe and not es_titan \
					and (nivel < nmin or nivel > nmax):
				fuera_banda += 1
			if not es_prueba and str(r.get("id", "")) == "moon_town" \
					and Vector2(x, z).length() < R_DISCO:
				moon_en_disco += 1
	_check(fuera == 0, "spawns: todos dentro del terreno",
		"fuera=%d" % fuera)
	_check(en_segura == 0, "spawns: ninguno en la zona segura de 40 m",
		"en_segura=%d" % en_segura)
	_check(mal_arq == 0, "spawns: arquetipo de la fauna de su region en todas",
		"mal=%d" % mal_arq)
	_check(sin_region == 0, "spawns: todos caen en una region",
		"sin_region=%d" % sin_region)
	_check(fuera_banda == 0, "spawns: nivel dentro de la banda de su region",
		"fuera_banda=%d" % fuera_banda)
	_check(moon_en_disco == 0,
		"spawns: ninguno de Moon Town dentro del disco de la ciudad",
		"en_disco=%d" % moon_en_disco)
