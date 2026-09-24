extends SceneTree
## Tests headless de la Fase 5.1 (selección, flash de daño, acercamiento de
## skills y REGLA DURA: los NPCs no se atacan). Fase 6.1: el botón flotante
## de atacar se retiró del HUD por pedido de Juan Diego; la acción "atacar"
## (Input Map, T por defecto) sigue existiendo y se testea aquí.
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_seleccion.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const NP: GDScript = preload("res://scripts/npc/npc.gd")
const ENT: GDScript = preload("res://scripts/core/entity.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const SS: GDScript = preload("res://scripts/skills/skill_system.gd")
const SDB: GDScript = preload("res://scripts/skills/skill_db.gd")
const IND: GDScript = preload("res://scripts/ui/indicador_seleccion.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _sel_count: int = 0
var _sel_ultima: Entity = null
var _daniados: int = 0
var _fallo_motivo: String = ""
var _usadas: Array[String] = []


func _init() -> void:
	print("[TEST] Fase 5.1 — seleccion, flash, boton atacar, skills con acercamiento, NPCs")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b): todo lo que
## usa global_position o get_tree() corre aquí.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	SDB.cargar()
	_t_seleccion()
	_t_indicador()
	_t_npc_no_atacable()
	_t_skill_no_combatible()
	_t_flash()
	_t_accion_atacar()
	_t_skill_acercamiento()
	_t_skill_pendiente_cancel_muerte()
	_t_skill_pendiente_cancel_deseleccion()
	_t_curacion_sin_moverse()
	_t_ataque_sin_seleccion_no_engancha()
	_t_skill_sin_seleccion_no_engancha()
	_t_autoataque_movil_guardado()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
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


func _al_seleccion(e: Entity) -> void:
	_sel_count += 1
	_sel_ultima = e


func _al_daniado(_cant: float, _fuente: Entity) -> void:
	_daniados += 1


func _al_fallida(_skill_id: String, motivo: String) -> void:
	_fallo_motivo = motivo


func _al_usada(skill_id: String) -> void:
	_usadas.append(skill_id)


func _entidad(pos: Vector3) -> Entity:
	var e: Entity = ENT.new(SB.new(10.0, 10.0, 10.0, 10.0))
	root.add_child(e)
	e.global_position = pos
	_basura.append(e)
	return e


func _enemigo(pos: Vector3) -> Enemy:
	var e: Enemy = EN.new()
	e.add_to_group("enemigos")
	root.add_child(e)
	e.global_position = pos
	_basura.append(e)
	return e


func _npc(pos: Vector3) -> NPC:
	var n: NPC = NP.new()
	n.add_to_group("npcs")
	root.add_child(n)
	n.global_position = pos
	_basura.append(n)
	return n


func _player(pos: Vector3, clase: String = "guerrero") -> Player:
	var p: Player = PL.new()
	# Fase 31: la clase antes del add_child (_ready configura las skills).
	p.clase_id = clase
	p.add_to_group("jugador")
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


## Selección/deselección + señal (idempotente) + los muertos no se eligen.
func _t_seleccion() -> void:
	var p: Player = _player(Vector3.ZERO)
	p.seleccion_cambiada.connect(_al_seleccion)
	_sel_count = 0
	var e: Enemy = _enemigo(Vector3(3, 0, 0))
	p.seleccionar(e)
	_check(p.seleccion == e, "seleccionar fija la entidad", "")
	_check(_sel_count == 1 and _sel_ultima == e, "seleccionar emite la señal una vez", "")
	p.seleccionar(e)
	_check(_sel_count == 1, "seleccionar lo mismo dos veces no re-emite", "")
	p.deseleccionar()
	_check(p.seleccion == null, "deseleccionar limpia", "")
	_check(_sel_count == 2 and _sel_ultima == null, "deseleccionar emite null", "")
	p.deseleccionar()
	_check(_sel_count == 2, "deseleccionar sin selección no emite", "")
	var muerto: Enemy = _enemigo(Vector3(5, 0, 0))
	muerto.die()
	p.seleccionar(muerto)
	_check(p.seleccion == null, "un muerto no se puede seleccionar", "")


## El indicador sigue a la selección y se oculta sin ella.
func _t_indicador() -> void:
	var p: Player = _player(Vector3.ZERO)
	var ind: IndicadorSeleccion = IND.new()
	root.add_child(ind)
	_basura.append(ind)
	ind.conectar(p)
	var e: Enemy = _enemigo(Vector3(4, 0, 2))
	p.seleccionar(e)
	_check(ind.objetivo() == e, "el indicador apunta a la selección", "")
	ind._process(0.016)
	_check(ind.visible, "el indicador es visible con selección", "")
	var px: Vector3 = ind.global_position
	_check(absf(px.x - 4.0) < 0.01 and absf(px.z - 2.0) < 0.01,
		"el indicador está bajo los pies del objetivo", "")
	p.deseleccionar()
	ind._process(0.016)
	_check(ind.objetivo() == null and not ind.visible,
		"sin selección el indicador se oculta", "")


## REGLA DURA: NPCs seleccionables pero jamás atacables (doble clic,
## botón, skill dañina → ignorados).
func _t_npc_no_atacable() -> void:
	var p: Player = _player(Vector3.ZERO)
	var n: NPC = _npc(Vector3(2, 0, 0))
	var en: Enemy = _enemigo(Vector3(3, 0, 0))
	_check(not n.combatible, "NPC: combatible = false", "")
	_check(en.combatible, "Enemy: combatible = true", "")
	# take_damage sobre no-combatible: se ignora TODO (vida, señales, flash).
	_daniados = 0
	n.daniado.connect(_al_daniado)
	var vida0: float = n.vida_actual
	n.take_damage(50.0, p)
	_check(n.vida_actual == vida0, "take_damage en NPC no quita vida", "")
	_check(_daniados == 0, "take_damage en NPC no emite daniado", "")
	_check(n.intensidad_flash() == 0.0, "take_damage en NPC no dispara flash", "")
	# El NPC SÍ se puede seleccionar…
	p.seleccionar(n)
	_check(p.seleccion == n, "el NPC se puede seleccionar", "")
	# …pero el botón/tecla de atacar lo ignora.
	p.solicitar_ataque()
	_check(p.objetivo_ataque == null, "solicitar_ataque ignora al NPC", "")
	# El helper del doble clic también lo rechaza.
	_check(p._es_objetivo_atacable(n) == null, "doble clic: NPC no atacable", "")
	_check(p._es_objetivo_atacable(en) == en, "doble clic: enemigo sí atacable", "")
	# Con un enemigo seleccionado, el ataque sí engancha.
	p.seleccionar(en)
	p.solicitar_ataque()
	_check(p.objetivo_ataque == en, "solicitar_ataque engancha al enemigo", "")


## SkillSystem: motivo "no_combatible" y mas_cercano filtra NPCs.
func _t_skill_no_combatible() -> void:
	var p: Player = _player(Vector3.ZERO)
	var s: SkillSystem = SS.new()
	s.skill_fallida.connect(_al_fallida)
	var n: NPC = _npc(Vector3(1, 0, 0))
	var en: Enemy = _enemigo(Vector3(9, 0, 0))
	_fallo_motivo = ""
	var vida0: float = n.vida_actual
	var ok: bool = s.lanzar("golpe_heroico", p, n)
	_check(not ok, "skill dañina sobre NPC falla", "")
	_check(_fallo_motivo == "no_combatible", "motivo = no_combatible",
		"fue '%s'" % _fallo_motivo)
	_check(n.vida_actual == vida0, "el NPC no recibe daño del skill", "")
	var cerca: Entity = SS.mas_cercano(p, [n, en])
	_check(cerca == en, "mas_cercano salta al NPC aunque esté más cerca", "")


## Flash rojo: estado en Entity que decae con el tiempo.
func _t_flash() -> void:
	var e: Entity = _entidad(Vector3.ZERO)
	_check(e.intensidad_flash() == 0.0, "sin daño no hay flash", "")
	e.take_damage(10.0, null)
	_check(e.intensidad_flash() > 0.0, "al recibir daño el flash se activa", "")
	e._process(0.1)
	var medio: float = e.intensidad_flash()
	_check(medio > 0.0 and medio < 1.0, "el flash decae con el tiempo",
		"intensidad=%.2f" % medio)
	e._process(1.0)
	_check(e.intensidad_flash() == 0.0, "el flash llega a cero", "")


## Fase 6.1: el botón flotante se retiró del HUD, pero la acción "atacar"
## sigue viva en el Input Map (T por defecto). Test de solo lectura: no
## muta el InputMap.
func _t_accion_atacar() -> void:
	_check(InputMap.has_action("atacar"),
		"la acción 'atacar' sigue existiendo en el Input Map", "")
	_check(_accion_tiene(84), "'atacar' trae T (84) por defecto del proyecto", "")
	var p: Player = _player(Vector3(700, 0, 700))
	_check(p.has_method("solicitar_ataque"),
		"Player.solicitar_ataque sigue disponible sin el botón", "")


func _accion_tiene(fisica: int) -> bool:
	for ev in InputMap.action_get_events("atacar"):
		if ev is InputEventKey and int((ev as InputEventKey).physical_keycode) == fisica:
			return true
	return false


## Skill fuera de rango: queda pendiente con orden de acercarse al objetivo;
## al llegar al rango se lanza. (Determinista: move_and_slide() en el
## harness --script no integra movimiento real, así que la llegada se
## simula; el movimiento físico ya lo cubren test_player + el playtest.)
## (Coordenadas lejanas: los grupos "enemigos"/"npcs" son globales y los
## nodos de tests anteriores siguen vivos hasta el final del archivo.)
func _t_skill_acercamiento() -> void:
	var p: Player = _player(Vector3(500, 0, 500), "mago")
	var en: Enemy = _enemigo(Vector3(500, 0, 520))
	p.skills.skill_usada.connect(_al_usada)
	_usadas.clear()
	var mana0: float = p.mana_actual
	# bola_fuego por id (fase 17): rango 12, maná 18. El objetivo está a 20.
	# Fase 18.4: el skill hostil necesita selección (se eliminó el fallback
	# al mob más cercano).
	p.seleccionar(en)
	p.lanzar_skill_id("bola_fuego")
	_check(p.tiene_lanzamiento_pendiente(), "skill fuera de rango queda pendiente", "")
	_check(p.mana_actual == mana0, "pendiente: aún no gasta maná", "")
	# La orden de acercamiento apunta al objetivo…
	p._physics_process(0.1)
	_check(p.tiene_lanzamiento_pendiente(), "lejos: el pendiente persiste", "")
	var d0: Vector3 = p._destino
	_check(d0.distance_to(Vector3(500, 0, 520)) < 0.01,
		"el destino de acercamiento es el objetivo", "")
	# …y lo sigue si se mueve.
	en.global_position = Vector3(500, 0, 530)
	p._physics_process(0.1)
	_check(p._destino.distance_to(Vector3(500, 0, 530)) < 0.01,
		"el destino sigue al objetivo en movimiento", "")
	# Al llegar al rango (simulamos la llegada), se lanza.
	p.global_position = Vector3(500, 0, 522) # a 8 del objetivo (rango 12)
	p._physics_process(0.1)
	_check(not p.tiene_lanzamiento_pendiente(), "en rango: el pendiente se resuelve", "")
	_check(_usadas.has("bola_fuego"), "al llegar al rango se lanza la bola_fuego", "")
	_check(en.vida_actual < en.stats.vida_max, "el objetivo recibe el daño", "")
	_check(p.mana_actual < mana0, "al lanzar sí gasta maná", "")


## El pendiente se cancela si el objetivo muere antes de llegar.
func _t_skill_pendiente_cancel_muerte() -> void:
	var p: Player = _player(Vector3(600, 0, 600), "mago")
	var en: Enemy = _enemigo(Vector3(600, 0, 620))
	p.skills.skill_usada.connect(_al_usada)
	_usadas.clear()
	var mana0: float = p.mana_actual
	# Fase 18.4: el skill hostil necesita selección (sin fallback al más cercano).
	p.seleccionar(en)
	p.lanzar_skill_id("bola_fuego")
	_check(p.tiene_lanzamiento_pendiente(), "pendiente creado (cancel-muerte)", "")
	en.die()
	p._physics_process(0.1)
	_check(not p.tiene_lanzamiento_pendiente(), "al morir el objetivo se cancela", "")
	_check(_usadas.is_empty(), "cancelado: no se lanza nada", "")
	_check(p.mana_actual == mana0, "cancelado: no gasta maná", "")


## El pendiente se cancela si se deselecciona el objetivo.
func _t_skill_pendiente_cancel_deseleccion() -> void:
	var p: Player = _player(Vector3(700, 0, 700), "mago")
	var en: Enemy = _enemigo(Vector3(700, 0, 720))
	p.seleccionar(en)
	p.lanzar_skill_id("bola_fuego")
	_check(p.tiene_lanzamiento_pendiente(), "pendiente creado (cancel-deselección)", "")
	p.deseleccionar()
	p._physics_process(0.1)
	_check(not p.tiene_lanzamiento_pendiente(), "al deseleccionar se cancela", "")


## Las curaciones se aplican al lanzador sin moverse ni pendientes.
func _t_curacion_sin_moverse() -> void:
	var p: Player = _player(Vector3.ZERO, "clerigo")
	p.take_damage(30.0, null)
	var vida_daniada: float = p.vida_actual
	# curacion_menor por id (fase 17). Sin objetivo: va al lanzador.
	p.lanzar_skill_id("curacion_menor")
	_check(not p.tiene_lanzamiento_pendiente(), "la curación no genera pendiente", "")
	_check(p.vida_actual > vida_daniada, "la curación se aplica al lanzador", "")
	_check(p.global_position == Vector3.ZERO, "el jugador no se mueve al curarse", "")


## Botón sin selección: NO engancha a ningún mob (fase 18.4: el
## auto-ataque al más cercano se eliminó por pedido de Juan Diego — sin
## seleccionar, apretar atacar no hace nada).
func _t_ataque_sin_seleccion_no_engancha() -> void:
	var p: Player = _player(Vector3(200, 0, 200))
	var en: Enemy = _enemigo(Vector3(200, 0, 205))
	p.solicitar_ataque()
	_check(p.objetivo_ataque == null, "sin selección: no fija objetivo", "")
	_check(p.seleccion == null, "sin selección: no selecciona nada", "")
	_check(not p._tiene_destino, "sin selección: no ordena caminar", "")
	# Con el mob seleccionado, el ataque sí engancha (modelo Flyff intacto).
	p.seleccionar(en)
	p.solicitar_ataque()
	_check(p.objetivo_ataque == en, "con selección: engancha al seleccionado", "")


## Skill hostil sin selección: no fija objetivo, no camina, no gasta maná
## (fase 18.4: se eliminó el fallback al mob más cercano).
func _t_skill_sin_seleccion_no_engancha() -> void:
	var p: Player = _player(Vector3(800, 0, 800), "mago")
	_enemigo(Vector3(800, 0, 805))
	var mana0: float = p.mana_actual
	p.lanzar_skill_id("bola_fuego")
	_check(not p.tiene_lanzamiento_pendiente(), "skill sin selección: sin pendiente", "")
	_check(p.objetivo_ataque == null, "skill sin selección: sin objetivo", "")
	_check(not p._tiene_destino, "skill sin selección: no ordena caminar", "")
	_check(p.mana_actual == mana0, "skill sin selección: no gasta maná", "")


## El camino guardado para la versión móvil sigue funcionando cuando se
## activa el flag (en PC va apagado por defecto).
func _t_autoataque_movil_guardado() -> void:
	# Coordenadas propias: otros tests ya dejaron enemigos en (200,0,205)
	# y el empate de distancia lo ganaría el viejo.
	var p: Player = _player(Vector3(250, 0, 250))
	var en: Enemy = _enemigo(Vector3(250, 0, 255))
	Player.autoataque_movil = true
	p.solicitar_ataque()
	_check(p.objetivo_ataque == en, "modo móvil: atacar engancha al más cercano", "")
	_check(p.seleccion == en, "modo móvil: también lo selecciona", "")
	var p2: Player = _player(Vector3(450, 0, 450), "mago")
	var en2: Enemy = _enemigo(Vector3(450, 0, 470))
	p2.lanzar_skill_id("bola_fuego")
	_check(p2.objetivo_ataque == en2, "modo móvil: skill engancha al más cercano", "")
	Player.autoataque_movil = false
	var p3: Player = _player(Vector3(650, 0, 650))
	_enemigo(Vector3(650, 0, 655))
	p3.solicitar_ataque()
	_check(p3.objetivo_ataque == null, "modo PC (flag apagado): no engancha", "")
