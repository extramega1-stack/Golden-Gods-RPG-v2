extends SceneTree
## Tests headless de la Fase 24 (Acto II): la caza de los seis fragmentos.
##
## Cubre:
## (a) la llamada exige la caída (bloqueada sin acto1);
## (b) los seis ecos: 6 objetivos de recolectar que avanzan con el
##     inventario y se consumen al entregar;
## (c) rumbo a la forja: avisar a Durnan + Bram (teaser Acto III);
## (d) catálogo en 32 misiones.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase24_acto2.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const QL: GDScript = preload("res://scripts/quests/quest_log.gd")
const QD: GDScript = preload("res://scripts/quests/quest_db.gd")

const FRAGS: Array[String] = ["fragmento_duna", "fragmento_volcan",
	"fragmento_pico", "fragmento_cristal", "fragmento_umbral",
	"fragmento_arena"]

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 24 — Acto II: los seis fragmentos")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_catalogo()
	_test_requiere_caida()
	_test_seis_ecos()
	_test_rumbo_forja()
	print("[TEST] fase24_acto2: %d ok, %d fallos" % [_ok, _fallos])
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
	_chk(QD.ids().size() == 32, "a: 32 misiones", str(QD.ids().size()))
	_chk(QD.requiere("q_acto2_llamada") == "q_acto1_caida",
		"a: la llamada exige la caída")
	_chk(QD.requiere("q_acto2_seis_ecos") == "q_acto2_llamada",
		"a: los ecos exigen la llamada")
	_chk(QD.requiere("q_acto2_rumbo_forja") == "q_acto2_seis_ecos",
		"a: la forja exige los ecos")


## (b) Sin caída, el Acto II está bloqueado.
func _test_requiere_caida() -> void:
	var q: QuestLog = _log()
	_chk(q.estado("q_acto2_llamada") == "bloqueada",
		"b: llamada bloqueada sin caída")
	_chk(q.aceptar("q_acto2_llamada") == "no_disponible",
		"b: no se acepta bloqueada")


## (c) Los seis ecos: recolectar + entregar consume.
func _test_seis_ecos() -> void:
	var q: QuestLog = _log()
	var p: Player = _player()
	# Prerrequisitos directos (el walk completo del Acto I lo cubre su test).
	_chk(q.aceptar("q_acto2_llamada") == "no_disponible",
		"c: sanity bloqueada sin caida")
	q._estados["q_acto1_caida"] = "entregada"
	_chk(q.estado("q_acto2_llamada") == "disponible",
		"c: con la caída se desbloquea")
	_chk(q.aceptar("q_acto2_llamada") == "ok", "c: aceptar llamada")
	q.registrar_dialogo("elthar")
	_chk(q.estado("q_acto2_llamada") == "lista", "c: hablar completa")
	q.entregar("q_acto2_llamada", p)
	_chk(q.aceptar("q_acto2_seis_ecos") == "ok", "c: aceptar ecos")
	# 3/6 no completan.
	for f in FRAGS.slice(0, 3):
		p.inventario.agregar(f, 1)
	q.sincronizar_recoleccion(p.inventario)
	_chk(q.estado("q_acto2_seis_ecos") == "activa",
		"c: con 3/6 sigue activa")
	for f in FRAGS.slice(3, 6):
		p.inventario.agregar(f, 1)
	q.sincronizar_recoleccion(p.inventario)
	_chk(q.estado("q_acto2_seis_ecos") == "lista", "c: con 6/6 lista")
	var res: Dictionary = q.entregar("q_acto2_seis_ecos", p)
	_chk(str(res.get("resultado", "")) == "ok", "c: entregar ecos ok")
	_chk(int(res.get("oro", 0)) == 600 and int(res.get("xp", 0)) == 1000,
		"c: oro 600 + xp 1000")
	for f in FRAGS:
		_chk(p.inventario.contar(f) == 0,
			"c: Elthar se queda con " + f)


## (d) Rumbo a la forja: Durnan + Bram.
func _test_rumbo_forja() -> void:
	var q: QuestLog = _log()
	var p: Player = _player()
	q._estados["q_acto2_seis_ecos"] = "entregada"
	_chk(q.estado("q_acto2_rumbo_forja") == "disponible",
		"d: rumbo disponible con ecos")
	_chk(q.aceptar("q_acto2_rumbo_forja") == "ok", "d: aceptar rumbo")
	q.registrar_dialogo("durnan")
	_chk(q.estado("q_acto2_rumbo_forja") == "activa",
		"d: con 1/2 sigue activa")
	q.registrar_dialogo("bram")
	_chk(q.estado("q_acto2_rumbo_forja") == "lista",
		"d: con 2/2 lista")
	_chk(q.entregar("q_acto2_rumbo_forja", p).get("resultado", "") == "ok",
		"d: entregar rumbo ok")
