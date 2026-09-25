class_name PaperDoll
extends Node3D
## Muñeco procedural del héroe (fase 36): muestra el equipo equipado en 3D.
##
## Cada slot ocupado de `Equipo` genera una pieza: un modelo GLB si el slot
## tiene `mesh_path` en `data/anclajes.json`, y mientras no lo tenga, el
## RESPALDO PROCEDURAL que la tabla describe (`forma`).
##
## Fase 48: aquí ya NO hay offsets, colores ni formas hardcodeadas. Todo sale
## de `AnclajesDB` (`data/anclajes.json`), la tabla que el spec prometía desde
## la fase 43. Poner un modelo 3D es rellenar `mesh_path` en el JSON, no
## reescribir este script. Los 85 GLB de Meshy están autorizados (CC0/CC-BY)
## pero aún no están en el repo: hoy todas las piezas son procedurales.
##
## Las piezas siguen siendo MeshInstance3D con malla y material COMPARTIDOS,
## con los mismos nombres de nodo de siempre (Arma/Hoja, Escudo, Coraza...).
## Sin equipo no genera nada (solo la cápsula del tscn). Puro visual: nunca
## toca stats (los mods los pone `Equipo`).
##
## Se auto-suscribe a `equipo.cambiado`; como el save REEMPLAZA el objeto
## `Equipo`, cada frame verifica la referencia (comparación barata) y si
## cambió, re-suscribe y reconstruye. `reconstruir()` también es pública
## (demo/tests).

## Mallas y materiales compartidos por slot (fase 12.1: nada único por pieza).
## La clave incluye el color porque ahora el tinte sale de la tabla.
static var _mats: Dictionary = {}

var _jugador: Player = null
var _equipo: Equipo = null


func _ready() -> void:
	reconstruir()


## Conecta al jugador (re-llamable). No duplica suscripciones.
func conectar(j: Player) -> void:
	_jugador = j
	_vigilar_equipo(true)


func _process(_delta: float) -> void:
	_vigilar_equipo(false)


## Si el objeto Equipo cambió (save/load lo reemplaza), re-suscribe y
## reconstruye. Comparación de referencia por frame: barata y sin polling.
func _vigilar_equipo(forzar: bool) -> void:
	var eq: Equipo = null
	if _jugador != null and is_instance_valid(_jugador):
		eq = _jugador.equipo
	if eq == _equipo and not forzar:
		return
	if _equipo != null and is_instance_valid(_equipo):
		if _equipo.cambiado.is_connected(reconstruir):
			_equipo.cambiado.disconnect(reconstruir)
	_equipo = eq
	if _equipo != null and is_instance_valid(_equipo):
		if not _equipo.cambiado.is_connected(reconstruir):
			_equipo.cambiado.connect(reconstruir)
	reconstruir()


## Tira las piezas y regenera desde el equipo actual.
func reconstruir(_arg = null) -> void:
	for h in get_children():
		h.queue_free()
	if _equipo == null or not is_instance_valid(_equipo):
		return
	for slot in Equipo.SLOTS:
		var item_id: String = _equipo.equipado_en(slot)
		if item_id == "":
			continue
		var pieza: Node3D = _pieza(slot)
		if pieza != null:
			pieza.name = slot
			add_child(pieza)


## Pieza de un slot, según la tabla de anclajes. `mesh_path` vacío = respaldo
## procedural; con ruta = el modelo. Si la ruta no existe (o no hay tabla),
## avisa y cae al respaldo: el juego nunca se rompe por un asset que falta.
func _pieza(slot: String) -> Node3D:
	var anclaje: Dictionary = AnclajesDB.obtener(slot)
	if anclaje.is_empty():
		push_warning("[PaperDoll] slot sin anclaje en data/anclajes.json: '%s'" % slot)
		return null
	var forma: Dictionary = AnclajesDB.forma_de(slot)
	var tinte: Color = AnclajesDB.tinte_de(slot)
	var nombre: String = str(forma.get("nombre", slot))
	var metal: float = float(forma.get("metal", 0.0))
	var brillo: bool = bool(forma.get("brillo", false))
	match str(forma.get("tipo", "")):
		"caja":
			var caja := _caja(nombre, _vec3(forma.get("tam", [])), tinte, metal, brillo)
			_aplicar_anclaje(caja, slot)
			return caja
		"esfera":
			var esfe := _esfera(nombre, float(forma.get("radio", 0.1)),
				float(forma.get("alto", 0.2)), tinte, metal, brillo)
			_aplicar_anclaje(esfe, slot)
			return esfe
		"par":
			var par := _par(nombre, _vec3(forma.get("tam", [])), tinte, metal, brillo)
			_aplicar_anclaje(par, slot)
			return par
		"espada":
			var espada := _espada(nombre, forma, tinte, metal, brillo)
			_aplicar_anclaje(espada, slot)
			return espada
		"mesh":
			var glb: Node3D = _pieza_glb(slot)
			if glb != null:
				_aplicar_anclaje(glb, slot)
				return glb
	# Sin forma reconocida: respaldo mínimo (una caja) para que el slot no
	# desaparezca en silencio.
	push_warning("[PaperDoll] forma desconocida en el slot '%s'" % slot)
	var caja_vacia := _caja(nombre, Vector3(0.12, 0.12, 0.12), tinte, metal, brillo)
	_aplicar_anclaje(caja_vacia, slot)
	return caja_vacia


## Coloca la pieza donde dice la tabla (offset + rotación + escala).
func _aplicar_anclaje(n: Node3D, slot: String) -> void:
	if n == null:
		return
	n.position = AnclajesDB.offset_de(slot)
	n.rotation_degrees = AnclajesDB.rotacion_de(slot)
	var e: float = AnclajesDB.escala_de(slot)
	if not is_equal_approx(e, 1.0):
		n.scale = Vector3(e, e, e)


## Fase 48: el modelo del slot, si lo hay. Es la vía por la que entrará el
## primer GLB: basta con poner la ruta en `mesh_path` del JSON.
func _pieza_glb(slot: String) -> Node3D:
	var ruta: String = str(AnclajesDB.obtener(slot).get("mesh_path", ""))
	if ruta == "":
		return null
	if not ResourceLoader.exists(ruta):
		push_warning("[PaperDoll] el modelo de '%s' no existe: %s" % [slot, ruta])
		return null
	var ps: PackedScene = load(ruta) as PackedScene
	if ps == null:
		push_warning("[PaperDoll] '%s' no es una escena válida: %s" % [slot, ruta])
		return null
	var inst: Node3D = ps.instantiate() as Node3D
	return inst


## Lee un tamaño [x, y, z] del JSON (Vector3.ZERO si no viene bien).
func _vec3(a: Variant) -> Vector3:
	if not (a is Array):
		return Vector3.ZERO
	var arr: Array = a as Array
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


## Arma de varias piezas (hoja + guarda): la lista `partes` de la tabla.
func _espada(nombre: String, forma: Dictionary, color: Color, metal: float,
		brillo: bool) -> Node3D:
	var raiz := Node3D.new()
	raiz.name = nombre
	for p in (forma.get("partes", []) as Array):
		if not (p is Dictionary):
			continue
		var pd: Dictionary = p
		var tipo: String = str(pd.get("tipo", "caja"))
		var pieza: MeshInstance3D = null
		if tipo == "esfera":
			pieza = _esfera(str(pd.get("nombre", "Pieza")),
				float(pd.get("radio", 0.1)), float(pd.get("alto", 0.2)), color, metal, brillo)
		else:
			pieza = _caja(str(pd.get("nombre", "Pieza")),
				_vec3(pd.get("tam", [])), color, metal, brillo)
		pieza.position = _vec3(pd.get("pos", []))
		raiz.add_child(pieza)
	return raiz


func _caja(nombre: String, tam: Vector3, color: Color, metal: float,
		brillo: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nombre
	var malla := BoxMesh.new()
	malla.size = tam
	mi.mesh = malla
	mi.material_override = _mat(nombre, color, metal, brillo)
	return mi


func _esfera(nombre: String, radio: float, alto: float, color: Color,
		metal: float, brillo: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nombre
	var malla := SphereMesh.new()
	malla.radius = radio
	malla.height = alto
	mi.mesh = malla
	mi.material_override = _mat(nombre, color, metal, brillo)
	return mi


## Par simétrico (guantes, botas): dos cajas espejadas en x. La posición
## viene de la tabla (el `offset.x` es la distancia al centro).
func _par(nombre: String, tam: Vector3, color: Color, metal: float,
		brillo: bool) -> Node3D:
	var raiz := Node3D.new()
	raiz.name = nombre
	for lado in [1.0, -1.0]:
		var mi := MeshInstance3D.new()
		mi.name = "%s_%s" % [nombre, "der" if lado > 0.0 else "izq"]
		var malla := BoxMesh.new()
		malla.size = tam
		mi.mesh = malla
		mi.material_override = _mat(nombre, color, metal, brillo)
		raiz.add_child(mi)
	return raiz


## Material compartido por nombre de pieza. `metal` y `brillo` los decide la
## tabla: el brillo es lo que enciende la emisión (oro y gemas brillan; el
## acero y el cuero no).
static func _mat(nombre: String, color: Color, metal: float,
		brillo: bool) -> StandardMaterial3D:
	var clave: String = "%s|%s|%.2f|%s" % [nombre, color.to_html(false), metal, str(brillo)]
	if _mats.has(clave):
		return _mats[clave] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.55
	mat.emission_enabled = brillo
	if brillo:
		mat.emission = color * 0.6
	_mats[clave] = mat
	return mat
