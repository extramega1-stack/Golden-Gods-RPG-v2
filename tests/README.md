# Tests headless — Fases 1, 2, 3, 4, 5, 5.1, 6, 6.2 y 7

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
La fase 6 añade `test_npcs.gd` (56 asserts): `NpcDB` carga nombre/rol/líneas
de `data/npcs.json` (mismo patrón que ItemDB/SkillDB), `NPC.configurar` lee
rol y diálogo y tolera campos ausentes, `Player.interactuar` emite
`hablar_con` solo con un NPC vivo seleccionado (sin selección o con un
enemigo no hace nada), la `VentanaDialogo` arranca oculta y muestra
nombre/rol/líneas correctas (avanzar por líneas, cerrar al final, E avanza
y ESC cierra consumidas antes que el Player), save v3 con NPCs (id +
posición; las partidas v2 sin bloque "npcs" cargan igual) y regresión de la
REGLA DURA (el NPC sigue no atacable: `take_damage` sin efecto,
`solicitar_ataque` lo ignora, pero sí se selecciona).
La fase 6.2 añade `test_clic.gd` (36 asserts): modelo Flyff de clic
izquierdo — primer clic selecciona (mob/NPC) sin atacar, segundo clic
sobre el mismo enemigo ataca (`objetivo_ataque`, `intent`, señal
`intencion_atacar`), clic en otro mob cambia la selección sin atacar,
segundo clic en NPC no hace nada (selección intacta), clic en suelo
deselecciona y ordena mover, y `_resolver_clic_entidad` es pura (decide
sin mutar). Todo sin abrir el juego.
La fase 7 añade `test_tienda.gd` (81 asserts): `TiendaDB` carga las 2
tiendas desde `data/tiendas.json` (nombres, stock, precios;
`tienda_de_npc` por npc), `Tienda.comprar` ("ok"/"sin_oro"/"sin_stock"/
"sin_espacio" con el oro revertido; el stock finito se agota),
`Tienda.vender` ("ok" con `precio_venta` de datos —stack de consumibles
descuenta bien—, "equipado" si está en algún slot del Equipo,
"sin_stock"), round-trip `to_dict`/`from_dict` (stock persistido;
tolerante a tiendas/items desconocidos), save v4 con tienda (stock
restaurado al cargar; las partidas v3 sin bloque "tiendas" cargan con
stock completo), `PanelTienda` (arranca oculto; `mostrar()` con NPC sin
tienda no revienta ni abre; ESC cierra) y `VentanaDialogo` (flujo
"Comerciar": la señal `comerciar_solicitado` solo con NPC vendedor; sin
tienda no hay botón —fase 6 intacta).

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
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_npcs.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_clic.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_tienda.gd

# Smoke test de la escena demo de la fase 6 (300 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake res://scenes/demo/fase6_demo.tscn --quit-after 300

# Smoke test de la escena demo de la fase 7 (300 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake res://scenes/demo/fase7_demo.tscn --quit-after 300
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
