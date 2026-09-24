#!/usr/bin/env python3
"""Generador determinista de spawns para el REWORK 2026 (Fase 15) — Golden Gods RPG.

Reemplaza el port de fase 12 (1121 creeps del legado WC3) por spawns generados
de forma determinista sobre las 10 regiones de data/regiones.json.

Contrato de salida (igual que fase 12): data/spawns.json, array de
{arquetipo, x, z, nivel} en coordenadas Godot.

REGLA NIVEL -> ARQUETIPO (misma que fase 12, tools/generar_spawns.py):
    nivel <= 30          -> goblin
    30 < nivel <= 200    -> lobo
    nivel > 200          -> ogro
Con las bandas actuales (1-70) todos los spawns son goblin: la variedad de
arquetipo aparecera cuando se anadan bandas por encima de 30. La regla es
estable y monotona: un nivel mas alto nunca mapea a un tier inferior. El
`nivel` elegido se preserva intacto en cada entrada.

DISTRIBUCION (semilla fija SEMILLA = 20260922, random.Random determinista):
  - Moon Town: 24 spawns de nivel 1-5 en el anillo 800 < r < 1450 (fuera del
    disco de la ciudad donde el worker de ciudad construye, dentro de la
    region).
  - Las otras 9 regiones: 1097 spawns repartidos por area (resto mayor),
    posicion uniforme dentro del rectangulo con margen de 8 u, nivel
    uniforme entero dentro de la banda [nivel_min, nivel_max] de su region.

ZONAS SEGURAS (fase 15): ningun spawn a menos de 40 m del centro de ninguna
de las 9 ciudades (Moon Town + 8 secundarias de data/portales_temp.json).
Se remuestrea con el mismo rng hasta salir de la zona segura.

PACK DE PRUEBA (fase 18.2+): 6 mobs fijos cerca de la plaza de Moon Town
(ver PACK_PRUEBA) para probar el combate; el total es 1127 = 1121 de
distribucion + 6 del pack.

PACK DE JEFES (fase 22, P2 contenido): 6 jefes de fragmento fijos, uno
cerca de cada ciudad de su cadena (ver PACK_JEFES). Llevan
"grupo": "jefe_fragmento" para eximirlos de la regla nivel -> arquetipo
(son arquetipos unicos, no tiers del generador) y de los conteos por
arquetipo. El total es 1133 = 1121 + 6 + 6.

Determinista y re-ejecutable: dos corridas -> mismo SHA-256.

Uso:
    python3 tools/generar_spawns_rework.py
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROYECTO = os.path.dirname(HERE)
DESTINO = os.path.join(PROYECTO, "data", "spawns.json")
REGIONES = os.path.join(PROYECTO, "data", "regiones.json")

SEMILLA = 20260922
TOTAL = 1133
SPAWNS_MOON = 24            # en el anillo 800 < r < 1450 de Moon Town
RADIO_SEGURO = 40.0         # m alrededor del centro de cada ciudad
R_CIUDAD = 800.0            # disco de la ciudad (lo construye otro worker)
MARGEN = 8.0                # margen dentro de cada rectangulo de region

# Pack de prueba de combate (fase 18.2+, pedido de Juan Diego 2026-09-23):
# mobs fijos cerca de la plaza de Moon Town para probar el sistema de
# combate sin caminar 800 m. Posiciones a mano (verificadas: fuera de los
# 18 edificios de data/ciudad_luna.json, fuera de la zona segura de 40 m
# y dentro del radio de streaming de 600 m -> se instancian al arrancar).
# Llevan "grupo": "prueba_combate" para que los tests los eximan de las
# reglas de distribucion (disco de la ciudad / banda de nivel de region).
# La regla nivel -> arquetipo SI se cumple (goblin<=30, lobo 31-200,
# ogro>200) para no romper ese contrato.
PACK_PRUEBA = [
    {"arquetipo": "goblin", "x": 130.0, "z": 70.0, "nivel": 2,
     "grupo": "prueba_combate"},
    {"arquetipo": "goblin", "x": 165.0, "z": 115.0, "nivel": 3,
     "grupo": "prueba_combate"},
    {"arquetipo": "goblin", "x": 100.0, "z": 165.0, "nivel": 2,
     "grupo": "prueba_combate"},
    {"arquetipo": "lobo", "x": 220.0, "z": -25.0, "nivel": 32,
     "grupo": "prueba_combate"},
    {"arquetipo": "lobo", "x": 190.0, "z": -95.0, "nivel": 35,
     "grupo": "prueba_combate"},
    {"arquetipo": "ogro", "x": 240.0, "z": 110.0, "nivel": 250,
     "grupo": "prueba_combate"},
]

# Centros de las 9 ciudades con zona segura (fase 15). Los 8 secundarios
# son los destinos de data/portales_temp.json (fase 14.1).
CIUDADES = [
    (0.0, 0.0),
    (9966.0, 0.0),
    (-9966.0, 0.0),
    (0.0, -5358.0),
    (0.0, 9966.0),
    (9966.0, -9966.0),
    (-9966.0, -9966.0),
    (-9966.0, 9966.0),
    (9966.0, 9966.0),
]

# Jefes de fragmento (fase 22, P2 contenido): un spawn fijo por jefe a
# ~350 m del centro de su ciudad (fuera de la zona segura de 40 m y del
# disco urbano, dentro del terreno). El "nivel" es informativo (dificultad
# sugerida 9-10); el arquetipo es unico y exento de la regla nivel ->
# arquetipo (ver "grupo"). Las misiones q_* lo cazan por arquetipo.
PACK_JEFES = [
    {"arquetipo": "devorador_dunas", "x": 10216.0, "z": 250.0, "nivel": 9,
     "grupo": "jefe_fragmento"},
    {"arquetipo": "fundidor_antiguo", "x": -9716.0, "z": 250.0, "nivel": 9,
     "grupo": "jefe_fragmento"},
    {"arquetipo": "aullido_pico", "x": 250.0, "z": -5108.0, "nivel": 9,
     "grupo": "jefe_fragmento"},
    {"arquetipo": "eco_cristal", "x": 250.0, "z": 10216.0, "nivel": 9,
     "grupo": "jefe_fragmento"},
    {"arquetipo": "susurro_umbral", "x": 10216.0, "z": -9716.0, "nivel": 10,
     "grupo": "jefe_fragmento"},
    {"arquetipo": "campeon_caido", "x": -9716.0, "z": -9716.0, "nivel": 10,
     "grupo": "jefe_fragmento"},
]


def arquetipo_de(nivel: int) -> str:
    """REGLA NIVEL -> ARQUETIPO (ver docstring del modulo)."""
    if nivel <= 30:
        return "goblin"
    if nivel <= 200:
        return "lobo"
    return "ogro"


def _en_zona_segura(x: float, z: float) -> bool:
    """True si (x, z) cae a menos de RADIO_SEGURO del centro de alguna ciudad."""
    return any(math.hypot(x - cx, z - cz) < RADIO_SEGURO for cx, cz in CIUDADES)


def main() -> int:
    with open(REGIONES, "r", encoding="utf-8") as f:
        regiones = json.load(f)
    rng = random.Random(SEMILLA)

    por_id = {r["id"]: r for r in regiones}
    moon = por_id["moon_town"]
    resto = [r for r in regiones if r["id"] != "moon_town"]

    # Reparto por area (resto mayor) para que la suma sea exacta.
    # Los packs fijo (prueba + jefes) se suman aparte: no entran en el reparto.
    objetivo = TOTAL - SPAWNS_MOON - len(PACK_PRUEBA) - len(PACK_JEFES)
    areas = [(r["x1"] - r["x0"]) * (r["z1"] - r["z0"]) for r in resto]
    area_total = sum(areas)
    cuotas = [objetivo * a / area_total for a in areas]
    asignados = [int(c) for c in cuotas]
    faltan = objetivo - sum(asignados)
    orden = sorted(range(len(resto)), key=lambda i: cuotas[i] - asignados[i],
                   reverse=True)
    for i in orden[:faltan]:
        asignados[i] += 1
    assert sum(asignados) == objetivo

    spawns = []

    # 1) Moon Town: anillo fuera del disco de la ciudad, niveles 1-5.
    nmin, nmax = int(moon["nivel_min"]), int(moon["nivel_max"])
    for _ in range(SPAWNS_MOON):
        while True:  # remuestreo hasta salir de las 9 zonas seguras
            ang = rng.random() * 2.0 * math.pi
            r = R_CIUDAD + rng.random() * (1450.0 - R_CIUDAD)
            x = r * math.cos(ang)
            z = r * math.sin(ang)
            if not _en_zona_segura(x, z):
                break
        nivel = rng.randint(nmin, nmax)
        spawns.append({
            "arquetipo": arquetipo_de(nivel),
            "x": round(x, 3),
            "z": round(z, 3),
            "nivel": nivel,
        })

    # 2) Resto de regiones: uniforme en rectangulo, nivel en su banda.
    for r, n_spawns in zip(resto, asignados):
        nmin, nmax = int(r["nivel_min"]), int(r["nivel_max"])
        for _ in range(n_spawns):
            while True:  # remuestreo hasta salir de las 9 zonas seguras
                x = r["x0"] + MARGEN + rng.random() * (r["x1"] - r["x0"] - 2 * MARGEN)
                z = r["z0"] + MARGEN + rng.random() * (r["z1"] - r["z0"] - 2 * MARGEN)
                if not _en_zona_segura(x, z):
                    break
            nivel = rng.randint(nmin, nmax)
            spawns.append({
                "arquetipo": arquetipo_de(nivel),
                "x": round(x, 3),
                "z": round(z, 3),
                "nivel": nivel,
            })

    # 3) Pack de prueba de combate: posiciones fijas, sin rng (el orden es
    # estable y no afecta al determinismo: dos corridas -> mismo SHA).
    spawns.extend(PACK_PRUEBA)

    # 4) Pack de jefes de fragmento (fase 22): igual de fijo y estable.
    spawns.extend(PACK_JEFES)

    assert len(spawns) == TOTAL, f"total={len(spawns)} != {TOTAL}"

    with open(DESTINO, "w", encoding="utf-8") as f:
        json.dump(spawns, f, indent=2, ensure_ascii=False)
        f.write("\n")

    conteo = {}
    for s in spawns:
        conteo[s["arquetipo"]] = conteo.get(s["arquetipo"], 0) + 1
    sha = hashlib.sha256(open(DESTINO, "rb").read()).hexdigest()
    print(f"[SPAWNS] total={len(spawns)} " +
          " ".join(f"{k}={conteo.get(k, 0)}" for k in ("goblin", "lobo", "ogro")))
    print(f"[SPAWNS] escrito {DESTINO} sha256={sha}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
