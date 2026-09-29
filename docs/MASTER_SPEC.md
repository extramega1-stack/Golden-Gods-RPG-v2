# GOLDEN GODS RPG — REMAKE · Documento Maestro de Especificación

**Versión del documento:** 3.55 — Fase 70: la FORMA del mundo (2026-09-29)
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

**Estado:** Fase 70 terminada (la última; el detalle de cada fase vive en su
sección, desde "Fase 0" hasta el final del documento) —
Fase 9: Detalle de misión + respawn de mobs:
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
  funcionando igual vía `Player.solicitar_ataque` (foco: selección
  combatible > objetivo de ataque; sin foco no hace nada — fase 18.4
  eliminó el auto-ataque al mob más cercano). El rebind de tecla por clic
  derecho murió con el botón:
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
  modelos procedurales de respaldo (los 85 GLB quedaron autorizados el 2026-09-25 con licencia CC0/CC-BY; ver Fase 48) hasta que Juan Diego autorice integrar los
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
| 12 | **Mundo abierto real** ✅: `data/terreno.bin` (heightmap del legado 1:1 —289×289 alturas + colores RGB por vértice—, escala real 36.864 u sin reescalar) + `Terreno` (`altura_en()` bilineal, 36 chunks 6×6 con 2 LODs por `visibility_range`, colisión en capa 1 como el suelo anterior; el clic sigue resolviendo sobre el terreno) · `Entity.terreno` + `_pegar_al_terreno()` (jugador, NPCs y creeps caminan pegados al suelo) · `data/spawns.json` (1121 creeps del legado: gx=x, gz=4096−y; nivel→arquetipo: ≤30 goblin, 31–200 lobo, >200 ogro; zona segura 40 m en la aldea; generador determinista `tools/generar_spawns.py`, **BORRADO en la fase 50.4**: lo reemplazó `tools/generar_spawns_rework.py` (región→arquetipo en vez de nivel→arquetipo) y su docstring describía una regla que ya no aplica. Ningún test ni script lo ejecutaba.) instanciados por `fase12_demo` con la factory de la fase 9 (respawn intacto) · `data/regiones.json` + `RegionDB` (10 regiones que cubren el mapa sin huecos: Piedraceniza 1–5, Tierras Francas 4–12, Ceniza y Forja 10–18, Costa del Lamento 12–20, Bosque Hondo 14–22, Abismo Lloroso 18–28, Tierras del Trueno 30–40, Umbral de Ladón 34–46, Corona Quebrada 40–52, El Velo 55–70) + `VigiaRegion` + `BannerRegion` ("Has descubierto: X", una vez por región) · `data/ciclo.json` + `CicloDia` (día de 720 s data-driven: sol/luna direccionales, cielo procedural, señales amanecer/anochecer) + `Antorcha` (OmniLight3D cálida con flicker, más intensa de noche; 6 en la aldea) · cámara con `far = 40000`; el título abre `fase12_demo` · tests fase12 (terreno 215 + regiones 52 + spawns 14 + ciclo 35 + integración) | Loop jugable: salir de Piedraceniza y caminar el mundo abierto con día/noche, descubrir regiones y pelear creeps por bandas de nivel |
| 12.1 | **Hotfix rendimiento: streaming de mobs** ✅ (pedido de Juan Diego: "va super lageado"): causa — la fase 12 instanciaba los 1121 creeps de una vez como nodos `Enemy` completos (`_physics_process` + `move_and_slide` + material propio + draw call cada uno) · `StreamingMobs` (`data/streaming.json`: radio_alta 600 / radio_baja 800 / intervalo 0.25 s): los spawns viven como DATOS y solo se instancian los cercanos, con histéresis (la banda intermedia no hace churn; invisible para el jugador) · el respawn de la fase 9 sigue programando sus timers pero la `puerta_reaparicion` del `SpawnerMobs` veta reaparecer lejos del jugador (el pendiente se reprograma cada 5 s, no se pierde) · IA escalonada por distancia (`Enemy.intervalo_cerebro`: <60 m cada frame, <250 m cada 3, resto cada 6; `reparto` 0–7 por instancia) · materiales compartidos por color de arquetipo (antes uno por mob) · la demo conecta botín/muerte/vigilancia al instanciar y saca de la lista al liberar (el save guarda la lista viva como siempre) · `tests/test_streaming.gd` (26 asserts: solo cercanos / histéresis / liberar+reinstanciar / puerta de respawn / intervalo_cerebro / materiales compartidos) | Loop jugable: el mundo abierto va fluido; los mobs aparecen al acercarse y el respawn sigue funcionando |
| 13 | **Orientación en el mundo: minimapa + brújula** ✅: `Minimap` (`scripts/ui/minimapa.gd`, capa `UiLayers.MINIMAPA` = 11): 200×200 abajo-derecha estilo WC3 con el terreno real pre-renderizado una vez (`Terreno.color_en`, grilla 144×144) · transformaciones puras `mundo_a_mapa`/`mapa_a_mundo` (redondas) · flecha blanca del jugador, puntos rojos de mobs (`StreamingMobs.mobs_vivos()`), dorados de NPCs · fade a 0.35 tras 4 s quieto · Alt+clic = ping dorado de 5 s · clic/arrastrar normal = `Player.ordenar_mover_a` (clamp al mundo + `altura_en`) · etiqueta con la región actual (`RegionDB`) · `mouse_filter STOP` solo en su rect (nunca come clics fuera) · `Brujula` (`scripts/ui/brujula.gd`, capa `UiLayers.BRUJULA` = 14, `MOUSE_FILTER_IGNORE`): tira 420×30 arriba-centro con N/E/S/O que giran con `CameraRig.yaw()` (norte = -Z) + diamante dorado hacia el objetivo de `QuestLog.mision_activa()` (lista → NPC `npc_origen`; activa matar → mob vivo más cercano del arquetipo; hablar → NPC objetivo; otro → origen) con distancia en m, pegado al borde si está detrás · ambas solo leen datos/señales · APIs de soporte: `Terreno.color_en`, `CameraRig.yaw`, `Player.ordenar_mover_a`, `StreamingMobs.mobs_vivos`, `QuestLog.mision_activa` · `tests/test_fase13_minimapa.gd` (31 asserts) + `tests/test_fase13_brujula.gd` (33 asserts) | Loop jugable: orientarse con el minimapa, pingear, clicar para moverse y seguir la brújula hasta el objetivo de la misión |

| 14 | **Rework 2026 del mapa: ciudad principal "Moon Town"** ✅: ADN de los mapas WC3 de Juan Diego conservado como idea — la ciudad principal reimaginada como "Moon Town" (nada copiado de Blizzard: todo procedural y original, dirección visual Lineage 2 + MU) · `data/terreno.bin` del rework (disco urbano plano H=40.0 en (0,0) radio 800; biomas por región con los tintes de `data/regiones.json`; generador `tools/generar_terreno_rework.py`; backup en `data/terreno_fase12.bak`) · `data/regiones.json` remapeado (región 1 = `moon_town` "Moon Town"; 10 rects sin huecos ni solapes) · `data/spawns.json` regenerado (1121 spawns; zona segura de 40 m en la ciudad; ninguno de Moon Town dentro del disco urbano; generador `tools/generar_spawns_rework.py`) · `data/ciudad_luna.json` + `CiudadLuna` (`scripts/mundo/ciudad_luna.gd`): 18 edificios data-driven (monumento con luna creciente dorada, Salón de Clases, forja de Bram, tienda de Sira, cuartel de Ilya, templo menor, 8 casas en 3 variantes procedurales, muralla con 4 puertas N/S/E/O), cada uno con StaticBody3D en capa 1 y BoxShape3D, alturas ≤ 28 u (cámara L2/MU), calles de 40 u libres de colisiones invisibles, ≥ 35 antorchas (reutilizan `Antorcha`; el ciclo día/noche las modula); API: `terreno` (asignar ANTES del add_child), `ciclo`/`fijar_ciclo()`, señal `ciudad_lista`, `punto_aparicion_jugador()`/`yaw_aparicion()`/`npc_spawn()`/`puntos_npc`/`cajas_colision()` · `fase14_demo` (hereda de `fase12_demo`: construye la ciudad antes de `super._ready()`; el jugador aparece en la plaza mirando al monumento; Ilya/Bram/Sira se recolocan en `npc_spawn()`; el título la abre; Continuar y F9/F10 intactos) · `data/npcs.json` habla de "Moon Town" en diálogos/roles (solo texto, sin tocar lógica) · minimapa en STANDBY: sigue leyendo `Terreno.color_en` del terreno nuevo (sin pulir ni extender) · `tests/test_fase14_terreno.gd` (34 asserts) + `tests/test_fase14_ciudad.gd` (49 asserts) + `tests/test_fase14_integracion.gd` (36 asserts) | Loop jugable: aparecer en la plaza de Moon Town con día/noche, hablar con Ilya/Bram/Sira, salir por las puertas y que el streaming active los mobs del mundo |
| 14.1 | **TEMPORAL — Portales de inspección** ~~✅~~ ❌ **ELIMINADA en la Fase 16 por pedido de Juan Diego**: borrados `data/portales_temp.json`, `scripts/mundo/portal_temporal.gd` y `tests/test_portales_temp.gd` (47 asserts), y quitado el bloque TEMPORAL de `fase14_demo.gd` (0 referencias en el código; el viaje rápido con NPCs porteros es el sistema permanente). *Diseño original:* `data/portales_temp.json` (10 destinos) · `PortalTemporal` (`scripts/mundo/portal_temporal.gd`): anillo procedural magenta emissive + Label3D con el nombre (billboard) + giro lento · `fase14_demo`: círculo de 9 portales en la plaza de Moon Town (r=55) + 1 portal de vuelta en cada destino; E cerca de un portal teletransporta · *Lo que sobrevive:* el criterio de destino por plaza (ahora es la matriz data-driven de `viaje_rapido.json` en la Fase 16) | ~~Loop: acercarse a un portal en la plaza → E → aparecer en el destino → E en su portal → volver a Moon Town~~ |
| 15 | **Las 8 ciudades secundarias en 3D** ✅: `CiudadLuna` generalizado (`scripts/mundo/ciudad_luna.gd`) — `centro: Vector2` desplaza TODA la construcción (edificios, muralla, antorchas, NPCs, aparición; las x/z del JSON son relativas) y `luces_reales` conmuta antorchas reales/falsas; con centro=(0,0) Moon Town se construye igual que en la fase 14 · 8 `data/ciudad_{desert,fire,north,mystic,shadow,rage,fury,golden}.json` (16 edificios c/u: monumento + 4–5 edificios temáticos + 6–7 casas + 4 puertas; `_paleta` propia por ciudad; muralla r=620; `aparicion_jugador` en la plaza; 1 NPC ambiental c/u) · 8 monumentos nuevos procedurales (≤ 28 u): oasis (pileta + palmeras), volcán (cono con grietas de lava + brasero), pico del norte (menhir con nieve), cristal arcano (aguja flotante que rota), pilar de sombra (obelisco + estandartes), trofeo de guerra (tótem con colmillos), tormenta esculpida (esfera + anillos), sol dorado (disco con rayos) · `FalsaAntorcha` (`scripts/mundo/falsa_antorcha.gd`): llama emissive con flicker y día/noche vía `ciclo`, SIN OmniLight3D (~41 luces reales ahorradas por ciudad; Moon Town conserva las reales) · 16 variantes de casa + variantes temáticas por edificio · `data/terreno.bin` con 9 discos planos (Moon r=800 H=40 + 8 secundarios r=700; backup `data/terreno_fase14.bak`; generador `tools/generar_terreno_rework.py`) · `data/spawns.json` con zona segura de 40 m en las 9 ciudades (generador `tools/generar_spawns_rework.py`) · 8 NPCs ambientales en `data/npcs.json` (yasmina, durnan, sella, elthar, vex, karg, maris, aurelio; la demo los coloca en su ciudad) · `data/portales_temp.json`: los 9 destinos de ciudad ahora apuntan a su plaza (`punto_aparicion_jugador`, sin "(futura)") · `fase14_demo` construye las 9 ciudades (las 8 con `luces_reales = false`) · corrección de datos: 9 edificios que invadían las calles de 40 u se movieron fuera (la spec exige calles libres) · `tests/test_fase15_ciudades.gd` (251 asserts en la Fase 16: los 31 de portales se eliminaron con la fase 14.1: 8 JSON + construcción con `centro`, monumento distintivo por ciudad, ≥10 edificios, muralla/puertas, colisiones en capa 1, 0 OmniLight3D en secundarias, spawn en suelo válido, NPC ambiental en su disco, alturas ≤ 28 u, calles libres (los asserts de portales se eliminaron en la Fase 16 con la 14.1), regresión Moon Town) + `tests/smoke_fase15_ciudades.gd` (demo real: visita las 8 plazas, 20 NPCs (fase 16), streaming sano, 0 errores) · fixes de regresión: `test_fase91.gd` actualizado a 20 NPCs (64 asserts; el "!" solo en ilya/bram/sira; ni los 8 ambientales ni los 9 porteros tienen misión y no lo muestran) y `test_respawn.gd` con el umbral correcto (√2×RADIO_VARIACION: el anterior era flaky ~17%) | Loop jugable: salir de Moon Town y visitar las 8 ciudades, cada una con su monumento, su paleta y su NPC |

| 15.1 | **Hotfix: clic izquierdo para caminar** ✅: causa raíz (NO síntoma) — los triángulos de `Terreno._caras_colision` y `Terreno._malla_chunk` (`scripts/mundo/terreno.gd`) tenían el winding invertido: las caras frontales apuntaban hacia ABAJO (-Y) y, como `ConcavePolygonShape3D` tiene `backface_collision=false` por defecto, los raycasts descendentes del clic izquierdo del Player atravesaban el terreno sin golpear nada (el clic nunca fijaba destino) · fix: orden `(a,c,b)/(c,d,b)` → `(a,b,c)/(c,b,d)` en ambos (malla + colisión) + comentario falso corregido en `_hacer_material` · NO se usó `backface_collision=true` (el winding correcto es el fix real) · `move_and_slide` ahora colisiona de verdad con el terreno (capa 1, diseño original) y `_pegar_al_terreno` sigue mandando por datos: ambos coinciden, nada se atasca · `tests/test_fase151_clic.gd` (12 asserts: rayo descendente golpea a la altura del dato en 2 puntos, rayo ascendente NO golpea —descarta el atajo `backface_collision=true`—, normales de `_caras_colision` hacia +Y, y la cadena del clic: el hit en la rama de suelo fija `_tiene_destino`) + `tests/smoke_fase151_clic.gd` (demo real: el jugador camina por clic y por WASD, ≥ 400 frames, sin hundirse ni flotar, 0 errores) | Loop jugable: clic en el suelo → el héroe camina hasta el punto (como antes de la fase 12) |
| 16 | **Viaje rápido con NPCs porteros + clima dinámico** ✅ (pedido de Juan Diego: los portales temporales de la 14.1 se ELIMINAN) · **Viaje rápido:** `data/viaje_rapido.json` (data-driven): 9 ciudades con `plaza` (punto de aparición), `nivel_min`/`nivel_max` por la banda de su región y la **matriz 9×8** de destinos con `costo_oro` y `nivel_min`; criterio (decisión de Juan Diego): `costo = redondeo5(base(nivel_min_destino) + 10 × distancia_km entre plazas)` con base {1:25, 4:60, 10:120, 12:140, 22:220, 26:280, 30:340, 36:440} — más lejos y banda de nivel mayor ⇒ más caro y más nivel; desde Moon Town: desert 160 (nv. 4), fire 220 (nv. 10), north 195 (nv. 12), mystic 240 (nv. 12), shadow 360 (nv. 22), rage 420 (nv. 26), fury 480 (nv. 30), golden 580 (nv. 36) · `ViajeRapido` (`scripts/mundo/viaje_rapido.gd`, lógica pura SIN UI: `evaluar()` con bloqueos por sin_oro / sin_nivel / en_combate / destino desconocido, `viajar()` que descuenta el oro exacto y devuelve la plaza del destino) · 9 NPCs porteros en `data/npcs.json` (rol `Portero`, campo `viaje_id`; spawn data-driven en los 8 `ciudad_*.json` + el de Moon Town en la plaza) · `VentanaDialogo`: botón "Viajar" solo con portero (señal `viaje_solicitado`) · `PanelViaje` (`scripts/ui/panel_viaje.gd`, capa `UiLayers.PANEL_VIAJE` = 29, arranca oculto, UI solo lee): lista destinos con costo/nivel, bloquea en combate, ESC cierra · **Clima:** `data/clima.json` + `Clima` (`scripts/mundo/clima.gd`): máquina de estados GLOBAL (despejado / lluvia / niebla / lluvia_niebla) con dado ponderado cada 90–180 s, transiciones interpoladas (4–6 s, sin cortes bruscos); lluvia (GPUParticles3D: 2000 gotas, atenuación del sol/luna, gris del cielo) + niebla (fog exponencial vía `CicloDia.ambiente()` + vars aditivas `factor_clima`/`gris_tormenta`); instanciado en `fase12_demo` (heredado por `fase14_demo`) · `tests/test_fase16_viaje.gd` (454 checks) + `tests/test_fase16_clima.gd` (123 asserts); regresión total 2236 en verde | Loop jugable: hablar con el Portero Anselmo en Moon Town → "Viajar" → pagar 160 de oro → aparecer en Desert Town (nv. ≥ 4); en combate el botón se bloquea · caminar el mundo con lluvia que entra y sale suave, y niebla en las regiones frías |
| 16.1 | **TEMPORAL — Viaje rápido GRATIS** ✅ (pedido de Juan Diego mientras confirma que el viaje funciona): `ViajeRapido.GRATIS_TEMPORAL = true` (`scripts/mundo/viaje_rapido.gd`) — `destinos_desde()` devuelve `costo_oro = 0` para los 8 destinos (el JSON conserva los costos reales sin tocar); `evaluar()`/`viajar()` fluyen igual (sin_oro imposible con costo 0); `PanelViaje` muestra "Gratis" en vez de "X oro" · `tests/test_fase16_viaje.gd` actualizado a modo flag-aware (452 checks en verde) · al quitarlo: volver la const a `false` | Loop jugable: hablar con el portero → "Viajar" → destino gratis (temporal) |
| 17 | **Barra de acciones estilo Flyff** ✅ (pedido de Juan Diego): `BarraAcciones` (`scripts/ui/barra_acciones.gd`, reemplaza a `BarraSkills`) — 8 slots abajo-centro, teclas F1..F8 (acciones `barra_1`..`barra_8` del Input Map; `limpiar_slot` = Supr) · cada slot: ataque básico, skill (SkillDB) o consumible (ItemDB) · drag & drop con preview desde: chip "⚔ Ataque", libro de habilidades (botón 📖 Skills) y filas de consumibles del inventario (`PanelInventario._chip_consumible`) · clic izquierdo en slot ocupado lo ejecuta (en slot vacío NO se consume: el clic-para-moverse pasa) · clic derecho o Supr limpia el slot bajo el cursor · arrastrar entre slots los intercambia · overlay de cooldown por slot + contador xN en consumibles · layout por defecto: F1 ataque, F2..F6 los 5 skills · `Player.lanzar_skill_id(id)` (nuevo; `lanzar_skill(i)` lo reusa) · persistencia versionada en el save (SAVE_VERSION 6, bloque `barra_acciones`: slots validados, ids inválidos descartados; partidas v5 cargan con el layout por defecto) · `tests/test_fase17_barra.gd` (49 asserts: validar/asignar/ejecutar/limpiar/swap/persistencia) | Loop jugable: arrastrar ataque, skills y pociones a la barra y usarlas con F1..F8 |
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
  de Juan Diego, fase 6.1; IMPLEMENTADA en la Fase 17):** menú de acciones disponibles
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

## Fase 18 — Cuatro clases completas (guerrero, mago, arquero, clérigo)

- **32 habilidades data-driven** en `data/skills.json` v2 (8 por clase), con tipos de efecto `dano|curar|aoe|buff|debuff`; campo `clase` por skill ("" = todas).
- **Clases jugables** en `data/clases.json`: guerrero, arquero, mago, clérigo (daguero sigue no jugable); `ClaseDB.jugables()`.
- **SkillSystem** extendido: AoE (radio alrededor del objetivo o del lanzador), buffs/debuffs porcentuales temporales con expiración por objetivo (reaplicar refresca, no acumula), curas; feedback visual por tinte temporal (curar verde, buff dorado, debuff violeta, AoE naranja); audio pendiente (TODO, no hay pipeline de sonido).
- **Player.clase_id** ("guerrero" por defecto); hotbar y libro de habilidades filtrados por `SkillDB.skills_por_clase()`; creación de personaje con 4 tarjetas de clase.
- **Save v7**: `clase_id` persiste; partidas v6 cargan con "guerrero" (tolerante).
- Tests: `tests/test_fase18_clases.gd` (95 checks); suite completa 2376 checks en verde.

---

*Fin del documento maestro v3.12 — Fase 18 (4 clases × 8 habilidades, SkillSystem con AoE/buff/debuff, save v7; 95 checks nuevos, 2376 en verde).

---

## Hotfix fase-18.1 — escena principal siempre actualizada (2026-09-22)

Bug de playtest (Juan Diego): "Nueva partida" → creación de personaje → abría la escena vieja `fase11_demo.tscn` en vez de la demo real actual.

- Nuevo `scripts/core/escenas.gd` (`class_name Escenas`): fuente única de verdad — `JUEGO` (demo real, hoy `fase14_demo.tscn`), `TITULO`, `CREACION`. La próxima fase que reemplace la escena cambia UNA constante.
- `pantalla_titulo.gd` y `creacion_personaje.gd` usan `Escenas.*` (se eliminaron sus `const ESCENA_*` duplicadas y divergentes).
- `tests/test_fase14_integracion.gd`: el contrato ahora verifica la fuente única (título y creación usan `Escenas.JUEGO`; `Escenas.JUEGO` apunta a `fase14_demo`; nadie apunta a `fase11_demo`/`fase12_demo`). 39 checks en verde.

*Fin del documento maestro v3.12.1 — Hotfix fase-18.1.*

---

## Fase 18.3 — Pack de prueba de combate cerca de Moon Town (2026-09-23)

Pedido de Juan Diego: monstruos cerca de la zona principal para probar el sistema de combate sin caminar 800 m (el spawn más cercano estaba a ~797 m de la plaza).

- `tools/generar_spawns_rework.py`: nuevo `PACK_PRUEBA` — 6 mobs fijos a 132–249 m del punto de aparición del jugador (3 goblins nv. 2–3, 2 lobos nv. 32–35, 1 ogro nv. 250); posiciones a mano, verificadas fuera de los 18 edificios de `data/ciudad_luna.json`, fuera de la zona segura de 40 m y dentro del radio de streaming (600 m → se instancian al arrancar). Llevan `"grupo": "prueba_combate"`.
- `data/spawns.json` regenerado: 1127 entradas (1121 por distribución + 6 del pack); el reparto por área ahora descuenta el pack (`TOTAL - SPAWNS_MOON - len(PACK_PRUEBA)`); determinismo intacto (dos corridas → mismo SHA-256).
- Tests actualizados: `tests/test_fase12_spawns.gd` (14 checks: 1127 / 492 goblins / 634 lobos / 1 ogro), `tests/test_fase12_integracion.gd` y `tests/test_fase14_terreno.gd` (34 checks). El pack cumple la regla nivel→arquetipo y la zona segura; queda eximido (documentado) del disco urbano y de la banda de nivel de región, que son reglas de *distribución*, no de colocación a mano.
- Nota: `test_fase12_integracion.gd` tiene 1 fallo pre-existente en HEAD ("el título abre fase14_demo", test desactualizado tras la fase 18.1) — no es regresión de esta fase.

*Fin del documento maestro v3.13 — Fase 18.3 (pack de prueba de combate).*

---

## Fase 18.4 — Sin selección no se engancha al mob más cercano (2026-09-23)

Pedido de Juan Diego (bug de playtest): "sin seleccionar el mob, si apretas atacar o una habilidad va directamente a atacar al mob mas cercano". El fallback de auto-ataque al mob más cercano (fase 5.1) volvió a notarse ahora que el pack 18.3 puso mobs cerca del spawn.

- `scripts/player/player.gd`: `solicitar_ataque()` — sin foco (sin selección combatible ni objetivo de ataque) no hace nada; se eliminó el enganche al mob más cercano y la const `RADIO_AUTOATAQUE`. `_objetivo_skill()` — sin foco devuelve null para skills hostiles (se eliminó el fallback sin límite de rango al mob más cercano del árbol). `lanzar_skill_id()` — skill hostil sin objetivo válido sale en silencio (no fija objetivo, no camina, no gasta maná).
- El modelo Flyff queda intacto: primer clic selecciona; segundo clic / T / slot de ataque / skill hostil atacan la SELECCIÓN. El auto-ataque persistente de la fase 10 (skill sobre objetivo válido → el héroe sigue pegando solo) no cambia.
- Tests: `tests/test_seleccion.gd` — `_t_ataque_fallback` reescrito como `_t_ataque_sin_seleccion_no_engancha` + nuevo `_t_skill_sin_seleccion_no_engancha`; `_t_skill_acercamiento` y `_t_skill_pendiente_cancel_muerte` ahora seleccionan antes de lanzar (el fallback ya no existe). Verde: seleccion 58/58, fase10 26/26, fase93 20/20, skills 41/41, npcs 56/56, fase17_barra 50/50, player 29/29; barrido `--check-only` limpio.

## Fase 18.5 — Auto-ataque guardado tras un flag para la futura versión móvil (2026-09-23)

Pedido de Juan Diego: la opción del mob más cercano se guarda para cuando se cree la versión móvil; mientras tanto queda guardada (inactiva en PC).

- `scripts/player/player.gd`: nuevo `static var autoataque_movil: bool = false` + const `RADIO_AUTOATAQUE` restaurada (8 m). Con el flag en true, `solicitar_ataque()` y `_objetivo_skill()` usan el camino guardado de la fase 5.1 (`_mob_cercano_movil()`); en false (PC) el comportamiento 18.4 no cambia. Es `static var` para que los tests verifiquen el camino guardado y no se pudra.
- Tests: nuevo `_t_autoataque_movil_guardado` en `tests/test_seleccion.gd` (flag on → atacar y skill enganchan al más cercano; flag off → no engancha). Verde: seleccion 62/62.

*Fin del documento maestro v3.13.2 — Fase 18.5 (flag guardado para móvil).*

## Fase 19 — Game feel de combate (2026-09-23)

Elegida por Juan Diego ("Game feel me gusta, usemos eso"): pulir el combate que ya existe — números de daño, barras de vida, hit-stop y screen shake.

- `scripts/combate/game_feel.gd` (nuevo, `class_name GameFeel`): un nodo en la escena demo. `Entity.take_damage` le avisa por el estático `al_recibir_danio` (no-op sin instancia, tests seguros).
  - Números de daño: pool de 20 Label3D con billboard y no_depth_test; blanco = normal, amarillo = crítico, rojo = daño al jugador. Flotan, hacen pop y se desvanecen en 0.9 s.
  - Hit-stop: congela `Engine.time_scale` unas centésimas — crítico 0.05 s, golpe mortal 0.09 s, golpe fuerte al jugador (>15% vida) 0.06 s. Con guardia anti re-entrada.
  - Shake: trauma al CameraRig (grupo `camera_rig`) — crítico del jugador 0.25, golpe mortal 0.45, golpe fuerte al jugador 0.35.
- `scripts/combate/barra_vida_mob.gd` (nuevo, `class_name BarraVidaMob`): hijo del Enemy en `enemigo.tscn` (patrón DamageFlash). Dos quads con billboard; aparece al dañar, el color va de verde a rojo, se oculta a vida llena y al morir.
- `scripts/player/camera_rig.gd`: `trauma` (0..1), `agregar_trauma()`, decaimiento solo; offset en `h_offset`/`v_offset` con trauma².
- `scripts/core/entity.gd`: `take_damage` acepta `es_critico := false` (retrocompatible).
- Los 3 atacantes (`player.gd`, `enemy.gd`, `skill_system.gd`) pasan `bool(res["crit"])`.
- Escenas: `GameFeel` agregado a `fase14_demo.tscn`; `BarraVida` a `enemigo.tscn`.
- Tests: `tests/test_fase19_gamefeel.gd` — 29/29 en verde (números, crítico, hit-stop, barra, shake, integración). Regresión: entity 48/48, fase10 26/26, seleccion 62/62, fase93 20/20, skills 41/41, npcs 56/56, player 29/29, fase17_barra 50/50; barrido `--check-only` limpio.

*Fin del documento maestro v3.14 — Fase 19 (game feel de combate).*

## Fase 19.1 — Hotfix: "Trying to cast a freed object" (2026-09-23)

Reporte de playtest de Juan Diego: al atacar/matar mobs (los 6 de prueba cerca de Moon Town), el debugger mostraba `Trying to cast a freed object` en `streaming_mobs.gd:159` dentro de `actualizar()` — el juego "como que se crashea".

Causa raíz (dos capas):
- `_al_reaparecer_enemigo` (fase9_demo) liberaba el cadáver con `_ultimo_muerto` (una sola ranura): con 2+ muertes antes de un respawn, el respawn de A liberaba el cadáver de B y el streaming se quedaba con `rd["nodo"]` apuntando a un objeto liberado.
- `streaming_mobs.gd` casteaba ANTES de validar (`rd["nodo"] as Enemy` y luego `is_instance_valid`): el `as` sobre objeto liberado dispara el error y ABORTA la función (verificado en headless) — `actualizar()` se cortaba a la mitad y los mobs posteriores no se instanciaban/liberaban ese tick.

Fix:
- `scripts/mundo/streaming_mobs.gd`: helper estático `_nodo_registro()` que valida ANTES de castear y limpia el registro si la referencia está liberada; usado en `actualizar()`, `mobs_vivos()` y `_liberar()`.
- `scenes/demo/fase9_demo.gd`: `_al_reaparecer_enemigo` ahora busca el cadáver por cercanía al punto de reaparición (`_indice_cadaver_cercano`, mismo margen de 8 m que el streaming) en vez de `_ultimo_muerto` (variable eliminada); valida antes de castear en la lista.
- `scripts/save/save_system.gd`: valida antes de castear en `_enemigos_a_datos()` y `_cargar_enemigos()` (la lista puede contener una referencia liberada entre ticks).
- Tests: `tests/test_fase19_1.gd` — 4 pruebas (referencia liberada no aborta el tick, respawn re-asocia tras limpieza, matcher de cadáveres, respawn libera el cadáver correcto).

*Fin del documento maestro v3.14.1 — Fase 19.1 (hotfix freed object).*

## Fase 20 — Paquete de rendimiento P0 + limpieza de demos (2026-09-24)

Auditoría game-developer (60 FPS): el tick caliente hacía `load()` + `instantiate()` + `queue_free()` por stream-in/out, `mobs_vivos()` recorría 1127 registros con alloc por llamada a 60 fps, minimapa/brújula hacían `queue_redraw()` cada frame, el arranque congelaba el juego (terreno 36 chunks + 9 ciudades en el primer frame) y Moon Town pagaba ~40 OmniLight3D siempre.

Fix (sin cambiar gameplay; modos nuevos opt-in, defaults intactos para tests):
- P0-1 Pool de mobs: `scripts/mundo/pool_mobs.gd` (nuevo, `class_name PoolMobs`): precarga `enemigo.tscn` UNA vez, freelist por arquetipo (`obtener`/`devolver`, `SkillFX` una vez por instancia). `Enemy.reiniciar(arquetipo)` (reconfigura, revive, colisión viva 4/1). La factory de la demo delega al pool; el streaming recicla vía `fijar_pool()` (sin pool = `queue_free()` como antes); conexiones de la demo con guarda `is_connected` (el reutilizado las trae). Tests: `tests/test_pool_mobs.gd` — 32/32.
- P0-2 UI dirty-driven: `StreamingMobs.mobs_vivos()` es caché exacta invalidada por evento (configurar/instanciar/liberar/reaparecer); minimapa redibuja solo si el jugador se movió (throttle 0.1 s), hay pings, el fade transiciona, el streaming emite instanciado/liberado o late 0.5 s con mobs; brújula igual por yaw/jugador/objetivo/misión. Tests: `tests/test_fase20_ui.gd` — 29/29.
- P0-3 Carga progresiva: `Terreno` y `CiudadLuna` aceptan `construccion_progresiva` (el `_ready` carga datos y encola; `_process` avanza con `progreso_*` y `*_listo` al terminar; `avanzar_construccion()` testeable). `scripts/ui/pantalla_carga.gd` (nueva, capa `UiLayers.CARGA` = 99). La demo parte el arranque: `_ready` rápido + `_al_mundo_listo()` tras el gate (colocar jugador/NPCs, viaje). Tests: `tests/test_fase20_carga.gd` — 36/36.
- P0-5 Budget luces/partículas + harness: `Antorcha` con culling por distancia (`jugador`, 120 m; sin jugador = siempre on); `CiudadLuna.fijar_jugador()` propaga (la demo lo llama); `Clima.tope_gotas` recorta el amount (default 2000 intacto). `scripts/ui/monitor_fps.gd` (nuevo, solo debug) y `tools/bench_fps.gd` (bench headless CPU: 144 FPS, p95 6.9 ms). Tests: `tests/test_fase20_perf.gd` — 10/10.
- Limpieza: una sola demo principal (`fase14_demo.tscn`, `Escenas.JUEGO`); borradas `fase3–12_demo.tscn` + `main.tscn`/`main.gd` (Fase 0). Se conserva `fase9_demo.tscn` como fixture de `test_fase91/92`; `test_fase12_integracion` verifica el contrato sobre `fase14_demo.tscn`.
- Regresión verde salvo 2 preexistentes (título en `test_fase12_integracion`; `NPCS_ESPERADOS` en `smoke_fase15_ciudades`).

*Fin del documento maestro v3.15 — Fase 20 (paquete de rendimiento P0).*

## Fase 21 — Pipeline de audio procedural (2026-09-24)

No había ni un solo SFX (solo `TODO(audio)` en skills y "sin audio" en clima). Sin binarios: todo sintetizado al arrancar.
- `data/sonidos.json` (nuevo): 13 recetas data-driven (forma/freq_ini/freq_fin/duracion/volumen).
- `scripts/audio/sintetizador.gd` (nuevo, puro/testeable): WAV mono 8 bits a 22050 Hz con barrido, envolvente y ataque; ruido determinista.
- `scripts/audio/audio_juego.gd` (nuevo, patrón GameFeel): buses SFX/Ambiente/Musica + pool de 8 voces round-robin + síntesis única al arrancar; API estática no-op sin instancia; `modo_prueba` rutea sin `play()` (el driver dummy pierde playbacks).
- Cableado: golpe/crítico en `Entity.take_damage`, stinger en `Enemy.die`, moneda/recoger en la demo, un SFX por tipo de efecto en `SkillSystem.lanzar` (TODO resuelto); la demo crea el nodo.
- Tests: `tests/test_fase20_audio.gd` — 23/23.

*Fin del documento maestro v3.16 — Fase 21 (audio procedural).*

## Fase 22 — P2 contenido: cadenas por ciudad + 6 jefes de fragmento (2026-09-24)

De 3 a 25 misiones sin tocar el canon (prólogo local; los fragmentos verdaderos siguen en el Acto II).
- Cadena por ciudad (2-3 misiones con `requiere`): Oasis, Volcán, Pico, Mística, Sombra (Culto del Velo), Arena (puerta del Tártaro), Tormenta y Dorada (laterales). Cada Q1 es local, Q2 cruza NPCs (Vex, Bram, Elthar, Sira, Ilya, Aurelio, Sella, Yasmina), Q3 es el jefe.
- 6 jefes data-driven en `enemies.json` (stats/xp400-550/oro/respawn 300 s) + 6 fragmentos materiales en `items.json` + 6 spawns fijos (`grupo: jefe_fragmento`) vía el generador (`tools/generar_spawns_rework.py`, TOTAL 1133; el test lo regenera: lo manual se pierde).
- `QuestDB.requiere()` + estado "bloqueada" en QuestLog (derivada, no guardada, sin bump de save; sin "!" ni oferta ni aceptar hasta entregar el prerrequisito).
- Tests: `tests/test_fase22_cadenas.gd` — 67/67 (bloqueo, cadena oasis, jefe+fragmento, datos, round-trip). Tests viejos actualizados a los conteos (quests 25, items 16, spawns 1133, "!" en ambientales).

*Fin del documento maestro v3.17 — Fase 22 (P2 contenido).*

## Fase 23 — Acto I: cadena principal de Moon Town (2026-09-24)

Cierra el prólogo con Ilya como hub (exige el trío vía `requiere: mensaje_sira`).
- Presentación de armas (hablar Bram + Sira), Primera sangre (6 goblins), La grieta respira (2 ogros + informar), La caída de Piedraceniza (oleada de 6 lobos; el barrio viejo extramuros cae, Moon Town resiste; teaser de los seis ecos = Acto II).
- Recompensas: cota de malla final + 300 oro + 400 XP. Catálogo: 29 misiones.
- Tests: `tests/test_fase23_acto1.gd` — 28/28.

*Fin del documento maestro v3.18 — Fase 23 (Acto I).*

## Fase 24 — Acto II: los seis fragmentos (2026-09-24)

La caza con los jefes ya puestos (sin tocar el canon: son ecos, no los fragmentos verdaderos).
- La llamada del Cristal (hablar Elthar, exige la caída), Los seis ecos (recolectar los 6 fragmentos; se consumen al entregar: Elthar los estudia), Rumbo a la Forja (avisar a Durnan + Bram; teaser del Acto III).
- Catálogo: 32 misiones. Tests: `tests/test_fase24_acto2.gd` — 26/26.

*Fin del documento maestro v3.19 — Fase 24 (Acto II).*

## Fase 25 — Acto III: la Forja del Molde (2026-09-24)

Durnan + Bram forjan el Molde (no el arma: su promesa).
- Carbón de hueso (5 colmillos), Limpiar el yunque (3 ogros), El Molde (estudio de Elthar + defender 4 lobos).
- Catálogo: 35 misiones. Tests: `tests/test_fase25_acto3.gd` — 18/18.

*Fin del documento maestro v3.20 — Fase 25 (Acto III).*

## Fase 26 — Acto IV: El Descenso (2026-09-24)

Karg abre la puerta bajo la Arena (canon: la Arena es la puerta al Tártaro).
- La puerta (hablar Vex, exige el Molde), El Descenso (4 ogros), El Umbral (Susurro + informar a Karg; la puerta duerme otro siglo).
- Catálogo: 38 misiones. Tests: `tests/test_fase26_acto4.gd` — 17/17.

*Fin del documento maestro v3.21 — Fase 26 (Acto IV).*

## Fase 27 — Acto V: La Última Guerra + decisión (2026-09-24)

Cierre del arco (canon: sendas del Arma y Liberty).
- La Última Guerra (6 ogros, exige el Umbral), Senda del Arma (rematar al Campeón: oro de mercenario, final amargo), Senda Liberty (sellar con Elthar: Eco del Verdugo legendario, final canónico).
- Catálogo: 41 misiones, 17 items. Tests: `tests/test_fase27_acto5.gd` — 22/22.

*Fin del documento maestro v3.22 — Fase 27 (Acto V).*

## Fase 28 — Talentos por clase (2026-09-24)

Progresión: 1 punto por nivel, 3 talentos × 4 clases con 3 rangos.
- `data/talentos.json` + `TalentoDB` (patrón SkillDB) + `Talentos` (lógica pura: puntos/rangos, `subir` valida clase/nivel/tope/puntos, mods ×rango con fuente `talento:id`, purga con devolución al cambiar de clase).
- Player otorga el punto en `subio_nivel`; save v8 con bloque `talentos` (retroactivo nivel-1 en v7).
- `PanelTalentos` (capa 30, tecla K, ESC cierra) en la escena principal.
- Tests: `tests/test_fase28_talentos.gd` — 30/30.

*Fin del documento maestro v3.23 — Fase 28 (talentos).*

## Fase 29 — Diálogos con lore (2026-09-24)

Los 20 NPCs hablan del mundo: sira 4, ambientales 4, porteros 3 (ilya 4 y bram 3 intactos por tests viejos).
- Cadenas respiradas en boca de sus NPCs (Devorador, Fundidor, Aullido, Susurro, Campeón, Velo, puerta de la Arena) + canon (Hefesto, Sello, Tártaro).
- Piedraceniza vuelve al canon como barrio viejo (Acto I).
- Tests: `tests/test_fase29_dialogos.gd` — 33/33.

*Fin del documento maestro v3.24 — Fase 29 (diálogos).*

## Fase 30 — Atributos FlyFF + personaje (2026-09-24)

Reparto STR/STA/DEX/INT con 2 puntos por nivel (inspirado en FlyFF Universe).
- `StatBlock.aguante` (STA: +15 vida y +1 defensa por punto; default 0, sin cambios para enemigos/clases/partidas viejas).
- `Player.puntos_atributo` + `repartir_atributo()` (valida, recalcula, sin rellenar); 2 puntos por nivel en `subio_nivel`.
- Save v9 con `puntos_atributo` (retroactivo 2/nivel).
- `PanelPersonaje` (capa 31, tecla H): tabla de derivados + 4 filas con "+".
- Tests: `tests/test_fase30_atributos.gd` — 26/26.

*Fin del documento maestro v3.25 — Fase 30 (atributos).*

## Fase 31 — Sistemas estilo FlyFF Universe (2026-09-24)

H intacto (Fase 30). K/I/C rehechos al estilo FlyFF Universe.

**Skills nivel 1–20 (tecla K):**
- `data/skills.json`: las 32 skills traen `max_nivel: 20`, `power_nivel` y `mana_nivel` (extra por nivel en unidades del efecto principal).
- `SkillSystem`: `puntos_skill` (2 por nivel del jugador), `configurar_clase()` (skills de la clase en 1, ajenas en 0; al cambiar de clase devuelve los puntos invertidos y es no-op si la clase no cambia), `subir_nivel()` con motivos, `power_efectivo()` / `mana_efectivo()` / `cantidad_efectiva()`. Lanzar usa los valores efectivos; las ajenas dan "no_aprendida".
- Curación migrada: `curacion_menor.power = 80`, `luz_sanadora.power = 200`; la fuente efectiva es `power_efectivo` (`efecto.cantidad` queda por compatibilidad).
- Save v10 con bloque `skills` (version 1, puntos + niveles); carga v9 tolerante (skills de la clase en 1).
- `PanelHabilidades` (capa 30, ex-`PanelTalentos`, acción `abrir_habilidades` en K, ESC cierra): pestañas "Skills" (nombre, Nv X/20, números efectivos, botón +) y "Talentos" (migración íntegra de la lógica de la Fase 28).

**Inventario FlyFF (tecla I):** `PanelInventario` rehecho — pestañas Todos / Equipo / Consumibles / Materiales / Misión, rejilla de 6 columnas, celda coloreada por tipo con inicial y cantidad, clic = seleccionar → barra con nombre, descripción y botones Usar/Equipar. `Inventario.listar()` y `PanelInventario.pasa_filtro()` (lógica testeable).

**Equipo paperdoll 12 slots (tecla C):** `Equipo.SLOTS` = arma, escudo, casco, armadura, guantes, botas, pendiente_1/2, collar, anillo_1/2, amuleto. Equipable = campo `slot` válido (no `tipo`); joyería genérica ("pendiente"/"anillo") al primer libre del par, o reemplaza el primero. `to_dict`/`from_dict` genéricos; la UI es paperdoll de 3 columnas con clic = quitar.
- 10 piezas nuevas en `data/items.json` (27 items): escudo_madera, casco_cuero, guantes_cuero, botas_cuero, collar_cobre, pendiente_luna/sol, anillo_poder/sabio, amuleto_guardian.
- Tests: `tests/test_fase31_skills.gd` — 115/115; `tests/test_fase31_equipo.gd` — 55/55; `tests/test_fase31_inventario.gd` — 55/55. Suite completa: 57 suites, 0 fallos.

*Fin del documento maestro v3.26 — Fase 31.*

## Fase 32 — Restyle visual FlyFF (2026-09-24)

Cromo estilo FlyFF Universe en HUD, minimapa, inventario y barra. Solo
visual: lógica, APIs y saves intactos.
- `TemaFlyFF` (`scripts/ui/tema_flyff.gd`): paleta compartida (dorado,
  fondo oscuro, HP rosa-rojo / MP azul / XP lima, marfil) + fábricas
  `marco()`, `fondo_barra()`, `relleno()` y `etiqueta()`.
- HUD: bloque de estado arriba-izquierda (marco dorado con retrato +
  barras HP/MP con valores "actual/máx" + Nv/Oro); XP fina full-width.
- Minimapa: marco dorado doble + pastilla oscura en la etiqueta de región.
- Inventario: marco FlyFF, título dorado claro, celdas con borde dorado
  grueso al seleccionar; barra y libro con el mismo marco.
- Tests: `tests/test_fase32_restyle.gd` — 39/39 (test_fase11: retrato por
  búsqueda recursiva).

*Fin del documento maestro v3.27 — Fase 32 (restyle FlyFF).*

## Fase 33 — Élites y loot raro (2026-09-24)

Caza de botín: los 3 mobs de basura pueden salir élites (los 6 jefes, nunca).
- `data/enemies.json`: bloque `elite` en goblin (5%), lobo (6%) y ogro
  (8%) — ×1.5 fuerza, ×5 XP/oro, tinte dorado y `loot_extra` con equipo
  fase 31 (espada_hierro, armaduras, anillos…).
- `Enemy`: `prob_elite()` / `hacer_elite()` (idempotente, sin mutar el
  caché del JSON) / `sortear_elite()` con el RNG propio; `configurar()`
  resetea (pool) y `reiniciar()` re-sortea cada reaparición. Sin bump de
  save: el élite persiste vía stats.
- Tests: `tests/test_fase33_elites.gd` — 58/58.

*Fin del documento maestro v3.28 — Fase 33 (élites).*

## Fix 33.1 — STA base 15 + creación FlyFF (2026-09-24)

La STA nacía en 0 porque `ClaseDB`/`aplicar_clase` no la plombeaban.
- `data/clases.json`: `aguante: 15.0` en las 5 clases (picos intactos:
  guerrero 45, mago 40, arquero 35 AGI…).
- `ClaseDB.stats_base()` + `Player.aplicar_clase()` con aguante.
- Creación de personaje: "STR %d · STA %d · DEX %d · INT %d" (fuera agilidad).
- Tests fase 11: base/jugador con STA 15 + pantalla de creación.

*Fin del fix 33.1.*

## Fase 34 — StatBlock STR/STA/DEX/INT sin agilidad (2026-09-24)

Reescritura del modelo de stats (pedido de Juan Diego): 15 base en todo
+ 15 de rol por clase, presupuestos iguales de 90 pts.
- Clases: guerrero 30/30/15/15 (frontline: 1150 HP, 45 def, atq 65),
  arquero 30/15/30/15 (DPS: atq 65, crit 17% ×1.8, vel.atq 1.24),
  mago 15/15/15/45 (burst: poder 117.5, 725 maná, 625 HP),
  clérigo 15/30/15/30 (soporte-tanque: 850 HP, 37.5 def, poder 80).
- Fórmulas: ataque 5+STR×2, defensa STR×0.5+STA×1.0, vel.mov plana 6.0,
  vel.ataque por DEX (era AGI); mobs fusionan su AGI en DEX.
- Balance: el DPS físico baja ~28% (ataque 100→65); la defensa de mobs
  también cae. Reequilibrio fino de HP de mobs tras playtest (Fase 35).
  Pendiente: curas escalando con poder (el INT del clérigo hoy solo da maná).

*Fin del documento maestro v3.29 — Fase 34 (stats 4-atributo).*

## Fase 35 — Balance: HP de basura + curas por poder (2026-09-24)

Con la skill `rpg` (fórmula deliberada, números acotados, datos no código).
- Basura con `mult_vida: 0.8` (goblin/lobo/ogro 300→240 HP): el guerrero
  fresco vuelve a 4 golpes (TTK previo a la fase 34, verificado con sonda).
  Vía MOD `balance:vida` (reversible, serializa en el save); jefes intactos.
- Curas ×(1+poder/200) (`SkillSystem.bono_curacion`, puro y testeado):
  clérigo 80→112, mago ×1.59, guerrero ×1.21; tope 2.5×. El INT del
  clérigo ya no solo da maná.
- Tests: `tests/test_fase35_balance.gd` — 28/28.

*Fin del documento maestro v3.30 — Fase 35 (balance).*

## Fase 36 — Paper-doll 3D visible (2026-09-24)

El equipo se ve en el héroe (skills `godot-3d-essentials` + `rpg`).
- `PaperDoll` (`scripts/player/paper_doll.gd`, hijo del Player desde
  `_ready`): pieza procedural por slot ocupado (espada+guarda, escudo,
  casco, coraza, guantes y botas pares, gemas doradas emissive para
  joyería), mallas y materiales COMPARTIDOS por slot.
- Auto-suscripción a `equipo.cambiado`; si el save reemplaza el objeto,
  re-suscribe y reconstruye (comparación por frame, sin polling).
  Puro visual: nunca toca stats.
- Tests: `tests/test_fase36_paperdoll.gd` — 38/38.

*Fin del documento maestro v3.31 — Fase 36 (paper-doll).*

## Fase 37 — Fixes playtest: barra, XP, HP (2026-09-24)

Tres reportes de Juan Diego, cada uno con causa raíz verificada (skills
`systematic-debugging` + `game-ui-ux` + `rpg`).
- **Tecla 4 ejecutaba el 5**: doble vía desincronizada (el Player mapeaba
  1-5 a `ids[]` directo; la barra muestra ataque en el slot 1 + offset).
  Vía única: las numéricas las atiende `BarraAcciones` (disparan el SLOT
  VISIBLE 1-5); el Player ya no escucha `habilidad_*` (`lanzar_skill`
  queda como API). Etiquetas "1/F1".."5/F5".
- **15 kills sin subir**: el mecanismo otorga bien (soda: 15 goblins →
  Nv 4, 600 XP). Defectos reales: la barra XP pintaba acumulados (nunca
  se reseteaba) → ahora muestra el tramo del nivel (`HUD.tramo_xp`,
  puro y testeado); y no había ningún feedback de recompensa → toast
  "+N XP" al matar (`_al_morir_enemigo`, solo asesino = jugador).
- **Mago 1150 → 600**: `aplicar_clase` no emitía señales y el HUD
  (event-driven) quedaba con el valor del guerrero hasta el primer golpe.
  Ahora emite `vida_cambiada` + `mana_cambiado` con los máximos nuevos.
- Extra: test fase35 flaky (sorteo élite 5% en el check de reiniciar) →
  determinista sin bloque élite.
- Tests: `tests/test_fase37_fixes.gd` — 11/11. Suite 100% verde + smokes.

*Fin del documento maestro v3.32 — Fase 37 (fixes playtest).*

## Fase 38 — Rebind de teclas por slot (2026-09-24)

Cierra el plan futuro del legado (§5.3) sobre la vía única de la Fase 37.
- Cada slot se dispara por su acción propia `slot_1..slot_8` (creadas en
  runtime; el `project.godot` no se toca). Defecto = F + número.
- Clic en la etiqueta de tecla → escucha y asigna la siguiente tecla;
  clic derecho → vuelve al defecto; ESC aborta. Aviso "¡En uso!" 1.2 s.
- Conflictos: se rechaza la tecla si la usa otro slot u otra acción del
  proyecto (p. ej. WASD). El gameplay sigue leyendo acciones con nombre.
- Persiste en el save (bloque barra v2: `atajos` con physicals, 0 =
  defecto). Saves v1 cargan con el defecto; overrides en conflicto se
  descartan al defecto. Los atajos sobreviven a la nueva partida.
- Tests: `tests/test_fase38_rebind.gd` — 24/24. Suite 100% verde + smokes.

*Fin del documento maestro v3.33 — Fase 38 (rebind por slot).*

## Fase 39 — Tutorial guiado (2026-09-24)

Onboarding teach-then-test (skills `rpg` + `level-design`): 6 pasos como
datos (mover → atacar → skill → poción → hablar → misión) que avanzan por
eventos y anuncian el siguiente por toast. Nunca bloquea.
- `scripts/tutorial/tutorial.gd`: escucha señales existentes
  (`intencion_atacar`, `skill_usada`, `inventario.cambiado`, `hablar_con`,
  `QuestLog.cambiada`) + posición para el mover. Poción y misión comparan
  foto-antes/ahora (el loot no avanza; matar no acepta).
- Save v11: bloque `tutorial` (paso + hecho). Sin bloque o save < v11 →
  hecho (el veterano que carga no recibe prompts).
- Demo: fase9 crea/conecta; fase11 lo arranca solo en nueva partida; al
  cargar se re-suscribe el inventario nuevo (`refrescar_conexiones`).
- Tests: `tests/test_fase39_tutorial.gd` — 25/25. Suite 100% verde + smokes.

*Fin del documento maestro v3.34 — Fase 39 (tutorial).*

## Fase 40 — Daguero, quinta clase jugable (2026-09-24)

Asesino DEX puro con datos, sin tocar código de sistemas (`rpg`).
- Base 15/15/45/15: crit 23% ×1.95, vel.atq 1.36, 625 HP. (Ataque: ver Fase 42, el daño escala con DEX → 83.75.)
  Tradeoff honesto: pega menos por golpe que el arquero (65) y es tan
  de papel como el mago; compensa con crítico y cadencia cuerpo a cuerpo.
- 8 skills rango corto (skills.json v3): puñalada, golpe_bajo y
  filo_venenoso (debuffs a ataque), danza_dagas (aoe), evasion_sombra,
  instinto_asesino y paso_sombra (buffs), golpe_gracia (2.4 +15% crit).
- 3 talentos (talentos.json v2): sangre_fria, paso_letal, danza_mortal.
- Creación: quinta tarjeta automática (lee `jugables()`); barra, libro,
  save y paper-doll lo toman sin cambios.
- Tests: `tests/test_fase40_daguero.gd` — 34/34. Suite 100% verde + smokes.

*Fin del documento maestro v3.35 — Fase 40 (daguero).*

## Fase 41 — Arena PvE por oleadas (2026-09-24)

10 oleadas data-driven en campo remoto + trofeos locales (`rpg`).
- `data/arena.json` v1: centro (-2000,-8000, spawn salvaje más cercano a
  1391 m), 10 oleadas (3→11 fieras, élites desde la 6), oro/XP extra ×N.
- `scripts/arena/arena.gd`: factory inyectada (pool), descanso 8 s
  (`avanzar(dt)` testeable), derrota al morir, victoria en la 10,
  trofeos mejor_oleada/victorias (save v12).
- Entrada: Maestro Renn en Moon Town (npcs.json v2 + spawn) → "Entrenar"
  en el diálogo → teleport + oleadas; victoria devuelve a la plaza; al
  cargar dentro del campo se vuelve a Moon (anti-atasco).
- Los kills dan su XP/loot y cuentan para misiones de matar.
- Tests: `tests/test_fase41_arena.gd` — 27/27. Suite 100% verde + smokes.

*Fin del documento maestro v3.36 — Fase 41 (arena).*

## Fase 42 — Fixes de playtest: barra, arena y daño por stat (2026-09-24)

Tres reportes de Juan Diego, causa raíz verificada cada uno
(`systematic-debugging` + `rpg`).
- **Doble barra de vida**: el material del frente es *billboard*, y el
  billboard descarta la escala del nodo — el frente se veía de ancho
  completo y desplazado (= 2 barras). Ahora el frente usa malla propia que
  se redimensiona (`center_offset` lo ancla a la izquierda); los
  materiales siguen compartidos (fase 20).
- **"Entrenar" no llevaba a la arena**: `Arena.centro_campo()` no existía
  (`Nonexistent function` en el log) → el teleport nunca corría. Añadido +
  test de regresión. De paso, `TiendaDB` ya no avisa por `tienda_id: null`.
- **Daño que no escalaba con el stat de la clase**: `StatBlock` elige el
  atributo principal de daño (`stat_daño`, campo nuevo en clases.json) y
  tanto `ataque` como `poder` escalan con él. Las skills ya leían
  `ataque`/`poder` (y las curas, `poder`): escalan solas. Coeficientes
  (`StatBlock.COEF_*`): STR 2.0, DEX 1.75, INT 2.5 (poder).

  | Clase | stat daño | Ataque | Poder | HP | Rol |
  |---|---|---|---|---|---|
  | Guerrero | STR | 65 | 65 | 1150 | tanque/frontline |
  | Arquero | DEX | 57.5 | 57.5 | 925 | DPS a distancia (cambió de 65) |
  | Mago | INT | 95 | 117.5 | 625 | burst AoE |
  | Clérigo | INT | 65 | 80 | 850 | soporte |
  | Daguero | DEX | 83.75 | 83.75 | 625 | burst melee (subió de 35) |

  Saves v1 (sin `stat_daño`) → STR; al cargar, la clase re-afirma el suyo.
  El panel de personaje marca el stat principal de tu clase.
- Tests: `tests/test_fase42_dano.gd` — 44/44. Suite 100% verde + smokes.


### Fase 42.1 — Arena: nunca se queda en una oleada (2026-09-24)

Playtest: "solo aparece una oleada y no aparecen más mobs". Causas
corregidas (con reproducción en la escena real + tests):
- **Stall real**: si el último corpse se liberaba sin pasar por `die()` (lo
  recycle el streaming/pool), `_espera` nunca se activaba y la arena
  quedaba colgada para siempre. Ahora `avanzar()` poda referencias
  inválidas (`vivos()`) y paga la recompensa desde un único sitio
  (`_pagar_oleada`, idempotente) → la oleada siempre avanza.
- **Oleada atascada con mobs vivos**: tras 12 s los supervivientes se
  teletransportan junto al jugador y le entran en aggro (`ayuda_oleada`).
- **Hueco de feedback**: los toasts dicen cuántos enemigos son y cuánto
  falta para la siguiente (descanso 8 s → 5 s).
- **Oleada vacía** (factory sin mobs) no se queda esperando: pasa a la
  siguiente. Los cadáveres vuelven al pool al cerrar cada oleada.


## Fase 43 — Contenido regional (2026-09-24)

El mundo tenía 10 regiones con banda de nivel y 1133 spawns, pero TODOS de
la misma fauna (goblin/lobo) y sin escala: "Nivel 45-70" era decorativo.
Ahora cada región tiene su identidad y su poder.
- **Escala por región** (`data/regiones.json` → `escala`): `stats`, `vida`,
  `defensa`, `xp`, `oro`. La `defensa` crece MÁS LENTO que vida/ataque a
  propósito: con mitigación por ratio, si todo escalara igual el TTK se
  disparaba (114-132 golpes en el endgame). Curva validada con sonda:
  TTK 4 → 23 golpes (3.6 s → 20 s), 4-7 kills por nivel, mobs de 31 a
  146 dps. Hook: `Enemy.aplicar_escala()` la llama el streaming (la arena
  conserva su curva propia).
- **10 mobs regionales** (`data/enemies.json`): escorpión de dunas, slog y
  gólem de ceniza, yeti, araña y espectro del velo, carnicoro, mimo,
  centinela dorada y sombra vacía. Base stats deliberadamente cerca de la del
  goblin (la identidad viene del comportamiento: rango, cadencia, aggro,
  loot y `stat_daño`); la potencia la pone la región.
- **10 items de loot regional** (`material`): carina, ascua, núcleos,
  seda, ecos, perla, lamento, lingote y sello.
- **Generador actualizado** (`tools/generar_spawns_rework.py`): la regla
  pasó de NIVEL→arquetipo a REGIÓN→arquetipo (62% mob de identidad + 38%
  mezcla clásica), determinista (mismo SHA) y con el campo `region`.
  Los tests de spawns/terreno ahora validan el contrato nuevo.
- El banner de región dice a qué esperar: nivel + nombres de sus enemigos.
- Tests: `tests/test_fase43_regional.gd` — 92/92. Suite 100% verde + smokes.


## Fase 44 — Herrería: profesiones (2026-09-24)

Los 17 materiales que caían de la Fase 43 no servían para nada: primero
profesión de la lista del legado, la que da un sumidero de oro y propósito
al loot.
- `data/recetas.json` (10 recetas): resultado + materiales + nivel de
  herrero + oro. Forja **instantánea** (sin timers), consume materiales y
  oro, **no da XP** y **no toca stats** (el equipo sigue aplicando sus mods).
- `RecetasDB` (datos) + `Herreria` (lógica pura: `puede_forjar`/`forjar`/
  `estado_materiales`) + `PanelHerreria` (UI que solo lee y llama a la API).
- **Dos herreros con identidad**: Bram (Moon Town, 7 recetas generales) y
  Durnan (volcán, 3 de fuego). Botón "Forjar" en el diálogo (solo ellos).
- **10 piezas** que usan los materiales regionales: daga de carina, lanza
  de hielo, daga de seda, guantes del umbral, amuleto de perla, botas del
  lamento, hoja de ascua, martillo de gólem, coraza de la centinela y foco
  vacío. Son **sidegrades**: empujan el stat principal de una clase
  (crítico, vel. de ataque, maná) a cambio de menos ataque plano que el
  `verdugo_eco` del élite (verificado por test: ninguna lo supera en todo).
- Sin bloque de save nuevo: materiales y equipo ya viajan en el inventario.
- Tests: `tests/test_fase44_herreria.gd` — 132/132. Suite 100% verde.

## Fase 45.1 — F5 ve todo (2026-09-24)

La regla de trabajo del remake es que **abrir el proyecto y darle a F5 debe
enseñar todo lo que hay hecho**, no una menú desde el que hay que navegar.

- **Main scene = `scenes/demo/fase14_demo.tscn`** (antes
  `scenes/titulo/pantalla_titulo.tscn`). F5 entra directo al mundo jugable:
  héroe en la plaza de Moon Town, HUD, barra de 8 skills, minimapa, 6 mobs de
  prueba y las vetas. Como `DatosSesion.continuar` es `false` por defecto, la
  rama de "nueva partida" se cumple sola y **el tutorial de la fase 39 arranca
  automáticamente** (6 pasos por toast: mover, atacar, skill, poción, hablar
  con Ilya, aceptar misión). La pantalla de título y la creación de personaje
  siguen existiendo (`scenes/titulo/pantalla_titulo.tscn`) y no se borran:
  solo dejan de ser el punto de entrada de F5.
- **Veta de prueba en la plaza** (`veta_prueba_cobre`, `grupo: prueba_mineria`,
  13 vetas en total): a **27 m** del punto de aparición, 22° a la izquierda de
  la vista, para que la minería se vea y se pueda probar sin caminar. Mismo
  criterio que el pack de 6 mobs de prueba de la fase 18.2; se exime de las
  reglas de distribución y los tests lo tratan aparte.
- `GestorVetas` avisa por consola cuántas vetas tiene cerca al arrancar
  (`[Fase45] minería: 13 vetas registradas, 1 en el mapa cerca`).
- Tests: `tests/test_fase45_mineria.gd` — 335/335. Suite 100% verde (70
  suites + 4 smokes).

## Fase 45.2 — Los avisos se ven (2026-09-24)

El tutorial existía (fase 39, 6 pasos) y **nunca se vio**. Dos bugs
encadenados, ambos de "avisos", no del tutorial:

1. **El feed de avisos colgaba del panel cerrado.** El `CanvasLayer` del
   toast (capa 15, el feed global) era hijo de `PanelMisiones`, que arranca
   `visible = false` (§9: los paneles nacen ocultos). Ningún aviso se veía
   **nunca**: ni el tutorial, ni los avisos de arena, ni los de viaje rápido.
   Nadie lo cazó porque el test de la fase 39 le pasa un `Callable` de
   mentira y nunca monta el panel real. Ahora el layer cuelga de la **escena**.
2. **`add_child` directo fallaba.** Al colgarlo de la escena, el `add_child`
   desde el `_ready` del panel se estrella con *"Parent node is busy setting
   up children"* (la escena está añadiendo sus propios hijos): el layer se
   quedaba **huérfano**, con el padre a null. Va con `add_child.call_deferred`.
3. **El tutorial arrancaba durante la pantalla de carga.** `empezar()` se
   llamaba en el `_ready` (fase 11), con el mundo a medio construir: sus
   avisos se perdían detrás del velo de carga y el paso "mover" **se completaba
   solo**, porque el arranque recoloca al jugador en la plaza (se entraba al
   paso 1 sin haber jugado). Ahora arranca en `_al_mundo_listo()`, con el
   mundo construido, el velo fuera y el jugador en su sitio.

Verificado con una captura del frame real en que el aviso se enciende
("Muévete con WASD o clic izquierdo" sobre la barra de acciones) y con
`tests/test_fase45_2_toast.gd` — 15/15, que monta el panel y el tutorial
**reales**. Suite 100% verde (71 suites + 4 smokes).

## Fase 46 — Manual de ayuda: controles y mecánicas (2026-09-24)

Había 27 acciones en el Input Map y **ni una página que las explicara**: ni el
jugador ni el reviewer tenían a mano cómo se juega.

- **`PanelAyuda`** (CanvasLayer propio, capa 32) con **dos pestañas**:
  - **Controles**: se generan del **Input Map en runtime**
    (`InputMap.get_actions()` + `OS.get_keycode_string()`), ordenados por tecla.
    Deliberadamente **no** es un JSON: así no puede desincronizarse ni del
    rebind por slot de la fase 38 ni de las teclas que se añadan después.
  - **Mecánicas**: 9 secciones, 26 entradas, en `data/mecanicas.json` (texto
    editorial → datos, §9.4): primeros pasos, movimiento y cámara, combate y
    selección, skills y barra, inventario/equipo/talentos/personaje, misiones y
    NPCs, profesiones (minería y herrería), mundo/viaje/regiones, arena y
    guardado.
- **Se abre con `?`** (acción `abrir_ayuda` del Input Map, tecla 47: sirve `/`
  y también `?`) y se cierra con ESC o con la misma tecla. Botón **Ayuda** en
  la pantalla de título.
- **Escena propia** `scenes/ui/panel_ayuda.tscn` (`abrir_al_arrancar = true`):
  se puede correr **sola con F6** desde el editor para revisarla sin entrar al
  juego. En la demo se instancia con el flag a `false`.
- **Adaptativo**: el panel va anclado a pantalla completa con margen, nunca
  centrado con tamaño fijo: con una ventana pequeña se encoge en vez de salirse.
- La UI solo lee: no toca stats, inventario ni oro (verificado por test).
- **Bug que el manual destapa** (arreglado en la fase 47, no aquí): `F9` está
  en `guardar_partida` **y** en `barra_6`, y `F10` en `cargar_partida` **y** en
  `barra_7`. La barra es F4–F11, no F1–F8 como dice el spec. El manual lo
  muestra tal cual es, sin maquillar.
- Tests: `tests/test_fase46_ayuda.gd` — 148/148. Suite 100% verde (72 suites +
  4 smokes).

## Fase 46.1 — El botón "?" del manual (2026-09-24)

El manual existía pero **solo se abría con una tecla que no se ve**: el
jugador no encontraba el signo `?` en ninguna parte. Una tecla invisible no se
aprende.

- **Botón `?` en el HUD**, esquina superior derecha (la única libre: el marco
  de estado vive arriba a la izquierda, la brújula arriba en el centro y el
  minimapa abajo a la derecha), con la misma piel dorada del resto y
  `tooltip` con la tecla. 38×38 px, pulsable.
- El HUD solo emite `ayuda_solicitada` (es un botón, no un sistema: no toca
  nada); la **demo** es quien abre el `PanelAyuda`. Igual idioma que el resto
  de señales de la fase 9.
- Tests: `test_fase46_ayuda` — 157/157 (incluye que el botón existe, se ve,
  tiene el tamaño suficiente, está anclado a la esquina y pide la ayuda al
  pulsarlo). Suite 100% verde (72 suites + 4 smokes).

## Fase 48 — Tabla de anclajes + presupuesto de GPU (2026-09-24)

Las dos piezas que faltaban para que entrar arte 3D sea una **fase de datos** y
no una reescritura. Además, Juan Diego **autorizó los 85 GLB de Meshy**
(licencia CC0/CC-BY, nunca Blizzard): la regla de `AGENTS.md` queda
actualizada y el bloqueo de §7.5 levanta.

- **`data/anclajes.json`: la tabla de anclajes**, la que el spec prometía desde
  la fase 43 y que no existía. Un registro por slot de `Equipo.SLOTS` (12) con
  `{anclaje, mesh_path, offset, rotacion, escala, tinte, forma}`:
  - `anclaje`: el **hueso del futuro modelo** donde cuelga la pieza
    (`Hand.R`, `Head`, `Chest`, `Neck`, `Foot.L`...).
  - `mesh_path`: la ruta del GLB. **Vacío = respaldo procedural**; con ruta =
    modelo (y si la ruta no existe, avisa y cae al respaldo: el juego no se
    rompe por un asset que falta).
  - `forma`: lo que se dibuja mientras no haya modelo (caja, esfera, par,
    espada de 2 piezas).
- **`PaperDoll` deja de tener offsets, colores ni formas hardcodeados**: los
  lee de la tabla. Los nodos conservan sus nombres (`arma/Hoja`, `guantes/*_der`)
  y las posiciones son las de siempre (la regresión de la fase 36 sigue verde).
  **Meter un modelo es rellenar `mesh_path` en el JSON.**
- **`AnclajesDB`**: carga tolerante, ids en orden, accesores por slot y
  `slots_sin_malla()` = la cola de trabajo de la fase de arte (hoy: los 12).
- **Presupuesto de render, que no existía** (§9.5 solo decía "mallas
  compartidas" y la fase 20 solo fijó el p95 de CPU). `MedidorGPU` mide la
  **GPU real** —draw calls, triángulos, objetos, memoria de vídeo y tiempo de
  frame— y `tools/bench_gpu.gd` lo ejecuta **sin `--headless`** (con drivers
  dummy el render da 0, que es justo lo que pasaba con `bench_fps.gd`).
  - **Medido en la fase 48** (Moon Town, 6 mobs de prueba, vetas de la plaza,
    RTX 3050 Ti, 1280×720): **233 FPS · 4,36 ms de frame · p95 4,55 ms ·
    443 draw calls · 285k triángulos · 150 MB de vídeo**.
  - Presupuesto declarado: p95 ≤ 16,7 ms (el número duro de la fase 20),
    ≤ 1200 draw calls, ≤ 900k triángulos, ≤ 1 GB de vídeo. Margen de 2,7× en
    draw calls: 85 modelos a ~10 draw calls cada uno lo saturarían, así que el
    presupuesto avisa antes de que se rompa.
- Tests: `tests/test_fase48_anclajes_bench.gd` — 238/238. Suite 100% verde (73
  suites + 4 smokes) + la regresión del paper-doll de la fase 36.

## Fase 47 — Las teclas de la barra decían mentira (2026-09-24)

La Fase 46 dejó al descubierto algo peor que una colisión: **las etiquetas F
de la barra de acciones no correspondían con ninguna tecla real**.

- Los 8 slots estaban ligados en el Input Map a **F4–F11**, mientras el HUD
  los rotula `"1/F1", "2/F2" … "4/F4" … "F8"`. O sea: **las ocho etiquetas F
  mentían**, F1–F3 no hacían nada, y F9/F10 disparaban a la vez *guardar* /
  *cargar* **y** un slot (el 6 y el 7).
- **Arreglo**: `barra_1..8` pasan a **F1–F8** (4194332–4194339). Con eso las
  etiquetas dicen la verdad, F1–F3 dejan de estar muertas, y **F9/F10 quedan
  solo para guardar y cargar**. Colisiones de teclas: 0.
- **El invariante que faltaba** (`tests/test_fase47_teclas.gd`, 41/41): ninguna
  tecla del juego puede estar en dos acciones a la vez, y cada etiqueta del
  HUD tiene que coincidir con la tecla real de su slot. Nadie lo tenía: cada
  test miraba su propio trozo y por eso el bug pasó 45 fases.
- El manual de la Fase 46 (datos y nota del panel) actualizado a F1–F8.
- Suite 100% verde (74 suites + 4 smokes).

## Fase 48.1 — `models/` con puerta de licencia (2026-09-24)

Para que Juan Diego pueda meter los GLB a mano, con reglas y sin sorpresas.

- **`models/`** con `README.md`: qué va ahí, qué no (el terreno **no**: es el
  heightmap de `data/terreno.bin`; y nada que no sea `.glb`/`.gltf`), la
  convención de huesos para las animaciones (`Hand.R`, `Head`, `Chest`,
  `Neck`, `Foot.L/R` y clips `idle/walk/attack/die` nombrados como la FSM) y
  el presupuesto de render de la fase 48.
- **`data/modelos.json`**: manifiesto de los modelos. Un `.glb` sin entrada
  aquí **no pasa los tests**, igual que un `.glb` con licencia que no sea
  CC0/CC-BY. Es la puerta automática de la regla dura §7.5 (nunca Blizzard).
- **`test_fase48` ampliado** (242/242) con esa comprobación en los dos
  sentidos: `models/` y el manifiesto tienen que decir lo mismo, y cada
  `mesh_path` de la tabla tiene que apuntar a un archivo que exista y esté
  declarado. Verificado metiendo un `.glb` falso: el test falla, y también
  falla al declararlo con `CC-BY-NC`.
- Meter un modelo son 3 pasos: copiar el `.glb`, registrarlo en el manifiesto,
  y poner su ruta en el `mesh_path` de `data/anclajes.json`.
- Suite 100% verde (74 suites + 4 smokes).

*Fin del documento maestro v3.47 — Fase 48.1 (models/ con puerta de licencia).*

## Fase 49 — El primer modelo 3D real dentro del juego (2026-09-26)

Juan Diego autorizó los 85 GLB del release `modelos-3d-v1` (CC0/CC-BY, prohibida
cualquier cosa de Blizzard). Antes de tocar el juego se midió el pack entero:
**96.760.060 triángulos, 3,25 GB, 255 texturas, 0 esqueletos, 0 animaciones y 0
nodos con nombre.** Todos son exports estáticos de Meshy de un nodo, y uno solo
ya revienta el techo de 900k triángulos por entidad de la fase 48. Ninguno es
usable tal cual: esta fase construye el camino y mete UNO de verdad.

- **`tools/preparar_modelo.py`** (Blender headless, portable en `~/Tools/blender`):
  importa el `.glb`, une las mallas, decima en 3 pasadas hasta el objetivo, lo
  **posa en el suelo** (min z = 0 y centrado en x/y, que si no el bicho aparece
  enterrado porque Meshy exporta centrado en el origen) y exporta. El piloto:
  **1.704.220 → 20.000 triángulos en 37 s**, 1,90 m de alto, 8,2 MB.
- **`data/enemies.json`**: el arquetipo declara `"modelo"` y `"modelo_escala"`.
  Solo datos; el código no menciona ningún archivo. `goblin` usa de momento
  `bandido.glb` (1,18 m con escala 0,62) — el mapping es **provisional**: los
  nombres del pack son del legacy y no coinciden con los 19 arquetipos, y por eso
  se cambia en el JSON y no en el código.
- **`scripts/enemy/enemy.gd`**: `configurar()` sustituye la malla de `Cuerpo` por
  la del modelo. No cambia el nodo (se llama igual), así que la colisión, el
  indicador de selección y `mostrar/ocultar_cuerpo` siguen funcionando. Cosas
  que este diseño resuelve a propósito:
  - **el pool**: siempre devuelve el nodo a la cápsula ANTES de decidir. Sin ese
    reset, un goblin con modelo se convertiría en el cuerpo del siguiente
    arquetipo que pasara por el pool.
  - **una malla en memoria, N instancias**: la malla se cachea por ruta en una
    `static var` (fase 12.1), no se copia por enemigo.
  - **sin `material_override`**: un tinte plano se comería la textura, así que un
    arquetipo con modelo se dibuja con el material del modelo. Los que no lo
    traen se siguen tiñendo igual que siempre.
  - **asset ausente**: si el `.glb` no está, avisa y cae a la cápsula. El juego no
    se rompe por un archivo que falte.
- **`test_fase49_modelos_3d.gd`** (34/34): manifiesto y licencias, el modelo
  declarado por datos, la sustitución de la malla, la textura a la vista, la
  malla compartida, el reset del pool, el camino del asset ausente, el techo de
  triángulos por entidad y el contrato de "pies en el suelo".
- **Presupuesto de GPU, con el modelo dentro** (pasada con la ventana enfocada,
  600 muestras): **206,6 FPS · p50 4,76 ms · p95 5,56 ms · max 8,43 ms · 435 draw
  calls · 279.637 primitivas · 270,8 MB · OK**. Los tres goblins de la plaza
  aportan 1 draw call y 20k triángulos cada uno.
- **Texturas**: por defecto en **Lossless** (`compress/mode=0`). Con VRAM
  Compressed el modelo baja de 271 a 214 MB, pero el material obliga a convertir
  `RGB8 → RGBA8` en tiempo de carga y no se ha podido medir en condiciones
  limpias; el ahorro no compensa el riesgo mientras el presupuesto sea de 1 GB.
- **`tools/bench_gpu.gd`**: ahora avisa si la ventana **no tiene el foco** y
  guarda `ventana_en_foco` en el informe. Sin eso, bajo Wayland el compositor
  estrangula el presenting a ~7,5 Hz (133 ms clavados en cada frame con la GPU al
  0%) y el veredicto sale "FUERA DE PRESUPUESTO" por algo que no es el juego: es
  un artefacto de medir sin foco, no una regresión.
- Suite 100% verde (75 suites + 4 smokes).

*Fin del documento maestro v3.48 — Fase 49 (el primer modelo 3D real en el juego).*

## Fase 49.1 — Esqueleto y los cuatro clips de la FSM (2026-09-26)

El modelo de la fase 49 se quedaba quieto: era una malla con textura, sin un
hueso. Esta fase le pone esqueleto y los cuatro clips que la FSM ya nombra, y
conecta la animación al estado del enemigo.

- **`tools/rig.py`** (módulo hermano de `preparar_modelo.py`, se activa con el
  cuarto argumento en 1): esqueleto humanoide de **19 huesos** y los cuatro
  clips **procedurales** —sin Mixamo, sin keys escritos a mano, el mismo
  resultado en cada corrida—:
  - Nombres pensados para que el modelo **sirva tal cual al paper-doll**: los
    7 anclajes de `data/anclajes.json` (`Chest`, `Neck`, `Head`, `Hand.L/R`,
    `Foot.L/R`) están en el esqueleto. Se comprueba en el test.
  - `idle` 2,04 s (respiración y balanceo, cicla), `walk` 1,04 s (piernas y
    brazos alternos, con rodilla que solo dobla hacia atrás, cicla), `attack`
    0,83 s (carga, tajo y recuperación, cicla) y `die` 1,21 s (rodillas que
    ceden y torso al suelo, **no** cicla: un cadáver que se levanta solo).
  - El esqueleto se escala a la altura real de cada modelo (el pack va de 0,9
    a 3,8 m), así que sirve para los humanoides sin tocar nada.
- **Los pesos van por envolvente, no por "bone heat"**: el solucionador de
  heat falla en headless (`failed to find solution for one or more bones`) y
  deja la malla **sin un solo peso**, o sea que el `.glb` salía sin skin: 19
  huesos y 4 clips de adorno, y el modelo sin deformar. La envolvente solo
  necesita un radio por hueso (`ENVOLVENTE`), es determinista y no necesita
  ventana. El script avisa si se queda fuera más del 5% de la malla.
- **`scripts/enemy/enemy.gd`**: el modelo se cuelga **instanciado** como nodo
  `Modelo`, en vez de cambiar la malla de `Cuerpo`. Es lo único que funciona
  con piel: una malla skinned pegada a un `MeshInstance3D` suelto no se deforma
  porque necesita el esqueleto en la misma rama. De ahí:
  - `estado` pasa a ser **propiedad**: los 9 sitios que lo asignan pasaban por
    el mismo setter, que pone el clip que toca. Setear el mismo estado no
    repite el clip (el pool reinicia estados en cada `_ready`).
  - `idle`/`walk`/`attack` ciclan y `die` no, marcado una vez sobre el recurso
    `Animation` compartido.
  - El pool desmonta el modelo con `remove_child` + `queue_free`: con solo
    `queue_free` el nodo sigue en el árbol un frame y el pool ve dos cuerpos.
- **`scripts/core/cuerpo.gd`** (nuevo): el flash de daño y los FX de skill
  tiñen `Cuerpo`, que con el rig ya no es un hijo directo. El helper resuelve
  la malla visual (cápsula o la que cuelgue de `Modelo`) y los dos sistemas lo
  usan; el jugador y los NPC siguen por la vía rápida.
- **`tests/fixtures/estatico.glb`** (53 KB, 800 triángulos, sin piel ni
  textura): los otros 84 modelos del pack son estáticos y el único asset real
  del repo es riggeado. El fixture cubre esa rama sin meter 16 MB de más.
- **`test_fase49_modelos_3d` ampliado (76/76)**: esqueleto con los 7 anclajes,
  `Skin` con bones, los 4 clips, el clip correcto por estado, el bucle de cada
  uno, que setear el mismo estado no reinicie la animación, la rama estática
  sin `AnimationPlayer`, el reset del pool y el contrato de pies en el suelo.
- **Presupuesto de GPU, con el rig puesto** (3 pasadas seguidas, 90 muestras,
  sin tirones: `veredicto OK`): **p50 4,17 ms · p95 4,17–4,24 ms · 424 draw
  calls · 263.070 primitivas · 258 MB**. Sale **más barato** que el modelo
  estático (435 draws, 279.637 primitivas, 271 MB): el esqueleto no cuesta
  frame, y el `AnimationPlayer` no añade draw call.
- El goblin con modelo se movió a **(36, -21)**: la zona segura es un radio de
  40 m desde el **origen**, no desde la plaza, así que fuera de ella, dentro
  del encuadre inicial y a más de 10 m (el radio de aggro) el punto más
  cercano posible está a 74 m. Es la mitad de los 132 m del pack original.
- Suite 100% verde (75 suites + 4 smokes).

*Fin del documento maestro v3.49 — Fase 49.1 (esqueleto y clips de la FSM).*

## Fase 50 — El jugador con modelo de clase (2026-09-26)

El jugador era una cápsula y es lo único que se mira el 100% del tiempo. El pack
trae 4 modelos `clase-*` que encajan con 4 de las 5 clases, y para `guerrero`
(no hay `clase-guerrero`) se eligió `job-luchador-guerrero-j1` de los cinco
candidatos del árbol de guerreros: es el tier 1, el que más se lee como clase
base sin parecerse al paladín del clérigo.

| Clase | Modelo del pack | Altura en el juego |
|---|---|---|
| arquero | `clase-arquero.glb` | 1,71 m |
| daguero | `clase-dagero.glb` (el pack lo llama "dagero") | 1,71 m |
| mago | `clase-mago.glb` | 1,71 m |
| clerigo | `clase-paladin.glb` (el pack no tiene clérigo) | 1,71 m |
| guerrero | `job-luchador-guerrero-j1.glb` | 1,71 m |

- **`data/clases.json`**: cada clase declara `modelo` + `modelo_escala` (0,90:
  la malla mide 1,90 m y la cápsula del jugador 1,7, así el paper-doll y la
  tabla de anclajes se quedan donde estaban). Datos, no código.
- **`scripts/player/player.gd`**: `aplicar_clase()` cuelga el `.glb` entero
  como `Modelo` (una malla con piel en un `MeshInstance3D` suelto no se deforma)
  y apaga la cápsula `Cuerpo` —que NO es la que colisiona: la colisión es el
  nodo `Colision`— para que no salga un tubo amarillo encima. Los clips los
  manda `_actualizar_animacion()` con los mismos hechos que el movimiento:
  quieto, caminando, tajo (0,32 s tras golpear, no el frame del golpe) y
  muerto. `idle`/`walk`/`attack` ciclan, `die` no.
- **El equipo no se movió de sitio**: `PaperDoll` cuelga del jugador, no del
  cuerpo, y sus offsets son absolutos en metros (casco a 1,58; mano a 1,15). Con
  el modelo a 1,71 m siguen cayendo donde tocaba, y el test lo comprueba. Lo
  que NO hay todavía es que el equipo siga a la animación (huesos): eso es la
  50.1.
- **El rig tuvo que arreglar tres cosas** para conThese models (y de paso al
  bandido), todas medidas y documentadas en `AGENTS.md`:
  1. Los huesos del brazo se construían con la longitud **con signo cambiado**
     (codo − hombro = −0,33), así que la cadena acababa **en la cabeza**: los
     pesos se los comía el muslo, al girar el brazo no se movía nada y al
     animar se retorcía el casco.
  2. Ni el "bone heat" (falla en headless y deja la malla sin peso) ni las
     envolventes de Blender servían: con el pecho y la cadera grandes, el
     brazo salía con Chest 34% / Hips 33% / Thigh 31% y se movía 2° cuando se
     le pedían 23. Ahora **los pesos se calculan a mano** (distancia a cada
     hueso, caída cuadrada, los 4 más cercanos, normalizados).
  3. La pose del brazo es un **dato por asset** (`pose_brazos` en
     `data/modelos.json`, quinto argumento del script), no se deduce de la
     silueta: con faldones y capas la relación ancho-pecho/ancho-cintura no
     distingue una T de un brazo colgando (el luchador en T daba 1,02).
- **`test_fase50_clases_modelos.gd` (88/88)**: las 5 clases con modelo
  declarado y en el manifiesto, esqueleto + skin + los 4 clips, el clip
  correcto por estado, que no se reinicie al repetir estado, que el clip
  **avance** de verdad (con frames reales, no solo la llamada), que cambiar de
  clase dos veces deje un solo `Modelo`, que el modelo mida lo que la cápsula y
  que los anclajes del equipo caigan dentro, y que una clase sin modelo no
  deje cuerpo colgando.
- **Presupuesto de GPU con el jugador con modelo** (3 pasadas limpias,
  veredicto OK): **p50 4,17–4,55 ms · p95 4,55–4,76 ms · 439 draw calls ·
  410.770 primitivas · 335 MB**. Sigue dentro de 1.200 / 900k / 1 GB.
- `models/` pesa **104 MB** con los 6 modelos (los 3 `.jpg` que Godot extrae de
  cada `.glb` son la mitad). El release sigue siendo la distribución del pack;
  el repo solo lleva lo que el juego usa de verdad.
- Suite 100% verde (76 suites + 4 smokes).

*Fin del documento maestro v3.50 — Fase 50 (el jugador con modelo de clase).*

## Fase 50.1 — Los modelos andaban de espaldas y con un brazo arriba (2026-09-26)

Playtest de Juan Diego sobre la fase 50: *"cuando camina, camina de espaldas, y
lo mismo pasa con los demás modelos"* y *"los brazos extendidos, tiene uno
levantado y otro más abajo"*. Los dos son de la misma zona y los dos-salieron
al fixes de la fase 50.

- **Andaba de espaldas (jugador y enemigos).** Los `.glb` del pack miran al
  **+Z** de Godot, porque el exportador mapea blender (X, Y, Z) -> gltf
  (X, Z, -Y) y la malla de Meshy mira al -Y de Blender. El forward del juego es
  **-Z**, así que el modelo entero iba al revés: la cara, la marcha y la
  persecución, en el mismo sentido equivocado.
  - El arreglo **no es girar el esqueleto**. El esqueleto tiene que mirar
    igual que la malla (por eso `tools/rig.py` sigue en -Y): si se gira, el
    ciclo de marcha se mueve al revés *respecto al personaje* y sale un
    moonwalk igual de feo. Se gira **al colgarlo**, con una constante
    compartida: `Cuerpo.GIRO_MODELO = PI`, en `scripts/core/cuerpo.gd`, que
    usan tanto `player.gd` como `enemy.gd`. Es una constante y no un dato por
    asset porque los 85 modelos salen de la misma cadena de exportación.
  - **Tests**: `test_fase49` (138) y `test_fase50` (90) comprueban que el
    modelo se cuelga con esa vuelta y que su **+Z local** (la cara) queda
    apuntando al frente de la entidad. La comparación es horizontal a
    propósito: el jugador y los enemigos se inclinan para pegarse al terreno y
    ese declive no dice nada sobre hacia dónde andan.
- **Un brazo arriba y otro abajo.** La base que baja los brazos de la pose en A
  a una natural ponía **signos opuestos por lado** en dos sitios a la vez
  (la constante y el factor de espejo), que se cancelaban: los dos lados
  acababan con la **misma** rotación numérica, y en huesos espejados eso deja un
  brazo arriba y el otro abajo. Ahora la magnitud es la misma para los dos y
  el espejo lo hace un único factor. Verificado en render: los dos brazos
  colgando, y el reposo natural más cerrado (0,12 rad).
- Los 6 modelos del repo se re-riggean con el esqueleto en su sitio (el -Y de
  la malla) y la pose de brazos corregida.
- Sin cambios de rendimiento (es una rotación y un ajuste de pose): 439 draw
  calls, 410.770 primitivas, 339 MB, igual que en la fase 50.
- Suite 100% verde (76 suites + 4 smokes).

*Fin del documento maestro v3.51 — Fase 50.1 (el frente del modelo y los brazos).*

## Fase 50.2 — Las manos dejan de estar abiertas (2026-09-26)

Tercer aviso del playtest sobre los modelos: *"sigue con las palmas abiertas
hacia abajo"*. Es lo único que quedaba de la pose.

- **El problema es geometría, no pose.** Los `.glb` del pack traen la palma
  abierta y los dedos separados, y los dedos del Meshy **son malla, no
  huesos**: ningún giro de muñeca puede cerrarlos. Con una pose sola no había
  manera, y el giro de muñeca solo (0,75 rad) los dejaba igual.
- **Dos cosas juntas** en `tools/rig.py`:
  1. `cerrar_manos()`: colapsa los vértices de la mano hacia un punto de puño,
     con más fuerza en la punta que en la muñeca (que se queda donde está,
     donde hace falta el anticuerpo). Se hace **antes** de calcular los pesos,
     para que la forma cerrada forme parte de la deformación. Con los 6 modelos
     del repo coge entre 431 y 1.594 vértices (de 26k-29k), y avisa si se
     quedan por debajo de 120: eso significaría que la selección no ha
     encontrado la mano en ese modelo.
  2. `TWIST_MANOS = 0.95` rad: la muñeca gira sobre su propio eje y la palma
     mira al muslo en vez de al suelo.
- **El primer intento de colapso se comió medio personaje** (4.931 vértices,
  incluido el otro brazo y la pierna, y salió un artefacto negro). Lo que lo
  arregla no es el algoritmo sino el filtro: solo vértices a menos de
  `RADIO_MANO` (19 cm) de la muñeca, por delante de ella y por debajo del
  pecho. Está escrito en el docstring para que no se repita.
- **El límite honesto**: esto no es un puño real, es una mano cerrada de
 C ago. Para un puño de verdad hay que riggear los dedos (5 huesos por mano, 10
  más de esqueleto) y en vez de colapsar vértices, doblarlos: es un trabajo
  grande y queda para cuando el resto del arte esté cerrado.
- Los 6 modelos re-riggean con esto. Sin coste de rendimiento (mover vértices no
  cambia triángulos): 439 draw calls, ~410k primitivas, 339 MB.
- Suite 100% verde (76 suites + 4 smokes).

*Fin del documento maestro v3.52 — Fase 50.2 (las manos cerradas).*

## Fase 50.3 — Las manos, esta vez sí (2026-09-26)

Segunda vuelta del playtest: *"las manos siguen extendidas"*. La fase 50.2 no
había arreglado nada: **el colapso iba a la ropa**.

- **El bug, en dos partes.** `cerrar_manos()` calculaba la muñeca con las
  proporciones del esqueleto, y en el lado derecho **no reflejaba el hombro**:
  la muñeca salía en x = −0,17 en vez de −0,51. Con ese error el colapso apretaba la **falda y el cinturón** (faldas se deforman),
  no la mano. Y con eso, la izquierda tampoco se cerraba bien: los dedos están
  a 21 cm de la muñeca estimada y el radio del selector eran 19 cm, así que la
  punta de los dedos quedaba fuera.
- **La solución es no calcular la mano: detectarla.** `detectar_manos()` la
  localiza **por la forma de la malla** — los dedos son lo más alejado en X del
  cuerpo, por debajo de los hombros — y devuelve su centro y su radio. Medido
  en los 6 modelos del repo: a `|x| > 0,85 · x_max` la nube mide 0,09–0,17 m,
  que es una mano; a `0,60` mide 0,27 m, que es el antebrazo.
- **Guarda de ropa**: si la nube es más ancha de 0,12 H, no es una mano sino una
  túnica o una capa. El **mago** cae en ese caso (su túnica abierta da 0,15 H):
  el script lo avisa y **le deja las manos como están**, porque apretar la túnica
  lo dejaría con el vestido hecho un ovillo. Los otros cinco sí cierran.
- Verificado pintando en rojo lo que el selector considera mano: ahora el rojo
  cae exactamente sobre las manos, no sobre la ropa (con el selector anterior el
  rojo salía en las mangas y en la falda, y era la pista de que íbamos
  equivocados).
- `TWIST_MANOS` se queda en 0,95 rad. Antes, con el signo del revés, las manos
  parecían aletas abiertas hacia fuera; ahora la palma mira al muslo.
- Los 6 modelos re-riggean. Sin coste de rendimiento: 439 draw calls, ~410k
  primitivas, 339 MB.
- Suite 100% verde (76 suites + 4 smokes).

*Fin del documento maestro v3.53 — Fase 50.3 (las manos cerradas de verdad).*

## Traspaso a otra PC (2026-09-28)

El contexto de este proyecto cabe en git, **incluida la conversación con
OpenCode**: `handover/` lleva el historial exportado (0,8 MB) y los dos manuales
para montarlo todo en otra máquina.

- `handover/README.md` — cómo clonar, **cómo abrir la conversación**
  (`opencode import` + `opencode -s <sessionID>`) y dónde se quedó el proyecto.
- `handover/ENTORNO.md` — lo que NO está en el repo: Godot 4.7.2, el Blender
  portable de `~/Tools`, los 2,6 GB de packs y el servicio `opencode-relay`.
- `handover/sesion-ggv2-2026-09-28.json.gz` — 1.308 mensajes.

Al exportar la sesión aparecieron credenciales reales en salidas de herramientas
antiguas (un token `ghr_` de GitHub y dos claves `sk-`): van **redactadas** en la
copia del repo, verificado con un barrido de patrones. La versión completa son
55 MB y **no entra en git**; para recuperarla, `opencode export` en la máquina
original.

*Fin del documento maestro v3.54 — Traspaso a otra PC.*


## Fase 45 — Minería: vetas por bioma (2026-09-24)

La primera de las dos profesiones que quedaban (la otra, cocina, es la fase
46). Hasta aquí los 17 materiales de la Fase 43 solo servían para la
herrería: ahora el jugador también puede **extraer** los suyos, y cada región
del mundo expone el mineral con el que se identifica.

- **12 vetas** en `data/vetas.json`, producidas por
  `tools/generar_vetas.py` (determinista, semilla 20260924, dos corridas →
  mismo SHA-256, igual que el terreno y los spawns). Una por cada una de las
  **10 regiones** + 2 repetidas (hierro junto a Moon Town, esmeraldas en el
  Umbral de Ladon). Se colocan en el anillo 900–1500 m del centro de su
  ciudad, fuera del disco urbano y fuera de la zona segura de 40 m; el Velo
  (sin ciudad propia) se reparte uniforme en su rectángulo.
- **6 minerales** nuevos en `data/items.json` (`mineral_cobre`, `mineral_hierro`,
  `mineral_plata`, `mineral_obsidiana`, `mineral_cristal`, `mineral_esmeralda`),
  cada uno con su tinte: el color ES la identidad de la veta en el mapa.
- **Escala data-driven, derivada de la región** (nada escrito a mano):
  `nivel` = `nivel_min` de la región (gate), `xp` = `min(12, 5 + nivel/3)` →
  5 XP al principio y 12 en endgame, `cantidad` = `min(3, 1 + nivel/15)` → de
  1 a 3 minerales por golpe.
- **3 usos + 180 s de respawn** (decidido por Juan Diego en la fase 45).
  Minar es **instantáneo**, da el XP de la veta, **no da oro** (el oro es de
  las recetas) y **no toca stats**.
- `VetaDB` (datos) · `Veta` (nodo: estado + visual + aviso flotante +
  guardado) · `Mineria` (lógica pura, sin estado ni nodo) · `GestorVetas`
  (coloca las vetas de la región con histéresis 700/900 m, como el streaming
  de mobs, y guarda su estado).
- **La veta es una `Entity` no combatible** (`combatible = false`, igual que
  los NPCs): así el raycast del clic la encuentra sin tocar al jugador y
  habla el mismo idioma — primer clic selecciona, segundo clic o **E** mina;
  si está lejos, el jugador camina hasta ella y mina al llegar
  (`minar_solicitado`, mismo patrón que `_pend_npc`). Nunca es objetivo de
  ataque ni entra en el foco de combate.
- **Aviso flotante** `Label3D` sobre la veta ("+2 Mineral de Cobre (+9 XP)"),
  reutilizado y apagado solo: sin UI nueva y sin acoplar la UI al mundo.
- **Nodos con nombre fijo** (`Cuerpo`, `Colision`, `Aviso`, `Cristal0..2`) para
  que la fase 47 sea un *swap* a modelos GLB y no una reescritura. Mallas,
  esfera de colisión y materiales **compartidos** (uno por mineral, no uno por
  veta) y la veta **no se procesa en reposo** (`set_process(false)`).
- **Save v13**: bloque `mineria` con los usos y la cuenta atrás de respawn de
  cada veta tocada (guardado mínimo). Una partida v12 sin bloque deja las
  vetas intactas. El estado de una veta lejana no se pierde al alejarse (si no,
  minar sería infinito: te ibas, volvías y la veta estaba llena).
- **Arreglo de datos**: los 10 materiales de la Fase 43 no tenían `apilable`,
  así que cada unidad ocupaba uno de los 20 slots y la mochila se llenaba
  minando. Con `apilable: true` el mineral apila (verificado por test).
- Tests: `tests/test_fase45_mineria.gd` — 318/318. Suite 100% verde (70
  suites + 4 smokes) + regresión de los conteos de items y la versión de save.

---

## Fase 50.4 — Saneamiento (2026-09-29)

Sin features: 13 correcciones, la mayoría heredadas de un diagnóstico del
proyecto. 12 de 13 aplicadas; la 13 (los flags `TEMPORAL` del viaje rápido)
queda para Juan Diego porque es una decisión de diseño, no una corrección.

- **Capas UI (§9.2):** `hud.gd` no asignaba `layer` y se quedaba en la 1
  (por debajo de la barra en 12 y de todos los paneles en 25+). Ahora
  `layer = UiLayers.HUD` (10). El minimapa usaba
  `z_index = UiLayers.MINIMAPA`, es decir una CAPA puesta donde va un orden
  entre hermanos: funcionaba solo por orden de árbol. El minimapa y la
  brújula cuelgan ahora de su propio `CanvasLayer` con
  `UiLayers.MINIMAPA` / `UiLayers.BRUJULA`, que es lo que §9.1 pide
  ("la UI de cada sistema en su CanvasLayer propio"). Nuevas constantes
  `TOAST` (15) y `BANNER_REGION` (70) en `ui_layers.gd`; el toast de
  `panel_misiones.gd` y el `CapaBanner` de `fase14_demo.tscn` dejan de
  llevar el número a mano.
- **`tools/run_tests.sh` (nuevo):** había 80 tests y ninguna forma de
  correrlos de una vez; la regresión completa era manual. Itera
  `tests/test_*.gd` (y `smoke_*.gd` con `--smokes`), suma exit codes e
  imprime el resumen.
- **Un test que rompía el repo:** `test_fase12_spawns.gd` ejecutaba
  `generar_spawns_rework.py` dos veces sobre `data/spawns.json` REAL. Si el
  generador fallaba a mitad, dejaba 1133 entradas corruptas. El generador
  ahora acepta una ruta de salida y el test escribe en `user://`, además de
  comprobar que el archivo del repo queda intacto.
- **Tests que faltaban:** la Fase 34 reescribió el modelo entero de stats
  (STR/STA/DEX/INT sin agilidad) y su único guardián era un check parcial
  de `test_stats.gd`; la Fase 45.1 cambió `run/main_scene` y no tenía
  check. Los dos van ahora en `tests/test_fase34_stats.gd` (124 checks).
- **Higiene:** 3 comentarios corruptos con caracteres CJK reparados
  (`test_fase44_herreria.gd`, `veta.gd`, este spec);
  `tools/generar_spawns.py` borrado (superseded por
  `generar_spawns_rework.py`, y su docstring describía una regla
  NIVEL→ARQUETIPO que ya no aplica);
  `panel_herreria.gd` creaba 4 `Herreria` y usaba 1 (3 objetos muertos);
  `panel_viaje.gd` se fabricaba su PROPIA `ViajeRapido` mientras la demo
  tenía la suya (dos cachés de `viaje_rapido.json` vivas a la vez) — ahora
  la demo le pasa la suya con `fijar_viaje`;
  `npc.gd` creaba un `StandardMaterial3D` por NPC (21 materiales), ahora
  comparte cache por color como `Enemy._mats_cache`.

## Fase 51 — Muerte y respawn del héroe (2026-09-29)

**El bug más grave del repo, y no lo detectaba ningún test.**
`Entity.die()` apagaba `_process`/`_physics_process` y ponía
`collision_layer = 0`, y `Player.murio` solo estaba conectado en
`arena.gd`. Morirse **fuera de la arena congelaba el juego para siempre**:
sin input, sin física y sin forma de revivir. El único escape era F10. Con
6 jefes de nivel 70 en el mapa no era un bug, era un muro.

- `Entity.revivir(vida, mana)` (nuevo): envuelve el `_revivir_silencioso()`
  que ya existía y solo se usaba al cargar un save, y además pone vida/maná
  y emite `vida_cambiada`/`mana_cambiado` (sin ellas el retrato se queda
  gris). Idempotente.
- `SkillSystem.purgar_temporales()` y `purgar_cooldowns()` (nuevos): el
  respawn limpia buffs, debuffs y cooldowns. La purga temporal barre
  también los debuffs que el jugador puso a los enemigos: al morir, el
  combate termina.
- `CameraRig.snap_seguimiento()` (nuevo): reposiciona sin interpolar. Sin
  esto, el teletransporte del respawn hacía volar la cámara cruzando el
  mapa entero.
- `Player.anclar_en_ciudad()` / `ancla()` / `reaparecer()` (nuevos).
- `scripts/mundo/respawn_heroe.gd` (nuevo, `RespawnHeros`): escucha
  `jugador.murio`, mantiene el punto seguro y llama a `reaparecer()`.
- **El ancla NO sale de `data/viaje_rapido.json`.** Sus plazas son `[x, z]`
  de dos elementos, sin `y`, y la altura real del terreno va de 40 u en
  Moon Town a 220 u en `rage` (175 u de descuadre). La fuente es
  `CiudadLuna.punto_aparicion_jugador()`, que sí consulta el terreno, y son
  las 9 ciudades que la demo ya construye.
- **Guardia de arena, con trampa evitada:** mirar `arena.activa()` en el
  instante de morir NO alcanza. La arena se conecta a `jugador.murio` antes
  que el respawn, así que su handler corre PRIMERO, termina la derrota y
  deja `activa() = false`; para cuando llega la señal del respawn, la arena
  ya parece inactiva y el héroe se iría a la ciudad a media partida. La
  arena ahora pone y quita el respawn a punto explícitamente
  (`RespawnHeros.suspender()`), y `_terminar()` NO lo libera (corre dentro
  de la misma señal); lo libera `detener()`.
- **Segundo bug de la misma clase, encontrado por el test de la fase:** al
  perder en la arena, la demo avisaba "habla con Renn" y dejaba al jugador
  **muerto y congelado en el campo**. Ahora al perder revive, teletransporta
  fuera y recién ahí devuelve el control al respawn.
- `Formulas.damage_sin_alloc()` (nuevo) devuelve un `ResultadoDano`
  reutilizado en vez de un `Dictionary` literal: eran dos asignaciones por
  golpe (el Dictionary de retorno y el literal `{"power": 1.0}`), en los
  tres call sites del hot path (`player.gd`, `enemy.gd`, `skill_system.gd`).
  `Formulas.damage()` sigue existiendo para los tests.
- `tests/test_fase51_muerte.gd` (nuevo, 62 checks).

## Fase 51.1 — Registro mínimo de sistemas (§9.1, parcial) (2026-09-29)

`gg_system` y `system_id` aparecían **0 veces en los 82 scripts**, aunque el
spec los exige: el descubrimiento era 100% rutas de nodo hardcodeadas desde
una cadena de demos de 6 niveles de herencia, con 12 variables `@onready`.

- `scripts/core/systems.gd` (nuevo, `Systems`): `registrar()`,
  `obtener()`, `exigir()`, `desregistrar()`. Acepta los dos tipos que hay
  en el proyecto: los `Node` entran además al grupo `gg_system`, y los
  `RefCounted` (`SaveSystem`, `ViajeRapido`, que no viven en el árbol) solo
  quedan en el diccionario del contenedor.
- Migrados los CUATRO que estorban —los que la demo instanciaba con `.new()`
  dentro de una demo y por tanto rompían cualquier test de integración—:
  `SaveSystem`, `Arena`, `GestorVetas` y `ViajeRapido`.
- **Deuda que queda declarada, no escondida:** los otros 78 scripts siguen
  con acceso directo. Esta fase es deliberadamente parcial: migrar los 82
  es mecánico pero son varias sesiones y retrasa el trabajo visible.

## Fase 52 — Jefes de verdad (2026-09-29)

Los 6 jefes de fragmento eran `Enemy` con más vida. En `data/enemies.json`
no había **ningún campo** que los distinguiera de un goblin: se reconocían
solo por tener XP >= 400.

- **Dato primero (§9.4):** bloque `jefe` en los 6 arquetipos, con
  `vida_mult` (4.5–5.1), `telegrafia_seg` (0.7–1.3), `enrage_seg` (40–70),
  `mult_dano` (3.0) y `fases[]` (3 tramos: 100–66 %, 66–33 %, 33–0 % con
  multiplicadores de velocidad y daño). Perfil por jefe: el Champion y el
  Fundidor telegrafían lento, el Susurro y el Devorador rápido.
- `Estado.PREPARANDO` en la FSM: el jefe se planta y se tiñe (material
  emisivo rojo) antes de cada golpe. Sin clip propio —el rig solo trae
  idle/walk/attack/die— reusa el de ataque, que es la pose de carga; la
  señal real es el tinte.
- Fases: cambian al cruzar el umbral de vida y **solo suben** (curarle al
  jefe no lo devuelve a la fase anterior). El enrage baja solo y termina
  sumando daño.
- Un arquetipo sin bloque `jefe` se comporta exactamente igual que antes:
  misma FSM, sin telegrafía, sin fases.
- `tests/test_fase52_jefes.gd` (nuevo, 78 checks).
- **Pendiente:** la barra de jefe estilo GoW (`BarraJefe`). Se decidió que
  sería un `Control` en su propio `CanvasLayer`, no como `BarraVidaMob` (que
  es 3D y vive sobre la cabeza del mob): se reutiliza la LÓGICA (el
  `pct`, el drenaje retardado, los colores por tramo) y no el render.

---

# BLOQUE DRAGONWILDS — Fases 53 a 62 (2026-09-29)

Diez fases que agregan la **capa de presión y de recolección** que el juego
no tenía, manteniendo el canon de Liberty, las 5 clases y la regla dura de
single-player local (§7.1). La inspiration fue RuneScape: Dragonwilds, pero
lo que se tomó es su **bucle**, no su forma: no hay construcción libre
estilo Dragonwilds más allá del Refugio, ni dragones, ni cofres, ni nada
online.

Estado al cerrar el bloque: **93 suites en verde** (89 tests + 4 smokes),
`tools/run_tests.sh` como runner único.

Las tres decisiones que framing el bloque (Juan Diego):
- **XP por habilidad**, sin niveles 1-99: el nivel de personaje NO se toca.
- **Hambre y sed suaves**: a 0 NO matan, dan debuff.
- **Refugio con construcción libre**, partida en dos fases (60/61) por ser
  la más cara.

---

## Fase 53 — Barra de jefe

Desde la 52 los jefes telegrafiaban, cambiaban de fase y entraban en rage, y
el jugador no veía nada. `scripts/ui/barra_jefe.gd`: un `Control` en
`UiLayers.BARRA_JEFE` (13), con nombre, barra, "fantasma" de daño diferido,
marcas de umbral en 66% y 33%, y latido en rage. Se engancha a
`Player.seleccion_cambiada` y solo aparece si el enemigo es jefe.

`BarraVidaMob` es 3D (un QuadMesh sobre la cabeza del mob); esta es UI. Se
reutiliza la LÓGICA (pct, drenaje retardado, peldaños de color) y no el
render. Test: 31 checks.

## Fase 54 — Comida y tick-eat

El proyecto tenía **2 consumibles y cero comida**. Ahora: 15 alimentos y
bebidas, con `hambre`/`sed`/`energia`/`riesgo` en `data/items.json` (77
items). La carne cruda que tiran goblin/lobo/ogro (85%) enferma; la asada
no. `scripts/core/vitals.gd` (puro, testeable sin nodos) es el contenedor
de los tres vitales; `Inventario.usar()` enruta comida y bebida a él, que es
el tick-eat. Test: 78 checks.

## Fase 55 — Tala

`data/arboles.json` (126 árboles, 9 especies por bioma,
`tools/generar_arboles.py` determinista). **`Arbol` HEREDA de `Veta`**: la
veta de la 45 ya era un nodo de recurso genérico (usos, respawn, aviso,
tinte, streaming con histéresis) y la tala es lo mismo con otro `item_id` y
otra silueta. Copiarlo habría repetido el `skill_fx.gd` vs `damage_flash.gd`
que ya está marcado como deuda. Lo único propio: tronco + copa, la señal
`talada` reemitida de `minada`, y la copa que desaparece al talarse.
`Talar` es la lógica pura, calcada de `Mineria`. Test: 3197 checks.

**Trampa pagada (segunda vez):** `_al_agotar()` tiene que aceptar el
`veta_id` que emite la señal. Declararlo sin argumentos hace que Godot corte
la conexión en runtime con *"Method expected 0 argument(s), but called
with 1"*, y no se ve en ningún `--check-only`.

## Fase 56 — Cocina

Cierra el círculo recolectar→cocinar→comer, y **no depende de la 61**: la
`Fogata` es una estación fija por ciudad, como los herreros. Cocinar es lo
que convierte el riesgo de la comida cruda en una decisión. `Cocina` es
pura; la leña sale de los troncos de la 55, así que la tala tiene consumidor.
La fogata se apaga sin leña (y con eso no gasta ni luz real ni partículas).
Test: 80 checks.

## Fase 57 — Habilidades con XP propio

Segundo eje PARALELO al nivel de personaje: `Habilidades` (pura) con XP por
habilidad y tramos, en `data/habilidades.json`. **El nivel de personaje no
se toca** y sigue mandando en StatBlock, combate y equipo. El XP de
habilidad abre los Hechos de la 59. La minería da los dos XP. Test: 58.

## Fase 58 — Hambre, sed y energía

El núcleo. `Vitals.avanzar(dt, actividad)` decae por tiempo y actividad
(pegar 2.2x, caminar 1.5x, parar 1.0x), nunca sale de 0..100, y la
enfermedad acelera el hambre. El `Player._tick_vitals` sincroniza por MODS
del StatBlock (`vital:energia`, `vital:debil`): la UI nunca escribe stats y
todo es reversible.

**DECISIÓN, blindada por test: a 0 NO matan.** Dan debuff (menos ataque y
defensa) y nada más: no drenan vida. Vaciarte la vida sería matarte de a
poco por otro nombre. La muerte sigue siendo de enemigos y jefes. El test
falla si alguien "arregla" el 0 para que mate.

Test: 41 checks.

## Fase 59 — Hechos de Habilidad

La mejor idea de Dragonwilds, traída: **subir una habilidad no te da "+5% de
daño", te da un HECHO que transforma la recolección**. 10 hechos en
`data/hechos.json`, dos tipos:
- `mod` → MOD del StatBlock, fuente `hecho:<id>` (distinta de `talento:<id>`
  de la 28 y de `buff:<id>` de los temporales, para que no se pisen).
- `bandera` → la leen los sistemas: `tala_area` (3 troncos por tajo,
  gastando UN uso), `tala_rangos` (+2 tramos de nivel), `veta_persistente`,
  `doble_respawn`, `cocina_lote`, `sed_ausente`, `hambre_ausente`.

Sin la 59, la 58 es un castigo. Con ella, cada vez que tenés hambre decidís
si gastás tu Hecho de Tala para resolverla rápido o si caminás a la fogata.
Esa decisión ES el juego. Test: 84 checks.

## Fase 60 — El Refugio: reclamar

El "refugio del Verdugo" es canon desde §6 Dominio 7 y hasta acá no existía.
9 puntos, uno por plaza, en `data/refugios.json`. Reclamar da ancla de
respawn, nodo de viaje rápido sin costo y el presupuesto de piezas de la 61.

**El dato trae [x, z] y NUNCA `y`**: la altura la consulta el terreno, por el
mismo motivo que en la 55 (las plazas de `viaje_rapido.json` tienen un `y`
desfasado hasta 175 u). Hay un test que lo comprueba. Test: 96 checks.

## Fase 61 — El Refugio: construir

La fase más cara, y la de más riesgo de VRAM (el mundo ya tenía 72
`ArrayMesh` y 36 `ConcavePolygonShape3D` residentes, §9.5). 8 piezas en
`data/piezas.json` con costo, caja y acción. `Constructor` es PURA: rejilla
de 2 u, 4 rotaciones (1 si la pieza no admite), AABB con holgura para que
no se solapen, y **el presupuesto de piezas se aplica ANTES de instanciar
nada**.

A propósito NO es un editor de construcción libre: sin rotación continua,
sin terreno, sin preview en 3D. Es un sistema acotado que no se come la
VRAM. El techo (24 por refugio) vive en el dato y hay un test que falla si
se pasa. Test: 80 checks.

## Fase 62 — Titanes que hostigan

El equivalente al dragón de Velgar: presente desde temprano, no solo en el
jefe. `titan_acecho` es un arquetipo NORMAL con bloque élite (no un jefe de
fragmento: no lleva `jefe`) y `factor_suelta: 6.0` — suelta la presa al
6x su aggro, contra 1.5x de un goblin. 8 spawns, uno por región menos Moon
Town (la primera tiene que respirar).

Los 1133 spawns se mantienen: 8 cupos salieron de la fauna. Eso tocó los
conteos de `test_fase12_spawns`, `test_fase14_terreno` y `test_fase43_regional`
(que contaban arquetipos y aplicaban la regla región→arquetipo), y los tres
eximen ahora el grupo `titan` como ya eximían `jefe_fragmento`. Test: 52.

---

# Hotfix 62.1 + Fases 63 y 64 — que el bloque 53–62 exista de verdad (2026-09-29)

Las diez fases anteriores cerraron con **93/93 en verde** y con un problema
que la suite no podía ver: de todo el bloque, lo único que el jugador veía era
la barra de jefe. Hambre, sed, energía, habilidades, Hechos, fogatas y
refugios estaban implementados, testeados y **inalcanzables**.

La lección ya estaba escrita en el repo (§3 del traspaso a la PC nueva): *"una
verificación en Blender no es una verificación. El fallo de las manos era
visible en pantalla y yo lo di por bueno porque los renders cuadraban"*. 93/93
en verde fue exactamente eso: los tests probaban la LÓGICA, no que el juego se
pudiera jugar. Y había un agujero peor que la UI.

## El bug que la suite no cazó

`Arbol` hereda de `Veta` (fase 55, para no duplicar el nodo de recurso). Esa
decisión, aislada, era correcta. El problema: **`Mineria.minar` tenía
`"mineria"` hardcodeado**, así que talar un árbol pasaba por la lógica de
minería y subía `mineria`. `Talar`, la clase que implementa `tala_area` y
`tala_rangos`, **no la llamaba nadie**: era código muerto.

Consecuencia: la habilidad `tala` no subía NUNCA y los Hechos de tala eran
permanentemente inalcanzables. Justo la decisión que la fase 59 escribió en el
spec como *"esa decisión ES el juego"* — gastar el Hecho de Tala para resolver
el hambre rápido, o caminar hasta la fogata — era imposible jugando.

El agujero no fue la lógica, fue la cobertura: los tests de la 55 y la 59
probaban `Talar` y `Mineria` por separado, y nadie probó el **camino real**
(`GestorVetas._al_minar_solicitado` → `Mineria` → `habilidades.ganar`). Ese
camino es el que ahora cubre `test_hotfix_62_1_tala.gd`.

El arreglo, con "datos primero" (§9.4): la habilidad la **declara el nodo**.
`Veta.habilidad_id` vale `"mineria"` y `Arbol` la sobreescribe a `"tala"` en su
`_init` (GDScript no deja redeclarar un miembro del padre). `Mineria` pregunta
al nodo y, si es un árbol, delega a `Talar` para que el Hecho `tala_area`
(3 troncos por un uso) se aplique de verdad.

## Hotfix 62.1 — que el bloque no mienta

Cinco correcciones, sin features nuevas salvo el feed:

- **Tala → `tala`**: como arriba.
- **Hechos que sobreviven al save/load**: `Habilidades.cargar_estado` escribe el
  XP en silencio y **no emitía `tramo_ganado`**, así que el `hechos.aplicar()`
  del Player no corría y los mods `hecho:*` se perdían en cada F10. El arreglo
  es recalcular, no persistir: `Hechos.desbloqueado()` es exactamente
  `habilidades.alcanza(habilidad, tramo)`, o sea que los Hechos son datos
  DERIVADOS. Guardarlos crearía una segunda fuente de verdad que puede
  discrepar, y no hace falta tocar el formato del save.
- **`system_id` en `Refugio` y `GestorArboles`**: sin eso `Systems.registrar`
  rechazaba los 9 refugios y el gestor con `push_warning`, y no eran
  descubribles. Solo 5 de 11 sistemas lo declaraban.
- **`RespawnHeros.actualizar_ancla()` al caminar**: su docstring lo prometía
  desde la 51 y nadie lo llamaba; el punto seguro solo se refrescaba al morir
  o al viajar rápido. Ahora tiene `_process` con reloj de 0,5 s (sin allocs).
- **`FeedAvisos`** (`scripts/ui/feed_avisos.gd`, capa 16): el feed que hace
  OBSERVABLE el arreglo. El toast de la 15 está entrelazado con el banner de
  misión de `PanelMisiones` y desarmar ese ovillo es un refactor con riesgo
  propio, así que este vive en la 16 y los dos conviven. Se registra en
  `Systems` como `feed_avisos` y `hecho_desbloqueado` lo engancha, con el
  título **y la descripción**: "Leñador" solo no dice que ahora sacás 3
  troncos. Cumple la intención que la 45.2 ya declaraba ("el toast es un feed
  GLOBAL") y que ningún sistema tenía por dónde usar.

Test: 54 checks.

## Fase 63 — que se vea

- **`IndicadorVitales`** (capa 17): hambre, sed, energía con color propio, más
  el icono de enfermedad, y escucha `Player.vital_bajo`, que hasta acá no tenía
  ni un listener. **La UI no lee por frame**: `Vitals` gana la señal
  `vital_cambiado`, que es "sucia" (solo emite si un valor se movió
  `TOQUE_MIN = 0.5`), porque `avanzar()` corre cada frame y lo caro no es la
  señal, es el redibujado de tres barras detrás. `consumir()` también avisa:
  comer tiene que verse en el acto.
  - El aviso bajo NO se latchea: la alerta se recalcula cada frame. Un HUD que
    avisa "te mueres de hambre" y lo deja pegado aunque comas es peor que no
    avisar. El test camina el ciclo de pulso entero porque con una sola llamada
    se mide el reloj y no la función.
- **Dos pestañas nuevas en el K** (`Recolección` y `Hechos`), no un panel
  nuevo: el K ya tenía Skills y Talentos, y un cuarto sitio para mirar lo mismo
  sería una tecla más que recordar. Recolección muestra las 4 barras de XP
  (al siguiente tramo, no al total: una barra llena cada tramo sí dice algo) y
  Hechos los 10 con su requisito, que es lo que permite verlos venir mientras
  caminás hacia la veta.

Test: 47 checks.

## Fase 64 — que se pueda usar

**Decisión de modelo**: `Fogata` y `Refugio` heredan de `Node3D`, no de
`Entity`. No se hicieron `Entity` para poder reusar el camino de selección: eso
les daría puntos de vida y aggro a una hoguera, que es un modelo equivocado. Se
interactúa por **proximidad** con la E, el mismo idioma que el patrón
"acercarse y actuar" de los NPCs, con `PromptInteraccion` (capa 18) diciendo qué
hace esa tecla. `Player.interactuable_cerca` es una señal con reloj de 0,25 s
que solo emite cuando el objetivo cambia.

- **Fogata**: apagada, la E la prende con un tronco (de cualquiera de las cinco
  especies: la tala da madera varied y obligar a llevar roble sería absurdo) y
  lo gasta de verdad. Encendida, la misma E pide cocinar. Se announcementa en el
  feed con los segundos de leña.
- **`PanelCocina`** (capa 34): cierra el círculo recolectar → cocinar → comer.
  Gasta el ingrediente, **entrega el asado** (que no enferma, que es todo el
  punto de cocinar), gasta leña de la fogata y sube `habilidad cocina`.
- **Refugio**: la E lo reclama, y al reclamar se **cablea al `RespawnHeros`**
  (`anclar_refugio`), así que un refugio reclamado ES el punto seguro. Es la
  deuda que la 60 dejó abierta. Reclamado, la E pasa a construir.
- **`PanelConstruccion`** (capa 33) + **`PiezaVisual`**: la UI que le faltaba a
  `Constructor`. Catálogo de las 8 piezas, preview fantasma, rotación, colocar
  y deshacer. Las mallas son **procedurales a partir de la caja AABB del dato**
  (si `cajas` cambia en el JSON, la malla cambia con él) y los materiales son
  **8 compartidos**, no uno por pieza colocada (§9.5). No usa GLB: los 85 de
  Meshy son estáticos de 96,7M triángulos.
  - El preview va **delante del jugador, automático**, no detrás del ratón: con
    el panel abierto el ratón está sobre los botones y un preview que lo
    persiguiera saltaría cada vez que se busca una pieza.
  - Seleccionar una pieza que NO admite rotación ahora **resetea la rotación**.
    Sin eso, mirar "Antorcha" con los 90 grados de la Mesa de antes la hacía
    inclazable, sin explicación en pantalla.
  - **Los materiales se gastan de verdad**: `Constructor.descontar` muta el
    `Dictionary` que se le pasa, y el panel le pasa una COPIA. Sin volcar el
    diff al `Inventario` real, las piezas salían gratis. Y deshacer los
    devuelve: sin eso, un clic mal puesto era un material perdido para siempre,
    que es la forma de hacer que el jugador deje de construir por miedo.

- **Acción de Input Map `construir` = V**, no C: la C ya era `abrir_equipo` y
  el `test_fase47_teclas` caught la colisión. Ese test existe para esto.

Test: 70 checks.

## Verificación

- **96/96 en verde** (92 tests + 4 smokes) contra los 93 de antes.
- **211 archivos .gd con `--check-only`, 0 errores de parseo.**
- Los tres tests nuevos: `test_hotfix_62_1_tala.gd` (54), `test_fase63_…` (47),
  `test_fase64_uso.gd` (70).

## Lo que aprendí en estas tres fases, y va al spec

1. **Un test unitario de cada pieza NO cubre la costura.** Los de la 55 y la 59
   pasaban y el camino real estaba roto. Cuando dos sistemas se unen por una
   señal, el test tiene que ir por la señal, no por las dos clases.
2. **GDScript captura por valor en las lambdas.** Un `var n: int` protegido por
   una lambda nunca se ve cambiar desde fuera: el test pasa "0 emisiones" y
   parece que la señal no funciona. Se acumula en un `Array`.
3. **GDScript no deja redeclarar un miembro del padre.** Para que `Arbol`
   tuviera otra `habilidad_id` hay que asignarla en `_init`, no declararla.
4. **`queue_free()` es diferido.** Un test que "limpia" un grupo con
   `queue_free` y después lo escanea está midiendo los nodos viejos: en este
   caso, la fogata de un test anterior seguía siendo la más cercana.
5. **La cobertura de la UI tiene que ser del dato, no del nodo.** Conectarse a
   una señal dentro de un test no prueba nada: hay que mover el dato y ver que
   la barra se mueve.

---

# Bloques 65 a 68 — del prototipo al juego (2026-09-29)

Los bloques 53–64 cerraron con 96/96 en verde. Estos cuatro no añadieron
contenido: **quitaron las razones por las que el juego no se podía jugar ni
mirar ni oír**. Cada uno empieza por un diagnóstico, no por una idea.

---

## Bloque 65 — Que el juego sea un juego

Cuatro cosas que hacen que un juego se sienta terminado, y que faltaban
TODAS. Tres no son features: son que el flujo exista.

**El juego arrancaba por el mundo, no por el título.** `main_scene` era
`fase14_demo`. El título y la creación de personaje estaban terminados (fases
11) y **nunca se usaban**: no se elegía clase ni nombre, y el nombre del héroe
salía vacío en el HUD. Ahora: título → crear personaje → mundo, con fundido.

**Trece scripts de UI se apropiaban del ESC**, cada uno en su `_input`. Con un
panel abierto funcionaba; con dos (inventario + equipo es fácil) cerraba los
dos a la vez o ninguno, según el orden del árbol. Ahora hay una **pila**
(`PilaUI`): el ESC cierra solo el de la cima. Los 13 migraron, y el panel que
se abre por proximidad entra y sale de la pila con su panel.

**No había menú de pausa.** Cero usos de `get_tree().paused` en todo el repo.
Reanudar / Opciones / Guardar / Volver al título / Salir, guardando antes de
salir o volver (sin preguntar: preguntar es una decisión del jugador y un
modal que puede dejar la partida sin guardar).

**No había opciones.** Sensibilidad, distancia de cámara, FOV e invertir-Y
eran `const` compilados. Ahora viven en **datos** (`Opciones.catalogo`) y la UI
se construye recorriendo el catálogo: añadir un ajuste es una línea, no un
widget a mano. Se aplican al instante (mueves el volumen y se oye) y
persisten en `user://opciones.json`, que **no** es el save (la resolución no
viaja con la partida).

**El guardado no era a prueba de corte de luz.** Se escribía directo sobre
`partida.json`: un corte a mitad de escritura dejaba un JSON truncado y, sin
backup, se perdía la partida. Ahora: `.tmp`, `flush`, backup del anterior,
rename atómico, y si el principal sale corrupto al cargar cae al `.bak`.
Autosave cada 5 min (el reloj se pone a cero al reanudar), sucio **por señales**
(no por diff de un diccionario cada frame). Y el **estado del mundo**: los
árboles talados y los refugios con sus piezas, que antes se guardaban a medias
—las vetas sí, los refugios no—, que es peor que no guardarlo.

**El panel de construcción mentía:** su ayuda decía "R rota · clic coloca ·
Supr quita" y no tenía ni un `_input`. Las tres teclas ahora hacen algo, y
`rotar_pieza` (R) está en el Input Map.

---

## Bloque 66 — Que el juego suene

La auditoría: **4 call sites de audio en todo el repo**, 13 sonidos a 8 bits /
22050 Hz, cero música (el bus existía y nunca se le asignaba nada), **cero
`AudioStreamPlayer3D`** (un goblin a 200 m sonaba igual que uno encima), cero
pisadas, y 3 sonidos declarados que nunca se llamaban. Todo pasaba los tests:
comprobaban que el sintetizador devolviera un WAV, no que el juego lo oyera.

- **16 bits, 44100 Hz, estéreo.** No es estética: 22050 tiene el techo en
  11 kHz (se perdía todo lo que pasara de ahí) y mono centrado se lee como un
  pitido. ADSR con release, y pasabajos en el ruido.
- **Variación**: 2–4 variantes por sonido, elegidas al azar. Es lo que separa
  un impacto de un pitido; con una sola el oído aprende la forma y la ignora.
  36 sonidos (antes 13).
- **Posicional**: pool de 16 `AudioStreamPlayer3D` además del 2D. El impacto y
  la muerte de un mob van al 3D; lo del jugador (comer, pisadas) sigue 2D.
- **Pisadas por distancia recorrida**, no por reloj: correr suena a más pasos
  que caminar. El material sale de la región.
- **Música por capas** (base siempre, exploración, combate, jefe), generada
  sin assets, con **ducking** (al entrar en combate la base baja) y un
  **director** que decide la escena por el estado real con histéresis de 2 s.
- `SonidoUI`: el punto único de los sonidos de interfaz.

**Tres bugs reales que encontró el test del bloque:**

1. El buffer del sintetizador se dimensionaba a `n*2` (mono) pero se escribía
   4 bytes por muestra (estéreo): la mitad de las muestras. El audio nunca
   había sonado bien.
2. **El release de la ADSR era código muerto**: comparaba segundos contra un
   `t` normalizado, así que nunca se alcanzaba y todo sonido se cortaba en
   sustain —el "clic" que la fase 21 decía evitar. Diez fases con un bug del
   que el spec afirmaba que estaba resuelto.
3. `PoolImpacto` se buscaba por **nombre de nodo**: renombrarlo rompía el
   efecto en silencio. Ahora usa el grupo (§9.1).

---

## Bloque 67 — Que se vea y no dé jumps

**El post-proceso empieza por un bug de imagen, no por una feature.** El
`Environment` de la fase 12 no tenía ni un campo de post-proceso, y de esos el
tonemapping no es una ausencia: Godot 4 usa LINEAR por defecto, así que con el
sol a 1.25 al mediodía **cualquier superficie iluminada clipaba a blanco puro**.
Se activa tonemap filmic + glow (solo emisivos) + SSAO + ajustes + niebla por
profundidad, y se afina el sol (dos splits con PCF, no 4 muestras
escalonadas). **Límite honesto**: la web usa `gl_compatibility`, que no tiene
glow ni SSAO; en web degrada a tonemap + ajustes en vez de configurar campos
que el backend va a ignorar.

**El equipo sigue a los huesos.** `data/anclajes.json` tenía el nombre del
hueso (`Hand.R`, `Head`) desde la fase 43 y los 6 GLB tienen sus 19 huesos, y
el código **nunca lo leía**: usaba offsets absolutos, así que el casco flotaba
a 1,58 m mientras el personaje se agachaba o moría. Ahora cada pieza se cuelga
de un `BoneAttachment3D`, con fallback al offset si no hay esqueleto. Para los
slots espejados la X del offset se invierte, porque el rig ya refleja el hueso.

**AnimationTree.** El `_actualizar_animacion` cortaba entre idle y walk con
`play()`. En un juego donde el personaje gira 180° constantemente, cada salto
era un pop. Ahora un `AnimationNodeBlend2` mezcla por velocidad normalizada, y
el cross-fade sale solo. Compartido con los enemigos, que tenían el mismo
problema (su IA piensa cada 0,25–6 s).

**UI responsive.** El juego corría a 1280×720 fijo, sin `window/stretch`, y 17
paneles usaban píxeles duros. Ahora `canvas_items` + `expand` y `AjustaUI`:
proporción acotada (con mínimo y máximo) + anclaje al borde.

**El test de la 36 —"el equipo no se movió de sitio"— celebraba el bug**: los
offsets fijos *son* "no moverse de sitio". Ese test estaba al revés.

---

## Bloque 68 — Que el golpe se sienta y haya a dónde ir

El game feel de la 19 tenía la mitad de lo que hace que un golpe se sienta
(números, hit-stop, shake) y le faltaba la otra: **el mundo no reaccionaba**.

- **Knockback** en la dirección opuesta al golpe, con tope y decaimiento. Se
  aplica **encima** de la IA: la IA del enemigo reescribe `velocity` cada frame
  y lo borraría.
- **Partículas de impacto** en pool, materiales compartidos, y el tipo lo
  declara el arquetipo (`tipo_sangre`): un jefe escupe chispas.
- **Proyectiles visibles.** Las skills siguen siendo hitscan (el daño no cambia)
  pero se ve volar la flecha. Que lleve proyectil lo decide el **dato** (5 de
  40), no un umbral en el código.
- **Kick de cámara direccional** cuando el *jugador* recibe daño (no cuando
  pega: el jugador no siente el peso de lo que el pega).
- **Afijos de loot**: los 77 items eran todos fijos, que no es una build, es un
  disfraz. Ahora stat + valor + rareza, deterministas por semilla, sin repetir
  stat en el mismo item, y solo los 4 stats base (vida/maná se derivan).
- **Códice/bestiario**: los 20 arquetipos con lore y drops **ya estaban** en el
  JSON y no se mostraban nunca.
- **NG+/prestigio**: al llegar al nivel 70 se reinicia personaje (no el mundo ni
  las habilidades de recolección) y se gana prestigio, que da más XP, enemigos
  más débiles con tope y afijos extra. Prestigio 0 = x1.0, así que un save
  viejo carga normal.

---

## Verificación del bloque

**99/99 en verde** (95 tests + 4 smokes), `check-only` sin errores, y
`--smokes` en verde. Nuevos: `test_bloque66_audio` (71), `test_bloque67_visual`
(53), `test_bloque68_impacto` (44).

Tres tests viejos rotos al arrancar, y los tres **afirmaban lo viejo**, no eran
bugs: `fase34` pedía que `main_scene` fuera el mundo, `fase47` prohibía que
Escape estuviera en dos acciones (ahora tiene excepción declarada: la pausa y
el cierre de panel comparten el ESC, y lo lleva la pila; cualquier otra tecla de
juego sigue prohibida en dos acciones) y `test_detalle_mision` abría un panel
sin registrarlo en la pila.

---

## Lo que sigue abierta

Lo que queda, en el orden en que más pesa. Actualizado después de las tres olas
de orquestación (afijos, códice, NG+, paper-doll, materiales, contenido,
tutorial, decoración, playtest).

1. **El p95 de frame time.** p50 = 0,69 ms sobre 16,7 de presupuesto: el juego
   está parado el 96% del tiempo y va a tirones, no lento. p95 = 34,74 ms,
   p99 = 42,48, max = 115,65 sobre 397 s de partida real. Es la brecha número
   uno para "jugable" y la única que depende de una máquina, no de código.
2. **La forma del mundo.** Después de que la ola 2 le pusiera PBR, y la ola 3
   le pusiera vegetación y props, el mundo dejó de ser cajas. Pero siguen siendo
   primitivas: no hay un solo edificio modelado. El pack externo de arte sigue
   sin estar en la máquina y `models/` tiene 6 GLB.
3. **Las texturas PBR son procedurales, no pintadas.** 20 juegos horneados al
   arrancar andan bien y cuestan 5,3 MB, pero son ruido. El salto de calidad de
   verdad son texturas hechas por alguien, y eso es trabajo de arte.
4. **Faltan misiones deActs VI al NG+ largo.** La ola 2 metió 15 misiones de NG+
   (una cadena de 3 por acto) y 13 plantillas de diarias. Es contenido para un
   ciclo, no para un periplo.
5. **El audio nunca se oyó.** Está implementado (síntesis 16-bit, 37 sonidos con
   variación, música por capas, director con histéresis) y verificado por test,
   pero nadie lo escuchó nunca. La música procedural es lo más probable que
   falle y lo más barato de cambiar.
6. **Omitido por el playtest:** el ataque con clic de ratón y el afijo en el
   item dropeado quedaron sin verificar, y el prestigio de NG+ necesita nivel 70
   que el playtest no alcanza en su tiempo. No están rotos: no están probados.

### Lo que se cerró y conviene no repetir

Cuatro veces en una sesión apareció el MISMO bug: un sistema escrito, con sus
tests en verde, y no conectado a la partida. Pasó con siete sistemas de una vez
(`_instalar_fase63_64_ui()` que nadie llamaba), con el panel del tutorial, con los
afijos y con la vegetación. La causa de fondo es la misma: **un test por sistema
no dice nada sobre si el sistema está conectado a nada**. Por eso ahora existe
`tests/smoke_fase_escena_completa.gd`, que carga la partida real y mira qué hay
dentro, y ata cada acción `abrir_*` del Input Map con el panel que la atiende.
