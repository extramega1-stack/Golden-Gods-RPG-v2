class_name NPC
extends Entity
## NPC no combatible de la fase 5.1: se puede seleccionar (indicador) y
## con él se hablará en fases futuras, pero NUNCA se le puede atacar.
##
## REGLA DURA: `combatible = false`. `Entity.take_damage` ignora el daño,
## `Player` rechaza fijarlo como objetivo de ataque y `SkillSystem`
## rechaza skills dañinas sobre él (motivo "no_combatible").
## Data-driven: `configurar(datos)` recibe el diccionario de data/npcs.json.

var nombre_mostrado: String = "NPC"


func _init(p_stats: StatBlock = null) -> void:
	super._init(p_stats)
	combatible = false


## Aplica una entrada de data/npcs.json (nombre + tinte del cuerpo).
func configurar(datos: Dictionary) -> void:
	nombre_mostrado = str(datos.get("nombre", "NPC"))
	_tintar(datos.get("color", [0.35, 0.55, 0.95]))


## Color del cuerpo (material propio por instancia, igual que Enemy).
func _tintar(c: Variant) -> void:
	var cuerpo: MeshInstance3D = get_node_or_null("Cuerpo") as MeshInstance3D
	if cuerpo == null:
		return
	var col: Array = c
	var r: float = float(col[0]) if col.size() > 0 else 0.35
	var g: float = float(col[1]) if col.size() > 1 else 0.55
	var b: float = float(col[2]) if col.size() > 2 else 0.95
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(r, g, b)
	mat.roughness = 0.7
	cuerpo.material_override = mat
