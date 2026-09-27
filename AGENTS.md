# AGENTS.md — Golden Gods RPG Remake (Godot 4.7.2)

RPG local single-player, mundo abierto estilo L2/MU. Fuente de verdad: `docs/MASTER_SPEC.md`.
Lo que no está en el spec no existe. Estado: Fase 50 terminada.

## REGLA AUTOMÁTICA (no pedir skills al usuario)

Antes de responder o actuar, clasifica la tarea y carga TÚ los skills de la
tabla de abajo con el tool `skill`, sin que el usuario los nombre. Si hay 1%
de probabilidad de que un skill aplique, cárgalo para revisar. Si la tarea
pivota de disciplina, re-routea solo. Anuncia `Using [skill] to [purpose]`.
Si no sabes cuál, carga `router-gamedev` primero y sigue su veredicto.

## Cómo usar skills en este repo (manual, solo si quieres forzar)

1. Mención explícita manda: `usa <skill1> + <skill2> para <tarea> en <ruta>`.
2. Si dudas, `usa router-gamedev para: <tarea>` — detecta `project.godot` y elige el set mínimo.
3. Máximo 1–3 skills por tarea. Al pivotar de disciplina, re-routea.
4. Anuncia `Using [skill] to [purpose]` antes de actuar.

## Ruteo por tarea → skills (set mínimo)

| Quiero hacer | Skills a cargar |
|---|---|
| GDScript, tipos, parse errors, APIs 4.7 | `godot-gdscript` |
| Escenas, instanciado, autoloads, `DatosSesion` | `godot-nodes-scenes` |
| Items/skills/quests/enemigos como datos `.tres`/JSON | `godot-resources` + `rpg` |
| Señales, grupos `gg_system`, UI event-driven | `godot-signals-groups` |
| Stats, daño, XP, clases, inventario, equipo, skills, loot | `rpg` |
| Enemigos: FSM 4 estados, aggro, respawn, élites, jefes | `game-ai` ; si es complejo: `ai-behavior-trees-utility-ai` |
| NPCs, diálogos con lore, porteros, misiones hablar | `dialogue-systems` + `game-ai` |
| Misiones, cadenas, bloqueos `requiere`, Actos I–V | `rpg` + `dialogue-systems` |
| Tienda, economía, oro, stock, banco/mercado futuro | `rpg` |
| Guardado versionado `user://savegame.json`, migración | `save-systems` |
| Terreno 36.864u, chunks/LOD, ciudades, regiones, viaje rápido, clima, día/noche | `level-design` + `godot-3d-essentials` (+ `procedural-gen` si es generado) |
| Spawns, drops, cadenas por ciudad, jefes fragmento | `procedural-gen` + `rpg` |
| Jugador, cámara L2/MU tercera persona, zoom 650, oclusión | `camera-systems` + `godot-3d-essentials` |
| Input Map `[input]`, WASD relativo cámara, hotbar F1–F8, rebind barra | `input-systems` |
| HUD, paneles I/C/J/K/H, capas `UiLayers`, FlyFF restyle | `godot-ui-control` + `game-ui-ux` |
| Combate feel: números daño, hit-stop, shake, barras mob, telegrafía jefes | `game-feel` |
| Física: `move_and_slide`, capas, raycast clic suelo, winding terreno | `godot-physics` ; feel raro: `physics-tuning` |
| Animación personajes, blend, paper-doll procedural | `godot-animation` |
| SFX/música procedural (`sintetizador.gd`, buses), ambiente zona | `godot-audio` ; diseño: `audio-design` |
| Shaders terreno/agua/vida, tintes élite, FX skills | `godot-shaders` ; base: `shader-programming` |
| Lag/streaming mobs, pools, materiales compartidos, UI dirty-driven, carga progresiva | `performance-optimization` |
| Talentos, atributos STR/STA/DEX/INT, jobs, prestigio/NG+, profesiones, tablero destino, mascotas/monturas | `rpg` |
| Arena oleadas, eventos PvE, diarias/semanales, trofeos locales, cinemáticas, tutorial, modo foto | `rpg` + `level-design` |
| Modelos/tiles/UI/sprites nuevos, paletas ciudad, monumentos | `create-game-assets` |
| Bug raro, crash, freed object, flaky test | `systematic-debugging` (luego el skill del dominio) |
| Exportar PC/web/móvil, presets, CI | `godot-export` |
| Publicar demo web / Steam | `itch-publish` / `steam-publish` |
| Probar idea en 1h antes de fase | `prototype-fast` |

Skills que NO aplican aquí: `godot-multiplayer` (single-player, regla dura 1),
`godot-2d-movement`/`godot-tilemap` (juego 3D), Unity/Unreal/Phaser/Roblox/web-engines,
cualquier skill de marketing/crypto/trading.

## Reglas duras (del spec, no negociables)

- Single-player local. Nada online/competitivo (§7.1).
- Combate no se rediseña, solo reimplementación fiel (§7.2).
- Mundo 36.864 u sin reescalar (§7.3). Canon Liberty inviolable (§7.4).
- Sin assets Blizzard, NUNCA (§7.5). Los 85 GLB de Meshy quedaron AUTORIZADOS
  por Juan Diego el 2026-09-25 **con licencia CC0/CC-BY** (Fase 48): al meter
  uno se registra en `data/modelos.json` (obligatorio: `test_fase48` falla
  si un `.glb` de `models/` no está declarado o no es CC0/CC-BY).
- Los 85 GLB del release son **estáticos y enormes** (96,7M triángulos, 0
  huesos, 0 animaciones). Antes de meter uno: `tools/preparar_modelo.py` con
  Blender headless (el 4º argumento en 1 añade esqueleto y los 4 clips). El
  arquetipo lo declara por datos con `modelo` + `modelo_escala`; el código
  nunca nombra un archivo (Fases 49 y 49.1).
- Una fase a la vez + playtest Juan Diego antes de avanzar (§7.6).
- UI solo lee `StatBlock`, nunca escribe. Sistemas por señales, API chica (§7.11, §9).
- Un script, un nodo, una responsabilidad. Registro en grupo `gg_system`, `system_id: StringName`. UI de cada sistema en su CanvasLayer propio (§9.1).
- Capas UI por rango en `scripts/core/ui_layers.gd`: 10–19 HUD, 20–69 paneles, 70–79 progresión/mundo, 80–89 tienda/diálogo/cine, 90–99 modales (§9.2).
- Todo atajo en Input Map `project.godot`, acciones en español. Prohibido `keycode ==` en sistemas (§9.3, §5.3).
- Datos primero: skill/item/enemigo nuevo = tocar `data/*.json`, no código. Consts tipadas en `*_data.gd` (§9.4, §11).
- Rendimiento: mallas/materiales compartidos, pools FX, cero allocs/frame en caliente, `visible=false` antes que crear/destruir (§9.5).
- Estándar GDScript 12 lecciones (§8): tipar todo (`var x: T` no `:=` sobre Variant), `Array[String]` en consts, builtins con sufijo (`clampf/maxi/absi`), sin `get()` 2 args sobre tipado, sin métodos instancia sobre `class_name`, velos `visible=false` al arrancar, verificar firmas Godot 4.7.
- Empaquetado: `zip -r` del sistema, nunca reutilizar nombres ZIP (§7.8).

## Workflow por entrega

1. Spec cerrada (actualizar `docs/MASTER_SPEC.md` con la fase).
2. Implementar un sistema a la vez (§11).
3. `godot --headless --path . --check-only --script <cada script nuevo>` → 0 fallos.
4. Test headless nuevo `tests/test_faseNN_<tema>.gd` (`extends SceneTree`, `godot --headless --path . --script res://tests/test_faseNN_<tema>.gd`) en verde + regresión verde.
5. ZIP con versión + commit + tag + release + SHA-256 (§7.10).
6. Playtest Juan Diego → siguiente fase.

## Comandos

```sh
godot --headless --path . --check-only --script res://scripts/<dominio>/<script>.gd
godot --headless --path . --script res://tests/test_faseNN_<tema>.gd
godot --headless --path . --import
```

## Modelo 3D: retopología (Fase 49)

Los `.glb` del pack no se pueden meter tal cual. Se retopologizan con Blender
portable (sin root, `~/Tools/blender/blender`, 4.5 LTS):

```sh
~/Tools/blender/blender --background --python tools/preparar_modelo.py -- \
  entrada.glb models/salida.glb 20000 0
#                                            ^objetivo  ^rig (1 = esqueleto + clips)
~/Tools/blender/blender --background --python tools/preparar_modelo.py -- \
  entrada.glb models/salida.glb 30000 1 40
#                                                   ^tris  ^rig  ^grados del brazo
```

Seis trampas de Blender/rig que ya están pagadas (medidas, no deducidas):

- **Los pesos se calculan a mano** (`rig.pesos_proprios`). Ni el "bone heat"
  (falla en headless: `failed to find solution`, deja la malla con 0 vértices
  con peso y el `.glb` sin skin) ni las envolventes de Blender sirven: con
  pecho y cadera grandes el brazo salía con Chest 34% / Hips 33% / Thigh 31% y
  se movía 2° cuando se le pedían 23.
- **La longitud de un hueso es positiva**: hombro − codo, no codo − hombro. Con
  el signo al revés la cadena del brazo acaba en la cabeza y el casco se
  retuerce al animar.
- **En espacio de hueso, el eje vertical es la Y** (la Y local es el largo del
  hueso). Bajar la cadera con `location.z` la mueve **horizontalmente** y el
  cadáver se queda flotando con las rodillas dobladas.
- **`AnimationPlayer.play(nombre, blend, velocidad)`**: el 3er argumento es la
  velocidad, no el bucle. Con `-1.0` reproduce del revés. El bucle va en el
  recurso (`loop_mode`).
- **La pose del brazo es un dato por asset** (`pose_brazos` en
  `data/modelos.json`, 5º argumento del script), no se deduce de la silueta: con
  faldones y capas el ancho相对 no distingue una T de un brazo colgando (el
  luchador en T daba 1,02, o sea "colgado").
- **Al terminar de rigear, la pose se queda en reposo**: sin acción, los
  huesos conservan los valores del último clip escrito (el `die`), y cualquier
  render o preview sale con el cadáver.

Después: registrar en `data/modelos.json` (con licencia y procedencia), y en el
`data/*.json` del consumidor poner `"modelo": "res://models/salida.glb"` +
`"modelo_escala"`. El test `test_fase49_modelos_3d` comprueba el camino entero.

Dos trampas ya pagadas, no repetirlas:

- **El bench necesita la ventana con el foco.** Bajo Wayland el compositor
  estrangula el presenting a ~7,5 Hz (133 ms clavados, GPU al 0%) y el veredicto
  sale "FUERA DE PRESUPUESTO" por nada. `tools/bench_gpu.gd` avisa y anota
  `ventana_en_foco` en el informe; si aparece ese aviso, el p95 no mide el juego.
- **Texturas en Lossless** (`compress/mode=0`). Con VRAM Compressed el modelo
  baja de 271 a 214 MB, pero el material fuerza una conversión `RGB8 → RGBA8`
  al cargar. Con 1 GB de presupuesto no compensa el riesgo.
- **Un modelo con piel se cuelga instanciado, no cambiando la malla.** Una
  malla skinned en un `MeshInstance3D` suelto no se deforma: necesita el
  `Skeleton3D` en la misma rama. Por eso va como nodo `Modelo` y la malla que
  se tiñe se resuelve con `Cuerpo.malla(entidad)` (`scripts/core/cuerpo.gd`).
  Al colgarlo hay que **apagar la cápsula `Cuerpo`** (la visual): la colisión
  es el nodo `Colision`, que no se toca.
- **La zona segura es un radio de 40 m desde el ORIGEN**, no desde la plaza.
  Los tests `test_fase12_spawns` y `test_fase14_terreno` la comprueban, y el
  jugador está a 45 m: por eso el goblin con modelo quedó a 74 m y no se puede
  closer sin tocar esas reglas.
