extends RefCounted
## MedidorClips — el inventario honesto de lo que hay dentro del
## `AnimationPlayer` de un modelo.
##
## RESPONSABILIDAD ÚNICA: decir qué clips existen, cuánto duran, si ciclan,
## y si tienen keys SOBRE LOS HUESOS DE LAS PIERNAS. Esta es la pregunta que
## separa "la animación va mal" de "el clip `walk` no existe": un clip sin
## keys en las piernas anda perfecto y se ve congelado.
##
## También deja por escrito con qué `speed_scale` y con qué `current_animation`
## está sonando, porque son los dos números que un cambio de código puede
## tocar en silencio: `speed_scale` multiplica el tiempo del clip sin tocar la
## pose (y por eso no se ve en la tira de PNGs), y `current_animation` dice si
## lo que suena es lo que uno cree que está sonando.

const LOCALIZADOR: GDScript = preload("res://tools/anim_medida/localizador.gd")


## Los cuatro clips que el juego espera de un modelo riggeado, en el orden en
## que los nombra `player.gd` (`CLIP_IDLE`, `CLIP_WALK`, `CLIP_ATAQUE`,
## `CLIP_MUERTE`). No se exige que existan todos: el informe dice cuáles.
const CLIPS_DEL_JUEGO: Array[String] = ["idle", "walk", "attack", "die"]


## Inventario completo del reproductor.
##
## Devuelve: `ok`, `motivo`, `clips` (el `get_animation_list` crudo), la
## lista `faltan` de los cuatro del juego, y `detalle` con un `Dictionary`
## por clip: `duracion`, `loop`, `step`, `keys_pierna`, `pistas_pierna`,
## `tiene_keys`.
static func medir(anim: AnimationPlayer) -> Dictionary:
	var salida: Dictionary = {"ok": false, "motivo": ""}
	if anim == null or not is_instance_valid(anim):
		salida["motivo"] = "no hay AnimationPlayer: este modelo no esta riggeado"
		return salida
	var crudos: PackedStringArray = anim.get_animation_list()
	var nombres: Array[String] = []
	for n in crudos:
		nombres.append(str(n))
	var faltan: Array[String] = []
	for c in CLIPS_DEL_JUEGO:
		if not crudos.has(StringName(c)):
			faltan.append(c)
	var detalle: Dictionary = {}
	for n in crudos:
		var animacion: Animation = anim.get_animation(n)
		detalle[str(n)] = {
			"duracion": animacion.length,
			"loop": int(animacion.loop_mode),
			"cicla": animacion.loop_mode != Animation.LOOP_NONE,
			"step": animacion.step,
			"pistas": animacion.get_track_count(),
			"keys_pierna": _keys_de_pierna(animacion),
			"pistas_pierna": _pistas_de_pierna(animacion),
			"tiene_keys": animacion.get_track_count() > 0,
		}
	salida["ok"] = true
	salida["clips"] = nombres
	salida["faltan"] = faltan
	salida["detalle"] = detalle
	# `current_animation_position` con el reproductor parado tira un ERROR del
	# motor ("no current animation"). Vacío es un dato, no una falla: nadie
	# pondría un clip ahora mismo.
	salida["actual"] = str(anim.current_animation)
	salida["posicion"] = anim.current_animation_position if anim.current_animation != &"" else 0.0
	salida["speed_scale"] = anim.speed_scale
	salida["sonando"] = anim.is_playing()
	salida["librerias"] = _nombres_de_librerias(anim)
	return salida


## Cuántos clips tienen keys de posición o rotación sobre algún hueso de las
## piernas. Con `walk > 0` y `idle > 0` hay ciclo de marcha; con `0` en uno de
## los dos, ese clip no mueve las piernas por más que se lo pida.
static func clips_que_mueven_piernas(anim: AnimationPlayer) -> Dictionary:
	var salida: Dictionary = {}
	if anim == null or not is_instance_valid(anim):
		return salida
	for n in anim.get_animation_list():
		var animacion: Animation = anim.get_animation(n)
		salida[str(n)] = _keys_de_pierna(animacion)
	return salida


## `true` si hay un `AnimationTree` activo en el subárbol. Con él activo, el
## `AnimationPlayer` deja de mandar: manda el árbol, y todo lo que diga el
## `seek()` del clip crudo es mentira. Por eso el inventario lo reporta.
static func hay_arbol_activo(anim: AnimationPlayer) -> bool:
	if anim == null or not is_instance_valid(anim):
		return false
	for n in anim.get_children():
		if n is AnimationTree and (n as AnimationTree).active:
			return true
	return false


## El `AnimationTree` activo de este reproductor, o `null`.
static func arbol(anim: AnimationPlayer) -> AnimationTree:
	if anim == null or not is_instance_valid(anim):
		return null
	for n in anim.get_children():
		if n is AnimationTree:
			return n as AnimationTree
	return null


## Valor publicado del parámetro del árbol, o `nan` si ese parámetro no existe.
## `nan` es información, no un error: significa "este árbol no publica este
## parámetro", que es exactamente lo que pasó con el `blend_amount` del
## bloque 67.
static func parametro(arbol_activo: AnimationTree, ruta: String) -> float:
	if arbol_activo == null or not is_instance_valid(arbol_activo):
		return NAN
	for p in arbol_activo.get_property_list():
		if str(p.get("name", "")) == ruta:
			return float(arbol_activo.get(ruta))
	return NAN


## Nombres de los clips, con su duración, en el orden del inventario. La línea
## es estable entre corridas: es la que se lee y se diffea.
static func linea_clips(anim: AnimationPlayer) -> String:
	if anim == null or not is_instance_valid(anim):
		return "sin AnimationPlayer"
	var partes: PackedStringArray = PackedStringArray()
	for n in anim.get_animation_list():
		var animacion: Animation = anim.get_animation(n)
		partes.append("%s=%.3fs" % [str(n), animacion.length])
	return " ".join(partes)


static func _keys_de_pierna(animacion: Animation) -> int:
	var total: int = 0
	for pista in animacion.get_track_count():
		if _es_pista_de_hueso(animacion, pista) \
				and int(animacion.track_get_type(pista)) in _TIPOS_DE_POSE:
			total += animacion.track_get_key_count(pista)
	return total


static func _pistas_de_pierna(animacion: Animation) -> int:
	var total: int = 0
	for pista in animacion.get_track_count():
		if _es_pista_de_hueso(animacion, pista) \
				and int(animacion.track_get_type(pista)) in _TIPOS_DE_POSE:
			total += 1
	return total


## ¿La pista toca un hueso de las piernas? La pista se llama
## `Rig/Skeleton3D:Thigh.L`: el hueso es el SUBNAME del NodePath, no el nombre
## del nodo. Buscarlo por el subname es lo que hace que esto funcione con
## cualquier modelo, esté donde esté el esqueleto.
static func _es_pista_de_hueso(animacion: Animation, pista: int) -> bool:
	var ruta: NodePath = animacion.track_get_path(pista)
	var sub: StringName = ruta.get_subname(0)
	if sub == &"":
		return false
	for alias in LOCALIZADOR.ALIAS_MUSLO_IZQ + LOCALIZADOR.ALIAS_ESPINILLA_IZQ \
			+ LOCALIZADOR.ALIAS_PIE_IZQ + LOCALIZADOR.ALIAS_MUSLO_DER \
			+ LOCALIZADOR.ALIAS_ESPINILLA_DER + LOCALIZADOR.ALIAS_PIE_DER:
		if str(sub) == alias:
			return true
	return false


static func _nombres_de_librerias(anim: AnimationPlayer) -> Array[String]:
	var salida: Array[String] = []
	for l in anim.get_animation_library_list():
		var lib: AnimationLibrary = anim.get_animation_library(l)
		if lib != null:
			salida.append(lib.get_class())
	return salida


## `TYPE_POSITION` (1) y `TYPE_ROTATION` (2): los únicos dos tipos de pista
## que mueven un hueso. Los `TYPE_METHOD` (4) que escriben el hueso por código
## se cuentan aparte, y por eso el informe lo dice.
const _TIPOS_DE_POSE: Array[int] = [1, 2]
