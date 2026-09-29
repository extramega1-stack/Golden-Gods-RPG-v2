#!/usr/bin/env python3
"""genera_arboles.py — data/arboles.json, determinista.

Mismo contrato que generar_vetas.py (fase 45): la tala es la recolección
hermana de la minería y comparte casi todo el nodo (`Veta`).

- SEMILLA fija, sin `random` global.
- Las ciudades con plaza sacan sus árboles en un anillo exterior (1500-2600),
  para no caer en la zona segura de 40 m ni en la plaza.
- Las regiones sin plaza reparten en su propio rectángulo.
- Se rechaza una posición si cae encima de una veta o de otro árbol.

Salida opcional por argumento (mismo criterio que generar_spawns_rework.py):
el test de determinismo escribe en user:// y no toca el repo.
"""

import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROYECTO = os.path.dirname(HERE)
DESTINO = os.path.join(PROYECTO, "data", "arboles.json")
if len(sys.argv) > 1:
    DESTINO = sys.argv[1]

REGIONES_PATH = os.path.join(PROYECTO, "data", "regiones.json")
VETAS_PATH = os.path.join(PROYECTO, "data", "vetas.json")

SEMILLA = 20260929
R_MIN_ANILLO = 1500.0
R_MAX_ANILLO = 2600.0
MARGEN_ZONA_SEGURA = 40.0
POR_CIUDAD = 14
POR_REGION = 16
INTENTOS_POR_ARBOL = 60

# region -> (nombre, item_id, tinte, xp, usos, respawn_s)
ESPECIES = {
    "moon_town":        ("Roble de Liberty",   "tronco_roble",    "#4a7a3a",  6, 3, 180),
    "tierras_francas":  ("Roble de Liberty",   "tronco_roble",    "#4a7a3a",  6, 3, 180),
    "ceniza_forja":     ("Pícaro de ceniza",  "tronco_picaro",   "#6b4a2a",  7, 2, 220),
    "bosque_hondo":     ("Pino de escarcha",  "tronco_pino",     "#2f5d4a",  7, 3, 210),
    "umbral_ladon":     ("Sauce de cristal",  "tronco_sauce",    "#4a6b9c",  8, 2, 240),
    "abismo_lloroso":   ("Hongo cautivo",     "tronco_hongo",    "#4a4a3a",  7, 2, 230),
    "tierras_trueno":   ("Frembo del Trueno", "tronco_frembo",   "#7a3a2a",  9, 2, 260),
    "costa_lamento":    ("Acacia espinosa",   "tronco_acacia",   "#9c8a4a",  6, 2, 200),
    "corona_quebrada":  ("Tótem de guerra",   "tronco_totem",    "#8a6a2a",  8, 2, 250),
    "velo":             ("Muérdago del Velo", "tronco_muerdago", "#3a2a4a",  9, 2, 260),
}

LIMITE = 18432.0

# Las 9 plazas de ciudad, en el mismo orden que generar_vetas.py. Cada anillo
# cae en la región que le toca, y de ahí sale la especie.
CIUDADES = [
    (0.0, 0.0), (9966.0, 0.0), (-9966.0, 0.0), (0.0, -5358.0),
    (0.0, 9966.0), (9966.0, -9966.0), (-9966.0, -9966.0),
    (-9966.0, 9966.0), (9966.0, 9966.0),
]


def cargar(path, clave):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f).get(clave, [])
    except (OSError, ValueError):
        return []


def ocupado(x, z, puntos, margen):
    return any(
        abs(x - px) < margen and abs(z - pz) < margen
        for px, pz in puntos
    )


def main() -> int:
    rng = random.Random(SEMILLA)
    with open(REGIONES_PATH, "r", encoding="utf-8") as f:
        regiones = json.load(f)
    vetas = []
    try:
        with open(VETAS_PATH, "r", encoding="utf-8") as f:
            vetas = [(float(v["x"]), float(v["z"])) for v in json.load(f)["vetas"]]
    except (OSError, ValueError, KeyError):
        vetas = []

    def region_de(x, z):
        """La region cuyo rect semiabierto contiene (x, z), o None."""
        for reg in regiones:
            if float(reg["x0"]) <= x < float(reg["x1"]) and \
                    float(reg["z0"]) <= z < float(reg["z1"]):
                return reg
        return None

    arboles = []
    for cx, cz in CIUDADES:
        puestos = 0
        intentos = 0
        while puestos < POR_CIUDAD and intentos < POR_CIUDAD * INTENTOS_POR_ARBOL:
            intentos += 1
            ang = rng.uniform(0.0, 2.0 * math.pi)
            dist = rng.uniform(R_MIN_ANILLO, R_MAX_ANILLO)
            x = max(-LIMITE, min(LIMITE, cx + math.cos(ang) * dist))
            z = max(-LIMITE, min(LIMITE, cz + math.sin(ang) * dist))

            reg = region_de(x, z)
            if reg is None:
                continue
            rid = str(reg.get("id", ""))
            especie = ESPECIES.get(rid)
            if especie is None:
                continue
            nombre, item, tinte, xp, usos, respawn = especie
            # No encima de una veta ni de otro arbol.
            ya = [(a["x"], a["z"]) for a in arboles]
            if ocupado(x, z, vetas, 10.0) or ocupado(x, z, ya, 12.0):
                continue

            arboles.append({
                "id": "arbol_%02d" % len(arboles),
                "nombre": "%s — %s" % (nombre, reg.get("nombre", rid)),
                "region": rid,
                "item_id": item,
                "cantidad": rng.choice([1, 1, 2]),
                "usos": usos,
                "respawn_s": respawn,
                "xp": xp,
                "nivel": int(reg.get("nivel_min", 1)),
                "tinte": tinte,
                "x": round(x, 3),
                "z": round(z, 3),
            })
            puestos += 1

    with open(DESTINO, "w", encoding="utf-8") as f:
        json.dump({"version": 1, "arboles": arboles}, f, ensure_ascii=False, indent=2)
        f.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
