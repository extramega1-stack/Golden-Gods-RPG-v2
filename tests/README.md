# Tests headless — Fases 1 y 2

`test_stats.gd` verifica los datos puros (`StatBlock` + `Formulas`) y
`test_entity.gd` la entidad base (`Entity`): daño, muerte, XP/niveles,
maná y round-trip de guardado. Todo sin abrir el juego.

```bash
# Solo la primera vez tras clonar, o cuando agregues scripts con `class_name`
# (regenera el caché de clases; sin esto los tests no resuelven los tipos):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --import

# Los tests (~2 segundos cada uno). Exit code 0 = todo verde:
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_stats.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_entity.gd
```

- Exit code **0** = todo verde.
- Exit code **N** = N fallos (el detalle sale por stderr).

Casos cubiertos: derivados calculados, tope de crítico, modificadores
plano/porcentuales por fuente (añadir, quitar, limpiar), daño normal, daño
crítico, varianza y daño mágico inyectados, daño mínimo 1 ante defensa enorme,
mitigación en (0,1], curva de XP monótona, pureza de `damage()` y round-trip
de guardado (`to_dict`/`from_dict`).
