"""La armadura en capas. Ver `docs/CONTRATO_PARTES.md`.

ESPACIO RESERVADO. Lo escribe otro agente. Hoy el modelo no tiene NINGUNA pieza de
armadura: los hombros son un tubo que se ensancha. Y una hombrera es justamente
lo que le dice al ojo que este es un guerrero y no un hombre con un casco.

Firma obligatoria, la misma que las otras partes:

    aplicar(m: Malla, p: dict, g: float, _v_tex: callable) -> dict

Que hace: hombreras, peto y rodilleras como geometria propia, biselada, apoyadas
sobre el cuerpo. Hoy no hay ninguna pieza: el metal es un rectangulo pintado en
la textura, no una placa que sobresale de la silueta.
"""
from mathutils import Vector  # noqa: F401  (lo usan las partes)


def aplicar(m, p, g, _v_tex) -> dict:
    raise NotImplementedError("parte_armadura.aplicar: sin escribir todavia")
