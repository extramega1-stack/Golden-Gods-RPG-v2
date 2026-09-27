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

## Vuelta que hay que darle al modelo al colgarlo, en radianes.
##
## Los `.glb` del pack (los 85 de Meshy) miran al **+Z** de Godot, porque el
## exportador mapea blender (X, Y, Z) -> gltf (X, Z, -Y) y la malla mira al -Y de
## Blender. El forward del juego es **-Z**, asi que sin esta vuelta el jugador
## camina de espaldas y los enemigos corren hacia el jugador dando la espalda.
##
## Es una constante y no un dato por asset porque los 85 modelos salen de la
## misma cadena de exportacion. Y NO se arregla girando el esqueleto en Blender:
## el esqueleto tiene que mirar igual que la malla (tools/rig.py) o el ciclo de
## marcha se mueve al reves respecto al personaje.
const GIRO_MODELO: float = PI


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
