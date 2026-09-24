class_name PanelHabilidades
extends CanvasLayer
## Panel de habilidades estilo FlyFF (fase 31, capa `UiLayers.PANEL_HABILIDADES`
## = 30, ex-talentos). Dos pestañas:
## - "Skills": las 8 de la clase actual, mejorables de Nv 1 a 20 con
##   `SkillSystem.puntos_skill` (2 por nivel del jugador).
## - "Talentos": migración del PanelTalentos de la fase 28 (3 × 4 clases,
##   3 rangos, 1 punto por nivel).
##
## La tecla **K** (acción `abrir_habilidades`) alterna; ESC cierra (consumido
## en `_input` antes que el Player). Arranca OCULTO y no se come clics
## inactivo (lección 11 de AGENTS.md). La UI solo LEE: gasta puntos vía
## `SkillSystem.subir_nivel()` / `Talentos.subir()` y se refresca al abrir,
## al subir de nivel y tras cada clic.
## `conectar(jugador)` es re-llamable (carga de partida): re-suscribe.

var _jugador: Player = null
var _puntos_skill: Label = null
var _filas_skills: VBoxContainer = null
var _puntos_tal: Label = null
var _filas_talentos: VBoxContainer = null


func _init() -> void:
	layer = UiLayers.PANEL_HABILIDADES
	_construir_cromo()
	visible = false


func _construir_cromo() -> void:
	var fondo := PanelContainer.new()
	fondo.set_anchors_preset(Control.PRESET_CENTER)
	fondo.position = Vector2(-260.0, -230.0)
	fondo.size = Vector2(520.0, 460.0)
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
	var titulo := Label.new()
	titulo.text = "Habilidades (K)"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 20)
	titulo.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	caja.add_child(titulo)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(tabs)
	tabs.add_child(_pestana_skills())
	tabs.add_child(_pestana_talentos())


func _pestana_skills() -> VBoxContainer:
	var caja := VBoxContainer.new()
	caja.name = "Skills"
	caja.add_theme_constant_override("separation", 6)
	_puntos_skill = Label.new()
	_puntos_skill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_puntos_skill.add_theme_font_size_override("font_size", 14)
	caja.add_child(_puntos_skill)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(scroll)
	_filas_skills = VBoxContainer.new()
	_filas_skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filas_skills.add_theme_constant_override("separation", 6)
	scroll.add_child(_filas_skills)
	return caja


func _pestana_talentos() -> VBoxContainer:
	var caja := VBoxContainer.new()
	caja.name = "Talentos"
	caja.add_theme_constant_override("separation", 6)
	_puntos_tal = Label.new()
	_puntos_tal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_puntos_tal.add_theme_font_size_override("font_size", 14)
	caja.add_child(_puntos_tal)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(scroll)
	_filas_talentos = VBoxContainer.new()
	_filas_talentos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filas_talentos.add_theme_constant_override("separation", 6)
	scroll.add_child(_filas_talentos)
	return caja


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
	_reconstruir_skills()
	_reconstruir_talentos()


# ---------------------------------------------------------------- skills ---

func _reconstruir_skills() -> void:
	if _filas_skills == null:
		return
	for h in _filas_skills.get_children():
		h.queue_free()
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var sys: SkillSystem = _jugador.skills
	if sys == null:
		return
	if _puntos_skill != null:
		_puntos_skill.text = "Nv %d · Puntos de skill: %d" % [_jugador.nivel, sys.puntos_skill]
	for sid in SkillDB.skills_por_clase(_jugador.clase_id):
		_filas_skills.add_child(_fila_skill(sid, sys))


func _fila_skill(sid: String, sys: SkillSystem) -> HBoxContainer:
	var datos: Dictionary = SkillDB.obtener(sid)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	var textos := VBoxContainer.new()
	textos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(textos)
	var nivel: int = sys.nivel_de(sid)
	var mx: int = maxi(1, int(datos.get("max_nivel", 20)))
	var nombre := Label.new()
	nombre.text = "%s   Nv %d/%d" % [str(datos.get("nombre", sid)), nivel, mx]
	nombre.add_theme_font_size_override("font_size", 15)
	textos.add_child(nombre)
	var nums := Label.new()
	nums.text = "%s · %s" % [str(datos.get("descripcion", "")), _numeros_skill(sid, sys)]
	nums.add_theme_font_size_override("font_size", 12)
	nums.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
	nums.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	textos.add_child(nums)
	var btn := Button.new()
	btn.text = "+"
	btn.custom_minimum_size = Vector2(44.0, 44.0)
	var motivo: String = sys.puede_subir(sid)
	btn.disabled = motivo != "ok"
	btn.tooltip_text = "Subir nivel" if motivo == "ok" else _texto_motivo_skill(motivo)
	btn.pressed.connect(_al_subir_skill.bind(sid))
	fila.add_child(btn)
	return fila


## Línea de números efectivos según el tipo de efecto.
func _numeros_skill(sid: String, sys: SkillSystem) -> String:
	var datos: Dictionary = SkillDB.obtener(sid)
	var tipo: String = str((datos.get("efecto", {}) as Dictionary).get("tipo", ""))
	var mana: float = sys.mana_efectivo(sid)
	match tipo:
		"dano", "aoe":
			return "Daño ×%.2f · Maná %d" % [sys.power_efectivo(sid), int(mana)]
		"curar":
			return "Cura %d · Maná %d" % [int(sys.power_efectivo(sid)), int(mana)]
		"buff":
			return "Efecto +%d%% · Maná %d" % [int(sys.cantidad_efectiva(sid) * 100.0), int(mana)]
		"debuff":
			return "Efecto −%d%% · Maná %d" % [int(sys.cantidad_efectiva(sid) * 100.0), int(mana)]
	return "Maná %d" % int(mana)


static func _texto_motivo_skill(motivo: String) -> String:
	match motivo:
		"sin_puntos":
			return "Sin puntos (sube de nivel)"
		"max_nivel":
			return "Nivel máximo"
		"no_aprendida":
			return "No aprendida"
	return motivo


func _al_subir_skill(sid: String) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	if _jugador.skills == null:
		return
	_jugador.skills.subir_nivel(sid)
	_reconstruir_skills()


# --------------------------------------------------------------- talentos ---

func _reconstruir_talentos() -> void:
	if _filas_talentos == null:
		return
	for h in _filas_talentos.get_children():
		h.queue_free()
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var tal: Talentos = _jugador.talentos
	if tal == null:
		return
	if _puntos_tal != null:
		_puntos_tal.text = "Nv %d · Puntos: %d" % [_jugador.nivel, tal.puntos]
	for tid in TalentoDB.talentos_por_clase(_jugador.clase_id):
		_filas_talentos.add_child(_fila_talento(tid, tal))


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
	btn.tooltip_text = "Subir rango" if motivo == "ok" else _texto_motivo_talento(motivo)
	btn.pressed.connect(_al_subir_talento.bind(tid))
	fila.add_child(btn)
	return fila


static func _pips(r: int, mx: int) -> String:
	var s: String = ""
	for i in range(mx):
		s += "●" if i < r else "○"
	return s


static func _texto_motivo_talento(motivo: String) -> String:
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


func _al_subir_talento(tid: String) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	if _jugador.talentos == null:
		return
	_jugador.talentos.subir(tid, _jugador.stats, _jugador.nivel,
		_jugador.clase_id)


## K alterna el panel.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("abrir_habilidades"):
		visible = not visible
		if visible:
			_reconstruir()
		get_viewport().set_input_as_handled()


## ESC cierra (corre antes que el _unhandled_input del Player).
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancelar_seleccion"):
		visible = false
		get_viewport().set_input_as_handled()
