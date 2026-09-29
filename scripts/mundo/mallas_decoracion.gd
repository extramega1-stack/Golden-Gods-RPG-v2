class_name MallasDecoracion
extends RefCounted
## Fase 70: las MALLAS y los MATERIALES de la decoración, compartidos.
##
## POR QUÉ UN `BoxMesh` DE 1x1x1 Y UN `scale`: la decoración del mundo son
## ~20.000 piezas (matas, arbustos, farolas, cajas) hechas de las mismas cinco
## primitivas de Godot. Si cada una crease su `BoxMesh` del tamaño exacto, el
## mundo tendría 20.000 recursos de malla y la carga se iría aVRAM y a CPU en
## cosa que no se ve. Con una primitiva unidad por tipo y la escala en el
## TRANSFORM del `MultiMesh`, hay CINCO mallas para todo el mundo y cada
## `MultiMesh` es UNA llamada de dibujo.
##
## Y el material tampoco se crea por pieza: sale de
## `BibliotecaMateriales`, que cachea por (superficie, tinte, variante) y ya
## comparte las TEXTURAS entre docenas de piezas. La decoración no agrega ni un
## material nuevo al catálogo: usa superficies que ya existían (`pasto`, `hoja`,
## `madera`, `piedra`, `yeso`, `tela`, `metal`) y los tintes exactos que el
## catálogo ya horneó en variante 0.
##
## TODO lo que hay acá es `static` y cacheado: se llama una vez al arrancar
## (o en el primer tramo de la reconstrucción) y después son búsquedas de
## diccionario. Ni un `new()` en el bucle caliente (§9.5).

## Precisión de las primitivas. 8 lados y 4 anillos: a 40 m de distancia una
## hoja de 16 lados no se distingue de una de 8, y la mitad de los triángulos
## se paga sola. La geometría de la decoración es toda de menos de 4 m.
const LADOS: int = 8
const ANILLOS: int = 4

static var _primitivas: Dictionary = {}
static var _materiales: Dictionary = {}


## La primitiva unidad de un tipo (`caja`, `cilindro`, `cono`, `esfera`,
## `prisma`). SIEMPRE la misma instancia: es un recurso compartido por todo el
## mundo y no se puede duplicar.
static func primitiva(tipo: String) -> Mesh:
	if _primitivas.has(tipo):
		return _primitivas[tipo] as Mesh
	var m: Mesh = null
	match tipo:
		"caja":
			var caja := BoxMesh.new()
			caja.size = Vector3.ONE
			m = caja
		"cilindro":
			var cil := CylinderMesh.new()
			cil.top_radius = 0.5
			cil.bottom_radius = 0.5
			cil.height = 1.0
			cil.radial_segments = LADOS
			cil.rings = 1
			m = cil
		"cono":
			var cono := CylinderMesh.new()
			cono.top_radius = 0.02
			cono.bottom_radius = 0.5
			cono.height = 1.0
			cono.radial_segments = LADOS
			cono.rings = 1
			m = cono
		"esfera":
			var esf := SphereMesh.new()
			esf.radius = 0.5
			esf.height = 1.0
			esf.radial_segments = LADOS
			esf.rings = ANILLOS
			m = esf
		"prisma":
			var pri := PrismMesh.new()
			pri.size = Vector3.ONE
			pri.left_to_right = 0.5
			m = pri
		_:
			push_warning("[MallasDecoracion] primitiva desconocida: " + tipo)
			return null
	_primitivas[tipo] = m
	return m


## El material de un slot de vegetación en una zona, YA cacheado. La clave
## incluye la zona porque el MISMO slot (el follaje) cambia de tono de región a
## región, y el tint es lo único que separa una pradera de un glaciar.
static func material_vegetal(zona: Dictionary, slot: String) -> StandardMaterial3D:
	var t: Dictionary = DecoracionDB.tinte_de(zona, slot)
	if t.is_empty():
		t = {"superficie": "hoja", "tinte": "#4e7a2b"}
	var clave: String = "veg|%s|%s" % [str(t.get("superficie", "hoja")),
		str(t.get("tinte", "#4e7a2b"))]
	return _cachear(clave, t)


## El material de un slot de prop de calle. `pal_*` NO pasa por acá: lo resuelve
## la ciudad, que ya tiene su paleta aplicada, y ese `StandardMaterial3D` se
## comparte igual.
static func material_ciudad(id: String) -> StandardMaterial3D:
	var t: Dictionary = DecoracionDB.ciudad_slot(id)
	if t.is_empty():
		t = DecoracionDB.ciudad_slot("piedra")
	var clave: String = "ciu|%s" % id
	return _cachear(clave, t)


static func _cachear(clave: String, t: Dictionary) -> StandardMaterial3D:
	if _materiales.has(clave):
		return _materiales[clave] as StandardMaterial3D
	var mat: StandardMaterial3D = null
	if bool(t.get("plano", false)):
		# Los planos (la luz del farol) no llevan textura: son emisivos.
		mat = BibliotecaMateriales.plano(str(t.get("tinte", "#808080")),
			0.35, 0.0, str(t.get("emision", "")), float(t.get("emision_energia", 1.0)))
	else:
		# `variar: false` a propósito: la variación de grano la decide la ZONA
		# (el tinte), no el metro. Si además variara por posición, cada mata
		# pediría su propia variante y el catálogo dejaría de caber en el
		# presupuesto de VRAM que vigila `test_render_materiales`.
		mat = BibliotecaMateriales.material(str(t.get("superficie", "piedra")),
			str(t.get("tinte", "#808080")), 0, false,
			float(t.get("rugosidad_rel", 1.0)), float(t.get("metalicidad_rel", 0.0)))
	_materiales[clave] = mat
	return mat


## La transformación LOCAL de una parte dentro de su forma: el tamaño es la
## escala, `giro` es la rotación y la posición sale de `pos` o, si viene
## `altura`, de la Y del CENTRO de la pieza. Poder decir "el centro de este
## plantón está a 1.35 m" es la diferencia entre un JSON legible y 30 líneas de
## medias. Se calcula UNA vez por parte y se guarda: componerla después es
## multiplicar, no recalcular.
static func local_de(parte: Dictionary) -> Transform3D:
	var tam: Array = parte.get("tam", [1.0, 1.0, 1.0])
	var escala := Vector3(
		float(tam[0]) if tam.size() > 0 else 1.0,
		float(tam[1]) if tam.size() > 1 else 1.0,
		float(tam[2]) if tam.size() > 2 else 1.0)
	var giro: Array = parte.get("giro", [0.0, 0.0, 0.0])
	var rot := Vector3(
		float(giro[0]) if giro.size() > 0 else 0.0,
		float(giro[1]) if giro.size() > 1 else 0.0,
		float(giro[2]) if giro.size() > 2 else 0.0)
	var pos: Array = parte.get("pos", [0.0, 0.0, 0.0])
	var p := Vector3(
		float(pos[0]) if pos.size() > 0 else 0.0,
		float(pos[1]) if pos.size() > 1 else 0.0,
		float(pos[2]) if pos.size() > 2 else 0.0)
	if parte.has("altura"):
		# `altura` manda sobre `pos[1]`: es la Y del centro, o sea "a media
		# altura de la pieza", que es como se piensa una planta apoyada.
		p.y = float(parte["altura"])
	return Transform3D(Basis.from_euler(rot).scaled(escala), p)


## Vacía las cachés (los tests lo llaman; el juego, nunca).
static func limpiar() -> void:
	_primitivas.clear()
	_materiales.clear()


static func primitivas_creadas() -> int:
	return _primitivas.size()


static func materiales_creados() -> int:
	return _materiales.size()
