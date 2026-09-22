class_name Antorcha
extends Node3D
## Antorcha para la aldea y POIs — Fase 12.
##
## OmniLight3D cálida (naranja 1.0/0.6/0.25) con flicker leve en `_process`
## (senos baratos, sin allocs por frame). Si `ciclo` es null, el brillo es
## fijo (solo parpadeo); con un CicloDia inyectado, la energía escala con
## la oscuridad: `base × (0.3 + 0.7 × oscuridad)` — de día apenas alumbra,
## de noche ilumina de verdad. La demo coloca las instancias; esta clase
## es el componente reutilizable.
##
## NOTA API del motor (lección 12): en Godot 3D la luz puntual se llama
## `OmniLight3D` (`PointLight3D` no existe; es solo 2D).

## Energía base a oscuridad plena (antes del factor día/noche y flicker).
var energia_base: float = 1.8
## Alcance de la luz en metros.
var alcance: float = 9.0
## Ciclo día/noche que modula el brillo; null = brillo fijo.
var ciclo: CicloDia = null

var _luz: OmniLight3D = null
var _t: float = 0.0
var _fase: float = 0.0


func _ready() -> void:
	_luz = OmniLight3D.new()
	_luz.name = "Llama"
	_luz.light_color = Color(1.0, 0.6, 0.25)
	_luz.light_energy = energia_base
	_luz.omni_range = alcance
	_luz.omni_attenuation = 1.2
	_luz.shadow_enabled = false
	add_child(_luz)
	# Fase desincronizada por instancia para que no parpadeen al unísono.
	_fase = float(get_instance_id() % 1000) / 1000.0 * TAU


func _process(delta: float) -> void:
	if _luz == null:
		return
	_t += delta
	# Flicker barato: dos senos, sin allocs (sin Vector/Color por frame).
	var parpadeo: float = 1.0 \
		+ 0.10 * sin(_t * 11.0 + _fase) \
		+ 0.07 * sin(_t * 23.7 + _fase * 1.7)
	_luz.light_energy = energia_base * factor_brillo() * parpadeo


## Factor día/noche: 1.0 si no hay ciclo; 0.3 de día → 1.0 de noche.
func factor_brillo() -> float:
	if ciclo == null:
		return 1.0
	return 0.3 + 0.7 * ciclo.oscuridad()


## Energía objetivo sin flicker (útil para tests y balanceo).
func energia_objetivo() -> float:
	return energia_base * factor_brillo()
