class_name GameFeel
extends Node3D
## Game feel de combate (fase 19): números de daño flotantes, hit-stop y
## screen shake. Vive como un solo nodo en la escena demo; `Entity.take_damage`
## le avisa vía el estático `al_recibir_danio` (no-op si no hay instancia,
## así los tests headless sin escena no truenan).
##
## - Números: pool de Label3D con billboard (blanco = daño normal,
##   amarillo = crítico, rojo = daño al jugador). Flotan, hacen pop y se
##   desvanecen. `no_depth_test` para que siempre se lean.
## - Hit-stop: congela `Engine.time_scale` unas centésimas en críticos,
##   golpes fuertes al jugador y golpes mortales.
## - Shake: trauma en el CameraRig (grupo "camera_rig").

static var inst: GameFeel = null

const POOL_NROS: int = 20
const NRO_TIEMPO: float = 0.9
const NRO_SUBIDA: float = 1.7

const COLOR_NORMAL: Color = Color(1.0, 1.0, 1.0)
const COLOR_CRIT: Color = Color(1.0, 0.85, 0.2)
const COLOR_JUGADOR: Color = Color(1.0, 0.25, 0.2)

var _nros: Array[Label3D] = []
var _nro_vida: Array[float] = []
var _nro_crit: Array[bool] = []
var _nro_idx: int = 0
var _congelado: bool = false
var _rig: CameraRig = null
## Último golpe registrado como crítico (tests).
var ultimo_fue_crit: bool = false


func _ready() -> void:
	inst = self
	_construir_pool()


func _exit_tree() -> void:
	if inst == self:
		inst = null


## Aviso desde Entity.take_damage. Seguro sin instancia (tests).
static func al_recibir_danio(dueno: Entity, dano: float, fuente: Entity, es_critico: bool) -> void:
	if inst == null:
		return
	inst._al_recibir_danio(dueno, dano, fuente, es_critico)


## Sacudida de cámara directa. Segura sin instancia.
static func sacudir(cantidad: float) -> void:
	if inst == null:
		return
	inst._sacudir(cantidad)


## Hit-stop directo. Seguro sin instancia.
static func hit_stop(duracion: float = 0.06, escala: float = 0.05) -> void:
	if inst == null:
		return
	inst._hit_stop(duracion, escala)


func _al_recibir_danio(dueno: Entity, dano: float, fuente: Entity, es_critico: bool) -> void:
	ultimo_fue_crit = es_critico
	var pos: Vector3 = dueno.global_position + Vector3(randf_range(-0.3, 0.3), 1.9, 0.0)
	var color: Color = COLOR_NORMAL
	if es_critico:
		color = COLOR_CRIT
	elif dueno is Player:
		color = COLOR_JUGADOR
	_mostrar_numero(pos, dano, color, es_critico)
	# Bloque 68: el kick direccional, SOLO si el que recibe es el jugador. Un
	# golpe a un mob cercano no debe mover la cámara: el jugador tiene que
	# poder seguir jugando mientras pega, no saltar con cada impacto.
	if dueno is Player and fuente != null and fuente is Node3D \
			and fuente != dueno and (fuente as Node3D).is_inside_tree():
		var dir: Vector3 = dueno.global_position - (fuente as Node3D).global_position
		_kick(dir, 0.10 if not es_critico else 0.20)
	var murio: bool = dueno.vida_actual <= 0.0
	if murio:
		_hit_stop(0.09, 0.05)
		_sacudir(0.45)
	elif es_critico:
		_hit_stop(0.05, 0.08)
		if fuente is Player:
			_sacudir(0.25)
	if dueno is Player and dano > dueno.stats.vida_max * 0.15 and not murio:
		_hit_stop(0.06, 0.1)
		_sacudir(0.35)


func _mostrar_numero(pos: Vector3, dano: float, color: Color, es_critico: bool) -> void:
	var idx: int = _nro_idx
	_nro_idx = (_nro_idx + 1) % POOL_NROS
	var nro: Label3D = _nros[idx]
	nro.global_position = pos
	nro.text = str(int(roundf(dano)))
	nro.modulate = color
	var base: float = 1.5 if es_critico else 1.0
	nro.scale = Vector3(base * 1.35, base * 1.35, base * 1.35)
	nro.visible = true
	_nro_vida[idx] = NRO_TIEMPO
	_nro_crit[idx] = es_critico


func _construir_pool() -> void:
	for i in POOL_NROS:
		var nro: Label3D = Label3D.new()
		nro.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nro.no_depth_test = true
		nro.pixel_size = 0.008
		nro.font_size = 96
		nro.outline_size = 16
		nro.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
		nro.visible = false
		add_child(nro)
		_nros.append(nro)
		_nro_vida.append(0.0)
		_nro_crit.append(false)


func _process(delta: float) -> void:
	for i in POOL_NROS:
		if _nro_vida[i] <= 0.0:
			continue
		_nro_vida[i] -= delta
		var nro: Label3D = _nros[i]
		if _nro_vida[i] <= 0.0:
			nro.visible = false
			continue
		nro.global_position.y += NRO_SUBIDA * delta
		var t: float = _nro_vida[i] / NRO_TIEMPO
		var c: Color = nro.modulate
		c.a = clampf(t * 2.0, 0.0, 1.0)
		nro.modulate = c
		var pop: float = clampf((NRO_TIEMPO - _nro_vida[i]) / 0.15, 0.0, 1.0)
		var base: float = 1.5 if _nro_crit[i] else 1.0
		var s: float = lerpf(base * 1.35, base, pop)
		nro.scale = Vector3(s, s, s)


func _hit_stop(duracion: float, escala: float) -> void:
	if _congelado:
		return
	_congelado = true
	Engine.time_scale = escala
	await get_tree().create_timer(duracion, true, false, true).timeout
	_restaurar_tiempo()


## Restaura el tiempo normal (la llama el temporizador del hit-stop;
## pública para tests).
func _restaurar_tiempo() -> void:
	Engine.time_scale = 1.0
	_congelado = false


## Bloque 68: el kick de cámara, DIRECCIONAL. `direccion` es hacia dónde
## vino el golpe. Se dispara solo cuando el que recibe es el jugador: el
## jugador no "siente" el peso de los golpes que pega, siente los que le pegan.
func _kick(direccion: Vector3, fuerza: float) -> void:
	if _rig == null:
		_rig = get_tree().get_first_node_in_group("camera_rig") as CameraRig
	if _rig != null:
		_rig.agregar_kick(direccion, fuerza)


func _sacudir(cantidad: float) -> void:
	if _rig == null:
		_rig = get_tree().get_first_node_in_group("camera_rig") as CameraRig
	if _rig != null:
		_rig.agregar_trauma(cantidad)


## ¿Hay algún número visible ahora? (tests).
func hay_numero_visible() -> bool:
	for nro in _nros:
		if nro.visible:
			return true
	return false
