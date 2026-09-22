extends SceneTree
## Smoke fase 14: mueve al jugador fuera de Moon Town para activar el
## streaming de mobs y corre 500 frames sin errores.
##   godot --headless --path . --script res://tests/smoke_fase14_streaming.gd

var _frames: int = 0
var _demo: Node = null
var _max_frames: int = 500
var _errores: int = 0


func _init() -> void:
	print("[SMOKE14] arranque")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var escena: PackedScene = load("res://scenes/demo/fase14_demo.tscn")
		_demo = escena.instantiate()
		root.add_child(_demo)
	elif _frames == 30:
		# Teletransportar al jugador 2000 u al este: activa streaming.
		var j: Node = root.find_child("Player", true, false)
		if j != null:
			var p: Vector3 = (j as Node3D).global_position
			(j as Node3D).global_position = Vector3(1019.4, p.y, -701.0)
			var terr: Node = _demo.get_node_or_null("Terreno")
			if terr != null and terr.has_method("altura_en"):
				var np: Vector3 = (j as Node3D).global_position
				np.y = float(terr.call("altura_en", np.x, np.z))
				(j as Node3D).global_position = np
			print("[SMOKE14] jugador fuera de la ciudad: %s" % str((j as Node3D).global_position))
		else:
			push_error("[SMOKE14] no se encontró Player")
			_errores += 1
	elif _frames == _max_frames:
		var sm: Node = root.find_child("StreamingMobs", true, false)
		var inst: int = -1
		if sm != null and sm.has_method("conteo_instanciados"):
			inst = int(sm.call("conteo_instanciados"))
		var npcs: int = get_nodes_in_group("npcs").size()
		print("[SMOKE14] frames=%d mobs_instanciados=%d npcs=%d errores=%d"
			% [_frames, inst, npcs, _errores])
		if _errores == 0:
			print("[SMOKE14] TODO VERDE")
		quit(_errores)
		return true
	return false
