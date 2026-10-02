# 72C — Cerrar los huecos de audio

## Por que esto existe
El audio esta muy bien construido: sintetizador procedural con ADSR y variantes
(scripts/audio/sintetizador.gd), musica adaptativa de 4 capas con director
(scripts/audio/musica.gd, director_musica.gd). Pero tiene huecos que se ven y se
oyen:

## Los 4 hechos, verificados. NO los re-descubras

### 1. La pantalla de titulo es MUDA
`AudioJuego`, `Musica` y `DirectorMusica` se crean en
`scenes/demo/fase9_demo.gd:102-117`, que es la escena de JUEGO.
`pantalla_titulo.gd:51-53` solo construye escena 3D y UI. No hay musica ni SFX
en el menu principal. El juego arranca en silencio.

### 2. El volumen guardado no se aplica en el titulo ni en la carga
`Opciones.cargar()` + `aplicar()` se llaman en `fase14_demo.gd:275-276`, dentro
de `_al_mundo_listo()`. Es decir, DESPUES de la pantalla de carga. Si el jugador
tuvo la musica baja, la carga y el titulo estan a volumen lleno.

### 3. 15 de 36 sonidos NUNCA se disparan
`data/sonidos.json` define 36 recetas. Quince no tienen call site:
`talar`, `romper`, `minar`, `construir`, `fogata`, `comer`, `beber`, `hambre`,
`sed`, `enfermo`, `descansar`, `murio_jugador`, `viajar`, `descubrir`,
`proyectil`.
Los tres primeros son sonidos de MECANICAS QUE YA EXISTEN en el juego: se tala, se
mina y se construye, y no suenan.

### 4. `SonidoUI` tiene 8 metodos y UN solo call site
`scripts/ui/sonido_ui.gd` define `clic`, `abrir_panel`, `error`, `mision`,
`level_up`, `hecho`, `dano_recibido`, `cerrar_panel`. Solo se usa
`cerrar_panel` (panel_inventario.gd:287). Los otros 7 estan muertos.
Y el bus `Ambiente` se CREA (audio_juego.gd:242) pero no tiene ni un solo player:
no hay ambiente por zona (viento, agua, aves) aunque el spec lo contempla
(MASTER_SPEC.md:591).

## Qué hacer

1. Audio en el titulo: instancia `AudioJuego` + `Musica` en la pantalla de
   titulo, en un estado de menu. Limpialo al entrar a partida.
2. Aplicar `Opciones.cargar()` + `aplicar()` ANTES de la pantalla de carga, o en
   el titulo, para que el volumen guardado valga desde el primer sonido.
3. Disparar los 15 sonidos.call sites en la mecanica que les corresponde:
   talar/minar/construir/fogata en el mundo; comer/beber/hambre/sed/enfermo/
   descansar en vitals y cocina; murio_jugador en la muerte; viajar en el viaje
   rapido; descubrir en el banner de region; proyectil en el pool de proyectiles.
4. Cablear los 7 `SonidoUI` muertos: clic en botones, abrir panel, error al no
   poder equipar/usar, mision al aceptar/completar, level_up al subir de nivel,
   hecho al desbloquear un Hecho, dano_recibido al recibir dano.
5. Ambiente por zona: al menos viento y agua en el bus `Ambiente`, con
   atenuacion por distancia como hace el pool 3D (audio_juego.gd:264-272).
6. Anti-spam: el pool ya lo tiene (audio_juego.gd:207-211). Respetalo.

## Tests
`tests/test_fase72_audio.gd`, extends SceneTree, `_chk()` + `quit(_fallos)`.
Incluye un check que verifique que CADA receta de `data/sonidos.json` tiene al
menos un call site real en el codigo de juego (grep sobre scripts/), no en tests.
Ese check es el que va a cazar los 15 huecos y a impedir que vuelvan.

## Archivos: tuyos, DISJUNTOS
PROPIOS: scripts/audio/**, scripts/ui/sonido_ui.gd, scripts/mundo/fogata.gd,
         scripts/mundo/refugio*.gd, tests/test_fase72_audio.gd, data/sonidos.json
TOCAR CON CUIDADO: scenes/titulo/pantalla_titulo.gd, scenes/demo/fase14_demo.gd,
         scenes/demo/fase12_demo.gd, scripts/core/opciones.gd,
         scripts/mundo/terreno.gd, scripts/mundo/clima.gd, project.godot

## Prohibido tocar
scripts/progresion/**, scripts/skills/**, scripts/mundo/talar.gd,
scripts/mundo/mineria.gd (worker 72B), scripts/core/resultado_partida.gd,
scripts/ui/panel_final.gd, scripts/ui/panel_derrota.gd, scripts/quests/**,
scripts/player/player.gd (worker 72A)

## Convenciones (spec §8 + §9)
Tipar todo. `Array[String]` en consts. Builtins con sufijo. Sin allocs por frame
en caliente — OJO: el audio se genera en memoria, no generes WAV por frame.
Un script un nodo una responsabilidad. Grupo `gg_system` + `system_id`.
Mallas/materiales compartidos. Datos primero.

## Verificacion antes de darlo por hecho
1. `godot --headless --path . --import` si agregaste class_name
2. `--check-only` sobre cada script nuevo -> 0 fallos
3. `GODOT=/home/webo/Tools/godot/godot tools/run_tests.sh --smokes` -> TODO verde
4. ESCUCHA de verdad si puedes. El spec (MASTER_SPEC.md:2474-2476) dice que el
   audio "nunca se oyo nunca": esta implementado y testeado y nadie lo escucho.
   Si podes, lanzalo y escucha. Si no podes, decilo explicitamente en tu informe
   en vez de darlo por bueno.

## No hagas
Godot 4.7.2. No commitees en main.
