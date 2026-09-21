# GOLDEN GODS RPG — REMAKE · Documento Maestro de Especificación

**Versión del documento:** 1.3 — Fase 3 (2026-09-21)
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

**Estado:** Fase 3 terminada — jugador + cámara por intenciones (`Intent`,
`Player`, `CameraRig`, `Movimiento` con tests headless en verde) y escena demo
`scenes/demo/fase3_demo.tscn` jugable 5 minutos (WASD + clic + doble clic +
cámara con botón derecho). La reimplementación sigue en la Fase 4 (§11).

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
| Clic izquierdo | Mover / seleccionar enemigo (anillo + ficha en HUD) / hablar con NPC |
| Doble clic izquierdo | Atacar |
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
| Shift+I | Cocina | J | Diario |
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
| F7 | Temporizadores | F9 | Registro misiones HUD |
| F10 | Reasignar atributos | F11 | Atlas del mundo |
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
Héroe (clic mover/seleccionar/hablar, doble clic atacar, WASD relativo a cámara,
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
| 4 | **Enemigo mínimo + loot + save/load temprano**: IA de 4 estados (quieto → persigue → ataca → muere), tabla de drops, datos versionados | Loop jugable: moverse → pegar → lootear → subir de nivel → guardar/cargar |
| 5 | **HUD**: la UI solo *lee* el StatBlock, nunca lo escribe | HUD funcional sobre datos reales |
| 6+ | **Sistemas, uno por uno, por señales** (equipo/paper doll, misiones, talentos, profesiones…; catálogo en §6) | Cada sistema jugable al integrarse |

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

Cada fase: especificación cerrada → implementación → `--check-only` (0 fallos) →
tests headless en verde → ZIP con versión → **playtest de Juan Diego** →
siguiente fase. Un solo ZIP final por fase, sin pings intermedios salvo
bloqueo real.

---

*Fin del documento maestro v1.3 — Fase 3 (jugador + cámara por intenciones).*
