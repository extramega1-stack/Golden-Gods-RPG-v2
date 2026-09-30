extends SceneTree
## Captura la escena del juego con el MISMO encuadre, para comparar dos looks.
##
## Por que una herramienta y no una foto a mano: para probar que un cambio de
## iluminacion funciona hay que comparar la MISMA vista antes y despues. Con
## encuadres distintos no se puede afirmar nada, y el ojo se deja engañar por el
## zoom.
##
## Uso:
##   godot --path . --script res://tools/captura_luz.gd -- --salida=build/capturas --etiqueta=antes
##
## Por que NO se puede testear en headless: un driver dummy no renderiza nada.
## Con `--headless` sale un PNG negro y uno podria concluir que el cambio rompio
## la imagen, cuando en realidad no se dibujo. Con ventana de verdad.

const DEMO := "res://scenes/demo/fase14_demo.tscn"
const ESPERAR := 900          # frames antes de capturar: el mundo tarda en armar
const ANCHO := 1600
const ALTO := 900


var _n: int = 0
var _hecho: bool = false
var _salida: String = "build/capturas"
var _etiqueta: String = "antes"
## Camara libre para encuadrar una superficie concreta. Sin esto solo se puede
## mirar la plaza entera desde el jugador, y a esa distancia no se juzga una
## textura: hay que pegarse a la pared.
var _cam: Vector3 = Vector3.ZERO
var _mira: Vector3 = Vector3.ZERO
var _fov: float = 0.0
var _tiene_cam: bool = false
## Encuadra automatically la superficie pedida. Adivinar coordenadas de la
## ciudad una y otra vez es perder tiempo: el layout puede cambiar y la captura
## queda mirando al vacio sin avisar. Con "auto" se busca el mesh y se mira su
## AABB, que es lo unico que no cambia.
var _auto: String = ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--salida="):
			_salida = a.get_slice("=", 1)
		elif a.begins_with("--etiqueta="):
			_etiqueta = a.get_slice("=", 1)
		elif a.begins_with("--cam="):
			_cam = _vec3(a.get_slice("=", 1))
			_tiene_cam = true
		elif a.begins_with("--mira="):
			_mira = _vec3(a.get_slice("=", 1))
		elif a.begins_with("--fov="):
			_fov = float(a.get_slice("=", 1))
		elif a.begins_with("--auto="):
			_auto = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_salida))
	root.content_scale_size = Vector2i(ANCHO, ALTO)

	var ps: PackedScene = load(DEMO)
	if ps == null:
		push_error("[CAPTURA] no se pudo cargar la escena")
		quit(1)
		return
	var mundo: Node = ps.instantiate()
	root.add_child(mundo)
	print("[CAPTURA] mundo instanciado, esperando %d frames" % ESPERAR)


func _process(_delta: float) -> bool:
	_n += 1
	if _n == 120 and (_tiene_cam or _auto != ""):
		_poner_camara()
	if _n < ESPERAR or _hecho:
		return false
	_hecho = true
	# Un frame mas despues de _process para que el buffer este completo.
	var vp: Viewport = root
	var img: Image = vp.get_texture().get_image()
	if img == null:
		push_error("[CAPTURA] la imagen vino nula: no hay ventana")
		quit(1)
		return true
	var ruta: String = "%s/%s.png" % [_salida, _etiqueta]
	img.save_png(ruta)
	# El histograma es lo que hace util la captura: dice si la imagen esta
	# quemada (todo en 255) o apagada (todo en 0), que es el fallo tipico al
	# tocar el tonemap. Un PNG mirando no siempre se nota.
	print("[CAPTURA] %s  %dx%d" % [ruta, img.get_width(), img.get_height()])
	print("[CAPTURA] brillo medio=%.3f  min=%d  max=%d" % [
		_brillo(img), _min(img), _max(img)])
	quit(0)
	return true


func _vec3(s: String) -> Vector3:
	var p: PackedStringArray = s.split(",")
	if p.size() < 3:
		return Vector3.ZERO
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


## Busca el mesh pedido y devuelve donde tiene que estar la camara para
## llenarlo de pantalla. Elige el de MAYOR volumen, que es el que mas superficie
## muestra.
func _buscar_auto() -> MeshInstance3D:
	var mejor: MeshInstance3D = null
	var vol := 0.0
	# El mundo es de 36.864 u y hay nueve ciudades. Sin este filtro el muro con
	# mas volumen sale a 5.540 unidades, en otra ciudad, y la captura no sirve
	# para juzgar nada. Solo interesan los muros donde el jugador esta.
	var ref: Vector3 = _pos_jugador()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var nm := String(n.name)
		match _auto:
			"pared":
				# Un muro es vertical, ancho y con altura apreciable; y no es
				# terreno (los chunks son enormes y planos).
				if nm.begins_with("Chunk_"):
					continue
				var sz := m.get_aabb().size
				if sz.y < 3.0 or sz.x < 1.5 or sz.z > sz.x * 1.6:
					continue
			"suelo":
				if not nm.begins_with("Chunk_"):
					continue
			_:
				pass
		var a0: AABB = m.global_transform * m.get_aabb()
		if ref != Vector3.ZERO and a0.get_center().distance_to(ref) > 220.0:
			continue
		var sz2 := a0.size
		var v: float = sz2.x * sz2.y * sz2.z
		if v > vol:
			vol = v
			mejor = m
	return mejor


## Donde esta el jugador, o el origen si todavia no existe.
func _pos_jugador() -> Vector3:
	for g in ["gg_system", "Player", ""]:
		for n in root.find_children("*", "Node3D", true, false):
			if not n.is_in_group("gg_system"):
				continue
			if String(n.name).find("jugador") >= 0 or String(n.name).find("Player") >= 0:
				return (n as Node3D).global_position
	for c in root.find_children("*", "Camera3D", true, false):
		return (c as Camera3D).global_position
	return Vector3.ZERO


func _poner_camara() -> void:
	if _auto != "":
		var obj: MeshInstance3D = _buscar_auto()
		if obj == null:
			push_warning("[CAPTURA] no se encontro nada para auto=%s" % _auto)
			return
		var aabb: AABB = obj.global_transform * obj.get_aabb()
		var c: Vector3 = aabb.get_center()
		var sz: Vector3 = aabb.size
		if _auto == "pared":
			# De frente a la cara mas ancha, a una distancia que la llene.
			var dist: float = maxf(sz.x, sz.y) * 0.85
			_cam = c + Vector3(0.0, 0.0, dist)
			_mira = c
		else:
			_cam = c + Vector3(0.0, sz.y * 1.4, sz.z * 0.6)
			_mira = c
		_tiene_cam = true
		print("[CAPTURA] auto=%s -> %s  centro=%s  tam=%s" % [
			_auto, obj.name, str(c.round()), str(sz.round())])
	var cam: Camera3D = null
	for c in root.find_children("*", "Camera3D", true, false):
		if cam == null or (c as Camera3D).current:
			cam = c as Camera3D
	if cam == null:
		cam = Camera3D.new()
		root.add_child(cam)
	cam.global_position = _cam
	cam.look_at(_mira, Vector3.UP)
	if _fov > 0.0:
		cam.fov = _fov
	cam.current = true
	print("[CAPTURA] camara en %s mirando a %s fov=%.1f" % [str(_cam), str(_mira), cam.fov])


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
