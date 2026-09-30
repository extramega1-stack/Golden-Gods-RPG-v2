"""La cara. Ver `docs/CONTRATO_PARTES.md`.

ESPACIO RESERVADO. Lo escribe otro agente. While it is empty, the model keeps
the egg head it always had, and the character keeps looking like a mannequin.

Firma obligatoria, la misma que las otras partes:

    aplicar(m: Malla, p: dict, g: float, _v_tex: callable) -> dict

Que hace: crea la cabeza con forma de cabeza. Hoy son ocho anillos elipsoidales
apilados, que dan un huevo. Y un huevo es la senal de muñeco: un personaje sin
cara se lee como maniqui antes de que le mires la ropa.
"""
from mathutils import Vector  # noqa: F401  (lo usan las partes)


def aplicar(m, p, g, _v_tex) -> dict:
    raise NotImplementedError("parte_cara.aplicar: sin escribir todavia")
