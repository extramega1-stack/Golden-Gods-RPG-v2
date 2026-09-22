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

## Fase 5.1 — REGLA DURA: los NPCs NO se pueden atacar. `false` en NPC;
## `true` en jugador y enemigos. `take_damage` lo ignora por completo.
var combatible: bool = true

## Fase 5.1 — flash rojo al recibir daño: estado testeable (segundos
## restantes). El gancho visual (`DamageFlash`) lee `intensidad_flash()`;
## la lógica vive aquí para que los tests la cubran sin 3D.
const FLASH_DURACION: float = 0.25
var flash_tiempo: float = 0.0

var stats: StatBlock
var vida_actual: float = 0.0
var mana_actual: float = 0.0
var nivel: int = 1
var xp_actual: int = 0

## Fase 12: terreno opcional para pegar la Y al suelo (mundo abierto).
## Lo asigna la demo; si es null el comportamiento no cambia (y = 0).
var terreno: Terreno = null


## Pega la posición Y a la altura del terreno. Llamar al final del
## _physics_process de cada entidad móvil (Player, Enemy).
func _pegar_al_terreno() -> void:
	if terreno == null:
		return
	var gp: Vector3 = global_position
	gp.y = terreno.altura_en(gp.x, gp.z)
	global_position = gp

var _muerto: bool = false
## Capas de colisión originales (die() las apaga; restaurar() las devuelve
## si se carga un estado vivo sobre una entidad que había muerto en la sesión).
var _capa_guardada: int = 1
var _mascara_guardada: int = 1


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
## REGLA DURA (fase 5.1): una entidad no combatible (NPC) ignora el daño
## por completo: sin vida perdida, sin señales, sin flash.
func take_damage(cantidad: float, fuente: Entity) -> void:
	if not combatible:
		return
	if not esta_vivo():
		return
	var dano: float = maxf(cantidad, 0.0)
	vida_actual = maxf(vida_actual - dano, 0.0)
	flash_tiempo = FLASH_DURACION
	daniado.emit(dano, fuente)
	vida_cambiada.emit(vida_actual, stats.vida_max)
	if vida_actual <= 0.0:
		die(fuente)


## Decaimiento del flash rojo (fase 5.1). Entity no definía _process:
## Enemy y Player solo usan _physics_process, así que no hay colisión.
func _process(delta: float) -> void:
	if flash_tiempo > 0.0:
		flash_tiempo = maxf(flash_tiempo - delta, 0.0)


## 0.0 = sin flash, 1.0 = impacto recién recibido. Lo lee DamageFlash.
func intensidad_flash() -> float:
	return clampf(flash_tiempo / FLASH_DURACION, 0.0, 1.0)


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
	_capa_guardada = collision_layer
	_mascara_guardada = collision_mask
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


## Restaura el estado desde un dict versionado (la usa el save/load).
## Tolera versiones desconocidas con push_warning y nunca rompe: ante campos
## ausentes usa valores sanos por defecto. Emite las señales de cambio
## (vida/maná/xp) para que la UI se refresque; nunca emite `murio`.
func restaurar(d: Dictionary) -> void:
	var version: int = int(d.get("version", 0))
	if version != SAVE_VERSION:
		push_warning("[Entity] versión de guardado no soportada: %d (esperada %d)" % [version, SAVE_VERSION])
	var estaba_muerto: bool = _muerto
	stats = StatBlock.from_dict(d.get("stats", {}))
	nivel = maxi(1, int(d.get("nivel", 1)))
	xp_actual = maxi(0, int(d.get("xp_actual", 0)))
	vida_actual = clampf(float(d.get("vida_actual", stats.vida_max)), 0.0, stats.vida_max)
	mana_actual = clampf(float(d.get("mana_actual", stats.mana_max)), 0.0, stats.mana_max)
	flash_tiempo = 0.0
	if vida_actual <= 0.0:
		_apagar_muerto_silencioso()
	elif estaba_muerto:
		_revivir_silencioso()
	vida_cambiada.emit(vida_actual, stats.vida_max)
	mana_cambiado.emit(mana_actual, stats.mana_max)
	xp_cambiada.emit(xp_actual, Formulas.xp_for_level(nivel + 1))


## Marca muerte sin señales ni efectos (para cargar partidas).
func _apagar_muerto_silencioso() -> void:
	_muerto = true
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	set_process(false)
	set_physics_process(false)


## Devuelve colisión y procesado al cargar un estado vivo sobre una entidad
## que había muerto en la sesión actual.
func _revivir_silencioso() -> void:
	_muerto = false
	set_deferred("collision_layer", _capa_guardada)
	set_deferred("collision_mask", _mascara_guardada)
	set_process(true)
	set_physics_process(true)


## Serialización versionada (la usa el save/load de la fase 4).
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
	# Se guardó muerta: carga muerta sin re-emitir `murio` (lo garantiza restaurar).
	var e: Entity = Entity.new()
	e.restaurar(d)
	return e
