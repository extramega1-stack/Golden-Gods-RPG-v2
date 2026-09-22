class_name CicloDia
extends Node
## Ciclo día/noche data-driven — Fase 12.
##
## Lee `res://data/ciclo.json` (`duracion_dia_seg`, `hora_inicial`) y mueve
## la hora 0–24 a razón de `24 * delta / duracion_dia_seg`. Construye en
## `_ready`: DirectionalLight3D "Sol", DirectionalLight3D "Luna" y un
## WorldEnvironment con cielo procedural (ProceduralSkyMaterial, verificado
## en Godot 4.7.2 headless).
##
## Curva solar: seno con amanecer ≈6h y anochecer ≈18h. De noche el sol se
## apaga (energía 0) y la luna toma el relevo (tenue, azulada). El
## Environment varía con la oscuridad: amanecer dorado, mediodía neutro,
## noche azul oscuro. Pensado para NO romper el look diurno actual: a plena
## luz el sol da 1.25 de energía blanca cálida y el ambiente es moderado.
##
## `avanzar(dt)` es la versión pura/testeable del avance (la llama
## `_process`): actualiza la hora y, si los nodos visuales ya existen
## (post-_ready), refresca luces y cielo. Las señales `amanecer`/`anochecer`
## se emiten al cruzar los umbrales 6h y 18h avanzando hacia adelante.

signal amanecer
signal anochecer

const RUTA_DATOS: String = "res://data/ciclo.json"
const UMBRAL_AMANECER: float = 6.0
const UMBRAL_ANOCHECER: float = 18.0

## Duración de un día completo en segundos reales (data-driven; inyectable
## en tests para acelerar el ciclo).
var duracion_dia_seg: float = 720.0

var _hora: float = 9.0
var _sol: DirectionalLight3D = null
var _luna: DirectionalLight3D = null
var _env: Environment = null
var _cielo_mat: ProceduralSkyMaterial = null


func _ready() -> void:
	var datos: Dictionary = _cargar_datos()
	duracion_dia_seg = float(datos.get("duracion_dia_seg", 720.0))
	if duracion_dia_seg <= 0.0:
		duracion_dia_seg = 720.0
	_hora = _envolver(float(datos.get("hora_inicial", 9.0)))
	_construir()
	_actualizar_visuales()


static var _datos_cache: Dictionary = {}


## Lee el JSON UNA vez (estático cacheado, mismo patrón que los DBs).
static func _cargar_datos() -> Dictionary:
	if not _datos_cache.is_empty():
		return _datos_cache
	var texto: String = FileAccess.get_file_as_string(RUTA_DATOS)
	if texto == "":
		push_warning("[CicloDia] no se pudo leer %s; usando defaults" % RUTA_DATOS)
		return {}
	# parse_string retorna Variant: NUNCA `:=` aquí (warning como error).
	var crudo = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[CicloDia] %s no es un diccionario JSON válido" % RUTA_DATOS)
		return {}
	_datos_cache = crudo
	return _datos_cache


func _construir() -> void:
	# Sol: luz principal diurna, con sombras.
	_sol = DirectionalLight3D.new()
	_sol.name = "Sol"
	_sol.shadow_enabled = true
	add_child(_sol)
	# Luna: relevo nocturno tenue y azulado, sin sombras (perf).
	_luna = DirectionalLight3D.new()
	_luna.name = "Luna"
	_luna.light_color = Color(0.55, 0.68, 1.0)
	_luna.shadow_enabled = false
	_luna.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(30.0), 0.0)
	add_child(_luna)
	# Cielo procedural + ambiente.
	_cielo_mat = ProceduralSkyMaterial.new()
	var cielo: Sky = Sky.new()
	cielo.sky_material = _cielo_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = cielo
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var mundo: WorldEnvironment = WorldEnvironment.new()
	mundo.name = "Cielo"
	mundo.environment = _env
	add_child(mundo)


func _process(delta: float) -> void:
	avanzar(delta)


## Avanza el reloj `dt` segundos reales y refresca los visuales.
## Idempotente respecto a los nodos: si aún no se construyeron (el nodo no
## está en el árbol), solo mueve la hora.
func avanzar(dt: float) -> void:
	if dt <= 0.0 or duracion_dia_seg <= 0.0:
		return
	var previa: float = _hora
	_hora = _envolver(_hora + 24.0 * dt / duracion_dia_seg)
	_emitir_cruces(previa, _hora)
	_actualizar_visuales()


## Hora actual del día, 0–24.
func hora() -> float:
	return _hora


## True si la oscuridad supera el 50% (noche cerrada o casi).
func es_de_noche() -> bool:
	return oscuridad() > 0.5


## 0 = día pleno, 1 = noche cerrada. En el amanecer/anochecer (sol en el
## horizonte) vale 1: el sol aún no ilumina.
func oscuridad() -> float:
	return 1.0 - clampf(_elevacion_sol(), 0.0, 1.0)


## Fija la hora directamente (0–24, con wrap). No emite señales: están
## pensadas para el avance continuo de `avanzar()`.
func fijar_hora(h: float) -> void:
	_hora = _envolver(h)
	_actualizar_visuales()


## Seno de la elevación solar: 0 en 6h y 18h, 1 al mediodía, negativo de
## noche (amanecer ≈6h, anochecer ≈18h).
func _elevacion_sol() -> float:
	return sin((_hora - UMBRAL_AMANECER) / 12.0 * PI)


static func _envolver(h: float) -> float:
	var r: float = fmod(h, 24.0)
	if r < 0.0:
		r += 24.0
	return r


## Emite `amanecer`/`anochecer` si el avance cruzó 6h/18h hacia adelante
## (contempla el wrap por la medianoche).
func _emitir_cruces(previa: float, nueva: float) -> void:
	if _cruzo(previa, nueva, UMBRAL_AMANECER):
		amanecer.emit()
	if _cruzo(previa, nueva, UMBRAL_ANOCHECER):
		anochecer.emit()


static func _cruzo(previa: float, nueva: float, umbral: float) -> bool:
	if previa <= nueva:
		return previa < umbral and nueva >= umbral
	# Wrap por 0h: el umbral se cruza si quedó en el tramo recorrido.
	return nueva >= umbral or previa < umbral


func _actualizar_visuales() -> void:
	if _sol == null or _luna == null or _env == null or _cielo_mat == null:
		return
	var elev: float = _elevacion_sol()
	var dia: float = clampf(elev, 0.0, 1.0)  # 0 de noche, 1 al mediodía
	var osc: float = 1.0 - dia
	_actualizar_sol(elev, dia)
	_actualizar_luna(osc)
	_actualizar_cielo(elev, osc)


func _actualizar_sol(elev: float, dia: float) -> void:
	if dia <= 0.0:
		_sol.light_energy = 0.0
		return
	# Energía diurna plena 1.25 (no rompe el look actual); el sol bajo
	# pierde algo de fuerza y se vuelve cálido.
	_sol.light_energy = 1.25 * dia
	var calidez: float = clampf(1.0 - dia * 2.5, 0.0, 1.0)
	_sol.light_color = Color(1.0, 0.98, 0.95).lerp(Color(1.0, 0.62, 0.32), calidez)
	# Este→cenit→oeste: de día el arco cubre 6h–18h.
	var t: float = clampf((_hora - UMBRAL_AMANECER) / 12.0, 0.0, 1.0)
	var elev_grados: float = maxf(elev, 0.0) * 75.0
	_sol.rotation = Vector3(
		deg_to_rad(-elev_grados),
		deg_to_rad(lerpf(-90.0, 90.0, t)),
		0.0)


func _actualizar_luna(osc: float) -> void:
	# Relevo nocturno: tenue y azulada, apagada de día.
	_luna.light_energy = 0.22 * osc


func _actualizar_cielo(elev: float, osc: float) -> void:
	# Paletas día / noche.
	var top_dia: Color = Color(0.32, 0.55, 0.90)
	var hor_dia: Color = Color(0.72, 0.83, 0.94)
	var top_noche: Color = Color(0.012, 0.020, 0.060)
	var hor_noche: Color = Color(0.045, 0.075, 0.150)
	_cielo_mat.sky_top_color = top_dia.lerp(top_noche, osc)
	_cielo_mat.ground_bottom_color = top_dia.lerp(top_noche, osc)
	# Horizonte: dorado en amanecer/anochecer (sol cerca del horizonte).
	var hor: Color = hor_dia.lerp(hor_noche, osc)
	var cerca_horizonte: float = clampf(1.0 - absf(elev) * 4.0, 0.0, 1.0)
	hor = hor.lerp(Color(1.0, 0.55, 0.26), cerca_horizonte * (1.0 - osc) * 0.85)
	_cielo_mat.sky_horizon_color = hor
	_cielo_mat.ground_horizon_color = hor
	# Ambiente: moderado de día, frío y bajo de noche.
	_env.ambient_light_color = Color(0.55, 0.60, 0.70).lerp(Color(0.14, 0.19, 0.34), osc)
	_env.ambient_light_energy = lerpf(0.55, 0.30, osc)
