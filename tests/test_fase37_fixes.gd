extends SceneTree
## Tests headless de la Fase 37 (pack de fixes del playtest de Juan Diego).
##
## (a) Barra: la tecla numérica N ejecuta el SLOT VISIBLE N (no ids[N-1]).
##     Reproducción del reporte "pulso 4 y ejecuta el 5": con curacion_menor
##     en el slot 4, el evento habilidad_4 debe curar (antes se ignoraba y
##     el 4 lanzaba ids[3], lo que se ve en el slot 5).
## (b) XP: 15 goblins con el jugador como fuente suben a Nv 4 (contrato del
##     grind temprano); la barra del HUD muestra el TRAMO del nivel actual
##     (no valores acumulados que nunca se resetean).
## (c) Clase: aplicar_clase emite vida/mana (el HUD event-driven corrige al
##     instante; antes quedaba el 1150 del guerrero hasta el primer golpe).
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase37_fixes.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const BA: GDScript = preload("res://scripts/ui/barra_acciones.gd")
const HUD: GDScript = preload("res://scripts/ui/hud.gd")
const FM: GDScript = preload("res://scripts/core/formulas.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []
var _usadas: Array[String] = []
var _vida_emit: Array = []
var _mana_emit: Array = []


func _init() -> void:
	print("[TEST] Fase 37 — fixes playtest (barra/XP/HP)")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_barra_numeros()
	_test_xp_grind()
	_test_tramo_xp()
	_test_clase_emite()
	print("[TEST] fase37_fixes: %d ok, %d fallos" % [_ok, _fallos])
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


func _evento_accion(accion: String) -> InputEventKey:
	# Fase 38: la barra escucha sus acciones slot_* por tecla física; un
	# InputEventAction solo casa por nombre exacto. Se traduce la acción
	# a su tecla física (como llega del juego real).
	var codigo: int = 0
	for ev in InputMap.action_get_events(accion):
		var k: InputEventKey = ev as InputEventKey
		if k != null:
			codigo = int(k.physical_keycode)
			break
	var tecla := InputEventKey.new()
	tecla.physical_keycode = codigo
	tecla.pressed = true
	return tecla


## (a) Tecla 4 → slot visible 4.
func _test_barra_numeros() -> void:
	var p: Player = PL.new()
	p.clase_id = "clerigo"
	root.add_child(p)
	_basura.append(p)
	var b: BarraAcciones = BA.new()
	root.add_child(b)
	_basura.append(b)
	b.conectar(p)
	_usadas.clear()
	p.skills.skill_usada.connect(func(sid: String) -> void: _usadas.append(sid))
	_chk(b.asignar(3, {"tipo": "skill", "id": "curacion_menor"}),
		"a: setup asigna cura al slot 4")
	p.take_damage(200.0, null)
	var vida0: float = p.vida_actual
	b._unhandled_input(_evento_accion("habilidad_4"))
	_chk(_usadas.has("curacion_menor"),
		"a: tecla 4 ejecuta el slot visible 4", str(_usadas))
	_chk(p.vida_actual > vida0, "a: la cura del slot 4 aplicó",
		"%f -> %f" % [vida0, p.vida_actual])
	# Documenta el offset que causaba el bug: con el layout por defecto el
	# slot 4 (índice 3) es el 3er skill, no el 4to.
	var b2: BarraAcciones = BA.new()
	_basura.append(b2)
	b2.restablecer_defecto()
	var ids: Array[String] = SkillDB.skills_por_clase("guerrero")
	_chk(str(b2.obtener(3).get("id", "")) == ids[2],
		"a: slot 4 visible = 3er skill (offset ataque)", str(b2.obtener(3)))


## (b) 15 goblins → Nv 4 con 600 XP.
func _test_xp_grind() -> void:
	var p: Player = PL.new()
	p.fijar_identidad("T", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	var aqs: Dictionary = (JSON.parse_string(
		FileAccess.get_file_as_string("res://data/enemies.json")) as Dictionary)["arquetipos"]
	for i in range(15):
		var e: Enemy = EN.new()
		root.add_child(e)
		_basura.append(e)
		e.configurar((aqs["goblin"] as Dictionary).duplicate(true))
		e.take_damage(99999.0, p)
	_chk(p.nivel == 4, "b: 15 goblins → Nv 4", "nv=" + str(p.nivel))
	_chk(p.xp_actual == 600, "b: 15 × 40 = 600 XP", "xp=" + str(p.xp_actual))


## (b2) Tramo de XP dentro del nivel.
func _test_tramo_xp() -> void:
	var t0: Vector2 = HUD.tramo_xp(0, 1)
	_chk(int(t0.x) == 0 and int(t0.y) == 100, "b: tramo nuevo Nv1 = 0/100", str(t0))
	var base4: int = FM.xp_for_level(4)
	var sig5: int = FM.xp_for_level(5)
	var t: Vector2 = HUD.tramo_xp(600, 4)
	_chk(int(t.x) == 600 - base4 and int(t.y) == sig5 - base4,
		"b: tramo Nv4 resetea la base", str(t))
	_chk(t.x >= 0.0 and t.x <= t.y and t.y > 0.0, "b: tramo acotado", str(t))


## (c) aplicar_clase emite vida/maná con los máximos nuevos.
func _test_clase_emite() -> void:
	var p: Player = PL.new()
	p.fijar_identidad("T", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	_vida_emit.clear()
	_mana_emit.clear()
	p.vida_cambiada.connect(func(a: float, m: float) -> void: _vida_emit = [a, m])
	p.mana_cambiado.connect(func(a: float, m: float) -> void: _mana_emit = [a, m])
	p.aplicar_clase("mago")
	# Mago 15/15/15/45: vida 100+15*20+15*15=625, maná 50+45*15=725.
	_chk(_vida_emit == [625.0, 625.0], "c: emite vida del mago", str(_vida_emit))
	_chk(_mana_emit == [725.0, 725.0], "c: emite maná del mago", str(_mana_emit))
