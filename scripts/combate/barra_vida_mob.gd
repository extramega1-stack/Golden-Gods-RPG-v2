class_name BarraVidaMob
extends Node3D
## Barra de vida flotante sobre los mobs (fase 19, game feel).
## Se adjunta como hijo del Enemy en enemigo.tscn (patrón DamageFlash).
## Solo LEE: señales `vida_cambiada` y `murio` del padre.
## Aparece al recibir daño; se oculta a vida llena tras una pausa corta
## y al morir. Dos quads con billboard (barato para muchos mobs).
##
## Fase 20 (P0-4): recursos compartidos. Antes cada barra creaba su propio
## QuadMesh + 2 StandardMaterial3D (con 50-100 mobs = 100-200 recursos y
## draw calls extra). Ahora el quad, el fondo y 10 peldaños de color del
## frente son estáticos compartidos (mismo patrón que Enemy._mats_cache);
## por instancia solo quedan los 2 MeshInstance3D. El color verde→rojo va
## por peldaños del 10% (invisible en una barra de 1.4 u).

const ANCHO: float = 1.4
const ALTO: float = 0.14
const ALTURA: float = 2.2
const TIEMPO_VISIBLE: float = 5.0
const PAUSA_LLENA: float = 0.5
## Peldaños del degradado verde→rojo del frente.
const PELDANOS: int = 10
const COLOR_LLENO: Color = Color(0.35, 0.9, 0.35)
const COLOR_VACIO: Color = Color(0.9, 0.25, 0.2)
const COLOR_FONDO: Color = Color(0.12, 0.04, 0.04)

static var _quad: QuadMesh = null
static var _mat_fondo: StandardMaterial3D = null
static var _mats_frente: Array = []

var _dueno: Entity = null
var _fg: MeshInstance3D = null
var _fondo: MeshInstance3D = null
## Fase 42: el frente usa malla propia (el billboard ignora scale.x del
## nodo, por eso el frente no se encogía y se veía una 2ª barra completa
## desplazada). Se redimensiona la MALLA y se compensa el centro para que
## crezca desde la izquierda; los MATERIALES siguen compartidos.
var _quad_frente: QuadMesh = null
var _reloj: float = 0.0


func _ready() -> void:
	_dueno = get_parent() as Entity
	if _dueno == null:
		set_process(false)
		return
	position = Vector3(0.0, ALTURA, 0.0)
	_fondo = _hacer_barra(false)
	_fg = _hacer_barra(true)
	add_child(_fondo)
	add_child(_fg)
	visible = false
	_dueno.vida_cambiada.connect(_al_vida_cambiada)
	_dueno.murio.connect(_al_morir)
	_actualizar(1.0)


func _hacer_barra(es_frente: bool) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	if es_frente:
		_quad_frente = QuadMesh.new()
		_quad_frente.size = Vector2(ANCHO, ALTO)
		mi.mesh = _quad_frente
		mi.material_override = _mat_frente_para(1.0)
	else:
		mi.mesh = _quad_compartido()
		mi.material_override = _mat_fondo_compartido()
	return mi


## Quad único compartido por todas las barras (fondo y frente).
static func _quad_compartido() -> QuadMesh:
	if _quad == null or not is_instance_valid(_quad):
		_quad = QuadMesh.new()
		_quad.size = Vector2(ANCHO, ALTO)
	return _quad


## Material de fondo único compartido.
static func _mat_fondo_compartido() -> StandardMaterial3D:
	if _mat_fondo == null or not is_instance_valid(_mat_fondo):
		_mat_fondo = _nuevo_material(COLOR_FONDO)
	return _mat_fondo


## Peldaño de color del frente para `pct` (0..1): 10 materiales
## compartidos verde→rojo. Sin allocs tras el primer uso.
static func _mat_frente_para(pct: float) -> StandardMaterial3D:
	if _mats_frente.size() != PELDANOS:
		_mats_frente.clear()
		for i in range(PELDANOS):
			var p: float = float(i) / float(PELDANOS - 1)
			_mats_frente.append(_nuevo_material(COLOR_VACIO.lerp(COLOR_LLENO, p)))
	var idx: int = clampi(int(round(clampf(pct, 0.0, 1.0) * float(PELDANOS - 1))), 0, PELDANOS - 1)
	return _mats_frente[idx] as StandardMaterial3D


static func _nuevo_material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = color
	return mat


func _al_vida_cambiada(vida: float, vida_max: float) -> void:
	if vida_max <= 0.0:
		return
	var pct: float = clampf(vida / vida_max, 0.0, 1.0)
	_actualizar(pct)
	visible = true
	if pct >= 1.0:
		_reloj = PAUSA_LLENA
	else:
		_reloj = TIEMPO_VISIBLE


func _actualizar(pct: float) -> void:
	if _fg == null or _quad_frente == null:
		return
	pct = clampf(pct, 0.0, 1.0)
	# Fase 42: escalamos la MALLA, no el nodo (billboard). El QuadMesh
	# está centrado, así que se compensa el centro para crecer a la izquierda.
	_quad_frente.size = Vector2(maxf(ANCHO * pct, 0.001), ALTO)
	_quad_frente.center_offset = Vector3((ANCHO - ANCHO * pct) * 0.5, 0.0, 0.0)
	# Peldaño compartido en vez de mutar un material propio.
	_fg.material_override = _mat_frente_para(pct)


## Resetea la barra para reutilizar el mob (PoolMobs): oculta y sin reloj.
func reiniciar() -> void:
	_reloj = 0.0
	visible = false
	set_process(true)


func _al_morir(_fuente: Entity) -> void:
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if _dueno == null or not visible:
		return
	if _reloj > 0.0:
		_reloj -= delta
		if _reloj <= 0.0:
			visible = false
