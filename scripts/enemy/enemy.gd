class_name Enemy
extends Entity
## Enemigo mínimo de la fase 4: IA de 4 estados + botín + XP al asesino.
##
## Estados: QUIETO → PERSEGUIR → ATACAR → MUERTO.
## Data-driven: `configurar(arquetipo)` recibe el diccionario de
## data/enemies.json (stats, aggro, rangos, cooldown, XP, loot). Un enemigo
## nuevo = editar datos, no código.
##
## - En PERSEGUIR usa la matemática de `Movimiento` (igual que el jugador).
## - En ATACAR pega con `Formulas.damage` → `objetivo.take_damage`.
## - Al morir emite `botin_generado(drops, posicion)` (un sistema externo
##   crea los pickups; este script no referencia ninguno) y le da su XP
##   al asesino vía `gain_xp` (API pública de Entity, no de otro sistema).
## Sin referencias a UI ni a sistemas futuros.

signal botin_generado(drops: Array, posicion: Vector3)

enum Estado { QUIETO, PERSEGUIR, ATACAR, MUERTO }

const GRAVEDAD: float = 24.0
const TASA_PERSECUCION: float = 8.0
## Deja de perseguir más allá de aggro × este factor (leash).
const FACTOR_SUELTA: float = 1.5

## Id del arquetipo en data/enemies.json (se asigna en la escena).
@export var arquetipo_id: String = ""

var nombre_mostrado: String = "Enemigo"
var estado: Estado = Estado.QUIETO
var radio_aggro: float = 10.0
var rango_ataque: float = 2.2
var cooldown_ataque: float = 1.6
var xp_recompensa: int = 10
## A quién persigue/ataca (lo asigna la escena demo; si es null se busca
## el grupo "jugador" en _ready).
var objetivo: Entity = null
## RNG propio (para tiradas de ataque y botín). Se puede fijar la semilla
## desde fuera para tests deterministas.
var rng: RandomNumberGenerator = null

var _tabla_loot: Dictionary = {}
var _cd: float = 0.0


func _init(p_stats: StatBlock = null) -> void:
	super._init(p_stats)
	# Fase 5.1: explícito. Los NPCs (clase NPC) ponen combatible = false;
	# los enemigos SIEMPRE son atacables.
	combatible = true
	rng = RandomNumberGenerator.new()
	rng.randomize()


func _ready() -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	if objetivo == null:
		objetivo = get_tree().get_first_node_in_group("jugador") as Entity


## Aplica un arquetipo de datos (data/enemies.json): stats, IA, loot y color.
func configurar(arquetipo: Dictionary) -> void:
	nombre_mostrado = str(arquetipo.get("nombre", "Enemigo"))
	stats = StatBlock.new(
		float(arquetipo.get("fuerza", 5.0)),
		float(arquetipo.get("agilidad", 5.0)),
		float(arquetipo.get("destreza", 5.0)),
		float(arquetipo.get("inteligencia", 5.0))
	)
	vida_actual = stats.vida_max
	mana_actual = stats.mana_max
	radio_aggro = float(arquetipo.get("radio_aggro", 10.0))
	rango_ataque = float(arquetipo.get("rango_ataque", 2.2))
	cooldown_ataque = float(arquetipo.get("cooldown_ataque", 1.6))
	xp_recompensa = int(arquetipo.get("xp", 10))
	var items: Array = []
	var loot: Dictionary = arquetipo.get("loot", {})
	if not loot.is_empty():
		items = loot.get("items", [])
	_tabla_loot = {
		"oro_min": int(arquetipo.get("oro_min", 0)),
		"oro_max": int(arquetipo.get("oro_max", 0)),
		"items": items,
	}
	_tintar(arquetipo.get("color", [0.8, 0.25, 0.25]))


## Color del cuerpo según el arquetipo (material propio por instancia).
func _tintar(c: Variant) -> void:
	var cuerpo: MeshInstance3D = get_node_or_null("Cuerpo") as MeshInstance3D
	if cuerpo == null:
		return
	var col: Array = c
	var r: float = float(col[0]) if col.size() > 0 else 0.8
	var g: float = float(col[1]) if col.size() > 1 else 0.25
	var b: float = float(col[2]) if col.size() > 2 else 0.25
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(r, g, b)
	mat.roughness = 0.7
	cuerpo.material_override = mat


func ocultar_cuerpo() -> void:
	var cuerpo: MeshInstance3D = get_node_or_null("Cuerpo") as MeshInstance3D
	if cuerpo != null:
		cuerpo.visible = false


func mostrar_cuerpo() -> void:
	var cuerpo: MeshInstance3D = get_node_or_null("Cuerpo") as MeshInstance3D
	if cuerpo != null:
		cuerpo.visible = true


func _physics_process(delta: float) -> void:
	if not esta_vivo():
		estado = Estado.MUERTO
		return
	_cd = maxf(_cd - delta, 0.0)
	_actualizar_estado()
	_actuar(delta)
	# Fase 12: los creeps caminan pegados al terreno del mundo abierto.
	_pegar_al_terreno()


## Distancia plana al objetivo; INF si no hay objetivo válido.
func _distancia_objetivo() -> float:
	if objetivo == null or not objetivo.esta_vivo():
		return INF
	var d: Vector3 = objetivo.global_position - global_position
	d.y = 0.0
	return d.length()


## Cerebro: solo decide el estado (sin física; testeable). Pública para tests.
func _actualizar_estado() -> void:
	var dist: float = _distancia_objetivo()
	match estado:
		Estado.QUIETO:
			if dist <= radio_aggro:
				estado = Estado.PERSEGUIR
		Estado.PERSEGUIR:
			if dist == INF or dist > radio_aggro * FACTOR_SUELTA:
				estado = Estado.QUIETO
			elif dist <= rango_ataque:
				estado = Estado.ATACAR
		Estado.ATACAR:
			if dist == INF:
				estado = Estado.QUIETO
			elif dist > rango_ataque * 1.25:
				estado = Estado.PERSEGUIR
		Estado.MUERTO:
			pass


## Cuerpo: actúa según el estado (movimiento + golpes + física).
func _actuar(delta: float) -> void:
	var meta: Vector3 = Vector3.ZERO
	if estado == Estado.PERSEGUIR and objetivo != null and objetivo.esta_vivo():
		var hacia: Vector3 = objetivo.global_position - global_position
		hacia.y = 0.0
		var dist: float = hacia.length()
		if dist > 0.05:
			meta = Movimiento.velocidad_meta(hacia.normalized(), dist, stats.vel_mov, 0.4, 2.0)
			rotation.y = lerp_angle(rotation.y, Movimiento.yaw_hacia(hacia), clampf(10.0 * delta, 0.0, 1.0))
	elif estado == Estado.ATACAR:
		if objetivo != null and objetivo.esta_vivo():
			var mirar: Vector3 = objetivo.global_position - global_position
			mirar.y = 0.0
			if mirar.length() > 0.05:
				rotation.y = lerp_angle(rotation.y, Movimiento.yaw_hacia(mirar), clampf(10.0 * delta, 0.0, 1.0))
		if _cd <= 0.0:
			_golpear()
			_cd = cooldown_ataque / maxf(stats.vel_ataque, 0.1)
	var plano: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var suave: Vector3 = Movimiento.suavizar(plano, meta, delta, TASA_PERSECUCION)
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVEDAD * delta
	velocity.x = suave.x
	velocity.z = suave.z
	move_and_slide()


## Un golpe al objetivo con las fórmulas puras (daño mínimo 1 garantizado).
func _golpear() -> void:
	if objetivo == null or not objetivo.esta_vivo():
		return
	var res: Dictionary = Formulas.damage(
		stats, objetivo.stats, {"power": 1.0},
		rng.randf(), rng.randf_range(-1.0, 1.0))
	objetivo.take_damage(float(res["final"]), self)


## Muerte: además del apagado de Entity, emite el botín y premia al asesino.
## Idempotente vía el early-out de esta_vivo().
func die(fuente: Entity = null) -> void:
	if not esta_vivo():
		return
	super.die(fuente)
	estado = Estado.MUERTO
	var drops: Array = DropTable.roll_drops(_tabla_loot, rng)
	botin_generado.emit(drops, global_position)
	if fuente != null and fuente != self and fuente.esta_vivo():
		fuente.gain_xp(xp_recompensa)


## Al cargar partida: el estado se deduce de la vida (muerto → MUERTO).
func restaurar(d: Dictionary) -> void:
	super.restaurar(d)
	estado = Estado.MUERTO if not esta_vivo() else Estado.QUIETO
	_cd = 0.0
