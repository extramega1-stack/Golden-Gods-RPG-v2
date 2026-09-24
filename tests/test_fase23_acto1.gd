extends SceneTree
## Tests headless de la Fase 23 (Acto I Moon Town): cadena principal que
## cierra el prólogo (hub Ilya, 4 misiones encadenadas).
##
## Cubre:
## (a) la cadena exige el trío de Moon (bloqueada sin mensaje_sira);
## (b) presentación: dos objetivos de hablar (Bram + Sira);
## (c) grieta: objetivos mixtos matar + informar;
## (d) caída: la oleada completa y la recompensa trae cota de malla;
## (e) el catálogo llega a 29 misiones.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase23_acto1.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const QL: GDScript = preload("res://scripts/quests/quest_log.gd")
const QD: GDScript = preload("res://scripts/quests/quest_db.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 23 — Acto I: cadena principal de Moon Town")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_catalogo()
	_test_requiere_trio()
	_test_presentacion()
	_test_cadena_completa()
	print("[TEST] fase23_acto1: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
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


## Completa el trío de Moon Town (prerrequisito del Acto I).
func _trio_listo(q: QuestLog, p: Player) -> void:
	_chk(q.aceptar("goblins_fuera") == "ok", "setup: aceptar goblins")
	for i in range(5):
		q.registrar_muerte("goblin")
	q.entregar("goblins_fuera", p)
	_chk(q.aceptar("colmillos_forja") == "ok", "setup: aceptar colmillos")
	p.inventario.agregar("colmillo", 4)
	q.sincronizar_recoleccion(p.inventario)
	q.entregar("colmillos_forja", p)
	_chk(q.aceptar("mensaje_sira") == "ok", "setup: aceptar mensaje")
	q.registrar_dialogo("ilya")
	q.entregar("mensaje_sira", p)
	_chk(q.estado("mensaje_sira") == "entregada", "setup: trío entregado")


## (a) Catálogo.
func _test_catalogo() -> void:
	# Fase 24: 32 = 29 + 3 del Acto II.
	_chk(QD.ids().size() == 32, "a: 32 misiones", str(QD.ids().size()))
	_chk(QD.requiere("q_acto1_presentacion") == "mensaje_sira",
		"a: el Acto I exige el trío (mensaje_sira)")


## (b) Sin trío, el Acto I está bloqueado.
func _test_requiere_trio() -> void:
	var q: QuestLog = _log()
	_chk(q.estado("q_acto1_presentacion") == "bloqueada",
		"b: presentación bloqueada sin trío")
	_chk(q.aceptar("q_acto1_presentacion") == "no_disponible",
		"b: no se acepta bloqueada")


## (c) Presentación: dos hablar (Bram + Sira).
func _test_presentacion() -> void:
	var q: QuestLog = _log()
	var p: Player = _player()
	_trio_listo(q, p)
	_chk(q.estado("q_acto1_presentacion") == "disponible",
		"c: se desbloquea con el trío")
	_chk(q.aceptar("q_acto1_presentacion") == "ok", "c: aceptar")
	q.registrar_dialogo("bram")
	_chk(q.estado("q_acto1_presentacion") == "activa",
		"c: con 1/2 sigue activa")
	q.registrar_dialogo("sira")
	_chk(q.estado("q_acto1_presentacion") == "lista",
		"c: con 2/2 lista")
	_chk(q.entregar("q_acto1_presentacion", p).get("resultado", "") == "ok",
		"c: entregar ok")


## (d) Cadena completa hasta la caída + recompensa final.
func _test_cadena_completa() -> void:
	var q: QuestLog = _log()
	var p: Player = _player()
	_trio_listo(q, p)
	_chk(q.aceptar("q_acto1_presentacion") == "ok", "d: aceptar q1")
	q.registrar_dialogo("bram")
	q.registrar_dialogo("sira")
	q.entregar("q_acto1_presentacion", p)
	_chk(q.aceptar("q_acto1_primera_sangre") == "ok", "d: aceptar q2")
	for i in range(6):
		q.registrar_muerte("goblin")
	_chk(q.estado("q_acto1_primera_sangre") == "lista", "d: q2 lista")
	q.entregar("q_acto1_primera_sangre", p)
	_chk(q.aceptar("q_acto1_grieta") == "ok", "d: aceptar q3")
	for i in range(2):
		q.registrar_muerte("ogro")
	_chk(q.estado("q_acto1_grieta") == "activa",
		"d: faltando informar sigue activa")
	q.registrar_dialogo("ilya")
	_chk(q.estado("q_acto1_grieta") == "lista", "d: informar completa q3")
	q.entregar("q_acto1_grieta", p)
	_chk(q.aceptar("q_acto1_caida") == "ok", "d: aceptar final")
	for i in range(6):
		q.registrar_muerte("lobo")
	_chk(q.estado("q_acto1_caida") == "lista", "d: oleada rechazada")
	var res: Dictionary = q.entregar("q_acto1_caida", p)
	_chk(str(res.get("resultado", "")) == "ok", "d: entregar final ok")
	_chk(p.inventario.contar("cota_malla") == 1,
		"d: cota de malla en inventario")
	_chk(int(res.get("oro", 0)) == 300 and int(res.get("xp", 0)) == 400,
		"d: oro 300 + xp 400")
