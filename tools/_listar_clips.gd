extends SceneTree
## Lista los clips de un FBX, uno por linea, para que un script de shell los
## pueda usar. Mixamo le pone el nombre que quiere y Godot lo prefija con el
## nombre del esqueleto, asi que no se puede adivinar el nombre del clip.
func _init() -> void:
	var ruta := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fbx="):
			ruta = a.get_slice("=", 1)
	if ruta == "" or not ResourceLoader.exists(ruta):
		quit(1)
		return
	var inst: Node = load(ruta).instantiate()
	root.add_child(inst)
	var cola: Array = [inst]
	while not cola.is_empty():
		var n: Node = cola.pop_back()
		if n is AnimationPlayer:
			for c in (n as AnimationPlayer).get_animation_list():
				print("CLIP=" + str(c))
		for c in n.get_children():
			cola.append(c)
	quit(0)
