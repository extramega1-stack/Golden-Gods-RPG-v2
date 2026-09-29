class_name IndicadorVitales
extends CanvasLayer
## Fase 63 (hotfix 62.1): hambre, sed y energía en pantalla.
##
## POR QUÉ EXISTE: la Fase 58 implementó el decaimiento entero, el debuff, la
## sincronización por MODS y la decisión de Juan Diego de que a 0 NO matan.
## Todo eso pasaba, y el jugador no tenía ni una barra: se le vaciaba el
## hambre, le bajaba el ataque y no había forma de saber por qué. Peor, la
## comida de la 54 se podía comer a ciegas.
##
## Lo que se hizo en su día fue lo correcto (lógica pura testeada, mods
## reversibles, sin matar), pero una regla de supervivencia que no se ve no
## es una regla: es un castigo invisible.
##
## - UI pura: se suscribe a `Vitals.vital_cambiado` y NO lee por frame. La
##   señal es "sucia" (Fase 63): `Vitals` la emite solo cuando un valor se
##   movió `TOQUE_MIN` puntos, porque `avanzar()` corre cada frame.
## - Escucha `Player.vital_bajo`, que hasta la 63 no tenía ni un listener.
## - Los tres estados: lleno, normal, bajo (pulsea) y vacío (rojo fijo).
##   El de `Vitals.UMBRAL_VACIO` (15) es el que dispara el aviso.

## Capa: `UiLayers.VITALES`, arriba a la izquierda, junto al retrato.
const CAPA: int = UiLayers.VITALES
## Ancho de cada barra. Tres de 130 px entran de sobra bajo el HUD.
const ANCHO: float = 130.0
const ALTO: float = 11.0
## Cada vital lleva su color propio: si los tres fueran el mismo, el jugador
## tendría que leer la etiqueta para saber cuál mirar.
const COLOR_HAMBRE: Color = Color(0.85, 0.55, 0.18)
const COLOR_SED: Color = Color(0.30, 0.60, 0.90)
const COLOR_ENERGIA: Color = Color(0.45, 0.80, 0.35)
const COLOR_BAJO: Color = Color(0.95, 0.30, 0.15)
const COLOR_FONDO: Color = Color(0.06, 0.06, 0.09, 0.88)
## Píxeles sobre el borde de la ventana.
const MARGEN: float = 16.0
## Alto reservado arriba, para no pisar el HUD.
const TOPE: float = 96.0
## Frecuencia del pulso cuando un vital está bajo.
const PULSO_SEG: float = 0.7

## Emitido cuando un vital entra en la franja baja. Lo usa el test; el juego
## ya lo recibe por `Player.vital_bajo`.
signal vital_en_bajo(cual: String)

## §9.1
var system_id: StringName = &"indicador_vitales"

var _caja: VBoxContainer = null
var _barras: Dictionary = {}
var _etiquetas: Dictionary = {}
var _icono_enfermedad: Label = null
var _espera: float = 0.0
## ¿Está en la fase atenuada del pulso? Un booleano y un reloj, y no dos
## escritores del mismo reloj (que es como estaba antes y nunca atenuaba).
var _pulsando: bool = false
var _alerta: bool = false
## El vital vigilado, para recalcular la alerta sin depender del aviso.
var _vitals: Vitals = null
## Copia de los tres valores para recalcular la alerta sin preguntar al vital.
var _alerts: Array[float] = [Vitals.MAXIMO, Vitals.MAXIMO, Vitals.MAXIMO]


func _ready() -> void:
	layer = CAPA
	_construir()
	visible = true
	set_process(true)


func _construir() -> void:
	_caja = VBoxContainer.new()
	_caja.name = "Vitales"
	_caja.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_caja.offset_left = MARGEN
	_caja.offset_top = TOPE
	_caja.add_theme_constant_override("separation", 3)
	_caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caja)

	_fila("hambre", "Hambre", COLOR_HAMBRE)
	_fila("sed", "Sed", COLOR_SED)
	_fila("energia", "Energía", COLOR_ENERGIA)

	# La enfermedad no es una barra: es un estado. Va como icono que se enciende.
	_icono_enfermedad = Label.new()
	_icono_enfermedad.text = "✦ enfermo"
	_icono_enfermedad.add_theme_font_size_override("font_size", 12)
	_icono_enfermedad.add_theme_color_override("font_color", Color(0.70, 0.95, 0.45))
	_icono_enfermedad.visible = false
	_icono_enfermedad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caja.add_child(_icono_enfermedad)


func _fila(id: String, texto: String, color: Color) -> void:
	var marco := PanelContainer.new()
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.custom_minimum_size = Vector2(ANCHO, 0)
	var est := StyleBoxFlat.new()
	est.bg_color = COLOR_FONDO
	est.set_corner_radius_all(3)
	est.content_margin_left = 4
	est.content_margin_right = 4
	est.content_margin_top = 2
	est.content_margin_bottom = 2
	marco.add_theme_stylebox_override("panel", est)

	var caja := HBoxContainer.new()
	caja.add_theme_constant_override("separation", 5)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.add_child(caja)

	var lbl := Label.new()
	lbl.text = texto
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	lbl.custom_minimum_size = Vector2(52, 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(lbl)
	_etiquetas[id] = lbl

	var barra := ProgressBar.new()
	barra.min_value = 0.0
	barra.max_value = Vitals.MAXIMO
	barra.value = Vitals.MAXIMO
	barra.show_percentage = false
	barra.custom_minimum_size = Vector2(ANCHO - 62.0, ALTO)
	barra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# El color va por código: así el "lleno" y el "vacío" se distinguen sin
	# tener que cambiar la textura de la barra.
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = color
	estilo.set_corner_radius_all(2)
	barra.add_theme_stylebox_override("fill", estilo)
	_barras[id] = {"barra": barra, "estilo": estilo, "color": color, "vacio": false}

	caja.add_child(barra)
	_caja.add_child(marco)


## Fase 63: se engancha al jugador. Va aparte del `_ready` porque el nodo se
## crea antes de que exista el jugador.
func vigilar(jugador: Player) -> void:
	if jugador == null or not is_instance_valid(jugador):
		return
	_vitals = jugador.vitals
	_refrescar(jugador.vitals)
	if not jugador.vitals.vital_cambiado.is_connected(_al_cambiar):
		jugador.vitals.vital_cambiado.connect(_al_cambiar)
	if not jugador.vitals.enfermedad_cambiada.is_connected(_al_enfermedad):
		jugador.vitals.enfermedad_cambiada.connect(_al_enfermedad)
	if not jugador.vital_bajo.is_connected(_al_vital_bajo):
		jugador.vital_bajo.connect(_al_vital_bajo)
	_al_enfermedad(jugador.vitals.enfermedad > 0.0)


func _al_cambiar(hambre: float, sed: float, energia: float, _enf: float) -> void:
	_pintar("hambre", hambre)
	_pintar("sed", sed)
	_pintar("energia", energia)


func _pintar(id: String, valor: float) -> void:
	match id:
		"hambre":
			_alerts[0] = valor
		"sed":
			_alerts[1] = valor
		"energia":
			_alerts[2] = valor
	if not _barras.has(id):
		return
	var e: Dictionary = _barras[id]
	var barra: ProgressBar = e["barra"]
	barra.value = valor
	var vacio: bool = valor < Vitals.UMBRAL_VACIO
	if vacio != bool(e["vacio"]):
		e["vacio"] = vacio
		# Vacío = rojo fijo. Bajo pero no vacío = el color del vital (lo hace
		# pulsar el pulso de abajo).
		var est: StyleBoxFlat = e["estilo"]
		est.bg_color = COLOR_BAJO if vacio else (e["color"] as Color)


func _al_enfermedad(activa: bool) -> void:
	if _icono_enfermedad != null:
		_icono_enfermedad.visible = activa


func _al_vital_bajo(cual: String) -> void:
	_alerta = true
	vital_en_bajo.emit(cual)


## Fase 63: si algún vital está en la franja baja, la fila entera parpadea.
## Con `modulate` sobre la fila, no con un tween por vital: un solo reloj.
func _process(delta: float) -> void:
	# La alerta se RECALCULA, no se queda en true para siempre: si se olvidara
	# apagarse, la fila parpadearía eternamente aunque comieras.
	_alerta = false
	for v in _alerts:
		if v < Vitals.UMBRAL_VACIO:
			_alerta = true
			break
	if not _alerta:
		_espera = 0.0
		_pulsando = false
		_caja.modulate = Color(1, 1, 1, 1)
		return
	_espera += delta
	if _espera < PULSO_SEG:
		return
	_espera = 0.0
	_pulsando = not _pulsando
	_caja.modulate = Color(0.55, 0.55, 0.55, 1.0) if _pulsando \
			else Color(1, 1, 1, 1)


## ¿Está en alerta? Para los tests.
func en_alerta() -> bool:
	return _alerta


## Refresco puntual, para cuando los vitales se resetean al reaparecer (el
## `Player.reaparecer()` de la 51 crea unos nuevos) o se cargan de un save.
func _refrescar(v: Vitals) -> void:
	if v == null:
		return
	_pintar("hambre", v.hambre)
	_pintar("sed", v.sed)
	_pintar("energia", v.energia)
	_al_enfermedad(v.enfermedad > 0.0)
