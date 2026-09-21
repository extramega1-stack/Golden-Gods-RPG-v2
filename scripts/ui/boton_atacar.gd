class_name BotonAtacar
extends CanvasLayer
## Botón de atacar de la fase 5.1: ejecuta la intención de ataque sobre el
## foco del jugador. Emite `ataque_solicitado`; la demo lo conecta a
## `Player.solicitar_ataque`.
##
## REGLA DURA (directriz de Juan Diego): la UI nunca escribe stats ni llama
## a take_damage: solo emite la intención y el Player la consume.
##
## - Clic izquierdo = atacar. Arrastrar con izquierdo = mover el botón
##   (la posición persiste en `ruta_config` vía ConfigFile).
## - Clic derecho = modo rebind ("pulsa una tecla…", ESC cancela):
##   reescribe la acción "atacar" del InputMap en runtime, persiste la
##   tecla y se aplica al arrancar (vía `cargar_config()`).
## - Todo por Input Map: ninguna tecla hardcodeada en el código.
## - Solo el botón lleva mouse_filter STOP; el resto es IGNORE (lección 11).

signal ataque_solicitado

## Ruta del ConfigFile. Inyectable en tests para no tocar el user:// real.
var ruta_config: String = "user://boton_atacar.cfg"

const ACCION: String = "atacar"
const TECLA_DEFECTO: int = 84 ## T (de aTacar); física, reasignable.
const UMBRAL_ARRASTRE: float = 8.0

var _boton: Button = null
var _etiqueta_rebind: Label = null
var _tecla_actual: int = TECLA_DEFECTO

var _pulsado: bool = false
var _movio: bool = false
var _acum: Vector2 = Vector2.ZERO
var _en_rebind: bool = false


func _ready() -> void:
	layer = UiLayers.BOTON_ATACAR
	_construir()
	cargar_config()
	_refrescar_texto()


func _construir() -> void:
	_boton = Button.new()
	_boton.custom_minimum_size = Vector2(132, 64)
	_boton.mouse_filter = Control.MOUSE_FILTER_STOP
	_boton.focus_mode = Control.FOCUS_NONE
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(0.28, 0.05, 0.06, 0.92)
	estilo.border_color = Color(0.75, 0.62, 0.3)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(6)
	_boton.add_theme_stylebox_override("normal", estilo)
	var estilo_hover: StyleBoxFlat = estilo.duplicate() as StyleBoxFlat
	estilo_hover.bg_color = Color(0.42, 0.09, 0.08, 0.95)
	_boton.add_theme_stylebox_override("hover", estilo_hover)
	var estilo_press: StyleBoxFlat = estilo.duplicate() as StyleBoxFlat
	estilo_press.bg_color = Color(0.55, 0.14, 0.1, 0.98)
	_boton.add_theme_stylebox_override("pressed", estilo_press)
	_boton.add_theme_color_override("font_color", Color(0.98, 0.9, 0.72))
	_boton.add_theme_font_size_override("font_size", 18)
	_boton.gui_input.connect(_al_gui_input)
	# Posición por defecto: abajo-derecha (la real se carga del ConfigFile).
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_boton.position = vp - Vector2(148, 96)
	add_child(_boton)

	_etiqueta_rebind = Label.new()
	_etiqueta_rebind.text = "Pulsa una tecla… (ESC cancela)"
	_etiqueta_rebind.set_anchors_preset(Control.PRESET_CENTER)
	_etiqueta_rebind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_etiqueta_rebind.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_etiqueta_rebind.add_theme_font_size_override("font_size", 22)
	_etiqueta_rebind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_etiqueta_rebind.visible = false
	add_child(_etiqueta_rebind)


func _refrescar_texto() -> void:
	if _boton == null:
		return
	_boton.text = "ATACAR [%s]\n(clic der.: tecla)" % _nombre_tecla(_tecla_actual)


func _nombre_tecla(fisica: int) -> String:
	# physical_keycode comparte constantes con keycode para letras y
	# teclas especiales (KEY_T = 84, KEY_ESCAPE = 4194305…).
	return OS.get_keycode_string(fisica)


## Aplica la tecla a la acción "atacar" (runtime) y la persiste.
func aplicar_tecla(fisica: int) -> void:
	if fisica <= 0:
		return
	_aplicar_runtime(fisica)
	guardar_config()


func _aplicar_runtime(fisica: int) -> void:
	if not InputMap.has_action(ACCION):
		InputMap.add_action(ACCION)
	InputMap.action_erase_events(ACCION)
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = fisica
	InputMap.action_add_event(ACCION, ev)
	_tecla_actual = fisica
	_refrescar_texto()


## La tecla actualmente asignada (tests + UI futura).
func tecla_actual() -> int:
	return _tecla_actual


func guardar_config() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("boton", "pos_x", _boton.position.x)
	cfg.set_value("boton", "pos_y", _boton.position.y)
	cfg.set_value("ataque", "tecla", _tecla_actual)
	cfg.save(ruta_config)


func cargar_config() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(ruta_config) != OK:
		return
	var px: float = float(cfg.get_value("boton", "pos_x", _boton.position.x))
	var py: float = float(cfg.get_value("boton", "pos_y", _boton.position.y))
	_boton.position = _fijar_a_viewport(Vector2(px, py))
	var t: int = int(cfg.get_value("ataque", "tecla", _tecla_actual))
	if t > 0:
		_aplicar_runtime(t)


func _fijar_a_viewport(p: Vector2) -> Vector2:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var tam: Vector2 = _boton.size
	if tam.x <= 0.0:
		tam = _boton.custom_minimum_size
	if vp.x <= tam.x or vp.y <= tam.y:
		# Viewport degenerado (p. ej. tests headless): no fijar.
		return p
	return Vector2(
		clampf(p.x, 0.0, maxf(vp.x - tam.x, 0.0)),
		clampf(p.y, 0.0, maxf(vp.y - tam.y, 0.0)))


func _al_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pulsado = true
				_movio = false
				_acum = Vector2.ZERO
			else:
				if _pulsado and not _movio and not _en_rebind:
					ataque_solicitado.emit()
					guardar_config()
				_pulsado = false
				_movio = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_entrar_rebind()
	elif event is InputEventMouseMotion and _pulsado:
		var mm: InputEventMouseMotion = event
		_acum += mm.relative
		if _acum.length() >= UMBRAL_ARRASTRE:
			_movio = true
			_boton.position = _fijar_a_viewport(_boton.position + mm.relative)


func _entrar_rebind() -> void:
	_en_rebind = true
	_pulsado = false
	_movio = false
	_etiqueta_rebind.visible = true


func _salir_rebind() -> void:
	_en_rebind = false
	_etiqueta_rebind.visible = false


## En modo rebind se traga las teclas antes de que lleguen al juego
## (_input corre antes que la GUI y que _unhandled_input).
func _input(event: InputEvent) -> void:
	if not _en_rebind:
		return
	if event is InputEventKey:
		var k: InputEventKey = event
		if not k.pressed or k.echo:
			return
		var fisica: int = int(k.physical_keycode)
		if fisica == 0:
			fisica = int(k.keycode)
		if fisica == int(KEY_ESCAPE):
			_salir_rebind()
		else:
			aplicar_tecla(fisica)
			_salir_rebind()
		get_viewport().set_input_as_handled()
