extends Control
## Creación de personaje (fase 11): nombre + clase del héroe.
##
## Pantalla de UI pura (sin 3D): fondo oscuro, LineEdit para el nombre
## (máx. 16 caracteres), tarjetas de clase desde ClaseDB (las no jugables
## salen "Próximamente" y deshabilitadas —activarlas después es solo tocar
## datos—), panel de descripción de la clase elegida y botones
## "Comenzar aventura" / "Atrás". ESC (ui_cancel) = atrás.
##
## Al confirmar: valida el nombre (sin error no avanza), escribe
## `DatosSesion.nueva_partida` y cambia a la escena de juego.

const ESCENA_TITULO: String = "res://scenes/titulo/pantalla_titulo.tscn"
const ESCENA_JUEGO: String = "res://scenes/demo/fase11_demo.tscn"

var _entrada: LineEdit = null
var _error: Label = null
var _desc_nombre: Label = null
var _desc_texto: Label = null
var _desc_stats: Label = null
var _grupo: ButtonGroup = null
var _clase_id: String = "guerrero"


## Valida el nombre del héroe. Retorna "" si es válido o el mensaje de
## error a mostrar. Longitud sensata: 1..16 (tras quitar espacios).
static func validar_nombre(n: String) -> String:
	var limpio: String = n.strip_edges()
	if limpio == "":
		return "El héroe necesita un nombre."
	if limpio.length() > 16:
		return "El nombre es demasiado largo (máx. 16)."
	return ""


func _ready() -> void:
	_construir()
	_actualizar_descripcion(_clase_id)
	_entrada.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_al_atras()


func _construir() -> void:
	var fondo: ColorRect = ColorRect.new()
	fondo.color = Color(0.02, 0.025, 0.045)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)

	var centro: CenterContainer = CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centro)

	var caja: VBoxContainer = VBoxContainer.new()
	caja.custom_minimum_size = Vector2(560, 0)
	caja.add_theme_constant_override("separation", 12)
	caja.alignment = BoxContainer.ALIGNMENT_CENTER
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centro.add_child(caja)

	var titulo: Label = Label.new()
	titulo.text = "Crea tu héroe"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 44)
	titulo.add_theme_color_override("font_color", Color(0.95, 0.76, 0.32))
	titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(titulo)

	var fila_nombre: HBoxContainer = HBoxContainer.new()
	fila_nombre.alignment = BoxContainer.ALIGNMENT_CENTER
	fila_nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(fila_nombre)
	_entrada = LineEdit.new()
	_entrada.placeholder_text = "Nombre del héroe"
	_entrada.max_length = 16
	_entrada.custom_minimum_size = Vector2(420, 46)
	_entrada.add_theme_font_size_override("font_size", 20)
	fila_nombre.add_child(_entrada)

	_error = Label.new()
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.add_theme_font_size_override("font_size", 16)
	_error.add_theme_color_override("font_color", Color(0.95, 0.35, 0.30))
	_error.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_error.visible = false
	caja.add_child(_error)

	var subt: Label = Label.new()
	subt.text = "Elige tu clase"
	subt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subt.add_theme_font_size_override("font_size", 20)
	subt.add_theme_color_override("font_color", Color(0.78, 0.72, 0.60))
	subt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(subt)

	var tarjetas: HBoxContainer = HBoxContainer.new()
	tarjetas.alignment = BoxContainer.ALIGNMENT_CENTER
	tarjetas.add_theme_constant_override("separation", 10)
	tarjetas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(tarjetas)
	_grupo = ButtonGroup.new()
	for cid in ClaseDB.ids():
		tarjetas.add_child(_tarjeta_clase(cid))

	var marco: PanelContainer = PanelContainer.new()
	marco.add_theme_stylebox_override("panel", _estilo(Color(0.06, 0.06, 0.09, 0.95), Color(0.40, 0.32, 0.20)))
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(marco)
	var margen: MarginContainer = MarginContainer.new()
	margen.add_theme_constant_override("margin_left", 16)
	margen.add_theme_constant_override("margin_right", 16)
	margen.add_theme_constant_override("margin_top", 12)
	margen.add_theme_constant_override("margin_bottom", 12)
	margen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.add_child(margen)
	var dcol: VBoxContainer = VBoxContainer.new()
	dcol.add_theme_constant_override("separation", 6)
	dcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margen.add_child(dcol)
	_desc_nombre = _etiqueta("", 24, Color(0.95, 0.76, 0.32))
	dcol.add_child(_desc_nombre)
	_desc_texto = _etiqueta("", 16, Color(0.90, 0.88, 0.84))
	_desc_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_texto.custom_minimum_size = Vector2(500, 66)
	dcol.add_child(_desc_texto)
	_desc_stats = _etiqueta("", 16, Color(0.70, 0.68, 0.62))
	dcol.add_child(_desc_stats)

	var fila: HBoxContainer = HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_CENTER
	fila.add_theme_constant_override("separation", 16)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(fila)
	var b_ok: Button = _boton_accion("Comenzar aventura")
	b_ok.pressed.connect(_al_confirmar)
	fila.add_child(b_ok)
	var b_atras: Button = _boton_accion("Atrás")
	b_atras.pressed.connect(_al_atras)
	fila.add_child(b_atras)


func _etiqueta(texto: String, tam: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _tarjeta_clase(cid: String) -> Button:
	var datos: Dictionary = ClaseDB.obtener(cid)
	var b: Button = Button.new()
	var nombre: String = str(datos.get("nombre", cid))
	if ClaseDB.es_jugable(cid):
		b.text = nombre
	else:
		b.text = "%s\n(Próximamente)" % nombre
		b.disabled = true
	b.toggle_mode = true
	b.button_group = _grupo
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 96)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", Color(0.93, 0.88, 0.74))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.90, 0.55))
	b.add_theme_color_override("font_disabled_color", Color(0.50, 0.48, 0.45))
	b.add_theme_stylebox_override("normal", _estilo(Color(0.08, 0.08, 0.11, 0.95), Color(0.35, 0.33, 0.30)))
	b.add_theme_stylebox_override("hover", _estilo(Color(0.12, 0.11, 0.10, 0.97), Color(0.60, 0.50, 0.30)))
	b.add_theme_stylebox_override("pressed", _estilo(Color(0.14, 0.12, 0.10, 0.98), Color(0.95, 0.76, 0.32)))
	b.add_theme_stylebox_override("disabled", _estilo(Color(0.05, 0.05, 0.07, 0.90), Color(0.22, 0.21, 0.20)))
	b.pressed.connect(_al_elegir_clase.bind(cid))
	if cid == _clase_id:
		b.button_pressed = true
	return b


func _estilo(fondo: Color, borde: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fondo
	sb.border_color = borde
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb


func _boton_accion(texto: String) -> Button:
	var b: Button = Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(240, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(0.93, 0.88, 0.74))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.90, 0.55))
	b.add_theme_stylebox_override("normal", _estilo(Color(0.10, 0.10, 0.14, 0.92), Color(0.55, 0.42, 0.18)))
	b.add_theme_stylebox_override("hover", _estilo(Color(0.16, 0.14, 0.12, 0.95), Color(0.95, 0.76, 0.32)))
	b.add_theme_stylebox_override("pressed", _estilo(Color(0.22, 0.17, 0.10, 0.97), Color(0.95, 0.76, 0.32)))
	return b


func _al_elegir_clase(cid: String) -> void:
	_clase_id = cid
	_actualizar_descripcion(cid)


func _actualizar_descripcion(cid: String) -> void:
	var datos: Dictionary = ClaseDB.obtener(cid)
	_desc_nombre.text = str(datos.get("nombre", cid))
	_desc_texto.text = str(datos.get("descripcion", ""))
	var base: Dictionary = ClaseDB.stats_base(cid)
	_desc_stats.text = "Fuerza %d · Agilidad %d · Destreza %d · Inteligencia %d" % [
		int(base.get("fuerza", 0.0)), int(base.get("agilidad", 0.0)),
		int(base.get("destreza", 0.0)), int(base.get("inteligencia", 0.0))]


func _al_confirmar() -> void:
	var nombre_limpio: String = _entrada.text.strip_edges()
	var err: String = validar_nombre(_entrada.text)
	_error.text = err
	_error.visible = err != ""
	if err != "":
		return
	DatosSesion.nueva_partida(nombre_limpio, _clase_id)
	get_tree().change_scene_to_file(ESCENA_JUEGO)


func _al_atras() -> void:
	get_tree().change_scene_to_file(ESCENA_TITULO)
