#!/usr/bin/env python3
"""Re-escribe los cuatro clips de un `.glb` YA RIGEADO y reexporta el `.glb`.

Fase 71 - por que este archivo existe. La animacion se "arreglo" cuatro veces
sin tocar los clips y el sintoma que ve el usuario no cambio: "al caminar
simplemente es como si flotara y solo tiene las manos levantadas abiertas".
Medido sobre el esqueleto de `models/clase_guerrero.glb`:

  - el ciclo de la marcha levanta el tobillo hasta 14 cm del suelo, o sea que el
    pie NUNCA apoya. Eso es flotar, y ninguna mezcla de idle/walk lo arregla;
  - la zancada es de 0,7432 u con el juego a 6 m/s, o sea 9,12 pisadas por
    segundo (una persona corre a unas 4): las piernas son un borron;
  - la cadera solo sube y baja 2,8 cm mientras el pie esta en el aire, que es al
    reves de como late una cadera.

Lo que hace ESTO, y solo esto: borra los cuatro `action` viejos y escribe
cuatro nuevos. No toca la malla, ni el retopo, ni los pesos, ni el esqueleto.
Las siete trampas de `tools/rig.py` y `tools/preparar_modelo.py` (roll del
hueso de brazo, longitudes positivas, eje Y local, `play_mode` del tercer
argumento, `pose_brazos` por asset, la pose que se queda en reposo) ya estan
pagadas y no hay que volver a pisarlas.

Uso:
    blender --background --python tools/animar_clips.py -- in.glb out.glb
    tools/animar_clips.sh models/clase_guerrero.glb

Criterios que cumple (los comprueba `tests/test_fase71_clips.gd`):
  a) REPOSO CON LOS BRAZOS ABAJO. El esqueleto del pack tiene el brazo a 40
     grados de la vertical (una A en reposo, ver `tools/rig.py`); los clips
     nuevos lo bajan a 7 con el codo a 17 de flexion, simetricos.
  b) SWING DE BRAZOS en la marcha, en el plano sagital y al reves del pie: el
     brazo contrario al que adelanta el pie es el que adelanta el brazo.
  c) PIE CORRECTO: en la pisada el pie esta plantado y se va hacia atras, y en
     el vuelo pasa adelante. El ciclo CRUDO sale espejado a proposito, porque
     el juego lo reproduce al reves (`ArbolAnimacion.CAMINAR_AL_REVES`).
  d) SIN DESPLAZAMIENTO DE RAIZ: el Hips no se translada en X ni en Y, solo rota
     y sube y baja lo que pesa el paso.
  e) BUCLE en idle y walk: la primera y la ultima clave son la misma pose.
  f) attack con las DOS manos (el juego lleva arma en las dos) y die con su
     duracion; los cuatro clips duran lo que duraban.

Y el numero que se pedia, que sale por construccion:
    VELOCIDAD_CLIP = zancada * 2 / duracion  (= 1,4264 u/s, `ArbolAnimacion`)
La zancada se deriva de la pierna real del modelo y la duracion se deriva de la
zancada, de modo que la invariante de no patinaje se cumple sin tocarla.
"""
from __future__ import annotations

import math
import sys

import bpy  # type: ignore
from mathutils import Matrix, Vector  # type: ignore

FPS = 24
CLIPS = ("idle", "walk", "attack", "die")

# --------------------------------------------------------------------------
# Constantes que vienen del JUEGO, no de un gusto. `VELOCIDAD_CLIP` es
# `ArbolAnimacion.VELOCIDAD_CLIP` (velocidad de viaje del clip de caminar en
# unidades de esqueleto) y `VEL_JUEGO` es `StatBlock.vel_mov`. El esqueleto se
# cuelga con `modelo_escala` 0,9 en las clases y el arbol reproduce el clip al
# ritmo que cancela el patinaje, o sea `v / (VELOCIDAD_CLIP * escala)`.
VELOCIDAD_CLIP = 1.4264
VEL_JUEGO = 6.0
ESCALA_MODELO = 0.9
# Multiplicador que el ARBOL le pondra al clip a 6 m/s, con la misma regla que
# `ArbolAnimacion.ritmo` (cuantizado a 0,25).
PASO_RITMO = 0.25
RITMO_JUEGO = (round(VEL_JUEGO / (VELOCIDAD_CLIP * ESCALA_MODELO) / PASO_RITMO)
               * PASO_RITMO)

# Zancada como fraccion de la pierna. 0,628 es lo que hace que el pie APOYE en
# los dos extremos del ciclo sin agacharse: en el apoyo y en el despegue la
# pierna esta mas tendida que en el paso, asi que para que el pie siga en el
# suelo la cadera tiene que bajar. Con 0,628 baja 5 cm; con 0,74 (el ciclo
# viejo) le tocaba bajar 10,5 cm y aun asi el pie flotaba 14 cm.
ZANCADA_POR_PIERNA = 0.628
# Reparto pisada (apoyo) contra vuelo. 0,62 deja el ciclo entero en contacto
# con el suelo salvo el vuelo corto, que es lo que se ve al caminar.
FASE_PISADA = 0.62

# Brazo en reposo, en radianes. 0,578 baja el brazo del pack de 40 grados a 7
# (es el `BASE_BRAZO` de `tools/rig.py`, medido en el render).
BRAZO_BAJAR = 0.578
# Flexion del codo en reposo: 12,6 grados, natural, no un palo.
BRAZO_CODO = 0.22
# Cuanta flexion del codo endereza la muneca al colgar el brazo, como fraccion
# de la flexion del codo. 0,9 deja los dedos mirando al suelo, que es como cuelga
# una mano; con 0 se quedan doblados hacia delante, que es lo que hacia la
MUNECA_REL = 0.90
# Swing del brazo en la marcha, en radianes.
BRAZO_SWING = 0.30
# Contracuerpo: giro de cadera y de pecho al caminar, respiracion en reposo.
HIPS_YAW_WALK = 0.085
HIPS_YAW_IDLE = 0.030
# Altura extra del tobillo con la punta levantada (talón al apoya, punta al
# despegue). Es geometria del pie, no del cuerpo.
TOBILLO_PUNTA = 0.075
# Inclinacion del pie al apoyar (punta arriba) y al despegar (punta abajo). Van
#Dados con la altura del tobillo: el pie no atraviesa el suelo si los dos van
# de la mano, y `longitud_pie * sin(0,18) = 0,077` es justo el TOBILLO_PUNTA.
PITCH_APOYAR = 0.12
PITCH_DESPEGAR = 0.18
# Cuanto sube el pie en el punto alto del vuelo, como fraccion de la pierna.
VUELO_ALTO = 0.34

ORDEN = [
    "Hips", "Spine", "Chest", "Neck", "Head",
    "Shoulder.L", "UpperArm.L", "LowerArm.L", "Hand.L",
    "Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R",
    "Thigh.L", "Shin.L", "Foot.L",
    "Thigh.R", "Shin.R", "Foot.R",
]


# ------------------------------------------------------------------ utilidades


def argumentos() -> list[str]:
    if "--" not in sys.argv:
        print("[ANIM] faltan argumentos: entrada.glb salida.glb")
        sys.exit(2)
    return sys.argv[sys.argv.index("--") + 1:]


def suave(x: float) -> float:
    """0 -> 1 sin aceleron ni frenon en los extremos. El `sin` de `rig.py`
    deja un tiron al final de cada tramo, y en un ciclo de 1,5 s a 6 m/s ese
    tiron se ve."""
    x = min(1.0, max(0.0, x))
    return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


def espejo(v: Vector) -> Vector:
    return Vector((-v.x, v.y, v.z))


def girado(v: Vector, eje: Vector, angulo: float) -> Vector:
    if abs(angulo) < 1e-12 or eje.length < 1e-9:
        return v.copy()
    return (Matrix.Rotation(angulo, 3, eje.normalized()) @ v).normalized()


def unitario(v: Vector, por_defecto: Vector) -> Vector:
    return v.normalized() if v.length > 1e-9 else por_defecto.copy()


# ------------------------------------------------------------------- esqueleto


class Esqueleto:
    """Lo del esqueleto que hay que MEDIR del archivo, no suponer. Las
    proporciones del pack varian (0,9 a 3,8 m de alto) y la zancada sale de la
    pierna real de cada modelo."""

    def __init__(self, arm: object) -> None:
        self.arm = arm
        h = {p.name: p.bone for p in arm.pose.bones}
        self.h = h
        self.cadera = h["Hips"].head_local.copy()
        self.muslo = self.largo("Thigh.L")
        self.espinilla = self.largo("Shin.L")
        self.pierna = self.muslo + self.espinilla
        self.tobillo = self.largo("Foot.L")
        self.tobillo_rep = h["Foot.L"].head_local.z
        self.hombro = self.largo("Shoulder.L")
        self.brazo_sup = self.largo("UpperArm.L")
        self.brazo_inf = self.largo("LowerArm.L")
        self.largo_cadena = self.brazo_sup + self.brazo_inf
        self.alto = h["Head"].tail_local.z
        self.semizancada = ZANCADA_POR_PIERNA * self.pierna

    def largo(self, nombre: str) -> float:
        h = self.h[nombre]
        return (h.head_local - h.tail_local).length

    def cabeza(self, nombre: str) -> Vector:
        return self.h[nombre].head_local.copy()

    def frames_walk(self) -> int:
        """Cuantos frames tiene el ciclo de marcha. Sale de la zancada, para
        que `zancada * 2 / duracion` sea exactamente `VELOCIDAD_CLIP`.

        OJO con el numero de la duracion: el exportador de Blender escribe la
        clave del frame N en el tiempo `N / fps` (medido: el clip viejo tiene
        claves 1..25 y Godot lo mide como 1,0417 s = 25/24, no 24/24). Por eso
        aqui la duracion que cuenta es `frames / fps` y no `(frames-1)/fps`.
        """
        zancada = 2.0 * self.semizancada
        dur = 2.0 * zancada / VELOCIDAD_CLIP
        return max(8, int(round(dur * FPS)))

    def duracion_walk(self) -> float:
        return self.frames_walk() / float(FPS)


# -------------------------------------------------------------------- escritura


class Escritor:
    """Escribe una pose completa en un frame con `keyframe_insert`, igual que
    `tools/rig.py`, pero la rotacion de cada hueso se calcula a partir de la
    DIRECCION que se quiere en el espacio del esqueleto y no de un numero de
    Euler deducido: el roll de los huesos de pierna no es el de los de brazo
    (a los de brazo `rig.py` les alinea el roll y a los de pierna no), y un
    Euler escrito a mano sale al reves en una de las dos cadenas.

    Y los huesos se colocan en el ORDEN de la jerarquia (la constante `ORDEN`),
    porque al asignar `pose_bone.matrix` Blender lee la pose del padre y si el
    padre todavia no esta puesto, el hijo queda colgando de donde estara."""

    def __init__(self, arm: object) -> None:
        self.arm = arm
        self._abs: dict = {}
        for nombre in ORDEN:
            pb = arm.pose.bones[nombre]
            pb.rotation_mode = "XYZ"
            pb.location = (0.0, 0.0, 0.0)
            pb.scale = (1.0, 1.0, 1.0)
        bpy.context.view_layer.update()

    def _colocar(self, nombre: str, m_abs: Matrix) -> None:
        """Pone un hueso en su matriz ABSOLUTA (la del espacio del esqueleto) y
        deja `location` y `rotation_euler` listos para exportar.

        Se asigna `pose_bone.matrix` y no se deduce el `matrix_basis` a mano,
        porque la relacion que hay entre `pose_bone.matrix`,
        `bone.matrix_local` y `matrix_basis` cambia con la rotacion que tenga el
        padre (medido: con el padre en reposo vale `local @ basis`, y en cuanto
        el padre se mueve ninguna de las cuatro combinaciones de izquierda da
        el mismo numero, con errores de hasta 1,19). Blender la resuelve bien y
        encima deduce el roll. Leer despues `matrix_basis` y pasarlo a
        `location` + `rotation_euler` reproduce el mismo numero (verificado con
        la cabeza del tobillo a 0,30 m de profundidad y 0,25 de altura).
        """
        pb = self.arm.pose.bones[nombre]
        pb.matrix = m_abs
        # El `view_layer.update()` entre hueso y hueso NO es opcional: al
        # asignar `pose_bone.matrix`, Blender lee la pose del padre, y sin
        # actualizar se queda con la del frame anterior (medido: 0,90 de error
        # en la espinilla, y el tobillo a 1,5 m del suelo). Cuesta 0,4 ms.
        bpy.context.view_layer.update()
        m = pb.matrix_basis
        pb.location = m.to_translation()
        pb.rotation_euler = m.to_3x3().to_euler("XYZ")
        self._abs[nombre] = m_abs

    def poner(self, nombre: str, cabeza: Vector, direccion: Vector) -> None:
        """Coloca un hueso: la cabeza en el espacio del esqueleto y el hueso
        apuntando a `direccion` (tambien en el espacio del esqueleto)."""
        hueso = self.arm.pose.bones[nombre].bone
        d0 = (hueso.matrix_local.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
        eje = d0.cross(direccion)
        if eje.length < 1e-7:
            rot = Matrix.Identity(3)
        else:
            cos = max(-1.0, min(1.0, d0.dot(direccion)))
            rot = Matrix.Rotation(math.acos(cos), 3, eje.normalized())
        r = rot @ hueso.matrix_local.to_3x3()
        self._colocar(nombre, Matrix.Translation(cabeza) @ r.to_4x4())

    def girar(self, nombre: str, eje: str, angulo: float) -> None:
        """Una rotacion ADEMAS del hueso, en el espacio del esqueleto y SOBRE SU
        PROPIA CABEZA. Es lo que permite el balanceo de cadera, el latigazo del
        pecho y la cabeza.

        Sobre su propia cabeza, y no sobre el origen: rotar sobre el origen
        desplaza la articulacion de la cadera, las piernas quedan colgando de
        un punto que ya no es el de la cadera y la cadena se descose (medido:
        el tobillo acababa 0,9 m por debajo del suelo)."""
        if abs(angulo) < 1e-12:
            return
        m = self._abs.get(nombre)
        if m is None:
            return
        cabeza = m.to_translation()
        self._colocar(nombre, Matrix.Translation(cabeza)
                      @ Matrix.Rotation(angulo, 3, eje).to_4x4()
                      @ Matrix.Translation(-cabeza) @ m)

    def clave(self, frame: float) -> None:
        for nombre in ORDEN:
            pb = self.arm.pose.bones[nombre]
            pb.keyframe_insert("rotation_euler", frame=frame)
            pb.keyframe_insert("location", frame=frame)
        self._abs.clear()


# -------------------------------------------------------------- la biomecanica


def ik_pierna(l_muslo: float, l_espinilla: float, adelante: float,
              arriba: float) -> tuple[float, float]:
    """Dos huesos, una punta. Devuelve los angulos de muslo y espinilla desde
    la vertical ABAJO, en positivo hacia DELANTE (la cara del personaje).

    La rodilla se dobla hacia atras porque el albedo del golpe va al lado
    contrario: el muslo queda mas adelantado que la linea cadera-tobillo. Asi
    sale la postura de un cuerpo y no la de un palo con una pierna mas corta.
    """
    d = math.hypot(adelante, -arriba)
    tope = (l_muslo + l_espinilla) * 0.9995
    d = max(min(d, tope), abs(l_muslo - l_espinilla) * 1.001)
    phi = math.atan2(adelante, -arriba)
    cos_a = (l_muslo * l_muslo + d * d - l_espinilla * l_espinilla) / (2.0 * l_muslo * d)
    alfa = math.acos(max(-1.0, min(1.0, cos_a)))
    ang_muslo = phi + alfa
    ku = l_muslo * math.sin(ang_muslo)
    kw = -l_muslo * math.cos(ang_muslo)
    ang_espinilla = math.atan2(adelante - ku, -(arriba - kw))
    return ang_muslo, ang_espinilla


def ruta_pie(u: float, esc: Esqueleto, semizancada: float) -> tuple[float, float]:
    """Trayectoria del TOBILLO en `u` (0..1, con el apoyo en u=0), en
    coordenadas de suelo: `adelante` respecto de la cadera del mismo instante y
    `arriba` respecto de la altura de reposo del tobillo.

    Es lo que decide si el personaje flota: el pie tiene que PEGAR AL SUELO en
    toda la pisada. El ciclo viejo levantaba el tobillo 14 cm y por eso el bicho
    andaba por el aire.
    """
    if u < FASE_PISADA:
        v = u / FASE_PISADA
        # Constante por construccion = el pie no patina respecto de la cadera.
        adelante = semizancada * (1.0 - 2.0 * v)
        # Al APOYAR el talon baja y el pie queda plano: el tobillo esta a su
        # altura de reposo. Al DESPEGAR la punta se apoya y el tobillo sube.
        if v < 0.10:
            arriba = TOBILLO_PUNTA * (1.0 - suave(v / 0.10))
        elif v > 0.80:
            arriba = TOBILLO_PUNTA * suave((v - 0.80) / 0.20)
        else:
            arriba = 0.0
        return adelante, arriba
    w = (u - FASE_PISADA) / (1.0 - FASE_PISADA)
    adelante = -semizancada + 2.0 * semizancada * suave(w)
    arriba = TOBILLO_PUNTA + VUELO_ALTO * esc.pierna * (math.sin(math.pi * w) ** 1.4)
    return adelante, arriba


def altura_cadera(u: float, esc: Esqueleto, semizancada: float) -> float:
    """Altura de la cadera sobre el suelo. Sale de lo que el pie PERMITE, no de
    un numero: si la cadera sube mas de lo que da la pierna, el pie se despega y
    el personaje flota. Es el techo de las dos piernas, y nunca pasa de la
    altura de reposo."""
    techo = []
    for du in (u - 0.5, u, u + 0.5):
        adelante, arriba = ruta_pie(du % 1.0, esc, semizancada)
        horiz = abs(adelante)
        if horiz >= esc.pierna * 0.999:
            continue
        techo.append(esc.tobillo_rep + arriba
                      + math.sqrt(max(0.0, esc.pierna ** 2 - horiz ** 2)))
    if not techo:
        return esc.tobillo_rep + esc.pierna
    return min(esc.tobillo_rep + esc.pierna, min(techo))


def brazo_abajo(flexion: float = 0.0) -> dict:
    """Direcciones de la cadena del brazo izquierdo para el brazo ABAJO, con
    `flexion` radianes de vaiven adelante-atras (el swing de la marcha).

    Se calcula una vez para la izquierda y la derecha sale por espejo. Es como
    se garantiza la simetria de verdad: con dos numeros opuestos escritos a
    mano (que es lo que hacia `rig.py`) el resultado sale asimetrico.
    """
    lateral = math.radians(7.0)
    d1 = Vector((math.sin(lateral), 0.0, -math.cos(lateral)))
    # El hombro gira el brazo entero en el plano sagital. OJO con el signo, que
    # se midio y no se dedujo: `+flexion` lleva el brazo HACIA ATRAS, y el
    # mismo numero lo hace en los DOS lados (el eje X local de `UpperArm.L` y
    # el de `UpperArm.R` dan el mismo sentido en el mundo). O sea que el caller
    # decide con los signos si los dos brazos van juntos (el tajo, `+atras` en
    # la carga y `-atras` en el golpe) o en contrafase (la marcha).
    d1 = girado(d1, Vector((1.0, 0.0, 0.0)), -flexion)
    d1 = unitario(d1, Vector((0.0, 0.0, -1.0)))
    # El codo dobla hacia DELANTE (una articulacion que dobla hacia atras es una
    # rotura). `eje x d1` apunta hacia delante, asi que el signo es positivo.
    eje = unitario(d1.cross(Vector((0.0, -1.0, 0.0))), Vector((1.0, 0.0, 0.0)))
    d2 = girado(d1, eje, BRAZO_CODO)
    # La mano sigue al antebrazo con la muñeca RELAJADA, no con la flexion de
    # 0,95 rad que le ponia `rig.py` (que hacia que el hueso de la mano, y con
    # el los 108 vertices de peso Hand, apuntara hacia delante y ARRIBA: medido,
    # la malla iba a (0,36, -0,25, 0,97) con el dorso de la mano mirando al
    # frente, y de ahi las "manos levantadas abiertas" del sintoma). Aqui la
    # muñeca endereza la mitad de la flexion del codo, que es lo que hace una
    # muñeca de verdad cuando el brazo cuelga.
    d3 = girado(d2, eje, MUÑECA_REL * BRAZO_CODO)
    return {"hombro": d1, "codo": d2, "muneca": d3}


def _accion(arm: object, nombre: str) -> object:
    """Accion nueva CON SU SLOT. Blender 4.4+ usa acciones por capas con slots:
    sin el slot, `keyframe_insert` escribe en el aire y el clip sale vacio al
    exportar. Es la misma trampa que `rig._nueva_accion`."""
    acc = bpy.data.actions.new(nombre)
    arm.animation_data_create()
    arm.animation_data.action = acc
    if hasattr(acc, "slots"):
        acc.slots.new(id_type="OBJECT", name="Object")
        arm.animation_data.action_slot = acc.slots[0]
    # `use_fake_user` NO es cosmology: en Blender 5.2 el exportador de glTF se
    # lleva solo las acciones que sobreviven, y sin esto la accion se va al
    # tirar la referencia y el GLB sale con CERO animaciones (medido: 10,2 MB de
    # malla y ningun clip, que es peor que no reanimar).
    acc.use_fake_user = True
    return acc


def _borrar_acciones() -> int:
    n = 0
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)
        n += 1
    return n


def _reposo(arm: object, esc: "Esqueleto", esq: "Escritor") -> None:
    """Todos los huesos en su pose de reposo. Sin accion, el valor de los
    huesos se queda congelado en el del ULTIMO clip escrito (el `die`), y
    cualquier render o preview sale con el cadaver."""
    for nombre in ORDEN:
        b = esc.h[nombre]
        esq.poner(nombre, b.head_local.copy(),
                  (b.matrix_local.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized())


def _tronco(esc: "Esqueleto", esq: "Escritor", resp: float,
            balanceo: float) -> None:
    """Hips + columna, en reposo con la respiracion encima. Los huesos que no
    se mueven se colocan en su pose de reposo explicita, para que la accion los
    lleve y no dependa de lo que hubiera quedado del clip anterior."""
    esq.poner("Hips", esc.cadera.copy(), Vector((0.0, 0.0, 1.0)))
    esq.girar("Hips", "Z", HIPS_YAW_IDLE * balanceo)
    esq.girar("Hips", "X", 0.012 * resp)
    for nombre, incl in (("Spine", 0.010 * resp), ("Chest", 0.018 * resp),
                         ("Neck", -0.020 * resp), ("Head", -0.025 * resp)):
        b = esc.h[nombre]
        esq.poner(nombre, b.head_local.copy(),
                  (b.matrix_local.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized())
        if incl:
            esq.girar(nombre, "X", incl)


def _brazo(esc: "Esqueleto", esq: "Escritor", lado: str, flex: float) -> None:
    """La cadena del brazo de un lado, colgando. Se calcula la izquierda y la
    derecha sale por espejo: es como se garantiza la simetria de verdad."""
    s = ".L" if lado == "L" else ".R"
    # `flex` es el angulo HACIA DELANTE en el mundo, y el MISMO numero produce
    # el mismo gesto en los dos lados: el eje X local de `UpperArm.L` y el de
    # `UpperArm.R` dan el mismo sentido en el mundo (medido). El espejo de abajo
    # solo endereza la apertura del brazo. Lo que decide si los dos brazos van
    # juntos (el tajo) o en contrafase (la marcha) son los signos que pasa el
    # caller, no esta funcion: con los signos puestos aqui se cancelan y los
    # dos brazos barren a la vez (medido: diferencia 0,0 y suma 34,4).
    d = brazo_abajo(flex)
    if lado == "R":
        d = {k: espejo(v) for k, v in d.items()}
    hombro = esc.cabeza("UpperArm" + s)
    codo = hombro + d["hombro"] * esc.brazo_sup
    muneca = codo + d["codo"] * esc.brazo_inf
    b = esc.h["Shoulder" + s]
    esq.poner("Shoulder" + s, b.head_local.copy(),
              (b.matrix_local.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized())
    esq.poner("UpperArm" + s, hombro, d["hombro"])
    esq.poner("LowerArm" + s, codo, d["codo"])
    esq.poner("Hand" + s, muneca, d["muneca"])


def _pitch_pie(u: float) -> float:
    """Rotacion del pie en el plano del apoyo, en radianes: el talon baja tras
    la pisada, el pie queda plano en el apoyo y la punta se levanta al
    despegar."""
    if u < FASE_PISADA:
        v = u / FASE_PISADA
        if v < 0.10:
            return PITCH_APOYAR * (1.0 - suave(v / 0.10))
        if v > 0.80:
            return -PITCH_DESPEGAR * suave((v - 0.80) / 0.20)
        return 0.0
    w = (u - FASE_PISADA) / (1.0 - FASE_PISADA)
    return -PITCH_DESPEGAR + (PITCH_APOYAR + PITCH_DESPEGAR) * suave(w)


def _pierna(esc: "Esqueleto", esq: "Escritor", lado: str, u: float,
            altura: float) -> None:
    """Pierna completa a partir de la posicion del tobillo, con IK de dos
    huesos. La cadera NO se translada en el plano: el personaje lo mueve el
    CharacterBody, no la animacion."""
    s = ".L" if lado == "L" else ".R"
    adelante, arriba = ruta_pie(u, esc, esc.semizancada)
    # La articulacion de la cadera es la CABEZA del muslo: no hay un hueso
    # "Hips.L" y buscarlo revienta.
    cadera = esc.h["Thigh" + s].head_local.copy()
    cadera.z = altura
    caida = altura - (esc.tobillo_rep + arriba)
    tobillo = cadera + Vector((0.0, -adelante, -caida))
    ang_m, ang_e = ik_pierna(esc.muslo, esc.espinilla, adelante, -caida)
    dir_m = Vector((0.0, -math.sin(ang_m), -math.cos(ang_m)))
    dir_e = Vector((0.0, -math.sin(ang_e), -math.cos(ang_e)))
    if lado == "R":
        dir_m = espejo(dir_m)
        dir_e = espejo(dir_e)
    esq.poner("Thigh" + s, cadera, dir_m)
    esq.poner("Shin" + s, cadera + dir_m * esc.muslo, dir_e)
    resto = (esc.h["Foot" + s].matrix_local.to_3x3()
             @ Vector((0.0, 1.0, 0.0))).normalized()
    if lado == "R":
        resto = espejo(resto)
    esq.poner("Foot" + s, tobillo,
              girado(resto, Vector((1.0, 0.0, 0.0)), _pitch_pie(u)))


def _pierna_de_pie(esc: "Esqueleto", esq: "Escritor", lado: str,
                   altura: float) -> None:
    """Pierna DE PIE: recta, con el pie plano en el suelo y el tobillo a la
    altura de reposo. Es la pose en la que la malla esta construida, asi que es
    la unica en la que los pies quedan apoyados de verdad."""
    s = ".L" if lado == "L" else ".R"
    # La articulacion de la cadera es la CABEZA del muslo: no hay un hueso
    # "Hips.L" y buscarlo revienta.
    cadera = esc.h["Thigh" + s].head_local.copy()
    cadera.z = altura
    caida = altura - esc.tobillo_rep
    ang_m, ang_e = ik_pierna(esc.muslo, esc.espinilla, 0.0, -caida)
    dir_m = Vector((0.0, -math.sin(ang_m), -math.cos(ang_m)))
    dir_e = Vector((0.0, -math.sin(ang_e), -math.cos(ang_e)))
    if lado == "R":
        dir_m = espejo(dir_m)
        dir_e = espejo(dir_e)
    esq.poner("Thigh" + s, cadera, dir_m)
    esq.poner("Shin" + s, cadera + dir_m * esc.muslo, dir_e)
    resto = (esc.h["Foot" + s].matrix_local.to_3x3()
             @ Vector((0.0, 1.0, 0.0))).normalized()
    if lado == "R":
        resto = espejo(resto)
    esq.poner("Foot" + s, cadera + Vector((0.0, 0.0, -caida)), resto)


# ------------------------------------------------------------------- los clips


def escribir_idle(arm: object, esc: "Esqueleto", frames: int) -> None:
    """Respiracion con los brazos ABAJO. Arranca y termina en la misma pose, y
    por eso el bucle no da un tiron (el viejo lo daba)."""
    _accion(arm, "idle")
    esq = Escritor(arm)
    for i in range(frames + 1):
        a = (i / float(frames)) * math.tau
        resp = math.sin(a)
        _tronco(esc, esq, resp, math.sin(a + 0.9))
        esq.poner("Hips", esc.cadera + Vector((0.0, 0.0, 0.004 * resp)),
                  Vector((0.0, 0.0, 1.0)))
        esq.girar("Hips", "Z", HIPS_YAW_IDLE * math.sin(a + 0.9))
        esq.girar("Hips", "X", 0.012 * resp)
        _brazo(esc, esq, "L", 0.0)
        _brazo(esc, esq, "R", 0.0)
        for lado in ("L", "R"):
            _pierna_de_pie(esc, esq, lado, esc.tobillo_rep + esc.pierna)
        esq.clave(i)


def escribir_walk(arm: object, esc: "Esqueleto", frames: int) -> None:
    """Ciclo de marcha, escrito AL REVES. El juego lo reproduce con
    `PLAY_MODE_BACKWARD` porque el ciclo crudo del pack salia espejado, y el
    test (c0) lo comprueba: aqui `u` es el TIEMPO REAL del juego y la clave del
    frame `i` lleva la pose de `u = 1 - i/frames`."""
    _accion(arm, "walk")
    esq = Escritor(arm)
    for i in range(frames + 1):
        u = (-i / float(frames)) % 1.0
        altura = altura_cadera(u, esc, esc.semizancada)
        adelante_l = ruta_pie(u, esc, esc.semizancada)[0]
        _tronco(esc, esq, 0.0, 0.0)
        esq.poner("Hips", esc.cadera + Vector((0.0, 0.0, altura - esc.cadera.z)),
                  Vector((0.0, 0.0, 1.0)))
        # Contracuerpo: la cadera gira al reves que la pierna que adelanta, y el
        # pecho en contrafase de la cadera. Sin esto el cuerpo va como un mueble.
        esq.girar("Hips", "Z", -HIPS_YAW_WALK * (adelante_l / esc.semizancada))
        esq.girar("Hips", "X", 0.018 * math.cos(u * math.tau))
        esq.girar("Chest", "Z", HIPS_YAW_WALK * 0.6
                  * (adelante_l / esc.semizancada))
        # El swing del brazo, al reves de su propio pie: el brazo contrario al
        # que adelanta es el que adelanta el brazo. Con `u = 0` el pie
        # izquierdo acaba de apoyan y va adelante, asi que el brazo izquierdo
        # va atras y el derecho adelante.
        # Con el pie izquierdo recien apoyado y adelantando, el brazo izquierdo
        # va ATRAS y el derecho adelante: la contrafase que hace que un cuerpo
        # parezca un cuerpo y no un mueble. El signo sale MEDIDO, no deducido:
        # con el otro, el brazo va 17,2 grados adelante justo cuando su pie va
        # 0,535 adelante (o sea, los dos del mismo lado).
        flex = BRAZO_SWING * math.cos(u * math.tau)
        _brazo(esc, esq, "L", -flex)
        _brazo(esc, esq, "R", flex)
        for lado, du in (("L", u), ("R", (u + 0.5) % 1.0)):
            _pierna(esc, esq, lado, du, altura)
        esq.clave(i)


def escribir_attack(arm: object, esc: "Esqueleto", frames: int) -> None:
    """Tajo con las DOS manos: el juego lleva arma en las dos y un tajo de una
    mano sola sale a medias. Carga, tajo y vuelta; no cicla."""
    _accion(arm, "attack")
    esq = Escritor(arm)
    # (segundo, flexion del brazo, giro de cadera, inclinacion)
    # (segundo, flexion del brazo, giro de cadera, inclinacion). Con la
    # convencion de `brazo_abajo`, POSITIVO es hacia atras: la carga lleva los
    # brazos atras y el golpe los lleva adelante.
    fases = ((0.00, 0.45, 0.00, 0.00),
             (0.40, 1.15, 0.34, 0.00),
             (0.52, -0.95, -0.32, 0.20),
             (0.75, -0.60, -0.20, 0.12),
             (1.00, 0.00, 0.00, 0.00))
    for f in range(frames + 1):
        t = f / float(frames)
        flex, giro, incl = fases[-1][1:]
        for (t0, f0, g0, i0), (t1, f1, g1, i1) in zip(fases, fases[1:]):
            if t0 <= t <= t1:
                w = suave((t - t0) / max(1e-6, t1 - t0))
                flex = f0 + (f1 - f0) * w
                giro = g0 + (g1 - g0) * w
                incl = i0 + (i1 - i0) * w
                break
        _tronco(esc, esq, 0.0, 0.0)
        esq.poner("Hips", esc.cadera + Vector((0.0, 0.0, -0.025 * incl)),
                  Vector((0.0, 0.0, 1.0)))
        esq.girar("Hips", "Z", -giro)
        esq.girar("Hips", "X", 0.12 * incl)
        esq.girar("Spine", "X", 0.14 * incl)
        esq.girar("Chest", "Y", 0.34 * incl)
        esq.girar("Chest", "Z", -0.18 * giro)
        esq.girar("Head", "X", -0.10 * incl)
        # Las dos manos al mismo tiempo, que es lo que lleva el juego: el
        # derecho marca el golpe y el izquierdo acompana con 0,12 mas.
        _brazo(esc, esq, "L", flex + 0.12)
        _brazo(esc, esq, "R", flex)
        for lado in ("L", "R"):
            _pierna_de_pie(esc, esq, lado,
                           esc.tobillo_rep + esc.pierna - 0.03 * incl)
        esq.clave(f)


def escribir_die(arm: object, esc: "Esqueleto", frames: int) -> None:
    """Se desploma: las rodillas ceden, el torso va al suelo y la cadera baja
    CON ellos (en el espacio del hueso, el eje Y es el largo del hueso y por eso
    bajar es `location.y`, no `location.z`). No cicla."""
    _accion(arm, "die")
    esq = Escritor(arm)
    fases = ((0.00, 0.00, 0.35, 0.00),
             (0.30, 0.22, 0.95, 0.45),
             (0.75, 0.60, 1.20, 0.90),
             (1.00, 0.72, 1.30, 1.00))
    for f in range(frames + 1):
        t = f / float(frames)
        bajo, ang, torso = fases[-1][1:]
        for (t0, b0, a0, s0), (t1, b1, a1, s1) in zip(fases, fases[1:]):
            if t0 <= t <= t1:
                w = suave((t - t0) / max(1e-6, t1 - t0))
                bajo = b0 + (b1 - b0) * w
                ang = a0 + (a1 - a0) * w
                torso = s0 + (s1 - s0) * w
                break
        altura = esc.tobillo_rep + esc.pierna * (1.0 - bajo)
        _tronco(esc, esq, 0.0, 0.0)
        esq.poner("Hips", esc.cadera + Vector((0.0, 0.0, altura - esc.cadera.z)),
                  Vector((0.0, 0.0, 1.0)))
        esq.girar("Hips", "X", 0.60 * torso)
        esq.girar("Spine", "X", 0.45 * torso)
        esq.girar("Chest", "X", 0.35 * torso)
        esq.girar("Head", "X", 0.30 * torso)
        _brazo(esc, esq, "L", 0.75 * torso)
        _brazo(esc, esq, "R", 0.75 * torso)
        # Las rodillas se doblan solas: al bajar la cadera la IK tiene que
        # doblarlas, y por eso el cadaver cae de rodillas y no como un palo.
        for lado in ("L", "R"):
            _pierna_de_pie(esc, esq, lado, altura)
        esq.clave(f)


# --------------------------------------------------------------- verificacion


def angulo_brazo(arm: object, nombre: str) -> float:
    """Grados que el brazo se separa de la vertical. Es el numero que se
    discute: el pack llega a 40 (una A tiesa) y el encargo pide brazos abajo."""
    pb = arm.pose.bones[nombre]
    d = (pb.tail - pb.head).normalized()
    return math.degrees(math.atan2(abs(d.x), -d.z))


def verificar(arm: object, esc: "Esqueleto") -> list[str]:
    """Mide lo que miden `tests/test_fase70_caminar.gd` y `test_fase71_clips.gd`,
    con el MISMO algoritmo, sobre el esqueleto. Se replica aqui para no tener
    que reexportar veinte veces hasta que cuadre: si el numero sale aqui, sale
    en Godot."""
    lineas: list[str] = []
    dur_walk = esc.duracion_walk()
    for act in bpy.data.actions:
        arm.animation_data_create()
        arm.animation_data.action = act
        if hasattr(act, "slots") and len(act.slots):
            arm.animation_data.action_slot = act.slots[0]
        f0, f1 = [int(v) for v in act.frame_range]
        n = 96
        ys: list[float] = []
        zs: list[float] = []
        caderas: list[Vector] = []
        for i in range(n + 1):
            bpy.context.scene.frame_set(f0 + int(round((f1 - f0) * i / float(n))))
            bpy.context.view_layer.update()
            p = arm.pose.bones["Foot.L"].head.copy()
            c = arm.pose.bones["Hips"].head.copy()
            ys.append(p.z)
            zs.append(-p.y + c.y)
            caderas.append(c.copy())
        dur = f1 / float(FPS)
        zancada = max(zs) - min(zs)
        i_apoyo = ys.index(min(ys))
        ini = max(0, i_apoyo - 8)
        fin = min(n, i_apoyo + 8)
        dz = zs[fin] - zs[ini]
        linea = ("%-7s frames %2d..%2d dur=%.4f s | zancada=%.4f u "
                 "natural=%.4f u/s | dz en el apoyo=%+.4f u | "
                 "tobillo min=%.4f max=%.4f | cadera y: min %.4f max %.4f"
                 % (act.name, f0, f1, dur, zancada, zancada * 2.0 / dur, dz,
                    min(ys), max(ys), min(c.z for c in caderas),
                    max(c.z for c in caderas)))
        lineas.append(linea)
    # Los brazos, en reposo (el idle) y el vaiven del walk.
    arm.animation_data.action = bpy.data.actions.get("idle")
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    brazos = "idle  brazo: L %.1f deg (codo %.1f)  R %.1f deg (codo %.1f)" % (
        angulo_brazo(arm, "UpperArm.L"), angulo_brazo(arm, "LowerArm.L"),
        angulo_brazo(arm, "UpperArm.R"), angulo_brazo(arm, "LowerArm.R"))
    _ua = arm.pose.bones["UpperArm.L"]
    _la = arm.pose.bones["LowerArm.L"]
    ang_codo = 180.0 - math.degrees((_la.tail - _la.head).angle(_ua.tail - _ua.head))
    lineas.append(brazos + " | angulo de codo %.1f deg" % ang_codo)
    arm.animation_data.action = bpy.data.actions.get("walk")
    vaiven = []
    f0, f1 = [int(v) for v in arm.animation_data.action.frame_range]
    for i in range(9):
        bpy.context.scene.frame_set(f0 + int(round((f1 - f0) * i / 8.0)))
        bpy.context.view_layer.update()
        ul = arm.pose.bones["UpperArm.L"]
        ur = arm.pose.bones["UpperArm.R"]
        pl = (ul.tail - ul.head).normalized()
        vaiven.append(math.degrees(math.atan2(-pl.y, -pl.z)))
    lineas.append("walk  brazo L vaiven: min %.1f max %.1f deg (delta %.1f) | "
                  "delta L-R en el frame 0 = %+.1f deg"
                  % (min(vaiven), max(vaiven), max(vaiven) - min(vaiven),
                     vaiven[0] - vaiven[0]))
    return lineas


# ----------------------------------------------------------------------- main


TESTIGO = "zz_pose_de_reposo"


def _accion_testigo(arm: object) -> None:
    """Accion VACIA que se deja ASIGNADA al esqueleto al exportar.

    No es un capricho: el exportador de glTF de Blender 5.2, en modo
    `ACTIONS`, se lleva todas las acciones de `bpy.data.actions` MENOS la que
    tiene el objeto activa. Medido: con ninguna asignada salen CERO
    animaciones, y con `idle` asignada salen las otras tres y no la idle. O sea
    que para que salgan las cuatro hay que tener algo asignado que no sea una
    de las cuatro, y eso se hace con una vacia que despues se recorta del
    `.glb` (ver `_recortar_clip`).
    """
    acc = bpy.data.actions.new(TESTIGO)
    acc.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = acc
    if hasattr(acc, "slots"):
        acc.slots.new(id_type="OBJECT", name="Object")
        arm.animation_data.action_slot = acc.slots[0]


def _recortar_clip(ruta: str, nombre: str) -> bool:
    """Quita una animacion del `.glb` ya escrito, reescribiendo solo el trozo
    JSON (el BIN se copia tal cual). Un acceso sin referenciar es glTF valido,
    asi que los accessors de la animacion quitada se quedan dead en el buffer:
    pesan poco y no hay que reindexar nada."""
    import json
    import struct

    with open(ruta, "rb") as f:
        datos = f.read()
    if len(datos) < 12:
        return False
    total = struct.unpack_from("<III", datos, 0)[2]
    trozos = []
    off = 12
    while off < total:
        largo, tipo = struct.unpack_from("<II", datos, off)
        trozos.append((tipo, datos[off + 8:off + 8 + largo]))
        off += 8 + largo
    fuera: list = []
    out: list = []
    for tipo, cuerpo in trozos:
        if tipo == 0x4E4F534A:  # JSON
            g = json.loads(cuerpo.decode("utf-8"))
            antes = len(g.get("animations", []))
            g["animations"] = [a for a in g.get("animations", [])
                                if a.get("name") != nombre]
            if len(g["animations"]) == antes:
                return False
            texto = json.dumps(g, separators=(",", ":")).encode("utf-8")
            texto += b" " * (-len(texto) % 4)
            fuera.append((tipo, texto))
        else:
            fuera.append((tipo, cuerpo))
    cab = bytearray()
    cab += struct.pack("<III", 0x46546C67, 2, 12 + sum(8 + len(c) for _, c in fuera))
    for tipo, cuerpo in fuera:
        cab += struct.pack("<II", len(cuerpo), tipo) + cuerpo
    with open(ruta, "wb") as f:
        f.write(bytes(cab))
    return True


def main() -> int:
    a = argumentos()
    if len(a) < 2:
        print("[ANIM] uso: animar_clips.py -- entrada.glb salida.glb")
        return 2
    entrada, salida = a[0], a[1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=entrada)

    print("[ANIM] objetos importados:")
    mallas = 0
    for o in sorted(bpy.context.scene.objects, key=lambda x: x.name):
        colecs = ",".join(c.name for c in o.users_collection)
        extra = ""
        if o.type == "MESH":
            mallas += 1
            extra = "verts=%d vgroups=%d" % (len(o.data.vertices),
                                             len(o.vertex_groups))
        if o.type == "ARMATURE":
            extra = "huesos=%d" % len(o.data.bones)
        print("[ANIM]   %-12s %-9s [%s] %s" % (o.name, o.type, colecs, extra))
    harapos = [o.name for o in bpy.context.scene.objects
               if any(c.name == "glTF_not_exported" for c in o.users_collection)]
    print("[ANIM]  Objetos que el exportador NO escribe (coleccion "
          "glTF_not_exported, que crea el IMPORTADOR de glTF): %s"
          % (", ".join(harapos) if harapos else "ninguno"))

    arm = next((o for o in bpy.context.scene.objects
                if o.type == "ARMATURE"), None)
    if arm is None:
        print("[ANIM] ERROR: el .glb no trae esqueleto")
        return 3
    esc = Esqueleto(arm)
    print("[ANIM] pierna %.4f u | muslo %.4f | espinilla %.4f | tobillo %.4f"
          % (esc.pierna, esc.muslo, esc.espinilla, esc.tobillo))
    print("[ANIM] zancada objetivo %.4f u (%.3f x pierna) | frames del walk %d"
          " (%.4f s)"
          % (2.0 * esc.semizancada, ZANCADA_POR_PIERNA, esc.frames_walk(),
             esc.duracion_walk()))

    n = _borrar_acciones()
    print("[ANIM] acciones borradas: %d" % n)
    fps = FPS
    bpy.context.scene.render.fps = fps
    escribir_idle(arm, esc, 49)     # 2,0417 s, el mismo que traia
    escribir_walk(arm, esc, esc.frames_walk())
    escribir_attack(arm, esc, 20)   # 0,8333 s, el mismo que traia
    escribir_die(arm, esc, 29)      # 1,2083 s, el mismo que traia

    for linea in verificar(arm, esc):
        print("[ANIM] %s" % linea)
    # El bucle: la primera y la ultima clave tienen que ser la MISMA pose, o el
    # reinicio del clip se ve como un tiron. Se mide la cabeza de los 19 huesos.
    peor: float = 0.0
    for nombre in ("idle", "walk"):
        acc = bpy.data.actions[nombre]
        arm.animation_data.action = acc
        if hasattr(acc, "slots") and len(acc.slots):
            arm.animation_data.action_slot = acc.slots[0]
        f0, f1 = [int(v) for v in acc.frame_range]
        bpy.context.scene.frame_set(f0)
        bpy.context.view_layer.update()
        a = {n: arm.pose.bones[n].head.copy() for n in ORDEN}
        bpy.context.scene.frame_set(f1)
        bpy.context.view_layer.update()
        d = max((a[n] - arm.pose.bones[n].head).length for n in ORDEN)
        peor = max(peor, d)
        print("[ANIM] bucle de '%s': diferencia entre el frame %d y el %d = "
              "%.5f u" % (nombre, f0, f1, d))
    zancada = 2.0 * esc.semizancada
    dur = esc.duracion_walk()
    print("[ANIM] cadencia a 6 m/s: ritmo del arbol %.2f | ciclo real %.4f s | "
          "pisadas/s %.2f | zancadas/s %.2f | zancada en el mundo %.3f m"
          % (RITMO_JUEGO, dur / RITMO_JUEGO, 2.0 * RITMO_JUEGO / dur,
             RITMO_JUEGO / dur, zancada * ESCALA_MODELO))
    print("[ANIM] velocidad de viaje del clip = %.4f u/s (ArbolAnimacion."
          "VELOCIDAD_CLIP = %.4f)" % (zancada * 2.0 / dur, VELOCIDAD_CLIP))

    _reposo(arm, esc, Escritor(arm))
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    _accion_testigo(arm)

    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    op = {"filepath": salida, "export_format": "GLB", "export_apply": True,
          "export_animations": True, "export_animation_mode": "ACTIONS",
          "export_skins": True, "export_try_sparse_sk": False,
          "export_yup": True}
    desconocidos = sorted(k for k in op if k not in props and k != "filepath")
    if desconocidos:
        print("[ANIM] AVISO: opciones que esta version de Blender no conoce: %s"
              % ", ".join(desconocidos))
    bpy.ops.export_scene.gltf(**{k: v for k, v in op.items() if k in props})
    ok = _recortar_clip(salida, TESTIGO)
    print("[ANIM] escrito %s (mallas en la escena: %d | accion testigo quitada: %s)"
          % (salida, mallas, "si" if ok else "NO"))
    if not ok:
        print("[ANIM] ERROR: el .glb se quedo con la accion testigo; el motor "
              "veria un clip de mas")
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
