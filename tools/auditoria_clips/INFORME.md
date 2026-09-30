# Auditoría de los clips del modelo

Síntoma auditado: *«al caminar simplemente es como si flotara y solo tiene las manos levantadas abiertas como siempre»*.

Medido sobre el esqueleto de los `.glb` con `seek` + `get_bone_global_pose` (orientación global, no la pista). Se recorre un ciclo entero de cada clip.

## Números

| número | valor | de dónde sale |
|---|---|---|
| ciclo del clip `walk` (s) | 1.0417 | `Animation.length` |
| ciclo en reloj de juego (s) | 0.2193 | ciclo / ritmo(6.0, 0.9) |
| ritmo que cancela el patinaje | 4.75 | fórmula del código |
| **pasadas por segundo** | **9.12** | 2 pisadas / ciclo real |
| zancada de una pisada (u de esqueleto) | 0.7392 | rango Z del `Foot.L` |
| zancada de una pisada (m de mundo) | 0.6653 | zancada x escala 0.9 |
| recorrido del muslo en un ciclo | 124.9° | orientación global |
| recorrido del hombro en un ciclo | 120.6° | orientación global |
| apertura del hombro respecto de reposo | 36.2° | |
| desplazamiento vertical de la cadera (u) | 0.0277 | rango Y de `Hips` |
| desplazamiento horizontal de la cadera (u) | 0.0000 | rango XZ |
| deriva de la cadera en un ciclo (u) | 0.0000 | último - primero |
| altura del pie (rango Y, u) | 0.1506 | |
| salto en la costura del bucle | 0.23° | |
| salto más fuerte dentro del ciclo | 1.19° | |
| instantantes con la pose cambiada | 236 de 241 | guardia propio |

## Las cuatro preguntas, una por una

**a) ¿Los clips mueven los brazos o solo las piernas?** Mueven el húmero y poco más. En `walk`, `UpperArm.L/R` tienen 31 keys y se separan de la pose de reposo; `Shoulder.L/R`, `LowerArm.L/R` y `Hand.L/R` no tienen pista o tienen UNA key, o sea que se quedan clavados. El detalle hueso por hueso, con la separación en grados, está en la tabla de la sección siguiente.

**b) ¿Cuál es la pose de reposo?** La de la sección `Pose de reposo`: NO es la del `die` (a `rig.py` se le llama a `_poner_en_reposo` al final), es la A de la malla, con los brazos abiertos a 40° de la vertical. Sin animación, esa es la pose que se ve.

**c) ¿Ciclan?** Importados, NO: los cuatro clips salen con `LOOP_NONE`. El bucle lo pone el juego en ejecución (`player.gd:_preparar_clips`), y solo en el jugador. La costura del clip, aun así, está bien cerrada.

**d) ¿La cadera se desplaza?** La pista de posición de `Hips` solo varía en Y: es el rebote vertical. X y Z son constantes, o sea que **NO hay movimiento de raíz** y el personaje NO se mueve dos veces. Los pies tampoco tienen pista de posición.

## (a) Los brazos, pista por pista y hueso por hueso

| hueso | idle: keys | idle: desv. reposo | walk: keys | walk: desv. reposo | walk: recorrido | walk: ángulo sobre la vertical |
|---|---|---|---|---|---|---|
| `Hips` | 19 | 0.0° | 31 | 0.0° | 0.0° | 180°-180° |
| `Spine` | 22 | 0.8° | 1 | 1.7° | 1.7° | 178°-178° |
| `Chest` | 50 | 2.9° | 32 | 4.9° | 19.1° | 178°-178° |
| `Neck` | 30 | 2.1° | 1 | 4.9° | 19.1° | 178°-178° |
| `Head` | 59 | 1.2° | 1 | 4.9° | 19.1° | 178°-178° |
| `Shoulder.L` | — | 2.9° (clavado) | — | 4.9° (clavado) | 18.8° | 90°-90° |
| `UpperArm.L` | 29 | 28.6° | 31 | 36.2° | 120.6° | 13°-28° |
| `LowerArm.L` | 1 | 71.9° | 1 | 71.0° | 155.6° | 19°-44° |
| `Hand.L` | 1 | 71.9° | 1 | 71.0° | 155.7° | 18°-48° |
| `Shoulder.R` | — | 2.9° (clavado) | — | 4.9° (clavado) | 19.1° | 90°-90° |
| `UpperArm.R` | 29 | 28.5° | 31 | 36.3° | 120.4° | 13°-28° |
| `LowerArm.R` | 1 | 71.9° | 1 | 71.1° | 155.6° | 19°-44° |
| `Hand.R` | — | 71.9° (clavado) | — | 71.1° (clavado) | 155.8° | 18°-48° |
| `Thigh.L` | 1 | 0.0° | 32 | 31.4° | 124.9° | 1°-31° |
| `Shin.L` | 1 | 0.0° | 21 | 33.9° | 155.7° | 0°-34° |
| `Foot.L` | 1 | 0.0° | 33 | 21.5° | 94.7° | 53°-84° |
| `Thigh.R` | 1 | 0.0° | 32 | 31.4° | 125.0° | 1°-31° |
| `Shin.R` | 1 | 0.0° | 21 | 35.4° | 125.7° | 0°-35° |
| `Foot.R` | 1 | 0.0° | 32 | 22.5° | 76.1° | 52°-84° |

`keys` es lo que se puede LEER de la pista, no lo que declara el recurso. `desv. reposo` son los grados de separación entre la pose del clip y la pose de reposo del hueso, y `(clavado)` avisa de que el hueso no se aparta de ella. `—` en la columna de `keys` es OTRA cosa: que el clip no tiene pista de ese hueso.

Lectura de la tabla:

- `Shoulder.L`: recorrido 18.82°, separación de la pose de reposo 4.86°.
- `Shoulder.R`: recorrido 19.05°, separación de la pose de reposo 4.86°.
- `LowerArm.L`: recorrido 155.57°, separación de la pose de reposo 71.03°.
- `LowerArm.R`: recorrido 155.60°, separación de la pose de reposo 71.08°.
- `Hand.L`: recorrido 155.70°, separación de la pose de reposo 71.03°.
- `Hand.R`: recorrido 155.75°, separación de la pose de reposo 71.08°.

O sea, y esto es lo que importa para el síntoma: **el hombro NO se anima, el antebrazo NO se dobla y la muñeca NO gira.** Los tres se quedan clavados en la pose del rig durante todo el clip. Lo único que se mueve del brazo es el húmero, y con una sola bisagra, la del hombro. En una marcha real el codo se dobla y se endereza un poco con cada zancada; aquí no, y un brazo que no se dobla se lee como una madera colgada.

### Dónde está la mano, en números

`sobre la cadera` es la altura de la mano menos la de la cadera: en NEGATIVO la mano cuelga por debajo de la cadera, que es un brazo colgando. `del eje` es la distancia lateral al eje del cuerpo. Cuando hay dos valores, son el mínimo y el máximo del clip.

| pose | hueso | sobre la cadera (u) | del eje (u) |
|---|---|---|---|
| reposo (sin animación) | `Hand.L` | +0.094 | 0.512 |
| reposo (sin animación) | `Hand.R` | +0.094 | 0.512 |
| idle | `Hand.L` | +0.006 / +0.007 | 0.131 / 0.149 |
| idle | `Hand.R` | +0.006 / +0.007 | 0.150 / 0.131 |
| walk | `Hand.L` | -0.006 / +0.064 | 0.174 / 0.181 |
| walk | `Hand.R` | -0.006 / +0.065 | 0.181 / 0.174 |

## (b) Pose de reposo del esqueleto (sin animación)

`ángulo` son los grados que el EJE del hueso se separa de la vertical colgante: 0° es el brazo pegado al cuerpo, 45° la A, 90° la T. Es el eje del hueso (`basis.y`), no la resta de cabezas: en este rig los huesos de brazo arrancan desplazados del padre y con la resta salen 90°, o sea una T que el modelo no tiene.

| hueso | ángulo de la vertical | abducción | cabeza (u) |
|---|---|---|---|
| `Hips` | 180.0° | +180.0° | (0.000, 0.952, 0.000) |
| `Spine` | 180.0° | +180.0° | (0.000, 1.102, 0.000) |
| `Chest` | 180.0° | +180.0° | (0.000, 1.302, 0.000) |
| `Neck` | 180.0° | +180.0° | (0.000, 1.503, 0.000) |
| `Head` | 180.0° | +180.0° | (0.000, 1.623, 0.000) |
| `Shoulder.L` | 90.0° | +90.0° | (0.050, 1.453, 0.000) |
| `UpperArm.L` | 40.0° | +40.0° | (0.170, 1.453, -0.000) |
| `LowerArm.L` | 40.0° | +40.0° | (0.383, 1.199, -0.000) |
| `Hand.L` | 52.2° | +40.0° | (0.512, 1.046, -0.000) |
| `Shoulder.R` | 90.0° | -90.0° | (-0.050, 1.453, 0.000) |
| `UpperArm.R` | 40.0° | -40.0° | (-0.170, 1.453, -0.000) |
| `LowerArm.R` | 40.0° | -40.0° | (-0.383, 1.199, -0.000) |
| `Hand.R` | 52.2° | -40.0° | (-0.512, 1.046, -0.000) |
| `Thigh.L` | 1.4° | +1.4° | (0.100, 0.952, 0.000) |
| `Shin.L` | 0.0° | +0.0° | (0.110, 0.531, 0.000) |
| `Foot.L` | 74.9° | -0.0° | (0.110, 0.100, 0.000) |
| `Thigh.R` | 1.4° | -1.4° | (-0.100, 0.952, 0.000) |
| `Shin.R` | 0.0° | -0.0° | (-0.110, 0.531, 0.000) |
| `Foot.R` | 74.9° | +0.0° | (-0.110, 0.100, 0.000) |

- `Hand.L` en reposo: **+0.094 u respecto de la cadera** y a 0.512 u
  del eje del cuerpo. La cadera está a 0.952 u del suelo y el
  modelo mide 1,90: un brazo de verdad colgando deja la mano
  varios centímetros POR DEBAJO de la cadera.
- `Hand.R` en reposo: **+0.094 u respecto de la cadera** y a 0.512 u
  del eje del cuerpo. La cadera está a 0.952 u del suelo y el
  modelo mide 1,90: un brazo de verdad colgando deja la mano
  varios centímetros POR DEBAJO de la cadera.

## (c) Bucle

| clip | duración (s) | `loop_mode` importado |
|---|---|---|
| `idle` | 2.0417 | 0 |
| `walk` | 1.0417 | 0 |
| `attack` | 0.8333 | 0 |
| `die` | 1.2083 | 0 |

Costura del bucle de `walk`: 0.23° de salto al cerrar el ciclo
contra 1.19° del salto más fuerte DENTRO del ciclo. La costura está
por debajo, así que el clip CIERRA bien y no hay tirón en el
empalme. Lo que hay es que el clip no cicla hasta que el código lo
dice.

Quién lo pone: los cuatro clips llegan con `LOOP_NONE` del
importador, y tanto `player.gd:_preparar_clips` como
`enemy.gd:_preparar_clips` los ponen a `LOOP_LINEAR` en
`idle`/`walk`/`attack` y a `LOOP_NONE` en `die`, en tiempo de
ejecución. Es un parche sobre un dato del asset, no una propiedad
del clip: si se cuelga un `.glb` por una ruta que no pase por
ninguno de los dos, no cicla. La tabla de la sección siguiente lo
comprueba en las dos entidades.

## (d) Movimiento de raíz

Pistas de POSICIÓN de cada clip. Si el `Hips` se desplazara en X o
en Z el personaje avanzaría con la animación y con el `CharacterBody`
 a la vez, y eso se ve como patinar.

| clip | hueso | keys | rango X (u) | rango Y (u) | rango Z (u) | deriva del ciclo (u) |
|---|---|---|---|---|---|---|
| `idle` | `Hips` | 18 | 0.0000 | 0.0116 | 0.0000 | 0.0000 |
| `walk` | `Hips` | 30 | 0.0000 | 0.0277 | 0.0000 | 0.0000 |
| `attack` | `Hips` | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| `die` | `Hips` | 33 | 0.0000 | 0.7000 | 0.0000 | 0.7000 |

Pistas de posición en los cuatro clips: 4. Todas son de `Hips` y
ninguna de otro hueso. Conclusión: **no hay movimiento de raíz**.
Lo único que se mueve de sitio es la cadera en Y, y es el rebote
vertical de la marcha, de 0.0277 u (2.49 cm de mundo).

## ¿El movimiento de los huesos llega a la malla?

Esta es la pregunta que separa dos bugs distintos: «el clip no mueve
el brazo» y «el clip mueve el brazo y la malla no le hace caso». Se
responde despielzando la malla a mano —suma ponderada de las poses
globales de los huesos— en reposo y en el instante del clip donde el
húmero está más abierto, y midiendo cuánto se ha movido esa nube de
vértices. La pierna es el control.

| clip | nube | vértices | peso medio | desplazamiento (u) | centro en reposo (sobre cadera / del eje) | centro en el clip |
|---|---|---|---|---|---|---|
| `idle` | **mano.L** | 1825 | 0.25 | 1.1966 | -0.780 / 0.831 | -0.685 / 0.316 |
| `idle` | **mano.R** | 1771 | 0.25 | 1.1659 | -0.758 / 0.847 | -0.703 / 0.266 |
| `idle` | pierna.L | 5136 | 0.25 | 0.0047 | -0.660 / 0.266 | -0.665 / 0.266 |
| `idle` | pierna.R | 6791 | 0.25 | 0.0047 | -0.663 / 0.271 | -0.667 / 0.271 |
| `walk` | **mano.L** | 1825 | 0.25 | 1.1176 | -0.799 / 0.831 | -0.745 / 0.186 |
| `walk` | **mano.R** | 1771 | 0.25 | 1.2604 | -0.777 / 0.847 | -0.648 / 0.148 |
| `walk` | pierna.L | 5136 | 0.25 | 0.3050 | -0.678 / 0.266 | -0.570 / 0.255 |
| `walk` | pierna.R | 6791 | 0.25 | 0.3915 | -0.681 / 0.271 | -0.594 / 0.278 |

En `walk` la nube de la mano se desplaza 1.1176 u y la de la
pierna 0.3050 u: la proporción es **3.66**.

**La malla SÍ sigue a los huesos del brazo**: el centro de la
nube de la mano pasa de -0.799 u sobre la cadera y 0.831 u del
eje en reposo a -0.745 u y 0.186 u en el clip. O sea que los
brazos NO se ven abiertos mientras el clip corre: se ven
PEGADOS al cuerpo. Los abiertos son la pose de REPOSO, la que
se ve sin animación, y por eso la pregunta que queda abierta
es «¿dónde se está viendo al personaje sin animación?», no
«¿qué hace el clip».

Lo que sí es un defecto es la AMPLITUD, y aquí el número
fiable es el del HUESO, no el de la nube: el antebrazo se
separa 71° de la pose de reposo durante todo el clip. La causa
está en `tools/rig.py`: `BASE_BRAZO` se le suma a `UpperArm`,
`LowerArm` Y `Hand`, y como el antebrazo y la mano heredan la
del húmero, la corrección se TRIPLICA al bajar por la cadena.
Donde se quería quitar 33° al brazo, la mano se queda 71°
desvuelta: los brazos van pegados al cuerpo y cruzan hacia
dentro en vez de colgar. Y como el codo y la muñeca están
clavados, un brazo que no se dobla se lee como una madera.

OJO con el desplazamiento de la nube de la mano: prueba que la
malla sigue a los huesos, pero su valor absoluto NO es una
medida del brazo. La nube se arma por «vértices cuyo peso
sumado a huesos de brazo pasa de 0,5 y que están lejos del eje»,
y eso incluye manga y faldón. Para la amplitud del brazo el
número bueno es el del hueso, el de la tabla de la sección (a).

## Lo que ve el juego: jugador y enemigo, por su camino de verdad

| entidad | árbol activo | clip en uso | `loop` del `walk` | mano sobre la cadera (u) | mano del eje (u) |
|---|---|---|---|---|---|
| jugador | sí | `walk` | 1 | -0.006 / +0.064 | 0.174 / 0.180 |
| enemigo | sí | `walk` | 1 | -0.015 / +0.057 | 0.207 / 0.436 |

Referencia: la pose de REPOSO del esqueleto deja la mano a
**+0.094 u sobre la cadera y a 0.512 u del eje**.

- **jugador**: bucle del walk: LINEAL | la mano se mueve 0.0053 u de lado en el bucle medido
- **enemigo**: bucle del walk: LINEAL | la mano se mueve 0.2287 u de lado en el bucle medido

## Qué pesa más en la sensación de «flotar»

Las dos causas se miden por separado y NO valen lo mismo.

### (i) El patinaje GLOBAL — cuadra. El INSTANTÁNEO, no se puede medir

En un ciclo el cuerpo avanza 1.316 m y los pies cubren 1.331 m: la
diferencia es **-1.5 cm por ciclo**, o sea que a esta velocidad el
multiplicador ya cancela el desliz. Coincide con lo que mide la
fase 70 por su camino (sale -1,0 cm).

**Y lo que NO se pudo medir, que es la mitad del diagnóstico:**
la velocidad del pie INSTANTÁNEA durante el apoyo. Se intentó por
dos caminos y los dos fallan, así que no hay número honesto que
poner:

- Por «el punto más bajo del pie» (que es lo que hace la fase 70
  para el `dz`): la ventana cae en el BALANCEO, no en el apoyo, y
  sale `dz` positivo. La primera versión de esta auditoría sacaba
  «+2,58 u/s hacia delante» y lo leía como patinaje con el pie
  clavado.
- Por «el tramo más largo con el pie yendo hacia atrás»: da un
  tramo del 33 % del ciclo a **-1.561 u/s**, y ese número no
  cuadra con nada, porque con un umbral de signo tan pequeño el
  tramo se come el ruido y se fusiona con casi todo el ciclo.

La razón de fondo es que **este clip no tiene fase de apoyo**.
La trayectoria del pie es una oscilación suave antero-posterior
respecto de la cadera durante TODO el ciclo, sin tramo clavado:
es un clip procedural, no una captura de movimiento. El pie nunca
se queda quieto en el suelo, ni siquiera un instante. Eso no
aparece en la cuenta global (que sí cuadra, -1,5 cm) y es
justamente lo que el ojo lee como «flotar».

Cómo se arregla, si se quiere: hace falta una fase de apoyo de
verdad, o sea un tramo con la altura del pie constante. Eso no se
consigue estirando el ciclo: hay que cambiar la forma de la
trayectoria del pie en `tools/rig.py`, o sea re-rigear.


### (ii) La cadencia — CONFIRMADA, y es lo que más pesa

**9.12 pisadas por segundo.**

Un humano sprintea a 2,2-2,5 pisadas por segundo. A 9.1 el ciclo
dura 0.2193 s, o sea **13.2 frames de 60 Hz**: la pierna ya ha
terminado su ciclo y el otro la empezó cuando la pantalla todavía
no ha mostrado tres. El ojo promedia varias posiciones del pie en el
mismo frame y lo lee como deslizamiento aunque el pie esté clavado.
ESO es lo que se ve como «flotar», y no lo arregla el multiplicador
de ritmo: el multiplicador mantiene la relación entre el pie y el
cuerpo, y lo que hay que cambiar es cuántos pasos hay en un segundo.

### (iii) El rebote, que es el tercero y es pequeño

La cadera sube y baja 2.49 cm por ciclo. Para una zancada de
0.665 m eso es lo que toca, así que no es un error. Solo que al
venir con 9.1 pisadas por segundo se convierte en un temblor en
vez de en un rebote. Es un síntoma, no una causa.

## Las tres opciones de diseño, con su número

`pasos/s = velocidad / zancada`. Da igual cuántos pasos se metan en
un ciclo: la zancada por paso es la del clip, 0.665 m. Por eso
**«alargar el ciclo» NO cambia la cadencia**, y esa es la
conclusión menos intuitiva de esta auditoría. Lo que cambia la
cadencia es la VELOCIDAD o la ZANCADA, y la zancada es un dato del
rig, o sea de Blender.

| velocidad (m/s) | ritmo | ciclo real (s) | pasos/s | patinaje/ciclo (cm) |
|---|---|---|---|---|
| 1.28 | 1.00 | 1.0417 | 1.92 | +0.7 |
| 2.00 | 1.50 | 0.6944 | 2.88 | +5.8 |
| 3.00 | 2.25 | 0.4630 | 4.32 | +5.8 |
| 4.00 | 3.00 | 0.3472 | 5.76 | +5.8 |
| 4.50 | 3.50 | 0.2976 | 6.72 | +0.9 |
| 6.00 | 4.75 | 0.2193 | 9.12 | -1.5 |

Las tres opciones que se pusieron sobre la mesa, con su número:

**A. Bajar la velocidad de caminata del juego.** A la velocidad natural del
clip (1.2838 m/s) el ritmo cae a 1,0, el ciclo dura 1.0417 s y son
**1.93 pisadas por segundo**: una marcha normal, cero patinaje.
El precio es que `vel_mov` no es solo animación: es `move_and_slide`,
el alcance de la esquiva, el de la persecución del enemigo y la
distancia de cierre. A 1.28 m/s se cruzan 100 m en 78 s, y en un
juego de rol eso se siente lento. Con 3 m/s son 4.51 pisadas/s.

**B. Alargar el ciclo (más zancadas por ciclo).** NO cambia los
pasos/s y por lo tanto no arregla la cadencia. Lo que sí la
arregla es alargar la ZANCADA, y eso es re-rigear con más amplitud
de pierna: para bajar a 4 pisadas/s a 6 m/s hacen falta 1.50 m de
zancada, o sea **2.3 veces** la que trae el clip (0.665 m). Es un
superhéroe, no un hombre; y 6 m/s con zancada de 1.50 m es un
esprint, así que el clip tendría que ser un `run` re-rigeado, no
un `walk` alargado.

**C. Aceptar el trote rápido.** 9.12 pisadas/s, que es lo que hay
ahora. No es una decisión: es lo que pasa si no se decide nada, y
es justo lo que el usuario describe como «flotar».

Lo que sale de los números, SIN decidir: el problema de fondo es que
6,0 m/s es un esprint (21,6 km/h, 3,2 veces la altura del cuerpo por
segundo) y el clip es un paseo. Ninguna de las tres opciones sale
gratis, y la comparación justa es: A cuesta velocidad de juego, B
cuesta re-rigear en Blender (y aquí no hay Blender, ver más abajo),
y C es dejar el síntoma como está.

### Si hiciera falta re-rigear: qué y cuánto

En esta máquina **no hay Blender** (`~/Tools/` solo tiene godot), y
el rig se generó con `tools/preparar_modelo.py` corrido dentro de
Blender, así que re-rigear no se puede hacer aquí. Lo que haría
falta, y no es una estimación de horas sino una lista:

1. Instalar Blender 4.5 LTS (portable o paquete del sistema).
2. `~/Tools/blender/blender --background --python tools/preparar_modelo.py -- \`
   models/original.glb models/clase_*.glb 30000 1 40` para los seis.
3. Cambiar en `tools/rig.py` la amplitud de la pierna en `_walk`
   (hoy `Thigh: a * 0.55`) y el `BASE_BRAZO`, y volver a exportar.
4. Reimportar y volver a medir con ESTE informe: el diff de
   `pasos/s` y `patinaje` dice si ha servido.

El paso 3 es el que importa: sin tocar `rig.py` el re-rig reproduce
exactamente los mismos números, y eso ya se ha pagado una vez.

## Los seis modelos, los mismos números

| modelo | medible | ciclo walk (s) | muslo (°) | hombro (°) | `Hips` Y (u) | `Hips` XZ (u) | pasos/s a 6 m/s | zancada (u) |
|---|---|---|---|---|---|---|---|---|
| `res://models/clase_guerrero.glb` | sí | 1.0417 | 124.9 | 120.6 | 0.0277 | 0.0000 | 9.12 | 0.7392 |
| `res://models/clase_arquero.glb` | sí | 1.0417 | 124.9 | 120.6 | 0.0277 | 0.0000 | 9.12 | 0.7393 |
| `res://models/clase_clerigo.glb` | sí | 1.0417 | 124.9 | 120.7 | 0.0277 | 0.0000 | 9.12 | 0.7389 |
| `res://models/clase_daguero.glb` | sí | 1.0417 | 124.9 | 120.6 | 0.0277 | 0.0000 | 9.12 | 0.7393 |
| `res://models/clase_mago.glb` | sí | 1.0417 | 124.9 | 120.6 | 0.0277 | 0.0000 | 9.12 | 0.7391 |
| `res://models/bandido_rig.glb` | sí | 1.0417 | 125.4 | 110.6 | 0.0277 | 0.0000 | 9.12 | 0.7389 |

---

Generado por `tools/auditoria_clips.gd`. La medición vive en `tools/auditoria_clips/medidor.gd`, que es el mismo módulo que carga `tests/test_auditoria_clips.gd`: el número del informe y el del test salen de la misma línea.
