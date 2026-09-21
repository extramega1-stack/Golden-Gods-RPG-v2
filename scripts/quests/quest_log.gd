class_name QuestLog
extends RefCounted
## Lógica PURA de misiones (fase 8). SIN UI y SIN datos hardcodeados: las
## definiciones viven en QuestDB (`data/quests.json`).
##
## Estados por misión: disponible → activa → lista → entregada.
##  - disponible: aún no aceptada (no registrada en `_estados`).
##  - activa: aceptada; los objetivos avanzan con `registrar_muerte`,
##    `sincronizar_recoleccion` o `registrar_dialogo`.
##  - lista: todos los objetivos completos; pendiente de entrega (el NPC de
##    origen recibe el botón "Entregar").
##  - entregada: recompensa entregada (terminal; ya no se ofrece).
##
## La UI (PanelMisiones, VentanaDialogo) SOLO LEE: todas las mutaciones
## pasan por estas APIs. Cada transición emite `cambiada`.

signal cambiada()

## Versión del bloque "misiones" del guardado (save v5).
const SAVE_VERSION: int = 1

## quest_id -> String ("activa"/"lista"/"entregada"). Lo no registrado es
## "disponible" (si existe en QuestDB) o "desconocida".
var _estados: Dictionary = {}
## quest_id -> Array con el progreso por objetivo (mismo orden que en los
## datos; la posición i corresponde al objetivo i).
var _progreso: Dictionary = {}


## Estado actual de una misión. Misiones desconocidas → "desconocida".
func estado(quest_id: String) -> String:
	if not QuestDB.existe(quest_id):
		return "desconocida"
	return str(_estados.get(quest_id, "disponible"))


## Acepta una misión disponible. Retorna "ok" / "desconocida" /
## "no_disponible" (ya aceptada, lista o entregada).
func aceptar(quest_id: String) -> String:
	if not QuestDB.existe(quest_id):
		return "desconocida"
	if estado(quest_id) != "disponible":
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


## Oferta de misión para un NPC: la primera "disponible" cuyo npc_origen
## sea él, o la primera "lista" para entregar cuyo npc_origen sea él.
## {} si no hay nada que ofrecer.
func oferta_para_npc(npc_id: String) -> Dictionary:
	if npc_id == "":
		return {}
	for qid in QuestDB.ids():
		if estado(qid) != "disponible":
			continue
		var datos: Dictionary = QuestDB.obtener(qid)
		if str(datos.get("npc_origen", "")) == npc_id:
			return {
				"modo": "disponible",
				"quest_id": qid,
				"nombre": str(datos.get("nombre", qid)),
				"descripcion": str(datos.get("descripcion", "")),
			}
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
	return {}


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
		if not QuestDB.existe(quest_id):
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
