class_name SkillSystem
extends RefCounted
## Ejecuta skills sobre entidades. Casi puro: el único azar es el RNG que el
## propio sistema genera al llamar a Formulas.damage (como hace player.gd).
##
## Fase 5. El sistema no guarda estado salvo los cooldowns por skill
## (segundos restantes) y los efectos temporales (fase 18). Los datos de
## cada skill vienen de SkillDB.
##
## Fase 18 — tipos de efecto del JSON v2:
## - "dano": como siempre (power × Formulas.damage, magica, bonus_crit,
##   varianza).
## - "curar": restaura `efecto.cantidad` de vida al lanzador.
## - "aoe": daño (power × damage) a todos los enemigos vivos en
##   `efecto.radio` metros alrededor del punto objetivo (posición del
##   objetivo) o del lanzador (sin objetivo, o si `rango` == 0). Los
##   candidatos se buscan en el grupo "enemigos" del árbol del lanzador
##   (mismo mecanismo que usa Player para el auto-ataque); los NPCs
##   (no combatibles) nunca son candidatos (REGLA DURA de la fase 5.1).
## - "buff": modificador porcentual temporal al lanzador: `efecto.stat`
##   (ataque|defensa|crit) × (1 + cantidad) durante `duracion` s.
## - "debuff": modificador porcentual temporal al objetivo enemigo:
##   `efecto.stat` (ataque|velocidad) × (1 - cantidad) durante
##   `duracion` s.
## Buffs/debuffs se implementan como MODS de StatBlock (fuente
## "buff:<skill_id>" / "debuff:<skill_id>"); tick() descuenta su duración
## y retira el mod al expirar. Reaplicar el mismo skill refresca la
## duración (no se acumula). Sin tocar StatBlock: solo add_mod/remove_mod;
## la UI solo lee.
## Feedback visual: Entity.mostrar_fx(color) por tipo de efecto (el nodo
## SkillFX lo tiñe). Feedback sonoro: AudioJuego.al_skill(tipo) en lanzar()
## (fase 20: pipeline existente).

## Fase 31 — niveles de skill estilo FlyFF (1–20, 2 puntos por nivel del
## jugador). Cada clase conoce sus skills a nivel 1 (`configurar_clase`);
## el resto están en 0 ("no aprendidas") y no se pueden subir ni lanzar.
## `power_nivel` del JSON escala el efecto principal: power para daño/aoe/
## curar, `efecto.cantidad` para buff/debuff (misma unidad del efecto).
## Sin `configurar_clase()`, el sistema opera en modo libre: todas las
## skills conocidas lanzan a nivel 1 (compatibilidad con tests viejos y
## herramientas). En juego el Player siempre configura su clase.

signal skill_usada(skill_id: String)
signal skill_fallida(skill_id: String, motivo: String)

## Colores del feedback visual por tipo de efecto.
const COLOR_CURAR: Color = Color(0.35, 1.0, 0.45)
const COLOR_BUFF: Color = Color(1.0, 0.85, 0.30)
const COLOR_DEBUFF: Color = Color(0.70, 0.35, 1.0)
const COLOR_AOE: Color = Color(1.0, 0.55, 0.15)

var _cds: Dictionary = {}
## Efectos temporales activos: Array de diccionarios {objetivo: WeakRef,
## mod_id: String, tiempo: float}.
var _efectos: Array = []

## Fase 31 — puntos para subir skills (el Player suma 2 por nivel).
var puntos_skill: int = 0
## skill_id -> nivel (0 = no aprendida / ausente).
var _niveles: Dictionary = {}
## Clase configurada ("" = modo libre: todo conocido a nivel 1).
var _clase_id: String = ""


## Fija la clase: sus skills empiezan en 1, el resto en 0. Devuelve los
## puntos invertidos en niveles (2–20) de la clase anterior, como la purga
## de talentos. Repetir con la misma clase es no-op: no reinicia progreso.
func configurar_clase(clase_id: String) -> int:
	if _clase_id == clase_id:
		return 0
	var devueltos: int = 0
	for sid in _niveles:
		var n: int = int(_niveles[sid])
		if n > 1:
			devueltos += n - 1
	puntos_skill += devueltos
	_niveles.clear()
	_clase_id = clase_id
	for sid in SkillDB.skills_por_clase(clase_id):
		_niveles[sid] = 1
	return devueltos


## Nivel actual (0 si no aprendida o desconocida).
func nivel_de(skill_id: String) -> int:
	return maxi(0, int(_niveles.get(skill_id, 0)))


## ¿Se puede subir un nivel? "ok" | "desconocida" | "no_aprendida" |
## "max_nivel" | "sin_puntos".
func puede_subir(skill_id: String) -> String:
	if not SkillDB.existe(skill_id):
		return "desconocida"
	if nivel_de(skill_id) <= 0:
		return "no_aprendida"
	var mx: int = maxi(1, int(SkillDB.obtener(skill_id).get("max_nivel", 20)))
	if nivel_de(skill_id) >= mx:
		return "max_nivel"
	if puntos_skill <= 0:
		return "sin_puntos"
	return "ok"


## Gasta 1 punto_skill y sube un nivel. Retorna "ok" o el motivo.
func subir_nivel(skill_id: String) -> String:
	var motivo: String = puede_subir(skill_id)
	if motivo != "ok":
		return motivo
	puntos_skill -= 1
	_niveles[skill_id] = nivel_de(skill_id) + 1
	return "ok"


## Power con el nivel aplicado (daño/aoe). Sin configurar: base.
func power_efectivo(skill_id: String) -> float:
	var sk: Dictionary = SkillDB.obtener(skill_id)
	var bonus: int = maxi(0, nivel_de(skill_id) - 1)
	return float(sk.get("power", 1.0)) \
		+ float(sk.get("power_nivel", 0.0)) * float(bonus)


## Costo de maná con el nivel aplicado. Sin configurar: base.
func mana_efectivo(skill_id: String) -> float:
	var sk: Dictionary = SkillDB.obtener(skill_id)
	var bonus: int = maxi(0, nivel_de(skill_id) - 1)
	return float(sk.get("mana", 0.0)) \
		+ float(sk.get("mana_nivel", 0.0)) * float(bonus)


## Efecto principal con el nivel aplicado (curar/buff/debuff: cantidad).
## Sin configurar: base.
func cantidad_efectiva(skill_id: String) -> float:
	var sk: Dictionary = SkillDB.obtener(skill_id)
	var ef: Dictionary = sk.get("efecto", {})
	var bonus: int = maxi(0, nivel_de(skill_id) - 1)
	return float(ef.get("cantidad", 0.0)) \
		+ float(sk.get("power_nivel", 0.0)) * float(bonus)


## Copia del dict de la skill con power/maná/cantidad efectivos.
## (SkillDB.obtener devuelve el dict vivo del caché: no se muta.)
func _skill_efectiva(skill_id: String) -> Dictionary:
	var sk: Dictionary = SkillDB.obtener(skill_id).duplicate()
	sk["power"] = power_efectivo(skill_id)
	sk["mana"] = mana_efectivo(skill_id)
	var ef: Dictionary = (sk.get("efecto", {}) as Dictionary).duplicate()
	ef["cantidad"] = cantidad_efectiva(skill_id)
	sk["efecto"] = ef
	return sk


## Serialización versionada (bloque "skills" del save, v10).
func to_dict() -> Dictionary:
	var bloque: Dictionary = {}
	for sid in _niveles:
		bloque[str(sid)] = nivel_de(str(sid))
	return {"version": 1, "puntos_skill": puntos_skill, "niveles": bloque}


## Restaura puntos + niveles (tolerante: versión distinta → vacío).
## Registra la clase para que un futuro `configurar_clase` con la misma
## sea no-op (no purgue lo cargado).
func cargar_estado(d: Dictionary, clase_id: String = "") -> void:
	_niveles.clear()
	puntos_skill = 0
	_clase_id = clase_id
	if int(d.get("version", 0)) != 1:
		if not d.is_empty():
			push_warning("[SkillSystem] versión de bloque desconocida; se arranca vacío")
		return
	puntos_skill = maxi(0, int(d.get("puntos_skill", 0)))
	var bloque: Dictionary = d.get("niveles", {})
	for sid in bloque:
		var skill_id: String = str(sid)
		if not SkillDB.existe(skill_id):
			continue
		var mx: int = maxi(1, int(SkillDB.obtener(skill_id).get("max_nivel", 20)))
		var n: int = clampi(int(bloque[sid]), 0, mx)
		if n > 0:
			_niveles[skill_id] = n


## Descuenta los cooldowns (nunca bajan de 0) y expira buffs/debuffs.
func tick(delta: float) -> void:
	var d: float = maxf(delta, 0.0)
	for k in _cds.keys():
		_cds[k] = maxf(float(_cds[k]) - d, 0.0)
	_expirar_efectos(d)


func cooldown_restante(skill_id: String) -> float:
	return float(_cds.get(skill_id, 0.0))


## Fase 51: purga TODOS los efectos temporales (la mourte del héroe). Recorre
## `_efectos` al revés, quita el mod del StatBlock de cada objetivo vivo y
## vacía el array. Misma lógica que `_expirar_efectos` con d = infinito.
##
## Barre también los debuffs que el jugador le puso a los enemigos: al morir,
## el combate termina y dejar un debuff huérfano 20 s más es ruido, no
## contenido. Los objetivos ya liberados se limpian sin tocar nada.
func purgar_temporales() -> void:
	for i in range(_efectos.size() - 1, -1, -1):
		var ef: Dictionary = _efectos[i]
		var ent: Entity = (ef.get("objetivo") as WeakRef).get_ref() as Entity
		if ent != null and is_instance_valid(ent):
			ent.stats.remove_mod(str(ef.get("mod_id", "")))
	_efectos.clear()


## Fase 51: deja los cooldowns a cero. Sin esto, reaparecer con un skill en
## cooldown de 12 s es un castigo invisible por morir.
func purgar_cooldowns() -> void:
	_cds.clear()


## ¿El efecto necesita un objetivo enemigo válido? (dano, debuff, y aoe
## dirigido con rango > 0). Las curaciones, los buffs y el aoe centrado en
## el lanzador (rango == 0) no chequean objetivo ni rango.
## REGLA DURA (fase 5.1): las skills dañinas sobre NPCs se ignoran siempre.
func _requiere_objetivo(skill: Dictionary) -> bool:
	var efecto: Dictionary = skill.get("efecto", {})
	var tipo: String = str(efecto.get("tipo", ""))
	if tipo == "dano" or tipo == "debuff":
		return true
	if tipo == "aoe" and float(skill.get("rango", 0.0)) > 0.0:
		return true
	return false


## "" si se puede lanzar; si no, el motivo:
## "desconocida" | "no_aprendida" | "objetivo" | "no_combatible" |
## "rango" | "mana" | "cooldown".
## Fase 31: "no_aprendida" solo aplica en modo con clase (configurado);
## sin configurar, toda skill conocida lanza a nivel 1 (modo libre).
func puede_lanzar(skill_id: String, lanzador: Entity, objetivo: Entity) -> String:
	if not SkillDB.existe(skill_id):
		return "desconocida"
	if _clase_id != "" and nivel_de(skill_id) <= 0:
		return "no_aprendida"
	var skill: Dictionary = SkillDB.obtener(skill_id)
	if _requiere_objetivo(skill):
		if objetivo == null or not objetivo.esta_vivo():
			return "objetivo"
		if not objetivo.combatible:
			return "no_combatible"
		var rango: float = float(skill.get("rango", 0.0))
		if _dist_plana(lanzador, objetivo) > rango:
			return "rango"
	if lanzador.mana_actual < mana_efectivo(skill_id):
		return "mana"
	if cooldown_restante(skill_id) > 0.0:
		return "cooldown"
	return ""


## Intenta lanzar el skill. Si falla, emite skill_fallida(motivo) y false.
## Si tiene éxito: descuenta maná, arranca el cooldown, aplica el efecto
## según su tipo, dispara el feedback visual, emite skill_usada y true.
## `candidatos`: lista opcional de entidades para el aoe (los tests la
## inyectan); si viene vacía se usa el grupo "enemigos" del árbol.
func lanzar(skill_id: String, lanzador: Entity, objetivo: Entity, candidatos: Array = []) -> bool:
	var motivo: String = puede_lanzar(skill_id, lanzador, objetivo)
	if motivo != "":
		skill_fallida.emit(skill_id, motivo)
		return false
	var skill: Dictionary = _skill_efectiva(skill_id)
	var mana: float = float(skill.get("mana", 0.0))
	if not lanzador.gastar_mana(mana):
		skill_fallida.emit(skill_id, "mana")
		return false
	_cds[skill_id] = float(skill.get("cooldown", 0.0))
	var efecto: Dictionary = skill.get("efecto", {})
	var tipo: String = str(efecto.get("tipo", ""))
	match tipo:
		"curar":
			_aplicar_curar(skill_id, lanzador)
		"dano":
			if objetivo != null:
				_aplicar_dano(skill, lanzador, objetivo)
		"aoe":
			_aplicar_aoe(skill, lanzador, objetivo, candidatos)
		"buff":
			_aplicar_buff(skill_id, lanzador, efecto)
		"debuff":
			if objetivo != null:
				_aplicar_debuff(skill_id, objetivo, efecto)
		_:
			push_warning("[SkillSystem] tipo de efecto desconocido: '%s' en %s" % [tipo, skill_id])
	# Bloque 68: el proyectil VISUAL. Las skills de daño siguen siendo hitscan
	# (el daño no cambia: es una decisión de balance, no de efecto), pero ahora
	# se VE la flecha/lo que salga del arquero y del mago. Sin esto, atacar a
	# distancia se siente como pulsar un botón: falta el "va de camino".
	if (tipo == "dano" or tipo == "aoe") and lanzador is Node3D \
			and is_instance_valid(lanzador):
		var _escena: Node = (lanzador as Node3D).get_tree().current_scene
		var pv := ProyectilVisual.asegurar(_escena)
		if pv != null:
			# Que lleve proyectil lo decide el DATO ("proyectil": true), no
			# un umbral de alcance en el codigo: poner una flecha encima de un
			# enemigo cuerpo a cuerpo es un error visual, y eso lo sabe el
			# dato, no el sistema.
			if bool(skill.get("proyectil", false)):
				pv.disparar(lanzador, objetivo as Node3D, tipo == "aoe")
	# Fase 20: SFX del skill lanzado (un sonido por tipo de efecto).
	AudioJuego.al_skill(tipo)
	skill_usada.emit(skill_id)
	return true


## Fase 31: la fuente efectiva de la curación es `power_efectivo` (power
## base migrado 80/200 + `power_nivel` por nivel). `efecto.cantidad` se
## conserva en datos por compatibilidad pero ya no se lee aquí.
## Fase 35: la cura escala con el poder del lanzador (el INT del clérigo
## ya no solo da maná): ×(1 + poder/200). Acotado (poder 300 → ×2.5).
func _aplicar_curar(skill_id: String, lanzador: Entity) -> void:
	lanzador.heal(power_efectivo(skill_id) * bono_curacion(lanzador.stats.poder))
	lanzador.mostrar_fx(COLOR_CURAR)


## Multiplicador de curación por poder. Puro y testeable.
static func bono_curacion(poder: float) -> float:
	return 1.0 + maxf(poder, 0.0) / 200.0


func _aplicar_dano(skill: Dictionary, lanzador: Entity, objetivo: Entity) -> void:
	# Fase 51: sin Dictionary por golpe (ver Player.ejecutar_ataque).
	var res: Formulas.ResultadoDano = Formulas.damage_sin_alloc(
		lanzador.stats, objetivo.stats, skill, randf(), randf_range(-1.0, 1.0))
	objetivo.take_damage(float(res.final), lanzador, res.crit)


func _aplicar_aoe(skill: Dictionary, lanzador: Entity, objetivo: Entity, candidatos: Array) -> void:
	var efecto: Dictionary = skill.get("efecto", {})
	var radio: float = float(efecto.get("radio", 0.0))
	var centro: Vector3 = lanzador.global_position
	if objetivo != null and float(skill.get("rango", 0.0)) > 0.0:
		centro = objetivo.global_position
	var lista: Array = candidatos
	if lista.is_empty():
		var arbol: SceneTree = lanzador.get_tree()
		if arbol != null:
			lista = arbol.get_nodes_in_group("enemigos")
	for c in lista:
		if not (c is Entity):
			continue
		var e: Entity = c
		if not e.esta_vivo() or not e.combatible:
			continue
		if _dist_plana_puntos(centro, e.global_position) > radio:
			continue
		_aplicar_dano(skill, lanzador, e)
	lanzador.mostrar_fx(COLOR_AOE)
	# Un aoe que no golpea a nadie es un casteo fallido normal (sin
	# enemigos cerca): no es un error y no se avisa.


## Mapeo stat del JSON → stat derivado de StatBlock. "" = desconocido.
static func stat_derivado(stat_json: String) -> String:
	match stat_json:
		"ataque":
			return "ataque"
		"defensa":
			return "defensa"
		"crit":
			return "crit_prob"
		"velocidad":
			return "vel_mov"
	return ""


func _aplicar_buff(skill_id: String, lanzador: Entity, efecto: Dictionary) -> void:
	var derivado: String = stat_derivado(str(efecto.get("stat", "")))
	if derivado == "":
		push_warning("[SkillSystem] buff con stat desconocido en %s" % skill_id)
		return
	var cantidad: float = float(efecto.get("cantidad", 0.0))
	var duracion: float = float(efecto.get("duracion", 0.0))
	_registrar_efecto(lanzador, "buff:" + skill_id, derivado, cantidad, duracion)
	lanzador.mostrar_fx(COLOR_BUFF)


func _aplicar_debuff(skill_id: String, objetivo: Entity, efecto: Dictionary) -> void:
	var derivado: String = stat_derivado(str(efecto.get("stat", "")))
	if derivado == "":
		push_warning("[SkillSystem] debuff con stat desconocido en %s" % skill_id)
		return
	var cantidad: float = float(efecto.get("cantidad", 0.0))
	var duracion: float = float(efecto.get("duracion", 0.0))
	# (1 - cantidad): el objetivo pierde esa fracción del stat.
	_registrar_efecto(objetivo, "debuff:" + skill_id, derivado, -cantidad, duracion)
	objetivo.mostrar_fx(COLOR_DEBUFF)


## Aplica el mod porcentual y registra su expiración. Si el mismo mod ya
## estaba activo (reaplicar el skill), se refresca la duración sin
## acumularse.
func _registrar_efecto(entidad: Entity, mod_id: String, derivado: String, valor_pct: float, duracion: float) -> void:
	_retirar_efecto(mod_id, entidad)
	entidad.stats.add_mod(mod_id, derivado, StatBlock.ModKind.PORCENTUAL, valor_pct)
	if duracion > 0.0:
		_efectos.append({
			"objetivo": weakref(entidad),
			"mod_id": mod_id,
			"tiempo": duracion,
		})


## Descuenta la duración de los efectos; al expirar retira el mod del
## StatBlock de SU objetivo. Las referencias muertas (entidad liberada)
## se limpian sin hacer nada. Cada entrada se retira una sola vez.
func _expirar_efectos(d: float) -> void:
	var i: int = _efectos.size() - 1
	while i >= 0:
		var ef: Dictionary = _efectos[i]
		ef["tiempo"] = float(ef["tiempo"]) - d
		if float(ef["tiempo"]) <= 0.0:
			var ent: Entity = (ef.get("objetivo") as WeakRef).get_ref() as Entity
			if ent != null and is_instance_valid(ent):
				ent.stats.remove_mod(str(ef.get("mod_id", "")))
			_efectos.remove_at(i)
		i -= 1


## Retira el mod del objetivo y su registro (refresco al reaplicar el
## skill). Solo coincide el MISMO objetivo: si el mismo skill afecta a
## varias entidades, cada una expira por su cuenta (sin mods huérfanos).
func _retirar_efecto(mod_id: String, entidad: Entity) -> void:
	for j in range(_efectos.size() - 1, -1, -1):
		var ef: Dictionary = _efectos[j]
		if str(ef.get("mod_id", "")) != mod_id:
			continue
		var ref: Entity = (ef.get("objetivo") as WeakRef).get_ref() as Entity
		if ref == entidad or ref == null or not is_instance_valid(ref):
			_efectos.remove_at(j)
	if entidad != null and is_instance_valid(entidad):
		entidad.stats.remove_mod(mod_id)


## ¿Hay un efecto temporal activo con este mod_id? (tests).
func efecto_activo(mod_id: String) -> bool:
	for ef in _efectos:
		if str((ef as Dictionary).get("mod_id", "")) == mod_id:
			return true
	return false


## El Entity vivo y combatible más cercano al lanzador (distancia plana,
## ignora y). Los NPCs (no combatibles) nunca son candidatos. null si no
## hay ningún candidato vivo.
static func mas_cercano(lanzador: Entity, candidatos: Array) -> Entity:
	var mejor: Entity = null
	var mejor_d: float = INF
	for c in candidatos:
		if not (c is Entity):
			continue
		var e: Entity = c
		if not e.esta_vivo():
			continue
		if not e.combatible:
			continue
		var d: float = _dist_plana(lanzador, e)
		if d < mejor_d:
			mejor_d = d
			mejor = e
	return mejor


## Distancia 3D plana entre dos entidades (se ignora el eje y).
static func _dist_plana(a: Entity, b: Entity) -> float:
	return _dist_plana_puntos(a.global_position, b.global_position)


## Distancia plana entre dos puntos (se ignora el eje y).
static func _dist_plana_puntos(pa: Vector3, pb: Vector3) -> float:
	var dx: float = pa.x - pb.x
	var dz: float = pa.z - pb.z
	return sqrt(dx * dx + dz * dz)
