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

## Materiales compartidos: los de las piezas salen de
## `data/materiales.json` (roll `piezas`) por `BibliotecaMateriales`, así que
## las ocho piezas de todo el juego comparten las texturas horneadas del
## mundo. Acá solo viven los del FANTASMA, que son un `StandardMaterial3D`
## translúcido por tipo y por eso no pueden salir de la biblioteca: el preview
## tiene que dejar ver el suelo por donde vas a construir.
static var _fantasmas: Dictionary = {}

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
	if fantasma:
		return _fantasma_de(tipo)
	return BibliotecaMateriales.de_rol(MaterialesDB.pieza(tipo), 0)


## El preview: translúcido y sin sombras, que es lo que permite ver el suelo
## a través de donde vas a construir. Ocho materiales en todo el juego.
func _fantasma_de(tipo: String) -> StandardMaterial3D:
	if _fantasmas.has(tipo):
		return _fantasmas[tipo] as StandardMaterial3D
	var rol: Dictionary = MaterialesDB.pieza(tipo)
	var real: StandardMaterial3D = BibliotecaMateriales.de_rol(rol, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = real.albedo_color
	m.roughness = real.roughness
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.45
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fantasmas[tipo] = m
	return m


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


## Limpia las cachés de materiales. Los tests las vacían entre casos; el
## juego no hace falta llamarlo nunca (son 8 piezas, no 216).
static func limpiar_cache() -> void:
	_fantasmas.clear()
	BibliotecaMateriales.limpiar()
