# 72A — Condiciones de victoria y derrota

## Por que esto existe
El juego NO tiene forma de ganar ni de perder. Se pueden jugar los 5 actos,
entregar las dos misiones finales (dan 600 oro y 1500 XP) y el juego sigue
exactamente igual. Cero pantallas de final, cero game over. Eso impide que el
juego sea "completo y jugable de principio a fin".

## Hechos ya verificados (no los re-descubras)
- Las 2 misiones finales existen como datos en `data/quests.json`:
  `q_final_sello` (Senda Liberty, la canónica) y `q_final_espada`
  (Senda del Arma). Ambas con `requiere: q_acto5_guerra`.
- `QuestLog.entregar()` (scripts/quests/quest_log.gd:280-319) marca `"entregada"`
  y paga recompensas. NADA lee ese estado despues.
- Hoy la muerte NO mata: el jugador revive en `RespawnHeros`
  (scripts/mundo/respawn_heroe.gd:182-200) sin penalidad, por decision
  documentada en scripts/player/player.gd:497-499.
- Solo la Arena PvE tiene victoria/derrota (scripts/arena/arena.gd:310-331) y no
  termina nada: la demo muestra un toast y te devuelve a la plaza.
- §7.4: el canon narrativo es inviolable. Final Liberty, dos sendas, Chronos
  invulnerable hasta el Acto V. NO cambies el canon, conectalo.
- §7.2: el combate NO se rediseña. No toques el combate.

## Qué hacer

### 1. Victoria
Al entregar `q_final_sello` (la canónica), el juego debe detectarlo y llevar a
una pantalla de final.

- Nueva clase `ResultadoPartida` (scripts/core/resultado_partida.gd) con la
  logica de victoria/derrota y su estado, SIGNALS para que la UI se suscriba
  (§9: la UI se suscribe a senales, nunca lee por frame).
- `PanelFinal` (scripts/ui/panel_final.gd, capa UI 92-94, rango de modales
  90-99 segun ui_layers.gd). Debe poder mostrar DOS finales distintos segun
  que senda se completo, con el tono del canon de MASTER_SPEC §3.
- Botones: "Volver al titulo" y "Continuar en NG+" (el NG+ ya existe y arranca
  desde pantalla_titulo.gd:203-218).

### 2. Derrota
La muerte del jugador debe tener coste y una pantalla de derrota, no un respawn
silencioso.

- Al morir con vida a 0: pantalla de derrota con opciones de revivir.
- Al revivir: en el ultimo refugio, perdiendo XP del nivel actual y un
  porcentaje de oro (el mundo ya tiene 9 refugios en data/refugios.json).
- La constante de perdida va en data/*.json, NO en el codigo (§9.4 datos
  primero).
- El guardado tiene que incluir el estado de derrota para no perder la partida.

### 3. Tests
`tests/test_fase72_victoria_derrota.gd`, extends SceneTree, convencion del repo:
`_chk(cond, nombre, detalle)` y `quit(_fallos)`.
Cubre: victoria por cada senda, derrota, coste de muerte, persistencia del
estado en el guardado, y que volver a cargar la partida no pierde el resultado.

## Archivos que SOS，你是 disjuntos con los otros dos workers
PROPIOS: scripts/core/resultado_partida.gd, scripts/ui/panel_final.gd,
         scripts/ui/panel_derrota.gd, tests/test_fase72_victoria_derrota.gd,
         data/derrota.json (nuevo), docs/especs/72A-victoria-derrota.md
TOCAR (con cuidado, solo lo minimo): scripts/quests/quest_log.gd,
         scripts/player/player.gd, scripts/mundo/respawn_heroe.gd,
         scripts/core/ui_layers.gd, scripts/save/save_system.gd,
         scenes/demo/fase14_demo.gd, project.godot (solo si agregas input action)

## Convenciones OBLIGATORIAS (spec §8, 12 lecciones)
- Tipar TODO: `var x: T`, nunca `:=` sobre Variant.
- `Array[String]` en consts.
- Builtins con sufijo: `absi`, `clampf`, `maxi`, `mini`, `snappedf`.
- Sin `get()` de 2 argumentos sobre algo tipado.
- Sin metodos de instancia sobre `class_name`.
- Un script, un nodo, una responsabilidad. Registro en grupo `gg_system` con
  `system_id: StringName`.
- Todo atajo en el InputMap de project.godot, accion en ESPAÑOL. Prohibido
  `keycode ==` en sistemas.
- UI solo LEE StatBlock, nunca lo escribe.
- Nada de allocs por frame en caliente. `visible=false` en vez de crear/destruir.

## Verificacion obligatoria antes de darlo por hecho
1. `godot --headless --path . --import` (si agregaste un class_name nuevo)
2. `godot --headless --path . --check-only --script <cada script nuevo>` -> 0 fallos
3. `GODOT=/home/webo/Tools/godot/godot tools/run_tests.sh --smokes` -> la suite
   completa en verde. NO subas dejando tests en rojo.
4. Un test nuevo que FALLE si el sistema no esta conectado a la partida. Un
   test que solo se pasa a si mismo no vale (el spec §2487-2493 documenta esta
   trampa explicitamente).

## No hagas
- No migres a Unreal ni a Three.js. Godot 4.7.2.
- No rediseñes el combate (§7.2).
- No cambies el canon narrativo (§7.4).
- No toques scripts/audio/** (otro worker) ni scripts/progresion/** ni
  scripts/skills/** (otro worker).
- No commitees en main. Trabaja en TU worktree y commitea ahi.
