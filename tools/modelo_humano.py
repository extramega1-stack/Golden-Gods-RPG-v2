#!/usr/bin/env python3
"""Genera un HUMANO PROCEDURAL desde cero, con dedos articulados, y lo exporta.

POR QUE EXISTE ESTE ARCHIVO Y NO UN `.glb` MAS
------------------------------------------------
Los seis modelos que habia en `models/` vienen de un generador automatico
(Meshy) y el problema NO se arregla con animacion ni con materiales. Medido:

  - El hueso `Hand.L` es un cubo: 108 vertices de peso y ni una falange. No hay
    informacion de mano en el asset, y una mano sin dedos no puede verse natural
    por muy bien alineada que este la muneca. El usuario reporto DOS veces que
    las manos quedan raras, y con la muneca resuelta (0,18 rad) y el codo a 26
    grados el sintema no se movio: la causa ya no era el codigo.
  - `data/anclajes.json` no tiene ninguna ranura de dedo, porque el esqueleto no
    los tiene.
  - Los clips se generaron con un script, no se animaron.

Asi que el modelo se construye aqui, con las cuatro piezas que un `.glb` de
paquete no trae:

  1. MALLA CON TOPOLOGIA PARA DEFORMAR. Cada articulacion lleva un LOOP (un
     anillo de vertices justo en el eje, con peso repartido 50/50 entre los dos
     huesos) y una BANDA DE APOYO a cada lado (anillos densely muestreados en el
     12% final de cada hueso, con el 100% de ese hueso). Sin eso, un giro de 90
     grados en el codo aplasta la malla: es lo que se ve raro, y no es el peso
     ni el material.
  2. 33 HUESOS: los 19 que el juego ya espera (mismos NOMBRES, que es lo unico
     que el codigo lee) mas 14 de dedos (pulgar, indice, medio, anular y menique
     en las dos manos). La jerarquia sale EXACAMENTE como la espera
     `scripts/player/paper_doll.gd`: `<nombre>/Rig/Skeleton3D`, con el
     AnimationPlayer hermano de `Rig`.
  3. PBR HORNEADO POR CODIGO, con la comprobacion de ENVOLTURA. Una textura que
     no envuelve tiene costura, y la costura no la caza ningun error: sale en
     pantalla y parece un fallo de arte. Aqui la textura se genera con una
     funcion periodica en AMBAS direcciones (ciclos enteros), y se mide: el salto
     entre la primera y la ultima columna tiene que ser del orden del gradiente
     de un pixel, no de un escalon. Ademas se comprueba que el sampler del
     `.glb` sale en REPEAT (10497) y no en CLAMP.
  4. LOS CUATRO CLIPS CON LOS DEDOS. La mano cierra en reposo, agarra en el
     tajo. Un cadaver con quince dedos clavados se ve mal aunque el brazo sea
     perfecto.

LO QUE NO TOCA
--------------
Ni `scripts/`, ni `data/`, ni `project.godot`. El juego tiene que seguir
funcionando con el modelo nuevo sin tocar una linea. Eso es lo que prueba que
el modelo es bueno: que el codigo no se entero.

USO
---
    blender --background --python tools/modelo_humano.py -- salida.glb [opciones]
        --clase guerrero|arquero|clerigo|mago|daguero|bandido
        --alto 1.889            altura en metros (la del juego: 1,7 / escala 0,9)
        --girth 1.0             corpulencia (1 = humano de referencia)
        --color "#rrggbb"      tinta principal
        --color2 "#rrggbb"     tinta secundaria
        --render               ademas deja PNG de la mano en reposo y en el tajo

MEDICIONES QUE IMPRIME (y que hay que LEER, no suponer)
------------------------------------------------------
poligonos, vertices, huesos, vertices por hueso de dedo, anillo y banda de apoyo
en hombro/codo/cadera, tiempos de build, y las tres comprobaciones de textura.

EL NUMERO QUE NO SE PUEDE ELEGIR: LA ZANCADA
--------------------------------------------
`tests/test_fase71_clips.gd` exige que el clip de marche cumpla
`zancada * 2 / duracion == ArbolAnimacion.VELOCIDAD_CLIP` (1,4264) y que el
ciclo dure 1,5 s exactos. Como la zancada sale de la pierna real
(`ZANCADA_POR_PIERNA * pierna` en `tools/animar_clips.py`) y la duracion sale de
la zancada, la pierna tiene que medir lo que mide. De ahi `ANCAJO_Z = 0.098` y
`CADERA_Z = 0.950`: 0,8519 m de pierna. No es un gusto, es la solucion de
`2 * 0,628 * pierna * 2 / 1,5 = 1,4264`. Si se cambia, la 71 se pone en rojo y
avisa de que el pie patina.
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

import bpy  # type: ignore
import numpy as np  # type: ignore
from mathutils import Matrix, Vector  # type: ignore

# El motor de clips ya esta escrito, medido y verificado
# (`tests/test_fase71_clips.gd`): se USA, no se reescribe. Se le cambia una sola
# cosa, la constante `ORDEN`, que es la lista con la que el escritor recorre los
# huesos al poner una clave. Con los catorce de dedos dentro, en orden de
# jerarquia (un hijo jamas puede escribirse antes que su padre).
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import animar_clips as AC  # type: ignore

# ---------------------------------------------------------------------------
# Proporciones. Units: metros, Z arriba, suelo en 0, el personaje mira al -Y.
#
# LAS PROPORCIONES DE LOS 19 HUESOS SON LAS DE `tools/rig.py` (PROP), y no son un
# gusto: son las que miden las proporciones de los seis `.glb` que ya tenian,
# y de las que salen la zancada, el piso de la cadera y el alto que la tabla de
# anclajes da por bueno. Lo UNICO que se toca es la altura del tobillo
# (0,098 en vez de 0,10), y es por el numero de arriba: con 0,10 la pierna mide
# 0,850 y la velocidad de viaje del clip sale 1,4152 en vez de 1,4264 (el techo
# del test es 0,02 de error, y con 0,10 se come 0,011 de los 0,020).
#
# OJO con la trampa de AGENTS.md: en espacio de HUESO el eje vertical es el Y
# local (el hueso apunta hacia su cola y su Y local es su propio largo). Por eso
# bajar la cadera en un clip es `location.y`, no `location.z`. Aqui, en cambio,
# se escriben matrices ABSOLUTAS (que es lo que hace `AC.Escritor`), y en el
# espacio del esqueleto el vertical sigue siendo Z. Son dos espacios distintos y
# no se mezclan.
PROP = {
    "pie_z": 0.038, "toe_y": -0.240, "toe_z": 0.026,
    "tobillo_z": 0.098, "rodilla_z": 0.527, "cadera_z": 0.950, "cadera_x": 0.100,
    "cintura_z": 1.100, "pecho_z": 1.300, "cuello_z": 1.500,
    "cabeza_z": 1.620, "cima_z": 1.8889,
    "hombro_z": 1.450, "hombro_x": 0.170, "hombro_in_x": 0.050,
    "codo_z": 1.125, "codo_x": 0.227,
    "muneca_z": 0.928, "muneca_x": 0.262,
    "pie_x": 0.110, "punta_x": 0.110,
}

## Angulo del brazo en la pose de la MALLA, en radianes desde la vertical. Es la
## pose en la que se construye la geometria y en la que queda el bind, y por eso
## aqui si es un dato del asset: 0,17 son 10 grados, una A relajada. Los clips
## no dependen de este numero (ellos escriben direcciones absolutas), asi que
## un modelo con los brazos mas abiertos no sale raro al animarlo.
BRAZO_REPOSO: float = 0.17

## Escalar final: la malla se mide contra el ALTO pedido y el esqueleto se
## escala con ella, para que las proporciones y la zancada no cambien.
ALTO: float = 1.8889

## Corpulencia. Multiplica los radios de la malla y el grosor de los huesos, no
## las longitudes: un guerrero es mas ancho, no mas alto.
GIRTH: float = 1.0

## Cuantos frames lleva cada clip. Lo rellena `main` antes de escribir cada uno,
## y lo usa `_tabla_dedos` para saber en que punto del clip va el agarre (el
## reloj de la escena NO sirve: ver ahi).
TOTAL_FRAMES: dict = {}

## Los cinco dedos de cada mano, en el orden en que se dibujan.
DEDOS: tuple = ("pulgar", "indice", "medio", "anular", "menique")
## La abreviatura de cada dedo: la que sale en las tablas de flexion y en el
## informe. Una letra, porque el informe tiene que caber en una linea.
DEDOS_ABREV: dict = {"pulgar": "T", "indice": "I", "medio": "M",
                     "anular": "A", "menique": "N"}

## Orden de escritura de los 33 huesos: los 19 del juego y los 14 de dedos. Un
## hijo NUNCA puede escribirse antes que su padre (`AC.Escritor.poner` lee la
## pose del padre), asi que los dedos van justo detras de su `Hand`.
ORDEN_BASE: tuple = ("Hips", "Spine", "Chest", "Neck", "Head",
                     "Shoulder.L", "UpperArm.L", "LowerArm.L", "Hand.L",
                     "Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R",
                     "Thigh.L", "Shin.L", "Foot.L",
                     "Thigh.R", "Shin.R", "Foot.R")

## Sufijo de los tres huesos de cada falange. El juego no lee ninguno (el
## paper-doll cuelga de `Hand.L`/`Hand.R`), asi que la convencion es libre; se
## deja legible porque los.medidores los nombran.
FALANGES: tuple = ("1", "2", "3")

## Fraccion de cada hueso que es BANDA DE APOYO: el 12% de cada punta. Los
## vertices de ahi van con el 100% de su hueso, y el anillo DEL EJE va 50/50 con
## el vecino. Ese par (banda + loop) es lo que evita que el codo se aplaste.
BANDA: float = 0.12


def orden_completo() -> list:
    """`ORDEN` de `animar_clips` con los catorce de dedos dentro."""
    out: list = []
    for nombre in ORDEN_BASE:
        out.append(nombre)
        if nombre == "Hand.L" or nombre == "Hand.R":
            lado = "." + nombre.split(".")[1]
            for dedo in DEDOS:
                for f in FALANGES:
                    out.append("%s.%s%s" % (dedo, f, lado))
    return out


# ---------------------------------------------------------------------------
# La mano: donde se decide si esto vale o no.
#
# Marco canonico de la mano, en metros desde la muneca:
#   Y = hacia la punta de los dedos (la MISMA direccion que el hueso `Hand`)
#   X = hacia el pulgar
#   Z = dorsal (el dorso de la mano, la cara que se ve desde fuera)
# Mano izquierda: X = -Y_mundo (el pulgar adelante), Y = la direccion del hueso
# (hacia abajo), Z = X x Y, que sale hacia +X = el lado de fuera = el dorso.
# La derecha es el espejo, y por eso el pulgar queda del mismo lado en las dos.
#
# OJO, Y AQUI ESTA LA TRAMPA QUE COSTO MEDIO DIA: el marco tiene que ser
# DERECHO (X x Y = Z) para que el pulgar y el dorso caigan en el lado que
# corresponde a cada mano. Con el pulgar adelante y los dedos ABAJO, la mano
# izquierda sale deredocha y la derecha sale zurda. Aqui lo que se hizo es
# dejar el marco como esta y negar la Y de TODOS los datos (nudillos, palma,
# direccion de la falange), porque negar el eje de un marco derecho lo
# convierte en izquierdo y habria que negar el dorso de una de las dos manos. Con
# los datos en +Y, las dos manos salen con el pulgar adelante. La version
# anterior tenia los datos en -Y con el marco en +Y: la malla salia pegada al
# antebrazo mirando al reves y los dedos se median a 135 grados de curl con la
# mano quieta, porque el hueso `Hand` apuntaba para un lado y la malla para otro.
#
# Longitudes de falange en metros, de proximal a distal. Medidas sobre una mano
# de 1,89 m de cuerpo: la punta del medio queda a 19,3 cm de la muneca, y el
# pulgar es el mas corto de todos aunque parezca el mas largo.
# El segundo elemento de cada fila es el DIAMETRO de cada falange (el anillo es
# el diametro, y por eso se aplica partido por dos). Y EL DEDO TENIA QUE SER MAS
# GRUESO, por dos razones distintas y las dos medidas en el render, no deducidas:
#   - con 0,0108 de radio el dedo sale de 11 mm de diametro, que es un alambre;
#   - con los numeros ya corregidos (19 mm) el dedo seguia saliendo mal, y la
#     causa NO era el diametro sino que los cinco dedos SE TOCABAN: los nudillos
#     estaban a 1,5 cm uno de otro y un dedo de 2,2 cm se come al vecino. Un
#     dedo que se solapa con el suyo no se ve como un dedo, se ve como un palo.
#     Se arregla separando los nudillos (NUDILLO, abajo) y no engordando mas.
# Un dedo real mide de 18 a 20 mm en la base y 15 en la punta; aqui van un poco
# mas gordos porque el personaje se ve a 4 m y un dedo de verdad a esa distancia
# son tres pixeles de ancho.
FALANGE_M: dict = {
    "I": ((0.0455, 0.0265, 0.0205), (0.0205, 0.0180, 0.0148)),
    "M": ((0.0500, 0.0300, 0.0215), (0.0212, 0.0188, 0.0152)),
    "A": ((0.0450, 0.0280, 0.0200), (0.0199, 0.0174, 0.0144)),
    "N": ((0.0350, 0.0215, 0.0180), (0.0174, 0.0154, 0.0128)),
    "T": ((0.0330, 0.0270, 0.0210), (0.0227, 0.0196, 0.0160)),
}
## Offset del nudillo (el centro deltubo) desde la muneca, en el marco canonico:
## (X hacia el pulgar, Y hacia la punta). El pulgar sale de la base de la palma,
## mas cerca de la muneca y mas a un lado, y sale hacia el pulgar y no hacia la
## punta: por eso su primera falange va casi de travieso.
# (X hacia el pulgar, Y hacia la punta). LA Y ES MENOR O IGUAL QUE EL FINAL DE
# LA PALMA, y no por casualidad: con los nudillos mas alla del borde de la palma
# y la tapa de la palma enmedio, la palma tapa la primera falange entera y la
# mano se ve como una plancha con cuatro rayas grabadas en vez de como una mano
# con dedos. Los nudillos quedan DENTRO de la palma (que acaba en 0,086) y los
# dedos salen por el canto.
#
# Y LA X: los cuatro nudillos van repartidos por TODO el ancho de la palma (8,6
# cm), no apretados en los 4,6 cm de antes. Con 1,5 cm de separacion y dedos de
# 2,2 cm, los cuatro se tocaban de punta a punta y la mano se leia como un
# secante con cinco rayas. Medido: la palma mide 0,0432 de semiancho y los
# nudillos llegan a 0,035, o sea 8 mm de palma por fuera del dedo, que es lo que
# hace de verdad una mano.
NUDILLO: dict = {
    "M": (0.0080, 0.0800), "I": (0.0350, 0.0750), "A": (-0.0090, 0.0790),
    "N": (-0.0350, 0.0690), "T": (0.0340, 0.0300),
}
## Direccion del pulgar en el marco canonico (normalizada). Apunta a un lado y
## algo hacia la punta; los otros cuatro van exactamente por -Y. A 53 grados del
## eje de los dedos, que es lo que hace la CMC de un pulgar de verdad: con los
## 38 de antes el pulgar salia como un palo pegado al lado de la mano, y en el
## render de espaldas se leia como un sexto dedo recto.
DIR_PULGAR: Vector = Vector((0.80, 0.60, 0.0)).normalized()
## Cuanto se abren los fingers en la base de cada dedo (rad). Los cuatro dedos se
## abren en abanico hacia el pulgar, no en linea: sin esto los cinco dedos
## nacen del mismo punto y la mano se lee como un guante.
##
## Y EL ABANICO BAJO, PORQUE SE ABRE EN EL EJE QUE NO SE VE. El abanico va en el
## marco canonico en X, y el X canonico es la Y del mundo (el pulgar mira al
## frente). O sea que abrir los dedos los reparte de ANTES a ATRAS, y de frente
## —que es como se mira el personaje— eso se ve como una mano clavada en la
## cadera con los dedos en abanico hacia el otro muslo. Con los nudillos ya
## separados (arriba), el abanico se puede bajar a la mitad: los dedos se leen
## separados sin abrirse en una escoba.
ABANICO: dict = {"I": 0.105, "M": 0.025, "A": -0.070, "N": -0.165, "T": 0.0}
## Semiancho de la palma en la muneca y en la linea de los nudillos.
PALMA: tuple = (0.0335, 0.0440)
## Grosor (semialto) de la palma: la palma es una placa, no un cilindro.
GROSOR_PALMA: float = 0.0225
## Radio del tubo de cada falange en la union y en la punta, y su aplanado
## (una falange es mas alta que ancha).
APLANADO: float = 0.86

## RESPIRACION DE LA MANO, en radianes por articulacion (MCP, PIP, DIP). Es lo
## que separa "una mano" de "un puno de madera", y son los numeros que se
## miran en el render, no los que se deducen.
##
## Reposo: la mano relajada de una persona cuelga con los dedos en curva, no
## rectos ni en puño. 22/32/18 es una curva suave de la que se lee la falange.
REPOSO_MANOS: dict = {"I": (0.42, 0.64, 0.34), "M": (0.45, 0.68, 0.36),
                      "A": (0.45, 0.68, 0.36), "N": (0.50, 0.72, 0.38),
                      "T": (0.28, 0.32, 0.24)}
## Puño cerrado completo: como agarra la mano. Mas que esto y sale un nudillo
## de hierro; menos y los dedos nodishan nada.
PUNO: dict = {"I": (1.02, 1.32, 0.68), "M": (1.05, 1.36, 0.70),
              "A": (1.05, 1.36, 0.70), "N": (1.08, 1.40, 0.72),
              "T": (0.72, 0.86, 0.54)}
## Agarre del tajo: casi puño pero con la flexion repartida, que es como
## agarra de verdad alguien que va a dar un tajo.
AGARRE: dict = {"I": (0.92, 1.32, 0.66), "M": (0.95, 1.36, 0.68),
                "A": (0.95, 1.36, 0.68), "N": (0.98, 1.40, 0.70),
                "T": (0.66, 0.86, 0.52)}
## Cuarta fibra de flexion: el pulgar se opone, no se dobra igual.
## En cada mano el pulgar va al lado OPUESTO, porque el pulgar esta en el lado
## del indicador en las dos (por eso el "dedo gordo" es el mismo lado del
## cuerpo en las dos manos), y su flexion es hacia el lado contrario al de los
## otros cuatro.


# ---------------------------------------------------------------------------
# Texturas
# ---------------------------------------------------------------------------
## Las imagenes se hornean por codigo con una funcion PERIODICA en las dos
## direcciones (ciclos enteros de seno/coseno sobre `u` y `v` en [0,1)). Eso es
## lo que hace que la textura ENVUELVA: el valor de la ultima columna es el
## que tendria la primera, y entre ellas solo hay un paso de pixel. Una textura
## con ruido libre (hash por pixel) NO envuelve: el salto entre la ultima
## columna y la primera sale a azar y a la derecha se ve una costura vertical.
## La comprobacion esta en `envuelve()` y su numero se imprime.
TEX_BASE: int = 1024
TEX_DATOS: int = 512

# ---------------------------------------------------------------------------
# REGIONES: de donde sale el material, y POR QUE NO HACE FALTA UN UV UNWRAP
# ---------------------------------------------------------------------------
## EL PROBLEMA QUE ESTA TABLA RESUELVE, con numeros medidos sobre la malla.
##
## La UV que escribe `Malla.vert` es `(u, v)` con u = ALREDEDOR del tubo y v = A
## LO LARGO. Y aqui esta lo que hacia la textura anterior con eso: nada. La
## funcion de hornado era una funcion de (u, v) y aplicaba lo mismo al casco que
## al muslo. Medido sobre la malla construida:
##
##   - Spine, Chest y Neck tienen 364 vertices y TODOS con `v = 0.0000`. O sea
##     que el torso entero (el 15% de la superficie).sampleaba UNA fila de la
##     textura. La causa es que `v_acum` se inicializaba a 0 y no sevolatile...
##     se incrementaba nunca: el torso no tenia coordenada vertical.
##   - el pie tiene UN SOLO valor de u, 0.5. Los 137 vertices del pie.sampleaban
##     una columna.
##   - el brazo ocupa v de 0 a 0,567, la pierna de 0 a 0,513, la palma de 0 a
##     0,096, el dedo de 0 a 0,18 y el pie de 0,014 a 0,379: TODOS arrancan en
##     cero. O sea que el brazo, la pierna, la palma y los dedos se pisan la
##     textura unos a otros en la misma mitad de arriba. Por eso no se podia
##     ni distinguirlos: no era que el material fuera malo, es que sharing UV no
##     deja poner dos materiales.
##
## El reparto: cada parte se lleva su propia FRANJA VERTICAL de la textura (una
## "banda"), y su `v` se reescala de su longitud de arco a esa franja. Las
## bandas no llegan ni al 0 ni al 1, de modo que el borde superior y el
## inferior de la imagen son la MISMA fila (el guardarrail) y la textura sigue
## envolviendo pixel a pixel. Y dentro de cada banda, la `u` (que es la
## direccion alrededor del tubo) reparte las sub-regiones: el peto de delante y
## la tela de atras son el mismo rectangulo con dos colores.
##
## Lo que esto compra, y es lo que no se puede comprar de otra forma sin un
## unwrap: la piel del muslo, la piel mas curtida de la mano, la uña, el cuero
## de la bota, el metal del casco y el forro de debajo son seis materiales en
## una sola imagen de 1024, con las costuras en su sitio.
BANDAS: dict = {
    # (inicio, fin) en fraccion de la altura de la textura.
    "torso":  (0.030, 0.170),   # la columna, de la pelvis al cuello
    "cabeza": (0.190, 0.300),   # el casco y la cara
    "brazo":  (0.320, 0.450),   # los dos brazos, del hombro a la muneca
    "pierna": (0.470, 0.620),   # las dos piernas, de la cadera al tobillo
    "mano":   (0.640, 0.720),   # las dos palmas
    "dedo":   (0.740, 0.820),   # los treinta huesos de dedo
    "pie":    (0.840, 0.960),   # las dos botas
}

## LOS MATERIALES, en orden: el indice en esta lista es el valor de la mascara.
## `rug` y `met` van al canal G y al B del ORM (glTF: R oclusion, G rugosidad,
## B metal), y son los numeros que hay que mirar en el render, no los que
## corregiria un motor.
##
## LA PIEL NO ES EL MISMO MATERIAL QUE LA MANO, y esa es la mitad del encargo.
## Con un solo "piel" por todo el cuerpo, la mano es indistinguible del muslo y
## el personaje se ve de maniqui. Aqui la piel del brazo y la de la mano son
## dos entradas con dos rugosidades (0,66 y 0,76) y dos tonos, y la UÑA es una
## tercera, mas clara y mas pulida, que es lo que hace que una mano se lea como
## una mano a tres metros.
MATERIALES: tuple = (
    # (clave,           rug,   met,  grano,   tono de la superficie)
    ("metal",          0.32, 1.00, 0.055, 1.00),   # placas, peto, casco
    ("metal_oscuro",   0.42, 1.00, 0.070, 0.72),   # ribetes, cinturon, hebillas
    ("tela",           0.88, 0.00, 0.110, 0.62),   # ropa de debajo
    ("piel",           0.66, 0.00, 0.045, 1.00),   # brazo, pierna, cara
    ("piel_manos",     0.76, 0.00, 0.060, 0.88),   # palmas y dedos
    ("uña",            0.40, 0.00, 0.020, 1.00),   # la punta del distal
    ("cuero",          0.56, 0.00, 0.085, 0.85),   # botas, correas, cinturon
    ("suela",          0.80, 0.00, 0.130, 0.45),   # la planta del pie
    ("guarnicion",     0.90, 0.00, 0.095, 0.40),   # el forro entre placas
)
## Indice de cada material, para no escribir numeros sueltos por el codigo.
MAT: dict = {k: i for i, (k, _, _, _, _) in enumerate(MATERIALES)}
## Lo que se pinta en la franja de guardia (el 3% de arriba y el de abajo, que
## no es de nadie): el forro oscuro. Es lo que hace que la fila 0 y la fila
## 1023 sean IGUALES y la textura envuelva, sin trucos en la comprobacion.
MAT_GUARDIA: int = MAT["guarnicion"]

## La paleta por clase. NO son seis colores: son tres ROLES (metal, tela, cuero)
## y la piel, que es la misma en las seis porque son seis personas. Lo que hace
## que un guerrero se vea guerrero y un mago se vea mago no es el tono, es que
## la armadura del guerrero es acero mate con una sobreveste roja y la del mago
## es tela con filamentos, y para eso esta la mascara de materiales.
PALETAS: dict = {
    "guerrero": {"metal": "#8d8878", "metal_oscuro": "#4c463c",
                 "tela": "#a83a2c", "cuero": "#4a3524", "guarnicion": "#241d18",
                 "suela": "#33291d"},
    "arquero":  {"metal": "#7f6a4a", "metal_oscuro": "#463823",
                 "tela": "#3f7a45", "cuero": "#6b5334", "guarnicion": "#2b2519",
                 "suela": "#3d2f1c"},
    "clerigo":  {"metal": "#c9a227", "metal_oscuro": "#8a7420",
                 "tela": "#d8d4c6", "cuero": "#6a5a3a", "guarnicion": "#9c968a",
                 "suela": "#4a4030"},
    "mago":     {"metal": "#6a6f80", "metal_oscuro": "#3a3a48",
                 "tela": "#3a4a8f", "cuero": "#46365e", "guarnicion": "#241d33",
                 "suela": "#241d33"},
    "daguero":  {"metal": "#4d4653", "metal_oscuro": "#241a2a",
                 "tela": "#5a2a6e", "cuero": "#3a2a3e", "guarnicion": "#1b1520",
                 "suela": "#1b1520"},
    "bandido":  {"metal": "#6f6757", "metal_oscuro": "#3a352c",
                 "tela": "#6b5a34", "cuero": "#4e4028", "guarnicion": "#2a251c",
                 "suela": "#332c1e"},
}
## La piel es de las seis clases, no de cada una: un guerrero y un mago tienen
## la misma piel y lo que cambia es lo que llevan puesto.
PIEL: dict = {"piel": "#c08a63", "piel_manos": "#a76f49", "uña": "#e6bda9"}


## EL DESFASE DE `u` POR PARTE, Y POR QUE EL PIE NECESITA UNO.
##
## La textura envuelve en `u` en la columna 1024, que es la misma que la 0. Y
## para que envuelva de verdad, el material tiene que ser el MISMO a ambos lados
## de ese cierre. Si una region llega justo hasta `u = 0`, entonces en la
## columna 1023 hay un material y en la 0 hay otro, y la costura sale.
##
## Alguien lo va a notar en la uña y en la suela, porque son las dos unicas
## regiones que OURAN por el cierre: la uña empieza en `u = 0` (es el dorso del
## dedo, y el dorso es justo donde el anillo arranca) y la suela llega hasta
## `u = 1` (es la mitad de abajo del pie, y la mitad de abajo termina donde
## termina el anillo). Medido: 91 filas con salto en la mascara, todas ellas en
## esas dos bandas, y el cociente de envolvente del albedo subia a 1,25.
##
## La uña se arregla escribiendola como region que CRUZA el cierre, que es lo
## que hace `rect` con `u0 > u1`. La suela no se puede: ocupa media vuelta y
## cualquier media vuelta toca uno de los dos extremos. Asi que al pie se le
## gira la `u` 0,75, con lo que el cierre cae en mitad del empeine.
U_DESFASE: dict = {"pie": 0.75}


def _u_tex(parte: str, t: float) -> float:
    """La `u` del anillo (0..1 alrededor del tubo) con el desfase de la parte."""
    return (t + U_DESFASE.get(parte, 0.0)) % 1.0


def _v_tex(parte: str, frac: float) -> float:
    """La `v` de la malla (longitud de arco) reescalada a la banda de la parte.

    `frac` es la fraccion del recorrido del tubo, de 0 a 1. Escribir la banda
    aqui y no en la mascara es lo que hace que las dos cosas no se puedan
    desincronizar: si alguien mueve una banda, la malla va con ella.
    """
    lo, hi = BANDAS[parte]
    return lo + (hi - lo) * min(1.0, max(0.0, frac))


def _hex(s: str) -> tuple:
    s = s.lstrip("#")
    return (int(s[0:2], 16) / 255.0, int(s[2:4], 16) / 255.0,
            int(s[4:6], 16) / 255.0)


def _mezcla3(a: tuple, b: tuple, t) -> np.ndarray:
    """`a -> b` con el peso `t`, que puede ser un numero o una imagen."""
    if np.isscalar(t):
        return np.array([a[i] + (b[i] - a[i]) * float(t) for i in range(3)])
    out = np.empty(t.shape + (3,), dtype=np.float64)
    for i in range(3):
        out[..., i] = a[i] + (b[i] - a[i]) * t
    return out


def _pintar_mascara() -> np.ndarray:
    """La mascara de MATERIALES de la textura: un entero por pixel.

    Devuelve un array `TEX_BASE x TEX_BASE` con el indice de `MATERIALES` que le
    toca a cada punto de la imagen. Es lo que hace el trabajo de "saber que parte
    del cuerpo estoy pintando": cada banda se pinta con su material base y
    encima se pintan las sub-regiones en `u` (que es la vuelta del tubo) y en `v`
    (que es el recorrido).

    Y SE PUEDE DUMPAR, que es la unica manera de comprobar sin tener los ojos:
    `hornear_texturas` escribe `mascara.png` al lado del albedo, y ahi se ve si
    las regiones han salido donde tenia que salir. Un mapa de regiones que no se
    mira es un mapa de regiones que no se sabe si esta bien.

    ## LA ORIENTACION DE `u` Y POR QUE CADA PARTE TIENE LA SUYA.
    `Malla.anillo` recorre el anillo con `a = t * 2pi` y escribe `u = t * rep_u`,
    o sea `u_tex = t`. El angulo `a` depende del marco que le haya tocado a la
    parte, y el marco sale de `marco(eje)`. Medido:
      - torso y cabeza: `ex = X`, `ey = Y`, o sea `a = 0` es el costado
        izquierdo, `a = 2pi/4` la espalda, `a = 3pi/4` la derecha y `a = pi/2`
        el FRENTE. La cara esta en `u_tex = 0.75`.
      - pierna: `a = 0` la espalda, `a = pi/4` el lado de fuera, `a = pi/2` el
        frente y `a = 3pi/4` el interior.
      - brazo: `ex = +Y` (la espalda) y `ey` hacia fuera, o sea `a = 0` es la
        espalda del brazo y `a = pi/4` el lado de fuera.
      - palma: el anillo va como `x = rx*sin, z = ry*cos`, o sea `u_tex = 0` es
        el DORSO, `0.25` el pulgar, `0.5` la palma y `0.75` el menique.
      - dedo: `u_tex = 0` es el dorso del dedo y `0.5` la yema.
      - pie: `_perfil_d` devuelve la mitad de arriba del perfil y luego la
        planta, o sea `u_tex` de 0 a 0.5 es el empeine y de 0.5 a 1 la suela.
    """
    n: int = TEX_BASE
    m = np.full((n, n), MAT_GUARDIA, dtype=np.int16)

    def rect(parte: str, u0: float, u1: float, f0: float, f1: float,
             mat: int) -> None:
        """Un rectangulo en la banda de la parte.

        `f0`/`f1` son fracciones de la BANDA (0 = el principio del tubo, 1 = la
        punta) y `u0`/`u1` son fracciones de la vuelta completa. Con `u0 > u1`
        se pinta el trozo que cruza el cierre, que es lo que necesita el torso
        (el peto se abre en el 0,62 y se cierra en el 0,90, y el forro de los
        costados es lo que hay en medio).
        """
        lo, hi = BANDAS[parte]
        y0 = int(round((lo + (hi - lo) * f0) * n))
        y1 = int(round((lo + (hi - lo) * f1) * n))
        if y1 <= y0:
            y1 = y0 + 1
        if u1 > u0:
            x0, x1 = int(round(u0 * n)), int(round(u1 * n))
        else:
            x0, x1 = int(round(u0 * n)), n
            m[y0:y1, 0:x1] = mat
        if x1 <= x0:
            x1 = x0 + 1
        m[y0:y1, x0:x1] = mat

    # ---------------------------------------------------------------- torso
    # El PETO: metal por delante, del pecho a las caderas. Los limites NO son un
    # degradado: hay un RIBETE de metal oscuro de tres centesimas de banda
    # rodeando el peto por los cuatro lados, que es lo que hace que la
    # transicion se lea como el canto de una placa y no como una mancha.
    rect("torso", 0.0, 1.0, 0.0, 1.0, MAT["tela"])            # la base: tela
    rect("torso", 0.60, 0.90, 0.355, 0.905, MAT["metal_oscuro"])   # ribete
    rect("torso", 0.625, 0.875, 0.385, 0.875, MAT["metal"])        # la placa
    # El peto no es plano: dos canales verticales marcados, que es lo que hace
    # que un pecho de armadura se lea como dos pectorales y no como un carton.
    rect("torso", 0.744, 0.756, 0.40, 0.86, MAT["metal_oscuro"])
    # El CINTURON, en cuero, con la hebilla por delante. Va en la cintura real
    # (z = 1,100, que es `f = 0.338` de la banda) y es lo que separa la placa
    # de la faldar de abajo.
    rect("torso", 0.0, 1.0, 0.275, 0.375, MAT["cuero"])
    rect("torso", 0.695, 0.805, 0.285, 0.365, MAT["metal_oscuro"])  # hebilla
    # La FALDA de placas, por delante, de la cintura al pelvis.
    rect("torso", 0.60, 0.90, 0.055, 0.265, MAT["metal_oscuro"])
    rect("torso", 0.625, 0.875, 0.075, 0.245, MAT["metal"])
    # El FORRO asoma por encima de la placa (el cuello y el hombro) y por los
    # costados, que es lo que hace que la armadura parezca puesta encima.
    rect("torso", 0.0, 1.0, 0.915, 1.0, MAT["guarnicion"])
    rect("torso", 0.0, 0.595, 0.36, 0.91, MAT["tela"])
    rect("torso", 0.905, 1.0, 0.36, 0.91, MAT["tela"])

    # --------------------------------------------------------------- cabeza
    # CASCO: metal por la corona y por los costados, con la CARA de piel al
    # descubierto. Un casco que se baja de mas es una mascara de robot, y uno
    # que no baja nada es un huevo metalico; la linea del casco va por el
    # browser, mas baja en la frente que en la nuca, que es como se pone de verdad un yelmo.
    rect("cabeza", 0.0, 1.0, 0.0, 1.0, MAT["piel"])
    rect("cabeza", 0.0, 1.0, 0.615, 1.0, MAT["metal"])        # la corona
    rect("cabeza", 0.0, 0.60, 0.545, 0.635, MAT["metal"])      # nuca y lateral
    rect("cabeza", 0.90, 1.0, 0.545, 0.635, MAT["metal"])
    rect("cabeza", 0.60, 0.90, 0.475, 0.545, MAT["metal_oscuro"])   # visera
    # La nariz, que es lo unico que separa una cara de una bola: una tira de
    # metal en el eje de la cara, de la visera a la boca.
    rect("cabeza", 0.740, 0.760, 0.185, 0.480, MAT["metal_oscuro"])
    # La boca y la barbilla, en piel curtida, que es donde la cara se ensucia.
    rect("cabeza", 0.660, 0.840, 0.075, 0.175, MAT["piel_manos"])

    # ---------------------------------------------------------------- brazo
    # PIEL por todo el brazo, con dos cosas puestas encima: el PAULDRON de metal
    # sobre el deltoide y la MANOPLA de cuero en la muneca. El ribete entre los
    # dos es lo que hace que no parezcan dos manchas.
    rect("brazo", 0.0, 1.0, 0.0, 1.0, MAT["piel"])
    rect("brazo", 0.0, 1.0, 0.165, 0.195, MAT["metal_oscuro"])  # canto del pauldron
    rect("brazo", 0.0, 1.0, 0.195, 0.195 + 0.0001, MAT["metal_oscuro"])
    rect("brazo", 0.0, 1.0, 0.0, 0.165, MAT["metal"])
    # El pauldron no es liso: una costura de cuero en diagonal.
    rect("brazo", 0.0, 0.16, 0.0, 0.165, MAT["cuero"])
    rect("brazo", 0.84, 1.0, 0.0, 0.165, MAT["cuero"])
    rect("brazo", 0.0, 1.0, 0.775, 0.805, MAT["metal_oscuro"])  # boca de la manopla
    rect("brazo", 0.0, 1.0, 0.805, 0.985, MAT["cuero"])

    # --------------------------------------------------------------- pierna
    # PIEL con la BOTA de cuero desde mas abajo de la rodilla, y una RODILLERA
    # de metal en la rodilla, que es la que esconde la articulacion.
    rect("pierna", 0.0, 1.0, 0.0, 1.0, MAT["piel"])
    rect("pierna", 0.0, 1.0, 0.775, 0.805, MAT["cuero"])       # boca de la bota
    rect("pierna", 0.0, 1.0, 0.805, 1.0, MAT["cuero"])
    rect("pierna", 0.0, 1.0, 0.495, 0.605, MAT["metal_oscuro"])  # rodillera
    rect("pierna", 0.0, 1.0, 0.515, 0.585, MAT["metal"])
    # Dos correas cruzadas sobre la espinilla, que es lo que hace que una bota
    # alta se lea como una bota alta y no como una manga de cuero.
    rect("pierna", 0.0, 1.0, 0.700, 0.735, MAT["cuero"])
    rect("pierna", 0.0, 1.0, 0.735, 0.770, MAT["cuero"])

    # ----------------------------------------------------------------- mano
    # PIEL CURTIDA, que es un material distinto del brazo, y con la palma (u de
    # 0.38 a 0.62) todavia mas curtida todavia. La correa de la muneca, cuero.
    rect("mano", 0.0, 1.0, 0.0, 1.0, MAT["piel_manos"])
    rect("mano", 0.38, 0.62, 0.20, 1.0, MAT["cuero"])
    rect("mano", 0.0, 1.0, 0.0, 0.155, MAT["cuero"])          # muneca
    rect("mano", 0.0, 1.0, 0.155, 0.185, MAT["metal_oscuro"])  # hebilla

    # ----------------------------------------------------------------- dedo
    # PIEL CURTIDA, y la UÑA en el dorso de la falange distal. La uña es lo que
    # hace que se lean cinco dedos y no cuatro: es la unica parte del cuerpo que
    # tiene una forma rectangular con las esquinas romas, y el ojo la busca.
    rect("dedo", 0.0, 1.0, 0.0, 1.0, MAT["piel_manos"])
    # La uña CRUZA el cierre (u0 > u1), porque el dorso del dedo es justo donde
    # el anillo empieza. Ver `U_DESFASE`.
    rect("dedo", 0.790, 0.210, 0.795, 1.0, MAT["uña"])
    rect("dedo", 0.760, 0.240, 0.760, 0.795, MAT["piel_manos"])   # cutis
    
    # ------------------------------------------------------------------ pie
    # CUERO (la bota) y SUELA, que es un material mas oscuro y mas rugoso. Sin
    # la suela separada el pie sale como un calcetin de cuero.
    # OJO: la suela va de 0,25 a 0,75, no de 0,5 a 1. Con el desfase de 0,75 del
    # pie, la planta (que en el anillo es la mitad de 0,5 a 1) cae ahi. Sin el
    # desfase la suela llegaba al cierre y la textura no envolvia.
    rect("pie", 0.0, 1.0, 0.0, 1.0, MAT["cuero"])
    rect("pie", 0.25, 0.75, 0.26, 1.0, MAT["suela"])           # la planta
    rect("pie", 0.0, 1.0, 0.90, 1.0, MAT["suela"])             # la puntera
    # La tira del empeine, que separa la bota del cuero liso.
    rect("pie", 0.62, 0.75, 0.0, 0.40, MAT["cuero"])
    return m


def _mezcla_por_material(mascara: np.ndarray, color: np.ndarray,
                         tono: np.ndarray) -> np.ndarray:
    """Tinte la mascara de color por material, en vez de por posicion.

    `color` es `TEX_BASE x TEX_BASE x 3` ya con el detalle multiplicado, y esto
    solo le pasa el TONO que le toca a cada pixel segun su material. Es la
    diferencia entre "una textura" y "una textura con un material en cada parte".
    """
    out: np.ndarray = color.copy()
    for i, (_clave, _rug, _met, _gran, t) in enumerate(MATERIALES):
        sel: np.ndarray = mascara == i
        if not sel.any():
            continue
        out[sel] *= t
    return out


def hornear_texturas(color: str, color2: str, semilla: int,
                     clase: str = "guerrero") -> dict:
    """Albedo, normal y ORM (occlusion/roughness/metallic) horneados.

    LA REGLA INNEGOCIABLE DE ESTA FUNCION: todo harmónico tiene el numero de
    ciclos ENTERO en U y en V. Por eso la imagen es periódica pixel a pixel y
    `envuelve` da verde. Un unico armónico con frecuencia decimal, o un
    `np.random`, y la costura vuelve a salir en pantalla; ya se cobro una vez
    (la nota de `onda` de mas abajo).

    Lo que ha cambiado respecto a la version anterior: ya no se pinta con tres
    senoidales globales. Se pinta con una MASCARA DE MATERIALES (`_pintar_mascara`)
    que sabe que parte del cuerpo es cada pixel, y el color, la rugosidad, el
    metal y el relieve salen de ahi. La funcion de (u, v) que habia antes seguia
    siendo correcta como funcion: lo que no podia era saber si estaba pintando
    un casco o un muslo.

    `semilla` desplaza las fases: dos modelos con la misma semilla salen
    identicos (determinista, como el resto del pipeline).
    """
    informe: dict = {}
    n: int = TEX_BASE
    # Rejilla de coordenadas periodicas. `k` es el numero de ciclos: entero, y
    # por eso la senoide de `k` cabe exacta en la imagen.
    v_tex, u_tex = np.meshgrid(np.arange(n) / float(n),
                               np.arange(n) / float(n), indexing="ij")

    def onda(ku: int, kv: int, ph: float) -> np.ndarray:
        """Un armónico con k ciclos en U y m ciclos en V, LOS DOS ENTEROS.

        Y aqui hay la trampa, y la pago ahora y no mas tarde: la primera
        version multiplicaba la frecuencia de V por un factor decimal
        (`f * k * v`), y con eso V salia con 2,22 ciclos y la textura NO
        ENVOLVIA en vertical: la costura salia a lo largo de todo el cuerpo, en
        horizontal, y la comprobación la cazó en el primer build (cociente 11,9
        contra 1,0 en horizontal). Un numero decimal en un producto parece
        inofensivo y aqui era exactamente el fallo.
        """
        return np.sin(math.tau * (ku * u_tex + kv * v_tex) + ph)

    fase: float = semilla * 0.618
    pal: dict = dict(PALETAS.get(clase, PALETAS["guerrero"]))
    pal.update(PIEL)

    # ------------------------------------------------------------- LA MASCARA
    mascara: np.ndarray = _pintar_mascara()

    # EL BORDE DE CADA REGION, y sale gratis. Donde dos materiales se tocan hay
    # un canto: ahi va el desgaste mas claro en las placas y la mugre en las
    # juntas. Se saca comparando la mascara con ella misma desplazada un pixel,
    # y se ENGORDA tres pixeles, porque a un pixel el canto sale como un pelo de
    # 1024 de la imagen y a cuatro metros no se ve. `np.roll` da la vuelta, asi
    # que el borde tambien envuelve.
    borde: np.ndarray = np.zeros((n, n), dtype=bool)
    for _paso in range(3):
        borde |= (mascara != np.roll(mascara, 1, axis=0))
        borde |= (mascara != np.roll(mascara, 1, axis=1))
    es_metal: np.ndarray = ((mascara == MAT["metal"])
                            | (mascara == MAT["metal_oscuro"]))
    es_piel: np.ndarray = ((mascara == MAT["piel"])
                           | (mascara == MAT["piel_manos"]))
    es_cuero: np.ndarray = ((mascara == MAT["cuero"])
                            | (mascara == MAT["suela"]))

    # ------------------------------------------------------------- EL DETALLE
    # Tres octavas de grano periodico, y el amplitud sale del material: por eso
    # los cuatro canales del ORM y el relieve se pintan con la MISMA mascara.
    # OJO con la tercera octava: `onda(97, 71)` son 71 ciclos en V sobre 1024,
    # o sea 14 pixeles por ciclo, y ahi ya esta al borde de la muesca. Se bajo a
    # 61/49 (16 y 20 pixeles) por lo mismo que los poros de la piel: por debajo
    # de ~12 pixeles por ciclo la senoidal describe la grilla, no la forma.
    #
    # Y ESTA ES LA QUE HACIA QUE LA PIEL SALIERA A PANA, y no era la
    # frecuencia sino que el "grano" NO ERA RUIDO. Las tres octavas guardaban
    # siempre la misma relacion 23/17, 47/31, 97/71, o sea 1,35:1 las tres. Tres
    # senoidales con la misma relacion se SUMAN en una rejilla coherente, y una
    # rejilla coherente es un rayado, no un grano. Como el UV del cuerpo es un
    # tubo, la U da la vuelta: 23 ciclos en la circunferencia son 23 lineas
    # verticales a lo largo del miembro. Eso es la pana, y se veía en el render
    # como acanalado de gabardina.
    #
    # EL GRANO TIENE QUE SER INCOHERENTE, y la forma de conseguirlo sin ruido
    # aleatorio (que rompe el ENVUELVE) es ROMPER LA RELACION de cada octava:
    # si los pares (ku, kv) no comparten proporcion, no se alinean y el conjunto
    # se ve como grano. Se eligieron relaciones distintas a proposito: 1,35 /
    # 1,62 / 1,15 / 1,25.
    grano: np.ndarray = (0.42 * onda(23, 17, fase)
                         + 0.28 * onda(47, 29, fase * 2.0)
                         + 0.18 * onda(61, 53, fase * 3.0)
                         + 0.12 * onda(89, 71, fase * 5.0))
    # La PIEL tiene poros, que son una frecuencia mas alta y mas fuerte que el
    # grano general. En la version anterior no habia poros porque no habia
    # material: la "piel" era la misma senoidal que el casco.
    #
    # Y ACA ESTA LA TRAMPA QUE HIZO QUE LA PIEL SALIERA A PANA. Los poros
    # estaban en `onda(149, 113)`: 113 ciclos en V sobre 1024 pixeles, o sea
    # nueve pixeles por ciclo, y a esa relacion la senoidal ALIASEA en vez de
    # leerse como poro. Peor: el UV es en bandas horizontales, asi que un
    # ciclo en V es una linea a lo largo del miembro, y en un brazo vertical eso
    # es una pana vertical. En el render la piel salia acanalada como tela de
    # gabardina.
    #
    # La frecuencia va medida contra la RESOLUCION, no contra lo que "parece"
    # un poro: menos de ~12 pixeles por ciclo la senoidal deja de describir la
    # forma y empieza a describir la grilla. 53 y 89 ciclos dan 19 y 11 pixeles,
    # que ya es detalle y no muesca.
    poros: np.ndarray = onda(53, 47, fase * 1.3) * 0.5 + onda(89, 79, fase) * 0.5
    # La TELA tiene trama: dos redes perpendiculares, que es un producto de dos
    # senoidales y sale con el cruce caracteristico del tejido.
    # CON DOS FASES DISTINTAS, y no es cosquillaje: con `fase` en los dos factores
    # y semilla 0 (el guerrero) la fase vale 0, los dos senos son 0 y la trama
    # entera es 0, o sea que el guerrero se queda SIN COSTURAS y el arquero si
    # las tiene. Un material que solo existe para una de las seis clases.
    # 29 ciclos, no 61. Con 61, y como el UV del torso es un tubo, la tunicca
    # salia a 61 rayitas verticales verticales: una camisa a rayas de oficina.
    # Una trama de tela tiene que leerse como TEJIDO, y a 61 lo que se lee es
    # un rayado. Bajarla a 29 la deja como textura de ropa y no como diseño.
    trama: np.ndarray = (np.sin(math.tau * 29.0 * u_tex + fase + 0.70)
                         * np.sin(math.tau * 29.0 * v_tex + 1.90))
    # El METAL va cepillado: rayas fines en una sola direccion, y ademas mas
    # fuerte en U que en V, que es como se cepilla una placa.
    cepillado: np.ndarray = onda(139, 11, fase * 0.7)

    altura: np.ndarray = np.zeros((n, n), dtype=np.float64)
    for i, (_clave, _rug, _met, g, _t) in enumerate(MATERIALES):
        sel: np.ndarray = mascara == i
        if not sel.any():
            continue
        h: np.ndarray = 0.35 * grano
        if i in (MAT["piel"], MAT["piel_manos"]):
            h = h + 0.30 * poros
        elif i == MAT["tela"]:
            h = h + 0.38 * trama
        elif i in (MAT["metal"], MAT["metal_oscuro"]):
            h = h + 0.30 * cepillado
        altura = np.where(sel, h * (g / 0.055), altura)

    # LOS REMACHES: una rejilla de puntos, SOLO en el metal, y SOLO cerca del
    # borde de la placa. Un remache en mitad de una placa no se ve; un remache a
    # un centimetro del canto es exactamente donde se pone uno.
    rejilla: np.ndarray = (np.sin(math.tau * 41.0 * u_tex + 0.4)
                           * np.sin(math.tau * 41.0 * v_tex + 0.4))
    remache: np.ndarray = (rejilla > 0.965) & es_metal & borde
    altura = altura + np.where(remache, 0.55, 0.0)
    # LAS COSTURAS: el punteado de las dos redes, sobre cuero, y pegado al
    # canto. El cuero sin costuras es plástico, y la bota es de las cosas que
    # mas se miran.
    costura: np.ndarray = ((trama > 0.80) | (trama < -0.80)) & es_cuero & borde
    altura = altura - np.where(costura, 0.42, 0.0)

    # --------------------------------------------------------------- EL COLOR
    # El tono base de cada pixel sale de su material, y lo de encima es el
    # desgaste (mas claro en los cantos de metal) y la mugre (mas oscura en las
    # juntas). Son los dos numeros que hacen que una superficie se lea como
    # usada y no como pintada.
    base: np.ndarray = np.zeros((n, n, 3), dtype=np.float64)
    for i, (clave, _rug, _met, _g, t) in enumerate(MATERIALES):
        sel = mascara == i
        if not sel.any():
            continue
        c = _hex(pal[clave])
        base[sel] = [c[0] * t, c[1] * t, c[2] * t]
    # El desgaste del canto: el metal se pule donde se le toca, y ese es el
    # borde. +0.22 de luz es lo que hace que una placa tenga un canto.
    base += np.where((borde & es_metal)[..., None], 0.22, 0.0)
    # La mugre de la junta: en el borde, pero en la tela y el cuero, mas sucio y
    # mas oscuro. Es lo que hace que las piezas se lean como PUESTAS.
    mugre: np.ndarray = (borde & (es_cuero | ((mascara == MAT["tela"]))))[..., None]
    base -= mugre * 0.20
    # ACÁ ESTABA EL RAYADO, y costó tres pruebas encontrarlo. La línea era
    # `base *= (0.90 + 0.10 * onda(5, 3, ...))`: una senoidal DIAGONAL, aplicada
    # a TODA la imagen y no a un material. En la textura se veía como las
    # diagonales, y en el modelo se veía como pana vertical, porque el UV del
    # cuerpo es un tubo y una diagonal en el mapa se convierte en una línea a lo
    # largo del miembro. Con 5 ciclos en U daba 5 bandas anchas; sumadas al
    # grano de abajo salía el acanalado fino que se veía en el render.
    #
    # POR QUÉ UNA SENOIDAL DIAGONAL NO PUEDE HACER DE SOMBRA: describe una
    # rejilla, y una rejilla es un rayado, no una sombra. Para apagar y encender
    # hace falta algo que no tenga filas: se usa el valor del material, que ya
    # es un numero por region, con su propio tono.
    base += (0.04 * grano)[..., None]
    base = np.clip(base, 0.0, 1.0)

    # ------------------------------------------------------------------ NORMAL
    # El mapa normal sale de diferencias centrales de la altura, que ya lleva la
    # mascara dentro: los poros de la piel y la trama de la tela levantan su
    # normal y el casco no. Al ser la altura periodica, el mapa tambien lo es.
    dx = np.roll(altura, -1, axis=1) - np.roll(altura, 1, axis=1)
    dy = np.roll(altura, -1, axis=0) - np.roll(altura, 1, axis=0)
    # LA FUERZA DEL NORMAL, Y POR QUE NO PUEDE SER GRANDE. Con 2,6 el mapa sale
    # a 18 grados de inclinacion por pixel y el personaje se ve como un felpudo
    # de pana: en el render salen rayas longitudinales que parecen un fallo de
    # topologia (y lo son, pero de la textura). A 0,9 son 6 grados, que es
    # relieves de piel y de tela y no se ve de lejos. Es un numero de arte, pero
    # se MEDIO mirando el render, no seAlejandro de la matematica.
    fuerza = 0.9
    nrm = np.stack((-dx * fuerza, -dy * fuerza, np.ones_like(altura)), axis=-1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    nrm = nrm * 0.5 + 0.5

    # -------------------------------------------------------------------- ORM
    # glTF empaqueta oclusion en R, roughness en G y metallic en B. Y aqui, por
    # primera vez, los tres canales son POR MATERIAL: el casco va a rugosidad
    # 0,32 y metal 1; la piel a 0,66 y metal 0; el cuero a 0,56 y metal 0. Antes
    # los tres salian de una unica mascara de vetas global, que es la razon de
    # que el cuerpo entero pareciera el mismo material.
    rug = np.zeros((n, n), dtype=np.float64)
    met = np.zeros((n, n), dtype=np.float64)
    for i, (_clave, r_, m_, _g, _t) in enumerate(MATERIALES):
        sel = mascara == i
        if not sel.any():
            continue
        rug = np.where(sel, r_, rug)
        met = np.where(sel, m_, met)
    # La variacion: el desgaste del canto baja la rugosidad (el metal pulido
    # brilla mas) y la mugre la sube. Y el grano de la piel la sube un poco,
    # que es lo que hace que la piel no parezca plastico.
    rug -= np.where(borde & es_metal, 0.12, 0.0)
    rug += np.where(mascara == MAT["suela"], 0.10, 0.0)
    rug += 0.07 * np.abs(grano) * es_piel
    rug += 0.05 * np.abs(cepillado) * es_metal
    rug = np.clip(rug, 0.05, 1.0)
    # La oclusion: alta en general, y BAJA en el canto de cada region, que es
    # una junta y una junta es hueca. Sin esto las piezas se leen pegadas con
    # pegamento.
    ocl = np.clip(0.94 - 0.42 * borde - 0.10 * np.abs(grano)
                  - 0.16 * (mascara == MAT["guarnicion"]), 0.0, 1.0)
    orm = np.stack((ocl, rug, met), axis=-1)

    informe["albedo"] = _guardar(base, n, "albedo", srgb=True)
    informe["normal"] = _guardar(nrm, TEX_DATOS, "normal", srgb=False)
    informe["orm"] = _guardar(orm, TEX_DATOS, "orm", srgb=False)
    informe["mascara"] = _guardar_mascara(mascara)
    informe["regiones"] = _informe_regiones(mascara)
    informe["clase"] = clase
    return informe


def _guardar_mascara(mascara: np.ndarray) -> dict:
    """El mapa de regiones a PNG, para PODER MIRARLO.

    Sin esto, un mapa de materiales es una caja negra con numeros dentro: si la
    banda del torso se pinta en el sitio equivocado no se ve hasta que se
    renderiza el personaje entero, y para entonces ya se ha perdido el motivo.
    """
    n: int = mascara.shape[0]
    # Un color por material, chose de los indexados mas separados.
    # Un color por MATERIAL, en el MISMO orden que `MATERIALES`. Estaban
    # corridos una posicion (empezaban por un negro de mas) y el mapa salia con
    # la etiqueta cambiada: el mismo error de indice que delata cualquier tabla
    # de dos columnas.
    paleta: list = [(198, 202, 208), (86, 88, 96), (58, 132, 190),
                    (214, 158, 116), (168, 111, 73), (244, 214, 196),
                    (124, 82, 48), (52, 44, 38), (150, 30, 30)]
    px: np.ndarray = np.ones((n, n, 4), dtype=np.float32)
    for i, col in enumerate(paleta[:len(MATERIALES)]):
        sel = mascara == i
        if not sel.any():
            continue
        for ch in range(3):
            px[..., ch][sel] = col[ch] / 255.0
    img = bpy.data.images.new("gg_mascara", n, n, alpha=False)
    img.colorspace_settings.name = "sRGB"
    img.pixels.foreach_set(px.reshape(-1))
    img.update()
    ruta = os.path.join(TMP, "mascara.png")
    img.filepath_raw = ruta
    img.file_format = "PNG"
    img.save()
    return {"ruta": ruta, "lado": n}


def _informe_regiones(mascara: np.ndarray) -> list:
    """Cuanto ocupa cada material en la textura, en pixeles y en porcentaje.

    Es el numero que hay que mirar para saber si una region se ha pintado: si
    `uña` sale a 0,0% es que la banda del dedo no esta donde deberia, y eso se ve
    aqui sin tener que renderizar nada.
    """
    out: list = []
    total: int = mascara.size
    for i, (clave, rug, met, grano, tono) in enumerate(MATERIALES):
        pix: int = int((mascara == i).sum())
        out.append({"material": clave, "rugosidad": rug, "metalicidad": met,
                    "grano": grano, "tono": tono, "pixeles": pix,
                    "porcentaje": round(100.0 * pix / float(total), 3)})
    return out


def _guardar(arr: np.ndarray, lado: int, nombre: str, srgb: bool) -> dict:
    """Escribe la imagen a PNG y devuelve el informe, con la ENVOLTURA medida.

    LA COMPROBACION DE ENVOLTURA, y por que es esta: una textura que no
    envuelve tiene costura, y la costura no la caza ningun error de importacion
    ni ningun test: sale en pantalla y parece un fallo de arte. Lo que se mide
    es el salto entre la primera y la ultima columna (y fila). Si la textura
    envuelve, ese salto es del orden del gradiente de UN pixel, porque la senoide
    es continua a lo largo del borde. Si NO envuelve, el salto es un escalon y el
    cociente se dispara. Se imprime el cociente: 1 es perfecto.
    """
    h, w = arr.shape[0], arr.shape[1]
    px = np.ones((h, w, 4), dtype=np.float32)
    px[..., 0:3] = arr.astype(np.float32)
    img = bpy.data.images.new("gg_%s" % nombre, w, h, alpha=False)
    img.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
    img.pixels.foreach_set(px.reshape(-1))
    img.update()
    ruta = os.path.join(TMP, "%s.png" % nombre)
    img.filepath_raw = ruta
    img.file_format = "PNG"
    img.save()
    img.source = "FILE"
    img.filepath = ruta
    img.reload()
    img.pack()
    # El salto del cierre, medido sobre lo que se ha escrito de verdad.
    img.pixels.foreach_get(px.reshape(-1))
    a8 = px[..., 0:3].astype(np.float64)
    # RMS y no maximo: el maximo de una fila y el maximo de otra CAEN en sitios
    # distintos, y el cociente de maximos mide el ruido, no la costura. Con RMS
    # se comparan dos distribuciones del mismo tamano y el numero significa
    # algo. El suelo es el paso de cuantizacion del PNG (1/255): por debajo de
    # eso el cociente ya no distingue nada.
    CUANT: float = 1.0 / 255.0

    def rms(d: np.ndarray) -> float:
        return float(np.sqrt((d * d).mean()))

    salto_col = rms(a8[:, 0, :] - a8[:, w - 1, :])
    salto_fil = rms(a8[0, :, :] - a8[h - 1, :, :])
    paso_col = rms(a8[:, 1, :] - a8[:, 0, :])
    paso_fil = rms(a8[1, :, :] - a8[0, :, :])
    coc_x = salto_col / max(paso_col, CUANT)
    coc_y = salto_fil / max(paso_fil, CUANT)
    return {"ruta": ruta, "lado": w, "salto_col": salto_col,
            "salto_fil": salto_fil, "paso_col": paso_col, "paso_fil": paso_fil,
            "cociente_x": coc_x, "cociente_y": coc_y,
            "envuelve": bool(coc_x <= 1.15 and coc_y <= 1.15)}


#: Carpeta de trabajo de los PNG horneados. Fuera del repo: son intermedios.
TMP: str = "/tmp/gg_modelo_humano"


# ---------------------------------------------------------------------------
# Malla
# ---------------------------------------------------------------------------
class Malla:
    """Acumula vertices, caras, UVs y el peso de cada vertex.

    El peso es POR ANILLO, no por vertice suelto: cada anillo se crea diciendo
    que huesos lo mueven y con que peso, y asi el reparto sale exacto y
    auditable (y no de un `bone heat` que en headless no encuentra solucion).
    """

    def __init__(self) -> None:
        self.v: list = []
        self.uv: list = []
        self.f: list = []
        self.w: list = []          # lista de dict {hueso: peso} por vertice
        self.grupos: list = []     # (nombre_hueso, [indices]) para el informe

    def vert(self, p: Vector, u: float, v: float, pesos: dict) -> int:
        self.v.append(Vector(p))
        self.uv.append((u, v))
        self.w.append(dict(pesos))
        return len(self.v) - 1

    def quad(self, a: int, b: int, c: int, d: int) -> None:
        self.f.append((a, b, c))
        self.f.append((a, c, d))

    def tri(self, a: int, b: int, c: int) -> None:
        self.f.append((a, b, c))

    def anillo(self, centro: Vector, ex: Vector, ey: Vector, rx: float,
               ry: float, n: int, pesos: dict, rep_u: float, v0: float) -> list:
        """Un anillo de `n` vertices: elipse en el plano (`ex`,`ey`).

        El plano del anillo es perpendicular a la direccion del miembro, que es
        lo que hace que el LOOP de la articulacion se quede circular al girar el
        hueso. Un anillo en un plano inclinado se aplana y se ve el pliegue.
        """
        salida: list = []
        for i in range(n):
            t: float = i / float(n)
            a: float = math.tau * t
            p = centro + ex * (math.cos(a) * rx) + ey * (math.sin(a) * ry)
            salida.append(self.vert(p, t * rep_u, v0, pesos))
        return salida

    def perfil(self, puntos: list, m: Matrix, pesos: dict, rep_u: float,
               v0: float) -> list:
        """Anillo de un perfil 2D (pares (a,b) en el plano del anillo)."""
        salida: list = []
        n: int = len(puntos)
        for i in range(n):
            t: float = i / float(n)
            p = m @ Vector((puntos[i][0], puntos[i][1], 0.0))
            salida.append(self.vert(p, t * rep_u, v0, pesos))
        return salida

    def loftear(self, anillos: list, cerrado: bool = True) -> None:
        """Cosido de anillos consecutivos. Mismo numero de vertices o no: si no
        coinciden, se reparte por parametro (util para unir la palma con un
        dedo, que no comparten shape)."""
        for k in range(len(anillos) - 1):
            a = anillos[k]
            b = anillos[k + 1]
            na, nb = len(a), len(b)
            for i in range(na if cerrado else na - 1):
                j: int = (i + 1) % na
                if na == nb:
                    self.quad(a[i], a[j], b[j], b[i])
                else:
                    jj: int = int(round(((i + 1) % na) * nb / float(na)))
                    self.quad(a[i], a[j], b[jj % nb], b[i])

    def tapar(self, anillo: list, centro: Vector, pesos: dict, hacia: float,
              sentido: int = 1) -> None:
        """Tapa un anillo con un abanico desde su centro (extremos del cuerpo,
        dedos de manos y pies).

        `sentido` = +1 deja la normal hacia +eje (la tapa de arriba) y -1 hacia
        -eje (la de abajo). Importa: una tapa con el sentido equivocado se ve
        negra en Godot, que es un fallo de una sola cara y ocupa media malla.
        """
        c = self.vert(centro, 0.5, hacia, pesos)
        for i in range(len(anillo)):
            j: int = (i + 1) % len(anillo)
            if sentido >= 0:
                self.tri(c, anillo[i], anillo[j])
            else:
                self.tri(c, anillo[j], anillo[i])

    def invertir(self, desde: int, hasta: int) -> None:
        """Le da la vuelta a las caras `[desde, hasta)`.

        La mano derecha es el ESPEJO de la izquierda y un espejo invierte el
        sentido de la cara: sin esto, media malla se dibuja del reves, que en
        Godot sale negra.
        """
        for i in range(desde, hasta):
            a, b, c = self.f[i]
            self.f[i] = (a, c, b)

    def cuenta(self) -> dict:
        n: int = len(self.v)
        con_peso: int = sum(1 for w in self.w if w)
        return {"vertices": n, "triangulos": len(self.f),
                "con_peso": con_peso,
                "max_pesos": max((len(w) for w in self.w), default=0)}


## Marcos ortonormales de un tubo. `eje` es la direccion del miembro; los otros
## dos se eligen de forma DETERMINISTA (mismo `eje` -> mismo marco), porque si
## el marco gira solo entre anillos el tubo se retuerce y la UV se enrolla.
def marco(eje: Vector) -> tuple:
    d = eje.normalized()
    ref = Vector((0.0, 0.0, 1.0))
    if abs(d.dot(ref)) > 0.94:
        ref = Vector((1.0, 0.0, 0.0))
    ex = ref.cross(d).normalized()
    ey = d.cross(ex).normalized()
    return d, ex, ey


def pesos_banda(t: float, banda: float = BANDA) -> tuple:
    """Reparto del peso de un anillo en una articulacion.

    Devuelve `(w_propio, w_siguiente)`. Con `t` en [0,1] dentro del hueso:
    la punta de la cabeza (`t<0`) es 100% del hueso anterior, el anillo DEL EJE
    (`t=0` o `t=1`) es 50/50, y en la BANDA (`|t|` menor que `banda`) interpola
    de 50/50 a 100/0 con una curva suave.
    """
    def suave(x: float) -> float:
        x = min(1.0, max(0.0, x))
        return x * x * (3.0 - 2.0 * x)
    if t <= 0.0:
        return 0.0, 1.0
    if t >= 1.0:
        return 1.0, 0.0
    if t < banda:
        return 0.5 + 0.5 * suave(t / banda), 1.0 - (0.5 + 0.5 * suave(t / banda))
    if t > 1.0 - banda:
        k: float = 0.5 - 0.5 * suave((1.0 - t) / banda)
        return 1.0 - k, k
    return 1.0, 0.0


# ---------------------------------------------------------------------------
# Malla: torso, cabeza, piernas, brazos y las dos manos con dedos.
#
# La malla se construye con un `POSADO DE REPOSO` natural (brazos a 10 grados de
# la vertical, dedos extendidos) y en ese estado se hace el bind. Los clips
# escriben direcciones ABSOLUTAS, asi que la pose en la que se construyo no
# cambia nada de la animacion: solo decide como se ve el modelo sin animar.
def _perfil_d(w: float, top: float, n: int, suelo: float = 0.004) -> list:
    """Perfil en "D" para el pie: arco arriba y planta plana abajo.

    Una elipse con la base aplastada deja triángulos de area cero; esta no: los
    `n` puntos son `n/2` en el arco y `n/2` en la planta, y la planta es un
    segmento recto, que es exactamente lo que es la suela. `n` PAR, porque el
    loft entre anillos necesita el mismo número de puntos.
    """
    n2: int = n // 2
    pts: list = []
    for i in range(n2):
        a: float = math.pi * i / float(n2)          # de +X a -X por arriba
        pts.append((w * math.cos(a), suelo + (top - suelo) * math.sin(a)))
    for i in range(1, n2):
        t: float = i / float(n2)                     # de -X a +X por la planta
        pts.append((-w + 2.0 * w * t, suelo))
    return pts


## Secciones de la columna: (z, semiancho X, semiprofundidad Y). Los cortes
## no salen de una formula: salen de una persona de pie, y lo que importa es
## que el pecho sea mas ancho que la cintura y que el cuello entre bien.
## Vive FUERA de `construir_malla` porque `_brazo` y `_pierna` lo necesitan para
## decidir donde esconder la raiz de sus tubos (ver `_cabe_en_torso`).
def torso_secciones(p: dict) -> list:
    return [
        (0.845, 0.152, 0.112), (0.890, 0.158, 0.118),   # pelvis
        (p["cintura_z"], 0.134, 0.104),                 # 1.100 cintura
        (1.180, 0.146, 0.108),
        (p["pecho_z"], 0.176, 0.121),                   # 1.300 pecho
        (1.380, 0.190, 0.124), (p["cuello_z"], 0.186, 0.120),  # 1.500 hombros
        (p["cuello_z"], 0.176, 0.118),
        (1.560, 0.085, 0.082),                          # la nuca se estrecha de golpe
        (1.600, 0.062, 0.060),                          # cuello
    ]


def _cabe_en_torso(p: dict, z: float) -> tuple:
    """(semiancho, semiprofundidad) del torso a la altura `z`.

    Sin girth: quien llama lo multiplica. Sale de la MISMA tabla con la que se
    construye el torso, y no de numeros escritos a mano, para que cambiar esa
    tabla no deje la raiz de un brazo colgando por fuera del pecho.
    """
    secs: list = torso_secciones(p)
    for (z0, rx0, ry0), (z1, rx1, ry1) in zip(secs, secs[1:]):
        if z0 <= z <= z1:
            t: float = (z - z0) / (z1 - z0)
            return rx0 + (rx1 - rx0) * t, ry0 + (ry1 - ry0) * t
    if z < secs[0][0]:
        return secs[0][1], secs[0][2]
    return secs[-1][1], secs[-1][2]


def construir_malla(p: dict, g: float) -> tuple:
    """Devuelve (Malla, informe). `p` = proporciones en metros, `g` = girth."""
    m = Malla()
    inf: dict = {"loops": [], "dedos": {}, "dedos_loop": {}}
    def r(base: float) -> float:
        return base * (1.0 + (g - 1.0) * 0.85)

    # ---------------------------------------------------------------- torso
    torso: list = torso_secciones(p)
    # La columna del torso: la cadena de huesos que la deforma, en orden.
    cadena_torso = ["Hips", "Spine", "Chest", "Neck", "Head"]
    # Las "cortes" donde esta cada hueso (el 0.950 es la cadera). Los tramos de
    # fuera (0.845 -> 0.950 y 1.600 -> 1.889) son 100% de un solo hueso.
    cortes_torso = [0.845, p["cadera_z"], p["cintura_z"], p["pecho_z"],
                    p["cuello_z"], p["cabeza_z"], 1.889]

    def secciones_torso() -> list:
        """Anillos del torso, densos en las cuatro articulaciones."""
        out: list = []
        for (z0, rx0, ry0), (z1, rx1, ry1) in zip(torso, torso[1:]):
            # 3 intermedios + extremos; en los tramos cortos se afina el paso.
            pasos: int = max(2, int(round((z1 - z0) / 0.042)))
            for k in range(pasos):
                t: float = k / float(pasos)
                z: float = z0 + (z1 - z0) * t
                out.append((z, rx0 + (rx1 - rx0) * t, ry0 + (ry1 - ry0) * t))
        z, rx, ry = torso[-1]
        out.append((z, rx, ry))
        return out

    def peso_columna(z: float) -> dict:
        """Peso de un anillo del torso, por DONDE cae respecto de los cortes."""
        if z <= cortes_torso[0]:
            return {"Hips": 1.0}
        if z >= cortes_torso[-1]:
            return {"Head": 1.0}
        # Anchura de la banda de apoyo en la articulacion, en metros.
        for i in range(len(cadena_torso) - 1):
            a, b = cadena_torso[i], cadena_torso[i + 1]
            j: int = cortes_torso[i + 1]
            if z < j - 0.10:
                return {a: 1.0}
            if z <= j + 0.10:
                w: float = 0.5 + 0.5 * (z - (j - 0.10)) / 0.20
                return {a: 1.0 - w, b: w} if w < 1.0 else {b: 1.0}
        return {"Head": 1.0}

    # `v_acum` antes era 0 para siempre, y el torso entero acababa con
    # `v = 0.0000` en los 834 vertices: 15% de la superficie del personaje
    # muestreando UNA fila de la textura. Se acumula la longitud de arco y se
    # reescala a la banda del torso, que es lo que le da al peto su sitio.
    largo_torso: float = torso[-1][0] - torso[0][0]
    v_acum: float = 0.0
    prev: list = None
    for idx, (z, rx, ry) in enumerate(secciones_torso()):
        w = peso_columna(z)
        if idx > 0:
            v_acum += z - secciones_torso()[idx - 1][0]
        anillo = m.anillo(Vector((0.0, 0.0, z)), Vector((1.0, 0.0, 0.0)),
                          Vector((0.0, 1.0, 0.0)), r(rx), r(ry), N_TORSO, w,
                          3.0, _v_tex("torso", v_acum / largo_torso))
        if prev is not None:
            m.loftear([prev, anillo])
        prev = anillo
    m.tapar(prev, Vector((0.0, 0.0, torso[0][0] - 0.02)), {"Hips": 1.0}, -0.05, -1)

    # ---------------------------------------------------------------- cabeza
    # (z, semiancho, semiprofundidad, desplazamiento Y del anillo). El
    # desplazamiento es lo que hace la cara: sin el, la cabeza es un huevo y no
    # se le ve la cara a nadie.
    cabeza = [
        (1.600, 0.062, 0.060, 0.000), (1.650, 0.076, 0.082, -0.006),
        (1.700, 0.085, 0.098, -0.010), (1.755, 0.089, 0.104, -0.012),
        (1.805, 0.086, 0.101, -0.014), (1.845, 0.072, 0.086, -0.014),
        (1.872, 0.048, 0.058, -0.012), (1.8889, 0.018, 0.022, -0.010),
    ]
    prev = None
    for z, rx, ry, dy in cabeza:
        anillo = m.anillo(Vector((0.0, dy, z)), Vector((1.0, 0.0, 0.0)),
                          Vector((0.0, 1.0, 0.0)), r(rx), r(ry), N_TORSO,
                          {"Head": 1.0}, 2.0,
                          _v_tex("cabeza", (z - 1.60) / (1.8889 - 1.60)))
        if prev is not None:
            m.loftear([prev, anillo])
        prev = anillo
    m.tapar(prev, Vector((0.0, -0.010, 1.8925)), {"Head": 1.0}, 0.30, +1)

    # ---------------------------------------------------------------- brazos
    # Se llama a `brazo_pos` y no a una copia: la malla y el esqueleto tienen
    # que salir del MISMO numero, o el hueso se va de la piel (y ya se ha ido
    # una vez: ver la nota de `brazo_pos`).
    for lado, sg in (("L", 1.0), ("R", -1.0)):
        h, c, mu = brazo_pos(p, sg)
        _brazo(m, p, r, g, "." + lado, h, c, mu, N_MIEMBRO, inf)

    # ---------------------------------------------------------------- piernas
    for lado, sg in (("L", 1.0), ("R", -1.0)):
        s = "." + lado
        cadera = Vector((p["cadera_x"] * sg, 0.0, p["cadera_z"]))
        rodilla = Vector((p["pie_x"] * sg, 0.0, p["rodilla_z"]))
        tobillo = Vector((p["pie_x"] * sg, 0.0, p["tobillo_z"]))
        _pierna(m, p, r, g, s, cadera, rodilla, tobillo, inf)
    return m, inf


## Anillos intermedios de un tramo de miembro. Los extremos (0,03 / 0,08 y
## 0,93 / 0,97) son la BANDA DE APOYO, dentro del 12% de cada punta; el resto
## reparte la silueta. Son ONCE y no seis porque sobraba presupuesto (11.134
## triangulos de los 30.000 que permite la fase 49) y con seis el bulto del
## biceps y la pantorrilla salia a tres tramos rectos: el perfil se nota en la
## silueta antes que en la textura, y una silueta de seis tramos no la arregla
## un material.
T_MID: tuple = (0.030, 0.075, 0.140, 0.220, 0.320, 0.430, 0.540, 0.650,
                0.750, 0.845, 0.930, 0.970)
## Lo mismo para los dedos, que son cortos y no ganan nada con mas anillos.
# T_MID_DEDO: cuatro anillos pegados a cada punta y dos en el medio. Con solo
# tres anillos (uno a 0,10, otro a 0,50 y otro a 0,90) el unico anillo de la
# articulation es el del LOOP, y al doblar sale un PLIEG en angulo vivo: en el
# render los dedos parecian alambre de.pay. Con la banda, la falange se dobla
# en arco.
T_MID_DEDO: tuple = (0.06, 0.15, 0.32, 0.50, 0.68, 0.85, 0.94)
N_TORSO: int = 26
N_MIEMBRO: int = 18
N_PIE: int = 18
N_PALMA: int = 16
N_DEDO: int = 16


def _miembro(m: Malla, info: dict, juntas: list, huesos: list,
             perfiles: list, n: int, rep_u: float, nombre_inf: str,
             siguiente: str = "", tapar: bool = True,
             banda: str = "brazo") -> None:
    """Tubo a lo largo de una cadena de articulaciones, con LOOP y BANDA.

    `juntas` son los puntos de articulacion y `huesos[k]` el hueso del tramo k.
    El anillo de cada junta es el LOOP: lleva 50/50 de los dos huesos que se
    encuentran ahi, de modo que al girar la articulacion el anillo se queda
    circular en vez de plegarse sobre si mismo. Los anillos de `T_MID` que caen
    dentro de `BANDA` (los tres primeros y los tres ultimos) son la banda de
    apoyo: van al 100% de su hueso y son los que le dan sitio al giro.

    `perfiles[k]` = (radio, t_del_bulto, factor) del tramo k. El radio a lo
    largo del tramo interpola con una curva suave, para que en la articulation
    no haya un escalon entre el anillo del LOOP y el primer anillo del tramo.

    `siguiente` es el hueso que SIGUE a la cadena (el pie, tras la espinilla). Si
    viene, el ultimo anillo y el del 0,94 comparten peso con el, para que el
    tobillo doble sin que la union se abra: los dos anillos siguen la misma
    promedio y la superficie no se-crackea. Sin esto el pie se separa de la pierna al moverse.
    """
    def suave(x: float) -> float:
        x = min(1.0, max(0.0, x))
        return x * x * (3.0 - 2.0 * x)

    # La `v` de la malla es la longitud de arco ACUMULADA desde el primer hueso
    # (asi se mide la deformacion y asi se imprimen los informes), y para la
    # textura se reescala a la BANDA de la parte. Sin esto el brazo y la pierna
    # arrancaban los dos en v = 0 y se pisaban la textura: por eso no se les
    # podia dar materiales distintos aunque se supiera cual era cual.
    largo_total: float = sum((juntas[k + 1] - juntas[k]).length
                             for k in range(len(juntas) - 1))
    largo_total = max(1e-6, largo_total)
    largo_acum: float = 0.0
    previo = None
    ultimo: list = None
    for k, J in enumerate(juntas):
        if k == 0:
            w: dict = {huesos[0]: 1.0}
        elif k == len(juntas) - 1 and siguiente:
            w = {huesos[k - 1]: 0.5, siguiente: 0.5}
        elif k == len(juntas) - 1:
            w = {huesos[k - 1]: 1.0}
        elif huesos[k - 1] == huesos[k]:
            w = {huesos[k]: 1.0}
        else:
            w = {huesos[k - 1]: 0.5, huesos[k]: 0.5}
        # EL RADIO DE LA JUNTA, Y POR QUE NO ES EL MAYOR DE LOS DOS TRAMOS.
        #
        # Este `max` era un parche para que el codo no saliera en arista, y lo que
        # consiguio fue el defecto que se ve en `cuerpo_frente.png`: un ARO
        # puesto encima de la articulacion, como un aro de thru. Medido: el codo
        # salia con un anillo de 0,062 de radio mientras el tubo que llegaba a
        # el iba por 0,036, o sea un escalon de 26 mm de alto en un solo anillo
        # (y en la rodilla, 32 mm). Un aro de metal en el codo se pone aposta; un
        # aro que sale solo de un escalon es un fallo de malla.
        #
        # Lo que hace falta NO es engordar la junta: es que el radio sea CONTINUO
        # a lo largo de la cadena. Y ya lo es por construccion, porque
        # `perfiles[k][0]` es a la vez donde acaba el tramo k-1 y donde empieza el
        # k. Con el radio de la junta tomado de ahi, los tres anillos que se tocan
        # (el ultimo del tramo, el LOOP y el primero del tramo siguiente) miden
        # lo mismo y no hay escalon que ver. La articulation se sigue-Abriendo
        # bien porque el LOOP ya no necesita engordar: lo que hace falta para que
        # un codo a 90 grados no se aplaste es el LOOP (50/50), no el radio.
        rad: float = perfiles[min(k, len(perfiles) - 1)][0]
        if k > 0:
            largo_acum += (J - juntas[k - 1]).length
        d, ex, ey = marco(juntas[k + 1] - J if k < len(juntas) - 1
                          else J - juntas[k - 1])
        anillo = m.anillo(J, ex, ey, rad, rad * 0.94, n, w, rep_u,
                          _v_tex(banda, largo_acum / largo_total))
        if previo is not None:
            m.loftear([previo, anillo])
        if k == 0:
            primero: list = anillo
        ultimo = anillo
        info["loops"].append({"miembro": nombre_inf, "junta": k,
                              "huesos": sorted(w.keys()), "anillos": n,
                              "pesos": sorted(w.values()), "en_banda": 0})
        if k < len(juntas) - 1:
            L: float = (juntas[k + 1] - J).length
            r0: float = perfiles[k][0]
            r1: float = perfiles[k + 1][0] if k + 1 < len(perfiles) else r0
            tb, fb = perfiles[k][1], perfiles[k][2]
            d, ex, ey = marco(juntas[k + 1] - J)
            previo = anillo
            for t in T_MID:
                P: Vector = J + (juntas[k + 1] - J) * t
                base: float = r0 + (r1 - r0) * suave(t)
                # EL BULTO, Y POR QUE ES UNA COSENO ELEVADA Y NO UN TENTATIVO.
                # El tentativo (linea que baja a 1,0 en `|t-tb| = 0,30`) tiene la
                # derivada rota en los bordes, y una derivada rota es un PLIEG:
                # en el render salia una arista circular en el biceps y en la
                # pantorrilla, que es el mismo defecto del aro, mas pequeño y en
                # un sitio donde no se busca. La coseno elevada vale `factor` en
                # el pico y 1,0 en el borde, y su derivada es CERO en los dos, de
                # modo que se pega a la base sin dejar nada.
                x: float = min(1.0, abs(t - tb) / 0.30)
                if fb != 1.0:
                    base *= 1.0 + (fb - 1.0) * 0.5 * (1.0 + math.cos(math.pi * x))
                wt: dict = {huesos[k]: 1.0}
                if siguiente and k == len(juntas) - 2 and t >= 0.90:
                    wt = {huesos[k]: 0.5, siguiente: 0.5}
                a2 = m.anillo(P, ex, ey, base, base * 0.94, n, wt,
                              rep_u,
                              _v_tex(banda, (largo_acum + L * t) / largo_total))
                m.loftear([previo, a2])
                previo = a2
            if abs(t) <= 0.0:
                pass
            info["loops"][-1]["en_banda"] = sum(
                1 for tt in T_MID if tt <= BANDA or tt >= 1.0 - BANDA)
            info["loops"][-1]["largo_hueso"] = L
    if tapar:
        m.tapar(ultimo, juntas[-1], {huesos[-1]: 1.0}, 0.0, +1)
        m.tapar(primero, juntas[0] - (juntas[1] - juntas[0]).normalized()
                * 0.010, {huesos[0]: 1.0}, -0.10, -1)


def _brazo(m: Malla, p: dict, r, g: float, s: str, hombro: Vector,
           codo: Vector, muneca: Vector, n: int, inf: dict) -> None:
    """Brazo completo con la mano, y la mano con los cinco dedos."""
    sg: float = 1.0 if s == ".L" else -1.0
    # ---------------------------------------------------------------- PUAS
    # DE DONDE SALIAN DOS ASTILLAS POR HOMBRO, Y POR QUE NO ERA EL RADIO.
    #
    # La causa no era el radio de la raiz (que tambien estaba mal, pero eso se
    # ve como un hombro gordo, no como una astilla). Era la DIRECCION: la raiz
    # estaba en `(0,100 * sg, 0, hombro_z)`, o sea en la misma altura del hombro
    # y 9 cm por dentro, y el tramo raiz->hombro iba en horizontal (+X). El
    # tramo hombro->codo va casi vertical (10 grados de la vertical). O sea que
    # los dos tramos son perpendiculares, y los dos anillos que los unen (el
    # ultimo de la raiz y el LOOP del hombro) estan separados por 7 cm y GIRADOS
    # 90 grados uno respecto del otro.
    #
    # La consecuencia es que el cosido entre dos discos de 12 cm, perpendiculares y
    # separados por medio centimetro, no puede ser un tubo: es una falda. Los
    # cuatro triangulos que cuelgan del canto del disco vertical hacia el disco
    # horizontal salen como aletas, y en `build/referencia/cuerpo_frente.png` se
    # ven como esquirlas triangulares planas clavadas en el hombro. Medido en el
    # primer intento de arreglo (bajar solo el radio a 0,050): la astilla baja a
    # la mitad de tamano pero sigue ahi, porque el giro de 90 grados no se fue.
    #
    # Lo que se hace es poner la raiz EN EL EJE DEL BRAZO, hacia atras:
    # `dentro = hombro - dir * LARGO_RAIZ`. Con eso el tramo raiz->hombro es
    # colineal con hombro->codo, los dos anillos tienen el mismo marco, y el giro
    # es de CERO grados. No hay falda que Hide nada: es un cono limpio, que es
    # justo la forma del deltoide (sale del trapecio y engorda hasta el hombro).
    LARGO_RAIZ: float = 0.045
    dir_brazo: Vector = (codo - hombro).normalized()
    dentro: Vector = hombro - dir_brazo * LARGO_RAIZ
    # Y el radio de la raiz se mide contra el torso en ESA altura, para que el
    # anillo caiga dentro del pecho y no asome por la nuca. Con `girth` alto el
    # torso se ensancha y el margen crece; con un personaje flaco se cierra. Un
    # numero fijo aqui se desajusta con cualquier otra clase.
    rx_t, ry_t = _cabe_en_torso(p, dentro.z)
    raiz: float = min(0.030, 0.60 * (rx_t * r(1.0) - abs(dentro.x)),
                      0.60 * ry_t * r(1.0))
    inf.setdefault("raices", []).append(
        {"miembro": "brazo" + s, "z": round(dentro.z, 4),
         "x": round(abs(dentro.x), 4), "radio": round(raiz, 4),
         "torso_rx": round(rx_t * r(1.0), 4)})
    # Perfiles: (radio en la junta, t_del_bulto, factor). `perfiles[k][0]` es a
    # la vez donde acaba el tramo k-1 y donde empieza el k, asi que la cadena de
    # radios no tiene ni un escalon (ver la nota de `_miembro`).
    perfiles = [
        (raiz, 0.30, 1.00),            # raiz -> hombro (dentro del pecho)
        (0.064 * r(1.0), 0.30, 1.08),  # hombro -> codo (el deltoide y el biceps)
        (0.043 * r(1.0), 0.25, 1.14),  # codo -> muneca (la barriga)
        (0.030 * r(1.0), 0.00, 1.00),  # la muneca, que es donde llega la palma
    ]
    huesos = ["UpperArm" + s, "UpperArm" + s, "LowerArm" + s]
    _miembro(m, inf, [dentro, hombro, codo, muneca], huesos, perfiles, n, 1.6,
             "brazo_" + s, "", True, "brazo")
    _mano(m, r, g, s, sg, muneca, codo, inf)


def _mano(m: Malla, r, g: float, s: str, sg: float, muneca: Vector,
          codo: Vector, inf: dict) -> None:
    """La mano: palma y cinco dedos, con sus tres huesos cada uno.

    MARCO CANONICO: se construye aqui en (X hacia el pulgar, Y hacia la punta,
    Z dorsal) y se lleva al esqueleto con la matriz de la mano. La mano
    DERECHA es el ESPEJO de la izquierda, y un espejo invierte el sentido de la
    cara: por eso despues se le dan la vuelta a las caras de esa mano. No es un
    detalle: si no, la mitad del modelo se dibuja del reves y con las normales
    hacia dentro, que en Godot es negro.
    """
    ey = (muneca - codo).normalized()
    ex = Vector((0.0, -1.0, 0.0))
    ex = (ex - ey * ex.dot(ey)).normalized()
    ez = ex.cross(ey).normalized()
    if s == ".R":
        # LA MANO DERECHA: SE NIEGA EL EJE DEL DORSO, NO EL DEL PULGAR.
        #
        # El pulgar va adelante en las DOS manos (con los brazos colgando y las
        # palmas contra los muslos, los dos pulgares miran al frente). Antes de
        # este arreglo se negaba el eje del pulgar para que el marco saliera
        # derecho, y el pulgar derecho acababa hacia ATRAS: la mano derecha se
        # leia del reves y por eso el render mostraba la palma cuando se
        # pedia el dorso.
        #
        # Lo que se puede negar es el EJE DEL DORSO, y hay que negarlo: la mano
        # derecha es el espejo de la izquierda y un espejo invierte la
        # orientacion, o sea que el marco de la derecha es ZURDO
        # (`det < 0`). Eso es lo correcto y no un error: por eso despues se le
        # dan la vuelta a las caras de esa mano con `invertir`.
        ez = -ez
    M = Matrix(((ex.x, ey.x, ez.x, muneca.x),
                (ex.y, ey.y, ez.y, muneca.y),
                (ex.z, ey.z, ez.z, muneca.z),
                (0.0, 0.0, 0.0, 1.0)))
    DORSO["Hand" + s] = ez.copy()
    cara_ini: int = len(m.f)
    # ------------------------------------------------------------------ palma
    w0: dict = {"LowerArm" + s: 0.5, "Hand" + s: 0.5}
    w1: dict = {"Hand" + s: 1.0}
    # (Y canonico, semiancho, semigrosor). La palma se abre hacia los nudillos
    # y se aplana: es una placa, no un cilindro.
    # LA PRIMERA SECCION DE LA PALMA ES MAS ANCHA QUE EL ANTEBRAZO. El anillo
    # final del antebrazo mide 0,036 y la palma arrancaba en 0,033: el tubo del
    # antebrazo salia por los lados de la muneca y se veia su interior. Ahora
    # la palma arranca en 0,038 x 0,031 y se traga el antebrazo entero; de ahi
    # para adelante se aplana, que es lo que hace una palma de verdad.
    # (Y, semiancho, semigrosor). LOS TRES ULTIMOS ANILLOS SON EL CANTO DE
    # LOS NUDILLOS, y van cerrando: con un solo anillo y una tapa plana, el
    # canto de la palma sale como el filo de una pala de cocina y los dedos
    # se le clavan encima. Redondeando el canto, los dedos salen de una curva.
    pal = [(0.000, 0.0380, 0.0310), (0.020, 0.0384, 0.0262),
           (0.042, 0.0404, 0.0228), (0.064, 0.0428, 0.0202),
           (0.080, 0.0432, 0.0176), (0.088, 0.0408, 0.0138),
           (0.093, 0.0330, 0.0098), (0.096, 0.0210, 0.0060)]
    def _tenar(cy: float) -> float:
        """El MONTECULO DEL PULGAR en el canto de la palma (el lado +X, el del
        pulgar). Sin el, la palma es una plancha cuadrada y la mano se lee como
        un manopla. Con el, el lado del pulgar engorda como engorda de verdad.
        El maximo esta a dos tercios de la palma, que es donde esta la base del
        pulgar."""
        u: float = min(1.0, max(0.0, cy / 0.045))
        return 0.0090 * math.sin(math.pi * u ** 0.8)

    previo = None
    for i, (cy, rx, ry) in enumerate(pal):
        w = w0 if i == 0 else w1
        # EL SENO Y EL COSENO VAN INTERCAMBIADOS, y no es cosquillaje: el
        # anillo se recorre como `x = rx*sin, z = ry*cos` para que el marco
        # (X, Z) sea DERECHO con respecto al avance de la palma (que va por +Y).
        # Con `x = rx*cos, z = ry*sin` el producto vectorial sale al reves, TODAS
        # las caras de la palma apuntan hacia dentro y en el render la palma
        # sale NEGRA con el pulgar en medio. Es el mismo bug que el del espejo
        # de la mano derecha, por el mismo motivo: el sentido de la cara.
        anillo = [m.vert(M @ Vector((rx * math.sin(math.tau * k / N_PALMA)
                                     + _tenar(cy),
                                     cy, ry * math.cos(math.tau * k / N_PALMA))),
                         (k / float(N_PALMA)) * 1.0,
                         _v_tex("mano", cy / 0.096), w)
                  for k in range(N_PALMA)]
        if previo is not None:
            m.loftear([previo, anillo])
        previo = anillo
    m.tapar(previo, M @ Vector((0.0, 0.0975, 0.0)), w1, 0.20, +1)
    # ----------------------------------------------------------------- dedos
    for dedo in DEDOS:
        abrev: str = DEDOS_ABREV[dedo]
        largo, radio = FALANGE_M[abrev]
        # Direccion de la falange en el marco canonico, en abanico.
        if dedo == "pulgar":
            d0 = Vector((DIR_PULGAR.x, DIR_PULGAR.y, DIR_PULGAR.z))
        else:
            ang: float = ABANICO[abrev]
            d0 = Vector((math.sin(ang), math.cos(ang), 0.0)).normalized()
        exd = Vector((0.0, 0.0, 1.0))
        exd = (exd - d0 * exd.dot(d0)).normalized()
        eyd = d0.cross(exd).normalized()
        nx, ny = NUDILLO[abrev]
        juntas: list = []
        P = Vector((nx, ny, -0.0015))
        for j in range(3):
            juntas.append(P.copy())
            P = P + d0 * largo[j]
        juntas.append(P.copy())
        nomb: list = ["%s.%s%s" % (dedo, f, s) for f in FALANGES]
        previos = None
        for k, Q in enumerate(juntas):
            if k == 0:
                w = {"Hand" + s: 0.5, nomb[0]: 0.5}
            elif k == len(juntas) - 1:
                w = {nomb[2]: 1.0}
            else:
                w = {nomb[k - 1]: 0.5, nomb[k]: 0.5}
            # LA YUNTA NO SE AFILA A CUCHILLO. Con el 68% del diametro de la
            # distal la punta del dedo salia en punta de aguja, y un dedo que se
            # acaba en aguja se ve como un alfiler: la uña (que es lo que hay que
            # ver) no tiene donde estar. Un dedo real se acaba en un redo
            # redondeado, y con el 80% ya se lee la yunta.
            rr: float = (radio[k] if k < 3 else radio[2] * 0.80) * 0.5
            anillo = [m.vert(M @ (Q + exd * (math.cos(math.tau * j / N_DEDO) * rr)
                                  + eyd * (math.sin(math.tau * j / N_DEDO)
                                           * rr * APLANADO)),
                             (j / float(N_DEDO)) * 0.6,
                             _v_tex("dedo", k / 3.0), w)
                      for j in range(N_DEDO)]
            if previos is not None:
                m.loftear([previos, anillo])
            previos = anillo
            if k < 3:
                Q2: Vector = juntas[k + 1]
                for t in T_MID_DEDO:
                    # La ultima falanga se estrecha hasta la punta; las otras
                    # dos van de joint a joint.
                    if k < 2:
                        rk: float = radio[k] * 0.5
                        rk1: float = radio[k + 1] * 0.5
                    else:
                        rk = radio[2] * 0.5
                        rk1 = radio[2] * 0.48
                    rr2: float = rk + (rk1 - rk) * t
                    P2: Vector = Q + (Q2 - Q) * t
                    a2 = [m.vert(M @ (P2 + exd * (math.cos(math.tau * j / N_DEDO) * rr2)
                                      + eyd * (math.sin(math.tau * j / N_DEDO)
                                               * rr2 * APLANADO)),
                                 (j / float(N_DEDO)) * 0.6,
                                 _v_tex("dedo", (k + t) / 3.0),
                                 {nomb[k]: 1.0})
                          for j in range(N_DEDO)]
                    m.loftear([previos, a2])
                    previos = a2
        m.tapar(previos, M @ P, {nomb[2]: 1.0}, 0.32, +1)
    # Cuantos vertices lleva cada hueso de dedo, y cuantos lo comparten con el
    # vecino en el LOOP. Es el numero que hay que mirar para saber si los dedos
    # tienen siquiera geometria que deformar.
    for dedo in DEDOS:
        for f in FALANGES:
            nm: str = "%s.%s%s" % (dedo, f, s)
            puros: int = 0
            compartidos: int = 0
            for w in m.w:
                if w.get(nm, 0.0) > 0.99:
                    puros += 1
                elif w.get(nm, 0.0) > 0.0:
                    compartidos += 1
            inf["dedos"][nm] = puros
            inf["dedos_loop"][nm] = compartidos
    if s == ".R":
        m.invertir(cara_ini, len(m.f))



def _pierna(m: Malla, p: dict, r, g: float, s: str, cadera: Vector,
            rodilla: Vector, tobillo: Vector, inf: dict) -> None:
    """Pierna completa con su pie.

    La cadera lleva un tramo corto DENTRO del torso (el primer anillo se queda
    dentro de la pelvis, que llega a 0,152 de semiancho y el muslo entra a
    0,100). Es el workaround barato de la union: sin el, se veria el agujero
    entre el muslo y la cadera al girar la pierna. Con el, lo que se ve es una
    costura de unin, que es lo que se ve en cualquierikinema.
    """
    sg: float = 1.0 if s == ".L" else -1.0
    # LA MISMA RAZON QUE EN EL BRAZO, y el mismo arreglo. La raiz estaba en
    # `(0,045 * sg, 0, cadera_z)`, en horizontal, y el tramo cadera->rodilla va
    # vertical: dos discos perpendiculares separados por 5,5 cm, y el mismo
    # cosido en falda que en el hombro (alli se veia como astilla, aqui como un
    # pliegue en la cadera). Puesta en el eje del muslo y hacia atras, el tramo
    # es colineal y el giro es de cero. El radio se mide contra el torso (que a
    # esa altura es la pelvis) para que caiga dentro.
    LARGO_RAIZ: float = 0.090
    dir_pierna: Vector = (rodilla - cadera).normalized()
    dentro: Vector = cadera - dir_pierna * LARGO_RAIZ
    rx_t, ry_t = _cabe_en_torso(p, dentro.z)
    raiz: float = min(0.052, 0.60 * (rx_t * r(1.0) - abs(dentro.x)),
                      0.60 * ry_t * r(1.0))
    inf.setdefault("raices", []).append(
        {"miembro": "pierna" + s, "z": round(dentro.z, 4),
         "x": round(abs(dentro.x), 4), "radio": round(raiz, 4),
         "torso_rx": round(rx_t * r(1.0), 4)})
    perfiles = [
        (raiz, 0.35, 1.00),              # raiz -> cadera (dentro de la pelvis)
        (0.098 * r(1.0), 0.25, 1.05),    # cadera -> rodilla (el muslo)
        (0.055 * r(1.0), 0.25, 1.12),    # rodilla -> tobillo (la pantorrilla)
        (0.032 * r(1.0), 0.00, 1.00),    # el tobillo, que es donde empieza el pie
    ]
    _miembro(m, inf, [dentro, cadera, rodilla, tobillo],
             ["Thigh" + s, "Thigh" + s, "Shin" + s], perfiles, N_MIEMBRO, 1.5,
             "pierna_" + s, "Foot" + s, True, "pierna")
    _pie(m, r, p, s, sg, inf)


def _pie(m: Malla, r, p: dict, s: str, sg: float, inf: dict) -> None:
    """El pie, con la planta en el suelo.

    La planta es un PLANO (z constante) y no el fondo de una elipse: un elipse
    con la base aplastada deja triangulos de area cero, y en Godot eso son
    caras degeneradas que se ven como puntitos negros. `_perfil_d` mete los
    puntos de la planta en linea recta y el resultado es la suela de verdad.
    """
    # (y del talón a la punta, semiancho, altura de la suela a la cresta).
    #
    # EL PIE ERA UN ZOCLO, Y SE VEIA EN EL RENDER DE PERFIL: 7,6 cm de ancho y
    # 12,6 cm de alto en el arco. Un pie real mide unos 10 de ancho y 7 de alto,
    # y el arco es el punto MAS BAJO, no el mas alto. Con la tabla de antes la
    # cresta del arco (0,126) estaba por encima del tobillo (0,098), o sea que
    # el pie era mas alto que la rodilla del tobillo y el personaje salia con
    # un zapato de carton en los dos pies. Medido en el perfil, no deducido.
    # Ahora: ancho de 6 a 9,6 cm, y el arco (0,074) por DEBAJO del talon (0,090),
    # que es como es de verdad: el talon sube a la articulation del tobillo y el
    # arco se queda en medio.
    tabla = [(0.062, 0.030, 0.090), (0.040, 0.038, 0.082),
             (0.012, 0.045, 0.074), (-0.022, 0.048, 0.068),
             (-0.062, 0.048, 0.060), (-0.100, 0.046, 0.052),
             (-0.140, 0.043, 0.045), (-0.180, 0.039, 0.038),
             (-0.212, 0.035, 0.030), (-0.238, 0.029, 0.024),
             (-0.254, 0.017, 0.017)]
    ex = Vector((1.0, 0.0, 0.0))
    ey = Vector((0.0, 0.0, 1.0))
    previo = None
    for i, (cy, hw, top) in enumerate(tabla):
        # Los tres primeros anillos (el talon) comparten peso con la espinilla:
        # el tobillo dobla y la union no se abre. Del centro hacia delante el
        # pie es suyo, que es donde tiene que rotar al_POINTERSE y al apoyo.
        w: dict = {"Shin" + s: 0.5, "Foot" + s: 0.5} if cy > -0.010 \
            else {"Foot" + s: 1.0}
        perfil = _perfil_d(hw * r(1.0), top * r(1.0), N_PIE)
        # LA `u` DEL PIE ERA UN SOLO VALOR (0,5) para los 137 vertices: el pie
        # entero, suela y empeine, muestreaba UNA COLUMNA de la textura y no
        # podia tener ni suela ni empeine ni nada. Se reparte alrededor del
        # perfil, que es lo que hace `k / n`.
        anillo = [m.vert(Vector((p["pie_x"] * sg + ex.x * a, cy, b)),
                         _u_tex("pie", k / float(N_PIE)),
                         _v_tex("pie", (0.062 - cy) / 0.316), w)
                  for k, (a, b) in enumerate(perfil)]
        if previo is not None:
            m.loftear([previo, anillo])
        previo = anillo
    m.tapar(previo, Vector((p["pie_x"] * sg, -0.262, 0.009)), {"Foot" + s: 1.0},
            0.44, +1)
    inf["pie_supera"] = 0.004


# ---------------------------------------------------------------------------
# Esqueleto: los 19 del juego con los mismos NOMBRES y los 14 de dedos.
#
# EL NOMBRE ES LO UNICO QUE EL JUEGO LEE. `paper_doll.gd` busca `Hand.L` y
# `Hand.R` para colgar el equipo, `test_fase49` busca los 7 anclajes de
# `data/anclajes.json` y `test_fase71` busca `Foot.L`, `Hips`, `UpperArm.L`...
# Las longitudes si se pueden cambiar (y una se ha cambiado, el tobillo: ver la
# cabecera), pero un nombre distinto deja el equipo flotando y tres tests en
# rojo. Por eso la lista sale de `orden_completo()` y no de aqui.
def brazo_pos(p: dict, sg: float) -> tuple:
    """Hombro, codo y muneca de un lado. UNA sola fuente de verdad: la malla y
    el esqueleto tienen que salir de aqui, o el hueso se va de la piel.

    Y EL ESPEJO VA EN EL DELTA, NO SOLO EN EL ORIGEN. Este es el fallo mas caro
    de la primera version: se multiplicaba el hombro por `sg` y se sumaba un
    delta con la X SIEMPRE positiva, con lo que el brazo derecho se doblaba
    HACIA DENTRO. Medido: el codo derecho salia en x = -0,115 en vez de -0,225
    (dentro del torso, no debajo del hombro) y la muneca en -0,082, o sea
    pegada al pecho. El esqueleto de la derecha estaba entero plegado dentro del
    cuerpo, la piel se deformaba con el, y en el render el brazo derecho se
    veia como una placa pegada al pecho y la mano como un manojo de alambres
    salidos de la belly. Todo eso era UN SIGNO.
    """
    ang: float = BRAZO_REPOSO
    sa, ca = math.sin(ang), math.cos(ang)
    hombro = Vector((p["hombro_x"] * sg, 0.0, p["hombro_z"]))
    codo = hombro + Vector((sa * 0.325 * sg, 0.0, -ca * 0.325))
    muneca = codo + Vector((sa * 0.197 * sg, 0.0, -ca * 0.197))
    return hombro, codo, muneca


def mano_dir(p: dict, sg: float) -> Vector:
    ang: float = BRAZO_REPOSO
    return Vector((math.sin(ang) * sg, 0.0, -math.cos(ang))).normalized()


def crear_esqueleto(nombre: str, p: dict) -> object:
    """Los 33 huesos, en el orden de `orden_completo()`.

    Los huesos de brazo llevan `align_roll((0,-1,0))` igual que `tools/rig.py`:
    ese roll es una de las trampas ya pagadas de AGENTS.md y no se toca.
    Los de dedo NO llevan align_roll a proposito, porque su orientacion en
    reposo no importa: el escritor de clips coloca cada falange con su
    direccion ABSOLUTA y el roll se deduce solo.
    """
    datos = bpy.data.armatures.new(nombre)
    obj = bpy.data.objects.new(nombre, datos)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = datos.edit_bones
    L, R = "L", "R"
    # --- columna
    cadena = [("Hips", (0.0, 0.0, p["cadera_z"]), (0.0, 0.0, p["cintura_z"]), None),
              ("Spine", (0.0, 0.0, p["cintura_z"]), (0.0, 0.0, p["pecho_z"]), "Hips"),
              ("Chest", (0.0, 0.0, p["pecho_z"]), (0.0, 0.0, p["cuello_z"]), "Spine"),
              ("Neck", (0.0, 0.0, p["cuello_z"]), (0.0, 0.0, p["cabeza_z"]), "Chest"),
              ("Head", (0.0, 0.0, p["cabeza_z"]), (0.0, 0.0, p["cima_z"]), "Neck")]
    for lado, sg in ((L, 1.0), (R, -1.0)):
        h, c, mu = brazo_pos(p, sg)
        s: str = "." + lado
        d = mano_dir(p, sg)
        cadena += [
            ("Shoulder" + s, (0.050 * sg, 0.0, p["hombro_z"]), (h.x, 0.0, h.z), "Chest"),
            ("UpperArm" + s, (h.x, 0.0, h.z), (c.x, 0.0, c.z), "Shoulder" + s),
            ("LowerArm" + s, (c.x, 0.0, c.z), (mu.x, 0.0, mu.z), "UpperArm" + s),
            # El hueso `Hand` llega a la linea de los nudillos, no a la punta: es
            # donde se cuelga el arma (`data/anclajes.json` -> "Hand.R"), y la
            # palma es el sitio donde un arma se sostiene.
            ("Hand" + s, (mu.x, 0.0, mu.z), (mu.x + d.x * 0.092, 0.0, mu.z + d.z * 0.092),
             "LowerArm" + s),
        ]
    for lado, sg in ((L, 1.0), (R, -1.0)):
        s: str = "." + lado
        cadena += [
            ("Thigh" + s, (p["cadera_x"] * sg, 0.0, p["cadera_z"]),
             (p["pie_x"] * sg, 0.0, p["rodilla_z"]), "Hips"),
            ("Shin" + s, (p["pie_x"] * sg, 0.0, p["rodilla_z"]),
             (p["pie_x"] * sg, 0.0, p["tobillo_z"]), "Thigh" + s),
            ("Foot" + s, (p["pie_x"] * sg, 0.0, p["tobillo_z"]),
             (p["punta_x"] * sg, p["toe_y"], p["toe_z"]), "Shin" + s),
        ]
    for nombre_h, cabeza, cola, padre in cadena:
        b = eb.new(nombre_h)
        b.head = cabeza
        b.tail = cola
        b.use_connect = False
        if padre is not None:
            b.parent = eb[padre]
        if nombre_h.split(".")[0] in ("Shoulder", "UpperArm", "LowerArm"):
            b.align_roll(Vector((0.0, -1.0, 0.0)))
    # --- los catorce de dedos, colgando de su `Hand`
    for lado, sg in ((L, 1.0), (R, -1.0)):
        s: str = "." + lado
        _, _, mu = brazo_pos(p, sg)
        d = mano_dir(p, sg)
        ex = Vector((0.0, -1.0, 0.0))
        ex = (ex - d * ex.dot(d)).normalized()
        ez = ex.cross(d).normalized()
        if lado == R:
            # Ver la nota de `_mano`: en la derecha se niega el dorso, no el
            # pulgar. El pulgar adelante en las dos manos.
            ez = -ez
        M = Matrix(((ex.x, d.x, ez.x, mu.x), (ex.y, d.y, ez.y, mu.y),
                    (ex.z, d.z, ez.z, mu.z), (0.0, 0.0, 0.0, 1.0)))
        DORSO["Hand" + s] = ez.copy()
        for dedo in DEDOS:
            abrev: str = DEDOS_ABREV[dedo]
            largo, _ = FALANGE_M[abrev]
            if dedo == "pulgar":
                d0 = Vector((DIR_PULGAR.x, DIR_PULGAR.y, 0.0)).normalized()
            else:
                d0 = Vector((math.sin(ABANICO[abrev]), math.cos(ABANICO[abrev]),
                             0.0)).normalized()
            nx, ny = NUDILLO[abrev]
            P = M @ Vector((nx, ny, -0.0015))
            padre = "Hand" + s
            for j, f in enumerate(FALANGES):
                b = eb.new("%s.%s%s" % (dedo, f, s))
                b.head = P
                P = P + (M.to_3x3() @ d0) * largo[j]
                b.tail = P
                b.use_connect = False
                b.parent = eb[padre]
                padre = b.name
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


# ---------------------------------------------------------------------------
# Piel y malla
# ---------------------------------------------------------------------------
def aplicar_piel(m: Malla, arm: object, tex: dict) -> dict:
    """Crea el objeto de malla, el parenta al esqueleto y reparte los pesos.

    EL PESO NO SE CALCULA CON `bone heat` NI CON ENVOLVENTES, y no es una
    preferencia. En headless el heat falla con "failed to find solution" y deja
    la malla sin un solo peso; las envolventes reparten la influencia entre
    todos los huesos cercanos, y con un torso de 0,19 de radio el pecho y la
    cadera se quedan con el 67% del brazo (medido en los seis modelos: el brazo
    se movia 2 grados cuando se le pedian 23). Aqui el peso se escribe POR
    ANILLO, en el mismo momento en que se crea el anillo, y sale exacto.
    """
    me = bpy.data.meshes.new("Cuerpo")
    me.from_pydata([tuple(v) for v in m.v], [], [tuple(f) for f in m.f])
    me.update()
    uv = me.uv_layers.new(name="UVMap")
    for i, loop in enumerate(me.loops):
        vi = loop.vertex_index
        uv.data[i].uv = m.uv[vi]
    for poly in me.polygons:
        poly.use_smooth = True
    me.materials.append(material(tex))
    me.update()
    obj = bpy.data.objects.new("Cuerpo", me)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    # Parentear SIN que Blender reparta pesos: se hace a mano despues.
    bpy.ops.object.parent_set(type="ARMATURE")
    grupos: dict = {}
    for nombre in sorted({k for w in m.w for k in w}):
        grupos[nombre] = obj.vertex_groups.new(name=nombre).index
    hist: dict = {}
    for vi, w in enumerate(m.w):
        total: float = sum(w.values())
        if total <= 0.0:
            continue
        for nombre, val in w.items():
            peso: float = val / total
            obj.vertex_groups[grupos[nombre]].add([vi], peso, "REPLACE")
            hist[nombre] = hist.get(nombre, 0.0) + peso
    for md in obj.modifiers:
        if md.type == "ARMATURE":
            md.use_bone_envelopes = False
            md.use_vertex_groups = True
    return {"grupos": len(grupos), "histograma": hist}


def material(ruta_tex: dict) -> object:
    """Un Principled con albedo + normal + ORM, en los nodos que el
    EXPORTADOR DE GLTF DE BLENDER 5.2 reconoce.

    Y aqui hay que leer el exportador, no suponerlo. El PBR de un `.glb` sale de
    UN SOLO grafo, y el exportador lo busca por nombres exactos:

    - el ALBEDO va DIRECTO al `Base Color` del Principled, a un nodo de imagen;
    - la oclusion va a la entrada `Occlusion` de un grupo de nodos que se tiene
      que llamar **exactamente** "glTF Material Output";
    - la rugosidad y el metal van JUNTOS a la entrada `MetallicRoughness` de ese
      mismo grupo (una sola entrada, no dos: el canal G es rugosidad y el B es
      metal, y los mete el exportador solo).

    Tres cosas que costan una tarde si sePokebnen:
    - el grupo tiene que llevar dentro un nodo `NodeGroupOutput`. Un grupo
      vacio (`node_groups.new` no lo crea) hace que el exportar reviente con
      `IndexError: list index out of range` dentro de `previous_socket`, y el
      mensaje no dice nada de grupos ni de materiales: parece un fallo de la
      malla;
    - la entrada se llama `MetallicRoughness`, no `Roughness`/`Metallic`. Con los
      nombrestipo glTF salen el albedo y la normal y NI UNO de los dos canales;
    - el factor de color no va por el grupo: va al Principled.
    """
    mat = bpy.data.materials.new("Cuerpo")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    salida = nt.nodes.new("ShaderNodeOutputMaterial")
    salida.location = (700, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (400, 0)
    # Metalico y rugosidad a 1, NO al valor por defecto (0 y 0,5). El
    # exportador escribe el factor que encuentra en el Principled SIEMPRE que
    # sea distinto de 1, y lo multiplica por la textura: con los valores de
    # fabrica el `.glb` sale con `metallicFactor: 0`, o sea que la textura
    # metalica horneada se multiplica por cero y el material sale de tela. Se ve
    # en el `.glb`, no en el render de Blender, porque en Blender el factor lo
    # aplica el Principled y la textura se ve igual de pelas.
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 1.0
    nt.links.new(bsdf.outputs["BSDF"], salida.inputs["Surface"])

    grupo = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
    grupo.interface.new_socket("Occlusion", socket_type="NodeSocketFloat")
    grupo.interface.new_socket("MetallicRoughness", socket_type="NodeSocketFloat")
    # El nodo de salida del grupo, sin el cual el exportador no encuentra las
    # entradas y revienta con un IndexError que no parece de materiales.
    go = grupo.nodes.new("NodeGroupOutput")
    go.location = (200, 0)
    grupo.nodes.new("NodeGroupInput").location = (-200, 0)
    gn = nt.nodes.new("ShaderNodeGroup")
    gn.node_tree = grupo
    gn.location = (150, -220)

    def imagen(clave: str, loc) -> object:
        img = bpy.data.images.load(ruta_tex[clave]["ruta"], check_existing=True)
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        # REPEAT explicito: el sampler por defecto de una imagen cargada puede
        # venir CLAMP, y con CLAMP la textura NO envuelve aunque la imagen si
        # (la costura aparece en la UV, que es donde se nota).
        tex.extension = "REPEAT"
        tex.location = loc
        tex.interpolation = "Smart"
        return tex

    alb = imagen("albedo", (-200, 320))
    nt.links.new(alb.outputs["Color"], bsdf.inputs["Base Color"])
    orm = imagen("orm", (-200, -120))
    nt.links.new(orm.outputs["Color"], gn.inputs["Occlusion"])
    nt.links.new(orm.outputs["Color"], gn.inputs["MetallicRoughness"])
    nrm = imagen("normal", (-200, -420))
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.location = (150, -420)
    nt.links.new(nrm.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


# ---------------------------------------------------------------------------
# Los dedos en los cuatro clips.
#
# EL MUNDO UNICO (y no es una copia de `tools/rig.py`): los clips del cuerpo ya
# estan escritos, medidos y verificados (`tools/animar_clips.py` y
# `test_fase71_clips.gd`). Anadir los dedos NO es reescribirlos: se engancha al
# unico punto por el que pasan los cuatro, `_brazo()`, que es quien coloca la
# cadena del brazo. Asi el cuerpo sale EXACTAMENTE como estaba (ni un numero
# cambiado) y los dedos salen de rebote. Copiar los cuatro clips para meterles
# los dedos dentro seria cambiar cuatro numeros que hoy dan verde.
#
# COMO SE DOBLA UN DEDO, y por que con ejes y no con Euler: la flexion de una
# falange se describe como "gira el dedo hacia la palma, N radianes". Eso es
# una rotacion de un vector `d` HACIA la palma `p`, y el eje que la hace es
# `d x p` (Rodrigues: rotar `d` un angulo a alrededor de `d x p` lo lleva
# exactamente a `p`, porque `(d x p) x d = p` para `d` y `p` perpendiculares y
# unitarios). Como `d` y `p` se calculan del esqueleto REAL y no de unos
# numeros escritos a mano, el signo sale solo y las dos manos salen espejo sin
# tener queSigns ningun signo a mano.
_FLEX_MUERTA: dict = {"I": (0.16, 0.22, 0.12), "M": (0.18, 0.24, 0.13),
                      "A": (0.18, 0.24, 0.13), "N": (0.20, 0.26, 0.14),
                      "T": (0.10, 0.12, 0.08)}
## Cuanto se abren los dedos de mas en cada pose. En la muerte la mano se cae
## abierta (por eso el "cadaver con los dedos clavados" que se reportaba): el
## antebrazo se relaja y los dedos se van con el.
ABANICO_MUERTA: float = 0.14
## Al agarrar, los dedos CONVERGEN. No es un detalle: una mano que se cierra
## con los dedos abiertos se lee como una garra, y la palma se ve a traves de
## los dedos. Con -0,22 los cinco se juntan y la mano se lee como un puño.
ABANICO_AGARRE: float = -0.22


def _tabla_dedos(arm: object) -> tuple:
    """Que postura de mano toca en el clip que se esta escribiendo.

    Es lo UNICO que se decide aqui y sale del nombre de la accion que esta
    activa, que es justo lo que el escritor de `animar_clips` va poniendo.
    """
    acc = arm.animation_data.action if arm.animation_data else None
    nombre: str = acc.name if acc else ""
    # EL FRAME DE AHORA MISMO NO SIRVE. `_brazo` se llama justo ANTES de
    # `esq.clave(f)`, o sea que en el frame 20 del tajo la escena sigue en el 1
    # y el reloj de la escena da 1 para toda la duracion del clip: con el se
    # midio un agarre que no cambiaba en los veinte frames. Lo que si esta
    # escrito son las claves de los frames anteriores, y la ultima de ellas es
    # el frame en el que estamos. De ahi sale el progreso real.
    f0, f1 = ([int(v) for v in acc.frame_range] if acc else (0, 0))
    total: float = max(1.0, float(TOTAL_FRAMES.get(nombre, 20)))
    t: float = min(1.0, max(0.0, (f1 + 1) / total))
    if nombre == "attack" and f1 <= 0:
        t = 0.0
    if nombre == "attack":
        # El tajo agarra: la mano se cierra mientras carga y se queda cerrada
        # en el golpe. Cerrar en la recuperacion habria que deshacerlo y se
        # veria un "des-entrar" de la mano en el aire.
        k: float = AC.suave(min(1.0, t / 0.45))
        return {DEDOS_ABREV[d]: tuple(
            REPOSO_MANOS[DEDOS_ABREV[d]][i]
            + (AGARRE[DEDOS_ABREV[d]][i] - REPOSO_MANOS[DEDOS_ABREV[d]][i]) * k
            for i in range(3)) for d in DEDOS}, ABANICO_AGARRE
    if nombre == "die":
        return _FLEX_MUERTA, ABANICO_MUERTA
    return REPOSO_MANOS, 0.0


def _poner_dedos(esc: "AC.Esqueleto", esq: "AC.Escritor", lado: str,
                 tabla: dict, abanico: float) -> None:
    """Las tres falanges de los cinco dedos de un lado, por direcciones
    absolutas.

    LA FLEXION SE APLICA ANTES DE COLOCAR EL HUESO, no despues. Esta es la
    misma logica que `animar_clips._brazo`: ahi, `brazo_abajo` devuelve la
    direccion de cada hueso YA doblada por el codo y por la muneca, y el escritor
    coloca cada hueso con esa direccion. Si aqui se acumulara la flexion DESPUES
    de colocar el hueso, la flexion de la ultima falange se perderia (no hay
    ningun hueso detras que la recoja) y la punta del dedo saldria recta: el
    `AGARRE` completo no se veria. Con la flexion antes, `flex[0]` dobla el dedo
    entero desde la base (la articulation MCP), `flex[1]` dobla la segunda falange
    sobre la primera (PIP) y `flex[2]` la tercera sobre la segunda (DIP).
    """
    s: str = "." + lado
    arm = esq.arm
    pb = arm.pose.bones["Hand" + s]
    # La rotacion ABSOLUTA que lleva el hueso de la mano desde su pose de
    # reposo: `pose @ rest^-1`. Con ella se lleva el marco de la mano (la palma,
    # que es perpendicular al hueso y no sale de ningun lado) al sitio donde esta
    # ahora. Sin esto los dedos se doblarian hacia un lado fijo del mundo en vez
    # de hacia la palma, que es el bug clasico del dedo.
    R_mano = pb.matrix.to_3x3() @ pb.bone.matrix_local.to_3x3().inverted()
    dorso = (R_mano @ DORSO["Hand" + s]).normalized()
    palma = -dorso
    d_mano = (R_mano @ (pb.bone.matrix_local.to_3x3()
                        @ Vector((0.0, 1.0, 0.0)))).normalized()
    cabeza_mano = pb.head.copy()
    # El eje de la articulation MCP: el que lleva la direccion de la mano hacia
    # la palma. El abanico va aparte, sobre la NORMAL de la palma (que es el eje
    # del abanico: abrir y cerrar los dedos es girar dentro del plano de la
    # palma).
    eje0 = d_mano.cross(palma)
    for dedo in DEDOS:
        abrev: str = DEDOS_ABREV[dedo]
        largo, _ = FALANGE_M[abrev]
        nomb: list = ["%s.%s%s" % (dedo, f, s) for f in FALANGES]
        flex = tabla[abrev]
        R = Matrix.Rotation(flex[0], 3, eje0.normalized()) if eje0.length > 1e-7 \
            else Matrix.Identity(3)
        if abs(abanico) > 1e-6:
            R = Matrix.Rotation(abanico, 3, palma) @ R
        c0 = arm.data.bones[nomb[0]].head_local.copy()
        cabeza: Vector = cabeza_mano + R_mano @ (
            c0 - arm.data.bones["Hand" + s].head_local)
        for j in range(3):
            d0 = (arm.data.bones[nomb[j]].matrix_local.to_3x3()
                  @ Vector((0.0, 1.0, 0.0))).normalized()
            d = (R @ d0).normalized()
            esq.poner(nomb[j], cabeza, d)
            cabeza = cabeza + d * largo[j]
            if j < 2:
                eje = d.cross(palma)
                if eje.length > 1e-7:
                    R = Matrix.Rotation(flex[j + 1], 3, eje.normalized()) @ R


## El DORSO de cada mano en el espacio del esqueleto, en su pose de reposo.
##
## NO es el `Z` local del hueso: es el eje que sale de la definicion del marco
## de la mano (`_mano`), y va aparte porque el roll del hueso no lo dice. Es el
## unico dato que hace falta para saber hacia donde esta la palma en cualquier
## frame, y sale de ahi y no de un numero.
DORSO: dict = {}


def _brazos_manos(esc: "AC.Esqueleto", esq: "AC.Escritor", lado: str,
                  flex: float) -> None:
    """El gancho de `_brazo`: coloca el brazo y despues los dedos.

    Se CUELA en `animar_clips._brazo` en vez de reescribir los cuatro clips.
    Los clips del cuerpo no se tocan ni un numero, asi que `test_fase71` sigue
    dando lo que daba, y los dedos salen de rebote.
    """
    _BRAZO_ORIGINAL(esc, esq, lado, flex)
    tabla, abanico = _tabla_dedos(esq.arm)
    _poner_dedos(esc, esq, lado, tabla, abanico)


_BRAZO_ORIGINAL = AC._brazo


# ---------------------------------------------------------------------------
# Comprobacion del `.glb` escrito. NO se da por hecho que la piel ha salido:
# un `.glb` sin `JOINTS_0`/`WEIGHTS_0` se abre en Godot, se ve, y no se deforma
# NADA. Es el fallo mas caro y el mas silencioso de todo el pipeline, asi que
# se lee el archivo escrito y se cuentan joints, pesos y vertices por dedo.
def verificar_glb(ruta: str) -> dict:
    import struct
    with open(ruta, "rb") as f:
        datos = f.read()
    total = struct.unpack_from("<III", datos, 0)[2]
    off, g, bin_ini = 12, None, 0
    while off < total:
        largo, tipo = struct.unpack_from("<II", datos, off)
        if tipo == 0x4E4F534A:
            g = json.loads(datos[off + 8:off + 8 + largo].decode("utf-8"))
        elif tipo == 0x004E4942:  # "BIN"
            bin_ini = off + 8
        off += 8 + largo
    if g is None:
        return {"ok": False, "error": "el .glb no tiene chunk JSON"}
    # LOS BYTES DEL BUFFER NO EMPIEZAN EN EL PRINCIPIO DEL ARCHIVO. Un `.glb` es
    # cabecera de 12 bytes + un chunk JSON + un chunk BIN, y el `byteOffset` de
    # los bufferView es relativo AL BUFFER, no al archivo. Leer sin sumar los 20
    # bytes de la cabecera da numeros que parecen plausibles y no lo son: con
    # 20 bytes de desfase, el recuento por hueso salia con indices de 121 en un
    # esqueleto de 49, y el informe decia "no hay dedos" con el dedo a la vista.
    # Este verificador leeria un `.glb` roto como si estuviera bien.
    out: dict = {"ok": True}
    out["nodos"] = [n.get("name", "") for n in g.get("nodes", [])]
    hijos = {i: list(n.get("children", [])) for i, n in enumerate(g["nodes"])}
    raices = [i for i in range(len(g["nodes"])) if i not in
              {c for v in hijos.values() for c in v}]
    arbol: list = []

    def _arbol(i: int, prof: int) -> None:
        if prof > 2:
            return
        arbol.append("  " * prof + (g["nodes"][i].get("name", "?") or "?")
                     + (" <%d hijos>" % len(hijos[i]) if len(hijos[i]) > 4
                        else ""))
        for c in hijos[i]:
            _arbol(c, prof + 1)

    for r in raices:
        _arbol(r, 0)
    out["arbol"] = arbol
    skins = g.get("skins", [])
    out["pieles"] = len(skins)
    out["huesos"] = len(skins[0].get("joints", [])) if skins else 0
    nombres: list = []
    if skins:
        for j in skins[0].get("joints", []):
            nombres.append(g["nodes"][j].get("name", ""))
    out["nombres_huesos"] = nombres
    prim = g["meshes"][0]["primitives"][0]
    at = prim.get("attributes", {})
    out["JOINTS_0"] = "JOINTS_0" in at
    out["WEIGHTS_0"] = "WEIGHTS_0" in at
    out["atributos"] = sorted(at.keys())
    for clave in ("TEXCOORD_0",):
        if clave not in at:
            out["ok"] = False
            out.setdefault("faltan", []).append(clave)
    # Cuantos vertices SKUEDE cada hueso de dedo, leyendo el buffer.
    mallas = []
    for m in g["meshes"]:
        for pr in m["primitives"]:
            mallas.append(pr)
    for pr in mallas:
        if "JOINTS_0" not in pr["attributes"]:
            continue
        ji = pr["attributes"]["JOINTS_0"]
        acc = g["accessors"][ji]
        bv = g["bufferViews"][acc["bufferView"]]
        # El `componentType` lo escribe el exportador en el ACCESOR, no en el
        # bufferView (los dos son validos en glTF, pero el bufferView no lo
        # lleva y leerlo ahi revienta con KeyError). Y `JOINTS_0` sale como
        # UNSIGNED_BYTE (5121) porque 49 huesos caben en un byte: es legal y
        # Godot lo importa bien, pero no se puede asumir 5123.
        ancho = {5121: 1, 5123: 2, 5125: 4}[acc["componentType"]]
        base = bin_ini + bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        out["verts"] = acc["count"]
        cuenta = {}
        # Leer 4 bytes como uint32 aqui es un error que no avisa: con
        # `JOINTS_0` en UNSIGNED_BYTE (que es lo que escribe el exportador
        # porque 49 huesos caben en un byte) salia un numero de hueso enorme
        # y el recuento por dedo salia VACIO, o sea "no hay dedos", que es
        # justo la conclusion que no hay que poder sacar de un asset.
        formato = {1: "<B", 2: "<H", 4: "<I"}[ancho]
        for v in range(acc["count"]):
            o = base + v * ancho * 4      # VEC4 de indices
            for c in range(4):
                j = struct.unpack_from(formato, datos, o + c * ancho)[0]
                cuenta[j] = cuenta.get(j, 0) + 1
        out["influencias_por_vert"] = {nombres[i2]: c for i2, c in cuenta.items()
                                       if i2 < len(nombres)}
    # El wrap del sampler: CLAMP (33071) en vez de REPEAT (10497) es una costura
    # garantizada, y es invisible en el `.glb` (el sampler es un entero).
    wraps: list = []
    for mat in g.get("materials", []):
        for clave, tex in mat.get("pbrMetallicRoughness", {}).items():
            if isinstance(tex, dict) and "index" in tex:
                wraps.append(g["textures"][tex["index"]].get("sampler"))
        if "normalTexture" in mat:
            tex = mat["normalTexture"]
            if isinstance(tex, dict) and "index" in tex:
                wraps.append(g["textures"][tex["index"]].get("sampler"))
    samps = [g.get("samplers", [])[s] if s is not None and s < len(g.get("samplers", []))
             else {"wrapS": 10497, "wrapT": 10497} for s in wraps]
    out["wraps"] = [{"wrapS": s.get("wrapS", 10497), "wrapT": s.get("wrapT", 10497)}
                    for s in samps]
    out["envuelve"] = all(w["wrapS"] == 10497 and w["wrapT"] == 10497 for w in out["wraps"])
    out["texturas"] = len(g.get("images", []))
    out["animaciones"] = sorted(a.get("name", "") for a in g.get("animations", []))
    for largo in out["animaciones"]:
        pass
    out["ok"] = bool(out["JOINTS_0"] and out["WEIGHTS_0"] and out["pieles"] == 1
                     and out["huesos"] >= 49 and out["envuelve"]
                     and out["animaciones"] == ["attack", "die", "idle", "walk"])
    return out


# ---------------------------------------------------------------------------
# Render de la mano. Sin esto se vuelve a cambiar todo a ciegas, que es
# exactamente como se rompio la animacion tres veces. Cycles por CPU: EEVEE
# necesita GPU y en headless no la hay.
def render_png(arm: object, carpeta: str) -> list:
    """CUATRO PNG, y no son un adorno: sin una imagen de la mano, cambiar la
    flexion de un dedo es volver a cambiar cosas a ciegas, que es exactamente
    como se rompio la animacion tres veces seguidas.

      - `mano_reposo` y `mano_ataque`: lo que pide el encargo. La misma mano,
        dos instantes, para ver si los dedos se leen.
      - `codo`: el codo DOBADO a 90 grados, en una pose que no esta en ningun
        clip. Es la prueba de que el LOOP y la BANDA hacen su trabajo: con una
        malla de cajas, aqui se ve el codo aplastado en una arista, y eso es lo
        que se reportaba como "manos raras" aunque el defecto estuviera en el
        brazo.
      - `cuerpo`: el personaje entero de frente, para mirar la silueta.

    Cycles por CPU: EEVEE necesita GPU y en headless no la hay, y sin render no
    hay manera de mirar nada.
    """
    escena = bpy.context.scene
    escena.render.engine = "CYCLES"
    escena.cycles.device = "CPU"
    escena.cycles.samples = 20
    escena.cycles.use_denoising = False
    escena.render.resolution_x = 640
    escena.render.resolution_y = 640
    mundo = bpy.data.worlds.new("Fondo")
    mundo.use_nodes = True
    mundo.node_tree.nodes["Background"].inputs[0].default_value = (0.10, 0.11, 0.14, 1.0)
    mundo.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    escena.world = mundo
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.lens = 70.0
    cam = bpy.data.objects.new("Cam", cam_d)
    escena.collection.objects.link(cam)
    escena.camera = cam
    luz_d = bpy.data.lights.new("Luz", "AREA")
    luz_d.size = 1.0
    luz_d.energy = 220.0
    luz = bpy.data.objects.new("Luz", luz_d)
    escena.collection.objects.link(luz)
    relleno_d = bpy.data.lights.new("Relleno", "AREA")
    relleno_d.size = 2.0
    relleno_d.energy = 60.0
    relleno = bpy.data.objects.new("Relleno", relleno_d)
    escena.collection.objects.link(relleno)
    salida: list = []
    cuerpo = bpy.data.objects["Cuerpo"]
    deps = bpy.context.evaluated_depsgraph_get()

    def puntos_de(bonetes: tuple) -> list:
        """Los vertices del mundo que manda alguno de esos huesos, YA POSADOS.

        Es la unica manera de encuadrar bien:apuntar con un numero de distancia
        a ojo sale con la camara dentro de la palma o con la mano en un rincon,
        y un render malo no sirve ni para dar el visto bueno ni para decidir. Con los
        puntos reales se calcula la caja y la camara se pone a la distancia que
        hace que quepa.
        """
        evaluada = cuerpo.evaluated_get(deps)
        base = cuerpo.matrix_world
        out: list = []
        for v in evaluada.data.vertices:
            mejor = ""
            peso = 0.0
            for g in v.groups:
                if g.weight > peso:
                    peso = g.weight
                    mejor = evaluada.vertex_groups[g.group].name
            if mejor in bonetes:
                out.append(base @ v.co)
        return out

    def tirar(nombre: str, foco: Vector, dist: float, arriba: Vector,
              lateral: Vector) -> None:
        objetivo: Vector = foco
        cam.location = objetivo + lateral * dist + arriba * dist
        d = (objetivo - cam.location).normalized()
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        luz.location = objetivo + lateral * dist * 0.6 + arriba * dist * 1.2
        luz.rotation_euler = (objetivo - luz.location).to_track_quat("-Z", "Y").to_euler()
        relleno.location = objetivo - lateral * dist
        relleno.rotation_euler = (objetivo - relleno.location).to_track_quat("-Z", "Y").to_euler()
        ruta = os.path.join(carpeta, "%s.png" % nombre)
        escena.render.filepath = ruta
        escena.render.image_settings.file_format = "PNG"
        bpy.ops.render.render(write_still=True)
        salida.append(ruta)
        print("[MOD] render %s" % ruta)

    def con_clip(nombre_clip: str, t: float) -> None:
        acc = bpy.data.actions.get(nombre_clip)
        arm.animation_data.action = acc
        if hasattr(acc, "slots") and len(acc.slots):
            arm.animation_data.action_slot = acc.slots[0]
        f0, f1 = [int(v) for v in acc.frame_range]
        bpy.context.scene.frame_set(f0 + int(round((f1 - f0) * t)))
        bpy.context.view_layer.update()

    # --- la mano, en reposo y en el tajo
    cam_d.lens = 60.0
    mano_dedos = tuple(["Hand.R"] + ["%s.%s.R" % (d, f) for d in DEDOS
                                     for f in FALANGES])
    for etiqueta, nombre_clip, t in (("recta", None, 0.0),
                                     ("reposo", "idle", 0.0),
                                     ("ataque", "attack", 0.60)):
        if nombre_clip is None:
            # La mano RECTA, con los dedos sin doblar: es el render que prueba
            # que los dedos TIENEN GEOMETRIA. Con los dedos ya en curva, un
            # dedo que no exista y un dedo que este pegado a la palma se ven
            # igual, y el render no dice nada.
            if arm.animation_data:
                arm.animation_data.action = None
            AC._reposo(arm, AC.Esqueleto(arm), AC.Escritor(arm))
            bpy.context.view_layer.update()
        else:
            con_clip(nombre_clip, t)
        pts = puntos_de(mano_dedos)
        bajo = Vector((min(p.x for p in pts), min(p.y for p in pts),
                       min(p.z for p in pts)))
        alto = Vector((max(p.x for p in pts), max(p.y for p in pts),
                       max(p.z for p in pts)))
        foco = (bajo + alto) * 0.5
        # La diagonal de la caja, no su lado mayor: con el lado mayor una mano
        # de 16 cm se encuadra a 7 cm y la camara se mete DENTRO de la palma.
        # A 1,75 diagonales con objetivo de 60 mm, la caja ocupa unos dos tercios
        # del encuadre: se ve la mano entera y con margen. Con 1,1 la mano se salia.
        tam = (alto - bajo).length * 1.75
        dist: float = tam
        print("[MOD] mano %s: caja %.3f x %.3f x %.3f m | encuadre a %.2f m"
              % (etiqueta, alto.x - bajo.x, alto.y - bajo.y, alto.z - bajo.z,
                 dist))
        # DE PERFIL, no de frente. La flexioon de los dedos se lee en la
        # SILUETA: mirando la mano de frente (desde el dorso) los dedos curls
        # quedan ocultos detras de la palma y el render sale una plancha. De
        # perfil se ve la falange, la falange y el nudillo, que es justo lo que
        # hay que mirar. La camara va al lado de fuera del cuerpo (-X para la
        # derecha), un poco por delante (-Y, el pulgar) y un poco por encima.
        # El plano en el que se doblan los dedos lo forman la direccion del dedo
        # y la NORMAL de la palma. Mirar de perfil ES mirar por la NORMAL de ese
        # plano, o sea desde el FRENTE del personaje y un poco por encima
        # (-Y, +Z): ahi la flexion se lee en la silueta, falange por falange.
        # Mirando desde fuera del cuerpo (-X) se ve el dorso de la mano y los
        # dedos se doblan HACIA el muslo, o sea escondidos detras de la mano:
        # el render sale una plancha con cuatro rayas y no dice nada.
        tirar("mano_" + etiqueta, foco, dist,
              Vector((0.0, 0.0, 0.20)), Vector((0.0, -1.0, 0.42)))
    # --- LA MANO DE ESPALDAS, Y POR QUE ESTA RENDERS.
    #
    # El encuadre de arriba mira POR EL NORMAL DEL PLANO EN EL QUE SE DOBLAN LOS
    # DEDOS, y en ese plano los cinco dedos estan uno al lado del otro: mirados
    # de perfil se ven curvos (que es lo que hay que ver para la flexion) pero no
    # se ven SEPARADOS. Un dedo que se solapa con el suyo no tiene grosor, y sin
    # ver el grosor no se puede decir si la mano esta bien. Este encuadre mira
    # desde AFUERA, o sea el dorso de la mano, que es donde se ve si hay cinco
    # dedos o hay uno y medio.
    if arm.animation_data:
        arm.animation_data.action = None
    AC._reposo(arm, AC.Esqueleto(arm), AC.Escritor(arm))
    bpy.context.view_layer.update()
    pts = puntos_de(mano_dedos)
    bajo = Vector((min(p.x for p in pts), min(p.y for p in pts),
                   min(p.z for p in pts)))
    alto = Vector((max(p.x for p in pts), max(p.y for p in pts),
                   max(p.z for p in pts)))
    foco = (bajo + alto) * 0.5
    tirar("mano_dorso", foco, (alto - bajo).length * 1.7,
          Vector((0.0, 0.0, 0.12)), Vector((-1.0, -0.30, 0.10)))
    cam_d.lens = 70.0

    # --- el codo a 90 grados: la prueba del LOOP
    con_clip("idle", 0.0)
    esq = AC.Escritor(arm)
    esc = AC.Esqueleto(arm)
    esc.h = {pb.name: pb.bone for pb in arm.pose.bones}
    hombro = esc.cabeza("UpperArm.R")
    flex: float = math.radians(100.0)
    d1 = Vector((math.sin(0.17), 0.0, -math.cos(0.17)))
    d2 = girar(d1, Vector((1.0, 0.0, 0.0)), -flex)
    esq.poner("UpperArm.R", hombro, d1)
    esq.poner("LowerArm.R", hombro + d1 * esc.brazo_sup, d2)
    esq.poner("Hand.R", hombro + d1 * esc.brazo_sup + d2 * esc.brazo_inf, d2)
    esq.clave(0)
    bpy.context.view_layer.update()
    codo = hombro + d1 * esc.brazo_sup
    # A 0,55 m y no a 0,42: a 42 cm la camara se mete dentro del antebrazo y el
    # render sale un manchas rosa sin silueta, que es justo lo que hace falta
    # para juzgar un codo.
    tirar("codo_90", codo, 0.55, Vector((0.0, 0.0, 0.30)),
          Vector((1.0, -1.0, 0.0)))

    # --- el cuerpo entero
    con_clip("idle", 0.0)
    tirar("cuerpo_frente", Vector((0.0, 0.0, 0.95)), 4.2,
          Vector((0.10, 0.0, 0.16)), Vector((0.0, -1.0, 0.0)))
    # DE PERFIL, que el de frente no lo cuenta. De frente se lee la anchura (los
    # hombros, la cadera) y de perfil la SILUETA, que es donde se ven los
    # problemas de verdad: una barriga, un hombro caido, una mano que sale de lado
    # sin querer. Con los dos juntos hay algo que mirar.
    tirar("cuerpo_perfil", Vector((0.0, 0.0, 0.95)), 4.2,
          Vector((0.10, 0.0, 0.16)), Vector((1.0, 0.0, 0.0)))
    return salida


def girar(v: Vector, eje: Vector, angulo: float) -> Vector:
    if abs(angulo) < 1e-12:
        return v.copy()
    from mathutils import Matrix as _M
    return (_M.Rotation(angulo, 3, eje.normalized()) @ v).normalized()


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
## Las seis siluetas. No son seis modelos distintos: es la MISMA malla con
## distinta corpulencia y distinto reparto de tinta, para que el juego no tenga
## seis personajes iguales y para que las manos (lo unico que se va a mirar) sean
## IDENTICAS en las seis. Lo que cambia es el numero, no la topologia.
PERFILES: dict = {
    "guerrero": {"girth": 1.10, "color": "#b03a2e", "color2": "#3a3a44", "g": 0},
    "arquero": {"girth": 0.95, "color": "#3f7a45", "color2": "#4a3a24", "g": 1},
    "clerigo": {"girth": 1.02, "color": "#d8d4c6", "color2": "#c9a227", "g": 2},
    "mago": {"girth": 0.90, "color": "#3a4a8f", "color2": "#7a4ab0", "g": 3},
    "daguero": {"girth": 0.93, "color": "#5a2a6e", "color2": "#241a2a", "g": 4},
    "bandido": {"girth": 0.86, "color": "#6b5a34", "color2": "#2f2a20", "g": 5},
}


def argumentos() -> list:
    if "--" not in sys.argv:
        print("[MOD] faltan argumentos: salida.glb [opciones]")
        sys.exit(2)
    return sys.argv[sys.argv.index("--") + 1:]


def main() -> int:
    t0: float = time.time()
    a = argumentos()
    salida: str = a[0]
    clase: str = "guerrero"
    girth: float = 0.0
    color: str = ""
    color2: str = ""
    alto: float = ALTO
    render: bool = False
    informe_ruta: str = ""
    i = 1
    while i < len(a):
        if a[i] == "--clase":
            clase = a[i + 1]
            i += 2
        elif a[i] == "--girth":
            girth = float(a[i + 1])
            i += 2
        elif a[i] == "--color":
            color = a[i + 1]
            i += 2
        elif a[i] == "--color2":
            color2 = a[i + 1]
            i += 2
        elif a[i] == "--alto":
            alto = float(a[i + 1])
            i += 2
        elif a[i] == "--informe":
            informe_ruta = a[i + 1]
            i += 2
        elif a[i] == "--render":
            render = True
            i += 1
        else:
            print("[MOD] opcion desconocida: %s" % a[i])
            return 2
    perfil = PERFILES.get(clase, PERFILES["guerrero"])
    if not girth:
        girth = perfil["girth"]
    color = color or perfil["color"]
    color2 = color2 or perfil["color2"]
    os.makedirs(TMP, exist_ok=True)
    os.makedirs(os.path.dirname(salida) or ".", exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = AC.FPS
    bpy.context.scene.render.fps_base = 1.0

    # 1) Texturas ------------------------------------------------------------
    t: float = time.time()
    tex = hornear_texturas(color, color2, perfil["g"], clase)
    t_tex: float = time.time() - t
    for clave in ("albedo", "normal", "orm"):
        d = tex[clave]
        print("[MOD] textura %-7s %dx%d | salto de cierre col %.4f (un pixel: "
              "%.4f, cociente %.2f) | fila %.4f / %.4f (%.2f) | %s"
              % (clave, d["lado"], d["lado"], d["salto_col"], d["paso_col"],
                 d["cociente_x"], d["salto_fil"], d["paso_fil"],
                 d["cociente_y"], "ENVUELVE" if d["envuelve"] else "NO ENVUELVE"))
    for clave in ("mascara",):
        pass
    if not all(tex[k]["envuelve"] for k in ("albedo", "normal", "orm")):
        print("[MOD] ERROR: una textura no envuelve; la costura saldra en "
              "pantalla y no la caza ningun test")
        return 5

    # Las regiones, que es lo que hace que esto sea un personaje y no un maniqui
    # con rayas. El porcentaje es de la TEXTURA, no de la malla: dice cuanto
    # peso le toca a cada material, y un material a 0,0% es una region que no se
    # esta pintando.
    print("[MOD] REGIONES: %d materiales en una textura de %d, en %d bandas de V"
          % (len(tex["regiones"]), TEX_BASE, len(BANDAS)))
    for r in tex["regiones"]:
        print("[MOD]   %-13s rug %.2f | metal %.0f%% | grano %.3f | tono %.2f | "
              "%7d px (%5.2f%% de la textura)"
              % (r["material"], r["rugosidad"], 100 * r["metalicidad"],
                 r["grano"], r["tono"], r["pixeles"], r["porcentaje"]))
    print("[MOD]   mapa de regiones: %s (para mirarlo, no para jugar)"
          % tex["mascara"]["ruta"])
    sin_pintar: list = [r["material"] for r in tex["regiones"]
                        if r["porcentaje"] < 0.05]
    if sin_pintar:
        print("[MOD] AVISO: materiales sin pintar: %s" % ", ".join(sin_pintar))

    # 2) Malla ---------------------------------------------------------------
    t = time.time()
    m, inf = construir_malla(PROP, girth)
    t_malla: float = time.time() - t
    c = m.cuenta()
    print("[MOD] malla: %d vertices, %d triangulos, %d con peso, max %d pesos "
          "por vertice" % (c["vertices"], c["triangulos"], c["con_peso"],
                           c["max_pesos"]))
    print("[MOD] presupuesto por entidad: %d de 30000 triangulos (%.0f%%)"
          % (c["triangulos"], 100.0 * c["triangulos"] / 30000.0))
    if c["triangulos"] > 30000:
        print("[MOD] ERROR: se pasa del presupuesto de la fase 49")
        return 6
    if c["triangulos"] >= 900000 * 0.5:
        print("[MOD] AVISO: la malla se lleva medio mundo")
    suma_puros: int = sum(inf["dedos"].values())
    print("[MOD] dedos: %d huesos, %d vertices al 100%% de su falange, %d "
          "compartidos en el LOOP" % (len(inf["dedos"]), suma_puros,
                                       sum(inf["dedos_loop"].values())))
    for nm in sorted(inf["dedos"]):
        if nm.endswith(".R"):
            print("[MOD]   %-12s %3d v puros, %3d v en el loop"
                  % (nm, inf["dedos"][nm], inf["dedos_loop"][nm]))
    if suma_puros == 0:
        print("[MOD] ERROR: ningun dedo tiene geometria propia")
        return 7
    print("[MOD] LOOP y BANDA por articulacion (lo que evita que el giro "
          "aplaste la malla):")
    for l in inf["loops"]:
        if l["miembro"] not in ("brazo_.L", "pierna_.L"):
            continue
        bucle: bool = len(l["huesos"]) > 1
        reparto: str = " ".join(
            "%s %d%%" % (h, round(100 * w))
            for h, w in zip(l["huesos"], l["pesos"]))
        print("[MOD]   %-10s junta %d | %d anillos | %d en la banda | %s%s"
              % (l["miembro"], l["junta"], l["anillos"], l.get("en_banda", 0),
                 reparto, "   <- LOOP" if bucle else ""))
    # LA RAIZ, CONTRA EL TORSO. El anillo de la raiz de cada tubo tiene que caer
    # DENTRO del torso, y eso no lo caza ningun test: si asoma, en el render sale
    # una aleta o una costura, que es justo lo que se reporto. Se imprime para
    # que el numero se pueda MIRAR cuando se cambia un perfil.
    for ra in inf.get("raices", []):
        print("[MOD]   raiz %-10s z %.3f | x %.3f + radio %.4f = %.4f | el torso "
              "llega a %.4f | %s"
              % (ra["miembro"], ra["z"], ra["x"], ra["radio"],
                 ra["x"] + ra["radio"], ra["torso_rx"],
                 "dentro" if ra["x"] + ra["radio"] < ra["torso_rx"] else "ASOMA"))

    # 3) Esqueleto y piel ----------------------------------------------------
    t = time.time()
    # EL BIND TIENE QUE HACERSE CON EL ESQUELETO EN SU POSE DE REPOSO. Si se
    # hiciera con el ultimo clip escrito, las inverse-bind saldrian de un
    # cadaver y la malla se deformaria desde ahi. Es la septima trampa de
    # `tools/rig.py`, y aqui se evita por construccion: todavia no hay ningun
    # clip escrito cuando se hace el bind.
    arm = crear_esqueleto("Rig", PROP)
    AC.ORDEN[:] = orden_completo()
    piel = aplicar_piel(m, arm, tex)
    t_piel: float = time.time() - t
    cuerpo = bpy.data.objects["Cuerpo"]
    print("[MOD] esqueleto: %d huesos = 19 del juego + %d de dedo (5 dedos x 3 "
          "falanges x 2 manos) | piel: %d grupos"
          % (len(arm.data.bones), len(arm.data.bones) - 19, piel["grupos"]))
    print("[MOD] reparto de peso por hueso (el mayor es el que manda):")
    for nombre, val in sorted(piel["histograma"].items(), key=lambda kv: -kv[1])[:8]:
        print("[MOD]   %-14s %6.1f" % (nombre, val))

    # 4) Clips ---------------------------------------------------------------
    t = time.time()
    AC._brazo = _brazos_manos
    esc = AC.Esqueleto(arm)
    print("[MOD] pierna %.4f u (muslo %.4f + espinilla %.4f) | zancada "
          "%.4f u | frames del walk %d (%.4f s)"
          % (esc.pierna, esc.muslo, esc.espinilla, 2.0 * esc.semizancada,
             esc.frames_walk(), esc.duracion_walk()))
    for nombre_clip, n_frames in (("idle", 49),
                                  ("walk", esc.frames_walk()),
                                  ("attack", 20), ("die", 29)):
        TOTAL_FRAMES[nombre_clip] = n_frames
        {"idle": AC.escribir_idle, "walk": AC.escribir_walk,
         "attack": AC.escribir_attack, "die": AC.escribir_die}[nombre_clip](
            arm, esc, n_frames)
    for linea in AC.verificar(arm, esc):
        print("[MOD] %s" % linea)
    AC._reposo(arm, esc, AC.Escritor(arm))
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    AC._accion_testigo(arm)
    t_clips: float = time.time() - t

    # 5) Medidas de los clips, con el mismo algoritmo que el test ------------
    # `_dedos_por_frame` mide lo que el encargo pide: CUANTO se cierra la mano
    # en cada clip. Si el idle no cierra la mano, el trabajo no esta hecho, y
    # este numero lo dice sin depender de que alguien mire un PNG.
    medidas = medir_dedos(arm)
    for k in sorted(medidas):
        print("[MOD] dedos en '%-18s' curl del medio %5.1f deg (0 recto, 90 "
              "media flexion, 150 puño) | DIP %.1f deg | recorrido en el clip "
              "%.1f deg | pulgar %.1f deg"
              % (k, medidas[k]["medio"], medidas[k]["dip"],
                 medidas[k]["recorrido"], medidas[k]["pulgar"]))
        print("[MOD] dedos en '%-18s' maximo del clip %.1f deg"
              % (k, medidas[k].get("medio_max", medidas[k]["medio"])))

    # 6) Exportar ------------------------------------------------------------
    t = time.time()
    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    op = {"filepath": salida, "export_format": "GLB", "export_apply": True,
          "export_animations": True, "export_animation_mode": "ACTIONS",
          "export_skins": True, "export_try_sparse_sk": False, "export_yup": True}
    desconocidos = sorted(k for k in op if k not in props and k != "filepath")
    if desconocidos:
        print("[MOD] AVISO: opciones que no existen: %s" % ", ".join(desconoc))
    bpy.ops.export_scene.gltf(**{k: v for k, v in op.items() if k in props})
    # La accion testigo (la que el exportador deja fuera, ver
    # `animar_clips._accion_testigo`) se recorta del `.glb` SOLO si ha salido.
    # En este pipeline no sale: el exportador se lleva las cuatro y descarta la
    # testigo por no tener-keyframes, que es justo lo que se queria. Se
    # comprueba en vez de asumirlo, porque si un dia salen cinco clips el juego
    # veria un estado de mas.
    v_pre = verificar_glb(salida)
    if AC.TESTIGO in v_pre["animaciones"]:
        if not AC._recortar_clip(salida, AC.TESTIGO):
            print("[MOD] ERROR: la accion testigo se ha quedado en el .glb")
            return 4
    elif v_pre["animaciones"] != ["attack", "die", "idle", "walk"]:
        print("[MOD] ERROR: clips en el .glb %s" % v_pre["animaciones"])
        return 4
    else:
        print("[MOD] la accion testigo no llego al .glb: no hay que recortarla")
    t_export: float = time.time() - t

    v = verificar_glb(salida)
    print("[MOD] .glb: %d huesos | piel %s | JOINTS_0 %s | WEIGHTS_0 %s | "
          "atributos %s | %d imagenes | wraps %s"
          % (v["huesos"], v["pieles"], v["JOINTS_0"], v["WEIGHTS_0"],
             ",".join(v["atributos"]), v["texturas"], v["wraps"]))
    for linea in v["arbol"]:
        print("[MOD] .glb: %s" % linea)
    print("[MOD] .glb: animaciones %s" % ", ".join(v["animaciones"]))
    dedos_glb = {k: n for k, n in v.get("influencias_por_vert", {}).items()
                 if k.split(".")[0] in ("pulgar", "indice", "medio", "anular",
                                        "menique")}
    print("[MOD] .glb: vertices influenciados por hueso de dedo (derecha): %s"
          % ", ".join("%s=%d" % (k, n) for k, n in sorted(dedos_glb.items())))
    if not v["ok"]:
        print("[MOD] ERROR: el .glb no cumple (piel, wrap, 33 huesos o clips)")
        return 8

    renders: list = render_png(arm, os.path.dirname(salida) or ".")
    t_total: float = time.time() - t0
    print("[MOD] TIEMPOS: texturas %.1f s | malla %.1f s | piel %.1f s | clips "
          "%.1f s | export %.1f s | TOTAL %.1f s"
          % (t_tex, t_malla, t_piel, t_clips, t_export, t_total))
    if informe_ruta:
        informe = {"clase": clase, "girth": girth, "color": color,
                   "color2": color2, "alto": alto, "malla": c, "texturas": tex,
                   "huesos": len(arm.data.bones), "dedos": inf["dedos"],
                   "dedos_loop": inf["dedos_loop"], "loops": inf["loops"],
                   "dedos_por_clip": medidas, "glb": v, "renders": renders,
                   "regiones": tex["regiones"], "bandas": BANDAS,
                   "mascara": tex["mascara"]["ruta"],
                   "tiempos": {"texturas": t_tex, "malla": t_malla,
                               "piel": t_piel, "clips": t_clips,
                               "export": t_export, "total": t_total}}
        with open(informe_ruta, "w") as f:
            json.dump(informe, f, indent=1, default=str)
        print("[MOD] informe: %s" % informe_ruta)
    print("[MOD] OK %s" % salida)
    return 0


def medir_dedos(arm: object) -> dict:
    """Cuanto se cierra la mano en cada clip, en GRADOS, sobre el esqueleto.

    Es la medicion que hace falta y que no hay: si el idle no cierra la mano, el
    encargo no esta hecho, y eso se lee en un numero y no en una sensacion. Se
    mide el ANGULO que hace la falange distal con la proximal en el esqueleto
    REAL, que es el mismo dato que se veria en un PNG pero en numero.
    """
    out: dict = {}
    for nombre in ("idle", "walk", "attack", "die"):
        acc = bpy.data.actions.get(nombre)
        if acc is None:
            continue
        arm.animation_data.action = acc
        if hasattr(acc, "slots") and len(acc.slots):
            arm.animation_data.action_slot = acc.slots[0]
        f0, f1 = [int(v) for v in acc.frame_range]
        n: int = 40
        medios: list = []
        pulgares: list = []
        dips: list = []
        for i in range(n + 1):
            bpy.context.scene.frame_set(f0 + int(round((f1 - f0) * i / float(n))))
            bpy.context.view_layer.update()
            medios.append(_curl(arm, "medio.3.R"))
            pulgares.append(_curl(arm, "pulgar.3.R"))
            dips.append(_flexion(arm, "medio.3.R", "medio.2.R"))
        out[nombre] = {"medio": medios[0], "recorrido": max(medios) - min(medios),
                       "pulgar": pulgares[0], "pulgar_recorrido":
                       max(pulgares) - min(pulgares),
                       "medio_max": max(medios), "dip": dips[0]}
    # A la pose de reposo, para que el numero de la izquierda tenga contra que
    # compararse. Y hay que SOLTAR la accion antes: con la accion puesta, el
    # `frame_set` de abajo la vuelve a evaluar y se lee la pose del `die`, no la
    # de reposo (medido: daba 48 grados de curl con la mano recta).
    if arm.animation_data:
        arm.animation_data.action = None
    AC._reposo(arm, AC.Esqueleto(arm), AC.Escritor(arm))
    bpy.context.view_layer.update()
    out["reposo_del_asset"] = {"medio": _curl(arm, "medio.3.R"),
                               "pulgar": _curl(arm, "pulgar.3.R"),
                               "recorrido": 0.0, "dip":
                               _flexion(arm, "medio.3.R", "medio.2.R")}
    return out


def _curl(arm: object, distal: str) -> float:
    """Grados que la punta del dedo se separa de la linea de la mano.

    Es la medida que importa: 0 es el dedo recto, 90 es un nudillo recto a media
    flexion y 150 es un puño. La articulacion por articulation esta en
    `_flexion`; esta es la que dice si la mano CIERRA.
    """
    pb = arm.pose.bones["Hand.R"]
    mano = (pb.tail - pb.head).normalized()
    d = arm.pose.bones[distal]
    return math.degrees(mano.angle((d.tail - d.head).normalized()))


def _flexion(arm: object, distal: str, previa: str) -> float:
    a = arm.pose.bones[distal]
    b = arm.pose.bones[previa]
    return math.degrees((a.tail - a.head).angle(b.tail - b.head))


if __name__ == "__main__":
    sys.exit(main())
