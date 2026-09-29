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

## Fase 18 — feedback visual de skills: tinte temporal con el color que
## elige quien dispara el efecto (`SkillSystem`). El gancho visual
## (`SkillFX`, hermano de DamageFlash) lo lee; la lógica del temporizador
## vive aquí y es testeable sin 3D. El daño ya tiene su propio flash rojo
## (flash_tiempo); este canal es para curar/buff/debuff/aoe.
const FX_DURACION: float = 0.45
var fx_tiempo: float = 0.0
var fx_color: Color = Color.WHITE

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
## `es_critico` (fase 19) alimenta el game feel (número amarillo + hit-stop);
## por defecto es false para no romper llamados viejos.
## REGLA DURA (fase 5.1): una entidad no combatible (NPC) ignora el daño
## por completo: sin vida perdida, sin señales, sin flash.
## Bloque 68: el EMPUJE. Un golpe que solo quita vida no se siente: el enemigo
## se queda clavado como un blanco. Con un empujón corto, el impacto transmite
## la fuerza y se lee como físico en vez de como un número que baja.
##
## Es un IMPULSO que se aplica encima del movimiento, no velocidad: se guarda
## aparte y se suma en el frame, para que la IA (que reescribe `velocity` cada
## frame en el enemigo) no lo borre. `empuje_actual()` es lo que la IA suma.
var _empuje: Vector3 = Vector3.ZERO
## Cuánto dura el empujón (el decaimiento lo hace desvanecerse).
var _empuje_t: float = 0.0
## Fuerza base del empuje por punto de daño. 0.12 m por punto: un golpe de 20
## empuja 2,4 m, que se nota sin lanzar al bicho lejos.
const EMPUJE_POR_DANO: float = 0.12
## Tope del empuje, para que un crítico no lance a un mob a otro bioma.
const EMPUJE_MAX: float = 4.0
## Segundos que dura el empujón.
const EMPUJE_TIEMPO: float = 0.22


## Aplica un empujón desde `origen` (quien golpea). La dirección es la
## opuesta a la que viene el golpe: si me pegas desde la izquierda, me
## empujo a la derecha.
func aplicar_empuje(origen: Node3D, dano: float, factor: float = 1.0) -> void:
	if origen == null or not is_instance_valid(origen):
		return
	var d: Vector3 = global_position - (origen as Node3D).global_position
	d.y = 0.0
	if d.length() < 0.001:
		# Origen encima: un empujón aleatorio en vez de nada (un mob no puede
		# ser impujecible solo por estar alineado).
		d = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	d = d.normalized()
	var fuerza: float = minf(dano * EMPUJE_POR_DANO * factor, EMPUJE_MAX)
	_empuje = d * fuerza
	_empuje_t = EMPUJE_TIEMPO


## El empujón actual, ya desvanecido. Lo suma quien mueve la entidad.
func empuje_actual(delta: float) -> Vector3:
	if _empuje_t <= 0.0:
		_empuje = Vector3.ZERO
		return Vector3.ZERO
	_empuje_t -= delta
	# Decae: el empujón no es un empujón constante, es un golpe.
	_empuje = _empuje.lerp(Vector3.ZERO, clampf(delta / EMPUJE_TIEMPO, 0.0, 1.0))
	return _empuje


## Qué partículas pegar según de quién es el cuerpo. Es la puerta que usa
## el pool: la decide el arquetipo (un esqueleto escupe hueso, no sangre).
func _tipo_sangre() -> String:
	if self is Enemy:
		var e: Enemy = self as Enemy
		if e.es_jefe:
			return "chispa"
		# El arquetipo lleva su propio tipo de sangre en los datos; si no lo
		# dice, es sangre. Es la puerta que el pool usa para elegir particula.
		var n: String = str(e.tipo_sangre)
		return n if n != "" else "sangre"
	return "chispa"


## ¿Está siendo empujado ahora? Para la UI y los tests.
func siendo_empujado() -> bool:
	return _empuje_t > 0.0


func take_damage(cantidad: float, fuente: Entity, es_critico: bool = false) -> void:
	if not combatible:
		return
	if not esta_vivo():
		return
	var dano: float = maxf(cantidad, 0.0)
	vida_actual = maxf(vida_actual - dano, 0.0)
	# Bloque 68: el golpe empuja. Un crítico empuja más (1.6x).
	if fuente != null and fuente != self and esta_vivo():
		aplicar_empuje(fuente, dano, 1.6 if es_critico else 1.0)
		# Bloque 68: la chispa. Va en el impacto, no en el atacante: el efecto
		# tiene que estar EN QUIEN RECIBIO el golpe.
		#
		# Defensivo: `is_inside_tree()` porque un test (o un preload) puede
		# pegar a una entidad que todavia no esta colgada, y `global_position`
		# reventaria. Sin arbol no hay chispa, que es el comportamiento de
		# antes del bloque.
		if is_inside_tree():
			var pool := PoolImpacto.de(get_tree().current_scene)
			if pool != null:
				pool.golpear(global_position + Vector3(0, 0.9, 0), _tipo_sangre())
	flash_tiempo = FLASH_DURACION
	daniado.emit(dano, fuente)
	GameFeel.al_recibir_danio(self, dano, fuente, es_critico)
	# Bloque 66: posicional. Un golpe a 40 m tiene que sonar a 40 m.
	if self is Node3D:
		AudioJuego.reproducir_en(self as Node3D, "critico" if es_critico else "golpe")
	else:
		AudioJuego.al_impacto(es_critico)
	vida_cambiada.emit(vida_actual, stats.vida_max)
	if vida_actual <= 0.0:
		die(fuente)


## Decaimiento del flash rojo (fase 5.1). Entity no definía _process:
## Enemy y Player solo usan _physics_process, así que no hay colisión.
func _process(delta: float) -> void:
	if flash_tiempo > 0.0:
		flash_tiempo = maxf(flash_tiempo - delta, 0.0)
	if fx_tiempo > 0.0:
		fx_tiempo = maxf(fx_tiempo - delta, 0.0)


## 0.0 = sin flash, 1.0 = impacto recién recibido. Lo lee DamageFlash.
func intensidad_flash() -> float:
	return clampf(flash_tiempo / FLASH_DURACION, 0.0, 1.0)


## Fase 18 — dispara el tinte visual de un skill (color por tipo de
## efecto). Lo lee SkillFX. No hace nada en muertos.
func mostrar_fx(color: Color) -> void:
	if not esta_vivo():
		return
	fx_color = color
	fx_tiempo = FX_DURACION


## 0.0 = sin tinte, 1.0 = skill recién lanzado. Lo lee SkillFX.
func intensidad_fx() -> float:
	return clampf(fx_tiempo / FX_DURACION, 0.0, 1.0)


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
	var vd: Dictionary = d.get("vitals", {})
	if not vd.is_empty():
		vitals = Vitals.from_dict(vd)
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


## Fase 54: los vitales de supervivencia. Los consume el inventario al
## comer/beber; el decaimiento por tiempo es de la fase 58. Es un objeto
## puro, así que se prueba headless sin nodos.
var vitals: Vitals = Vitals.new()

## Fase 51: revive EN RUNTIME, no al cargar un save. Envuelve
## `_revivir_silencioso()` (que ya restaura capas y procesado) y además pone
## vida/maná y emite las señales, para que la UI se entere.
##
## Antes esto no existía: `die()` apagaba `_process`/`_physics_process` y
## `collision_layer`, y solo la arena escuchaba a `Player.murio`. Morir
## fuera de la arena congelaba el juego para siempre.
##
## `vida`/`mana` negativos = llenar el máximo. Sobre una entidad viva no
## hace nada (idempotente, como `die()`).
func revivir(vida: float = -1.0, mana: float = -1.0) -> void:
	if not _muerto:
		return
	_revivir_silencioso()
	vida_actual = stats.vida_max if vida < 0.0 else clampf(vida, 0.0, stats.vida_max)
	mana_actual = stats.mana_max if mana < 0.0 else clampf(mana, 0.0, stats.mana_max)
	flash_tiempo = 0.0
	# Sin esto la UI queda con 0/máx hasta el siguiente cambio: el retrato se
	# pinta de gris al morir y no se destiñe si no le llega nada.
	vida_cambiada.emit(vida_actual, stats.vida_max)
	mana_cambiado.emit(mana_actual, stats.mana_max)


## Serialización versionada (la usa el save/load de la fase 4).
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"nivel": nivel,
		"xp_actual": xp_actual,
		"vida_actual": vida_actual,
		"mana_actual": mana_actual,
		"stats": stats.to_dict(),
		"vitals": vitals.to_dict(),
	}


static func from_dict(d: Dictionary) -> Entity:
	# Se guardó muerta: carga muerta sin re-emitir `murio` (lo garantiza restaurar).
	var e: Entity = Entity.new()
	e.restaurar(d)
	return e
