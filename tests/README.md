# Tests headless — Fases 1, 2, 3, 4, 5, 5.1, 6, 6.2, 7, 8, 8.1, 9, 9.1, 9.2, 9.3, 10, 11, 12, 12.1, 13, 14, 14.1, 15 y 15.1

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
`RegionDB` carga `data/regiones.json` (10 regiones del rework 2026, ids
únicos en orden, 10 campos, tintes "#rrggbb", bandas 1–5 … 45–70;
`cargar()` idempotente), cobertura total y sin solapes por muestreo (625
puntos del mapa, esquinas incluidas; intervalos semiabiertos, el borde
18432 incluido), Moon Town contiene al (0,0), `region_en` en bordes compartidos y fuera del mapa → {},
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
`data/spawns.json` trae 1121 entradas {arquetipo, x, z, nivel} del rework
2026 (distribuidos por las 10 regiones, nivel dentro de la banda de su
región; nivel→arquetipo: ≤30 goblin, 31–200 lobo, >200 ogro; zona segura
de 40 m en la aldea; los de Moon Town fuera del disco de la ciudad),
todas dentro del terreno y con arquetipos válidos;
`tools/generar_spawns_rework.py` es determinista.

La fase 12 (ciclo) añade `test_fase12_ciclo.gd` (35 asserts):
`data/ciclo.json` (día de 720 s, hora inicial 9.0), `CicloDia.avanzar()`
proporcional a `duracion_dia_seg` con wrap 0–24, sol alto al mediodía
(`oscuridad()≈0`) y apagado a medianoche (`oscuridad()≈1`, la Luna releva),
señales `amanecer`/`anochecer` al cruzar 6h/18h, `fijar_hora` con wrap, y
`Antorcha` (factor 1.0 sin ciclo; 0.3 de día → 1.0 de noche con ciclo;
flicker dentro de banda).

La fase 12 (integración) añade `test_fase12_integracion.gd` (18 asserts):
cada spawn cae en una región, la aldea (0,0) está en Moon Town, la
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
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_streaming.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase13_minimapa.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase13_brujula.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase14_ciudad.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase14_terreno.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase14_integracion.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_portales_temp.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase15_ciudades.gd
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase151_clic.gd

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

# Smoke test de la escena demo de la fase 14 (Moon Town: ciudad data-driven
# con 18 edificios, NPCs recolocados, minimapa STANDBY; 500 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake res://scenes/demo/fase14_demo.tscn --quit-after 500

# Smoke test del streaming fuera de la ciudad (teletransporta al jugador a
# (1019.4, -701), activa el streaming de mobs y corre 500 frames sin errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/smoke_fase14_streaming.gd

# Smoke test de las 8 ciudades secundarias (instancia la demo real, visita las
# 8 plazas con teletransporte, verifica 11 NPCs y streaming sano, 0 errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/smoke_fase15_ciudades.gd

# Smoke test del hotfix 15.1 (el jugador camina por clic y por WASD en la
# demo real, ≥ 400 frames, sin hundirse ni flotar, 0 errores):
~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/smoke_fase151_clic.gd
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

La fase 12.1 añade `test_streaming.gd` (26 asserts): `StreamingMobs` instancia solo los registros dentro de `radio_alta` y libera más allá de `radio_baja` (histéresis sin churn en la banda intermedia); la puerta de reaparición del `SpawnerMobs` veta reaparecer lejos (el pendiente se reprograma, no se pierde) y al acercarse el mob reaparece re-asociado a su registro; `Enemy.intervalo_cerebro(dist)` devuelve 1/3/6 por bandas; el tinte por arquetipo comparte material entre mobs del mismo color.

La fase 13 añade `test_fase13_minimapa.gd` (31 asserts): `mundo_a_mapa`/`mapa_a_mundo` son redondas (5 puntos + esquinas exactas), el fade baja a 0.35 tras 4 s quieto y vuelve a 1.0 al moverse, Alt+clic crea un ping de 5 s que expira solo (sin ordenar mover), clic normal llama `ordenar_mover_a` con el punto del mundo, `Terreno.color_en` no revienta sin bin y la etiqueta muestra la región actual (vacía fuera del mapa). Y `test_fase13_brujula.gd` (33 asserts): `offset_para` centra el N con yaw 0, pone E a la derecha y O a la izquierda, hace wrap en ±PI y es idéntico con +TAU; `offset_marcador` deja intacto lo visible y pega al borde lo de detrás; `resolver_objetivo` devuelve null sin misión, el goblin vivo más cercano para matar, el NPC de origen si la misión está lista, el NPC objetivo para hablar y el origen para recolectar (null si el NPC no existe); `QuestLog.cambiada` refresca el marcador (aceptar → mob, completar → NPC, entregar → apagado); `configurar` con todo null no revienta.

La fase 14 añade `test_fase14_ciudad.gd` (49 asserts): `CiudadLuna` construye la ciudad principal "Moon Town" reimaginada desde `data/ciudad_luna.json` (18 edificios data-driven: monumento con luna creciente dorada, Salón de Clases, forja de Bram, tienda de Sira, cuartel de Ilya, templo menor, 8 casas en 3 variantes procedurales, 4 puertas N/S/E/O); cada edificio con StaticBody3D en capa 1 y BoxShape3D; muralla con >= 40 tramos; `puntos_npc`/`npc_spawn()` para ilya/bram/sira (dentro del radio 800 y fuera de colisiones); `punto_aparicion_jugador()` en la plaza mirando al monumento y sobre el terreno; ninguna estructura supera 28 u; plaza y calles (40 u) libres de colisiones invisibles por muestreo; >= 35 antorchas reutilizando `Antorcha`.

La fase 14 (terreno del rework) añade `test_fase14_terreno.gd` (34 asserts): `data/terreno.bin` del rework 2026 (disco plano urbano de 40.0 u en (0,0) radio 800; biomas por región con tintes de `data/regiones.json`), `data/regiones.json` remapeado (región 1 = `moon_town` "Moon Town", 10 rects sin huecos ni solapes), `data/spawns.json` regenerado (1121 spawns, zona segura de 40 m en la ciudad, ninguno de Moon Town dentro del disco), y determinismo de `tools/generar_terreno_rework.py` / `tools/generar_spawns_rework.py`.

La fase 14 (integración) añade `test_fase14_integracion.gd` (36 asserts): `fase14_demo` hereda de `fase12_demo`, crea `CiudadLuna` con el terreno asignado ANTES del add_child, usa `punto_aparicion_jugador()`/`yaw_aparicion()`/`npc_spawn()` y conserva el flujo fase 12 (`super._ready()`); el título abre `fase14_demo.tscn`; `data/npcs.json` habla de "Moon Town" (sin "Piedraceniza", solo texto); el spawn del jugador cae sobre el terreno, en la región `moon_town` y fuera de colisiones; `npc_spawn()` devuelve los puntos data-driven de ilya/bram/sira; el minimapa sigue leyendo `Terreno.color_en` del terreno nuevo (STANDBY: sin pulir, solo no romper).

La fase 14.1 (TEMPORAL) añade `test_portales_temp.gd` (47 asserts): `data/portales_temp.json` trae >= 10 destinos con {id, nombre, x, z} (ids únicos, todos dentro del mundo, moon_town + 8 ciudades futuras + Montaña Oscura); `PortalTemporal` construye el visual al configurar (Label3D con el nombre del destino, billboard activado, etiqueta arriba; sin destino no construye); `jugador_distancia`/`portal_cercano` son puros (el más cercano dentro del radio gana, fuera no hay portal); `punto_destino(terreno)` cae en (x, z) sobre el terreno + margen; con ruta inexistente `cargar_destinos` devuelve vacío sin reventar (aislamiento: quitar los archivos temporales no rompe la demo).

La fase 15 añade `test_fase15_ciudades.gd` (282 asserts): los 8 `data/ciudad_{desert,fire,north,mystic,shadow,rage,fury,golden}.json` cargan (nombre, 16 edificios, monumento con su variante, 4 puertas, 1 NPC ambiental, `aparicion_jugador`, `_paleta`; ruta inexistente → false); cada ciudad se construye con `centro` asignado y `luces_reales = false` como la demo (emite `ciudad_lista`; 16 nodos raíz; muralla con ≥ 40 tramos y 4 puertas); monumento distintivo por ciudad verificado en su subárbol (oasis→agua, volcan→FalsaAntorcha en el cráter, pico_norte→nieve, cristal→cristal_arcano sin nieve ni cilindros de 4 lados, sombra→cilindros de 4 lados, trofeo_guerra→hueso, tormenta→2 anillos TorusMesh, sol_dorado→disco r=4.5 con `is_equal_approx` —las dimensiones de CylinderMesh son float32); colisiones: StaticBody3D en capa 1 con BoxShape3D en cada edificio y 0 OmniLight3D en las secundarias (≥ 40 FalsaAntorcha); `punto_aparicion_jugador()` en suelo válido (|y − altura_en| ≤ 1.0), en la plaza (≤ 60 u del centro) y fuera de colisiones; el NPC ambiental en su punto data-driven, dentro del disco r=700 y fuera de colisiones; ninguna estructura supera 28 u; plaza y calles (muestreo cada 20 u) libres de colisiones; los 10 destinos de `portales_temp.json` dentro del mundo y sobre terreno válido, y los 9 de ciudades coinciden con su `punto_aparicion_jugador()`; regresión Moon Town con el código generalizado (18 edificios, luna creciente CSG verbatim, 4 puertas, ≥ 35 Antorcha reales, sin `_paleta`). Además `test_fase91.gd` (64 asserts) se actualizó a los 11 NPCs de la demo (el "!" solo aparece en ilya/bram/sira; los 8 ambientales no tienen misión y no lo muestran) y `test_respawn.gd` corrigió su umbral flaky (la variación es ±RADIO_VARIACION por eje: el máximo real es √2×RADIO_VARIACION, no RADIO+0.05).

La fase 15.1 (hotfix clic izquierdo) añade `test_fase151_clic.gd` (12 asserts): el winding de `Terreno` estaba invertido (frontales hacia -Y) y los raycasts descendentes del clic atravesaban el suelo; ahora el rayo descendente GOLPEA (hit con colisionador Chunk a la altura del dato, en 2 puntos), el rayo ascendente desde debajo NO golpea (descarta el atajo `backface_collision=true`), las normales de `_caras_colision` apuntan a +Y, y la cadena del clic (el hit en la rama de suelo de `_clic_izquierdo`) fija `_tiene_destino`. Más `tests/smoke_fase151_clic.gd` (demo real: el jugador camina por clic y por WASD, ≥ 400 frames, sin hundirse ni flotar, 0 errores).
