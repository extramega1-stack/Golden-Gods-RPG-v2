# GOLDEN GODS RPG — REMAKE · Documento Maestro de Especificación

**Versión del documento:** 2.5 — Fase 9.2 (2026-09-21)
**Motor:** Godot 4.7.2 · **Idioma del juego:** español
**Alcance:** este documento es la especificación oficial del rewrite limpio.
Todo lo que se reimplemente debe salir de aquí; lo que no esté aquí no existe.

---

## 1. Propósito y estado

El 2026-09-21 Juan Diego ordenó reescribir Golden Gods RPG desde cero en un repo
nuevo: el proyecto anterior acumuló 26 versiones de parches (v10.1 → v10.26.0 en
4 días) y arrastraba deuda técnica. El diseño —todos los sistemas, decisiones,
lore y controles— ya está claro y vive en este documento. El código viejo es
desechable; el diseño no.

**Estado:** Fase 9 terminada — Detalle de misión + respawn de mobs:
- **Detalle de misión:** campo `lore` (string, 1–3 líneas, coherente con el
  canon Liberty) en cada misión de `data/quests.json` — *Goblins fuera*
  (Ilya: los titanes se agitan, goblins rondando Piedraceniza, la defensa
  de Liberty), *Colmillos para la forja* (Bram: lobos de los riscos, acero
  para la defensa), *Un mensaje urgente* (Sira: heridos de Piedraceniza,
  urgencia); `QuestDB.lore()` (mismo patrón que el resto de campos). En
  `PanelMisiones` (J) el nombre de cada misión en curso es un **botón**
  clicable (con pinta de etiqueta) que abre la sub-ventana
  `VentanaDetalleMision` (capa `UiLayers.DETALLE_MISION` = 28,
  PANEL_MISIONES + 1, rango 20–69): nombre, **lore** (autowrap, con aire),
  objetivos con progreso ("Goblins derrotados: 3/5" vía
  `QuestLog.progreso_texto`) y recompensas (oro, XP, items con cantidad
  vía ItemDB). Arranca oculta (lección 11) y no se come clics inactiva;
  cierra con ESC (consumido en `_input` antes que el panel), clic fuera
  (velo propio) o el botón "Cerrar". La UI solo lee.
- **Respawn de mobs:** `respawn_seg` por arquetipo en `data/enemies.json`
  (goblin 15 s, lobo 20 s, ogro 30 s); si falta, default
  `SpawnerMobs.RESPAWN_DEFAULT_SEG` = **20 s** (constante con nombre, no
  magia). Nuevo `scripts/mundo/spawner_mobs.gd` (`class_name SpawnerMobs
  extends Node`): `vigilar(e)` guarda el punto de origen y conecta la señal
  `murio`; al morir programa la reaparición tras `respawn_seg` en su punto
  de origen con pequeña variación aleatoria (`randf_range`, lección 12);
  al cumplirse el timer reinstancia el enemigo con el mismo arquetipo vía
  una factory `Callable(arquetipo_id, posicion) -> Enemy` inyectada por la
  demo (el spawner NO conoce rutas de escenas), auto-vigila al reaparecido
  y emite `reaparecido(nuevo)` para que la demo conecte sus señales
  (botín, muerte, lista del guardado). El timer es testeable headless con
  `avanzar(dt)` (tiempo simulado; `_process` lo usa con tiempo real). El
  respawn es **runtime**: el save guarda los enemigos vivos como siempre
  (los muertos pendientes de respawn simplemente no están en la lista; el
  timer no se persiste). Los NPCs nunca respawnean: el spawner solo acepta
  `Enemy` (los NPCs no mueren).
- Escena demo `scenes/demo/fase9_demo.tscn` (principal del proyecto):
  5 goblins + lobo + ogro; el jugador puede matar los 5 goblins de la
  misión aunque los mate a todos (respawnean). F9 guarda / F10 carga.
- `tests/test_detalle_mision.gd` (42 asserts) + `tests/test_respawn.gd`
  (34 asserts); regresión total 708 en verde.

**Fase 9.1 terminada — "!" de misión, segundo clic en NPC lejano y demo con 15 mobs:**
- **"!" dorado sobre NPCs con misión disponible** (pedido literal de Juan Diego):
  `NPC.fijar_marcador_mision(mostrar)` crea perezoso un `Label3D` ("!",
  billboard activado, dorado, flotando sobre la cabeza, oculto al inicio —
  lección 11); `NPC.marcador_visible()` para tests. La demo se suscribe a
  la señal `cambiada` del QuestLog y refresca los marcadores: al aceptar la
  misión el "!" desaparece (ya no está disponible); si hay otra misión
  disponible para ese NPC, sigue visible. **Solo** "misión disponible para
  aceptar": ni entregables ni activas muestran el marcador.
- **Segundo clic en NPC lejano = ir e interactuar** (como el ataque a mobs,
  sin violencia): el resolver `_resolver_clic_entidad` devuelve la nueva
  acción `AccionClic.INTERACTUAR` (el enum era SELECCIONAR/ATACAR/NADA);
  `_aplicar_clic` la ejecuta vía `_acercarse_a_npc`: si el NPC está dentro
  de `Player.RADIO_INTERACCION` (**3.0**, constante con nombre) habla
  directo (igual que E); si está lejos queda una interacción pendiente y
  el jugador camina hasta él —reusa el patrón "acercarse y actuar al
  llegar" del lanzamiento pendiente de skills— y al llegar emite
  `hablar_con` solo. Se cancela si el NPC muere, se deselecciona, el
  jugador toma el control manual (WASD) u ordena otro movimiento. Los NPCs
  nunca reciben daño: no se toca el combate (sin objetivo de ataque, sin
  `intencion_atacar`).
- **Spawner verificado en la demo real:** el reporte de "spawner nunca
  instanciado" era un falso positivo del grep (buscó el path del archivo;
  `fase9_demo.gd` instancia `SpawnerMobs` por su `class_name`, configura
  arquetipos, inyecta la factory `_crear_enemigo` y vigila cada enemigo).
  El repro headless (matar un goblin en `fase9_demo.tscn`, avanzar 16 s >
  `respawn_seg` 15 s) reaparece el mob: guardado como test de regresión en
  `tests/test_fase91.gd`. Además la demo ahora junta **sus propios**
  enemigos (`_mis_enemigos()`, descendientes del nodo demo) en vez del
  grupo global "enemigos" — con dos demos en el mismo árbol ya no se
  mezclan.
- **Demo con 15 mobs más lejos:** 5 goblins + 5 lobos + 5 ogros en
  `fase9_demo.tscn`, todos a ≥ 22 m del punto de aparición del jugador
  (fuera del aggro inicial: máx `radio_aggro` = 14 del lobo; la variación
  de respawn ±2 m no los mete en aggro). Los 15 quedan vigilados por el
  spawner (respawn incluido).
- `tests/test_fase91.gd` (45 asserts) + `test_clic.gd` actualizado a 38
  (el segundo clic en NPC ahora es INTERACTUAR); regresión total **755**
  en verde.

**Fase 9.2 terminada — E respeta el radio, banner de completada y "?" dorado:**
- **E respeta `RADIO_INTERACCION` (3.0):** `Player.interactuar()` ya no
  abre el diálogo de inmediato si el NPC seleccionado está lejos: activa
  la MISMA interacción pendiente que el segundo clic lejano (reusa
  `_acercarse_a_npc`, sin duplicar lógica) — el jugador camina hasta el
  NPC y al llegar habla solo. Dentro del radio abre el diálogo directo
  como antes. Nunca fija objetivo de ataque ni emite `intencion_atacar`
  (sin violencia). Para no crear recursión mutua (`interactuar()` →
  `_acercarse_a_npc()` → `interactuar()`…), el caso cercano emite
  `hablar_con` directo dentro de `_acercarse_a_npc`.
- **Banner prominente de misión completada:** cuando los objetivos de una
  misión se completan (transición activa→lista), la demo la detecta en la
  señal `QuestLog.cambiada` y muestra un banner dorado centrado:
  "¡Misión completada!" (30 px) + "<nombre>\nVuelve con <NPC de origen>"
  (20 px), borde dorado brillante, 4 s fijo + 0.8 s de fundido —
  claramente más grande/dorado/duradero que el toast normal de 2.5 s.
  API: `PanelMisiones.toast_completada(nombre, npc_nombre)` +
  `ultimo_banner` y `banner_visible()` (tests + UI futura). El banner
  vive en panel propio (no pelea con el toast normal) y arranca oculto
  (lección 11). Al cargar partida se suprimen los banners (el progreso
  restaurado no es "recién completado"; los estados se re-sincronizan
  igual para no duplicarlos después).
- **"?" dorado de entrega pendiente:** el marcador del NPC se generaliza
  a `fijar_marcador(tipo)` con `NPC.TipoMarcador {NINGUNO, DISPONIBLE,
  ENTREGAR}` ("!" = misión disponible, "?" = entrega pendiente; el mismo
  Label3D billboard dorado de la 9.1, reusado al cambiar de tipo sin
  duplicarlo). Los wrappers bool `fijar_marcador_mision` /
  `fijar_marcador_entrega` se conservan (los tests de la 9.1 siguen
  verdes) y se añade `marcador_tipo()`. **Prioridad: la "?" manda sobre
  el "!"** cuando un NPC tiene ambas (`_prioridad_marcador`, pura y
  testeable). Todo se refresca vía `QuestLog.cambiada` (al entregar, el
  estado pasa a "entregada" y la "?" desaparece).
- `tests/test_fase92.gd` (43 asserts): E lejos no abre diálogo pero deja
  pendiente y al llegar habla (sin atacar ni emitir intención); E cerca
  abre directo; banner visible al completar objetivos con nombre y NPC;
  "?" solo con entrega pendiente y se oculta al entregar; prioridad
  "?" > "!"; API del marcador generalizado. `test_npcs.gd` actualizado
  (`_t_interactuar` usa NPC dentro del radio). Regresión total **798**
  en verde.

**Fase 8.1 terminada — Hotfix layout responsivo del diálogo** (bug de
- **`data/quests.json`** + `QuestDB` (mismo patrón que NpcDB/TiendaDB): 3
  misiones coherentes con el canon Liberty — *Goblins fuera* (Ilya: matar 5
  goblins; 150 oro, 120 XP, 2 pociones de vida), *Colmillos para la forja*
  (Bram: recolectar 4 colmillos de lobo; 100 oro, 80 XP, espada de hierro)
  y *Un mensaje urgente* (Sira: llevar el mensaje a Ilya; 50 oro, 60 XP,
  2 pociones de maná). Tipos de objetivo: `matar` (arquetipo+cantidad),
  `recolectar` (item+cantidad), `hablar` (npc).
- **Lógica pura** `QuestLog` (RefCounted, SIN UI): estados
  disponible → activa → lista → entregada, señal `cambiada`;
  `aceptar()` ("ok"/"desconocida"/"no_disponible"), `registrar_muerte`,
  `sincronizar_recoleccion` (idempotente, min(inv, cantidad)),
  `registrar_dialogo`, `oferta_para_npc` (primero "disponible" de ese NPC,
  si no la primera "lista" para entregar), `entregar` (consume lo
  recolectado, da oro/XP/items por las APIs del Player; la UI nunca toca
  stats), `progreso_texto` ("Goblins derrotados: 3/5"), `to_dict`/
  `from_dict` versionados y tolerantes.
- **`VentanaDialogo`**: botón + descripción de misión (ocultos por
  defecto); `mostrar_mision(modo, nombre, descripcion)` ("disponible" →
  "¡Misión disponible: X!" + descripción; "entregar" → "Entregar misión:
  X"); la señal `mision_solicitada` NO cierra el diálogo (la demo
  acepta/entrega y refresca). Sin oferta no hay botón: fase 6/7 intactas.
- **`PanelMisiones`** (capa 27; arranca oculto —lección 11—): tecla **J**
  (nueva acción `abrir_misiones` del Input Map) alterna; ESC cierra.
  Misiones en curso con progreso "x/y" y "¡Lista para entregar!";
  completadas en su sección. **Toast** integrado (CanvasLayer hijo, capa
  15): mensajes 2.5 s con fundido ("Misión aceptada: X" / "Misión
  completada: +N oro, +M XP").
- **Guardado v5**: bloque `"misiones"` (estados + progreso; restaurado en
  sitio como Tienda); tolerante (las partidas v4 sin misiones cargan con el
  QuestLog vacío).
- Escena demo `scenes/demo/fase8_demo.tscn` (principal del proyecto):
  hablar con NPC registra el diálogo y refresca el botón de misión; las
  muertes avanzan "matar"; pickups y compras/ventas sincronizan
  "recolectar" (vender baja el progreso); F9 guarda / F10 carga con las
  misiones.

**Fase 8.1 terminada — Hotfix layout responsivo del diálogo** (bug de
Juan Diego en monitor 21:9: el panel se cortaba por el borde inferior y
la barra de skills tapaba el texto):
- `VentanaDialogo`: el panel va anclado abajo-centro con
  `grow_horizontal = GROW_DIRECTION_BOTH` +
  `grow_vertical = GROW_DIRECTION_BEGIN` (crece hacia ARRIBA) y su borde
  inferior queda en `-(ZONA_INFERIOR_RESERVADA + 16) = -116` px, por
  encima de la barra de skills. Se eliminó el hack
  `panel.position -= Vector2(260, 220)`; sin offsets mágicos ligados a la
  resolución.
- `UiLayers.ZONA_INFERIOR_RESERVADA = 100` (constante compartida): la
  barra de skills la usa en su `offset_top` y el diálogo como tope
  inferior + aire — consistentes por construcción.
- `tests/test_ui_layout.gd` (36 asserts): en 3440×1440 (Bram, texto de
  misión más largo) y 1920×1080 (Ilya) verifica panel dentro del
  viewport, panel sin solapar la barra, borde inferior del panel por
  encima de la barra, capas diálogo(81) > barra(12), todas las barras
  del HUD dentro del viewport y la descripción de la misión sin
  encimarse con los botones (el VBox `separation` les da aire).

Fase 7 terminada — Tienda / economía básica:
- **Tienda data-driven** (`data/tiendas.json` + `TiendaDB`, mismo patrón
  que NpcDB/ItemDB): 2 tiendas — Forja de Bram (armas/armaduras) y Botica
  de Sira (pociones/materiales; **nueva NPC** Alquimista Sira en
  `data/npcs.json`, diálogo coherente con el canon Liberty). Los NPCs
  vendedores declaran `"tienda_id"` (null/ausente = no vende).
- **Lógica pura** `Tienda` (RefCounted, SIN UI): `comprar()`
  ("ok"/"sin_oro"/"sin_stock"/"sin_espacio" —el oro se revierte si el
  inventario no recibe—/"tienda_desconocida"/"item_desconocido") y
  `vender()` ("ok"/"sin_stock"/"item_desconocido"/**"equipado"** —
  rechaza vender lo equipado en algún slot del Equipo—); señal `cambiada`.
  Stock **finito**: comprar lo agota. Precios data-driven: `precio_compra`
  explícito por tienda/item; `precio_venta` explícito, y si falta el
  default es `precio_compra / 2` entero.
- **UI solo lee** (`PanelTienda`, capa 82; arranca oculto —lección 11—):
  stock del vendedor (Comprar), mochila (Vender; los equipados muestran
  "equipado" sin botón), oro actual (refrescado con `oro_cambiado`); ESC
  cierra consumido antes que el Player. La `VentanaDialogo` muestra
  "Comerciar" solo con NPC vendedor (señal `comerciar_solicitado`; cierra
  el diálogo; sin tienda el comportamiento de fase 6 queda intacto).
  `Player.gastar_oro()` (única vía para restar oro; false sin tocar nada).
- **Guardado v4**: bloque `"tiendas"` (stock restante); tolerante (las
  partidas v3 sin tiendas cargan con stock completo).
- Escena demo `scenes/demo/fase7_demo.tscn` (principal del proyecto): el
  jugador arranca con 200 de oro; F9 guarda / F10 carga con la tienda.
Fase 6.2: modelo de clic estilo Flyff (pedido de Juan Diego).
Fase 6.1: botón de atacar retirado del HUD (la acción `atacar` por T o
segundo clic sigue igual).
Fase 6: NPCs e interacción básica:
- **Selección:** clic selecciona mob/NPC (anillo dorado 3D bajo sus
  pies, `IndicadorSeleccion`); clic en suelo vacío o ESC deselecciona. La
  selección muerta se limpia sola. **Fase 6.2 (modelo Flyff):** el primer
  clic en una entidad la selecciona (sin atacar ni mover); el SEGUNDO clic
  sobre la misma selección ataca solo si es un enemigo combatible vivo
  (dos clics rápidos o lentos valen igual); clic en otra entidad distinta
  cambia la selección sin atacar; segundo clic en el mismo NPC no hace
  nada (ni ataca ni mueve, la selección se mantiene).
- **Flash rojo al recibir daño:** estado `flash_tiempo` en `Entity`
  (testeable, decae en `_process`) + gancho visual `DamageFlash` (tiñe el
  "Cuerpo" sin mutar materiales compartidos).
- **Botón de atacar: RETIRADO del HUD (fase 6.1, pedido de Juan Diego por
  feedback de playtest — le molestaba en pantalla).** El script
  `scripts/ui/boton_atacar.gd` y su nodo en las demos se eliminaron; la
  acción `atacar` del Input Map (T por defecto o segundo clic) sigue
  funcionando igual vía `Player.solicitar_ataque` (foco > mob más cercano
  en rango ≤ 8 m). El rebind de tecla por clic derecho murió con el botón:
  vuelve con la barra de acciones arrastrable (feature planificada, §9.3).
  Capa UI 13 queda reservada.
- **Feature planificada (idea de Juan Diego, NO implementada):** barra de
  acciones arrastrable estilo Flyff — ver §9.3.
- **Skills con acercamiento:** skill dañina fuera de rango → lanzamiento
  pendiente: el jugador se acerca (reusa persecución) y la lanza al llegar;
  se cancela si el objetivo muere o deja de ser el foco. Curaciones al
  lanzador sin moverse.
- **REGLA DURA: los NPCs NO se pueden atacar** (`Entity.combatible = false`
  en `NPC`; `true` en jugador/enemigos). `take_damage` los ignora por completo
  (sin vida, sin señales, sin flash); el Player rechaza fijarlos como objetivo
  (segundo clic, tecla) y `SkillSystem` rechaza skills dañinas sobre ellos
  (motivo `"no_combatible"`). Los NPCs SÍ se pueden seleccionar.
  Datos: `data/npcs.json` (Mariscala Ilya Voss, Herrero Bram).
- Nuevas acciones Input Map: `atacar` (T), `cancelar_seleccion` (ESC).
- Escena demo `scenes/demo/fase5_1_demo.tscn` (principal del proyecto).
- **Fase 6 — NPCs e interacción básica:** NPCs data-driven completos
  (`scripts/npc/npc_db.gd`, mismo patrón que ItemDB/SkillDB; `data/npcs.json`
  con `nombre`, `rol` y `dialogo` por NPC); tecla **E** (nueva acción
  `interactuar` del Input Map) con un NPC vivo seleccionado abre la
  **VentanaDialogo** (`scripts/ui/ventana_dialogo.gd`, capa 81: nombre, rol y
  líneas; avance con E/clic/"Continuar", cierre con "Cerrar"/ESC; arranca
  oculta y sin comerse clics — lección 11); el Player emite la intención
  `hablar_con` y la UI solo lee (nunca escribe stats); interactuar sin
  selección no hace nada. **Guardado v3** (`user://partida.json`): incluye
  los NPCs (id + posición; no mueren, así que no se guarda vida) y es
  tolerante (las partidas v2 sin NPCs cargan igual). **REGLA DURA intacta:**
  los NPCs siguen no atacables (solo hablar y seleccionar).
- Escena demo `scenes/demo/fase6_demo.tscn` (principal del proyecto).
La reimplementación sigue en la Fase 9+ (§11).

---

## 2. Repos y legado

| Rol | URL / ruta |
|---|---|
| Proyecto nuevo (este) | `https://github.com/extramega1-stack/Golden-Gods-RPG-v2` (privado, publicado 2026-09-21) |
| Clon local | `~/workspace/godot-rpg-remake` |
| Proyecto legado (congelado en v10.26.0, **no tocar**) | `https://github.com/extramega1-stack/Golden-Gods-RPG` · local `~/workspace/godot-rpg` |

---

## 3. Canon narrativo (resumen de `BIBLIA_NARRATIVA.md` del legado)

**Título:** GOLDEN GODS: LA ÚLTIMA GUERRA · **Final canónico: LIBERTY.**

1. **Premisa:** eres el último descendiente del héroe que mató a un dios. Los
   titanes regresan por las grietas del Tártaro; los olímpicos moribundos quieren
   usarte como arma; los mortales de Liberty ofrecen la tercera vía: acabar la
   guerra para siempre.
2. **Facciones (3 + culto):** Olímpicos (Zeus moribundo, Atenea; te usan como arma)
   · Titanes (Chronos, Océano, Atlas, Hécate, Tánatos, Némesis, Prometeo el ambiguo)
   · **Liberty** (mortales libres, Mariscala Ilya Voss) · Culto del Velo (antagonistas).
3. **El Verdugo de Titanes:** 6 fragmentos + escama "chatis" de Ladón + forja de
   Hefesto. Doble uso: **espada** (matar a Chronos) o **Sello** (encerrar a dioses
   y titanes fuera del mundo mortal, al precio de que la magia abandone el mundo).
4. **Dos sendas** (se define en el Acto II, se consolida en el IV; NG+ muestra la
   otra mitad): **El Arma** (senda de los Dioses, final amargo) · **Liberty**
   (canónica: el Sello; el Heredero cuelga el Verdugo inerte en Piedraceniza).
   Finales secretos fuera de las sendas: Era Titánica y El Relevo.
5. **6 regiones** (cada una: fragmento + poder + jefe): Ceniza y Forja · El Abismo
   Lloroso · La Corona Quebrada · Tierras del Trueno · El Velo (exige sacrificar un
   NPC aliado) · Las Tierras Francas (hogar de Liberty).
6. **5 actos:** I La Grieta (tutorial, caída de Piedraceniza) · II Los Seis
   Fragmentos · III La Forja · IV El Descenso (la Arena es la puerta al Tártaro)
   · V La Última Guerra (Chronos vulnerable; decisión: espada o sello).
7. **Reglas duras del canon:** Chronos es presencia *invulnerable* hasta el Acto V.
   Nada online/competitivo. Estética gótica L2/MU.

---

## 4. Dirección del juego

- **RPG local single-player**, mundo abierto estilo **Lineage II / MU**. Nada
  online, nada competitivo, nada de rankings contra otros jugadores. Trofeos,
  récords y marcas personales: **locales**.
- **Cámara:** tercera persona baja detrás del héroe (estilo L2/MU). Sin paneo libre.
- **Mundo:** 36.864 × 36.864 unidades, **sin reescalar** (las fórmulas del minimapa
  dependen de ese tamaño).
- **Clases jugables (4):** guerrero, arquero, mago, daguero.
- **Dirección visual UI:** metal oscuro acerado (L2) + dorado viejo y rojo sangre (MU).
- **Modelos 3D:** el mapa del legado quedó limpio (modelos retirados en v10.18.0;
  respaldo en `~/workspace/backups/golden-gods-models-v10.17.8/`). El remake usa
  modelos procedurales de respaldo hasta que Juan Diego autorice integrar los
  85 GLB de Meshy. **Nunca copiar assets de Blizzard**: sustitutos originales,
  licencias permitidas.
- **Combate:** se reimplementa tal cual el legado ("decente", decisión de
  Juan Diego) — **no se rediseña** en el rewrite.

---

## 5. Tabla de controles (heredada del legado, con conflictos resueltos)

### 5.1 Mouse (esquema v10.19, vigente)

| Entrada | Acción |
|---|---|
| Clic izquierdo (suelo / nada) | Mover al punto (suelo) / deseleccionar |
| Clic izquierdo (entidad) | Primer clic: seleccionar (mob o NPC; sin atacar ni mover) · clic en otra entidad: cambia la selección |
| Segundo clic en el MISMO enemigo seleccionado | Atacar (modelo Flyff, fase 6.2; rápido o lento vale igual) |
| Segundo clic en el mismo NPC seleccionado | Habla: si está cerca abre el diálogo directo; si está lejos el jugador camina hasta él y al llegar interactúa solo (fase 9.1; sin violencia) |
| Botón derecho (mantener) | Cámara: giro infinito (captura inmediata al presionar) |
| Botón central (mantener) | Cámara: drag alternativo con amortiguamiento |
| Rueda | Zoom (máximo 650, decisión de Juan Diego) |
| Minimapa: clic/arrastrar izq. | Mover la cámara |
| Minimapa: Alt + clic | Ping en el mapa |

### 5.2 Teclado

| Tecla | Acción | Tecla | Acción |
|---|---|---|---|
| WASD | Moverse (relativo a cámara) | Shift+A | Alquimia |
| Q / E | Cámara yaw/pitch (amortiguado) | B | Forja de mejora |
| 1–8 | Hotbar habilidades | Shift+B | Tablón de recompensas |
| Z / X | Pociones vida / maná | C | Panel de equipo |
| TAB | Tutorial (avanzar paso) | Ctrl+C | Censo de criaturas |
| ESC | Cerrar panel superior / saltear cinemática | Shift+C | Colecciones |
| INSERT | Diagnóstico de cámara | Shift+D | Mejoras permanentes |
| E | **Interactuar contextual** (ver §5.3) | Shift+E | Joyas MU |
| Alt+E | Talentos | F | Banco personal |
| Shift+F | Montura | G | Pesca |
| Shift+G | Expediciones | Shift+H | Perfiles de equipo |
| Alt+H | Narrador (tono/intensidad) | I | Títulos |
| Shift+I | Cocina | J | **Misiones** (rewrite, fase 8) |
| Alt+J | Visiones del otro sendero | K | Gemas |
| Shift+K | Soulshots/Spiritshots | L | Stats de sesión |
| Shift+L | Calendario | M | Viaje rápido |
| Shift+M | Facciones | N | Arena (oleadas) |
| Shift+N | Aceites de arma | O | Sets de equipo |
| Ctrl+O | Trofeos locales | P | Mascota |
| Shift+P | Pausa real | Ctrl+P | Prestigio / NG+ |
| Alt+Q | Tablero de Destino | R | Dificultad |
| Shift+R | Entrenamiento (oro→XP) | Alt+R | Runas |
| Shift+S | Volumen | T | Habilidades |
| Shift+T | Arma artefacto | Ctrl+T | Caza de tesoros |
| Alt+T | Profesiones | U | Diarias |
| V | Herrería (crafteo) | Shift+V | Códice |
| Shift+W | Desafío semanal | Shift+X | Caja misteriosa |
| Shift+Y | Juguetes | Shift+Z | Apuestas arena |
| F1 | Crónica / lore | F2 | Comandos |
| F3 | Campaña | F4 | Hoja de personaje |
| F5 | Filtro de botín | F6 | Hardcore (doble puls.) |
| F7 | Temporizadores | F9 | **Guardar partida** (rewrite) |
| F10 | **Cargar partida** (rewrite) | F11 | Atlas del mundo |
| F12 | Modo foto | Ctrl+F8 | Forzar ruleta |

### 5.3 Conflictos del legado — decisiones del rewrite

| Conflicto | Decisión |
|---|---|
| Shift+B (tablón vs regiones) | **Shift+B = Tablón** · Regiones → **Alt+B** |
| Q (boss rush vs recolectar) | **E = interactuar contextual**: el interactuable más cercano (nodo de recolección, santuario, NPC). Boss Rush conserva **Q** como tecla de su panel |
| F12 (modo foto vs safari) | **F12 = modo foto**; el safari detecta la foto pasivamente (sin tecla propia) |
| P (patrulla legacy vs mascota) | **P = mascota**; el comando patrulla legacy se elimina |
| Alt+H (narrador sin binding) | **Alt+H = panel del narrador** (oficial desde el día 1) |
| F8 | Libre (el sistema viejo de talentos quedó retirado) |
| F9 (registro misiones HUD) / F10 (reasignar atributos) | **F9 = guardar partida** · **F10 = cargar partida** (rewrite, fase 4): el save/load temprano necesita atajos desde el día 1. Registro de misiones y reasignación de atributos recuperan sus teclas en sus fases (§11) |
| T (habilidades, plan futuro del legado) | **T = atacar** (rewrite, fase 5.1): intención de ataque al foco; reasignable por el jugador (clic derecho en el botón) |
| ESC (cerrar panel superior) | **ESC = deseleccionar** (rewrite, fase 5.1); cuando haya paneles modales, ellos consumirán ESC antes (pila de paneles, fase futura) |

> **Política de input (§9.3):** en el legado las 76 teclas estaban hardcodeadas por
> keycode en cada script. En el remake **todo atajo vive en el Input Map del
> proyecto** (`project.godot` → `[input]`) con acciones nombradas (`mover`,
> `abrir_equipo`, …). Ningún script compara `keycode` directamente.

---

## 6. Catálogo de sistemas del legado (por dominio)

El legado tenía **166 scripts**. Catálogo agrupado por dominio para
reimplementar; **no es orden de ejecución**. El orden oficial es el de §11
(directriz de Juan Diego, 2026-09-21: fórmulas → entidad → jugador/cámara →
enemigo+loot+save → HUD → sistemas por señales).
Cada entrega termina con verificación headless + tests en verde +
**playtest de Juan Diego** antes de pasar a la siguiente (método vigente:
una parte a la vez, pulirla, luego la otra).

### Dominio 1 — Núcleo técnico
Input Map completo (§5) · guardado versionado (`user://savegame.json` con
migraciones) · pila global de paneles (ESC) · skin UI central (L2+MU) · helpers de
popups/animaciones · audio (volúmenes Master/Música/SFX) · registro de sistemas.

### Dominio 2 — Jugador, cámara, HUD
Héroe (clic: mover/seleccionar/hablar; segundo clic en el mismo enemigo
ataca, WASD relativo a cámara,
pegado al terreno) · cámara L2/MU (drag botón derecho con captura = giro infinito,
Q/E con amortiguamiento, zoom máx 650, oclusión por bisección, overlay INSERT) ·
HUD (retrato, HP/MP/XP suavizadas + fantasma de daño L2, hotbar 1–8, pociones Z/X,
recursos, feed animado, velos modales) · minimapa WC3 (200 px, fade en reposo,
pings Alt+clic, recorte al rectángulo) · creación de personaje · pantalla de título.

### Dominio 3 — Mundo
Terreno por chunks con LOD (36.864 u) · agua · 1191 spawns de criaturas
(`data/creatures.json`) con arquetipos y tinte por nivel · doodads (MultiMesh) ·
fábricas procedurales originales (criaturas, assets) · vida ambiental (día/noche,
partículas por zona/bioma, fauna, pájaros, critters, antorchas, aldeanos con
rutinas, POIs, cordillera) · 10 regiones con bandas de nivel · atlas F11 ·
brújula · viaje rápido · clima · audio ambiental por zona.

### Dominio 4 — Combate y clases (reimplementación fiel, sin rediseño)
4 clases (tabla única) · stats str/agi/dex/int · maná + 8 habilidades con hotbar ·
proyectiles · pools de FX (impactos, ráfagas, cero allocs) · game feel (hit-stop,
telegrafía de jefes, barras de jefe estilo GoW, combo, DPS) · 7 jefes griegos +
24 súbditos con habilidades · élites con afijos · jefe mundial cíclico ·
dificultad · modo hardcore · Verdugo de Titanes (6 fragmentos + poderes en hotbar)
· Voluntad Libre.

### Dominio 5 — Equipo y mejora (paper doll primero)
16 slots (arma, arma izq., escudo, casco, armadura, guantes, botas, capa, alas,
amuleto, anillos ×2, aretes ×2, collar, mascota) con restricciones por clase
(guerrero=escudo+doble, dagero=solo doble, arquero/mago=solo escudo) · loot estilo
Diablo/WoW/MU con tooltips ▲/▼ · **paper doll**: 11 anclajes en el héroe, tabla
data-driven slot→{anclaje, mesh_path, offset, escala, tinte}, `mesh_path` listo
para los futuros GLB de Meshy, visuales procedurales por rareza · runas (6,
Alt+R, máx 3 en arma) · joyas MU (Shift+E) · gemas (K) · forja +1..+9 con
**encantamiento con riesgo** (seguro hasta +6, 90%→25% hasta +15; fallo +7..+10
baja 1, +11..+15 quiebra a +0, el arma nunca se destruye) · **máquina del caos**
(Goblin, % visible) · **transfiguración** (apariencia sin cambiar stats) ·
**alas por tiers** (Gorrión→Ángel→Titán, prioridad visual sobre capa) ·
**reliquias de dioses caídos** (4 sets ×3, bonus 2/4) · sets de equipo (O) ·
perfiles de equipo (Shift+H) · filtro de botín (F5) · lista de deseos.

### Dominio 6 — Progresión
Sistema Jobs (5 jobs por clase) + misiones de cambio + Renacimiento · prestigio/NG+
(Ctrl+P) con Ascensión y Eco del Portador · finales secretos NG+ · **talentos**
(Alt+E: 3 ramas × 5 nodos × 3 rangos por clase, 1 pto/nivel desde nv 10) ·
**subclases** (nv 40, misión "El Segundo Camino", 3 pasivas) · **profesiones**
(Alt+T: Herboristería + Minería, nodos por bioma, 11 recetas) + alquimia (Shift+A)
+ cocina (Shift+I) + herrería (V) · **tablero de destino** (Alt+Q: 21 nodos,
3 ramas) · **mascotas evolutivas** (Cría→Joven→Adulto→Épica) · monturas (Shift+F) ·
soulshots (Shift+K) · aceites (Shift+N) · bendición diaria · oráculo · descanso
estilo WoW · entrenamiento (oro→XP) · reasignación de atributos (F10) · mejoras
permanentes (Shift+D) · títulos (I) · auras cosméticas · juguetes (Shift+Y).

### Dominio 7 — Contenido narrativo y mundo vivo
Campaña (38 misiones, F3) + capítulo II + epílogo · **misiones 2.0** (tracker WoW,
!/?, 5 tipos, cadena "El Bastión del Alba") · diarias (U) · semanales (Shift+W) ·
caza de tesoros (Ctrl+T) · tablón (Shift+B) · expediciones (Shift+G) ·
**santuarios del Verdugo** (10 murales, E, → Códice) · **compañero narrador**
(estilo Mimir, 35 líneas, Alt+H) · **favores de espíritus** ("Fantasmas del Alba",
6 misiones) · **visiones del otro sendero** (Alt+J) · **8 heraldos ocultos**
(endgame, ritual, trofeo local) · **set pieces colosales** (solo visuales) ·
**refugio del Verdugo** (Piedraceniza, 4 módulos, sala de trofeos) · facciones
(Shift+M) + reputación · códice/bestiario (Shift+V) · crónica (F1, 44 entradas) ·
diario (J) · hitos · **arena** (contrarreloj + oleadas N + horda + apuestas
Shift+Z + boss rush Q) · **eventos PvE cada 2 h** (pase, récord local) ·
calendario (Shift+L) · favores/mascota/pesca (G) · 12 **trofeos 100% locales**
(Ctrl+O) + salón de trofeos 3D + récords (salón de la fama) · némesis personal ·
ruleta diaria · login diario · motd · cinemáticas salteables · tutorial de 8 pasos ·
modo foto (F12) + safari · sellos rúnicos (**aparcados** por Juan Diego) ·
**ira del Verdugo** (**aparcada**: toca combate).

### Dominio 8 — Economía y conveniencia
Tiendas y NPCs (diálogos, curandero, fusión, herrería) · banco (F) · mercado negro
(Shift+N→ **reubicar**: Shift+N hoy es aceites; mercado negro pasa a **Alt+N**) ·
caja misteriosa (Shift+X) · lápida con regreso · temporadas · comandos (F2) ·
temporizadores (F7) · hoja de personaje (F4) · créditos · respaldo automático
de partida.

> Nota: el mercado negro del legado usaba Shift+N, en conflicto con los aceites de
> arma (también Shift+N). Decisión: **Shift+N = aceites**, **Alt+N = mercado negro**.

---

## 7. Reglas duras

1. **Single-player local.** Nada online, nada competitivo, nada de rankings entre
   jugadores. Trofeos/récords/marcas: locales.
2. **El combate no se rediseña** (Fase 4 = reimplementación fiel del legado).
3. **Mundo sin reescalar:** 36.864 u; fórmulas del minimapa intactas.
4. **Canon narrativo** (§3) inviolable: final Liberty, dos sendas, Chronos
   invulnerable hasta el Acto V.
5. **Sin assets de Blizzard**: originales o licencias permitidas (CC0/CC-BY).
   Los 85 GLB de Meshy **no** se integran hasta que Juan Diego lo autorice.
6. **Una parte a la vez:** cada fase se pule hasta feel AAA y la valida Juan Diego
   en playtest antes de pasar a la siguiente. El headless solo valida parseo.
7. **Botón ESPADA del Verdugo: rojo sangre.** (Decisión estética de Juan Diego.)
8. **Empaquetado:** siempre `zip -r` del sistema (nunca zipfile de Python);
   nunca reutilizar nombres de ZIP.
9. **Verificación:** `~/workspace/tools/godot/godot --check-only` sobre todos los
   scripts tras cada tanda, antes de empaquetar. 0 fallos reales.
10. **Evidencia por entrega:** commit + tag + release + árbol limpio + SHA-256.
11. **La UI solo lee el StatBlock, nunca lo escribe.** Los sistemas se hablan
    por señales con API chica; nada cuelga del código de otro sistema
    (directriz de Juan Diego, 2026-09-21).

---

## 8. Estándar GDScript obligatorio (las 12 lecciones, desde el día 1)

1. **Veneno Variant:** `var x = expr` es Variant y contamina todo `var y := ...`
   que la use. Preferir `var x: Tipo = ...` con tipo conocido.
2. **`Object.get()` de 1 argumento:** `obj.get("prop", default)` con receptor
   tipado es parse error. Usar helper `_sget(obj, prop, default)`.
3. **Warnings como errores:** nunca `:=` sobre lo que retorne Variant
   (`JSON.parse_string`, `.get()` de 1 arg, subíndice en Array/Dictionary sin
   tipar). Usar `=` o `as`. Sin `CONFUSABLE_LOCAL_DECLARATION`.
4. **Consts Array sin tipar:** `const FOO := [...]` → `FOO[i]` es Variant.
   Declarar `const FOO: Array[String] = [...]` (vale para int, etc.).
5. **APIs alucinadas:** verificar cada firma en la doc de Godot 4.7
   (ej. `Time.get_date_string_from_system()`, no `get_date_string()`).
6. **`_player: Node`:** acceso 3D en receptor tipado como Node es unsafe y rompe
   `:=`. Tipar como Node3D o usar `var p: Vector3 = ...`.
7. **Barrido sintáctico, no álgebra de tipos casera** para detectar Variant.
8. **Builtins sin sufijo retornan Variant:** `abs/clamp/lerp/min/max/pow/ceil/…`
   → usar `absi/clampf/maxi/…` o `=` en vez de `:=`.
9. **Sin métodos de instancia sobre clases con class_name** (`LootData.has_method()`
   es parse error → `LootData.new().has_method()`); **sin helpers `_get/_set`**
   (colisionan con los virtuales de Object).
10. **Runtime visto en playtest:** `Gradient.remove_point()` exige ≥1 punto;
    `ItemList.allow_multiselect` no existe (usar `select_mode`).
11. **Velos modales:** todo ColorRect fullscreen arranca `visible=false`.
12. **Firmas dudosas:** barrer archivos nuevos contra APIs poco usadas antes de
    empaquetar (`randf_range`, no `randf(a,b)`; `find_child` no filtra por tipo;
    `SurfaceTool.append_from` exige 3 args; `process_mode` con enum, no literal).

---

## 9. Política de arquitectura (nueva, corrige el legado)

### 9.1 Organización de nodos
- `Main` (Node3D) → hijos por dominio: `World`, `Player`, `CameraRig`, `HUD`,
  `Systems` (nodo contenedor; cada sistema es un hijo con script propio).
- Cada sistema: **un script, un nodo, una responsabilidad**. Se registra en el
  grupo `gg_system` y expone `system_id: StringName`. Descubrimiento por grupo,
  nunca por rutas hardcodeadas de hermanos.
- UI: cada sistema construye su UI en runtime en **un CanvasLayer propio**.

### 9.2 Capas UI (fuente única de verdad)
Rangos reservados — ningún sistema elige su capa a ojo:

| Rango | Uso |
|---|---|
| 10–19 | HUD y elementos persistentes (barras, minimapa, feed, brújula) |
| 20–69 | Paneles de sistemas (inventario, equipo, talentos, mapa…) |
| 70–79 | Sistemas de progresión/mundo (prestigio, destino, refugio) |
| 80–89 | Tiendas, diálogos, cinemáticas |
| 90–99 | Modales críticos (confirmaciones de riesgo, pausa, título) |

Constantes en `scripts/core/ui_layers.gd` (Fase 1). El caos del legado
(3 sistemas eligiendo la capa 87) no se repite.

### 9.3 Input
Todo atajo en el **Input Map** (`[input]` en `project.godot`), acciones con nombre
en español claro (`abrir_equipo`, `talentos`, `pausa`…). Prohibido `keycode == KEY_X`
en scripts de sistemas. Excepción: la cámara puede leer estado físico de WASD vía
`Input.is_physical_key_pressed` solo para movimiento.

### 9.4 Datos y guardado
- `user://savegame.json` **versionado** (`"version": N`); cada sistema migra su
  bloque o lo descarta con aviso. Respaldo `.bak` automático.
- Tablas de datos (clases, loot, recetas, talentos) como **consts tipadas** en
  scripts `*_data.gd` separados de la lógica.

### 9.5 Rendimiento
Compartir mallas/materiales; pools para FX; cero allocs por frame en sistemas
calientes; `visible=false` en vez de crear/destruir nodos.

---

## 10. Datos y assets (a portar del legado en su fase)

- `data/creatures.json` — 1191 spawns (Fase 3).
- Terreno: `terrain_*.bin/png/json`, `zones.png`, `path_grid.bin`, `water_data.bin` (Fase 3).
- Audio: `data/combat/*.wav`, pasos, viento, agua, UI (Fase 1–3).
- UI: `data/ui/*`, cursores, `minimap.png` (Fase 2).
- Doodads: `data/doodads.json` + `creep_archetypes.ini` + `units.json` (Fase 3).
- Shaders: `terrain_modern.gdshader`, `vida/water_alive.gdshader` (Fase 3).
- Modelos: `~/workspace/backups/golden-gods-models-v10.17.8/` (respaldo 536 archivos;
  restaurar solo con autorización) · 85 GLB de Meshy en
  `~/workspace/your_files/golden-gods-modelos-3d-v1.zip` (**no integrar** hasta que
  Juan Diego lo autorice).

---

## 11. Plan de fases (orden oficial de Juan Diego, 2026-09-21)

Principio: **todo cuelga de los datos, nada cuelga del código de otro sistema.**
Si stats, fórmulas y entidades están bien diseñados, los sistemas de arriba son
"contenido con botones". Cada fase termina con algo jugable/testeable antes de
pasar a la siguiente; el bug se atrapa en la capa donde nació, no tres capas arriba.

| Fase | Contenido | Entregable |
|---|---|---|
| 0 | Repo + este documento + esqueleto | La escena abre sin errores |
| 1 | **Datos puros**: `StatBlock` + fórmulas puras + tests headless | Tests en verde (~2 s) |
| 2 | **Entidad base**: `Entity` con StatBlock, vida, `take_damage()`, `die()`, `gain_xp()`; jugador, creep, jefe y NPC son Entity | Un solo camino para el daño |
| 3 | **Jugador + cámara**: el input genera *intenciones*, no ejecuta acciones; game feel antes de que haya contenido que lo distraiga | Caminar con cámara L2/MU que se siente bien |
| 4 | **Enemigo mínimo + loot + save/load temprano** ✅: IA de 4 estados (quieto → persigue → ataca → muere), tabla de drops, datos versionados, HUD mínimo de solo lectura | Loop jugable: moverse → pegar → lootear → subir de nivel → guardar (F9) / cargar (F10) |
| 5 | **Inventario, equipo y skills** ✅: `data/items.json` (10 items) y `data/skills.json` (5 skills); `Inventario` (apilar, capacidad), `Equipo` (slots arma/armadura, mods por fuente sin tocar stats base), `SkillSystem` (maná/cooldown/rango, teclas 1–5); loot → inventario; HUD con barra de skills + paneles I/C (solo lectura); save/load v2 tolerante | Loop jugable: recoger → equipar → lanzar skills → guardar (F9) / cargar (F10) |
| 5.1 | **Pulido de selección y combate** ✅: indicador de selección 3D (clic simple selecciona mob/NPC; suelo vacío o ESC deselecciona) · flash rojo al recibir daño (estado en `Entity` + `DamageFlash`) · botón de atacar arrastrable con tecla reasignable (acción `atacar`, defecto T; persiste en `user://`) · skills dañinas con acercamiento automático (lanzamiento pendiente, cancelable) · **REGLA DURA: NPCs no atacables** (`combatible = false`; `data/npcs.json`) | Loop jugable: seleccionar → atacar con botón/tecla → skills que se acercan solas → NPCs que se seleccionan pero no se pueden dañar |
| 6 | **NPCs e interacción básica** ✅: NPCs data-driven completos (`NpcDB` + `nombre`/`rol`/`dialogo` en `data/npcs.json`) · E abre la VentanaDialogo con el NPC seleccionado (nombre, rol, líneas; E/clic/Continuar avanza, Cerrar/ESC cierra; UI solo lee) · save v3 tolerante con NPCs (id + posición) | Loop jugable: seleccionar NPC → hablar con E → guardar (F9) / cargar (F10) con NPCs restaurados |
| 6.2 | **Hotfix modelo de clic Flyff** ✅: un solo handler `_clic_izquierdo` (se elimina la rama `double_click` del motor) — primer clic selecciona mob/NPC (sin atacar ni mover), segundo clic sobre el mismo enemigo combatible ataca (rápido o lento valen igual), clic en otro mob cambia la selección sin atacar, segundo clic en NPC no hace nada, suelo/nada mueve y deselecciona · decisión pura `_resolver_clic_entidad` (enum `AccionClic`) testeable sin cámara + `_aplicar_clic` + `_orden_mover_punto` · `tests/test_clic.gd` (36 asserts) | Loop jugable: clic → seleccionar → segundo clic → atacar (como Flyff) |
| 7 | **Tienda / economía básica** ✅: `data/tiendas.json` + `TiendaDB` (data-driven, mismo patrón que NpcDB/ItemDB; NPCs vendedores con `"tienda_id"` en `data/npcs.json`; nuevo NPC Alquimista Sira, diálogo coherente con el canon Liberty) · `Tienda` (RefCounted, lógica pura SIN UI: `comprar`/`vender` con códigos de resultado, stock finito que se agota, `gastar_oro` como única vía para restar oro; vender rechaza lo equipado con "equipado"; precios data-driven —`precio_compra` explícito, `precio_venta` explícito o default `precio_compra/2`—) · `PanelTienda` (capa 82; arranca oculto, UI solo lee, stock/mochila/oro, ESC cierra) · "Comerciar" en la `VentanaDialogo` solo con NPC vendedor (señal `comerciar_solicitado`) · **save v4** tolerante (bloque `"tiendas"`; las v3 cargan con stock completo) | Loop jugable: hablar con Bram/Sira → comerciar → comprar/vender con oro → agotar stock → guardar (F9) / cargar (F10) con stock restaurado |
| 8 | **Misiones** ✅: `data/quests.json` + `QuestDB` (data-driven, mismo patrón que NpcDB/TiendaDB; 3 misiones del canon Liberty: Goblins fuera / Colmillos para la forja / Un mensaje urgente) · `QuestLog` (RefCounted, lógica pura SIN UI: estados disponible→activa→lista→entregada, señal `cambiada`; aceptar con códigos, registrar_muerte, sincronizar_recoleccion idempotente, registrar_dialogo, oferta_para_npc, entregar —consume lo recolectado y da oro/XP/items por las APIs del Player—, progreso_texto, to_dict/from_dict versionados) · botón de misión en la `VentanaDialogo` (`mostrar_mision`; la señal `mision_solicitada` no cierra el diálogo; sin oferta no hay botón —fase 6/7 intactas) · `PanelMisiones` (capa 27; arranca oculto; J alterna con la acción `abrir_misiones`, ESC cierra; en curso con progreso "x/y" y "¡Lista para entregar!", completadas aparte; toast integrado 2.5 s) · **save v5** tolerante (bloque `"misiones"` restaurado en sitio; las v4 cargan con QuestLog vacío) | Loop jugable: hablar con Ilya → aceptar → matar 5 goblins → entregar (+150 oro, +120 XP) · llevar colmillos a Bram → espada de hierro · mensaje de Sira a Ilya · panel J con progreso en vivo · guardar (F9) / cargar (F10) con misiones restauradas |
| 8.1 | **Hotfix layout responsivo del diálogo** ✅: `VentanaDialogo` anclado abajo-centro con `grow_vertical = GROW_DIRECTION_BEGIN` (el panel crece hacia arriba) + borde inferior en `-(ZONA_INFERIOR_RESERVADA + 16) = -116` px (por encima de la barra de skills); `UiLayers.ZONA_INFERIOR_RESERVADA = 100` compartida con `barra_skills.gd`; se eliminó el hack `panel.position -= Vector2(260, 220)` · `tests/test_ui_layout.gd` (36 asserts: panel dentro del viewport, sin solapar la barra, capas 81 > 12, HUD dentro del viewport, en 3440×1440 y 1920×1080) | Bug de Juan Diego en 21:9: el panel se cortaba por abajo y la barra tapaba el texto — ahora el diálogo completo se ve en 16:9 y 21:9 |
| 9 | **Detalle de misión + respawn de mobs** ✅: campo `lore` (canon Liberty) en `data/quests.json` + `QuestDB.lore()`; en `PanelMisiones` (J) cada misión en curso es un botón que abre la sub-ventana `VentanaDetalleMision` (capa 28: nombre, lore con autowrap, objetivos "x/y", recompensas oro/XP/items; arranca oculta, cierra con ESC/clic fuera/"Cerrar"; UI solo lee) · `respawn_seg` por arquetipo en `data/enemies.json` (goblin 15 s, lobo 20 s, ogro 30 s; default 20 s) + `SpawnerMobs` (`vigilar`/`avanzar(dt)` testeable/`reaparecido`; factory inyectada; respawn runtime —el timer no se guarda; NPCs no respawnean) | Loop jugable: pulsar una misión en J → leer su lore y progreso → matar 5 goblins (respawnean si los matas a todos) → entregar · guardar (F9) / cargar (F10) sin timers persistidos |
| 9.1 | **"!" de misión + segundo clic en NPC + demo con 15 mobs** ✅: `Label3D` dorado con billboard sobre NPCs con misión **disponible** (se refresca con `QuestLog.cambiada`; al aceptar desaparece) · segundo clic en NPC seleccionado lejano → `AccionClic.INTERACTUAR`: camina hasta él (`Player.RADIO_INTERACCION` = 3.0, patrón "acercarse y actuar al llegar") y al llegar abre el diálogo solo; cerca habla directo; cancelable (muerte/deselección/WASD); sin violencia · spawner verificado en la demo real (el reporte de "no instanciado" era falso positivo del grep) + la demo junta sus propios enemigos (`_mis_enemigos()`) · 15 mobs (5 por arquetipo) a ≥ 22 m del spawn, fuera del aggro inicial | Loop jugable: ver "!" sobre Ilya/Bram/Sira → aceptar (el "!" se apaga) · segundo clic en NPC lejano → el héroe camina y habla solo · matar mobs que respawnean |
| 9.2 | **E con radio + banner de completada + "?" de entrega** ✅: `Player.interactuar()` (E) respeta `RADIO_INTERACCION` 3.0 — NPC lejos = misma interacción pendiente que el segundo clic lejano (caminar y hablar al llegar), nunca ataca ni emite `intencion_atacar` · banner dorado prominente al completar objetivos ("¡Misión completada: <nombre>! Vuelve con <NPC>"; 4 s + 0.8 s fundido; `PanelMisiones.toast_completada`) · marcador del NPC generalizado a `fijar_marcador(tipo)` con `TipoMarcador {NINGUNO, DISPONIBLE "!", ENTREGAR "?"}`; la "?" manda sobre el "!" y desaparece al entregar; todo vía `QuestLog.cambiada` | Loop jugable: E en NPC lejano → el héroe camina y habla al llegar · completar 5 goblins → banner dorado + "?" sobre Ilya → entregar (la "?" se apaga) |
| 9+ | **Sistemas, uno por uno, por señales** (equipo/paper doll, talentos, profesiones…; catálogo en §6) | Cada sistema jugable al integrarse |

Reglas de la rebuild:

- Un sistema a la vez. Nunca dos sistemas grandes el mismo día.
- Cada paso termina con algo jugable de ~5 minutos que Juan Diego puede probar.
- **La UI solo lee el StatBlock, nunca lo escribe.** Los sistemas se hablan por
  señales con API chica (§7.11).
- Data-driven desde el día 1: añadir un skill, item o enemigo = tocar datos,
  no código. Las fórmulas y tablas viven en datos con nombre, no como
  constantes mágicas regadas.
- Escala inicial: 1 clase, 5 skills, 10 items, 3 enemigos. El contenido es
  barato cuando la base es sólida; carísimo cuando no.
- NO primero: pulido de UI, contenido masivo, talentos grandes, nada
  "tipo MMORPG".
- **Tecla E fija (decisión de diseño, fase 6):** la acción `interactuar` es
  reasignable solo editando el Input Map. El patrón de rebind en runtime
  (clic derecho + `user://`) pertenecía a las acciones con botón del HUD
  que la "posee"; el botón de atacar se retiró en fase 6.1 y el rebind
  vuelve con la barra de acciones (abajo). La tecla sigue siendo 100%
  data-driven (Input Map en `project.godot`), sin keycode hardcodeado en
  el código.
- **Feature planificada — barra de acciones arrastrable estilo Flyff (idea
  de Juan Diego, fase 6.1; NO implementada):** menú de acciones disponibles
  (atacar, skills, pociones, items…) desde el que el usuario **arrastra cada
  acción al slot de la barra que quiera**; la tecla del slot ejecuta la
  acción asignada (ej.: arrastrar "atacar" al slot 1 → la tecla 1 ataca en
  vez de lanzar la skill). Requisitos cuando se implemente: mapeo
  slot→acción data-driven y persistido en `user://`; la barra emite
  intenciones y los sistemas las consumen (la UI nunca escribe stats);
  el rebind de teclas por slot reemplaza al rebind del botón retirado;
  convivir con la barra de skills actual (o absorberla) sin romper el save
  versionado.

Cada fase: especificación cerrada → implementación → `--check-only` (0 fallos) →
tests headless en verde → ZIP con versión → **playtest de Juan Diego** →
siguiente fase. Un solo ZIP final por fase, sin pings intermedios salvo
bloqueo real.

---

*Fin del documento maestro v2.5 — Fase 9.2 (E respeta el radio de interacción, banner dorado de misión completada, "?" dorado de entrega pendiente con prioridad sobre el "!", marcador del NPC generalizado a `fijar_marcador(tipo)`; 798 tests en verde).*
