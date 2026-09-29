class_name BibliotecaMateriales
extends RefCounted
## Fase 69: la biblioteca de materiales del mundo. Un `StandardMaterial3D`
## por (superficie, tinte, variante), compartido por TODAS las mallas.
##
## POR QUÉ NO UN MATERIAL POR MALLA: 146 edificios × 20 cajas son ~3.000
## `MeshInstance3D`. Si cada uno crease su `StandardMaterial3D` habría 3.000
## materiales y el pico de VRAM de la carga se va. Acá hay del orden de 150, y
## las texturas se comparten de a docenas de mallas: la regla de §9.5
## (materiales compartidos), que es la que hace que pasar de 1 a 4 texturas no
## cueste nada.
##
## POR QUÉ EL TRIPLANAR LO PONE EL MOTOR Y NO UN SHADER: `StandardMaterial3D`
## trae `uv1_triplanar` + `uv1_world_triplanar`, y el shader que Godot genera
## sale literalmente
## `uv1_triplanar_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz * uv1_scale + uv1_offset`.
## O sea: proyección en espacio de MUNDO con escala y offset aplicados. Eso es
## justo lo que necesitan las primitivas: un `BoxMesh` de 24 m con UV 0..1
## estiraría una textura de madera a lo largo de la pared; proyectada en mundo
## cada metro lleva su trozo de grano y no hay costura visible en las aristas.
##
## EL TRIPLANAR EN MUNDO TRAE UN REGALO: la fase del grano queda anclada a la
## posición del edificio, no a la malla. Por eso dos casas del mismo tipo
## nunca se ven idénticas aunque compartan variante.

static var _materiales: Dictionary = {}
## Cuántos materiales se crearon de verdad (lo vigila el test).
static var _creados: int = 0


## El material de una superficie pintada de un tinte, en una variante.
## Devuelve SIEMPRE la misma instancia para la misma clave.
##
## - `variar` = false ignora la semilla y devuelve siempre la variante 0: un
##   remache o una antorcha no cambian de tono por estar en otra calle.
## - `variar` = true saca la variante de la semilla, y la semilla la pone la
##   POSICIÓN del edificio. Mismo edificio, mismo material, siempre: un save
##   que reconstruya el mundo tiene que salir idéntico, así que la semilla no
##   puede ser un contador ni un `rand`.
static func material(id_superficie: String, tinte: String, semilla: int,
		variar: bool, rel_rugosidad: float = 1.0,
		rel_metalicidad: float = 1.0) -> StandardMaterial3D:
	MaterialesDB.cargar()
	var v: int = 0
	var n_var: int = MaterialesDB.variantes()
	if variar and n_var > 1:
		v = posmod(semilla, n_var)
	var clave: String = "%s|%s|%d" % [id_superficie, tinte, v]
	if _materiales.has(clave):
		return _materiales[clave] as StandardMaterial3D
	var s: Dictionary = MaterialesDB.superficie(id_superficie)
	if s.is_empty():
		push_warning("[BibliotecaMateriales] superficie desconocida: " + id_superficie)
		s = MaterialesDB.superficie("piedra")
	var mat := StandardMaterial3D.new()
	_vestir(mat, id_superficie, s, tinte, v, rel_rugosidad, rel_metalicidad)
	_materiales[clave] = mat
	_creados += 1
	return mat


## Un material SIN texturas, para lo que emite (ventanas, lava, agua, cristal).
## También compartido, también todo desde el dato.
static func plano(tinte: String, rugosidad: float, metallicidad: float,
		emision: String, energia: float) -> StandardMaterial3D:
	var clave: String = "plano|%s|%.3f|%.3f|%s|%.3f" % [tinte, rugosidad,
		metallicidad, emision, energia]
	if _materiales.has(clave):
		return _materiales[clave] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.html(tinte)
	mat.roughness = clampf(rugosidad, 0.0, 1.0)
	mat.metallic = clampf(metallicidad, 0.0, 1.0)
	if not emision.is_empty():
		mat.emission_enabled = true
		mat.emission = Color.html(emision)
		mat.emission_energy_multiplier = energia
	_materiales[clave] = mat
	_creados += 1
	return mat


## Atajo para una entrada del catálogo (un `roles` de `materiales.json`, o un
## `piezas`). El `Dictionary` trae `superficie`, `tinte` y los
## multiplicadores `rugosidad_rel` / `metalicidad_rel`.
static func de_rol(rol: Dictionary, semilla: int) -> StandardMaterial3D:
	MaterialesDB.cargar()
	if rol.is_empty():
		push_warning("[BibliotecaMateriales] rol vacío")
		return null
	var sup: String = str(rol.get("superficie", "piedra"))
	var rel_r: float = float(rol.get("rugosidad_rel", 1.0))
	var rel_m: float = float(rol.get("metalicidad_rel", 1.0))
	if bool(rol.get("plano", false)):
		var rs: Dictionary = MaterialesDB.superficie(sup)
		return plano(str(rol.get("tinte", "#808080")),
			float(rs.get("rugosidad", 0.5)) * rel_r, rel_m,
			str(rol.get("emision", "")), float(rol.get("emision_energia", 1.0)))
	return material(sup, str(rol.get("tinte", "#808080")), semilla,
		bool(rol.get("variar", false)), rel_r, rel_m)


## La semilla de variación de un edificio, derivada de su POSICIÓN.
##
## POR QUÉ NO UN CONTADOR NI UN `rand`: si la semilla no es función de la
## posición, un save que reconstruya el mundo desde cero reparte los granos
## de otra manera y las casas cambian de color entre una sesión y la
## siguiente. FNV-1a sobre la celda entera: entero, estable entre versiones de
## Godot y sin signo, así que `posmod` da siempre la misma variante.
static func semilla_de(x: float, z: float) -> int:
	var h: int = 2166136261
	var ejes: PackedInt64Array = PackedInt64Array([int(floorf(x)), int(floorf(z))])
	for v in ejes:
		var u: int = v & 0xFFFFFFFF
		for _b in 4:
			h = ((h ^ (u & 0xFF)) * 16777619) & 0x3FFFFFFF
			u >>= 8
	return h


## Hornea por adelantado TODO lo que el mundo va a pedir, para que el primer
## edificio no se coma el coste en medio de la construcción progresiva (§9.5:
## la carga se paga al arrancar, no en el primer frame que lo pide).
##
## No hornea las 4 variantes de las 8 superficies: las superficies que ningún
## rol declara con `"variar": true` solo necesitan la variante 0. El recorte
## sale del dato, no de una lista en código.
static func precalentar() -> int:
	MaterialesDB.cargar()
	var n: int = 0
	var con_var: Dictionary = {}
	for r in MaterialesDB.roles():
		var rol: Dictionary = MaterialesDB.rol(r)
		if bool(rol.get("variar", false)):
			con_var[str(rol.get("superficie", ""))] = true
	for c in MaterialesDB.paleta_claves():
		var pr: Dictionary = MaterialesDB.paleta_rol(c)
		if bool(pr.get("variar", false)):
			con_var[str(pr.get("superficie", ""))] = true
	for sup in MaterialesDB.superficies():
		var n_var: int = MaterialesDB.variantes() if con_var.has(sup) else 1
		for v in n_var:
			if not GeneradorTexturas.conjunto(sup, v).is_empty():
				n += 1
	return n


static func limpiar() -> void:
	_materiales.clear()
	_creados = 0


static func creados() -> int:
	return _creados


static func claves() -> Array[String]:
	var a: Array[String] = []
	for k in _materiales.keys():
		a.append(str(k))
	a.sort()
	return a


# ---------------------------------------------------------------------------
# Vestido del material
# ---------------------------------------------------------------------------

## Texturas PBR + triplanar en mundo + variación por variante.
static func _vestir(mat: StandardMaterial3D, id_sup: String, s: Dictionary,
		tinte: String, v: int, rel_rugosidad: float, rel_metalicidad: float) -> void:
	var conjunto: Dictionary = GeneradorTexturas.conjunto(id_sup, v)
	if conjunto.is_empty():
		return
	var alb: Texture2D = conjunto[GeneradorTexturas.CLAVE_ALBEDO] as Texture2D
	var nrm: Texture2D = conjunto[GeneradorTexturas.CLAVE_NORMAL] as Texture2D
	var orm: Texture2D = conjunto[GeneradorTexturas.CLAVE_ORM] as Texture2D

	mat.albedo_texture = alb
	mat.albedo_color = _tinte(tinte, v)

	mat.normal_enabled = true
	mat.normal_texture = nrm
	mat.normal_scale = 1.0

	# Un solo archivo ORM para rugosidad, metallicidad y oclusión. Los canales
	# se eligen con `TEXTURE_CHANNEL_*` y NO con `RMATC_CHANNEL_*`: en 4.7 el
	# enum se renombró y el viejo no existe (parse error, verificado con un
	# script chico antes de escribir esto).
	mat.roughness_texture = orm
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.metallic_texture = orm
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	mat.roughness = clampf(float(s.get("rugosidad", 0.9)) * rel_rugosidad, 0.0, 1.0)
	mat.metallic = clampf(rel_metalicidad, 0.0, 1.0)

	# Oclusión horneada del mapa (el detalle fino que la SSAO del bloque 67 no
	# alcanza). En `gl_compatibility` (build web) no hay AO: se apaga en vez
	# de escribir campos que el backend va a ignorar.
	if _hay_ssr():
		mat.ao_enabled = true
		mat.ao_texture = orm
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.ao_light_affect = 0.0  # solo ambiente, como el resto del proyecto

	# --- TRIPLANAR: el mecanismo nativo, no un shader propio ---
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_triplanar_sharpness = 1.0
	var variacion: Dictionary = MaterialesDB.variacion()
	# `uv1_scale` multiplica la posición de mundo: 1/escala_uv es "un tile
	# cada N metros".
	var esc: float = maxf(0.05, float(s.get("escala_uv", 3.0)))
	var esc_var: float = 1.0 + (frac(0.7548776662 * (float(v) + 1.0)) * 2.0 - 1.0) \
		* float(variacion.get("uv_escala", 0.0))
	mat.uv1_scale = Vector3.ONE * (1.0 / esc) * esc_var
	# El offset va en UV, no en metros: es la FASE del grano. Con el triplanar
	# en mundo es lo que evita que dos edificios pegados repitan el mismo
	# trozo de pared.
	var alcance: float = float(variacion.get("uv_offset", 0.0))
	mat.uv1_offset = Vector3(
		frac(0.6180339887 * (float(v) + 1.0)),
		frac(0.4142135624 * (float(v) + 1.0)),
		frac(0.8660254038 * (float(v) + 1.0))) * alcance


## El motor multiplica: `ALBEDO = albedo_color * albedo_tex`. El mapa trae el
## grano y el color plano pone el tono, que es lo que permite que un solo set
## de texturas sirva para los 9 tintes de pared del mundo. La ganancia
## compensa que el mapa promedia ~0.94 y oscurecería el mundo entero un 6%.
static func _tinte(tinte: String, v: int) -> Color:
	var c: Color = Color.html(tinte)
	var variacion: Dictionary = MaterialesDB.variacion()
	var g: float = MaterialesDB.albedo_ganancia()
	var tono: float = 1.0 + (frac(0.5698402910 * (float(v) + 1.0)) * 2.0 - 1.0) \
		* float(variacion.get("tono", 0.0))
	var sat: float = 1.0 + (frac(0.8019377358 * (float(v) + 1.0)) * 2.0 - 1.0) \
		* float(variacion.get("saturacion", 0.0))
	var lum: float = c.get_luminance()
	return Color(
		clampf((lum + (c.r - lum) * sat) * tono * g, 0.0, 1.0),
		clampf((lum + (c.g - lum) * sat) * tono * g, 0.0, 1.0),
		clampf((lum + (c.b - lum) * sat) * tono * g, 0.0, 1.0),
		1.0)


static func _hay_ssr() -> bool:
	var m: String = str(ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "forward_plus"))
	return m != "gl_compatibility"


## Fracción áurea: secuencia de baja discrepancia. La variante v saca su tono
## de acá y no de un `rand`, para que el horneado sea reproducible.
static func frac(x: float) -> float:
	return x - floorf(x)
