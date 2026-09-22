class_name PanelViaje
extends CanvasLayer
## Panel de viaje rápido de la fase 16 (capa `UiLayers.PANEL_VIAJE` = 29,
## rango 20–69 = paneles de sistemas).
##
## Arranca OCULTO (`visible = false`; lección 11) y no se come clics
## inactivo. Al abrirse: velo modal fullscreen con MOUSE_FILTER_STOP (como
## VentanaDialogo/PanelTienda); ESC cierra (consumido en `_input` antes
## que el Player).
##
## Lista los 8 destinos desde la ciudad del portero (nombre, costo en oro
## y nivel mínimo). Los no alcanzables se muestran atenuados con el motivo
## ("Te faltan X de oro", "Requiere nivel N"); cada fila tiene su botón
## "Viajar" (deshabilitado si está bloqueada).
##
## REGLA: la UI SOLO LEE. Todas las mutaciones pasan por
## `ViajeRapido.viajar()` (la demo). Se reconstruye al abrirse y cuando
## cambia el oro del jugador.

signal viaje_solicitado(destino_id: String)
signal viaje_cerrado

var _viaje: ViajeRapido = null
var _jugador: Player = null
var _origen_id: String = ""

var _titulo: Label = null
var _oro: Label = null
var _lista: VBoxContainer = null
var _estado: Label = null
## Última info calculada por mostrar() (solo lectura; tests).
var _info_actual: Array = []


func _ready() -> void:
	layer = UiLayers.PANEL_VIAJE
	_construir()
	# Lección 11: oculto desde el arranque.
	visible = false


func _construir() -> void:
	var velo: ColorRect = ColorRect.new()
	velo.name = "Velo"
	velo.color = Color(0.0, 0.0, 0.0, 0.55)
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	velo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(velo)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(520, 480)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(0.07, 0.07, 0.1, 0.97)
	estilo.border_color = Color(0.55, 0.7, 1.0)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", estilo)
	add_child(panel)

	var caja: VBoxContainer = VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(caja)

	_titulo = Label.new()
	_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_titulo.add_theme_color_override("font_color", Color(0.65, 0.78, 1.0))
	_titulo.add_theme_font_size_override("font_size", 22)
	caja.add_child(_titulo)

	_oro = Label.new()
	_oro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_oro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_oro.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	_oro.add_theme_font_size_override("font_size", 17)
	caja.add_child(_oro)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 300)
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	caja.add_child(scroll)
	_lista = VBoxContainer.new()
	_lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lista.add_theme_constant_override("separation", 4)
	scroll.add_child(_lista)

	_estado = Label.new()
	_estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_estado.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_estado.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	_estado.add_theme_font_size_override("font_size", 14)
	caja.add_child(_estado)

	var fila: HBoxContainer = HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_END
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(fila)
	var cerrar: Button = Button.new()
	cerrar.text = "Cerrar  (ESC)"
	cerrar.focus_mode = Control.FOCUS_NONE
	cerrar.mouse_filter = Control.MOUSE_FILTER_STOP
	cerrar.pressed.connect(cerrar_panel)
	fila.add_child(cerrar)


## Conecta el panel al jugador; re-llamar reconecta (como PanelTienda).
func conectar(j: Player) -> void:
	if _jugador != null and _jugador.oro_cambiado.is_connected(_al_oro):
		_jugador.oro_cambiado.disconnect(_al_oro)
	_jugador = j
	if _jugador != null:
		_jugador.oro_cambiado.connect(_al_oro)
	if esta_abierta():
		_reconstruir()


## Lógica del panel SIN nodos (tests): una entrada por destino con
## {destino_id, nombre, costo_oro, nivel_min, ok, motivo, motivo_texto}.
func info_filas(origen_id: String, jugador: Player) -> Array:
	var v: ViajeRapido = _viaje_asegurado()
	var resultado: Array = []
	for d in v.destinos_desde(origen_id):
		var dd: Dictionary = d
		var ev: Dictionary = v.evaluar(jugador, origen_id, str(dd.get("destino_id", "")))
		resultado.append({
			"destino_id": str(dd.get("destino_id", "")),
			"nombre": str(dd.get("nombre", "")),
			"costo_oro": int(dd.get("costo_oro", 0)),
			"nivel_min": int(dd.get("nivel_min", 1)),
			"ok": bool(ev.get("ok", false)),
			"motivo": str(ev.get("motivo", "")),
			"motivo_texto": ViajeRapido.texto_motivo(ev),
		})
	return resultado


## Abre el panel para viajar desde la ciudad del portero. Sin datos o sin
## jugador no hace nada (no revienta).
func mostrar(origen_id: String, jugador: Player) -> void:
	if origen_id == "" or jugador == null:
		return
	var v: ViajeRapido = _viaje_asegurado()
	if v.destinos_desde(origen_id).is_empty():
		return
	_origen_id = origen_id
	conectar(jugador)
	_info_actual = info_filas(_origen_id, _jugador)
	_reconstruir()
	visible = true


func cerrar_panel() -> void:
	if not esta_abierta():
		return
	visible = false
	viaje_cerrado.emit()


func esta_abierta() -> bool:
	return visible


## Ciudad origen mostrada ("" si nunca se abrió).
func origen_actual() -> String:
	return _origen_id


## Info calculada por el último mostrar() ("" si nunca se abrió).
func info_actual() -> Array:
	return _info_actual


## Mensaje de estado (para fallos al aceptar un destino); solo lectura.
func informar(texto: String) -> void:
	_estado.text = texto


func _al_oro(_oro_actual: int) -> void:
	if esta_abierta():
		_reconstruir()


func _reconstruir() -> void:
	if _jugador == null or _origen_id == "":
		return
	_titulo.text = "Viaje rápido — desde %s" % _viaje_asegurado().nombre_ciudad(_origen_id)
	_oro.text = "Oro: %d" % _jugador.oro
	_info_actual = info_filas(_origen_id, _jugador)
	for h in _lista.get_children():
		h.queue_free()
	for info in _info_actual:
		_lista.add_child(_fila_destino(info))


func _fila_destino(info: Dictionary) -> HBoxContainer:
	var fila: HBoxContainer = HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lab: Label = Label.new()
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# TEMPORAL: con GRATIS_TEMPORAL el costo es 0 y se muestra "Gratis".
	var costo_mostrar: int = int(info.get("costo_oro", 0))
	var texto_costo: String = "Gratis" if costo_mostrar <= 0 else "%d oro" % costo_mostrar
	lab.text = "%s — %s · Nv. %d" % [
		str(info.get("nombre", "")), texto_costo,
		int(info.get("nivel_min", 1))]
	fila.add_child(lab)
	var bloqueado: bool = not bool(info.get("ok", false))
	if bloqueado:
		# Atenuada con el motivo (fase 16).
		fila.modulate = Color(1.0, 1.0, 1.0, 0.45)
		var mot: Label = Label.new()
		mot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mot.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
		mot.add_theme_font_size_override("font_size", 13)
		mot.text = str(info.get("motivo_texto", ""))
		fila.add_child(mot)
	var boton: Button = Button.new()
	boton.text = "Viajar"
	boton.focus_mode = Control.FOCUS_NONE
	boton.mouse_filter = Control.MOUSE_FILTER_STOP
	boton.disabled = bloqueado
	if not bloqueado:
		boton.pressed.connect(_al_viajar.bind(str(info.get("destino_id", ""))))
	fila.add_child(boton)
	return fila


## La UI solo lee: el viaje real lo ejecuta la demo con ViajeRapido.
func _al_viajar(destino_id: String) -> void:
	if not esta_abierta() or destino_id == "":
		return
	viaje_solicitado.emit(destino_id)


func _viaje_asegurado() -> ViajeRapido:
	if _viaje == null:
		_viaje = ViajeRapido.new()
		_viaje.cargar_datos()
	return _viaje


## _input corre antes que el _unhandled_input del Player: el panel
## consume ESC (cerrar) antes de que llegue al juego.
func _input(event: InputEvent) -> void:
	if not esta_abierta():
		return
	if event.is_action_pressed("cancelar_seleccion"):
		cerrar_panel()
		get_viewport().set_input_as_handled()
