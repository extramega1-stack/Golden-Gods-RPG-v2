extends SceneTree
## Tests headless de la Fase 39 (tutorial guiado).
##
## Cubre: 6 pasos como datos que avanzan por eventos (mover por posición,
## atacar/skill/poción/hablar/misión por señales), fotos anti-falso-positivo
## (el loot no avanza poción; matar no acepta misiones), toasts en orden,
## persistencia versionada y regla de veterano (save < v11 → hecho).
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase39_tutorial.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const TU: GDScript = preload("res://scripts/tutorial/tutorial.gd")
const QL: GDScript = preload("res://scripts/quests/quest_log.gd")
const SS: GDScript = preload("res://scripts/save/save_system.gd")
const NPC: GDScript = preload("res://scripts/npc/npc.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []
var _toasts: Array[String] = []


func _init() -> void:
	print("[TEST] Fase 39 — tutorial guiado")
	QuestDB.cargar()
	ItemDB.cargar()


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_pasos()
	_test_fotos()
	_test_persistencia()
	_test_save()
	print("[TEST] fase39_tutorial: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	DirAccess.remove_absolute("user://partida.json")
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _toast(texto: String) -> void:
	_toasts.append(texto)


func _kit() -> Array:
	var p: Player = PL.new()
	p.fijar_identidad("T", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	var m: QuestLog = QL.new()
	_basura.append(m)
	var t: Tutorial = TU.new()
	root.add_child(t)
	_basura.append(t)
	_toasts.clear()
	t.conectar(p, m, _toast)
	return [p, m, t]


## Los 6 pasos avanzan en orden con sus eventos y los toasts salen en orden.
func _test_pasos() -> void:
	var kit: Array = _kit()
	var p: Player = kit[0]
	var m: QuestLog = kit[1]
	var t: Tutorial = kit[2]
	t.empezar()
	_chk(t.paso_actual() == 0, "pasos: arranca en mover")
	_chk(_toasts == [str(Tutorial.PASOS[0].get("texto", ""))],
		"pasos: prompt mover", str(_toasts))
	# Mover: teletransporte + tick manual (determinista, sin frames extra).
	p.global_position = Vector3(5, 0, 0)
	t._process(0.016)
	_chk(t.paso_actual() == 1, "pasos: mover avanza")
	p.intencion_atacar.emit(null)
	_chk(t.paso_actual() == 2, "pasos: atacar avanza")
	p.skills.skill_usada.emit("golpe_heroico")
	_chk(t.paso_actual() == 3, "pasos: skill avanza")
	p.inventario.agregar("pocion_vida", 1)
	_chk(p.inventario.usar("pocion_vida", p), "pasos: setup poción usable")
	_chk(t.paso_actual() == 4, "pasos: poción avanza")
	var npc: NPC = NPC.new()
	_basura.append(npc)
	p.hablar_con.emit(npc)
	_chk(t.paso_actual() == 5, "pasos: hablar avanza")
	var qid: String = QuestDB.ids()[0]
	_chk(m.aceptar(qid) == "ok", "pasos: setup misión aceptable", qid)
	_chk(t.hecho() and t.paso_actual() == -1, "pasos: misión termina")
	_chk(_toasts[_toasts.size() - 1] == Tutorial.TEXTO_FINAL,
		"pasos: toast final", _toasts[_toasts.size() - 1])
	_chk(_toasts.size() == 7, "pasos: 6 prompts + final", str(_toasts.size()))


## Anti-falso-positivo: el loot no avanza poción; matar no acepta misiones.
func _test_fotos() -> void:
	var kit: Array = _kit()
	var p: Player = kit[0]
	var t: Tutorial = kit[2]
	t.empezar()
	p.global_position = Vector3(5, 0, 0)
	t._process(0.016)
	p.intencion_atacar.emit(null)
	p.skills.skill_usada.emit("golpe_heroico")
	_chk(t.paso_actual() == 3, "fotos: setup en poción")
	# Lootear (agregar) dispara cambiado pero no descuenta: no avanza.
	p.inventario.agregar("pocion_vida", 3)
	_chk(t.paso_actual() == 3, "fotos: loot no avanza poción")
	# Herir no usa poción: tampoco avanza.
	p.take_damage(10.0, null)
	_chk(t.paso_actual() == 3, "fotos: daño no avanza poción")


## Round-trip del bloque: hecho y paso a medias sobreviven.
func _test_persistencia() -> void:
	var kit: Array = _kit()
	var t: Tutorial = kit[2]
	t.empezar()
	var p: Player = kit[0]
	p.global_position = Vector3(5, 0, 0)
	t._process(0.016)
	var d: Dictionary = t.to_dict()
	_chk(int(d.get("version", 0)) == 1, "save: version 1")
	var t2: Tutorial = TU.new()
	_basura.append(t2)
	t2.cargar_estado(d)
	_chk(not t2.hecho() and t2.paso_actual() == 1,
		"save: paso a medias sobrevive")
	var fin: Dictionary = {"version": 1, "hecho": true, "paso": 99}
	var t3: Tutorial = TU.new()
	_basura.append(t3)
	t3.cargar_estado(fin)
	_chk(t3.hecho() and t3.paso_actual() == -1, "save: hecho manda")


## SaveSystem v11: bloque tutorial + regla de veterano (< v11 → hecho).
func _test_save() -> void:
	DirAccess.remove_absolute("user://partida.json")
	var p: Player = PL.new()
	p.fijar_identidad("T", "guerrero")
	root.add_child(p)
	_basura.append(p)
	var t: Tutorial = TU.new()
	root.add_child(t)
	_basura.append(t)
	var s: SaveSystem = SS.new()
	s.jugador = p
	s.tutorial = t
	_chk(SaveSystem.SAVE_VERSION == 11, "save: versión 11")
	_chk(s.guardar(), "save: guarda con tutorial")
	var crudo: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("user://partida.json"))
	var datos: Dictionary = crudo
	_chk(bool((datos.get("tutorial", {}) as Dictionary).get("hecho", true)) == false,
		"save: bloque tutorial presente", str(datos.get("tutorial", {})))
	# Carga fresca: hecho=false.
	var p2: Player = PL.new()
	root.add_child(p2)
	_basura.append(p2)
	var t2: Tutorial = TU.new()
	root.add_child(t2)
	_basura.append(t2)
	var s2: SaveSystem = SS.new()
	s2.jugador = p2
	s2.tutorial = t2
	_chk(s2.cargar(), "save: carga v11")
	_chk(not t2.hecho(), "save: hecho=false restaurado")
	# Veterano: mismo archivo con versión 10 y sin bloque → hecho.
	datos["version"] = 10
	datos.erase("tutorial")
	var f: FileAccess = FileAccess.open("user://partida.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(datos))
	f.close()
	var t3: Tutorial = TU.new()
	_basura.append(t3)
	var s3: SaveSystem = SS.new()
	s3.jugador = p2
	s3.tutorial = t3
	_chk(s3.cargar(), "save: carga v10 tolerante")
	_chk(t3.hecho(), "save: veterano sin prompts")
