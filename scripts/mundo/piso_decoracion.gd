class_name PisoDecoracion
extends MultiMeshInstance3D
## Fase 70: UNA CAPA de decoración. Un `MultiMesh` con un slot por celda de la
## grilla, una malla compartida y un material compartido.
##
## POR QUÉ UN NODO POR CAPA Y NO UN NODO POR PIEZA: un `MeshInstance3D` por
## matita de pasto serían 20.000 nodos, 20.000 transformaciones que el motor
## tiene que recorrer en C++ cada frame y 20.000 llamadas de dibujo. Un
## `MultiMesh` son 20 transformaciones en un buffer contiguo y UNA llamada: la
## fila de un `MultiMesh` es lo que el renderer instancia, no hay término medio.
##
## POR QUÉ `visible = false` EN VEZ DE "NO PONGAS NADA": la capacidad se
## reserva una vez al arrancar y no vuelve a cambiar. Una celda vacía se escribe
## con una transformación DEGENERADA (base de escala 0): ocupa un slot del
## buffer que ya estaba reservado y no genera ni un triángulo. Es la regla de
## §9.5 aplicada a un `MultiMesh`: en caliente no se crea ni se destruye nada,
## se reescriben números.
##
## El nodo empieza INVISIBLE y solo se enciende cuando el anillo quedó
## completo. Mientras se reescribe se vería el anillo viejo mezclado con el
## nuevo, y eso es peor que un frame de pantalla vacía.

## Capacidad por defecto si alguien configura sin decir cuántas celdas hay.
const CAPACIDAD_MINIMA: int = 1

var capacidad: int = 0
## Cuántos slots tienen una pieza puesta ahora mismo. Lo mira el test.
var puestos: int = 0
## Si la capa se apaga sola por distancia (los props de las 9 ciudades, que
## viven TODAS en el mismo árbol de escena).
var alcance: float = 0.0
## Si la capa proyecta sombra. Sale del dato, especie por especie: la hierba no
## proyecta (es una décima parte del frame y no aporta lectura) y un árbol sí,
## porque un árbol sin sombra se ve pegado al suelo como una calcomanía.
var proyecta_sombra: bool = false
## Un transform degenerado: escala 0 en los tres ejes. No genera triángulos ni
## píxeles, pero ocupa su slot del buffer (que ya estaba reservado).
static var _nulo: Transform3D = Transform3D(
	Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)


static func nulo() -> Transform3D:
	return _nulo


func _init() -> void:
	multimesh = MultiMesh.new()
	visible = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Tampoco entran en la iluminación indirecta: son pocos triángulos y muchos
	# píxeles, y el cazarro de la GI no compra nada acá.
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## Enciende o apaga la proyección de sombra de la capa. Se llama una vez por
## capa (al repintar la zona), no por frame.
func set_sombra(activo: bool) -> void:
	proyecta_sombra = activo
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if activo \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Reserva la capacidad y deja los slots en nulo. Se llama UNA vez.
func configurar(malla: Mesh, mat: Material, slots: int,
		alcance_capa: float = 0.0) -> void:
	capacidad = maxi(CAPACIDAD_MINIMA, slots)
	alcance = maxf(0.0, alcance_capa)
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = malla
	multimesh.instance_count = capacidad
	multimesh.visible_instance_count = -1
	for i in capacidad:
		multimesh.set_instance_transform(i, _nulo)
	# El material va como `material_override` y no en la superficie del
	# `MultiMesh`: es lo que permite que la malla (una primitiva de 1x1x1) la
	# compartan todas las capas con la misma forma.
	if mat != null:
		material_override = mat
	if alcance > 0.0:
		visibility_range_begin = 0.0
		visibility_range_end = alcance
		visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	puestos = 0


## Pone (o cambia) una pieza en un slot.
func poner(slot: int, xf: Transform3D) -> void:
	if slot < 0 or slot >= capacidad:
		return
	multimesh.set_instance_transform(slot, xf)
	puestos += 1


## Deja un slot vacío. No baja el contador: es un write al buffer, no una
## operación de lista.
func borrar(slot: int) -> void:
	if slot < 0 or slot >= capacidad:
		return
	multimesh.set_instance_transform(slot, _nulo)


## Pone el contador a cero SIN tocar el buffer.
##
## POR QUÉ EXISTE Y POR QUÉ NO HAY UN `vaciar()`: vaciar la capa son
## `capacidad` escrituras, y en la fase 70 eso son ~5.000 escrituras de buffer
## en UN frame cada vez que se replanta el anillo de vegetación. No hace falta:
## como `capacidad` es exactamente la cantidad de celdas del anillo, cada celda
## escribe TODOS sus slots durante el drenaje (con su pieza o con el transform
## degenerado, vía `poner` y `borrar`). Al terminar el drenaje no queda nada del
## anillo viejo, y este `recountar` deja el contador listo para la vuelta
## siguiente.
func recountar() -> void:
	puestos = 0


## Enciende la capa. Recién ahí se ve: la reconstrucción del anillo va frame a
## frame y una capa a medio escribir se ve rota.
func encender() -> void:
	visible = true


func apagar() -> void:
	visible = false


## Triángulos que esta capa mete en el PEOR caso, con los `capacidad` slots
## puestos. El test lo vigila contra el presupuesto sin abrir el motor.
func triangulos_maximos() -> int:
	if multimesh == null or multimesh.mesh == null:
		return 0
	return multimesh.mesh.get_faces().size() / 3 * maxi(0, capacidad)
