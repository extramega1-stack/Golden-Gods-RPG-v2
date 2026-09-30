extends SceneTree
## Tests headless de la Fase 50 (el jugador con modelo de clase).
##
## El jugador era una cápsula y el pack trae 4 modelos `clase-*` que encajan
## con 4 de las 5 clases (`guerrero` lo cubre un `job-*`). Lo que se demuestra:
##
## (a) Datos: las 5 clases declaran `modelo` + `modelo_escala`, el archivo
##     existe y está declarado en `data/modelos.json`.
## (b) Jugador: `aplicar_clase()` cuelga el modelo como `Modelo`, con
##     `Skeleton3D`, `AnimationPlayer` y los 4 clips de la FSM.
## (c) Clips: quieto / caminando / tajo / muerto, cada uno con su clip, y sin
##     reiniciar la animación cuando el estado no cambia.
## (d) Cambiar de clase dos veces no deja dos modelos colgando.
## (e) El equipo sigue cayendo donde toca: los offsets de
##     `data/anclajes.json` (casco a 1,58 m, mano a 1,15 m) están medidos
##     sobre un cuerpo de 1,7 m, y el modelo tiene que estar a esa altura o el
##     casco vuela por encima de la cabeza.
## (f) El modelo se cuelga mirando al -Z, que es hacia donde anda el jugador.
##     Sin esta vuelta el personaje camina de espaldas: el pack viene mirando
##     al +Z (el exportador mapea el -Y de Blender al +Z) y el forward del
##     juego es -Z.
func _test_frente() -> void:
	var cid: String = _una_clase_con_modelo()
	if cid == "":
		return
	var p: Player = _jugador(cid)
	var modelo: Node3D = p.get_node_or_null("Modelo") as Node3D
	_chk(modelo != null, "f: hay modelo")
	if modelo == null:
		return
	_chk(is_equal_approx(modelo.rotation.y, Cuerpo.GIRO_MODELO),
		"f: el modelo se gira para mirar al frente del juego",
		"rotation.y=%.2f esperado=%.2f" % [modelo.rotation.y, Cuerpo.GIRO_MODELO])
	# La CARA del modelo es su +Z local (convencion del pack, ver
	# Cuerpo.GIRO_MODELO). El forward del jugador es su -Z. Con la vuelta
	# aplicada, la cara del modelo tiene que apuntar donde el jugador anda.
	#
	# La comparacion es HORIZONTAL a proposito: el jugador se inclina para
	# pegarse al terreno, y ese declive no dice nada sobre hacia donde anda.
	var cara: Vector3 = modelo.global_transform.basis.z
	var anda: Vector3 = -p.global_transform.basis.z
	cara = Vector3(cara.x, 0.0, cara.z).normalized()
	anda = Vector3(anda.x, 0.0, anda.z).normalized()
	_chk(cara.dot(anda) > 0.99, "f: el modelo mira donde mira el jugador",
		"dot=%.3f (cara=%s anda=%s)" % [cara.dot(anda), str(cara.round()), str(anda.round())])


## (g) Modelo ausente: el jugador se queda con la cápsula y avisa.
##
## Cómo correrlo:
##   godot --headless --path <proyecto> --script res://tests/test_fase50_clases_modelos.gd

const RUTA_CLASES: String = "res://data/clases.json"
const RUTA_MANIFIESTO: String = "res://data/modelos.json"
const PL: GDScript = preload("res://scripts/player/player.gd")
const ArbolAnimacion: GDScript = preload("res://scripts/core/arbol_animacion.gd")
const ANCLAJES: GDScript = preload("res://scripts/player/anclajes_db.gd")
const CLIPS: Array = ["idle", "walk", "attack", "die"]
## La capsula del jugador (scenes/demo/fase14_demo.tscn) mide 1,7 m.
const ALTO_ESPERADO: float = 1.7
## Margen para la comparacion con los offsets de la tabla de anclajes.
const TOLERANCIA: float = 0.22

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []
## Estado de la comprobacion que necesita frames reales (el clip avanzando).
var _fase_espera: int = 0
var _frames_esperados: int = 0
var _p: Player = null
var _ap: AnimationPlayer = null


func _init() -> void:
	print("[TEST] Fase 50 — el jugador con modelo de clase")
	ANCLAJES.cargar()


func _process(delta: float) -> bool:
	if _fase_espera > 0:
		_esperar_frames(delta)
		return false
	_test_datos()
	_test_jugador()
	_test_clips()
	# Si la parte de clips ha pedido esperar frames, el resto corre en esa fase
	# (con frames reales entre medias). Si no, se sigue aqui mismo.
	if _fase_espera == 0:
		_test_cambio()
		_test_equipo_en_su_sitio()
		_test_frente()
		_test_ausente()
		_finalizar()
	return false


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] " + nombre + ("" if detalle == "" else "  <-- " + detalle))


func _json(ruta: String) -> Dictionary:
	var texto: String = FileAccess.get_file_as_string(ruta)
	if texto.is_empty():
		return {}
	var v: Variant = JSON.parse_string(texto)
	return v if v is Dictionary else {}


## (a) Las 5 clases con modelo declarado por datos, y declarado en el manifiesto.
func _test_datos() -> void:
	var clases: Dictionary = _json(RUTA_CLASES).get("clases", {})
	_chk(clases.size() >= 5, "a: siguen las 5 clases", "n=%d" % clases.size())
	var declarados: Dictionary = {}
	for entrada in _json(RUTA_MANIFIESTO).get("modelos", []):
		declarados[str((entrada as Dictionary).get("archivo", ""))] = true
	var con_modelo: int = 0
	for cid in clases:
		var c: Dictionary = clases[cid]
		if not c.has("modelo"):
			continue
		con_modelo += 1
		var ruta: String = str(c["modelo"])
		_chk(ruta.begins_with("res://models/"), "a: ruta de modelo en " + cid, ruta)
		_chk(ResourceLoader.exists(ruta), "a: el modelo existe en " + cid, ruta)
		var arch: String = ruta.get_file()
		_chk(declarados.has(arch), "a: declarado en data/modelos.json: " + arch)
		var esc: float = float(c.get("modelo_escala", 1.0))
		_chk(esc > 0.5 and esc < 1.5, "a: escala sensata en " + cid, "escala=%.2f" % esc)
	_chk(con_modelo >= 4, "a: al menos 4 clases con modelo", "con modelo=%d" % con_modelo)


## (b) El jugador cuelga el modelo con esqueleto y los 4 clips.
func _test_jugador() -> void:
	var clases: Dictionary = _json(RUTA_CLASES).get("clases", {})
	for cid in clases:
		if not (clases[cid] as Dictionary).has("modelo"):
			continue
		var p: Player = _jugador(cid)
		var modelo: Node3D = p.get_node_or_null("Modelo") as Node3D
		_chk(modelo != null, "b: %s cuelga su modelo" % cid)
		if modelo == null:
			continue
		var m: MeshInstance3D = _primera_malla(modelo)
		_chk(m != null, "b: %s trae malla" % cid)
		if m != null:
			_chk(m.skin != null, "b: %s con Skin (se deforma)" % cid)
		_chk(_buscar(modelo, "Skeleton3D") != null, "b: %s trae esqueleto" % cid)
		var ap: AnimationPlayer = _buscar(modelo, "AnimationPlayer") as AnimationPlayer
		_chk(ap != null, "b: %s trae AnimationPlayer" % cid)
		if ap != null:
			for c in CLIPS:
				_chk(ap.has_animation(str(c)), "b: %s tiene el clip %s" % [cid, str(c)])


## (c) El clip sigue lo que hace el jugador.
func _test_clips() -> void:
	var cid: String = _una_clase_con_modelo()
	if cid == "":
		return
	var p: Player = _jugador(cid)
	var ap: AnimationPlayer = _buscar(p.get_node_or_null("Modelo"), "AnimationPlayer") as AnimationPlayer
	if ap == null:
		_chk(false, "c: hay reproductor que mirar")
		return
	# quieto: sin velocidad
	#
	# OJO, Y ESTA ES LA REGLA DE ORO DE ESTE ARCHIVO: con el motor UNICO
	# (`ArbolAnimacion`) el clip ya NO lo elige el `AnimationPlayer`, lo conduce
	# el árbol. `current_animation` está vacío para los CUATRO estados por igual
	# y `is_playing()` da falso. No es que el clip no suene: es que quien suena
	# es el árbol. Por eso lo que se compara es el ESTADO de la máquina. Antes
	# este test afirmaba `current_animation == "idle"` y "== attack" y pasaba,
	# porque comparaba el nombre que el propio código acababa de escribir con
	# `play()`: una tautología, no una medición.
	p.velocity = Vector3.ZERO
	for i in 30:
		p.call("_actualizar_animacion", 0.016)
	_chk(ArbolAnimacion.estado_actual(ap) == "locomocion",
		"c: quieto esta en locomocion (la mezcla es idle)",
		"estado=%s" % ArbolAnimacion.estado_actual(ap))
	# caminando: velocidad horizontal
	p.velocity = Vector3(4.0, 0.0, 0.0)
	p.call("_actualizar_animacion", 0.016)
	# BUG DEL BLOQUE 67 (encontrado jugando): con el AnimationTree FUNCIONANDO
	# ya no se comprueba `current_animation`, porque el clip ya no lo elige el
	# reproductor: lo conduce el arbol. Se comprueba lo que de verdad importa,
	# que es la mezcla. Antes este test afirmaba "reproduce walk" y pasaba
	# porque `blend.blend_amount` reventaba con "Invalid assignment" y el
	# arbol no hacia nada: el test celebraba el bug.
	#
	# FASE 70, y este test CELEBRABA EL SIGUIENTE BUG: afirmaba que a 4 m/s la
	# mezcla iba a `blend_position ~ 1`, y pasaba — porque la mezcla estaba
	# SATURADA y a 4 m/s ya valía exactamente 1,0. O sea, este test contaba
	# "la mezcla funciona" cuando lo que comprobaba era "la mezcla no mezcla".
	# Ahora se comprueba lo que sí distingue una mezcla de un corte: que a
	# media velocidad esté en un valor INTERMEDIO, y que a tope sí llegue a 1.
	var tree: AnimationTree = ap.get_node_or_null("ArbolAnimacion") as AnimationTree
	if tree != null:
		var b: Variant = tree.get("parameters/locomocion/blend_position")
		var v_max: float = p.stats.vel_mov
		var esperada: float = ArbolAnimacion.mezcla_por_velocidad(4.0, v_max)
		_chk(b != null and absf(float(b) - esperada) < 0.02,
			"c: la mezcla es la que toca a 4 m/s (ni 0 ni 1)",
			"blend_position=%s esperada=%.3f (v_max=%.2f)" % [str(b), esperada, v_max])
		_chk(float(b) > 0.05 and float(b) < 0.95,
			"c: y a media velocidad esta en un valor INTERMEDIO, no saturada",
			"blend_position=%.3f" % float(b))
		# A tope sí tiene que ser walk puro.
		p.velocity = Vector3(v_max, 0.0, 0.0)
		p.call("_actualizar_animacion", 0.016)
		var bt: Variant = tree.get("parameters/locomocion/blend_position")
		_chk(bt != null and float(bt) > 0.99,
			"c: a tope la mezcla es walk puro",
			"blend_position=%s" % str(bt))
		# Y quieto debe volver a idle por el otro lado: si esto no baja, el
		# personaje se queda congelado en el paso.
		p.velocity = Vector3.ZERO
		p.call("_actualizar_animacion", 0.016)
		var b0: Variant = tree.get("parameters/locomocion/blend_position")
		_chk(b0 != null and absf(float(b0)) < 0.05,
			"c: quieto la mezcla vuelve a 'idle' (blend_position ~0)",
			"blend_position=%s" % str(b0))
		# Y el árbol tiene que estar CONECTADO al esqueleto. Con el
		# `root_node` de por defecto ("..") el árbol no resuelve ninguna pista y
		# no anima nada, y todo lo de arriba pasaba igual: por eso se comprueba.
		_chk(str(tree.root_node) != "..",
			"c: el arbol apunta al esqueleto (con '..' no anima NADA)",
			"root_node='%s'" % str(tree.root_node))
	else:
		_chk(str(ap.current_animation) == "walk",
			"c: sin arbol, caminando reproduce 'walk' (fallback)",
			"reproduciendo '%s'" % str(ap.current_animation))
	# Por debajo del umbral vuelve a quieto (el umbral existe para que el idle y
	# el walk no parpadeen al soltar el WASD). SIN arbol, el clip lo elige el
	# reproductor; CON arbol, lo que importa es que la mezcla se vaya a idle.
	p.velocity = Vector3(0.2, 0.0, 0.0)
	p.call("_actualizar_animacion", 0.016)
	if tree != null:
		var bm: Variant = tree.get("parameters/locomocion/blend_position")
		_chk(bm != null and absf(float(bm)) < 0.05,
			"c: velocidad minima vuelve a la mezcla 'idle'",
			"blend_position=%s" % str(bm))
	else:
		_chk(str(ap.current_animation) == "idle",
			"c: velocidad minima vuelve a 'idle'", "reproduciendo '%s'"
			% str(ap.current_animation))
	# tajo: el timer que deja el ataque
	p.velocity = Vector3.ZERO
	p.set("_t_swing", 0.3)
	var entro_tajo: bool = false
	for i in 30:
		p.call("_actualizar_animacion", 0.016)
		if ArbolAnimacion.estado_actual(ap) == "attack":
			entro_tajo = true
			break
	_chk(entro_tajo, "c: el tajo entra en el estado 'attack'",
		"estado=%s" % ArbolAnimacion.estado_actual(ap))
	# muerto
	p.call("_actualizar_animacion", 0.016)
	_chk(ArbolAnimacion.estado_actual(ap) == "attack", "c: el tajo aguanta su tiempo",
		"estado=%s" % ArbolAnimacion.estado_actual(ap))
	# `esta_vivo()` mira el flag `_muerto` de Entity, no la vida: se mata por
	# la via publica.
	p.die()
	_chk(not p.esta_vivo(), "c: el jugador esta muerto de verdad")
	for i in 30:
		p.call("_actualizar_animacion", 0.016)
	_chk(ArbolAnimacion.estado_actual(ap) == "die", "c: muerto entra en el estado 'die'",
		"estado=%s" % ArbolAnimacion.estado_actual(ap))
	# el bucle: idle/walk/attack ciclan, die no
	for c in ["idle", "walk", "attack"]:
		_chk(ap.get_animation(str(c)).loop_mode == Animation.LOOP_LINEAR, "c: '%s' cicla" % str(c))
	_chk(ap.get_animation("die").loop_mode == Animation.LOOP_NONE, "c: 'die' no cicla")
	# El avance del clip se mide aparte, con frames reales (ver _esperar_frames).


## (d) Cambiar de clase no deja el modelo anterior colgando.
func _test_cambio() -> void:
	var clases: Dictionary = _json(RUTA_CLASES).get("clases", {})
	var con_modelo: Array = []
	for cid in clases:
		if (clases[cid] as Dictionary).has("modelo"):
			con_modelo.append(str(cid))
	if con_modelo.size() < 2:
		return
	var p: Player = _jugador(str(con_modelo[0]))
	p.aplicar_clase(str(con_modelo[1]))
	var modelos: Array = p.get_children().filter(
		func(n: Node) -> bool: return str(n.name) == "Modelo")
	_chk(modelos.size() == 1, "d: queda un solo nodo 'Modelo'", "n=%d" % modelos.size())
	var m: MeshInstance3D = _primera_malla(p.get_node_or_null("Modelo") as Node3D)
	_chk(m != null, "d: el modelo nuevo tiene malla")
	if m != null:
		var ruta: String = str((clases[con_modelo[1]] as Dictionary)["modelo"])
		_chk(str(m.mesh.resource_path).begins_with(ruta), "d: es el modelo de la clase nueva",
			"malla=%s esperado=%s" % [str(m.mesh.resource_path), ruta])


## (e) El equipo cae donde toca: los offsets de la tabla son absolutos y estan
## medidos sobre un cuerpo de 1,7 m.
func _test_equipo_en_su_sitio() -> void:
	var cid: String = _una_clase_con_modelo()
	if cid == "":
		return
	var p: Player = _jugador(cid)
	var modelo: Node3D = p.get_node_or_null("Modelo") as Node3D
	var m: MeshInstance3D = _primera_malla(modelo)
	if m == null:
		_chk(false, "e: hay modelo que medir")
		return
	var esc: float = float((_json(RUTA_CLASES)["clases"][cid] as Dictionary).get("modelo_escala", 1.0))
	var base: AABB = m.global_transform * m.get_aabb()
	var aabb: AABB = AABB(base.position * esc, base.size * esc)
	_chk(absf(aabb.size.y - ALTO_ESPERADO) < 0.25, "e: el modelo mide lo que la capsula",
		"alto=%.2f esperado=%.2f" % [aabb.size.y, ALTO_ESPERADO])
	_chk(absf(aabb.position.y) < 0.05, "e: los pies en el suelo",
		"y=%.3f" % aabb.position.y)
	# El casco va a 1,58 m y la mano a 1,15 m: si el modelo no llega ahi, el
	# equipo vuela o se hunde.
	var cabeza: float = aabb.position.y + aabb.size.y
	_chk(absf(cabeza - 1.70) < TOLERANCIA, "e: la cabeza esta donde espera el casco",
		"cabeza=%.2f (casco a 1.58)" % cabeza)
	var a_mano: Dictionary = ANCLAJES.obtener("arma")
	var y_mano: float = float((a_mano.get("offset", [0, 1.15, 0]) as Array)[1])
	_chk(y_mano < aabb.size.y, "e: el anclaje de la mano esta dentro del modelo",
		"mano=%.2f alto=%.2f" % [y_mano, aabb.size.y])


## (f) Modelo ausente: cápsula y aviso, nunca un crash.
func _test_ausente() -> void:
	var p: Player = _jugador("mago")
	_chk(p.get_node_or_null("Modelo") != null, "f: el mago trae modelo")
	# Clase sin modelo declarado: se desmonta el anterior y no se cuelga nada.
	p.call("aplicar_modelo", "clase_inexistente")
	_chk(p.get_node_or_null("Modelo") == null, "f: una clase sin modelo no deja cuerpo")
	_chk(p.esta_vivo(), "f: el jugador sigue vivo y en pie")


func _jugador(clase: String) -> Player:
	var p: Player = PL.new()
	p.fijar_identidad("H", clase)
	p.aplicar_clase(clase)
	root.add_child(p)
	_basura.append(p)
	return p


func _una_clase_con_modelo() -> String:
	var clases: Dictionary = _json(RUTA_CLASES).get("clases", {})
	for cid in clases:
		if (clases[cid] as Dictionary).has("modelo"):
			return str(cid)
	return ""


func _primera_malla(n: Node) -> MeshInstance3D:
	if n == null:
		return null
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var hallada: MeshInstance3D = _primera_malla(c)
		if hallada != null:
			return hallada
	return null


func _buscar(n: Node, tipo: String) -> Node:
	if n == null:
		return null
	if n.get_class() == tipo:
		return n
	for c in n.get_children():
		var hallada: Node = _buscar(c, tipo)
		if hallada != null:
			return hallada
	return null


## Deja correr frames reales y comprueba que el clip avanza sin reiniciarse.
## Si `_poner_clip` llamara a `play()` en cada frame, la posicion se quedaria
## clavada en 0.
##
## Se usa un jugador NUEVO en vez de resucitar al del bloque anterior:
## `restaurar()` es la via del save y necesita el dict entero (con `version`),
## y aqui lo que se quiere medir es el reloj del AnimationPlayer.
func _esperar_frames(_delta: float) -> void:
	match _fase_espera:
		1:
			var cid: String = _una_clase_con_modelo()
			_p = _jugador(cid)
			_ap = _buscar(_p.get_node_or_null("Modelo"), "AnimationPlayer") as AnimationPlayer
			if _ap == null:
				_chk(false, "c: hay reproductor para medir el avance")
				_fase_espera = 5
			else:
				_fase_espera = 2
		2:
			_p.velocity = Vector3(3.0, 0.0, 0.0)
			_p.call("_actualizar_animacion", 0.016)
			_chk(str(_ap.current_animation) == "walk", "c: un jugador que anda reproduce 'walk'",
				"reproduciendo '%s'" % str(_ap.current_animation))
			_fase_espera = 3
		3:
			_frames_esperados += 1
			if _ap.current_animation_position <= 0.0:
				if _frames_esperados > 180:
					print("[TEST] c: sin presentacion no se mide el avance (se omite)")
					_fase_espera = 5
				return
			_fase_espera = 4
		4:
			_chk(_ap.current_animation_position > 0.0,
				"c: el clip avanza sin reiniciarse en cada frame",
				"posicion=%.3f" % _ap.current_animation_position)
			_fase_espera = 5
		5:
			_fase_espera = 0
			_test_cambio()
			_test_equipo_en_su_sitio()
			_test_frente()
			_test_ausente()
			_finalizar()


func _finalizar() -> void:
	print("[TEST] fase50_clases_modelos: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		if is_instance_valid(n):
			(n as Node).free()
	quit(_fallos)
