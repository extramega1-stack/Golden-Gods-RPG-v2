extends SceneTree
## Tests headless de la Fase 49 (modelos 3D en el juego, rig y clips).
##
## Lo que se demuestra es el CAMINO COMPLETO del asset real
## (`models/bandido_rig.glb`), no "que un GLB abre":
##
## (a) Manifiesto: todo `.glb` de `models/` está declarado, con licencia
##     CC0/CC-BY, `res://` existente y `.import` generado. Nadie de Blizzard.
## (b) Datos: el arquetipo que usa el modelo lo declara por clave (`modelo` +
##     `modelo_escala`), no por código.
## (c) Enemigo: `configurar()` cuelga el modelo como nodo `Modelo`, apaga la
##     cápsula, deja la textura a la vista (sin `material_override` plano) y
##     comparte la malla entre instancias (1 malla en memoria, N enemigos).
## (d) Rig: el `.glb` del arquetipo trae `Skeleton3D` con los 7 anclajes de
##     `data/anclajes.json` y un `AnimationPlayer` con los 4 clips de la FSM.
## (e) Clips: cambiar de estado reproduce el clip que toca. `die` no cicla.
## (f) Estático: un `.glb` sin piel (los otros 84 del pack) se cuelga igual y
##     sin `AnimationPlayer` no rompe nada.
## (g) El pool: reutilizar el nodo con un arquetipo SIN modelo desmonta el
##     modelo y devuelve la cápsula. Sin ese reset, un goblin riggeado se
##     convertiría en el cuerpo del siguiente arquetipo del pool.
## (h) Asset ausente: un `modelo` que no existe avisa y cae a la cápsula
##     (el juego no se rompe por un archivo que falte).
## (i) Presupuesto: el modelo respectea el techo de triángulos por entidad.
## (j) El contrato de "piso": el nodo compensa la altura para que los pies
##     queden en y=0 (si no, el bicho aparece enterrado).
##
## Cómo correrlo:
##   godot --headless --path <proyecto> --script res://tests/test_fase49_modelos_3d.gd

const RUTA_MANIFIESTO: String = "res://data/modelos.json"
const RUTA_ENEMIGOS: String = "res://data/enemies.json"
const ESCENA_ENEMIGO: PackedScene = preload("res://scenes/enemy/enemigo.tscn")
const RUTA_ESTATICA: String = "res://tests/fixtures/estatico.glb"
const ANCLAJES: Array = ["Chest", "Neck", "Head", "Hand.L", "Hand.R", "Foot.L", "Foot.R"]
const CLIPS: Array = ["idle", "walk", "attack", "die"]
const PRESUPUESTO_TRIS_POR_ENTIDAD: int = 30000

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 49 — modelos 3D (el bandido, dentro del juego)")


func _process(_d: float) -> bool:
	_test_manifiesto()
	_test_datos()
	_test_enemigo()
	_test_rig()
	_test_clips()
	_test_estatico()
	_test_pool()
	_test_ausente()
	_test_frente()
	_test_presupuesto()
	_test_piso()
	print("[TEST] fase49_modelos_3d: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		if is_instance_valid(n):
			(n as Node).free()
	quit(_fallos)
	return true


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


func _archivos_models() -> Array:
	var salida: Array = []
	var dir: DirAccess = DirAccess.open("res://models")
	if dir == null:
		return salida
	for f in dir.get_files():
		if f.get_extension().to_lower() == "glb":
			salida.append("res://models/" + f)
	return salida


## (a) Manifiesto: nada sin declarar, licencia válida, importado y sin
## ventaja de Blizzard.
func _test_manifiesto() -> void:
	var m: Dictionary = _json(RUTA_MANIFIESTO)
	_chk(not m.is_empty(), "a: existe " + RUTA_MANIFIESTO)
	var lista: Array = m.get("modelos", [])
	_chk(lista.size() > 0, "a: el manifiesto tiene al menos un modelo",
		"size=%d" % lista.size())
	var declarados: Dictionary = {}
	for entrada in lista:
		if not (entrada is Dictionary):
			continue
		var e: Dictionary = entrada
		var arch: String = str(e.get("archivo", ""))
		declarados[arch] = true
		_chk(not arch.is_empty(), "a: entrada con 'archivo'")
		if arch.is_empty():
			continue
		_chk(ResourceLoader.exists("res://models/" + arch), "a: el asset existe: " + arch)
		_chk(FileAccess.file_exists("res://models/%s.import" % arch),
			"a: Godot lo importó: " + arch)
		var lic: String = str(e.get("licencia", ""))
		_chk(lic in ["CC0", "CC-BY"], "a: licencia libre: " + arch, "licencia=" + lic)
		var fuente: String = str(e.get("fuente", "")).to_lower()
		_chk(not fuente.contains("blizzard"), "a: sin asset de Blizzard: " + arch)
		_chk(fuente != "", "a: con procedencia: " + arch)
		_chk(not str(e.get("nombre", "")).is_empty(), "a: con nombre legible: " + arch)
		# Si el asset trae animaciones, el manifiesto tiene que declararlas:
		# es el contrato con la FSM.
		var declarados_clips: Array = e.get("clips", [])
		for c in declarados_clips:
			_chk(str(c) in CLIPS, "a: clip declarado en la lista de la FSM: " + arch,
				"clip=" + str(c))
	var en_disco: Array = _archivos_models()
	_chk(en_disco.size() == lista.size(), "a: el disco y el manifiesto cuadran",
		"disco=%d manifiesto=%d" % [en_disco.size(), lista.size()])
	for ruta in en_disco:
		_chk(declarados.has(str(ruta.get_file())), "a: declarado en el manifiesto: " + str(ruta))


## (b) El modelo se declara POR DATOS, no por código.
func _test_datos() -> void:
	var e: Dictionary = _json(RUTA_ENEMIGOS)
	var arqs: Dictionary = e.get("arquetipos", {})
	_chk(arqs.size() >= 19, "b: siguen los 19 arquetipos", "n=%d" % arqs.size())
	var con_modelo: int = 0
	for clave in arqs:
		var a: Dictionary = arqs[clave]
		if not a.has("modelo"):
			continue
		con_modelo += 1
		var ruta: String = str(a["modelo"])
		_chk(ruta.begins_with("res://"), "b: ruta res:// en " + clave, ruta)
		_chk(ResourceLoader.exists(ruta), "b: el modelo existe en " + clave, ruta)
		var esc: float = float(a.get("modelo_escala", 1.0))
		_chk(esc > 0.05 and esc < 4.0, "b: escala sensata en " + clave, "escala=%.2f" % esc)
	_chk(con_modelo > 0, "b: al menos un arquetipo con modelo 3D",
		"con modelo=%d" % con_modelo)


## (c) El enemigo cuelga el modelo y apaga la cápsula.
func _test_enemigo() -> void:
	var arqs: Dictionary = _json(RUTA_ENEMIGOS).get("arquetipos", {})
	var clave: String = _primer_con_modelo(arqs)
	_chk(clave != "", "c: hay arquetipo con modelo")
	if clave == "":
		return
	var e1: Node3D = _enemigo()
	e1.call("configurar", arqs[clave])
	var modelo: Node3D = e1.get_node_or_null("Modelo") as Node3D
	_chk(modelo != null, "c: el modelo queda como nodo 'Modelo'")
	if modelo == null:
		return
	var capsula: MeshInstance3D = e1.get_node_or_null("Cuerpo") as MeshInstance3D
	_chk(capsula != null and not capsula.visible, "c: la cápsula se apaga")
	var m1: MeshInstance3D = _primera_malla(modelo)
	_chk(m1 != null, "c: el modelo trae malla")
	if m1 == null:
		return
	_chk(not (m1.mesh is CapsuleMesh), "c: la malla del modelo no es la cápsula",
		"malla=%s" % str(m1.mesh.get_class()))
	_chk(m1.material_override == null, "c: sin material_override plano (se ve la textura)")
	var esc: float = float((arqs[clave] as Dictionary).get("modelo_escala", 1.0))
	if absf(esc - 1.0) > 0.001:
		_chk(modelo.scale.is_equal_approx(Vector3(esc, esc, esc)),
			"c: escala del modelo aplicada", "scale=%s" % str(modelo.scale))
	# 1 malla en memoria, N instancias (fase 12.1): el recurso se comparte.
	var e2: Node3D = _enemigo()
	e2.call("configurar", arqs[clave])
	var m2: MeshInstance3D = _primera_malla(e2.get_node_or_null("Modelo") as Node3D)
	_chk(m2 != null and m2.mesh == m1.mesh, "c: la malla se comparte entre instancias (1 en memoria)")


## (d) El `.glb` del arquetipo viene riggeado y con los 4 clips de la FSM.
func _test_rig() -> void:
	var arqs: Dictionary = _json(RUTA_ENEMIGOS).get("arquetipos", {})
	var clave: String = _primer_con_modelo(arqs)
	if clave == "":
		return
	var e: Node3D = _enemigo()
	e.call("configurar", arqs[clave])
	var modelo: Node3D = e.get_node_or_null("Modelo") as Node3D
	if modelo == null:
		_chk(false, "d: hay modelo que mirar")
		return
	var sk: Skeleton3D = _buscar(modelo, "Skeleton3D") as Skeleton3D
	_chk(sk != null, "d: el modelo trae Skeleton3D")
	if sk != null:
		var nombres: Array = []
		for i in sk.get_bone_count():
			nombres.append(sk.get_bone_name(i))
		for a in ANCLAJES:
			_chk(str(a) in nombres, "d: hueso de anclaje presente: " + str(a))
	var ap: AnimationPlayer = _buscar(modelo, "AnimationPlayer") as AnimationPlayer
	_chk(ap != null, "d: el modelo trae AnimationPlayer")
	if ap == null:
		return
	for c in CLIPS:
		_chk(ap.has_animation(str(c)), "d: clip presente: " + str(c))
	# La malla tiene que estar "skinned" de verdad, si no el esqueleto es
	# decorado y el modelo no se deforma.
	var m: MeshInstance3D = _primera_malla(modelo)
	_chk(m != null and m.skin != null, "d: la malla tiene Skin (se deforma)")
	if m != null and m.skin != null:
		_chk(m.skin.get_bind_count() > 0, "d: la Skin tiene bones")


## (e) El clip sigue al estado de la FSM.
func _test_clips() -> void:
	var arqs: Dictionary = _json(RUTA_ENEMIGOS).get("arquetipos", {})
	var clave: String = _primer_con_modelo(arqs)
	if clave == "":
		return
	var e: Node3D = _enemigo()
	e.call("configurar", arqs[clave])
	var ap: AnimationPlayer = _buscar(e.get_node_or_null("Modelo") as Node3D, "AnimationPlayer") as AnimationPlayer
	if ap == null:
		_chk(false, "e: hay AnimationPlayer que mirar")
		return
	var orden: Array = [[0, "idle"], [1, "walk"], [2, "attack"], [3, "die"]]
	for par in orden:
		e.set("estado", int(par[0]))
		_chk(str(ap.current_animation) == str(par[1]),
			"e: estado %d reproduce '%s'" % [int(par[0]), str(par[1])],
			"reproduciendo '%s'" % str(ap.current_animation))
		_chk(ap.is_playing(), "e: el clip de '%s' suena" % str(par[1]))
	# `idle`/`walk`/`attack` ciclan (si no, el bicho se congela a media pose)
	# y `die` no (si no, un cadaver se levanta solo).
	for c in ["idle", "walk", "attack"]:
		_chk(ap.get_animation(str(c)).loop_mode == Animation.LOOP_LINEAR,
			"e: '%s' cicla" % str(c))
	_chk(ap.get_animation("die").loop_mode == Animation.LOOP_NONE,
		"e: 'die' no cicla")
	# Setear el mismo estado no reinicia el clip (el pool setea estados).
	var pos_antes: float = ap.current_animation_position
	e.set("estado", 3)
	_chk(is_equal_approx(ap.current_animation_position, pos_antes),
		"e: setear el mismo estado no reinicia la animación")


## (f) Un `.glb` sin piel (los otros 84 del pack) se cuelga igual.
func _test_estatico() -> void:
	_chk(ResourceLoader.exists(RUTA_ESTATICA), "f: existe el fixture estático")
	if not ResourceLoader.exists(RUTA_ESTATICA):
		return
	var e: Node3D = _enemigo()
	e.call("configurar", {"nombre": "Estatico", "modelo": RUTA_ESTATICA})
	var modelo: Node3D = e.get_node_or_null("Modelo") as Node3D
	_chk(modelo != null, "f: el modelo estático se cuelga")
	if modelo == null:
		return
	_chk(_primera_malla(modelo) != null, "f: el estático trae malla")
	_chk(_buscar(modelo, "AnimationPlayer") == null, "f: el estático no tiene reproductor")
	# Cambiar de estado con modelo estático no puede reventar nada.
	for i in 4:
		e.set("estado", i)
	_chk(true, "f: cambiar de estado sin clips no rompe")


## (g) El pool: un arquetipo sin modelo desmonta el modelo y deja la cápsula.
func _test_pool() -> void:
	var arqs: Dictionary = _json(RUTA_ENEMIGOS).get("arquetipos", {})
	var clave: String = _primer_con_modelo(arqs)
	var sin_modelo: String = ""
	for k in arqs:
		if not (arqs[k] as Dictionary).has("modelo"):
			sin_modelo = str(k)
			break
	_chk(clave != "" and sin_modelo != "", "g: hay arquetipo con y sin modelo")
	if clave == "" or sin_modelo == "":
		return
	var e: Node3D = _enemigo()
	e.call("configurar", arqs[clave])
	_chk(e.get_node_or_null("Modelo") != null, "g: el modelo está puesto")
	e.call("configurar", arqs[sin_modelo])
	_chk(e.get_node_or_null("Modelo") == null, "g: el modelo se desmonta al reusar el nodo",
		"modelo=%s" % str(e.get_node_or_null("Modelo")))
	var cuerpo: MeshInstance3D = e.get_node_or_null("Cuerpo") as MeshInstance3D
	_chk(cuerpo != null and cuerpo.mesh is CapsuleMesh, "g: vuelve a la cápsula")
	_chk(cuerpo != null and cuerpo.visible, "g: la cápsula vuelve a verse")
	_chk(cuerpo != null and cuerpo.scale.is_equal_approx(Vector3.ONE), "g: la escala vuelve a 1",
		"scale=%s" % str(cuerpo.scale))
	_chk(cuerpo != null and cuerpo.material_override != null, "g: el arquetipo sin modelo sí se tiñe")


## (h) Un modelo que no existe no rompe el juego: cápsula + aviso.
func _test_ausente() -> void:
	var e: Node3D = _enemigo()
	e.call("configurar", {
		"nombre": "Roto",
		"modelo": "res://models/no_existe_este_archivo.glb",
		"color": [0.5, 0.2, 0.2],
	})
	var cuerpo: MeshInstance3D = e.get_node_or_null("Cuerpo") as MeshInstance3D
	_chk(e.get_node_or_null("Modelo") == null, "h: no cuelga nada")
	_chk(cuerpo != null and cuerpo.mesh is CapsuleMesh, "h: cae a la cápsula si falta el modelo")
	_chk(cuerpo != null and cuerpo.material_override != null, "h: y se tiñe igual que antes")


## (h2) El enemigo tambien mira al frente al que persigue: el pack viene en +Z
##      y el juegoPersigue hacia el -Z.
func _test_frente() -> void:
	var arqs: Dictionary = _json(RUTA_ENEMIGOS).get("arquetipos", {})
	var clave: String = _primer_con_modelo(arqs)
	if clave == "":
		return
	var e: Node3D = _enemigo()
	e.call("configurar", arqs[clave])
	var modelo: Node3D = e.get_node_or_null("Modelo") as Node3D
	_chk(modelo != null, "h2: hay modelo")
	if modelo == null:
		return
	_chk(is_equal_approx(modelo.rotation.y, Cuerpo.GIRO_MODELO),
		"h2: el enemigo se gira para mirar al frente",
		"rotation.y=%.2f" % modelo.rotation.y)
	# Horizontal a proposito: el enemigo se pega al terreno y ese declive no
	# dice nada sobre hacia donde persigue.
	var cara: Vector3 = modelo.global_transform.basis.z
	var persigue: Vector3 = -e.global_transform.basis.z
	cara = Vector3(cara.x, 0.0, cara.z).normalized()
	persigue = Vector3(persigue.x, 0.0, persigue.z).normalized()
	_chk(cara.dot(persigue) > 0.99, "h2: el enemigo mira a donde persigue",
		"dot=%.3f" % cara.dot(persigue))


## (i) El presupuesto por entidad.
func _test_presupuesto() -> void:
	var arqs: Dictionary = _json(RUTA_ENEMIGOS).get("arquetipos", {})
	var clave: String = _primer_con_modelo(arqs)
	if clave == "":
		return
	var e: Node3D = _enemigo()
	e.call("configurar", arqs[clave])
	var m: MeshInstance3D = _primera_malla(e.get_node_or_null("Modelo") as Node3D)
	if m == null:
		_chk(false, "i: hay malla que medir")
		return
	var tris: int = m.mesh.get_faces().size() / 3
	_chk(tris > 0, "i: la malla tiene geometría", "tris=%d" % tris)
	_chk(tris <= PRESUPUESTO_TRIS_POR_ENTIDAD, "i: triángulos dentro del presupuesto por entidad",
		"tris=%d techo=%d" % [tris, PRESUPUESTO_TRIS_POR_ENTIDAD])


## (j) El contrato de "piso": los pies quedan en y=0.
func _test_piso() -> void:
	var m: Dictionary = _json(RUTA_MANIFIESTO)
	var lista: Array = m.get("modelos", [])
	if lista.is_empty():
		return
	var arch: String = str((lista[0] as Dictionary).get("archivo", ""))
	var ruta: String = "res://models/" + arch
	if not ResourceLoader.exists(ruta):
		return
	var inst: Node = (load(ruta) as PackedScene).instantiate()
	_basura.append(inst)
	root.add_child(inst)
	var mi: MeshInstance3D = _primera_malla(inst)
	_chk(mi != null, "j: el modelo tiene malla")
	if mi == null:
		return
	var aabb: AABB = mi.global_transform * mi.get_aabb()
	_chk(absf(aabb.position.y) < 0.02, "j: los pies quedan en el suelo (y~0)",
		"y=%.4f alto=%.2f" % [aabb.position.y, aabb.size.y])
	_chk(aabb.size.y > 0.1, "j: el modelo tiene altura real", "alto=%.3f" % aabb.size.y)


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


## Primer nodo del subárbol cuya clase sea `tipo` ("Skeleton3D", "AnimationPlayer").
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


func _primer_con_modelo(arqs: Dictionary) -> String:
	for k in arqs:
		if (arqs[k] as Dictionary).has("modelo"):
			return str(k)
	return ""


func _enemigo() -> Node3D:
	var e: Node3D = ESCENA_ENEMIGO.instantiate() as Node3D
	root.add_child(e)
	_basura.append(e)
	return e
