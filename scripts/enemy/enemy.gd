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
## Colisión de un enemigo vivo (ver scenes/enemy/enemigo.tscn): la usa
## reiniciar() al sacar del pool; devolver al pool la apaga a 0.
const CAPA_VIVA: int = 4
const MASCARA_VIVA: int = 1

## Id del arquetipo en data/enemies.json (se asigna en la escena).
@export var arquetipo_id: String = ""

var nombre_mostrado: String = "Enemigo"

## Fase 49 — el estado es una propiedad para que el clip de animación cambie
## en los 9 sitios que lo asignan, no en uno. `_estado` guarda el valor; la
## propiedad solo lo reenvía y, si el modelo tiene `AnimationPlayer`, pone el
## clip que le toca a la FSM. Setear el mismo estado no repite el clip (el
## pool reinicia estados en cada `_ready` y no queremos que el bicho se
## reinicie solo).
var _estado: Estado = Estado.QUIETO
var estado: Estado:
	get: return _estado
	set(v):
		if v == _estado:
			return
		_estado = v
		_reproducir_estado(v)

## Fase 49: el modelo 3D del arquetipo, si lo hay, y su reproductor. El
## `AnimationPlayer` solo existe si el `.glb` viene riggeado; con un modelo
## estatico se queda en null y el bicho se dibuja igual que antes.
var _modelo: Node3D = null
var _anim: AnimationPlayer = null

## Clip por estado de la FSM. Los nombres son los de `data/anclajes.json`.
const CLIP_POR_ESTADO: Dictionary = {
	Estado.QUIETO: "idle",
	Estado.PERSEGUIR: "walk",
	Estado.ATACAR: "attack",
	Estado.MUERTO: "die",
}
var radio_aggro: float = 10.0
var rango_ataque: float = 2.2
var cooldown_ataque: float = 1.6
var xp_recompensa: int = 10
## Fase 43: base del arquetipo (para escalar sin acumular) y XP sin escala.
var xp_recompensa_base: int = 10
var _base_arquetipo: Dictionary = {}
## A quién persigue/ataca (lo asigna la escena demo; si es null se busca
## el grupo "jugador" en _ready).
var objetivo: Entity = null
## RNG propio (para tiradas de ataque y botín). Se puede fijar la semilla
## desde fuera para tests deterministas.
var rng: RandomNumberGenerator = null

var _tabla_loot: Dictionary = {}
var _cd: float = 0.0
## Fase 33 — élite data-driven (bloque "elite" del arquetipo): más fuerza,
## ×5 XP/oro, tinte dorado, escala 1.3 y loot extra raro (equipo fase 31).
## El sorteo vive en `sortear_elite()` (pool/respawn); `configurar()` siempre
## resetea (reutilización del pool). Sin bloque: prob 0 (jefes nunca).
var es_elite: bool = false
const ESCALA_ELITE: float = 1.3
const SUFIJO_ELITE: String = "élite"
## Fase 12.1: reparto del tick de IA (0..7, lo fija el streaming al
## instanciar) + contador de frames para escalonar el cerebro.
var reparto: int = 0
var _frame_ia: int = 0
## Fase 12.1: materiales compartidos por color de arquetipo (antes cada
## mob creaba su StandardMaterial3D propio: 1121 materiales únicos).
static var _mats_cache: Dictionary = {}


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


## Fase 49 — pone el modelo 3D del arquetipo debajo del enemigo.
##
## Instancia el `.glb` entero como nodo `Modelo` en vez de cambiar la malla de
## `Cuerpo`. Es lo que permite que traiga `Skeleton3D` y `AnimationPlayer`: una
## malla con skin pegada a un `MeshInstance3D` suelto no se deforma, porque la
## piel necesita el esqueleto en la misma rama.
##
## Siempre desmonta lo anterior ANTES de decidir: el pool reutiliza el nodo
## entre arquetipos y sin ese reset un goblin con modelo arrastraría el modelo
## al siguiente arquetipo que pasara por el pool.
##
## Campos del arquetipo: `modelo` (ruta del `.glb`) y `modelo_escala`.
## Devuelve true si queda un modelo puesto.
func _aplicar_modelo(arquetipo: Dictionary) -> bool:
	_desmontar_modelo()
	var cuerpo: MeshInstance3D = get_node_or_null("Cuerpo") as MeshInstance3D
	if cuerpo == null:
		return false
	var ruta: String = str(arquetipo.get("modelo", ""))
	if ruta == "":
		return false
	if not ruta.begins_with("res://"):
		push_warning("[Enemy] la ruta de modelo no es res://: %s" % ruta)
		return false
	if not ResourceLoader.exists(ruta):
		# Sin modelo se juega con la capsula: el juego nunca se rompe por un
		# asset que falte (misma politica que el paper-doll).
		push_warning("[Enemy] el modelo de '%s' no existe: %s" % [nombre_mostrado, ruta])
		return false
	var ps: PackedScene = load(ruta) as PackedScene
	if ps == null:
		push_warning("[Enemy] '%s' no es una escena importable: %s" % [nombre_mostrado, ruta])
		return false
	var inst: Node3D = ps.instantiate() as Node3D
	if inst == null:
		push_warning("[Enemy] '%s' no instancia a un Node3D" % ruta)
		return false
	inst.name = "Modelo"
	add_child(inst)
	_modelo = inst
	var esc: float = float(arquetipo.get("modelo_escala", 1.0))
	if esc > 0.0 and not is_equal_approx(esc, 1.0):
		_modelo.scale = Vector3(esc, esc, esc)
	# La capsula se apaga: si no, se ven las dos.
	cuerpo.visible = false
	_anim = _buscar_anim(inst)
	_preparar_clips()
	_reproducir_estado(_estado)
	return true


## Casi todos los clips tienen que ciclar: importados asi vienen lineales, y
## sin bucle el bicho se congela a media pose y vuelve de golpe. `attack`
## tambien cicla porque el estado ATACAR dura mas que el clip (el cooldown es
## de ~1,6 s y el clip dura 0,83): si no, el bicho se queda con el ultimo
## frame del tajo entre golpe y golpe. `die` es el unico lineal: un cadaver
## que se levanta solo cada 1,2 s. Se marca una sola vez por modelo (el
## recurso Animation es compartido, que es lo que se quiere).
func _preparar_clips() -> void:
	if _anim == null:
		return
	for nombre in ["idle", "walk", "attack"]:
		if _anim.has_animation(nombre):
			_anim.get_animation(nombre).loop_mode = Animation.LOOP_LINEAR
	if _anim.has_animation("die"):
		_anim.get_animation("die").loop_mode = Animation.LOOP_NONE


## Quita el modelo y deja la capsula como estaba. La parte que se puede
## equivocar (pool), y por eso va al principio de `_aplicar_modelo`.
func _desmontar_modelo() -> void:
	if _modelo != null and is_instance_valid(_modelo):
		# Fuera del arbol en el acto, freeing al final del frame: si solo se
		# hiciera queue_free(), el pool veria el modelo viejo un frame mas.
		remove_child(_modelo)
		_modelo.queue_free()
	_modelo = null
	_anim = null
	var cuerpo: MeshInstance3D = get_node_or_null("Cuerpo") as MeshInstance3D
	if cuerpo != null:
		cuerpo.visible = estado != Estado.MUERTO
		cuerpo.scale = Vector3.ONE
		cuerpo.material_override = null


## Primer `AnimationPlayer` del subarbol del modelo (el importador lo deja en
## la raiz del `.glb`, pero no se fia).
func _buscar_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var hallada: AnimationPlayer = _buscar_anim(c)
		if hallada != null:
			return hallada
	return null


## Pone el clip que le toca al estado. Sin modelo, o sin ese clip, no hace
## nada: el enemigo se queda con su animacion anterior en vez de rayar.
func _reproducir_estado(v: Estado) -> void:
	if _anim == null or not is_instance_valid(_anim):
		return
	var clip: String = str(CLIP_POR_ESTADO.get(v, ""))
	if clip == "" or not _anim.has_animation(clip):
		return
	# Sin parametros: el 3er argumento de play() es la VELOCIDAD, y con -1.0
	# reproducia del reves. El bucle va en el recurso (ver _preparar_clips).
	_anim.play(clip)


## Aplica un arquetipo de datos (data/enemies.json): stats, IA, loot y color.
## Fase 33: resetea el estado élite (el pool reutiliza nodos).
func configurar(arquetipo: Dictionary) -> void:
	es_elite = false
	scale = Vector3.ONE
	nombre_mostrado = str(arquetipo.get("nombre", "Enemigo"))
	stats = StatBlock.new(
		float(arquetipo.get("fuerza", 5.0)),
		float(arquetipo.get("aguante", 0.0)),
		float(arquetipo.get("destreza", 5.0)),
		float(arquetipo.get("inteligencia", 5.0))
	)
	# Fase 42: los mobs dañan con su stat principal (STR por defecto; un
	# arquetipo puede declarar "stat_daño" para mobs de finesse/arcana).
	stats.set_stat_daño(str(arquetipo.get("stat_daño", "fuerza")))
	vida_actual = stats.vida_max
	mana_actual = stats.mana_max
	radio_aggro = float(arquetipo.get("radio_aggro", 10.0))
	rango_ataque = float(arquetipo.get("rango_ataque", 2.2))
	cooldown_ataque = float(arquetipo.get("cooldown_ataque", 1.6))
	xp_recompensa = int(arquetipo.get("xp", 10))
	xp_recompensa_base = xp_recompensa
	_base_arquetipo = {
		"fuerza": float(arquetipo.get("fuerza", 5.0)),
		"aguante": float(arquetipo.get("aguante", 0.0)),
		"destreza": float(arquetipo.get("destreza", 5.0)),
		"inteligencia": float(arquetipo.get("inteligencia", 5.0)),
	}
	var items: Array = []
	var loot: Dictionary = arquetipo.get("loot", {})
	if not loot.is_empty():
		items = loot.get("items", [])
	_tabla_loot = {
		"oro_min": int(arquetipo.get("oro_min", 0)),
		"oro_max": int(arquetipo.get("oro_max", 0)),
		"items": items,
	}
	# Fase 35: ajuste de balance data-driven (1.0 = sin cambio). Vía MOD
	# (reversible, serializa en el save como el resto de mods).
	var mv: float = float(arquetipo.get("mult_vida", 1.0))
	if mv != 1.0:
		stats.add_mod("balance:vida", "vida_max", StatBlock.ModKind.PORCENTUAL, mv - 1.0)
		vida_actual = stats.vida_max
	# Fase 49: si el arquetipo trae modelo 3D, la cápsula se sustituye por él
	# (y NO se tiñe: un `material_override` plano se comería la textura). Si no
	# lo trae, se vuelve a la cápsula (el pool reutiliza el nodo) y se tiñe.
	if not _aplicar_modelo(arquetipo):
		_tintar(arquetipo.get("color", [0.8, 0.25, 0.25]))


## Fase 43 — escala regional (data/regiones.json → bloque `escala`):
## multiplica los STATS BASE del arquetipo (stats) y sus recompensas
## (xp, oro). Idempotente si se pasa el factor ABSOLUTO de la región
## (no acumulado): llamar dos veces con 3.0 deja 3.0, no 9.0.
## La aplica el streaming (la arena usa su propia curva y no la llama).
func aplicar_escala(escala: Dictionary) -> void:
	if escala.is_empty():
		return
	var ms: float = float(escala.get("stats", 1.0))
	# Fase 43: la defensa crece MÁS LENTO que la vida/ataque. Si no, la
	# mitigación (ratio) hace que el TTK se dispare en las bandas altas
	# (el mobs aguanta 100+ golpes). `defensa` escala el aguante (placas).
	var mdef: float = float(escala.get("defensa", ms))
	if ms > 0.0 and not is_equal_approx(ms, 1.0):
		stats.set_base("fuerza", float(arquetipo_base("fuerza")) * ms)
		stats.set_base("destreza", float(arquetipo_base("destreza")) * ms)
		stats.set_base("inteligencia", float(arquetipo_base("inteligencia")) * ms)
	if mdef > 0.0 and not is_equal_approx(mdef, 1.0):
		stats.set_base("aguante", float(arquetipo_base("aguante")) * mdef)
	stats.recalc()
	vida_actual = stats.vida_max
	mana_actual = stats.mana_max
	var mx: float = float(escala.get("xp", 1.0))
	if mx > 0.0 and not is_equal_approx(mx, 1.0):
		xp_recompensa = int(roundf(float(xp_recompensa_base) * mx))
	var mo: float = float(escala.get("oro", 1.0))
	if mo > 0.0 and not is_equal_approx(mo, 1.0):
		_tabla_loot["oro_min"] = int(roundf(float(_tabla_loot.get("oro_min", 0)) * mo))
		_tabla_loot["oro_max"] = int(roundf(float(_tabla_loot.get("oro_max", 0)) * mo))
	# Fase 43: la vida crece MÁS que los stats (si no, el TTK queda plano en
	# todas las bandas y el combate no escala). Va como MOD (id estable →
	 # aplicarla dos veces no la acumula).
	var mv: float = float(escala.get("vida", 1.0))
	if mv > 0.0 and not is_equal_approx(mv, 1.0):
		stats.add_mod("escala:vida", "vida_max", StatBlock.ModKind.PORCENTUAL, mv - 1.0)
		vida_actual = stats.vida_max


## Valor BASE del arquetipo (sin escala) para un stat. Lo guarda configurar()
## para que aplicar_escala sea idempotente.
func arquetipo_base(stat: String) -> float:
	return float(_base_arquetipo.get(stat, 0.0))


## Fase 33 — probabilidad élite del arquetipo (0 sin bloque: jefes nunca).
static func prob_elite(arquetipo: Dictionary) -> float:
	var bloque: Dictionary = arquetipo.get("elite", {})
	return clampf(float(bloque.get("prob", 0.0)), 0.0, 1.0)


## Convierte al mob en élite según el bloque: ×fuerza (recalcula vida y
## ataque), vida/maná llenos, ×XP/oro, loot extra raro, "X élite", tinte
## dorado y escala 1.3. Idempotente y con defaults (bloque parcial válido).
## La lista de items se DUPLICA antes de añadir: la de configurar() es una
## referencia al caché del JSON y no debe mutarse.
func hacer_elite(bloque: Dictionary) -> void:
	if es_elite:
		return
	es_elite = true
	stats.set_base("fuerza", stats.fuerza * float(bloque.get("mult_fuerza", 1.5)))
	vida_actual = stats.vida_max
	mana_actual = stats.mana_max
	xp_recompensa = int(roundf(float(xp_recompensa) * float(bloque.get("mult_xp", 5.0))))
	var mo: float = float(bloque.get("mult_oro", 5.0))
	_tabla_loot["oro_min"] = int(roundf(float(_tabla_loot.get("oro_min", 0)) * mo))
	_tabla_loot["oro_max"] = int(roundf(float(_tabla_loot.get("oro_max", 0)) * mo))
	var lista: Array = (_tabla_loot.get("items", []) as Array).duplicate()
	for extra in bloque.get("loot_extra", []):
		if extra is Dictionary:
			lista.append((extra as Dictionary).duplicate())
	_tabla_loot["items"] = lista
	nombre_mostrado = "%s %s" % [nombre_mostrado, SUFIJO_ELITE]
	_tintar(bloque.get("tinte", [1.0, 0.62, 0.12]))
	scale = Vector3.ONE * ESCALA_ELITE


## Sortea élite con el RNG propio (pool + respawn). Retorna si quedó élite.
func sortear_elite(arquetipo: Dictionary) -> bool:
	if rng == null:
		return false
	if rng.randf() < prob_elite(arquetipo):
		hacer_elite(arquetipo.get("elite", {}))
	return es_elite




## Color del cuerpo según el arquetipo (material COMPARTIDO por color:
## fase 12.1 — antes cada mob creaba su StandardMaterial3D propio).
func _tintar(c: Variant) -> void:
	var cuerpo: MeshInstance3D = get_node_or_null("Cuerpo") as MeshInstance3D
	if cuerpo == null:
		return
	var col: Array = c
	var r: float = float(col[0]) if col.size() > 0 else 0.8
	var g: float = float(col[1]) if col.size() > 1 else 0.25
	var b: float = float(col[2]) if col.size() > 2 else 0.25
	var clave: String = "%d,%d,%d" % [int(r * 255.0), int(g * 255.0), int(b * 255.0)]
	if not _mats_cache.has(clave):
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(r, g, b)
		mat.roughness = 0.7
		_mats_cache[clave] = mat
	cuerpo.material_override = _mats_cache[clave]


## Fase 49: con modelo puesto hay dos nodos que dibujar (la capsula apagada y
## `Modelo`), y los dos tienen que moverse a la vez o se ve la capsula
## apareciendo encima del personaje.
func ocultar_cuerpo() -> void:
	var cuerpo: MeshInstance3D = get_node_or_null("Cuerpo") as MeshInstance3D
	if cuerpo != null:
		cuerpo.visible = false
	if _modelo != null and is_instance_valid(_modelo):
		_modelo.visible = false


func mostrar_cuerpo() -> void:
	var cuerpo: MeshInstance3D = get_node_or_null("Cuerpo") as MeshInstance3D
	if cuerpo != null:
		cuerpo.visible = _modelo == null
	if _modelo != null and is_instance_valid(_modelo):
		_modelo.visible = true


func _physics_process(delta: float) -> void:
	if not esta_vivo():
		estado = Estado.MUERTO
		return
	_cd = maxf(_cd - delta, 0.0)
	# Fase 12.1: el cerebro no piensa cada frame. Cerca del objetivo piensa
	# siempre; lejos se reparte (el `reparto` lo fija el streaming al
	# instanciar para que no piensen todos en el mismo frame).
	_frame_ia += 1
	var dist_cerebro: float = _distancia_objetivo()
	if (_frame_ia + reparto) % intervalo_cerebro(dist_cerebro) == 0:
		_actualizar_estado()
	_actuar(delta)
	# Fase 12: los creeps caminan pegados al terreno del mundo abierto.
	_pegar_al_terreno()


## Fase 12.1: cada cuántos frames de física piensa el cerebro según la
## distancia plana al objetivo. Pura y testeable (INF = sin objetivo).
static func intervalo_cerebro(dist: float) -> int:
	if dist < 60.0:
		return 1
	if dist < 250.0:
		return 3
	return 6


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
	objetivo.take_damage(float(res["final"]), self, bool(res["crit"]))


## Muerte: además del apagado de Entity, emite el botín y premia al asesino.
## Idempotente vía el early-out de esta_vivo().
func die(fuente: Entity = null) -> void:
	if not esta_vivo():
		return
	super.die(fuente)
	estado = Estado.MUERTO
	AudioJuego.al_morir()
	var drops: Array = DropTable.roll_drops(_tabla_loot, rng)
	botin_generado.emit(drops, global_position)
	if fuente != null and fuente != self and fuente.esta_vivo():
		fuente.gain_xp(xp_recompensa)


## Al cargar partida: el estado se deduce de la vida (muerto → MUERTO).
## Fase 43: restaura también la XP y la escala del arquetipo — sin esto un
## mob guardado daba la XP por defecto (10) en vez de la regional escalada.
func restaurar(d: Dictionary) -> void:
	super.restaurar(d)
	estado = Estado.MUERTO if not esta_vivo() else Estado.QUIETO
	_cd = 0.0
	xp_recompensa_base = int(d.get("xp_base", xp_recompensa_base))
	xp_recompensa = int(d.get("xp_recompensa", xp_recompensa))
	var ba: Dictionary = d.get("base_arquetipo", {})
	if not ba.is_empty():
		_base_arquetipo = ba


## Fase 43 — añade el estado de recompensa/escala al save del enemigo
## (override de Entity.to_dict; el resto del bloque se mantiene igual).
func to_dict() -> Dictionary:
	var d: Dictionary = super.to_dict()
	d["xp_base"] = xp_recompensa_base
	d["xp_recompensa"] = xp_recompensa
	d["base_arquetipo"] = _base_arquetipo.duplicate()
	return d


## Fase 20 — reutilización por pooling (PoolMobs): deja al enemigo como
## recién configurado y vivo, listo para reaparecer en otra posición.
## Reaplica el arquetipo (stats/vida/maná/loot/tinte), revive colisión y
## procesado, muestra el cuerpo y limpia velocidad/flash/fx. Idempotente:
## llamarlo sobre un enemigo ya vivo solo lo reconfigura.
func reiniciar(arquetipo: Dictionary) -> void:
	configurar(arquetipo)
	# Fase 33: cada reaparición re-sortea élite (con el RNG propio).
	sortear_elite(arquetipo)
	_muerto = false
	estado = Estado.QUIETO
	_cd = 0.0
	_frame_ia = 0
	flash_tiempo = 0.0
	fx_tiempo = 0.0
	velocity = Vector3.ZERO
	collision_layer = CAPA_VIVA
	collision_mask = MASCARA_VIVA
	mostrar_cuerpo()
	# Fase 20: la barra de vida se resetea con el mob (oculta, sin reloj).
	var barra: BarraVidaMob = get_node_or_null("BarraVida") as BarraVidaMob
	if barra != null:
		barra.reiniciar()
	set_process(true)
	set_physics_process(true)
