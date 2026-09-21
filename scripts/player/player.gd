class_name Player
extends Entity
## El héroe: una Entity que se mueve por INTENCIONES y ataca por objetivo.
##
## Cada physics frame: lee el input (InputMap, sin teclas hardcodeadas),
## construye UN Intent y lo consume para moverse. El input NUNCA ejecuta
## acciones directas:
## - WASD (relativo a la cámara) → move_dir; tiene prioridad y cancela
##   la orden de clic y el objetivo de ataque (control manual total).
## - Clic izquierdo → destino en el mundo (raycast a la capa de suelo).
## - Doble clic izquierdo → intenta fijar un enemigo como objetivo de
##   ataque (raycast); si lo logra, lo persigue hasta el rango y pega
##   con `Formulas.damage`. Sin animaciones todavía: solo el número.
## Sin referencias a UI ni a ningún otro sistema.

signal intencion_atacar(objetivo: Entity)
signal oro_cambiado(oro: int)
signal item_recogido(item: Dictionary)

## --- Game feel: todos los tunables en un solo sitio ---
const ACEL_TASA: float = 9.0      ## Qué tan rápido arranca (mayor = más inmediato).
const FRENADO_TASA: float = 11.0  ## Qué tan rápido frena (mayor = más seco).
const RADIO_LLEGADA: float = 0.35 ## Distancia al destino donde se detiene.
const RADIO_FRENADO: float = 2.5  ## Distancia donde empieza a desacelerar.
const VEL_GIRO: float = 12.0      ## Qué tan rápido rota el cuerpo al moverse.
const GRAVEDAD: float = 24.0      ## Gravedad propia (mundo sin físicas raras).
const ALCANCE_RAYO: float = 1000.0 ## Alcance del raycast clic→mundo.
const RANGO_ATAQUE: float = 2.6   ## Distancia cuerpo a cuerpo del héroe.

## Ruta al CameraRig en la escena (se asigna en el .tscn; sin esto el WASD
## usa yaw 0 y el clic no tiene cámara para proyectar).
@export var ruta_rig: NodePath

## La intención del frame actual (la UI futura y los tests pueden leerla).
var intent: Intent
## Objetivo de ataque (doble clic sobre un enemigo). null = sin objetivo.
var objetivo_ataque: Entity = null
## Oro e inventario simple (el inventario real llega en la fase 5).
var oro: int = 0
var inventario_simple: Array = []

var _rig: CameraRig = null
var _tiene_destino: bool = false
var _destino: Vector3 = Vector3.ZERO
var _cd_ataque: float = 0.0


func _ready() -> void:
	intent = Intent.new()
	# Stats de prueba para la demo (fase 4): ataque = 5 + 45*2 + 10*0.5 = 100.
	# Solo si el bloque viene por defecto (sin stats explícitos): no pisar
	# los stats que alguien pasó al constructor (tests, save/load).
	if stats.fuerza == 0.0 and stats.agilidad == 0.0 \
			and stats.destreza == 0.0 and stats.inteligencia == 0.0:
		stats.fuerza = 45.0
		stats.agilidad = 10.0
		stats.recalc()
		vida_actual = stats.vida_max
	if ruta_rig != NodePath(""):
		_rig = get_node_or_null(ruta_rig) as CameraRig


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.double_click:
				_intentar_fijar_objetivo(mb.position)
			else:
				_orden_mover_a(mb.position)


## Doble clic: si el rayo pega en un enemigo vivo, se vuelve el objetivo de
## ataque (se persigue y se pega al llegar al rango). Si pega en el suelo,
## se comporta como una orden de mover (comportamiento del legado).
func _intentar_fijar_objetivo(pantalla: Vector2) -> void:
	intent.quiere_atacar = true
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var origen: Vector3 = cam.project_ray_origin(pantalla)
	var dir: Vector3 = cam.project_ray_normal(pantalla)
	var consulta: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origen, origen + dir * ALCANCE_RAYO
	)
	var excluir: Array[RID] = [get_rid()]
	consulta.exclude = excluir
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(consulta)
	if hit.is_empty():
		objetivo_ataque = null
		_tiene_destino = false
		intencion_atacar.emit(null)
		return
	var col: Object = hit.get("collider")
	if col is Enemy:
		var en: Enemy = col as Enemy
		if en.esta_vivo():
			objetivo_ataque = en
			intent.objetivo = en
			_tiene_destino = true
			_destino = en.global_position
			intencion_atacar.emit(en)
			return
	objetivo_ataque = null
	_orden_mover_a(pantalla)
	intencion_atacar.emit(null)


## Clic izquierdo: proyecta el cursor al mundo y guarda el destino.
## Una orden de mover cancela el objetivo de ataque (control manual).
func _orden_mover_a(pantalla: Vector2) -> void:
	objetivo_ataque = null
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var origen: Vector3 = cam.project_ray_origin(pantalla)
	var dir: Vector3 = cam.project_ray_normal(pantalla)
	var consulta: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origen, origen + dir * ALCANCE_RAYO
	)
	var excluir: Array[RID] = [get_rid()]
	consulta.exclude = excluir
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(consulta)
	if hit.is_empty():
		return
	var punto: Vector3 = hit["position"]
	_destino = punto
	_tiene_destino = true


func _physics_process(delta: float) -> void:
	if not esta_vivo():
		return
	_cd_ataque = maxf(_cd_ataque - delta, 0.0)
	_construir_intent()
	_consumir_intent(delta)
	_actualizar_ataque(delta)


## Paso 1: input → Intent (datos). Sin mover nada todavía.
func _construir_intent() -> void:
	var v: Vector2 = Input.get_vector(
		"mover_izquierda", "mover_derecha", "mover_adelante", "mover_atras"
	)
	intent.move_dir = v
	if v.length() > 0.05:
		# El WASD tiene prioridad: cancela la orden de clic y el ataque
		# (el jugador toma el control manual total).
		_tiene_destino = false
		objetivo_ataque = null
	intent.tiene_destino = _tiene_destino
	intent.destino = _destino


## Si hay objetivo de ataque: lo persigue hasta el rango; en rango se queda
## quieto para pegar. Si el objetivo muere, se limpia solo.
func _actualizar_persecucion_ataque() -> void:
	if objetivo_ataque == null:
		return
	if not objetivo_ataque.esta_vivo():
		objetivo_ataque = null
		_tiene_destino = false
		return
	var a_obj: Vector3 = objetivo_ataque.global_position - global_position
	a_obj.y = 0.0
	if a_obj.length() <= RANGO_ATAQUE:
		_tiene_destino = false
	else:
		_destino = objetivo_ataque.global_position
		_tiene_destino = true


## Paso 2: Intent → velocidad. El único lugar que escribe velocity.
func _consumir_intent(delta: float) -> void:
	var yaw: float = _rig.rotation.y if _rig != null else 0.0
	_actualizar_persecucion_ataque()
	var meta: Vector3 = Vector3.ZERO
	var dir_wasd: Vector3 = Movimiento.direccion_relativa_camara(intent.move_dir, yaw)
	if dir_wasd.length() > 0.05:
		meta = dir_wasd * stats.vel_mov
	elif intent.tiene_destino:
		var a_destino: Vector3 = intent.destino - global_position
		a_destino.y = 0.0
		var dist: float = a_destino.length()
		if dist <= RADIO_LLEGADA:
			_tiene_destino = false
			intent.tiene_destino = false
		else:
			meta = Movimiento.velocidad_meta(
				a_destino.normalized(), dist, stats.vel_mov,
				RADIO_LLEGADA, RADIO_FRENADO
			)
	var plano_actual: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var tasa: float = ACEL_TASA if meta.length() >= plano_actual.length() else FRENADO_TASA
	var suave: Vector3 = Movimiento.suavizar(plano_actual, meta, delta, tasa)
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVEDAD * delta
	velocity.x = suave.x
	velocity.z = suave.z
	move_and_slide()
	# El cuerpo mira hacia donde se mueve (con giro amortiguado).
	var rapidez: float = Vector2(velocity.x, velocity.z).length()
	if rapidez > 0.5:
		var giro: float = clampf(VEL_GIRO * delta, 0.0, 1.0)
		rotation.y = lerp_angle(rotation.y, Movimiento.yaw_hacia(velocity), giro)


## Paso 3: si hay objetivo en rango y el cooldown lo permite, pega.
func _actualizar_ataque(delta: float) -> void:
	if not puede_atacar():
		return
	var dir: Vector3 = objetivo_ataque.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.05:
		var giro: float = clampf(VEL_GIRO * delta, 0.0, 1.0)
		rotation.y = lerp_angle(rotation.y, Movimiento.yaw_hacia(dir), giro)
	ejecutar_ataque()


func _dist_a_objetivo() -> float:
	if objetivo_ataque == null:
		return INF
	var d: Vector3 = objetivo_ataque.global_position - global_position
	d.y = 0.0
	return d.length()


## ¿Listo para pegar? Objetivo vivo, en rango y cooldown cumplido.
func puede_atacar() -> bool:
	return (_cd_ataque <= 0.0
		and objetivo_ataque != null
		and objetivo_ataque.esta_vivo()
		and _dist_a_objetivo() <= RANGO_ATAQUE)


## Golpe básico con las fórmulas puras. Sin animación todavía (fase 4).
func ejecutar_ataque() -> void:
	if not puede_atacar():
		return
	var res: Dictionary = Formulas.damage(
		stats, objetivo_ataque.stats, {"power": 1.0},
		randf(), randf_range(-1.0, 1.0))
	objetivo_ataque.take_damage(float(res["final"]), self)
	_cd_ataque = 1.0 / maxf(stats.vel_ataque, 0.1)


## Suma oro (lo emite para el HUD). Nunca deja el oro bajo 0.
func ganar_oro(cantidad: int) -> void:
	oro = maxi(0, oro + cantidad)
	oro_cambiado.emit(oro)


## Guarda un item como dato (el inventario real llega en la fase 5).
func guardar_item(item: Dictionary) -> void:
	inventario_simple.append(item)
	item_recogido.emit(item)
