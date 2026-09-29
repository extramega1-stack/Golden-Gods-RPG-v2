class_name PostProceso
extends RefCounted
## Bloque 67: el post-proceso del mundo (tonemap, glow, SSAO, ajustes).
##
## POR QUÉ ES PRIORITARIO, Y POR QUÉ NO ES "ACTIVAR UN FLAG":
##
## El `Environment` de la fase 12 era el más pobre posible: fondo, cielo
## procedural y ambiente. NI UN campo de post-procesado. Y de esos, uno no es
## una ausencia de feature sino un BUG DE IMAGEN: Godot 4 usa tonemapping
## LINEAR por defecto, así que cualquier sol por encima de 1.0 CLIPEA A BLANCO
## PURO. Con `light_energy = 1.25` en el mediodía, las superficies iluminadas
## están quemadas. El tonemap filmic no es "más bonito": es corregir una
## imagen que se recorta.
##
## LO QUE SE ACTIVA Y POR QUÉ CADA COSA:
## - Tonemap FILMIC/ACES: recorta las altas luces sin quemarlas. Es lo que
##   hace que el sol se vea como sol y no como una mancha blanca.
## - Glow: solo en emisivos (antorchas, lava, cristales, la luna del
##   monumento). Da profundidad al cielo y hace que la luz "respire".
## - SSAO: ocluye las esquinas. Sin esto, las bases de los edificios flotan
##   sobre el suelo: es el detalle que más delata una escena con primitivas.
## - Ajustes (brillo/contraste/saturación): el toque final. Un poco de
##   saturación, porque los materiales planos de `albedo_color` son grises.
##
## EL LÍMITE DE LA WEB, QUE NO SE IGNORA: `renderer/rendering_method.web` es
## `gl_compatibility`, y ese renderer NO SOPORTA glow, SSAO ni volumétricos.
## No es que esté "desactivado": no existe. Por eso todo se decide por
## calidad y por si el renderer es `forward_plus`: en la build web el bloque
## degrada a tonemap + ajustes, que sí funcionan, en vez de intentar configurar
## campos que el backend va a ignorar (o, peor, a glitcheare).

## Enganchamos el post-proceso a un `WorldEnvironment` ya construido (el del
## ciclo día/noche). Devuelve si el renderer soporta lo que se pidió.
static func aplicar(env: Environment) -> bool:
	if env == null:
		push_warning("[PostProceso] Environment nulo")
		return false
	var calidad: int = Opciones.entero("calidad", 2)
	var hay_ssr: bool = _soportado()
	# El ambient del cielo es mejor que un color plano: el cielo procedural ya
	# se genera, y usarlo como ambiente hace que la luz "entonada" tinga las
	# superficies.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if hay_ssr \
		else Environment.AMBIENT_SOURCE_COLOR

	# --- tonemapping: el fix del clipping (bug de imagen, no feature) ---
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0

	# --- ajustes: el toque final ---
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.14  # los materiales planos son grises

	# --- glow: solo si el renderer lo soporta ---
	env.glow_enabled = hay_ssr and calidad >= 1
	if env.glow_enabled:
		env.glow_intensity = 0.55
		env.glow_strength = 1.0
		env.glow_bloom = 0.05
		# El umbral en 1.0 significa "solo lo que está emitting por encima de
		# blanco", que es exactamente lo que queremos (antorchas, lava) y no
		# "todo se ve borroso".
		env.glow_hdr_threshold = 1.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# --- SSAO: ocluir las esquinas ---
	env.ssao_enabled = hay_ssr and calidad >= 2
	if env.ssao_enabled:
		env.ssao_radius = 1.2
		env.ssao_intensity = 2.4
		env.ssao_power = 1.6
		env.ssao_detail = 0.6
		# El radio es lo que decide si la oclusión se ve como "contacto" o
		# como una mancha. 1,2 m es lo que se ve bien en un juego con edificios
		# de 5-8 m: más y la sombra "flota".

	# --- niebla: la de la fase 16 es 2D y se nota el corte ---
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.55, 0.58, 0.62)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0  # el cielo se ve, la niebla afecta al terreno

	return hay_ssr


## ¿El renderer actual soporta glow/SSAO? `gl_compatibility` (la build web) no
## los tiene: no es que estén a 0, es que el campo no existe en ese backend.
static func _soportado() -> bool:
	var m: String = str(ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "forward_plus"))
	return m != "gl_compatibility"


## Afina el sol: el default del motor (1.0) no está calculado para un mundo
## con albedo plano. Se sube el contraste del sol, se ablanda la sombra (las
## sombras duras de 4 muestras se ven escalonadas) y se pone un sesgo para
## que la penumbra no sea negra.
static func afinar_sol(sol: DirectionalLight3D) -> void:
	if sol == null or not is_instance_valid(sol):
		return
	sol.light_energy = 1.15
	sol.light_color = Color(1.0, 0.97, 0.90)  # sol cálido, no blanco puro
	sol.shadow_enabled = true
	# 4 muestras = sombras escalonadas y visibles; 2 con filtro PCF suave.
	sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sol.shadow_bias = 0.04
	sol.shadow_normal_bias = 1.4
	sol.shadow_blur = 1.2
	sol.light_angular_distance = 0.6  # sombras algo difusas, como el scattering
