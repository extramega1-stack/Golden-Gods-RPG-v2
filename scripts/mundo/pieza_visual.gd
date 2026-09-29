class_name PiezaVisual
extends Node3D
## Fase 64: la representación 3D de una pieza del Refugio.
##
## POR QUÉ EXISTE: la Fase 61 entregó `Constructor` como lógica PURA y sin
## instanciación visual — a propósito, por el presupuesto de VRAM (§9.5: el
## mundo ya traía 72 ArrayMesh y 36 ConcavePolygonShape3D residentes). Esa
## decisión era correcta para una fase de lógica, pero dejaba al Refugio
## invisible: se colocaban piezas que no se veían, que es la forma más
## desconcertante de "funciona pero no hay nada".
##
## Lo que hace este nodo:
## - Malla PROCEDURAL por tipo de pieza, a partir de la caja AABB del dato.
##   Sin GLB: los 85 de Meshy son estáticos enormes (96,7M triángulos) y
##   meterlos para una fogata de 1,4 m sería absurdo.
## - Material COMPARTIDO por tipo: ocho materiales para todas las piezas del
##   juego, no uno por pieza colocada.
## - `fantasma` para el preview: sin colisión y translúcido, que es lo que
##   permite ver el suelo a través de donde vas a construir.
##
## NO tiene colisión. Las piezas del refugio son decorativas; hacerlas
## StaticBody para 216 piezas posibles sería VRAM por adorno, y §9.5 lo pide
## explícitamente.

## §9.1
var system_id: StringName = &"pieza_visual"

## Materiales compartidos por tipo: 8 en todo el juego, uno por pieza
## colocada. `_cache_materiales` los construye una vez.
static var _materiales: Dictionary = {}
## El color por tipo, derivado del id para que dos piezas parezcan distintas
## sin necesidad de un dato de arte.
const COLORES: Dictionary = {
	"fogata": Color(0.45, 0.30, 0.22),
	"yunque": Color(0.28, 0.30, 0.34),
	"mesa": Color(0.52, 0.38, 0.24),
	"cofre": Color(0.40, 0.30, 0.20),
	"saco": Color(0.55, 0.50, 0.40),
	"estante": Color(0.45, 0.33, 0.22),
	"columna": Color(0.62, 0.60, 0.55),
	"antorcha": Color(0.35, 0.26, 0.18),
}

var tipo: String = ""
var fantasma: bool = false
var _malla: MeshInstance3D = null


## Construye la malla para `tipo` en el nodo. La posición y la rotación las
## pone el que la coloca; esta función solo dibuja.
func construir(p_tipo: String, p_fantasma: bool = false) -> bool:
	if not PiezasDB.existe(p_tipo):
		return false
	tipo = p_tipo
	fantasma = p_fantasma
	_malla = MeshInstance3D.new()
	_malla.name = "Malla"
	_malla.mesh = _mesh_de(p_tipo)
	_malla.material_override = _material(p_tipo, p_fantasma)
	add_child(_malla)
	if p_tipo == "fogata":
		_añadir_llama()
	return true


## La caja del dato manda en la forma: si `cajas` cambia en el JSON, la malla
## cambia con ella, sin tocar código.
func _mesh_de(tipo: String) -> BoxMesh:
	var c: Vector3 = PiezasDB.caja(tipo)
	var m := BoxMesh.new()
	m.size = c
	return m


func _material(tipo: String, fantasma: bool) -> Material:
	var clave: String = tipo + ("_fant" if fantasma else "")
	if _materiales.has(clave):
		return _materiales[clave]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORES.get(tipo, Color(0.5, 0.5, 0.5))
	mat.roughness = 0.9
	if fantasma:
		# Translúcido y sin sombras: el preview tiene que dejar ver el suelo.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.45
		mat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_materiales[clave] = mat
	return mat


## La fogata es la única pieza con algo encendido encima: sin esto, una
## "fogata" construida dentro del refugio es un cajón marrón.
func _añadir_llama() -> void:
	if fantasma:
		return
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.62, 0.25)
	luz.light_energy = 1.4
	luz.omni_range = 7.0
	luz.position = Vector3(0.0, PiezasDB.caja("fogata").y * 0.5 + 0.3, 0.0)
	add_child(luz)


## Limpia la caché de materiales. Los tests la vacían entre casos; el juego
## no hace falta llamarlo nunca (los 8 materiales son 8, no 216).
static func limpiar_cache() -> void:
	_materiales.clear()
