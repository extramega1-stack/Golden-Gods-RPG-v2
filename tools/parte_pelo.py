"""El pelo. Ver `docs/CONTRATO_PARTES.md`.

ESPACIO RESERVADO. Lo escribe otro agente. Hoy no hay pelo: el casco es un casquete
liso. Y el pelo es de las pocas cosas que cambian la SILUETA de un personaje mas
que cualquier textura: es la primera forma que el ojo detecta.

Firma obligatoria, la misma que las otras partes:

    aplicar(m: Malla, p: dict, g: float, _v_tex: callable) -> dict

Que hace: el pelo y la barba como geometria propia, con los mechones agrupados en
mechas y no en un casquete. Pesa al hueso Head y se mueve con la cabeza.
"""
from mathutils import Vector  # noqa: F401  (lo usan las partes)


def aplicar(m, p, g, _v_tex) -> dict:
    raise NotImplementedError("parte_pelo.aplicar: sin escribir todavia")
