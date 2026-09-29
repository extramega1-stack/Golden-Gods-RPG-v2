extends SceneTree
## Bloque 67 — que se vea: post-proceso y equipo sobre los huesos.
##
## POR QUÉ ESTE ARCHIVO: el bloque 53–62 estaba verde y aun así el equipo
## flotaba en el aire. La fase 36 tenía un test de regresión ("el equipo no se
## movió de sitio") que CELEBRABA el bug: los offsets fijos son exactamente
## "no moverse de sitio". Ese test se escribe al revés aquí.

const PL: GDScript = preload("res://scripts/player/player.gd")
const PD: GDScript = preload("res://scripts/player/paper_doll.gd")
const PP: GDScript = preload("res://scripts/core/post_proceso.gd")
const AD: GDScript = preload("res://scripts/player/anclajes_db.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Bloque 67 — Que se vea")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_tonemap()
	_test_post_proceso_escalable()
	_test_anclajes_en_el_dato()
	_test_equipo_sigue_al_hueso()
	print("[TEST] bloque67_visual: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _jugador(clase: String = "guerrero") -> Player:
	var p: Player = PL.new()
	p.fijar_identidad("H", clase)
	p.aplicar_clase(clase)
	root.add_child(p)
	_basura.append(p)
	return p


# --- (a) el tonemapping: un BUG DE IMAGEN, no una feature -----------

## Godot 4 usa TONE_MAPPER_LINEAR por defecto. Con `light_energy = 1.25` al
## mediodía, cualquier superficie iluminada CLIPEA A BLANCO PURO. El
## tonemapping filmic no es estética: es una imagen que se estaba quemando.
func _test_tonemap() -> void:
	var env := Environment.new()
	var ok: bool = PP.aplicar(env)
	_chk(env.tonemap_mode == Environment.TONE_MAPPER_FILMIC,
		"el tonemapping es FILMIC, no LINEAR (67)", str(env.tonemap_mode))
	_chk(env.tonemap_mode != Environment.TONE_MAPPER_LINEAR,
		"que era lo que quemaba las altas luces", "")
	_chk(env.adjustment_enabled, "los ajustes están activos (67)", "")
	_chk(env.adjustment_saturation > 1.0,
		"y suben la saturación (los materiales planos son grises)",
		str(env.adjustment_saturation))
	# La niebla del clima (fase 16) es EXPONENCIAL; esta es la del post-proceso.
	# Ambas pueden convivir, pero tienen que ser coherentes.
	_chk(env.fog_enabled, "la niebla está activa", "")
	_chk(env.fog_mode == Environment.FOG_MODE_EXPONENTIAL
			or env.fog_mode == Environment.FOG_MODE_DEPTH,
		"y es un modo de niebla por profundidad (no la 2D de antes)", str(env.fog_mode))
	_chk(ok == PP._soportado(),
		"PostProceso.aplicar() reporta si el renderer soporta el post-proceso",
		"ok=%d soportado=%s" % [ok, PP._soportado()])


# --- (b) el post-proceso escala con la calidad y el renderer ---------

func _test_post_proceso_escalable() -> void:
	# Calidad baja: sin SSAO ni glow (el post-proceso se puede pagar).
	Opciones.cargar()
	Opciones.poner("calidad", 0)
	var env_baja := Environment.new()
	PP.aplicar(env_baja)
	_chk(not env_baja.ssao_enabled, "en calidad Baja, SSAO apagado", "")
	# Calidad alta: con todo.
	Opciones.poner("calidad", 3)
	var env_alta := Environment.new()
	PP.aplicar(env_alta)
	_chk(env_alta.ssao_enabled, "en calidad Alta, SSAO encendido", "")
	# El tonemap se queda en todos los niveles: es un fix, no un lujo.
	Opciones.poner("calidad", 0)
	var env_baja2 := Environment.new()
	PP.aplicar(env_baja2)
	_chk(env_baja2.tonemap_mode == Environment.TONE_MAPPER_FILMIC,
		"el tonemap está SIEMPRE (es un fix, no un lujo)", "")
	Opciones.restablecer()

	# Y el renderer: la web es gl_compatibility, que NO tiene glow/SSAO.
	# La función tiene que distinguirlo, no asumir PC.
	_chk(PP._soportado() == (str(ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "forward_plus")) != "gl_compatibility"),
		"detecta si el renderer soporta el post-proceso", "")


# --- (c) el dato: los anclajes tienen nombre de hueso -----------------

func _test_anclajes_en_el_dato() -> void:
	AD.cargar()
	_chk(AD.slots().size() >= 12, "hay 12 slots", str(AD.slots().size()))
	# El campo `anclaje` con el NOMBRE DEL HUESO existe desde la fase 43, pero
	# el código nunca lo leía (era la deuda #1 del traspaso). Ahora sí.
	var con_hueso: int = 0
	for slot in AD.slots():
		if AD.anclaje_de(slot) != "":
			con_hueso += 1
	_chk(con_hueso >= 12,
		"los 12 slots declaran su hueso (67 los usa)", "%d con hueso" % con_hueso)
	# Y son los huesos que los GLB tienen.
	for h in ["Hand.R", "Hand.L", "Head", "Chest", "Neck"]:
		var alguien: bool = false
		for slot in AD.slots():
			if AD.anclaje_de(slot) == h:
				alguien = true
		_chk(alguien, "el hueso '%s' está en la tabla" % h, "")


# --- (d) EL EQUIPO SIGUE AL PERSONAJE --------------------------------

## Este es el test al revés del de la fase 36. Allí se comprobaba que el
## equipo "no se movía de sitio" (offsets fijos = no moverse). Aquí se
## comprueba lo contrario: que SE MUEVE con el hueso, que es lo correcto.
##
## El test monta el jugador DE VERDAD (el modelo GLB carga en headless y trae
## sus 19 huesos), equipa el arma, y comprueba que la pieza cuelga del
## `BoneAttachment3D` y no de un offset absoluto del mundo.
func _test_equipo_sigue_al_hueso() -> void:
	var p: Player = _jugador()
	var modelo: Node = p.get_node_or_null("Modelo")
	_chk(modelo != null, "el jugador carga su modelo (el test usa el real)", "")
	if modelo == null:
		return
	var esqueletos: Array[Node] = modelo.find_children("*", "Skeleton3D", true, false)
	_chk(esqueletos.size() > 0, "el modelo trae Skeleton3D", str(esqueletos.size()))
	if esqueletos.is_empty():
		return
	var e0: Skeleton3D = esqueletos[0] as Skeleton3D
	_chk(e0.get_bone_count() >= 19,
		"con los 19 huesos del rig de la fase 49.1", str(e0.get_bone_count()))
	# Los huesos que el JSON declara tienen que EXISTIR en el modelo, o el
	# anclaje a hueso no se puede hacer.
	for h in ["Hand.R", "Hand.L", "Head", "Chest", "Neck"]:
		_chk(e0.find_bone(h) >= 0, "el modelo tiene el hueso '%s'" % h,
			str(e0.find_bone(h)))

	var pd: PaperDoll = p.get_node_or_null("PaperDoll") as PaperDoll
	_chk(pd != null, "el PaperDoll existe", "")
	if pd == null:
		return

	# El anclaje: un BoneAttachment3D por hueso, colgando del esqueleto.
	var ba: BoneAttachment3D = pd._anclaje_a_hueso("Hand.R")
	_chk(ba != null, "se crea un BoneAttachment3D para Hand.R (67)", "")
	if ba != null:
		_chk(ba.get_parent() == e0, "cuelga del ESQUELETO, no del PaperDoll", "")
		_chk(ba.bone_idx == e0.find_bone("Hand.R"),
			"con el bone_idx correcto", str(ba.bone_idx))
		# Cacheado: la segunda llamada devuelve EL MISMO nodo (una alloc por
		# pieza y reconstrucción sería tirar memoria).
		_chk(pd._anclaje_a_hueso("Hand.R") == ba, "y está cacheado", "")

	# Y un hueso que no existe: null, no revienta (fallback al offset).
	_chk(pd._anclaje_a_hueso("HuesoInexistente") == null,
		"un hueso inexistente da null (fallback al offset de reposo)", "")

	# El comportamiento que de verdad importa: una pieza se CUELGA del hueso.
	# Se equipa el arma y se comprueba que su padre es el BoneAttachment3D,
	# no el PaperDoll (que es lo que estaba roto).
	if p.equipo != null and p.inventario != null:
		p.inventario.agregar("espada_corta", 1)
		p.equipo.equipar("espada_corta", p.stats, p.inventario)
		_chk(p.equipo.equipado_en("arma") != "", "el arma se equipada", "")
		pd.reconstruir()
		# La pieza NO cuelga del PaperDoll si hay hueso: cuelga del
		# BoneAttachment3D, que a su vez cuelga del esqueleto. Por eso se
		# busca en el esqueleto y no en el PaperDoll.
		var anclaje: BoneAttachment3D = pd._anclaje_a_hueso("Hand.R")
		var arma: Node = _buscar_por_nombre(anclaje, "arma") if anclaje != null else null
		_chk(arma != null, "el arma se generó (y quedó bajo el anclaje del hueso)", "")
		if arma != null:
			_chk(arma.get_parent() is BoneAttachment3D,
				"CUELGA DE UN HUESO, no de un offset fijo (la deuda #1 del traspaso)",
				"padre=%s" % arma.get_parent().name)
			_chk(arma.get_parent().get_parent() == e0,
				"y el anclaje cuelga del esqueleto", "")
		# Y el PaperDoll ya NO lo tiene como hijo directo: si lo tuviera,
		# el anclaje a hueso se estaría perdiendo.
		_chk(_buscar_por_nombre(pd, "arma") == null,
			"y el PaperDoll NO lo cuelga directo (si no, el hueso se pierde)", "")


## Busca un nodo por nombre, en profundidad.
func _buscar_por_nombre(n: Node, nombre: String) -> Node:
	if n.name == nombre:
		return n
	for c in n.get_children():
		var r: Node = _buscar_por_nombre(c, nombre)
		if r != null:
			return r
	return null
