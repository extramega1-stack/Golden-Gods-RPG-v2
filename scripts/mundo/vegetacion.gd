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
## =========================================================================
## FASE 152 — EL PARPADEO AL MOVERSE. POR QUÉ ESTE ARCHIVO CAMBIÓ.
## =========================================================================
##
## El síntoma era "cada vez que me muevo todo parpadea". El diagnóstico
## (`tests/test_fase152_flicker.gd`, que camina al jugador 20 s y cuenta) dio
## estos números sobre el código anterior:
##
##     11 replantes · 173 frames de 1.200 con el anillo INVISIBLE · 2.790
##     escrituras al búfer por segundo
##
## Los 173 frames NO son un defecto de rendimiento: son 173 frames de pantalla
## VACÍA, y su forma lo dice todo. El mismo banco de pruebas, sobre el código de
## antes, mide estas ráfagas de anillo invisible dentro de los mismos 1.200
## frames:
##
##     [103, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7]
##
## 103 + 10 × 7 = 173. O sea:
##
## - UNA ráfaga de 103 frames (1,7 s) al empezar la sesión: el anillo NUNCA se
##   encendía hasta que el jugador caminaba 9 m. La causa eran dos `return`
##   tempranos en `_process` —los dos que miran el reloj de la replantación—
##   que saltaban el bucle de `encender()` que estaba más abajo. No era un
##   parpadeo: era un mundo sin pasto.
## - UNA ráfaga de 7 frames (117 ms) cada 9 m recorridos, o sea cada 1,5 s a
##   6 m/s: `_preparar_anillo` apagaba las 16 capas y `_drenar` tardaba 8 frames
##   en volver a llenarlas.
##
## El comentario que lo justificaba ("mezclar el anillo viejo con el nuevo se ve
## peor que un frame de pantalla vacía") estaba al revés: ocho frames de nada es
## peor que ocho frames con el borde del anillo atrasado, que es lo único que se
## ve mientras se rellena.
##
## TRES CAMBIOS, EN ORDEN DE IMPORTANCIA:
##
## (1) DOBLE BÚFER, Y LA CAPA NO SE APAGA NUNCA. Cada `PisoDecoracion` tiene
##     dos `MultiMesh`: el anillo nuevo se escribe en el de atrás, que nadie ve,
##     y al terminar se intercambia el puntero. Los dos anillos están completos
##     y correctos en todo momento, así que el intercambio no tiene un solo
##     frame de mezcla. Con eso, la pregunta "¿cuándo se apaga esta capa?"
##     tiene respuesta: nunca.
##
## (2) LA CORTA DE LA FRONTERA. Si el jugador no cruzó una frontera de celda,
##     el anillo nuevo es IDÉNTICO al que ya está en pantalla y no se escribe
##     NADA. Antes costaba 5.000 escrituras cada 9 m para no cambiar un píxel,
##     y ese es el caso real de quien camina en zigzag o se detiene. Las
##     escrituras por segundo del diagnóstico bajaron de 2.790 a 1.775 por esto
##     solo, y a 518 con la calidad en "Baja".
##
## (3) CERO ASIGNACIONES EN LA RUTA DE ESCRITURA. Antes, cada celda que se
##     sembraba armaba un `Array` de `Dictionary` (`_grupos_de_celda`) que se
##     tiraba a la basura en el mismo frame: 44 celdas × 6 especies = 264
##     contenedores por frame, en caliente, que es justo lo que §9.5 prohíbe. La
##     lista de celdas también era un `Array[Vector2i]` nuevo de 317 cajas cada
##     replantación. Ahora son `PackedInt32Array` reservados una vez, y
##     `_sembrar_slot` escribe directo al `MultiMesh`. `_grupos_de_celda` sigue
##     existiendo, pero solo la llaman los TESTS, que necesitan ver la decisión
##     sin escribir en la GPU.
##
## Y el LOD lleva HISTÉRESIS (`HISTERESIS_LOD`): una celda sembrada con su
## parte "cerca" no se retira hasta pasar `radio_cerca + H`, y una que no la
## tiene no la toma hasta bajar de `radio_cerca - H`. El `if` pelado de antes
## hacía que una mata de hierba a 51,9 m hiciera pop y a 52,1 m desaparece,
## cruzando la frontera una y otra vez al caminar en círculos.
##
## Uso (la demo lo instancia; la API es la de `GestorArboles`):
##   var v := Vegetacion.new()
##   v.fijar_terreno($Terreno)
##   add_child(v)
##   v.fijar_jugador($Player)

## Registro en `gg_system` (el mismo contrato que `GestorArboles`), para que
## `Opciones.aplicar_video()` le avise de un cambio de calidad sin rutas de
## nodo hardcodeadas.
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

## Celdas del anillo actual, en orden estable, en DOS buffers de enteros
## planos (no un `Array[Vector2i]`: un array de 317 vectores boxed es 317
## asignaciones cada vez que el jugador cruza una frontera). `i` es el slot de
## la celda.
var _celda_x: PackedInt32Array = PackedInt32Array()
var _celda_y: PackedInt32Array = PackedInt32Array()
var _n: int = 0
## El estado del LOD por slot (0 = la celda no tuvo su parte "cerca", 1 = sí).
## Es el pestillo de la histéresis: sin él, el radio pelado hace pop.
var _slot_cerca: PackedByteArray = PackedByteArray()
## Los slots a escribir de esta replantación, en orden. Se reservan una vez y
## se recorren con un cursor; `append` sobre un `PackedInt32Array` Realmente no
## reserva, pero `_n_pend` deja el invariante explícito.
var _pend: PackedInt32Array = PackedInt32Array()
var _n_pend: int = 0
var _cabeza: int = 0
var _celda_actual: Vector2i = Vector2i(2147483647, 2147483647)
## La celda del anillo que está EN PANTALLA. Es la que permite la CORTA: si el
## jugador no cruzó una frontera, el anillo nuevo es idéntico al que ya se ve
## y no se escribe nada. Sin esto, estar quieto costaba 5.000 escrituras cada
## 9 m para no cambiar un píxel.
var _celda_previa: Vector2i = Vector2i(2147483647, 2147483647)
var _zona_actual: String = ""
var _origen_replan: Vector3 = Vector3.ZERO
var _reloj: float = 0.0
var _anillo_listo: bool = false
## Cuántas veces se PUBLICÓ un anillo nuevo, o sea cuántas se llegaron a
## escribir y a intercambiar. NO cuenta los intentos: la corta de la frontera
## hace que many replantaciones no escreban nada, y un contador de intentos
## diría "replantaste 12 veces" cuando en pantalla hubo 7 anillos distintos.
## Lo mira `test_fase152_flicker`, que compara este número con las escrituras
## para ver que de las dos cosas la que importa es la segunda.
var _replanteos: int = 0
## Triángulos del anillo con TODAS las celdas sembradas (el peor caso posible,
## que la densidad del dato nunca alcanza). Lo mira el test.
var _triangulos_peor_caso: int = 0
## El PATRÓN del disco: los desplazamientos (dx, dz) de cada celda respecto del
## centro, en el MISMO orden que `RejillaDecoracion.celdas()`. Se calcula una
## vez por radio y no vuelve a cambiar, así que replantar es sumarle el centro
## celda a celda: 317 sumas enteras, cero asignaciones.
var _patron_dx: PackedInt32Array = PackedInt32Array()
var _patron_dz: PackedInt32Array = PackedInt32Array()
var _n_patron: int = 0
var _radio_patron: float = -1.0
## Con cuántas celdas se llenó cada uno de los dos búferes. El búfer de
## escritura es el que se veía hace dos replantaciones, así que el dato va por
## búfer: es lo que evita re-vaciar la corona que ya está vacía.
var _n_por_bufer: PackedInt32Array = PackedInt32Array([0, 0])
## Hay un intercambio de búfer esperando a que termine el drenaje. Es lo que
## impide intercambiar dos veces por frame cuando no se escribió nada: sin este
## flag, `_drenar` daba por hecho que había algo que publicar e iba volteando
## los búferes 60 veces por segundo, enseñando el anillo de dos replantaciones
## atrás en lugar del de ahora.
var _intercambio_pendiente: bool = false
var _capacidad: int = 0
## El interruptor del panel de opciones. Cuando está apagado el anillo entero
## sale de la imagen y el sistema deja de procesar: cero escrituras, cero
## parpadeo, y es la forma de "apagá una cosa a la vez" del diagnóstico
## hecha un ajuste del juego.
var _activo: bool = true

## Media banda muerta del LOD, en metros. Sin esto, una celda a 51,9 m hace
## pop y a 52,1 m desaparece, y cruzar la frontera en zigzag la enciende y la
## apaga cada dos pasos. Es el mismo motivo por el que un termostato tiene
## zona muerta.
const HISTERESIS_LOD: float = 6.0
## Qué tan corto es el anillo según la calidad. Menos celdas son menos
## escrituras por segundo, así que BAJAR la calidad baja el trabajo de verdad y
## no solo un número: es lo que el encargo pide del ajuste de calidad.
const ESCALA_RADIO_POR_CALIDAD: Array[float] = [0.5, 0.78, 1.0, 1.0]
## Cuántos slots se escriben por frame según la calidad. A calidad baja el
## presupuesto se DOBLA, porque lo que queda por hacer es chico y prefiero
## terminarlo en un frame que dejarlo a medias dos.
const ESCALA_PRESUPUESTO_POR_CALIDAD: Array[float] = [2.0, 1.5, 1.0, 1.0]


func _ready() -> void:
	DecoracionDB.cargar()
	_construir_capas()
	add_to_group(Systems.GRUPO)
	aplicar_calidad()


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func fijar_terreno(t: Terreno) -> void:
	terreno = t
	set_process(_activo and t != null and jugador != null)


func fijar_jugador(j: Node3D) -> void:
	jugador = j
	set_process(_activo and j != null and terreno != null)
	if j != null and terreno != null and _activo:
		replantar_anillo()


## Reconstruye el anillo entero AHORA, de una pasada. Los tests la llaman
## directo para no depender de frames; el juego usa el camino repartido, salvo
## el cambio de calidad, que sí es de una pasada porque si no el anillo se
## queda con el radio viejo hasta que el jugador camine 9 m.
func replantar_anillo() -> void:
	if jugador == null or not is_instance_valid(jugador):
		return
	var p: Vector3 = jugador.global_position
	_celda_actual = RejillaDecoracion.celda_de(p.x, p.z, DecoracionDB.paso())
	_origen_replan = p
	_preparar_anillo()
	_drenar(_n_pend)
	_encender()


## LO QUE PIDE `Opciones.aplicar_video()`. Tres cosas de una vez: el
## interruptor de la decoración, el radio que marca la calidad, y un replanteo
## forzado (si solo cambiara el radio, el anillo viejo se vería hasta el
## próximo movimiento del jugador, que es la clase de desajuste que se ve como
## parpadeo).
func aplicar_calidad() -> void:
	_activo = Opciones.booleano("vegetacion", true)
	set_process(_activo and terreno != null and jugador != null)
	if not _activo:
		for c in _capas:
			for p in (c as Array):
				(p as PisoDecoracion).apagar()
		return
	if _anillo_listo:
		_encender()
	if jugador != null and is_instance_valid(jugador) and terreno != null:
		replantar_anillo()


## El radio del anillo con la escala de la calidad. El dato (`radio_lejos`) es
## el máximo; la calidad decide cuánto de ese máximo se dibuja.
func radio_efectivo() -> float:
	var q: int = clampi(Opciones.entero("calidad", 2), 0, ESCALA_RADIO_POR_CALIDAD.size() - 1)
	return DecoracionDB.radio_lejos() * ESCALA_RADIO_POR_CALIDAD[q]


## Cuántos slots se escriben por frame. El dato es la base; la calidad lo
## escala para que el remainder del anillo no se reparta en cinco frames.
func celdas_por_frame() -> int:
	var q: int = clampi(Opciones.entero("calidad", 2), 0,
		ESCALA_PRESUPUESTO_POR_CALIDAD.size() - 1)
	return maxi(1, int(float(DecoracionDB.celdas_por_frame())
		* ESCALA_PRESUPUESTO_POR_CALIDAD[q]))


# ---------------------------------------------------------------------------
# El anillo
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _n == 0 or not _activo:
		return
	if _cabeza >= _n_pend and _anillo_listo:
		# Anillo al día: solo hay que enterarse de que el jugador se movió.
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
	_drenar(celdas_por_frame())


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


## Prepara la lista de celdas del anillo y encola los slots a escribir.
##
## POR QUÉ NO SE VACÍA NADA ACÁ: vaciar son `capacidad` escrituras (16 capas ×
## 317 celdas ≈ 5.000) en un SOLO frame, y además la lista nueva de celdas se
## armaba como un `Array[Vector2i]` nuevo: 317 cajas por replantación. Las dos
## cosas están prohibidas (§9.5) y las dos eran, además, parte de la causa del
## parpadeo.
##
## POR QUÉ SE ESCRIBE EL ANILLO ENTERO Y NO SOLO LA DIFERENCIA: se podría
## escribir solo los slots cuya celda cambió, y se hace para el caso de que la
## celda NO haya cambiado. Cuando la celda cambia, el disco se corrió: la celda
## del slot `i` es `centro + patrón[i]`, así que TODAS las celdas son otras y el
## delta da cero. Es la Ley de Torricelli del anillo, y no hay atajo que la
## esquive mientras el slot se numeré por posición en el patrón. La alternativa
## (una tabla celda→slot con reasignación) es un mapa hash de 300 entradas
## guardado en dos lados: cambiaría el número de escrituras, que nunca fue el
## problema, a costa de una estructura de datos que sí puede perder vegetación.
## Ver la nota de `escrituras` en `PisoDecoracion`.
##
## Y lo que hace que esto NO se vea mientras se escribe es el doble búfer de
## `PisoDecoracion`: estas escrituras van al búfer de atrás, y el de adelante
## —el que se ve— sigue siendo el anillo entero y correcto del-frame anterior.
func _preparar_anillo() -> void:
	_patron_si_hay_que_rehacerlo()
	_n = mini(_n_patron, _capacidad)
	for i in _n:
		_celda_x[i] = _celda_actual.x + _patron_dx[i]
		_celda_y[i] = _celda_actual.y + _patron_dz[i]
	_n_pend = 0
	# La CORTA: si la celda del jugador es la misma y el radio no cambió, el
	# anillo nuevo es IDÉNTICO al que ya se está viendo, así que no hay nada
	# que escribir y no hay nada que intercambiar. Es el caso de quien está
	# quieto, y de quien camina en zigzag dentro de una celda: los dos pagaban
	# 5.000 escrituras cada 9 m para no cambiar un píxel.
	if _celda_actual == _celda_previa and absf(radio_efectivo() - _radio_patron) < 0.001 \
			and _anillo_listo:
		return
	for i in _n:
		_pend[_n_pend] = i
		_n_pend += 1
	# Los slots que quedaron FUERA del anillo (solo pasa cuando la calidad
	# acortó el radio) hay que vaciarlos, o la corona vieja seguiría dibujada
	# en el aire. PERO SOLO en el búfer donde no se han vaciado ya: el búfer de
	# escritura es el que se veía hace dos replantaciones, y puede venir de una
	# calidad más alta con la corona llena. Por eso el conteo va POR BÚFER: sin
	# esto, calidad baja pagaba 317 escrituras por celda para dibujar 81.
	var w: int = _capa_0().bufer_de_escritura()
	if _n_por_bufer[w] > _n:
		for i in range(_n, _n_por_bufer[w]):
			_pend[_n_pend] = i
			_n_pend += 1
	_celda_previa = _celda_actual
	_n_por_bufer[w] = _n
	_intercambio_pendiente = true
	_cabeza = 0
	_anillo_listo = _n_pend == 0
	_reloj = 0.0
	var c: Vector2 = RejillaDecoracion.centro_de(_celda_actual, DecoracionDB.paso())
	_repintar_si_cambio_de_zona(DecoracionDB.zona_en(c.x, c.y))


## La primera capa de la lista. Todas las dieciséis comparten el MISMO búfer de
## escritura (el intercambio es por capa, pero el estado es el mismo para
## todas), así que una alcanza para preguntar.
func _capa_0() -> PisoDecoracion:
	if _capas.is_empty():
		return null
	var k0: Array = _capas[0]
	return null if k0.is_empty() else (k0[0] as PisoDecoracion)


## El patrón del disco solo cambia cuando cambia el RADIO, o sea cuando cambia
## la calidad. Recalcularlo son 317 restas a un array ya reservado: no asigna
## y no pasa por el camino caliente más de una vez por ajuste del panel.
func _patron_si_hay_que_rehacerlo() -> void:
	var r: float = radio_efectivo()
	if absf(r - _radio_patron) < 0.001:
		return
	_radio_patron = r
	_n_patron = RejillaDecoracion.patron(DecoracionDB.paso(), r,
		_patron_dx, _patron_dz)


## Escribe hasta `max_slots` slots del búfer de ATRÁS. Al terminar, lo
## intercambia: el anillo recién escrito pasa a ser el que se ve.
func _drenar(max_slots: int) -> void:
	var n: int = 0
	while n < max_slots and _cabeza < _n_pend:
		var slot: int = _pend[_cabeza]
		_sembrar_slot(slot, _celda_x[slot], _celda_y[slot])
		_cabeza += 1
		n += 1
	if _cabeza >= _n_pend:
		_anillo_listo = true
		if _intercambio_pendiente:
			_intercambio_pendiente = false
			_replanteos += 1
			_intercambiar_capas()


## Pasa a verse el búfer que se acaba de llenar, en las dieciséis capas de un
## tirón. Es el equivalente de video de un doble búfer: como los dos anillos
## están completos, no hay nada que mezclar.
func _intercambiar_capas() -> void:
	for c in _capas:
		for p in (c as Array):
			(p as PisoDecoracion).intercambiar()


## Enciende las capas. Se llama UNA vez, cuando el anillo se planta por
## primera vez; a partir de ahí la capa no se apaga nunca más. Encender algo
## que ya está encendido es tocar el nodo sin motivo, así que se pregunta.
func _encender() -> void:
	for c in _capas:
		for p in (c as Array):
			var piso: PisoDecoracion = p
			if not piso.visible:
				piso.encender()


# ---------------------------------------------------------------------------
# La siembra
# ---------------------------------------------------------------------------

## Escribe UN slot completo: todas las capas, con su pieza o con el transform
## degenerado, y deja el slot marcado como ocupado por esa celda.
##
## POR QUÉ NO USA `_grupos_de_celda`: esa función devuelve un `Array` de
## `Dictionary` por celda, uno por especie, y la ruta de escritura la needs
## 44 por frame en caliente. Son 264 contenedores por frame que el motor
## tiene que pedir al heap y devolver, que es la asignación en caliente que
## §9.5 prohíbe, y que además hace que el frame que reescribe el anillo sea el
## más lento. La decisión (zona segura, LOD, dado) y el transform salen de los
## MISMOS helpers que usa `_grupos_de_celda` — la duplicación que había antes
## de la fase 152 era una copia de la fórmula, no del recorrido.
func _sembrar_slot(slot: int, cx: int, cy: int) -> void:
	var paso: float = DecoracionDB.paso()
	var centro := Vector2((float(cx) + 0.5) * paso, (float(cy) + 0.5) * paso)
	var semilla: int = DecoracionDB.semilla(centro.x, centro.y)
	var zona: Dictionary = DecoracionDB.zona_resuelta(centro.x, centro.y)
	# El pestillo de la histéresis se lee del estado que tenía ESTE slot y se
	# escribe en el mismo lugar: es lo que evita que la frontera del LOD haga
	# pop al caminar en círculos.
	_slot_cerca[slot] = 1 if _dentro_del_lod(centro, _slot_cerca[slot] == 1) else 0
	for k in _especies.size():
		var tipo: String = _especies[k]
		var capas_k: Array = _capas[k]
		if not _cabe_aqui(tipo, k, centro, zona, semilla, _slot_cerca[slot] == 1):
			for p in capas_k.size():
				(capas_k[p] as PisoDecoracion).borrar(slot)
			continue
		var ancla := _transform_de(centro, semilla, k, DecoracionDB.vegetal(tipo), paso)
		var locales_k: Array = _locales[k]
		for p in capas_k.size():
			(capas_k[p] as PisoDecoracion).poner(slot,
				MallasDecoracion.componer(locales_k[p] as Transform3D, ancla))


## Lo que hay en UNA celda, especie por especie y en el orden de `_especies`.
## Cada elemento es `{especie, ancla, partes}`:
## - `ancla` es el transform de la pieza ENTERA (dónde cae, con qué giro y a qué
##   escala). Su `origin.y` es el suelo menos el `hundir` de la especie.
## - `partes` son los transform de cada parte de su forma, ya compuestos con
##   `MallasDecoracion.componer`. Es lo que se escribe en el `MultiMesh`.
## Un grupo con `partes` vacío es una especie que no cabe ahí (zona segura, LOD
## o el dado), y la celda escribe el degenerado en sus capas.
##
## ESTA ES LA COPIA QUE LOS TESTS MIDEN, Y LA RUTA DE ESCRITURA NO LA USA.
## Se conserva porque el test necesita ver la decisión sin escribir en la GPU,
## y porque `grupos_de_celda` es la referencia contra la que hay que comparar
## cuando algo se ve raro. Lo que NO se permite es que las dos se separen: la
## fórmula es `_cabe_aqui` + `_transform_de` + `MallasDecoracion.componer`, y las
## dos rutas llaman a esos tres. Lo que se DUPLICA es el recorrido (armar el
## `Array` de `Dictionary`), y ese solo existe para el test.
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
		if _cabe_aqui(tipo, k, centro, zona, semilla, false):
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
	_capacidad = RejillaDecoracion.capacidad(DecoracionDB.paso(),
		DecoracionDB.radio_lejos())
	_reservar_buffers()
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
			piso.configurar(malla, null, _capacidad)
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


## Los buffers del anillo, TODOS del tamaño de la capacidad y TODOS reservados
## acá. Después de esto, ni `_preparar_anillo` ni `_sembrar_slot` crean nada:
## escriben enteros y transformaciones en memoria que ya existe. La capacidad
## se calcula con el radio MÁXIMO (el del dato) aunque la calidad juegue con
## uno más corto: la reserva es fija y bajar la calidad no la toco.
func _reservar_buffers() -> void:
	_celda_x.resize(_capacidad)
	_celda_y.resize(_capacidad)
	_slot_cerca.resize(_capacidad)
	_pend.resize(_capacidad)
	_patron_dx.resize(_capacidad)
	_patron_dz.resize(_capacidad)
	_slot_cerca.fill(0)


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
	return _n


func capacidad_capa() -> int:
	return _capacidad


func anillo_listo() -> bool:
	return _anillo_listo


func replanteos() -> int:
	return _replanteos


func pendientes() -> int:
	return _n_pend - _cabeza


## Cuántos slots CAMBIARON en la última replantación. El test lo compara con
## la cantidad de celdas del anillo: si fueran iguales, el delta update no
## estaría haciendo nada y el arreglo sería solo cosmético.
func slots_rewrite() -> int:
	return _n_pend


## Cuántas capas están APAGADAS ahora mismo. El parpadeo del mundo abierto es
## este número llegando a 16: el anillo entero invisible. `test_fase152_flicker`
## camina al jugador y lo cuenta frame por frame, que es la única forma de
## Catch un parpadeo de ocho frames.
func capas_apagadas() -> int:
	var n: int = 0
	for c in _capas:
		for p in (c as Array):
			if not (p as PisoDecoracion).visible:
				n += 1
	return n


## Escrituras al `MultiMesh` que hicieron TODAS las capas juntas. Es el número
## que hay que comparar antes y después del arreglo: el flicker viene de
## escribir de más y de apagar la capa mientras se escribe.
func escrituras_totales() -> int:
	var n: int = 0
	for c in _capas:
		for p in (c as Array):
			n += (p as PisoDecoracion).escrituras
	return n


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
##
## El LOD se consulta SIN pestillo (`ya_esta = false`), que es el lado
## conservador de la banda muerta: una celda que todavía no tiene su parte
## "cerca" solo la toma si ya está claramente dentro. Es lo que ve un test que
## mira una celda suelta, sin historial, y por eso el otro lado de la banda se
## prueba en `_dentro_del_lod` directamente.
func especie_sembrada(celda: Vector2i) -> String:
	var paso: float = DecoracionDB.paso()
	var c: Vector2 = RejillaDecoracion.centro_de(celda, paso)
	var semilla: int = DecoracionDB.semilla(c.x, c.y)
	var zona: Dictionary = DecoracionDB.zona_resuelta(c.x, c.y)
	for k in _especies.size():
		var tipo: String = _especies[k]
		if _cabe_aqui(tipo, k, c, zona, semilla, false):
			return tipo
	return ""


## LA DECISIÓN, en un solo lugar. `_sembrar_slot` la usa para saber si escribe
## la pieza o el hueco, y `especie_sembrada` la usa para responder al test. Las
## dos caminos tienen que dar lo mismo: por eso es una función y no dos.
##
## El orden importa (zona segura, luego LOD, luego dado) solo por legibilidad:
## son tres `and` sin efectos secundarios, cualquiera de los tres puede cortar.
##
## `ya_esta` es el lado de la banda muerta del LOD que corresponde a esta celda
## en este slot. La ruta de escritura se lo pasa desde `_slot_cerca`; los tests,
## que miran una celda sin historial, pasan `false`.
func _cabe_aqui(tipo: String, k: int, centro: Vector2, zona: Dictionary,
		semilla: int, ya_esta: bool = false) -> bool:
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
	if str(v.get("alcance", "cerca")) == "cerca" \
			and not _dentro_del_lod(centro, ya_esta):
		return false
	return _pasa_el_dado(semilla, k, zona, tipo, v)


## LA HISTÉRESIS DEL LOD, que es lo que separa "LOD" de "parpadeo". La banda
## muerta va de `radio_cerca - HISTERESIS_LOD` a `radio_cerca + HISTERESIS_LOD`,
## y de qué lado se está lo dice el estado PREVIO del slot. Un `if` sobre
## `radio_cerca` solo no alcanza: al caminar, una celda cruzaría el radio
## una y otra vez y su hierba aparecería y desaparecería en el mismo segundo.
func _dentro_del_lod(centro: Vector2, ya_esta: bool) -> bool:
	if jugador == null or not is_instance_valid(jugador):
		return true
	var r: float = DecoracionDB.radio_cerca()
	var dx: float = centro.x - jugador.global_position.x
	var dz: float = centro.y - jugador.global_position.z
	var d2: float = dx * dx + dz * dz
	if ya_esta:
		# Está sembrada: solo se retira cuando se ALEJA de `r + H`.
		var ra: float = r + HISTERESIS_LOD
		return d2 <= ra * ra
	# No está sembrada: solo se toma cuando se ACERCA a `r - H`.
	var rb: float = maxf(0.0, r - HISTERESIS_LOD)
	return d2 <= rb * rb
