#!/usr/bin/env bash
# anim_medida.sh — mide la animación y deja un informe con números ARRIBA.
#
# POR QUÉ EXISTE: la animación se "arregló" tres veces. En las tres se
# cambiaron líneas sin mirar un solo número, y el usuario siguió viendo que
# camina horrible. Esto es el instrumento que faltaba: corre la bancada, saca
# la tira de PNGs, y escribe un informe que se puede DIFFEAR contra el de la
# corrida anterior.
#
# USO
#   tools/anim_medida.sh                        guerrero, con tira y diff
#   tools/anim_medida.sh --clase=clerigo        otra clase
#   tools/anim_medida.sh --sin-tira              sin ventana: solo números
#   tools/anim_medida.sh --muestras=30           menos instantes por ciclo
#   tools/anim_medida.sh --linea-base            copia el informe a docs/
#   tools/anim_medida.sh --comparar=otro.md      diff contra otro informe
#   GODOT=/ruta/al/godot tools/anim_medida.sh
#
# CÓMO LEER LA SALIDA
#   Los números del ciclo de marcha salen ARRIBA, en una tabla. Abajo está el
#   detalle, y abajo del todo la fecha. Entre dos corridas, `diff` los bloques
#   de arriba: si el patinaje bajó de 120 cm a 5 cm, se ve en tres líneas.
#   La sección "No se pudo medir" lista lo que el instrumento no pudo hacer, con
#   el motivo. Un hueco es información; un número inventado es veneno.
#
# LA TIRA NECESITA VENTANA, y por eso va aparte. Sin ventana Godot usa el
# driver dummy y las fotos salen de un gris; la herramienta lo dice y sigue,
# así que `--sin-tira` no pierde nada del resto.

set -uo pipefail

GODOT="${GODOT:-$(command -v godot || echo "$HOME/Tools/godot/godot")}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -x "$GODOT" ]]; then
	echo "ERROR: no encuentro godot. Usá GODOT=/ruta/al/godot tools/anim_medida.sh" >&2
	exit 127
fi

CLASE="guerrero"
CON_TIRA=1
LINEA_BASE=0
COMPARAR=""
MOSTRAR_SOLO_NUMEROS=1
EXTRA=()
for arg in "$@"; do
	case "$arg" in
		--clase=*) CLASE="${arg#*=}" ;;
		--sin-tira) CON_TIRA=0 ;;
		--linea-base) LINEA_BASE=1 ;;
		--comparar=*) COMPARAR="${arg#*=}" ;;
		--todo) MOSTRAR_SOLO_NUMEROS=0 ;;
		--muestras=* | --modelo=* | --salida=*) EXTRA+=("$arg") ;;
		-h | --help) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
		*) echo "flag desconocida: $arg" >&2; exit 2 ;;
	esac
done

SALIDA="build/informe_animacion"
INFORME="$PROJECT/$SALIDA/informe_animacion.md"
PRECIO="$SALIDA/informe_anterior.md"
TIRA="build/tira_animacion/tira.json"

# El `.godot/` es el caché de importación. En un worktree recién clonado no
# existe y sin él todo script que use un `class_name` falla al parsear.
if [[ ! -d "$PROJECT/.godot" ]]; then
	echo "[medida] importando el proyecto la primera vez..."
	(cd "$PROJECT" && "$GODOT" --headless --path . --import >/dev/null 2>&1)
fi

cd "$PROJECT" || exit 1

echo "[medida] 1/3 · bancada (números, sin tira todavía)"
"$GODOT" --headless --path . --fixed-fps 60 \
	--script res://tools/anim_medida/bancada_animacion.gd -- \
	--clase="$CLASE" --salida="$SALIDA" "${EXTRA[@]+"${EXTRA[@]}"}" \
	>/dev/null 2>&1

if [[ $CON_TIRA -eq 1 ]]; then
	echo
	echo "[medida] 2/3 · tira de PNGs (necesita ventana)"
	timeout 240 "$GODOT" --path . \
		--script res://tools/anim_medida/tira_animacion.gd -- \
		--clase="$CLASE" 2>/dev/null | grep '^\[TIRA\]'
	# La bancada se corre OTRA vez para que el informe traiga la tira. Es
	# un segundo y evita mantener estado entre dos procesos.
	echo "[medida] 3/3 · segunda corrida, para pegar la tira al informe"
	"$GODOT" --headless --path . --fixed-fps 60 \
		--script res://tools/anim_medida/bancada_animacion.gd -- \
		--clase="$CLASE" --salida="$SALIDA" "${EXTRA[@]+"${EXTRA[@]}"}" \
		>/dev/null 2>&1
else
	echo
	echo "[medida] 2/3 · tira omitida (--sin-tira)"
fi

# Guardar el informe anterior para el diff de la próxima corrida. Va ANTES de
# escribir el nuevo, y el "primer Informe" no cuenta como comparación.
if [[ -f "$INFORME" ]]; then
	cp "$INFORME" "$PRECIO"
fi
if [[ $LINEA_BASE -eq 1 ]]; then
	"$GODOT" --headless --path . --fixed-fps 60 \
		--script res://tools/anim_medida/bancada_animacion.gd -- \
		--clase="$CLASE" --salida="$SALIDA" --linea-base "${EXTRA[@]+"${EXTRA[@]}"}" \
		>/dev/null 2>&1
	echo "[medida] linea base escrita en docs/INFORME_ANIMACION.md"
fi

echo
echo "[medida] números de ESTA corrida (los que se discuten):"
sed -n '/^## Números/,/^## No se pudo medir/p' "$INFORME"
echo
if [[ -n "$COMPARAR" && -f "$COMPARAR" ]]; then
	echo "[medida] diff contra $COMPARAR (sólo el bloque de números)"
	sed -n '/^## Números/,/^## No se pudo medir/p' "$COMPARAR" >/tmp/anim_antes.txt
	sed -n '/^## Números/,/^## No se pudo medir/p' "$INFORME" >/tmp/anim_despues.txt
	diff -u /tmp/anim_antes.txt /tmp/anim_despues.txt && echo "(sin cambios)"
	rm -f /tmp/anim_antes.txt /tmp/anim_despues.txt
elif [[ -f "$PRECIO" ]]; then
	echo "[medida] cambió respecto de la corrida anterior. diff:"
	sed -n '/^## Números/,/^## No se pudo medir/p' "$PRECIO" >/tmp/anim_antes.txt
	sed -n '/^## Números/,/^## No se pudo medir/p' "$INFORME" >/tmp/anim_despues.txt
	diff -u /tmp/anim_antes.txt /tmp/anim_despues.txt && echo "(sin cambios)"
	rm -f /tmp/anim_antes.txt /tmp/anim_despues.txt
else
	echo "[medida] primera corrida: no hay informe anterior con que comparar."
fi

echo
if [[ $MOSTRAR_SOLO_NUMEROS -eq 0 ]]; then
	cat "$INFORME"
fi
echo "[medida] informe: $INFORME"
if [[ -f "$TIRA" ]]; then
	echo "[medida] tira:    build/tira_animacion/tira_mundo.png y tira_lugar.png"
fi
exit 0
