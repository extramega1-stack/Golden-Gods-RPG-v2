#!/usr/bin/env python3
"""Sella una malla troceada en una sola superficie continua y le devuelve
las UV y los pesos de piel.

ESTADO: FUNCIONA, Y AUNDA ASI NO SE USA EN EL JUEGO
----------------------------------------------------
Medido en `models/clase_guerrero.glb`: la malla tiene **169 islas** y el voxel
remesh las deja en **1**, conservando la forma con 1,15% de deriva. Los pesos y
las UV se devuelven enteros (9.692 UV, 38.768 pesos, 49 huesos).

Aun asi NO se integra, por un motivo que solo se ve mirando un render: **la
textura queda a parches**. Las UV son por isla, asi que soldar 169 islas crea
cosauras de textura nuevas en cada union. El brazo queda limpio (su isla era
continua) pero el torso, la cabeza y el pelo quedan como un mosaico.

Peor todavia: el modelo soldado queda con la cara y el pelo convertidos en
bloques, que es una perdida visible frente al original liso.

La redaccion correcta de esto es RE-UV y repintar, que necesita un pipeline de
textura que este proyecto no tiene todavia (las texturas son procedurales
horneadas, no pintadas). Es trabajo de arte, no de herramienta.

Mientras tanto la malla troceada no es lo que mas pesa: con la animacion
procedural, que mueve poco las articulaciones, las costuras no se abren. Se
abren con mocap real, y ahi lo que falla es que el cuerpo es un maniqui, no la
topologia.

POR QUE ESTA HERRAMIENTA EXISTE, medido, no supuesto
------------------------------------------------------
`models/clase_guerrero.glb` tiene **169 islas** separadas (islas contiguas por
arista) y `clase_arquero.glb` tiene **801**. La malla no es un cuerpo: es un
monton de trozos pegados, uno por segmento de hueso. Al flexionar un codo, los
trozos de ese codo se separan y se abre una costura de geometria.

Es por eso que una animacion real (mocap) se ve peor sobre estos modelos que la
animacion procedural: la procedural mueve poco las articulaciones y no abre las
costuras; el mocap las flexiona en cada cuadro y las abre todas.

El voxel remesh de OpenVDB une las islas en una sola superficie y conserva la
forma: a voxel 0,020 sobre un personaje de 1,896 u, la caja pasa de
0,589 x 1,900 x 0,396 a 0,586 x 1,898 x 0,391. Eso es medio punto porcentual.

EL REMESH DESTRUYE UV Y PESOS, y por eso no basta
-------------------------------------------------
Un voxel remesh a secas deja el personaje sin textura y sin esqueleto, que es
PEOR que antes. Este script guarda las dos cosas antes de soldar y las devuelve
por proyeccion de la superficie mas cercana sobre la malla original:

  * UV: cada loop del mesh nuevo toma la UV del vertice original mas cercano.
  * Pesos: se reconstruen los grupos de huesos con los NOMBRES que tenia el
    original (los indices no sobreviven al remesh).

Como la forma se conserva, el donante de un vertice nuevo es el vertice
original que estaba en ese mismo trozo de piel.

USO
---
    blender -b --factory-startup --python tools/soldar_malla.py -- \
        entrada.glb salida.glb [voxel]

    voxel por defecto: 0.020

    # solo verificar una malla (no escribe nada)
    blender -b --factory-startup --python tools/soldar_malla.py -- \
        --verificar models/clase_guerrero.glb

QUE IMPRIME
-----------
Malla original: vértices, islas, UV, pesos.
Malla soldada:  vértices, islas, caja, diferencia de forma, y cuántas UV y
                cuántos pesos se transfirieron.

Las islas son el número que importa: tiene que dar 1 (o muy pocas, si el voxel
es tan fino que las puntas de los dedos o el pelo se sueltan).
"""
import sys
import time

import bpy
from mathutils.bvhtree import BVHTree

# El cuerpo y el arma son mallas separadas en el GLB. El `Icosphere` es un arma
# colgada de la mano: soldarlo con el cuerpo deformaria el arma.
NOMBRE_CUERPO = "Cuerpo"


def arg(argv):
    """Devuelve (voxel, entrada, salida, solo_verificar)."""
    voxel = 0.020
    entrada = ""
    salida = ""
    verificar = False
    pos = []
    for a in argv:
        if a == "--verificar":
            verificar = True
        elif a.endswith(".glb"):
            pos.append(a)
    if pos:
        entrada = pos[0]
    if len(pos) > 1:
        salida = pos[1]
    if len(pos) > 2:
        try:
            voxel = float(pos[2])
        except ValueError:
            voxel = 0.020
    return voxel, entrada, salida, verificar


def islas(malla):
    """Cuantas islas contiguas por arista tiene la malla.

    Union-find. Devuelve (n_islas, n_aristas_compartidas). Una malla continua
    da 1 isla y un monton de aristas compartidas.
    """
    verts = malla.vertices
    padre = list(range(len(verts)))

    def buscar(x):
        while padre[x] != x:
            padre[x] = padre[padre[x]]
            x = padre[x]
        return x

    compartidas = 0
    for pol in malla.polygons:
        idx = list(pol.vertices)
        for i in range(len(idx)):
            a = buscar(idx[i])
            b = buscar(idx[(i + 1) % len(idx)])
            if a == b:
                compartidas += 1
            else:
                padre[b] = a
    raices = {buscar(i) for i in range(len(verts))}
    return len(raices), compartidas


def _baricentrico(p, pts, uvs):
    """Coordenas barycentricas de `p` en el triangulo `pts`, y la UV que sale.

    Si algun vertice no tenia UV devuelve None: es mejor dejar el loop sin tocar
    que inventarle una coordenada.
    """
    if any(u is None for u in uvs):
        return None
    a, b, c = pts
    v0 = b - a
    v1 = c - a
    v2 = p - a
    d00 = v0.dot(v0)
    d01 = v0.dot(v1)
    d11 = v1.dot(v1)
    d20 = v2.dot(v0)
    d21 = v2.dot(v1)
    den = d00 * d11 - d01 * d01
    if abs(den) < 1e-12:
        return None
    vv = (d11 * d20 - d01 * d21) / den
    ww = (d00 * d21 - d01 * d20) / den
    uu = 1.0 - vv - ww
    return (uu * uvs[0][0] + vv * uvs[1][0] + ww * uvs[2][0],
            uu * uvs[0][1] + vv * uvs[1][1] + ww * uvs[2][1])


def caja_de(malla):
    xs = [v.co.x for v in malla.vertices]
    ys = [v.co.y for v in malla.vertices]
    zs = [v.co.z for v in malla.vertices]
    return (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))


def abrir(entrada):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=entrada)


def cuerpo_de(entrada):
    abrir(entrada)
    cuerpos = [o for o in bpy.data.objects
               if o.type == 'MESH' and o.name == NOMBRE_CUERPO]
    if not cuerpos:
        raise SystemExit("[SELLAR] no encontre una malla llamada '%s' en %s"
                         % (NOMBRE_CUERPO, entrada))
    return cuerpos[0]


def main():
    voxel, entrada, salida, verificar = arg(
        sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if not entrada:
        raise SystemExit(__doc__)
    t0 = time.time()

    cuerpo = cuerpo_de(entrada)
    n_islas, aristas = islas(cuerpo.data)
    caja0 = caja_de(cuerpo.data)
    print("[SELLAR] ORIGINAL|verts=%d|tris=%d|islas=%d|aristas=%d|caja=%.3f x %.3f x %.3f"
          % (len(cuerpo.data.vertices), len(cuerpo.data.polygons), n_islas,
             aristas, caja0[0], caja0[1], caja0[2]))
    if verificar:
        print("[SELLAR] VERIFICACION pedida: no se escribio nada.")
        return
    if n_islas <= 1:
        print("[SELLAR] la malla ya es continua (1 isla). No hay nada que sellar.")
        return

    # ------------------------------------------------- 1. GUARDAR LO ORIGINAL
    ov = cuerpo.data.vertices
    oup = [v.co.copy() for v in ov]
    otri = [list(p.vertices) for p in cuerpo.data.polygons]

    uv_vert = {}
    if cuerpo.data.uv_layers:
        capa0 = cuerpo.data.uv_layers[0]
        for loop in cuerpo.data.loops:
            vi = loop.vertex_index
            uv = capa0.data[loop.index].uv
            if vi in uv_vert:
                a = uv_vert[vi]
                uv_vert[vi] = ((a[0] + uv[0]) * 0.5, (a[1] + uv[1]) * 0.5)
            else:
                uv_vert[vi] = (uv[0], uv[1])

    # Los pesos se guardan por NOMBRE de grupo: los indices no sobreviven.
    pesos_orig = []
    for i in range(len(ov)):
        d = {}
        for g in cuerpo.vertex_groups:
            try:
                w = g.weight(i)
            except Exception:
                w = 0.0
            if w > 0.001:
                d[g.name] = w
        pesos_orig.append(d)
    print("[SELLAR] se guarda|verts=%d|con_uv=%d|con_pesos=%d|grupos=%d"
          % (len(ov), len(uv_vert), sum(1 for d in pesos_orig if d),
             len(cuerpo.vertex_groups)))

    # ----------------------------------------------------------- 2. VOXEL REMESH
    # `voxel_remesh` es un operador de contexto: sin objeto seleccionado y
    # activo tira "poll() failed", y el error no menciona la seleccion.
    bpy.ops.object.select_all(action='DESELECT')
    cuerpo.select_set(True)
    bpy.context.view_layer.objects.active = cuerpo
    cuerpo.data.remesh_voxel_size = voxel
    cuerpo.data.remesh_voxel_adaptivity = 0.0
    bpy.ops.object.voxel_remesh()
    cuerpo.data.update()
    print("[SELLAR] REMESH|voxel=%.3f|verts=%d" % (voxel, len(cuerpo.data.vertices)))

    # ---------------------------------- 3. PROYECCION DE LA SUPERFICIE MAS CERCANA
    #
    # BUG QUE COSTO UN RENDER ENTERO, y que se ve a ojo: la UV se tomaba del
    # VERTICE mas cercano, no del punto exacto. Un vertice nuevo cae en medio de
    # un triangulo de la original, y el vertice mas cercano puede estar al otro
    # lado de una costura de UV. El resultado era un mosaico de bloques sobre todo
    # el torso y la cara: la malla quedaba continua pero la textura era PEOR que
    # antes, que es peor que no haber sellado nada.
    #
    # Lo correcto es interpolar barycentricamente sobre el punto de impacto. Los
    # PESOS si se quedan con el vertice donante, porque son datos por vertice y no
    # se interpolan.
    bvh = BVHTree.FromPolygons(oup, otri, all_triangles=False, epsilon=0.0)

    def uv_en_punto(loc, idx):
        """UV del punto `loc`, interpolada dentro del poligono `idx`."""
        if idx >= len(otri):
            return None
        inds = otri[idx]
        if len(inds) < 3:
            return uv_vert.get(inds[0]) if inds else None
        if len(inds) == 3:
            return _baricentrico(loc, [oup[i] for i in inds],
                                 [uv_vert.get(i) for i in inds])
        # Poligono de mas de 3 lados: triangulacion en abanico desde el primero.
        total = None
        n = 0
        for k in range(1, len(inds) - 1):
            tri = [inds[0], inds[k], inds[k + 1]]
            t = _baricentrico(loc, [oup[i] for i in tri],
                              [uv_vert.get(i) for i in tri])
            if t is not None:
                total = t if total is None else [a + b for a, b in zip(total, t)]
                n += 1
        return [c / n for c in total] if n else None

    donante = {}
    uv_por_vertice = {}
    for v in cuerpo.data.vertices:
        hit = bvh.find_nearest(v.co)
        if hit is None or hit[0] is None or hit[2] is None:
            continue
        loc, idx = hit[0], hit[2]
        uv_por_vertice[v.index] = uv_en_punto(loc, idx)
        if idx >= len(otri):
            continue
        mejor, mejor_d = -1, 1e18
        for cand in otri[idx]:
            d = (oup[cand] - loc).length_squared
            if d < mejor_d:
                mejor_d, mejor = d, cand
        donante[v.index] = mejor
    print("[SELLAR] DONANTES|%d de %d" % (len(donante), len(cuerpo.data.vertices)))

    # ------------------------------------------------------------------- 4. UV
    capa = cuerpo.data.uv_layers.active
    if capa is None and cuerpo.data.uv_layers:
        capa = cuerpo.data.uv_layers[0]
    if capa is not None:
        n_uv = 0
        for loop in cuerpo.data.loops:
            t = uv_por_vertice.get(loop.vertex_index)
            if t is not None:
                capa.data[loop.index].uv = (t[0], t[1])
                n_uv += 1
        print("[SELLAR] UV|loops=%d|escritas=%d (barycentrico, NO vertice mas cercano)"
              % (len(cuerpo.data.loops), n_uv))

    # ---------------------------------------------------------------- 5. PESOS
    for g in list(cuerpo.vertex_groups):
        cuerpo.vertex_groups.remove(g)
    grupos = {}
    n_pes = 0
    for v in cuerpo.data.vertices:
        d = donante.get(v.index, -1)
        if d < 0:
            continue
        for nombre, w in pesos_orig[d].items():
            if nombre not in grupos:
                grupos[nombre] = cuerpo.vertex_groups.new(name=nombre)
            grupos[nombre].add([v.index], w, 'REPLACE')
            n_pes += 1
    print("[SELLAR] PESOS|escritos=%d|grupos=%d" % (n_pes, len(cuerpo.vertex_groups)))

    # --------------------------------------------------- 6. VERIFICAR Y EXPORTAR
    n_islas2, aristas2 = islas(cuerpo.data)
    caja1 = caja_de(cuerpo.data)
    print("[SELLAR] SELLADA|verts=%d|islas=%d|aristas=%d|caja=%.3f x %.3f x %.3f"
          % (len(cuerpo.data.vertices), n_islas2, aristas2,
             caja1[0], caja1[1], caja1[2]))
    deriva = max(abs(caja1[i] - caja0[i]) / max(caja0[i], 1e-6) for i in range(3))
    print("[SELLAR] DERIVA de forma|%.2f%%| (una malla remesheada siempre engorda o adelgaza un poco)" % (deriva * 100))

    bpy.ops.object.shade_smooth()
    if not salida:
        raise SystemExit("[SELLAR] falta la ruta de salida. Nada se guardo.")
    # `save_as_mainfile` escribe un .blend aunque le pidas .glb. El que escribe
    # glTF es el exportador, y Godot no carga un .blend renombrado.
    bpy.ops.export_scene.gltf(filepath=salida, export_format='GLB',
                              use_selection=False, export_animations=False,
                              export_skins=True)
    print("[SELLAR] GUARDADO|%s|%.1f s" % (salida, time.time() - t0))


if __name__ == "__main__":
    main()