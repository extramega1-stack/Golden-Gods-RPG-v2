# Tests headless — Fases 1, 2, 3, 4, 5 y 5.1

`test_stats.gd` verifica los datos puros (`StatBlock` + `Formulas`),
`test_entity.gd` la entidad base (`Entity`): daño, muerte, XP/niveles,
maná y round-trip de guardado. `test_player.gd` verifica la fase 3
(`Intent` como datos + la matemática pura de `Movimiento`: dirección
relativa a cámara, llegada suave, suavizado y orientación). La fase 4
añade: `test_enemy.gd` (enemigo data-driven, IA QUIETO→PERSEGUIR→ATACAR→MUERTO,
golpe con fórmulas, botín + XP al morir, ataque del jugador, oro),
`test_loot.gd` (tabla de botín determinista por semilla, rangos de oro
y cantidades, pickups por proximidad) y `test_save.gd` (guardar/cargar
versionado: vida, oro, posición, inventario y equipo reales —incluye que
los mods del equipo siguen aplicados en stats— y muertos/vivos). La fase 5
añade: `test_inventory.gd` (`ItemDB` + `Inventario`: apilado, quitar, usar
consumibles, serialización) y `test_skills.gd` (`SkillDB` + `SkillSystem`:
mana, cooldowns, rango, curación al lanzador, objetivo más cercano).
La fase 5.1 añade `test_seleccion.gd` (56 asserts): selección/deselección
+ señal (idempotente; muertos no elegibles), indicador 3D (visible bajo
los pies, se oculta sin selección), flash rojo (estado en `Entity` que
decae), rebind del botón de atacar (reescritura del InputMap + persistencia
en ConfigFile con ruta temporal inyectada), skills con acercamiento
(pendiente → destino al objetivo → lanzamiento al llegar; cancelación por
muerte y por deselección; curaciones sin moverse) y la REGLA DURA de NPCs
no atacables (doble clic, botón/tecla y skill dañina ignorados con motivo
"no_combatible"; el NPC sí se selecciona; `take_damage` sin efecto).
Todo sin abrir el juego.

```bash
# Solo la primera vez tras clonar, o cuando agregues scripts con `class_name`
# (regenera el caché de clases; sin esto los tests no resuelven los tipos):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --import

# Los tests (~2 segundos cada uno). Exit code 0 = todo verde:
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_stats.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_entity.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_player.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_enemy.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_loot.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_save.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_inventory.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_skills.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_seleccion.gd

# Smoke test de la escena demo de la fase 5.1 (300 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake res://scenes/demo/fase5_1_demo.tscn --quit-after 300
```

- Exit code **0** = todo verde.
- Exit code **N** = N fallos (el detalle sale por stderr).

Casos cubiertos: derivados calculados, tope de crítico, modificadores
plano/porcentuales por fuente (añadir, quitar, limpiar), daño normal, daño
crítico, varianza y daño mágico inyectados, daño mínimo 1 ante defensa enorme,
mitigación en (0,1], curva de XP monótona, pureza de `damage()` y round-trip
de guardado (`to_dict`/`from_dict`), transiciones de la IA del enemigo
(incluye leash y objetivo muerto), ataque del jugador con cooldown y rango,
oro que nunca baja de 0, determinismo del botín por semilla, pickups por
proximidad, y round-trip completo del save (no re-emite botín al cargar,
enemigos muertos quedan muertos).
