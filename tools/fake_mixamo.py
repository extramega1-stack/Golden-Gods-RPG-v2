"""Genera un FBX con esqueleto MIXAMO, para probar el conversor sin Mixamo.

POR QUE EXISTE ESTE SCRIPT Y POR QUE NO ES UN TRABAJO REAL: el conversor de
animaciones (`tools/retarget_mixamo.gd`) no se puede probar sin un FBX de Mixamo,
y los de Mixamo requieren cuenta de Adobe. Entonces este script fabrica uno con
Blender, con la misma convención de nombres que Mixamo, y con una animación
CONOCIDA, para que el conversor se pueda verificar de verdad y no de palabra.

LA CONVENCION DE MIXAMO, que es lo que hay que mapear. Notese que no coincide
con la del juego en NADA, y por eso hace falta un mapa:

  mixamorig:Hips         -> Hips
  mixamorig:Spine        -> Spine
  mixamorig:Spine1       -> Chest
  mixamorig:Spine2       -> Chest        (el juego no tiene dos dorsales)
  mixamorig:Neck         -> Neck
  mixamorig:Head         -> Head
  mixamorig:LeftShoulder -> Shoulder.L
  mixamorig:LeftArm      -> UpperArm.L
  mixamorig:LeftForeArm  -> LowerArm.L
  mixamorig:LeftHand     -> Hand.L
  mixamorig:RightArm     -> UpperArm.R
  mixamorig:RightForeArm -> LowerArm.R
  mixamorig:RightHand    -> Hand.R
  mixamorig:LeftUpLeg    -> Thigh.L
  mixamorig:LeftLeg      -> Shin.L
  mixamorig:LeftFoot     -> Foot.L
  mixamorig:RightUpLeg   -> Thigh.R
  mixamorig:RightLeg     -> Shin.R
  mixamorig:RightFoot    -> Foot.R

DIFERENCIA CRITICA: el juego tiene 49 huesos y Mixamo tiene 15 sin contar los
dedos, mas 15 por mano si se piden con las manos. Los 30 huesos de dedo del
juego NO tienen equivalente en Mixamo. Esos se copian del REST del juego, o sea
que los dedos quedan en la pose que los deje el ultimo clip escrito. Es una
limitacion real del retarget por nombres, no un bug: la solucion seria retarget por metodo y constraints, y Mixamo no las trae.

LA ANIMACION: un ciclo de marcha de 32 cuadros a 30 fps, con las caderas
girando y los brazos en contrafase. Es simple a proposito: si el conversor
devuelve algo raro, el problema es del conversor y no de una animacion compleja
que no sabemos de donde salio.

Uso:
  blender --background --python tools/fake_mixamo.py -- /tmp/prueba.fbx
"""
import bpy
import math
import sys
from mathutils import Vector

VECES = 32
FPS = 30

# (nombre de Mixamo, posicion, hueso padre)
HUESOS = [
	("Hips", (0.0, 0.98, 0.0), None),
	("Spine", (0.0, 1.10, 0.0), "Hips"),
	("Spine1", (0.0, 1.24, 0.0), "Spine"),
	("Spine2", (0.0, 1.38, 0.0), "Spine1"),
	("Neck", (0.0, 1.48, 0.0), "Spine2"),
	("Head", (0.0, 1.58, 0.0), "Neck"),
	("LeftShoulder", (0.05, 1.44, 0.0), "Spine2"),
	("LeftArm", (0.18, 1.44, 0.0), "LeftShoulder"),
	("LeftForeArm", (0.18, 1.16, 0.0), "LeftArm"),
	("LeftHand", (0.18, 0.94, 0.0), "LeftForeArm"),
	("RightShoulder", (-0.05, 1.44, 0.0), "Spine2"),
	("RightArm", (-0.18, 1.44, 0.0), "RightShoulder"),
	("RightForeArm", (-0.18, 1.16, 0.0), "RightArm"),
	("RightHand", (-0.18, 0.94, 0.0), "RightForeArm"),
	("LeftUpLeg", (0.09, 0.92, 0.0), "Hips"),
	("LeftLeg", (0.09, 0.50, 0.0), "LeftUpLeg"),
	("LeftFoot", (0.09, 0.08, 0.0), "LeftLeg"),
	("RightUpLeg", (-0.09, 0.92, 0.0), "Hips"),
	("RightLeg", (-0.09, 0.50, 0.0), "RightUpLeg"),
	("RightFoot", (-0.09, 0.08, 0.0), "RightLeg"),
]


## Las curvas de una accion, con las dos APIs. La vieja (`fcurves` directo) es
## de Blender 4.3 y anteriores; la nueva son las acciones con ranuras de 4.4 en
## adelante. Se prueban las dos y se devuelve la primera que funcione.
def _curvas(accion):
	viejo = getattr(accion, "fcurves", None)
	if viejo is not None:
		return list(viejo)
	salida = []
	for capa in getattr(accion, "layers", []):
		for tira in getattr(capa, "strips", []):
			bolsa = getattr(tira, "channelbag", None)
			if bolsa is None:
				continue
			for ranura in getattr(accion, "slots", []):
				try:
					cb = bolsa(ranura)
				except TypeError:
					cb = bolsa(ranura, ensure=False)
				if cb is not None:
					salida.extend(cb.fcurves)
	return salida


def main() -> int:
	args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	salida = args[0] if args else "/tmp/fake_mixamo.fbx"

	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o, do_unlink=True)

	rig = bpy.data.armatures.new("mixamorig")
	obj = bpy.data.objects.new("mixamorig", rig)
	bpy.context.scene.collection.objects.link(obj)
	bpy.context.view_layer.objects.active = obj
	obj.select_set(True)
	bpy.ops.object.mode_set(mode="EDIT")

	eb = obj.data.edit_bones
	por_nombre = {}
	for nombre, cabeza, padre in HUESOS:
		b = eb.new("mixamorig:" + nombre)
		b.head = Vector(cabeza)
		# La cola define el eje del hueso: va HACIA ABAJO, que es la convencion
		# de Mixamo y la que el conversor asume.
		b.tail = Vector((cabeza[0], cabeza[1] - 0.10, cabeza[2]))
		if padre is not None:
			b.parent = por_nombre[padre]
		por_nombre[nombre] = b

	bpy.ops.object.mode_set(mode="OBJECT")

	# LA MALLA, Y POR QUE ESTA SIENDO QUE NO HACE FALTA.
	#
	# El conversor no la usa: al retargetear solo se leen poses de huesos. Lo que
	# pasa es que el IMPORTADOR DE FBX DE GODOT rechaza un FBX sin geometria: con
	# el esqueleto solo, el archivo tenia 254 AnimationCurve y Godot lo importaba
	# igual como `valid=false`. El sintoma era "el conversor no encuentra el
	# clip", y la causa era que el importador nunca lo cargo.
	#
	# Es una caja de 40 cm pegada al esqueleto, y ya esta.
	bpy.ops.mesh.primitive_cube_add(size=0.4, location=(0.0, 1.1, 0.0))
	cubo = bpy.context.active_object
	cubo.name = "mixamorig:mesh"

	# --- la animacion: ciclo de marcha ---
	# Los POSE BONES, que es donde vive la rotacion. `EditBone` no la tiene.
	pb = {}
	for nombre, _c, _p in HUESOS:
		b = obj.pose.bones["mixamorig:" + nombre]
		b.rotation_mode = "XYZ"
		pb[nombre] = b

	obj.animation_data_create()
	accion = bpy.data.actions.new("Walking")
	obj.animation_data.action = accion
	hips = pb["Hips"]
	hips.rotation_mode = "XYZ"
	for f in range(VECES):
		t = f / float(VECES) * math.tau
		# Las caderas rotan en Y (guiñada) y en Z (balanceo): los dos ejes que
		# hacen que una marcha se lea como marcha.
		hips.rotation_euler = (0.0, math.sin(t) * 0.09, math.sin(t) * 0.05)
		hips.keyframe_insert("rotation_euler", frame=f + 1)
		hips.location = (0.0, 0.0, abs(math.sin(t)) * 0.025)
		hips.keyframe_insert("location", frame=f + 1)

		for lado, signo in (("Left", 1.0), ("Right", -1.0)):
			# En contrafase: el brazo izquierdo va adelante cuando el derecho va
			# atras. El signo es el que decide, y esta es la parte que mas se
			# invierte sin querer.
			brazo = pb[lado + "Arm"]
			brazo.rotation_euler = (math.sin(t) * 0.42 * signo, 0.0, 0.0)
			brazo.keyframe_insert("rotation_euler", frame=f + 1)

			pierna = pb[lado + "UpLeg"]
			pierna.rotation_euler = (math.sin(t + math.pi) * 0.38 * signo, 0.0, 0.0)
			pierna.keyframe_insert("rotation_euler", frame=f + 1)

			rodilla = pb[lado + "Leg"]
			# La rodilla solo dobla, y hacia atras: el signo negativo es lo que
			# hace que sea una rodilla y no un codo.
			rodilla.rotation_euler = (max(0.0, -math.sin(t + math.pi)) * 0.55 * signo,
				0.0, 0.0)
			rodilla.keyframe_insert("rotation_euler", frame=f + 1)

	# LA INTERPOLACION, Y UN CAMBIO DE API QUE SE COME UNA TAREA.
	#
	# En Blender 4.4 y posteriores las acciones tienen RANURAS: `Action.fcurves`
	# ya no existe y las curvas se leen por
	# `action.layers[0].strips[0].channelbag(slot).fcurves`. En 5.2, que es la
	# que hay instalada, `accion.fcurves` tira AttributeError.
	#
	# Pero esto es un refinamiento, no una necesidad: el default de Blender ya
	# es BEZIER con Auto Clamped, que es exactamente lo que se pedia. O sea que
	# la version vieja de estas lineas no estaba haciendo nada. Se dejan como
	# refinamiento opcional y se anota por que.
	for fc in _curvas(accion):
		for kp in fc.keyframe_points:
			kp.interpolation = "BEZIER"
			kp.handle_left_type = "AUTO_CLAMPED"
			kp.handle_right_type = "AUTO_CLAMPED"

	# DIAGNOSTICO, porque el exportador se comio la animacion en silencio dos
	# veces. Se imprime que hay antes de exportar: sin esto, el unico sintoma es
	# "el FBX no tiene curvas" y no se sabe si fallo el keyframe o el exportador.
	curvas = _curvas(accion)
	print("[FAKE] accion: " + str(accion.name) + " | curvas: " + str(len(curvas)))
	for c in curvas[:3]:
		print("[FAKE]   pista " + str(c.data_path) + " con " + str(len(c.keyframe_points)) + " claves")
	if not curvas:
		print("[FAKE] AVISO: la accion no tiene curvas, el FBX saldra sin animacion")
	print("[FAKE] pose bones: " + str(len(obj.pose.bones)))
	print("[FAKE] animation_data: %s" % str(obj.animation_data))
	if obj.animation_data:
		print("[FAKE] action asignada: %s" % str(obj.animation_data.action))

	# El range del clip: 32 cuadros a 30 fps son 1,066 s. Un ciclo de marcha
	# humano son 0,9-1,1 s, asi que el numero es realista.
	accion.frame_start = 1
	accion.frame_end = VECES
	accion.use_fake_user = True

	# EL EXPORTADOR DE FBX, no `save_as_mainfile`. Este ultimo guarda un `.blend`
	# PONIENDOLE la extension que se le pida: el archivo resultante se llamaba
	# `.fbx` y no contenia NI UN TAG de FBX (0 Model, 0 Deformer, 0 Pose), y
	# Godot lo importaba como `valid=false`. El sintoma era "el conversor esta
	# roto" y la causa era que el archivo de prueba no era un FBX.
	#
	# `bake_anim` tiene que ir en True. Con False el exportador respeta el action
	# slot de Blender 4.4+, y con este esqueleto de prueba se lo come entero: el
	# FBX salia con 43 Model y CERO AnimationCurve, sin avisar. Con True hornea
	# las poses cuadro a cuadro y las escribe siempre.
	#
	# El precio del horneado es que las curvas quedan en un cuadro cada una en vez
	# de las 32 claves con interpolacion: para una animacion de prueba da igual.
	# El armature TIENE que estar seleccionado y declarado en `object_types`, o el
	# exportador se lo salta: el FBX salia con 43 Model pero CERO
	# AnimationCurve, o sea un esqueleto sin animacion. Y el sintoma era
	# "el conversor no encuentra el clip", no "el exportador fallo".
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	cubo.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.export_scene.fbx(
		filepath=salida,
		use_selection=True,
		object_types={"ARMATURE", "MESH"},
		apply_scale_options="FBX_SCALE_NONE",
		bake_anim=True,
		add_leaf_bones=False,
		primary_bone_axis="Y",
		secondary_bone_axis="X",
		path_mode="COPY",
	)
	print("[FAKE] esqueleto mixamorig con %d huesos" % len(HUESOS))
	print("[FAKE] animacion 'Walking': %d cuadros a %d fps" % (VECES, FPS))
	print("[FAKE] guardado en %s" % salida)
	return 0


if __name__ == "__main__":
	sys.exit(main())
