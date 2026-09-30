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
## =========================================================================
## FASE 152: DOS BÚFERS, Y POR QUÉ.
## =========================================================================
##
## El síntoma era "cada vez que me muevo todo parpadea". La causa era que el
## anillo se reescribía EN EL MISMO búfer que se está viendo, a 44 celdas por
## frame durante 8 frames. Durante esos 8 frames la pantalla mezclaba el anillo
## viejo con el nuevo, y el nuevo está corrido una celda (14 m) con respecto del
## viejo: la vegetación se veía deslizar 14 m sobre el suelo. La primera versión
## del arreglo apagó la capa y quedó 173 frames de pantalla VACÍA en 20 s de
## caminata; eso es peor, y era el número que había que bajar.
##
## LA SOLUCIÓN ES EL DOBLE BÚFER, y es la de todos los sistemas de mundo
## streamed: se escribe el anillo NUEVO en el búfer de atrás, que nadie ve, y
## cuando terminó de llenarse se intercambia el puntero. Los dos búferes
## contienen un anillo COMPLETO y CORRECTO en todo momento, así que el
## intercambio es instantáneo y no hay ni un frame de mezcla.
##
##Lo que cuesta: el doble de búfer. 317 slots × 48 bytes × 2 = 30 KB por capa,
## 487 KB para las dieciséis capas del anillo, contra un presupuesto de VRAM de
## 1 GB. Y lo que AHORRA: toda una clase de bug. Con un solo búfer no hay
## ningún estado en el que el anillo se vea, y "se ve a medio escribir" no es una
## opción que el código pueda alcanzar.
##
## El intercambio es un entero y una propiedad: `MultiMeshInstance3D.multimesh`
## es un puntero, y cambiarlo hace que el nodo pase a dibujar otro búfer. No
## copia 317 transformaciones: no copia NADA.

## Capacidad por defecto si alguien configura sin decir cuántas celdas hay.
const CAPACIDAD_MINIMA: int = 1

var capacidad: int = 0
## Los DOS búferes. `_escritura` es el índice del que se está llenando; el
## `multimesh` del nodo apunta al otro, que es el que se ve.
var _buferes: Array[MultiMesh] = []
var _escritura: int = 1
## Cuántos slots tienen una pieza puesta AHORA, en el búfer que se ve. Lo mira el
## test. Lleva un byte por slot y por búfer: es lo que hace que el número
## signifique "piezas en pantalla" y no "llamadas a `poner`".
var _con_pieza: Array[PackedByteArray] = []
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
## Escrituras al búfer que hizo ESTA capa desde que arrancó. Lo mira
## `test_fase152_flicker`: es el número con el que se compara el antes y el
## después, y el que responde "cuántas veces por segundo se reescriben las
## instancias del anillo".
##
## NOTA HONESTA SOBRE QUÉ MIDE: el flicker NUNCA fue esto. Antes eran 2.790 por
## segundo y el arreglo los deja donde estaban, y el parpadeo desaparece igual,
## porque el parpadeo eran 173 frames de pantalla vacía. Las escrituras bajan de
## verdad cuando la replantación no cambia de celda (el jugador quieto, o en
## zigzag dentro de una celda) y bajan a la mitad con la calidad en "Baja",
## porque el anillo es más corto. Pero el número que importaba era el otro.
var escrituras: int = 0


static func nulo() -> Transform3D:
	return _nulo


func _init() -> void:
	_buferes = [MultiMesh.new(), MultiMesh.new()]
	multimesh = _buferes[0]
	_escritura = 1
	_con_pieza = [PackedByteArray(), PackedByteArray()]
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


## Reserva la capacidad y deja los slots en nulo, en LOS DOS búferes. Se llama
## UNA vez. Los dos se reservan acá y nunca más: es lo que permite escribir en
## el de atrás sin crear nada.
func configurar(malla: Mesh, mat: Material, slots: int,
		alcance_capa: float = 0.0) -> void:
	capacidad = maxi(CAPACIDAD_MINIMA, slots)
	alcance = maxf(0.0, alcance_capa)
	for i in _buferes.size():
		var mm: MultiMesh = _buferes[i]
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = malla
		mm.instance_count = capacidad
		mm.visible_instance_count = -1
		for s in capacidad:
			mm.set_instance_transform(s, _nulo)
		_con_pieza[i].resize(capacidad)
		_con_pieza[i].fill(0)
	# El material va como `material_override` y no en la superficie del
	# `MultiMesh`: es lo que permite que la malla (una primitiva de 1x1x1) la
	# compartan todas las capas con la misma forma.
	if mat != null:
		material_override = mat
	if alcance > 0.0:
		visibility_range_begin = 0.0
		visibility_range_end = alcance
		visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Pone (o cambia) una pieza en un slot del búfer de ESCRITURA.
func poner(slot: int, xf: Transform3D) -> void:
	if slot < 0 or slot >= capacidad:
		return
	_buferes[_escritura].set_instance_transform(slot, xf)
	escrituras += 1
	# OJO con la doble indexación y NADA de variable local: un `PackedByteArray`
	# es un tipo VALOR, así que `var b: PackedByteArray = _con_pieza[i]` copia el
	# array y escribir en `b` no vuelve a `_con_pieza`. La copia pasea con
	# copy-on-write y el error sale como "el conteo de piezas da cero", que es un
	# síntoma a tres archivos de distancia de la línea que está mal.
	_con_pieza[_escritura][slot] = 1


## Deja un slot vacío. Es un write al buffer, no una operación de lista: no
## toca nodos, no libera memoria, no reordena nada.
func borrar(slot: int) -> void:
	if slot < 0 or slot >= capacidad:
		return
	_buferes[_escritura].set_instance_transform(slot, _nulo)
	escrituras += 1
	_con_pieza[_escritura][slot] = 0


## EL INTERCAMBIO. Se llama UNA vez por replantación, cuando el búfer de atrás
## ya tiene el anillo completo. Pasa a verse lo que se acaba de escribir y el
## búfer que se veía pasa a ser el de escritura.
##
## Por qué es un solo frame y no un crossfade: los dos búferes están completos
## en todo momento, así que no hay nada que interpolar. Lo que cambia en el
## instante del intercambio es el contenido del anillo, y ese cambio es real:
## el jugador se movió 9 m. Un crossfade haría que las dos imágenes se
## mezclaran en el aire, que es peor.
##
## EL ORDEN DE LAS TRES LÍNEAS IMPORTA y por eso el índice se lee en una
## variable antes de cambiarlo: `multimesh` tiene que pasar a apuntar al búfer
## que se ACABABA DE LLENAR (el que `_escritura` designa HASTA acá), y recién
## después `_escritura` se corre para que apunte al otro. Al revés, la capa
## muestra un búfer vacío y el conteo de piezas da cero: el síntoma es "no se
## ve nada" y la causa está a dos líneas.
func intercambiar() -> void:
	var recien_lleno: int = _escritura
	multimesh = _buferes[recien_lleno]
	puestos = _contar_puestos(recien_lleno)
	_escritura = 1 - recien_lleno


## El dueño del sistema necesita saber si el búfer donde va a escribir ya
## tiene limpios los slots que quedaron fuera del anillo: como el búfer de
## escritura es el que se veía hace dos replantaciones, hay que llevar ese dato
## por búfer y no uno global.
func bufer_de_escritura() -> int:
	return _escritura


func _contar_puestos(bufer: int) -> int:
	var n: int = 0
	for b in _con_pieza[bufer]:
		n += b
	return n


## Cuántas piezas hay en el búfer que se ve. Se cuenta al intercambiar, que es
## 317 sumas una vez por replantación: en caliente leerlo sería caro, y el dato
## no cambia entre replantaciones.
var puestos: int = 0


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
