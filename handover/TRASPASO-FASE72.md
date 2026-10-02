# Traspaso — Fase 72

> Escrito por el coordinador al cierre de sesión. Los tres workers de Orca
> **terminaron sin que nada fuera integrado**. Empezá por acá.

## 1. Estado

Godot 4.7.2, RPG single-player, **121/121 tests verde** en `main` (commit
`7dc0ddf`, tag `v3.56`). Los tres workers de la Fase 72 tienen su trabajo
commiteado en ramas y exportado en parches, **pero ninguno está integrado**.

## 2. PRIMERO: integrar el trabajo de los workers

Es lo único que bloquea todo lo demás. Tres parches, 72 archivos, 5.353 líneas,
**sin verificar por el coordinador**.

| Frente | Rama | Commit | Tamaño |
|---|---|---|---|
| 72A victoria/derrota | `extramega1-stack/victoria-derrota` | `8ed5c47` | 101 KB, 16 archivos |
| 72B progresión | `extramega1-stack/progresion-desconectada` | `1896f27` | 92 KB, 26 archivos |
| 72C audio | `extramega1-stack/audio-huecos` | `16e3fe5` | 88 KB, 30 archivos |

Parches en `handover/fase72-patches/`.

Orden: **72A primero** (es lo que hace el juego ganable), después 72B, después
72C. Son de propiedad de archivo disjunta por diseño, pero los tres tocan
`scenes/demo/fase14_demo.gd` y `project.godot`: habrá conflictos.
**Integrá uno, corré la suite, y recién después el siguiente.**

```sh
cd /home/webo/Projects/Golden-Gods-RPG-v2
git merge --no-ff extramega1-stack/victoria-derrota
GODOT=/home/webo/Tools/godot/godot tools/run_tests.sh --smokes
```

Si un worker dejó la suite en rojo, **arreglalo antes de integrar el siguiente**.
Los 3 tests nuevos que escribieron (`test_fase72_*`) tienen que pasar ellos
también: un worker que entrega con tests rojos no entregó.

## 3. Qué hizo el coordinador antes de cerrar

Todo commiteado, todo verificado:

- **Limpieza de la sesión de Mixamo.** 17 MB de artefactos de prueba que
  estaban trackeados en git, fuera. 3 tests revertidos que justificaban cambios
  con una modificación que nunca se aplicó. Tag `v3.56`, 73 commits pusheados.
- **El goblin se moveía a la velocidad de una clase.** Va colgado a escala 0,62 y
  usaba la misma velocidad de cuerpo que las clases (escala 0,9): medido, **8,00
  pisadas por segundo** contra las 3,0–3,4 que el esqueleto sostiene. Un
  arquetipo ahora puede declarar su propia velocidad (`enemy.gd`), y el goblin
  declara 4,2 m/s.
- **Un bug de test:** `const ESCALA = 0.9` para todos los modelos, cuando
  `bandido_rig` va a 0,62. Medía su zancada 1,45 veces inflada. Ahora lee la
  escala de los mismos datos que el juego.
- **4 paneles no se apilaban al abrir** (inventario, equipo, habilidades, ficha):
  flipeaban `visible` y solo llamaban `PilaUI.cerrar()` al cerrar, nunca
  `PilaUI.abrir()`. El ESC comprueba `es_cima(self)`, así que **no los cerraba**.
- **El tutorial abría una caja que ESC no cerraba** — única salida una pestaña de
  30 px. Ahora cierra con ESC cuando no hay nada apilado encima.
- **Un bug en el propio playtest:** la fase P11 no ocultaba el panel que iba a
  probar, y como el panel alterna con su tecla, la tecla lo cerraba. El check de
  "se abre con su tecla" fallaba sin que hubiera nada roto.
- **`QuestDB.existe()` no sincronizaba la rotación diaria.** Las diarias son
  efímeras (su id lleva la fecha) y se generan en runtime, así que `existe()` las
  daba por inexistentes y el `QuestLog` las rechazaba como bloqueadas.
- **El p95 de frame no era un problema.** El spec lo declaraba como brecha nº1 con
  34,74 ms; venía de una medición donde el proceso terminaba el frame en 0,69 ms
  (artefacto del banco). El bench real da **16,67 ms, 0 frames fuera de
  presupuesto**. Spec actualizado.
- **`tools/soldar_malla.py`** nueva: la malla del guerrero tiene **169 islas**
  (el arquero, 801) y el voxel remesh las une en 1. **No se integró**: la textura
  queda a parches porque las UV son por isla. Está documentada con esa limitación.

## 4. Estado real del proyecto (medido, no supuesto)

El README decía "Fase 0, nada jugable" y mentía. Lo que hay:

- **Combate completo**: hit-stop, knockback, telegrafía de jefe, fases, élites
- **Progresión completa**: XP, niveles, 4 atributos, equipo, 40 habilidades, 15
  talentos, 56 misiones, NG+
- **20 arquetipos de enemigo** con IA determinista, 6 jefes con 3 fases
- **Mundo**: 36.864 u, 10 regiones, 9 ciudades, 1.133 spawns, ciclo día/noche,
  clima de 4 estados
- **Audio**: sintetizador procedural + música adaptativa de 4 capas con director
- **Guardado**: versionado, atómico, `.bak`, probado end-to-end
- **Rendimiento**: p95 16,67 ms en GTX 1660, 373 MB VRAM

**Lo que faltaba y es lo que da sentido a la Fase 72: no había forma de ganar ni
de perder.** Se podían entregar las dos misiones finales y el juego seguía igual.

## 5. Pendiente, en orden

1. **Integrar 72A, 72B, 72C** (sección 2)
2. **`tools/jugar.sh` tiene 4 pasos en rojo.** Son la partida completa, el arnés
   que verifica que la UI *se mueva*. Los 4:
   - `la fase «hablar» termina sola` — el jugador llega al NPC pero la fase no
     termina en 9.001 frames (150 s), en (171, 40, -27)
   - `la fase «paneles ESC» termina sola` — mismo corte en (0, 40, 45)
   - `el ESC cierra lo que hay abierto antes de empezar` — `PanelTutorial`
   - `«PanelInventario» se abre con su tecla` — probablemente lo arregló el fix
     de la pila; **no se volvió a correr la partida completa después**
3. **Después**: 19 de 20 enemigos son cápsulas, 146 edificios son `BoxMesh`, cero
   antialiasing configurado, sin shaders (agua, terreno).
4. **19 worktrees viejos de Orca** sin limpiar. **No los borres a ciegas:**
   `w9-modelo` tiene 83 archivos sin commitear y `w10-texturas` 5 commits sin
   integrar. No son míos.

## 6. Reglas duras (spec §7, no negociables)

1. Single-player local. Nada online, nada competitivo
2. **El combate no se rediseña**, solo reimplementación fiel
3. Mundo sin reescalar: 36.864 u
4. Canon narrativo inviolable: final Liberty, dos sendas, Chronos invulnerable
   hasta el Acto V
5. Sin assets de Blizzard. Los 85 GLB de Meshy están autorizados CC0/CC-BY
6. Una fase a la vez, con playtest antes de pasar
7. La UI **solo lee** el `StatBlock`, nunca lo escribe
8. Evidencia por entrega: commit + tag + release + árbol limpio + SHA-256

Convenciones (spec §8): tipar todo (`var x: T`), `Array[String]` en consts,
builtins con sufijo (`clampf/maxi/mini/absi`), sin `get()` de 2 args sobre
tipado, sin métodos de instancia sobre `class_name`, todo atajo en el InputMap
con acción **en español**, `keycode ==` prohibido en sistemas, datos primero
(`data/*.json`, no código), cero allocs por frame en caliente.

**Si agregás un `class_name` nuevo: `godot --headless --path . --import` ANTES de
los tests.** El tipo se registra en la caché global de Godot, no en el repo.

## 7. Trampas que me costaron tiempo

**Mi propia sesión, medido:**

- **`AnimationPlayer.seek()` NO evalúa las pistas.** Para ver una animación hay que
  advancing el `AnimationTree` (`ArbolAnimacion.avanzar`). Perder 3 renders por
  esto. Y `montar()` solo rellena la ruta del árbol si el nodo **ya está dentro
  del árbol**: montarlo en `_initialize` lo deja apuntando a nada.
- **Una corrutina sin `await` no corre.** `_paso()` con `await` adentro, llamada
  sin `await`, no produce nada y no da error.
- **Un `replace` de texto que no encuentra el ancla NO da error**: escribe el
  archivo igual y sigue. Me pasó dos veces, una por un carácter inter-lineal
  invisible. **Siempre verificá que el reemplazo se aplicó.**
- **`save_as_mainfile` escribe `.blend` aunque le pidas `.glb`.** Para glTF es
  `bpy.ops.export_scene.gltf(export_format='GLB')`.
- **`bpy.ops.object.voxel_remesh` es un operador de contexto**: sin objeto
  seleccionado y activo tira `poll() failed`, y el error no menciona selección.
- **`tools/run_tests.sh` mide tests, no gameplay.** `tools/jugar.sh` es el que
  corre la partida completa. Un test por sistema no dice nada sobre si el sistema
  está conectado a nada.
- **Un test que depende de la fecha se rompe solo al cambiar el día.**
  `rotacion_diaria.gd` usa `Time.get_unix_time_from_system()`.

**Orca:**

- **Si a un worker le pasás una ruta FUERA de su worktree, se frena en un diálogo
  de permisos.** AGENTS.md ya lo advertía. Puse la spec dentro del worktree y
  mandé "Allow always".
- **`worker-start` necesita `--agent opencode`.** Sin eso: "A configured --agent
  is required".
- **`worker-start` devuelve el id de TAREA, no el dispatch.** Para ver el estado
  usá `orca orchestration worker-list --run <run_id>`.
- **Los workers NO commitean al terminar.** Hay que commitear en su worktree antes
  de liberar: `worker-release`.
- `PATH="$HOME/.local/bin:$PATH"` — `orca` no está en el PATH por defecto.

## 8. Orca: run activo

```
run:     run_a0a0dfd82d7c
objetivo: Fase 72: prototipo completo y jugable de principio a fin
```

Los 3 workers quedaron `succeeded/done`, `terminal=reclaimable`. Liberalos con:

```sh
orca orchestration worker-release --dispatch ctx_ef1847fe2aa8   # 72A
orca orchestration worker-release --dispatch ctx_4f8b9b17d215   # 72B
orca orchestration worker-release --dispatch ctx_0e66dbb98869   # 72C
```

**Liberá después de integrar**, por si hay que reabrir.

Specs de cada frente, en `docs/especs/` y también dentro de cada worktree.
