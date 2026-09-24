extends SceneTree
## Tests headless de la Fase 22 (P2 contenido): cadenas de misiones con
## prerrequisito `requiere` + jefes de fragmento.
##
## Cubre:
## (a) QuestDB.requiere() y conteo del catálogo (25 misiones, 6 con jefe);
## (b) estado "bloqueada": sin prerrequisito no se ofrece ni se acepta;
##     al entregar el prerrequisito se desbloquea (cadena oasis completa);
## (c) jefe: matar el arquetipo completa el objetivo; la recompensa trae el
##     fragmento; respawn largo en datos (300 s);
## (d) jefes y fragmentos existen en enemies.json/items.json; spawns de
##     jefe en data/spawns.json dentro del mundo;
## (e) round-trip de guardado con cadenas (bloqueada derivada, no guardada).
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase22_cadenas.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const QL: GDScript = preload("res://scripts/quests/quest_log.gd")
const QD: GDScript = preload("res://scripts/quests/quest_db.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 22 — cadenas de misiones + jefes de fragmento")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_catalogo()
	_test_bloqueada()
	_test_cadena_oasis()
	_test_jefe()
	_test_datos_jefes()
	_test_roundtrip()
	print("[TEST] fase22_cadenas: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		# QuestLog es RefCounted (se autolibera); solo los Node se liberan.
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _log() -> QuestLog:
	var q: QuestLog = QL.new()
	_basura.append(q)
	return q


func _player() -> Player:
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)
	return p


## Acepta + completa + entrega una misión de matar N del arquetipo.
func _completar_matar(q: QuestLog, qid: String, arq: String, n: int) -> void:
	_chk(q.aceptar(qid) == "ok", "aceptar " + qid)
	for i in range(n):
		q.registrar_muerte(arq)
	_chk(q.estado(qid) == "lista", qid + " lista tras matar", q.estado(qid))


## (a) Catálogo.
func _test_catalogo() -> void:
	# Fase 23: 29 = 25 + 4 del Acto I (este test es de fase 22, solo
	# verifica su parte + el total actualizado).
	_chk(QD.ids().size() == 29, "a: 29 misiones", str(QD.ids().size()))
	_chk(QD.requiere("q_oasis_agua") == "", "a: q1 sin prerrequisito")
	_chk(QD.requiere("q_oasis_secreto") == "q_oasis_agua", "a: q2 requiere q1")
	_chk(QD.requiere("q_oasis_devorador") == "q_oasis_secreto", "a: q3 requiere q2")
	_chk(QD.requiere("goblins_fuera") == "", "a: Moon sin prerrequisitos")
	_chk(QD.requiere("inexistente") == "", "a: desconocida = sin requiere")


## (b) Bloqueada: no se ofrece ni se acepta.
func _test_bloqueada() -> void:
	var q: QuestLog = _log()
	_chk(q.estado("q_oasis_secreto") == "bloqueada", "b: q2 bloqueada al inicio")
	_chk(q.aceptar("q_oasis_secreto") == "no_disponible",
		"b: bloqueada no se acepta")
	var of: Dictionary = q.oferta_para_npc("yasmina")
	_chk(str(of.get("quest_id", "")) == "q_oasis_agua",
		"b: Yasmina ofrece q1, no q2", str(of.get("quest_id", "")))


## (c) Cadena oasis completa: q1 → q2 → q3 (hablar + jefe).
func _test_cadena_oasis() -> void:
	var q: QuestLog = _log()
	var p: Player = _player()
	_completar_matar(q, "q_oasis_agua", "goblin", 4)
	_chk(q.entregar("q_oasis_agua", p).get("resultado", "") == "ok",
		"c: entregar q1 ok")
	_chk(q.estado("q_oasis_secreto") == "disponible",
		"c: q2 se desbloquea al entregar q1")
	_chk(q.aceptar("q_oasis_secreto") == "ok", "c: aceptar q2")
	q.registrar_dialogo("vex")
	_chk(q.estado("q_oasis_secreto") == "lista", "c: hablar con Vex completa")
	_chk(q.entregar("q_oasis_secreto", p).get("resultado", "") == "ok",
		"c: entregar q2 ok")
	_chk(q.estado("q_oasis_devorador") == "disponible", "c: q3 desbloqueada")


## (c2) Jefe: objetivo, recompensa con fragmento y respawn largo.
func _test_jefe() -> void:
	var q: QuestLog = _log()
	var p: Player = _player()
	_completar_matar(q, "q_oasis_agua", "goblin", 4)
	q.entregar("q_oasis_agua", p)
	_chk(q.aceptar("q_oasis_secreto") == "ok", "j: setup q2")
	q.registrar_dialogo("vex")
	q.entregar("q_oasis_secreto", p)
	_chk(q.aceptar("q_oasis_devorador") == "ok", "j: aceptar jefe")
	q.registrar_muerte("goblin")
	_chk(q.estado("q_oasis_devorador") == "activa",
		"j: matar otro arquetipo no avanza")
	q.registrar_muerte("devorador_dunas")
	_chk(q.estado("q_oasis_devorador") == "lista", "j: el jefe completa")
	var res: Dictionary = q.entregar("q_oasis_devorador", p)
	_chk(str(res.get("resultado", "")) == "ok", "j: entregar jefe ok")
	_chk(p.inventario.contar("fragmento_duna") == 1,
		"j: fragmento en inventario", str(p.inventario.contar("fragmento_duna")))
	_chk(int(res.get("oro", 0)) == 250 and int(res.get("xp", 0)) == 350,
		"j: oro 250 + xp 350")


## (d) Datos de jefes, fragmentos y spawns.
func _test_datos_jefes() -> void:
	var et: String = FileAccess.get_file_as_string("res://data/enemies.json")
	var ed: Dictionary = JSON.parse_string(et) as Dictionary
	var arqs: Dictionary = ed.get("arquetipos", {})
	var jefes: Array[String] = ["devorador_dunas", "fundidor_antiguo",
		"aullido_pico", "eco_cristal", "susurro_umbral", "campeon_caido"]
	for j in jefes:
		_chk(arqs.has(j), "d: arquetipo " + j)
		var a: Dictionary = arqs.get(j, {})
		_chk(float(a.get("respawn_seg", 0.0)) >= 300.0,
			"d: " + j + " respawn largo", str(a.get("respawn_seg", 0.0)))
		_chk(int(a.get("xp", 0)) >= 400, "d: " + j + " xp de jefe")
	var it: String = FileAccess.get_file_as_string("res://data/items.json")
	var idd: Dictionary = JSON.parse_string(it) as Dictionary
	var por_id: Dictionary = {}
	for x in (idd.get("items", []) as Array):
		por_id[str((x as Dictionary).get("id", ""))] = true
	for f in ["fragmento_duna", "fragmento_volcan", "fragmento_pico",
			"fragmento_cristal", "fragmento_umbral", "fragmento_arena"]:
		_chk(por_id.has(f), "d: item " + f)
	var st: String = FileAccess.get_file_as_string("res://data/spawns.json")
	var lista: Array = JSON.parse_string(st) as Array
	var puestos: Dictionary = {}
	for s in lista:
		var sd: Dictionary = s
		puestos[str(sd.get("arquetipo", ""))] = Vector2(
			float(sd.get("x", 0.0)), float(sd.get("z", 0.0)))
	var terr := Terreno.new()
	for j in jefes:
		_chk(puestos.has(j), "d: spawn de " + j)
		if puestos.has(j):
			var pv: Vector2 = puestos[j]
			_chk(terr.dentro(pv.x, pv.y), "d: spawn de " + j + " en el mundo")
	terr.free()


## (e) Round-trip: la bloqueada es derivada, no guardada.
func _test_roundtrip() -> void:
	var q: QuestLog = _log()
	var p: Player = _player()
	_completar_matar(q, "q_oasis_agua", "goblin", 4)
	q.entregar("q_oasis_agua", p)
	var q2: QuestLog = QuestLog.from_dict(q.to_dict())
	_chk(q2.estado("q_oasis_agua") == "entregada", "e: q1 entregada tras load")
	_chk(q2.estado("q_oasis_secreto") == "disponible",
		"e: q2 disponible tras load (derivada)")
	_chk(q2.estado("q_oasis_devorador") == "bloqueada",
		"e: q3 sigue bloqueada tras load")
