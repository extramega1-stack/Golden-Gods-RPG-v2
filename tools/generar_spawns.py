#!/usr/bin/env python3
"""Generador de spawns para la Fase 12 (Mundo abierto real) — Golden Gods RPG remake.

Lee los creeps del proyecto legado (cat == 'creep') y los porta a los 3
arquetipos data-driven del remake, produciendo data/spawns.json con entradas
{arquetipo, x, z, nivel} en coordenadas Godot.

REGLA NIVEL -> ARQUETIPO (definida para esta fase, coherente con los tiers de
dificultad del legado: niveles altos = zonas de élite):
    nivel <= 30          -> goblin   (zona de bajo nivel;  361 spawns)
    30 < nivel <= 200    -> lobo     (zona de nivel medio; 458 spawns)
    nivel > 200          -> ogro     (zona de alto nivel;  302 spawns)
La regla es estable y monotona: un nivel mas alto nunca mapea a un arquetipo
de tier inferior. El `nivel` original se preserva intacto en cada entrada para
que el escalado de stats del enemigo siga funcionando como en el legado.

CONVERSION WC3 -> Godot (verificada del legado, scripts/world.gd):
    gx = x
    gz = 4096 - y
Las coordenadas se restringen (clamp) al terreno jugable [-18432, 18432]
(104 creeps del legado quedan al sur del terreno, gz > 18432; se recortan al
borde en vez de descartarse para no perder spawns).

ZONA SEGURA: se excluyen spawns a menos de 40 m de la aldea inicial (0, 0).
(En la practica, ninguno de los 1121 creeps cae ahi, pero la regla queda
blindada si el legado crece.)

Determinista y re-ejecutable: no usa azar, recorre la fuente en orden,
escribe JSON con formato fijo. Dos corridas -> mismo SHA-256.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROYECTO = os.path.dirname(HERE)                    # godot-rpg-remake/
LEGADO = "/home/hatch/workspace/godot-rpg"          # CONGELADO: solo lectura

LIMITE = 18432.0        # medio ancho del terreno jugable (m)
RADIO_SEGURO = 40.0     # m alrededor de la aldea inicial (0, 0)
CENTER_Y = 4096.0       # conversion WC3 -> Godot (legado: gz = 4096 - y)


def arquetipo_de(nivel: int) -> str:
    """REGLA NIVEL -> ARQUETIPO (ver docstring del modulo)."""
    if nivel <= 30:
        return "goblin"
    if nivel <= 200:
        return "lobo"
    return "ogro"


def main() -> int:
    fuente = os.path.join(LEGADO, "data", "creatures.json")
    destino = os.path.join(PROYECTO, "data", "spawns.json")

    with open(fuente, "r", encoding="utf-8") as f:
        criaturas = json.load(f)

    spawns = []
    excluidos_segura = 0
    recortados = 0
    for c in criaturas:
        if c.get("cat") != "creep":
            continue
        gx = float(c["x"])
        gz = CENTER_Y - float(c["y"])
        nivel = int(c["level"])
        if math.hypot(gx, gz) < RADIO_SEGURO:
            excluidos_segura += 1
            continue
        cx = min(max(gx, -LIMITE), LIMITE)
        cz = min(max(gz, -LIMITE), LIMITE)
        if cx != gx or cz != gz:
            recortados += 1
        spawns.append({
            "arquetipo": arquetipo_de(nivel),
            "x": round(cx, 3),
            "z": round(cz, 3),
            "nivel": nivel,
        })

    with open(destino, "w", encoding="utf-8") as f:
        json.dump(spawns, f, indent=2, ensure_ascii=False)
        f.write("\n")

    conteo = {}
    for s in spawns:
        conteo[s["arquetipo"]] = conteo.get(s["arquetipo"], 0) + 1
    sha = hashlib.sha256(open(destino, "rb").read()).hexdigest()
    print(f"[SPAWNS] total={len(spawns)} " +
          " ".join(f"{k}={conteo.get(k, 0)}" for k in ("goblin", "lobo", "ogro")) +
          f" excluidos_zona_segura={excluidos_segura} recortados_a_limite={recortados}")
    print(f"[SPAWNS] escrito {destino} sha256={sha}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
