#!/usr/bin/env bash
# animar_clips.sh — reescribe los cuatro clips de un `.glb` YA riggeado.
#
# POR QUÉ EXISTE: la animación se "arregló" cuatro veces sin tocar los clips y
# el sintoma que ve el usuario siguió ahí ("como si flotara y con las manos
# levantadas abiertas"). El trabajo de verdad estaba en el `.glb`, no en el
# código, y este es el camino para arreglarlo sin volver a tocar la
# retopología ni los pesos (que tienen siete trampas ya pagadas en AGENTS.md).
#
# USO
#   tools/animar_clips.sh models/clase_guerrero.glb
#   tools/animar_clips.sh --todos                 los seis, de uno en uno
#   tools/animar_clips.sh --sin-copia models/x.glb
#   BLENDER=/ruta/blender tools/animar_clips.sh models/x.glb
#
# Un `.glb` es IRREVERSIBLE: por eso copia el original a
# `build/originales_clips/<nombre>.glb` antes de escribir, y solo escribe si el
# Blender terminó con los cuatro clips dentro. Si algo sale mal, la copia está.
#
# LO QUE NO TOCA: la malla, los pesos, el esqueleto. Se borran los cuatro
# `action` viejos y se escriben cuatro nuevos. El script verifica después que
# la piel sigue ahí: si el `.glb` saliera sin JOINTS_0/WEIGHTS_0 o con menos
# de 19 huesos, avisa y devuelve error.

set -uo pipefail

BLENDER="${BLENDER:-$(command -v blender || echo /usr/bin/blender)}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPIA="$RAIZ/build/originales_clips"

if [[ ! -x "$BLENDER" ]]; then
	echo "ERROR: no encuentro blender. Usá BLENDER=/ruta/blender tools/animar_clips.sh" >&2
	exit 127
fi

CON_COPIA=1
LISTA=()
for arg in "$@"; do
	case "$arg" in
		--todos)
			LISTA+=(models/clase_guerrero.glb models/clase_arquero.glb
			        models/clase_clerigo.glb models/clase_mago.glb
			        models/clase_daguero.glb models/bandido_rig.glb)
			;;
		--sin-copia) CON_COPIA=0 ;;
		-h | --help) sed -n '2,26p' "${BASH_SOURCE[0]}"; exit 0 ;;
		*) LISTA+=("$arg") ;;
	esac
done

if [[ ${#LISTA[@]} -eq 0 ]]; then
	echo "uso: tools/animar_clips.sh models/CLASE.glb | --todos" >&2
	exit 2
fi

fallos=0
for modelo in "${LISTA[@]}"; do
	ruta="$RAIZ/$modelo"
	if [[ ! -f "$ruta" ]]; then
		echo "[ANIM] no existe $modelo" >&2
		fallos=$((fallos + 1))
		continue
	fi
	nombre="$(basename "$modelo")"
	salida="$RAIZ/build/anim71/$nombre"
	mkdir -p "$(dirname "$salida")"
	if [[ $CON_COPIA -eq 1 ]]; then
		mkdir -p "$COPIA"
		if [[ ! -f "$COPIA/$nombre" ]]; then
			cp "$ruta" "$COPIA/$nombre"
			echo "[ANIM] copia del original: build/originales_clips/$nombre"
		fi
	fi

	echo "[ANIM] $nombre"
	if ! "$BLENDER" --background --python "$RAIZ/tools/animar_clips.py" -- \
			"$ruta" "$salida" 2>&1 | grep -E '^\[ANIM\]|^ERROR'; then
		echo "[ANIM] $nombre: Blender falló" >&2
		fallos=$((fallos + 1))
		continue
	fi

	# El `.glb` escrito tiene que traer los cuatro clips y la piel intacta. Sin
	# esta comprobación, un `.glb` sin animaciones parece un éxito y es un
	# modelo congelado.
	if ! python3 - "$salida" <<'PY'
import json, struct, sys
ruta = sys.argv[1]
d = open(ruta, "rb").read()
total = struct.unpack_from("<III", d, 0)[2]
off, g = 12, None
while off < total:
    largo, tipo = struct.unpack_from("<II", d, off)
    if tipo == 0x4E4F534A:
        g = json.loads(d[off + 8:off + 8 + largo].decode("utf-8"))
    off += 8 + largo
nombres = sorted(a["name"] for a in g.get("animations", []))
pide = ["attack", "die", "idle", "walk"]
prim = g["meshes"][0]["primitives"][0]["attributes"]
ok = True
if nombres != pide:
    print("  ERROR: clips %s, se esperaban %s" % (nombres, pide)); ok = False
for clave in ("JOINTS_0", "WEIGHTS_0"):
    if clave not in prim:
        print("  ERROR: la piel se perdio (falta %s)" % clave); ok = False
if len(g.get("skins", [{}])[0].get("joints", [])) != 19:
    print("  ERROR: el esqueleto no tiene 19 huesos"); ok = False
if ok:
    largos = []
    for a in g["animations"]:
        acc = g["accessors"][a["samplers"][0]["input"]]
        largos.append("%s=%.3fs" % (a["name"], acc["max"][0]))
    print("  OK: 4 clips (%s) | piel con pesos | 19 huesos" % " ".join(largos))
sys.exit(0 if ok else 1)
PY
	then
		fallos=$((fallos + 1))
		continue
	fi
	cp "$salida" "$ruta"
	echo "[ANIM] escrito $modelo"
done

if [[ $fallos -gt 0 ]]; then
	echo "[ANIM] $fallos modelo(s) sin escribir; los originales siguen intactos" >&2
	exit 1
fi
exit 0
