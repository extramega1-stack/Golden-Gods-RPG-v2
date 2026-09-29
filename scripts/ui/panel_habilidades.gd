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
## Fase 63: las dos pestañas del bloque 57/59. Viven AQUÍ y no en un panel
## nuevo a propósito: el K ya tenía "Skills" y "Talentos", y un cuarto
## sitio para mirar lo mismo sería una tecla más que recordar.
var _resumen_hab: Label = null
var _filas_hab: VBoxContainer = null
var _contador_hechos: Label = null
var _filas_hechos: VBoxContainer = null


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
	# Fase 63: recolección y Hechos. El `name` de cada VBox es el título de
	# la pestaña en un TabContainer.
	tabs.add_child(_pestana_habilidades())
	tabs.add_child(_pestana_hechos())


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
		if _jugador.habilidades != null \
				and _jugador.habilidades.tramo_ganado.is_connected(_reconstruir):
			_jugador.habilidades.tramo_ganado.disconnect(_reconstruir)
	_jugador = j
	if _jugador != null and is_instance_valid(_jugador):
		if _jugador.talentos != null \
				and not _jugador.talentos.cambiada.is_connected(_reconstruir):
			_jugador.talentos.cambiada.connect(_reconstruir)
		if not _jugador.subio_nivel.is_connected(_reconstruir):
			_jugador.subio_nivel.connect(_reconstruir)
		# Fase 63: las barras de XM de las cuatro habilidades y el estado de
		# los 10 Hechos se refrescan por señal, no al abrir el panel.
		if _jugador.habilidades != null \
				and not _jugador.habilidades.tramo_ganado.is_connected(_reconstruir):
			_jugador.habilidades.tramo_ganado.connect(_reconstruir)
	_reconstruir()


func _reconstruir(_arg = null) -> void:
	_reconstruir_skills()
	_reconstruir_talentos()
	# Fase 63: también las del bloque de supervivencia.
	_reconstruir_habilidades()
	_reconstruir_hechos()


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


# ------------------------------------------------- habilidades (fase 63) ---

## Fase 63: las cuatro habilidades de RECOLECCIÓN de la 57. Deliberadamente en
## un panel aparte de "Skills": las de clase suben gastando puntos, y estas
## suben solo con talar/minar/cocinar. Mezclarlas haría creer que hay una
## sola moneda de progreso, y no la hay.
func _pestana_habilidades() -> VBoxContainer:
	var caja := VBoxContainer.new()
	caja.name = "Recolección"
	caja.add_theme_constant_override("separation", 6)
	_resumen_hab = Label.new()
	_resumen_hab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resumen_hab.add_theme_font_size_override("font_size", 12)
	_resumen_hab.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
	_resumen_hab.text = "Estas NO gastan puntos: suben con lo que hacés."
	caja.add_child(_resumen_hab)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(scroll)
	_filas_hab = VBoxContainer.new()
	_filas_hab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filas_hab.add_theme_constant_override("separation", 8)
	scroll.add_child(_filas_hab)
	return caja


func _reconstruir_habilidades() -> void:
	if _filas_hab == null:
		return
	for h in _filas_hab.get_children():
		h.queue_free()
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var hab: Habilidades = _jugador.habilidades
	if hab == null:
		return
	for hid in hab.ids():
		_filas_hab.add_child(_fila_habilidad(hid, hab))


## Una fila: nombre, barra de progreso al siguiente tramo, y los números.
## La barra va al siguiente tramo, NO al total: un "0/100" contra la barra
## completa no dice nada, y una barra llena cada tramo sí.
func _fila_habilidad(hid: String, hab: Habilidades) -> VBoxContainer:
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 2)

	var cabecera := HBoxContainer.new()
	caja.add_child(cabecera)
	var nombre := Label.new()
	nombre.text = str(hab.nombre_de(hid))
	nombre.add_theme_font_size_override("font_size", 15)
	nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cabecera.add_child(nombre)
	var tramo := Label.new()
	var t: int = hab.tramo_de(hid)
	tramo.text = "tramo %d / %d" % [t, maxi(1, hab.tramos_totales(hid))]
	tramo.add_theme_font_size_override("font_size", 12)
	tramo.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	cabecera.add_child(tramo)

	var barra := ProgressBar.new()
	barra.custom_minimum_size = Vector2(0, 14)
	barra.show_percentage = false
	barra.min_value = 0.0
	barra.max_value = 1.0
	# `progreso_tramo` va de 0 a 1 dentro del tramo actual.
	barra.value = hab.progreso_tramo(hid)
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = _color_habilidad(hid)
	estilo.set_corner_radius_all(3)
	barra.add_theme_stylebox_override("fill", estilo)
	caja.add_child(barra)

	var nota := Label.new()
	nota.text = "%d XM · %s" % [hab.xp_de(hid),
		("%d XM al siguiente tramo" % maxi(0, hab.xp_para_siguiente(hid)))
			if not hab.en_tope(hid) else "tramo máximo"]
	nota.add_theme_font_size_override("font_size", 11)
	nota.add_theme_color_override("font_color", Color(0.65, 0.65, 0.6))
	caja.add_child(nota)
	return caja


## Cada habilidad con su color, como las barras de vitales: mismo dato, mismo
## color en los dos sitios donde se mira.
static func _color_habilidad(hid: String) -> Color:
	match hid:
		"tala":
			return Color(0.45, 0.72, 0.32)
		"mineria":
			return Color(0.85, 0.62, 0.25)
		"cocina":
			return Color(0.90, 0.45, 0.35)
		"recoleccion":
			return Color(0.55, 0.62, 0.88)
	return Color(0.7, 0.7, 0.7)


# ----------------------------------------------------- hechos (fase 63) ---

## Fase 63: los 10 Hechos de la 59. Se muestran TODOS, bloqueados included,
## con su requisito: un logro que aparece de la nada no se disfruta, uno que
## ves venir mientras caminás hacia la veta, sí.
func _pestana_hechos() -> VBoxContainer:
	var caja := VBoxContainer.new()
	caja.name = "Hechos"
	caja.add_theme_constant_override("separation", 6)
	_contador_hechos = Label.new()
	_contador_hechos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_contador_hechos.add_theme_font_size_override("font_size", 14)
	_contador_hechos.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	caja.add_child(_contador_hechos)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(scroll)
	_filas_hechos = VBoxContainer.new()
	_filas_hechos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filas_hechos.add_theme_constant_override("separation", 8)
	scroll.add_child(_filas_hechos)
	return caja


func _reconstruir_hechos() -> void:
	if _filas_hechos == null:
		return
	for h in _filas_hechos.get_children():
		h.queue_free()
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var h: Hechos = _jugador.hechos
	if h == null:
		return
	if _contador_hechos != null:
		_contador_hechos.text = "%d de %d" % [h.desbloqueados().size(), h.total()]
	for hid in h.ids():
		_filas_hechos.add_child(_fila_hecho(hid, h))


func _fila_hecho(hid: String, h: Hechos) -> VBoxContainer:
	var abierto: bool = h.desbloqueado(hid)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 1)

	var nombre := Label.new()
	nombre.text = ("★ " if abierto else "☆ ") + h.nombre_de(hid)
	nombre.add_theme_font_size_override("font_size", 15)
	# El color dice el estado antes de leer: dorado si está abierto, apagado
	# si falta. Es la jerarquía que hace legible una lista de 10.
	nombre.add_theme_color_override("font_color",
		Color(1.0, 0.82, 0.35) if abierto else Color(0.55, 0.54, 0.52))
	caja.add_child(nombre)

	var desc := Label.new()
	desc.text = h.descripcion_de(hid)
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color",
		Color(0.8, 0.78, 0.72) if abierto else Color(0.5, 0.5, 0.48))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(desc)

	if not abierto:
		var req := Label.new()
		var r: Array = h.requisito_de(hid)
		var hab: Habilidades = _jugador.habilidades
		var hab_nombre: String = hab.nombre_de(str(r[0])) \
				if r.size() >= 2 and hab != null else str(r[0])
		req.text = "Requiere %s tramo %d" % [hab_nombre, int(r[1]) if r.size() >= 2 else 0]
		req.add_theme_font_size_override("font_size", 11)
		req.add_theme_color_override("font_color", Color(0.45, 0.5, 0.45))
		caja.add_child(req)
	return caja
