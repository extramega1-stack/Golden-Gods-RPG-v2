extends SceneTree
## Tests headless de la Fase 38 (rebind de teclas por slot de la barra).
##
## Cubre (skill `input-systems`: capturar, conflicto, persistir, defecto):
## (a) defecto intacto: F4 (barra_4) y tecla 4 (habilidad_4) disparan el
##     slot visible 4; el Player ya no escucha (vía única, fase 37);
## (b) fijar_atajo(Q) al slot 1: Q lo ejecuta; conflicto si Q ya está en
##     otro slot o en otra acción del proyecto (WASD); "tipo" si no es
##     tecla; "indice" fuera de rango;
## (c) restablecer_atajo devuelve el defecto (Q deja de disparar, 1/F1 sí);
## (d) persistencia v2 con round-trip; save v1 (sin atajos) carga con el
##     defecto; override inválido en el save se descarta al defecto.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase38_rebind.gd

const BA: GDScript = preload("res://scripts/ui/barra_acciones.gd")
const SDB: GDScript = preload("res://scripts/skills/skill_db.gd")
const IDB: GDScript = preload("res://scripts/inventory/item_db.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []
var _usadas: Array[String] = []


func _init() -> void:
	print("[TEST] Fase 38 — rebind por slot")
	SDB.cargar()
	IDB.cargar()


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_defecto()
	_test_rebind()
	_test_conflicto()
	_test_reset()
	_test_persistencia()
	print("[TEST] fase38_rebind: %d ok, %d fallos" % [_ok, _fallos])
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


func _kit() -> Array:
	var p: Player = PL.new()
	p.clase_id = "clerigo"
	root.add_child(p)
	_basura.append(p)
	var b: BarraAcciones = BA.new()
	root.add_child(b)
	_basura.append(b)
	b.conectar(p)
	return [p, b]


func _tecla(codigo: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = codigo
	ev.pressed = true
	return ev


func _accion(nombre: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = nombre
	ev.pressed = true
	return ev


## (a) Defecto: F4 y 4 disparan el slot 4.
func _test_defecto() -> void:
	var kit: Array = _kit()
	var p: Player = kit[0]
	var b: BarraAcciones = kit[1]
	_usadas.clear()
	p.skills.skill_usada.connect(func(sid: String) -> void: _usadas.append(sid))
	_chk(b.asignar(3, {"tipo": "skill", "id": "curacion_menor"}),
		"a: setup cura en slot 4")
	p.take_damage(200.0, null)
	# Teclas físicas como en el juego real: 4 = physical 52 (habilidad_4),
	# F4 = physical 4194335 (barra_4, desde la fase 47: la barra es F1-F8).
	# Los InputEventAction solo casan por nombre exacto y no ejercitan el
	# mapeo físico del slot.
	b._unhandled_input(_tecla(52))
	_chk(_usadas.has("curacion_menor"), "a: tecla 4 → slot 4", str(_usadas))
	# Kit fresco para F4 (la cura del check anterior dejó cooldown).
	_usadas.clear()
	var kit2: Array = _kit()
	var p2: Player = kit2[0]
	var b2: BarraAcciones = kit2[1]
	p2.skills.skill_usada.connect(func(sid: String) -> void: _usadas.append(sid))
	_chk(b2.asignar(3, {"tipo": "skill", "id": "curacion_menor"}),
		"a: setup cura en slot 4 (kit2)")
	p2.take_damage(200.0, null)
	b2._unhandled_input(_tecla(4194335))
	_chk(_usadas.has("curacion_menor"), "a: F4 → slot 4", str(_usadas))
	_chk(b.atajo_texto(3) == "4/F4", "a: etiqueta defecto", b.atajo_texto(3))


## (b) Rebind a Q: Q ejecuta, validaciones.
func _test_rebind() -> void:
	var kit: Array = _kit()
	var p: Player = kit[0]
	var b: BarraAcciones = kit[1]
	_usadas.clear()
	p.skills.skill_usada.connect(func(sid: String) -> void: _usadas.append(sid))
	_chk(b.asignar(0, {"tipo": "skill", "id": "curacion_menor"}),
		"b: setup cura en slot 1")
	_chk(b.fijar_atajo(0, _tecla(KEY_Q)) == "ok", "b: Q al slot 1")
	_chk(b.atajo_texto(0) == "Q", "b: etiqueta Q", b.atajo_texto(0))
	p.take_damage(200.0, null)
	var vida0: float = p.vida_actual
	b._unhandled_input(_tecla(KEY_Q))
	_chk(_usadas.has("curacion_menor") and p.vida_actual > vida0,
		"b: Q ejecuta el slot 1")
	_chk(b.fijar_atajo(99, _tecla(KEY_Q)) == "indice", "b: índice malo")
	_chk(b.fijar_atajo(1, _accion("barra_2")) == "tipo", "b: no-tecla es tipo")


## (c) Conflictos: otro slot y acciones del proyecto (W = mover).
func _test_conflicto() -> void:
	var kit: Array = _kit()
	var b: BarraAcciones = kit[1]
	_chk(b.fijar_atajo(0, _tecla(KEY_Q)) == "ok", "c: setup Q en slot 1")
	_chk(b.fijar_atajo(1, _tecla(KEY_Q)) == "conflicto",
		"c: Q duplicada en slot 2 se rechaza")
	_chk(b.fijar_atajo(1, _tecla(KEY_W)) == "conflicto",
		"c: W (mover_adelante) se rechaza")
	_chk(b.atajo_texto(1) == "2/F2", "c: el slot 2 conserva defecto",
		b.atajo_texto(1))


## (d) Reset al defecto.
func _test_reset() -> void:
	var kit: Array = _kit()
	var p: Player = kit[0]
	var b: BarraAcciones = kit[1]
	_usadas.clear()
	p.skills.skill_usada.connect(func(sid: String) -> void: _usadas.append(sid))
	_chk(b.asignar(0, {"tipo": "skill", "id": "curacion_menor"}),
		"d: setup cura en slot 1")
	b.fijar_atajo(0, _tecla(KEY_Q))
	b.restablecer_atajo(0)
	_chk(b.atajo_texto(0) == "1/F1", "d: etiqueta vuelve", b.atajo_texto(0))
	_usadas.clear()
	b._unhandled_input(_tecla(KEY_Q))
	_chk(not _usadas.has("curacion_menor"), "d: Q ya no dispara")
	p.take_damage(200.0, null)
	b._unhandled_input(_tecla(49))
	_chk(_usadas.has("curacion_menor"), "d: tecla 1 vuelve a disparar")


## (e) Persistencia v2 + tolerancia v1.
func _test_persistencia() -> void:
	var kit: Array = _kit()
	var b: BarraAcciones = kit[1]
	b.fijar_atajo(0, _tecla(KEY_Q))
	b.fijar_atajo(6, _tecla(KEY_Z))
	var d: Dictionary = b.to_dict()
	_chk(int(d.get("version", 0)) == 2, "e: save v2", str(d.get("version", 0)))
	var atajos: Array = d.get("atajos", [])
	_chk(atajos.size() == 8 and int(atajos[0]) == KEY_Q and int(atajos[6]) == KEY_Z,
		"e: atajos guardados", str(atajos))
	var b2: BarraAcciones = BA.new()
	_basura.append(b2)
	b2.cargar_estado(d)
	_chk(b2.atajo_texto(0) == "Q" and b2.atajo_texto(6) == "Z",
		"e: round-trip restaura", b2.atajo_texto(0) + "/" + b2.atajo_texto(6))
	# Save v1 sin atajos → defecto.
	var b3: BarraAcciones = BA.new()
	_basura.append(b3)
	b3.cargar_estado({"version": 1, "slots": []})
	_chk(b3.atajo_texto(0) == "1/F1", "e: v1 conserva defecto")
	# Override inválido (tecla de otro slot) se descarta al defecto.
	var b4: BarraAcciones = BA.new()
	_basura.append(b4)
	b4.fijar_atajo(0, _tecla(KEY_Q))
	var mala: Dictionary = b4.to_dict()
	(mala.get("atajos", []) as Array)[1] = KEY_Q
	b4.cargar_estado(mala)
	_chk(b4.atajo_texto(1) == "2/F2", "e: override en conflicto → defecto")
