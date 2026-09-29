class_name ArbolAnimacion
extends RefCounted
## Bloque 67: el `AnimationTree` que mezcla idle y walk con un cross-fade.
##
## POR QUÉ EXISTE: el `_actualizar_animacion` de la 50 llama a
## `_poner_clip("walk")` o `_poner_clip("idle")` según si la velocidad supera
## un umbral, y `_poner_clip` hace `play(clip)`. Eso es un CORTE SECO: en un
## juego como este, donde el personaje gira 180° constantemente y arranca y
## para cada dos pasos, los clips se cortan tan a menudo que se ven como un
## pop. Un `AnimationTree` con un `StateMachine` y un `BlendSpace1D` (o un
## `Blend2` idle↔walk) mezcla los dos con un cross-fade y el movimiento se ve
## continuo.
##
## POR QUÉ ES UNA CLASE ESTÁTICA Y NO UN NODO: el blend depende solo de la
## VELOCIDAD normalizada, no de quién camina. Se comparte entre el jugador y
## los enemigos (que tienen el mismo problema: 20 arquetipos, todos con el
## mismo corte), y se puede testear sin montar ni una escena.
##
## CÓMO FUNCIONA, sin entrar en el detalle de Godot: si hay `AnimationTree`,
## se le pone un `blend_position` normalizado (0 = quieto, 1 = corriendo) y
## él mezcla. Si NO hay (un mob sin modelo), se cae al `play()` de siempre,
## que es el comportamiento anterior y no se pierde nada.

## El `AnimationTree` se guarda por `AnimationPlayer` (el nodo real del
## modelo): es lo que hay que repetir por entidad.
static var _trees: Dictionary = {}


## El `AnimationTree` de un `AnimationPlayer`, o null si no se puede.
##
## `AnimationNodeBlendTree` con un nodo `output` alimentado por un
## `AnimationNodeBlend2` (idle ↔ walk) es la forma más barata de cross-fade: no
## necesita `StateMachine` y son 2Blend2 en vez de una máquina de estados.
static func tree_de(anim: AnimationPlayer, idle: String, walk: String) -> AnimationTree:
	if anim == null or not is_instance_valid(anim):
		return null
	if _trees.has(anim):
		return _trees[anim]
	var tree := AnimationTree.new()
	tree.name = "ArbolAnimacion"
	# `animation_player` es la ruta al AnimationPlayer desde el árbol: el
	# AnimationTree es hermano del AnimationPlayer, cuelga del mismo padre.
	tree.anim_player = anim.get_path() if anim.get_parent() != null else NodePath()
	var root: AnimationNodeBlendTree = AnimationNodeBlendTree.new()
	var blend := AnimationNodeBlend2.new()
	blend.blend_amount = 0.0  # arranca en idle
	# Los dos inputs del blend, cada uno su clip.
	blend.add_node("idle", AnimationNodeAnimation.new())
	(blend.get_node("idle") as AnimationNodeAnimation).animation = idle
	blend.add_node("walk", AnimationNodeAnimation.new())
	(blend.get_node("walk") as AnimationNodeAnimation).animation = walk
	root.add_node("locomocion", blend, Vector2(200, 0))
	var salida := AnimationNodeAnimation.new()
	salida.animation = idle
	root.add_node("output", salida, Vector2(400, 0))
	root.connect_node("output", 0, "locomocion")
	tree.tree_root = root
	# El AnimationTree cuelga del AnimationPlayer.
	anim.add_child(tree)
	tree.active = true
	_trees[anim] = tree
	return tree


## Pone la mezcla según la velocidad. `norm` va de 0 (quieto) a 1 (corriendo);
## es la velocidad normalizada, no la real. Devuelve si usó el árbol o el
## fallback, que los tests usan para comprobar ambos caminos.
static func mezclar(anim: AnimationPlayer, idle: String, walk: String,
		norm: float, xfade: float = 0.15) -> bool:
	if anim == null or not is_instance_valid(anim):
		return false
	var tree: AnimationTree = tree_de(anim, idle, walk)
	if tree == null:
		# Fallback: sin árbol, el `play()` de siempre. Es el comportamiento de
		# un mob sin modelo, y no se pierde nada.
		anim.play(idle if norm <= 0.0 else walk)
		return false
	var n: float = clampf(norm, 0.0, 1.0)
	var root: AnimationNodeBlendTree = tree.tree_root as AnimationNodeBlendTree
	if root == null:
		return false
	var blend: AnimationNodeBlend2 = root.get_node("locomocion") as AnimationNodeBlend2
	if blend == null:
		return false
	# El blend_amount es TODO lo que hace falta: `AnimationNodeBlend2` mezcla
	# los dos clips con este peso, y el cambio de 0 a 1 ES el cross-fade
	# (continuous). El `xfade` del AnimationPlayer es para cambiar de clip
	# ENTERO, que es otro caso (ataque, muerte) y lo lleva `_poner_clip`.
	blend.blend_amount = n
	return true


## Limpia la caché de árboles. Solo los tests: en el juego los AnimationTree
## mueren con su AnimationPlayer y Godot los libera.
static func limpiar_cache() -> void:
	_trees.clear()
