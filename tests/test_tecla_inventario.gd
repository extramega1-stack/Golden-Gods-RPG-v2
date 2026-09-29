extends SceneTree
## ¿El inventario se abre con su tecla, de verdad?
##
## El playtest completo de la ola 3 reportó "«PanelInventario» se abre con su
## tecla" en rojo, pero también "se abre y se cierra con ESC, y la pila queda
## vacía" en verde. O sea: el panel funciona, la tecla no. Eso puede ser un bug
## del juego o un problema del propio playtest, y hay que saber cuál antes de
## tocar nada.
##
## La diferencia con los otros tests de UI: estos despachan el evento por la
## cadena REAL de entrada (`Input.parse_input_event`), no llaman al método. Si el
## panel se abre con un método llamado a mano, eso no prueba que la tecla
## funcione, y es justo el error de razon que dejó siete sistemas sin conectar
## durante meses.

var _ok: int = 0
var _fallos: int = 0
var _fase: int = 0
var _demo: Node = null
var _jugador: Node3D = null
var _inicio_ms: int = 0
var _frames: int = 0


func _process(_d: float) -> bool:
	match _fase:
		0:
			_fase = 1
			var packed: PackedScene = load("res://scenes/demo/fase14_demo.tscn")
			_demo = packed.instantiate()
			root.add_child(_demo)
			_inicio_ms = Time.get_ticks_msec()
			return false
		1:
			if Time.get_ticks_msec() - _inicio_ms > 180000:
				_chk(false, "la partida llega a estar lista")
				return _fin()
			_jugador = root.find_child("Player", true, false) as Node3D
			if _jugador == null:
				return false
			_fase = 2
			return false
		2:
			_frames += 1
			if _frames < 30:
				return false
			_fase = 3
			_probar_tecla()
			return false
		3:
			_fase = 4
			_frames += 1
			if _frames < 4:
				return false
			# Tras la pulsación el panel debería estar visible.
			var panel: CanvasLayer = _por_id(_demo, &"panel_inventario")
			if panel == null:
				panel = _por_nombre(_demo, "PanelInventario")
			_chk(panel != null, "el panel de inventario está en la partida", "")
			if panel != null:
				_chk(panel.visible,
					"la TECLA I abre el inventario (evento real por Input.parse_input_event)",
					"visible=%s" % str(panel.visible))
				# Y cerrarlo con ESC lo deja limpio, que es lo que se rompería
				# si la pila no se vaciara.
				_pulsar("cancelar_seleccion")
				_fase = 5
			return false
		5:
			_fase = 6
			_frames += 1
			if _frames < 4:
				return false
			var panel: CanvasLayer = _por_id(_demo, &"panel_inventario")
			if panel != null:
				_chk(not panel.visible, "y ESC lo cierra", "visible=%s" % str(panel.visible))
			return _fin()
	return false


func _probar_tecla() -> void:
	_chk(InputMap.has_action("abrir_inventario"),
		"la acción abrir_inventario existe en el Input Map", "")
	if InputMap.has_action("abrir_inventario"):
		var evs: Array = InputMap.action_get_events("abrir_inventario")
		_chk(evs.size() > 0, "y tiene al menos un evento", str(evs.size()))
	_pulsar("abrir_inventario")


## Despacha la acción por la cadena real de entrada. Esto es lo que hace la
## diferencia con llamar al método a mano: atraviesa `_input` y
## `_unhandled_input` como lo haría una tecla de verdad.
func _pulsar(accion: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = accion
	ev.pressed = true
	Input.parse_input_event(ev)
	var ev2 := InputEventAction.new()
	ev2.action = accion
	ev2.pressed = false
	Input.parse_input_event(ev2)


func _por_id(n: Node, id: StringName) -> Node:
	for h in _todos(n):
		if "system_id" in h and h.get("system_id") == id:
			return h
	return null


func _por_nombre(n: Node, nom: String) -> Node:
	for h in _todos(n):
		if String(h.name) == nom:
			return h
	return null


func _todos(n: Node) -> Array:
	var out: Array = []
	var cola: Array = [n]
	while not cola.is_empty():
		var cur: Node = cola.pop_back()
		out.append(cur)
		for c in cur.get_children():
			cola.append(c)
	return out


func _fin() -> bool:
	print("[TEST] tecla_inventario: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] %s%s" % [nombre, "" if detalle == "" else "  <-- " + detalle])
