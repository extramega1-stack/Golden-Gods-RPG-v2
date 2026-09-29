class_name Vegetacion
extends Node3D
## Fase 70: la VEGETACIÓN del mundo abierto. Un anillo que sigue al jugador, con
## LOD por distancia, y NUNCA todo a la vez.
##
## POR QUÉ UN ANILLO Y NO UN BOSQUE: el mundo es de 36.864 u de lado y el
## presupuesto de VRAM del proyecto es 1 GB en una GTX 1660. Sembrar todo lo
## que hay sería o bien un bosque de cientos de miles de mallas (imposible) o
## bien un millón de slots de `MultiMesh` (peor: el buffer de transformaciones
## pesa 48 bytes por instancia, y un millón son 48 MB que no se pueden tocar ni
## por cerca en caliente). El anillo resuelve las dos: ~320 celdas y ~1.000
## transformaciones en total, reescritas de a 44 celdas por frame, y CERO
## asignaciones después de arrancar.
##
## POR QUÉ UN SLOT POR CELDA Y NO UNA NUBE: es la idea de `RejillaDecoracion`.
## El slot de una celda es su índice en el anillo, el anillo es un disco, y el
## disco tiene la MISMA cantidad de celdas este donde esté el jugador. La
## capacidad es entonces una constante que se reserva una vez. No hay
## diccionarios "celda -> slot", ni búsqueda libre, ni lista que mantener, y
## vaciar una celda es escribir un transform degenerado, no borrar un nodo.
##
## EL DETERMINISMO: qué especie cae en qué celda, con qué giro, con qué escala
## y de qué color sale de `DecoracionDB.dado(semilla, indice)`, con la semilla
## derivada de la POSICIÓN. Nunca un `rand`. Si fuera al revés, cargar un save
## reconstruye el mundo con el pasto en otros metros y el jugador no reconoce
## ni el claro por el que caminó ayer.
##
## LA ZONA SEGURA: dentro de `radio_zona_segura` (40 m, el mismo radio que
## vigilan `test_fase12_spawns` y `test_fase14_terreno`) NO se siembra nada que
## sea alto. La hierba y las flores sí: tapar la plaza de aparición con un árbol
## sería un bug de diseño, no de rendimiento.
##
## El material de una capa es el de la región donde está el CENTRO del anillo.
## Las regiones son de 3.000 u y el anillo de 140, así que en el caso normal
## todo el anillo es de una región; al cruzar una frontera el anillo entero se
## repinta con el material de la nueva (un `material_override` por capa, que es
## escribir un puntero, no crear nada).
##
## Uso (la demo lo instancia; la API es la de `GestorArboles`):
##   var v := Vegetacion.new()
##   v.fijar_terreno($Terreno)
##   add_child(v)
##   v.fijar_jugador($Player)

## Registro en `gg_system` (el mismo contrato que `GestorArboles`).
var system_id: StringName = &"vegetacion"

var terreno: Terreno = null
var jugador: Node3D = null

## `_capas[k]` es la lista de `PisoDecoracion` de la especie `_especies[k]`
## (una por parte de su forma). `_locales[k]` trae la transformación local ya
## calculada de cada parte: componer es multiplicar, no recalcular.
var _capas: Array = []
var _locales: Array = []
var _especies: Array[String] = []
## Qué sombra proyecta cada especie. Sale del dato: la hierba no proyecta
## (son 0.0001 del frame) y un árbol sí, porque un árbol sin sombra se ve
## pegado al suelo como una calcomanía.
var _sombras: Array[bool] = []

## Celdas del anillo actual, en orden estable. `i` es el slot de la celda.
var _celdas: Array[Vector2i] = []
var _cabeza: int = 0
var _celda_actual: Vector2i = Vector2i(2147483647, 2147483647)
var _zona_actual: String = ""
var _origen_replan: Vector3 = Vector3.ZERO
var _reloj: float = 0.0
var _anillo_listo: bool = false
## Cuántas veces se replantó el anillo. Lo mira el test.
var _replanteos: int = 0
## Triángulos del anillo con TODAS las celdas sembradas (el peor caso posible,
## que la densidad del dato nunca alcanza). Lo mira el test.
var _triangulos_peor_caso: int = 0


func _ready() -> void:
	DecoracionDB.cargar()
	_construir_capas()
	set_process(terreno != null and jugador != null)


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func fijar_terreno(t: Terreno) -> void:
	terreno = t
	set_process(t != null and jugador != null)


func fijar_jugador(j: Node3D) -> void:
	jugador = j
	set_process(j != null and terreno != null)
	if j != null and terreno != null:
		replantar_anillo()


## Reconstruye el anillo entero AHORA, de una pasada. Los tests la llaman
## directo para no depender de frames; el juego usa el camino repartido.
func replantar_anillo() -> void:
	if jugador == null or not is_instance_valid(jugador):
		return
	var p: Vector3 = jugador.global_position
	_celda_actual = RejillaDecoracion.celda_de(p.x, p.z, DecoracionDB.paso())
	_origen_replan = p
	_preparar_anillo()
	_drenar(_celdas.size())


# ---------------------------------------------------------------------------
# El anillo
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _celdas.is_empty():
		return
	if _cabeza >= _celdas.size() and _anillo_listo:
		# Anillo terminado: solo hay que enterarse de que el jugador se movió.
		_reloj -= delta
		if _reloj > 0.0:
			return
		_reloj = 0.25
		if not _merece_replanter():
			return
		_celda_actual = RejillaDecoracion.celda_de(jugador.global_position.x,
			jugador.global_position.z, DecoracionDB.paso())
		_origen_replan = jugador.global_position
		_preparar_anillo()
		_replanteos += 1
	_drenar(DecoracionDB.celdas_por_frame())
	if _cabeza >= _celdas.size() and _anillo_listo:
		for c in _capas:
			for p in (c as Array):
				(p as PisoDecoracion).encender()


## Replantera solo si el jugador se movió lo suficiente. Sin este margen, uno
## que camina en zigzag sobre una frontera de celda replantaría el anillo cada
## tres pasos: 1.000 escrituras de buffer cada 5 metros.
func _merece_replanter() -> bool:
	if jugador == null or not is_instance_valid(jugador):
		return false
	if not _anillo_listo:
		return true
	return jugador.global_position.distance_to(_origen_replan) \
		>= DecoracionDB.reconstruir_tras_m()


## Calcula las celdas del anillo y deja las capas apagadas antes de sembrar.
##
## POR QUÉ NO SE VACÍA LA CAPA ACÁ: eso son `capacidad` escrituras de buffer
## (16 capas × 317 celdas ≈ 5.000) en un SOLO frame, cada vez que el jugador
## cruza una frontera, y es exactamente el tiron de frame que §9.5 prohíbe. Como
## la capacidad ES la cantidad de celdas del anillo, cada celda pisa TODOS sus
## slots durante el drenaje (con su pieza o con el transform degenerado), así
## que al terminar no queda nada del anillo viejo. Lo único que hay que resetear
## es el contador, y para eso está `PisoDecoracion.recountar()`.
func _preparar_anillo() -> void:
	_celdas = RejillaDecoracion.celdas(_celda_actual, DecoracionDB.paso(),
		DecoracionDB.radio_lejos())
	_cabeza = 0
	_anillo_listo = false
	_reloj = 0.0
	var c: Vector2 = RejillaDecoracion.centro_de(_celda_actual, DecoracionDB.paso())
	_repintar_si_cambio_de_zona(DecoracionDB.zona_en(c.x, c.y))
	# La capa se apaga mientras se reescribe: mezclar el anillo viejo con el
	# nuevo durante ocho frames se ve peor que un frame de pantalla vacía.
	for c2 in _capas:
		for p in (c2 as Array):
			(p as PisoDecoracion).apagar()
			(p as PisoDecoracion).recountar()


## Escribe hasta `max_celdas` celdas. Cada celda escribe una pieza por especie
## que le toca; el resto de los slots quedan en el degenerado que puso
## `_preparar_anillo`.
func _drenar(max_celdas: int) -> void:
	var n: int = 0
	while n < max_celdas and _cabeza < _celdas.size():
		_sembrar(_celdas[_cabeza], _cabeza)
		_cabeza += 1
		n += 1
	if _cabeza >= _celdas.size():
		_anillo_listo = true


# ---------------------------------------------------------------------------
# La siembra
# ---------------------------------------------------------------------------

## Escribe una celda COMPLETA: todas las capas, con su pieza o con el
## transform degenerado. Que sea TODAS y no solo las que tocaban es lo que
## hace que el anillo viejo desaparezca sin un `vaciar()` de 5.000 escrituras:
## cada celda pisa su slot en cada capa, y al terminar el drenaje no queda nada.
##
## NO HAY CÁLCULO ACÁ: solo se reparte lo que devuelve `_grupos_de_celda`. La
## decisión (zona segura, LOD, dado), el transform de la pieza y la composición
## con las partes viven en esa función, que es la misma que mide el test. Cuando
## `_sembrar` tenía su propia copia de la decisión, un test verde no probaba
## nada: las dos copias se podían desincronizar calladitas.
func _sembrar(celda: Vector2i, slot: int) -> void:
	var grupos: Array = _grupos_de_celda(celda)
	for k in grupos.size():
		var partes: Array = (grupos[k] as Dictionary)["partes"]
		var capas_k: Array = _capas[k]
		for p in capas_k.size():
			if p < partes.size():
				(capas_k[p] as PisoDecoracion).poner(slot,
					partes[p] as Transform3D)
			else:
				(capas_k[p] as PisoDecoracion).borrar(slot)


## Lo que hay en UNA celda, especie por especie y en el orden de `_especies`.
## Cada elemento es `{especie, ancla, partes}`:
## - `ancla` es el transform de la pieza ENTERA (dónde cae, con qué giro y a qué
##   escala). Su `origin.y` es el suelo menos el `hundir` de la especie.
## - `partes` son los transform de cada parte de su forma, ya compuestos con
##   `MallasDecoracion.componer`. Es lo que se escribe en el `MultiMesh`.
## Un grupo con `partes` vacío es una especie que no cabe ahí (zona segura, LOD
## o el dado), y la celda escribe el degenerado en sus capas.
func _grupos_de_celda(celda: Vector2i) -> Array:
	var grupos: Array = []
	var paso: float = DecoracionDB.paso()
	var centro: Vector2 = RejillaDecoracion.centro_de(celda, paso)
	var semilla: int = DecoracionDB.semilla(centro.x, centro.y)
	var zona: Dictionary = DecoracionDB.zona_resuelta(centro.x, centro.y)
	for k in _especies.size():
		var tipo: String = _especies[k]
		var partes: Array = []
		var ancla := Transform3D.IDENTITY
		if _cabe_aqui(tipo, k, centro, zona, semilla):
			ancla = _transform_de(centro, semilla, k, DecoracionDB.vegetal(tipo),
				paso)
			for local in (_locales[k] as Array):
				partes.append(MallasDecoracion.componer(
					local as Transform3D, ancla))
		grupos.append({"especie": tipo, "ancla": ancla, "partes": partes})
	return grupos


## El dado de la celda. La probabilidad sale del dato: `peso / uno_cada`, con
## el peso de la ZONA (lo que hace que el Bosque Hondo sea un bosque y la Ceniza
## y Forja un campo de piedra) y la frecuencia de la ESPECIE.
func _pasa_el_dado(semilla: int, k: int, zona: Dictionary, tipo: String,
		v: Dictionary) -> bool:
	var peso: float = DecoracionDB.peso_de(zona, tipo)
	if peso <= 0.0:
		return false
	var prob: float = clampf(peso / float(DecoracionDB.uno_cada_de(zona, tipo)),
		0.0, 1.0)
	if prob >= 1.0:
		return true
	# El índice 1000 + k separa una especie de otra dentro de la MISMA celda: el
	# hash depende del par (semilla, índice), no de un contador que avanzaría con
	# el orden de las filas.
	return DecoracionDB.unidad(semilla, 1000 + k) < prob


## El transform de la pieza: dónde cae (jitter DENTRO de la celda, no en la
## grilla entera — por eso dos matas vecinas no salen en el mismo punto), cómo
## gira y a qué escala.
##
## LA Y SON DOS COSAS SUMADAS y las dos importan:
## - `terreno.altura_en(x, z)`: la altura DEL SUELO en el metro exacto donde cae
##   la planta (con su jitter ya aplicado). Es la Y del mundo, la misma que
##   pisa el jugador, la que leen `Arbol` y `Veta`.
## - `-hundir`: cuánto se hunde la base. NO es decorativo: una planta cuya base
##   solo ROZA el suelo se ve pegada con cinta, y en una pendiente la esquina
##   que da al declive queda en el aire. Sale del dato (`hundir` de la especie),
##   nunca de un número escrito acá.
func _transform_de(centro: Vector2, semilla: int, k: int, v: Dictionary,
		paso: float) -> Transform3D:
	var i: int = 2000 + k * 8
	var margen: float = paso * 0.40
	var x: float = centro.x + DecoracionDB.entre(semilla, i + 1, -margen, margen)
	var z: float = centro.y + DecoracionDB.entre(semilla, i + 2, -margen, margen)
	var y: float = -_hundir_de(v)
	if terreno != null and is_instance_valid(terreno):
		y += terreno.altura_en(x, z)
	# Un poco de inclinación: pasto y ramas que salen perfectamente verticales
	# se leen como una SERIE de postes. Es el detalle de un centavo que separa
	# "vegetación" de "vegetación posta".
	var inc: float = float(v.get("inclinacion", 0.15))
	var euler := Vector3(
		DecoracionDB.entre(semilla, i + 3, -inc, inc),
		DecoracionDB.entre(semilla, i + 4, 0.0, TAU),
		DecoracionDB.entre(semilla, i + 5, -inc, inc))
	var esc: Array = v.get("escala", [0.8, 1.4])
	var s: float = DecoracionDB.entre(semilla, i + 6,
		float(esc[0]) if esc.size() > 0 else 0.8,
		float(esc[1]) if esc.size() > 1 else 1.4)
	return Transform3D(Basis.from_euler(euler).scaled(Vector3.ONE * s),
		Vector3(x, y, z))


## Cuánto se hunde la base de una especie. Sale del dato, con un piso de
## `HUNDIR_MINIMO` para que ninguna planta nueva pueda declararse flotante por
## olvido: escribir `"hundir": 0` es el error, y el error de este archivo es
## invisible en el juego (una flor a 6 cm del suelo parece bien) y evidente en
## el test.
const HUNDIR_MINIMO: float = 0.12


func _hundir_de(v: Dictionary) -> float:
	return maxf(HUNDIR_MINIMO, float(v.get("hundir", 0.0)))


# ---------------------------------------------------------------------------
# Las capas
# ---------------------------------------------------------------------------

## Una capa por (especie, parte de su forma). Todas comparten la primitiva
## unidad de la Biblioteca, así que el mundo entero usa cinco `Mesh` para toda
## la vegetación.
func _construir_capas() -> void:
	_capas.clear()
	_locales.clear()
	_especies.clear()
	_sombras.clear()
	_triangulos_peor_caso = 0
	var slots: int = RejillaDecoracion.capacidad(DecoracionDB.paso(),
		DecoracionDB.radio_lejos())
	for tipo in DecoracionDB.vegetales():
		var v: Dictionary = DecoracionDB.vegetal(tipo)
		var partes: Array = DecoracionDB.partes(str(v.get("forma", "")))
		if partes.is_empty():
			push_warning("[Vegetacion] especie sin forma: " + tipo)
			continue
		var capas_k: Array = []
		var locales_k: Array = []
		for p in partes:
			var parte: Dictionary = p
			var malla: Mesh = MallasDecoracion.primitiva(str(parte.get("prim", "caja")))
			if malla == null:
				continue
			var piso := PisoDecoracion.new()
			piso.name = "%s_%d" % [tipo, capas_k.size()]
			piso.configurar(malla, null, slots)
			capas_k.append(piso)
			locales_k.append(MallasDecoracion.local_de(parte))
			_triangulos_peor_caso += piso.triangulos_maximos()
		if capas_k.is_empty():
			continue
		_sombras.append(bool(v.get("sombra", false)))
		_especies.append(tipo)
		_capas.append(capas_k)
		_locales.append(locales_k)
	for k in _especies.size():
		for c in (_capas[k] as Array):
			add_child(c)
	# El material depende de la zona, que se resuelve en `_preparar_anillo`.
	_repintar_si_cambio_de_zona("")


## Cambia el `material_override` de todas las capas si el anillo pasó a otra
## región. Es escribir un puntero por capa: cero materiales nuevos, cero texturas
## horneadas acá (las de la región las pidió la Biblioteca, que las cachea).
func _repintar_si_cambio_de_zona(zona_id: String) -> void:
	if zona_id == _zona_actual and _zona_actual != "":
		return
	_zona_actual = zona_id
	var zona: Dictionary = DecoracionDB.zona_por_id(zona_id)
	for k in _especies.size():
		var partes: Array = DecoracionDB.partes(str(
			DecoracionDB.vegetal(_especies[k]).get("forma", "")))
		var capas_k: Array = _capas[k]
		for p in capas_k.size():
			if p >= partes.size():
				continue
			var piso: PisoDecoracion = capas_k[p]
			piso.material_override = MallasDecoracion.material_vegetal(zona,
				str((partes[p] as Dictionary).get("tinte", "follaje")))
			if p == 0:
				piso.set_sombra(bool(_sombras[k]))


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func celdas_en_anillo() -> int:
	return _celdas.size()


func capacidad_capa() -> int:
	if _capas.is_empty():
		return 0
	var k0: Array = _capas[0]
	return 0 if k0.is_empty() else (k0[0] as PisoDecoracion).capacidad


func anillo_listo() -> bool:
	return _anillo_listo


func replanteos() -> int:
	return _replanteos


func pendientes() -> int:
	return _celdas.size() - _cabeza


func especies() -> Array[String]:
	return _especies


func capas_totales() -> int:
	var n: int = 0
	for c in _capas:
		n += (c as Array).size()
	return n


## Cuántas piezas hay puestas ahora mismo. El test lo usa para comprobar que la
## densidad sale del dato y no de un `for` que llena todo.
func piezas_puestas() -> int:
	var n: int = 0
	for c in _capas:
		for p in (c as Array):
			n += (p as PisoDecoracion).puestos
	return n


## El peor caso de triángulos del anillo completo. Con la densidad del dato
## nunca se llega; está para que el test lo compare con el presupuesto.
func triangulos_peor_caso() -> int:
	return _triangulos_peor_caso


## LO QUE HAY EN UNA CELDA, tal como se escribe en el búfer: un
## `{especie, ancla, partes}` por especie, con las partes ya compuestas. Es el
## MISMO `_grupos_de_celda` que usa `_sembrar`, no una copia: el test no puede
## dar verde midiendo una fórmula que el juego no usa.
##
## POR QUÉ NO SE LEE EL `MultiMesh`: el búfer vive en el RenderingServer, y en
## headless (rasterizador dummy) `get_instance_transform` devuelve identidad
## para todo. Un test que lo leyera daría verde con la vegetación entera flotando
## en el cielo. Esto es el mismo cálculo en CPU, así que mide la geometría que el
## rasterizador recibe.
func grupos_de_celda(celda: Vector2i) -> Array:
	return _grupos_de_celda(celda)


## Qué especie caería en una celda del mundo por el SOLO dado, sin el LOD ni la
## zona segura: es una función pura de la celda. El test la usa para comprobar
## que la misma celda da SIEMPRE la misma especie — la propiedad que hace que un
## save reconstruya el mundo igual.
func especie_en_celda(celda: Vector2i) -> String:
	var c: Vector2 = RejillaDecoracion.centro_de(celda, DecoracionDB.paso())
	var semilla: int = DecoracionDB.semilla(c.x, c.y)
	var zona: Dictionary = DecoracionDB.zona_resuelta(c.x, c.y)
	for k in _especies.size():
		var tipo: String = _especies[k]
		var v: Dictionary = DecoracionDB.vegetal(tipo)
		if v.is_empty():
			continue
		if _pasa_el_dado(semilla, k, zona, tipo, v):
			return tipo
	return ""


## Qué especie hay REALMENTE sembrada en una celda: el dado más el LOD y la
## zona segura, o sea exactamente la decisión que toma `_sembrar`. Que las dos
## coincided es lo que el test vigila: si el dado dijera una cosa y la siembra
## otra, el test de determinismo estaría probando la función equivocada.
func especie_sembrada(celda: Vector2i) -> String:
	var paso: float = DecoracionDB.paso()
	var c: Vector2 = RejillaDecoracion.centro_de(celda, paso)
	var semilla: int = DecoracionDB.semilla(c.x, c.y)
	var zona: Dictionary = DecoracionDB.zona_resuelta(c.x, c.y)
	for k in _especies.size():
		var tipo: String = _especies[k]
		if _cabe_aqui(tipo, k, c, zona, semilla):
			return tipo
	return ""


## LA DECISIÓN, en un solo lugar. `_sembrar` la usa para saber si escribe la
## pieza o el hueco, y `especie_sembrada` la usa para responder al test. Las
## dos caminos tienen que dar lo mismo: por eso es una función y no dos.
##
## El orden importa (zona segura, luego LOD, luego dado) solo por legibilidad:
## son tres `and` sin efectos secundarios, cualquiera de los tres puede cortar.
func _cabe_aqui(tipo: String, k: int, centro: Vector2, zona: Dictionary,
		semilla: int) -> bool:
	var v: Dictionary = DecoracionDB.vegetal(tipo)
	if v.is_empty():
		return false
	# La zona segura: nada ALTO dentro de los 40 m de la aldea inicial. Es la
	# misma regla que ya vigilan los tests de spawns y de terreno, y el motivo
	# es el mismo: el punto de aparición tiene que estar despejado. La hierba y
	# las flores sí pueden estar: tapan la mirada, no el paso.
	var r: float = DecoracionDB.radio_zona_segura()
	if r > 0.0 and DecoracionDB.es_tipo_alto(tipo) \
			and centro.length_squared() < r * r:
		return false
	# LOD: lo "cerca" (hierba, flores, juncos) no existe en el borde del anillo.
	# A 140 m un plantón de medio metro son dos píxeles: se ve como ruido, no
	# como vegetación, y ocuparía los mismos slots que un árbol que sí se lee.
	if str(v.get("alcance", "cerca")) == "cerca" and _lejos_del_jugador(centro):
		return false
	return _pasa_el_dado(semilla, k, zona, tipo, v)


func _lejos_del_jugador(centro: Vector2) -> bool:
	if jugador == null or not is_instance_valid(jugador):
		return false
	var dx: float = centro.x - jugador.global_position.x
	var dz: float = centro.y - jugador.global_position.z
	var r: float = DecoracionDB.radio_cerca()
	return dx * dx + dz * dz > r * r
