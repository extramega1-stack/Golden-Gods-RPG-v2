extends SceneTree
## Tests headless de la Fase 5 (skills: SkillDB + SkillSystem).
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_skills.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const SDB: GDScript = preload("res://scripts/skills/skill_db.gd")
const SS: GDScript = preload("res://scripts/skills/skill_system.gd")
const ENT: GDScript = preload("res://scripts/core/entity.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _ultimo_fallo_id: String = ""
var _ultimo_fallo_motivo: String = ""
var _usadas: Array[String] = []


func _init() -> void:
	print("[TEST] Fase 5 — skills")
	SDB.cargar()
	_t_db()
	_t_desconocida()


var _empezo: bool = false


## Los Entity necesitan el árbol para global_position (ver lección 13b de
## AGENTS.md: el árbol existe recién en el primer _process). Todo lo que
## mide distancias corre aquí.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_sin_mana()
	_t_casteo_y_cooldown()
	_t_dano_real()
	_t_curacion()
	_t_rango()
	_t_objetivo_muerto()
	_t_mas_cercano()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
	return true


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


func _al_fallida(skill_id: String, motivo: String) -> void:
	_ultimo_fallo_id = skill_id
	_ultimo_fallo_motivo = motivo


func _al_usada(skill_id: String) -> void:
	_usadas.append(skill_id)


## Entity con stats dados, metida al árbol en la posición indicada.
func _entidad(fuerza: float, agilidad: float, destreza: float, inteligencia: float, pos: Vector3) -> Entity:
	var e: Entity = ENT.new(SB.new(fuerza, agilidad, destreza, inteligencia))
	root.add_child(e)
	e.position = pos
	_basura.append(e)
	return e


func _t_db() -> void:
	var ids: Array[String] = SDB.lista()
	_check(ids.size() == 5, "SkillDB tiene 5 skills", str(ids.size()))
	var esperado: Array[String] = ["golpe_heroico", "tajo_veloz", "bola_fuego", "curacion_menor", "ejecucion"]
	_check(ids == esperado, "lista() en orden de hotbar", str(ids))
	_check(SDB.existe("bola_fuego"), "existe(bola_fuego)")
	_check(not SDB.existe("magia_inexistente"), "no existe skill inventada")
	var bf: Dictionary = SDB.obtener("bola_fuego")
	_check(str(bf.get("nombre", "")) == "Bola de fuego", "obtener devuelve el dict", str(bf.get("nombre", "")))


func _t_desconocida() -> void:
	var sys: SkillSystem = SS.new()
	sys.skill_fallida.connect(_al_fallida)
	var lanz: Entity = ENT.new(SB.new(10.0, 8.0, 6.0, 4.0))
	_basura.append(lanz)
	_ultimo_fallo_motivo = ""
	var motivo: String = sys.puede_lanzar("magia_inexistente", lanz, null)
	_check(motivo == "desconocida", "puede_lanzar desconocida", motivo)
	var ok: bool = sys.lanzar("magia_inexistente", lanz, null)
	_check(not ok, "lanzar desconocida → false")
	_check(_ultimo_fallo_motivo == "desconocida", "motivo desconocida", _ultimo_fallo_motivo)


func _t_sin_mana() -> void:
	var sys: SkillSystem = SS.new()
	sys.skill_fallida.connect(_al_fallida)
	var lanz: Entity = _entidad(45.0, 10.0, 0.0, 0.0, Vector3.ZERO)
	var obj: Entity = _entidad(10.0, 8.0, 4.0, 2.0, Vector3(1, 0, 0))
	lanz.mana_actual = 0.0
	_ultimo_fallo_motivo = ""
	var mana_antes: float = lanz.mana_actual
	var ok: bool = sys.lanzar("golpe_heroico", lanz, obj)
	_check(not ok, "lanzar sin maná → false")
	_check(_ultimo_fallo_motivo == "mana", "motivo mana", _ultimo_fallo_motivo)
	_check(lanz.mana_actual == mana_antes, "no gasta nada sin maná", str(lanz.mana_actual))
	_check(sys.cooldown_restante("golpe_heroico") == 0.0, "fallo no pone cooldown")


func _t_casteo_y_cooldown() -> void:
	var sys: SkillSystem = SS.new()
	sys.skill_fallida.connect(_al_fallida)
	sys.skill_usada.connect(_al_usada)
	var lanz: Entity = _entidad(45.0, 10.0, 0.0, 0.0, Vector3.ZERO)
	var obj: Entity = _entidad(10.0, 8.0, 4.0, 2.0, Vector3(1, 0, 0))
	var mana_antes: float = lanz.mana_actual
	_usadas.clear()
	_ultimo_fallo_motivo = ""
	var ok: bool = sys.lanzar("golpe_heroico", lanz, obj)
	_check(ok, "lanzar ok → true")
	_check(lanz.mana_actual == mana_antes - 10.0, "descuenta maná (10)", str(lanz.mana_actual))
	var cd: float = sys.cooldown_restante("golpe_heroico")
	_check(cd > 0.0 and cd <= 4.0, "pone cooldown", str(cd))
	_check(_usadas.has("golpe_heroico"), "emite skill_usada")
	_ultimo_fallo_motivo = ""
	var ok2: bool = sys.lanzar("golpe_heroico", lanz, obj)
	_check(not ok2, "segundo lanzamiento inmediato → false")
	_check(_ultimo_fallo_motivo == "cooldown", "motivo cooldown", _ultimo_fallo_motivo)
	sys.tick(2.0)
	var cd2: float = sys.cooldown_restante("golpe_heroico")
	_check(cd2 > 0.0 and cd2 < cd, "tick reduce el cooldown", "%f -> %f" % [cd, cd2])
	sys.tick(100.0)
	_check(sys.cooldown_restante("golpe_heroico") == 0.0, "tick nunca baja de 0")
	_ultimo_fallo_motivo = ""
	var ok3: bool = sys.lanzar("golpe_heroico", lanz, obj)
	_check(ok3, "tras tick permite relanzar", _ultimo_fallo_motivo)
	_check(lanz.mana_actual == mana_antes - 20.0, "segundo casteo descuenta maná", str(lanz.mana_actual))


func _t_dano_real() -> void:
	var sys: SkillSystem = SS.new()
	var lanz: Entity = _entidad(45.0, 10.0, 0.0, 0.0, Vector3.ZERO)
	var obj: Entity = _entidad(10.0, 8.0, 4.0, 2.0, Vector3(2, 0, 0))
	var vida_antes: float = obj.vida_actual
	var ok: bool = sys.lanzar("tajo_veloz", lanz, obj)
	_check(ok, "tajo_veloz se lanza")
	_check(obj.vida_actual < vida_antes, "la vida del objetivo baja >0", "%f -> %f" % [vida_antes, obj.vida_actual])


func _t_curacion() -> void:
	var sys: SkillSystem = SS.new()
	var lanz: Entity = _entidad(10.0, 8.0, 4.0, 10.0, Vector3.ZERO)
	lanz.take_damage(60.0, null)
	var vida_herido: float = lanz.vida_actual
	_check(vida_herido < lanz.stats.vida_max, "lanzador herido", str(vida_herido))
	var mana_antes: float = lanz.mana_actual
	var ok: bool = sys.lanzar("curacion_menor", lanz, null)
	_check(ok, "curacion_menor se lanza sin objetivo")
	_check(lanz.vida_actual > vida_herido, "curación sube la vida", "%f -> %f" % [vida_herido, lanz.vida_actual])
	_check(lanz.mana_actual == mana_antes - 20.0, "curación cuesta 20 de maná", str(lanz.mana_actual))


func _t_rango() -> void:
	var sys: SkillSystem = SS.new()
	sys.skill_fallida.connect(_al_fallida)
	var lanz: Entity = _entidad(45.0, 10.0, 0.0, 0.0, Vector3.ZERO)
	var lejos: Entity = _entidad(10.0, 8.0, 4.0, 2.0, Vector3(20, 0, 0))
	var medio: Entity = _entidad(10.0, 8.0, 4.0, 2.0, Vector3(10, 0, 0))
	_ultimo_fallo_motivo = ""
	var ok: bool = sys.lanzar("golpe_heroico", lanz, lejos)
	_check(not ok, "objetivo fuera de rango → false")
	_check(_ultimo_fallo_motivo == "rango", "motivo rango", _ultimo_fallo_motivo)
	_check(sys.cooldown_restante("golpe_heroico") == 0.0, "fuera de rango no pone cooldown")
	var vida_antes: float = medio.vida_actual
	var ok2: bool = sys.lanzar("bola_fuego", lanz, medio)
	_check(ok2, "bola_fuego sí alcanza a 10m (rango 12)")
	_check(medio.vida_actual < vida_antes, "bola_fuego hace daño a distancia", str(medio.vida_actual))


func _t_objetivo_muerto() -> void:
	var sys: SkillSystem = SS.new()
	sys.skill_fallida.connect(_al_fallida)
	var lanz: Entity = _entidad(45.0, 10.0, 0.0, 0.0, Vector3.ZERO)
	var obj: Entity = _entidad(10.0, 8.0, 4.0, 2.0, Vector3(1, 0, 0))
	obj.die()
	_ultimo_fallo_motivo = ""
	var ok: bool = sys.lanzar("golpe_heroico", lanz, obj)
	_check(not ok, "objetivo muerto → false")
	_check(_ultimo_fallo_motivo == "objetivo", "motivo objetivo", _ultimo_fallo_motivo)
	_ultimo_fallo_motivo = ""
	var ok2: bool = sys.lanzar("tajo_veloz", lanz, null)
	_check(not ok2, "objetivo null en skill de daño → false")
	_check(_ultimo_fallo_motivo == "objetivo", "motivo objetivo con null", _ultimo_fallo_motivo)


func _t_mas_cercano() -> void:
	var lanz: Entity = _entidad(10.0, 8.0, 4.0, 2.0, Vector3.ZERO)
	var cerca: Entity = _entidad(10.0, 8.0, 4.0, 2.0, Vector3(2, 0, 0))
	var muerto: Entity = _entidad(10.0, 8.0, 4.0, 2.0, Vector3(1, 0, 0))
	muerto.die()
	var lejos: Entity = _entidad(10.0, 8.0, 4.0, 2.0, Vector3(8, 0, 0))
	var elegido: Entity = SS.mas_cercano(lanz, [cerca, muerto, lejos])
	_check(elegido == cerca, "mas_cercano elige el vivo más próximo")
	cerca.die()
	var elegido2: Entity = SS.mas_cercano(lanz, [cerca, muerto, lejos])
	_check(elegido2 == lejos, "mas_cercano ignora muertos")
	_check(SS.mas_cercano(lanz, [muerto]) == null, "sin vivos → null")
	_check(SS.mas_cercano(lanz, []) == null, "lista vacía → null")
