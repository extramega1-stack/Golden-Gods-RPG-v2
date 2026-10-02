class_name Trofeos
extends RefCounted
## Trofeos de FIN DE CONTENIDO. Cierre del "el contenido se acaba en el 70".
##
## POR QUÉ NO VAN EN `Hechos` (`data/hechos.json`), Y POR QUÉ NO EN
## `PanelNgPlus`: la pregunta la hacía el encargo, así que la respuesta
## corta es esta.
##
## `Hechos` son TALENTOS DE HABILIDAD (fase 59): cada uno declara
## `habilidad` + `tramo` y su estado se RECALCULA desde
## `habilidades.alcanza(...)` en cada `aplicar()`. Su unidad es "el jugador
## subió Tala al tramo 2". Un trofeo es otra cosa: "cerraste tres ciclos de
## NG+" no se deduce de ninguna habilidad, no tiene `tramo`, y su
## desbloqueo tiene que SOBREVIVIR al prestige (que es justo lo que borra la
## vuelta). Meter un trofeo en `Hechos` obligaría a inventarle un
## `habilidad`/`tramo` que no existe, o a meter un `if` de ciclo en
## `Hechos.aplicar()` — que es exactamente el "nada de `if` en GDScript" que
## el spec prohíbe (§9.4). Y `Hechos` es un `RefCounted` que se RECREA en
## `Player._ready()`: cualquier contador de "cuántas veces cerraste el ciclo"
## que viviera ahí se pondría a cero en cada carga de partida. Un trofeo que
## se pierde al guardar es peor que no tenerlo.
##
## POR QUÉ SÍ VIVEN AQUÍ Y NO DENTRO DE `PanelNgPlus`: `PanelNgPlus` es UI
## (§7.11: la UI solo lee, nunca escribe). Un trofeo que se gana tiene que
## GUARDARSE, y eso lo hace el sistema, no un `CanvasLayer`. El panel se
## limita a leer `Trofeos` y a repintarse con su señal.
##
## EL DATO MANDA: las condiciones viven en `data/ngplus_trofeos.json`, una
## entrada por trofeo. Añadir un trofeo es añadir un objeto a ese JSON;
## aquí no hay ni un número de condición, ni una lista de ids, ni un
## `match` por cada trofeo. Sólo hay un `match` POR TIPO DE CONDICIÓN, que
## es genérico y no se crece con el contenido.
##
## PURA salvo `contexto_actual()`: `evaluar()` recibe un `Contexto` y no toca
## nada más. Eso es lo que la hace testeable sin una partida.

const RUTA: String = "res://data/ngplus_trofeos.json"

## Catálogo (id -> datos) y su orden DECLARADO, cacheados como `QuestDB`.
static var _trofeos: Dictionary = {}
static var _orden: Array[String] = []
static var _cargado: bool = false

## La instancia VIVA, como `PanelNgPlus.actual` y `Systems.actual`. Hace
## falta porque `Trofeos` guarda el set de ganados y el panel se repinta
## varias veces: si cada repintado creara un `Trofeos.new()`, el set se
## perdería entre repintados y la lista de trofeos sería siempre la misma
## desde cero. La UI lee ESTA instancia; nadie más escribe en ella.
static var actual: Trofeos = null

## Contexto de evaluación, para un `Contexto` como diccionario. Se pasa por
## `evaluar(ctx)` y no se guarda: el trofeo se guarda, el contexto no.
const CTX_CICLO: String = "ciclo"
const CTX_PRESTIGIO: String = "prestigio"
const CTX_MISIONES: String = "misiones_ngplus_entregadas"
const CTX_ACTOS: String = "actos_ngplus_completados"

## Emitida cuando un trofeo se otorga. La UI la escucha (§9.5: se repinta
## porque el DATO se movió, no cada frame).
signal otorgado(trofeo_id: String)
## Emitida en el mismo momento, para quien prefiera una señal de "cambió algo"
## sin parámetro.
signal cambiado

## Los trofeos YA ganados, como `id -> true`. Es lo único que se guarda (y
## lo único que hay que guardar: el resto se recalcula desde el save).
var _ganados: Dictionary = {}


func _init() -> void:
	actual = self


## La instancia viva, creándola si hace falta. Es lo que usa la UI: leer una
## instancia que se tira al final del frame no mostraría nada.
static func instancia() -> Trofeos:
	if actual == null or not is_instance_valid(actual):
		actual = Trofeos.new()
	return actual


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	var texto: String = FileAccess.get_file_as_string(RUTA)
	if texto.is_empty():
		push_warning("[Trofeos] no se pudo leer " + RUTA)
		return
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		push_warning("[Trofeos] " + RUTA + " no es un diccionario JSON válido")
		return
	for entrada in (datos as Dictionary).get("trofeos", []):
		if not (entrada is Dictionary):
			continue
		var t: Dictionary = entrada
		var tid: String = str(t.get("id", ""))
		if tid == "":
			continue
		if _trofeos.has(tid):
			push_warning("[Trofeos] id duplicado: %s" % tid)
			continue
		_trofeos[tid] = t
		_orden.append(tid)


static func ids() -> Array[String]:
	cargar()
	return _orden.duplicate()


static func trofeo(id: String) -> Dictionary:
	cargar()
	return _trofeos.get(id, {})


static func nombre_de(id: String) -> String:
	return str(trofeo(id).get("nombre", id))


static func descripcion_de(id: String) -> String:
	return str(trofeo(id).get("descripcion", ""))


## La condición declarada, tal cual está en el JSON (para la UI y el test).
static func condicion_de(id: String) -> Dictionary:
	return trofeo(id).get("condicion", {})


static func total() -> int:
	cargar()
	return _orden.size()


func tiene(id: String) -> bool:
	return _ganados.has(id)


## Los ids ganados, en el orden DECLARADO del JSON (no en el orden del
## Dictionary, que no está garantizado) para que la lista de la UI sea
## estable entre sesiones.
func ganados() -> Array[String]:
	var salida: Array[String] = []
	for id in _orden:
		if _ganados.has(id):
			salida.append(id)
	return salida


func total_ganados() -> int:
	return _ganados.size()


## EVALÚA el contexto y otorga lo que seicillin. Devuelve los ids NUEVOS (no
## los que ya estaban), para que el llamante pueda avisar solo de esos.
##
## Idempotente: llamar dos veces con el mismo contexto no otorga nada la
## segunda vez. Es lo que permite llamarlo al cargar una partida y cada vez
## que cambia el NG+, sin llevar la cuenta en el callante.
func evaluar(ctx: Dictionary) -> Array[String]:
	cargar()
	var nuevos: Array[String] = []
	for id in _orden:
		if _ganados.has(id):
			continue
		if _cumple(trofeo(id).get("condicion", {}), ctx):
			_ganados[id] = true
			nuevos.append(id)
	if not nuevos.is_empty():
		for id in nuevos:
			otorgado.emit(id)
		cambiado.emit()
	return nuevos


## ¿Se cumple ESTA condición con ESTE contexto? Un `match` por TIPO, no por
## trofeo: añadir un trofeo no añade código aquí.
##
## Una condición con un tipo desconocido NO se cumple nunca. Es lo
## conservador: un `false` es "el trofeo no llega todavía", y un trofeo que
## no llega es un bug pequeño; un `true` por defecto sería un trofeo que se
## otorga solo, que es un bug que se ve.
func _cumple(cond: Dictionary, ctx: Dictionary) -> bool:
	if cond.is_empty():
		return false
	var valor: int = int(cond.get("valor", 0))
	match str(cond.get("tipo", "")):
		"ciclo_min":
			return int(ctx.get(CTX_CICLO, 0)) >= valor
		"prestigio_min":
			return int(ctx.get(CTX_PRESTIGIO, 0)) >= valor
		"afijos_min":
			return _afijos_de(int(ctx.get(CTX_PRESTIGIO, 0))) >= valor
		"acto_ngplus_completo":
			return _actos_completos(ctx).has(int(cond.get("acto", 0)))
		"actos_ngplus_completos_min":
			return _actos_completos(ctx).size() >= valor
		"misiones_ngplus_entregadas_min":
			return int(ctx.get(CTX_MISIONES, 0)) >= valor
		_:
			return false


## Los ids de las misiones entregadas los mete el llamante en el contexto
## (`CTX_MISIONES_ENTREGADAS`): el `Trofeos` no va a buscar la partida por su
## cuenta, igual que `QuestLog` no busca al jugador.
const CTX_MISIONES_ENTREGADAS: String = "misiones_entregadas"

## Los actos de NG+ COMPLETOS en este contexto, como `acto -> true`.
##
## "Completo" es "todas las misiones de ese acto entregadas", y las dos
## mitades salen del DATO, no de una lista en el código:
## - cuántas hay: `QuestDB.acto_ngplus(quest_id)` sobre el catálogo entero,
## - cuántas están: los ids que el llamante pasó en el contexto.
##
## Por qué el conteo completo y no "alguna de este acto": "terminaste la
## cadena del Acto III" tiene que significar la cadena entera. Con "alguna"
## el trofeo saltaría después de la primera misión y el nombre mentiría.
## Una cadena de NG+ nueva declarada en el JSON se recoge aquí sin tocar
## nada.
func _actos_completos(ctx: Dictionary) -> Dictionary:
	var entregadas: Dictionary = {}
	for qid in (ctx.get(CTX_MISIONES_ENTREGADAS, []) as Array):
		entregadas[str(qid)] = true
	# acto -> [entregadas, total]
	var conteo: Dictionary = {}
	for qid in QuestDB.ids():
		if not QuestDB.es_ngplus(qid):
			continue
		var acto: int = QuestDB.acto_ngplus(qid)
		if acto <= 0:
			continue
		if not conteo.has(acto):
			conteo[acto] = [0, 0]
		var fila: Array = conteo[acto]
		fila[1] = int(fila[1]) + 1
		if entregadas.has(qid):
			fila[0] = int(fila[0]) + 1
	var salida: Dictionary = {}
	for acto in conteo:
		var fila: Array = conteo[acto]
		if int(fila[0]) > 0 and int(fila[0]) >= int(fila[1]):
			salida[int(acto)] = true
	return salida


## Los afijos extra que da un prestigio, leído del MISMO cálculo del NG+
## (`NuevoJuegoPlus.afijos_extra`): si el bloque 68 cambia su fórmula, el
## trofeo cambia con ella y no hay dos números que se puedan desincronizar.
func _afijos_de(prestigio: int) -> int:
	return NuevoJuegoPlus.afijos_extra(prestigio)


## El contexto de la partida que hay AHORA, leído del guardado. Es el que
## usa el panel; `evaluar()` no lo llama nunca, así que un test puede
## evaluar contra lo que quiera sin tocar el disco.
##
## `misiones` puede ser null: sin `QuestLog` los trofeos de contenido
## (actos completados) no se pueden evaluar, y los de ciclo y prestigio sí.
## Se pasa null en vez de inventar un QuestLog vacío porque un QuestLog
## vacío daría "0 misiones entregadas" sin distinction entre "no hay
## misiones" y "no me las pasaron".
func contexto_actual(misiones: QuestLog = null) -> Dictionary:
	return contexto_de(SaveSystem.estado_ngplus(), misiones)


## El mismo contexto pero con un `EstadoNgPlus` que el llamante YA TIENE, sin
## ir a buscarlo al disco.
##
## POR QUÉ EXISTE LA SEGUNDA FORMA: `SaveSystem.guardar()` la usa, y ahí el
## estado que manda es el VIVO, no el de la última vez que se guardó. Peor:
## `SaveSystem.estado_ngplus()` es un estático que PUBLICA el ciclo y el
## prestigio que lee (`EstadoNgPlus.desde_dict`), así que llamarlo desde el
## guardado pisaría con el valor del disco el NG+ que el jugador acababa de
## prestigiar en memoria. El loot leería el margen de afijos de la vuelta
## anterior durante toda la partida.
func contexto_de(estado: EstadoNgPlus, misiones: QuestLog = null) -> Dictionary:
	if estado == null or not is_instance_valid(estado):
		estado = EstadoNgPlus.new()
	var entregadas: Array = []
	if misiones != null:
		entregadas = misiones.entregadas()
	return {
		CTX_CICLO: maxi(0, estado.ciclo),
		CTX_PRESTIGIO: maxi(0, estado.prestigio),
		CTX_MISIONES: _cuenta_ngplus(entregadas),
		CTX_MISIONES_ENTREGADAS: entregadas,
	}


func _cuenta_ngplus(entregadas: Array) -> int:
	var n: int = 0
	for qid in entregadas:
		if QuestDB.es_ngplus(str(qid)):
			n += 1
	return n


# --- save -------------------------------------------------------------

const SAVE_VERSION: int = 1

## Solo los ids ganados. Los CONTEXTOS no se guardan: se releen del save,
## que es su única fuente, y un trofeo que se cumpliera con un contexto
## viejo no se otorga dos veces porque `_ganados` ya lo tiene.
func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "ganados": _ganados.duplicate()}


## Carga los ids ganados. TOLERANTE, como todo lo que lee un save: versión
## distinta o bloque ausente → arranca vacío; un trofeo que ya no existe en
## el JSON se ignora en silencio (cambiar el catálogo no puede romper la
## carga de una partida vieja).
func cargar_estado(d: Dictionary) -> void:
	_ganados.clear()
	if int(d.get("version", 0)) != SAVE_VERSION:
		push_warning("[Trofeos] versión %d (esperada %d); se arranca vacío"
			% [int(d.get("version", 0)), SAVE_VERSION])
		return
	for tid in d.get("ganados", {}).keys():
		var id: String = str(tid)
		if not _trofeos.has(id):
			continue
		_ganados[id] = true


## Vacía los trofeos. Lo usa el reinicio del NG+: prestigiar es empezar de
## cero, y un trofeo que sobrevive a la vuelta en la que se ganó deja de
## significar lo que dice. NO lo llama `SaveSystem.reiniciar_para_ngplus()`
## (scripts/save/** está fuera de la propiedad de esta fase): queda como API
## y el test la ejercita. Cuando se enchufe, es una línea.
func reiniciar() -> void:
	if _ganados.is_empty():
		return
	_ganados.clear()
	cambiado.emit()
