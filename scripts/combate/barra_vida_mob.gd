class_name BarraVidaMob
extends Node3D
## Barra de vida flotante sobre los mobs (fase 19, game feel).
## Se adjunta como hijo del Enemy en enemigo.tscn (patrón DamageFlash).
## Solo LEE: señales `vida_cambiada` y `murio` del padre.
## Aparece al recibir daño; se oculta a vida llena tras una pausa corta
## y al morir. Dos quads con billboard (barato para muchos mobs).

const ANCHO: float = 1.4
const ALTO: float = 0.14
const ALTURA: float = 2.2
const TIEMPO_VISIBLE: float = 5.0
const PAUSA_LLENA: float = 0.5

var _dueno: Entity = null
var _fg: MeshInstance3D = null
var _fondo: MeshInstance3D = null
var _reloj: float = 0.0


func _ready() -> void:
	_dueno = get_parent() as Entity
	if _dueno == null:
		set_process(false)
		return
	position = Vector3(0.0, ALTURA, 0.0)
	_fondo = _hacer_barra(Color(0.12, 0.04, 0.04))
	_fg = _hacer_barra(Color(0.35, 0.9, 0.35))
	add_child(_fondo)
	add_child(_fg)
	visible = false
	_dueno.vida_cambiada.connect(_al_vida_cambiada)
	_dueno.murio.connect(_al_morir)
	_actualizar(1.0)


func _hacer_barra(color: Color) -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(ANCHO, ALTO)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = color
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	return mi


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
	if _fg == null:
		return
	_fg.scale.x = maxf(pct, 0.001)
	# El QuadMesh está centrado: se recorre para que crezca desde la izquierda.
	_fg.position.x = -ANCHO * (1.0 - pct) * 0.5
	var mat: StandardMaterial3D = _fg.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(0.9, 0.25, 0.2).lerp(Color(0.35, 0.9, 0.35), pct)


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
