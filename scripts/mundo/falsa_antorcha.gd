class_name FalsaAntorcha
extends Node3D
## Antorcha SIN luz dinamica para las 8 ciudades secundarias (Fase 15).
##
## Cada Antorcha real crea un OmniLight3D: 9 ciudades x ~41 antorchas serian
## ~370 luces puntuales y un problema de rendimiento. Esta variante muestra
## la llama como malla emissive con flicker en `_process` (modula
## emission_energy, sin allocs por frame) y dia/noche via `ciclo`, igual que
## Antorcha. Moon Town conserva sus Antorcha reales (rendia bien).
##
## Uso: igual que Antorcha (la crea CiudadLuna cuando `luces_reales=false`).

## Energia base de la emision a oscuridad plena (antes de dia/noche+flicker).
var energia_base: float = 2.4
## Color de la llama (se fija ANTES del add_child; por defecto calida).
var color_llama: Color = Color(1.0, 0.55, 0.15)
## Ciclo dia/noche que modula el brillo; null = brillo fijo.
var ciclo: CicloDia = null

var _mat_llama: StandardMaterial3D = null
var _t: float = 0.0
var _fase: float = 0.0


func _ready() -> void:
	_mat_llama = StandardMaterial3D.new()
	_mat_llama.albedo_color = color_llama
	_mat_llama.emission_enabled = true
	_mat_llama.emission = color_llama
	_mat_llama.emission_energy_multiplier = energia_base
	# Llama exterior: esfera achatada y alargada.
	var ext := SphereMesh.new()
	ext.radius = 0.9
	ext.height = 1.8
	ext.radial_segments = 10
	ext.rings = 6
	var emi := MeshInstance3D.new()
	emi.name = "LlamaExt"
	emi.mesh = ext
	emi.material_override = _mat_llama
	emi.scale = Vector3(1.0, 1.6, 1.0)
	add_child(emi)
	# Nucleo mas claro y pequeno.
	var mat_nuc := StandardMaterial3D.new()
	mat_nuc.albedo_color = Color(1.0, 0.9, 0.6)
	mat_nuc.emission_enabled = true
	mat_nuc.emission = Color(1.0, 0.85, 0.5)
	mat_nuc.emission_energy_multiplier = energia_base * 1.4
	var nuc := SphereMesh.new()
	nuc.radius = 0.45
	nuc.height = 0.9
	nuc.radial_segments = 8
	nuc.rings = 4
	var nmi := MeshInstance3D.new()
	nmi.name = "LlamaNucleo"
	nmi.mesh = nuc
	nmi.material_override = mat_nuc
	nmi.position = Vector3(0, -0.2, 0)
	add_child(nmi)
	# Fase desincronizada por instancia (no parpadean al unisono).
	_fase = float(get_instance_id() % 1000) / 1000.0 * TAU


func _process(delta: float) -> void:
	if _mat_llama == null:
		return
	_t += delta
	# Mismo flicker barato que Antorcha: dos senos, sin allocs.
	var parpadeo: float = 1.0 \
		+ 0.12 * sin(_t * 11.0 + _fase) \
		+ 0.08 * sin(_t * 23.7 + _fase * 1.7)
	_mat_llama.emission_energy_multiplier = energia_base * factor_brillo() * parpadeo


## Factor dia/noche: 1.0 si no hay ciclo; 0.3 de dia -> 1.0 de noche.
func factor_brillo() -> float:
	if ciclo == null:
		return 1.0
	return 0.3 + 0.7 * ciclo.oscuridad()
