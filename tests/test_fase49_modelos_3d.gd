extends SceneTree
## Tests headless de la Fase 49 (modelos 3D en el juego).
##
## Lo que se demuestra aquí es el CAMINO COMPLETO del primer asset real
## (`models/bandido.glb`), no "que un GLB abre":
##
## (a) Manifiesto: todo `.glb` de `models/` está declarado, con licencia
##     CC0/CC-BY, `res://` existente y `.import` generado. Nadie de Blizzard.
## (b) Datos: el arquetipo que usa el modelo lo declara por clave (`modelo` +
##     `modelo_escala`), no por código.
## (c) Enemigo: `configurar()` cambia la cápsula por el modelo, deja la
##     textura a la vista (sin `material_override` plano) y comparte la malla
##     entre todos los enemigos de ese arquetipo (1 malla en memoria, N
##     instancias).
## (d) El pool: reutilizar el nodo con un arquetipo SIN modelo devuelve la
##     cápsula de la escena. Sin este reset, un goblin con modelo se
##     convertiría en el cuerpo del siguiente arquetipo del pool.
## (e) Asset ausente: un `modelo` que no existe avisa y cae a la cápsula
##     (el juego no se rompe por un archivo que falte).
## (f) Presupuesto: el modelo respectea el techo de triángulos por entidad.
## (g) El contrato de "piso": el nodo del GLB compensa la mitad de la altura
##     para que los pies queden en y=0 (si no, el bicho aparece enterrado).
##
## Cómo correrlo:
##   godot --headless --path <proyecto> --script res://tests/test_fase49_modelos_3d.gd

const RUTA_MANIFIESTO: String = "res://data/modelos.json"
const RUTA_ENEMIGOS: String = "res://data/enemies.json"
const ESCENA_ENEMIGO: PackedScene = preload("res://scenes/enemy/enemigo.tscn")
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
	_test_pool()
	_test_ausente()
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


## (c) El enemigo viste el modelo: malla correcta, textura a la vista y
## compartida entre instancias.
func _test_enemigo() -> void:
	var arqs: Dictionary = _json(RUTA_ENEMIGOS).get("arquetipos", {})
	var clave: String = _primer_con_modelo(arqs)
	_chk(clave != "", "c: hay arquetipo con modelo")
	if clave == "":
		return
	var e1: Node3D = _enemigo()
	var e1_config: Dictionary = arqs[clave]
	# La config se llama por la vía real del juego (sobre la instancia).
	e1.call("configurar", e1_config)
	var cuerpo: MeshInstance3D = e1.get_node_or_null("Cuerpo") as MeshInstance3D
	_chk(cuerpo != null, "c: el enemigo conserva su nodo 'Cuerpo'")
	if cuerpo == null:
		return
	_chk(not cuerpo.mesh is CapsuleMesh, "c: la cápsula se sustituye por el modelo",
		"malla=%s" % str(cuerpo.mesh.get_class()))
	_chk(cuerpo.material_override == null, "c: sin material_override plano (se ve la textura)")
	var esc: float = float(e1_config.get("modelo_escala", 1.0))
	if absf(esc - 1.0) > 0.001:
		_chk(cuerpo.scale.is_equal_approx(Vector3(esc, esc, esc)),
			"c: escala del cuerpo aplicada", "scale=%s" % str(cuerpo.scale))
	var e2: Node3D = _enemigo()
	e2.call("configurar", e1_config)
	var cuerpo2: MeshInstance3D = e2.get_node_or_null("Cuerpo") as MeshInstance3D
	_chk(cuerpo2.mesh == cuerpo.mesh, "c: la malla se comparte entre instancias (1 en memoria)")


## (d) El pool: un arquetipo sin modelo devuelve la cápsula.
func _test_pool() -> void:
	var arqs: Dictionary = _json(RUTA_ENEMIGOS).get("arquetipos", {})
	var clave: String = _primer_con_modelo(arqs)
	var sin_modelo: String = ""
	for k in arqs:
		if not (arqs[k] as Dictionary).has("modelo"):
			sin_modelo = str(k)
			break
	_chk(clave != "" and sin_modelo != "", "d: hay arquetipo con y sin modelo")
	if clave == "" or sin_modelo == "":
		return
	var e: Node3D = _enemigo()
	e.call("configurar", arqs[clave])
	var cuerpo: MeshInstance3D = e.get_node_or_null("Cuerpo") as MeshInstance3D
	var malla_modelo: Mesh = cuerpo.mesh
	e.call("configurar", arqs[sin_modelo])
	_chk(cuerpo.mesh is CapsuleMesh, "d: vuelve a la cápsula al reusar el nodo",
		"malla=%s" % str(cuerpo.mesh.get_class()))
	_chk(cuerpo.mesh != malla_modelo, "d: la malla del modelo se soltó")
	_chk(cuerpo.scale.is_equal_approx(Vector3.ONE), "d: la escala vuelve a 1",
		"scale=%s" % str(cuerpo.scale))
	_chk(cuerpo.material_override != null, "d: el arquetipo sin modelo sí se tiñe")


## (e) Un modelo que no existe no rompe el juego: cápsula + aviso.
func _test_ausente() -> void:
	var e: Node3D = _enemigo()
	var roto: Dictionary = {
		"nombre": "Roto",
		"modelo": "res://models/no_existe_este_archivo.glb",
		"color": [0.5, 0.2, 0.2],
	}
	e.call("configurar", roto)
	var cuerpo: MeshInstance3D = e.get_node_or_null("Cuerpo") as MeshInstance3D
	_chk(cuerpo != null and cuerpo.mesh is CapsuleMesh, "e: cae a la cápsula si falta el modelo")
	_chk(cuerpo.material_override != null, "e: y se tiñe igual que antes")


## (f) El presupuesto por entidad.
func _test_presupuesto() -> void:
	var arqs: Dictionary = _json(RUTA_ENEMIGOS).get("arquetipos", {})
	var clave: String = _primer_con_modelo(arqs)
	if clave == "":
		return
	var e: Node3D = _enemigo()
	e.call("configurar", arqs[clave])
	var cuerpo: MeshInstance3D = e.get_node_or_null("Cuerpo") as MeshInstance3D
	var tris: int = cuerpo.mesh.get_faces().size() / 3
	_chk(tris > 0, "f: la malla tiene geometría", "tris=%d" % tris)
	_chk(tris <= PRESUPUESTO_TRIS_POR_ENTIDAD, "f: triángulos dentro del presupuesto por entidad",
		"tris=%d techo=%d" % [tris, PRESUPUESTO_TRIS_POR_ENTIDAD])


## (g) El contrato de "piso": el nodo del GLB deja los pies en y=0.
func _test_piso() -> void:
	var m: Dictionary = _json(RUTA_MANIFIESTO)
	var lista: Array = m.get("modelos", [])
	if lista.is_empty():
		return
	var arch: String = str((lista[0] as Dictionary).get("archivo", ""))
	var ruta: String = "res://models/" + arch
	if not ResourceLoader.exists(ruta):
		return
	var ps: PackedScene = load(ruta) as PackedScene
	var inst: Node = ps.instantiate()
	_basura.append(inst)
	root.add_child(inst)
	var mi: MeshInstance3D = null
	for n in _mallas(inst):
		mi = n
		break
	_chk(mi != null, "g: el modelo tiene malla")
	if mi == null:
		return
	var aabb: AABB = mi.global_transform * mi.get_aabb()
	_chk(absf(aabb.position.y) < 0.02, "g: los pies quedan en el suelo (y~0)",
		"y=%.4f alto=%.2f" % [aabb.position.y, aabb.size.y])
	_chk(aabb.size.y > 0.1, "g: el modelo tiene altura real", "alto=%.3f" % aabb.size.y)


func _mallas(n: Node) -> Array:
	var salida: Array = []
	if n is MeshInstance3D:
		salida.append(n)
	for c in n.get_children():
		salida.append_array(_mallas(c))
	return salida


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
