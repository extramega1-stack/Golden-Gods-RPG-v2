class_name SkillFX
extends Node
## Gancho visual del feedback de skills (fase 18): tiñe el nodo "Cuerpo"
## de la entidad dueña con `Entity.fx_color` mientras
## `Entity.intensidad_fx() > 0`. Hermano de DamageFlash (mismo patrón:
## solo LEE el estado; la lógica del temporizador vive en Entity y es
## testeable sin 3D). No muta recursos compartidos: duplica el material
## activo y lo restaura al terminar.
## Se adjunta como hijo de Player/Enemy en las escenas demo.

var _dueno: Entity = null
var _cuerpo: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _base: Color = Color.WHITE
var _override_original: Material = null


func _ready() -> void:
	_dueno = get_parent() as Entity
	if _dueno == null:
		push_warning("[SkillFX] el padre no es Entity; me desactivo")
		set_process(false)
		return
	_cuerpo = _dueno.get_node_or_null("Cuerpo") as MeshInstance3D
	if _cuerpo == null:
		push_warning("[SkillFX] '%s' no tiene nodo 'Cuerpo'" % _dueno.name)
		set_process(false)


func _process(_delta: float) -> void:
	if _dueno == null or _cuerpo == null:
		return
	var inten: float = _dueno.intensidad_fx()
	if inten <= 0.0:
		_restaurar()
		return
	_asegurar_material()
	if _mat != null:
		_mat.albedo_color = _base.lerp(_dueno.fx_color, inten)


## Duplica el material activo (override > surface override > malla) y lo
## instala como override propio. Recaptura si algo externo lo reemplazó.
func _asegurar_material() -> void:
	if _mat != null and _cuerpo.material_override == _mat:
		return
	_override_original = _cuerpo.material_override
	var actual: Material = _cuerpo.get_active_material(0)
	if actual is StandardMaterial3D:
		_mat = (actual as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		_mat = StandardMaterial3D.new()
		_mat.roughness = 0.7
	_base = _mat.albedo_color
	_cuerpo.material_override = _mat


## Quita el override propio y devuelve el original.
func _restaurar() -> void:
	if _mat == null:
		return
	if _cuerpo.material_override == _mat:
		_cuerpo.material_override = _override_original
	_mat = null
	_override_original = null
