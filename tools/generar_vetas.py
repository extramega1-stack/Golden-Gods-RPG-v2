#!/usr/bin/env python3
"""Generador determinista de vetas mineras (Fase 45) — Golden Gods RPG.

Convierte la lista de profesiones del legado (§4 Dominio 6: "Herboristería +
Minería, nodos por bioma, 11 recetas") en 12 vetas de mineral colocadas sobre
las 10 regiones de `data/regiones.json`.

Contrato de salida: `data/vetas.json`, objeto `{version, vetas: [...]}` donde
cada veta es:

    {id, nombre, region, item_id, cantidad, usos, respawn_s, xp, nivel, tinte,
     x, z}  (+ `grupo` solo en la veta de prueba)

`x`/`z` van en coordenadas Godot (las mismas que `data/spawns.json`). El
`GestorVetas` las carga y `Veta` las pone en el mundo; la Y sale del terreno
(`Terreno.altura_en`), no del JSON.

DISTRIBUCION (semilla fija SEMILLA = 20260924, random.Random determinista):
  - Las 9 regiones con ciudad: la veta cae en el anillo 900 < r < 1500 del
    centro de SU ciudad (fuera del disco urbano de 800 m, a distancia de
    caminata de la plaza) y dentro del rectangulo de su region.
  - El Velo (sin ciudad propia): posicion uniforme dentro del rectangulo.
  - Ninguna veta de DISTRIBUCION a menos de `R_MIN_CIUDAD` de cualquier
    centro de ciudad.
  - Mas la VETA DE PRUEBA de la plaza (ver VETA_PRUEBA): 12 + 1 = 13.

ESCALA (todo derivado de la region, no escrito a mano):
  - `nivel`   = `nivel_min` de la region (gate: no se mina antes).
  - `xp`      = min(12, 5 + nivel_min // 3)  → 5 XP al inicio, 12 en endgame.
  - `cantidad`= min(3, 1 + nivel_min // 15)  → 1-3 minerales por golpe.
  - `usos`    = 3 y `respawn_s` = 180 (decidido por Juan Diego en la fase 45).

Determinista y re-ejecutable: dos corridas -> mismo SHA-256.

Uso:
    python3 tools/generar_vetas.py
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
DESTINO = os.path.join(PROYECTO, "data", "vetas.json")
REGIONES = os.path.join(PROYECTO, "data", "regiones.json")

SEMILLA = 20260924
TOTAL = 12
VETAS_PRUEBA = 1
MARGEN = 8.0                # margen dentro de cada rectangulo de region
R_CIUDAD = 800.0            # disco urbano (lo construye CiudadLuna)
R_MIN_CIUDAD = 900.0        # las vetas quedan fuera de ese disco
R_MAX_CIUDAD = 1500.0       # y a menos de 1500 m (a distancia de caminata)
MAX_INTENTOS = 4000

USOS = 3
RESPAWN_S = 180
XP_MAX = 12

# VETA DE PRUEBA (fase 45.1): la veta de distribucion mas cercana a Moon Town
# esta a 1.100 m de la plaza (fuera del disco urbano, por diseño). Esta esta
# DENTRO de la plaza, a 85 m del punto de aparición del jugador, para que al
# abrir el juego se vea y se pueda minar sin caminar (el mismo criterio que el
# pack de 6 mobs de prueba de la fase 18.2). Lleva `grupo: prueba_mineria`
# para eximirla de las reglas de distribución, igual que aquel pack.
# (-10, 20): 27 m del punto de aparicion (0, 40, 45) y 22 grados a la IZQUIERDA
# de la vista (el jugador mira al norte, -Z, hacia el monumento). A 27 m la
# veta se ve de sobra al abrir el juego; a 100+ m con el zoom de camara es un
# pixel. 22 m del monumento y 145 m del edificio mas cercano (la forja): no
# cae dentro de ningun edificio ni encima del monumento.
VETA_PRUEBA = {
    "id": "veta_prueba_cobre",
    "region": "moon_town",
    "item_id": "mineral_cobre",
    "x": -10.0,
    "z": 20.0,
    "grupo": "prueba_mineria",
}

# Centros de las 9 ciudades (los mismos de generar_spawns_rework.py).
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

# REGION -> MINERAL (fase 45). Cada region expone el mineral con el que se
# identifica, para que el mapa se lea de un vistazo: el desierto da cobre,
# la forja obsidiana, el bosque esmeraldas, el velo cristales.
MINERAL_DE_REGION = {
    "moon_town": "mineral_cobre",
    "tierras_francas": "mineral_hierro",
    "ceniza_forja": "mineral_obsidiana",
    "tierras_trueno": "mineral_cristal",
    "bosque_hondo": "mineral_esmeralda",
    "umbral_ladon": "mineral_plata",
    "abismo_lloroso": "mineral_obsidiana",
    "costa_lamento": "mineral_plata",
    "corona_quebrada": "mineral_esmeralda",
    "velo": "mineral_cristal",
}

# Vetas extra: 12 = 10 regiones + 2 repetidas (las zonas donde el mineral es
# la puerta de entrada a la cadena de oficios).
VETAS_EXTRA = {
    "moon_town": "mineral_hierro",
    "umbral_ladon": "mineral_esmeralda",
}

NOMBRE_MINERAL = {
    "mineral_cobre": "Veta de Cobre",
    "mineral_hierro": "Veta de Hierro",
    "mineral_plata": "Veta de Plata",
    "mineral_obsidiana": "Veta de Obsidiana",
    "mineral_cristal": "Veta de Cristal",
    "mineral_esmeralda": "Veta de Esmeralda",
}

# MINERAL -> tinte (#rrggbb). El color ES la identidad de la veta en el mapa:
# se ve de lejos qué mineral es sin acercarse, y las vetas del mismo mineral
# comparten un único material (sin material nuevo por veta).
TINTE_DE_MINERAL = {
    "mineral_cobre": "#b87333",
    "mineral_hierro": "#8a8a94",
    "mineral_plata": "#d7e3ea",
    "mineral_obsidiana": "#3b2b47",
    "mineral_cristal": "#7fd4ff",
    "mineral_esmeralda": "#3fd98a",
}


def _dist_a_ciudad(x: float, z: float) -> float:
    """Distancia al centro de ciudad mas cercano."""
    return min(math.hypot(x - cx, z - cz) for cx, cz in CIUDADES)


def _centro_de(region: dict) -> tuple | None:
    """Centro de ciudad dentro del rectangulo de la region, o None."""
    for cx, cz in CIUDADES:
        if region["x0"] <= cx <= region["x1"] and region["z0"] <= cz <= region["z1"]:
            return (cx, cz)
    return None


def _dentro_de_region(region: dict, x: float, z: float) -> bool:
    return (region["x0"] + MARGEN <= x <= region["x1"] - MARGEN
            and region["z0"] + MARGEN <= z <= region["z1"] - MARGEN)


def _punto(region: dict, rng: random.Random, centro: tuple | None) -> tuple:
    """Punto valido para una veta: dentro de su region y lejos de las ciudades.

    Con ciudad: anillo 900-1500 m. Sin ciudad: uniforme en el rectangulo.
    Remuestrea con el rng sembrado (determinista) y nunca devuelve None: si
    tras MAX_INTENTOS no sale, cae al borde de la region mas alejado de la
    ciudad mas cercana (siempre dentro del mundo).
    """
    for _ in range(MAX_INTENTOS):
        if centro is None:
            x = rng.uniform(region["x0"] + MARGEN, region["x1"] - MARGEN)
            z = rng.uniform(region["z0"] + MARGEN, region["z1"] - MARGEN)
        else:
            ang = rng.uniform(0.0, math.tau)
            rad = rng.uniform(R_MIN_CIUDAD, R_MAX_CIUDAD)
            x = centro[0] + math.cos(ang) * rad
            z = centro[1] + math.sin(ang) * rad
        if not _dentro_de_region(region, x, z):
            continue
        if _dist_a_ciudad(x, z) < R_MIN_CIUDAD:
            continue
        return (x, z)
    cx = (region["x0"] + region["x1"]) * 0.5
    cz = (region["z0"] + region["z1"]) * 0.5
    return (cx, cz)


def _escala_de(nivel_min: int) -> tuple:
    """(xp, cantidad) derivadas del nivel minimo de la region."""
    xp = min(XP_MAX, 5 + nivel_min // 3)
    cantidad = min(3, 1 + nivel_min // 15)
    return (xp, cantidad)


def main() -> int:
    with open(REGIONES, "r", encoding="utf-8") as f:
        regiones = json.load(f)

    rng = random.Random(SEMILLA)
    vetas: list[dict] = []
    contadores: dict = {}

    for r in regiones:
        rid = r["id"]
        pedido = [MINERAL_DE_REGION[rid]]
        if rid in VETAS_EXTRA:
            pedido.append(VETAS_EXTRA[rid])
        for mineral in pedido:
            xp, cantidad = _escala_de(int(r["nivel_min"]))
            n = contadores.get(mineral, 0)
            contadores[mineral] = n + 1
            sufijo = "" if n == 0 else "_%d" % (n + 1)
            x, z = _punto(r, rng, _centro_de(r))
            vetas.append({
                "id": "veta_%s_%s%s" % (rid, mineral, sufijo),
                "nombre": "%s — %s" % (NOMBRE_MINERAL[mineral], r["nombre"]),
                "region": rid,
                "item_id": mineral,
                "cantidad": cantidad,
                "usos": USOS,
                "respawn_s": RESPAWN_S,
                "xp": xp,
                "nivel": int(r["nivel_min"]),
                "tinte": TINTE_DE_MINERAL[mineral],
                "x": round(x, 3),
                "z": round(z, 3),
            })

    # Veta de prueba (dentro de la plaza, exenta de las reglas de distribución).
    px, pc = _escala_de(1)
    vetas.append({
        "id": VETA_PRUEBA["id"],
        "nombre": "%s — Moon Town (prueba)" % NOMBRE_MINERAL[VETA_PRUEBA["item_id"]],
        "region": VETA_PRUEBA["region"],
        "item_id": VETA_PRUEBA["item_id"],
        "cantidad": pc,
        "usos": USOS,
        "respawn_s": RESPAWN_S,
        "xp": px,
        "nivel": 1,
        "tinte": TINTE_DE_MINERAL[VETA_PRUEBA["item_id"]],
        "grupo": VETA_PRUEBA["grupo"],
        "x": VETA_PRUEBA["x"],
        "z": VETA_PRUEBA["z"],
    })

    assert len(vetas) == TOTAL + VETAS_PRUEBA, "total=%d != %d" % (
        len(vetas), TOTAL + VETAS_PRUEBA)
    assert len({v["id"] for v in vetas}) == len(vetas), "hay ids de veta repetidos"

    datos = {"version": 1, "vetas": vetas}
    with open(DESTINO, "w", encoding="utf-8") as f:
        json.dump(datos, f, indent=2, ensure_ascii=False)
        f.write("\n")

    sha = hashlib.sha256(open(DESTINO, "rb").read()).hexdigest()
    print("[VETAS] escrito %s vetas=%d sha256=%s" % (DESTINO, len(vetas), sha))
    for v in vetas:
        print("  %-34s %-18s x=%9.1f z=%9.1f  usos=%d xp=%2d cant=%d"
              % (v["id"], v["item_id"], v["x"], v["z"], v["usos"], v["xp"], v["cantidad"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
