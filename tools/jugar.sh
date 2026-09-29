#!/usr/bin/env bash
# jugar.sh — corre la PRUEBA DE PARTIDA COMPLETA, de punta a punta.
#
# ESTO NO ES un test por sistema. Carga la pantalla de título real, crea un
# personaje, entra al mundo, camina, pelea, lootea, sube de nivel, habla con un
# NPC, cocina en una fogata, construye en un refugio, guarda, sale al título,
# recarga, y abre y cierra cada panel con ESC. Cada paso comprueba que LA UI SE
# MOVIÓ, no que la función se pueda llamar.
#
# POR QUÉ `--fixed-fps 60`: sin él el bucle headless corre a ~145 FPS y un
# "segundo" de partida dura 6 ms de reloj, así que "el vital baja con el
# tiempo" no se puede comprobar. Con `--fixed-fps` cada frame vale exactamente
# 1/60 de segundo de JUEGO. El p95 de frame time se mide aparte, con reloj de
# pared, así que el número que sale es real.
#
# USO
#   tools/jugar.sh                 # partida completa SIN la caminata al bosque
#   tools/jugar.sh --arboles       # partida completa CON la caminata al bosque
#   tools/jugar.sh --verbose       # además del latido de progreso
#   GODOT=/ruta/al/godot tools/jugar.sh
#
# CÓMO LEER LA SALIDA
#   Cada línea es un chequeo. "PASA" es verde, "FALLA" es rojo con el motivo
#   escrito abajo, y "OMITIDO" es un paso que no se pudo cubrir (y por qué).
#   Abajo está el p95 de frame time de toda la partida.
#   EXIT CODE = número de pasos en rojo. 0 = la partida anda.
#
# LIMITACIÓN DECLARADA: headless usa drivers dummy, así que el p95 mide CPU
# (lógica + física) y NO la GPU. Para la GPU está tools/bench_gpu.gd, que
# necesita la ventana con el foco.

set -uo pipefail

GODOT="${GODOT:-$(command -v godot || echo "$HOME/Tools/godot/godot")}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -x "$GODOT" ]]; then
	echo "ERROR: no encuentro godot. Usá GODOT=/ruta/al/godot tools/jugar.sh" >&2
	exit 127
fi

CON_ARBOLES=0
VERBOSE=0
for arg in "$@"; do
	case "$arg" in
		--arboles) CON_ARBOLES=1 ;;
		--verbose) VERBOSE=1 ;;
		-h | --help) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
		*) echo "flag desconocida: $arg" >&2; exit 2 ;;
	esac
done

# El `.godot/` es el caché de importación. En un worktree recién clonado no
# existe y sin él todo script que use un `class_name` falla al parsear (la
# trampa de AGENTS.md). Se importa una vez.
if [[ ! -d "$PROJECT/.godot" ]]; then
	echo "[jugar] importando el proyecto la primera vez..."
	(cd "$PROJECT" && "$GODOT" --headless --path . --import >/dev/null 2>&1)
fi

# La partida con el bosque son 1792 u de caminata a 6 u/s: ~300 s de tiempo de
# JUEGO, que con `--fixed-fps` son del orden de 2 min de reloj. Sin eso, la
# partida corta dura menos de un minuto.
TIMEOUT=1800
ARGS=()
if [[ $CON_ARBOLES -eq 0 ]]; then
	ARGS=(-- --sin-arboles)
else
	TIMEOUT=2700
fi
if [[ $VERBOSE -eq 0 ]]; then
	ARGS+=(--sin-latido)
fi

echo "[jugar] godot:  $GODOT"
echo "[jugar] corre:  la partida completa de punta a punta"
echo "[jugar] hasta: ${TIMEOUT}s de reloj"
echo

cd "$PROJECT"
timeout "$TIMEOUT" "$GODOT" --headless --path . --fixed-fps 60 \
	--script res://tests/playtest_completo.gd "${ARGS[@]}" 2>&1 \
	| grep -vE '^\[Fase|^ERROR: Condition|^\s+at: |^\s+\[[0-9]\]|GDScript backtrace|ObjectDB instances|^\s+at: cleanup'
CODIGO=${PIPESTATUS[0]}

echo
if [[ $CODIGO -eq 0 ]]; then
	echo "[jugar] la partida anda de punta a punta (0 pasos en rojo)."
else
	echo "[jugar] hay $CODIGO paso(s) en rojo. Mirá el RESUMEN de arriba:"
	echo "[jugar] cada FALLA dice qué no se movió y dónde."
fi
exit $CODIGO
