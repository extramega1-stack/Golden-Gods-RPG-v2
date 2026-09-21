class_name Entity
extends CharacterBody3D
## Entidad base única del juego: jugador, creep, jefe y NPC son Entity.
##
## Principio de la rebuild (directriz de Juan Diego): UN SOLO camino para el
## daño. Todo lo que tiene vida/maná/nivel/XP pasa por aquí; cuando algo pega
## mal, se busca aquí y no en cinco sistemas distintos.
##
## - Los DATOS viven en `stats: StatBlock` (fase 1). Entity no inventa fórmulas:
##   usa `Formulas` (mitigación, curva de XP).
## - Entity NO sabe quién lo ataca ni quién lo mira: la fuente del daño es solo
##   otra Entity (o null si es ambiental), y el mundo exterior se entera por
##   SEÑALES. La UI futura solo LEE estas señales y el StatBlock, nunca escribe.
## - Sin referencias a jugador, enemigo, UI ni ningún otro sistema.
## - Es CharacterBody3D porque todos (héroe, creeps, NPCs) necesitarán moverse
##   y colisionar; la física concreta llega en las fases 3-4.
##
## Decisiones de diseño documentadas:
## - Al subir de nivel: se recalculan los derivados y vida/maná se rellenan al
##   máximo (clásico). El reparto de puntos de atributo llegará con progresión.
## - Una entidad muerta no recibe daño, no se cura, no gasta maná ni gana XP.
## - `die()` es idempotente: la señal `murio` se emite una sola vez.
## - Guardado versionado (SAVE_VERSION = 2): sobre de entidad {nivel, xp, vida,
##   mana} + el dict versionado del StatBlock (v1). Nace aquí aunque el
##   save/load se use en la fase 4.

signal vida_cambiada(vida_actual: float, vida_max: float)
signal mana_cambiado(mana_actual: float, mana_max: float)
signal daniado(cantidad: float, fuente: Entity)
signal murio(fuente: Entity)
signal xp_cambiada(xp_actual: int, xp_siguiente_nivel: int)
signal subio_nivel(nivel: int)

const SAVE_VERSION: int = 2

var stats: StatBlock
var vida_actual: float = 0.0
var mana_actual: float = 0.0
var nivel: int = 1
var xp_actual: int = 0

var _muerto: bool = false


## p_stats null → bloque base (útil al instanciar desde escena).
func _init(p_stats: StatBlock = null) -> void:
	if p_stats == null:
		stats = StatBlock.new()
	else:
		stats = p_stats
	vida_actual = stats.vida_max
	mana_actual = stats.mana_max


## ¿Sigue en combate? Falso solo después de die().
func esta_vivo() -> bool:
	return not _muerto


## Recibe daño ya calculado (quien ataca usa Formulas.damage).
## Nunca deja la vida bajo 0; al llegar a 0 llama a die() una sola vez.
func take_damage(cantidad: float, fuente: Entity) -> void:
	if not esta_vivo():
		return
	var dano: float = maxf(cantidad, 0.0)
	vida_actual = maxf(vida_actual - dano, 0.0)
	daniado.emit(dano, fuente)
	vida_cambiada.emit(vida_actual, stats.vida_max)
	if vida_actual <= 0.0:
		die(fuente)


## Cura hasta el máximo. Sin efecto en muertos.
func heal(cantidad: float) -> void:
	if not esta_vivo():
		return
	vida_actual = minf(vida_actual + maxf(cantidad, 0.0), stats.vida_max)
	vida_cambiada.emit(vida_actual, stats.vida_max)


## Intenta gastar maná. Retorna true si alcanzó (lo descuenta), false si no.
## Sin efecto en muertos.
func gastar_mana(cantidad: float) -> bool:
	if not esta_vivo():
		return false
	var coste: float = maxf(cantidad, 0.0)
	if mana_actual < coste:
		return false
	mana_actual -= coste
	mana_cambiado.emit(mana_actual, stats.mana_max)
	return true


## Restaura maná hasta el máximo. Sin efecto en muertos.
func restaurar_mana(cantidad: float) -> void:
	if not esta_vivo():
		return
	mana_actual = minf(mana_actual + maxf(cantidad, 0.0), stats.mana_max)
	mana_cambiado.emit(mana_actual, stats.mana_max)


## Muerte: idempotente; desactiva colisión y procesado de forma limpia.
## set_deferred porque die() puede llamarse dentro de callbacks físicas.
func die(fuente: Entity = null) -> void:
	if _muerto:
		return
	_muerto = true
	vida_actual = 0.0
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	set_process(false)
	set_physics_process(false)
	murio.emit(fuente)


## Gana XP; puede subir varios niveles de una vez. Sin efecto en muertos.
## Emite subio_nivel una vez por nivel ganado (en orden) y xp_cambiada al final.
func gain_xp(cantidad: int) -> void:
	if not esta_vivo():
		return
	if cantidad <= 0:
		return
	xp_actual += cantidad
	while xp_actual >= Formulas.xp_for_level(nivel + 1):
		nivel += 1
		_al_subir_nivel()
		subio_nivel.emit(nivel)
	xp_cambiada.emit(xp_actual, Formulas.xp_for_level(nivel + 1))


## Recalcula derivados y rellena vida/maná (ver decisiones de diseño arriba).
func _al_subir_nivel() -> void:
	stats.recalc()
	vida_actual = stats.vida_max
	mana_actual = stats.mana_max
	vida_cambiada.emit(vida_actual, stats.vida_max)
	mana_cambiado.emit(mana_actual, stats.mana_max)


## Serialización versionada (la usará el save/load de la fase 4).
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"nivel": nivel,
		"xp_actual": xp_actual,
		"vida_actual": vida_actual,
		"mana_actual": mana_actual,
		"stats": stats.to_dict(),
	}


static func from_dict(d: Dictionary) -> Entity:
	var version: int = int(d.get("version", 0))
	if version != SAVE_VERSION:
		push_warning("[Entity] versión de guardado no soportada: %d (esperada %d)" % [version, SAVE_VERSION])
	var stats_dict: Dictionary = d.get("stats", {})
	var e: Entity = Entity.new(StatBlock.from_dict(stats_dict))
	e.nivel = maxi(1, int(d.get("nivel", 1)))
	e.xp_actual = maxi(0, int(d.get("xp_actual", 0)))
	e.vida_actual = clampf(float(d.get("vida_actual", e.stats.vida_max)), 0.0, e.stats.vida_max)
	e.mana_actual = clampf(float(d.get("mana_actual", e.stats.mana_max)), 0.0, e.stats.mana_max)
	if e.vida_actual <= 0.0:
		# Se guardó muerta: carga muerta sin re-emitir señales.
		e._muerto = true
	return e
