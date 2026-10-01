#!/usr/bin/env bash
# Convierte los FBX de Mixamo a clips del juego.
#
# POR QUE CADA CLIP TIENE SU PROPIO --duracion: no es un parametro estetico.
# La caminata tiene que calzar con la velocidad del codigo (100 cm/s) o los
# pies patinan, y el golpe tiene que entrar en los 0,83 s que el combate ya
# asumia, o cada ataque se siente como un castigo.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT=/home/webo/Tools/godot/godot
FUENTE=anim/fuente
DESTINO=anim/clips
LOG=anim/clips/convertir.log
mkdir -p "$DESTINO"
: > "$LOG"

convertir() {
  local clip="$1" destino="$2"; shift 2
  local fbx="$FUENTE/mixamo_$clip.fbx"
  if [ ! -f "$fbx" ]; then
    printf '  [FALTA] %-16s falta %s\n' "$clip" "$fbx" | tee -a "$LOG"
    return 1
  fi
  local extra=("$@")
  local args=(--fbx="res://$fbx" --salida="res://$DESTINO/$destino.tres")
  [ ${#extra[@]} -gt 0 ] && args+=("${extra[@]}")
  "$GODOT" --headless --path . --script res://tools/retarget_mixamo.gd \
    -- "${args[@]}" >>"$LOG" 2>&1
  if grep -q "ERROR\|SCRIPT ERROR" <(tail -20 "$LOG"); then
    printf '  [ERROR]  %-16s\n' "$clip" | tee -a "$LOG"
    return 1
  fi
  # La duracion se lee de la linea del conversor, no de un grep sobre toda la
  # salida: ese grep se agarrava del primer numero que encontraba en pantalla
  # (la version de Godot) y reportaba 4,7 s para los cuatro clips.
  local d
  d=$(grep -oE 'cuadros x [0-9]+ huesos \| dur [0-9.]+' "$LOG" | tail -1 \
      | grep -oE 'dur [0-9.]+' | grep -oE '[0-9.]+')
  printf '  [LISTO]  %-16s -> %-12s %s s\n' "$clip" "$destino.tres" "${d:-?}" | tee -a "$LOG"
}

echo "Convirtiendo animaciones de Mixamo:"
convertir idle   idle   --loop=1 --blend=0.25
# El walk NO se retimea: el sistema ya ajusta la velocidad con el reloj del
# arbol (`ritmo`), y retimear el clip a mano es pelearse con el diseno.
# El blend de 0,25 media el ultimo cuarto del ciclo y hace flotar mas el pie
# (27 cm contra 21 cm medidos). Con 0,10 el empalme del loop se sigue
# suavizando y el pie se mantiene. El empalme IMPORTA: el clip corre a ~4,3
# ciclos por segundo, o sea que sin el el salto del loop se ve 4 veces por
# segundo.
# El empalme del loop se resuelve cortando el ciclo en su periodo REAL, no
# mezclando el final hacia el principio (eso deformaba el apoyo y salia
# moonwalk). Ver `_mejor_periodo` en el conversor.
convertir walk   walk   --loop=1 --blend=0
convertir attack attack --duracion=0.83
convertir die    die
echo "Log: $LOG"
