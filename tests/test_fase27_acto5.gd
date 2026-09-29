extends SceneTree
## Tests headless de la Fase 27 (Acto V): La Última Guerra + decisión.
##
## Cubre:
## (a) la guerra exige el umbral; ambas sendas exigen la guerra;
## (b) la guerra: 6 ogros;
## (c) senda del Arma: rematar al Campeón, oro de mercenario;
## (d) senda Liberty: sellar con Elthar, Eco del Verdugo en inventario;
## (e) catálogo en 41 misiones, item legendario en datos.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase27_acto5.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const QL: GDScript = preload("res://scripts/quests/quest_log.gd")
const QD: GDScript = preload("res://scripts/quests/quest_db.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 27 — Acto V: La Última Guerra")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_catalogo()
	_test_requiere_umbral()
	_test_guerra()
	_test_senda_arma()
	_test_senda_liberty()
	print("[TEST] fase27_acto5: %d ok, %d fallos" % [_ok, _fallos])
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


## (a) Catálogo, prerrequisitos e item.
func _test_catalogo() -> void:
	# El catálogo ESCRITO, sin la rotación de runtime. `ids()` mezcla las
	# dos cosas porque es lo que necesita el juego (el panel tiene que listar
	# también las diarias), y por eso su total depende de qué día es: 60 hoy,
	# 61 mañana. Un número así no puede ser lo que este test quiere afirmar.
	# Lo que se afirma es que el catálogo escrito no se encogió: 41 del juego
	# base + 15 de NG+.
	_chk(QD.ids_de_archivo().size() == 56,
		"a: 56 misiones escritas (41 base + 15 NG+)",
		str(QD.ids_de_archivo().size()))
	_chk(QD.requiere("q_acto5_guerra") == "q_acto4_umbral",
		"a: la guerra exige el umbral")
	_chk(QD.requiere("q_final_espada") == "q_acto5_guerra",
		"a: el Arma exige la guerra")
	_chk(QD.requiere("q_final_sello") == "q_acto5_guerra",
		"a: el Sello exige la guerra")
	var it: String = FileAccess.get_file_as_string("res://data/items.json")
	var idd: Dictionary = JSON.parse_string(it) as Dictionary
	var eco: Dictionary = {}
	for x in (idd.get("items", []) as Array):
		if str((x as Dictionary).get("id", "")) == "verdugo_eco":
			eco = x
	_chk(not eco.is_empty(), "a: existe Eco del Verdugo")
	_chk(str(eco.get("rareza", "")) == "legendario", "a: rareza legendario")


## (b) Sin umbral no hay guerra.
func _test_requiere_umbral() -> void:
	var q: QuestLog = _log()
	_chk(q.estado("q_acto5_guerra") == "bloqueada",
		"b: guerra bloqueada sin umbral")
	_chk(q.aceptar("q_acto5_guerra") == "no_disponible",
		"b: no se acepta bloqueada")


## (c) La guerra: 6 ogros.
func _test_guerra() -> void:
	var q: QuestLog = _log()
	var p: Player = _player()
	q._estados["q_acto4_umbral"] = "entregada"
	_chk(q.estado("q_acto5_guerra") == "disponible",
		"c: guerra disponible con umbral")
	_chk(q.aceptar("q_acto5_guerra") == "ok", "c: aceptar guerra")
	for i in range(6):
		q.registrar_muerte("ogro")
	_chk(q.estado("q_acto5_guerra") == "lista", "c: vanguardia rechazada")
	_chk(q.entregar("q_acto5_guerra", p).get("resultado", "") == "ok",
		"c: entregar guerra ok")
	_chk(q.estado("q_final_espada") == "disponible",
		"c: el Arma se ofrece")
	_chk(q.estado("q_final_sello") == "disponible",
		"c: el Sello se ofrece")


## (d) Senda del Arma: paga de mercenario.
func _test_senda_arma() -> void:
	var q: QuestLog = _log()
	var p: Player = _player()
	q._estados["q_acto5_guerra"] = "entregada"
	_chk(q.aceptar("q_final_espada") == "ok", "d: aceptar Arma")
	q.registrar_muerte("campeon_caido")
	_chk(q.estado("q_final_espada") == "lista", "d: campeón rematado")
	var res: Dictionary = q.entregar("q_final_espada", p)
	_chk(str(res.get("resultado", "")) == "ok", "d: entregar Arma ok")
	_chk(int(res.get("oro", 0)) == 1200 and int(res.get("xp", 0)) == 1800,
		"d: oro 1200 + xp 1800")


## (e) Senda Liberty: el Sello + Eco del Verdugo.
func _test_senda_liberty() -> void:
	var q: QuestLog = _log()
	var p: Player = _player()
	q._estados["q_acto5_guerra"] = "entregada"
	_chk(q.aceptar("q_final_sello") == "ok", "e: aceptar Sello")
	q.registrar_dialogo("elthar")
	_chk(q.estado("q_final_sello") == "lista", "e: ritual completo")
	var res: Dictionary = q.entregar("q_final_sello", p)
	_chk(str(res.get("resultado", "")) == "ok", "e: entregar Sello ok")
	_chk(p.inventario.contar("verdugo_eco") == 1,
		"e: Eco del Verdugo en inventario")
