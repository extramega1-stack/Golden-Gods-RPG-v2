# Informe de animación — res://models/clase_guerrero.glb

Instrumento de la fase de medición. Los números de arriba son los que
se discuten; el detalle está abajo y la fecha, más abajo todavía.

## Números

número                                      valor  veredicto  
───────────────────────────────────────────────────────────────────
modelo                             res://models/clase_guerrero.glb             
clip walk (s)                               1.042             
clips del juego que faltan                      0             
speed_scale en juego                        1.000             
clip sonando                                 idle             
ciclo (grados acumulados)                   646.4  CICLO      
ciclo (grados/frame a 60 fps)                4.61             
patinaje por ciclo (cm)                    119.49  HORRIBLE   
patinaje sobre el avance (%)                132.2             
zancada del pie por ciclo (u)               0.742             
velocidad natural del clip (u/s)            0.713             
velocidad del juego (u/s)                   6.000             
speed_scale que cancela el patinaje           8.42             
eje de avance del pie (crudo)                  -Z             
eje de avance del pie (con giro PI)             +Z             
pie en vuelo, hacia adelante (u)           -0.522             
pie en contacto, hacia adelante (u)          0.327  AL_REVES   
blend_position caminando lento              1.000             
blend_position trotando                     1.000  MEZCLA_SATURADA
blend_position corriendo                    1.000             
blend se satura desde (u/s)                  1.20             
tira de PNGs                            12 frames             

## No se pudo medir

- nada: se midió todo lo pedido

## Clips del AnimationPlayer

- nombres: attack, die, idle, walk
- faltan de los cuatro del juego: ninguno
- clip sonando: `idle` en t=0.000 s, speed_scale=1.000, sonando=true
- hay AnimationTree activo: false

| clip | duración (s) | cicla | keys en piernas | pistas en piernas |
|---|---|---|---|---|
| `attack` | 0.833 | true | 6 | 6 |
| `die` | 1.208 | false | 192 | 6 |
| `idle` | 2.042 | true | 6 | 6 |
| `walk` | 1.042 | true | 171 | 6 |

## Ciclo: grados por frame

- veredicto: **CICLO**
- grados acumulados en un ciclo (las dos piernas): 646.4
- pico de giro: 4.61 grados/frame a 60 fps
- excursion vertical de cada hueso (u):
    izq.muslo      0.0276
    izq.espinilla  0.0889
    izq.pie        0.1502
    der.muslo      0.0276
    der.espinilla  0.0889
    der.pie        0.1516

## Patinaje (foot sliding)

- velocidad natural del clip (zancada/ciclo): **0.713 u/s**
- la misma, medida solo en la pisada: 2.148 u/s
- velocidad del juego: 6.000 u/s
- patinaje por ciclo: **119.49 cm** (132.2 % del avance del personaje)
- `speed_scale` que cancela el patinaje: **8.42**
- veredicto: **HORRIBLE**

| pie | zancada (u) | pisada (% ciclo) | fiable | avance del personaje (cm) | pie en el mundo (cm) | deslizamiento (cm) | % | vel. natural ciclo | vel. natural pisada |
|---|---|---|---|---|---|---|---|---|---|
| `izq.pie` | 0.738 | 15% | NO | 95.34 | 133.94 | 133.94 | 140.5 | 0.708 | 2.700 |
| `der.pie` | 0.747 | 22% | NO | 84.75 | 105.03 | 105.03 | 123.9 | 0.717 | 1.596 |

## Dirección

- eje de avance del personaje: `-Z`
- vuelta aplicada al modelo: 3.1416 rad (PI = el modelo mira al revés del eje del juego)
- veredicto: **AL_REVES**

Los dos números de cada pie van proyectados sobre el eje de avance del
juego (con la vuelta del modelo deshecha), así que el SIGNO lo es todo:
positivo es "hacia donde va el personaje", negativo es "al revés".

| pie | eje del barrido (crudo) | amplitud X / Z (u) | en vuelo (u) | en contacto (u) | pisada (% del ciclo) | veredicto |
|---|---|---|---|---|---|---|
| `izq.pie` | **Z** | 0.018 / 0.738 | -0.508 | +0.429 | 15% | **AL_REVES** |
| `der.pie` | **Z** | 0.019 / 0.747 | -0.535 | +0.225 | 22% | **AL_REVES** |

Eje del barrido del hueso del pie a lo largo del ciclo: en crudo va hacia `-Z`, y con la vuelta de `Cuerpo.GIRO_MODELO` ya aplicada va hacia `+Z`, mientras el personaje avanza hacia `-Z`.

## Mezcla (blend_position)

- veredicto: **MEZCLA_SATURADA** — la mezcla se mueve de verdad en el 12 % del barrido
- llega a 1.0 (tope, se acabó el cross-fade) desde: 1.20 u/s
- barrido completo, 0 a 9.60 u/s:

    v= 0.00 u/s  blend=0.000  idle   1.0x
    v= 0.60 u/s  blend=0.333  idle   1.0x
    v= 1.20 u/s  blend=1.000  idle   1.0x
    v= 1.80 u/s  blend=1.000  idle   1.0x
    v= 2.40 u/s  blend=1.000  idle   1.0x
    v= 3.00 u/s  blend=1.000  idle   1.0x
    v= 3.60 u/s  blend=1.000  idle   1.0x
    v= 4.20 u/s  blend=1.000  idle   1.0x
    v= 4.80 u/s  blend=1.000  idle   1.0x
    v= 5.40 u/s  blend=1.000  idle   1.0x
    v= 6.00 u/s  blend=1.000  idle   1.0x
    v= 6.60 u/s  blend=1.000  idle   1.0x
    v= 7.20 u/s  blend=1.000  idle   1.0x
    v= 7.80 u/s  blend=1.000  idle   1.0x
    v= 8.40 u/s  blend=1.000  idle   1.0x
    v= 9.00 u/s  blend=1.000  idle   1.0x
    v= 9.60 u/s  blend=1.000  idle   1.0x

## Tira de PNGs (playtest visual)

- ciclo renderizado en 12 frames a 200x300 px, fondo uniforme `#525c6b`
- velocidad a la que se renderiza la tira `mundo`: 6.000 u/s
- `mundo` (el cuerpo avanza a la velocidad del juego, con el
  suelo rayado: si el pie patina, la bola se va de la marca): `res://build/tira_animacion/tira_mundo.png`
- `lugar` (el ciclo en el sitio, para ver la máquina del clip): `res://build/tira_animacion/tira_lugar.png`
- frames sueltos: `res://build/tira_animacion`

## Metadata (cambia entre corridas, no forma parte del diff)

- clase: guerrero
- clip_medido: walk
- escala: 0.9
- fecha: 2026-09-29 17:20:00
- giro_modelo_rad: 3.14159265358979
- godot: 4.7.2
- herramienta: tools/anim_medida/bancada_animacion.gd
- modelo: res://models/clase_guerrero.glb
- muestras_por_ciclo: 60
- umbral_caminar_en_juego: 0.45
- velocidad_juego_u_s: 6.0
