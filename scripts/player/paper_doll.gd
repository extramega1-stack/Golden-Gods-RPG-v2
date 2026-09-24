class_name PaperDoll
extends Node3D
## Muñeco procedural del héroe (fase 36): muestra el equipo equipado en 3D.
##
## Cada slot ocupado de `Equipo` genera una pieza procedural (MeshInstance3D
## con malla + material COMPARTIDOS por slot): espada y escudo a los lados,
## casco en la cabeza, coraza en el torso, guantes y botas, y gemas doradas
## emissive para la joyería. Sin equipo no genera nada (solo la cápsula del
## tscn). Puro visual: nunca toca stats (los mods los pone `Equipo`).
##
## Se auto-suscribe a `equipo.cambiado`; como el save REEMPLAZA el objeto
## `Equipo`, cada frame verifica la referencia (comparación barata) y si
## cambió, re-suscribe y reconstruye. `reconstruir()` también es pública
## (demo/tests).

## Colores por slot (acero, madera, cuero, oro).
const COLOR_ACERO: Color = Color(0.70, 0.72, 0.78)
const COLOR_MADERA: Color = Color(0.50, 0.35, 0.20)
const COLOR_CUERO: Color = Color(0.45, 0.30, 0.18)
const COLOR_ORO: Color = Color(1.00, 0.75, 0.25)

## Mallas y materiales compartidos por slot (fase 12.1: nada único por pieza).
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


## Pieza procedural por slot resuelto (pendiente_1 → pendiente…).
func _pieza(slot: String) -> Node3D:
	var base: String = slot.split("_")[0]
	match base:
		"arma":
			return _espada()
		"escudo":
			return _caja("Escudo", Vector3(0.10, 0.70, 0.50),
				Vector3(-0.52, 1.00, 0.0), COLOR_MADERA)
		"casco":
			return _esfera("Casco", 0.28, 0.55, Vector3(0, 1.58, 0), COLOR_ACERO)
		"armadura":
			return _caja("Coraza", Vector3(0.72, 0.70, 0.46),
				Vector3(0, 1.00, 0), COLOR_ACERO)
		"guantes":
			return _par("Guantes", Vector3(0.16, 0.16, 0.16),
				Vector3(0.44, 0.95, 0), COLOR_CUERO)
		"botas":
			return _par("Botas", Vector3(0.20, 0.26, 0.30),
				Vector3(0.16, 0.13, 0), COLOR_CUERO)
		"pendiente":
			var lado: float = 0.26 if slot == "pendiente_1" else -0.26
			return _esfera("Pendiente", 0.07, 0.14, Vector3(lado, 1.48, 0.05),
				COLOR_ORO, true)
		"collar", "amuleto":
			return _esfera("Joya", 0.09, 0.18, Vector3(0, 1.28, 0.30),
				COLOR_ORO, true)
		"anillo":
			var x: float = 0.44 if slot == "anillo_1" else -0.44
			return _esfera("Anillo", 0.06, 0.12, Vector3(x, 0.90, 0.10),
				COLOR_ORO, true)
	return null


## Espada a la derecha: hoja + guarda.
func _espada() -> Node3D:
	var raiz := Node3D.new()
	raiz.name = "Arma"
	var hoja := MeshInstance3D.new()
	hoja.name = "Hoja"
	var malla := BoxMesh.new()
	malla.size = Vector3(0.09, 0.95, 0.18)
	hoja.mesh = malla
	hoja.material_override = _mat("arma", COLOR_ACERO, 0.6)
	hoja.position = Vector3(0.50, 1.15, 0.10)
	raiz.add_child(hoja)
	var guarda := MeshInstance3D.new()
	guarda.name = "Guarda"
	var gm := BoxMesh.new()
	gm.size = Vector3(0.30, 0.07, 0.24)
	guarda.mesh = gm
	guarda.material_override = _mat("arma", COLOR_ACERO, 0.6)
	guarda.position = Vector3(0.50, 0.66, 0.10)
	raiz.add_child(guarda)
	return raiz


func _caja(nombre: String, tam: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nombre
	var malla := BoxMesh.new()
	malla.size = tam
	mi.mesh = malla
	mi.material_override = _mat(nombre, color, 0.0)
	mi.position = pos
	return mi


func _esfera(nombre: String, radio: float, alto: float, pos: Vector3,
		color: Color, brillo: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nombre
	var malla := SphereMesh.new()
	malla.radius = radio
	malla.height = alto
	mi.mesh = malla
	mi.material_override = _mat(nombre, color, 0.8 if brillo else 0.0)
	mi.position = pos
	return mi


## Par simétrico (guantes, botas): dos cajas espejadas en x.
func _par(nombre: String, tam: Vector3, pos: Vector3, color: Color) -> Node3D:
	var raiz := Node3D.new()
	raiz.name = nombre
	for lado in [1.0, -1.0]:
		var mi := MeshInstance3D.new()
		mi.name = "%s_%s" % [nombre, "der" if lado > 0.0 else "izq"]
		var malla := BoxMesh.new()
		malla.size = tam
		mi.mesh = malla
		mi.material_override = _mat(nombre, color, 0.0)
		mi.position = Vector3(pos.x * lado, pos.y, pos.z)
		raiz.add_child(mi)
	return raiz


## Material compartido por nombre (emissive para joyería).
static func _mat(nombre: String, color: Color, metal: float) -> StandardMaterial3D:
	if _mats.has(nombre):
		return _mats[nombre] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.55
	if metal >= 0.8:
		mat.emission_enabled = true
		mat.emission = color * 0.6
	_mats[nombre] = mat
	return mat
