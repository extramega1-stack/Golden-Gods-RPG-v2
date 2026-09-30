class_name RejillaDecoracion
extends RefCounted
## Fase 70: la GRILLA de la decoración. La cuenta, sin estado.
##
## POR QUÉ UNA GRILLA Y NO UNA NUBE DE PUNTOS: la decoración del mundo (el
## pasto, los arbustos, los props de la calle) es un `MultiMesh` con UN SLOT POR
## CELDA. Esa es la decisión que hace que todo esto cueste lo que cuesta:
##
## - No hay asignación dinámica ni búsqueda libre. El slot de una celda es su
##   índice en el anillo, y el anillo se numera una sola vez con una función
##   pura. Nada de diccionarios de "celda -> slot" que hay que mantener.
## - El ANILLO TIENE SIEMPRE EL MISMO TAMAÑO, porque el anillo es un DISCO
##   centrado en la celda del jugador: hay la misma cantidad de celdas dentro
##   del radio, este donde esté el jugador. Eso convierte la capacidad en una
##   CONSTANTE conocida al arrancar, que es lo que permite reservar el
##   `MultiMesh` una vez y no volver a reservarlo nunca.
## - Se puede reescribir entero sin dejar basura: cada celda escribe sus slots
##   o los deja degenerados. No hay que buscar "qué había antes" para limpiarlo.
##
## El precio: la densidad es por celda, no por metro cuadrado. Es una decisión
## buena acá porque el pasto y el adoquín quieren ir a la celda, no a la
## superficie exacta, y porque una rejilla de 14 m es lo que hace legible una
## silueta de arbusto a 100 m sin necesitar el detalle del centro.
##
## NADA DE ESTO ES NODOS: la grilla no se puede ver ni colisiona. Se la usa
## para calcular índices, y el `MultiMesh` traduce índice -> geometría.


## Cuántas celdas tiene el anillo: un disco de radio `radio` con celdas de
## `paso`, en coordenadas de celda. Es el número de slots que hay que reservar
## y NO depende de dónde esté el jugador: es el presupuesto fijo de la
## decoración.
static func capacidad(paso: float, radio: float) -> int:
	var p: float = maxf(1.0, paso)
	var r: float = maxf(0.0, radio) / p
	var n: int = int(ceil(r))
	var total: int = 0
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			if float(dx * dx + dz * dz) <= r * r:
				total += 1
	return maxi(1, total)


## Las celdas del anillo alrededor de `centro`, ORDENADAS de forma estable (dz
## por fuera, dx por dentro). El orden importa: el índice de la lista es el slot
## del `MultiMesh`, y dos traversales tienen que dar la misma lista para que el
## mundo sea reconstruible.
static func celdas(centro: Vector2i, paso: float, radio: float) -> Array[Vector2i]:
	var p: float = maxf(1.0, paso)
	var r: float = maxf(0.0, radio) / p
	var n: int = int(ceil(r))
	var fuera: Array[Vector2i] = []
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			if float(dx * dx + dz * dz) > r * r:
				continue
			fuera.append(Vector2i(centro.x + dx, centro.y + dz))
	return fuera


## El MISMO disco que `celdas()`, pero SOLO los desplazamientos respecto del
## centro, escritos en dos buffers que reservó el llamador. Devuelve cuántos hay.
##
## POR QUÉ EXISTE Y POR QUÉ `celdas()` NO ALCANZA: el anillo sigue al jugador y
## se vuelve a armar cada vez que él cruza una frontera de celda. Con `celdas()`
## eso son 317 objetos `Vector2i` boxed en un `Array` nuevo cada replantación,
## en la ruta caliente, y es exactamente la asignación por frame que §9.5
## prohíbe. Con el patrón, replantar es sumarle `centro.x` a 317 enteros que ya
## están en un `PackedInt32Array`: ni una caja, ni una reserva, ni un pico de
## memoria.
##
## EL ORDEN ES EL DE `celdas()` Y TIENE QUE SEGUIR SIÉNDOLO: el índice del
## patrón es el slot del `MultiMesh`. Si los dos métodos cambiaran de orden, el
## mismo `(x, z)` del mundo caería en un slot distinto y la vegetación saltaría
## de metro.
static func patron(paso: float, radio: float, dx: PackedInt32Array,
		dz: PackedInt32Array) -> int:
	var p: float = maxf(1.0, paso)
	var r: float = maxf(0.0, radio) / p
	var n: int = int(ceil(r))
	var total: int = 0
	for z in range(-n, n + 1):
		for x in range(-n, n + 1):
			if float(x * x + z * z) > r * r:
				continue
			if total < dx.size():
				dx[total] = x
				dz[total] = z
			total += 1
	return total


## La celda del mundo que contiene a (x, z). El origen de la grilla es (0, 0)
## del mundo, no del jugador: si dependiera del jugador, cruzar una frontera
## cambiaría la semilla de todo el anillo y las plantas saltarían de metro.
static func celda_de(x: float, z: float, paso: float) -> Vector2i:
	var p: float = maxf(1.0, paso)
	return Vector2i(int(floorf(x / p)), int(floorf(z / p)))


## El centro en metros de una celda.
static func centro_de(celda: Vector2i, paso: float) -> Vector2:
	var p: float = maxf(1.0, paso)
	return Vector2((float(celda.x) + 0.5) * p, (float(celda.y) + 0.5) * p)
