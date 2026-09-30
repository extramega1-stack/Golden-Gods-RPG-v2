# Fase 69.1 — El juego a 60 fps en una GTX 1660, medido

Fecha: 2026-09-29. Hardware de medición: **la GTX 1660 del usuario, no una
máquina de desarrollo**. Por eso este documento existe: la pregunta era si el
juego entra en 60 fps en esa placa, y hasta ahora nadie lo había corrido.

## Veredicto en una línea

**Sí: p95 = 16,67 ms, y 7 961 de 7 961 frames de juego dentro de presupuesto.**
El presupuesto de 60 fps son 16,7 ms y el p95 medido es 16,67 ms, que es el
tope de 60 fps clavado: no hay ni un frame perdido. Lo único caro de la
partida son 40–46 ms al entrar a la ciudad, una vez.

## La máquina

| | |
|---|---|
| GPU | NVIDIA GeForce GTX 1660 (TU116), 6 GB, driver 610.57.04 |
| API | Vulkan 1.4.341 — Forward+ |
| Monitor | Samsung Odyssey G40B, 1920×1080 a **239,76 Hz** |
| Compositor | Hyprland / Wayland, `directScanoutTo: 0` |
| Godot | 4.7.2.stable |
| Escena | `res://scenes/demo/fase14_demo.tscn` (la partida real) |
| Ventana | 941×508 px, viewport 1333×720, `scaling_3d_scale` 1.0 |
| VRAM | 373 MB de 1 GB de presupuesto |

## La partida completa (carga + 133 s de juego)

```sh
godot --display-driver wayland --path . --script res://tools/bench_gpu.gd -- \
  --cargar --frames=8000 --warmup=0 --vsync=0 --tope=60 \
  --out=build/bench/bench_partida_60fps.json \
  --dump=build/bench/bench_partida_60fps_dump.json
```

8 000 frames medidos desde el frame 0 (o sea, **incluida la construcción de
las 9 ciudades**), con el tope de 60 fps del propio motor y el vsync apagado:

| | p50 | p95 | p99 | p99.9 | media | max |
|---|---|---|---|---|---|---|
| toda la corrida | 16,67 | **16,67** | 16,67 | 16,67 | 16,67 | 40,00 |
| solo juego (tras la carga) | 16,67 | **16,67** | 16,67 | — | 16,67 | **16,67** |

- **0 frames de más de 16,7 ms en los 7 961 frames de juego.**
- 3 frames de más de 20 ms en total, los tres durante la construcción del
  mundo (22,0 / 32,1 / 40,0 ms). En la corrida anterior a este arreglo el
  mismo tramo daba 8 spikes con un pico de 71 ms; con el escalonado de la
  cola de obra quedó en 3 spikes con pico de 40 ms (46,5 ms en otra corrida:
  la cola de carga es lo que más varía entre corridas).
- 1 022 draw calls, 935 138 primitivas, 5,4 ms de CPU por frame (4,7 de
  proceso + 0,7 de física) sobre los 16,67 disponibles. O sea: **el juego usa
  un tercio del frame de CPU y el resto lo espera el vsync.**

## Los cuatro niveles de calidad (estado estacionario, 2 500 frames cada uno)

```sh
for q in 0 1 2 3; do
  godot --display-driver wayland --path . --script res://tools/bench_gpu.gd -- \
    --frames=2500 --warmup=240 --vsync=0 --tope=60 --calidad=$q \
    --out=build/bench/bench_calidad_$q.json
done
```

| calidad | p50 | p95 | max | draw | primitivas | veredicto |
|---|---|---|---|---|---|---|
| Baja | 16,67 | 16,67 | 16,67 | 1 017 | 834 002 | entra |
| Media | 16,67 | 16,67 | 16,67 | 1 017 | 834 002 | entra |
| Alta | 16,67 | 16,67 | 16,67 | 1 020 | 834 952 | entra |
| Ultra | 16,67 | 16,67 | 16,67 | 1 071 | 958 414 | entra |

Los cuatro entran con el frame más caro clavado en 16,67 ms: a 720p esta
placa no nota la diferencia. Para ver si el ajuste hace algo hay que poner a
la GPU en el cuello de botella, y para eso el bench tiene `--escala`:

```sh
godot --display-driver wayland --path . --script res://tools/bench_gpu.gd -- \
  --frames=1500 --warmup=180 --vsync=0 --tope=0 --escala=2.0 --calidad=0 \
  --out=build/bench/bench_ssaa2_calidad_0.json
```

| calidad | p50 | p95 | max | draw | VRAM |
|---|---|---|---|---|---|
| Baja | 3,27 | 3,70 | 4,48 | 1 022 | 401 MB |
| Ultra | **5,42** | 5,56 | 6,91 | 1 076 | 442 MB |

**Ultra cuesta +2,15 ms por frame (+66 %), +54 draw calls y +41 MB de VRAM
que Baja.** El ajuste mueve la aguja de verdad: son la SSAO con el doble de
muestras, el glow, la cuarta división del atlas de sombras y el desenfoque de
la sombra. Los dos caben en 16,7 ms; la diferencia se nota cuando la
resolución sube, y por eso hay una escala para bajar.

## Lo que se arregló para poder medir esto (y dos bugs de verdad)

1. **El bench no apagaba el vsync.** Ponía `Opciones.poner("vsync", false)` en
   `_initialize`, pero la demo hace `Opciones.cargar()` cuando el mundo queda
   listo (`fase12_demo._process` → `_al_mundo_listo` →
   `_instalar_fase63_64_ui`), y `cargar()` vacía el diccionario: el bench
   midiendo con el vsync del usuario. Con vsync puesto, `delta` es el del
   monitor SIEMPRE que se llegue o no — el p95 medía la frecuencia de la
   pantalla, no el juego. Ahora los overrides se aplican **después** de esa
   puerta, y el bench imprime lo que puso.

2. **La puerta de "mundo listo" no esperaba nada.** Era
   `has_method("_al_mundo_listo") or get_child_count() > 20`, que da `true` en
   el primer frame (la demo tiene 29 hijos nada más instanciarse). El warmup
   corría mientras la ciudad se seguía levantando. Ahora usa
   `_mundo_pendiente`, que es la señal buena.

3. **`root.request_focus()` no existe en Godot 4.7** (es `grab_focus()`).
   Saltaba un error de script en cada corrida: la ventana nunca pedía el foco.

4. **La calidad no se aplicaba al mundo vivo.** `PostProceso.aplicar()` lo
   llamaba solo `ciclo_dia`, al construir el mundo. Mover "Calidad gráfica" en
   el panel guardaba el número y no tocaba ni el glow ni la SSAO hasta salir y
   volver a entrar. Ahora `Opciones.aplicar_video()` reencarma el
   `WorldEnvironment` y el sol del árbol (`PostProceso.aplicar_al_mundo()`), y
   la sombra y el número de muestras de SSAO también siguen a la calidad.

5. **El tirón de la entrada a la ciudad: 71 ms → 40 ms.** Con 9 ciudades
   construyéndose a la vez, `PASOS_POR_FRAME` es por CIUDAD: eran 27 pasos de
   obra por frame. A 1 paso el mismo tramo baja de 8 spikes a 3, y el pico de
   71 ms a 40 ms. La pantalla de carga dura 27 frames en vez de 11 (0,45 s a
   60 fps), que es infinitamente más barato que el tirón.

## La trampa de AGENTS.md, medida

Bajo Wayland la corrida por XWayland dio **p50 134,72 / p95 134,85 ms a 7,4
fps**: 133,3 ms clavados, que es el presenting estrangulado, no el juego. Con
el driver nativo de Wayland el presenting va a 240 Hz (1/239,76 = 4,1708 ms) y
el juego va sobrado.

La regla nueva (`VeredictoRender.estrangulado()`) no mira `has_focus()`, que
resultó no ser de fiar —en este setup da `false` con el presenting sano—, sino
la **forma** de la distribución: si el p50 es larguísimo (>100 ms), el p95 es
indistinguible del p50 (<1 ms) y ni un frame llegó a 9 fps, eso es el
compositor. Un juego lento tiene una **cola** (p50 8 / p95 35), no una línea.
El bench anota `ventana_en_foco` igual, como contexto, y marca
`valido: false` en el informe cuando el número no cuenta.

## Lo que queda sin resolver, dicho claro

- **`primitivas` se pasa del presupuesto.** 935 138 contra las 900 000 de
  `MedidorGPU.PRESUPUESTO_PRIMITIVAS`, así que el veredicto del bench sale
  "FUERA DE PRESUPUESTO" aunque el p95 entre de sobra. El número del
  presupuesto (900 k) se fijó para un mundo más chico que el que terminó
  siendo; **el arreglo es recalibrar ese número o bajar la escena, no
  optimizar**: con 935 k primitivas la GTX 1660 va al 100 % de 60 fps con un
  tercio del frame de CPU. No se tocó `medidor_gpu.gd` (no es de esta fase).
- **La calidad no se nota a 720p.** Entra en 60 fps en los cuatro niveles con
  el frame clavado. El ajuste sirve para equipos más flojos o resoluciones más
  altas; a esta placa, a esta resolución, elegir "Baja" no compra nada. Está
  documentado arriba con la medición que lo prueba, no con una intuición.
- **El resto del coste de la carga vive en `_al_mundo_listo`**, que recoloca 21
  NPCs, prende las fogatas e instala la UI de la fase 63/64 en un solo frame.
  Ese archivo (`scenes/demo/fase14_demo.gd`) no es de esta fase. Lo que sí se
  podía tocar, la cola de obra de las 9 ciudades, ya está escalonado.
- **Un aviso de error ajeno**: `_colocar_fogatas` (`fase14_demo.gd:162`) llama
  `get_global_transform()` sobre un nodo que todavía no está en el árbol, y el
  motor escupe `ERROR: Condition "!is_inside_tree()" is true` en cada entrada a
  la ciudad. No afecta al frame time, pero es ruido en el log.
- **El número de FPS que se ve en el juego sigue sin estar medido** con el
  `MonitorFPS` dentro de la partida (el título → creación → partida), porque
  el bench entra por la escena de juego directo. El flujo de pantallas es lo
  único sin medir.

## Qué se puede testear en headless y qué no

`tests/test_rendimiento.gd` (25 checks) cubre lo que ES lógica, en el árbol de
escena de verdad y moviendo el ajuste por la misma puerta que el panel:

- que subir la calidad reencienda la SSAO y el glow del `WorldEnvironment`
  **vivo** (la regresión del bug), y que con dos mundos vivos les llegue a los
  dos;
- que la calidad baje el coste de verdad, no un número: muestras de SSAO,
  desenfoque de la sombra, divisiones del atlas;
- que la escala de render llegue al viewport;
- que el bench distinga "lento" de "estrangulado por el compositor", con los
  números de la corrida real que se descartó.

Se verificó que el test **no celebra el bug**: anulando la llamada a
`PostProceso.aplicar_al_mundo()` (o sea, volviendo al bug) el test pasa de 24
ok / 0 fallos a 15 ok / 9 fallos.

**Lo que NO se puede testear en headless: que la GTX 1660 sostenga 60 fps.**
Eso necesita una GPU real y una ventana, y sale de acá. Un test headless con
drivers dummy mide lógica y da 0 en todos los monitores de render.

## Cómo reproducirlo

```sh
# La partida completa, con la carga, a 60 fps
godot --display-driver wayland --path . --script res://tools/bench_gpu.gd -- \
  --cargar --frames=8000 --warmup=0 --vsync=0 --tope=60 \
  --out=build/bench/bench_partida_60fps.json --dump=build/bench/bench_dumped.json

# Un nivel de calidad
godot --display-driver wayland --path . --script res://tools/bench_gpu.gd -- \
  --frames=2500 --warmup=240 --vsync=0 --tope=60 --calidad=0

# Con la GPU en el cuello (supersampling), para comparar calidades
godot --display-driver wayland --path . --script res://tools/bench_gpu.gd -- \
  --frames=1500 --warmup=180 --vsync=0 --tope=0 --escala=2.0 --calidad=3
```

`--display-driver wayland` es obligatorio en esta máquina: por XWayland el
compositor estrangula el presenting y el veredicto no vale. Los JSON de esta
corrida están en `build/bench/` (ignorado por git: se regeneran con los
comandos de arriba).
