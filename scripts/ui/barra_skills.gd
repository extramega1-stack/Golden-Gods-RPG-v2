class_name BarraSkills
extends CanvasLayer
## Hotbar de skills de la fase 5: 5 casillas abajo-centro con overlay de
## cooldown. Solo LEE el SkillSystem del jugador (señales + cooldowns).
## Todos los controles llevan mouse_filter IGNORE: no se come ni un clic
## del juego (lección 11 de AGENTS.md).

var _skills: SkillSystem = null
var _ids: Array[String] = []
var _overlays: Array[Label] = []


func _ready() -> void:
	layer = UiLayers.BARRA_SKILLS
	_construir()


func _construir() -> void:
	_ids = SkillDB.lista()
	var barra: HBoxContainer = HBoxContainer.new()
	barra.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	barra.grow_horizontal = Control.GROW_DIRECTION_BOTH
	barra.grow_vertical = Control.GROW_DIRECTION_BEGIN
	barra.offset_top = -100.0
	barra.offset_bottom = -24.0
	barra.add_theme_constant_override("separation", 8)
	barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(barra)
	for i in range(_ids.size()):
		barra.add_child(_nueva_casilla(i, _ids[i]))


func _nueva_casilla(i: int, skill_id: String) -> Control:
	var sk: Dictionary = SkillDB.obtener(skill_id)
	var nombre: String = str(sk.get("nombre", skill_id))
	var partes: PackedStringArray = nombre.split(" ")
	var corto: String = str(partes[0]) if partes.size() > 0 else skill_id
	var marco: Control = Control.new()
	marco.custom_minimum_size = Vector2(88, 68)
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fondo: PanelContainer = PanelContainer.new()
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(0.06, 0.06, 0.09, 0.85)
	estilo.border_color = Color(0.75, 0.62, 0.3)
	estilo.set_border_width_all(2)
	fondo.add_theme_stylebox_override("panel", estilo)
	marco.add_child(fondo)
	var caja: VBoxContainer = VBoxContainer.new()
	caja.set_anchors_preset(Control.PRESET_FULL_RECT)
	caja.alignment = BoxContainer.ALIGNMENT_CENTER
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_theme_constant_override("separation", 0)
	fondo.add_child(caja)
	var tecla: Label = _etiqueta("[%d]" % [i + 1], 13, Color(0.7, 0.65, 0.55))
	tecla.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(tecla)
	var nom: Label = _etiqueta(corto, 15, Color(0.95, 0.9, 0.75))
	nom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(nom)
	# Overlay de cooldown: velo oscuro con los segundos restantes.
	var overlay: Label = _etiqueta("", 22, Color(1, 1, 1))
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.visible = false
	var velo: StyleBoxFlat = StyleBoxFlat.new()
	velo.bg_color = Color(0.02, 0.02, 0.05, 0.78)
	overlay.add_theme_stylebox_override("normal", velo)
	marco.add_child(overlay)
	_overlays.append(overlay)
	return marco


func _etiqueta(texto: String, tam: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = texto
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", tam)
	return l


## Conecta la barra al jugador (solo lectura: guarda su SkillSystem y
## escucha skill_usada para refrescar al instante).
func conectar(j: Player) -> void:
	if j == null:
		return
	_skills = j.skills
	if _skills != null and not _skills.skill_usada.is_connected(_al_skill_usada):
		_skills.skill_usada.connect(_al_skill_usada)
	_actualizar()


func _al_skill_usada(_skill_id: String) -> void:
	_actualizar()


func _process(_delta: float) -> void:
	_actualizar()


func _actualizar() -> void:
	if _skills == null:
		return
	for i in range(_ids.size()):
		if i >= _overlays.size():
			continue
		var rest: float = _skills.cooldown_restante(_ids[i])
		var total: float = float(SkillDB.obtener(_ids[i]).get("cooldown", 0.0))
		var ov: Label = _overlays[i]
		if rest > 0.0 and total > 0.0:
			ov.visible = true
			ov.text = "%.1f" % rest
		else:
			ov.visible = false
			ov.text = ""
