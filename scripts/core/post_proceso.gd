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
	var hay_ssr: bool = _soportado()
	# El ambient del cielo es mejor que un color plano: el cielo procedural ya
	# se genera, y usarlo como ambiente hace que la luz "entonada" tinga las
	# superficies.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if hay_ssr \
		else Environment.AMBIENT_SOURCE_COLOR

	# --- tonemapping: el fix del clipping (bug de imagen, no feature) ---
	_tonemap_y_ajustes(env)

	# --- glow y SSAO: lo único que depende de la calidad ---
	efectos_de_calidad(env, hay_ssr, Opciones.entero("calidad", 2))

	# --- niebla: la de la fase 16 es 2D y se nota el corte ---
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.55, 0.58, 0.62)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0  # el cielo se ve, la niebla afecta al terreno

	return hay_ssr


## Tonemap y ajustes. NO dependen de la calidad: son el fix del clipping, y
## apagarlos por rendimiento devolvería el bug de imagen que arreglaron. Se
## separan del bloque de efectos para que la calidad pueda mover SOLO lo que
## es efecto.
static func _tonemap_y_ajustes(env: Environment) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.14  # los materiales planos son grises


## Glow y SSAO, que son los dos únicos bloques que la calidad enciende y apaga.
## Sale en una función propia para que la calidad se pueda cambiar EN VIVO sin
## volver a armar el `Environment` entero (y sin pisarle la niebla al `Clima`,
## que es de otro sistema y no se mezcla acá).
static func efectos_de_calidad(env: Environment, hay_ssr: bool, calidad: int) -> void:
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
		# El radio es lo que decide si la oclusión se ve como "contacto" o
		# como una mancha. 1,2 m es lo que se ve bien en un juego con edificios
		# de 5-8 m: más y la sombra "flota".
		env.ssao_radius = 1.2
		env.ssao_intensity = 2.4
		env.ssao_power = 1.6
		#
		# POR QUÉ ESTO NO PARPADEA Y EL GLOW TAMPOCO: los dos se calculan por
		# frame desde la profundidad, sin historial. `test_fase152_flicker` se lo
		# pregunta al motor y cuenta cero campos temporales en 4.7. El parpadeo de
		# un post-proceso con acumulación temporal (TAA, SSAO con jitter) no tiene
		# de dónde venir acá; el que se veía era la decoración.
		#
		# Y `ssao_detail` NO es un detalle: es el número de MUESTRAS por píxel.
		# 0 es una pasada barata y 1,0 es lo que se ve al final. En "Alta"
		# alcanza con 0,6 y solo "Ultra" se paga la calidad completa. Sin esto
		# los cuatro niveles rendían IGUAL, o sea que el ajuste no ajustaba.
		env.ssao_detail = 1.0 if calidad >= 3 else 0.6


## Reaplica SOLO la calidad, en un `Environment` ya montado. Es lo que llama
## `Opciones.aplicar_video()` cuando el jugador mueve el deslizador: el
## tonemap no se toca (no es efecto, es corrección) y la NIEBLA NO SE TOCA
## (es de `Clima`, y pisarla desde acá le devolvía al mundo una niebla de
## profundidad fija cada vez que se abría el panel).
static func reaplicar_calidad(env: Environment) -> bool:
	if env == null:
		return false
	var hay_ssr: bool = _soportado()
	efectos_de_calidad(env, hay_ssr, Opciones.entero("calidad", 2))
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
	sombras_de_calidad(sol, Opciones.entero("calidad", 2))


## LA PARTE DE LAS SOMBRAS QUE SÍ DEPENDE DE LA CALIDAD, y es la única que
## toca el movimiento de verdad. El parpadeo del acne no es temporal (el bias
## es el mismo frame tras frame): es RESOLUCIÓN. El mapa de sombra tiene un
## tamaño fijo en texels y lo reparte entre el alcance de la luz y la
## resolución de pantalla, así que a 36.864 u de lado cada texel cubre un
## montón de piso llano, y una ladera de tierra la resuelve distinta un frame
## que otro.
##
## `directional_shadow_max_distance` es el alcance: bajarlo a 90 m concentra el
## mapa donde está el jugador y multiplica la resolución efectiva por cuatro.
## El resto del mundo ya está bajo niebla a esa distancia, así que no se pierde
## nada de lo que se ve. Y el `shadow_bias` sube un poco con la calidad baja,
## que es el trueque de siempre: menos resolución se compensa con más
## separación, y el artefacto se vuelve una sombra separada en vez de una
## sombra que late.
static func sombras_de_calidad(sol: DirectionalLight3D, calidad: int) -> void:
	if sol == null or not is_instance_valid(sol):
		return
	var q: int = clampi(calidad, 0, 3)
	# LA SOMBRA NO SE APAGA NUNCA, ni en "Baja". No es un lujo ni un ahorro: sin
	# sombra el edificio flota contra el terreno y el mundo deja de tener suelo.
	# Lo que baja la calidad es la CALIDAD de la sombra (alcance, sesgo,
	# desenfoque, divisiones), no si hay sombra. Se afirma acá y no solo al
	# construir la escena, para que reaplicarla en vivo no la pueda dejar suelta.
	sol.shadow_enabled = true
	var alcances: Array[float] = [60.0, 80.0, 110.0, 0.0]
	sol.directional_shadow_max_distance = alcances[q]
	var biases: Array[float] = [0.09, 0.06, 0.04, 0.04]
	sol.shadow_bias = biases[q]
	# EL DESENFOQUE Y LAS DIVISIONES DEL ATLAS, que faltaban y son la parte
	# cara de verdad. `shadow_blur` es un paso separable MAS sobre el atlas, y
	# cada división del atlas es una pasada completa: son las dos palancas que
	# mueven el frame, y sin ellas el ajuste de calidad no ajustaba la sombra.
	#
	# OJO CON EL ENUM, y no es memoria: NO existe la división única. El mínimo
	# de `ShadowMode` es `SHADOW_PARALLEL_2_SPLITS` (consultado con `ClassDB`),
	# así que el escalón de Ultra a cuatro divisiones es de 2 a 2, no de 1 a 2.
	# Y medido: Ultra son +2,15 ms por frame, +66 %, +54 draw calls y +41 MB de
	# VRAM contra Baja (docs/bench_gtx1660.md). Los cuatro niveles entran en 60
	# fps a 720p; el ajuste existe para resoluciones más altas y equipos más
	# flojos, no porque en esta placa se note.
	sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if q >= 2 and _soportado():
		# Desde "Alta": sombra suave. Con menos muestras la sombra necesita más
		# separación para no quebrarse en las superficies inclinadas, así que el
		# sesio normal SUBE cuando el desenfoque baja.
		sol.shadow_blur = 1.2
		sol.shadow_normal_bias = 1.4
	else:
		sol.shadow_blur = 0.0
		sol.shadow_normal_bias = 1.4 + float(3 - q) * 0.35
	if q >= 3 and _soportado():
		# Solo "Ultra" paga la cuarta división del atlas.
		sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


## Reaplica la calidad a todas las luces direccionales de la escena. Va con
## `aplicar_video()` por la misma razón que `reaplicar_calidad`.
static func reaplicar_calidad_a_luces(raiz: Node) -> void:
	if raiz == null:
		return
	for n in raiz.find_children("*", "DirectionalLight3D", true, false):
		sombras_de_calidad(n as DirectionalLight3D, Opciones.entero("calidad", 2))
