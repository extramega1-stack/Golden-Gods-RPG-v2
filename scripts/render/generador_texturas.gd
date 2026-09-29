class_name GeneradorTexturas
extends RefCounted
## Fase 69: horneado de las texturas PBR del mundo. Una vez al arrancar.
##
## POR QUÉ HORNEAR Y NO TENER ARCHIVOS: el proyecto no trae un solo `.png` de
## superficie (18 albedos sueltos, cero normal maps, cero ORM) y la regla dura
## §7.5 no deja meter arte de Blizzard. Lo que SÍ se puede hacer es escribir el
## pixel: albedo con grano, normal map derivado del campo de altura, y un ORM
## (R = oclusión horneada, G = rugosidad, B = metallicidad) que es el formato
## que Godot ya sabe leer de un `StandardMaterial3D`.
##
## POR QUÉ `get_seamless_image` Y NO UN BUCLE CON RUIDO: el tile se repite
## sobre una fachada de 24 m. Un ruido no tileable muestra la costura en cada
## repetición, que es justo el defecto que se vino a arreglar.
## `FastNoiseLite.get_seamless_image(ancho, alto, invert, 3d, skirt)` devuelve
## un L8 que ya envuelve por los cuatro bordes. OJO: en 4.7 pide DOS
## argumentos de tamaño; en 3.x era uno, y es un parse error, no un warning.
##
## EL CACHE ES LA REGLA DURA: `Image.new()` y `ImageTexture` por fotograma es
## exactamente lo que §9.5 prohíbe. Acá se hornea una vez por (superficie,
## variante) y se devuelve SIEMPRE la misma instancia. 8 superficies × 4
## variantes × 3 mapas = 96 texturas de 128 px ≈ 6 MB con mipmaps.

const CLAVE_ALBEDO: String = "albedo"
const CLAVE_NORMAL: String = "normal"
const CLAVE_ORM: String = "orm"

static var _cache: Dictionary = {}
## Cuántas texturas se hornearon de verdad. Si sube en el bucle caliente,
## alguien está llamando por fotograma (test `test_render_materiales`).
static var _horneadas: int = 0


## El set PBR de una superficie en una variante. Devuelve SIEMPRE la misma
## `ImageTexture` para la misma clave: la segunda llamada NO hornea nada.
## El Dictionary trae `albedo`, `normal` y `orm`.
static func conjunto(id: String, variante: int) -> Dictionary:
	MaterialesDB.cargar()
	var clave: String = "%s#%d" % [id, variante]
	if _cache.has(clave):
		return _cache[clave]
	var s: Dictionary = MaterialesDB.superficie(id)
	if s.is_empty():
		push_warning("[GeneradorTexturas] superficie desconocida: " + id)
		return {}
	var res: Dictionary = _hornea(s, variante, hash_de(id))
	_cache[clave] = res
	_horneadas += 1
	return res


## Vacía el cache. Los tests lo llaman; el juego, nunca.
static func limpiar() -> void:
	_cache.clear()
	_horneadas = 0


static func claves() -> Array[String]:
	var a: Array[String] = []
	for k in _cache.keys():
		a.append(str(k))
	a.sort()
	return a


static func horneadas() -> int:
	return _horneadas


# ---------------------------------------------------------------------------
# Horneado
# ---------------------------------------------------------------------------

static func _hornea(s: Dictionary, variante: int, semilla_id: int) -> Dictionary:
	var px: int = MaterialesDB.textura_px()
	var total: int = px * px
	var base: int = MaterialesDB.semilla() + semilla_id + variante * 7919
	var frec: float = float(s.get("frecuencia", 0.05))

	# --- los tres campos de ruido, ya tileables ---
	var g: PackedFloat32Array = _campo(px, frec, int(s.get("octavas", 4)), base)
	var r: PackedFloat32Array = _campo(px, frec * 3.0, 3, base + 131)
	var moteados: Array = s.get("moteado", [])
	var m: Array[PackedFloat32Array] = []
	var colores_mote: Array[Color] = []
	for i in moteados.size():
		var md: Dictionary = moteados[i]
		m.append(_campo(px, frec * float(md.get("frecuencia", 0.5)), 3,
			base + 977 + i * 31))
		colores_mote.append(Color.html(str(md.get("color", "#808080"))))

	# --- patron caracteristico: sillares, teja, veta, urdimbre, guijarro ---
	var pat: Dictionary = s.get("patron", {})
	var p_tipo: String = str(pat.get("tipo", "ninguno"))
	var p_frec: float = float(pat.get("frecuencia", 0.0))
	var p_amp: float = float(pat.get("amplitud", 0.0))
	var p_junta: float = float(pat.get("junta", 0.0))
	var gran: float = float(s.get("granulometria", 0.5))
	var gan: float = float(s.get("ganancia", 0.4))
	var rug_var: float = float(s.get("rugosidad_var", 0.1))
	var n_fuerza: float = float(s.get("normal_fuerza", 1.0)) \
		* MaterialesDB.normal_fuerza_global()
	var alb_base: float = MaterialesDB.albedo_base()

	# --- un solo recorrido: campo de altura + albedo + las tres texturas ---
	var altura: PackedFloat32Array = PackedFloat32Array()
	altura.resize(total)
	var mote_f: PackedFloat32Array = PackedFloat32Array()
	mote_f.resize(total)
	var alb: PackedByteArray = PackedByteArray()
	alb.resize(total * 4)
	var nrm: PackedByteArray = PackedByteArray()
	nrm.resize(total * 4)
	var orm: PackedByteArray = PackedByteArray()
	orm.resize(total * 4)

	for y in px:
		var v: float = float(y) / float(px)
		var y0: int = y * px
		for x in px:
			var u: float = float(x) / float(px)
			var i: int = y0 + x
			var gv: float = g[i]
			var alt: float = _patron(p_tipo, u, v, p_frec, p_junta, gv) * p_amp \
				+ (gv - 0.5) * gran
			altura[i] = alt
			# Moteado: cuanto mancha hay y de qué color (multiplicador).
			var mf: float = 0.0
			var cr: float = 0.0
			var cg: float = 0.0
			var cb: float = 0.0
			for k in moteados.size():
				var md: Dictionary = moteados[k]
				var um: float = float(md.get("umbral", 0.7))
				var sm: float = maxf(0.001, float(md.get("suavizado", 0.15)))
				var w: float = clampf((m[k][i] - um) / sm, 0.0, 1.0)
				w *= w * (3.0 - 2.0 * w)  # smoothstep
				if w <= 0.0:
					continue
				mf = maxf(mf, w)
				var c: Color = colores_mote[k]
				cr = lerpf(cr, c.r, w)
				cg = lerpf(cg, c.g, w)
				cb = lerpf(cb, c.b, w)
			mote_f[i] = mf
			# El relieve alto raspa y aclara; la grieta se ensucia. El mapa de
			# albedo va casi neutro: el COLOR lo pone `albedo_color` del
			# material (ALBEDO = albedo_color * albedo_tex), y así un solo set
			# de texturas sirve para los 9 tintes de pared del mundo.
			var sh: float = clampf(0.86 + 0.30 * gan * alt + 0.10 * (gv - 0.5),
				0.0, 1.0) * alb_base
			var i4: int = i * 4
			alb[i4] = _b(sh * lerpf(1.0, cr, mf))
			alb[i4 + 1] = _b(sh * lerpf(1.0, cg, mf))
			alb[i4 + 2] = _b(sh * lerpf(1.0, cb, mf))
			alb[i4 + 3] = 255

	# --- normal map: gradiente con envoltura, para que la esquina no cante ---
	# `paso` va con el LADO del tile y no al revés: el gradiente por téxel es
	# (dh/duv)/px, así que para que el relieve se vea IGUAL a 64 px que a 512
	# el factor tiene que multiplicar por px. Con `n_fuerza * 0.09` una junta
	# de sillar queda a ~60° de inclinación y el grano fino a ~15°: se ve
	# relieve sin que la pared parezca de yeso rallado.
	var paso: float = n_fuerza * 0.09 * float(px)
	for y in px:
		var y0b: int = y * px
		var ym: int = ((y - 1 + px) % px) * px
		var yp: int = ((y + 1) % px) * px
		for x in px:
			var xm: int = (x - 1 + px) % px
			var xp: int = (x + 1) % px
			var i: int = y0b + x
			var dx: float = altura[y0b + xp] - altura[y0b + xm]
			var dy: float = altura[yp + x] - altura[ym + x]
			var nrm_v := Vector3(-dx * paso, -dy * paso, 1.0).normalized()
			var i4b: int = i * 4
			nrm[i4b] = _b(nrm_v.x * 0.5 + 0.5)
			nrm[i4b + 1] = _b(nrm_v.y * 0.5 + 0.5)
			nrm[i4b + 2] = _b(nrm_v.z * 0.5 + 0.5)
			nrm[i4b + 3] = 255

	# --- ORM: R = oclusión horneada, G = rugosidad, B = metallicidad ---
	# G va en [0.70, 1.0] a propósito: es un MODULADOR. El valor absoluto lo
	# lleva `mat.roughness` (el de la superficie por el `rugosidad_rel` del
	# rol), así un mismo set de texturas sirve para un yeso mate y un metal.
	var byte_metal: int = _b(float(s.get("metalicidad", 0.0)))
	for y in px:
		var y0c: int = y * px
		var ym2: int = ((y - 1 + px) % px) * px
		var yp2: int = ((y + 1) % px) * px
		for x in px:
			var i: int = y0c + x
			var xm2: int = (x - 1 + px) % px
			var xp2: int = (x + 1) % px
			# 5 tomas: la media local. Lo que queda POR DEBAJO de la media es
			# una grieta, y una grieta no recibe luz rebotada. El factor es
			# grande a proposito: con la oclusion "correcta" pero sutil (0.01 de
			# desviacion) el canal R no hace absolutamente nada.
			var blur: float = (altura[i] * 2.0 + altura[y0c + xm2]
				+ altura[y0c + xp2] + altura[ym2 + x] + altura[yp2 + x]) / 6.0
			var ao: float = clampf(0.72 + 4.0 * (altura[i] - blur), 0.0, 1.0)
			var rg: float = clampf(0.86 + rug_var * (r[i] - 0.5)
				- 0.12 * (1.0 - altura[i]) + 0.10 * mote_f[i], 0.70, 1.0)
			var i4c: int = i * 4
			orm[i4c] = _b(ao)
			orm[i4c + 1] = _b(rg)
			orm[i4c + 2] = byte_metal
			orm[i4c + 3] = 255

	return {
		CLAVE_ALBEDO: _textura(px, alb),
		CLAVE_NORMAL: _textura(px, nrm),
		CLAVE_ORM: _textura(px, orm),
	}


## Ruido FBM tileable de `px` lado, en 0..1.
static func _campo(px: int, frecuencia: float, octavas: int, semilla: int) -> PackedFloat32Array:
	var n := FastNoiseLite.new()
	n.seed = semilla
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = maxf(0.001, frecuencia)
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = clampi(octavas, 1, 8)
	n.fractal_gain = 0.5
	n.fractal_lacunarity = 2.0
	var img: Image = n.get_seamless_image(px, px, false, false, 0.0)
	var datos: PackedByteArray = img.get_data()
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(px * px)
	for i in px * px:
		out[i] = float(datos[i]) / 255.0
	return out


static func _textura(px: int, bytes: PackedByteArray) -> ImageTexture:
	var img: Image = Image.create_from_data(px, px, false, Image.FORMAT_RGBA8, bytes)
	# Mipmaps: sin ellos la textura hierve a lo lejos y al moverse. Cuesta un
	# 33% más de VRAM y es la diferencia entre "grano" y "ruido de TV".
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _b(v: float) -> int:
	return clampi(int(roundf(clampf(v, 0.0, 1.0) * 255.0)), 0, 255)


static func _frac(x: float) -> float:
	return x - floorf(x)


## Hash entero determinista de un string. Determinista de por vida: si el mundo
## se reconstruye desde un save tiene que salir el MISMO grano.
static func hash_de(nombre: String) -> int:
	var h: int = 2166136261
	for i in nombre.length():
		h = ((h ^ nombre.unicode_at(i)) * 16777619) & 0x3FFFFFFF
	return h


# ---------------------------------------------------------------------------
# Los patrones: por qué cada superficie tiene FORMA y no solo color
# ---------------------------------------------------------------------------

static func _patron(tipo: String, u: float, v: float, frec: float, junta: float,
		ruido: float) -> float:
	match tipo:
		"sillares":
			var filas: int = maxi(1, int(frec))
			var fila: int = int(floorf(v * float(filas)))
			# Hiladas alternadas a media pieza: el aparejo de un muro de verdad.
			var desf: float = 0.5 if (fila % 2 == 1) else 0.0
			var cols: int = filas * 2
			var fu: float = _frac(u * float(cols) + desf)
			var fv: float = _frac(v * float(filas))
			return (_ladrillo(fu, fv) * (1.0 - junta) - junta * 0.45) \
				+ (ruido - 0.5) * 0.10
		"filas":
			var nf: int = maxi(1, int(frec))
			var f: float = _frac(v * float(nf))
			# La teja es una cúpula por fila con el goterón entre medias.
			var d: float = 2.0 * f - 1.0
			return (sqrt(maxf(0.0, 1.0 - d * d)) * (1.0 - junta) - junta * 0.45) \
				+ (ruido - 0.5) * 0.10
		"vetas":
			var nv: int = maxi(1, int(frec))
			return 0.5 + 0.5 * sin(TAU * (u + ruido * 0.10) * float(nv))
		"tejido":
			var nt: int = maxi(1, int(frec))
			var cx: float = 0.5 + 0.5 * cos(TAU * u * float(nt))
			var cy: float = 0.5 + 0.5 * cos(TAU * v * float(nt))
			# Trama y urdimbre se cruzan: el toldo visto al trasluz.
			var par: bool = int(floorf(u * float(nt))) % 2 == 0
			return (cy if par else cx) * 0.6 + (cx if par else cy) * 0.4
		"canto":
			var nc: int = maxi(1, int(frec))
			var cx2: int = int(floorf(u * float(nc))) % nc
			var cy2: int = int(floorf(v * float(nc))) % nc
			var fu2: float = _frac(u * float(nc))
			var fv2: float = _frac(v * float(nc))
			var dx: float = (fu2 - 0.5) * 2.0
			var dy: float = (fv2 - 0.5) * 2.0
			var dd: float = sqrt(dx * dx + dy * dy)
			var domo: float = sqrt(maxf(0.0, 1.0 - dd * dd))
			return domo * (0.30 + 0.70 * hash2(cx2, cy2))
		"fibras":
			var nf2: int = maxi(1, int(frec))
			return 0.5 + 0.5 * sin(TAU * (u * float(nf2) + ruido * 0.45))
		_:
			return 0.5


## Un sillar: bloque con la junta recesa en el borde de la celda.
static func _ladrillo(fu: float, fv: float) -> float:
	var dx: float = absf(fu - 0.5) * 2.0
	var dy: float = absf(fv - 0.5) * 2.0
	var d: float = maxf(dx, dy)
	return 0.30 + 0.70 * (1.0 - smoothstep(0.58, 0.98, d))


static func hash2(ix: int, iy: int) -> float:
	var h: int = (ix * 374761393 + iy * 668265263) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return float(h % 65536) / 65536.0
