extends SceneTree
## Tests headless de la Fase 29 (diálogos con lore).
##
## Cubre:
## (a) todos los NPCs tienen 3-4 líneas (ilya 4 y bram 3 intactos);
## (b) primera línea de ilya intacta (canon + tests viejos);
## (c) el lore menciona las cadenas: Devorador, Fundidor, Aullido,
##     Susurro, Campeon, Velo, Tartaro, Hefesto, Sello y Arena.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase29_dialogos.gd

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false


func _init() -> void:
	print("[TEST] Fase 29 — diálogos con lore")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_conteos()
	_test_marcadores_intactos()
	_test_lore()
	print("[TEST] fase29_dialogos: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _npcs() -> Array:
	var texto: String = FileAccess.get_file_as_string("res://data/npcs.json")
	var datos: Variant = JSON.parse_string(texto)
	if not (datos is Dictionary):
		return []
	return (datos as Dictionary).get("npcs", [])


## (a) Conteos por NPC.
func _test_conteos() -> void:
	var lista: Array = _npcs()
	_chk(lista.size() == 21, "a: 21 npcs (fase 41: +maestro)", str(lista.size()))
	var por_id: Dictionary = {}
	for x in lista:
		por_id[str((x as Dictionary).get("id", ""))] = x
	_chk((por_id["ilya"] as Dictionary).get("dialogo", []).size() == 4,
		"a: ilya intacta con 4")
	_chk((por_id["bram"] as Dictionary).get("dialogo", []).size() == 3,
		"a: bram intacto con 3")
	for k in ["sira", "yasmina", "durnan", "sella", "elthar", "vex",
			"karg", "maris", "aurelio"]:
		_chk((por_id[k] as Dictionary).get("dialogo", []).size() == 4,
			"a: " + k + " con 4 líneas")
	for k in por_id:
		if str(k).begins_with("portero_"):
			_chk((por_id[k] as Dictionary).get("dialogo", []).size() == 3,
				"a: " + str(k) + " con 3 líneas")


## (b) Marcadores de compatibilidad intactos.
func _test_marcadores_intactos() -> void:
	var lista: Array = _npcs()
	var por_id: Dictionary = {}
	for x in lista:
		por_id[str((x as Dictionary).get("id", ""))] = x
	var ilya: Array = (por_id["ilya"] as Dictionary).get("dialogo", [])
	_chk(str(ilya[0]).contains("Moon Town"), "b: primera línea de ilya")
	_chk(str(ilya[3]).contains("vuelve a hablarme"),
		"b: última línea de ilya")


## (c) El lore respira las cadenas y el canon.
func _test_lore() -> void:
	var todo: String = FileAccess.get_file_as_string("res://data/npcs.json")
	# Nota: npcs.json es ASCII sin tildes (convención del archivo).
	for palabra in ["Devorador", "Fundidor", "Aullido", "Susurro",
			"Campeon", "Velo", "Tartaro", "Hefesto", "Sello", "Arena"]:
		_chk(todo.contains(palabra), "c: lore menciona " + palabra)
