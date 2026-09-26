"""Esqueleto y animaciones procedurales para un humanoid sin esqueleto.

Lo usan los `.glb` del pack de Meshy: llegan con una sola malla, un nodo y ni
un hueso, así que no se mueven. Este módulo les pone un esqueleto humanoide y
los cuatro clips que la FSM del juego ya nombra (`data/anclajes.json`):
`idle`, `walk`, `attack`, `die`.

Se llama desde `tools/preparar_modelo.py` con el cuarto argumento en 1:

    blender --background --python tools/preparar_modelo.py -- in.glb out.glb 20000 1

Nombres de hueso: coinciden con los 7 anclajes de `data/anclajes.json`
(`Chest`, `Neck`, `Head`, `Hand.L`, `Hand.R`, `Foot.L`, `Foot.R`), así que un
modelo rigged sirve tal cual para el paper-doll de equipo.

Todo es procedural y determinista: los mismos clips en cada corrida, sin
keyframes escritos a mano ni Mixamo.
"""

import math

import bpy
from mathutils import Vector

# Proporciones en metros sobre un humano de 1,90 m (Z arriba, el suelo en 0,
# mirando a -Y que es "adelante" en Blender). Se ajustan a la altura real del
# modelo con `escalar()`.
PROP = {
    "pie_z": 0.04, "toe_y": -0.26, "toe_z": 0.03,
    "ankle_z": 0.10, "knee_z": 0.53, "hip_z": 0.95, "hip_x": 0.10,
    "waist_z": 1.10, "chest_z": 1.30, "neck_z": 1.50,
    "head_z": 1.62, "top_z": 1.90,
    "shoulder_z": 1.45, "shoulder_x": 0.17, "shoulder_in_x": 0.05,
    "elbow_z": 1.12, "elbow_x": 0.30,
    "wrist_z": 0.92, "wrist_x": 0.33, "hand_z": 0.85,
    "foot_x": 0.11, "toe_x": 0.11,
}


def _huesos(p: dict) -> list:
    """Cadena de huesos (nombre, cabeza, cola, padre) en metros."""
    L, R = "L", "R"
    return [
        ("Hips", (0, 0, p["hip_z"]), (0, 0, p["waist_z"]), None),
        ("Spine", (0, 0, p["waist_z"]), (0, 0, p["chest_z"]), "Hips"),
        ("Chest", (0, 0, p["chest_z"]), (0, 0, p["neck_z"]), "Spine"),
        ("Neck", (0, 0, p["neck_z"]), (0, 0, p["head_z"]), "Chest"),
        ("Head", (0, 0, p["head_z"]), (0, 0, p["top_z"]), "Neck"),
    ] + [
        # Brazo: hombro sale del pecho, luego brazo, antebrazo y mano.
        ("Shoulder." + L, (p["shoulder_in_x"], 0, p["shoulder_z"]), (p["shoulder_x"], 0, p["shoulder_z"]), "Chest"),
        ("UpperArm." + L, (p["shoulder_x"], 0, p["shoulder_z"]), (p["elbow_x"], 0, p["elbow_z"]), "Shoulder." + L),
        ("LowerArm." + L, (p["elbow_x"], 0, p["elbow_z"]), (p["wrist_x"], 0, p["wrist_z"]), "UpperArm." + L),
        ("Hand." + L, (p["wrist_x"], 0, p["wrist_z"]), (p["wrist_x"], -0.06, p["hand_z"]), "LowerArm." + L),
        ("Shoulder." + R, (-p["shoulder_in_x"], 0, p["shoulder_z"]), (-p["shoulder_x"], 0, p["shoulder_z"]), "Chest"),
        ("UpperArm." + R, (-p["shoulder_x"], 0, p["shoulder_z"]), (-p["elbow_x"], 0, p["elbow_z"]), "Shoulder." + R),
        ("LowerArm." + R, (-p["elbow_x"], 0, p["elbow_z"]), (-p["wrist_x"], 0, p["wrist_z"]), "UpperArm." + R),
        ("Hand." + R, (-p["wrist_x"], 0, p["wrist_z"]), (-p["wrist_x"], -0.06, p["hand_z"]), "LowerArm." + R),
        # Pierna: muslo, tibia, pie y punta (para el apoyo al caminar).
        ("Thigh." + L, (p["hip_x"], 0, p["hip_z"]), (p["foot_x"], 0, p["knee_z"]), "Hips"),
        ("Shin." + L, (p["foot_x"], 0, p["knee_z"]), (p["foot_x"], 0, p["ankle_z"]), "Thigh." + L),
        ("Foot." + L, (p["foot_x"], 0, p["ankle_z"]), (p["toe_x"], p["toe_y"], p["toe_z"]), "Shin." + L),
        ("Thigh." + R, (-p["hip_x"], 0, p["hip_z"]), (-p["foot_x"], 0, p["knee_z"]), "Hips"),
        ("Shin." + R, (-p["foot_x"], 0, p["knee_z"]), (-p["foot_x"], 0, p["ankle_z"]), "Thigh." + R),
        ("Foot." + R, (-p["foot_x"], 0, p["ankle_z"]), (-p["toe_x"], p["toe_y"], p["toe_z"]), "Shin." + R),
    ]


# Radio de la envolvente de cada hueso, en metros. Cubre el cuerpo entero sin
# que las puntas de los dedos se ganen el muslo.
ENVOLVENTE = {
    "Hips": 0.55, "Spine": 0.45, "Chest": 0.50, "Neck": 0.20, "Head": 0.28,
    "Shoulder": 0.24, "UpperArm": 0.30, "LowerArm": 0.26, "Hand": 0.18,
    "Thigh": 0.42, "Shin": 0.36, "Foot": 0.24,
}


def _crear_esqueleto(nombre: str, p: dict) -> object:
    datos = bpy.data.armatures.new(nombre)
    obj = bpy.data.objects.new(nombre, datos)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for nombre_h, cabeza, cola, padre in _huesos(p):
        eb = datos.edit_bones.new(nombre_h)
        eb.head = cabeza
        eb.tail = cola
        eb.envelope_distance = ENVOLVENTE.get(nombre_h.split(".")[0], 0.30)
        if padre is not None:
            eb.parent = datos.edit_bones[padre]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def _nueva_accion(arm: object, nombre: str) -> object:
    """Acción nueva asignada al esqueleto.

    Blender 4.4+ usa acciones por capas con "slots": si no se crea el slot a
    mano, `keyframe_insert` escribe en el aire y el clip sale vacío al
    exportar. Por eso se hace aquí y no en el keyframing.
    """
    acc = bpy.data.actions.new(nombre)
    arm.animation_data_create()
    arm.animation_data.action = acc
    if hasattr(acc, "slots"):
        try:
            slot = acc.slots.new(id_type="OBJECT", name="Object")
            arm.animation_data.action_slot = slot
        except (RuntimeError, TypeError) as exc:
            print("[RIG] aviso: sin slot para '%s' (%s)" % (nombre, exc))
    return acc


def _clave(arm: object, hueso: str, frame: int, rot=(0.0, 0.0, 0.0), loc=None) -> None:
    pb = arm.pose.bones[hueso]
    pb.rotation_mode = "XYZ"
    pb.rotation_euler = (rot[0], rot[1], rot[2])
    pb.keyframe_insert(data_path="rotation_euler", frame=frame)
    if loc is not None:
        pb.location = loc
        pb.keyframe_insert(data_path="location", frame=frame)


def _clave_lista(arm: object, huesos: dict, frame: int) -> None:
    """`huesos` = {nombre: (rx, ry, rz)}; `None` = hueso quieto."""
    for nombre, rot in huesos.items():
        if rot is None:
            continue
        _clave(arm, nombre, frame, rot)


def _idle(arm: object, fps: int) -> None:
    """Respiración en 2 s, en bucle: el frame final repite el primero."""
    _nueva_accion(arm, "idle")
    pasos = 8
    for i in range(pasos + 1):
        f = 1 + int(i * (2.0 * fps) / pasos)
        t = i / pasos
        # Un ciclo de respiración y un leve balanceo, ambos senoidales.
        resp = math.sin(t * math.tau)
        sway = math.sin(t * math.tau + 0.9)
        _clave_lista(arm, {
            "Hips": (0.0, sway * 0.02, 0.0),
            "Spine": (resp * 0.015, 0.0, 0.0),
            "Chest": (resp * 0.03, sway * 0.03, 0.0),
            "Neck": (-resp * 0.02, 0.0, 0.0),
            "Head": (-resp * 0.03, -sway * 0.05, 0.0),
            "UpperArm.L": (0.0, 0.0, 0.10 + resp * 0.02),
            "UpperArm.R": (0.0, 0.0, -0.10 - resp * 0.02),
            "LowerArm.L": (0.0, 0.0, -0.18),
            "LowerArm.R": (0.0, 0.0, 0.18),
        }, f)
        # Ojo: en espacio de hueso el eje vertical es el Y (el hueso apunta
        # hacia arriba, y su Y local es su propio largo). Con z esto salia
        # horizontal y la cadera no bajaba nunca.
        _clave(arm, "Hips", f, loc=(0.0, sway * 0.006, 0.0))


def _walk(arm: object, fps: int) -> None:
    """Ciclo de marcha de 1 s, en bucle: piernas y brazos alternos."""
    _nueva_accion(arm, "walk")
    pasos = 8
    for i in range(pasos + 1):
        f = 1 + int(i * fps / pasos)
        t = i / pasos
        a = math.sin(t * math.tau)          # avance de la pierna
        b = math.sin(t * math.tau + math.pi)  # la contraria
        # La rodilla solo dobla hacia atras: sin hiperextension.
        rodilla_l = max(0.0, -math.sin(t * math.tau - 0.7)) * 0.9
        rodilla_r = max(0.0, -math.sin(t * math.tau + math.pi - 0.7)) * 0.9
        _clave_lista(arm, {
            "Hips": (0.0, math.sin(t * math.tau) * 0.10, 0.0),
            "Spine": (0.03, 0.0, 0.0),
            "Chest": (0.0, -math.sin(t * math.tau) * 0.08, 0.0),
            "Head": (0.0, 0.0, 0.0),
            "Thigh.L": (a * 0.55, 0.0, 0.0),
            "Shin.L": (rodilla_l, 0.0, 0.0),
            "Foot.L": (-a * 0.25 - rodilla_l * 0.4, 0.0, 0.0),
            "Thigh.R": (b * 0.55, 0.0, 0.0),
            "Shin.R": (rodilla_r, 0.0, 0.0),
            "Foot.R": (-b * 0.25 - rodilla_r * 0.4, 0.0, 0.0),
            "UpperArm.L": (b * 0.42, 0.0, 0.10),
            "LowerArm.L": (-0.25, 0.0, 0.0),
            "UpperArm.R": (a * 0.42, 0.0, -0.10),
            "LowerArm.R": (-0.25, 0.0, 0.0),
        }, f)
        # Doble rebote vertical: dos pisadas por ciclo.
        _clave(arm, "Hips", f, loc=(0.0, abs(math.sin(t * math.tau)) * 0.028 - 0.014, 0.0))


def _attack(arm: object, fps: int) -> None:
    """Golpe con el brazo derecho: carga, tajo y vuelta. No cicla."""
    _nueva_accion(arm, "attack")
    total = 0.8
    fases = [
        # (segundo, rotaciones) — carga, tajo, recuperación.
        (0.00, {"Chest": (0.0, -0.45, 0.0), "Spine": (0.0, -0.20, 0.0),
                "UpperArm.R": (-0.70, 0.0, -0.45), "LowerArm.R": (-1.10, 0.0, 0.0),
                "Hips": (0.0, -0.18, 0.0)}),
        (0.22, {"Chest": (0.0, -0.55, 0.0), "Spine": (0.0, -0.28, 0.0),
                "UpperArm.R": (-1.10, 0.0, -0.55), "LowerArm.R": (-1.35, 0.0, 0.0),
                "Hips": (0.0, -0.24, 0.0)}),
        (0.34, {"Chest": (0.12, 0.50, 0.0), "Spine": (0.10, 0.30, 0.0),
                "UpperArm.R": (0.85, 0.0, 0.20), "LowerArm.R": (-0.15, 0.0, 0.0),
                "Hips": (0.0, 0.35, 0.0)}),
        (0.46, {"Chest": (0.05, 0.35, 0.0), "Spine": (0.05, 0.20, 0.0),
                "UpperArm.R": (0.55, 0.0, 0.05), "LowerArm.R": (-0.30, 0.0, 0.0),
                "Hips": (0.0, 0.22, 0.0)}),
        (total, {"Chest": (0.0, 0.0, 0.0), "Spine": (0.02, 0.0, 0.0),
                 "UpperArm.R": (0.0, 0.0, -0.10), "LowerArm.R": (-0.18, 0.0, 0.0),
                 "Hips": (0.0, 0.0, 0.0)}),
    ]
    for seg, rot in fases:
        _clave_lista(arm, rot, 1 + int(seg * fps))


def _die(arm: object, fps: int) -> None:
    """Se desploma: rodillas que ceden y torso al suelo. No cicla."""
    _nueva_accion(arm, "die")
    total = 1.2
    fases = [
        (0.00, {"Thigh.L": (0.35, 0.0, 0.0), "Thigh.R": (0.35, 0.0, 0.0),
                "Shin.L": (0.70, 0.0, 0.0), "Shin.R": (0.70, 0.0, 0.0),
                "Spine": (0.10, 0.0, 0.0), "Chest": (0.08, 0.0, 0.0),
                "Head": (0.10, 0.0, 0.0)}),
        (0.30, {"Thigh.L": (0.90, 0.0, 0.0), "Thigh.R": (0.90, 0.0, 0.0),
                "Shin.L": (1.45, 0.0, 0.0), "Shin.R": (1.45, 0.0, 0.0),
                "Foot.L": (0.35, 0.0, 0.0), "Foot.R": (0.35, 0.0, 0.0),
                "Spine": (0.35, 0.0, 0.0), "Chest": (0.30, 0.0, 0.0),
                "Head": (0.25, 0.0, 0.0),
                "UpperArm.L": (0.55, 0.0, 0.45), "UpperArm.R": (0.55, 0.0, -0.45),
                "LowerArm.L": (-0.40, 0.0, 0.0), "LowerArm.R": (-0.40, 0.0, 0.0)}),
        (0.75, {"Thigh.L": (1.15, 0.0, 0.0), "Thigh.R": (1.15, 0.0, 0.0),
                "Shin.L": (1.55, 0.0, 0.0), "Shin.R": (1.55, 0.0, 0.0),
                "Foot.L": (0.55, 0.0, 0.0), "Foot.R": (0.55, 0.0, 0.0),
                "Hips": (0.55, 0.0, 0.0), "Spine": (0.45, 0.0, 0.0),
                "Chest": (0.35, 0.0, 0.0), "Head": (0.30, 0.0, 0.0),
                "UpperArm.L": (0.95, 0.0, 0.60), "UpperArm.R": (0.95, 0.0, -0.60),
                "LowerArm.L": (-0.25, 0.0, 0.0), "LowerArm.R": (-0.25, 0.0, 0.0)}),
        (total, {"Thigh.L": (1.25, 0.0, 0.0), "Thigh.R": (1.25, 0.0, 0.0),
                 "Shin.L": (1.60, 0.0, 0.0), "Shin.R": (1.60, 0.0, 0.0),
                 "Foot.L": (0.60, 0.0, 0.0), "Foot.R": (0.60, 0.0, 0.0),
                 "Hips": (0.60, 0.0, 0.0), "Spine": (0.50, 0.0, 0.0),
                 "Chest": (0.40, 0.0, 0.0), "Head": (0.35, 0.0, 0.0),
                 "UpperArm.L": (1.00, 0.0, 0.65), "UpperArm.R": (1.00, 0.0, -0.65),
                 "LowerArm.L": (-0.20, 0.0, 0.0), "LowerArm.R": (-0.20, 0.0, 0.0)}),
    ]
    for seg, rot in fases:
        _clave_lista(arm, rot, 1 + int(seg * fps))
    # Al desplomarse el cuerpo baja: la cadera va al suelo (Y local = abajo,
    # ver la nota del idle). Sin esto el cadaver se queda flotando a media
    # altura con las rodillas dobladas.
    for seg, baja in ((0.0, 0.0), (0.3, -0.20), (0.75, -0.62), (total, -0.70)):
        _clave(arm, "Hips", 1 + int(seg * fps), loc=(0.0, baja, 0.0))


CLIPS = (("idle", _idle), ("walk", _walk), ("attack", _attack), ("die", _die))


def enrutar(malla: object) -> object:
    """Le pone esqueleto, pesos y los cuatro clips a `malla`. Devuelve el rig."""
    prop = dict(PROP)
    # Las proporciones estan calibradas para 1,90 m: si el modelo mide otra
    # cosa, se escala el esqueleto con el (el pack va de 0,9 a 3,8 m).
    alto = max((malla.matrix_world @ Vector(c)).z for c in malla.bound_box) \
        - min((malla.matrix_world @ Vector(c)).z for c in malla.bound_box)
    if alto > 0.01:
        k = alto / PROP["top_z"]
        for key in list(prop):
            prop[key] = prop[key] * k
    rig = _crear_esqueleto("Rig", prop)
    bpy.ops.object.select_all(action="DESELECT")
    malla.select_set(True)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    # Los pesos van por ENVOLVENTE, no por "bone heat". El solucionador de
    # heat falla en headless ("failed to find solution for one or more bones")
    # y deja la malla sin un solo peso, o sea que el .glb salia sin skin: bones
    # y clips de adorno, y el modelo ni se deforma. La envolvente solo necesita
    # los radios de ENVOLVENTE, es determinista y funciona sin ventana.
    bpy.ops.object.parent_set(type="ARMATURE_ENVELOPE")
    for md in malla.modifiers:
        if md.type == "ARMATURE":
            md.use_bone_envelopes = True
            md.use_vertex_groups = False
    fps = 24
    bpy.context.scene.render.fps = fps
    for nombre_clip, fn in CLIPS:
        fn(rig, fps)
    rig.animation_data.action = None
    bpy.context.scene.frame_set(1)
    con_peso = sum(1 for v in malla.data.vertices if len(v.groups) > 0)
    total = max(1, len(malla.data.vertices))
    print("[RIG] esqueleto: %d huesos | altura %.2f m" % (len(rig.data.bones), alto))
    print("[RIG] vertices con peso: %d/%d (%.0f%%)" % (
        con_peso, total, 100.0 * con_peso / total))
    if con_peso < total * 0.95:
        print("[RIG] AVISO: sin peso en mas del 5%% de la malla; sube ENVOLVENTE")
    print("[RIG] clips: %s" % ", ".join(n for n, _ in CLIPS))
    return rig
