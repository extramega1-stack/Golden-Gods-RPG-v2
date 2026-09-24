class_name PanelPersonaje
extends CanvasLayer
## Ventana de personaje estilo FlyFF (fase 30, capa 31).
##
## Muestra nombre/nivel/clase, la tabla de derivados (vida, maná, ataque,
## poder, defensa, crítico, velocidades) y las 4 filas de atributos
## repartibles (STR/fuerza, STA/aguante, DEX/destreza, INT/inteligencia)
## con botón "+" (2 puntos por nivel). Arranca OCULTA; **H** (acción
## `abrir_personaje`) alterna; ESC cierra. La UI solo LEE y gasta vía
## `Player.repartir_atributo()`; se refresca al mostrar, al subir de nivel
## y al cambiar stats/talentos.
## `conectar(jugador)` es re-llamable (carga de partida).

var _jugador: Player = null
var _fondo: PanelContainer = null
var _cabecera: Label = null
var _puntos: Label = null
var _stats: Label = null
var _filas: VBoxContainer = null


func _init() -> void:
	layer = UiLayers.PANEL_PERSONAJE
	_construir_cromo()
	visible = false


func _construir_cromo() -> void:
	_fondo = PanelContainer.new()
	_fondo.set_anchors_preset(Control.PRESET_CENTER)
	_fondo.position = Vector2(-220.0, -230.0)
	_fondo.size = Vector2(440.0, 460.0)
	add_child(_fondo)
	var margen := MarginContainer.new()
	margen.add_theme_constant_override("margin_left", 16)
	margen.add_theme_constant_override("margin_right", 16)
	margen.add_theme_constant_override("margin_top", 12)
	margen.add_theme_constant_override("margin_bottom", 12)
	_fondo.add_child(margen)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	margen.add_child(caja)
	_cabecera = Label.new()
	_cabecera.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cabecera.add_theme_font_size_override("font_size", 20)
	_cabecera.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	caja.add_child(_cabecera)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 13)
	caja.add_child(_stats)
	_puntos = Label.new()
	_puntos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_puntos.add_theme_font_size_override("font_size", 14)
	caja.add_child(_puntos)
	_filas = VBoxContainer.new()
	_filas.add_theme_constant_override("separation", 4)
	caja.add_child(_filas)


## Conecta (o reconecta) al jugador. Re-suscribe sin duplicar.
func conectar(j: Player) -> void:
	if _jugador != null and is_instance_valid(_jugador):
		if _jugador.subio_nivel.is_connected(_reconstruir):
			_jugador.subio_nivel.disconnect(_reconstruir)
	_jugador = j
	if _jugador != null and is_instance_valid(_jugador):
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
	if _cabecera != null:
		_cabecera.text = "%s · Nv %d · %s" % [_jugador.nombre,
			_jugador.nivel, _jugador.clase_id]
	if _stats != null:
		var st: StatBlock = _jugador.stats
		_stats.text = "Vida %d/%d · Maná %d/%d\nAtaque %.0f · Poder %.0f · Defensa %.0f\nCrítico %.0f%% ×%.2f · Vel Atq %.2f · Vel Mov %.1f" % [
			_jugador.vida_actual, st.vida_max, _jugador.mana_actual,
			st.mana_max, st.ataque, st.poder, st.defensa,
			st.crit_prob * 100.0, st.crit_dmg, st.vel_ataque, st.vel_mov]
	if _puntos != null:
		_puntos.text = "Puntos de atributo: %d" % _jugador.puntos_atributo
	for atributo in Player.ATRIBUTOS_REPARTIBLES:
		_filas.add_child(_fila_atributo(atributo))


func _fila_atributo(atributo: String) -> HBoxContainer:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	var etiqueta := Label.new()
	var tag: String = str(Player.ETIQUETA_ATRIBUTO.get(atributo, atributo))
	etiqueta.text = "%s  %d" % [tag, int(float(_jugador.stats.get(atributo)))]
	etiqueta.custom_minimum_size = Vector2(120.0, 0.0)
	etiqueta.add_theme_font_size_override("font_size", 15)
	fila.add_child(etiqueta)
	var que_hace := Label.new()
	que_hace.text = _descripcion_atributo(atributo)
	que_hace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	que_hace.add_theme_font_size_override("font_size", 12)
	que_hace.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
	fila.add_child(que_hace)
	var btn := Button.new()
	btn.text = "+"
	btn.custom_minimum_size = Vector2(44.0, 36.0)
	var puede: bool = _jugador.puntos_atributo > 0
	btn.disabled = not puede
	btn.tooltip_text = "Repartir 1 punto" if puede else "Sin puntos (sube de nivel)"
	btn.pressed.connect(_al_repartir.bind(atributo))
	fila.add_child(btn)
	return fila


static func _descripcion_atributo(atributo: String) -> String:
	match atributo:
		"fuerza":
			return "Daño físico"
		"aguante":
			return "Vida y defensa"
		"destreza":
			return "Crítico y velocidad de ataque"
		"inteligencia":
			return "Maná y poder"
	return ""


func _al_repartir(atributo: String) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	_jugador.repartir_atributo(atributo)
	_reconstruir()


## H alterna el panel.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("abrir_personaje"):
		visible = not visible
		if visible:
			_reconstruir()
		get_viewport().set_input_as_handled()


## ESC cierra (corre antes que el _unhandled_input del Player).
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancelar_seleccion"):
		visible = false
		get_viewport().set_input_as_handled()
