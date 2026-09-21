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
## Fase 9.1 — "!" dorado sobre la cabeza: hay una misión disponible para
## aceptar con este NPC (pedido de Juan Diego). La demo lo refresca con la
## señal `cambiada` del QuestLog: al aceptar el "!" desaparece (ya no está
## disponible); si hay otra misión disponible para ese NPC, sigue visible.
## Solo "disponible": ni entregables ni activas muestran el marcador.
## Fase 9.2 — el marcador se generaliza: el tipo ∈ {NINGUNO, DISPONIBLE "!",
## ENTREGAR "?"}. La "?" dorada (entrega pendiente) tiene prioridad sobre
## el "!" (misión disponible) cuando un NPC tiene ambas a la vez.
enum TipoMarcador { NINGUNO, DISPONIBLE, ENTREGAR }

const ALTURA_MARCADOR: float = 2.35
const COLOR_MARCADOR: Color = Color(1.0, 0.78, 0.15)  ## Dorado.
var _marcador: Label3D = null
## Fase 9.2: tipo actual del marcador (NINGUNO si nunca se fijó).
var _tipo_marcador: int = TipoMarcador.NINGUNO


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


## Fase 9.2 — fija el marcador por tipo ("!" disponible, "?" entrega,
## NINGUNO lo oculta). El Label3D se crea perezoso (oculto al inicio
## —lección 11—) y flota sobre la cabeza con billboard para que siempre
## mire a cámara. Idempotente: cambiar de tipo reusa el mismo Label3D.
func fijar_marcador(tipo: int) -> void:
	if _marcador == null:
		_marcador = Label3D.new()
		_marcador.name = "MarcadorMision"
		_marcador.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_marcador.font_size = 96
		_marcador.modulate = COLOR_MARCADOR
		_marcador.outline_size = 12
		_marcador.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
		_marcador.no_depth_test = true
		_marcador.position = Vector3(0.0, ALTURA_MARCADOR, 0.0)
		_marcador.visible = false
		add_child(_marcador)
	match tipo:
		TipoMarcador.ENTREGAR:
			_marcador.text = "?"
		TipoMarcador.DISPONIBLE:
			_marcador.text = "!"
		_:
			tipo = TipoMarcador.NINGUNO
	_marcador.visible = tipo != TipoMarcador.NINGUNO
	_tipo_marcador = tipo


## Compatibilidad con la fase 9.1: true muestra el "!" de misión
## disponible, false lo oculta.
func fijar_marcador_mision(mostrar: bool) -> void:
	fijar_marcador(TipoMarcador.DISPONIBLE if mostrar else TipoMarcador.NINGUNO)


## Compatibilidad: true muestra la "?" de entrega pendiente, false la
## oculta.
func fijar_marcador_entrega(mostrar: bool) -> void:
	fijar_marcador(TipoMarcador.ENTREGAR if mostrar else TipoMarcador.NINGUNO)


## ¿El marcador de misión está visible ahora? (tests + UI futura).
func marcador_visible() -> bool:
	return _marcador != null and _marcador.visible


## Tipo actual del marcador (NINGUNO/DISPONIBLE/ENTREGAR). (tests + UI).
func marcador_tipo() -> int:
	return _tipo_marcador


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
