class_name SkillSystem
extends RefCounted
## Ejecuta skills sobre entidades. Casi puro: el único azar es el RNG que el
## propio sistema genera al llamar a Formulas.damage (como hace player.gd).
##
## Fase 5. El sistema no guarda estado salvo los cooldowns por skill
## (segundos restantes). Los datos de cada skill vienen de SkillDB.

signal skill_usada(skill_id: String)
signal skill_fallida(skill_id: String, motivo: String)

var _cds: Dictionary = {}


## Descuenta los cooldowns; nunca bajan de 0.
func tick(delta: float) -> void:
	var d: float = maxf(delta, 0.0)
	for k in _cds.keys():
		_cds[k] = maxf(float(_cds[k]) - d, 0.0)


func cooldown_restante(skill_id: String) -> float:
	return float(_cds.get(skill_id, 0.0))


## "" si se puede lanzar; si no, el motivo:
## "desconocida" | "objetivo" | "rango" | "mana" | "cooldown".
## La curación no chequea objetivo ni rango (se aplica al lanzador).
func puede_lanzar(skill_id: String, lanzador: Entity, objetivo: Entity) -> String:
	if not SkillDB.existe(skill_id):
		return "desconocida"
	var skill: Dictionary = SkillDB.obtener(skill_id)
	var efecto: Dictionary = skill.get("efecto", {})
	var es_dano: bool = str(efecto.get("tipo", "")) == "dano"
	if es_dano:
		if objetivo == null or not objetivo.esta_vivo():
			return "objetivo"
		var rango: float = float(skill.get("rango", 0.0))
		if _dist_plana(lanzador, objetivo) > rango:
			return "rango"
	if lanzador.mana_actual < float(skill.get("mana", 0.0)):
		return "mana"
	if cooldown_restante(skill_id) > 0.0:
		return "cooldown"
	return ""


## Intenta lanzar el skill. Si falla, emite skill_fallida(motivo) y false.
## Si tiene éxito: descuenta maná, arranca el cooldown, aplica el efecto
## (curar → heal al lanzador; dano → Formulas.damage + take_damage),
## emite skill_usada y retorna true.
func lanzar(skill_id: String, lanzador: Entity, objetivo: Entity) -> bool:
	var motivo: String = puede_lanzar(skill_id, lanzador, objetivo)
	if motivo != "":
		skill_fallida.emit(skill_id, motivo)
		return false
	var skill: Dictionary = SkillDB.obtener(skill_id)
	var mana: float = float(skill.get("mana", 0.0))
	if not lanzador.gastar_mana(mana):
		skill_fallida.emit(skill_id, "mana")
		return false
	_cds[skill_id] = float(skill.get("cooldown", 0.0))
	var efecto: Dictionary = skill.get("efecto", {})
	var tipo: String = str(efecto.get("tipo", ""))
	if tipo == "curar":
		lanzador.heal(float(efecto.get("cantidad", 0.0)))
	elif tipo == "dano" and objetivo != null:
		# Formulas.damage retorna Dictionary declarado: `=` es seguro aquí.
		var res = Formulas.damage(lanzador.stats, objetivo.stats, skill, randf(), randf_range(-1.0, 1.0))
		objetivo.take_damage(float(res["final"]), lanzador)
	skill_usada.emit(skill_id)
	return true


## El Entity vivo más cercano al lanzador (distancia plana, ignora y).
## null si no hay ningún candidato vivo.
static func mas_cercano(lanzador: Entity, candidatos: Array) -> Entity:
	var mejor: Entity = null
	var mejor_d: float = INF
	for c in candidatos:
		if not (c is Entity):
			continue
		var e: Entity = c
		if not e.esta_vivo():
			continue
		var d: float = _dist_plana(lanzador, e)
		if d < mejor_d:
			mejor_d = d
			mejor = e
	return mejor


## Distancia 3D plana entre dos entidades (se ignora el eje y).
static func _dist_plana(a: Entity, b: Entity) -> float:
	var pa: Vector3 = a.global_position
	var pb: Vector3 = b.global_position
	var dx: float = pa.x - pb.x
	var dz: float = pa.z - pb.z
	return sqrt(dx * dx + dz * dz)
