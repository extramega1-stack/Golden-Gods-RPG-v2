# `models/` — los modelos 3D del juego

Aquí van los **`.glb`** (glTF binarios). Godot los importa solo al abrir el
proyecto o con `godot --headless --path . --import`.

> **Estado actual: 6 modelos** — `bandido_rig.glb` (un `goblin` de la plaza) y
> los cinco de clase (`clase_arquero`, `clase_daguero`, `clase_mago`,
> `clase_clerigo`, `clase_guerrero`), que son los que lleva el jugador. Los 79
> restantes del pack siguen sin entrar. Cada modelo que se meta tiene que estar **registrado en
> `data/modelos.json`** con su licencia y su origen: hay un test
> (`test_fase48_anclajes_bench`) que falla si un `.glb` no está en el manifiesto
> o si la licencia no es CC0/CC-BY.

## Reglas duras (§7.5)

1. **Nunca un asset de Blizzard.** Ni texturas ni mallas ni animaciones.
2. Solo licencia **CC0** o **CC-BY** (registrada en el manifiesto).
3. Los **85 GLB de Meshy** quedaron **autorizados por Juan Diego el 2026-09-25**
   con licencia CC0/CC-BY. Al meter uno, su entrada en `data/modelos.json`
   dice de qué asset es.

## Antes de meter un `.glb`: retopologízalo

Los 85 GLB del release `modelos-3d-v1` son **estáticos y enormes**: 96.760.060
triángulos en total, 255 texturas, **0 esqueletos, 0 animaciones, 0 nodos con
nombre**, y uno solo ya pasa de 900k triángulos (el techo por entidad). No se
mueven ni se animan solos: hay que ponerles un esqueleto.

El paso 0 es retopologizar (y riggear) con Blender headless:

```sh
~/Tools/blender/blender --background --python tools/preparar_modelo.py -- \
  ~/ruta/creep-bandido-1.glb models/bandido_rig.glb 20000 1
#                                                   ^tris  ^rig (1 = con esqueleto)
```

Con `rig 1` entra `tools/rig.py`: 19 huesos con los nombres de
`data/anclajes.json` y los 4 clips de la FSM (`idle`, `walk`, `attack`, `die`),
generados por procedimiento y con el mismo resultado en cada corrida. El
**quinto argumento son los grados del brazo** desde la vertical: el pack viene
en A (~40°) y el bandido traía los brazos más bajos (~30°). No se deduce de la
malla —con faldones y capas la silueta miente—; se declara en
`data/modelos.json` con la clave `pose_brazos`.

Qué hace: une las mallas, decima en 3 pasadas hasta el objetivo, **posa el
modelo en el suelo** (min z = 0, centrado en x/y — los exports de Meshy vienen
centrados en el origen y el bicho aparece enterrado) y exporta. El piloto:
1.704.220 → 20.000 triángulos en 37 s, 1,90 m, 8,2 MB.

Godot extrae las texturas del `.glb` a `models/*.jpg` e importa cada una por
separado: **déjalas en Lossless** (`compress/mode=0`). Con VRAM Compressed este
modelo baja de 271 a 214 MB, pero su material fuerza una conversión
`RGB8 → RGBA8` al cargar y no se ha podido medir limpio; con 1 GB de presupuesto
no compensa.

## Cómo se conecta un modelo (3 pasos)

1. **Retopologízalo y copia el `.glb` aquí.** Ejemplo: `models/heroe.glb`.
2. **Regístralo en `data/modelos.json`** (licencia, autor, fuente).
3. **Pon su ruta donde lo consuma un `data/*.json`**:
   - cuerpo del jugador → `data/clases.json`, en la clase:
     ```json
     "modelo": "res://models/clase_guerrero.glb",
     "modelo_escala": 0.90
     ```
     `aplicar_clase()` lo cuelga y apaga la cápsula. El equipo (paper-doll) se
     queda en su sitio porque sus offsets son absolutos en metros y el modelo
     mide lo mismo que la cápsula.
   - cuerpo de un enemigo → `data/enemies.json`, en el arquetipo:
     ```json
     "modelo": "res://models/bandido_rig.glb",
     "modelo_escala": 0.62
     ```
     `scripts/enemy/enemy.gd` sustituye la cápsula por la malla (sin tocar el
     nodo `Cuerpo`, y siempre volviendo a la cápsula si el siguiente arquetipo
     del pool no tiene modelo).
   - pieza de equipo → `data/anclajes.json`, en el slot que corresponda:
   ```json
   "slot": "arma",
   "mesh_path": "res://models/espada_hierro.glb",
   "anclaje": "Hand.R"
   ```
   Con `mesh_path` relleno, el `PaperDoll` usa el modelo **en vez de** la
   forma procedural de `forma` (que sigue ahí como respaldo: si el archivo
   falta, avisa y vuelve a la primitiva, el juego no se rompe).

## Qué NO va aquí

- **Terreno**: el terreno es el heightmap de `data/terreno.bin` (289×289,
  36 chunks con 2 LOD). No se sustituye por un modelo; si quieres detalle,
  son doodads.
- **Nada que no sea `.glb`/`.gltf`**: las texturas sueltas, `.fbx` u
  `.obj` se convierten a `.glb` antes de entrar, para que el motor solo tenga
  que leer un formato.

## Convención de nombres de hueso (para las animaciones)

El `anclaje` de cada slot es el **hueso del modelo** donde cuelga la pieza, y
la Fase 49 colga un `AnimationPlayer` llamado `Anim` con clips nombrados como
la FSM que ya tiene el juego:

| Clip | Estado de la FSM | Cuándo |
|---|---|---|
| `idle` | `QUIETO` | parado |
| `walk` | `PERSEGUIR` | caminando o persiguiendo |
| `attack` | `ATACAR` | golpeando o lanzando skill |
| `die` | `MUERTO` | muerto |

Huesos que usa la tabla hoy: `Hand.R`, `Hand.L`, `Head`, `Chest`, `Neck`,
`Foot.L`, `Foot.R`. Si tu modelo usa otros nombres, se cambian en
`data/anclajes.json` (no hay que tocar código). El bandido ya los trae todos:
sale de `tools/rig.py` con esos nombres a propósito, para que el paper-doll
funcione con él sin tocar nada.

Los clips se reproducen solos según el estado del enemigo (`estado` es una
propiedad en `scripts/enemy/enemy.gd`). `idle`, `walk` y `attack` ciclan;
`die` no. Si tu modelo no trae `AnimationPlayer`, el enemigo se dibuja igual,
solo que quieto.

## Presupuesto de render (§9.5, Fase 48)

Medido con el mundo entero, antes del modelo: **443 draw calls, 285k
triángulos, 233 FPS**. Con el bandido puesto (3 goblins en la plaza, Fase 49):
**435 draw calls, 279.637 primitivas, 206,6 FPS · p50 4,76 ms · p95 5,56 ms ·
270,8 MB**. Presupuesto: **≤ 1200 draw calls, ≤ 900k triángulos, ≤ 1 GB de
vídeo**, y ≤ 30k triángulos por entidad.

Cada modelo con su propio material cuesta draw calls aunque se repita. Antes
de meter 85 modelos, conviene agrupar por material y reusar. El bench:

```sh
godot --path . --script res://tools/bench_gpu.gd -- --frames=400 --warmup=150
```

**Con la ventana enfocada.** Bajo Wayland, una ventana sin foco la estrangula
el compositor a ~7,5 Hz (133 ms clavados en cada frame, con la GPU al 0% de uso)
y el veredicto sale "FUERA DE PRESUPUESTO" por el present, no por el juego. El
bench avisa si no tiene el foco y anota `ventana_en_foco` en el JSON: si ves ese
aviso, el p95 no vale. Con el rig: **p50 4,17 ms · p95 4,17–4,24 ms · 424 draws · 263.070 primitivas ·
258 MB** (sale más barato que el modelo estático: el esqueleto no cuesta frame).
Con el jugador ya con modelo de clase: **p50 4,17–4,55 ms · p95 4,55–4,76 ms ·
439 draws · 410.770 primitivas · 335 MB**. Los 6 modelos ocupan 104 MB (la mitad
son los `.jpg` que Godot extrae de cada `.glb`).
