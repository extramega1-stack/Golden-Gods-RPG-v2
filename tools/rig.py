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


def alto_de(malla: object) -> float:
    """Altura de la malla en metros, en el espacio del mundo."""
    bbs = [malla.matrix_world @ Vector(c) for c in malla.bound_box]
    return max(v.z for v in bbs) - min(v.z for v in bbs)


def _huesos(p: dict) -> list:
    """Cadena de huesos (nombre, cabeza, cola, padre) en metros."""
    L, R = "L", "R"
    return [
        ("Hips", (0, 0, p["hip_z"]), (0, 0, p["waist_z"]), None),
        ("Spine", (0, 0, p["waist_z"]), (0, 0, p["chest_z"]), "Hips"),
        ("Chest", (0, 0, p["chest_z"]), (0, 0, p["neck_z"]), "Spine"),
        ("Neck", (0, 0, p["neck_z"]), (0, 0, p["head_z"]), "Chest"),
        ("Head", (0, 0, p["head_z"]), (0, 0, p["top_z"]), "Neck"),
    ] + _brazos(p) + [
        # Pierna: muslo, tibia, pie y punta (para el apoyo al caminar).
        ("Thigh." + L, (p["hip_x"], 0, p["hip_z"]), (p["foot_x"], 0, p["knee_z"]), "Hips"),
        ("Shin." + L, (p["foot_x"], 0, p["knee_z"]), (p["foot_x"], 0, p["ankle_z"]), "Thigh." + L),
        ("Foot." + L, (p["foot_x"], 0, p["ankle_z"]), (p["toe_x"], p["toe_y"], p["toe_z"]), "Shin." + L),
        ("Thigh." + R, (-p["hip_x"], 0, p["hip_z"]), (-p["foot_x"], 0, p["knee_z"]), "Hips"),
        ("Shin." + R, (-p["foot_x"], 0, p["knee_z"]), (-p["foot_x"], 0, p["ankle_z"]), "Thigh." + R),
        ("Foot." + R, (-p["foot_x"], 0, p["ankle_z"]), (-p["toe_x"], p["toe_y"], p["toe_z"]), "Shin." + R),
    ]


# Radio de la envolvente de cada hueso, en metros.
#
# Estos numeros son ANATOMICOS a proposito. Con los primeros (0,55 en la
# cadera, 0,50 en el pecho) el pecho y la cadera se tragaban los brazos: el
# brazo izquierdo salia con Chest 34% / Hips 33% / Thigh 31%, o sea que los
# huesos del brazo no tenian NINGUN peso y al animarlos no se movia nada. Y al
# reves, la cabeza salia con LowerArm en vez de con Head.
ENVOLVENTE = {
    "Hips": 0.22, "Spine": 0.17, "Chest": 0.21, "Neck": 0.10, "Head": 0.17,
    "Shoulder": 0.10, "UpperArm": 0.13, "LowerArm": 0.12, "Hand": 0.09,
    "Thigh": 0.16, "Shin": 0.14, "Foot": 0.11,
}


def _brazos(p: dict) -> list:
    """Huesos del brazo siguiendo la direccion real del brazo de la malla.

    `p["ang_brazo"]` es el angulo desde la vertical (0 = colgando, 1.3 = T).
    La cadena sale del pecho: hombro, brazo, antebrazo y mano.
    """
    import math as _m
    a: float = float(p.get("ang_brazo", 0.15))
    dz: float = -_m.cos(a)
    dx: float = _m.sin(a)
    hombro: Vector = Vector((p["shoulder_x"], 0.0, p["shoulder_z"]))
    # Longitudes POSITIVAS: hombro - codo y codo - muñeca. Al revés (codo -
    # hombro = -0.33) el codo salia hacia arriba y hacia dentro, o sea que la
    # cadena del brazo acababa en la cabeza: los pesos se los comia el muslo, al
    # girar el brazo no se movia nada y al animar se retorcia el casco.
    largo1: float = p["shoulder_z"] - p["elbow_z"]
    largo2: float = p["elbow_z"] - p["wrist_z"]
    codo: Vector = hombro + Vector((dx * largo1, 0.0, dz * largo1))
    muneca: Vector = hombro + Vector((dx * (largo1 + largo2), 0.0, dz * (largo1 + largo2)))
    mano: Vector = muneca + Vector((dx * 0.08, -0.06, dz * 0.08))
    out: list = []
    for lado, sg in (("L", 1.0), ("R", -1.0)):
        h = Vector((hombro.x * sg, hombro.y, hombro.z))
        c = Vector((codo.x * sg, codo.y, codo.z))
        m = Vector((muneca.x * sg, muneca.y, muneca.z))
        f = Vector((mano.x * sg, mano.y, mano.z))
        out.append(("Shoulder." + lado, (h.x - sg * 0.12, h.y, h.z), (h.x, h.y, h.z), "Chest"))
        out.append(("UpperArm." + lado, (h.x, h.y, h.z), (c.x, c.y, c.z), "Shoulder." + lado))
        out.append(("LowerArm." + lado, (c.x, c.y, c.z), (m.x, m.y, m.z), "UpperArm." + lado))
        out.append(("Hand." + lado, (m.x, m.y, m.z), (f.x, f.y, f.z), "LowerArm." + lado))
    return out


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
        if nombre_h.split(".")[0] in ("UpperArm", "LowerArm", "Shoulder"):
            # Eje Z local hacia delante: con eso, rotar en Z baja/sube el brazo
            # en el plano frontal. Sin esto, animar un brazo abierto depende de
            # como haya caído el roll y los clips salen en diagonales.
            eb.align_roll(Vector((0.0, -1.0, 0.0)))
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


# Cuanto hay que BAJAR el brazo de su pose de reposo (la detectada) a una
# natural (colgado, ~0.20 rad). Llena `enrutar()`; lo consume `_clave_lista`.
BASE_BRAZO: dict = {"L": 0.0, "R": 0.0}

# En espacio de hueso, rotar en Z baja el brazo en el plano frontal. El signo
# se midio mirando el render, no deducido: al reves el luchador se quedaba con
# el brazo izquierdo arriba (un "stop") y el derecho colgando, en vez de los dos
# colgando. Con este signo, la izquierda suma y la derecha resta.
HUESOS_DE_BRAZO: tuple = ("UpperArm", "LowerArm", "Hand")

REPOSO_NATURAL: float = 0.20

## Angulo por defecto del brazo desde la vertical, en radianes. Corresponde a la
## A en la que viene el pack de Meshy; se sobreescribe por asset.
POSE_POR_DEFECTO: float = 0.70

## Cuantos huesos pueden influences un mismo vertice (los mas cercanos).
MAX_HUESOS: int = 4


def _clave_lista(arm: object, huesos: dict, frame: int) -> None:
    """`huesos` = {nombre: (rx, ry, rz)}; `None` = hueso quieto.

    A los huesos de brazo se les suma la base: asi un modelo que viene en T
    aparece con los brazos colgando en el idle, sin tener que escribir la
    compensacion clip a clip.
    """
    for nombre, rot in huesos.items():
        if rot is None:
            continue
        partes = nombre.split(".")
        if partes[0] in HUESOS_DE_BRAZO and len(partes) > 1:
            sg: float = 1.0 if partes[1] == "L" else -1.0
            rot = (rot[0], rot[1], rot[2] + sg * BASE_BRAZO[partes[1]])
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


def _poner_en_reposo(arm: object) -> None:
    """Deja todos los huesos en su pose de reposo (sin rotar)."""
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)


def _distancia_segmento(p: Vector, a: Vector, b: Vector) -> float:
    """Distancia de un punto al segmento a-b."""
    ab = b - a
    largo2 = ab.dot(ab)
    if largo2 < 1e-9:
        return (p - a).length
    t = max(0.0, min(1.0, (p - a).dot(ab) / largo2))
    return (p - (a + ab * t)).length


def pesos_proprios(malla: object, arm: object) -> int:
    """Reparte los pesos a mano: distancia a cada hueso, caida cuadrada.

    Blender tiene dos formas de hacerlo y aqui ninguna servia:

    - "bone heat" (laautomatica de verdad) falla en headless con
      "failed to find solution" y deja la malla sin un solo peso.
    - "envelope" reparte la influencia entre todos los huesos cercano, y con un
      torso gordo el pecho y la cadera se quedan con el 67% del brazo. Medido:
      el brazo se movia 2 grados cuando se le pedian 23.

    Aqui cada vertice se queda con los `MAX_HUESOS` huesos mas cercanos, con
    peso (1 - d/r)^2 (el cuadrado hace que mande el mas cercano en vez de
    repartirse) y normalizado a 1. Determinista, sin ventana, y con la
    correccion de los pesos al alcance.
    """
    print("[RIG] calculando pesos a mano (%d vertices x %d huesos)" % (
        len(malla.data.vertices), len(arm.data.bones)))
    segmentos = []
    for i, hueso in enumerate(arm.data.bones):
        segmentos.append((i, hueso.head_local.copy(), hueso.tail_local.copy(),
                          ENVOLVENTE.get(hueso.name.split(".")[0], 0.12)))
    grupos = {}
    for hueso in arm.data.bones:
        g = malla.vertex_groups.new(name=hueso.name)
        grupos[hueso.name] = g.index
    for v in malla.data.vertices:
        candidatos = []
        for idx, a, b, radio in segmentos:
            d = _distancia_segmento(v.co, a, b)
            if d < radio:
                candidatos.append((d, radio, idx))
        if not candidatos:
            candidatos = [min(
                ((_distancia_segmento(v.co, a, b), r, i) for i, a, b, r in segmentos),
                key=lambda t: t[0])]
        candidatos.sort(key=lambda t: t[0])
        pesos = []
        for d, radio, idx in candidatos[:MAX_HUESOS]:
            w = max(0.0, 1.0 - d / radio) ** 2
            if w > 0.0:
                pesos.append((idx, w))
        total = sum(w for _, w in pesos)
        if total <= 0.0:
            pesos = [(candidatos[0][2], 1.0)]
            total = 1.0
        for idx, w in pesos:
            malla.vertex_groups[grupos[arm.data.bones[idx].name]].add([v.index], w / total, "REPLACE")
    return len(malla.data.vertices)


def enrutar(malla: object, ang_brazo: float = None) -> object:
    """Le pone esqueleto, pesos y los cuatro clips a `malla`. Devuelve el rig.

    `ang_brazo` es el angulo del brazo DESDE LA VERTICAL, en radianes: 0.2 son
    los brazos colgando, 0.7 (40 grados) es la A en la que viene todo el pack de
    Meshy, 1.3 es la T horizontal. Lo declara el asset en `data/modelos.json`
    (`pose_brazos`) y lo pasa `preparar_modelo.py`; no se deduce de la malla
    porque con faldones y capas la silueta no lo distingue.
    """
    prop = dict(PROP)
    p_ang_brazo: float = POSE_POR_DEFECTO if ang_brazo is None else float(ang_brazo)
    # Las proporciones estan calibradas para 1,90 m: si el modelo mide otra
    # cosa, se escala el esqueleto con el (el pack va de 0,9 a 3,8 m).
    alto = max((malla.matrix_world @ Vector(c)).z for c in malla.bound_box) \
        - min((malla.matrix_world @ Vector(c)).z for c in malla.bound_box)
    if alto > 0.01:
        k = alto / PROP["top_z"]
        for key in list(prop):
            prop[key] = prop[key] * k
    ang: float = float(p_ang_brazo)
    prop["ang_brazo"] = ang
    global BASE_BRAZO
    BASE_BRAZO = {"L": (ang - REPOSO_NATURAL), "R": -(ang - REPOSO_NATURAL)}
    print("[RIG] pose de brazos declarada: %.0f grados (%.2f rad) | alto %.2f m"
          % (math.degrees(ang), ang, alto_de(malla)))
    rig = _crear_esqueleto("Rig", prop)
    bpy.ops.object.select_all(action="DESELECT")
    malla.select_set(True)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    # Parentear SIN que Blender reparta pesos: se hace a mano despues
    # (pesos_proprios), porque ni el heat ni las envolventes sirven aqui.
    bpy.ops.object.parent_set(type="ARMATURE")
    pesos_proprios(malla, rig)
    for md in malla.modifiers:
        if md.type == "ARMATURE":
            md.use_bone_envelopes = False
            md.use_vertex_groups = True
    fps = 24
    bpy.context.scene.render.fps = fps
    for nombre_clip, fn in CLIPS:
        fn(rig, fps)
    rig.animation_data.action = None
    # Los huesos guardan los valores del ULTIMO clip escrito (el `die`), y sin
    # accion no los reinicia nadie: la malla se queda congelada en el desplome
    # y cualquier render o preview sale con el cadaver. Se dejan en reposo.
    _poner_en_reposo(rig)
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
