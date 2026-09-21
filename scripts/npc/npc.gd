class_name NPC
extends Entity
## NPC no combatible (fases 5.1–6): se puede seleccionar (indicador) y con
## él se habla (ventana de diálogo, fase 6), pero NUNCA se le puede atacar.
##
## REGLA DURA: `combatible = false`. `Entity.take_damage` ignora el daño,
## `Player` rechaza fijarlo como objetivo de ataque y `SkillSystem`
## rechaza skills dañinas sobre él (motivo "no_combatible").
## Data-driven: `configurar(datos)` recibe la entrada de data/npcs.json
## (via NpcDB): nombre, rol, color y líneas de diálogo.

var nombre_mostrado: String = "NPC"
## Identificador en data/npcs.json (fase 6: para el guardado).
var npc_id: String = ""
var rol: String = ""
var lineas_dialogo: Array[String] = []


func _init(p_stats: StatBlock = null) -> void:
	super._init(p_stats)
	combatible = false


## Aplica una entrada de data/npcs.json. Tolerante: los campos nuevos
## (rol, dialogo) tienen valores por defecto si faltan.
func configurar(datos: Dictionary) -> void:
	npc_id = str(datos.get("id", ""))
	nombre_mostrado = str(datos.get("nombre", "NPC"))
	rol = str(datos.get("rol", ""))
	lineas_dialogo.clear()
	var lineas: Array = datos.get("dialogo", [])
	for l in lineas:
		lineas_dialogo.append(str(l))
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
