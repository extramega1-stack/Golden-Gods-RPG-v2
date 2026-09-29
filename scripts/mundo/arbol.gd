class_name Arbol
extends Veta
## Fase 55: un árbol talable. HEREDA de `Veta` en vez de duplicarla.
##
## Por qué hereda y no copia: la fx 45 dejó `Veta` como un nodo de recurso
## genérico (usos, respawn, aviso flotante, tinte, señal de recolección) y la
## fx 45.1 lo bonnesó con pool e histéresis. Un árbol es exactamente el mismo
## nodo con otro `item_id` y otra silueta. Copiarlo sería repetir el
## `skill_fx.gd` vs `damage_flash.gd` que ya está marcado como deuda.
##
## Lo ÚNICO que cambia:
## - la malla (tronco + copa en vez de una roca),
## - el nombre de la señal (`talada` en vez de `minada`), reemitida desde la
##   del padre, para que el código de tala se lea solo.
##
## La lógica —usos, respawn, tinte, aviso, colisión, `es_veta()`— es la del
## padre, sin tocar.

## Reemitida de `minada`, para que la tala se lea sola en el código que la
## escucha. Mismos argumentos.
signal talada(item_id: String, cantidad: int, xp: int)

## Alto del tronco y radio de la copa, en unidades de mundo. Un árbol tiene
## que leerse de lejos: es la silueta que orienta al jugador.
const ALTO_TRONCO: float = 4.2
const RADIO_COPA: float = 2.3

## Hotfix 62.1: talar sube `tala`, no `mineria`. El padre declara "mineria" y
## esta línea es la que hace que la tala tenga su propio XP de habilidad. Sin
## ella los Hechos de tala (tala_area, tala_rangos) nunca se desbloquean.
## No se puede redeclarar el miembro (GDScript lo prohíbe sobre un padre), así
## que se sobreescribe el valor en `_init`.

var _tronco: MeshInstance3D = null
var _copa: MeshInstance3D = null


func _init() -> void:
	super()
	habilidad_id = "tala"
	# La veta se avisa a sí misma de que se agotó; el árbol se engancha a esa
	# señal para sacarle la copa, y al reponer para devolvérsela. No se
	# sobreescribe `consumir_uso()` (eso tocaría la lógica de respawn del
	# padre): son 6 líneas de enganche contra una copia entera del nodo.
	minada.connect(_reemitir)
	agotada.connect(_al_agotar)


func _reemitir(item_id: String, cantidad: int, xp: int) -> void:
	talada.emit(item_id, cantidad, xp)


## La veta resuelve su cuerpo en `_ready`; el árbol lo reemplaza por su
## silueta justo después, conservando posición, rotación y colisión.
func _ready() -> void:
	super()
	_construir_arbol()


func _construir_arbol() -> void:
	# Fuera la roca de la veta.
	var cuerpo := get_node_or_null("Cuerpo") as MeshInstance3D
	if cuerpo != null:
		cuerpo.visible = false

	_tronco = MeshInstance3D.new()
	_tronco.name = "Tronco"
	var cil := CylinderMesh.new()
	cil.top_radius = 0.34
	cil.bottom_radius = 0.46
	cil.height = ALTO_TRONCO
	_tronco.mesh = cil
	_tronco.position = Vector3(0.0, ALTO_TRONCO * 0.5, 0.0)
	_tronco.material_override = _material(Color(0.32, 0.21, 0.13))
	add_child(_tronco)

	_copa = MeshInstance3D.new()
	_copa.name = "Copa"
	var esf := SphereMesh.new()
	esf.radius = RADIO_COPA
	esf.height = RADIO_COPA * 2.0
	esf.radial_segments = 8
	esf.rings = 4
	_copa.mesh = esf
	_copa.position = Vector3(0.0, ALTO_TRONCO + 0.7, 0.0)
	_copa.material_override = _material(tinte)
	add_child(_copa)


## Material propio del árbol (son pocos y estáticos; el tinte de la copa sí
## cambia por bioma, así que no se comparte como los de `Enemy`).
func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


## Al agotarse, el árbol se ve talado: sin copa. Es la señal de "aquí ya no
## hay nada" sin texto.
func _aplicar_tinte() -> void:
	if _copa != null and is_instance_valid(_copa):
		_copa.material_override = _material(tinte)


## Cuando la veta se agota, el árbol se ve talado: sin copa. Es la señal de
## "aquí ya no hay nada" sin necesidad de un texto.
## Ojo: `agotada` emite el id de la veta, así que el handler tiene que
## aceptarlo. Declararlo sin argumentos hace que Godot corte la conexión en runtime
## con "Method expected 0 argument(s), but called with 1".
func _al_agotar(_veta_id: String = "") -> void:
	if _copa != null and is_instance_valid(_copa):
		_copa.visible = false


## Reaparición: vuelve la copa. La llama el padre desde su `tick()` cuando
## se cumple el respawn, a través de `mostrar_cuerpo()`.
func mostrar_cuerpo() -> void:
	if _copa != null and is_instance_valid(_copa):
		_copa.visible = true
	super.mostrar_cuerpo()
