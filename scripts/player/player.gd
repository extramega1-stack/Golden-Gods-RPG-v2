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
## - Clic izquierdo en enemigo: el primer clic lo selecciona; el SEGUNDO
##   clic sobre el MISMO enemigo seleccionado lo fija como objetivo de
##   ataque (modelo Flyff, fase 6.2; dos clics rápidos o lentos valen igual).
##   Lo persigue hasta el rango y pega con `Formulas.damage`.
## - Clic izquierdo en NPC: el primer clic lo selecciona; el SEGUNDO clic
##   sobre el MISMO NPC seleccionado lo hace hablar: si está lejos, el
##   jugador camina hasta él y al llegar interactúa solo (fase 9.1; sin
##   violencia: los NPCs nunca reciben daño). Si ya está cerca, el segundo
##   clic abre el diálogo directo (igual que E).
##   Sin animaciones todavía: solo el número.
## Sin referencias a UI ni a ningún otro sistema.

signal intencion_atacar(objetivo: Entity)
signal oro_cambiado(oro: int)
## Fase 5.1: cambió la entidad seleccionada (clic simple). null = deselección.
## La escuchan el indicador 3D y la UI futura; la emite solo Player.
signal seleccion_cambiada(entidad: Entity)
## Fase 6: el jugador quiere hablar con este NPC (acción `interactuar`).
## La emite solo Player; la demo abre la VentanaDialogo (la UI no toca
## al Player ni a sus stats).
signal hablar_con(npc: NPC)
## Fase 11: cambió la identidad del héroe (nombre y/o clase visible en la
## UI). La emiten `fijar_identidad` y la carga del save; la escuchan el
## retrato del HUD y la UI futura (solo lectura).
signal identidad_cambiada

## --- Game feel: todos los tunables en un solo sitio ---
const ACEL_TASA: float = 9.0      ## Qué tan rápido arranca (mayor = más inmediato).
const FRENADO_TASA: float = 11.0  ## Qué tan rápido frena (mayor = más seco).
const RADIO_LLEGADA: float = 0.35 ## Distancia al destino donde se detiene.
const RADIO_FRENADO: float = 2.5  ## Distancia donde empieza a desacelerar.
const VEL_GIRO: float = 12.0      ## Qué tan rápido rota el cuerpo al moverse.
const GRAVEDAD: float = 24.0      ## Gravedad propia (mundo sin físicas raras).
const ALCANCE_RAYO: float = 1000.0 ## Alcance del raycast clic→mundo.
const RANGO_ATAQUE: float = 2.6   ## Distancia cuerpo a cuerpo del héroe.
## Fase 18.4 (guardado para la futura versión móvil, pedido de Juan Diego):
## con `autoataque_movil` en true, atacar y los skills hostiles sin
## selección vuelven al comportamiento de la fase 5.1 (enganchan al mob
## más cercano). En PC queda en false: sin selección no se hace nada.
## Es `static var` (no const) para que los tests verifiquen el camino
## guardado y no se pudra con el tiempo.
static var autoataque_movil: bool = false
## Radio del enganche guardado para móvil (fase 5.1; inactivo en PC).
const RADIO_AUTOATAQUE: float = 8.0
## Fase 9.1: radio de interacción con NPCs. El segundo clic en un NPC
## seleccionado que esté más lejos camina hasta él y al llegar habla solo;
## si ya está dentro de este radio, el segundo clic abre el diálogo directo.
const RADIO_INTERACCION: float = 3.0

## Fase 6.2 (modelo Flyff, pedido de Juan Diego): el clic izquierdo es UN
## solo gesto y la intención depende de lo clicado y del estado:
## - Primer clic en una entidad no seleccionada → SELECCIONAR (sin atacar).
## - Segundo clic en la MISMA selección y es enemigo combatible vivo →
##   ATACAR (dos clics rápidos o lentos valen igual).
## - Segundo clic en la misma selección y es NPC vivo → INTERACTUAR (fase
##   9.1): cerca habla directo, lejos camina hasta él y habla al llegar.
## - Segundo clic en la misma selección no atacable y no NPC → NADA.
## - Clic en otra entidad distinta → SELECCIONAR (ni ataca ni mueve).
## - Clic en suelo / nada → orden de mover (+ deselecciona).
enum AccionClic { SELECCIONAR, ATACAR, NADA, INTERACTUAR }

## Ruta al CameraRig en la escena (se asigna en el .tscn; sin esto el WASD
## usa yaw 0 y el clic no tiene cámara para proyectar).
@export var ruta_rig: NodePath

## La intención del frame actual (la UI futura y los tests pueden leerla).
var intent: Intent
## Objetivo de ataque (segundo clic en la selección / tecla "atacar").
## null = sin objetivo.
var objetivo_ataque: Entity = null
## Fase 5.1 — entidad seleccionada (clic en mob o NPC). Fase 6.2: el
## segundo clic sobre el mismo mob seleccionado ataca (modelo Flyff).
## Los NPCs SÍ se pueden seleccionar, pero NUNCA son objetivo de ataque.
## Clic en suelo vacío o ESC deselecciona.
var seleccion: Entity = null
## Oro del héroe.
var oro: int = 0
## Fase 11 — identidad del héroe: nombre visible + clase (id de ClaseDB).
## La UI solo la LEE (señal `identidad_cambiada`); la escriben
## `fijar_identidad` (creación de personaje) y la carga del save.
var nombre: String = "Héroe"
var clase_id: String = "guerrero"
## Sistemas de la fase 5 (se crean en _ready; nunca son null en juego).
var inventario: Inventario = null
var equipo: Equipo = null
var skills: SkillSystem = null
## Fase 28 — talentos del héroe (1 punto por nivel; la UI los gasta).
var talentos: Talentos = null

var _rig: CameraRig = null
var _tiene_destino: bool = false
var _destino: Vector3 = Vector3.ZERO
var _cd_ataque: float = 0.0
## Fase 5.1 — lanzamiento pendiente: skill dañina cuyo objetivo estaba fuera
## de rango. El jugador se acerca y la lanza al llegar; se cancela si el
## objetivo muere o deja de ser el foco (muerte/deselección/WASD).
var _pend_skill: String = ""
var _pend_objetivo: Entity = null
## Fase 9.1 — interacción pendiente: segundo clic en un NPC seleccionado
## que estaba lejos. El jugador camina hasta él y al llegar habla solo
## (reusa el patrón de "acercarse y actuar al llegar" del lanzamiento
## pendiente). Se cancela si el NPC muere, se deselecciona o el jugador
## toma el control manual (WASD) u ordena otro movimiento.
var _pend_npc: NPC = null


func _ready() -> void:
	intent = Intent.new()
	# Fase 11: los stats de demo (45/10 → ataque 100, como antes) ahora
	# vienen de DATOS (ClaseDB, clase "guerrero"): mismo resultado numérico,
	# única vía de datos. Solo si el bloque viene por defecto (sin stats
	# explícitos): no pisa los stats que alguien pasó al constructor
	# (tests, save/load).
	if stats.fuerza == 0.0 and stats.agilidad == 0.0 \
			and stats.destreza == 0.0 and stats.inteligencia == 0.0:
		aplicar_clase("guerrero")
	if ruta_rig != NodePath(""):
		_rig = get_node_or_null(ruta_rig) as CameraRig
	# Sistemas de la fase 5 (después de lo existente: no dependen del rig).
	inventario = Inventario.new()
	equipo = Equipo.new()
	skills = SkillSystem.new()
	# Fase 28: talentos (1 punto por nivel subido).
	talentos = Talentos.new()
	if not subio_nivel.is_connected(_al_subir_nivel_talentos):
		subio_nivel.connect(_al_subir_nivel_talentos)


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
	elif event.is_action_pressed("interactuar"):
		# Fase 6: tecla E (Input Map, acción "interactuar").
		interactuar()
	elif event.is_action_pressed("cancelar_seleccion"):
		# Fase 5.1: ESC deselecciona (el lanzamiento pendiente se cancela
		# solo en el siguiente frame, porque su objetivo deja de ser el foco).
		deseleccionar()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			# Fase 6.2: un solo handler de clic izquierdo (modelo Flyff).
			# El flag double_click del motor ya no decide nada: dos clics
			# rápidos siguen funcionando por construcción (el primero
			# selecciona, el segundo ataca).
			_clic_izquierdo(mb.position)


## Habilidades 1-5: lanza el skill i-ésimo del hotbar de la CLASE del
## jugador (fase 18: `skills_por_clase(clase_id)`, no todos los skills).
## Fase 5.1: si es dañina y el objetivo está fuera de rango, NO se lanza
## todavía: queda "pendiente" y el jugador se acerca hasta el rango para
## lanzarla (se cancela si el objetivo muere o se deselecciona). Las
## curaciones y los buffs se aplican al lanzador sin moverse. Pública para
## tests.
## Fase 10: un skill dañino sobre un objetivo válido fija el objetivo de
## ataque (auto-ataque persistente): tras el casteo el héroe sigue
## golpeando solo hasta que el mob muera, salga del rango (lo persigue y
## retoma) o llegue otra orden.
func lanzar_skill(i: int) -> void:
	if skills == null:
		return
	var ids: Array[String] = skills_clase()
	if i < 0 or i >= ids.size():
		return
	lanzar_skill_id(ids[i])


## Skills de la clase del jugador, en orden del JSON (los que salen en el
## hotbar y en el libro de habilidades). Clase desconocida → lista vacía.
func skills_clase() -> Array[String]:
	return SkillDB.skills_por_clase(clase_id)


## Fase 17 — lanza un skill por id (lo usa la barra de acciones). Mismo
## cuerpo que lanzar_skill(i); el índice solo resuelve el id.
## Fase 18 — "hostil" = dano, debuff, o aoe dirigido (rango > 0): sobre un
## objetivo válido fija el objetivo de ataque (auto-ataque persistente de
## la fase 10) y, si está fuera de rango, queda pendiente y el jugador se
## acerca. Curar, buff y aoe centrado en el lanzador nunca tocan el
## combate en curso. Fase 18.4: un skill hostil sin objetivo (sin selección)
## no hace nada — no engancha al mob más cercano.
func lanzar_skill_id(id: String) -> void:
	if skills == null:
		return
	if not SkillDB.existe(id):
		return
	var sk: Dictionary = SkillDB.obtener(id)
	var obj: Entity = _objetivo_skill(id)
	if _es_hostil(sk):
		if obj == null or not obj.esta_vivo():
			# Fase 18.4 — skill hostil sin objetivo (sin selección): no
			# hace nada en vez de enganchar al mob más cercano.
			return
		# Fase 10 — auto-ataque persistente (pedido de Juan Diego: "cuando
		# llega le pega, el personaje le sigue atacando al mob"). Entrar en
		# combate con un skill fija el objetivo de ataque; el bucle de
		# `_actualizar_ataque` + la persecución ya existentes hacen el resto
		# con la cadencia y el daño intactos. El bucle lo detienen: la muerte
		# del objetivo (fase 9.3: deselección + sin caminar al cadáver), otra
		# orden (mover, WASD, deselección/ESC), otro objetivo u otro skill
		# dañino sobre otro objetivo. Vale aunque el casteo falle (sin maná
		# o en cooldown): el jugador quería pelear con ese mob. Las
		# curaciones (obj null) no tocan el combate en curso.
		# `_objetivo_skill` ya excluye NPCs y muertos (REGLA DURA intacta).
		# Fase 18: "skill dañino" aquí = hostil (dano, debuff, aoe dirigido).
		objetivo_ataque = obj
		intent.objetivo = obj
		intent.quiere_atacar = true
		intencion_atacar.emit(obj)
		var rango: float = float(sk.get("rango", 0.0))
		if _dist_a(obj) > rango:
			_pend_skill = id
			_pend_objetivo = obj
			_tiene_destino = true
			_destino = obj.global_position
			return
	skills.lanzar(id, self, obj)


## ¿Hay un lanzamiento pendiente de resolverse? (tests + UI futura).
func tiene_lanzamiento_pendiente() -> bool:
	return _pend_skill != "" and _pend_objetivo != null


## ¿Hay una interacción pendiente de resolverse? (tests + UI futura).
func tiene_interaccion_pendiente() -> bool:
	return _pend_npc != null


## Fase 6 — interacción contextual (tecla E): con un NPC vivo
## seleccionado se quiere hablar. Fase 9.2: E respeta el radio de
## interacción. Si el NPC está LEJOS, NO abre el diálogo de inmediato:
## activa la MISMA interacción pendiente que el segundo clic lejano
## (`_acercarse_a_npc`): el jugador camina hasta él y al llegar habla
## solo. Si está dentro del radio, abre el diálogo directo como antes.
## Nunca fija objetivo de ataque ni emite `intencion_atacar`.
## Sin selección útil (nada, un enemigo, o un NPC muerto) no hace nada y
## no falla: los enemigos no abren diálogo. Pública para tests y la UI.
func interactuar() -> void:
	if not esta_vivo():
		return
	var npc: NPC = seleccion as NPC
	if npc == null or not npc.esta_vivo():
		return
	_acercarse_a_npc(npc)


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
## Fase 9.1: también cancela la interacción pendiente (caminar a un NPC).
## Fase 10: también suelta el objetivo de ataque y la orden de movimiento.
## Deseleccionar es soltar el foco de combate por completo: ESC detiene el
## auto-ataque y la marcha (como en los MMO), nadie camina al cadáver
## (fase 9.3) y la cancelación del lanzamiento pendiente por deselección
## vale siempre (foco = selección u objetivo de ataque, ambos null aquí).
func deseleccionar() -> void:
	objetivo_ataque = null
	_tiene_destino = false
	intent.tiene_destino = false
	if seleccion == null:
		_pend_npc = null
		return
	seleccion = null
	_pend_npc = null
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


## Fase 5.1 — intención de ataque desde la tecla "atacar" (T) o el slot de
## ataque de la barra de acciones (fase 17): ataca al foco (selección
## combatible > objetivo de ataque actual).
## Fase 18.4 — sin foco NO hace nada: se eliminó el auto-ataque al mob más
## cercano (pedido de Juan Diego: sin seleccionar, apretar atacar no
## engancha a ningún mob). El comportamiento viejo quedó guardado tras el
## flag `autoataque_movil` para la futura versión móvil. Si hay una
## selección no atacable (NPC), no hace nada.
## La UI solo emite la intención; el Player la consume aquí.
func solicitar_ataque() -> void:
	if not esta_vivo():
		return
	var foco: Entity = _foco_combate()
	# Fase 9.3 — blindaje explícito: un muerto nunca es objetivo válido
	# (ni fija objetivo ni ordena caminar hacia él).
	if foco != null and not foco.esta_vivo():
		foco = null
	if foco == null and autoataque_movil:
		# Camino guardado para la futura versión móvil (fase 5.1).
		foco = _mob_cercano_movil()
	if foco == null:
		# Fase 18.4 — sin foco (y sin el modo móvil) no se hace nada:
		# nada se selecciona ni se ataca.
		return
	objetivo_ataque = foco
	intent.objetivo = foco
	intent.quiere_atacar = true
	_tiene_destino = true
	_destino = foco.global_position
	intencion_atacar.emit(foco)


## Fase 18.4 — enganche al mob más cercano, guardado para la futura
## versión móvil (comportamiento de la fase 5.1). Solo se usa si
## `autoataque_movil` está en true.
func _mob_cercano_movil() -> Entity:
	var arbol: SceneTree = get_tree()
	if arbol == null:
		return null
	var cerca: Entity = SkillSystem.mas_cercano(self, arbol.get_nodes_in_group("enemigos"))
	if cerca == null or _dist_a(cerca) > RADIO_AUTOATAQUE:
		return null
	seleccionar(cerca)
	return cerca


## Objetivo para un skill: las curaciones y los buffs van al lanzador
## (null, el sistema los aplica sobre sí mismo); el daño, los debuffs y el
## aoe dirigido (rango > 0) usan el foco de combate (selección combatible >
## objetivo de ataque); el aoe centrado en el lanzador (rango == 0) no
## necesita objetivo. Fase 18.4: sin foco, los skills hostiles devuelven
## null y no hacen nada — salvo con `autoataque_movil` en true, que
## restaura el camino guardado para móvil (mob más cercano, fase 5.1).
## Los NPCs nunca son objetivo de daño.
func _objetivo_skill(skill_id: String) -> Entity:
	var sk: Dictionary = SkillDB.obtener(skill_id)
	var efecto: Dictionary = sk.get("efecto", {})
	var tipo: String = str(efecto.get("tipo", ""))
	if tipo == "curar" or tipo == "buff":
		return null
	if tipo == "aoe" and float(sk.get("rango", 0.0)) <= 0.0:
		return null
	var foco: Entity = _foco_combate()
	if foco != null:
		return foco
	if autoataque_movil:
		var arbol: SceneTree = get_tree()
		if arbol == null:
			return null
		return SkillSystem.mas_cercano(self, arbol.get_nodes_in_group("enemigos"))
	return null


## Fase 18 — ¿este skill es "hostil" (entra en combate / puede quedar
## pendiente de acercamiento)? dano, debuff y aoe dirigido (rango > 0).
static func _es_hostil(sk: Dictionary) -> bool:
	var efecto: Dictionary = sk.get("efecto", {})
	var tipo: String = str(efecto.get("tipo", ""))
	if tipo == "dano" or tipo == "debuff":
		return true
	if tipo == "aoe" and float(sk.get("rango", 0.0)) > 0.0:
		return true
	return false


## ¿Este collider puede ser objetivo de ataque? Solo Enemy vivo y
## combatible. Testeable sin cámara (lo usan `_resolver_clic_entidad`
## y `solicitar_ataque`).
func _es_objetivo_atacable(col: Object) -> Enemy:
	if col is Enemy:
		var en: Enemy = col as Enemy
		if en.esta_vivo() and en.combatible:
			return en
	return null


## Fase 6.2 — raycast clic→mundo (capa de suelo + entidades). Sin cámara
## (tests headless) no hay rayo: devuelve {}.
func _rayo_clic(pantalla: Vector2) -> Dictionary:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var origen: Vector3 = cam.project_ray_origin(pantalla)
	var dir: Vector3 = cam.project_ray_normal(pantalla)
	var consulta: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origen, origen + dir * ALCANCE_RAYO
	)
	var excluir: Array[RID] = [get_rid()]
	consulta.exclude = excluir
	return get_world_3d().direct_space_state.intersect_ray(consulta)


## Fase 6.2 — UN solo handler de clic izquierdo (modelo Flyff): el rayo
## decide la rama. Entidad viva → `_resolver_clic_entidad` decide y
## `_aplicar_clic` ejecuta. Suelo → orden de mover. Nada → deseleccionar
## sin moverse (una orden de mover cancela el objetivo de ataque).
func _clic_izquierdo(pantalla: Vector2) -> void:
	var hit: Dictionary = _rayo_clic(pantalla)
	if hit.is_empty():
		_clic_en_vacio()
		return
	var col: Object = hit.get("collider")
	if col is Entity:
		var ent: Entity = col as Entity
		if ent.esta_vivo():
			_aplicar_clic(ent, _resolver_clic_entidad(ent))
			return
		# Fase 9.3: un cadáver no es objetivo ni es suelo: deselecciona sin
		# ordenar moverse (pedido de Juan Diego: no caminar a los muertos).
		_clic_en_vacio()
		return
	_orden_mover_punto(hit["position"])


## Fase 9.3 — clic que no ordena nada: quita el objetivo de ataque y
## deselecciona, sin fijar destino (clic en el vacío o sobre un cadáver).
func _clic_en_vacio() -> void:
	objetivo_ataque = null
	deseleccionar()


## Fase 6.2 — decisión "entidad clicada → acción", PURA y testeable sin
## cámara (el raycast vive en `_clic_izquierdo`). NO aplica nada: devuelve
## AccionClic.SELECCIONAR / .ATACAR / .NADA.
func _resolver_clic_entidad(e: Entity) -> int:
	if e == null or not e.esta_vivo():
		return AccionClic.NADA
	if e == seleccion:
		# Segundo clic en la misma selección: ataca solo si es un enemigo
		# combatible vivo (REGLA DURA: los NPCs nunca son objetivo de
		# ataque). Fase 9.1: el segundo clic en un NPC vivo seleccionado
		# INTERACTÚA (cerca habla directo; lejos camina hasta él).
		if _es_objetivo_atacable(e) != null:
			return AccionClic.ATACAR
		var n: NPC = e as NPC
		if n != null and n.esta_vivo():
			return AccionClic.INTERACTUAR
		return AccionClic.NADA
	# Otra entidad distinta: solo seleccionar (ni atacar ni mover).
	return AccionClic.SELECCIONAR


## Fase 6.2 — ejecuta la decisión de `_resolver_clic_entidad` sobre la
## entidad clicada. Pública para tests (los tests headless no tienen
## viewport para raycast).
func _aplicar_clic(e: Entity, accion: int) -> void:
	match accion:
		AccionClic.SELECCIONAR:
			seleccionar(e)
		AccionClic.ATACAR:
			# Intención de ataque completa: objetivo, intent, orden de
			# acercarse y señal. La persecución y el golpe siguen en
			# _physics_process (igual que el doble clic anterior).
			objetivo_ataque = e
			intent.objetivo = e
			intent.quiere_atacar = true
			_tiene_destino = true
			_destino = e.global_position
			intencion_atacar.emit(e)
		AccionClic.INTERACTUAR:
			# Fase 9.1: segundo clic en el NPC seleccionado. Sin violencia:
			# no fija objetivo de ataque ni emite intencion_atacar.
			_acercarse_a_npc(e as NPC)
		_:
			pass


## Fase 6.2 — orden de mover a un punto ya resuelto del suelo: cancela el
## objetivo de ataque, deselecciona y fija el destino. Testeable sin cámara
## (`_clic_izquierdo` la usa para la rama de suelo).
func _orden_mover_punto(punto: Vector3) -> void:
	objetivo_ataque = null
	deseleccionar()
	_destino = punto
	_tiene_destino = true


## Orden pública de moverse a un punto (la usa el minimapa de la fase 13).
func ordenar_mover_a(punto: Vector3) -> void:
	_orden_mover_punto(punto)


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
	_actualizar_interaccion_pendiente()
	_consumir_intent(delta)
	_actualizar_ataque(delta)
	# Fase 12: el héroe camina pegado al terreno del mundo abierto.
	_pegar_al_terreno()


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
		_pend_npc = null
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
		# Fase 9.3: el objetivo murió o dejó de ser el foco: se cancela el
		# pendiente Y la orden de acercarse (si no, el jugador camina al
		# cadáver: pedido de Juan Diego). Si hay un objetivo de ataque vivo,
		# la persecución retoma la marcha más abajo en este mismo frame.
		_pend_skill = ""
		_pend_objetivo = null
		_tiene_destino = false
		intent.tiene_destino = false
		return
	var sk: Dictionary = SkillDB.obtener(_pend_skill)
	var rango: float = float(sk.get("rango", 0.0))
	if _dist_a(obj) <= rango:
		var id: String = _pend_skill
		_pend_skill = ""
		_pend_objetivo = null
		skills.lanzar(id, self, obj)
		# Fase 9.3: si el casteo lo mató, la orden de acercarse muere con él
		# (no caminar al cadáver). Si sobrevivió, el combate no cambia.
		if not obj.esta_vivo():
			_tiene_destino = false
			intent.tiene_destino = false
	else:
		_destino = obj.global_position
		_tiene_destino = true


## Fase 9.1 — resuelve la interacción pendiente: si el NPC murió o dejó
## de ser la selección (deselección, WASD, ESC, clic en suelo), se cancela;
## si ya está dentro del radio de interacción, habla; si no, actualiza el
## destino para seguir acercándose (mismo patrón que el lanzamiento
## pendiente). Los NPCs nunca reciben daño: esto solo mueve y habla.
func _actualizar_interaccion_pendiente() -> void:
	if _pend_npc == null:
		return
	var n: NPC = _pend_npc
	if not n.esta_vivo() or n != seleccion:
		_pend_npc = null
		return
	if _dist_a(n) <= RADIO_INTERACCION:
		_pend_npc = null
		_tiene_destino = false
		interactuar()
	else:
		_destino = n.global_position
		_tiene_destino = true


## Fase 9.1 — segundo clic en un NPC ya seleccionado (y la tecla E
## desde la fase 9.2): si está dentro del radio de interacción habla
## directo (emite `hablar_con`); si está lejos queda una interacción
## pendiente y el jugador camina hasta él. Pública para tests (los tests
## headless no tienen viewport para raycast).
func _acercarse_a_npc(n: NPC) -> void:
	if n == null or not n.esta_vivo():
		return
	if _dist_a(n) <= RADIO_INTERACCION:
		# Fase 9.2: se emite directo (interactuar() ya delega aquí; llamar
		# de vuelta a interactuar() sería recursión mutua).
		hablar_con.emit(n)
		return
	_pend_npc = n
	_tiene_destino = true
	_destino = n.global_position


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
	objetivo_ataque.take_damage(float(res["final"]), self, bool(res["crit"]))
	_cd_ataque = 1.0 / maxf(stats.vel_ataque, 0.1)


## Suma oro (lo emite para el HUD). Nunca deja el oro bajo 0.
func ganar_oro(cantidad: int) -> void:
	oro = maxi(0, oro + cantidad)
	oro_cambiado.emit(oro)


## Fase 28: cada nivel da 1 punto de talento (propio, no de Entity).
func _al_subir_nivel_talentos(_nivel: int) -> void:
	if talentos == null:
		talentos = Talentos.new()
	talentos.puntos += 1


## Fase 11 — identidad del héroe (nombre + clase visible en la UI).
## Asigna y emite `identidad_cambiada` para que el retrato y la UI futura
## se actualicen (solo lectura). No toca stats.
func fijar_identidad(p_nombre: String, p_clase_id: String) -> void:
	nombre = p_nombre
	clase_id = p_clase_id
	# Fase 28: al cambiar de clase se purgan los talentos ajenos.
	if talentos != null:
		talentos.purgar_clase(stats, clase_id)
	identidad_cambiada.emit()


## Fase 11 — aplica los atributos base de una clase desde datos (ClaseDB):
## pone los 4 atributos, recalcula derivados y llena vida/maná.
## Idempotente y tolerante: un id desconocido no toca nada ni revienta.
## NO emite `identidad_cambiada` (son stats, no identidad).
func aplicar_clase(id: String) -> void:
	if not ClaseDB.existe(id):
		return
	var base: Dictionary = ClaseDB.stats_base(id)
	stats.fuerza = float(base.get("fuerza", 0.0))
	stats.agilidad = float(base.get("agilidad", 0.0))
	stats.destreza = float(base.get("destreza", 0.0))
	stats.inteligencia = float(base.get("inteligencia", 0.0))
	stats.recalc()
	vida_actual = stats.vida_max
	mana_actual = stats.mana_max


## Descuenta oro (lo usa la tienda, fase 7). Retorna false SIN TOCAR NADA
## si no alcanza (o si la cantidad es negativa); true descuenta y emite
## `oro_cambiado`. Es la única vía para restar oro; `ganar_oro` no cambia.
func gastar_oro(cantidad: int) -> bool:
	if cantidad < 0:
		return false
	if oro < cantidad:
		return false
	oro -= cantidad
	oro_cambiado.emit(oro)
	return true
