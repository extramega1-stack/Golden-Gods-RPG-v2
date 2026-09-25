extends SceneTree
## Tests headless de la Fase 47 (teclas de la barra).
##
## El bug: los 8 slots de la barra de acciones responden a F4–F11, pero el HUD
## los rotula "1/F1", "2/F2"… "F8". O sea: **todas las etiquetas F mentían**,
## F1–F3 no hacían nada, y F9/F10 disparaban a la vez *guardar*/*cargar* y un
## slot. Nadie lo cazó porque no había ningún test que comparara las etiquetas
## con el Input Map: cada uno miraba su trozo.
##
## (a) La barra es F1–F8, una tecla por slot, sin repeticiones.
## (b) F9 guarda y F10 carga, y no pisan la barra.
## (c) INVARIANTE GENERAL: ninguna tecla del juego está en dos acciones.
## (d) Las etiquetas del HUD dicen la verdad: la F de cada slot es la que
##     tiene el Input Map.
## (e) El manual (data/mecanicas.json) dice F1–F8.
##
## Cómo correrlo:
##   godot --headless --path <proyecto> --script res://tests/test_fase47_teclas.gd

const BA: GDScript = preload("res://scripts/ui/barra_acciones.gd")

var _ok: int = 0
var _fallos: int = 0


func _init() -> void:
	pass


func _process(_d: float) -> bool:
	_test_barra()
	_test_guardar()
	_test_invariante()
	_test_etiquetas()
	_test_manual()
	print("[TEST] fase47_teclas: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] " + nombre + ("" if detalle == "" else "  <-- " + detalle))


## Tecla física que el Input Map tiene para una acción ("" si no hay).
func _tecla_de(accion: String) -> String:
	for e in InputMap.action_get_events(accion):
		if e is InputEventKey:
			return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	return ""


## (a) La barra: F1 a F8, una por slot.
func _test_barra() -> void:
	var vistas: Array[String] = []
	for i in range(1, 9):
		var accion: String = "barra_%d" % i
		_chk(InputMap.has_action(accion), "a: existe " + accion)
		var t: String = _tecla_de(accion)
		_chk(t == "F%d" % i, "a: %s = F%d" % [accion, i], "es %s" % t)
		_chk(not vistas.has(t), "a: %s no repite tecla" % accion, t)
		vistas.append(t)


## (b) Guardar y cargar, sin pisar la barra.
func _test_guardar() -> void:
	_chk(_tecla_de("guardar_partida") == "F9", "b: guardar = F9",
		_tecla_de("guardar_partida"))
	_chk(_tecla_de("cargar_partida") == "F10", "b: cargar = F10",
		_tecla_de("cargar_partida"))


## (c) El invariante que faltaba: ninguna tecla compartida por dos acciones
## del juego.
func _test_invariante() -> void:
	var por_tecla: Dictionary = {}
	for a in InputMap.get_actions():
		var accion: String = str(a)
		if accion.begins_with("ui_") or accion.begins_with("slot_"):
			continue
		for e in InputMap.action_get_events(accion):
			if not (e is InputEventKey):
				continue
			var t: String = OS.get_keycode_string((e as InputEventKey).physical_keycode)
			if t == "":
				continue
			if por_tecla.has(t):
				_chk(false, "c: " + t + " está en dos acciones",
					"%s y %s" % [str(por_tecla[t]), accion])
			else:
				por_tecla[t] = accion
	_chk(por_tecla.size() >= 27, "c: el juego tiene al menos 27 teclas",
		str(por_tecla.size()))


## (d) Las etiquetas del HUD dicen la verdad.
func _test_etiquetas() -> void:
	_chk(BA.TECLAS.size() == 8, "d: 8 etiquetas", str(BA.TECLAS.size()))
	for i in range(8):
		var real: String = _tecla_de("barra_%d" % (i + 1))
		var etiqueta: String = BA.TECLAS[i]
		_chk(etiqueta.ends_with("/" + real) or etiqueta == real,
			"d: la etiqueta del slot %d dice F%d" % [i + 1, i + 1],
			"etiqueta=%s real=%s" % [etiqueta, real])
	# El slot 1 también dispara con la tecla 1 (habilidad_1): "1/F1" es correcto.
	_chk(BA.TECLAS[0] == "1/F1", "d: el slot 1 avisa de sus dos teclas",
		BA.TECLAS[0])
	_chk(_tecla_de("habilidad_1") == "1", "d: y la 1 es la habilidad_1",
		_tecla_de("habilidad_1"))


## (e) El manual no dice F4–F11.
func _test_manual() -> void:
	var texto: String = FileAccess.get_file_as_string("res://data/mecanicas.json")
	_chk(not texto.is_empty(), "e: existe data/mecanicas.json")
	_chk(not texto.contains("F4 a F11"), "e: el manual ya no dice F4 a F11")
	_chk(texto.contains("F1 a F8"), "e: el manual dice F1 a F8")
