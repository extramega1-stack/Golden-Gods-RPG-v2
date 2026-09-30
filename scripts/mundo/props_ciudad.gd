class_name PropsCiudad
extends Node3D
## Fase 70: los PROPS DE CALLE de una ciudad. Farolas, bancos, cajas, barriles,
## toldos, postes y carritos, sobre las cuatro calles radiales.
##
## POR QUÉ UN `MultiMesh` Y NO UN NODO POR PROP: una ciudad con 180 props son
## 180 nodos y 180 llamadas de dibujo, y el mundo tiene NUEVE ciudades en el
## mismo árbol de escena: 1.600 nodos y 1.600 draw calls para poner un banco.
## Con un `MultiMesh` por (prop, pieza) son ~20 llamadas por ciudad, las mismas
## veinte mallas compartidas por las nueve, y el alcance por distancia apaga la
## ciudad que no estás mirando.
##
## POR QUÉ NO HAY COLISIÓN: un banco que frena al jugador es un acierto en un
## juego de paseo y un desastre en uno de combate (empuja la pelea contra la
## pared sin que el jugador pueda esquivarla) y, peor, agrega 180
## `StaticBody3D` al mundo por ciudad. `test_fase15_ciudades` además exige que
## TODO `StaticBody3D` de la ciudad tenga una `BoxShape3D`; los props no son
## estructuras, así que no entran en ese conteo ni en el de `edificios`.
##
## LA SEMILLA ES DE POSICIÓN: la vereda de la calle 2, tramo 17, tiene el mismo
## farol en cualquier sesión y en cualquier máquina. Si el prop saliera de un
## `rand`, cargar un save pondría los bancos en otras veredas y el jugador
## perdería de vista la calle que recuerda.
##
## DÓNDE NO SE PONE: dentro de un edificio. Se descartan las celdas de vereda
## cuya caja cae dentro de alguna AABB de colisión de la ciudad, que es la
## forma exacta de saber dónde está cada edificio sin volver a duplicar su
## planta en el dato.

## Lado de la celda del bucket de obstáculos, en metros. Del orden del ancho de
## un edificio: pocos candidatos por bucket.
const CELDA_BUCKET: float = 20.0
## Calles radiales por ciudad, y lados de cada calle.
const CALLES: int = 4
const LADOS: int = 2
## Margen alrededor del prop para la prueba de choque con un edificio. Un banco
## pegado a la pared molesta; a un metro de la pared parece puesto a mano.
const HOLGURA: float = 1.6

## Terreno para las alturas. La ciudad se lo pasa ya resuelto (lo tiene en la
## mano): no se busca por el árbol para no depender del orden de armado.
var terreno_actual: Terreno = null

## Cuántos props se pusieron. Lo mira el test.
var puestos: int = 0
## Cuántas celdas de vereda se consideraron (con y sin prop).
var candidatas: int = 0
## Cuántas se descartaron por caer dentro de un edificio.
var descartadas: int = 0

## Dónde quedó cada prop, en el orden en que sefue poniendo. Son ~150
## `Transform3D` por ciudad (48 bytes cada uno): es el "plano" de la calle, y
## existe porque `MultiMesh.get_instance_transform` NO se puede leer de vuelta
## en headless (el búfer vive en el RenderingServer y en el rasterizador dummy
## no se conserva), así que sin esto la única forma de probar que dos
## ciudades iguales dan la misma calle sería abrir un motor con ventana.
var _plano: Array[Transform3D] = []

## `_capas[i]` son las capas del prop `_ids[i]`; `_locales[i]`, sus
## transformaciones locales. `_slot_de_prop` mapea el índice de la lista de
## `data/decoracion.json` al de estas dos, porque una forma que falte deja un
## hueco y desalinearía todo si se usara el índice crudo.
var _capas: Array = []
var _locales: Array = []
var _ids: Array[String] = []
var _slot_de_prop: Dictionary = {}
var _altura_max: float = 0.0
## La capa en la que quedó cada prop, en el mismo orden que `_plano`. Es lo que
## permite reconstruir sus piezas sin volver a correr el dado (el test lo
## usa; el juego, nunca).
var _slots: Array[int] = []


# ---------------------------------------------------------------------------

## Construye la calle de una ciudad. Devuelve cuántos props quedaron puestos.
## `paleta` es el `Dictionary` interno de `CiudadLuna` (los 5 colores de la
## ciudad) y `obstaculos` son las AABB de colisión que la ciudad ya calculó.
func construir(centro: Vector2, radio_muralla: float, plaza_radio: float,
		paleta: Dictionary, obstaculos: Array) -> int:
	DecoracionDB.cargar()
	position = Vector3(centro.x, 0.0, centro.y)
	var paso: float = DecoracionDB.ciudad_paso()
	var r_hasta: float = DecoracionDB.ciudad_r_hasta()
	if r_hasta <= 0.0:
		r_hasta = maxf(0.0, radio_muralla - DecoracionDB.ciudad_distancia_puerta())
	var r_desde: float = maxf(DecoracionDB.ciudad_r_desde(), plaza_radio + 20.0)
	puestos = 0
	candidatas = 0
	descartadas = 0
	_altura_max = 0.0
	if r_hasta <= r_desde:
		return 0
	var n_pasos: int = maxi(1, int((r_hasta - r_desde) / paso))
	var buckets: Dictionary = _indexar(obstaculos)
	# La capacidad son exactamente las celdas de vereda que hay, ni una más: un
	# `MultiMesh` reserva 48 bytes por instancia y pedir de más son cientos de
	# KB por capa que no se tocan nunca.
	_construir_capas(paleta, n_pasos * CALLES * LADOS)
	var lateral: float = CiudadLuna.ANCHO_CALLE * 0.5 + DecoracionDB.ciudad_margen()
	for g in range(CALLES):
		var ang: float = float(g) * PI * 0.5
		var dir := Vector2(sin(ang), -cos(ang))
		var perp := Vector2(cos(ang), sin(ang))
		for lado in range(LADOS):
			var s: float = 1.0 if lado == 0 else -1.0
			for i in range(n_pasos):
				var base: Vector2 = dir * (r_desde + (float(i) + 0.5) * paso)
				# El hash sacude la vereda en las DOS direcciones: una fila de
				# farolas perfectamente parecidas a 11 m se lee como una cuenta
				# de luz, no como una calle.
				var semilla: int = DecoracionDB.semilla(base.x + centro.x,
					base.y + centro.y)
				var r: float = r_desde + (float(i) + 0.5) * paso \
					+ DecoracionDB.entre(semilla, 11, -paso * 0.32, paso * 0.32)
				var lz: float = lateral + DecoracionDB.entre(semilla, 12, -1.2, 1.2)
				var x: float = dir.x * r + perp.x * lz * s
				var z: float = dir.y * r + perp.y * lz * s
				var wx: float = x + centro.x
				var wz: float = z + centro.y
				candidatas += 1
				if _dentro_de_un_edificio(buckets, x, z):
					descartadas += 1
					continue
				var p: int = _prop_de_celda(semilla)
				if p < 0 or not _slot_de_prop.has(p):
					continue
				_colocar(int(_slot_de_prop[p]), p, x, z, wx, wz, semilla)
	_encender_todas()
	return puestos


## Las capas arrancan INVISIBLES (`PisoDecoracion._init`), porque una capa a
## medio escribir se ve rota. La vegetación las enciende cuando su anillo queda
## completo; los props de calle se construyen de una sola pasada, así que el
## punto de encenderlas es AL FINAL de `construir` y no antes.
##
## POR QUÉ ESTO FALTABA Y NADIE LO VIÓ: los props se armaban, se contaban, el
## test leía `plano()` y `piezas_de_prop()` y daba verde, y las nueve ciudades
## tenían las farolas y los bancos sentados a oscuras en la calle. Un sistema
## entero, con sus datos y sus pruebas, invisible en el juego. Es la clase de
## bug que ningún test de sistema pilla: mide que la geometría esté donde debe,
## no que alguien la mire.
func _encender_todas() -> void:
	for c in _capas:
		for p in (c as Array):
			(p as PisoDecoracion).encender()


# ---------------------------------------------------------------------------
# La decisión: qué prop, si alguno, va en esta celda de vereda
# ---------------------------------------------------------------------------

## El primer prop de la lista que pasa su dado. UNA celda lleva UN SOLO prop:
## una vereda con un farola, un banco y tres cajas en el mismo metro no es una
## vereda, es un rummage. El orden de la lista ES la jerarquía (la farola gana
## porque es la primera que se sortea) y sale del dato.
func _prop_de_celda(semilla: int) -> int:
	var lista: Array = DecoracionDB.ciudad_props()
	for idx in lista.size():
		if not (lista[idx] is Dictionary):
			continue
		var uno: int = maxi(1, int((lista[idx] as Dictionary).get("uno_cada", 8)))
		if DecoracionDB.unidad(semilla, 3000 + idx) < 1.0 / float(uno):
			return idx
	return -1


func _colocar(slot: int, prop: int, x: float, z: float, wx: float, wz: float,
		semilla: int) -> void:
	var capas_k: Array = _capas[slot]
	if capas_k.is_empty():
		return
	# La Y del MUNDO, leída en el metro exacto (wx, wz) y con la prop hundida un
	# poco: un banco que solo ROZA el suelo se ve pegado con cinta, y en la
	# vereda en pendiente (que no es plana: la ciudad se apoya en el terreno)
	# la pata de abajo queda en el aire. La cantidad sale del dato.
	var y: float = -DecoracionDB.ciudad_hundir()
	if terreno_actual != null and is_instance_valid(terreno_actual):
		y += terreno_actual.altura_en(wx, wz)
	var lista: Array = DecoracionDB.ciudad_props()
	var yaw: float = float((lista[prop] as Dictionary).get("yaw", 0.0)) \
		+ DecoracionDB.entre(semilla, 3100 + prop, -0.35, 0.35)
	var esc: float = DecoracionDB.entre(semilla, 3200 + prop, 0.90, 1.12)
	var xf := Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0))
		.scaled(Vector3.ONE * esc), Vector3(x, y, z))
	var locales: Array = _locales[slot]
	for p in capas_k.size():
		(capas_k[p] as PisoDecoracion).poner(puestos,
			MallasDecoracion.componer(locales[p] as Transform3D, xf))
	_plano.append(xf)
	_slots.append(slot)
	puestos += 1


# ---------------------------------------------------------------------------
# Capas y obstáculos
# ---------------------------------------------------------------------------

func _construir_capas(paleta: Dictionary, capacidad: int) -> void:
	if not _capas.is_empty():
		return
	_plano.clear()
	_slots.clear()
	var lista: Array = DecoracionDB.ciudad_props()
	for idx in lista.size():
		if not (lista[idx] is Dictionary):
			continue
		var d: Dictionary = lista[idx]
		var partes: Array = DecoracionDB.partes(str(d.get("forma", "")))
		if partes.is_empty():
			push_warning("[PropsCiudad] prop sin forma: " + str(d.get("id", "")))
			continue
		var capas_k: Array = []
		var locales_k: Array = []
		for p in partes:
			var parte: Dictionary = p
			var malla: Mesh = MallasDecoracion.primitiva(str(parte.get("prim", "caja")))
			if malla == null:
				continue
			var piso := PisoDecoracion.new()
			piso.name = "%s_%d" % [str(d.get("id", "prop")), capas_k.size()]
			piso.configurar(malla, _material_de(str(parte.get("tinte", "piedra")),
				paleta), capacidad, DecoracionDB.ciudad_alcance())
			capas_k.append(piso)
			locales_k.append(MallasDecoracion.local_de(parte))
		if capas_k.is_empty():
			continue
		for c in capas_k:
			add_child(c)
		_slot_de_prop[idx] = _capas.size()
		_ids.append(str(d.get("id", "")))
		_capas.append(capas_k)
		_locales.append(locales_k)
		_altura_max = maxf(_altura_max, _alto_de_forma(partes))


## La altura de un prop, para el registro de alturas de la ciudad.
func _alto_de_forma(partes: Array) -> float:
	var alto: float = 0.0
	for p in partes:
		var d: Dictionary = p
		var tam: Array = d.get("tam", [1.0, 1.0, 1.0])
		var y: float = float(tam[1]) if tam.size() > 1 else 1.0
		var pos: Array = d.get("pos", [0.0, 0.0, 0.0])
		var cy: float = float(d["altura"]) if d.has("altura") \
			else (float(pos[1]) if pos.size() > 1 else 0.0)
		alto = maxf(alto, absf(cy) + y * 0.5)
	return alto


## El material de un slot. Los `pal_*` son la paleta de la ciudad (el mismo
## `StandardMaterial3D` que usan los muros y los tejados: por eso un farol de
## Golden Town sale dorado y uno de Fury Town de acero, sin un solo hex en el
## código). El resto son tintes fijos de `data/decoracion.json`.
func _material_de(slot: String, paleta: Dictionary) -> StandardMaterial3D:
	if slot.begins_with("pal_") and paleta.has(slot):
		var p: Dictionary = paleta[slot]
		return BibliotecaMateriales.material(str(p.get("superficie", "piedra")),
			str(p.get("tinte", "#808080")), 0, false,
			float(p.get("rugosidad_rel", 1.0)),
			float(p.get("metalicidad_rel", 0.0)))
	return MallasDecoracion.material_ciudad(slot)


## Las AABB de la ciudad en buckets de 20 m. Sin esto habría que probar las
## ~200 cajas de colisión contra cada una de las ~360 celdas de vereda: 72.000
## pruebas por ciudad, nueve ciudades, al construir.
func _indexar(obstaculos: Array) -> Dictionary:
	var b: Dictionary = {}
	for o in obstaculos:
		if not (o is AABB):
			continue
		var caja: AABB = o
		var x0: int = int(floorf(caja.position.x / CELDA_BUCKET))
		var z0: int = int(floorf(caja.position.z / CELDA_BUCKET))
		var x1: int = int(floorf((caja.position.x + caja.size.x) / CELDA_BUCKET))
		var z1: int = int(floorf((caja.position.z + caja.size.z) / CELDA_BUCKET))
		for cz in range(z0, z1 + 1):
			for cx in range(x0, x1 + 1):
				var k: Vector2i = Vector2i(cx, cz)
				if not b.has(k):
					b[k] = []
				(b[k] as Array).append(caja)
	return b


func _dentro_de_un_edificio(buckets: Dictionary, x: float, z: float) -> bool:
	var cx: int = int(floorf(x / CELDA_BUCKET))
	var cz: int = int(floorf(z / CELDA_BUCKET))
	var sonda := AABB(Vector3(x - HOLGURA, -1000.0, z - HOLGURA),
		Vector3(HOLGURA * 2.0, 2000.0, HOLGURA * 2.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var lista: Variant = buckets.get(Vector2i(cx + dx, cz + dz), [])
			if not (lista is Array):
				continue
			for o in (lista as Array):
				if (o as AABB).intersects(sonda):
					return true
	return false


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func props_por_id() -> Array[String]:
	return _ids


func capacidad_capa() -> int:
	if _capas.is_empty():
		return 0
	var k0: Array = _capas[0]
	return 0 if k0.is_empty() else (k0[0] as PisoDecoracion).capacidad


func altura_max() -> float:
	return _altura_max


func capas_totales() -> int:
	var n: int = 0
	for c in _capas:
		n += (c as Array).size()
	return n


## El plano de la calle: dónde quedó cada prop, en orden. Es lo que compara el
## test para probar que dos ciudades iguales dan la misma calle y dos
## ciudades distintas dan calles distintas.
func plano() -> Array[Transform3D]:
	return _plano


## LAS PIEZAS del prop `puesto` (el índice de `plano()`), ya compuestas: es lo
## mismo que escribe `PisoDecoracion.poner` en `_colocar`, con el mismo
## `MallasDecoracion.componer`.
##
## POR QUÉ HACE FALTA Y POR QUÉ NO BASTA `plano()`: el ancla de un prop se
## calculaba bien y el error estaba en la COMPOSICIÓN, o sea en las piezas. Un
## test que midiera el ancla daba verde con la farola entera a 169 m de altura:
## el dato que se guardaba era el correcto y el que se dibujaba, no. Igual que
## con el `MultiMesh`, esto no se lee del búfer (en headless
## `get_instance_transform` devuelve identidad): es el mismo cálculo en CPU.
func piezas_de_prop(puesto: int) -> Array[Transform3D]:
	var salida: Array[Transform3D] = []
	if puesto < 0 or puesto >= _plano.size() or puesto >= _slots.size():
		return salida
	var locales: Array = _locales[_slots[puesto]]
	for p in locales.size():
		salida.append(MallasDecoracion.componer(
			locales[p] as Transform3D, _plano[puesto]))
	return salida
