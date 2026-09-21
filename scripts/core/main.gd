extends Node3D
## Bootstrap del remake limpio — Fase 0.
##
## Responsabilidad única: existir como raíz del juego y reportar la versión.
## Los sistemas se irán añadiendo como nodos hijos en fases posteriores,
## siguiendo el documento maestro docs/MASTER_SPEC.md.
##
## Estándar de código (obligatorio desde el día 1, ver MASTER_SPEC §8):
## - Nada de `:=` sobre expresiones que devuelvan Variant.
## - Tipos explícitos en variables, parámetros y retornos.
## - Sin APIs del motor inventadas: verificar cada firma en la doc de Godot 4.7.

const GAME_TITLE: String = "Golden Gods RPG — Remake"
const GAME_VERSION: String = "0.1.0-fase0"


func _ready() -> void:
	print("[GGR] %s lista. Versión: %s" % [GAME_TITLE, GAME_VERSION])
