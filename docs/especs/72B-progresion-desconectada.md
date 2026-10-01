# 72B — Conectar la progresion que esta escrita y es inalcanzable

## Por que esto existe
Cuatro sistemas de progresion estan escritos, testeados, y NO se pueden tocar
jugando. El mas grave no es que falte un panel: es que **dos ejes de habilidad
nunca dan experiencia**, asi que sus desbloqueos son permanentemente imposibles.

El propio spec (MASTER_SPEC.md:2487-2493) documenta esta trampa: "sistemas
escritos, testeados y no conectados a la partida". Vos sos el cuarto worker que
la persigue.

## Los 5 fallos, ya verificados con grep. NO los re-descubras

### 1. La tala NO sube la habilidad Tala  (el mas grave)
`scripts/mundo/arbol.gd:37` declara `habilidad_id = "tala"`. Pero
`scripts/mundo/mineria.gd:59` (funcion `minar`) llama a `Talar.talar`, que
devuelve el XP en un dict y **nunca se lo pasa a `habilidades`**.
Consecuencia: `tala_area` y `talar_maestro` estan bloqueados para siempre.

### 2. La habilidad `recoleccion` nunca gana XP
`habilidades.ganar("recoleccion", ...)` aparece SOLO en
`tests/test_fase59_hechos.gd:165`. Nunca desde el juego. Las otras 3 si ganan
(mineria.gd:75, panel_cocina.gd:216, y tala deberia).
Consecuencia: sus 2 Hechos son inalcanzables.

### 3. Cuatro Hechos sin consumidor
`data/hechos.json` declara 10 Hechos. El juego consulta
`hechos.tiene()` SOLO para `tala_area`, `tala_rangos`, `hambre_ausente`,
`sed_ausente` (scripts/mundo/talar.gd:57,65 y scripts/player/player.gd:512-513).
Los otros 4 — `veta_persistente`, `doble_yacimiento`, `cocina_lote`,
`fogata_perenne` — NO los consulta nadie. Son recompensas que el jugador no
puede ganar.

### 4. PanelNgPlus nunca se instancia
`scripts/progresion/panel_ngplus.gd` existe, `PanelNgPlus.alternar()` no tiene
NINGUN call site fuera de los tests. La capa 36 de ui_layers.gd esta reservada y
vacia. Con el panel vanishes:
- los 12 trofeos de `data/ngplus_trofeos.json` (inalcanzables)
- las 13 diarias de `data/diarias.json` (`RotacionDiaria` se lee pero las
  plantillas no se registran en ninguna partida)

### 5. El escalado de afijos de botin va a CERO
`scripts/loot/drop_table.gd:33-35` dice explicitamente que el escalado a 0
porque los arquetipos no declaran `nivel` ni `afijos_extra`. O sea: todos los
bots dan el mismo afijo para siempre, sin importar el nivel del mundo.

## Qué hacer

1. Que talar/minar otorguen XP a la habilidad correcta, por la via NORMAL (el
   mismo camino que usan mineria y cocina). No hardcodear.
2. Conectar `recoleccion` al punto donde el jugador junta objetos.
3. Dar consumidor a los 4 Hechos huerfanos, en el sistema que les corresponde
   (veta -> mineria; cocina_lote -> cocina; fogata_perenne -> fogata/refugio;
   doble_yacimiento -> probablemente partida/inventario).
4. Instanciar `PanelNgPlus` en la partida, registrado en `gg_system`, con su
   signal y su tecla en el InputMap en español. Conectar Trofeos y
   RotacionDiaria a el.
5. Declarar `nivel` y `afijos_extra` en los arquetipos de `data/enemies.json`
   para que el escalado de afijos funcione. Es un cambio de DATOS (§9.4).
6. Todo con dato configurable: constantes en `data/*.json`, no en el codigo.

## Tests
`tests/test_fase72_progresion_conectada.gd`, extends SceneTree, `_chk()` +
`quit(_fallos)`.
OJO: cada test debe fallar si el sistema NO esta conectado a la partida. Un test
que instancia el panel y lo prueba en aislamiento pasa aunque el panel no este
en el juego. Include un check que verifique que existe el call site real en el
codigo de la partida (grep sobre scripts/), como hace el spec con otros casos.

## Archivos: son tuyos, DISJUNTOS con los otros dos workers
PROPIOS: scripts/progresion/**, scripts/skills/hechos.gd,
         scripts/skills/habilidades*.gd, scripts/mundo/talar.gd,
         scripts/mundo/arbol.gd, scripts/mundo/mineria.gd,
         scripts/loot/drop_table.gd,
         tests/test_fase72_progresion_conectada.gd, data/*.json (tus cambios)
TOCAR CON CUIDADO: scenes/demo/fase14_demo.gd (registrar el panel),
         scripts/core/ui_layers.gd, project.godot (InputMap, accion en espanol),
         scripts/core/opciones.gd (tecla del panel, si aplica)

## Prohibido tocar
scripts/audio/** (worker 72C), scripts/core/resultado_partida.gd,
scripts/ui/panel_final.gd, scripts/ui/panel_derrota.gd (worker 72A),
scripts/quests/** (worker 72A)

## Convenciones (spec §8 + §9) — obligatorias
Tipar todo (`var x: T`). `Array[String]` en consts. Builtins con sufijo
(`absi/clampf/maxi/mini`). Sin `get()` de 2 args sobre tipado. Sin metodos de
instancia sobre `class_name`. Un script un nodo una responsabilidad. Grupo
`gg_system` + `system_id: StringName`. Datos primero, no codigo. UI solo lee
StatBlock. Cero allocs por frame en caliente.

## Verificacion antes de darlo por hecho
1. `godot --headless --path . --import` si agregaste class_name
2. `--check-only` sobre cada script nuevo -> 0 fallos
3. `GODOT=/home/webo/Tools/godot/godot tools/run_tests.sh --smokes` -> TODO verde.
   No dejes tests en rojo.
4. Un test que falle si el sistema no esta conectado a la partida real.

## No hagas
Godot 4.7.2. No rediseñes el combate. No cambies el canon. No commitees en main.
