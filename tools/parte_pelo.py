"""El pelo y la barba como geometria. Ver `docs/CONTRATO_PARTES.md`.

QUE HACE Y POR QUE ESTE ARCHIVO EXISTE
--------------------------------------
El pelo es de las pocas cosas que cambian la SILUETA de un personaje mas que
cualquier textura, y la silueta es lo primero que detecta el ojo. Un elipsoide
liso es una cabeza de globo con casco: un personaje con pelo se lee como una
persona, y el mismo personaje sin pelo se lee como un maniqui aunque tenga los
ocho anillos, los nueve materiales y la PBR que envuelve.

ASI QUE AQUI NO HAY UN CASQUETE. Hay una masa y hay mechones, y la diferencia
concreta entre un casquete y un pelo son tres cosas que hace este archivo:

1. **La mechon se apoya en el craneo y CAE, no sale disparada.** Este es el
   fallo que la primera version de este archivo cometio, y se ve a un metro:
   las mechones crecian por la TANGENTE al elipsoide, y la tangente de una
   esfera en su ecuador es horizontal, asi que en los costados la mechon
   salia horizontal y en la cima salia vertical. El resultado eran254 pinchos
   radiales clavados en un huevo, que es un erizo de mar, no un pelo. Un pelo
   sale del craneo, RECORRE el craneo y despues cuelga. Por eso la punta de
   cada mechon no esta en una direccion, esta en un LUGAR de la superficie
   (`LINEA_PUNTAS`), y el camino se construye como una polilinea sobre el
   elipsoide que sale de ahi libre y hacia abajo. Eso es lo unico que separa
   un mechon de un clavo.

2. **Debajo de los mechones hay un SCALP, y es oscuro.** La mascara de
   materiales del script principal pinta la corona de la cabeza con METAL (un
   casco, ver `_pintar_mascara`), y el metal es claro. Un pelo oscuro sobre un
   casquete claro se lee como un erizo sobre un huevo, por muy bien repartidos
   que esten los mechones: lo que se ve entre ellos es el blanco. Asi que hay
   una capa de scalp pegada al craneo, dos milimetros por fuera, que cubre el
   craneo desde la linea del pelo hasta la cima y pinta con el material del
   pelo. Entre mechones se ve el SCALP, que es exactamente lo que pide el
   encargo ("mechas con las que se ve el scalp en las separaciones"), pero en
   vez de verse un casco se ve pelo por debajo. Y el pelo de verdad se lee
   asi: no se ve la piel entre los mechones, se ve el pelo que esta debajo.

3. **La barba pesa lo mismo que veinte mechones en la cabeza.** Es la mitad del
   trabajo visual de este archivo. Y la barba NO es un anillo de dientes: es
   un bloque. Tres o cuatro GRUESOS por lado, con las raices juntas, la masa
   llena y las puntas juntandose, que es lo que hace que un personaje con
   barba se reconozca a tres metros. Pondera el largo: una barba que llega al
   pecho es un personaje distinto que una que llega a la barbilla, asi que el
   largo es un dato (`LARGO_BARBA`), no un accidente de la curva.

LO QUE NO PASA AQUI, Y POR QUE
-----------------------------
- **El pelo no es un casco cerrado.** Ni un bloque continuo ni una chapa con
  lineas de mechones encima: la capa de scalp es OSCURA y va pegada al craneo
  (2 mm), o sea que no proyecta silueta propia, y la silueta la ponen los
  mechones, que salen de ella, se separan y se puntiaguan. El ojo busca "casco"
  en el CONTORNO, y en el contorno no hay scalp: hay mechones.

- **El pelo no intersecta el craneo.** Cada anillo se comprueba contra el
  elipsoide y se empuja hacia afuera (`Craneo.surface`). Sin eso, una mechon
  que nace en la nuca y baja por el occipucio se hunde en la cabeza y sale un
  agujero en la nuca, que en el render es una mancha negra.

- **El pelo no intersecta el cuello ni el pecho.** `FUERA_PETO` es la tabla
  del cuello y del pecho tal cual la tiene `torso_secciones` (copiada aqui
  porque las partes no dependen entre si), y toda mechon por debajo de
  `Z_BARBA_MIN` o por delante del cuello se recorta contra ella. Los numeros
  salen en el informe, que trae la caja del pelo para comparar con la de la
  armadura.

- **Pesa `{"Head": 1.0}` entero**, porque la cabeza se mueve con `Head` y el
  pelo con ella. Cero mezcla con `Neck`: una mechon con parte del peso en el
  cuello se despega de la cabeza al girar el cuello.

LA V DE LA TEXTURA
------------------
Se pide con `_v_tex("pelo", t)`, nunca escribiendo el numero de V a mano. OJO:
hoy `BANDAS` (en `modelo_humano.py`) NO tiene la entrada `"pelo"`, asi que
`_v_tex("pelo", t)` levanta `KeyError`. Este archivo NO toca `modelo_humano.py`
(es de otro dueno), asi que pide `"pelo"` y, si la banda no esta todavia, cae
al cinturon del torso, que es `cuero`: el material oscuro, rugoso y no
metalico mas parecido que ya existe. En cuanto se agregue `"pelo"` a `BANDAS`,
este archivo cambia solo. Ver `_V` y el informe de `aplicar`.

FIRMA
-----
    aplicar(m: Malla, p: dict, g: float, _v_tex: callable) -> dict

`p` acepta tres claves opcionales que el llamador puede pasar sin cambiar la
firma: `"pelo"` (multiplicador del largo, 1.0 = corto/medio), `"barba"`
(bool) y `"bigote"` (bool). Los tres tienen valor por defecto aqui.
"""
from __future__ import annotations

import math
import random
from mathutils import Vector

# ---------------------------------------------------------------------------
# LOS NUMEROS, que son datos del asset y no numeros magicos.
# ---------------------------------------------------------------------------
## Semilla. El contrato pide que dos builds con la misma semilla den el mismo
## modelo byte a byte, asi que el `random` va con semilla y no se siembra solo.
SEMILLA: int = 20260930

## LA CABEZA, medida contra el anillo a 1,755 que hace `construir_malla`
## (0,089 de semiancho, 0,104 de semiprofundidad). El craneo se modela con un
## elipsoide porque es lo que permite POSEER cualquier punto de la superficie
## con un `(psi, z)`, y la superficie es lo que hay que tocar para sembrar las
## raices. Comprobado el ajuste: a 1,700 el modelo da x 0,085 / frente -0,109 y
## el elipsoide da 0,0847 / -0,1099; a 1,650, -0,088 contra -0,0884. Lo que
## sobra, dos milimetros, los come el hundido de la raiz.
CRANEO_A: float = 0.089       # semiancho X
CRANEO_B: float = 0.104       # semiprofundidad Y (la cara mira al -Y)
CRANEO_C: float = 0.14445     # semialtura Z, de (1,8889 - 1,600) / 2
CRANEO_ZC: float = 1.74445    # centro en Z
CRANEO_YC: float = -0.011     # centro en Y: el craneo esta corrido a la cara

## LA CORRECCION DEL CRANEO, y por que este archivo la necesita. El elipsoide
## de arriba es una aproximacion de la tabla de anillos de la cabeza, y en la
## CORONA se queda corto hasta TRECE MILIMETROS: la cabeza real se cierra mas
## rapido que un elipsoide, asi que en 1,850 el modelo esta 13,3 mm por fuera de
## la elipsoide. Con el pelo pegado a la elipsoide (que es lo que se hacia
## antes) la capa de scalp se metia DENTRO de la cabeza y no se veia, y en el
## render salia el casco de metal de la mascara asomando por encima del pelo:
## el pelo oscuro sobre un casco claro, que es un erizo sobre un huevo.
##
## La correccion esta MEDIDA, no estimada: se comparo el radio de la elipsoide
## con el radio de la tabla de anillos en cinco azimuts y nueve alturas, y se
## quedo con el peor caso de cada altura (que es el que hay que cubrir). Abajo de
## 1,740 el elipsoide es el que se pasa, y por eso la correccion es 0 y no
## negativa: ahi el pelo apoya en la elipsoide y sobra.
CORRECCION: tuple = (
    (1.600, 0.004), (1.660, 0.007), (1.700, 0.002), (1.740, 0.000),
    (1.780, 0.005), (1.820, 0.011), (1.850, 0.014), (1.878, 0.008),
    (1.889, 0.004),
)
## El grosor de la capa de scalp por fuera de la piel. Dos milimetros: es una
## capa de pelo, no un casco, y si se pone mas se ve el escalon en la linea.
ESCALP: float = 0.002
## El relieve de esa capa, en metros, en la coronilla. 0,006 son seis milimetros
## de pelo aplastado, que es lo que separa un monticulo de pelo de un globo.
ESCALP_RELIEF: float = 0.014

CIMA_Z: float = 1.8889        ## la cima de la cabeza, el dato de `PROP`
## La corona del pelo, que es donde acaba la capa de scalp. Un centimetro por
## debajo de la cima, porque a la cima el elipsoide se cierra y un anillo ahi
## sale de 4 centimetros de ancho: la tapa de un dedo y ya esta.
CIMA_PELO: float = 1.8780

## El pelo NO sube mas de 0,048 sobre la cima. Medido, no puesto a ojo: con el
## pelo a ras de la calota el personaje se ve rapado; con el pelo 0,08 mas
## arriba se ve con gorro de papier. 0,048 es el sitio donde la linea del pelo
## rompe la silueta sin inventarse un gorro.
Z_TOPE: float = CIMA_Z + 0.048

## La barba no baja de aqui, y no es un gusto: el pecho llega a 0,121 de
## semiprofundidad a la altura de los hombros y el cuello se estrecha a 0,060
## justo antes de la cabeza, de modo que por debajo de 1,555 el volumen que hay
## delante es el del PECHO, y una barba que llega ahi se mete DENTRO del peto.
Z_BARBA_MIN: float = 1.555

## El grosor de una mechon. No es un pelo: es un MECHON, o sea el grupo de
## pelos que el ojo lee como una unidad. Un pelo de verdad a esta escala
## (cabeza de 0,29) seria mas delgado que un pixel y no se veria. Un mechon de
## 0,0085 son 17 mm de grosor, que es lo que hace que en el render se lean
## cinco o seis mechas en vez de un copo.
R_MECHON: float = 0.0085
## La mechon de la CALOTA es mas gruesa, y por una razon concreta: las de la
## linea son las que definen la silueta y tienen que verse separadas, y las de
## la calota son las que HUBIERAN de tapar el casco si no hubiera la capa de
## scalp, asi que pueden ser anchas y solaparse. Menos pelo, mas masa.
R_CALOTA: float = 0.0105
## La barba es mas gruesa: son menos mechas y mas voluminosas, y por eso pesa
## mas en la lectura del personaje que veinte mechas en la cabeza.
R_BARBA: float = 0.0160
## La mitad del ancho que se le deja a cada lado del cuerpo para que la punta
## no se mezcle con la siguiente.
TAPER: tuple = (1.00, 0.98, 0.90, 0.70, 0.34)
## La barba afina MENOS: una barba que se afila como un pelo se lee como un
## peine de dientes. Con estos numeros la punta sigue siendo un punto pero el
## cuerpo de la mechon se mantiene lleno.
TAPER_BARBA: tuple = (1.00, 1.00, 0.95, 0.78, 0.40)
## Donde cae cada anillo de la curva. El ultimo esta antes de la punta porque
## la punta es el VERTICE del camino y el anillo final lo cierra `tapar`: un
## anillo de radio cero son cinco vertices en el mismo punto y cinco
## cuadrilateros degenerados, y en el render sale un aviso de geometria sucia
## por veinte triangulos que no pintan nada.
T_MECHON: tuple = (0.00, 0.28, 0.55, 0.79, 0.94)
## Caras por seccion del tubo. Cinco es el minimo con el que un tubo lee
## redondeado de perfil; con cuatro se ve el diametro en la silueta.
LADOS: int = 5
## El paso de `_curva`: quanto avanza cada tramo de un camino que gira. 0,022
## son 22 mm, y con mechones de 6 a 10 cm salen cinco tramos parejos. Si el paso
## fuera de 40 mm, cuatro tramos se quedan cortos para la longitud y la curva se
## ve angulosa; si fuera de 8 mm, la misma mechon gasta quince anillos.
PASO: float = 0.022

## LA LINEA DEL PELO, en grados a la redonda de la cabeza (0 = la frente, 90 =
## el lado, de cara al ojo, 180 = la nuca) con la altura de la linea. NO es un
## gorro: baja en las sienes y en los costados y vuelve a bajar en la nuca, que
## es lo que separa una melena de una calva con flequillo. De frente la frente
## es alta (1,836), a los 62 grados baja a 1,812 en la sien, y en la nuca
## llega a 1,690, que es la altura de donde le sale el cuello. Una linea recta
## seria un casquete.
## Y POR QUE LA LINEA ESTA TAN BAJA, que es el numero mas importante de este
## archivo y no es una cuestion de gusto. La mascara de materiales del script
## principal (que es de otro dueno) pinta la CABEZA con un CASCO de metal desde
## la v 0,615 de la banda para arriba, y la banda va de 1,600 a 1,8889: el
## metal arranca en 1,7777. O sea que por encima de 1,7777 la cabeza es un casco
## BLANCO, y cualquier linea de pelo mas alta que eso deja una franja blanca en
## la frente que el ojo lee como una calva rapada con un casco puesto, que es
## justo el defecto que este archivo viene a arreglar. Con la linea a 1,836 (que
## es donde estaria la frente de una cabeza normal) salia UNA BANDA BLANCA de
## seis centimetros entre el pelo y la visera, y en el render parecia que el
## personaje llevaba un gorro.
##
## Por eso el pelo baja a 1,770 en la frente y a 1,778 en la sien, y por eso hay
## un FLEQUILLO que cuelga por delante de esa linea. La frente que queda al
## descubierto son 3 centimetros, que es poco, y el flequillo se come la mitad.
## Si el dueno de la mascara baja el casco o mete el pelo como material, esto es
## una tabla y se cambia aqui.
LINEA_PELO: tuple = (
    (0.0, 1.770), (30.0, 1.776), (60.0, 1.778), (95.0, 1.774),
    (125.0, 1.756), (155.0, 1.726), (180.0, 1.692),
)
## EL FLEQUILLO, que es lo que tapa la linea de pelo de verdad. Una linea de
## pelo es un BORDE, y un borde de pelo se lee como pelo si de el salen
## mechones hacia delante. Sin flequillo, la linea es un corte y el pelo se lee
## como un casquete encajado en la cabeza, por muy(textura que tenga.
##
## La salida del flequillo es su propia tabla y no `SALIDA_MECHA` porque el
## flequillo no barre: CUELGA. Y cuelga hacia DELANTE y abajo, que es lo que
## hace que de frente se vea una cortina de pelo sobre la frente y no un
## flequillo de lado.
SALIDA_FLEQUILLO: tuple = (6.0, -0.030)
VUELO_FLEQUILLO: tuple = (0.0, -0.20, -0.98)
## DONDE ABANDONA EL CRANEO CADA MECHON, y esta es la tabla que hace que esto
## sea pelo y no un peine de clavos clavados en un huevo. En vez de darle una
## direccion a la punta, se le da el LUGAR de la superficie donde la mechon se
## DESPEGA: la que nace a `q` grados recorre el craneo hasta `barrido` grados
## mas y a la altura `zs`, y ahi suelta y cuelga.
##
## Que la forma de esta tabla sea la que es, no es un capricho, y sale de medir
## el recorrido sobre el elipsoide. De frente la mechon se despega ARRIBA y va
## hacia atras (es como se peina la frente, y por eso el flequillo se ve de
## frente y no de perfil); en la sien suelta a la altura de la oreja; en el
## costado suelta mas abajo; en la nuca suelta casi en la nuca. Si la punta
## fuese siempre un poco mas atras que la raiz, la cabeza se veria con una
## capucha; si sueltase siempre en la misma altura, con un corte recto.
##
## Y por que un LUGAR y no la punta entera: la distancia sobre el craneo desde
## la linea de la frente hasta la nuca son 25 centimetros, y una mechon de 25
## centimetros dibujada con cinco anillos es un palo. Lo que se dibuja con cinco
## anillos es un RECORRIDO de 4 a 7 centimetros y luego el vuelo, que es recto y
## por eso se lee bien con pocos anillos.
SALIDA_MECHA: tuple = (
    (0.0, 54.0, 1.8700),     # el flequillo: sube y se va atras
    (30.0, 84.0, 1.8660),
    (60.0, 104.0, 1.8220),   # la sien: suelta a la altura de la oreja
    (90.0, 118.0, 1.7780),
    (120.0, 140.0, 1.7440),
    (150.0, 166.0, 1.6980),
    (180.0, 186.0, 1.6700),  # la nuca: suelta justo donde empieza el cuello
)
## LA DIRECCION DEL VUELO, o sea hacia donde se va la mechon cuando ya no apoya.
## Es un par `(y, z)` en el PLANO SAGITAL, y ser sagital es lo importante: en
## una elipsa, la tangente en el costado va hacia un LADO, y una mechon que
## vuela por ahi abre la cabeza ocho centimetros por lado y se ve un casquete de
## avispa. La y es hacia atras (positivo) y la z es hacia arriba. Cero x.
##
## Que suba en la frente y baje en la nuca es lo que hace que la cabeza tenga
## DOS lecturas y no una: de frente el flequillo se ve de punta (porque sube) y
## de perfil la nuca se ve colgando (porque cae). Con un solo valor para todo, o
## el flequillo parece un gorro o la nuca parece rapada.
VUELO: tuple = (
    (0.0, 0.52, 0.85),     # el flequillo: arriba y atras
    (30.0, 0.60, 0.80),
    (60.0, 0.85, -0.52),   # la sien: atras y abajo, por detras de la oreja
    (90.0, 0.58, -0.81),
    (120.0, 0.36, -0.93),
    (150.0, 0.16, -0.99),
    (180.0, 0.06, -1.00),  # la nuca: cae recta
)
## Y el vuelo de la CALOTA, que no mira la tabla: la calota va tumbada, y si
## obedece el `VUELO` de la frente (que sube) se levanta y el personaje se ve
## con un gorro. Esta va casi vertical para atras, que es como se peina de
## verdad el pelo de arriba.
VUELO_CALOTA: tuple = (0.0, 0.30, -0.95)
## Y DONDE ESTA LA RAYA, en grados a la redonda. No en el centro (0) sino a 14:
## una raya en el centro es simetrica y por eso no se ve (el ojo necesita una
## asimetria para leer una raya), y una raya muy separada del centro deja el
## lado de la raya rapado.
RAYA_G: float = 14.0
## LARGO DE LA MECHON en la linea, por la misma clave. Corto en la frente,
## largo en la nuca: es la melena, y es la silueta de atras la que mas cambia un
## personaje visto de perfil. 0,108 en la nuca deja la punta a unos 7
## centimetros de la linea de la nuca, que es donde le empieza el cuello.
LARGO_MECHA: tuple = (
    (0.0, 0.058), (40.0, 0.066), (80.0, 0.078), (120.0, 0.092), (180.0, 0.108),
)
## La parte del largo que se la pasa PEGADA al craneo antes de soltar. Ni todo
## ni nada: con todo, la mechon es una linea de puntos sobre la cabeza; con
## nada, sale disparada desde la raiz y otra vez el erizo de mar.
HUGO: float = 0.62
## La punta se separa de la piel mas de lo que estaba la raiz, y la razon es
## que el pelo se DESPEGA: pegado al craneo todo el rato, el pelo es una
## pintura. Con la punta a mas de un radio y medio del craneo, la mechon
## proyecta su propia sombra sobre la sien, que es la mitad de lo que hace que
## se lea pelo.
HOLGURA_PUNTA: float = 2.0
## Y la raiz se hunde. Un mechon que nazca pegado a la piel se ve, desde
## cualquier angulo, como un tubo que le crece de la cara. Hundirla tambien es
## lo que hace que el pelo no se despegue de la cabeza cuando `parte_cara` se
## monte y su craneo se aparte dos milimetros del elipsoide de aqui.
HOLGURA_RAIZ: float = 0.85
## La altura minima de la punta, por familia, para que ninguna mechon se clave
## en el cuello. Es un tope de seguridad: los largos de la tabla ya salen por
## encima, y lo que hace es que el dia que se alarguen no haya que repasar los
## numeros.
Z_MIN_PATILLA: float = 1.706
Z_MIN_CALOTA: float = 1.660

## Donde arranca la barba: la mandibula. En la punta (0 grados) casi en el
## fondo de la barbilla, y sube por la mandibula hasta juntarse con la patilla
## y con la nuca. Los dos numeros de los extremos casi coinciden a proposito: si
## no, se ve una discontinuidad en el angulo de la mandibula.
LINEA_BARBA: tuple = (
    (0.0, 1.638), (40.0, 1.643), (80.0, 1.655), (110.0, 1.670),
    (140.0, 1.688), (165.0, 1.708), (180.0, 1.726),
)
## El bigote, en la altura del labio superior y en un arco corto delante de la
## nariz. Es la parte mas delicate de la barba: si `parte_cara` pone una nariz o
## un labio que sobresalgan mas que el elipsoide, el bigote se queda DENTRO y
## no se ve. Por eso va corto y pegado, no largo y salido.
Z_BIGOTE: float = 1.664
BIGOTE_G: tuple = (30.0,)    # grados de apertura del arco del bigote

## Donde se siembra cada familia de mechas. NUMEROS, no constantes magicas.
N_LINEA: int = 30            ## la fila de la linea del pelo, la que define la silueta
N_CALOTA: int = 54           ## las que tiapan la calota, tumbadas hacia atras
N_CIMA: int = 5              ## las de la cima, las unicas que rompen el huevo
N_PATILLA: int = 4           ## por lado
N_FLEQUILLO: int = 13        ## el flequillo de la frente, en una sola fila
Z_MIN_FLEQUILLO: float = 1.740   ## no por debajo de la visera (que esta en 1,737)
## La barba va por GRUPOS, no por mechones sueltas: `BARBA` son los grupos y
## `POR_GRUPO` las mechones de cada grupo. Tres mechones con la raiz junta y
## la punta separada se leen como un mechon gordo; tres mechones sueltas en la
## mandibula se leen como tres clavos.
BARBA: int = 6
POR_GRUPO: int = 3
MENTON: int = 6
BIGOTE_GRUPOS: int = 2

## EL LARGO DE LA BARBA, que es un dato del personaje y no un accidente de la
## curva. 0,088 es una barba CORTA que llega cinco centimetros por debajo de la
## barbilla, y el numero sale de dos limites medidos, no de un gusto: con la
## barbilla a 1,649 la punta cae cerca de `Z_BARBA_MIN` (1,555), que es donde el
## pecho empieza a tragarsela, y si se sube de 0,13 la punta se mete en el
## peto. Si se baja de 0,05 desaparece la barba y el personaje vuelve a ser un
## hombre con la cara lisa, que es justo el defecto que viene a arreglar. La
## barba larga al pecho es OTRO personaje, y es otro dato, no este.
LARGO_BARBA: float = 0.077

## El cuello y el pecho por los que NO se puede meter una mechon, copiados de
## `torso_secciones` del script principal (que es de otro dueno) para que las
## partes no dependan entre si. Son (altura, semiprofundidad) y el `girth` lo
## escala igual que `construir_malla` lo escala con su `r()`. Arriba de 1,6025
## no hay nada: es la cabeza, y de eso se encarga el elipsoide.
FUERA_PETO: tuple = ((1.500, 0.120), (1.530, 0.118), (1.560, 0.082),
                     (1.600, 0.060))
Z_CUello: float = 1.6025

## La V del pelo. Se pide la banda `"pelo"`; si todavia no existe (hoy no
## existe: ver el docstring), se cae a esta franja del CINTURON del torso, que
## es `cuero`: el material oscuro, rugoso y no metalico mas parecido que ya
## esta en la mascara. Sin esta caida el pelo se pintaria con el material del
## CASCO (que es lo que hay en la corona, metal claro), que es exactamente lo
## que hace que el pelo se lea como un erizo sobre un huevo. La franja va de
## 0,290 a 0,360 de la banda del torso, que es donde la mascara pinta el
## cinturon (0,275 a 0,375), por dentro para no pisar la hebilla, que es
## `metal_oscuro` entre 0,695 y 0,805 de `u`: por eso el `u` del pelo no pasa
## de 0,66.
FRANJA_CINTURON: tuple = (0.290, 0.360)
## El `u` del pelo, para que las mechones no salgan todas en la misma columna
## de la textura y se puedan separar por matiz.
U_PELO: tuple = (0.02, 0.66)


def _tabla(pts: tuple, x: float) -> float:
    """Interpolacion lineal sobre una tabla `(x, y)` en `x` creciente.

    Se fija en los extremos: fuera de la tabla devuelve el primer o el ultimo
    valor, y no extrapola. Un pelo que se alarga por encima de la tabla y se
    va del craneo es peor que un pelo corto.
    """
    if x <= pts[0][0]:
        return pts[0][1]
    if x >= pts[-1][0]:
        return pts[-1][1]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x0 <= x <= x1:
            t: float = (x - x0) / (x1 - x0)
            return y0 + (y1 - y0) * t
    return pts[-1][1]


def _tabla3(pts: tuple, x: float) -> tuple:
    """Como `_tabla`, pero sobre tablas `(x, y, z)`."""
    if x <= pts[0][0]:
        return pts[0][1], pts[0][2]
    if x >= pts[-1][0]:
        return pts[-1][1], pts[-1][2]
    for (x0, y0, z0), (x1, y1, z1) in zip(pts, pts[1:]):
        if x0 <= x <= x1:
            t: float = (x - x0) / (x1 - x0)
            return y0 + (y1 - y0) * t, z0 + (z1 - z0) * t
    return pts[-1][1], pts[-1][2]


def _suave(x: float) -> float:
    """Smoothstep, que es la unica curva que no se nota en la silueta."""
    x = min(1.0, max(0.0, x))
    return x * x * (3.0 - 2.0 * x)


# ---------------------------------------------------------------------------
# EL CRANEO
# ---------------------------------------------------------------------------
class Craneo:
    """La superficie del craneo, que es de donde salen las raices.

    Es un elipsoide y no la tabla de anillos del modelo porque lo que hace falta
    no es la forma, es PODER SITUAR UN PUNTO CUALQUIERA DE LA SUPERFICIE: las
    raices se siembran por `(psi, z)` y de ahi sale una direccion y una normal.
    El ajuste contra la tabla real esta medido (docstring de `CRANEO_A`).

    El `girth` escala SOLO los dos radios, que es lo que hace `construir_malla`
    con su `r(rx), r(ry)`: las alturas y el desplazamiento de la cara no se
    escalan. Un guerrero es mas ancho, no mas alto.
    """

    def __init__(self, girth: float) -> None:
        f: float = 1.0 + (girth - 1.0) * 0.85
        self.a: float = CRANEO_A * f
        self.b: float = CRANEO_B * f
        self.c: float = CRANEO_C
        self.zc: float = CRANEO_ZC
        self.yc: float = CRANEO_YC
        self.girth: float = f

    def punto(self, psi: float, z: float) -> Vector:
        """El punto de la superficie en el azimuth `psi` y la altura `z`.

        `psi` va en radianes y 0 es la FRENTE (el -Y, que es a donde mira el
        personaje), asi que el `sin` va con +X y el `cos` con -Y. El eje Z del
        personaje es el `z` de la altura, o sea que el craneo esta tumbado.
        """
        w: float = (z - self.zc) / self.c
        s: float = math.sqrt(max(0.0, 1.0 - w * w))
        return Vector((self.a * s * math.sin(psi),
                       self.yc - self.b * s * math.cos(psi), z))

    def normal(self, p: Vector) -> Vector:
        """La normal AFUERA del elipsoide (el gradiente, normalizado)."""
        n = Vector((p.x / (self.a * self.a),
                    (p.y - self.yc) / (self.b * self.b),
                    (p.z - self.zc) / (self.c * self.c)))
        if n.length < 1e-12:
            return Vector((0.0, 0.0, 1.0))
        return n.normalized()

    def dentro(self, p: Vector) -> bool:
        d = Vector((p.x, p.y - self.yc, p.z - self.zc))
        return (d.x / self.a) ** 2 + (d.y / self.b) ** 2 + (d.z / self.c) ** 2 < 1.0

    def correccion(self, z: float) -> float:
        """Cuanto se queda corto la elipsoide a la altura `z` (ver `CORRECCION`)."""
        return _tabla(CORRECCION, z)

    def superficie(self, p: Vector, holgura: float) -> Vector:
        """Si `p` esta dentro del craneo, lo saca por la RADIAL y lo separa
        `holgura` de la piel.

        Se saca por la radial (la direccion desde el centro del elipsoide), no
        por la normal, porque por la radial se conserva la altura: una mecha que
        se hunde en la sien tiene que salir por la sien, no salir disparada
        hacia arriba. Y el numero que decide si esta dentro es
        `(x/a)^2 + (y/b)^2 + (z/c)^2 < 1`, no la longitud del gradiente, que es
        otra cuenta distinta y no avisa.
        """
        d = Vector((p.x, p.y - self.yc, p.z - self.zc))
        e: float = (d.x / self.a) ** 2 + (d.y / self.b) ** 2 + (d.z / self.c) ** 2
        if e >= 1.0 or e < 1e-12:
            return p.copy() + self.normal(p) * (holgura + self.correccion(p.z))
        k: float = 1.0 / math.sqrt(e)
        sup = Vector((d.x * k, self.yc + d.y * k, self.zc + d.z * k))
        return sup + self.normal(sup) * (holgura + self.correccion(p.z))

    def sobre(self, psi: float, z: float, holgura: float) -> Vector:
        """El punto de la superficie en `(psi, z)`, separado `holgura`."""
        return self.superficie(self.punto(psi, z), holgura)


# ---------------------------------------------------------------------------
# LA MECHA
# ---------------------------------------------------------------------------
def _marco(eje: Vector) -> tuple:
    """Marco ortonormal de un tubo. Copia de la idea de `modelo_humano.marco`
    (mismo criterio: marco DETERMINISTA, porque si el marco gira solo entre
    anillos el tubo se retuerce y la UV se enrolla)."""
    d = eje.normalized()
    ref = Vector((0.0, 0.0, 1.0))
    if abs(d.dot(ref)) > 0.94:
        ref = Vector((1.0, 0.0, 0.0))
    ex = ref.cross(d).normalized()
    return ex, d.cross(ex).normalized()


def _suavizar(pts: list) -> list:
    """Chaikin: una vuelta de corte de esquinas sobre la polilinea.

    Es OBLIGATORIO y no es estetica. La curva de las mechonas se recorre con
    `_cam`, que interpola por longitud de arco; si la polilinea tiene un cambio
    de direccion, la interpolacion se queda pegada al camino y sale un ANGULO
    en la silueta, que en una mechona es una rotura. Con Chaikin el angulo se
    corta antes de interpolar.

    Y por que Chaikin y no un Catmull-Rom, que es lo que se pondria primero: un
    Catmull-Rom hace la CRESTA en el punto donde gira la direccion, y la cresta
    se sale del camino. Con cuatro puntos de una barba, la punta salia veinte
    centimetros mas abajo de la que decia la tabla y se metia en el pecho; con
    las mechonas de la frente, la cabeza se le abria cuatro centimetros por
    lado. Chaikin solo puede cortar por dentro del camino: es la unica de las
    dos que no puede mentir.
    """
    nuevo: list = [pts[0].copy()]
    for a, b in zip(pts, pts[1:]):
        nuevo.append(a.lerp(b, 0.25))
        nuevo.append(a.lerp(b, 0.75))
    nuevo.append(pts[-1].copy())
    return nuevo


def _cam(pts: list, t: float) -> Vector:
    """El punto del camino a la fraccion `t` de su LONGITUD DE ARCO.

    Por longitud de arco y no por parametro porque los tramos del camino no
    miden lo mismo (una mechon pega 4 centimetros al craneo y vuela 3), y
    recorrerlos a paso de parametro meteria un anillo mas en el tramo corto que
    en el largo: la punta se veria achatada.
    """
    t: float = min(1.0, max(0.0, t))
    acum: list = [0.0]
    total: float = 0.0
    for a, b in zip(pts, pts[1:]):
        total += (b - a).length
        acum.append(total)
    if total < 1e-9:
        return pts[0].copy()
    meta: float = t * total
    for i in range(len(acum) - 1):
        if acum[i + 1] >= meta:
            span: float = acum[i + 1] - acum[i]
            f: float = 0.0 if span < 1e-9 else (meta - acum[i]) / span
            return pts[i].lerp(pts[i + 1], f)
    return pts[-1].copy()


def _cam_d(pts: list, t: float) -> Vector:
    """La tangente del camino por diferencia finita, que es lo bastante exacta
    para un marco y no mete ruido como laformula."""
    h: float = 0.02
    a = _cam(pts, max(0.0, t - h))
    b = _cam(pts, min(1.0, t + h))
    d = b - a
    if d.length < 1e-9:
        return Vector((0.0, 0.0, -1.0))
    return d.normalized()


def _curva(raiz: Vector, dirs: list, paso: float = 0.0) -> list:
    """Una polilinea que avanza a PASO CONSTANTE por una direccion que gira.

    El paso constante es lo unico que evita que la curva se dispare, y la razon
    es concreta: `_cam` es un Catmull-Rom, que entre dos puntos hace la cresta
    justo donde cambia la direccion. Si los puntos van a distancia fija del
    primero (que es lo natural de escribir) el primer tramo es corto y el
    segundo largo, y la cresta cae en el punto de giro: una barba de cuatro
    puntos le salia la punta veinte centimetros mas abajo de donde decia la
    tabla, y una mechon de la frente se le abria el lado ocho centimetros.

    `dirs` es una lista de direcciones YA NORMALIZADAS, una por tramo, y cada
    tramo dura lo mismo. Quien llama decide cuanto dura cada uno.
    """
    paso = paso if paso > 1e-6 else PASO
    out: list = [raiz.copy()]
    for d in dirs:
        out.append(out[-1] + d * paso)
    return out


def _mecha(m, camino: list, r0: float, pesos: dict, u0: float, rep_u: float,
           vt, taper: tuple) -> dict:
    """Un TUBO a lo largo del camino, afinado, y su punta tapada.

    `camino` es la polilinea que se recorre con Catmull-Rom. El radio de cada
    anillo sale de `taper` y el ultimo esta antes de la punta, que es el
    ultimo punto del camino y la cierra `tapar`: un anillo de radio cero son
    cinco vertices en el mismo punto y cinco cuadrilateros degenerados, y en el
    render sale un aviso de geometria sucia por veinte triangulos que no
    pintan nada.
    """
    v0: int = len(m.v)
    f0: int = len(m.f)
    camino = _suavizar(list(camino))
    ex, ey = _marco(_cam_d(camino, 0.02))
    anillos: list = []
    for i, t in enumerate(T_MECHON):
        c = _cam(camino, t)
        tg = _cam_d(camino, t)
        # Se reproyecta `ex` en el plano del anillo en vez de recalcular el
        # marco: es lo que evita que el tubo se retuerza cuando la curva dobla.
        a = ex - tg * ex.dot(tg)
        if a.length < 1e-7:
            a = ey - tg * ey.dot(tg)
        a.normalize()
        b = tg.cross(a).normalized()
        r: float = r0 * taper[i]
        anillo: list = []
        for j in range(LADOS):
            ang: float = math.tau * (j / LADOS)
            q = c + a * (math.cos(ang) * r) + b * (math.sin(ang) * r)
            anillo.append(m.vert(q, u0 + rep_u * t, vt(t), pesos))
        anillos.append(anillo)
    m.loftear(anillos)
    # Las dos tapas. La de la raiz hacia dentro (queda enterrada en el craneo y
    # no se ve nunca, pero deja la malla cerrada, que es lo que espera el
    # exportador) y la de la punta hacia fuera.
    m.tapar(anillos[0], camino[0], pesos, vt(0.0), -1)
    m.tapar(anillos[-1], camino[-1], pesos, vt(1.0), +1)
    return {"mechas": 1, "vertices": len(m.v) - v0, "triangulos": len(m.f) - f0}


def _caminar(craneo: Craneo, psi0: float, z0: float, dpsi: float, dz: float,
             dist: float) -> tuple:
    """El punto de la superficie a `dist` metros de `(psi0, z0)` avanzando
    `(dpsi, dz)`.

    Marcha en el espacio `(psi, z)` porque AHI esta la parametrizacion, y
    devuelve el punto 3D. Es lo que hace que las mechones de la calota tengan
    todas el MISMO recorrido sobre el craneo y no unas mas largas que otras:
    si la longitud se midiera enparametro, la mechona de la sien, que tiene
    mucho mas recorrido angular, saldia el doble de larga que la de la cima.
    """
    paso: int = 24
    prev = craneo.punto(psi0, z0)
    acum: float = 0.0
    for k in range(1, paso + 1):
        t: float = k / float(paso)
        p = craneo.punto(psi0 + dpsi * t, z0 + dz * t)
        acum += (p - prev).length
        prev = p
        if acum >= dist:
            return p, t
    return prev, 1.0


def _envolvente(craneo: Craneo, p: Vector, holgura: float) -> Vector:
    """La ENVOLVENTE del pelo: la caja estrecha en la que el pelo puede estar.

    Es una red, no un mecanismo: los caminos ya salen por dentro (sus puntos
    son de la superficie del elipsoide mas un radio), y esta red atrapa lo que
    se escapa de verdad, que es la punta de las mechonas de la linea y de la
    calota. Sin ella el pelo se abre por los lados como una avisa y la cabeza
    mide medio metro de ancho.

    Los tres limites, y por que estan donde estan:
      - los lados, a la semiancho del craneo en esa altura mas `holgura`: el
        pelo PUEDE standout un par de centimetros, que es lo que le da grosor
        a la cabeza, pero no mas.
      - atras, igual: la melena cuelga por detras de la nuca, no por la espalda.
      - por delante, PEGADO a la superficie, sin holgura: el pelo no asoma por
        delante de la frente, y una rebaba ahi es un fallo, no un estilo.
      - arriba, a `Z_TOPE`, que es el limite del encargo.
    """
    w: float = (p.z - craneo.zc) / craneo.c
    s: float = math.sqrt(max(0.0, 1.0 - w * w))
    lim: float = craneo.a * s + holgura
    out = p.copy()
    out.x = min(lim, max(-lim, out.x))
    out.y = min(craneo.yc + craneo.b * s + holgura, out.y)
    out.y = max(craneo.yc - craneo.b * s, out.y)
    out.z = min(Z_TOPE, out.z)
    return out


def _fuera_del_peto(p: Vector, girth: float) -> Vector:
    """Saca del cuello y del pecho lo que se meta.

    Se comprueba en la banda del cuello y del pecho, y en dos ejes: por delante
    (la Y, contra la tabla `FUERA_PETO`) y por abajo (la Z, contra
    `Z_BARBA_MIN`). Con las dos, el pelo no puede aparecer dentro del peto ni
    aunque la barba se alargue un dia. Es una red de seguridad, no el mecanismo
    principal: los numeros de la barba estan calculados para no necesitarlo.
    """
    if p.z > Z_CUello:
        return p
    z: float = max(p.z, Z_BARBA_MIN)
    sem: float = 0.060
    for (z0, ry0), (z1, ry1) in zip(FUERA_PETO, FUERA_PETO[1:]):
        if z0 <= z <= z1:
            t: float = (z - z0) / (z1 - z0)
            sem = ry0 + (ry1 - ry0) * t
            break
    limite: float = -sem * girth - 0.004
    if p.y < limite:
        return Vector((p.x, limite, z))
    return Vector((p.x, p.y, z))


# ---------------------------------------------------------------------------
# LA V. Se pide la banda "pelo" y, si todavia no esta, el cinturon.
# ---------------------------------------------------------------------------
class _V:
    """La V de la textura para el pelo.

    Se pide `_v_tex("pelo", t)` y NUNCA se escribe un numero de V a mano. Como
    `BANDAS` (en `modelo_humano.py`, que es de otro dueno y este archivo no lo
    toca) todavia no tiene la entrada `"pelo"`, la llamada levanta `KeyError` y
    aqui se cae al cinturon del torso, que es `cuero`. En cuanto se agregue la
    banda, esto deja de mirar la caida y el pelo se pinta con su material sin
    tocar este archivo. `propia` dice cual de los dos caminos se esta usando, y
    sale en el informe, porque un pelo pintado con el cinturon hay que saberlo.
    """

    def __init__(self, vtex) -> None:
        self.f = vtex
        self.propia: bool = True
        try:
            self.f("pelo", 0.0)
        except KeyError:
            self.propia = False

    def __call__(self, t: float) -> float:
        if self.propia:
            return self.f("pelo", t)
        lo, hi = FRANJA_CINTURON
        return self.f("torso", lo + (hi - lo) * min(1.0, max(0.0, t)))


# ---------------------------------------------------------------------------
# LA CAPA DE SCALP, que es lo que hay DEBAJO de los mechones
# ---------------------------------------------------------------------------
def _scalp(m, craneo: Craneo, pesos: dict, vt, filas: int, cols: int) -> dict:
    """La piel con pelo: una capa finísima pegada al craneo.

    NO es un casco, y por que no lo es: no proyecta silueta (va a dos milimetros
    del craneo, y el craneo ya esta ahi), no baja de la linea del pelo (el borde
    lo tapan las mechones de la linea, que cuelgan por fuera), y esta pintada
    con el MATERIAL DEL PELO, no con el del casco. Es lo que se ve ENTRE
    mechones, que es exactamente lo que el encargo pide que se vea, y es lo que
    evita que se vea el casco de metal claro de la corona.

    Es una rejilla polar sobre la superficie del elipsoide: las filas van de la
    linea del pelo a la cima siguiendo la forma de la linea, y las columnas
    dan la vuelta. La ultima fila esta en `CIMA_PELO`, un centimetro bajo la
    cima, porque a la cima el elipsoide se cierra y el anillo sale de 4
    centimetros: la tapa es un abanico de 26 triangulos y ya esta.
    """
    v0: int = len(m.v)
    f0: int = len(m.f)
    holgura: float = ESCALP
    # LA CAPA ESTA MELLADA, y no es un detalle. Con la capa lisa, las partes de
    # la coronilla que quedan al descubierto (del lado de la raya, que es donde
    # el pelo se peina para el otro lado) se veian como un DOMO LISO, y un domo
    # liso con pelo alrededor se lee como una calva con el pelo atado, que es
    # justo el defecto. Con la capa mellada, lo que se ve entre los mechones es
    # pelo aplastado, que es lo que se ve de verdad en una raya. Cuesta CERO
    # triangulos: es desplazar los vertices que ya existian.
    #
    # El ruido va con SU PROPIA semilla y no con la del pelo, para que cambiar
    # el numero de mechonas no mueva este ruido (y al reves): el contrato pide
    # que el build sea reproducible, y dos consumidores del `random` compartido
    # se desincronizan en cuanto uno de los dos cambia.
    ruido = random.Random(SEMILLA + 1)
    mellado: list = [[ruido.uniform(0.0, 1.0) for _ in range(cols)]
                     for _ in range(filas)]
    anillos: list = []
    for i in range(filas):
        t: float = (i / float(filas - 1)) ** 0.86
        anillo: list = []
        for j in range(cols):
            psi: float = math.tau * j / cols
            grados: float = math.degrees(psi) % 360.0
            if grados > 180.0:
                grados = 360.0 - grados
            z_linea: float = _tabla(LINEA_PELO, grados)
            z: float = z_linea + (CIMA_PELO - z_linea) * t
            # Mas relieve arriba que en la linea: en la linea la capa la tapan
            # los mechones y el relieve se ve como un escalon, y en la coronilla
            # es la capa la que se ve de verdad.
            h: float = holgura + ESCALP_RELIEF * t * t * mellado[i][j]
            anillo.append(m.vert(craneo.sobre(psi, z, h),
                                U_PELO[0] + (U_PELO[1] - U_PELO[0]) * (j / cols),
                                vt(0.5), pesos))
        anillos.append(anillo)
    m.loftear(anillos)
    # La tapa de la corona, con el centro un poco mas arriba para que no quede
    # un disco plano que se lea como la tapa de un tarro.
    centro = m.vert(craneo.sobre(0.0, CIMA_PELO + 0.0016, holgura), 0.5,
                    vt(1.0), pesos)
    for j in range(cols):
        k: int = (j + 1) % cols
        m.tri(centro, anillos[-1][j], anillos[-1][k])
    return {"mechas": 0, "vertices": len(m.v) - v0, "triangulos": len(m.f) - f0}


# ---------------------------------------------------------------------------
# LA PARTE
# ---------------------------------------------------------------------------
def aplicar(m, p, g, _v_tex) -> dict:
    """El pelo y la barba, como geometria propia. Pesa `{"Head": 1.0}` entero.

    `p` admite tres claves opcionales, sin cambiar la firma:
      - `"pelo"`:  multiplicador del largo del pelo (1.0 = el canonico).
      - `"barba"`: bool, si el personaje lleva barba (por defecto, si).
      - `"bigote"`: bool, si lleva bigote (por defecto, si, si lleva barba).

    Se siembran cuatro familias de pelo (la linea, la calota, la cima y las
    patillas) y tres de barba (la mandibula, el menton y el bigote), y el
    groso de la cabeza es la capa de scalp, con las mechones encima. Cada
    familia tiene su destino en `LINEA_PUNTAS` y dentro de la familia cada
    mechon se desvia un poco, que es lo que hace que el pelo se vea peinado y
    no moldeado.
    """
    craneo = Craneo(g)
    vt = _V(_v_tex)
    rng = random.Random(SEMILLA)
    pesos: dict = {"Head": 1.0}
    v_pelo: int = len(m.v)

    largo_pelo: float = float(p.get("pelo", 1.0))
    con_barba: bool = bool(p.get("barba", True))
    con_bigote: bool = bool(p.get("bigote", con_barba))

    informe: dict = {"mechas": 0, "vertices": 0, "triangulos": 0,
                     "banda": "pelo" if vt.propia else "cinturon (cuero)",
                     "barba": con_barba, "bigote": con_bigote,
                     "cajas": {}}

    def suma(d: dict, familia: str) -> None:
        """Acumula el total Y la caja de la familia.

        La caja por familia sale en el informe porque es el unico numero que
        dice QUE FAMILIA se esta yendo de su sitio: un pelo que se sale dos
        centimetros del craneo y una barba que se mete en el pecho se ven igual
        en el total, y se distinguen aqui.
        """
        informe["mechas"] += d["mechas"]
        informe["vertices"] += d["vertices"]
        informe["triangulos"] += d["triangulos"]
        desde: int = len(m.v) - d["vertices"]
        vs = m.v[desde:]
        if not vs:
            return
        c = informe["cajas"].setdefault(
            familia, {"x": [9.0, -9.0], "y": [9.0, -9.0], "z": [9.0, -9.0],
                      "mechas": 0, "triangulos": 0})
        c["mechas"] += d["mechas"]
        c["triangulos"] += d["triangulos"]
        for eje, val in (("x", 0), ("y", 1), ("z", 2)):
            lo = min(v[val] for v in vs)
            hi = max(v[val] for v in vs)
            c[eje][0] = min(c[eje][0], lo)
            c[eje][1] = max(c[eje][1], hi)

    def simetrico(psi: float) -> float:
        """El angulo al que se leen los indices de las tablas: 0 la frente,
        180 la nuca, y los dos lados dan el mismo numero."""
        grados: float = math.degrees(psi) % 360.0
        return grados if grados <= 180.0 else 360.0 - grados

    def linea(psi: float, margen: float) -> float:
        return _tabla(LINEA_PELO, simetrico(psi)) + margen

    def camino_mecha(psi0: float, z0: float, largo: float, jinete: float,
                     z_min: float, vuelo: tuple = None, holg: float = 0.0,
                     salida: tuple = None, punta: float = 0.0) -> list:
        """El camino de una mechon de la cabeza: sale del craneo, lo RECORRE y
        despues vuela.

        Los cuatro puntos del camino, y los cuatro hacen falta:

        - `c0` la raiz, HUNDIDA en el craneo (`HOLGURA_RAIZ`), para que no se vea
          un tubo que le crece de la cara.
        - `c1` y `c2` son puntos de la SUPERFICIE del elipsoide, al 50% y al 100%
          del tramo que pega. Por eso la mechon apoya en la cabeza en vez de
          flotar a un centímetro. Los dos se separan de la piel un radio y un
          radio y medio, y no mas: separarlos mucho es lo que hacia que la
          primera version disparase las mechonas ocho centimetros hacia un lado
          (el punto intermedio se empujaba con la NORMAL del elipsoide, y en
          la sien la normal es horizontal).
        - `c3` la punta, ya en vuelo libre, en la direccion de `VUELO`.

        `jinete` sube o baja los dos puntos que pegan, y `z_min` es la altura a la
        que no baja la punta, para que ninguna se clave en el cuello.
        """
        q0: float = simetrico(psi0)
        lado: float = 1.0 if math.degrees(psi0) % 360.0 <= 180.0 else -1.0
        # `SALIDA_MECHA`, `VUELO` y `LARGO_MECHA` estan en GRADOS (son tablas de
        # lectura, como `LINEA_PELO`) y el resto del archivo trabaja en
        # radianes. El cambio va aqui y no mas abajo porque es el unico sitio
        # donde las dos unidades se tocan: pasarlo dos veces hacia arriba o
        # hacia abajo es lo que hacia que las mechonas salieran disparadas a 57
        # radianes de la cabeza.
        barrido, z_sal = salida if salida is not None else _tabla3(SALIDA_MECHA, q0)
        z_sal = z_sal if z_sal > 0.0 else z0 + z_sal
        psi_s: float = math.radians(barrido) * lado
        largo: float = largo * largo_pelo
        hug: float = min(HUGO * largo, 0.80 * largo)
        r: float = R_MECHON
        holg: float = r + 0.010
        c0 = _envolvente(craneo, craneo.sobre(psi0, z0, r * HOLGURA_RAIZ), holg)
        p1, _t1 = _caminar(craneo, psi0, z0, psi_s - psi0, z_sal - z0, hug * 0.5)
        p2, _t2 = _caminar(craneo, psi0, z0, psi_s - psi0, z_sal - z0, hug)
        c1 = p1 + craneo.normal(p1) * (r * (0.55 + 0.55 * jinete))
        # `punta` es la separacion extra de la punta, en radios. Es lo que hace
        # que una capa de mechones se vea COMO UNA CAPA y no como una chapa: con
        # la punta pegada al craneo, dieciocho mechonas juntas por la circunferencia
        # se tocan y su union es una superficie lisa, que es el domo que salia.
        # Con la punta a tres radios y medio del craneo, entre una y otra se ve
        # el hueco, y el hueco con sombra es lo que se lee como pelo.
        c2 = p2 + craneo.normal(p2) * (r * (HOLGURA_PUNTA + punta))
        # EL VUELO, que va en el PLANO SAGITAL (ver `VUELO`) pero conserva la x
        # que llevaba la mechon sobre el craneo. Esa x conservada es lo que
        # impide que la curva se dispare hacia un lado: si la punta vuelve a x
        # de la salida, la velocidad lateral se corta de golpe en el punto de
        # despegue y el Catmull-Rom hace alli la cresta, que es como se le
        # abria la cabeza al personaje por los dos lados.
        v = vuelo if vuelo is not None else (0.0,) + _tabla3(VUELO, q0)
        # `v` es (x, y, z). Los dos primeros canales de `VUELO` son sagitales
        # (cero x) porque para la melena abrir la cabeza por los lados es lo
        # peor que se puede hacer; la calota SI lleva x, que es lo que forma la
        # raya (ver `RAYA_G`).
        dir = Vector((v[0], v[1], v[2]))
        dir = dir.normalized() if dir.length > 1e-7 else Vector((0.0, 0.0, -1.0))
        resto: float = max(0.010, largo - hug)
        # Dos tramos, no uno: con uno solo el angulo entre el craneo y el vuelo
        # cae entero sobre `c2` y la curva se dobla ahi. Con dos, uno endereza
        # y el otro vuela, y el cambio de direccion queda repartido.
        ex: float = c2.x - c1.x
        c3 = c2 + Vector((ex / max(0.012, hug), dir.y, dir.z)) * (resto * 0.55)
        c3.x = c2.x + ex / max(0.012, hug) * resto
        c4 = c3 + Vector((ex / max(0.012, hug) * 0.5, dir.y, dir.z)) * (resto * 0.45)
        c4.x = c3.x + ex / max(0.012, hug) * resto * 0.5
        if c4.z < z_min:
            # La punta se ha metido en el cuello: se sube a la altura minima sin
            # cambiar de direccion, que es lo que haria un pelo que topa con el
            # hombro. Un pelo que topa con el hombro no se shorten, se dobla.
            c4.z = z_min
        return [_envolvente(craneo, q, holg) for q in (c0, c1, c2, c3, c4)]

    # ------------------------------------------------------- 0) EL SCALP
    # Primero, porque va debajo de todo lo demas y si se hiciera despues la
    # capa taparia los mechones. Son 5 filas por 28 columnas: 234 triangulos
    # para todo el craneo, que es el 2% del presupuesto y compra la diferencia
    # entre "pelo" y "erizo sobre un huevo de metal".
    suma(_scalp(m, craneo, pesos, vt, 6, 34), "scalp")

    # -------------------------------------------------------- 1) LA LINEA
    # La fila que define la silueta, y la que mas se ve de perfil. Cada mechon
    # nace 6 mm por encima de la linea (para que la raiz quede enterrada en el
    # scalp y no se vea el borde de la capa) y su largo sale de `LARGO_MECHA`.
    # Treinta en toda la vuelta es una cada doce grados, que es lo justo para
    # que la silueta este cortada de arriba abajo sin llegar a ser un peine.
    for k in range(N_LINEA):
        psi: float = math.tau * (k + 0.5) / N_LINEA - math.pi
        largo: float = _tabla(LARGO_MECHA, simetrico(psi)) * rng.uniform(0.88, 1.12)
        camino = camino_mecha(psi, linea(psi, 0.006), largo,
                              rng.uniform(-0.20, 0.50), 1.6)
        suma(_mecha(m, camino, R_MECHON * rng.uniform(0.86, 1.16), pesos,
                    U_PELO[0] + (U_PELO[1] - U_PELO[0]) * (k / N_LINEA),
                    0.05, vt, TAPER), "linea")

    # -------------------------------------------------------- 2) LA CALOTA
    # Las que van tumbadas hacia atras y son la masa de la que el flequillo es
    # el borde. Se siembran en tres filas sobre la corona, con el angulo de oro
    # para el reparto (una fila regular de 18 se lee como un peine; una fila
    # corrida por el angulo de oro no se lee como nada). Y cada una es un
    # GRUESO, porque aqui lo que se busca es cobertura, no separacion: el
    # reparto justo es el que hace que se vea el scalp entre ellas.
    for k in range(N_CALOTA):
        fila_i: int = k // 18
        psi: float = math.tau * ((k * 0.6180339887498949) % 1.0) - math.pi
        t: float = (0.34 + 0.32 * fila_i) ** 0.9
        zl: float = linea(psi, 0.010)
        z: float = zl + (CIMA_PELO - zl - 0.004) * t
        largo: float = (0.072 + 0.030 * rng.random())
        # La fila de arriba se SEPARA de la coronilla y la de abajo se pega. Sin
        # esto las tres filas hacen la misma capa y de tres cuartos la coronilla
        # se ve como un domo liso: el pelo esta pero pegado, y lo que el ojo
        # necesita es la SOMBRA que el pelo proyecta sobre el pelo.
        alto: float = 1.0 if fila_i == 2 else 0.0
        # LA RAYA, y es el dato que mas cambia la calota. Si las cincuenta y
        # cuatro van exactamente para atras, de frente la coronilla se ve como
        # un DOMO LISO con pelos pegados, que es un casquete; si a cada una se
        # le da su bocado lateral, se forma la raya por la que el pelo se peina,
        # y la raya es lo que el ojo lee como pelo de verdad. La mitad de las
        # mechonas cae a un lado de la raya y la otra mitad al otro, y las dos
        # mitades arrancan de la MISMA linea, que es donde se ve el scalp.
        lado_r: float = 1.0 if (k % 2 == 0) else -1.0
        # Cuanto mas cerca de la raya, MAS lateral se hace el bocado: en la
        # raya misma el pelo se levanta y no se va a ningun lado, que es lo que
        # pasa de verdad en la raya.
        # Y la raya NO es la misma en las tres filas. Con la misma raya en las
        # tres, la fila de arriba barre por encima de las de abajo y la coronilla
        # se ve como un domo liso con UNA franja de pelo cruzandolo; con tres
        # rayas en tres sitios, la coronilla tiene tres capas que se cruzan y el
        # ojo la lee como pelo de verdad. Es el mismo truco que las rayas de un
        # rapado a machine, y funciona por lo mismo.
        raya_f: float = RAYA_G * lado_r + (fila_i - 1) * 13.0
        bocado: float = 0.52 * (1.0 - _suave(min(
            1.0, abs(math.degrees(psi) - raya_f) / 84.0)))
        camino = camino_mecha(psi, z, largo * (0.78 if alto > 0.5 else 1.0),
                              0.85 * alto + rng.uniform(0.0, 0.40),
                              Z_MIN_CALOTA,
                              vuelo=(-lado_r * bocado,
                                     VUELO_CALOTA[1] * (0.55 if alto > 0.5 else 1.0),
                                     VUELO_CALOTA[2] * (0.55 if alto > 0.5 else 1.0)
                                     + 0.12 * bocado),
                              punta=1.6 * alto)
        suma(_mecha(m, camino, R_CALOTA * rng.uniform(0.82, 1.18), pesos,
                    U_PELO[0] + (U_PELO[1] - U_PELO[0]) * rng.random(),
                    0.05, vt, TAPER), "calota")

    # ------------------------------------------------------------- 3) LA CIMA
    # Las unicas que rompen el huevo por arriba, y son pocas a proposito: siete
    # mechones cortas que se levantan de la calota. Con veinte el personaje
    # parece que tiene un gorro de papier, que es justo lo que el encargo
    # prohibe. Cada una sale casi vertical y se tumba hacia atras, o sea que la
    # silueta del craneo se ve por el contorno.
    for k in range(N_CIMA):
        psi: float = math.tau * k / N_CIMA + 0.22
        raiz = craneo.sobre(psi, CIMA_PELO - 0.004, R_MECHON * 0.7)
        n = craneo.normal(raiz)
        largo: float = (0.016 + 0.009 * rng.random()) * largo_pelo
        # El cuelgue esta en la punta, no en la raiz: una mechon que se levanta
        # y se vuelve a acostar es un copete, y siete copetes juntos son un
        # gorro. Esta se levanta y SE QUEDA, y por eso rompe la linea.
        # Rumbo a atras desde el primer tramo. Una mechona de la cima que sale
        # vertical es un pincho, y cinco pinchos en fila son un gorro de papier;
        # la que sale ya tumbada a atras es pelo, y rompe la linea lo mismo.
        camino = _curva(raiz, [(n * 0.72 + Vector((0.0, 0.55, -0.10))).normalized(),
                               (n * 0.55 + Vector((0.0, 0.72, -0.22))).normalized(),
                               (n * 0.42 + Vector((0.0, 0.80, -0.32))).normalized()],
                        paso=largo / 3.0)
        suma(_mecha(m, camino, R_MECHON * rng.uniform(0.72, 1.00), pesos,
                    U_PELO[0] + 0.05 * k, 0.04, vt, TAPER), "cima")

    # ------------------------------------------------------- 4) EL FLEQUILLO
    # Trece mechones en una fila recta por delante de la linea, que CUELGAN
    # sobre la frente. Es la familia que mas cambia la lectura de frente: con
    # ella la frente tiene pelo encima y el personaje se ve de frente; sin ella
    # la linea de pelo es un corte limpio y el pelo se lee como un casquete
    # encajado. Y es la que tapa la franja de metal de la mascara, que es el
    # motivo por el que existe.
    for k in range(N_FLEQUILLO):
        u1: float = (k + 0.5) / N_FLEQUILLO
        psi: float = math.radians(-52.0 + 104.0 * u1)
        # La raiz sube un poco hacia las sienes: el flequillo de verdad tiene el
        # centro mas bajo que los costados, y es lo que evita que se lea como
        # una visera.
        z: float = _tabla(LINEA_PELO, simetrico(psi)) + 0.004 + 0.014 * (u1 - 0.5) ** 2
        largo: float = (0.030 + 0.016 * rng.random()) * largo_pelo
        camino = camino_mecha(psi, z, largo, rng.uniform(-0.10, 0.30),
                              Z_MIN_FLEQUILLO, vuelo=VUELO_FLEQUILLO,
                              salida=SALIDA_FLEQUILLO)
        suma(_mecha(m, camino, R_MECHON * rng.uniform(0.90, 1.20), pesos,
                    U_PELO[0] + (U_PELO[1] - U_PELO[0]) * u1,
                    0.05, vt, TAPER), "flequillo")

    # --------------------------------------------------------- 5) LAS PATILLAS
    # Delante de la oreja, bajando. Sin patilla el pelo de los lados se corta
    # en linea recta y el personaje se ve rapado por detras de la oreja, que es
    # justo donde el ojo busca "casco" y encuentra una linea. Estas NO siguen la
    # tabla de salida sino que bajan por la sien, que es lo unico que las hace
    # patilla y no pelo.
    for lado in (1.0, -1.0):
        for k in range(N_PATILLA):
            psi: float = lado * math.radians(64.0 + 7.0 * k)
            z: float = 1.7880 - 0.014 * k
            largo: float = (0.042 + 0.014 * rng.random()) * largo_pelo
            # Camino PROPIO y no el de `camino_mecha`, porque la patilla no barre:
            # baja recta por la sien. Si se le pasara por la tabla de salida,
            # la primera version hacia lo que hacia la cabeza entera, que es
            # abrirse ocho centimetros hacia un lado.
            c0 = craneo.sobre(psi, z, R_MECHON * HOLGURA_RAIZ)
            c1 = craneo.sobre(psi, z - largo * 0.34, R_MECHON * 0.7)
            c2 = craneo.sobre(psi, z - largo * 0.66, R_MECHON * 1.5)
            c3 = c2 + Vector((0.0, 0.004, -largo * 0.34))
            c3.z = max(c3.z, Z_MIN_PATILLA)
            camino = [_envolvente(craneo, q, R_MECHON + 0.006)
                      for q in (c0, c1, c2, c3)]
            suma(_mecha(m, camino,
                        R_MECHON * rng.uniform(0.62, 0.82), pesos,
                        U_PELO[0] + 0.03 * k, 0.04, vt, TAPER), "patilla")

    # ============================================================== LA BARBA
    # Y aqui esta la mitad del trabajo visual del archivo. La barba NO es un
    # anillo de dientes clavados en la mandibula, que es como se ve una barba
    # procedural: es un BLOQUE. Por eso va por GRUPOS de tres mechones con la
    # raiz junta y la punta separada, y los grupos se reparten a lo largo de la
    # mandibula con la punta siempre al mismo lado, de modo que la masa se lea
    # como una masa. Si los tres bloques tuvieran la misma curva se veria un
    # cascaron, que es el otro fallo tipico: la mandibula cae hacia atras y
    # arriba, el menton cae hacia adelante y abajo, y el bigote sale horizontal.
    if con_barba:
        abajo = Vector((0.0, 0.0, -1.0))

        def camino_barba(psi: float, largo: float, adelante: float,
                         abajo_peso: float, converge: float = 0.0) -> list:
            """El camino de una mechon de barba: nace en la mandibula, sale hacia
            AFUERA de la cara y despues cae.

            Tres tramos a paso constante (`_curva`), y las direcciones giran de
            "salgo de la cara" a "caigo recto": asi crece la barba de verdad, de
            dentro hacia fuera y despues hacia abajo. `adelante` es lo que
            separa la mandibula del menton, y `abajo_peso` cuanto cae.

            `_curva` y no cuatro puntos a distancia fija del primero porque con
            cuatro puntos a distancia fija la punta salia veinte centimetros
            mas abajo de la que decia `LARGO_BARBA`, y se metia en el pecho:
            el Catmull-Rom hace la cresta donde cambia la direccion, y ahi el
            primer tramo es el mas corto.
            """
            raiz = craneo.punto(psi, _tabla(LINEA_BARBA, simetrico(psi)))
            n = craneo.normal(raiz)
            hacia = (abajo * abajo_peso
                     + Vector((0.0, -adelante, 0.0))).normalized()
            n = n.normalized() if n.length > 1e-7 else hacia
            # LA CONVERGENCIA, y es lo que hace que esto sea una barba y no un
            # peine. Cada mechona cae recta hacia abajo desde su sitio, y con
            # veinte mechonas rectas la barba es una fila de dientes con la
            # piel entre ellos. La barba de verdad se cierra: las de la sien
            # van hacia la barbilla y las de la barbilla casi no van a ningun
            # lado, asi que abajo hay masa y arriba hay mechonas sueltas. El
            # `x` crece de tramo en tramo, que es como se cierra de verdad.
            sg: float = 1.0 if psi > 0.0 else -1.0
            base = [(n * 0.58 + hacia * 0.42).normalized(),
                    (n * 0.24 + hacia * 0.80).normalized(),
                    (n * 0.08 + hacia * 1.00).normalized(),
                    hacia]
            camino = _curva(raiz + n * (R_BARBA * 0.55),
                            [Vector((d.x - sg * converge * ((i + 1) / 4.0), d.y, d.z))
                             .normalized() for i, d in enumerate(base)])
            # El largo manda sobre el paso: si la barba es corta, el ultimo
            # tramo se acorta, y si es larga el camino crece por el final. Un
            # pelo que se dobla al final en vez de crecer es un pelo corto.
            while len(camino) - 1 < max(2, int(round(largo / PASO))):
                camino.append(camino[-1] + hacia * PASO)
            camino = camino[:max(3, int(round(largo / PASO)) + 1)]
            # La red del cuello y del pecho. Es la que garantiza que la barba no
            # se meta en el peto, y va AL FINAL, sobre el camino ya construido,
            # porque si se comprobara antes el corte se deshace: los puntos que
            # se Push hacia delante son justo los de la punta.
            return [_fuera_del_peto(q, craneo.girth) for q in camino]

        # El arco de la mandibula, en GRUPOS. El reparto va de la barbilla hacia
        # atras por los dos lados, y la punta se cierra un poco hacia el centro
        # (`adelante` positivo) para que el bloque tenga forma de barba y no de
        # faldon.
        # La mandibula, en grupos, y con el largo APAGANDOSE hacia atras. El
        # reparto anterior la mandia en un arco casi entero con el largo
        # parejo, y eso es lo que hacia que se viera una fila de dientes: una
        # barba es una CUÑA, larga en la barbilla y corta en la sien, y la
        # silueta de la cuña es lo que la lee como barba.
        for k in range(BARBA):
            u1: float = (k + 0.5) / BARBA
            q: float = 42.0 + 116.0 * u1
            lado: float = 1.0 if k % 2 == 0 else -1.0
            psi: float = lado * math.radians(q)
            largo_g: float = LARGO_BARBA * (0.82 - 0.56 * u1)
            for j in range(POR_GRUPO):
                # Las del grupo: la raiz en un disco pequeno y la punta abierta
                # en abanico, que es la lectura de "mechon" y no la de "clavo".
                off: float = (j - (POR_GRUPO - 1) * 0.5) * rng.uniform(0.8, 1.2)
                psi_j = psi + math.radians(4.6) * off
                largo = largo_g * rng.uniform(0.84, 1.14)
                # En la mandibula la barba va ATRAS (la patilla se une a la
                # nuca) y no adelante: adelante es solo de la barbilla.
                camino = camino_barba(psi_j, largo, -0.10 - 0.14 * u1,
                                      0.80 + 0.16 * rng.random(),
                                      converge=0.34 + 0.20 * u1)
                suma(_mecha(m, camino, R_BARBA * rng.uniform(0.80, 1.10), pesos,
                            U_PELO[0] + (U_PELO[1] - U_PELO[0]) * rng.random(),
                            0.05, vt, TAPER_BARBA), "mandibula")

        # El menton: el bloque gordo de la punta de la barba, y el que mas pesa
        # en la lectura del personaje. Son cuatro mechones MUY anchas y las mas
        # largas de todas, y van hacia DELANTE, que es lo que distingue una
        # barba de una coleta.
        for k in range(MENTON):
            psi: float = math.radians(-30.0 + 12.0 * k)
            largo: float = LARGO_BARBA * rng.uniform(0.90, 1.12)
            camino = camino_barba(psi, largo, 0.17, 0.82, converge=0.12)
            suma(_mecha(m, camino, R_BARBA * rng.uniform(1.05, 1.30), pesos,
                        U_PELO[0] + 0.05 * k, 0.05, vt, TAPER_BARBA), "menton")

        # LA BARBA MAXILAR, que no cuelga: PEGA. Cuatro mechonas gruesas por
        # lado tumbadas sobre la mandibula, de la barbilla hacia la oreja. Es la
        # pieza que hace que la barba se lea como una masa y no como una fila
        # de raices: sin ella, las veintiocho mechonas de la mandibula y del
        # menton se ven de frente por SUS EXTREMOS DE ARRIBA, que es un
        #BOTON de trece botones en fila justo encima de la boca.
        for lado in (1.0, -1.0):
            for k in range(4):
                psi: float = lado * math.radians(10.0 + 26.0 * k)
                raiz = craneo.punto(psi, _tabla(LINEA_BARBA, simetrico(psi)))
                n = craneo.normal(raiz)
                # La direccion es la TANGENTE a la mandibula (la del elipsoide
                # en el sentido de alejarse de la barbilla) y no "abajo": una
                # mechona tumbada es la que tapa las raices, y si cuelga las
                # tapa todavia menos.
                lg = craneo.punto(psi + lado * math.radians(26.0),
                                  _tabla(LINEA_BARBA, simetrico(psi) + 26.0))
                largo_j: float = min(0.042, (lg - raiz).length + 0.012)
                camino = _curva(raiz + n * (R_BARBA * 0.55),
                                [(n * 0.30 + (lg - raiz).normalized() * 0.80).normalized(),
                                 ((lg - raiz).normalized() * 0.85
                                  + Vector((0.0, 0.0, -0.35))).normalized(),
                                 ((lg - raiz).normalized() * 0.80
                                  + Vector((0.0, 0.0, -0.60))).normalized()],
                                paso=largo_j / 3.0)
                suma(_mecha(m, camino, R_BARBA * rng.uniform(1.05, 1.35), pesos,
                            U_PELO[0] + 0.05 * (k + (0 if lado > 0 else 4)),
                            0.05, vt, TAPER_BARBA), "maxilar")

    if con_bigote:
        # Corto y pegado al labio, en dos grupos. Si `parte_cara` sobresale mas
        # que este elipsoide, el bigote se queda dentro de la cara y no se ve:
        # por eso nace bajo la linea de la nariz y crece casi vertical.
        for gr in range(BIGOTE_GRUPOS):
            centro_g: float = (-BIGOTE_G[0] if gr == 0 else BIGOTE_G[0]) * 0.45
            for j in range(3):
                psi: float = math.radians(centro_g + (j - 1) * 11.0)
                raiz = craneo.punto(psi, Z_BIGOTE)
                n = craneo.normal(raiz)
                largo: float = 0.022 + 0.010 * rng.random()
                hacia = Vector((0.0, -0.46, -0.89)).normalized()
                camino = [_fuera_del_peto(q, craneo.girth) for q in
                          _curva(raiz + n * (R_BARBA * 0.45),
                                 [(n * 0.70 + hacia * 0.30).normalized(),
                                  (n * 0.22 + hacia * 0.86).normalized(),
                                  hacia], paso=largo / 3.0)]
                suma(_mecha(m, camino, R_BARBA * rng.uniform(0.52, 0.72), pesos,
                            U_PELO[0] + 0.05 * (gr * 3 + j), 0.04, vt,
                            TAPER_BARBA), "bigote")

    # ------------------------------------------------------------ EL INFORME
    # La caja del pelo, que es lo que hay que COMPARAR con la caja de la
    # armadura para que nadie meta una placa que se coma las mechones. Y el
    # alto sobre la cima, que es el numero que el encargo pone como limite.
    propios = m.v[v_pelo:]
    if propios:
        xs = [v.x for v in propios]
        ys = [v.y for v in propios]
        zs = [v.z for v in propios]
        informe["caja"] = {"x": [min(xs), max(xs)], "y": [min(ys), max(ys)],
                           "z": [min(zs), max(zs)]}
        informe["alto_sobre_cima"] = max(zs) - CIMA_Z
        informe["y_min"] = min(ys)
        informe["z_min"] = min(zs)
    # Los huesos del pelo SOLO, y no los de la malla entera: si se lista la
    # malla entera salen los cuarenta y cinco y no se ve ni un pelo de que el
    # pelo pesa lo que tiene que pesar.
    informe["huesos"] = sorted({k for w in m.w[v_pelo:] for k in w})
    print("[PELO] %d mechas | %d vertices, %d triangulos | banda %s | alto sobre "
          "la cima %.3f (tope %.3f) | barba %s | y min %.3f, z min %.3f | "
          "pesa %s"
          % (informe["mechas"], informe["vertices"], informe["triangulos"],
             informe["banda"], informe.get("alto_sobre_cima", 0.0), Z_TOPE,
             "si" if con_barba else "no", informe.get("y_min", 0.0),
             informe.get("z_min", 0.0), informe["huesos"]))
    return informe
