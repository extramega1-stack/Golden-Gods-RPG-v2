class_name PanelTalentos
extends CanvasLayer
## Panel de talentos de la fase 28 (capa `UiLayers.PANEL_TALENTOS` = 30).
##
## Arranca OCULTO y no se come clics inactivo. La tecla **K** (acción
## `abrir_talentos`) alterna; ESC cierra (consumido en `_input` antes que
## el Player). La UI solo LEE: gasta puntos vía `Talentos.subir()` y se
## refresca con su señal `cambiada` (+ `subio_nivel` del jugador).
## `conectar(jugador)` es re-llamable (carga de partida): re-suscribe.

var _jugador: Player = null
var _fondo: PanelContainer = null
var _puntos: Label = null
var _filas: VBoxContainer = null


func _init() -> void:
	layer = UiLayers.PANEL_TALENTOS
	_construir_cromo()
	visible = false


func _construir_cromo() -> void:
	_fondo = PanelContainer.new()
	_fondo.set_anchors_preset(Control.PRESET_CENTER)
	_fondo.position = Vector2(-220.0, -190.0)
	_fondo.size = Vector2(440.0, 380.0)
	add_child(_fondo)
	var margen := MarginContainer.new()
	margen.add_theme_constant_override("margin_left", 16)
	margen.add_theme_constant_override("margin_right", 16)
	margen.add_theme_constant_override("margin_top", 12)
	margen.add_theme_constant_override("margin_bottom", 12)
	_fondo.add_child(margen)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 8)
	margen.add_child(caja)
	var titulo := Label.new()
	titulo.text = "Talentos (K)"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 20)
	titulo.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	caja.add_child(titulo)
	_puntos = Label.new()
	_puntos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_puntos.add_theme_font_size_override("font_size", 14)
	caja.add_child(_puntos)
	_filas = VBoxContainer.new()
	_filas.add_theme_constant_override("separation", 6)
	caja.add_child(_filas)


## Conecta (o reconecta) al jugador. Re-suscribe sin duplicar.
func conectar(j: Player) -> void:
	if _jugador != null and is_instance_valid(_jugador):
		if _jugador.talentos != null \
				and _jugador.talentos.cambiada.is_connected(_reconstruir):
			_jugador.talentos.cambiada.disconnect(_reconstruir)
		if _jugador.subio_nivel.is_connected(_reconstruir):
			_jugador.subio_nivel.disconnect(_reconstruir)
	_jugador = j
	if _jugador != null and is_instance_valid(_jugador):
		if _jugador.talentos != null \
				and not _jugador.talentos.cambiada.is_connected(_reconstruir):
			_jugador.talentos.cambiada.connect(_reconstruir)
		if not _jugador.subio_nivel.is_connected(_reconstruir):
			_jugador.subio_nivel.connect(_reconstruir)
	_reconstruir()


func _reconstruir(_arg = null) -> void:
	if _filas == null:
		return
	for h in _filas.get_children():
		h.queue_free()
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var tal: Talentos = _jugador.talentos
	if tal == null:
		return
	if _puntos != null:
		_puntos.text = "Nv %d · Puntos: %d" % [_jugador.nivel, tal.puntos]
	for tid in TalentoDB.talentos_por_clase(_jugador.clase_id):
		_filas.add_child(_fila_talento(tid, tal))


func _fila_talento(tid: String, tal: Talentos) -> HBoxContainer:
	var datos: Dictionary = TalentoDB.obtener(tid)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	var textos := VBoxContainer.new()
	textos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(textos)
	var nombre := Label.new()
	var r: int = tal.rango_de(tid)
	var mx: int = maxi(1, int(datos.get("max_rango", 3)))
	nombre.text = "%s  %s" % [str(datos.get("nombre", tid)), _pips(r, mx)]
	nombre.add_theme_font_size_override("font_size", 15)
	textos.add_child(nombre)
	var desc := Label.new()
	desc.text = "%s (Nv %d)" % [str(datos.get("descripcion", "")),
		int(datos.get("requiere_nivel", 1))]
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	textos.add_child(desc)
	var btn := Button.new()
	btn.text = "+"
	btn.custom_minimum_size = Vector2(44.0, 44.0)
	var motivo: String = tal.puede_subir(tid, _jugador.nivel, _jugador.clase_id)
	btn.disabled = motivo != "ok"
	btn.tooltip_text = "Subir rango" if motivo == "ok" else _texto_motivo(motivo)
	btn.pressed.connect(_al_subir.bind(tid))
	fila.add_child(btn)
	return fila


static func _pips(r: int, mx: int) -> String:
	var s: String = ""
	for i in range(mx):
		s += "●" if i < r else "○"
	return s


static func _texto_motivo(motivo: String) -> String:
	match motivo:
		"sin_puntos":
			return "Sin puntos (sube de nivel)"
		"max_rango":
			return "Rango máximo"
		"nivel":
			return "Nivel insuficiente"
		"clase":
			return "De otra clase"
	return motivo


func _al_subir(tid: String) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	if _jugador.talentos == null:
		return
	_jugador.talentos.subir(tid, _jugador.stats, _jugador.nivel,
		_jugador.clase_id)


## K alterna el panel.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("abrir_talentos"):
		visible = not visible
		if visible:
			_reconstruir()
		get_viewport().set_input_as_handled()


## ESC cierra (corre antes que el _unhandled_input del Player).
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancelar_seleccion"):
		visible = false
		get_viewport().set_input_as_handled()
