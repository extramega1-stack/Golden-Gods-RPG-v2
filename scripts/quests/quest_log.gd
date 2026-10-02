class_name QuestLog
extends RefCounted
## Lógica PURA de misiones (fase 8). SIN UI y SIN datos hardcodeados: las
## definiciones viven en QuestDB (`data/quests.json`).
##
## Estados por misión: disponible → activa → lista → entregada.
##  - disponible: aún no aceptada (no registrada en `_estados`).
##  - bloqueada (fase 22): con `requiere` cuyo prerrequisito no está
##    "entregada". No se ofrece, no muestra "!" y no se puede aceptar;
##    es derivada (nunca se guarda: al entregar el prerrequisito pasa a
##    disponible sola).
##  - activa: aceptada; los objetivos avanzan con `registrar_muerte`,
##    `sincronizar_recoleccion` o `registrar_dialogo`.
##  - lista: todos los objetivos completos; pendiente de entrega (el NPC de
##    origen recibe el botón "Entregar").
##  - entregada: recompensa entregada (terminal; ya no se ofrece).
##
## La UI (PanelMisiones, VentanaDialogo) SOLO LEE: todas las mutaciones
## pasan por estas APIs. Cada transición emite `cambiada`.

signal cambiada()

## Misión en curso para la brújula de la fase 13: devuelve
## {"quest": <datos de QuestDB>, "estado": "lista"|"activa"} o {} si no hay.
## Prioridad: primero una "lista" (pendiente de entrega), si no la primera
## "activa". Lógica pura, solo lee.
func mision_activa() -> Dictionary:
	var primera_activa: String = ""
	for qid in _estados.keys():
		var est: String = str(_estados[qid])
		if est == "lista":
			return {"quest": QuestDB.obtener(str(qid)), "estado": "lista"}
		if est == "activa" and primera_activa == "":
			primera_activa = str(qid)
	if primera_activa != "":
		return {"quest": QuestDB.obtener(primera_activa), "estado": "activa"}
	return {}

## Versión del bloque "misiones" del guardado (save v5).
const SAVE_VERSION: int = 1

## quest_id -> String ("activa"/"lista"/"entregada"). Lo no registrado es
## "disponible" (si existe en QuestDB) o "desconocida".
var _estados: Dictionary = {}
## quest_id -> Array con el progreso por objetivo (mismo orden que en los
## datos; la posición i corresponde al objetivo i).
var _progreso: Dictionary = {}


## Estado actual de una misión. Misiones desconocidas → "desconocida".
## Sin registrar: "disponible", salvo que el DATO la bloquee.
##
## Hay DOS motivos de bloqueo derivados, y los dos se deciden en el dato:
##  1. `requiere` (fase 22): el prerrequisito no está entregado → "bloqueada".
##  2. NG+ (esta fase): `ngplus_ciclo` dice que la misión es de una vuelta
##     posterior a la que se está jugando → "bloqueada" también.
##
## El segundo es un dato más de la regla, no una regla nueva: por eso las 41
## misiones del juego base, que no declaran `ngplus_ciclo`, se comportan
## EXACTAMENTE igual que antes (mismo estado, mismos caminos, mismas UI). El
## "¿está disponible?" es la única pregunta nueva, y la contesta
## `QuestDB.disponible_en_ciclo` mirando dos números del JSON.
func estado(quest_id: String) -> String:
	if not QuestDB.existe(quest_id):
		return "desconocida"
	var reg: String = str(_estados.get(quest_id, ""))
	if reg != "":
		return reg
	# Ya aceptada: se sigue viendo, juegue o no el NG+. El jugador la empezó
	# y no se le quita de encima a mitad de camino.
	if not QuestDB.disponible_en_ciclo(quest_id, EstadoNgPlus.ciclo_en_juego()):
		return "bloqueada"
	# Una diaria/semanal VENCIDA tampoco está disponible: mañana ya no se
	# ofrece, aunque su id siga en el catálogo. Es la diferencia entre "no la
	# conozco" (estado "desconocida") y "la conozco pero se acabó" — y hace
	# falta que sean cosas distintas para que `oferta_para_npc` la salte sin
	# avisar y para que la carga de una partida vieja no llore.
	if not QuestDB.vigente(quest_id):
		return "vencida"
	var req: String = QuestDB.requiere(quest_id)
	if req != "" and str(_estados.get(req, "")) != "entregada":
		return "bloqueada"
	return "disponible"


## Acepta una misión disponible. Retorna "ok" / "desconocida" /
## "no_disponible" (ya aceptada, lista o entregada).
##
## "vencida" es un retorno PROPIO y no un "no_disponible": son cosas
## distintas. "no_disponible" significa que ya la tenés o que algo de la
## cadena te falta, y el jugador puede actuar. "vencida" significa que este
## encargo era de ayer y no se puede volver a tomar, y el jugador no puede
## hacer nada al respecto. Confundirlas haría que un NPC dijera "no disponible"
## por una diaria que simplemente ya pasó, y el jugador pensaría que algo
## falló.
func aceptar(quest_id: String) -> String:
	if not QuestDB.existe(quest_id):
		return "desconocida"
	var est: String = estado(quest_id)
	if est == "vencida":
		return "vencida"
	if est != "disponible":
		return "no_disponible"
	_estados[quest_id] = "activa"
	_progreso[quest_id] = _ceros_para(quest_id)
	cambiada.emit()
	return "ok"


## Registra una muerte: avanza los objetivos "matar" de las misiones
## activas que pidan ese arquetipo.
func registrar_muerte(arquetipo_id: String) -> void:
	var cambio: bool = false
	for qid in _estados.keys():
		var quest_id: String = str(qid)
		if str(_estados[quest_id]) != "activa":
			continue
		var objetivos: Array = _objetivos_de(quest_id)
		var prog: Array = _progreso.get(quest_id, [])
		for i in range(objetivos.size()):
			var obj: Dictionary = objetivos[i]
			if str(obj.get("tipo", "")) != "matar":
				continue
			if str(obj.get("arquetipo", "")) != arquetipo_id:
				continue
			if i >= prog.size():
				continue
			var meta: int = maxi(1, int(obj.get("cantidad", 1)))
			if int(prog[i]) < meta:
				prog[i] = int(prog[i]) + 1
				cambio = true
		if _revisar_completada(quest_id):
			cambio = true
	if cambio:
		cambiada.emit()


## Sincroniza los objetivos "recolectar" con el inventario real:
## progreso = min(inv.contar(item), cantidad). Idempotente: se puede
## llamar en cada recogida, compra o venta sin efectos colaterales.
func sincronizar_recoleccion(inv: Inventario) -> void:
	if inv == null:
		return
	var cambio: bool = false
	for qid in _estados.keys():
		var quest_id: String = str(qid)
		if str(_estados[quest_id]) != "activa":
			continue
		var objetivos: Array = _objetivos_de(quest_id)
		var prog: Array = _progreso.get(quest_id, [])
		for i in range(objetivos.size()):
			var obj: Dictionary = objetivos[i]
			if str(obj.get("tipo", "")) != "recolectar":
				continue
			if i >= prog.size():
				continue
			var meta: int = maxi(1, int(obj.get("cantidad", 1)))
			var nuevo: int = mini(inv.contar(str(obj.get("item", ""))), meta)
			if int(prog[i]) != nuevo:
				prog[i] = nuevo
				cambio = true
		if _revisar_completada(quest_id):
			cambio = true
	if cambio:
		cambiada.emit()


## Registra que el jugador habló con un NPC: completa los objetivos
## "hablar" de las misiones activas que pidan ese npc.
func registrar_dialogo(npc_id: String) -> void:
	var cambio: bool = false
	for qid in _estados.keys():
		var quest_id: String = str(qid)
		if str(_estados[quest_id]) != "activa":
			continue
		var objetivos: Array = _objetivos_de(quest_id)
		var prog: Array = _progreso.get(quest_id, [])
		for i in range(objetivos.size()):
			var obj: Dictionary = objetivos[i]
			if str(obj.get("tipo", "")) != "hablar":
				continue
			if str(obj.get("npc", "")) != npc_id:
				continue
			if i >= prog.size():
				continue
			var meta: int = maxi(1, int(obj.get("cantidad", 1)))
			if int(prog[i]) < meta:
				prog[i] = meta
				cambio = true
		if _revisar_completada(quest_id):
			cambio = true
	if cambio:
		cambiada.emit()


## Texto de progreso para la UI: una línea por objetivo
## (ej. "Goblins derrotados: 3/5"). "" si la misión no existe.
func progreso_texto(quest_id: String) -> String:
	if not QuestDB.existe(quest_id):
		return ""
	var objetivos: Array = _objetivos_de(quest_id)
	var prog: Array = _progreso.get(quest_id, [])
	var lineas: Array[String] = []
	for i in range(objetivos.size()):
		var obj: Dictionary = objetivos[i]
		var meta: int = maxi(1, int(obj.get("cantidad", 1)))
		var actual: int = 0
		if i < prog.size():
			actual = int(prog[i])
		lineas.append("%s: %d/%d" % [str(obj.get("texto", "Objetivo")), actual, meta])
	return "\n".join(lineas)


## Los objetivos de una misión con su estado actual: un array de
## diccionarios `{tipo, cantidad, actual, texto, ...}` en el MISMO orden que
## `data/quests.json`. `{}` si la misión no existe.
##
## POR QUÉ EXISTE: `progreso_texto()` da el texto ya formateado, que es lo que
## quiere la UI, pero no sirve para saber QUÉ objetivo falta: hay que volver a
## parsear la cadena. Esto es lo que le deja al juego —y a la partida
## completa— preguntar "¿qué me falta?" sin interpretar español.
func objetivos_con_progreso(quest_id: String) -> Array:
	var salida: Array = []
	if not QuestDB.existe(quest_id):
		return salida
	var objetivos: Array = _objetivos_de(quest_id)
	var prog: Array = _progreso.get(quest_id, [])
	for i in range(objetivos.size()):
		var o: Dictionary = (objetivos[i] as Dictionary).duplicate()
		o["actual"] = int(prog[i]) if i < prog.size() else 0
		o["meta"] = maxi(1, int(o.get("cantidad", 1)))
		salida.append(o)
	return salida


## Oferta de misión para un NPC: la primera "disponible" cuyo npc_origen
## sea él, o la primera "lista" para entregar cuyo npc_origen sea él.
## {} si no hay nada que ofrecer.
##
## Las VENCIDAS se saltan en silencio y sin considerarlas "disponible": un
## NPC no puede ofrecer el encargo de ayer, y no es un problema que haya que
## avisar. `estado()` ya devuelve "vencida" para ellas; el filtro lo deja
## explícito porque `oferta_para_npc` es la función que el juego llama cuando
## el jugador habla con alguien, y ahí importa que no salga una oferta muerta.
func oferta_para_npc(npc_id: String) -> Dictionary:
	if npc_id == "":
		return {}
	# "lista" (lista para entregar) se busca PRIMERO, y esto no es un detalle de
	# orden. Antes se buscaba al reves, y al agregar las DIARIAS un NPC con una
	# diaria disponible tapaba para siempre a su mision de acto ya terminada: el
	# jugador no podia NUNCA entregarla, porque el dialogo ofrecia siempre la
	# diaria. Es el mismo esquema de "dato nuevo que llega y nadie revisa el
	# camino viejo" que se repetiO toda la sesion.
	#
	# Ademas es la MISMA regla que ya usa el marcador del NPC: la "?" de entrega
	# pendiente manda sobre el "!" de mision disponible. Antes el marcador y el
	# dialogo priorizaban al reves, y se veia un "?" en el mundo con un "!" al
	# hablar con el NPC. Ahora los dos priorizan igual.
	for qid in QuestDB.ids():
		if estado(qid) != "lista":
			continue
		var datos: Dictionary = QuestDB.obtener(qid)
		if str(datos.get("npc_origen", "")) == npc_id:
			return {
				"modo": "entregar",
				"quest_id": qid,
				"nombre": str(datos.get("nombre", qid)),
				"descripcion": str(datos.get("descripcion", "")),
			}
	# Ahora si, las nuevas.
	for qid in QuestDB.ids():
		if estado(qid) != "disponible":
			continue
		var datos2: Dictionary = QuestDB.obtener(qid)
		if str(datos2.get("npc_origen", "")) == npc_id:
			return {
				"modo": "disponible",
				"quest_id": qid,
				"nombre": str(datos2.get("nombre", qid)),
				"descripcion": str(datos2.get("descripcion", "")),
			}
	return {}


## Los ids de las misiones YA ENTREGADAS, en el orden del catálogo. Los
## necesita `Trofeos` para saber qué actos de NG+ están completos, y está
## aquí (y no en `Trofeos`) porque el estado de las misiones vive en esta
## clase: una sola fuente de verdad.
func entregadas() -> Array[String]:
	var salida: Array[String] = []
	for qid in QuestDB.ids():
		if str(_estados.get(qid, "")) == "entregada":
			salida.append(qid)
	return salida


## Entrega una misión "lista": consume los items recolectados
## (`inventario.quitar`), da oro (`ganar_oro`), XP (`gain_xp`) e items
## (`inventario.agregar`) y marca "entregada".
## Retorna {"resultado":"ok","oro":N,"xp":M,"items":[...]} o
## {"resultado":"no_lista"/"desconocida"}.
func entregar(quest_id: String, jugador: Player) -> Dictionary:
	if not QuestDB.existe(quest_id):
		return {"resultado": "desconocida"}
	if estado(quest_id) != "lista":
		return {"resultado": "no_lista"}
	if jugador == null or jugador.inventario == null:
		push_warning("[QuestLog] entregar sin jugador/inventario: %s" % quest_id)
		return {"resultado": "no_lista"}
	var datos: Dictionary = QuestDB.obtener(quest_id)
	var recomp: Dictionary = datos.get("recompensas", {})
	# 1) Consumir lo recolectado (en estado "lista" el jugador lo tiene).
	for obj in _objetivos_de(quest_id):
		var od: Dictionary = obj
		if str(od.get("tipo", "")) != "recolectar":
			continue
		jugador.inventario.quitar(
			str(od.get("item", "")), maxi(1, int(od.get("cantidad", 1))))
	# 2) Recompensas: oro, XP e items.
	var oro: int = maxi(0, int(recomp.get("oro", 0)))
	var xp: int = maxi(0, int(recomp.get("xp", 0)))
	var items: Array = recomp.get("items", [])
	if oro > 0:
		jugador.ganar_oro(oro)
	if xp > 0:
		jugador.gain_xp(xp)
	var entregados: Array = []
	for it in items:
		if not (it is Dictionary):
			continue
		var rd: Dictionary = it
		var item_id: String = str(rd.get("id", ""))
		var cant: int = maxi(1, int(rd.get("cantidad", 1)))
		if item_id == "" or not ItemDB.existe(item_id):
			push_warning("[QuestLog] recompensa ignora item inválido: '%s' (%s)" % [item_id, quest_id])
			continue
		jugador.inventario.agregar(item_id, cant)
		entregados.append({"id": item_id, "cantidad": cant})
	_estados[quest_id] = "entregada"
	cambiada.emit()
	return {"resultado": "ok", "oro": oro, "xp": xp, "items": entregados}


## Serialización versionada (la usa el save v5).
func to_dict() -> Dictionary:
	var bloque: Dictionary = {}
	for qid in _estados:
		var quest_id: String = str(qid)
		var prog: Array = _progreso.get(quest_id, [])
		bloque[quest_id] = {
			"estado": str(_estados[quest_id]),
			"progreso": prog.duplicate(),
		}
	return {"version": SAVE_VERSION, "misiones": bloque}


static func from_dict(d: Dictionary) -> QuestLog:
	var q: QuestLog = QuestLog.new()
	q.cargar_estado(d)
	return q


## Restaura el estado desde un dict (tolerante: versión distinta o bloque
## ausente → arranca vacío con push_warning, NUNCA revienta; ignora
## misiones desconocidas y estados inválidos).
func cargar_estado(d: Dictionary) -> void:
	_estados.clear()
	_progreso.clear()
	var ver: int = int(d.get("version", 0))
	if ver != SAVE_VERSION:
		push_warning("[QuestLog] versión %d (esperada %d); se arranca vacío" % [ver, SAVE_VERSION])
		cambiada.emit()
		return
	var bloque: Dictionary = d.get("misiones", {})
	for qid in bloque:
		var quest_id: String = str(qid)
		# UNA DIARIA DE AYER NO ROMPE LA CARGA. Este es el caso que pedía
		# revisar: el bloque "misiones" de una partida de ayer tiene ids
		# `dia_d000738_...` que hoy no están en el catálogo, porque la rotación
		# de hoy se registra al arrancar. Perderla es lo correcto (venció), así
		# que se ignora en silencio. Una misión normal desconocida, en cambio,
		# SÍ es un problema (un id mal escrito, o un catálogo que se quedó
		# corto) y por eso avisa como siempre.
		if not QuestDB.existe(quest_id):
			if not QuestDB.es_id_de_rotacion(quest_id):
				push_warning("[QuestLog] ignora misión desconocida en guardado: %s" % quest_id)
			continue
		var entrada: Variant = bloque.get(qid, {})
		if not (entrada is Dictionary):
			continue
		var ed: Dictionary = entrada
		var estado_g: String = str(ed.get("estado", "disponible"))
		if estado_g != "activa" and estado_g != "lista" and estado_g != "entregada":
			push_warning("[QuestLog] estado inválido en guardado: %s (%s)" % [quest_id, estado_g])
			continue
		var crudo: Array = ed.get("progreso", [])
		var objetivos: Array = _objetivos_de(quest_id)
		var prog_g: Array = []
		for i in range(objetivos.size()):
			var meta: int = maxi(1, int((objetivos[i] as Dictionary).get("cantidad", 1)))
			var v: int = 0
			if i < crudo.size():
				v = maxi(0, int(crudo[i]))
			prog_g.append(mini(v, meta))
		_estados[quest_id] = estado_g
		_progreso[quest_id] = prog_g
	cambiada.emit()


func _objetivos_de(quest_id: String) -> Array:
	var datos: Dictionary = QuestDB.obtener(quest_id)
	return datos.get("objetivos", [])


func _ceros_para(quest_id: String) -> Array:
	var ceros: Array = []
	for i in range(_objetivos_de(quest_id).size()):
		ceros.append(0)
	return ceros


## Si una misión activa tiene todos los objetivos completos → pasa a
## "lista". Retorna true si cambió el estado.
func _revisar_completada(quest_id: String) -> bool:
	if str(_estados.get(quest_id, "")) != "activa":
		return false
	var objetivos: Array = _objetivos_de(quest_id)
	if objetivos.is_empty():
		return false
	var prog: Array = _progreso.get(quest_id, [])
	for i in range(objetivos.size()):
		var obj: Dictionary = objetivos[i]
		var meta: int = maxi(1, int(obj.get("cantidad", 1)))
		if i >= prog.size() or int(prog[i]) < meta:
			return false
	_estados[quest_id] = "lista"
	return true
