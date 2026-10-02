# Traspaso — Fase 72 y 73

> **Actualizado 2026-10-02.** La Fase 72 está **INTEGRADA Y VERIFICADA**, y la
> partida completa pasa de punta a punta. Este archivo ya no dice "empezá por
> acá": dice qué se hizo y qué queda.

## 1. Estado

Godot 4.7.2, RPG single-player. `main` con el árbol limpio y sincronizado con
`origin`. El SHA exacto se lee de `git log -1`; no está escrito acá a
propósito, porque envejece con cada commit y un traspaso que miente sobre el
commit es peor que uno que no lo dice.

- **124/124 tests** verdes con `tools/run_tests.sh --smokes`.
- **`tools/jugar.sh`: 60 verdes, 0 rojos**, en dos runs seguidos. Antes daba 4.
- Tags: `v3.57` (72 integrada), `v3.58` (partida en verde), `fase-72-integrada`.

**Lo único que falta es el playtest de Juan Diego** (§7.6 lo exige antes de
avanzar a otra fase).

## 2. La Fase 72: DONE

Los tres workers de Orca terminaron sin que nada fuera integrado. Ya están
integrados, uno a uno, con la suite en verde entre medio.

| Frente | Rama | Estado |
|---|---|---|
| 72A victoria/derrota | `extramega1-stack/victoria-derrota` | integrada |
| 72B progresión | `extramega1-stack/progresion-desconectada` | integrada |
| 72C audio | `extramega1-stack/audio-huecos` | integrada |

Los parches de respaldo siguen en `handover/fase72-patches/` (fuera del índice
por diseño: duplicaban el repo en cada commit sin agregar nada).

Los tres workers de Orca quedaron **liberados** (`Terminals: released=3`). El 72C
estaba en `ready` y no en `succeeded`, así que se verificó antes que su rama ya
estaba integrada y que no tenía trabajo sin commitear, y se usó `worker-stop`
(fence) más `worker-release`.

## 3. La partida completa: de 4 rojos a 0

Es la parte que costó encontrar, porque un rojo de `jugar.sh` **no es un test
roto: es el juego roto**. De los cinco, cuatro no eran el juego.

### Tres bugs de UI, de verdad

1. **El fundido se quedaba en la pila de paneles para siempre.** Se metía con
   `PilaUI.abrir()` y nunca salía. Como la cima es la única que recibe el ESC y
   la única que puede apilarse encima, **después de un cambio de escena no se
   abría ningún panel**: mochila, equipo, códice, opciones. Arreglado con el
   contrato de la pila: entrar al abrir, **salir al cerrar**.
2. **El menú de pausa no abría con una tecla.** El `PanelTutorial` se cuelga
   antes en el orden del árbol y se quedaba con el ESC. El primer ESC no abría
   nada y el segundo sí. El tutorial ahora **se lo cede**: una tecla es de un
   dueño, y el ESC es del menú de pausa.
3. **La tecla 0 no abría el tutorial y la caja no se podía cerrar.** La acción
   estaba en el Input Map y nadie la escuchaba; y cada señal la reabría en el
   mismo frame. La regla que quedó escrita: **cerrar a mano manda sobre la
   señal**.

### Cuatro del arnés (producen falsos rojos si no se Dichan)

- Las teclas **nunca se soltaban**, y `is_action_pressed()` es el flanco de
  bajada: los reintentos de la misma tecla no hacían nada.
- El clic sobre el NPC **caía fuera de pantalla** (y=5678 de 1280), o sea que
  era un clic en el suelo, que además **deselecciona**.
- **Tres ESC en un mismo frame son un ESC**: Godot despacha
  `_unhandled_input` una vez por frame.
- `MenuPausa` y `PanelTutorial` **no son paneles comunes** (la pausa es la base
  de su propia pila; el tutorial se cierra con la tecla 0).

Y se agregó la fase que faltaba: **aceptar una misión no es completarla**.

## 4. Lo que sigue

1. **Playtest de Juan Diego de `v3.58`.** Es lo único bloqueante.
2. Los 5 `OMITIDO` de la partida son límites declarados del arnés headless (el
   raycast no llega al collider del mob, un material no lleva afijos, y la
   partida corta no llega a talar un árbol ni a prestigiar). No son fallos.
3. **Los 27 worktrees de Orca siguen ahí.** NO los borres a ciegas: `w9-modelo`
   tiene **83 archivos sin commitear** y `w10-texturas` **5 commits sin
   integrar** (verificado otra vez hoy). No son míos.
4. Antes de la Fase 73, el handover señalaba que **19 de 20 enemigos son
   cápsulas**, 146 edificios son `BoxMesh`, sin antialiasing y sin shaders de
   agua o terreno. Sigue igual.

## 5. Reglas duras (spec §7, no negociables)

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

## 6. Trampas que me costaron tiempo

**Godot:**

- **`AnimationPlayer.seek()` NO evalúa las pistas.** Para ver una animación hay
  que advancing el `AnimationTree` (`ArbolAnimacion.avanzar`). Perder 3 renders
  por esto. Y `montar()` solo rellena la ruta del árbol si el nodo **ya está
  dentro del árbol**: montarlo en `_initialize` lo deja apuntando a nada.
- **Una corrutina sin `await` no corre.** `_paso()` con `await` adentro, llamada
  sin `await`, no produce nada y no da error.
- **Un `replace` de texto que no encuentra el ancla NO da error**: escribe el
  archivo igual y sigue. **Siempre verificá que el reemplazo se aplicó.**
- **`save_as_mainfile` escribe `.blend` aunque le pidas `.glb`.** Para glTF es
  `bpy.ops.export_scene.gltf(export_format='GLB')`.
- **`bpy.ops.object.voxel_remesh` es un operador de contexto**: sin objeto
  seleccionado y activo tira `poll() failed`, y el error no menciona selección.
- **`tools/run_tests.sh` mide tests, no gameplay.** `tools/jugar.sh` es el que
  corre la partida completa. Un test por sistema no dice nada sobre si el
  sistema está conectado a nada.
- **Un test que depende de la fecha se rompe solo al cambiar el día.**
  `rotacion_diaria.gd` usa `Time.get_unix_time_from_system()`.
- **Las lambdas de GDScript capturan por VALOR.** Escribir dentro de una lambda
  no cambia la variable de afuera: por eso los handlers de test son métodos del
  propio script, no lambdas.
- **`for ... else` no existe en GDScript.**

**Orca:**

- **`orca serve` levanta el runtime headless**, sin GUI. Es lo que hay que usar
  si la app no está corriendo: el CLI solo lee `orca-runtime.json`, que la app
  escribe. Después de usarlo, `kill` por PID (el `pgrep -f "orca serve"` se
  matchea a sí mismo y cuelga la shell).
- **Si a un worker le pasás una ruta FUERA de su worktree, se frena en un diálogo
  de permisos.** AGENTS.md ya lo advertía.
- **`worker-start` necesita `--agent opencode`.** Sin eso: "A configured
  --agent is required".
- **`worker-start` devuelve el id de TAREA, no el dispatch.** Para ver el estado
  usá `orca orchestration worker-list --run <run_id>`.
- **Los workers NO commitean al terminar.** Hay que commitear en su worktree antes
  de liberar: `worker-release`.
- **`worker-release` es solo para workers *settled*.** Uno en `active` se frena
  con `worker-stop --dispatch <id>` primero, y después se libera el terminal.
- `PATH="$HOME/.local/bin:$PATH"` — `orca` no está en el PATH por defecto.

## 7. Orca: run de la Fase 72

```
run:     run_a0a0dfd82d7c
objetivo: Fase 72: prototipo completo y jugable de principio a fin
```

Los 3 workers quedaron liberados. El run se conserva como registro.

Specs de cada frente, en `docs/especs/`.