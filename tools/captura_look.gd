extends SceneTree
## Captura la escena con un LOOK, para comparar esteticas sobre el MISMO
## encuadre. Ver `captura_luz.gd` para la version sin cambios.
##
## Uso:
##   godot --path . --script res://tools/captura_look.gd -- --look=oscuro --etiqueta=DESPUES
##
## LO QUE HACE Y POR QUE NO TOCA EL JUEGO: sobrescribe el `Environment` y el sol
## de la escenaYA INSTANCIADA, solo mientras corre este script. No modifica ni un
## archivo del juego. Es una prueba, no un cambio: si el look convence, recien ahi
## se decide si se vuelve el default.
##
## Y POR QUE "OSCURO" Y NO UNO CUALQUIERA: el look de Dark Souls no es detalle,
## es iluminacion. Personajes de 8.000 triangulos y texturas de 512, y aun asi
## se ve realista. Lo que hace el look es esto:
##   - casi nada de luz ambiente, para que la sombra sea NEGRA y no gris
##   - una sola fuente cálida y baja, que es la que dibuja la silueta
##   - niebla alta, que esconde la distancia y da profundidad
##   - contraste alto y saturacion BAJA: la sangre y el fuego se leen por
##     contraste, no por color saturado
##   - el cielo no compite: si el cielo es azul brillante, nada se ve oscuro

const DEMO := "res://scenes/demo/fase14_demo.tscn"
const ESPERAR := 900
const ANCHO := 1600
const ALTO := 900

var _n: int = 0
var _hecho: bool = false
var _salida: String = "build/capturas"
var _etiqueta: String = "look"
var _look: String = "oscuro"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--salida="):
			_salida = a.get_slice("=", 1)
		elif a.begins_with("--etiqueta="):
			_etiqueta = a.get_slice("=", 1)
		elif a.begins_with("--look="):
			_look = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_salida))
	root.content_scale_size = Vector2i(ANCHO, ALTO)
	var ps: PackedScene = load(DEMO)
	if ps == null:
		push_error("[LOOK] no se pudo cargar la escena")
		quit(1)
		return
	root.add_child(ps.instantiate())


func _process(_delta: float) -> bool:
	_n += 1
	# POR QUE HAY QUE APAGAR LOS SISTEMAS Y NO GANARLES LA CARRERA.
	#
	# Hay DOS que reescriben la luz en cada frame: `ciclo_dia`, que pone el
	# cielo y el sol segun la hora, y `clima`, que pone la niebla. Y el orden
	# importa: `_process` del SceneTree corre ANTES que el de los nodos, asi que
	# aunque los reescribiera cada frame, ellos van despues y ganan.
	#
	# Por eso la escena salia azul plana: el cielo y la niebla los ponia el
	# sistema, no yo. Y no por los numeros, que ya estaban bien.
	#
	# La solucion no es aplicarlo mas fuerte ni mas seguido: es apagar los dos
	# nodos, aplicar una vez, y que no vuelva a tocar nada. Es una PRUEBA, asi
	# que apagar el ciclo es lo correcto: en el juego searden de verdad.
	if _n == 60 and not _hecho:
		_apagar_sistemas()
		_aplicar()
		_diagnostico()
	if _n < ESPERAR or _hecho:
		return false
	_hecho = true
	var img: Image = root.get_texture().get_image()
	if img == null:
		quit(1)
		return true
	var ruta: String = "%s/%s.png" % [_salida, _etiqueta]
	img.save_png(ruta)
	print("[LOOK] %s  brillo medio=%.3f  min=%d  max=%d" % [
		ruta, _brillo(img), _min(img), _max(img)])
	quit(0)
	return true


var _ya_anunciado: bool = false


func _diagnostico() -> void:
	# MEDIR, NO SUPOner. Varios intentos de tuning no movieron la imagen, y eso
	# significa que el problema no son los numeros que estoy escribiendo: es que
	# la luz que ilumina la escena NO es la que yo toco. Esto imprime lo que hay
	# de verdad.
	print("DIAG --- luces en la escena ---")
	for n in root.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		var vis := "visible"
		if not l.visible: vis = "INVISIBLE"
		if l is DirectionalLight3D:
			print("DIAG  %-10s dir  energia=%.2f color=%s %s  rot=%s" % [
				l.name, l.light_energy, str(l.light_color), vis,
				str((l as DirectionalLight3D).rotation_degrees)])
		else:
			print("DIAG  %-10s energia=%.2f color=%s %s" % [
				l.name, l.light_energy, str(l.light_color), vis])
	print("DIAG --- materiales sin iluminar? ---")
	var sin_luz := 0
	var total := 0
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		total += 1
		if (n as GeometryInstance3D).material_override != null:
			sin_luz += 1
	print("DIAG  geometrias=%d  con material_override=%d" % [total, sin_luz])
	print("DIAG --- el environment que se esta usando ---")
	for n in root.find_children("*", "WorldEnvironment", true, false):
		var e: Environment = (n as WorldEnvironment).environment
		if e == null:
			print("DIAG  WorldEnvironment %s SIN environment" % n.name)
			continue
		print("DIAG  %s" % n.name)
		print("DIAG    ambient=%.2f color=%s source=%d" % [
			e.ambient_light_energy, str(e.ambient_light_color), e.ambient_light_source])
		print("DIAG    exposure=%.2f  tonemap=%d  bg=%d" % [
			e.tonemap_exposure, e.tonemap_mode, e.background_mode])
		print("DIAG    fog d=%.4f vol=%.4f  sky=%s" % [
			e.fog_density, e.volumetric_fog_density,
			("si" if e.sky != null else "NO")])
		if e.sky != null and e.sky.sky_material is ProceduralSkyMaterial:
			var c: ProceduralSkyMaterial = e.sky.sky_material
			print("DIAG    cielo top=%s  horizon=%s" % [
				str(c.sky_top_color), str(c.sky_horizon_color)])
		else:
			print("DIAG    cielo: material de tipo %s" % str(e.sky.sky_material))


func _apagar_sistemas() -> void:
	for n in root.find_children("*", "", true, false):
		var s := String(n.name)
		if s == "CicloDia" or s == "Clima" or s.begins_with("Cielo"):
			(n as Node).process_mode = Node.PROCESS_MODE_DISABLED
			print("[LOOK] sistema apagado para la prueba: %s" % s)
	# Y el `Environment` no es un nodo: se llega por los WorldEnvironment que ya
	# existen, y se los congela con `environment` listo para escribir.
	print("[LOOK] el ciclo de dia y el clima quedan apagados: escribian la "
		+ "luz cada frame y ganaban despues")


func _aplicar() -> void:
	match _look:
		"oscuro":
			_oscuro()
		_:
			push_warning("[LOOK] look desconocido: %s" % _look)
	if not _ya_anunciado:
		_ya_anunciado = true
		print("[LOOK] look %s aplicado, y re-aplicado cada frame porque el "
			% _look + "ciclo de dia reescribe el cielo cada frame")


func _oscuro() -> void:
	# --- el cielo, primero: si el cielo brilla, nada mas puede verse oscuro ---
	for n in root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (n as WorldEnvironment).environment
		if env == null:
			continue
		# Un cielo procedural de dia es un foco de luz enorme. Al atardecer se
		# pone el sol bajo y el cielo se apaga.
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var cielo: ProceduralSkyMaterial = env.sky.sky_material
			cielo.sky_top_color = Color(0.035, 0.045, 0.070)
			cielo.sky_horizon_color = Color(0.190, 0.130, 0.105)
			cielo.sky_curve = 0.22
			cielo.ground_bottom_color = Color(0.020, 0.022, 0.028)
			cielo.ground_horizon_color = Color(0.070, 0.070, 0.085)
			cielo.sun_angle_max = 8.0
			cielo.sun_curve = 0.06

		# --- ambiente casi nulo: la sombra tiene que ser NEGRA ---
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.038, 0.040, 0.048)
		env.ambient_light_sky_contribution = 0.0
		env.ambient_light_energy = 0.16
		env.reflected_light_source = Environment.REFLECTION_SOURCE_BG

		# --- TONEMAP: ACES con la exposicion ABAJO. Este es el numero que mas
		# cambia la imagen y el mas facil de olvidar: sin bajar la exposicion,
		# todo lo demas se ve igual porque el tonemap sube lo que se apaga. ---
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 0.52
		env.tonemap_white = 3.2

		# --- NIEBLA. Doble: la clasica por profundidad para el alcance, y la
		# VOLUMETRICA para la luz que se ve. Sin la volumetrica no hay rayos de
		# sol atravesando la niebla, y eso es la mitad del look. ---
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = Color(0.042, 0.046, 0.058)
		env.fog_light_energy = 0.6
		env.fog_density = 0.0016
		env.fog_depth_begin = 45.0
		env.fog_depth_end = 320.0
		env.fog_sky_affect = 0.0
		env.fog_height = 0.0
		env.fog_height_density = 0.012

		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.0022
		env.volumetric_fog_albedo = Color(0.16, 0.17, 0.21)
		env.volumetric_fog_emission = Color(0.030, 0.034, 0.048)
		env.volumetric_fog_emission_energy = 0.10
		env.volumetric_fog_gi_inject = 0.0
		env.volumetric_fog_anisotropy = 0.32
		env.volumetric_fog_length = 96.0
		env.volumetric_fog_detail_spread = 2.0
		env.volumetric_fog_ambient_inject = 0.0

		# --- occlusion y dispersion ---
		if env.ssao_enabled:
			env.ssao_radius = 2.2
			env.ssao_intensity = 4.2
			env.ssao_power = 2.0
			env.ssao_detail = 1.0
		env.ssil_enabled = true
		env.ssil_intensity = 1.1
		env.ssil_radius = 4.0
		env.ssil_normal_rejection = 1.0

		# --- GLOW solo en lo que de verdad emite: antorchas, lava, luna ---
		env.glow_enabled = true
		env.glow_intensity = 0.85
		env.glow_strength = 1.0
		env.glow_bloom = 0.12
		env.glow_hdr_threshold = 0.92
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		env.glow_hdr_scale = 2.2

		# --- EL GRADO DE COLOR. Contraste arriba y saturacion ABAJO: en este
		# look la sangre y el fuego se leen por contraste, no por color. Con la
		# saturacion de 1,14 que tenia antes, todo se ve pintado. ---
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.0
		env.adjustment_contrast = 0.20
		env.adjustment_saturation = -0.16

		# --- EL FILTRO DE LENTE, Y POR QUE NO ESTA AQUI ---
		# Vignette, film grain y aberracion cromatica NO son properties de
		# `Environment` en Godot 4.7. La vignette vive en
		# `CameraAttributesPractical`, y el grano y la aberracion son del
		# COMPOSITOR, que es otra cosa enteramente (`Compositor` +
		# `CompositorEffect`). Asignarlos aca tira error en cada frame.
		#
		# El contraste y la saturacion de arriba hacen el trabajo de ahi: la
		# viñetapscura las cuatro esquinas, que se puede lograr Bajando el ambiente
		# y con la niebla, que ya esta puesta. Y el grano, cuando se pueda hacer
		# con el compositor, es lo ultimo que hay que anadir.

	# --- el sol: una sola fuente, baja y calida. La altura es lo que dibuja la
	# silueta: con el sol alto no hay sombras largas, y sin sombras largas no hay
	# lectura de volumen. ---
	for n in root.find_children("*", "DirectionalLight3D", true, false):
		var sol: DirectionalLight3D = n
		if sol.name == "Luna":
			continue
		sol.rotation = Vector3(deg_to_rad(-24.0), deg_to_rad(41.0), 0.0)
		sol.light_color = Color(1.0, 0.80, 0.60)
		sol.light_energy = 3.4
		sol.light_angular_distance = 0.8
		sol.shadow_enabled = true
		sol.shadow_blur = 1.6
		sol.shadow_normal_bias = 1.2
		sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sol.directional_shadow_max_distance = 85.0
	for n in root.find_children("*", "DirectionalLight3D", true, false):
		if (n as DirectionalLight3D).name == "Luna":
			(n as DirectionalLight3D).light_energy = 0.10
	# LAS ANTORCHAS. Hay 20 en la plaza y estaban a 0,8-1,0 de energia, que es lo
	# justo para verse de dia. En una escena oscura son la ILUMINACION, no un
	# detalle: si no iluminan, la escena esta a oscuras y no se ve nada.
	# Con radio mas grande porque a 0,8 de energia y radio chico iluminan un
	# metro y el resto de la plaza queda negro.
	var antorchas := 0
	for n in root.find_children("*", "OmniLight3D", true, false):
		var o := n as OmniLight3D
		if o.light_energy <= 0.0:
			continue
		# LA LAMPARA Y EL NODO, no solo la luz. Un OmniLight con el nodo padre
		# invisible tampoco dibuja nada, y en el diagnostico cinco de las veinte
		# estaban apagadas por el ciclo de dia.
		var padre := o.get_parent()
		while padre != null:
			if not (padre as Node3D).visible:
				(padre as Node3D).visible = true
				break
			padre = padre.get_parent()
		o.visible = true
		if o.omni_range < 8.0:
			o.omni_range = 16.0
		o.light_energy = maxf(o.light_energy, 3.2)
		o.omni_attenuation = 1.3
		antorchas += 1
	# Y las llamas, que son las mallas: si la llama no se dibuja, el jugador no
	# ve de donde sale la luz, y una luz sin fuente visible parece un error.
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if String(n.name).find("Llama") >= 0 or String(n.name).find("llama") >= 0:
			(n as Node3D).visible = true
	print("[LOOK] antorchas encendidas: %d" % antorchas)
	# El sol deja de ser la fuente principal: es el relleno del cielo.
	for n in root.find_children("*", "DirectionalLight3D", true, false):
		var d := n as DirectionalLight3D
		if d.name == "Sol":
			d.light_energy = 0.85
			d.light_color = Color(0.72, 0.74, 0.90)


func _brillo(img: Image) -> float:
	var suma: float = 0.0
	var n: int = 0
	var paso: int = maxi(1, img.get_width() / 160)
	for y in range(0, img.get_height(), paso):
		for x in range(0, img.get_width(), paso):
			suma += img.get_pixel(x, y).get_luminance()
			n += 1
	return suma / maxf(float(n), 1.0)


func _min(img: Image) -> int:
	var v: int = 255
	var paso: int = maxi(1, img.get_width() / 160)
	for y in range(0, img.get_height(), paso):
		for x in range(0, img.get_width(), paso):
			v = mini(v, int(img.get_pixel(x, y).get_luminance() * 255.0))
	return v


func _max(img: Image) -> int:
	var v: int = 0
	var paso: int = maxi(1, img.get_width() / 160)
	for y in range(0, img.get_height(), paso):
		for x in range(0, img.get_width(), paso):
			v = maxi(v, int(img.get_pixel(x, y).get_luminance() * 255.0))
	return v
