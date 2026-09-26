#!/usr/bin/env python3
"""Prepara un modelo de `models/` para el juego: retopologiza y exporta.

Fase 49 — el pipeline de arte, en modo headless. Recibe un GLB de Meshy tal
cual (1M+ triángulos, sin esqueleto) y deja un GLB que el motor puede dibujar:
triángulos dentro del presupuesto y, si se pide, con esqueleto y clips.

QUÉ HACE Y POR QUÉ (Fase 48 lo dejó medido):
- El mundo entero mide 285k triángulos con un techo de 900k. Un personaje del
  pack de Meshy trae de media 1,14M: uno solo revienta el presupuesto. Aquí se
  decima al objetivo (por defecto 20k, que es lo que admite un mob).
- El Decimate de Blender es "collapse" y reparte el peso de la malla, que es
  justo lo que se quiere aquí: conserva la silueta y descarta el relieve que
  no se ve a 20 m de distancia.

Uso:
    blender --background --python tools/preparar_modelo.py -- \
        entrada.glb salida.glb [triangulos] [rig: 0|1]

Se ejecuta en varias pasadas porque una pasada sola al 1% deja agujeros; tres
pasadas al 33% dan un reparto mucho más limpio con el mismo resultado final.
"""
from __future__ import annotations

import sys

import bpy  # type: ignore

# Control de triángulos por objeto (el pack trae uno, pero no se fía).
PASADAS = 3


def args() -> list[str]:
    if "--" not in sys.argv:
        print("[PREP] faltan argumentos: entrada.glb salida.glb [tris] [rig]")
        sys.exit(2)
    return sys.argv[sys.argv.index("--") + 1 :]


def triangulos(objs: list) -> int:
    total = 0
    deps = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        if o.type != "MESH":
            continue
        me = o.evaluated_get(deps).to_mesh()
        for p in me.polygons:
            total += max(1, len(p.vertices) - 2)
        o.evaluated_get(deps).to_mesh_clear()
    return total


def juntar(objs: list) -> object:
    """Une todas las mallas en un solo objeto (el pack trae 1, pero por si acaso)."""
    bpy.ops.object.select_all(action="DESELECT")
    mallas = [o for o in objs if o.type == "MESH"]
    for o in mallas:
        o.select_set(True)
    if not mallas:
        print("[PREP] el GLB no trae ninguna malla")
        sys.exit(3)
    bpy.context.view_layer.objects.active = mallas[0]
    if len(mallas) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = "Cuerpo"
    return obj


def decimar(obj: object, objetivo: int) -> None:
    """Reduce la malla al objetivo con varias pasadas de Decimate (collapse)."""
    actual = triangulos([obj])
    if actual <= objetivo:
        print(f"[PREP] ya está por debajo del objetivo ({actual} <= {objetivo})")
        return
    for _ in range(PASADAS):
        actual = triangulos([obj])
        if actual <= objetivo:
            break
        ratio = max(objetivo / float(actual), 0.01)
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    print(f"[PREP] {actual} -> {triangulos([obj])} triángulos (objetivo {objetivo})")


def posar(obj: object) -> None:
    """Pega el modelo al suelo: min z = 0 y centrado en x/y.

    Los exports de Meshy vienen centrados en el origen, así que sin esto el
    personaje se dibuja medio enterrado y a la hora de pegarlo al terreno hay
    que compensar a ojo. Aquí se resuelve una vez, en el asset.
    """
    import mathutils

    bb = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
    dx = -(max(v.x for v in bb) + min(v.x for v in bb)) * 0.5
    dy = -(max(v.y for v in bb) + min(v.y for v in bb)) * 0.5
    dz = -min(v.z for v in bb)
    obj.location = (dx, dy, dz)
    bpy.context.view_layer.update()
    print("[PREP] posado en el suelo (x%.2f y%.2f z%.2f)" % (dx, dy, dz))


def info(obj: object) -> str:
    bb = [obj.matrix_world @ __import__("mathutils").Vector(c) for c in obj.bound_box]
    alto = max(v.z for v in bb) - min(v.z for v in bb)
    ancho = max(v.x for v in bb) - min(v.x for v in bb)
    return "alto %.2f m | ancho %.2f m" % (alto, ancho)


def main() -> int:
    a = args()
    entrada, salida = a[0], a[1]
    objetivo = int(a[2]) if len(a) > 2 else 20000
    hacer_rig = (len(a) > 3 and a[3] == "1")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=entrada)
    objetos = list(bpy.context.scene.objects)
    print(f"[PREP] {entrada}: {len(objetos)} objetos, entrada ~{triangulos(objetos)} triángulos")

    cuerpo = juntar(objetos)
    print(f"[PREP] malla unida: {info(cuerpo)}")
    decimar(cuerpo, objetivo)
    print(f"[PREP] decimada: {info(cuerpo)}")

    posar(cuerpo)
    print(f"[PREP] posado: {info(cuerpo)}")

    if hacer_rig:
        import rig  # type: ignore  (módulo hermano, opcional)

        rig.enrutar(cuerpo)
        print("[PREP] esqueleto y clips generados")

    bpy.ops.export_scene.gltf(
        filepath=salida,
        export_format="GLB",
        export_apply=True,
        export_animations=bool(hacer_rig),
        export_yup=True,
    )
    print(f"[PREP] escrito {salida}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
