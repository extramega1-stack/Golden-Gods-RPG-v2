extends SceneTree
## Convierte animaciones de Mixamo (FBX) a clips del juego.
##
## POR QUE NO ALCANZA CON IMPORTAR EL FBX: Godot lo importa con la convencion de
## nombres de Mixamo, y el juego usa otra. Ademas el juego tiene 49 huesos, 30
## de ellos de dedos, y Mixamo no trae dedos animables. O sea que hay que MAPEAR.
##
## USO:
##   godot --headless --path . --import
##   godot --headless --path . --script res://tools/retarget_mixamo.gd -- \
##       --fbx=res://anim/fuente/mixamo_attack.fbx \
##       --salida=res://anim/clips/attack.tres --duracion=0.83
##
## ARGUMENTOS:
##   --fbx=      el FBX de Mixamo (ya importado por Godot)
##   --clip=     nombre interno del clip; si falta se usa el primero
##   --salida=   donde se guarda el .tres
##   --duracion= segundos que debe durar. 0 = dejar la duracion original.
##   --blend=    0..0.5, cuanto del final se mezcla hacia el primer cuadro, para
##               que el ciclo no de un tiron al repetirse
##   --loop=1    el clip se repite
##
## POR QUE SE LEEN LAS PISTAS DEL RECURSO Y NO SE EVALUA EL ESQUELETO:
## la version anterior hacia `ap.play()` + `ap.seek()` y leia las poses del
## esqueleto. En un FBX de Mixamo eso no actualiza nada: el horneado salia con
## la misma pose en los 61 cuadros y el unico sintoma era un clip "vacio" que
## igual se guardaba. Ahora se interpolan las claves del `Animation` del FBX
## directamente, que es determinista y no depende del reproductor.
##
## LAS CUATRO COSAS QUE HACE BIEN, que antes estaban mal:
##
## 1. LA RUTA DE LA PISTA. No es `Hips:rotation`. Godot, al importar un GLB,
##    escribe `Rig/Skeleton3D:Hips`: el hueso va como SUBNOMBRE del NodePath, sin
##    la propiedad, y el TIPO de pista decide que se anima. Con la ruta vieja
##    (`Hips:rotacion`, que ademas no es un nombre de propiedad valido) NINGUNA
##    pista aplicaba: el .tres cargaba, los tests pasaban, y el personaje no se
##    movia. Un recurso que carga no es un recurso que funcione.
##
## 2. LAS POSICIONES. Antes se escribia `Vector3.ZERO` en los 20 huesos, lo que
##    manda cada hueso al origen de su padre y APLASTA el esqueleto. Ahora solo
##    se anima la posicion de `Hips`, y unicamente su componente Y (el balanceo
##    vertical), escalada por la diferencia de tamano entre los dos personajes.
##
## 3. EL ROOT MOTION. Las caminatas de Mixamo mueven `Hips` 182 cm hacia
##    adelante. Como el juego mueve al personaje con codigo, copiar eso lo haria
##    moverse dos veces y las dos se pelearian. La traslacion horizontal se
##    descarta: el juego manda.
##
## 4. EL DELTA CONTRA LA POSE DE REPOSO. Se copia la rotacion RELATIVA al
##    reposo de Mixamo, y esa diferencia se aplica sobre el reposo del juego:
##    `destino = reposo_juego * (ahora_mixamo * reposo_mixamo^-1)`. Copiar la
##    rotacion cruda haria que en el primer cuadro el personaje salte a la pose
##    de Mixamo en vez de quedarse en la del juego.

const MAPA: Dictionary = {
	"Hips": "Hips",
	"Spine": "Spine",
	"Spine1": "Chest",
	"Spine2": "Chest",
	"Neck": "Neck",
	"Head": "Head",
	"LeftShoulder": "Shoulder.L",
	"LeftArm": "UpperArm.L",
	"LeftForeArm": "LowerArm.L",
	"LeftHand": "Hand.L",
	"RightShoulder": "Shoulder.R",
	"RightArm": "UpperArm.R",
	"RightForeArm": "LowerArm.R",
	"RightHand": "Hand.R",
	"LeftUpLeg": "Thigh.L",
	"LeftLeg": "Shin.L",
	"LeftFoot": "Foot.L",
	"RightUpLeg": "Thigh.R",
	"RightLeg": "Shin.R",
	"RightFoot": "Foot.R",
}

const PREFIJO_ESQ := "Rig/Skeleton3D"

var _ruta_fbx: String = ""
var _clip: String = ""
var _salida: String = ""
var _duracion: float = 0.0
var _blend: float = 0.0
var _loop: bool = false
var _bob: bool = true


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fbx="):
			_ruta_fbx = a.get_slice("=", 1)
		elif a.begins_with("--clip="):
			_clip = a.get_slice("=", 1)
		elif a.begins_with("--salida="):
			_salida = a.get_slice("=", 1)
		elif a.begins_with("--duracion="):
			_duracion = maxf(0.0, a.get_slice("=", 1).to_float())
		elif a.begins_with("--blend="):
			_blend = clampf(a.get_slice("=", 1).to_float(), 0.0, 0.5)
		elif a == "--loop=1":
			_loop = true
		elif a == "--bob=0":
			_bob = false
	if _ruta_fbx == "" or _salida == "":
		push_error("[RT] falta --fbx o --salida")
		quit(1)
		return
	if not ResourceLoader.exists(_ruta_fbx):
		push_error("[RT] el FBX no esta importado. Corre antes "
			+ "'godot --headless --path . --import'")
		quit(1)
		return
	_convertir()


func _convertir() -> void:
	var destino: Node = load("res://models/clase_guerrero.glb").instantiate()
	root.add_child(destino)
	var esq_d: Skeleton3D = _primer_esq(destino)
	if esq_d == null:
		push_error("[RT] el modelo del juego no tiene Skeleton3D")
		quit(1)
		return

	var fuente: Node = load(_ruta_fbx).instantiate()
	root.add_child(fuente)
	var esq_f: Skeleton3D = null
	var ap: AnimationPlayer = null
	for n in _descendientes(fuente):
		if esq_f == null and n is Skeleton3D:
			esq_f = n
		if ap == null and n is AnimationPlayer:
			ap = n
	if esq_f == null or ap == null:
		push_error("[RT] el FBX no trae esqueleto con animacion")
		quit(1)
		return

	var lista: PackedStringArray = ap.get_animation_list()
	if _clip == "" and lista.size() > 0:
		_clip = lista[0]
	if not lista.has(_clip):
		push_error("[RT] no existe '%s'. Hay: %s" % [_clip, str(lista)])
		quit(1)
		return
	var orig: Animation = ap.get_animation(_clip)
	var fps: float = 30.0
	var cuadros: int = maxi(2, int(round(orig.length * fps)))
	print("[RT] clip '%s': %.3f s = %d cuadros" % [_clip, orig.length, cuadros])

	# --- indice: nombre de Mixamo -> pista de rotacion ---
	# Se leen las rutas del recurso. El hueso es el SUBNOMBRE del NodePath
	# (`Skeleton3D:mixamorig_Hips`).
	var pista_rot: Dictionary = {}
	var pista_pos: Dictionary = {}
	for i in range(orig.get_track_count()):
		var ruta := orig.track_get_path(i)
		var sub := str(ruta.get_subname(0))
		if sub.is_empty():
			# Sin subnombre: se saca del texto de la ruta.
			var trozos := str(ruta).split(":")
			sub = trozos[1] if trozos.size() > 1 else ""
		var limpio := _limpiar(sub)
		if not MAPA.has(limpio):
			continue
		if orig.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			if not pista_rot.has(limpio):
				pista_rot[limpio] = i
		elif orig.track_get_type(i) == Animation.TYPE_POSITION_3D and limpio == "Hips":
			pista_pos[limpio] = i
	print("[RT] pistas usables: %d rotacion, %d posicion"
		% [pista_rot.size(), pista_pos.size()])
	if pista_rot.is_empty():
		push_error("[RT] ninguna pista de rotacion con nombre reconocible")
		quit(1)
		return

	# El reposo de MIXAMO (el punto de comparacion del delta) y el del JUEGO (la
	# pose sobre la que se aplica). Solo se leen los REST: no hace falta que el
	# esqueleto se este reproducciendo.
	var reposo_mixamo: Dictionary = {}
	for i2 in range(esq_f.get_bone_count()):
		var c2 := _limpiar(esq_f.get_bone_name(i2))
		if pista_rot.has(c2) and not reposo_mixamo.has(c2):
			reposo_mixamo[c2] = esq_f.get_bone_rest(i2).basis.get_rotation_quaternion()
	var reposo_juego: Dictionary = {}
	for c3 in reposo_mixamo.keys():
		var dn: String = str(MAPA[c3])
		var i_d: int = esq_d.find_bone(dn)
		if i_d < 0:
			continue
		if not reposo_juego.has(dn):
			reposo_juego[dn] = esq_d.get_bone_rest(i_d).basis.get_rotation_quaternion()
	var destinos: Array[String] = []
	for k3 in reposo_juego.keys():
		destinos.append(str(k3))
	print("[RT] huesos del juego: %d | destinos con destino: %d"
		% [esq_d.get_bone_count(), destinos.size()])

	# --- el horneado: TODOS los cuadros primero, en memoria ---
	var rots: Array = []
	var velocidad: Array[float] = []
	var hips_y: Array[float] = []
	for c4 in range(cuadros):
		var t := float(c4) / float(cuadros) * orig.length
		var deltas: Dictionary = {}
		for c5 in pista_rot.keys():
			if not reposo_mixamo.has(c5):
				continue
			var q: Quaternion = _muestra_rot(orig, int(pista_rot[c5]), t)
			var rm: Quaternion = reposo_mixamo[c5]
			# Spine1 y Spine2 van los dos a Chest: se promedian los DELTAS. Un
			# promedio de Euler daria algo que no es una rotacion, que es el
			# error clasico de este mapa.
			var d := q * rm.inverse()
			var dn2: String = str(MAPA[c5])
			if deltas.has(dn2):
				deltas[dn2] = (deltas[dn2] as Quaternion).slerp(d, 0.5)
			else:
				deltas[dn2] = d
		var cuadro: Dictionary = {}
		for dn3 in destinos:
			if deltas.has(dn3):
				cuadro[dn3] = (reposo_juego[dn3] as Quaternion) * (deltas[dn3] as Quaternion)
			else:
				cuadro[dn3] = reposo_juego[dn3]
		rots.append(cuadro)
		hips_y.append(_muestra_pos(orig, int(pista_pos["Hips"]), t) if pista_pos.has("Hips") else 0.0)
		# La velocidad de las manos dice cuando termina el golpe.
		var v := 0.0
		if c4 > 0:
			var prev: Dictionary = rots[c4 - 1]
			for m in ["Hand.L", "Hand.R"]:
				if cuadro.has(m):
					v += (cuadro[m] as Quaternion).angle_to(prev[m])
		velocidad.append(v)

	# Verificacion de que el horneado sirvio para algo.
	if absf((rots[0]["Hips"] as Quaternion).angle_to(rots[cuadros / 2]["Hips"])) < 0.001:
		push_error("[RT] el horneado no-varying: el FBX no se esta leyendo")
		quit(1)
		return

	# --- el retimeo ---
	#
	# LO QUE ESTA MAL Y COMO SE ARREGLA: el juego pide 0,83 s y el golpe dura 2,03.
	# La primera version recortaba CUADROS hasta llegar a 0,83, y el recorte
	# caia en el cuadro 25 cuando el pico de velocidad estaba en el 27: se
	# perdiaba justo la parte mas rapida del tajo, que es la que se ve.
	#
	# Lo correcto es COMPRIMIR EL TIEMPO, no recortar el movimiento: se toma
	# todo el swing (hasta donde termina la accion) y se remuestrea a los cuadros
	# que entran en el tiempo pedido. El arco del golpe se mantiene completo,
	# solo que mas rapido.
	var dur_final := orig.length
	var n_salida := cuadros
	if _duracion > 0.0:
		# Un LOOP se estira entero: el ciclo entero ES la accion, y hay que
		# hacerlo calzar con la velocidad del codigo. Un GOLPE se recorta en la
		# recuperacion, que el juego mezcla con el idle.
		#
		# LA TRAMPA DE LA CAMINATA: el clip de Mixamo dura 1,167 s y el personaje
		# camina a 100 cm/s, o sea que en un ciclo avanza 117 cm. Pero la zancada
		# que el clip espera es de 155 cm (182 del personaje de Mixamo, al 85%
		# porque nuestro modelo tiene las piernas mas cortas). Con el clip tal
		# cual los pies patinan 38 cm por ciclo. Por eso el clip va a 1,55 s:
		# 155 cm / 100 cm/s.
		var fin_accion: int = cuadros if _loop else _fin_de_accion(velocidad, cuadros)
		var n_fuente := maxi(2, fin_accion)
		n_salida = maxi(2, int(round(_duracion * fps)))
		# SE ESTIRA O SE COMPRIME, y las dos cosas sirven. Comprimir es el
		# ataque (2,03 s a 0,83 s). Estirar es la caminata: repetir el mismo
		# ciclo mas lento para que la zancada coincida con los 100 cm/s del
		# codigo. Una guarda que solo permitia comprimir dejaba la caminata en
		# 1,167 s y los pies patinando 38 cm por ciclo.
		dur_final = _duracion
		print("[RT] retimeo: la accion va del cuadro 0 al %d; se comprime a %d "
			% [n_fuente - 1, n_salida] + "cuadros (%.3f s -> %.3f s, x%.2f)"
			% [orig.length, dur_final, float(n_fuente) / float(n_salida)])
		# El remuestreo: cada cuadro de salida toma su cuadro de origen.
		var remuestreado: Array = []
		var remuestreado_y: Array[float] = []
		for c5 in range(n_salida):
			var origen: float = float(c5) * float(n_fuente - 1) / float(n_salida - 1)
			remuestreado.append(rots[int(round(origen))])
			remuestreado_y.append(hips_y[int(round(origen))])
		rots = remuestreado
		hips_y = remuestreado_y
	if _loop and _blend <= 0.0:
		var p := _mejor_periodo(rots)
		if p < rots.size():
			print("[RT] el ciclo real es de %d cuadros, no de %d; se corta el empalme roto"
				% [p, rots.size()])
			rots = rots.slice(0, p)
			hips_y = hips_y.slice(0, p)
		n_salida = rots.size()
		dur_final = float(n_salida) / fps

	# --- el clip nuevo ---
	var an := Animation.new()
	an.length = dur_final
	an.step = 1.0 / fps
	if _loop:
		an.loop_mode = Animation.LOOP_LINEAR
		_fusionar_loop(rots, n_salida)

	for dn5 in destinos:
		an.add_track(Animation.TYPE_ROTATION_3D)
		an.track_set_path(an.get_track_count() - 1,
			NodePath("%s:%s" % [PREFIJO_ESQ, dn5]))
	# El balanceo vertical, y solo el: la traslacion horizontal es el root motion
	# que se descarta.
	var escala_y := _escala_altura(esq_d, esq_f)
	var media_y := 0.0
	for v2 in hips_y:
		media_y += v2
	media_y /= maxf(1.0, float(hips_y.size()))
	var ih_d: int = esq_d.find_bone("Hips")
	var reposo_hips := esq_d.get_bone_rest(ih_d).origin if ih_d >= 0 else Vector3.ZERO
	var ruta_hips := NodePath("%s:Hips" % PREFIJO_ESQ)
	an.add_track(Animation.TYPE_POSITION_3D)
	an.track_set_path(an.get_track_count() - 1, ruta_hips)
	var idx_hips := an.get_track_count() - 1
	var indice_rot: Dictionary = {}
	for dn6 in destinos:
		indice_rot[dn6] = _indice(an, NodePath("%s:%s" % [PREFIJO_ESQ, dn6]))

	for c6 in range(n_salida):
		var t2 := float(c6) / fps
		var cuadro2: Dictionary = rots[c6]
		for dn7 in destinos:
			an.rotation_track_insert_key(int(indice_rot[dn7]), t2, cuadro2[dn7])
		# Solo Y, y alrededor de la media para no arrastrar al personaje.
		var bob := (hips_y[c6] - media_y) * escala_y if _bob else 0.0
		an.position_track_insert_key(idx_hips, t2, reposo_hips + Vector3(0.0, bob, 0.0))

	print("[RT] %d cuadros x %d huesos | dur %.3f s | bob x%.2f"
		% [n_salida, destinos.size(), dur_final, escala_y])
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_salida.get_base_dir()))
	var err := ResourceSaver.save(an, _salida)
	if err != OK:
		push_error("[RT] no se pudo guardar: %d" % err)
		quit(1)
		return
	print("[RT] guardado %s" % _salida)
	quit(0)


## El empalme del loop.
##
## LO QUE NO FUNCIONA: mezclar los ultimos cuadros hacia el primero (`--blend`).
## El ultimo cuadro cae JUSTO en la fase de apoyo, y aplanarlo ahi corrige el
## salto del loop pero desplaza el pie hacia atras: medido, -0,0382 u en el
## apoyo, que es moonwalk. Son dosChecks que se contradicen y no se ganan los
## dos mezclando.
##
## LO QUE SI: buscar el PERIODO REAL del ciclo y cortar ahi. Una caminata de
## Mixamo no dura lo que dice el archivo: el ciclo de dos pisadas puede cerrar
## en 34 cuadros y no en 35, y el cuadro de sobra es exactamente el empalme
## roto. Se busca el periodo que minimiza el error entre el cuadro k y el k+p, y
## se corta ahi. Sin deformar nada.
func _mejor_periodo(rots: Array) -> int:
	var n := rots.size()
	if n < 6:
		return n
	var mejor := n
	var mejor_err := INF
	for p in range(maxi(3, n / 2), n):
		var err := 0.0
		var cnt := 0
		for k in range(n - p):
			for dn in rots[0].keys():
				err += (rots[k][dn] as Quaternion).angle_to(
					rots[k + p][dn] as Quaternion)
				cnt += 1
		err /= maxf(1.0, float(cnt))
		if err < mejor_err:
			mejor_err = err
			mejor = p
	return mejor


## Mezcla opcional del final hacia el principio. Apagada por defecto: deforma
## la fase de apoyo. Se deja porque para clips SIN ciclo de apoyo (un ataque, una
## muerte) es el mecanismo correcto de cerrar.
func _fusionar_loop(rots: Array, n: int) -> void:
	if not _loop or _blend <= 0.0 or n < 4:
		return
	var k := maxi(2, int(round(float(n) * _blend)))
	for j in range(n - k, n):
		var w := float(j - (n - k)) / float(maxi(k - 1, 1))
		var mezcla: Dictionary = {}
		for dn in rots[0].keys():
			mezcla[dn] = (rots[j][dn] as Quaternion).slerp(rots[0][dn] as Quaternion, w)
		rots[j] = mezcla


func _indice(an: Animation, ruta: NodePath) -> int:
	for i in range(an.get_track_count()):
		if an.track_get_path(i) == ruta:
			return i
	return -1


## La rotacion interpolada en el tiempo `t`. Se lee del recurso, no del
## esqueleto: es lo unico que funciona con un FBX de Mixamo.
func _muestra_rot(a: Animation, idx: int, t: float) -> Quaternion:
	if a.track_get_key_count(idx) <= 0:
		return Quaternion.IDENTITY
	return a.rotation_track_interpolate(idx, t)


func _muestra_pos(a: Animation, idx: int, t: float) -> float:
	if a.track_get_key_count(idx) <= 0:
		return 0.0
	return a.position_track_interpolate(idx, t).y


## Donde termina el golpe: el ultimo pico de velocidad de las manos. Lo que
## viene despues es el character volviendo al idle, que el juego ya mezcla por
## su cuenta, y comprimirlo es lo que hace que el golpe no se sienta lento.
func _fin_de_accion(vel: Array[float], cuadros: int) -> int:
	var pico := 0.0
	for v in vel:
		pico = maxf(pico, v)
	if pico <= 0.0:
		return cuadros
	var ultimo_pico := 0
	for i in range(cuadros):
		if vel[i] >= pico * 0.85:
			ultimo_pico = i
	print("[RT] el pico de velocidad esta en el cuadro %d; el recorte cae despues"
		% ultimo_pico)
	for i in range(ultimo_pico, cuadros):
		if vel[i] < pico * 0.18:
			return maxi(2, i)
	return cuadros


## La razon de tamano entre los dos personajes, para que el balanceo de Mixamo
## sea proporcional en el modelo del juego.
func _escala_altura(esq_d: Skeleton3D, esq_f: Skeleton3D) -> float:
	var ld := 0.0
	var lf := 0.0
	for c in [["Thigh.L", "Shin.L", "Foot.L"], ["Thigh.R", "Shin.R", "Foot.R"]]:
		ld += _largo_cadena(esq_d, c)
	for c2 in [["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot"],
			["mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot"]]:
		lf += _largo_cadena(esq_f, c2)
	if lf <= 0.0:
		return 1.0
	return ld / lf


## EL BUG: la lambda recibia la lista de cadenas en vez de UNA cadena, y
## `find_bone` recibia un Array. Godot tiraba el error pero la funcion seguia y
## devolvia 1.0, o sea el balanceo se iba a perder sin que nadie lo notara.
func _largo_cadena(esq: Skeleton3D, c: Array) -> float:
	var t := 0.0
	for j in range(c.size() - 1):
		var a: int = esq.find_bone(str(c[j]))
		var b: int = esq.find_bone(str(c[j + 1]))
		if a >= 0 and b >= 0:
			t += (esq.get_bone_rest(a).origin - esq.get_bone_rest(b).origin).length()
	return t


func _limpiar(n: String) -> String:
	var s := n
	if s.begins_with("mixamorig:"):
		s = s.substr(11)
	elif s.begins_with("mixamorig_"):
		s = s.substr(10)
	if s.ends_with("_end"):
		s = s.substr(0, s.length() - 4)
	return s


func _primer_esq(n: Node) -> Skeleton3D:
	for d in _descendientes(n):
		if d is Skeleton3D:
			return d
	return null


func _descendientes(n: Node) -> Array:
	var salida: Array = []
	var cola: Array = [n]
	while not cola.is_empty():
		var x: Node = cola.pop_back()
		salida.append(x)
		for c in x.get_children():
			cola.append(c)
	return salida