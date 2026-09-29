#!/usr/bin/env bash
# run_tests.sh — corre la suite headless y resume. Es lo que faltaba: había
# 80 tests y ninguna forma de correrlos todos de una vez (la regresión
# completa era manual).
#
#   tools/run_tests.sh              # los 76 test_*.gd
#   tools/run_tests.sh --smokes     # además los 4 smoke_*.gd (lentos)
#   tools/run_tests.sh test_fase50  # solo los que matcheen el filtro
#
# Cada test es `extends SceneTree` y hace `quit(<nº de fallos>)`, así que el
# exit code ES el número de fallos. Un test que no existe o no compila sale
# != 0 y también cuenta como rojo.

set -uo pipefail

GODOT="${GODOT:-$(command -v godot || echo "$HOME/Tools/godot/godot")}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -x "$GODOT" ]]; then
	echo "ERROR: no encuentro godot. Usá GODOT=/ruta/al/godot tools/run_tests.sh" >&2
	exit 127
fi

CON_SMOKES=0
FILTRO=""
for arg in "$@"; do
	case "$arg" in
		--smokes) CON_SMOKES=1 ;;
		-*) echo "flag desconocida: $arg" >&2; exit 2 ;;
		*) FILTRO="$arg" ;;
	esac
done

mapfile -t TESTS < <(ls -1 "$PROJECT"/tests/test_*.gd 2>/dev/null | sort)
if [[ $CON_SMOKES -eq 1 ]]; then
	mapfile -t SMOKES < <(ls -1 "$PROJECT"/tests/smoke_*.gd 2>/dev/null | sort)
	TESTS+=("${SMOKES[@]}")
fi

if [[ -n "$FILTRO" ]]; then
	SALIDA=()
	for t in "${TESTS[@]}"; do
		[[ "$(basename "$t")" == *"$FILTRO"* ]] && SALIDA+=("$t")
	done
	TESTS=("${SALIDA[@]}")
fi

if [[ ${#TESTS[@]} -eq 0 ]]; then
	echo "ERROR: no hay tests que corran${FILTRO:+ con el filtro '$FILTRO'}" >&2
	exit 1
fi

ROJOS=0
VERDES=0
FALLIDOS=()

for t in "${TESTS[@]}"; do
	nombre="$(basename "$t" .gd)"
	# Los smokes abren escenas reales: necesitan margen.
	if [[ "$nombre" == smoke_* ]]; then timeout=240; else timeout=120; fi

	salida=$(cd "$PROJECT" && timeout "$timeout" "$GODOT" --headless --path . \
		--script "res://tests/$nombre.gd" 2>&1)
	codigo=$?

	if [[ $codigo -eq 0 ]]; then
		VERDES=$((VERDES + 1))
		printf '  \033[32mOK\033[0m   %s\n' "$nombre"
	else
		ROJOS=$((ROJOS + 1))
		FALLIDOS+=("$nombre ($codigo)")
		printf '  \033[31mFAIL\033[0m %s  (exit %d)\n' "$nombre" "$codigo"
		# Un test en rojo vale la pena ver por qué.
		echo "$salida" | grep -iE "error|fallo|_chk|TODO VERDE" | tail -6 | sed 's/^/         /'
	fi
done

echo
echo "───────────────────────────────"
printf 'verdes: %d   rojos: %d   total: %d\n' "$VERDES" "$ROJOS" "${#TESTS[@]}"
if [[ $ROJOS -gt 0 ]]; then
	echo "en rojo:"
	printf '  · %s\n' "${FALLIDOS[@]}"
	exit 1
fi
echo "todo verde"
