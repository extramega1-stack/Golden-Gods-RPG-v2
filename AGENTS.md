# AGENTS.md — Golden Gods RPG Remake (Godot 4.7.2)

RPG local single-player, mundo abierto estilo L2/MU. Fuente de verdad: `docs/MASTER_SPEC.md`.
Lo que no está en el spec no existe. Estado: Fase 46 terminada.

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
- Sin assets Blizzard; 85 GLB Meshy solo con autorización Juan Diego (§7.5).
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
