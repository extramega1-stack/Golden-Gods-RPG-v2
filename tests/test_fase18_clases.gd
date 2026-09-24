extends SceneTree
## Tests headless de la Fase 18 (4 clases: sistemas, UI, save).
##
## Cómo correrlos (un solo comando, ~3 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase18_clases.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)
##
## Cubre:
## (a) SkillDB.skills_por_clase: 8 skills por cada clase jugable y el campo
##     "clase" del JSON coincide; "daguero" no es jugable.
## (b) Player: clase por defecto "guerrero"; skills_clase() = los 8 del
##     guerrero; lanzar_skill(i) usa la clase (mago: índice 0 =
##     descarga_arcana).
## (c) Cooldowns por skill (se descuentan con tick, no bajan de 0).
## (d) Save v7: round-trip guarda "clase_id" y version 7; partida v6 sin
##     clase_id carga "guerrero" (tolerante); v6 con clase_id la respeta;
##     clase_id desconocida cae a "guerrero".
## (e) Buff/debuff: aplican el mod porcentual, expiran con tick (el stat
##     vuelve a su base) y reaplicar refresca sin acumular.
## (f) Aoe: golpea a varios enemigos en el radio, ignora al fuera de rango
##     y nunca toca NPCs (REGLA DURA); el aoe centrado (rango 0) no necesita
##     objetivo.
## (g) Curar: restaura vida al lanzador + feedback visual (fx_tiempo > 0).
## (h) BarraAcciones: el layout por defecto usa los skills de la clase del
##     jugador conectado; el libro se filtra por clase.
## El drag & drop real y el tinte en pantalla se validan en el playtest de
## Juan Diego.

const SDB: GDScript = preload("res://scripts/skills/skill_db.gd")
const SS: GDScript = preload("res://scripts/skills/skill_system.gd")
const ENT: GDScript = preload("res://scripts/core/entity.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const NP: GDScript = preload("res://scripts/npc/npc.gd")
const CDB: GDScript = preload("res://scripts/player/clase_db.gd")
const SV: GDScript = preload("res://scripts/save/save_system.gd")
const BA: GDScript = preload("res://scripts/ui/barra_acciones.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 18 — 4 clases: skills, buffs, aoe, save v7, barra")
	SDB.cargar()
	CDB.cargar()
	_t_por_clase()


var _empezo: bool = false


## Los Entity necesitan el árbol para global_position (lección 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_defecto_guerrero()
	_t_cooldowns()
	_t_save_v7()
	_t_save_v6_tolerante()
	_t_buff_expira()
	_t_debuff_expira()
	_t_debuff_dos_objetivos()
	_t_aoe_multiple()
	_t_aoe_npc_intocable()
	_t_curar_fx()
	_t_barra_por_clase()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).free()
	DirAccess.remove_absolute("user://partida.json")
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
	return true


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		if detalle != "":
			printerr("[FALLO] %s — %s" % [nombre, detalle])
		else:
			printerr("[FALLO] %s" % nombre)


## --- Helpers ---

## Player en el árbol con la clase aplicada (stats reales de la clase).
func _player_clase(cid: String, pos: Vector3) -> Player:
	var p: Player = PL.new()
	p.fijar_identidad("Test", cid)
	p.aplicar_clase(cid)
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


func _enemigo(pos: Vector3) -> Enemy:
	var e: Enemy = EN.new()
	root.add_child(e)
	e.global_position = pos
	e.add_to_group("enemigos")
	_basura.append(e)
	return e


func _npc(pos: Vector3) -> NPC:
	var n: NPC = NP.new()
	root.add_child(n)
	n.global_position = pos
	_basura.append(n)
	return n


## --- (a) 8 skills por clase ---

func _t_por_clase() -> void:
	var jugables: Array[String] = CDB.jugables()
	_check(jugables == ["guerrero", "arquero", "mago", "clerigo"],
		"jugables: 4 en orden (daguero fuera)",
		str(jugables))
	for cid in jugables:
		var ids: Array[String] = SDB.skills_por_clase(cid)
		_check(ids.size() == 8, "8 skills para %s" % cid, str(ids.size()))
		for sid in ids:
			var sk: Dictionary = SDB.obtener(sid)
			var c: String = str(sk.get("clase", ""))
			_check(c == "" or c == cid,
				"skill %s pertenece a %s" % [sid, cid], "clase='%s'" % c)
	_check(not CDB.es_jugable("daguero"), "daguero no es jugable")
	_check(SDB.skills_por_clase("inexistente").is_empty(),
		"clase desconocida → lista vacía")


## --- (b) clase por defecto guerrero ---

func _t_defecto_guerrero() -> void:
	var p: Player = _player_clase("guerrero", Vector3.ZERO)
	_check(p.clase_id == "guerrero", "clase por defecto: guerrero")
	var ids: Array[String] = p.skills_clase()
	_check(ids.size() == 8 and ids[0] == "golpe_heroico",
		"skills_clase guerrero: 8, primero golpe_heroico", str(ids))
	var m: Player = _player_clase("mago", Vector3(20, 0, 0))
	var mids: Array[String] = m.skills_clase()
	_check(mids.size() == 8 and mids[0] == "descarga_arcana",
		"skills_clase mago: 8, primero descarga_arcana", str(mids))
	# lanzar_skill(i) resuelve por clase: el índice 0 del mago no es el
	# del guerrero (el hotbar ya no es global).
	_check(mids[0] != ids[0], "hotbar por clase: mago[0] != guerrero[0]")


## --- (c) cooldowns ---

func _t_cooldowns() -> void:
	var p: Player = _player_clase("clerigo", Vector3(40, 0, 0))
	var ss: SkillSystem = p.skills
	p.vida_actual = p.stats.vida_max * 0.5
	_check(ss.lanzar("curacion_menor", p, null), "curar: casteo ok")
	_check(ss.cooldown_restante("curacion_menor") > 0.0,
		"cooldown arranca > 0")
	_check(not ss.lanzar("curacion_menor", p, null),
		"cooldown: segundo casteo inmediato falla")
	ss.tick(30.0)
	_check(ss.cooldown_restante("curacion_menor") == 0.0,
		"cooldown: tick largo lo deja en 0")
	_check(ss.lanzar("curacion_menor", p, null),
		"cooldown: tras expirar se puede castear")


## --- (d) save v9 ---

func _t_save_v7() -> void:
	var p: Player = _player_clase("mago", Vector3(1, 0, 2))
	p.fijar_identidad("Ilya", "mago")
	# Fase 28: 1 punto de talento gastado antes de guardar.
	p.gain_xp(100000)
	_check(p.talentos.subir("mente_arcana", p.stats, p.nivel, "mago") == "ok",
		"save v9: talento comprado antes de guardar")
	var s: SaveSystem = SV.new()
	s.jugador = p
	s.enemigos = []
	s.npcs = []
	s.tienda = null
	s.misiones = null
	s.barra_acciones = null
	_check(s.guardar(), "save v9: guardar() true")
	var crudo: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.RUTA))
	var version: int = int((crudo as Dictionary).get("version", 0))
	_check(version == 9, "save v9: version 9 en disco", "version=%d" % version)
	var dj: Dictionary = (crudo as Dictionary).get("jugador", {})
	_check(str(dj.get("clase_id", "")) == "mago", "save v9: clase_id guardada")
	var p2: Player = PL.new()
	var s2: SaveSystem = SV.new()
	s2.jugador = p2
	_check(s2.cargar(), "save v9: cargar() true")
	_check(p2.clase_id == "mago", "save v9: clase_id restaurada", p2.clase_id)
	_check(p2.nombre == "Ilya", "save v9: nombre restaurado")
	_check(p2.talentos.rango_de("mente_arcana") == 1,
		"save v9: rango de talento restaurado")
	_check(p2.stats.has_mod("talento:mente_arcana"),
		"save v9: mod de talento aplicado")


## Partida v6 (sin clase_id) → "guerrero"; con clase_id se respeta;
## clase_id desconocida → "guerrero".
func _escribir_v6(clase_id: Variant) -> void:
	var dj: Dictionary = {
		"entidad": {},
		"oro": 0,
		"nombre": "Viejo",
		"pos": [0.0, 0.0, 0.0],
	}
	if clase_id != null:
		dj["clase_id"] = str(clase_id)
	var datos: Dictionary = {"version": 6, "jugador": dj, "enemigos": []}
	var f: FileAccess = FileAccess.open(SaveSystem.RUTA, FileAccess.WRITE)
	f.store_string(JSON.stringify(datos))
	f.close()


func _cargar_clase_dict() -> String:
	var p: Player = PL.new()
	var s: SaveSystem = SV.new()
	s.jugador = p
	s.cargar()
	_basura.append(p)
	return p.clase_id


func _t_save_v6_tolerante() -> void:
	_escribir_v6(null)
	_check(_cargar_clase_dict() == "guerrero",
		"save v6 sin clase_id → guerrero por defecto")
	_escribir_v6("clerigo")
	_check(_cargar_clase_dict() == "clerigo",
		"save v6 con clase_id la respeta")
	_escribir_v6("paladin_inexistente")
	_check(_cargar_clase_dict() == "guerrero",
		"save v6 con clase_id desconocida → guerrero")


## --- (e) buff expira ---

func _t_buff_expira() -> void:
	var p: Player = _player_clase("guerrero", Vector3(60, 0, 0))
	var ss: SkillSystem = p.skills
	var base: float = p.stats.ataque
	_check(ss.lanzar("grito_guerra", p, null), "buff: grito_guerra ok")
	_check(ss.efecto_activo("buff:grito_guerra"), "buff: efecto registrado")
	_check(is_equal_approx(p.stats.ataque, base * 1.25),
		"buff: ataque ×1.25", "ataque=%.2f base=%.2f" % [p.stats.ataque, base])
	_check(p.fx_tiempo > 0.0, "buff: feedback visual en el lanzador")
	ss.tick(5.0)
	_check(ss.efecto_activo("buff:grito_guerra"),
		"buff: sigue activo a los 5s (dura 10s)")
	# Reaplicar antes de expirar refresca la duración sin acumular el mod.
	# Se simula el cooldown ya cumplido (en datos el cd 20s > duración
	# 10s, así que en juego no se puede reaplicar antes de que expire).
	ss._cds["grito_guerra"] = 0.0
	_check(ss.lanzar("grito_guerra", p, null), "buff: reaplicar ok")
	_check(is_equal_approx(p.stats.ataque, base * 1.25),
		"buff: reaplicar no acumula", "ataque=%.2f" % p.stats.ataque)
	ss.tick(9.0)
	_check(ss.efecto_activo("buff:grito_guerra"),
		"buff: tras refrescar sigue activo 9s después")
	ss.tick(2.0)
	_check(not ss.efecto_activo("buff:grito_guerra"), "buff: expiró")
	_check(is_equal_approx(p.stats.ataque, base),
		"buff: el stat vuelve a su base", "ataque=%.2f base=%.2f" % [p.stats.ataque, base])


## --- (e2) debuff expira ---

func _t_debuff_expira() -> void:
	var p: Player = _player_clase("mago", Vector3(80, 0, 0))
	var e: Enemy = _enemigo(Vector3(84, 0, 0))
	var ss: SkillSystem = p.skills
	var base: float = e.stats.vel_mov
	# prision_hielo: rango 10, debuff velocidad -50% durante 5s.
	_check(ss.lanzar("prision_hielo", p, e), "debuff: prision_hielo ok")
	_check(ss.efecto_activo("debuff:prision_hielo"), "debuff: efecto registrado")
	_check(is_equal_approx(e.stats.vel_mov, base * 0.5),
		"debuff: vel_mov ×0.5", "vel=%.2f base=%.2f" % [e.stats.vel_mov, base])
	_check(e.fx_tiempo > 0.0, "debuff: feedback visual en el objetivo")
	ss.tick(6.0)
	_check(not ss.efecto_activo("debuff:prision_hielo"), "debuff: expiró")
	_check(is_equal_approx(e.stats.vel_mov, base),
		"debuff: el stat vuelve a su base")


## El mismo debuff sobre dos enemigos expira por separado: no quedan
## mods huérfanos en el segundo objetivo.
func _t_debuff_dos_objetivos() -> void:
	var p: Player = _player_clase("mago", Vector3(70, 0, 0))
	var e1: Enemy = _enemigo(Vector3(74, 0, 0))
	var e2: Enemy = _enemigo(Vector3(76, 0, 0))
	var ss: SkillSystem = p.skills
	var base: float = e1.stats.vel_mov
	_check(ss.lanzar("prision_hielo", p, e1), "debuff: a e1 ok")
	ss._cds["prision_hielo"] = 0.0 # simula el cooldown cumplido
	_check(ss.lanzar("prision_hielo", p, e2), "debuff: a e2 ok")
	# prision_hielo: debuff de velocidad ×0.5 (cantidad 0.5) durante 5 s.
	_check(is_equal_approx(e1.stats.vel_mov, base * 0.5), "debuff: e1 al 50%")
	_check(is_equal_approx(e2.stats.vel_mov, base * 0.5), "debuff: e2 al 50%")
	ss.tick(6.0) # duración 5 s: ambos expiran en la misma pasada
	_check(is_equal_approx(e1.stats.vel_mov, base), "debuff: e1 recupera")
	_check(is_equal_approx(e2.stats.vel_mov, base),
		"debuff: e2 recupera (sin mod huérfano)",
		"vel=%.2f base=%.2f" % [e2.stats.vel_mov, base])
	_check(not ss.efecto_activo("debuff:prision_hielo"),
		"debuff: sin efectos activos")


## --- (f) aoe golpea múltiples ---

func _t_aoe_multiple() -> void:
	var p: Player = _player_clase("guerrero", Vector3(100, 0, 0))
	var e1: Enemy = _enemigo(Vector3(101, 0, 0))
	var e2: Enemy = _enemigo(Vector3(103, 0, 0))
	var e3: Enemy = _enemigo(Vector3(110, 0, 0))
	var v1: float = e1.vida_actual
	var v2: float = e2.vida_actual
	var v3: float = e3.vida_actual
	var ss: SkillSystem = p.skills
	# torbellino: aoe centrado en el lanzador (rango 0), radio 4.
	_check(ss.lanzar("torbellino", p, null, [e1, e2, e3]),
		"aoe: torbellino sin objetivo ok")
	_check(e1.vida_actual < v1 and e2.vida_actual < v2,
		"aoe: golpea a los 2 en el radio")
	_check(is_equal_approx(e3.vida_actual, v3),
		"aoe: no toca al fuera del radio")
	_check(p.fx_tiempo > 0.0, "aoe: feedback visual en el lanzador")


## El aoe nunca toca NPCs (REGLA DURA) ni muertos.
func _t_aoe_npc_intocable() -> void:
	var p: Player = _player_clase("clerigo", Vector3(120, 0, 0))
	var npc: NPC = _npc(Vector3(121, 0, 0))
	var e: Enemy = _enemigo(Vector3(122, 0, 0))
	var muerto: Enemy = _enemigo(Vector3(121, 0, 1))
	muerto.take_damage(99999.0, null)
	var vn: float = npc.vida_actual
	var ve: float = e.vida_actual
	var ss: SkillSystem = p.skills
	# nova_sagrada: aoe centrado (rango 0), radio 4.
	_check(ss.lanzar("nova_sagrada", p, null, [npc, e, muerto]),
		"aoe: nova_sagrada ok")
	_check(is_equal_approx(npc.vida_actual, vn),
		"aoe: el NPC no recibe daño (REGLA DURA)")
	_check(e.vida_actual < ve, "aoe: el enemigo sí recibe daño")
	_check(not muerto.esta_vivo(), "aoe: el muerto sigue muerto")


## --- (g) curar + fx ---

func _t_curar_fx() -> void:
	var p: Player = _player_clase("clerigo", Vector3(140, 0, 0))
	p.vida_actual = p.stats.vida_max - 120.0
	var antes: float = p.vida_actual
	var ss: SkillSystem = p.skills
	_check(ss.lanzar("curacion_menor", p, null), "curar: casteo ok")
	_check(p.vida_actual > antes, "curar: restaura vida")
	_check(p.fx_tiempo > 0.0 and p.intensidad_fx() > 0.0,
		"curar: feedback visual activo")


## --- (h) barra por clase ---

func _t_barra_por_clase() -> void:
	var p: Player = _player_clase("mago", Vector3(160, 0, 0))
	var b: BarraAcciones = BA.new()
	root.add_child(b)
	_basura.append(b)
	b.conectar(p)
	b.restablecer_defecto()
	var s1: Dictionary = b.obtener(1)
	_check(str(s1.get("id", "")) == "descarga_arcana",
		"barra: defecto del mago = descarga_arcana en F2", str(s1))
	var todos_mago: bool = true
	for i in range(1, 8):
		var sid: String = str(b.obtener(i).get("id", ""))
		if sid != "" and str(SDB.obtener(sid).get("clase", "")) != "mago":
			todos_mago = false
	_check(todos_mago, "barra: slots F2..F8 solo skills de mago")
	# El libro filtra por clase: 8 chips de mago.
	b.reconstruir_libro()
	var chips: int = 0
	for h in b._libro_caja.get_children():
		if h is BarraAcciones.ChipArrastre:
			chips += 1
			var sid: String = str((h as BarraAcciones.ChipArrastre).datos.get("id", ""))
			if str(SDB.obtener(sid).get("clase", "")) != "mago":
				chips = -99
	_check(chips == 8, "libro: 8 chips filtrados a mago", "chips=%d" % chips)
	# Sin conexión: cae al guerrero por defecto.
	var b2: BarraAcciones = BA.new()
	_basura.append(b2)
	b2.restablecer_defecto()
	_check(str(b2.obtener(1).get("id", "")) == "golpe_heroico",
		"barra: sin jugador, defecto = guerrero")
