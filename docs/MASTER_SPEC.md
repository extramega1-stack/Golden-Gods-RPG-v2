# GOLDEN GODS RPG — REMAKE · Documento Maestro de Especificación

**Versión del documento:** 3.10 — Fase 16.1 (2026-09-22)
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
| 9.3 | **Hotfix: el muerto no queda seleccionado** ✅: al morir el objetivo pendiente o al matarlo el casteo, `_actualizar_lanzamiento_pendiente` cancela también la orden de acercarse (la fuga estaba en las skills, no en el ataque básico) · clic sobre un cadáver deselecciona sin ordenar moverse (`_clic_en_vacio`) · blindaje explícito `esta_vivo()` en `solicitar_ataque` | Pedido de Juan Diego: tras matar un mob, T o una skill ya no hacen caminar al héroe hacia el cadáver |
| 10 | **Auto-ataque persistente** ✅: entrar en combate con un skill dañino fija `objetivo_ataque` (antes solo el pendiente sin selección lo hacía) — tras el casteo el héroe sigue golpeando solo con la cadencia y el daño intactos · si el objetivo sale del rango lo persigue y retoma (patrón "acercarse y actuar" existente) · el bucle lo detienen: muerte del objetivo (9.3), otra orden (mover/WASD/deselección/ESC), otro objetivo u otro skill dañino sobre otro objetivo · `deseleccionar()` ahora suelta el foco de combate completo (objetivo + orden de movimiento): ESC detiene el auto-ataque y la marcha · `tests/test_fase10.gd` (26 asserts) | Pedido de Juan Diego: "yo selecciono una habilidad y cuando llega le pega, el personaje le sigue atacando al mob" — T, doble clic o skill inician un bucle que solo para al morir el mob o al recibir otra orden |
| 11 | **Héroe y presentación** ✅: `data/clases.json` + `ClaseDB` (mismo patrón que las otras DBs: `cargar()` idempotente, `ids()` en orden, `jugables()`, `es_jugable()`, `stats_base()`, `color_primario()`/`color_secundario()` con default dorado; solo el guerrero jugable —activar otra clase es solo datos—; guerrero 45/10/0/0, idéntico feel al demo) · `Player` con identidad (`nombre`, `clase_id`, señal `identidad_cambiada`, `fijar_identidad()`, `aplicar_clase()`; `_ready` ya no hardcodea stats: usa `ClaseDB`) · `DatosSesion` (holder estático entre escenas, sin autoload: `nueva_partida`/`pedir_continuar`/`limpiar`/`aplicar_a`) · pantalla de título (primera escena del juego: fondo 3D procedural propio —suelo oscuro, 6 pilares, 2 braseros con luz anaranjada, cielo casi negro, cámara con órbita lenta—; "GOLDEN GODS" dorado + botones Nueva partida / Continuar / Salir; Continuar deshabilitado sin save; ESC sale) · creación de personaje (nombre con validación 1–16 + tarjetas de clase desde datos —las no jugables salen "Próximamente"— + descripción y stats; "Comenzar aventura"/"Atrás") · retrato del héroe en el HUD (emblema procedural 64×64 con la inicial de la clase + nombre + nivel; `subio_nivel`/`murio`/`identidad_cambiada`; UI solo lee) · demo fase11 (hereda de fase9: nueva partida aplica `DatosSesion`, continuar carga el save con el flujo del F10 refactorizado en `_cargar_partida_guardada()`) · save con `"nombre"`/`"clase_id"` en el bloque jugador (sin bump de versión: partidas viejas cargan con "Héroe"/"guerrero") · `tests/test_fase11.gd` (56 asserts) | Loop jugable: título → crear héroe (nombre + clase) → jugar con retrato → guardar (F9) / cargar (F10) con nombre y clase restaurados; Continuar desde el título carga la partida |
| 12 | **Mundo abierto real** ✅: `data/terreno.bin` (heightmap del legado 1:1 —289×289 alturas + colores RGB por vértice—, escala real 36.864 u sin reescalar) + `Terreno` (`altura_en()` bilineal, 36 chunks 6×6 con 2 LODs por `visibility_range`, colisión en capa 1 como el suelo anterior; el clic sigue resolviendo sobre el terreno) · `Entity.terreno` + `_pegar_al_terreno()` (jugador, NPCs y creeps caminan pegados al suelo) · `data/spawns.json` (1121 creeps del legado: gx=x, gz=4096−y; nivel→arquetipo: ≤30 goblin, 31–200 lobo, >200 ogro; zona segura 40 m en la aldea; generador determinista `tools/generar_spawns.py`) instanciados por `fase12_demo` con la factory de la fase 9 (respawn intacto) · `data/regiones.json` + `RegionDB` (10 regiones que cubren el mapa sin huecos: Piedraceniza 1–5, Tierras Francas 4–12, Ceniza y Forja 10–18, Costa del Lamento 12–20, Bosque Hondo 14–22, Abismo Lloroso 18–28, Tierras del Trueno 30–40, Umbral de Ladón 34–46, Corona Quebrada 40–52, El Velo 55–70) + `VigiaRegion` + `BannerRegion` ("Has descubierto: X", una vez por región) · `data/ciclo.json` + `CicloDia` (día de 720 s data-driven: sol/luna direccionales, cielo procedural, señales amanecer/anochecer) + `Antorcha` (OmniLight3D cálida con flicker, más intensa de noche; 6 en la aldea) · cámara con `far = 40000`; el título abre `fase12_demo` · tests fase12 (terreno 215 + regiones 52 + spawns 14 + ciclo 35 + integración) | Loop jugable: salir de Piedraceniza y caminar el mundo abierto con día/noche, descubrir regiones y pelear creeps por bandas de nivel |
| 12.1 | **Hotfix rendimiento: streaming de mobs** ✅ (pedido de Juan Diego: "va super lageado"): causa — la fase 12 instanciaba los 1121 creeps de una vez como nodos `Enemy` completos (`_physics_process` + `move_and_slide` + material propio + draw call cada uno) · `StreamingMobs` (`data/streaming.json`: radio_alta 600 / radio_baja 800 / intervalo 0.25 s): los spawns viven como DATOS y solo se instancian los cercanos, con histéresis (la banda intermedia no hace churn; invisible para el jugador) · el respawn de la fase 9 sigue programando sus timers pero la `puerta_reaparicion` del `SpawnerMobs` veta reaparecer lejos del jugador (el pendiente se reprograma cada 5 s, no se pierde) · IA escalonada por distancia (`Enemy.intervalo_cerebro`: <60 m cada frame, <250 m cada 3, resto cada 6; `reparto` 0–7 por instancia) · materiales compartidos por color de arquetipo (antes uno por mob) · la demo conecta botín/muerte/vigilancia al instanciar y saca de la lista al liberar (el save guarda la lista viva como siempre) · `tests/test_streaming.gd` (26 asserts: solo cercanos / histéresis / liberar+reinstanciar / puerta de respawn / intervalo_cerebro / materiales compartidos) | Loop jugable: el mundo abierto va fluido; los mobs aparecen al acercarse y el respawn sigue funcionando |
| 13 | **Orientación en el mundo: minimapa + brújula** ✅: `Minimap` (`scripts/ui/minimapa.gd`, capa `UiLayers.MINIMAPA` = 11): 200×200 abajo-derecha estilo WC3 con el terreno real pre-renderizado una vez (`Terreno.color_en`, grilla 144×144) · transformaciones puras `mundo_a_mapa`/`mapa_a_mundo` (redondas) · flecha blanca del jugador, puntos rojos de mobs (`StreamingMobs.mobs_vivos()`), dorados de NPCs · fade a 0.35 tras 4 s quieto · Alt+clic = ping dorado de 5 s · clic/arrastrar normal = `Player.ordenar_mover_a` (clamp al mundo + `altura_en`) · etiqueta con la región actual (`RegionDB`) · `mouse_filter STOP` solo en su rect (nunca come clics fuera) · `Brujula` (`scripts/ui/brujula.gd`, capa `UiLayers.BRUJULA` = 14, `MOUSE_FILTER_IGNORE`): tira 420×30 arriba-centro con N/E/S/O que giran con `CameraRig.yaw()` (norte = -Z) + diamante dorado hacia el objetivo de `QuestLog.mision_activa()` (lista → NPC `npc_origen`; activa matar → mob vivo más cercano del arquetipo; hablar → NPC objetivo; otro → origen) con distancia en m, pegado al borde si está detrás · ambas solo leen datos/señales · APIs de soporte: `Terreno.color_en`, `CameraRig.yaw`, `Player.ordenar_mover_a`, `StreamingMobs.mobs_vivos`, `QuestLog.mision_activa` · `tests/test_fase13_minimapa.gd` (31 asserts) + `tests/test_fase13_brujula.gd` (33 asserts) | Loop jugable: orientarse con el minimapa, pingear, clicar para moverse y seguir la brújula hasta el objetivo de la misión |

| 14 | **Rework 2026 del mapa: ciudad principal "Moon Town"** ✅: ADN de los mapas WC3 de Juan Diego conservado como idea — la ciudad principal reimaginada como "Moon Town" (nada copiado de Blizzard: todo procedural y original, dirección visual Lineage 2 + MU) · `data/terreno.bin` del rework (disco urbano plano H=40.0 en (0,0) radio 800; biomas por región con los tintes de `data/regiones.json`; generador `tools/generar_terreno_rework.py`; backup en `data/terreno_fase12.bak`) · `data/regiones.json` remapeado (región 1 = `moon_town` "Moon Town"; 10 rects sin huecos ni solapes) · `data/spawns.json` regenerado (1121 spawns; zona segura de 40 m en la ciudad; ninguno de Moon Town dentro del disco urbano; generador `tools/generar_spawns_rework.py`) · `data/ciudad_luna.json` + `CiudadLuna` (`scripts/mundo/ciudad_luna.gd`): 18 edificios data-driven (monumento con luna creciente dorada, Salón de Clases, forja de Bram, tienda de Sira, cuartel de Ilya, templo menor, 8 casas en 3 variantes procedurales, muralla con 4 puertas N/S/E/O), cada uno con StaticBody3D en capa 1 y BoxShape3D, alturas ≤ 28 u (cámara L2/MU), calles de 40 u libres de colisiones invisibles, ≥ 35 antorchas (reutilizan `Antorcha`; el ciclo día/noche las modula); API: `terreno` (asignar ANTES del add_child), `ciclo`/`fijar_ciclo()`, señal `ciudad_lista`, `punto_aparicion_jugador()`/`yaw_aparicion()`/`npc_spawn()`/`puntos_npc`/`cajas_colision()` · `fase14_demo` (hereda de `fase12_demo`: construye la ciudad antes de `super._ready()`; el jugador aparece en la plaza mirando al monumento; Ilya/Bram/Sira se recolocan en `npc_spawn()`; el título la abre; Continuar y F9/F10 intactos) · `data/npcs.json` habla de "Moon Town" en diálogos/roles (solo texto, sin tocar lógica) · minimapa en STANDBY: sigue leyendo `Terreno.color_en` del terreno nuevo (sin pulir ni extender) · `tests/test_fase14_terreno.gd` (34 asserts) + `tests/test_fase14_ciudad.gd` (49 asserts) + `tests/test_fase14_integracion.gd` (36 asserts) | Loop jugable: aparecer en la plaza de Moon Town con día/noche, hablar con Ilya/Bram/Sira, salir por las puertas y que el streaming active los mobs del mundo |
| 14.1 | **TEMPORAL — Portales de inspección** ~~✅~~ ❌ **ELIMINADA en la Fase 16 por pedido de Juan Diego**: borrados `data/portales_temp.json`, `scripts/mundo/portal_temporal.gd` y `tests/test_portales_temp.gd` (47 asserts), y quitado el bloque TEMPORAL de `fase14_demo.gd` (0 referencias en el código; el viaje rápido con NPCs porteros es el sistema permanente). *Diseño original:* `data/portales_temp.json` (10 destinos) · `PortalTemporal` (`scripts/mundo/portal_temporal.gd`): anillo procedural magenta emissive + Label3D con el nombre (billboard) + giro lento · `fase14_demo`: círculo de 9 portales en la plaza de Moon Town (r=55) + 1 portal de vuelta en cada destino; E cerca de un portal teletransporta · *Lo que sobrevive:* el criterio de destino por plaza (ahora es la matriz data-driven de `viaje_rapido.json` en la Fase 16) | ~~Loop: acercarse a un portal en la plaza → E → aparecer en el destino → E en su portal → volver a Moon Town~~ |
| 15 | **Las 8 ciudades secundarias en 3D** ✅: `CiudadLuna` generalizado (`scripts/mundo/ciudad_luna.gd`) — `centro: Vector2` desplaza TODA la construcción (edificios, muralla, antorchas, NPCs, aparición; las x/z del JSON son relativas) y `luces_reales` conmuta antorchas reales/falsas; con centro=(0,0) Moon Town se construye igual que en la fase 14 · 8 `data/ciudad_{desert,fire,north,mystic,shadow,rage,fury,golden}.json` (16 edificios c/u: monumento + 4–5 edificios temáticos + 6–7 casas + 4 puertas; `_paleta` propia por ciudad; muralla r=620; `aparicion_jugador` en la plaza; 1 NPC ambiental c/u) · 8 monumentos nuevos procedurales (≤ 28 u): oasis (pileta + palmeras), volcán (cono con grietas de lava + brasero), pico del norte (menhir con nieve), cristal arcano (aguja flotante que rota), pilar de sombra (obelisco + estandartes), trofeo de guerra (tótem con colmillos), tormenta esculpida (esfera + anillos), sol dorado (disco con rayos) · `FalsaAntorcha` (`scripts/mundo/falsa_antorcha.gd`): llama emissive con flicker y día/noche vía `ciclo`, SIN OmniLight3D (~41 luces reales ahorradas por ciudad; Moon Town conserva las reales) · 16 variantes de casa + variantes temáticas por edificio · `data/terreno.bin` con 9 discos planos (Moon r=800 H=40 + 8 secundarios r=700; backup `data/terreno_fase14.bak`; generador `tools/generar_terreno_rework.py`) · `data/spawns.json` con zona segura de 40 m en las 9 ciudades (generador `tools/generar_spawns_rework.py`) · 8 NPCs ambientales en `data/npcs.json` (yasmina, durnan, sella, elthar, vex, karg, maris, aurelio; la demo los coloca en su ciudad) · `data/portales_temp.json`: los 9 destinos de ciudad ahora apuntan a su plaza (`punto_aparicion_jugador`, sin "(futura)") · `fase14_demo` construye las 9 ciudades (las 8 con `luces_reales = false`) · corrección de datos: 9 edificios que invadían las calles de 40 u se movieron fuera (la spec exige calles libres) · `tests/test_fase15_ciudades.gd` (251 asserts en la Fase 16: los 31 de portales se eliminaron con la fase 14.1: 8 JSON + construcción con `centro`, monumento distintivo por ciudad, ≥10 edificios, muralla/puertas, colisiones en capa 1, 0 OmniLight3D en secundarias, spawn en suelo válido, NPC ambiental en su disco, alturas ≤ 28 u, calles libres (los asserts de portales se eliminaron en la Fase 16 con la 14.1), regresión Moon Town) + `tests/smoke_fase15_ciudades.gd` (demo real: visita las 8 plazas, 20 NPCs (fase 16), streaming sano, 0 errores) · fixes de regresión: `test_fase91.gd` actualizado a 20 NPCs (64 asserts; el "!" solo en ilya/bram/sira; ni los 8 ambientales ni los 9 porteros tienen misión y no lo muestran) y `test_respawn.gd` con el umbral correcto (√2×RADIO_VARIACION: el anterior era flaky ~17%) | Loop jugable: salir de Moon Town y visitar las 8 ciudades, cada una con su monumento, su paleta y su NPC |

| 15.1 | **Hotfix: clic izquierdo para caminar** ✅: causa raíz (NO síntoma) — los triángulos de `Terreno._caras_colision` y `Terreno._malla_chunk` (`scripts/mundo/terreno.gd`) tenían el winding invertido: las caras frontales apuntaban hacia ABAJO (-Y) y, como `ConcavePolygonShape3D` tiene `backface_collision=false` por defecto, los raycasts descendentes del clic izquierdo del Player atravesaban el terreno sin golpear nada (el clic nunca fijaba destino) · fix: orden `(a,c,b)/(c,d,b)` → `(a,b,c)/(c,b,d)` en ambos (malla + colisión) + comentario falso corregido en `_hacer_material` · NO se usó `backface_collision=true` (el winding correcto es el fix real) · `move_and_slide` ahora colisiona de verdad con el terreno (capa 1, diseño original) y `_pegar_al_terreno` sigue mandando por datos: ambos coinciden, nada se atasca · `tests/test_fase151_clic.gd` (12 asserts: rayo descendente golpea a la altura del dato en 2 puntos, rayo ascendente NO golpea —descarta el atajo `backface_collision=true`—, normales de `_caras_colision` hacia +Y, y la cadena del clic: el hit en la rama de suelo fija `_tiene_destino`) + `tests/smoke_fase151_clic.gd` (demo real: el jugador camina por clic y por WASD, ≥ 400 frames, sin hundirse ni flotar, 0 errores) | Loop jugable: clic en el suelo → el héroe camina hasta el punto (como antes de la fase 12) |
| 16 | **Viaje rápido con NPCs porteros + clima dinámico** ✅ (pedido de Juan Diego: los portales temporales de la 14.1 se ELIMINAN) · **Viaje rápido:** `data/viaje_rapido.json` (data-driven): 9 ciudades con `plaza` (punto de aparición), `nivel_min`/`nivel_max` por la banda de su región y la **matriz 9×8** de destinos con `costo_oro` y `nivel_min`; criterio (decisión de Juan Diego): `costo = redondeo5(base(nivel_min_destino) + 10 × distancia_km entre plazas)` con base {1:25, 4:60, 10:120, 12:140, 22:220, 26:280, 30:340, 36:440} — más lejos y banda de nivel mayor ⇒ más caro y más nivel; desde Moon Town: desert 160 (nv. 4), fire 220 (nv. 10), north 195 (nv. 12), mystic 240 (nv. 12), shadow 360 (nv. 22), rage 420 (nv. 26), fury 480 (nv. 30), golden 580 (nv. 36) · `ViajeRapido` (`scripts/mundo/viaje_rapido.gd`, lógica pura SIN UI: `evaluar()` con bloqueos por sin_oro / sin_nivel / en_combate / destino desconocido, `viajar()` que descuenta el oro exacto y devuelve la plaza del destino) · 9 NPCs porteros en `data/npcs.json` (rol `Portero`, campo `viaje_id`; spawn data-driven en los 8 `ciudad_*.json` + el de Moon Town en la plaza) · `VentanaDialogo`: botón "Viajar" solo con portero (señal `viaje_solicitado`) · `PanelViaje` (`scripts/ui/panel_viaje.gd`, capa `UiLayers.PANEL_VIAJE` = 29, arranca oculto, UI solo lee): lista destinos con costo/nivel, bloquea en combate, ESC cierra · **Clima:** `data/clima.json` + `Clima` (`scripts/mundo/clima.gd`): máquina de estados GLOBAL (despejado / lluvia / niebla / lluvia_niebla) con dado ponderado cada 90–180 s, transiciones interpoladas (4–6 s, sin cortes bruscos); lluvia (GPUParticles3D: 2000 gotas, atenuación del sol/luna, gris del cielo) + niebla (fog exponencial vía `CicloDia.ambiente()` + vars aditivas `factor_clima`/`gris_tormenta`); instanciado en `fase12_demo` (heredado por `fase14_demo`) · `tests/test_fase16_viaje.gd` (454 checks) + `tests/test_fase16_clima.gd` (123 asserts); regresión total 2236 en verde | Loop jugable: hablar con el Portero Anselmo en Moon Town → "Viajar" → pagar 160 de oro → aparecer en Desert Town (nv. ≥ 4); en combate el botón se bloquea · caminar el mundo con lluvia que entra y sale suave, y niebla en las regiones frías |
| 16.1 | **TEMPORAL — Viaje rápido GRATIS** ✅ (pedido de Juan Diego mientras confirma que el viaje funciona): `ViajeRapido.GRATIS_TEMPORAL = true` (`scripts/mundo/viaje_rapido.gd`) — `destinos_desde()` devuelve `costo_oro = 0` para los 8 destinos (el JSON conserva los costos reales sin tocar); `evaluar()`/`viajar()` fluyen igual (sin_oro imposible con costo 0); `PanelViaje` muestra "Gratis" en vez de "X oro" · `tests/test_fase16_viaje.gd` actualizado a modo flag-aware (452 checks en verde) · al quitarlo: volver la const a `false` | Loop jugable: hablar con el portero → "Viajar" → destino gratis (temporal) |
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

*Fin del documento maestro v3.10 — Fase 16.1 (viaje rápido temporalmente GRATIS por pedido de Juan Diego; 452 checks de viaje en verde).*
