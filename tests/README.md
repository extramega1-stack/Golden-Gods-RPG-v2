# Tests headless — Fases 1, 2, 3, 4, 5, 5.1, 6, 6.2, 7, 8, 8.1, 9, 9.1, 9.2, 9.3, 10 y 11

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
La fase 8 añade `test_quests.gd` (99 asserts): `QuestDB` carga las 3
misiones desde `data/quests.json` (mismo patrón que NpcDB/TiendaDB),
`QuestLog` (aceptar "ok"/"desconocida"/"no_disponible";
`registrar_muerte` x5 → "lista" y progreso_texto "5/5";
`sincronizar_recoleccion` con Inventario real → "lista"; `entregar` da
oro/XP/items, consume los 4 colmillos y pasa a "entregada"; entregar sin
completar → "no_lista"; `registrar_dialogo("ilya")` completa el objetivo
"hablar"; `oferta_para_npc` disponible/activa/lista/entregada; señal
`cambiada`; round-trip `to_dict`/`from_dict` versionado; `from_dict({})`
vacío tolerante), save v5 con misiones (estados + progreso restaurados en
sitio; las partidas v4 sin bloque "misiones" cargan con QuestLog vacío),
`PanelMisiones` (arranca oculto; `alternar()`; `toast()` no revienta) y
`VentanaDialogo` (`mostrar_mision`: disponible/entregar/ocultar; la señal
`mision_solicitada` se emite sin cerrar el diálogo).
La fase 8.1 añade `test_ui_layout.gd` (36 asserts): layout responsivo del
diálogo en 3440×1440 (21:9, con Bram —el texto de misión más largo) y
1920×1080 (16:9, con Ilya) — el panel queda dentro del viewport, no
solapa la barra de skills, su borde inferior queda por encima de la
barra, capas diálogo(81) > barra(12), todas las barras del HUD dentro
del viewport y la descripción de la misión sin encimarse con los botones.
La fase 9 añade `test_detalle_mision.gd` (42 asserts): `QuestDB.lore()`
para las 3 misiones (lores del canon Liberty), `VentanaDetalleMision`
(arranca oculta; `mostrar` abre con nombre/lore/objetivos "x/y"/
recompensas con oro, XP e items con cantidad; misión desconocida o log
null no abren ni revientan; ESC, clic fuera y `cerrar_detalle` la
cierran) y su integración en `PanelMisiones` (el nombre de cada misión en
curso es un botón que abre el detalle; ESC con el detalle abierto no
cierra el panel; cerrar el panel cierra el detalle). Y
`test_respawn.gd` (34 asserts): `SpawnerMobs` (la muerte programa el
respawn tras `respawn_seg`; no reaparece antes de tiempo; el reaparecido
tiene el mismo arquetipo, está vivo y cerca del origen; default 20 s si
falta el campo o es ≤ 0; varios pendientes a la vez; el reaparecido se
auto-vigila; `vigilar` 2 veces no duplica; sin factory no revienta; la
señal `reaparecido` se emite) y que el save no persiste timers (el JSON
no guarda "respawn"/"pendiente"; vivos/muertos cargan como siempre).
La fase 9.1 añade `test_fase91.gd` (45 asserts): "!" dorado sobre NPCs con
misión disponible (`NPC.fijar_marcador_mision`: Label3D con billboard,
dorado, sobre la cabeza, oculto al inicio e idempotente; la demo refresca
los marcadores con `QuestLog.cambiada` —al aceptar, el "!" desaparece;
solo "disponible" lo muestra), segundo clic en NPC (resolver →
INTERACTUAR; cerca habla directo; lejos deja interacción pendiente con
destino al NPC que lo sigue si se mueve; al llegar al radio de
interacción abre el diálogo solo; deseleccionar cancela; nunca ataca ni
emite `intencion_atacar`) y respawn en la escena demo REAL (15 mobs, 5
por arquetipo, todos fuera del aggro inicial; matar un goblin en
`fase9_demo.tscn` y avanzar 16 s lo reaparece cerca de su origen; la
lista del guardado vuelve a 15). Además `test_clic.gd` (38 asserts)
cubre el nuevo comportamiento del segundo clic en NPC (INTERACTUAR en
vez de NADA).

La fase 10 añade `test_fase10.gd` (26 asserts): auto-ataque persistente
(pedido de Juan Diego: "cuando llega le pega, el personaje le sigue
atacando al mob") — un skill dañino sobre un objetivo válido fija
`objetivo_ataque` (antes solo el pendiente sin selección lo hacía);
tras el casteo los básicos se repiten solos con la cadencia existente
(skill en rango, skill pendiente al llegar, T y doble clic inician el
bucle); si el objetivo se aleja el destino lo sigue y al volver a rango
retoma; la muerte del objetivo detiene el bucle, deselecciona y no
camina al cadáver (9.3); la orden de mover lo cancela; `deseleccionar()`
suelta el foco de combate completo (objetivo + orden de movimiento);
la curación no fija objetivo ni mueve.

La fase 11 añade `test_fase11.gd` (56 asserts): héroe y presentación —
`ClaseDB` carga `data/clases.json` (4 ids en orden, solo "guerrero"
jugable, stats base 45/10/0/0, colores que parsean a Color con default
dorado), `validar_nombre` ("" / "   " / 17 caracteres → error; "Ilya" /
"A" / 16 caracteres → válido), identidad del `Player` (`_ready` aplica la
clase guerrero desde datos; `fijar_identidad` emite `identidad_cambiada`;
`aplicar_clase` pone stats y llena vida/maná; id desconocido no toca nada),
`DatosSesion` (`nueva_partida`/`pedir_continuar`/`limpiar`/`aplicar_a` con
Player real y con `continuar=true` sin tocar nada), save con nombre/clase
(round-trip restaura ambos; dict viejo sin esas claves carga con
"Héroe"/"guerrero"), `PantallaTitulo.puede_continuar` (ruta inyectada),
`RetratoHeroe` (pinta nombre/nivel/inicial; `die()` → modulate gris;
`refrescar()` con vivo restaura; `identidad_cambiada` re-lee) y regresión
del HUD (conectar/refrescar con el retrato integrado no revientan).

La fase 12 (regiones) añade `test_fase12_regiones.gd` (52 asserts):
`RegionDB` carga `data/regiones.json` (10 regiones, ids únicos en orden,
10 campos, tintes "#rrggbb", bandas 1–5 … 55–70; `cargar()` idempotente),
cobertura total y sin solapes por muestreo (625 puntos del mapa, esquinas
incluidas; intervalos semiabiertos, el borde 18432 incluido), Piedraceniza
contiene al (0,0), `region_en` en bordes compartidos y fuera del mapa → {},
`por_id` existente/desconocido, `VigiaRegion` (emite `descubierta` una sola
vez por región por sesión, `region_actual`, sin jugador/db no revienta,
`reiniciar_descubrimientos`) y `BannerRegion` (arranca oculto,
`mouse_filter` IGNORE en él y sus hijos, `mostrar()` con texto correcto,
fundido de entrada/salida y auto-ocultado ~3.5 s, reutilizable).

La fase 12 (terreno) añade `test_fase12_terreno.gd` (215 asserts):
`Terreno` lee `data/terreno.bin` (289×289 alturas + colores), escala real
(TAMANO 36864, PASO 128, X0/Z0 −18432), `altura_en()` bilineal con clamp en
bordes, `dentro()`, 36 chunks 6×6 con 2 LODs (`visibility_range` 0–900 y
900–30000), colisión en capa 1, y `Entity._pegar_al_terreno()` (con
`terreno == null` no cambia nada).

La fase 12 (spawns) añade `test_fase12_spawns.gd` (14 asserts):
`data/spawns.json` trae 1121 entradas {arquetipo, x, z, nivel} del legado
(gx=x, gz=4096−y; nivel→arquetipo: ≤30 goblin, 31–200 lobo, >200 ogro;
zona segura de 40 m en la aldea), todas dentro del terreno y con
arquetipos válidos; `tools/generar_spawns.py` es determinista.

La fase 12 (ciclo) añade `test_fase12_ciclo.gd` (35 asserts):
`data/ciclo.json` (día de 720 s, hora inicial 9.0), `CicloDia.avanzar()`
proporcional a `duracion_dia_seg` con wrap 0–24, sol alto al mediodía
(`oscuridad()≈0`) y apagado a medianoche (`oscuridad()≈1`, la Luna releva),
señales `amanecer`/`anochecer` al cruzar 6h/18h, `fijar_hora` con wrap, y
`Antorcha` (factor 1.0 sin ciclo; 0.3 de día → 1.0 de noche con ciclo;
flicker dentro de banda).

La fase 12 (integración) añade `test_fase12_integracion.gd` (18 asserts):
cada spawn cae en una región, la aldea (0,0) está en Piedraceniza, la
escala es la real (36864), la demo fase12 referencia Terreno/CicloDia/
VigiaRegion/BannerRegion/Antorchas (sin enemigos fijos: los da
spawns.json), cámara con `far = 40000`, y el título abre `fase12_demo`.

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
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_quests.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_ui_layout.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_detalle_mision.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase10.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_respawn.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase11.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase12_regiones.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase12_terreno.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase12_spawns.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase12_ciclo.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase12_integracion.gd

# Smoke test de la escena demo de la fase 6 (300 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake res://scenes/demo/fase6_demo.tscn --quit-after 300

# Smoke test de la escena demo de la fase 7 (300 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake res://scenes/demo/fase7_demo.tscn --quit-after 300

# Smoke test de la escena demo de la fase 8 (300 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake res://scenes/demo/fase8_demo.tscn --quit-after 300

# Smoke test de la escena demo de la fase 9 (300 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake res://scenes/demo/fase9_demo.tscn --quit-after 300

# Smoke test de la pantalla de título (300 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake res://scenes/titulo/pantalla_titulo.tscn --quit-after 300

# Smoke test de la creación de personaje (300 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake res://scenes/creacion/creacion_personaje.tscn --quit-after 300

# Smoke test de la escena demo de la fase 11 (300 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake res://scenes/demo/fase11_demo.tscn --quit-after 300

# Smoke test de la escena demo de la fase 12 (mundo abierto: terreno 36.864 u,
# 1121 creeps, ciclo día/noche; 400 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake res://scenes/demo/fase12_demo.tscn --quit-after 400
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
