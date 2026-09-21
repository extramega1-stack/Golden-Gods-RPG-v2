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
## Fase 5.1: cambió la entidad seleccionada (clic simple). null = deselección.
## La escuchan el indicador 3D y la UI futura; la emite solo Player.
signal seleccion_cambiada(entidad: Entity)

## --- Game feel: todos los tunables en un solo sitio ---
const ACEL_TASA: float = 9.0      ## Qué tan rápido arranca (mayor = más inmediato).
const FRENADO_TASA: float = 11.0  ## Qué tan rápido frena (mayor = más seco).
const RADIO_LLEGADA: float = 0.35 ## Distancia al destino donde se detiene.
const RADIO_FRENADO: float = 2.5  ## Distancia donde empieza a desacelerar.
const VEL_GIRO: float = 12.0      ## Qué tan rápido rota el cuerpo al moverse.
const GRAVEDAD: float = 24.0      ## Gravedad propia (mundo sin físicas raras).
const ALCANCE_RAYO: float = 1000.0 ## Alcance del raycast clic→mundo.
const RANGO_ATAQUE: float = 2.6   ## Distancia cuerpo a cuerpo del héroe.
## Fase 5.1: el botón de atacar, sin selección útil, engancha al combatible
## vivo más cercano dentro de este radio (luego lo persigue hasta el rango).
const RADIO_AUTOATAQUE: float = 8.0

## Ruta al CameraRig en la escena (se asigna en el .tscn; sin esto el WASD
## usa yaw 0 y el clic no tiene cámara para proyectar).
@export var ruta_rig: NodePath

## La intención del frame actual (la UI futura y los tests pueden leerla).
var intent: Intent
## Objetivo de ataque (doble clic / botón de atacar). null = sin objetivo.
var objetivo_ataque: Entity = null
## Fase 5.1 — entidad seleccionada (clic simple en mob o NPC; también se
## selecciona con doble clic). Los NPCs SÍ se pueden seleccionar, pero
## NUNCA son objetivo de ataque. Clic en suelo vacío o ESC deselecciona.
var seleccion: Entity = null
## Oro del héroe.
var oro: int = 0
## Sistemas de la fase 5 (se crean en _ready; nunca son null en juego).
var inventario: Inventario = null
var equipo: Equipo = null
var skills: SkillSystem = null

var _rig: CameraRig = null
var _tiene_destino: bool = false
var _destino: Vector3 = Vector3.ZERO
var _cd_ataque: float = 0.0
## Fase 5.1 — lanzamiento pendiente: skill dañina cuyo objetivo estaba fuera
## de rango. El jugador se acerca y la lanza al llegar; se cancela si el
## objetivo muere o deja de ser el foco (muerte/deselección/WASD).
var _pend_skill: String = ""
var _pend_objetivo: Entity = null


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
	# Sistemas de la fase 5 (después de lo existente: no dependen del rig).
	inventario = Inventario.new()
	equipo = Equipo.new()
	skills = SkillSystem.new()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("habilidad_1"):
		lanzar_skill(0)
	elif event.is_action_pressed("habilidad_2"):
		lanzar_skill(1)
	elif event.is_action_pressed("habilidad_3"):
		lanzar_skill(2)
	elif event.is_action_pressed("habilidad_4"):
		lanzar_skill(3)
	elif event.is_action_pressed("habilidad_5"):
		lanzar_skill(4)
	elif event.is_action_pressed("atacar"):
		# Fase 5.1: tecla reasignable (Input Map, acción "atacar").
		solicitar_ataque()
	elif event.is_action_pressed("cancelar_seleccion"):
		# Fase 5.1: ESC deselecciona (el lanzamiento pendiente se cancela
		# solo en el siguiente frame, porque su objetivo deja de ser el foco).
		deseleccionar()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.double_click:
				_intentar_fijar_objetivo(mb.position)
			else:
				_orden_mover_a(mb.position)


## Habilidades 1-5: lanza el skill i-ésimo del hotbar con objetivo inteligente.
## Fase 5.1: si es dañina y el objetivo está fuera de rango, NO se lanza
## todavía: queda "pendiente" y el jugador se acerca hasta el rango para
## lanzarla (se cancela si el objetivo muere o se deselecciona). Las
## curaciones se aplican al lanzador sin moverse. Pública para tests.
func lanzar_skill(i: int) -> void:
	if skills == null:
		return
	var ids: Array[String] = SkillDB.lista()
	if i < 0 or i >= ids.size():
		return
	var id: String = ids[i]
	var sk: Dictionary = SkillDB.obtener(id)
	var efecto: Dictionary = sk.get("efecto", {})
	var es_dano: bool = str(efecto.get("tipo", "")) == "dano"
	var obj: Entity = _objetivo_skill(id)
	if es_dano and obj != null and obj.esta_vivo():
		var rango: float = float(sk.get("rango", 0.0))
		if _dist_a(obj) > rango:
			_pend_skill = id
			_pend_objetivo = obj
			# El objetivo pendiente se vuelve foco de combate: así la regla
			# de cancelación (muerte / deselección / WASD) vale igual para
			# el caso "sin selección" (fallback al más cercano).
			if obj != seleccion and obj != objetivo_ataque:
				objetivo_ataque = obj
				intent.objetivo = obj
			_tiene_destino = true
			_destino = obj.global_position
			return
	skills.lanzar(id, self, obj)


## ¿Hay un lanzamiento pendiente de resolverse? (tests + UI futura).
func tiene_lanzamiento_pendiente() -> bool:
	return _pend_skill != "" and _pend_objetivo != null


## Fase 5.1 — selecciona una entidad (mob o NPC). Idempotente: seleccionar
## dos veces lo mismo no re-emite. Los muertos no se pueden seleccionar.
func seleccionar(e: Entity) -> void:
	if e == null or not e.esta_vivo():
		return
	if e == seleccion:
		return
	seleccion = e
	seleccion_cambiada.emit(e)


## Fase 5.1 — quita la selección (clic en suelo vacío, ESC). Idempotente.
func deseleccionar() -> void:
	if seleccion == null:
		return
	seleccion = null
	seleccion_cambiada.emit(null)


## Fase 5.1 — el foco de combate: la selección si es un combatible vivo;
## si no, el objetivo de ataque si sigue vivo. Los NPCs nunca son foco.
func _foco_combate() -> Entity:
	if seleccion != null and seleccion.esta_vivo() and seleccion.combatible:
		return seleccion
	if objetivo_ataque != null and objetivo_ataque.esta_vivo() and objetivo_ataque.combatible:
		return objetivo_ataque
	return null


## Distancia plana a una entidad; INF si es null.
func _dist_a(e: Entity) -> float:
	if e == null:
		return INF
	var d: Vector3 = e.global_position - global_position
	d.y = 0.0
	return d.length()


## Fase 5.1 — intención de ataque desde el botón del HUD o la tecla
## "atacar": ataca al foco (selección > objetivo actual); sin foco y SIN
## selección, engancha al combatible vivo más cercano dentro de
## RADIO_AUTOATAQUE. Si hay una selección no atacable (NPC), no hace nada:
## el fallback solo aplica cuando no hay selección.
## La UI solo emite la intención; el Player la consume aquí.
func solicitar_ataque() -> void:
	if not esta_vivo():
		return
	var foco: Entity = _foco_combate()
	if foco == null:
		if seleccion != null:
			return
		var arbol: SceneTree = get_tree()
		if arbol == null:
			return
		var cerca: Entity = SkillSystem.mas_cercano(self, arbol.get_nodes_in_group("enemigos"))
		if cerca == null or _dist_a(cerca) > RADIO_AUTOATAQUE:
			return
		seleccionar(cerca)
		foco = cerca
	objetivo_ataque = foco
	intent.objetivo = foco
	intent.quiere_atacar = true
	_tiene_destino = true
	_destino = foco.global_position
	intencion_atacar.emit(foco)


## Objetivo para un skill: las curaciones van al lanzador (null, el sistema
## las aplica sobre sí mismo); el daño usa el foco de combate (selección
## combatible > objetivo de ataque) y, si no hay foco, el combatible vivo
## más cercano. Los NPCs nunca son objetivo de daño.
func _objetivo_skill(skill_id: String) -> Entity:
	var sk: Dictionary = SkillDB.obtener(skill_id)
	var efecto: Dictionary = sk.get("efecto", {})
	if str(efecto.get("tipo", "")) == "curar":
		return null
	var foco: Entity = _foco_combate()
	if foco != null:
		return foco
	var arbol: SceneTree = get_tree()
	if arbol == null:
		return null
	return SkillSystem.mas_cercano(self, arbol.get_nodes_in_group("enemigos"))


## ¿Este collider puede ser objetivo de ataque? Solo Enemy vivo y
## combatible. Testeable sin cámara (el raycast real vive en
## _intentar_fijar_objetivo).
func _es_objetivo_atacable(col: Object) -> Enemy:
	if col is Enemy:
		var en: Enemy = col as Enemy
		if en.esta_vivo() and en.combatible:
			return en
	return null


## Doble clic: el doble clic también selecciona; solo los enemigos
## combatibles se vuelven objetivo de ataque (REGLA DURA: NPCs nunca).
## Si pega en el suelo, se comporta como una orden de mover (legado).
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
		deseleccionar()
		intencion_atacar.emit(null)
		return
	var col: Object = hit.get("collider")
	if col is Entity and (col as Entity).esta_vivo():
		seleccionar(col as Entity)
	var en: Enemy = _es_objetivo_atacable(col)
	if en != null:
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
## Fase 5.1: si el rayo pega en una entidad viva la selecciona; si pega
## en suelo vacío (o no pega en nada), deselecciona.
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
		deseleccionar()
		return
	var col: Object = hit.get("collider")
	if col is Entity and (col as Entity).esta_vivo():
		seleccionar(col as Entity)
	else:
		deseleccionar()
	var punto: Vector3 = hit["position"]
	_destino = punto
	_tiene_destino = true


func _physics_process(delta: float) -> void:
	if not esta_vivo():
		return
	if skills != null:
		skills.tick(delta)
	_cd_ataque = maxf(_cd_ataque - delta, 0.0)
	# Fase 5.1: la selección muerta se limpia sola (el indicador se oculta).
	if seleccion != null and not seleccion.esta_vivo():
		deseleccionar()
	_construir_intent()
	_actualizar_lanzamiento_pendiente()
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


## Fase 5.1 — resuelve el lanzamiento pendiente: si el objetivo murió o
## dejó de ser el foco (deselección, WASD, ESC), se cancela; si ya está en
## rango se lanza; si no, se actualiza el destino para acercarse (reusa la
## persecución de _consumir_intent). Las curaciones nunca llegan aquí.
func _actualizar_lanzamiento_pendiente() -> void:
	if _pend_skill == "":
		return
	var obj: Entity = _pend_objetivo
	var valido: bool = obj != null and obj.esta_vivo() and obj.combatible \
		and (obj == seleccion or obj == objetivo_ataque)
	if not valido:
		_pend_skill = ""
		_pend_objetivo = null
		return
	var sk: Dictionary = SkillDB.obtener(_pend_skill)
	var rango: float = float(sk.get("rango", 0.0))
	if _dist_a(obj) <= rango:
		var id: String = _pend_skill
		_pend_skill = ""
		_pend_objetivo = null
		skills.lanzar(id, self, obj)
	else:
		_destino = obj.global_position
		_tiene_destino = true


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
