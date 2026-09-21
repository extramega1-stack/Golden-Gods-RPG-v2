# Tests headless — Fases 1, 2, 3 y 4

`test_stats.gd` verifica los datos puros (`StatBlock` + `Formulas`),
`test_entity.gd` la entidad base (`Entity`): daño, muerte, XP/niveles,
maná y round-trip de guardado. `test_player.gd` verifica la fase 3
(`Intent` como datos + la matemática pura de `Movimiento`: dirección
relativa a cámara, llegada suave, suavizado y orientación). La fase 4
añade: `test_enemy.gd` (enemigo data-driven, IA QUIETO→PERSEGUIR→ATACAR→MUERTO,
golpe con fórmulas, botín + XP al morir, ataque del jugador, oro),
`test_loot.gd` (tabla de botín determinista por semilla, rangos de oro
y cantidades, pickups por proximidad) y `test_save.gd` (guardar/cargar
versionado: vida, oro, posición, inventario simple y muertos/vivos).
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

# Smoke test de la escena demo de la fase 4 (300 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake res://scenes/demo/fase4_demo.tscn --quit-after 300
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
