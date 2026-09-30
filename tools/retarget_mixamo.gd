extends SceneTree
## Convierte animaciones de Mixamo (FBX) a clips del juego.
##
## POR QUE NO ALCANZA CON IMPORTAR EL FBX: Godot lo importa con la convencion de
## nombres de Mixamo, y el juego usa otra. Ademas el juego tiene 49 huesos, 30
## de ellos de dedos, y Mixamo no trae dedos. O sea que hay que MAPEAR.
##
## POR QUE HAY UN GENERADOR DE UN FBX FALSO AL LADO, y no es un joke:
## `tools/fake_mixamo.py` fabrica un FBX con la convencion de Mixamo y una
## animacion CONOCIDA. Sin el no se puede probar NADA, porque los FBX de Mixamo
## requieren cuenta de Adobe y no hay API anonima. Con el, si el conversor
## devuelve algo raro, el problema es del conversor y no de una animacion
## desconocida.
##
## USO:
##   godot --headless --path . --import
##   godot --headless --path . --script res://tools/retarget_mixamo.gd -- \
##       --fbx=res://anim/fuente/mixamo_prueba.fbx --clip=Walking \
##       --salida=res://anim/walk_prueba.tres

## El mapa, que es el corazon de la herramienta.
##
## Spine1 y Spine2 van los dos a `Chest`, que es lo que el juego tiene. Se
## PROMEDIAN: si solo se copiara uno, el pecho recibiria la mitad del movimiento
## y el torso se veria rigido. Esa mezcla es la parte del mapa que mas se nota.
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

var _ruta_fbx: String = ""
var _clip: String = ""
var _salida: String = ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fbx="):
			_ruta_fbx = a.get_slice("=", 1)
		elif a.begins_with("--clip="):
			_clip = a.get_slice("=", 1)
		elif a.begins_with("--salida="):
			_salida = a.get_slice("=", 1)
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

	# --- el mapa, resolving los indices UNA vez y no por cuadro ---
	#
	# EL BUG QUE COSTO UN RATO, y es de los que no se ven mirando el codigo: se
	# iteraba sobre las CLAVES del mapa, que ya estan limpias ("Hips"), y se
	# buscaba `esq_f.find_bone("Hips")`. Pero el hueso del esqueleto se llama
	# `mixamorig_Hips`. O sea que se buscaba un nombre que no existe, y el
	# resultado era "0 huesos mapeados" sin que nada fallara.
	#
	# La vuelta es al reves: se iteran los HUESOS del esqueleto, se les quita el
	# prefijo, y eso se busca en el mapa. Que es ademas lo que hace que el
	# reporte de "sin destino" sea real.
	var pares: Array = []
	for i in range(esq_f.get_bone_count()):
		var limpio := _limpiar(esq_f.get_bone_name(i))
		if not MAPA.has(limpio):
			continue
		var destino_nombre: String = str(MAPA[limpio])
		var i_d: int = esq_d.find_bone(destino_nombre)
		if i_d < 0:
			print("[RT]   el juego no tiene '" + destino_nombre + "'")
			continue
		pares.append({"f": i, "d": i_d, "n": limpio, "destino": destino_nombre})
	var sin_mapear: int = esq_f.get_bone_count() - pares.size()
	print("[RT] huesos del juego: %d | mapeados: %d | de Mixamo sin destino: %d" % [
		esq_d.get_bone_count(), pares.size(), sin_mapear])
	for i in range(esq_f.get_bone_count()):
		var nm := _limpiar(esq_f.get_bone_name(i))
		if not MAPA.has(nm):
			print("[RT]   sin destino: " + nm + " (se queda en el REST)")

	# --- el clip ---
	var lista: PackedStringArray = ap.get_animation_list()
	if _clip == "" and lista.size() > 0:
		_clip = lista[0]
	if not lista.has(_clip):
		push_error("[RT] no existe '%s'. Hay: %s" % [_clip, str(lista)])
		quit(1)
		return
	var orig: Animation = ap.get_animation(_clip)
	# Los fps NO salen del Animation: en Godot 4 el recurso guarda la duracion y
	# los fps vienen del AnimationPlayer. 30 es el de Mixamo y el del proyecto.
	var fps: float = 30.0
	var cuadros: int = maxi(2, int(round(orig.length * fps)))
	print("[RT] clip '%s': %.3f s a %.1f fps = %d cuadros" % [
		_clip, orig.length, fps, cuadros])

	# --- el clip nuevo: una pista de rotacion y una de posicion por hueso ---
	var an := Animation.new()
	an.length = orig.length
	an.step = 1.0 / fps
	an.loop_mode = Animation.LOOP_LINEAR if orig.loop_mode != Animation.LOOP_NONE \
		else Animation.LOOP_NONE
	# Se animan SOLO los huesos mapeados. Los otros 30 (los de los dedos) se
	# quedan en el REST, y eso es una limitacion real: Mixamo no trae dedos.
	var rutas: Array[String] = []
	for p in pares:
		var r: String = "%s:%s" % [str(p["destino"]), "rotacion"]
		an.add_track(Animation.TYPE_ROTATION_3D)
		an.track_set_path(an.get_track_count() - 1, NodePath(r))
		rutas.append(r)
		an.add_track(Animation.TYPE_POSITION_3D)
		an.track_set_path(an.get_track_count() - 1, NodePath("%s:posicion" % p["destino"]))

	# --- el horneado, cuadro a cuadro ---
	# EL RETARGET REAL: se copia la rotacion LOCAL del hueso de Mixamo. Local y
	# no global, porque un hueso se mueve por la rotacion que tiene respecto de
	# SU padre, y las dos jerarquias son analogas. Copiar la global daria un
	# resultado que depende de donde este el personaje en el mundo.
	#
	# Y se escribe sobre los indices ya resueltos, no buscandolos: la version
	# anterior buscaba el hueso de origen comparando poses Transform3D, que es
	# O(n) por cuadro y fragil.
	for c in range(cuadros):
		ap.seek(c / float(cuadros) * orig.length, true)
		ap.advance(0.0)
		var mezclado: Dictionary = {}
		for p in pares:
			var g: Transform3D = esq_f.get_bone_global_pose(p["f"])
			var padre: int = esq_f.get_bone_parent(p["f"])
			var g_padre: Transform3D = esq_f.get_bone_global_pose(padre) \
				if padre >= 0 else Transform3D.IDENTITY
			var local: Transform3D = g_padre.affine_inverse() * g
			var q: Quaternion = local.basis.get_rotation_quaternion()
			# La mezcla de Spine1 y Spine2: se promedian los cuaterniones. Un
			# promedio de Euler daria un resultado que no es una rotacion, que
			# es el error clasico de este mapa.
			if mezclado.has(p["destino"]):
				mezclado[p["destino"]] = (mezclado[p["destino"]] as Quaternion).slerp(q, 0.5)
			else:
				mezclado[p["destino"]] = q
		# Se escribe despues del bucle para que la mezcla este completa.
		for p2 in pares:
			var nom: String = p2["destino"]
			var q2: Quaternion = mezclado[nom]
			an.rotation_track_insert_key(_ruta(an, "%s:rotacion" % nom), c, q2)
			an.position_track_insert_key(_ruta(an, "%s:posicion" % nom), c, Vector3.ZERO)

	print("[RT] horneados %d cuadros x %d huesos" % [cuadros, pares.size()])
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_salida.get_base_dir()))
	var err := ResourceSaver.save(an, _salida)
	if err != OK:
		push_error("[RT] no se pudo guardar: %d" % err)
		quit(1)
		return
	print("[RT] guardado %s" % _salida)
	quit(0)


## El indice de la pista con esa ruta. Se busca por ruta y NO por posicion, que
## es lo unico estable cuando se tienen muchas pistas.
func _ruta(an: Animation, ruta: String) -> int:
	for i in range(an.get_track_count()):
		if str(an.track_get_path(i)) == ruta:
			return i
	return -1


func _limpiar(n: String) -> String:
	var s := n
	if s.begins_with("mixamorig:"):
		s = s.substr(11)
	elif s.begins_with("mixamorig_"):
		s = s.substr(10)
	s = s.replace("_L", "").replace("_R", "")
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
