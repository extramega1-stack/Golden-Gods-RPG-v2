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
## - Clic izquierdo en veta (fase 45): el primer clic la selecciona; el
##   SEGUNDO clic (o la tecla E) la mina: si está lejos camina hasta ella y
##   mina al llegar. Igual que el NPC, sin violencia (no es combatible).
## Sin referencias a UI ni a ningún otro sistema.

## Fase 58: un vital bajó del umbral. La UI lo escucha para avisar.
signal vital_bajo(cual: String)

signal intencion_atacar(objetivo: Entity)
signal oro_cambiado(oro: int)
## Fase 5.1: cambió la entidad seleccionada (clic simple). null = deselección.
## La escuchan el indicador 3D y la UI futura; la emite solo Player.
signal seleccion_cambiada(entidad: Entity)
## Fase 6: el jugador quiere hablar con este NPC (acción `interactuar`).
## La emite solo Player; la demo abre la VentanaDialogo (la UI no toca
## al Player ni a sus stats).
signal hablar_con(npc: NPC)
## Fase 45: el jugador quiere minar esta veta (tecla E con la veta
## seleccionada, o segundo clic sobre ella). La emite solo Player; la
## escucha `GestorVetas`, que coloca las vetas y tiene la `Mineria`.
signal minar_solicitado(veta: Veta)

## Fase 64: hay algo que interactuar cerca (fogata, refugio) y este es el
## texto del prompt ("Prender fogata", "Reclamar refugio"). Se emite con ""
## cuando ya no hay nada, que es lo que hace aparecer y ocultar el prompt.
##
## Es una señal y no una consulta: el prompt tiene que aparecer AL LLEGAR, no
## cuando el jugador abra un panel.
signal interactuable_cerca(texto: String, nodo: Node)
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
## Fase 64: alcance de la mano. Más generoso que `RADIO_INTERACCION` (3.0, que
## es para que el heroe `se acerque` a un NPC) porque una fogata es grande y
## hay que poder llegar a ella sin pisarla.
const RADIO_MUNDO: float = 4.5
## Grupo de los nodos con los que se puede interactuar por proximidad.
const GRUPO_INTERACTUABLE: StringName = &"interactuable"

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
## - Fase 45: segundo clic en la MISMA veta → MINAR (una veta nunca es
##   objetivo de ataque: no es combatible, como los NPCs).
enum AccionClic { SELECCIONAR, ATACAR, NADA, INTERACTUAR, MINAR }

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
## Fase 57: XP por habilidad. Es un SEGUNDO eje, paralelo al nivel de
## personaje: este sigue mandando en StatBlock, combate y equipo. El XP de
## acá abre los Talentos de Habilidad de la fase 59.
var habilidades: Habilidades = null
## Bloque 66: pisadas (acumulado de distancia + caché del material del suelo).
var _paso_acumulado: float = 0.0
var _piso_cache: String = ""
var _piso_cache_frame: int = -1
## La DB de regiones, para saber bajo qué material pisas. La asigna la demo.
var _region_db: RegionDB = null
## Fase 59: Talentos de Habilidad. Se desbloquean con el XP de habilidad (la
## 57) y transforman la recolección. Los de tipo `mod` se aplican al
## StatBlock; los de tipo `bandera` los leen tala, veta, cocina y vitals.
var hechos: Hechos = null
## Fase 30 — puntos de atributo estilo FlyFF (2 por nivel; se reparten en
## STR/fuerza, STA/aguante, DEX/destreza e INT/inteligencia).
var puntos_atributo: int = 0
## Atributos repartibles (fuente única; fase 34: STR/STA/DEX/INT, sin agilidad).
## Fase 51: el ataque básico no tiene datos propios más allá del power 1.0.
## En una const para no construir un Dictionary en cada golpe.
const SKILL_ATAQUE_BASICO: Dictionary = {"power": 1.0}

const ATRIBUTOS_REPARTIBLES: Array[String] = ["fuerza", "aguante", "destreza", "inteligencia"]
## Etiquetas FlyFF para la UI.
const ETIQUETA_ATRIBUTO: Dictionary = {"fuerza": "STR", "aguante": "STA",
	"destreza": "DEX", "inteligencia": "INT"}

var _rig: CameraRig = null
var _tiene_destino: bool = false
var _destino: Vector3 = Vector3.ZERO
var _cd_ataque: float = 0.0
## Fase 51: punto seguro. Es la última plaza de ciudad visitada; es donde
## reaparece el héroe al morir. NO sale de `data/viaje_rapido.json`: esas
## plazas traen `y = 45.0` constante y la altura real del terreno llega a
## 220 u (ver `RespawnHeros`), así que respawnear ahí te tiraba al suelo
## desde el aire. `RespawnHeros` lo llena con `CiudadLuna.punto_aparicion_jugador()`.
var _ancla_posicion: Vector3 = Vector3.ZERO
var _ancla_yaw: float = 0.0
## Fase 50: modelo 3D de la clase y estado de animación. El reproductor solo
## existe si el `.glb` viene riggeado; con un modelo estático se dibuja igual
## pero quieto.
var _modelo: Node3D = null
var _anim: AnimationPlayer = null
var _clip_actual: String = ""
## Segundos que queda de "tajo" tras pegar. Es lo que mantiene el clip `attack`
## el tiempo justo y no solo el frame en que se golpea.
var _t_swing: float = 0.0

const CLIP_CAMINAR: StringName = &"walk"
const CLIP_ATAQUE: StringName = &"attack"
const CLIP_MUERTE: StringName = &"die"
## Por debajo de esta velocidad horizontal el jugador se considera quieto: con
## el umbral en 0 el idle y el walk parpadean al soltar el WASD.
const UMBRAL_CAMINAR: float = 0.45
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
## Fase 45: minado pendiente — segundo clic (o E) en una veta que estaba
## lejos. Mismo patrón que `_pend_npc`: el jugador camina hasta ella y al
## llegar emite `minar_solicitado`. Se cancela igual (WASD, ESC, clic en
## suelo, muerte o veta agotada).
var _pend_veta: Veta = null


func _ready() -> void:
	intent = Intent.new()
	# Fase 11: los stats de demo (45/10 → ataque 100, como antes) ahora
	# vienen de DATOS (ClaseDB, clase "guerrero"): mismo resultado numérico,
	# única vía de datos. Solo si el bloque viene por defecto (sin stats
	# explícitos): no pisa los stats que alguien pasó al constructor
	# (tests, save/load).
	if stats.fuerza == 0.0 and stats.aguante == 0.0 \
			and stats.destreza == 0.0 and stats.inteligencia == 0.0:
		aplicar_clase("guerrero")
	if ruta_rig != NodePath(""):
		_rig = get_node_or_null(ruta_rig) as CameraRig
	# Sistemas de la fase 5 (después de lo existente: no dependen del rig).
	inventario = Inventario.new()
	equipo = Equipo.new()
	# Fase 57: se crea antes que la demo para que tala/minería/cocina ya
	# tengan dónde sumar XP.
	habilidades = Habilidades.crear_desde_datos()
	hechos = Hechos.crear_desde_datos()
	hechos.fijar_habilidades(habilidades)
	# Fase 59: cuando una habilidad cruza un tramo, los hechos se recalculan.
	# Así el "talar en área" aparece solo, sin que nadie lo abra a mano.
	if not habilidades.tramo_ganado.is_connected(_al_subir_tramo):
		habilidades.tramo_ganado.connect(_al_subir_tramo)
	hechos.aplicar(stats)
	skills = SkillSystem.new()
	# Fase 31: las skills de la clase empiezan en nivel 1.
	skills.configurar_clase(clase_id)
	# Fase 28: talentos (1 punto por nivel subido).
	talentos = Talentos.new()
	if not subio_nivel.is_connected(_al_subir_nivel_talentos):
		subio_nivel.connect(_al_subir_nivel_talentos)
	# Fase 36: muñeco 3D del equipo (visual; se auto-suscribe y se
	# re-suscribe solo si el save reemplaza el objeto Equipo).
	var muneco := PaperDoll.new()
	muneco.name = "PaperDoll"
	add_child(muneco)
	muneco.conectar(self)


func _unhandled_input(event: InputEvent) -> void:
	# Fase 37: las teclas de skills las atiende la BarraAcciones (vía
	# única: ejecuta el SLOT VISIBLE, con el offset de ataque incluido).
	# lanzar_skill(i) queda como API (tests y otros sistemas).
	if event.is_action_pressed("atacar"):
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


## Fase 45: ¿hay un minado pendiente de resolverse? (tests).
func tiene_minado_pendiente() -> bool:
	return _pend_veta != null


## Fase 6 — interacción contextual (tecla E): con un NPC vivo
## seleccionado se quiere hablar. Fase 9.2: E respeta el radio de
## interacción. Si el NPC está LEJOS, NO abre el diálogo de inmediato:
## activa la MISMA interacción pendiente que el segundo clic lejano
## (`_acercarse_a_npc`): el jugador camina hasta él y al llegar habla
## solo. Si está dentro del radio, abre el diálogo directo como antes.
## Nunca fija objetivo de ataque ni emite `intencion_atacar`.
## Sin selección útil (nada, un enemigo, o un NPC muerto) no hace nada y
## no falla: los enemigos no abren diálogo. Pública para tests y la UI.
## Fase 45: si lo seleccionado es una VETA, E mina en vez de hablar (mismo
## idioma de interacción, sin abrir ningún diálogo).
func interactuar() -> void:
	if not esta_vivo():
		return
	var veta: Veta = seleccion as Veta
	if veta != null:
		_acercarse_a_veta(veta)
		return
	var npc: NPC = seleccion as NPC
	if npc != null and npc.esta_vivo():
		_acercarse_a_npc(npc)
		return
	# Fase 64: fogata o refugio. SIN selección, por proximidad: son Node3D y no
	# `Entity`, así que no entran en `seleccion` (que es de combate y NPC).
	# Making them Entities just to reuse the selection path would give a
	# campfire hit points and aggro, que es un modelo equivocado.
	var n: Node = _interactuable_mas_cercano()
	if n != null:
		_interactuar_con(n)


## Fase 64: reloj del prompt. Un cuarto de segundo es suficiente para que el
## rótulo se vea estable, y es lo que cuesta un `get_nodes_in_group`.
const INTERVALO_INTERACTUABLE: float = 0.25
var _reloj_interactuable: float = 0.0
## Lo último que se le dijo al prompt, para no emitir la señal igual.
var _interactuable_ultimo: String = ""


## Fase 64: emite `interactuable_cerca` solo cuando el objetivo cambia. Si
## emitiera cada medio segundo con el mismo texto, el prompt se redibujaría
## sin motivo, que es exactamente lo que §9.5 prohíbe.
func _tick_interactuable(delta: float) -> void:
	_reloj_interactuable -= delta
	if _reloj_interactuable > 0.0:
		return
	_reloj_interactuable = INTERVALO_INTERACTUABLE
	var n: Node = _interactuable_mas_cercano()
	var texto: String = texto_interactuable(n) if n != null else ""
	if texto == _interactuable_ultimo and n != null:
		return
	if texto == "" and _interactuable_ultimo == "":
		return
	_interactuable_ultimo = texto
	interactuable_cerca.emit(texto, n)


## Lo que hay al alcance de la mano, o null. NUNCA pone la `y` a cero en la
## comparación: una fogata con el player un metro más abajo tiene que seguir
## siendo alcanzable, y comparar en 3D daba falso negativo.
func _interactuable_mas_cercano() -> Node:
	var mejor: Node = null
	var mejor_d: float = RADIO_MUNDO
	for n in get_tree().get_nodes_in_group(GRUPO_INTERACTUABLE):
		var nd: Node3D = n as Node3D
		if nd == null or not is_instance_valid(nd):
			continue
		var d: float = nd.global_position.distance_to(global_position)
		if d <= mejor_d:
			mejor_d = d
			mejor = nd
	return mejor


## El texto del prompt para lo que hay al alcance ("" si no hay nada). Lo lee
## el nodo por su propia API, para que añadir un interactuable nuevo no
## obligue a tocar este archivo.
func texto_interactuable(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return ""
	var p: Callable = n.get("texto_interaccion")
	if not p.is_valid():
		return ""
	return str(p.call(self))


func _interactuar_con(n: Node) -> void:
	var p: Callable = n.get("interactuar_jugador")
	if p.is_valid():
		p.call(self)


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
		_pend_veta = null
		return
	seleccion = null
	_pend_npc = null
	_pend_veta = null
	seleccion_cambiada.emit(null)


## Fase 51: fija el punto seguro (la plaza de ciudad más reciente). La
## llama `RespawnHeros`; el juego no la llama por su cuenta porque no sabe
## dónde están las ciudades.
func anclar_en_ciudad(pos: Vector3, yaw: float = 0.0) -> void:
	_ancla_posicion = pos
	_ancla_yaw = yaw


## Punto seguro actual. Lo lee `RespawnHeros` para saber si ya hubo alguno
## (sin ancla, el respawn cae en el origen, que es el centro del mundo).
func ancla() -> Vector3:
	return _ancla_posicion


## Fase 59: una habilidad subió de tramo → recalcular los hechos.
func _al_subir_tramo(_hab: String, _tramo: int) -> void:
	if hechos != null:
		hechos.aplicar(stats)


## Fase 58: decaimiento de los vitales y sincronización con el StatBlock.
##
## DECISIÓN DE JUAN DIEGO: a 0 NO matan. Noriegan a 1 de vida y dejan un
## debuff. La muerte sigue siendo de los enemigos y de los jefes. Es el tono
## "wholesome" de Dragonwilds y no pelea con el respawn sin penalidad (fase 51).
##
## Todo el efecto pasa por MODS del StatBlock (`vital:energia`): la UI nunca
## escribe stats y el cambio es reversible, como el resto de los efectos.
func _tick_vitals(delta: float) -> void:
	if vitals == null:
		return
	# La actividad multiplica el gasto: pelear, correr y recolectar gastan
	# más que estar parado. Es lo que hace que comer importe en el camino.
	# Fase 59: los Hechos escriben los multiplicadores de decaimiento. Viven
	# en `Vitals` como números y no como referencia al sistema de talentos,
	# para que `Vitals` siga siendo puro.
	if hechos != null:
		vitals.mult_hambre = 0.5 if hechos.tiene("hambre_ausente") else 1.0
		vitals.mult_sed = 0.5 if hechos.tiene("sed_ausente") else 1.0

	var actividad: float = 1.0
	if objetivo_ataque != null and objetivo_ataque.esta_vivo():
		actividad = 2.2
	elif _tiene_destino:
		actividad = 1.5
	elif _moviendo_ahora:
		actividad = 1.3

	var aviso: bool = vitals.avanzar(delta, actividad)
	_sincronizar_vitals()
	if aviso:
		_avisar_vital()


## Pone o saca los mods de los vitales según dónde estén.
func _sincronizar_vitals() -> void:
	if vitals == null or stats == null:
		return
	# Energía → velocidad de ataque y de movimiento. Con energía >= 50 el
	# multiplicador es 1.0, o sea que no hace falta el mod.
	var mult: float = vitals.mult_ataque()
	if mult < 0.999:
		stats.add_mod("vital:energia", "vel_ataque",
			StatBlock.ModKind.PORCENTUAL, mult - 1.0)
		stats.add_mod("vital:energia_mov", "vel_mov",
			StatBlock.ModKind.PORCENTUAL, vitals.mult_velocidad() - 1.0)
	else:
		if stats.has_mod("vital:energia"):
			stats.remove_mod("vital:energia")
		if stats.has_mod("vital:energia_mov"):
			stats.remove_mod("vital:energia_mov")

	# Hambruna/sed a 0 → SOLO un debuff de debilidad.
	#
	# No drena vida ni te baja a 1 HP: la decisión de Juan Diego es que a 0 no
	# matan, y vaciarte la vida sería matarte de a poco por otro nombre. La
	# penalidad es que pegás y resistís peor, y la de la vida la siguen
	# aplicando los enemigos. Es el tono "wholesome" de Dragonwilds.
	var flojo: bool = vitals.hambre <= 0.0 or vitals.sed <= 0.0
	if flojo:
		if not stats.has_mod("vital:debil"):
			stats.add_mod("vital:debil", "defensa",
				StatBlock.ModKind.PORCENTUAL, -0.5)
			stats.add_mod("vital:debil_dano", "ataque",
				StatBlock.ModKind.PORCENTUAL, -0.3)
	elif stats.has_mod("vital:debil"):
		stats.remove_mod("vital:debil")
		stats.remove_mod("vital:debil_dano")


## El aviso una sola vez por franja (no cada frame).
func _avisar_vital() -> void:
	var cual: String = vitals.mas_bajo()
	if cual == "" or cual == _ultimo_vital_avisado:
		return
	_ultimo_vital_avisado = cual
	vital_bajo.emit(cual)


## ¿El jugador se está moviendo este frame? Lo cachea el movimiento.
var _moviendo_ahora: bool = false
## Para no repetir el mismo aviso cada frame.
var _ultimo_vital_avisado: String = ""


## Fase 51: revive al héroe en el punto seguro y deja el estado limpio.
## Sin penalidad (decisión de Juan Diego): no se pierde XP ni oro.
##
## El teletransporte va pegado al terreno (`_pegar_al_terreno`) porque el
## ancla viene de `CiudadLuna`, que sí consulta la altura real. Aun así se
## pega por si alguien pasa un ancla a mano.
func reaparecer() -> void:
	revivir()                     # Entity.revivir: señales + colisión
	global_position = _ancla_posicion
	_pegar_al_terreno()
	_tiene_destino = false
	_destino = Vector3.ZERO
	intent.tiene_destino = false
	deseleccionar()               # suelta objetivo_ataque, selección y pendientes
	if skills != null:
		skills.purgar_temporales()
		skills.purgar_cooldowns()
	# Fase 58: morirse con el estómago vacío no puede dejarte en 0 para
	# siempre — tenés que poder volver a pelear. Los vitals vuelven a lleno
	# y se limpian los mods.
	vitals = Vitals.new()
	_sincronizar_vitals()
	if _rig != null and is_instance_valid(_rig):
		_rig.snap_seguimiento()   # si no, la cámara cruza el mapa interpolando


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
		# Fase 45: la veta se mina con el mismo gesto (segundo clic). Una veta
		# agotada no es seleccionable: su colisión está apagada y el raycast
		# ni la encuentra.
		if e is Veta:
			return AccionClic.MINAR if (e as Veta).esta_minable() else AccionClic.NADA
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
		AccionClic.MINAR:
			# Fase 45: segundo clic en la veta seleccionada. Tampoco fija
			# objetivo de ataque (no es combatible): camina y mina al llegar.
			_acercarse_a_veta(e as Veta)
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
	# Fase 58: los vitales decaen con el tiempo y la actividad. Va primero
	# para que el resto del frame ya sienta el efecto de la energía.
	_tick_vitals(delta)
	# Fase 64: qué hay al alcance de la mano. Va con reloj propio para no
	# recorrer el grupo 60 veces por segundo (§9.5): comparar dos flotantes
	# cada medio segundo es imperceptible y cuesta casi nada.
	_tick_interactuable(delta)
	if skills != null:
		skills.tick(delta)
	_cd_ataque = maxf(_cd_ataque - delta, 0.0)
	# Fase 5.1: la selección muerta se limpia sola (el indicador se oculta).
	# Fase 45: también se suelta una veta que se agotó al minarla (si no,
	# el indicador quedaría flotando sobre el aire).
	if seleccion != null and not seleccion.esta_vivo():
		deseleccionar()
	elif seleccion is Veta and not (seleccion as Veta).esta_minable():
		deseleccionar()
	_construir_intent()
	_actualizar_lanzamiento_pendiente()
	_actualizar_interaccion_pendiente()
	_actualizar_minado_pendiente()
	_consumir_intent(delta)
	_actualizar_ataque(delta)
	_actualizar_animacion(delta)
	# Fase 12: el héroe camina pegado al terreno del mundo abierto.
	_pegar_al_terreno()
	# Bloque 66: pisadas. Van por DISTANCIA recorrida, no por tiempo: correr
	# tiene que sonar a más pasos que caminar, y el pie tiene que seguir el
	# ritmo real del movimiento, no un reloj fijo.
	_tick_pisadas(delta)


# --- bloque 66: pisadas -----------------------------------------------

## Distancia entre pisadas con el jugador caminando normal. A 4,2 m/s (la
## velocidad base) da ~2,4 pasos por segundo, que es un paso humano.
const PASO_DISTANCIA: float = 1.75
## Por debajo de esta velocidad no hay pisada: uno quieto no suena.
const UMBRAL_MOVIMIENTO: float = 0.6

func _tick_pisadas(delta: float) -> void:
	var plano := Vector2(velocity.x, velocity.z)
	var v: float = plano.length()
	if v < UMBRAL_MOVIMIENTO:
		_paso_acumulado = 0.0
		return
	_paso_acumulado += v * delta
	if _paso_acumulado < PASO_DISTANCIA:
		return
	_paso_acumulado = 0.0
	# El sonido es del jugador: 2D, no posicional (el que escucha es él).
	AudioJuego.reproducir(_sonido_piso(), -1)


## El material del suelo según la región. Se cachea porque `region_en` es un
## barrido de rectángulos y esto corre en `_physics_process`.
func _sonido_piso() -> String:
	if _piso_cache == "" or _piso_cache_frame != Engine.get_process_frames():
		_piso_cache_frame = Engine.get_process_frames()
		_piso_cache = _piso_segun_region()
	return _piso_cache


func _piso_segun_region() -> String:
	if _region_db == null:
		return "paso_tierra"
	var r: Dictionary = _region_db.region_en(global_position.x, global_position.z)
	return AudioJuego.paso_de_region(str(r.get("id", "")))


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
		_pend_veta = null
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


## Fase 45 — segundo clic en una veta ya seleccionada (y la tecla E): si está
## dentro del radio de interacción mina al instante (emite `minar_solicitado`
## y la `GestorVetas` la mina); si está lejos queda un minado pendiente y el
## jugador camina hasta ella. Sin violencia: una veta nunca es objetivo de
## ataque. Pública para tests.
func _acercarse_a_veta(v: Veta) -> void:
	if v == null or not is_instance_valid(v):
		return
	if not v.esta_minable():
		# Agotada: no hay nada que hacer (ni la selecciona).
		return
	if _dist_a(v) <= RADIO_INTERACCION:
		minar_solicitado.emit(v)
		return
	_pend_veta = v
	_tiene_destino = true
	_destino = v.global_position


## Fase 45 — resuelve el minado pendiente: si la veta se agotó, dejó de ser la
## selección (ESC, WASD, clic en suelo) o ya no es válida, se cancela; si está
## dentro del radio, mina; si no, sigue acercándose (mismo patrón que el
## diálogo pendiente).
func _actualizar_minado_pendiente() -> void:
	if _pend_veta == null:
		return
	var v: Veta = _pend_veta
	if not is_instance_valid(v) or not v.esta_minable() or v != seleccion:
		_pend_veta = null
		return
	if _dist_a(v) <= RADIO_INTERACCION:
		_pend_veta = null
		_tiene_destino = false
		minar_solicitado.emit(v)
	else:
		_destino = v.global_position
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
	# Fase 58: la actividad que consume los vitales depende de si te movés.
	_moviendo_ahora = Vector2(velocity.x, velocity.z).length() > 0.4
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
	# Fase 51: `damage_sin_alloc` + el dict de skill en una const evitan las
	# dos asignaciones por golpe que tenia este path (el Dictionary que
	# devolvia Formulas y el literal {"power": 1.0}).
	var res: Formulas.ResultadoDano = Formulas.damage_sin_alloc(
		stats, objetivo_ataque.stats, SKILL_ATAQUE_BASICO,
		randf(), randf_range(-1.0, 1.0))
	objetivo_ataque.take_damage(float(res.final), self, res.crit)
	_cd_ataque = 1.0 / maxf(stats.vel_ataque, 0.1)
	# Fase 50: el tajo del jugador dura lo que el clip, no lo que el cooldown.
	_t_swing = 0.32


## Suma oro (lo emite para el HUD). Nunca deja el oro bajo 0.
func ganar_oro(cantidad: int) -> void:
	oro = maxi(0, oro + cantidad)
	oro_cambiado.emit(oro)


## Fase 28: cada nivel da 1 punto de talento (propio, no de Entity).
## Fase 30: cada nivel da 2 puntos de atributo.
## Fase 31: cada nivel da 2 puntos de skill.
func _al_subir_nivel_talentos(_nivel: int) -> void:
	if talentos == null:
		talentos = Talentos.new()
	talentos.puntos += 1
	puntos_atributo += 2
	if skills == null:
		skills = SkillSystem.new()
	skills.puntos_skill += 2


## Fase 30: reparte 1 punto de atributo (FlyFF). Retorna "ok" /
## "sin_puntos" / "atributo" (no repartible). Recalcula derivados y deja
## la vida/maná actuales (no rellena; solo hace clamp si exceden).
func repartir_atributo(atributo: String) -> String:
	if puntos_atributo <= 0:
		return "sin_puntos"
	if atributo not in ATRIBUTOS_REPARTIBLES:
		return "atributo"
	puntos_atributo -= 1
	stats.set_base(atributo, float(stats.get(atributo)) + 1.0)
	stats.recalc()
	vida_actual = minf(vida_actual, stats.vida_max)
	mana_actual = minf(mana_actual, stats.mana_max)
	vida_cambiada.emit(vida_actual, stats.vida_max)
	mana_cambiado.emit(mana_actual, stats.mana_max)
	return "ok"


## Fase 11 — identidad del héroe (nombre + clase visible en la UI).
## Asigna y emite `identidad_cambiada` para que el retrato y la UI futura
## se actualicen (solo lectura). No toca stats.
func fijar_identidad(p_nombre: String, p_clase_id: String) -> void:
	nombre = p_nombre
	clase_id = p_clase_id
	# Fase 28: al cambiar de clase se purgan los talentos ajenos.
	if talentos != null:
		talentos.purgar_clase(stats, clase_id)
	# Fase 31: al cambiar de clase se reconfiguran los niveles de skill
	# (las skills de la clase nueva empiezan en 1; devuelve los puntos
	# invertidos en la anterior).
	if skills != null:
		skills.configurar_clase(clase_id)
	identidad_cambiada.emit()


## Fase 11 — aplica los atributos base de una clase desde datos (ClaseDB):
## pone los 4 atributos (fuerza, aguante, destreza, inteligencia) y su stat
## principal de daño (fase 42), recalcula derivados y llena vida/maná.
## Idempotente y tolerante: un id desconocido no toca nada ni revienta.
## NO emite `identidad_cambiada` (son stats, no identidad).
func aplicar_clase(id: String) -> void:
	if not ClaseDB.existe(id):
		return
	var base: Dictionary = ClaseDB.stats_base(id)
	stats.set_stat_daño(ClaseDB.stat_daño(id))
	stats.fuerza = float(base.get("fuerza", 0.0))
	stats.aguante = float(base.get("aguante", 0.0))
	stats.destreza = float(base.get("destreza", 0.0))
	stats.inteligencia = float(base.get("inteligencia", 0.0))
	stats.recalc()
	vida_actual = stats.vida_max
	mana_actual = stats.mana_max
	# Fase 37: el HUD es event-driven — sin estos emits queda pintando la
	# clase anterior (p. ej. 1150 del guerrero al elegir mago) hasta el
	# primer golpe.
	vida_cambiada.emit(vida_actual, stats.vida_max)
	mana_cambiado.emit(mana_actual, stats.mana_max)
	# Fase 50: el cuerpo cambia con la clase (datos, no código).
	aplicar_modelo(id)


## Fase 50 — cuelga el modelo 3D de la clase y deja sonando su clip.
##
## Se instancia el `.glb` entero como `Modelo` en vez de cambiar la malla de
## `Cuerpo`: una malla con piel en un `MeshInstance3D` suelto no se deforma,
## necesita el `Skeleton3D` en la misma rama. Misma regla que el enemigo
## (fase 49.1). La cápsula `Cuerpo` se apaga mientras hay modelo (si no, tapa
## al personaje por delante: la de la foto salía un tubo amarillo encima), pero
## NO es la que colisiona: la colisión es el nodo `Colision`, que no se toca. Y
## si el modelo falta, la cápsula vuelve a verse.
func aplicar_modelo(clase_id: String) -> void:
	if _modelo != null and is_instance_valid(_modelo):
		remove_child(_modelo)
		_modelo.queue_free()
	_modelo = null
	_anim = null
	_clip_actual = ""
	var capsula: MeshInstance3D = get_node_or_null("Cuerpo") as MeshInstance3D
	if capsula != null:
		capsula.visible = true
	var datos: Dictionary = ClaseDB.obtener(clase_id)
	var ruta: String = str(datos.get("modelo", ""))
	if ruta == "" or not ResourceLoader.exists(ruta):
		if ruta != "":
			push_warning("[Player] el modelo de la clase no existe: %s" % ruta)
		return
	var ps: PackedScene = load(ruta) as PackedScene
	if ps == null:
		push_warning("[Player] el modelo no es importable: %s" % ruta)
		return
	var inst: Node3D = ps.instantiate() as Node3D
	if inst == null:
		push_warning("[Player] el modelo no instancia a un Node3D: %s" % ruta)
		return
	inst.name = "Modelo"
	add_child(inst)
	# El pack viene mirando al +Z y el juego anda hacia el -Z: sin esta vuelta
	# el jugador camina de espaldas (ver Cuerpo.GIRO_MODELO).
	_modelo = inst
	_modelo.rotation.y = Cuerpo.GIRO_MODELO
	var esc: float = float(datos.get("modelo_escala", 1.0))
	if esc > 0.0 and not is_equal_approx(esc, 1.0):
		_modelo.scale = Vector3(esc, esc, esc)
	_anim = _buscar_anim(inst)
	_preparar_clips()
	_poner_clip("idle")
	if capsula != null:
		capsula.visible = false


func _buscar_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var hallada: AnimationPlayer = _buscar_anim(c)
		if hallada != null:
			return hallada
	return null


## `idle`, `walk` y `attack` ciclan; `die` no. Marcado una vez por modelo: el
## recurso Animation es compartido.
func _preparar_clips() -> void:
	if _anim == null:
		return
	for nombre in ["idle", "walk", "attack"]:
		if _anim.has_animation(nombre):
			_anim.get_animation(nombre).loop_mode = Animation.LOOP_LINEAR
	if _anim.has_animation("die"):
		_anim.get_animation("die").loop_mode = Animation.LOOP_NONE


## Pone un clip solo si cambia: llamar a `play` cada frame reinicia la
## animación y el jugador daría tirones.
func _poner_clip(nombre: String) -> void:
	if _anim == null or not is_instance_valid(_anim):
		return
	if _clip_actual == nombre:
		return
	if not _anim.has_animation(nombre):
		return
	_clip_actual = nombre
	_anim.play(nombre)


## Decide el clip con los mismos hechos que usa el movimiento, sin estado
## propio: quieto, caminando, tajo o muerto.
func _actualizar_animacion(delta: float) -> void:
	_t_swing = maxf(_t_swing - delta, 0.0)
	if not esta_vivo():
		_poner_clip(str(CLIP_MUERTE))
		return
	if _t_swing > 0.0:
		_poner_clip(str(CLIP_ATAQUE))
		return
	var plano: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if plano.length() > UMBRAL_CAMINAR:
		_poner_clip("walk")
	else:
		_poner_clip("idle")




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
