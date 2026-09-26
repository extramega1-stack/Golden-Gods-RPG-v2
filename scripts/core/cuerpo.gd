class_name Cuerpo
extends RefCounted
## Localiza la malla VISUAL de una entidad, esté donde esté.
##
## Hasta la fase 49 el cuerpo era siempre un `MeshInstance3D` hijo directo
## llamado `Cuerpo` (la cápsula procedural). Con los modelos 3D eso ya no
## vale: un `.glb` riggeado viene como `Modelo/Rig/Skeleton3D/Cuerpo`, y el
## nodo que se tiñe (flash de daño, FX de skill) es el de dentro, no un hijo
## directo.
##
## Antes de duplicar una búsqueda recursiva en cada sistema que tiñe, está
## aquí. Orden de resolución:
##
## 1. `Cuerpo` como hijo directo (la vía rápida de siempre: cápsula,
##   o el jugador, los NPC y el resto).
## 2. `Modelo` como hijo directo, y dentro la primera malla que haya
##    (el rig va en medio, no se sabe dónde lo deje el importador).
## 3. `null`: la entidad no dibuja malla (no debería pasar) y quien llama
##    avisa y se desactiva, como ya hacían.
##
## Sin estado: solo una búsqueda. Del resto (material, tinte) se ocupa cada
## sistema, que es el que sabe qué tiene que restaurar.

const NOMBRE_CUERPO: NodePath = ^"Cuerpo"
const NOMBRE_MODELO: NodePath = ^"Modelo"


## Malla visual de `entidad`, o `null` si no tiene.
static func malla(entidad: Node) -> MeshInstance3D:
	if entidad == null:
		return null
	var directo: MeshInstance3D = entidad.get_node_or_null(NOMBRE_CUERPO) as MeshInstance3D
	if directo != null:
		return directo
	var modelo: Node = entidad.get_node_or_null(NOMBRE_MODELO)
	if modelo == null:
		return null
	return _primera_malla(modelo)


## Primera `MeshInstance3D` del subárbol, en profundidad.
static func _primera_malla(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var hallada: MeshInstance3D = _primera_malla(c)
		if hallada != null:
			return hallada
	return null
