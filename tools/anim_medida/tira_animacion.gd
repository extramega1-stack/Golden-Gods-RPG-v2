extends SceneTree
## TiraAnimacion — la marcha de un vistazo, sin abrir el juego a mano.
##
## POR QUÉ EXISTE: hay cosas que un número no dice. Si el pie patina, el
## número lo dice; si la marcha va al revés, el número también; pero si el
## personaje parece una jabalina con piernas, hace falta VERLO. Y verlo a mano
## cuesta: hay que encontrar el goblin, medir cuánto camina, esperar al ciclo
## justo y tenerle el ojo encima a 60 fps. Esta herramienta saca 12 fotos del
## mismo ciclo, con fondo uniforme y el personaje centrado, y las junta en una
## tira.
##
## LAS DOS TIRAS, y por qué las dos:
## - `lugar`: el ciclo en el sitio, el cuerpo quieto. Se ve la MÁQUINA del
##   clip: qué hace la pierna con el cuerpo quieto. Si el pie barre hacia
##   atrás en el aire y hacia delante en el suelo, aquí se ve clarísimo.
## - `mundo`: el cuerpo AVANZA a la velocidad real del juego y la cámara lo
##   sigue, con el suelo rayado de marcas cada 0,5 u. Si el pie patina, deja
##   de estar sobre la misma marca; si no patina, la marca no cambia. Es la
##   tira que demuestra el número de patinaje.
##
## NECESITA VENTANA. Sin `--headless`, porque sin ventana Godot usa el driver
## dummy y las imágenes salen negras. En headless esta herramienta lo dice y
## escribe el motivo en el JSON, para que el informe lo reporte como "no se
## puede medir" en vez de fingir que no hizo falta.
##
## USO
##   godot --path . --script res://tools/anim_medida/tira_animacion.gd -- \
##       --clase=guerrero --frames=12 --ancho=200 --alto=300
##   godot --headless --path . --script res://tools/anim_medida/tira_animacion.gd
##
## SALIDA
##   <salida>/frame_mundo_00.png … (una por frame, las dos tiras)
##   <salida>/tira_mundo.png      (las 12 pegadas en una fila)
##   <salida>/tira_lugar.png
##   <salida>/tira.json           (lo que lee la bancada y lo pega al informe)

const LOCALIZADOR: GDScript = preload("res://tools/anim_medida/localizador.gd")
const CUERPO: GDScript = preload("res://scripts/core/cuerpo.gd")
const PLAYER: GDScript = preload("res://scripts/player/player.gd")

const RUTA_CLASES: String = "res://data/clases.json"
const SALIDA_POR_DEFECTO: String = "build/tira_animacion"
const RUTA_JSON: String = "tira.json"
const CLIP_POR_DEFECTO: String = "walk"

## El fondo uniforme: un gris medio frío. Contra él se ve cualquier silueta y
## no compite con el color de la textura del modelo.
const FONDO: Color = Color(0.32, 0.36, 0.42)
const COLOR_SUELO: Color = Color(0.55, 0.55, 0.58)
const COLOR_MARCA: Color = Color(0.80, 0.80, 0.84)
const COLOR_PIE_IZQ: Color = Color(1.0, 0.25, 0.20)
const COLOR_PIE_DER: Color = Color(0.25, 0.55, 1.0)
## Separación de las marcas del suelo, en u. Media yarda: se distinguen a simple
## vista y no marean.
const PASO_MARCA: float = 0.5
## Margen de encuadre sobre el tamaño del personaje.
const MARGEN: float = 1.15
## Luz ambiente, para que la cara oculta del personaje no sea un agujero negro.
const AMBIENTE: float = 0.85

const MODO_LUGAR: String = "lugar"
const MODO_MUNDO: String = "mundo"

var _clase: String = "guerrero"
var _modelo: String = ""
var _clip: String = CLIP_POR_DEFECTO
var _frames: int = 12
var _ancho: int = 200
var _alto: int = 300
var _salida: String = SALIDA_POR_DEFECTO
var _velocidad: float = 0.0
var _escala: float = 1.0

var _fase: int = 0
var _inst: Node3D = null
var _anim: AnimationPlayer = null
var _skel: Skeleton3D = null
var _vp: SubViewport = null
var _camara: Camera3D = null
var _camara_base: Vector3 = Vector3.ZERO
var _tiras: Dictionary = {}
var _marcas_izq: MeshInstance3D = null
var _marcas_der: MeshInstance3D = null
var _muestras: Array[Dictionary] = []
var _crono: float = 0.0
var _i: int = 0
var _modo: String = MODO_MUNDO
var _hechas: Dictionary = {}
var _errores: Array[String] = []
var _pendiente: bool = false
var _fotos: Array[Image] = []
var _primera_foto: Image = null


func _initialize() -> void:
	_leer_argumentos()
	_comprobar_ventana()


func _leer_argumentos() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clase="):
			_clase = a.get_slice("=", 1)
		elif a.begins_with("--modelo="):
			_modelo = a.get_slice("=", 1)
		elif a.begins_with("--clip="):
			_clip = a.get_slice("=", 1)
		elif a.begins_with("--frames="):
			_frames = maxi(int(a.get_slice("=", 1)), 2)
		elif a.begins_with("--ancho="):
			_ancho = maxi(int(a.get_slice("=", 1)), 32)
		elif a.begins_with("--alto="):
			_alto = maxi(int(a.get_slice("=", 1)), 32)
		elif a.begins_with("--salida="):
			_salida = a.get_slice("=", 1)
		elif a.begins_with("--velocidad="):
			_velocidad = float(a.get_slice("=", 1))


## Sin ventana no hay render, y una tira de PNGs negros es peor que no tener
## tira: parece que la animación anda mal. Se dice y se sale.
func _comprobar_ventana() -> void:
	if DisplayServer.get_name() != "headless":
		return
	var motivo: String = "la tira necesita ventana: sin ella Godot usa el driver " \
			+ "dummy y las imagenes salen negras. Correr SIN --headless."
	_errores.append(motivo)
	print("[TIRA] no se puede medir: %s" % motivo)
	_terminar()
	quit(0)


func _process(delta: float) -> bool:
	match _fase:
		0:
			_montar()
			_fase = 1
		1:
			_capturar()
		2:
			_fase = 1
			_modo = MODO_LUGAR
			_i = 0
			_pendiente = false
		_:
			_terminar()
			quit(0)
			return true
	return false


## El palco: un `SubViewport` con su propio mundo 3D, un entorno de fondo
## uniforme, una luz, el suelo rayado, el modelo y dos bolas en los pies.
func _montar() -> void:
	if _modelo == "":
		_modelo = _modelo_de_clase()
	if _modelo == "" or not ResourceLoader.exists(_modelo):
		_errores.append("el modelo '%s' no existe" % _modelo)
		print("[TIRA] %s" % _errores[0])
		_terminar()
		_fase = 9
		return
	if not DirAccess.dir_exists_absolute("res://" + _salida):
		DirAccess.make_dir_recursive_absolute("res://" + _salida)
	_vp = SubViewport.new()
	_vp.size = Vector2i(_ancho, _alto)
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_ambiente()
	if is_zero_approx(_velocidad):
		_velocidad = _velocidad_del_juego()
	_inst = (load(_modelo) as PackedScene).instantiate() as Node3D
	_inst.name = "Modelo"
	_inst.rotation.y = float(CUERPO.GIRO_MODELO)
	_vp.add_child(_inst)
	_anim = LOCALIZADOR.reproductor(_inst)
	_skel = LOCALIZADOR.esqueleto(_inst)
	if _anim == null or _skel == null:
		_errores.append("el modelo no tiene AnimationPlayer o Skeleton3D: "
				+ "no hay nada que renderizar")
		_terminar()
		_fase = 9
		return
	_inst.scale = Vector3.ONE * _escala
	_suelo()
	_marcas()
	_camara = Camera3D.new()
	_camara.fov = 50.0
	_vp.add_child(_camara)
	_muestras = _muestras_del_ciclo()
	_hechas = {"ok": true, "modelo": _modelo, "clip": _clip,
			"frames": _muestras.size(), "ancho": _ancho, "alto": _alto,
			"fondo": "#%s" % FONDO.to_html(false), "velocidad": _velocidad,
			"escala": _escala, "carpeta": "res://" + _salida, "tira": "",
			"pngs": [] as Array[String], "notas": [] as Array[String]}
	_enquadrar()


## Un fondo de un solo color y una luz ambiente: sin esto la mitad del
## personaje es negra y la tira no sirve para juzgar nada.
func _ambiente() -> void:
	var entorno := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = FONDO
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.98, 0.95)
	env.ambient_light_energy = AMBIENTE
	# Sin tonemap: los colores de las marcas tienen que ser los que se
	# escribieron, o el rojo del pie izquierdo sale ladrillo.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	entorno.environment = env
	_vp.add_child(entorno)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(40.0), 0.0)
	luz.light_energy = 1.4
	luz.shadow_enabled = false
	_vp.add_child(luz)


## El suelo: una franja clara y las marcas cada 0,5 u. En la tira `mundo` son
## las marcas las que hacen visible el patinaje, porque están Quietas en el
## mundo mientras el pie resbala por encima de ellas.
func _suelo() -> void:
	var suelo := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2(2.0, 40.0)
	suelo.mesh = plano
	suelo.material_override = _material(COLOR_SUELO)
	suelo.position = Vector3(0.0, 0.0, 0.0)
	_vp.add_child(suelo)
	var largo: float = 40.0
	var cuantas: int = int(largo / PASO_MARCA) + 1
	for i in cuantas:
		var marca := MeshInstance3D.new()
		var caja := BoxMesh.new()
		caja.size = Vector3(0.035, 0.004, PASO_MARCA * 0.45)
		marca.mesh = caja
		marca.material_override = _material(COLOR_MARCA)
		marca.position = Vector3(0.0, 0.004, -float(i) * PASO_MARCA + largo * 0.5)
		_vp.add_child(marca)


## Las dos bolas del pie. En la tira `mundo` son las que muestran el
## deslizamiento sin tener que mirar el hueso: donde esté la bola roja es donde
## el pie izquierdo está, y si entre frames se va de la marca, patina.
func _marcas() -> void:
	_marcas_izq = _bola(COLOR_PIE_IZQ)
	_marcas_der = _bola(COLOR_PIE_DER)
	_vp.add_child(_marcas_izq)
	_vp.add_child(_marcas_der)


func _bola(color: Color) -> MeshInstance3D:
	var nodo := MeshInstance3D.new()
	var esfera := SphereMesh.new()
	esfera.radius = 0.035
	esfera.height = 0.07
	nodo.mesh = esfera
	nodo.material_override = _material(color)
	return nodo


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Las 12 (o las que sean) poses del ciclo, medidas antes de renderizar: el
## encuadre sale de ellas y no de adivinar.
func _muestras_del_ciclo() -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	var largo: float = 1.0
	var duracion: float = 0.0
	if _anim != null and _anim.has_animation(_clip):
		duracion = _anim.get_animation(_clip).length
		largo = maxi(duracion, 0.0001)
	for i in _frames:
		salida.append({"t": largo * float(i) / float(maxi(_frames - 1, 1)),
				"t_rel": float(i) / float(maxi(_frames - 1, 1))})
	return salida


## Encuadra al personaje centrado y de tamaño conocido, mirando de LADO: en
## vista lateral se lee la zancada y se lee el patinaje, que es lo que hay
## que juzgar. La caja se mide sobre las poses del ciclo, no sobre el mesh
## entero, así que el personaje nunca se sale de cuadro al moverse.
## Encuadra al PERSONAJE COMPLETO, centrado, mirando de lado.
##
## Se mide sobre los huesos del esqueleto de TODAS las poseS del ciclo, no solo
## los de los pies. Encuadrar solo los pies es el error que salió: la caja
## quedaba de 2 cm de alto en el tobillo, la camara se metia por debajo del
## suelo, el plano de 2x40 u llenaba el cuadro entero y las doce fotos salian
## del MISMO gris. Un instrumento que miente y no lo dice es peor que uno que
## no mide, asi que ademas hay una puerta de calidad mas abajo.
func _enquadrar() -> void:
	var puntos: Array[Vector3] = []
	for m in _muestras:
		_poner_pose(float(m["t"]))
		for pos in _posiciones_de_huesos():
			puntos.append(_inst.to_global(pos))
	var caja: AABB = AABB()
	var primero: bool = true
	for p in puntos:
		if primero:
			caja = AABB(p, Vector3.ZERO)
			primero = false
		else:
			caja = caja.expand(p)
	# La malla, que puede salir de los huesos (un casco, una espada).
	caja = caja.merge(_caja_de_la_malla())
	if primero:
		caja = AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
	# Un poco de aire: ni la cabeza ni los pies pueden tocar el borde.
	caja = caja.grow(0.10 * maxf(caja.size.y, 0.5))
	var centro: Vector3 = caja.get_center()
	var tam: Vector3 = caja.size
	# De lado y un poco por encima de la cintura, que es desde donde se lee
	# una marcha: la zancada se ve de perfil y el pie se ve contra el suelo.
	var hacia: Vector3 = Vector3(1.0, 0.10, 0.0).normalized()
	var fov: float = deg_to_rad(_camara.fov)
	var aspecto: float = float(_ancho) / float(_alto)
	var d_v: float = (tam.y * 0.5) / tan(fov * 0.5)
	var d_h: float = (maxf(tam.x, tam.z) * 0.5) / maxf(tan(fov * 0.5) * aspecto, 0.001)
	var distancia: float = maxf(d_v, d_h) * MARGEN
	_camara.position = centro + hacia * distancia
	_camara.look_at(centro, Vector3.UP)
	# La posicion de referencia, para que la camara siga al cuerpo que avanza
	# en vez de ir arrastrando el desplazamiento frame a frame.
	_camara_base = _camara.position


## La caja de la malla visual, ya en el espacio del viewport. Se transforman
## las ocho esquinas una por una en vez de multiplicar la `AABB` entera: el
## operador `Transform3D * AABB` no existe en GDScript 4.7 y sale un error de
## tipeo que se lee como si el problema fuera otro.
func _caja_de_la_malla() -> AABB:
	var malla: MeshInstance3D = CUERPO.malla(_inst)
	if malla == null or malla.mesh == null:
		return AABB()
	var local: AABB = malla.mesh.get_aabb()
	var fuera: AABB = AABB()
	var primero: bool = true
	for i in 8:
		var esquina: Vector3 = malla.global_transform * local.get_endpoint(i)
		if primero:
			fuera = AABB(esquina, Vector3.ZERO)
			primero = false
		else:
			fuera = fuera.expand(esquina)
	return fuera


## Un instante del clip, en la rama del modelo.
func _poner_pose(t: float) -> void:
	if _anim == null:
		return
	_anim.play(_clip)
	_anim.seek(t, true)
	_anim.advance(0.0)


## TODOS los huesos, no solo los de los pies: el encuadre tiene que incluir la
## cabeza o el personaje sale de cuadro.
func _posiciones_de_huesos() -> Array[Vector3]:
	var salida: Array[Vector3] = []
	if _skel == null:
		return salida
	for i in _skel.get_bone_count():
		salida.append((_skel.get_bone_global_pose(i) as Transform3D).origin)
	return salida


## Un frame, en DOS fases, y no es un detalle: la imagen de un `SubViewport`
## es la del ÚLTIMO dibujado, no la del estado actual de los nodos. Si se pone
## la pose y se lee la imagen en el mismo frame, se leen doce veces la misma
## foto (que es lo que pasaba: doce PNGs de 856 bytes, todos idénticos). Por
## eso: un frame se pone la pose, y el siguiente se lee.
func _capturar() -> void:
	if _i >= _muestras.size():
		_pasar_de_modo()
		return
	if not _pendiente:
		_poner_frame()
		_pendiente = true
		return
	_pendiente = false
	var imagen: Image = _vp.get_texture().get_image()
	if imagen == null or imagen.is_empty():
		_errores.append("el SubViewport devolvio una imagen vacia en el frame %d" % _i)
		_fase = 9
		return
	(_hechas["pngs"] as Array[String]).append(
			"res://%s/frame_%s_%02d.png" % [_salida, _modo, _i])
	imagen.save_png("res://%s/frame_%s_%02d.png" % [_salida, _modo, _i])
	var copia: Image = imagen.duplicate()
	_fotos.append(copia)
	if _primera_foto == null:
		_primera_foto = copia
	_agregar_a_tira(imagen)
	_i += 1
	_crono += 1.0 / 60.0


## La pose del frame `_i` en el palco, con el cuerpo mas o menos avanzado.
func _poner_frame() -> void:
	var m: Dictionary = _muestras[_i]
	var t: float = float(m["t"])
	# En `mundo` el cuerpo avanza a la velocidad real y la cámara lo sigue; en
	# `lugar` el cuerpo se queda quieto y solo se mueve la pose.
	var avance: float = 0.0
	if _modo == MODO_MUNDO:
		avance = -_velocidad * t
	_inst.position = Vector3(0.0, 0.0, avance)
	if _camara != null:
		_camara.position = _camara_base + Vector3(0.0, 0.0, avance)
	_poner_pose(t)
	_colocar_marcas()


func _colocar_marcas() -> void:
	if _skel == null:
		return
	var piernas: Dictionary = LOCALIZADOR.piernas(_skel)
	if _marcas_izq != null:
		var izq: int = int((piernas.get("izq", {}) as Dictionary).get("pie", -1))
		if izq >= 0:
			var origen: Vector3 = (_skel.get_bone_global_pose(izq) as Transform3D).origin
			_marcas_izq.position = _inst.to_global(origen)
	if _marcas_der != null:
		var der: int = int((piernas.get("der", {}) as Dictionary).get("pie", -1))
		if der >= 0:
			var origen: Vector3 = (_skel.get_bone_global_pose(der) as Transform3D).origin
			_marcas_der.position = _inst.to_global(origen)


## Las tiras se guardan aparte, porque un `Image` dentro del `Dictionary` que
## se serializa a JSON rompe el `JSON.stringify` y el informe se queda sin
## salida. `_tiras` es de Memoria; `_hechas` es lo que se escribe.
func _agregar_a_tira(imagen: Image) -> void:
	var clave: String = "tira_" + _modo
	if not _tiras.has(clave):
		_tiras[clave] = imagen.duplicate()
		return
	var tira: Image = _tiras[clave] as Image
	var pegada: Image = imagen.duplicate()
	var x: int = _i * _ancho
	if x + pegada.get_width() > tira.get_width():
		# La tira se agranda: un `Image` es de tamaño fijo y recorte se le
		# nota (frames que desaparecen).
		var nueva: Image = Image.create_empty(maxi(tira.get_width(),
				x + pegada.get_width()), maxi(tira.get_height(), _alto), false,
				tira.get_format())
		nueva.blit_rect(tira, Rect2i(0, 0, tira.get_width(), tira.get_height()),
				Vector2i.ZERO)
		tira = nueva
	tira.blit_rect(pegada, Rect2i(0, 0, pegada.get_width(), pegada.get_height()),
			Vector2i(x, 0))
	_tiras[clave] = tira


func _pasar_de_modo() -> void:
	var clave: String = "tira_" + _modo
	# LA PUERTA DE CALIDAD. Doce fotos del mismo gris no son un playtest: son
	# un render que no cambio. Compararlas entre si es barato y convierte el
	# fallo mas silencioso de esta herramienta (encuadre roto, camara dentro
	# del suelo, SubViewport sin renderizar) en un motivo escrito.
	var identicas: int = _contar_identicas()
	if identicas >= maxi(_muestras.size() - 1, 1):
		_errores.append("las %d fotos de la tira '%s' salieron IDENTICAS: el "
				% [_muestras.size(), _modo]
				+ "render no esta cambiando, la tira no sirve para nada")
	_hechas["fotos_identicas"] = identicas
	if _tiras.has(clave):
		var tira: Image = _tiras[clave] as Image
		tira.save_png("res://%s/%s.png" % [_salida, clave])
		# Una clave por tira, no una sola: con una sola, la segunda pisaba la
		# primera y el informe citaba siempre `lugar`, que es la que menos
		# muestra.
		_hechas[clave] = "res://%s/%s.png" % [_salida, clave]
		print("[TIRA] %s/%s.png  (%d frames de %dx%d)" % [_salida, clave,
				_muestras.size(), _ancho, _alto])
	if _modo == MODO_MUNDO:
		_fase = 2
	else:
		_fase = 3


## El JSON que lee `bancada_animacion.gd` y pega al informe. Aunque no haya
## tira, se escribe: el informe tiene que poder decir POR QUÉ no la hay.
## Cuántas de las fotos capturadas son byte a byte igual que la primera.
func _contar_identicas() -> int:
	var primera: Image = _primera_foto
	if primera == null or _fotos.is_empty():
		return 0
	var iguales: int = 0
	for f in _fotos:
		if f.get_data() == primera.get_data():
			iguales += 1
	return iguales


func _terminar() -> void:
	var salida: Dictionary = _hechas.duplicate(true)
	salida["ok"] = _errores.is_empty() and bool(_hechas.get("ok", false))
	if not _errores.is_empty():
		salida["ok"] = false
		salida["motivo"] = "; ".join(_errores)
	if not FileAccess.file_exists("res://" + _salida):
		DirAccess.make_dir_recursive_absolute("res://" + _salida)
	var f: FileAccess = FileAccess.open("res://%s/%s" % [_salida, RUTA_JSON],
			FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(salida, "  "))
		f.close()
		print("[TIRA] %s/%s" % [_salida, RUTA_JSON])


## La velocidad REAL del juego, leída del mismo `Player` que la lee la
## bancada. Si se inventara un 6,0 de memoria y el jugador cambiara, la tira
## estaría mostrando un patinaje que el juego no tiene.
func _velocidad_del_juego() -> float:
	var p: Node = PLAYER.new()
	p.set("nombre", "H")
	p.call("fijar_identidad", "H", _clase)
	root.add_child(p)
	p.call("aplicar_clase", _clase)
	var stats: Object = p.get("stats") as Object
	var v: float = 0.0
	if stats != null:
		v = float(stats.get("vel_mov"))
	p.queue_free()
	return v


func _modelo_de_clase() -> String:
	if not FileAccess.file_exists(RUTA_CLASES):
		return ""
	var f: FileAccess = FileAccess.open(RUTA_CLASES, FileAccess.READ)
	if f == null:
		return ""
	var datos: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (datos is Dictionary):
		return ""
	var clases: Dictionary = (datos as Dictionary).get("clases", {}) as Dictionary
	var entrada: Dictionary = clases.get(_clase, {}) as Dictionary
	if entrada.is_empty():
		return ""
	_escala = float(entrada.get("modelo_escala", 1.0))
	return str(entrada.get("modelo", ""))
