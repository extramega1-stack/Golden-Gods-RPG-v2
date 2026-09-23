class_name Clima
extends Node3D
## Sistema de clima — Fase 16 (lluvia + niebla, pedido de Juan Diego).
##
## Máquina de estados GLOBAL data-driven desde `res://data/clima.json`:
## un solo estado activo para todo el mundo (`despejado`, `lluvia`,
## `niebla`, `lluvia_niebla`). Cada `intervalo_revision_seg` segundos
## (aleatorio entre min y max) tira un dado ponderado con los pesos
## `siguientes` del estado actual; el peso de auto-transición define la
## duración esperada, así no hay duraciones explícitas por estado.
##
## Efectos por intensidad (0-1, siempre interpolados en `transicion_seg`,
## sin cortes bruscos):
## - Lluvia: UN solo GPUParticles3D pre-creado (cantidad fija data-driven,
##   `preprocess` para que no empiece de golpe), que sigue al jugador
##   recentrándose — no se recrea nunca. Sin audio (no hay sistema aún).
## - Cielo: atenúa sol/luna vía `CicloDia.factor_clima` y agrisa el cielo
##   vía `CicloDia.gris_tormenta` (API pública; ver ciclo_dia.gd fase 16).
## - Niebla: fog exponencial del Environment del ciclo
##   (`CicloDia.ambiente()`); el ciclo nunca toca el fog, no hay pelea.
##
## Rendimiento (fase 12.1): cero allocs por frame en el camino caliente —
## las partículas son un solo nodo, no se instancia/destruye nada por
## frame; la lluvia solo se reposiciona cuando está activa o en transición.
##
## Contrato de la demo (como CiudadLuna): `ciclo` y `jugador` se asignan
## ANTES del add_child. `avanzar(dt)` es la versión pura/testeable del
## avance (la llama `_process`); sin estar en el árbol solo mueve la
## máquina de estados y las intensidades.

signal cambio_clima(estado: String)

const RUTA_DATOS: String = "res://data/clima.json"

## Ciclo día/noche al que se atenúa el sol y se le modula la niebla.
var ciclo: CicloDia = null
## El emisor de lluvia se recentra sobre este nodo (el jugador).
var jugador: Node3D = null
## Si es false, el clima solo cambia con fijar_clima() (tests, debug).
var cambio_automatico: bool = true

var _estado: String = "despejado"
var _lluvia_int: float = 0.0
var _niebla_int: float = 0.0
var _obj_lluvia: float = 0.0
var _obj_niebla: float = 0.0
var _transicion: float = 5.0
var _revision_en: float = 120.0
var _rev_min: float = 90.0
var _rev_max: float = 180.0
var _atenuacion_sol_min: float = 0.45
var _gris_cielo_max: float = 0.75
var _densidad_max: float = 0.012
var _cielo_afectado: float = 0.35
var _altura_lluvia: float = 14.0

var _rng: RandomNumberGenerator = null
var _listo: bool = false
var _lluvia: GPUParticles3D = null
var _env: Environment = null


func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_leer_config()
	_establecer_estado("despejado")
	_revision_en = _rng.randf_range(_rev_min, _rev_max)


func _ready() -> void:
	if ciclo == null:
		push_warning("[Clima] sin ciclo inyectado: la máquina de estados funciona pero no hay visuales")
		return
	_env = ciclo.ambiente()
	_construir_lluvia()
	_configurar_niebla()
	_listo = true


func _process(delta: float) -> void:
	avanzar(delta)


## Avanza la máquina de estados y las intensidades `dt` segundos.
## Sin estar en el árbol (pre-_ready) solo mueve estado/intensidades:
## los visuales se aplican únicamente cuando los nodos ya existen.
func avanzar(dt: float) -> void:
	if dt <= 0.0:
		return
	if cambio_automatico:
		_revision_en -= dt
		if _revision_en <= 0.0:
			_revision_en = _rng.randf_range(_rev_min, _rev_max)
			_tirar_transicion()
	# Interpolación suave hacia los objetivos del estado (nada de cortes).
	var paso: float = clampf(dt / _transicion, 0.0, 1.0)
	_lluvia_int = _acercar(_lluvia_int, _obj_lluvia, paso)
	_niebla_int = _acercar(_niebla_int, _obj_niebla, paso)
	if _listo:
		_aplicar_visuales()


## Fija el clima manualmente ("despejado", "lluvia", "niebla",
## "lluvia_niebla"). Reinicia el temporizador automático. Devuelve false
## (sin cambiar nada) si el estado no existe en data/clima.json.
func fijar_clima(estado: String) -> bool:
	if not _estados().has(estado):
		push_warning("[Clima] estado desconocido: '%s'" % estado)
		return false
	_establecer_estado(estado)
	_revision_en = _rng.randf_range(_rev_min, _rev_max)
	return true


## Estado actual ("despejado" | "lluvia" | "niebla" | "lluvia_niebla").
func clima_actual() -> String:
	return _estado


## Intensidad global del clima 0-1 (máximo entre lluvia y niebla).
func intensidad() -> float:
	return maxf(_lluvia_int, _niebla_int)


## Intensidad de lluvia 0-1 (interpola en transicion_seg).
func intensidad_lluvia() -> float:
	return _lluvia_int


## Intensidad de niebla 0-1 (interpola en transicion_seg).
func intensidad_niebla() -> float:
	return _niebla_int


## Semilla fija para el dado de transiciones (tests deterministas).
func fijar_semilla(s: int) -> void:
	_rng.seed = s


## True si el nodo de lluvia está emitiendo (para tests/UI).
func emitiendo_lluvia() -> bool:
	return _lluvia != null and _lluvia.emitting


## Fracción de gotas activas 0-1 (para tests/UI).
func proporcion_lluvia() -> float:
	if _lluvia == null:
		return 0.0
	return _lluvia.amount_ratio


## Densidad de niebla aplicada al Environment (para tests/UI).
func densidad_niebla() -> float:
	return _densidad_max * _niebla_int


static func _acercar(a: float, b: float, paso: float) -> float:
	if a < b:
		return minf(a + paso, b)
	return maxf(a - paso, b)


func _establecer_estado(estado: String) -> void:
	_estado = estado
	var e: Dictionary = _estados().get(estado, {})
	_obj_lluvia = clampf(float(e.get("lluvia", 0.0)), 0.0, 1.0)
	_obj_niebla = clampf(float(e.get("niebla", 0.0)), 0.0, 1.0)
	_transicion = float(e.get("transicion_seg", 5.0))
	if _transicion <= 0.0:
		_transicion = 5.0
	cambio_clima.emit(estado)


## Dado ponderado con los pesos "siguientes" del estado actual.
func _tirar_transicion() -> void:
	var e: Dictionary = _estados().get(_estado, {})
	var pesos: Dictionary = e.get("siguientes", {})
	var total: float = 0.0
	for k in pesos:
		total += maxf(float(pesos[k]), 0.0)
	if total <= 0.0:
		return
	var r: float = _rng.randf() * total
	for k in pesos:
		r -= maxf(float(pesos[k]), 0.0)
		if r <= 0.0:
			_establecer_estado(str(k))
			return


## Camino caliente: solo aritmética y setters sobre nodos existentes.
## La lluvia solo se reposiciona cuando está activa o en transición.
func _aplicar_visuales() -> void:
	var li: float = _lluvia_int
	var ni: float = _niebla_int
	# Sol/cielo: el ciclo aplica estos factores en su propio _process
	# (1 frame de retardo como máximo, invisible).
	ciclo.factor_clima = lerpf(1.0, _atenuacion_sol_min, li)
	ciclo.gris_tormenta = li * _gris_cielo_max
	# Niebla: fog exponencial del Environment del ciclo.
	if _env != null:
		_env.fog_density = _densidad_max * ni
		_env.fog_light_color = Color(0.75, 0.78, 0.85).lerp(Color(0.55, 0.58, 0.62), li)
	# Lluvia: recentrar sobre el jugador (sin recrear nada).
	if _lluvia != null:
		if li > 0.0005 or _obj_lluvia > 0.0005:
			_lluvia.emitting = true
			_lluvia.visible = true
			_lluvia.amount_ratio = li
			if jugador != null and is_instance_valid(jugador):
				_lluvia.global_position = jugador.global_position + Vector3(0.0, _altura_lluvia, 0.0)
		else:
			_lluvia.emitting = false
			_lluvia.visible = false
			_lluvia.amount_ratio = 0.0


func _construir_lluvia() -> void:
	var d: Dictionary = _cfg().get("lluvia", {})
	var gotas: int = maxi(int(d.get("gotas", 2000)), 1)
	var radio: float = float(d.get("radio_area", 28.0))
	var caida: float = float(d.get("velocidad_caida", 30.0))
	var pre: float = float(d.get("preprocess_seg", 1.4))
	_lluvia = GPUParticles3D.new()
	_lluvia.name = "Lluvia"
	_lluvia.amount = gotas
	_lluvia.lifetime = pre
	# preprocess = la lluvia ya cae distribuida al activarse (no empieza de golpe).
	_lluvia.preprocess = pre
	_lluvia.explosiveness = 0.0
	_lluvia.randomness = 0.6
	_lluvia.amount_ratio = 0.0
	_lluvia.emitting = false
	_lluvia.visible = false
	_lluvia.visibility_aabb = AABB(
		Vector3(-radio, -20.0, -radio),
		Vector3(radio * 2.0, radio * 2.0 + 40.0, radio * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(radio, 1.0, radio)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 3.0
	pm.gravity = Vector3(0.0, -caida, 0.0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	_lluvia.process_material = pm
	# Gota = prisma fino y alargado, azulado translúcido, sin sombreado (perf).
	var malla := BoxMesh.new()
	malla.size = Vector3(0.03, 0.55, 0.03)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.62, 0.74, 0.92, 0.45)
	malla.material = mat
	_lluvia.draw_pass_1 = malla
	add_child(_lluvia)


func _configurar_niebla() -> void:
	if _env == null:
		push_warning("[Clima] el ciclo no tiene Environment: sin niebla")
		return
	# Hotfix fase-18.2: en macOS la niebla del Environment pinta la pantalla
	# blanca (bug conocido de Godot 4.x con el driver Metal, ver issue
	# godotengine/godot#115064). Se desactiva solo en Mac; en el resto de
	# plataformas la niebla sigue funcionando igual.
	if OS.get_name() == "macOS":
		_env.fog_enabled = false
		return
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.fog_density = 0.0
	_env.fog_sky_affect = _cielo_afectado


func _leer_config() -> void:
	var c: Dictionary = _cfg()
	var rev: Dictionary = c.get("intervalo_revision_seg", {})
	_rev_min = float(rev.get("min", 90.0))
	_rev_max = float(rev.get("max", 180.0))
	if _rev_max < _rev_min:
		_rev_max = _rev_min
	var ll: Dictionary = c.get("lluvia", {})
	_atenuacion_sol_min = clampf(float(ll.get("atenuacion_sol_min", 0.45)), 0.0, 1.0)
	_gris_cielo_max = clampf(float(ll.get("gris_cielo_max", 0.75)), 0.0, 1.0)
	_altura_lluvia = float(ll.get("altura", 14.0))
	var nb: Dictionary = c.get("niebla", {})
	_densidad_max = maxf(float(nb.get("densidad_max", 0.012)), 0.0)
	_cielo_afectado = clampf(float(nb.get("cielo_afectado", 0.35)), 0.0, 1.0)


func _estados() -> Dictionary:
	return _cfg().get("estados", _estados_default())


## Si el JSON falta o está roto: un único estado despejado (no revienta).
func _estados_default() -> Dictionary:
	return {"despejado": {"lluvia": 0.0, "niebla": 0.0, "transicion_seg": 5.0, "siguientes": {"despejado": 1.0}}}


static var _datos_cache: Dictionary = {}


## Lee el JSON UNA vez (estático cacheado, mismo patrón que CicloDia).
static func _cfg() -> Dictionary:
	if not _datos_cache.is_empty():
		return _datos_cache
	var texto: String = FileAccess.get_file_as_string(RUTA_DATOS)
	if texto == "":
		push_warning("[Clima] no se pudo leer %s; usando defaults" % RUTA_DATOS)
		return {}
	# parse_string retorna Variant: NUNCA `:=` aquí (warning como error).
	var crudo = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[Clima] %s no es un diccionario JSON válido" % RUTA_DATOS)
		return {}
	_datos_cache = crudo
	return _datos_cache
