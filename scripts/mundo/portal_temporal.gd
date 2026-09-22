class_name PortalTemporal
extends Node3D
## TEMPORAL — Fase 14.1: portales de inspección para Juan Diego.
## QUITAR cuando lo pida: borrar este archivo + `data/portales_temp.json`
## + el bloque TEMPORAL de `scenes/demo/fase14_demo.gd`.
##
## Un portal es un anillo procedural con look "debug/temporal" (magenta
## emissive, nada que parezca contenido final) + Label3D con el nombre del
## destino (billboard, legible desde lejos). Acercarse + E teletransporta.
## Sin colisiones: se atraviesa caminando.
##
## Uso desde la demo:
##   var p := PortalTemporal.new()
##   p.configurar(dest)          # dest: {id, nombre, x, z} de portales_temp.json
##   p.position = Vector3(x, terreno.altura_en(x, z), z)
##   add_child(p)

## Ruta por defecto de los destinos (data-driven aunque sea temporal).
const RUTA_DESTINOS: String = "res://data/portales_temp.json"
## Radio de interacción: hay que estar pegado al portal y pulsar E.
const RADIO_USO: float = 6.0
## Altura extra sobre el terreno al teletransportar (no aparecer enterrado).
const MARGEN_SUELO: float = 1.5

## Destino configurado: {id: String, nombre: String, x: float, z: float}.
var destino: Dictionary = {}
var _anillo: MeshInstance3D = null
var _t: float = 0.0


static func cargar_destinos(ruta: String = RUTA_DESTINOS) -> Array:
	var lista: Array = []
	if not FileAccess.file_exists(ruta):
		push_warning("[PortalTemporal] sin %s: no hay portales" % ruta)
		return lista
	var texto: String = FileAccess.get_file_as_string(ruta)
	var crudo: Variant = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[PortalTemporal] JSON inválido en %s" % ruta)
		return lista
	var arr: Array = (crudo as Dictionary).get("destinos", [])
	for d in arr:
		if d is Dictionary:
			lista.append(d)
	return lista


## Portal más cercano a `p` dentro de `radio` (null si ninguno). Puro.
static func portal_cercano(portales: Array, p: Vector3, radio: float = RADIO_USO) -> PortalTemporal:
	var mejor: PortalTemporal = null
	var mejor_d: float = radio
	for q in portales:
		var portal: PortalTemporal = q as PortalTemporal
		if portal == null:
			continue
		var d: float = portal.jugador_distancia(p)
		if d <= mejor_d:
			mejor_d = d
			mejor = portal
	return mejor


## Configura el destino y construye el visual. Llamar antes del add_child
## (o después: si ya está en el árbol, construye de inmediato).
func configurar(d: Dictionary) -> void:
	destino = d
	if is_inside_tree():
		_construir()


func _ready() -> void:
	_construir()


func _process(delta: float) -> void:
	# Giro lento del anillo: se nota que es un portal "vivo"/temporal.
	_t += delta
	if _anillo != null:
		_anillo.rotation.z = _t * 0.6


## Distancia horizontal al jugador (pura, testeable).
func jugador_distancia(p: Vector3) -> float:
	var a: Vector3 = global_position - p
	a.y = 0.0
	return a.length()


## Punto de llegada en el mundo para este destino (sobre el terreno).
func punto_destino(terreno: Terreno) -> Vector3:
	var x: float = float(destino.get("x", 0.0))
	var z: float = float(destino.get("z", 0.0))
	var y: float = MARGEN_SUELO
	if terreno != null:
		y = terreno.altura_en(x, z) + MARGEN_SUELO
	return Vector3(x, y, z)


func _construir() -> void:
	if not destino.is_empty() and _anillo != null:
		return
	if destino.is_empty():
		return
	var nombre: String = str(destino.get("nombre", "?"))
	# Anillo vertical magenta emissive: look "temporal", no contenido final.
	var toro := TorusMesh.new()
	toro.inner_radius = 4.2
	toro.outer_radius = 5.4
	toro.rings = 48
	toro.ring_segments = 10
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.85, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.1, 0.8)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_anillo = MeshInstance3D.new()
	_anillo.mesh = toro
	_anillo.material_override = mat
	_anillo.rotation.x = PI * 0.5
	_anillo.position = Vector3(0, 6.0, 0)
	add_child(_anillo)
	# Disco interior translúcido que gira con el anillo (hijo del anillo).
	var disco := CylinderMesh.new()
	disco.top_radius = 4.0
	disco.bottom_radius = 4.0
	disco.height = 0.2
	disco.radial_segments = 32
	var mat_d := StandardMaterial3D.new()
	mat_d.albedo_color = Color(0.4, 0.1, 0.9, 0.35)
	mat_d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_d.emission_enabled = true
	mat_d.emission = Color(0.5, 0.1, 1.0)
	mat_d.emission_energy_multiplier = 1.2
	mat_d.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dmi := MeshInstance3D.new()
	dmi.mesh = disco
	dmi.material_override = mat_d
	_anillo.add_child(dmi)
	# Base pequeña.
	var base := CylinderMesh.new()
	base.top_radius = 6.2
	base.bottom_radius = 7.0
	base.height = 0.8
	base.radial_segments = 32
	var bmi := MeshInstance3D.new()
	bmi.mesh = base
	var mat_b := StandardMaterial3D.new()
	mat_b.albedo_color = Color(0.2, 0.2, 0.24)
	mat_b.roughness = 0.9
	bmi.material_override = mat_b
	bmi.position = Vector3(0, 0.4, 0)
	add_child(bmi)
	# Nombre del destino arriba, siempre mirando a cámara.
	var etiqueta := Label3D.new()
	etiqueta.text = nombre
	etiqueta.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	etiqueta.font_size = 64
	etiqueta.pixel_size = 0.08
	etiqueta.outline_size = 12
	etiqueta.outline_modulate = Color(0, 0, 0, 1)
	etiqueta.modulate = Color(1, 0.9, 1)
	etiqueta.position = Vector3(0, 14.0, 0)
	add_child(etiqueta)
