# `models/` — los modelos 3D del juego

Aquí van los **`.glb`** (glTF binarios). Godot los importa solo al abrir el
proyecto o con `godot --headless --path . --import`.

> **Estado actual: 0 modelos.** El juego es 100% procedural. Cada modelo que
> se meta tiene que estar **registrado en `data/modelos.json`** con su licencia
> y su origen: hay un test (`test_fase48_anclajes_bench`) que falla si un `.glb`
> no está en el manifiesto o si la licencia no es CC0/CC-BY.

## Reglas duras (§7.5)

1. **Nunca un asset de Blizzard.** Ni texturas ni mallas ni animaciones.
2. Solo licencia **CC0** o **CC-BY** (registrada en el manifiesto).
3. Los **85 GLB de Meshy** quedaron **autorizados por Juan Diego el 2026-09-25**
   con licencia CC0/CC-BY. Al meter uno, su entrada en `data/modelos.json`
   dice de qué asset es.

## Cómo se conecta un modelo (3 pasos)

1. **Copia el `.glb` aquí.** Ejemplo: `models/heroe.glb`.
2. **Regístralo en `data/modelos.json`** (licencia, autor, fuente).
3. **Pon su ruta en `data/anclajes.json`**, en el slot que corresponda:
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
`data/anclajes.json` (no hay que tocar código).

## Presupuesto de render (§9.5, Fase 48)

Medido con el mundo entero: **443 draw calls, 285k triángulos, 233 FPS**.
Presupuesto: **≤ 1200 draw calls, ≤ 900k triángulos, ≤ 1 GB de vídeo**.

Cada modelo con su propio material cuesta draw calls aunque se repita. Antes
de meter 85 modelos, conviene agrupar por material y reusar. El bench:

```sh
godot --path . --script res://tools/bench_gpu.gd -- --frames=400 --warmup=150
```
