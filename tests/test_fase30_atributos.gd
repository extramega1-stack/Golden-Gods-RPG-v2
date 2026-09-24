extends SceneTree
## Tests headless de la Fase 30 (atributos estilo FlyFF + personaje).
##
## Cubre:
## (a) aguante: vida_max +15 y defensa +1 por punto; set_base válido e
##     inválido; round-trip con aguante;
## (b) Player: 2 puntos por nivel; repartir valida/gasta/aplica; inválido
##     y sin puntos no tocan nada;
## (c) save v9: puntos_atributo en disco y restaurados (retroactivo v8);
## (d) PanelPersonaje: 4 filas, botón gasta, cabecera con nombre/nivel.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase30_atributos.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const SV: GDScript = preload("res://scripts/save/save_system.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 30 — atributos FlyFF + personaje")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_aguante()
	_test_repartir()
	_test_save_v9()
	_test_panel()
	print("[TEST] fase30_atributos: %d ok, %d fallos" % [_ok, _fallos])
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


## (a) Aguante en StatBlock.
func _test_aguante() -> void:
	var s: StatBlock = SB.new(0.0, 0.0, 0.0, 0.0, 10.0)
	_basura.append(s)
	_chk(absf(s.vida_max - 250.0) < 0.01,
		"a: 10 aguante = +150 vida", str(s.vida_max))
	_chk(absf(s.defensa - 10.0) < 0.01, "a: +1 defensa por punto",
		str(s.defensa))
	s.set_base("aguante", 20.0)
	_chk(absf(s.vida_max - 400.0) < 0.01, "a: set_base aguante")
	s.set_base("carisma", 5.0)
	_chk(absf(s.vida_max - 400.0) < 0.01, "a: atributo inválido no toca")
	var s2: StatBlock = SB.from_dict(s.to_dict())
	_chk(absf(s2.aguante - 20.0) < 0.01, "a: round-trip con aguante")


## (b) Reparto en el Player.
func _test_repartir() -> void:
	var p: Player = _player()
	_chk(p.puntos_atributo == 0, "b: nivel 1 sin puntos")
	_chk(p.repartir_atributo("fuerza") == "sin_puntos",
		"b: sin puntos no reparte")
	p.gain_xp(100000)
	var pts: int = p.puntos_atributo
	_chk(pts == (p.nivel - 1) * 2, "b: 2 puntos por nivel",
		"nv=%d pts=%d" % [p.nivel, pts])
	_chk(p.repartir_atributo("carisma") == "atributo",
		"b: atributo inválido no")
	var atq: float = p.stats.ataque
	var fza: float = p.stats.fuerza
	_chk(p.repartir_atributo("fuerza") == "ok", "b: repartir ok")
	_chk(p.puntos_atributo == pts - 1, "b: gasta 1 punto")
	_chk(absf(p.stats.fuerza - (fza + 1.0)) < 0.01, "b: +1 fuerza")
	_chk(p.stats.ataque > atq, "b: el ataque sube")
	var vida: float = p.stats.vida_max
	_chk(p.repartir_atributo("aguante") == "ok", "b: aguante ok")
	_chk(absf(p.stats.vida_max - (vida + 15.0)) < 0.01,
		"b: +15 vida por STA", str(p.stats.vida_max))


## (c) Save v9 con puntos retroactivos.
func _test_save_v9() -> void:
	var p: Player = _player()
	p.gain_xp(100000)
	p.repartir_atributo("destreza")
	var s: SaveSystem = SV.new()
	s.jugador = p
	s.enemigos = []
	s.npcs = []
	_basura.append(s)
	_chk(s.guardar(), "c: guardar v9")
	var crudo: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(SaveSystem.RUTA))
	_chk(int((crudo as Dictionary).get("version", 0)) == 10,
		"c: version 10 en disco")
	var dj: Dictionary = (crudo as Dictionary).get("jugador", {})
	_chk(int(dj.get("puntos_atributo", -1)) == p.puntos_atributo,
		"c: puntos guardados")
	var p2: Player = _player()
	var s2: SaveSystem = SV.new()
	s2.jugador = p2
	s2.enemigos = []
	s2.npcs = []
	_basura.append(s2)
	_chk(s2.cargar(), "c: cargar v9")
	_chk(p2.puntos_atributo == p.puntos_atributo,
		"c: puntos restaurados")
	_chk(absf(p2.stats.destreza - p.stats.destreza) < 0.01,
		"c: base restaurada")
	# Sin bloque (v8): retroactivo 2/nivel (entidad de nivel 5).
	dj.erase("puntos_atributo")
	(dj.get("entidad", {}) as Dictionary)["nivel"] = 5
	var p3: Player = _player()
	var s3: SaveSystem = SV.new()
	s3.jugador = p3
	_basura.append(s3)
	s3._cargar_jugador(dj)
	_chk(p3.puntos_atributo == 8, "c: retroactivo 2/nivel en v8")


## (d) PanelPersonaje.
func _test_panel() -> void:
	var p: Player = _player()
	p.fijar_identidad("Test", "guerrero")
	var panel: PanelPersonaje = PanelPersonaje.new()
	root.add_child(panel)
	_basura.append(panel)
	panel.conectar(p)
	_chk(panel._filas.get_child_count() == 4,
		"d: 4 filas STR/STA/DEX/INT", str(panel._filas.get_child_count()))
	_chk(str(panel._cabecera.text).contains("Test"),
		"d: cabecera con nombre", panel._cabecera.text)
	p.gain_xp(100000)
	panel.conectar(p)
	var viva: HBoxContainer = null
	for h in panel._filas.get_children():
		var hb: HBoxContainer = h as HBoxContainer
		if hb != null and not hb.is_queued_for_deletion():
			viva = hb
			break
	var btn: Button = viva.get_child(2) as Button
	_chk(btn != null and not btn.disabled, "d: con puntos el + activa")
	var f0: float = p.stats.fuerza
	btn.pressed.emit()
	_chk(absf(p.stats.fuerza - (f0 + 1.0)) < 0.01,
		"d: el botón reparte STR")
