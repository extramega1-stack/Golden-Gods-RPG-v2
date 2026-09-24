extends SceneTree
## Tests headless de la Fase 26 (Acto IV): El Descenso.
##
## Cubre:
## (a) el descenso exige el molde (bloqueada sin acto3);
## (b) puerta: preguntar a Vex; descenso: 4 ogros;
## (c) umbral mixto (susurro + informar a Karg) y recompensa final;
## (d) catálogo en 38 misiones.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase26_acto4.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const QL: GDScript = preload("res://scripts/quests/quest_log.gd")
const QD: GDScript = preload("res://scripts/quests/quest_db.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 26 — Acto IV: El Descenso")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_catalogo()
	_test_requiere_molde()
	_test_cadena_descenso()
	print("[TEST] fase26_acto4: %d ok, %d fallos" % [_ok, _fallos])
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
	_chk(QD.ids().size() == 38, "a: 38 misiones", str(QD.ids().size()))
	_chk(QD.requiere("q_acto4_puerta") == "q_acto3_molde",
		"a: la puerta exige el molde")
	_chk(QD.requiere("q_acto4_descenso") == "q_acto4_puerta",
		"a: el descenso exige la puerta")
	_chk(QD.requiere("q_acto4_umbral") == "q_acto4_descenso",
		"a: el umbral exige el descenso")


## (b) Sin molde, el Descenso está bloqueado.
func _test_requiere_molde() -> void:
	var q: QuestLog = _log()
	_chk(q.estado("q_acto4_puerta") == "bloqueada",
		"b: puerta bloqueada sin molde")
	_chk(q.aceptar("q_acto4_puerta") == "no_disponible",
		"b: no se acepta bloqueada")


## (c) Cadena completa del Descenso.
func _test_cadena_descenso() -> void:
	var q: QuestLog = _log()
	var p: Player = _player()
	q._estados["q_acto3_molde"] = "entregada"
	_chk(q.estado("q_acto4_puerta") == "disponible",
		"c: puerta disponible con molde")
	_chk(q.aceptar("q_acto4_puerta") == "ok", "c: aceptar puerta")
	q.registrar_dialogo("vex")
	_chk(q.estado("q_acto4_puerta") == "lista", "c: Vex indica")
	_chk(q.entregar("q_acto4_puerta", p).get("resultado", "") == "ok",
		"c: entregar puerta ok")
	_chk(q.aceptar("q_acto4_descenso") == "ok", "c: aceptar descenso")
	for i in range(4):
		q.registrar_muerte("ogro")
	_chk(q.estado("q_acto4_descenso") == "lista", "c: tramo limpio")
	q.entregar("q_acto4_descenso", p)
	_chk(q.aceptar("q_acto4_umbral") == "ok", "c: aceptar umbral")
	q.registrar_muerte("susurro_umbral")
	_chk(q.estado("q_acto4_umbral") == "activa",
		"c: sin informar sigue activa")
	q.registrar_dialogo("karg")
	_chk(q.estado("q_acto4_umbral") == "lista", "c: informar completa")
	var res: Dictionary = q.entregar("q_acto4_umbral", p)
	_chk(str(res.get("resultado", "")) == "ok", "c: entregar umbral ok")
	_chk(int(res.get("oro", 0)) == 600 and int(res.get("xp", 0)) == 1000,
		"c: oro 600 + xp 1000")
