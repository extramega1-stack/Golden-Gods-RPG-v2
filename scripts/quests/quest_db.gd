class_name QuestDB
extends RefCounted
## Catálogo de misiones: carga `res://data/quests.json` UNA sola vez y lo
## cachea.
##
## Mismo patrón que NpcDB/TiendaDB (fases 6/7): solo LEE el JSON;
## `cargar()` es idempotente. Las misiones son datos puros; la lógica de
## estados vive en QuestLog (fase 8).

static var _cache: Dictionary = {}
static var _cargado: bool = false
## Los ids que vinieron de `data/quests.json`, en el orden DECLARADO del
## archivo. Es lo que separa "el catálogo escrito a mano" de "el catálogo
## más lo que la rotación registró hoy": `ids()` devuelve los dos (es lo que
## necesita el juego), y `ids_de_archivo()` solo el primero.
static var _ids_de_archivo: Array[String] = []
## La rotación vigente que se registró por última vez, como clave
## "día|semana|ciclo". Vacía = todavía no se registró ninguna. Sirve para no
## re-registrar lo mismo en cada llamada (que sería trabajo por frame) y para
## notar el cambio de día.
static var _rotacion_clave: String = ""


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	var texto: String = FileAccess.get_file_as_string("res://data/quests.json")
	if texto == "":
		push_warning("[QuestDB] no se pudo leer res://data/quests.json")
		return
	# parse_string retorna Variant: NUNCA `:=` aquí (warning como error).
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		push_warning("[QuestDB] quests.json no es un diccionario JSON válido")
		return
	var lista: Array = datos.get("quests", [])
	for entrada in lista:
		if not (entrada is Dictionary):
			continue
		var quest: Dictionary = entrada
		var quest_id: String = str(quest.get("id", ""))
		if quest_id == "":
			continue
		if _cache.has(quest_id):
			push_warning("[QuestDB] id duplicado en quests.json: %s" % quest_id)
			continue
		_cache[quest_id] = quest
		_ids_de_archivo.append(quest_id)


##
## SIN `existe()` LA ROTACIÓN DIARIA NO EXISTE, y es un bug que llevaba tiempo.
##
## `obtener()` llama a `_sincronizar_rotacion()` antes de leer, y `obtener()` es
## el camino normal. `existe()` NO la llamaba: miraba el `_cache` crudo. Las
## misiones diarias son EFIMERAS — su id lleva la fecha (`dia_d020728_...`) y se
## generan en runtime, no están en `data/quests.json`. Así que antes de la
## sincronización `_cache` no las tiene y `existe()` decía `false` para una
## misión que el juego estaba ofreciendo.
##
## El síntoma era `test_contenido_ngplus` en rojo con la cadena completa
## (disponible → se acepta → llega a lista → se entrega → queda entregada), y el
## detalle "bloqueada": el `QuestLog` no encontraba la misión que el propio
## sistema de rotación le acababa de generar. Un test que depende de la fecha se
## rompe solo al cambiar el día, y por eso el rojo aparecía sin que nadie
## hubiera tocado nada.
static func existe(quest_id: String) -> bool:
	_sincronizar_rotacion()
	return _cache.has(quest_id)


static func obtener(quest_id: String) -> Dictionary:
	_sincronizar_rotacion()
	var quest: Variant = _cache.get(quest_id, {})
	if quest is Dictionary:
		return quest
	return {}


static func ids() -> Array[String]:
	_sincronizar_rotacion()
	var resultado: Array[String] = []
	for k in _cache:
		resultado.append(str(k))
	return resultado


## Los ids DECLARADOS en `data/quests.json`, en el orden del archivo, sin las
## misiones que la rotación registró en runtime.
##
## POR QUÉ EXISTE ESTA SEGUNDA PUERTA: `ids()` mezcla las dos cosas, porque es
## lo que necesita el juego (el panel tiene que listar también las diarias).
## Pero un test que cuenta el catálogo NO quiere el total: quiere afirmar que
## las 56 misiones escritas están y que no se encogieron. Con `ids()` ese
## número dependería de qué día es y de cuántas diarias hay declaradas, o sea
## sería un número frágil que además no dice lo que el test quiere decir. Con
## `ids_de_archivo()` el número es estable y el aserto significa algo.
static func ids_de_archivo() -> Array[String]:
	cargar()
	return _ids_de_archivo.duplicate()


## Mete una MISIÓN CONCRETA en el catálogo en runtime. Es la puerta por la
## que entran las diarias y las semanales, que no pueden estar en el JSON
## porque su id depende de la fecha.
##
## Un id ya presente SOLO se pisa si lo que llega es efímero (una rotación):
## el bloque de `quests.json` manda sobre el catálogo y no se toca desde
## runtime. La condición es la inversa de la del `cargar` de siempre (que
## AVISA ante un duplicado), y es a propósito: la rotación re-registra las
## mismas ids cada vez que cambia el día, y un aviso por cada una en cada
## cambio sería ruido. Devuelve si la misión quedó en el catálogo.
static func registrar_en_runtime(quest: Dictionary) -> bool:
	var quest_id: String = str(quest.get("id", ""))
	if quest_id == "":
		return false
	if (quest.get("objetivos", []) as Array).is_empty():
		push_warning("[QuestDB] misión sin objetivos: %s" % quest_id)
		return false
	if _cache.has(quest_id) and not es_efimera(quest_id):
		return false
	_cache[quest_id] = quest
	return true


## Registra la rotación vigente del día, si cambió. Lo llaman `existe()`,
## `obtener()` y `ids()`, que son las tres puertas por las que entra el resto
## del juego al catálogo.
##
## El "si cambió" es lo que la hace barata: la clave es un string corto con
## día, semana y ciclo, y mientras no cambie no se hace NADA. Cambia al
## cruzar la medianoche o al prestigiar, que son los dos momentos en los que
## la rotación tiene que cambiar de verdad. Nunca se borra la rotación
## anterior: el catálogo crece, `vigente()` la marca como vencida y el
## `QuestLog` deja de ofrecerla. Así una misión a la que el jugador aceptó
## ayer no desaparece de su panel a medianoche.
static func _sincronizar_rotacion() -> void:
	# Primero el JSON: la rotación se REGISTRA SOBRE el catálogo, así que
	# registrar antes de cargar escribiría sobre un `_cache` vacío y el
	# `cargar` de después no las vería.
	cargar()
	var clave: String = RotacionDiaria.clave_vigente(EstadoNgPlus.ciclo_en_juego())
	if clave == _rotacion_clave:
		return
	_rotacion_clave = clave
	for m in RotacionDiaria.misiones_vigentes(EstadoNgPlus.ciclo_en_juego()):
		registrar_en_runtime(m)


## ¿La rotación del catálogo es la del día (y semana) de HOY, y la del ciclo
## que se está jugando? Lo decide el DATO `vence_dia` (el día) y
## `rotacion_ciclo` (la vuelta), con dos comparaciones: sin mirar el tipo, sin
## parsear el id y sin una lista de ids vencidos que mantener.
##
## LAS DOS MITADES HACEN FALTA LAS DOS. Con el día solo, prestigiar a media
## sesión dejaba vivas las diarias de la vuelta anterior junto a las nuevas y
## el jugador veía el doble de encargos de los que le tocan. Con el ciclo
## solo, cruzar la medianoche dejaba las de ayer. Esta función es el filtro
## de las dos, y es la que hace que "vigente" signifique "te toca a ti".
static func vigente(quest_id: String) -> bool:
	var q: Dictionary = obtener(quest_id)
	if not es_efimera(quest_id):
		return true
	if maxi(0, int(q.get("vence_dia", 0))) < RotacionDiaria.dia_hoy():
		return false
	return int(q.get("rotacion_ciclo", 0)) == EstadoNgPlus.ciclo_en_juego()


## Forcea el re-registro de la rotación. Lo usan los tests (que cambian la
## fecha y el ciclo a propósito) y el reinicio del NG+.
static func sincronizar_rotacion() -> void:
	_rotacion_clave = ""


## ¿Es una misión de ROTACIÓN (diaria o semanal)? Sale del DATO `efimera` que
## pone `RotacionDiaria`, no del prefijo del id: el prefijo es una convención
## y la convención se equivoca; el campo no.
static func es_efimera(quest_id: String) -> bool:
	var quest: Variant = _cache.get(quest_id, {})
	if quest is Dictionary:
		return bool((quest as Dictionary).get("efimera", false))
	return false


## ¿El id es DE UNA ROTACIÓN, esté o no en el catálogo ahora?
##
## Hace falta el segundo caso: una partida guardada ayer tiene ids
## `dia_d000738_...` en su bloque "misiones", y hoy, en un proceso recién
## arrancado, esos ids NO están en el catálogo (solo se registran los de hoy).
## Sin esta función, cargar esa partida soltaría un `push_warning` por cada
## diaria vencida — y no sería un bug: sería lo esperado. Una diaria que ya no
## existe no puede romper la carga, pero ensuciar la consola con avisos que
## nadie va a saber explicar sí lo parece.
##
## El prefijo es lo único disponible cuando el id no está en el catálogo, y
## para eso sí sirve: distingue "misión normal" de "misión que tenía fecha".
static func es_id_de_rotacion(quest_id: String) -> bool:
	if es_efimera(quest_id):
		return true
	return quest_id.begins_with(RotacionDiaria.PREFIJO_DIARIA) \
			or quest_id.begins_with(RotacionDiaria.PREFIJO_SEMANAL)


## ¿La misión se puede OFRECER ahora? Reúne las dos reglas de disponibilidad
## que son de contenido y no de cadena: el ciclo de NG+ y la vigencia de la
## rotación. Las dos salen del dato; la del `requiere` la trae `estado()`.
static func ofertable(quest_id: String, ciclo: int) -> bool:
	return disponible_en_ciclo(quest_id, ciclo) and vigente(quest_id)


## Lore de una misión (fase 9): 1–3 líneas de texto narrativo desde
## `data/quests.json`. Mismo patrón que el resto de campos: "" si la
## misión no existe o no declara lore.
static func lore(quest_id: String) -> String:
	return str(obtener(quest_id).get("lore", ""))


## Prerrequisito de cadena (fase 22): id de la misión que debe estar
## "entregada" para que esta esté disponible. "" = sin prerrequisito.
static func requiere(quest_id: String) -> String:
	return str(obtener(quest_id).get("requiere", ""))


# --- NG+ (contenido de fin de partida) ----------------------------------
#
# El desbloqueo por ciclo de NG+ es DATO, no código: el arquetipo de misión
# declara `ngplus_ciclo` (desde qué vuelta aparece) y el sistema lo consulta.
# Estas funciones son las ÚNICAS que leen ese campo, y el `QuestLog` solo las
# consulta. No hay un `if` por acto, ni por vuelta, ni una lista de ids: se
# declara una cadena nueva en el JSON y el sistema la ofrece sola.
#
# LO QUE NO HAY, Y POR QUÉ (`ngplus_ciclo_hasta`): una ventana que retira
# contenido. Se implementó y se descartó. La razón es que el NG+ se abre pero
# NO se cierra: el ciclo 5 tiene que traer lo del 1, lo del 2, lo del 3 y lo
# del 4, todo junto, y no una lista que se vacía. La novedad la ponen las
# diarias y las semanales, que cambian de semilla cada día y en cada prestige,
# que es donde tiene que estar: un campo de "hasta qué ciclo" sobre misiones
# fijas solo servía para quitarle cosas al jugador.

## Desde qué ciclo de NG+ aparece la misión. 0 = no es de NG+ y aparece desde
## el principio (las 41 misiones del bloque 8–22, que no declaran nada).
static func ngplus_ciclo(quest_id: String) -> int:
	return maxi(0, int(obtener(quest_id).get("ngplus_ciclo", 0)))


## ¿La misión es contenido de NG+? Lo que hace que las 15 de NG+ se puedan
## contar, filtrar y premiar aparte de las 41 del juego base.
static func es_ngplus(quest_id: String) -> bool:
	return ngplus_ciclo(quest_id) > 0


## El acto al que pertenece la cadena (1..5). Lo declaran las 15 de NG+ y
## ninguna de las 41 base. 0 = sin acto.
static func acto_ngplus(quest_id: String) -> int:
	return maxi(0, int(obtener(quest_id).get("ngplus_acto", 0)))


## ¿Está disponible esta misión en el ciclo de NG+ `ciclo`? La regla, entera
## y en un solo sitio:
##
## - si no declara `ngplus_ciclo` → SIEMPRE disponible. Las 41 misiones del
##   juego base no cambian de comportamiento con el NG+, y esto es lo que lo
##   garantiza: añadir contenido no puede romper lo que ya funcionaba.
## - si lo declara → disponible desde ese ciclo, y para siempre (el NG+ abre,
##   no cierra; ver la nota de arriba sobre `ngplus_ciclo_hasta`).
static func disponible_en_ciclo(quest_id: String, ciclo: int) -> bool:
	var desde: int = ngplus_ciclo(quest_id)
	return desde <= 0 or ciclo >= desde


## Todas las misiones de NG+ disponibles en el ciclo `ciclo`, en el orden
## DECLARADO del JSON. La usa el test y la UI: "qué hay para hacer en esta
## vuelta" sale del dato, no de una lista en el código.
static func ids_ngplus_de_ciclo(ciclo: int) -> Array[String]:
	var salida: Array[String] = []
	for qid in ids():
		if es_ngplus(qid) and disponible_en_ciclo(qid, ciclo):
			salida.append(qid)
	return salida


## Los ids de las misiones de NG+ de un acto, en orden declarado. Los usa
## `Trofeos` para saber si un acto está COMPLETO (todas las suyas
## entregadas) sin saber cuántas son.
static func ids_ngplus_de_acto(acto: int) -> Array[String]:
	var salida: Array[String] = []
	for qid in ids():
		if es_ngplus(qid) and acto_ngplus(qid) == acto:
			salida.append(qid)
	return salida
