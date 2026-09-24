extends SceneTree
## Tests headless de la Fase 28 (talentos por clase).
##
## Cubre:
## (a) TalentoDB: 12 talentos (3 por clase jugable), ordenados por nivel;
## (b) subir(): valida clase/nivel/tope/puntos y aplica mods × rango;
## (c) Player: 1 punto por nivel; cambio de clase purga y devuelve;
## (d) round-trip de guardado (puntos+rangos; mods idempotentes);
## (e) PanelTalentos: 3 filas en guerrero, gastar por botón sin reventar.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase28_talentos.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const TL: GDScript = preload("res://scripts/skills/talentos.gd")
const TDB: GDScript = preload("res://scripts/skills/talento_db.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 28 — talentos por clase")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_db()
	_test_subir()
	_test_player_niveles()
	_test_roundtrip()
	_test_panel()
	print("[TEST] fase28_talentos: %d ok, %d fallos" % [_ok, _fallos])
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


func _player() -> Player:
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)
	return p


func _stats_base() -> StatBlock:
	var s: StatBlock = SB.new(45.0, 10.0, 0.0, 0.0)
	_basura.append(s)
	return s


## (a) Catálogo.
func _test_db() -> void:
	_chk(TDB.ids().size() == 12, "a: 12 talentos", str(TDB.ids().size()))
	for c in ["guerrero", "mago", "arquero", "clerigo"]:
		_chk(TDB.talentos_por_clase(c).size() == 3,
			"a: 3 talentos de " + c)
	_chk(TDB.talentos_por_clase("guerrero")[0] == "filo_pesado",
		"a: ordenados por requiere_nivel")
	_chk(not TDB.existe("talento_fantasma"), "a: no existe inventado")


## (b) Lógica de gasto.
func _test_subir() -> void:
	var t: Talentos = TL.new()
	_basura.append(t)
	var s: StatBlock = _stats_base()
	var base_atq: float = s.ataque
	_chk(t.subir("talento_fantasma", s, 10, "guerrero") == "desconocido",
		"b: desconocido")
	_chk(t.subir("mente_arcana", s, 10, "guerrero") == "clase",
		"b: de otra clase no")
	_chk(t.subir("filo_pesado", s, 1, "guerrero") == "nivel",
		"b: nivel insuficiente no")
	_chk(t.subir("filo_pesado", s, 5, "guerrero") == "sin_puntos",
		"b: sin puntos no")
	t.puntos = 5
	_chk(t.subir("filo_pesado", s, 5, "guerrero") == "ok", "b: subir ok")
	_chk(t.rango_de("filo_pesado") == 1 and t.puntos == 4,
		"b: rango 1, puntos 4")
	_chk(absf(s.ataque - (base_atq + 3.0)) < 0.01,
		"b: +3 ataque por rango", str(s.ataque))
	_chk(t.subir("filo_pesado", s, 5, "guerrero") == "ok", "b: rango 2")
	_chk(t.subir("filo_pesado", s, 5, "guerrero") == "ok", "b: rango 3")
	_chk(absf(s.ataque - (base_atq + 9.0)) < 0.01,
		"b: ×3 rangos = +9", str(s.ataque))
	_chk(t.subir("filo_pesado", s, 5, "guerrero") == "max_rango",
		"b: tope de rango")


## (c) Player: puntos por nivel y purga al cambiar de clase.
func _test_player_niveles() -> void:
	var p: Player = _player()
	_chk(p.talentos != null, "c: talentos creado en _ready")
	_chk(p.talentos.puntos == 0, "c: nivel 1 sin puntos")
	p.gain_xp(100000)
	_chk(p.nivel > 1 and p.talentos.puntos == p.nivel - 1,
		"c: 1 punto por nivel", "nv=%d pts=%d" % [p.nivel, p.talentos.puntos])
	p.talentos.subir("filo_pesado", p.stats, p.nivel, p.clase_id)
	var atq: float = p.stats.ataque
	_chk(atq > 0.0, "c: talento aplicado al player")
	p.fijar_identidad("Héroe", "mago")
	_chk(p.talentos.rango_de("filo_pesado") == 0,
		"c: al cambiar de clase se purga")
	_chk(not p.stats.has_mod("talento:filo_pesado"),
		"c: sin mods ajenos")


## (d) Round-trip puntos+rangos; aplicar idempotente.
func _test_roundtrip() -> void:
	var t: Talentos = TL.new()
	_basura.append(t)
	t.puntos = 2
	var s: StatBlock = _stats_base()
	_chk(t.subir("piel_hierro", s, 5, "guerrero") == "ok", "d: setup rango")
	var t2: Talentos = Talentos.from_dict(t.to_dict())
	_chk(t2.puntos == 1 and t2.rango_de("piel_hierro") == 1,
		"d: puntos+rangos restaurados")
	var s2: StatBlock = _stats_base()
	var base_def: float = s2.defensa
	t2.aplicar_todos(s2)
	t2.aplicar_todos(s2)
	_chk(absf(s2.defensa - (base_def + 5.0)) < 0.01,
		"d: aplicar idempotente (+5 una vez)", str(s2.defensa))


## (e) Panel: filas por clase y gasto sin reventar.
func _test_panel() -> void:
	var p: Player = _player()
	var panel: PanelTalentos = PanelTalentos.new()
	root.add_child(panel)
	_basura.append(panel)
	panel.conectar(p)
	_chk(panel._filas.get_child_count() == 3,
		"e: 3 filas en guerrero", str(panel._filas.get_child_count()))
	p.gain_xp(100000)
	panel.conectar(p)
	# Las filas viejas se liberan al final del frame: buscar la viva.
	var btn: Button = null
	for h in panel._filas.get_children():
		var hb: HBoxContainer = h as HBoxContainer
		if hb == null or hb.is_queued_for_deletion():
			continue
		btn = hb.get_child(1) as Button
		break
	_chk(btn != null and not btn.disabled, "e: con puntos el botón activa")
	btn.pressed.emit()
	_chk(p.talentos.rango_de("filo_pesado") == 1,
		"e: el botón gasta el punto")
