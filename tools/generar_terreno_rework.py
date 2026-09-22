#!/usr/bin/env python3
"""Generador determinista del terreno del REWORK 2026 (Fase 15) — Golden Gods RPG.

Reemplaza el heightmap porteado del legado (fase 12) por un terreno nuevo con
relieve y biomas con identidad propia (nada copiado de Blizzard). Formato de
salida EXACTO al que lee scripts/mundo/terreno.gd (NO tocar el loader):

    u32 289, u32 289, 12 bytes cero,
    289x289 float32 LE row-major (indice = iz*289+ix),
    289x289x3 u8 RGB por vertice.

Mapeo: x = -18432 + ix*128,  z = -18432 + iz*128,  ix/iz en 0..288.
Escala: 36.864 u, sin reescalar (Terreno.TAMANO / PASO / X0 / Z0).

DISENO (x = este, z = sur; el norte es z negativo):
  - Llanuras centrales alrededor del origen (26..52 u), con ondulacion suave.
  - Montana Oscura (norte, z < ~-3500): cordillera alta con ruido de cresta
    (peaks ~520 u), roca oscura y picos con nieve (>340 u).
  - Desierto al este (x > ~2000): dunas suaves, color arena propio.
  - Costa al suroeste: el terreno baja a 2..8 u (arena humeda / orilla);
    SIN agua profunda incaminable en esta fase: la altura minima global es
    2.0 u y los "vados" son solo color (arena + leve tinte azul verdoso en
    los puntos mas bajos de la costa).
  - Bosques (sur y noroeste): parches de verde oscuro sobre la pradera.
  - Colinas rocosas al oeste (Ceniza y Forja) y al noreste (Umbral de Ladon).

DISCOS DE CIUDAD (fijos para el worker de ciudades, que construye en paralelo):
  - Moon Town: centro (0, 0), radio 800 u, aplanado a H_CIUDAD = 40.0 u
    (constante en todo el disco; anillo de mezcla suave nominal 800..1050 u).
    H = 40.0 esta por encima de cualquier punto bajo del mapa (min 2.0 u).
  - 8 ciudades secundarias (fase 15): centros = destinos de
    data/portales_temp.json, radio 700 u, anillo de mezcla suave nominal
    700..950 u. La altura de cada disco es la altura NATURAL del terreno en
    su centro (muestreada antes de aplanar), para no crear acantilados con
    el bioma (ej. North Town queda a ~213 u, en las estribaciones).
  - El aplanado exacto se extiende una celda (128 u) mas alla del radio
    contratado para que la interpolacion bilineal tambien sea H exacta en
    todo r <= radio contratado.
  - Ningun disco se solapa con otro (distancias verificadas en el reporte):
    el orden de aplicacion no afecta al resultado.

Determinista y re-ejecutable: semilla fija SEMILLA = 20260922, sin azar del
sistema (hash entero de coordenadas). Dos corridas -> mismo SHA-256.
El mundo fuera de los discos de ciudad es BYTE-IDENTICO al de la fase 14.

Uso:
    python3 tools/generar_terreno_rework.py
Escribe data/terreno.bin (guarda antes el viejo como data/terreno_fase14.bak).
"""
from __future__ import annotations

import hashlib
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROYECTO = os.path.dirname(HERE)
DESTINO = os.path.join(PROYECTO, "data", "terreno.bin")
RESPALDO = os.path.join(PROYECTO, "data", "terreno_fase14.bak")

# --- Constantes del mundo (deben coincidir con scripts/mundo/terreno.gd) ---
SEMILLA = 20260922
LADO = 289
PASO = 128.0
X0 = -18432.0
Z0 = -18432.0
TAMANO = 36864.0

# --- Disco de Moon Town (contrato con el worker de ciudad, fase 14) ---
H_CIUDAD = 40.0      # altura aplanada del disco de Moon Town
R_CIUDAD = 800.0     # radio del disco perfectamente plano (contrato)
# El aplanado exacto se extiende una celda (128 u) mas alla para que la
# interpolacion bilineal tambien sea H en todo r <= R_CIUDAD.
R_PLANO = 928.0      # hasta aqui h == H_CIUDAD exacto
R_MEZCLA = 1050.0    # hasta aqui la mezcla suave con el terreno natural

# --- Discos de las 8 ciudades secundarias (fase 15) ---
R_CIUDAD2 = 700.0    # radio del disco perfectamente plano (contrato)
R_PLANO2 = 828.0     # = 700 + 128: aplanado exacto (misma razon que R_PLANO)
R_MEZCLA2 = 950.0    # hasta aqui la mezcla suave con el terreno natural
# Centros = destinos de data/portales_temp.json (fase 14.1).
CENTROS_CIUDAD = [
    ("desert",  9966.0,     0.0),
    ("fire",   -9966.0,     0.0),
    ("north",      0.0, -5358.0),
    ("mystic",     0.0,  9966.0),
    ("shadow",  9966.0, -9966.0),
    ("rage",   -9966.0, -9966.0),
    ("fury",   -9966.0,  9966.0),
    ("golden",  9966.0,  9966.0),
]

MASCARA64 = 0xFFFFFFFFFFFFFFFF


def _hash01(ix: int, iz: int, semilla: int) -> float:
    """Hash entero determinista -> [0, 1). Funciona con ix/iz negativos."""
    h = (ix * 374761393 + iz * 668265263 + semilla * 1442695040888963407) & MASCARA64
    h = ((h ^ (h >> 30)) * 1274126177) & MASCARA64
    h = ((h ^ (h >> 27)) * 787798968560317543) & MASCARA64
    h ^= h >> 31
    return (h & MASCARA64) / 18446744073709551616.0


def _interp_suave(t: float) -> float:
    return t * t * (3.0 - 2.0 * t)


def _ruido_valor(x: float, z: float, escala: float, semilla: int) -> float:
    """Ruido de valor 2D con interpolacion suave, en [0, 1)."""
    gx = x * escala
    gz = z * escala
    ix = int(gx) if gx >= 0 else int(gx) - 1
    iz = int(gz) if gz >= 0 else int(gz) - 1
    fx = gx - ix
    fz = gz - iz
    a = _hash01(ix, iz, semilla)
    b = _hash01(ix + 1, iz, semilla)
    c = _hash01(ix, iz + 1, semilla)
    d = _hash01(ix + 1, iz + 1, semilla)
    ux = _interp_suave(fx)
    uz = _interp_suave(fz)
    return a + (b - a) * ux + (c - a) * uz + (a - b - c + d) * ux * uz


def _fbm(x: float, z: float, escala: float, octavas: int, semilla: int) -> float:
    """fBm normalizado a [0, 1]."""
    total = 0.0
    amplitud = 0.5
    norma = 0.0
    s = semilla
    for _ in range(octavas):
        total += amplitud * _ruido_valor(x, z, escala, s)
        norma += amplitud
        amplitud *= 0.5
        escala *= 2.03
        s += 101
    return total / norma


def _cresta(x: float, z: float, escala: float, octavas: int, semilla: int) -> float:
    """Ruido de cresta (ridged) para montanas: filos marcados, en [0, 1]."""
    total = 0.0
    amplitud = 0.55
    norma = 0.0
    s = semilla
    for _ in range(octavas):
        n = _ruido_valor(x, z, escala, s)
        r = 1.0 - abs(2.0 * n - 1.0)
        total += amplitud * r * r
        norma += amplitud
        amplitud *= 0.5
        escala *= 2.11
        s += 77
    return total / norma


def _banda(v: float, e0: float, e1: float) -> float:
    """Transicion suave 0->1 entre e0 y e1 (e0 < e1)."""
    if v <= e0:
        return 0.0
    if v >= e1:
        return 1.0
    t = (v - e0) / (e1 - e0)
    return t * t * (3.0 - 2.0 * t)


def _mezcla(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


# Semillas derivadas (una por capa, todas fijas)
_S_BASE = SEMILLA + 1
_S_BORDE_N = SEMILLA + 2
_S_CRESTA = SEMILLA + 3
_S_COLINAS = SEMILLA + 4
_S_DUNAS = SEMILLA + 5
_S_COLOR = SEMILLA + 6
_S_COLOR2 = SEMILLA + 7


def _altura_natural(x: float, z: float) -> float:
    """Altura del terreno sin discos de ciudad. Minimo global 2.0 u."""
    # 1) Llanuras centrales: base ~38 u con ondulacion suave +-14.
    base = 38.0 + 28.0 * (_fbm(x, z, 1.0 / 3500.0, 4, _S_BASE) - 0.5)

    # 2) Montana Oscura (norte): cordillera con borde ondulado.
    borde = -3500.0 - 2500.0 * _fbm(x, z, 1.0 / 6000.0, 3, _S_BORDE_N)
    mascara_norte = 1.0 - _banda(z, borde - 2500.0, borde + 1500.0)
    cresta = _cresta(x, z, 1.0 / 2600.0, 4, _S_CRESTA)
    montana = mascara_norte * (170.0 + 350.0 * cresta)

    # 3) Colinas altas al noreste (Umbral de Ladon) y al oeste (Ceniza y Forja).
    mascara_ne = _banda(x, 3000.0, 9000.0) * (1.0 - _banda(z, -3000.0, 2000.0))
    mascara_o = (1.0 - _banda(x, -9000.0, -3000.0))
    colinas = (mascara_ne * 110.0 + mascara_o * 60.0) * \
        _fbm(x, z, 1.0 / 2200.0, 3, _S_COLINAS)
    colinas *= 1.0 - mascara_norte  # la cordillera manda en el norte

    # 4) Desierto al este: aplana hacia dunas suaves (~30 u).
    este = _banda(x, 2000.0, 9000.0)
    dunas = 30.0 + 12.0 * (_fbm(x, z, 1.0 / 1800.0, 3, _S_DUNAS) - 0.5)

    # 5) Costa al suroeste: depresion hacia 2..8 u (sin agua profunda).
    dist_so = ((x + 18432.0) ** 2 + (z - 18432.0) ** 2) ** 0.5
    costa = 1.0 - _banda(dist_so, 4000.0, 15000.0)
    playa = 4.0 + 2.5 * _fbm(x, z, 1.0 / 1500.0, 2, _S_DUNAS)

    h = base + montana + colinas * (1.0 - costa)
    h = _mezcla(h, dunas, este * 0.75)
    h = _mezcla(h, playa, min(costa, 1.0))
    return max(h, 2.0)


# Alturas de los discos secundarios: natural en el centro, muestreadas una
# sola vez (deterministas: misma semilla, mismo resultado en cada corrida).
DISCOS2 = [(cid, cx, cz, _altura_natural(cx, cz))
           for cid, cx, cz in CENTROS_CIUDAD]


def _altura(x: float, z: float) -> float:
    """Altura final: natural + 9 discos de ciudad aplanados."""
    h = _altura_natural(x, z)
    # Moon Town (fase 14): debe quedar BYTE-IDENTICO; este bloque no cambia.
    r = (x * x + z * z) ** 0.5
    if r < R_PLANO:
        h = H_CIUDAD
    elif r < R_MEZCLA:
        t = _banda(r, R_PLANO, R_MEZCLA)  # 0 en el borde plano, 1 fuera
        h = _mezcla(H_CIUDAD, h, t)
    # 8 ciudades secundarias (fase 15). Los discos no se solapan entre si ni
    # con el de Moon Town, asi que el orden no importa y fuera de ellos h no
    # cambia (byte-identico a fase 14).
    for _cid, cx, cz, h_disco in DISCOS2:
        dx = x - cx
        dz = z - cz
        r2 = (dx * dx + dz * dz) ** 0.5
        if r2 < R_PLANO2:
            h = h_disco
        elif r2 < R_MEZCLA2:
            t = _banda(r2, R_PLANO2, R_MEZCLA2)
            h = _mezcla(h_disco, h, t)
    return h


# --- Paleta propia (nada copiado de Blizzard) ---
_PRADERA = (102, 132, 74)
_PRADERA2 = (88, 118, 62)
_ARENA = (194, 160, 101)
_ARENA_ORILLA = (217, 192, 138)
_VADO = (110, 150, 170)
_BOSQUE = (43, 84, 38)
_ROCA_OSCURA = (74, 68, 84)
_ROCA = (110, 100, 88)
_NIEVE = (232, 236, 242)


def _varia(base: tuple, x: float, z: float, amp: float) -> tuple:
    n = (_fbm(x, z, 1.0 / 900.0, 3, _S_COLOR) - 0.5) * 2.0 * amp
    n2 = (_fbm(x, z, 1.0 / 260.0, 2, _S_COLOR2) - 0.5) * 2.0 * amp * 0.5
    return tuple(max(0, min(255, int(round(c + n + n2)))) for c in base)


def _mezcla_c(a: tuple, b: tuple, t: float) -> tuple:
    return tuple(int(round(_mezcla(ca, cb, t))) for ca, cb in zip(a, b))


def _color(x: float, z: float, h: float) -> tuple:
    """Color por vertice segun bioma + altura. Paleta propia."""
    c = _varia(_PRADERA, x, z, 14.0)

    # Desierto al este.
    w_desierto = _banda(x, 800.0, 2200.0)
    if w_desierto > 0.0:
        c = _mezcla_c(c, _varia(_ARENA, x, z, 12.0), w_desierto)

    # Bosque al sur y al noroeste (parches oscuros sobre la pradera).
    w_bosque = _banda(z, 800.0, 2200.0) * (1.0 - _banda(abs(x), 800.0, 2200.0))
    w_bosque_nw = (1.0 - _banda(x, -9000.0, -3000.0)) * \
        (1.0 - _banda(z, -9000.0, -3000.0))
    parche = _fbm(x, z, 1.0 / 2600.0, 3, _S_COLOR)
    w_b = max(w_bosque, w_bosque_nw * 0.8) * _banda(parche, 0.35, 0.65)
    if w_b > 0.0:
        c = _mezcla_c(c, _varia(_BOSQUE, x, z, 10.0), min(w_b, 1.0))

    # Colinas rocosas (oeste y noreste).
    w_roca = max((1.0 - _banda(x, -9000.0, -3000.0)) * _banda(h, 60.0, 120.0),
                 _banda(x, 3000.0, 9000.0) * (1.0 - _banda(z, -3000.0, 2000.0))
                 * _banda(h, 80.0, 160.0))
    if w_roca > 0.0:
        c = _mezcla_c(c, _varia(_ROCA, x, z, 12.0), min(w_roca, 1.0))

    # Montana Oscura (norte): roca oscura propia.
    w_mont = _banda(-z, 800.0, 2200.0) * (1.0 - _banda(abs(x), 800.0, 2200.0))
    if w_mont > 0.0:
        c = _mezcla_c(c, _varia(_ROCA_OSCURA, x, z, 10.0), w_mont)

    # Costa suroeste: arena de orilla; vados (h < 4) con tinte de agua somera.
    w_costa = (1.0 - _banda(x, -9000.0, -3000.0)) * _banda(z, 800.0, 2200.0)
    if w_costa > 0.0:
        orilla = _ARENA_ORILLA if h < 10.0 else _varia(_PRADERA2, x, z, 12.0)
        c = _mezcla_c(c, orilla, w_costa)
        if h < 4.0:
            c = _mezcla_c(c, _VADO, w_costa * _banda(4.0 - h, 0.0, 2.0) * 0.7)

    # Nieve en los picos altos.
    w_nieve = _banda(h, 340.0, 420.0)
    if w_nieve > 0.0:
        c = _mezcla_c(c, _NIEVE, w_nieve)

    return c


def main() -> int:
    if os.path.exists(DESTINO) and not os.path.exists(RESPALDO):
        os.replace(DESTINO, RESPALDO)
        print(f"[TERRENO] respaldo del bin fase 14 -> {RESPALDO}")

    # Sanidad: ningun disco se solapa con otro (asi el orden no importa y
    # fuera de los discos el mundo es byte-identico a la fase 14).
    discos_todos = [("moon_town", 0.0, 0.0, R_MEZCLA)] + \
        [(cid, cx, cz, R_MEZCLA2) for cid, cx, cz, _h in DISCOS2]
    for i in range(len(discos_todos)):
        for j in range(i + 1, len(discos_todos)):
            a, b = discos_todos[i], discos_todos[j]
            d = math.hypot(a[1] - b[1], a[2] - b[2])
            assert d > a[3] + b[3], f"discos solapados: {a[0]} y {b[0]}"

    n = LADO * LADO
    alturas = [0.0] * n
    colores = [0] * (n * 3)

    h_min = float("inf")
    h_max = float("-inf")
    # Planitud por disco: [id, cx, cz, radio_contrato, altura_esperada, min, max].
    planitud = [["moon_town", 0.0, 0.0, R_CIUDAD, H_CIUDAD,
                 float("inf"), float("-inf")]]
    planitud += [[cid, cx, cz, R_CIUDAD2, h_d, float("inf"), float("-inf")]
                 for cid, cx, cz, h_d in DISCOS2]

    for iz in range(LADO):
        z = Z0 + iz * PASO
        base_i = iz * LADO
        for ix in range(LADO):
            x = X0 + ix * PASO
            h = _altura(x, z)
            i = base_i + ix
            alturas[i] = h
            r, g, b = _color(x, z, h)
            colores[i * 3] = r
            colores[i * 3 + 1] = g
            colores[i * 3 + 2] = b
            if h < h_min:
                h_min = h
            if h > h_max:
                h_max = h
            for p in planitud:
                dd = math.hypot(x - p[1], z - p[2])
                if dd < p[3]:
                    if h < p[5]:
                        p[5] = h
                    if h > p[6]:
                        p[6] = h

    with open(DESTINO, "wb") as f:
        f.write(struct.pack("<II", LADO, LADO))
        f.write(bytes(12))
        for h in alturas:
            f.write(struct.pack("<f", h))
        f.write(bytes(colores))

    sha = hashlib.sha256(open(DESTINO, "rb").read()).hexdigest()
    print(f"[TERRENO] escrito {DESTINO} sha256={sha}")
    print(f"[TERRENO] alturas: min={h_min:.2f} max={h_max:.2f}")
    print("[TERRENO] discos:")
    for p in planitud:
        cid, cx, cz, radio, h_esp, mn, mx = p
        print(f"[TERRENO]   {cid:10s} centro=({cx:7.0f},{cz:7.0f}) "
              f"r<{radio:.0f}: H={h_esp:8.3f} min={mn:.4f} max={mx:.4f}")
        assert mn == mx == h_esp, f"el disco {cid} no quedo plano"
    assert h_min >= 2.0, "hay agua profunda (min < 2.0)"
    return 0


if __name__ == "__main__":
    sys.exit(main())
