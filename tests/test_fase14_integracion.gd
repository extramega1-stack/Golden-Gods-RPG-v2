extends SceneTree
## Tests headless de la Fase 14 (INTEGRACIÓN — Moon Town en la demo).
##
## Blinda que las piezas de la fase 14 encajan en la demo principal:
## `fase14_demo` hereda de `fase12_demo`, construye `CiudadLuna` con el
## terreno ANTES del add_child (contrato de su API), el jugador aparece en
## `punto_aparicion_jugador()` con `yaw_aparicion()`, los NPCs Ilya/Bram/
## Sira se recolocan en `npc_spawn(id)`, el título abre la demo fase14 y
## `data/npcs.json` ya no menciona la ciudad vieja. La lógica fina de cada
## pieza la cubren test_fase14_terreno y test_fase14_ciudad.
##
## Cómo correrlo:
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase14_integracion.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.

const CL: GDScript = preload("res://scripts/mundo/ciudad_luna.gd")
const TG: GDScript = preload("res://scripts/mundo/terreno.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 14 — integración de Moon Town en la demo")


func _check(cond: bool, nombre: String) -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		push_error("[FALLO] " + nombre)


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_escena_y_titulo()
	_t_script_demo()
	_t_npcs_texto()
	_t_ciudad_y_terreno()
	print("[TEST] integración fase 14: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
	return true


## 1. Contrato de escena: la tscn fase14 y el título apuntan a la demo nueva.
func _t_escena_y_titulo() -> void:
	var tscn: String = FileAccess.get_file_as_string("res://scenes/demo/fase14_demo.tscn")
	_check(not tscn.is_empty(), "fase14_demo.tscn legible")
	_check(tscn.find("fase14_demo.gd") >= 0, "tscn usa fase14_demo.gd")
	_check(tscn.find("scripts/mundo/terreno.gd") >= 0, "tscn incluye Terreno")
	_check(tscn.find("scripts/mundo/ciclo_dia.gd") >= 0, "tscn incluye CicloDia")
	_check(tscn.find("scripts/mundo/vigia_region.gd") >= 0, "tscn incluye VigiaRegion")
	_check(tscn.find("scripts/ui/banner_region.gd") >= 0, "tscn incluye BannerRegion")
	_check(tscn.find("Goblin1") < 0, "tscn sin enemigos fijos (los da spawns.json)")
	_check(tscn.find("far = 40000.0") >= 0, "cámara con far 40000 para el mundo")
	var titulo: String = FileAccess.get_file_as_string("res://scripts/ui/pantalla_titulo.gd")
	_check(titulo.find("fase14_demo.tscn") >= 0, "el título abre fase14_demo")
	_check(titulo.find("fase12_demo.tscn") < 0, "el título ya no abre fase12_demo")


## 2. El script de la demo hereda de fase12 y usa la API de CiudadLuna.
func _t_script_demo() -> void:
	var gd: String = FileAccess.get_file_as_string("res://scenes/demo/fase14_demo.gd")
	_check(gd.find("fase12_demo.gd") >= 0, "fase14_demo hereda de fase12_demo")
	_check(gd.find("CiudadLuna.new()") >= 0, "la demo crea CiudadLuna")
	_check(gd.find(".terreno = $Terreno") >= 0, "asigna terreno ANTES del add_child")
	_check(gd.find("add_child(_ciudad)") >= 0, "añade la ciudad al árbol")
	_check(gd.find("punto_aparicion_jugador()") >= 0, "usa punto_aparicion_jugador()")
	_check(gd.find("yaw_aparicion()") >= 0, "usa yaw_aparicion()")
	_check(gd.find("npc_spawn(") >= 0, "recoloca NPCs con npc_spawn()")
	_check(gd.find("super._ready()") >= 0, "conserva el flujo fase 12 (super)")


## 3. data/npcs.json habla de Moon Town (texto; la lógica no se toca).
func _t_npcs_texto() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/npcs.json")
	_check(not raw.is_empty(), "npcs.json legible")
	_check(raw.find("Piedraceniza") < 0, "sin menciones a Piedraceniza")
	_check(raw.find("Moon Town") >= 0, "menciona Moon Town")
	var parsed: Variant = JSON.parse_string(raw)
	_check(parsed is Dictionary, "npcs.json parsea")
	var npcs: Array = (parsed as Dictionary).get("npcs", [])
	var por_id: Dictionary = {}
	for e in npcs:
		var d: Dictionary = e
		por_id[str(d.get("id", ""))] = d
	for id in ["ilya", "bram", "sira"]:
		_check(por_id.has(id), "NPC '%s' existe" % id)
	_check(str((por_id.get("bram", {}) as Dictionary).get("rol", "")).find("Moon Town") >= 0,
		"rol de Bram: Herrero de Moon Town")
	_check(str((por_id.get("sira", {}) as Dictionary).get("rol", "")).find("Moon Town") >= 0,
		"rol de Sira: Boticaria de Moon Town")


## 4. La ciudad construida con el terreno real: spawn del jugador sobre el
## terreno, dentro de la región moon_town y fuera de colisiones; los NPCs
## en sus puntos data-driven; el minimapa puede leer color_en del terreno
## nuevo (STANDBY: no se pule, solo se verifica que no rompe).
func _t_ciudad_y_terreno() -> void:
	var t: Terreno = TG.new()
	root.add_child(t)
	_basura.append(t)
	var ciudad: CiudadLuna = CL.new()
	ciudad.terreno = t
	root.add_child(ciudad)
	_basura.append(ciudad)
	var spawn: Vector3 = ciudad.punto_aparicion_jugador()
	_check(absf(spawn.y - t.altura_en(spawn.x, spawn.z)) <= 1.0,
		"spawn del jugador sobre el terreno (y=%.1f)" % spawn.y)
	_check(Vector2(spawn.x, spawn.z).length() <= 800.0, "spawn dentro del radio 800")
	var db := RegionDB.new()
	_check(db.cargar(), "RegionDB.cargar()")
	var reg: Dictionary = db.region_en(spawn.x, spawn.z)
	_check(str(reg.get("id", "")) == "moon_town", "spawn en la región moon_town")
	var cajas: Array = ciudad.cajas_colision()
	var dentro: bool = false
	for c in cajas:
		if (c as AABB).has_point(spawn):
			dentro = true
	_check(not dentro, "spawn fuera de colisiones de edificios")
	var esperados: Dictionary = {"ilya": Vector2(-50, 160), "bram": Vector2(170, -30), "sira": Vector2(-178, -25)}
	for id in esperados.keys():
		var p: Vector3 = ciudad.npc_spawn(str(id))
		var e: Vector2 = esperados[id]
		_check(absf(p.x - e.x) <= 1.0 and absf(p.z - e.y) <= 1.0,
			"npc_spawn('%s') = (%.0f, %.0f)" % [id, p.x, p.z])
	# Minimapa STANDBY: el terreno nuevo responde color_en sin reventar.
	var c: Color = t.color_en(0.0, 0.0)
	_check(c.a >= 0.0 and c.a <= 1.0, "Terreno.color_en no revienta (minimapa STANDBY)")
