extends SceneTree
## Tests headless de la Fase 25 (Acto III): la Forja del Molde.
##
## Cubre:
## (a) la forja exige el rumbo (bloqueada sin acto2);
## (b) carbón: recolectar 5 colmillos;
## (c) yunque: 3 ogros; molde mixto (hablar Elthar + 4 lobos);
## (d) catálogo en 35 misiones.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase25_acto3.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const QL: GDScript = preload("res://scripts/quests/quest_log.gd")
const QD: GDScript = preload("res://scripts/quests/quest_db.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 25 — Acto III: la Forja")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_catalogo()
	_test_requiere_rumbo()
	_test_cadena_forja()
	print("[TEST] fase25_acto3: %d ok, %d fallos" % [_ok, _fallos])
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


## (a) Catálogo y prerrequisito.
func _test_catalogo() -> void:
	_chk(QD.ids().size() == 35, "a: 35 misiones", str(QD.ids().size()))
	_chk(QD.requiere("q_acto3_carbon") == "q_acto2_rumbo_forja",
		"a: el carbón exige el rumbo")
	_chk(QD.requiere("q_acto3_yunque") == "q_acto3_carbon",
		"a: el yunque exige el carbón")
	_chk(QD.requiere("q_acto3_molde") == "q_acto3_yunque",
		"a: el molde exige el yunque")


## (b) Sin rumbo, la Forja está bloqueada.
func _test_requiere_rumbo() -> void:
	var q: QuestLog = _log()
	_chk(q.estado("q_acto3_carbon") == "bloqueada",
		"b: carbón bloqueado sin rumbo")
	_chk(q.aceptar("q_acto3_carbon") == "no_disponible",
		"b: no se acepta bloqueada")


## (c) Cadena completa de la Forja.
func _test_cadena_forja() -> void:
	var q: QuestLog = _log()
	var p: Player = _player()
	q._estados["q_acto2_rumbo_forja"] = "entregada"
	_chk(q.estado("q_acto3_carbon") == "disponible",
		"c: carbón disponible con rumbo")
	_chk(q.aceptar("q_acto3_carbon") == "ok", "c: aceptar carbón")
	p.inventario.agregar("colmillo", 5)
	q.sincronizar_recoleccion(p.inventario)
	_chk(q.estado("q_acto3_carbon") == "lista", "c: 5 colmillos listan")
	_chk(q.entregar("q_acto3_carbon", p).get("resultado", "") == "ok",
		"c: entregar carbón ok")
	_chk(p.inventario.contar("colmillo") == 0,
		"c: la fragua consume los colmillos")
	_chk(q.aceptar("q_acto3_yunque") == "ok", "c: aceptar yunque")
	for i in range(3):
		q.registrar_muerte("ogro")
	_chk(q.estado("q_acto3_yunque") == "lista", "c: 3 ogros listan")
	q.entregar("q_acto3_yunque", p)
	_chk(q.aceptar("q_acto3_molde") == "ok", "c: aceptar molde")
	q.registrar_dialogo("elthar")
	_chk(q.estado("q_acto3_molde") == "activa",
		"c: sin defender sigue activa")
	for i in range(4):
		q.registrar_muerte("lobo")
	_chk(q.estado("q_acto3_molde") == "lista", "c: molde listo")
	var res: Dictionary = q.entregar("q_acto3_molde", p)
	_chk(str(res.get("resultado", "")) == "ok", "c: entregar molde ok")
	_chk(int(res.get("oro", 0)) == 400 and int(res.get("xp", 0)) == 600,
		"c: oro 400 + xp 600")
