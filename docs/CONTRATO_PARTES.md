CONTRATO DE LAS PARTES DEL PERSONAJE

Este archivo NO es codigo: es el acuerdo entre `modelo_humano.py` y los modulos
de las partes. Esta escrito antes de que exista nadie, y por eso esta aca.

POR QUE EXISTE. El modelo procedural se armaba entero dentro de una funcion de
2.000 lineas, y el unico jeito de paralelizar el trabajo era partirse ese
archivo: si dos personas tocan el mismo archivo, una pisa a la otra y se pierde
el trabajo de las dos. Con este contrato cada parte es un archivo propio, con su
dueño, y ninguno toca el archivo de otro.

LAS REGLAS, en una linea cada una:

1. Cada parte es un modulo con UNA funcion que se llama `aplicar`. Ni mas, ni
   menos. Quien lo lea tiene que poder entender la parte sin leer el resto.

2. Cada parte CREA SU PROPIA GEOMETRIA con `m.vert`, `m.anillo`, `m.perfil`,
   `m.loftear` y `m.tapar`. No desplaza geometria que creo otra parte: si tenes
   que mover algo que no es tuyo, es que tu parte deberia ser la que lo crea.
   La excepcion son las piezas de armadura, que se apoyan sobre el cuerpo, y que
   por eso pesan 50/50 con el hueso de debajo en el borde de contacto.

3. El peso de cada vertice va al hueso que lo mueve. Una pieza de pelo pesa
   `{"Head": 1.0}`. Una hombrera pesa `{"UpperArm.L": 0.5, "Chest": 0.5}` en el
   borde que toca el brazo y `{"Chest": 1.0}` en el resto. Un peso equivocado se
   ve como una pieza que se raspa o que se atraviesa al moverse, y no se
   arregla con mas prueba.

4. La V de la textura se pide con `_v_tex(nombre, t)`, nunca escribiendo el
   numero a mano. La mascara de materiales esta partida en franjas de V por
   nombre de parte, y si una parte escribe su V fuera de su franja se pinta con
   el material de otra. Ese fue el bug de los indices corridos una posicion.

5. Nada de aleatorio sin semilla. `modelo_humano.py` es determinista: dos
   builds con la misma semilla dan el mismo modelo, byte a byte.

6. Lo que no se toca: `scripts/`, `data/`, `project.godot`. El juego tiene que
   seguir cargando el modelo sin tocar una linea de codigo.

LA FIRMA, y es la misma para las cuatro:

    aplicar(m: Malla, p: dict, g: float, _v_tex: callable) -> dict

    m       la malla que se esta construyendo. Se le AGREGA geometria.
    p       proporciones en metros (el `PROP` del script principal). Todas las
            medidas en metros, con el origen en el centro de los pies.
    g       `girth`, el multiplicador de corpulencia. 1.0 es el canonico.
    _v_tex  `lambda nombre, t: float`, el valor de V para la textura.
    devuelve un dict con las medidas de la parte, para el informe.

DONDE SE LLAMA. En `construir_malla()`, DESPUES del torso y antes de las
extremidades, en este orden:

    torso
    piernas
    DE aqui en mas, las partes: cara, armadura, pelo
    brazos
    manos

Y el orden importa: las partes van antes de los brazos porque una hombrera se
apoya en el hombro, y el hombro lo crea el brazo. Si se pone al reves, la
hombrera queda flotando al aire.

DONDE VAN LOS HUESOS. Los huesos los crea `modelo_humano.py` y no se tocan.
Una parte no anade huesos nuevos: los que existen son 49 y el juego los espera
por nombre. Si tu parte necesita mover algo, lo mueve con el hueso que ya esta.
