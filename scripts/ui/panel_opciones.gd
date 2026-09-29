class_name PanelOpciones
extends CanvasLayer
## Bloque 65: el panel de ajustes.
##
## POR QUÉ ESTÁ CONSTRUIDO ASÍ: los ajustes viven en `Opciones.catalogo()`,
## que es un dato. Este panel RECORRE el catálogo y arma el widget que pide
## cada tipo. Añadir un ajuste es una línea en el JSON de catálogo, no un
## `HSlider.new()` a mano. Esa es la diferencia entre un panel que se puede
## extender y uno que hay que mantener.
##
## - Aplica al instante: cada cambio llama `Opciones.poner()` + `Opciones.aplicar()`,
##   así que el volumen se OYE mientras se arrastra y el FOV se VE.
## - `process_mode = ALWAYS`, porque se abre encima del menú de pausa, que
##   pausa el árbol: sin esto el panel no recibiría ni el ratón.
## - Los cambios NO se guardan solos: hay un botón "Guardar". Un ajuste a medio
##   hacer que se pierda al cerrar sería peor que no tener panel.

const CAPA: int = UiLayers.PANEL_OPCIONES

## §9.1
var system_id: StringName = &"panel_opciones"

var _filas: Dictionary = {}
var _caja: VBoxContainer = null
var _pestanas: TabContainer = null
var _cambios: bool = false


func _init() -> void:
	layer = CAPA
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir()
	visible = false


func _construir() -> void:
	var fondo := PanelContainer.new()
	fondo.set_anchors_preset(Control.PRESET_CENTER)
	fondo.size = Vector2(560.0, 470.0)
	fondo.position = Vector2(-280.0, -235.0)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.add_theme_constant_override("margin_left", 16)
	margen.add_theme_constant_override("margin_right", 16)
	margen.add_theme_constant_override("margin_top", 12)
	margen.add_theme_constant_override("margin_bottom", 12)
	fondo.add_child(margen)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 8)
	margen.add_child(caja)
	_caja = caja

	var titulo := Label.new()
	titulo.text = "Opciones"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 22)
	titulo.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	caja.add_child(titulo)

	_pestanas = TabContainer.new()
	_pestanas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(_pestanas)
	for grupo in ["audio", "video", "camara", "interfaz"]:
		_pestanas.add_child(_pestana_grupo(String(grupo)))

	var botones := HBoxContainer.new()
	botones.add_theme_constant_override("separation", 8)
	caja.add_child(botones)
	var b_defecto := Button.new()
	b_defecto.text = "Restablecer"
	b_defecto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_defecto.pressed.connect(_al_restablecer)
	botones.add_child(b_defecto)
	var b_cerrar := Button.new()
	b_cerrar.text = "Guardar y volver"
	b_cerrar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_cerrar.pressed.connect(_al_cerrar)
	botones.add_child(b_cerrar)


func _nombre_grupo(grupo: String) -> String:
	match grupo:
		"audio":
			return "Audio"
		"video":
			return "Vídeo"
		"camara":
			return "Cámara"
		"interfaz":
			return "Interfaz"
	return grupo.capitalize()


func _pestana_grupo(grupo: String) -> VBoxContainer:
	var caja := VBoxContainer.new()
	caja.name = _nombre_grupo(grupo)
	caja.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(scroll)
	var dentro := VBoxContainer.new()
	dentro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dentro.add_theme_constant_override("separation", 8)
	scroll.add_child(dentro)
	for id in Opciones.grupo(grupo):
		dentro.add_child(_fila(id))
	return caja


## Un widget por tipo de ajuste. Todos escriben por `Opciones.poner()`, que es
## el único que escribe: la UI no toca buses ni viewport directamente.
func _fila(id: String) -> Control:
	var tipo: String = _tipo_de(id)
	var etq := Label.new()
	etq.text = Opciones.etiqueta_de(id)
	etq.custom_minimum_size = Vector2(190.0, 0)
	etq.mouse_filter = Control.MOUSE_FILTER_IGNORE

	match tipo:
		Opciones.TIPO_BOOL:
			var chk := CheckBox.new()
			chk.button_pressed = Opciones.booleano(id)
			chk.toggled.connect(_al_cambiar.bind(id))
			var caja := HBoxContainer.new()
			caja.add_theme_constant_override("separation", 10)
			etq.custom_minimum_size = Vector2(260.0, 0)
			caja.add_child(etq)
			caja.add_child(chk)
			_filas[id] = chk
			return caja
		Opciones.TIPO_ENUM:
			var opt := OptionButton.new()
			for o in _opciones_de(id):
				opt.add_item(str(o))
			opt.selected = clampi(Opciones.entero(id), 0, maxf(0, opt.item_count - 1))
			opt.item_selected.connect(_al_cambiar_enum.bind(id))
			var caja2 := HBoxContainer.new()
			caja2.add_theme_constant_override("separation", 10)
			etq.custom_minimum_size = Vector2(260.0, 0)
			caja2.add_child(etq)
			caja2.add_child(opt)
			_filas[id] = opt
			return caja2
		Opciones.TIPO_VOLUMEN, Opciones.TIPO_SLIDER:
			var sl := HSlider.new()
			sl.min_value = _min_de(id, 0.0)
			sl.max_value = _max_de(id, 100.0)
			sl.step = _paso_de(id, 1.0)
			sl.value = Opciones.flotante(id)
			sl.custom_minimum_size = Vector2(220.0, 24.0)
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sl.value_changed.connect(_al_cambiar_slider.bind(id))
			var valor := Label.new()
			valor.custom_minimum_size = Vector2(74.0, 0)
			valor.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			valor.add_theme_color_override("font_color", Color(0.8, 0.78, 0.7))
			valor.text = _texto_valor(id, sl.value)
			sl.value_changed.connect(func(_v: float): valor.text = _texto_valor(id, sl.value))
			var caja3 := HBoxContainer.new()
			caja3.add_theme_constant_override("separation", 10)
			caja3.add_child(etq)
			caja3.add_child(sl)
			caja3.add_child(valor)
			_filas[id] = {"slider": sl, "valor": valor}
			return caja3
	return etq


## Los dB se muestran como 0-100 porque -60 dB es "-100 %" de oído y el
## jugador no razona en dB. El mínimo es -60, que es silencio de verdad.
func _texto_valor(id: String, v: float) -> String:
	if _tipo_de(id) == Opciones.TIPO_VOLUMEN:
		var pct: int = int(round((v - Opciones.DB_MIN) / (Opciones.DB_MAX - Opciones.DB_MIN) * 100.0))
		return "%d %%" % clampi(pct, 0, 100)
	return ("%.2f" % v) if absf(v) < 1.0 else ("%.0f" % v)


func _al_cambiar(v: bool, id: String) -> void:
	_cambios = true
	Opciones.poner(id, v)
	Opciones.aplicar()


func _al_cambiar_enum(i: int, id: String) -> void:
	_cambios = true
	Opciones.poner(id, i)
	Opciones.aplicar()


func _al_cambiar_slider(v: float, id: String) -> void:
	_cambios = true
	Opciones.poner(id, v)
	Opciones.aplicar()


func _al_restablecer() -> void:
	Opciones.restablecer()
	_refrescar()


func _al_cerrar() -> void:
	if _cambios:
		Opciones.guardar()
	_cambios = false
	visible = false
	# La cámara se entera para el FOV y la distancia sin reabrir nada.
	for n in get_tree().get_nodes_in_group("camera_rig"):
		var cr: Node = n
		if cr.has_method("reponer_opciones"):
			cr.call("reponer_opciones")


func abrir() -> void:
	Opciones.cargar()
	_refrescar()
	_cambios = false
	visible = true


func esta_abierta() -> bool:
	return visible


func _refrescar() -> void:
	for id in _filas.keys():
		var w: Variant = _filas[id]
		if w is CheckBox:
			(w as CheckBox).button_pressed = Opciones.booleano(id)
		elif w is OptionButton:
			var ob: OptionButton = w
			ob.selected = clampi(Opciones.entero(id), 0, maxi(0, ob.item_count - 1))
		elif w is Dictionary:
			var d: Dictionary = w
			var sl: HSlider = d["slider"]
			sl.set_value_no_signal(Opciones.flotante(id))
			var lbl: Label = d["valor"]
			lbl.text = _texto_valor(id, sl.value)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cerrar_menu"):
		_al_cerrar()
		get_viewport().set_input_as_handled()


## --- acceso al catálogo, para no duplicar su forma ---

func _tipo_de(id: String) -> String:
	for a in Opciones.catalogo():
		if str(a["id"]) == id:
			return str(a["tipo"])
	return Opciones.TIPO_SLIDER


func _min_de(id: String, def: float) -> float:
	for a in Opciones.catalogo():
		if str(a["id"]) == id:
			return float(a.get("min", def))
	return def


func _max_de(id: String, def: float) -> float:
	for a in Opciones.catalogo():
		if str(a["id"]) == id:
			return float(a.get("max", def))
	return def


func _paso_de(id: String, def: float) -> float:
	for a in Opciones.catalogo():
		if str(a["id"]) == id:
			return float(a.get("paso", def))
	return def


func _opciones_de(id: String) -> Array:
	for a in Opciones.catalogo():
		if str(a["id"]) == id:
			return a.get("opciones", [])
	return []
