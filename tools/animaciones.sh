#!/usr/bin/env bash
# Convierte TODOS los FBX de Mixamo que haya en anim/fuente/ a clips del juego.
#
# POR QUE UN SCRIPT Y NO CUATRO COMANDOS: el conversor es uno por archivo, y
# cuatro comandos manuales con tres flags cada uno es la forma facil de que uno
# quede mal escrito y el fallo se descubra en el juego, no aca. Y para descubrir
# que a un clip se le olvido el nombre hay que jugar, no compilar.
#
# USO:
#   1. Entrar a mixamo.com con una cuenta de Adobe.
#   2. Descargar CADA animacion como FBX, con "Without Skin" y 30 fps.
#   3. Nombrarlos asi y meterlos en anim/fuente/:
#        mixamo_idle.fbx
#        mixamo_walk.fbx
#        mixamo_attack.fbx
#        mixamo_die.fbx
#      El nombre del archivo es el del clip del juego, que solo acepta cuatro:
#      idle, walk, attack, die. Verificado: son los que pide el codigo.
#   4. Correr ESTE SCRIPT. Y antes, una vez, el import de Godot.
#
#   bash tools/animaciones.sh
#
# QUE HACE, en orden:
#   1. Importa los FBX nuevos, porque Godot no ve un archivo que no importo y
#      el error sale como "el clip no existe", que no dice nada de la causa.
#   2. Corre el conversor sobre cada FBX.
#   3. Muestra cuantos huesos quedaron mapeados, porque 0 es el sintoma del bug
#      del mapa y hay que verlo en el momento, no tres dias despues.

set -uo pipefail

GODOT="${GODOT:-/home/webo/Tools/godot/godot}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FUENTE="$RAIZ/anim/fuente"
DESTINO="$RAIZ/anim/clips"

CLIPS=(idle walk attack die)

if [ ! -x "$GODOT" ]; then
	echo "ERROR: no encuentro Godot en $GODOT"
	echo "       ponelo con:  GODOT=/ruta/al/godot bash tools/animaciones.sh"
	exit 1
fi

cd "$RAIZ" || exit 1

# 1) el import. Sin esto, Godot no conoce los FBX nuevos.
echo "== 1/3 importando FBX =="
"$GODOT" --headless --path . --import >/dev/null 2>&1

# 2) el conversor, uno por clip.
echo "== 2/3 convirtiendo =="
mkdir -p "$DESTINO"
convertidos=0
fallidos=0
for c in "${CLIPS[@]}"; do
	fbx="anim/fuente/mixamo_${c}.fbx"
	if [ ! -f "$fbx" ]; then
		echo "   -- ${c}: falta anim/fuente/mixamo_${c}.fbx"
		fallidos=$((fallidos + 1))
		continue
	fi
	# El nombre del clip DENTRO del FBX no se sabe de antemano: Mixamo le pone
	# el suyo, y Godot lo prefija con el nombre del esqueleto. Se lista lo que hay
	# y se usa el primero, que con un FBX de Mixamo es el unico.
	clip=$("$GODOT" --headless --path . --script res://tools/_listar_clips.gd -- \
		--fbx="res://anim/fuente/mixamo_${c}.fbx" 2>/dev/null \
		| grep -m1 "^CLIP=" | cut -d= -f2-)
	if [ -z "$clip" ]; then
		echo "   !! ${c}: el FBX no importo o no tiene animacion"
		fallidos=$((fallidos + 1))
		continue
	fi
	salida="$("$GODOT" --headless --path . --script res://tools/retarget_mixamo.gd -- \
		--fbx="res://${fbx#./}" --clip="$clip" \
		--salida="res://anim/clips/${c}.tres" 2>&1)"
	mapeados=$(echo "$salida" | grep -m1 "mapeados:" | grep -oE "mapeados: [0-9]+" | grep -oE "[0-9]+")
	if [ -n "$mapeados" ] && [ "$mapeados" -gt 0 ]; then
		echo "   ok ${c}: ${mapeados} huesos, clip '${clip}'"
		convertidos=$((convertidos + 1))
	else
		echo "   !! ${c}: 0 huesos mapeados. El FBX no es de Mixamo, o el nombre"
		echo "      del esqueleto no es mixamorig_. Pasa --ayuda al conversor."
		fallidos=$((fallidos + 1))
	fi
done

# 3) el resumen, que es lo que uno lee para saber si sirvio.
echo "== 3/3 resultado =="
echo "   convertidos: ${convertidos} de ${#CLIPS[@]}"
if [ "$fallidos" -gt 0 ]; then
	echo ""
	echo "LO QUE FALTA, y es lo unico que hay que hacer:"
	echo "  entras a https://www.mixamo.com con tu cuenta de Adobe"
	echo "  para cada una: animacion -> Download -> 'Without Skin' -> FBX"
	echo "  la guardas como anim/fuente/mixamo_<nombre>.fbx"
	echo "  y volves a correr este script."
	echo ""
	echo "Nombres que acepta: ${CLIPS[*]}"
	echo ""
	echo "LIMITE QUE NO SE ARREGLA: el juego tiene 30 huesos de dedo y Mixamo no"
	echo "trae dedos, asi que los dedos quedan en reposo. No van a cerrar ni a"
	echo "agarrar. Para eso hay que bajar el FBX con los dedos de Mixamo"
	echo "('Con Fingers' en el selector de esqueleto) y re-rigear."
fi
