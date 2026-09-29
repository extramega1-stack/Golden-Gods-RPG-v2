class_name Constructor
extends RefCounted
## Fase 61: la construcción del Refugio. Lógica PURA, sin nodos.
##
## Es la fase más cara del proyecto y la que más riesgo de romper el
## presupuesto de GPU: el mundo ya tenía 72 `ArrayMesh` y 36
## `ConcavePolygonShape3D` RESIDENTES (§9.5) antes de esto. Por eso el
## presupuesto de piezas es un dato (`piezas_max` en `data/refugios.json`),
## se aplica ANTES de instanciar nada, y hay un test que falla si se pasa.
##
## Lo que NO hace, a propósito:
## - No permite rotación libre: solo 4 orientaciones, y solo si la pieza la
##   admite. Un editor de construcción libre es un sistema entero.
## - No hay terreno ni colisión: las piezas se anclan al suelo plano del
##   refugio (el disco urbano es plano por diseño del terreno).
##
## Instanciar los NODOS es tarea de `Refugio`/`PiezaNodo`; esta clase solo
## decide qué se puede poner y dónde.

## La rejilla de construcción. 2 u: coincide con el ancho de una calle y
## deja hueco para pasar entre las piezas.
const REJILLA: float = 2.0
## Separación mínima entre dos piezas, para que no queden pegadas.
const HOLGURA: float = 0.1


## La posición del snapping, ya en la rejilla.
static func ajustar(pos: Vector3) -> Vector3:
	return Vector3(roundf(pos.x / REJILLA) * REJILLA, 0.0, roundf(pos.z / REJILLA) * REJILLA)


## Las 4 rotaciones permitidas (en grados), para las piezas que la admiten.
static func rotaciones(id: String) -> Array[float]:
	if not PiezasDB.admite_rotacion(id):
		return [0.0]
	return [0.0, 90.0, 180.0, 270.0]


## ¿Se puede colocar esta pieza acá? Chequea, en este orden:
## 1. que la pieza exista, 2. el presupuesto de piezas, 3. que esté dentro
##    del refugio, 4. que no se solape con otra.
## `piezas_puestas` es la lista de `Refugio` (tipo, x, z, rot).
static func puede_colocar(refugio: Refugio, tipo: String, pos: Vector3,
		rot: float, piezas_puestas: Array) -> bool:
	if not PiezasDB.existe(tipo):
		return false
	# El presupuesto de VRAM va PRIMERO: es lo caro de deshacer.
	if piezas_puestas.size() >= refugio.piezas_max:
		return false
	var p := ajustar(pos)
	# Dentro del refugio.
	if Vector2(p.x - refugio.global_position.x, p.z - refugio.global_position.z).length() > refugio.radio:
		return false
	# Y la rotación tiene que ser una de las que la pieza admite.
	var rs := rotaciones(tipo)
	var rnorm: float = fposmod(rot, 360.0)
	var ok_rot: bool = false
	for r in rs:
		if is_equal_approx(fposmod(r, 360.0), rnorm):
			ok_rot = true
			break
	if not ok_rot:
		return false
	# Sin solapes.
	return not se_solapa(tipo, p, rot, piezas_puestas)


## ¿La caja de `tipo` en `pos`/`rot` pisa alguna pieza ya puesta?
static func se_solapa(tipo: String, pos: Vector3, rot: float, piezas: Array) -> bool:
	var caja := _caja_orientada(tipo, rot)
	for q in piezas:
		var p: Dictionary = q
		var otra := _caja_orientada(str(p.get("tipo", "")),
			float(p.get("rot", 0.0)))
		var centro := Vector3(float(p.get("x", 0.0)), 0.0, float(p.get("z", 0.0)))
		if _aabb_tocan(centro - otra * 0.5, centro + otra * 0.5,
				pos - caja * 0.5 + Vector3(0, caja.y * 0.5, 0),
				pos + caja * 0.5 + Vector3(0, caja.y * 0.5, 0)):
			return true
	return false


## La caja de la pieza, ya girada. Rotación solo de 90°: alcanza con
## intercambiar X y Z.
static func _caja_orientada(tipo: String, rot: float) -> Vector3:
	var c := PiezasDB.caja(tipo)
	var r: int = int(roundf(fposmod(rot, 360.0) / 90.0)) % 4
	if r % 2 == 1:
		return Vector3(c.z, c.y, c.x)
	return c


static func _aabb_tocan(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> bool:
	return (a0.x - HOLGURA <= b1.x and a1.x + HOLGURA >= b0.x
		and a0.z - HOLGURA <= b1.z and a1.z + HOLGURA >= b0.z)


## ¿Tenés los materiales? `inventario` es un Dictionary {item_id: cantidad}.
static func tiene_materiales(tipo: String, inventario: Dictionary) -> bool:
	for item in PiezasDB.costo(tipo).keys():
		var need: int = int(PiezasDB.costo(tipo)[item])
		if int(inventario.get(item, 0)) < need:
			return false
	return true


static func materiales_faltantes(tipo: String, inventario: Dictionary) -> Array:
	var faltan: Array = []
	for item in PiezasDB.costo(tipo).keys():
		var need: int = int(PiezasDB.costo(tipo)[item])
		var hay: int = int(inventario.get(item, 0))
		if hay < need:
			faltan.append({"item": item, "faltan": need - hay})
	return faltan


## El inventario para colocar, y el estado final. Quien llama es responsable
## de meter el item en el inventario de verdad; esto es la cuenta.
static func descontar(tipo: String, inventario: Dictionary) -> Dictionary:
	if not tiene_materiales(tipo, inventario):
		return {"ok": false, "motivo": "sin_materiales",
			"faltan": materiales_faltantes(tipo, inventario)}
	for item in PiezasDB.costo(tipo).keys():
		var need: int = int(PiezasDB.costo(tipo)[item])
		inventario[item] = int(inventario.get(item, 0)) - need
		if int(inventario[item]) <= 0:
			inventario.erase(item)
	return {"ok": true, "motivo": "", "faltan": []}


## Texto legible del motivo, para el aviso.
static func texto_motivo(motivo: String) -> String:
	match motivo:
		"sin_materiales":
			return "Te faltan materiales"
		"fuera_de_radio":
			return "Fuera del refugio"
		"presupuesto":
			return "El refugio está lleno"
		"solapado":
			return "Ahí hay algo puesto"
		"no_existe":
			return "No existe esa pieza"
		_:
			return "No se puede colocar ahí"
