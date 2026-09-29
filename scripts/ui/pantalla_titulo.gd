class_name PantallaTitulo
extends Node3D
## Pantalla de título (fase 11): primera escena del juego
## (`run/main_scene` en project.godot).
##
## Fondo 3D procedural propio (nada copiado): plano de suelo oscuro, anillo
## de 6 pilares de piedra, dos braseros con luz anaranjada, cielo casi
## negro azulado (WorldEnvironment, BackgroundMode COLOR) y cámara con
## órbita lenta alrededor del centro.
##
## UI (CanvasLayer, capa UiLayers.TITULO): título dorado "GOLDEN GODS",
## subtítulo "RPG — La Última Guerra" y botones Nueva partida / Continuar /
## Nuevo Game+ / Salir, centrados, con hover visible. Continuar va
## deshabilitado si no hay partida guardada. ESC (ui_cancel) = salir.
##
## BLOQUE 68 (NG+): el botón "Nuevo Game+" cierra el ciclo — reinicia el
## personaje conservando el prestigio — y el rótulo de estado de abajo enseña
## en qué ciclo se está y qué dan los multiplicadores. Sin esas dos cosas el
## NG+ no es una mecánica: es una fórmula en un archivo.

## Las rutas de escena viven en Escenas (fuente única): la escena de juego
## es siempre la más actualizada sin que cada pantalla la repita.
const RADIO_ORBITA: float = 15.0
const ALTURA_ORBITA: float = 6.5
const VEL_ORBITA: float = 0.10
## Texto del botón de NG+ en sus dos estados. Son DOS pulsaciones, no una: el
## reset borra el nivel, el oro y el equipo del personaje, y un botón de un
## solo clic al lado de "Nueva partida" es un accidente esperando a pasar.
const TEXTO_NGPLUS: String = "Nuevo Game+"
const TEXTO_NGPLUS_CONFIRMAR: String = "¿Seguro? Reiniciar el personaje"

var _camara: Camera3D = null
var _angulo: float = 0.6
var _boton_continuar: Button = null
## Fase 46: el manual de ayuda (controles y mecánicas), se abre con ? o aquí.
var _ayuda: PanelAyuda = null
const ESCENA_AYUDA: PackedScene = preload("res://scenes/ui/panel_ayuda.tscn")
## Bloque 68: el botón de NG+ y el rótulo de estado, que se releen al volver a
## la pantalla (vuelve del mundo y el save ya cambió).
var _boton_ngplus: Button = null
var _estado_ngplus: Label = null
var _ngplus_confirmando: bool = false


## ¿Hay partida guardada para continuar? Ruta inyectable para tests (por
## defecto la ruta real del SaveSystem).
static func puede_continuar(ruta: String = SaveSystem.RUTA) -> bool:
	return FileAccess.file_exists(ruta)


func _ready() -> void:
	_construir_escena()
	_construir_ui()


func _process(delta: float) -> void:
	if _camara == null:
		return
	_angulo += VEL_ORBITA * delta
	_camara.position = Vector3(
		cos(_angulo) * RADIO_ORBITA, ALTURA_ORBITA, sin(_angulo) * RADIO_ORBITA)
	_camara.look_at(Vector3(0.0, 2.0, 0.0), Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_al_salir()


func _construir_escena() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.42, 0.58)
	env.ambient_light_energy = 0.6
	var mundo: WorldEnvironment = WorldEnvironment.new()
	mundo.environment = env
	add_child(mundo)

	var sol: DirectionalLight3D = DirectionalLight3D.new()
	sol.rotation = Vector3(-0.7, 0.5, 0.0)
	sol.light_color = Color(0.55, 0.62, 0.8)
	sol.light_energy = 0.5
	add_child(sol)

	# Suelo: plano oscuro de piedra.
	var suelo: MeshInstance3D = MeshInstance3D.new()
	var plano: PlaneMesh = PlaneMesh.new()
	plano.size = Vector2(70, 70)
	suelo.mesh = plano
	suelo.material_override = _material(Color(0.09, 0.09, 0.12), 0.95)
	add_child(suelo)

	# Anillo de 6 pilares de piedra.
	for i in range(6):
		var a: float = TAU * float(i) / 6.0
		var pilar: MeshInstance3D = MeshInstance3D.new()
		var caja: BoxMesh = BoxMesh.new()
		caja.size = Vector3(1.4, 9.0, 1.4)
		pilar.mesh = caja
		pilar.material_override = _material(Color(0.16, 0.16, 0.19), 0.9)
		pilar.position = Vector3(cos(a) * 11.0, 4.5, sin(a) * 11.0)
		add_child(pilar)

	# Dos braseros con luz anaranjada.
	_brasero(Vector3(4.5, 0.0, 4.0))
	_brasero(Vector3(-4.5, 0.0, 4.0))

	_camara = Camera3D.new()
	_camara.fov = 55.0
	add_child(_camara)


func _material(color: Color, rugosidad: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rugosidad
	return m


func _brasero(pos: Vector3) -> void:
	var base: MeshInstance3D = MeshInstance3D.new()
	var cil: CylinderMesh = CylinderMesh.new()
	cil.top_radius = 0.55
	cil.bottom_radius = 0.35
	cil.height = 1.3
	base.mesh = cil
	base.material_override = _material(Color(0.12, 0.10, 0.10), 0.85)
	base.position = pos + Vector3(0.0, 0.65, 0.0)
	add_child(base)
	# Brasa: esfera pequeña emisiva sobre el brasero.
	var brasa: MeshInstance3D = MeshInstance3D.new()
	var esf: SphereMesh = SphereMesh.new()
	esf.radius = 0.28
	esf.height = 0.56
	brasa.mesh = esf
	var mat: StandardMaterial3D = _material(Color(1.0, 0.45, 0.1), 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.42, 0.08)
	mat.emission_energy_multiplier = 2.0
	brasa.material_override = mat
	brasa.position = pos + Vector3(0.0, 1.45, 0.0)
	add_child(brasa)
	var luz: OmniLight3D = OmniLight3D.new()
	luz.light_color = Color(1.0, 0.52, 0.16)
	luz.light_energy = 2.2
	luz.omni_range = 14.0
	luz.position = pos + Vector3(0.0, 2.2, 0.0)
	add_child(luz)


func _construir_ui() -> void:
	var capa: CanvasLayer = CanvasLayer.new()
	capa.layer = UiLayers.TITULO
	add_child(capa)

	var centro: CenterContainer = CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(centro)

	var caja: VBoxContainer = VBoxContainer.new()
	caja.add_theme_constant_override("separation", 14)
	caja.alignment = BoxContainer.ALIGNMENT_CENTER
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centro.add_child(caja)

	var titulo: Label = Label.new()
	titulo.text = "GOLDEN GODS"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 84)
	titulo.add_theme_color_override("font_color", Color(0.95, 0.76, 0.32))
	titulo.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	titulo.add_theme_constant_override("shadow_offset_x", 3)
	titulo.add_theme_constant_override("shadow_offset_y", 3)
	titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(titulo)

	var subtitulo: Label = Label.new()
	subtitulo.text = "RPG — La Última Guerra"
	subtitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitulo.add_theme_font_size_override("font_size", 26)
	subtitulo.add_theme_color_override("font_color", Color(0.78, 0.72, 0.60))
	subtitulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(subtitulo)

	var aire: Control = Control.new()
	aire.custom_minimum_size = Vector2(1, 20)
	aire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(aire)

	var b_nueva: Button = _nuevo_boton("Nueva partida")
	b_nueva.pressed.connect(_al_nueva_partida)
	caja.add_child(b_nueva)

	_boton_continuar = _nuevo_boton("Continuar")
	_boton_continuar.disabled = not puede_continuar()
	_boton_continuar.pressed.connect(_al_continuar)
	caja.add_child(_boton_continuar)

	# Bloque 68: el NG+. Nace deshabilitado si no hay partida o si el personaje
	# no llegó al tope del mundo (lo decide el guardado, no la UI: `puede_ngplus`
	# lee el save, y el save es la única fuente de verdad).
	_boton_ngplus = _nuevo_boton(TEXTO_NGPLUS)
	_boton_ngplus.pressed.connect(_al_nuevo_game_plus)
	caja.add_child(_boton_ngplus)

	# Bloque 68: el estado del NG+, SIEMPRE visible. Con prestigio 0 dice que
	# no hay NG+: es la línea que le dice al jugador que existe algo detrás
	# del nivel 70, y sin ella el NG+ es invisible hasta que ocurre.
	_estado_ngplus = Label.new()
	_estado_ngplus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_estado_ngplus.add_theme_font_size_override("font_size", 15)
	_estado_ngplus.add_theme_color_override("font_color", Color(0.72, 0.62, 0.40))
	_estado_ngplus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(_estado_ngplus)
	refrescar_ngplus()

	# Fase 46: el manual de controles y mecánicas, también desde el título.
	var b_ayuda: Button = _nuevo_boton("Ayuda (?)")
	b_ayuda.pressed.connect(_al_ayuda)
	caja.add_child(b_ayuda)

	var b_salir: Button = _nuevo_boton("Salir")
	b_salir.pressed.connect(_al_salir)
	caja.add_child(b_salir)


## Fase 46: abre el manual (el mismo panel que se abre con la tecla ?).
func _al_ayuda() -> void:
	if _ayuda == null or not is_instance_valid(_ayuda):
		_ayuda = ESCENA_AYUDA.instantiate() as PanelAyuda
		add_child(_ayuda)
	_ayuda.alternar()


func _nuevo_boton(texto: String) -> Button:
	var b: Button = Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(340, 58)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", Color(0.93, 0.88, 0.74))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.90, 0.55))
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.43, 0.40))
	b.add_theme_stylebox_override("normal", _estilo_boton(Color(0.10, 0.10, 0.14, 0.92), Color(0.55, 0.42, 0.18)))
	b.add_theme_stylebox_override("hover", _estilo_boton(Color(0.16, 0.14, 0.12, 0.95), Color(0.95, 0.76, 0.32)))
	b.add_theme_stylebox_override("pressed", _estilo_boton(Color(0.22, 0.17, 0.10, 0.97), Color(0.95, 0.76, 0.32)))
	b.add_theme_stylebox_override("disabled", _estilo_boton(Color(0.07, 0.07, 0.09, 0.90), Color(0.30, 0.28, 0.26)))
	return b


func _estilo_boton(fondo: Color, borde: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fondo
	sb.border_color = borde
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	return sb


## Nueva partida: va a la creación SIN presuponer nada (la creación valida
## el nombre y escribe DatosSesion.nueva_partida).
func _al_nueva_partida() -> void:
	Transicion.ir_a(Escenas.CREACION)


func _al_continuar() -> void:
	DatosSesion.pedir_continuar()
	Transicion.ir_a(Escenas.JUEGO)


# --- bloque 68: el NG+ desde el título ---------------------------------

## Primera pulsación: pide confirmación. Segunda: reinicia. Cualquier otra
## pulsación (o el ESC) cancela y devuelve el botón a su texto, para que no
## quede armado esperando una confirmación que ya no se quiere.
func _al_nuevo_game_plus() -> void:
	if not _ngplus_confirmando:
		_ngplus_confirmando = true
		_boton_ngplus.text = TEXTO_NGPLUS_CONFIRMAR
		return
	_ngplus_confirmando = false
	_boton_ngplus.text = TEXTO_NGPLUS
	if not empezar_nuevo_game_plus():
		return
	Transicion.ir_a(Escenas.JUEGO)


## El NG+ de verdad, sin la navegación: cierra el ciclo por el sistema de
## guardado y deja la sesión en modo "continuar" para que el mundo arranque
## desde la vuelta nueva. Separado del botón a propósito, para que el test
## pueda ejercitar el reset SIN cambiar de escena (cambiar de escena en un
## `SceneTree` de test se come el test).
##
## Devuelve false si no se pudo (no había partida, estaba corrupta, o el
## personaje no llegó al tope): en ese caso la partida queda como estaba,
## porque el reset atómico no borra nada hasta que la vuelta nueva está
## escrita.
func empezar_nuevo_game_plus() -> bool:
	if not SaveSystem.reiniciar_para_ngplus():
		return false
	DatosSesion.pedir_continuar()
	_ngplus_confirmando = false
	if _boton_ngplus != null and is_instance_valid(_boton_ngplus):
		_boton_ngplus.text = TEXTO_NGPLUS
	refrescar_ngplus()
	return true


## Relee el estado del NG+ del disco y repinta botón y rótulo. Se llama al
## construir la pantalla y después de un reset; no hay bucle que la llame,
## porque el save solo cambia cuando alguien escribe.
func refrescar_ngplus() -> void:
	if _boton_ngplus == null or not is_instance_valid(_boton_ngplus):
		return
	var disponible: bool = SaveSystem.puede_nuevo_game_plus()
	_boton_ngplus.disabled = not disponible
	_ngplus_confirmando = false
	_boton_ngplus.text = TEXTO_NGPLUS
	if _estado_ngplus == null or not is_instance_valid(_estado_ngplus):
		return
	_estado_ngplus.text = _texto_estado(SaveSystem.estado_ngplus(), disponible)


## La línea de estado. Con prestigio 0 no dice "Ciclo 0 · XP x1.00", que es
## ruido: dice que la espiral existe y cuál es la puerta de entrada.
static func _texto_estado(e: EstadoNgPlus, disponible: bool) -> String:
	if e == null or e.prestigio <= 0:
		return "Primera vuelta · el NG+ se abre en el nivel %d" % NuevoJuegoPlus.tope_nivel()
	var linea: String = "NG+ · Ciclo %d · %d de prestigio · XP x%.2f · Enemigos x%.2f" % [
		e.ciclo, e.prestigio, e.multiplicador_xp(), e.multiplicador_enemigo()]
	if not disponible:
		linea += " · vuelve al nivel %d para cerrar otro ciclo" % NuevoJuegoPlus.tope_nivel()
	return linea


## El texto del rótulo de estado, tal como está en pantalla. El test lo lee
## por aquí en vez de buscar el Label en el árbol: una pantalla con 6 labels no
## es algo que un test deba conocer por dentro.
func texto_estado() -> String:
	if _estado_ngplus == null or not is_instance_valid(_estado_ngplus):
		return ""
	return _estado_ngplus.text


## El botón de NG+ del título (null si la pantalla aún no construyó su UI).
func boton_ngplus() -> Button:
	return _boton_ngplus


func _al_salir() -> void:
	get_tree().quit()
