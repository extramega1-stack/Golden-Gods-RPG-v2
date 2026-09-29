class_name BarraJefe
extends CanvasLayer
## Fase 53: barra de jefe, estilo GoW, arriba-centro.
##
## POR QUÉ EXISTE: desde la fase 52 los 6 jefes de fragmento telegrafían,
## cambian de fase y entran en rage — y el jugador no veía nada de eso. La
## fase 52 dejó el comportamiento del jefe invisible.
##
## DIFERENCIA CON `BarraVidaMob`: aquella es 3D (un QuadMesh sobre la
## cabeza del mob) y se escala MUTANDO LA MALLA. Esta es UI: un `Control`
## en su propio `CanvasLayer` (rango 10–19 de `UiLayers`). Lo que se reusa
## es la LÓGICA (el porcentaje, el drenaje retardado de la barra "fantasma",
## los peldaños de color), no el render.
##
## - Solo aparece si el enemigo es jefe (`Enemy.es_jefe`).
## - Marca los umbrales de fase (66% y 33%) para que el jugador vea que el
##   jefe está entrando en la escalada.
## - Enrage: la barra cambia de color y late.
## - La UI solo LEE al jefe por señales. Nunca le escribe stats.

## Tiempo que la barra sigue visible tras dejar de recibir vida.
const TIEMPO_VISIBLE: float = 3.0
## Altura y ancho en px (el HUD ya reserva 100 px abajo; esto va arriba).
const ANCHO: float = 620.0
const ALTO: float = 18.0
const UMBRALES_FASE: Array[float] = [0.66, 0.33]
## Los 10 peldaños de color, igual que BarraVidaMob: la barra "degrada" en
## pasos en vez de interpolar, que es lo que hace legible el damage de golpe.
const PELDANOS: int = 10
const COLOR_NOMINAL: Color = Color(0.72, 0.10, 0.10)
const COLOR_RAGE: Color = Color(0.95, 0.30, 0.05)
const COLOR_FONDO: Color = Color(0.08, 0.03, 0.03)
const COLOR_MARCA: Color = Color(0.95, 0.85, 0.45, 0.55)

## Emitida cuando el jugador elige atacar a este jefe (para el click-to-target
## si algún día se quiere). La barra no ataca ni se mueve.
signal jefe_visto(nombre: String)

var _jefe: Entity = null
var _nombre: Label = null
var _barra: ProgressBar = null
var _fantasma: ProgressBar = null
var _reloj: float = 0.0
var _mostrada: bool = false


func _ready() -> void:
	layer = UiLayers.BARRA_JEFE
	_construir()
	visible = false
	set_process(true)


func _construir() -> void:
	var marco := PanelContainer.new()
	marco.set_anchors_preset(Control.PRESET_CENTER_TOP)
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.add_theme_stylebox_override("panel", TemaFlyFF.marco())
	marco.offset_top = 60.0
	marco.offset_left = -ANCHO * 0.5
	marco.offset_right = ANCHO * 0.5
	add_child(marco)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	marco.add_child(col)

	_nombre = TemaFlyFF.etiqueta("", 18, Color(0.95, 0.85, 0.55))
	_nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_nombre)

	var caja := Control.new()
	caja.custom_minimum_size = Vector2(ANCHO, ALTO)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(caja)

	# Fondo
	var fondo := ColorRect.new()
	fondo.color = COLOR_FONDO
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(fondo)

	# Barra "fantasma": baja con retardo, para ver cuánto pegó el último golpe.
	_fantasma = ProgressBar.new()
	_fantasma.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fantasma.show_percentage = false
	_fantasma.min_value = 0.0
	_fantasma.max_value = 1.0
	_fantasma.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fantasma.add_theme_stylebox_override("fill", TemaFlyFF.relleno(COLOR_NOMINAL))
	caja.add_child(_fantasma)

	_barra = ProgressBar.new()
	_barra.set_anchors_preset(Control.PRESET_FULL_RECT)
	_barra.show_percentage = false
	_barra.min_value = 0.0
	_barra.max_value = 1.0
	_barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_barra.add_theme_stylebox_override("fill", TemaFlyFF.relleno(COLOR_NOMINAL))
	caja.add_child(_barra)

	# Marcas de los umbrales de fase: el jugador ve DÓNDE termina cada fase.
	for u in UMBRALES_FASE:
		var marca := ColorRect.new()
		marca.color = COLOR_MARCA
		marca.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marca.anchor_left = u
		marca.anchor_right = u
		marca.anchor_top = 0.0
		marca.anchor_bottom = 1.0
		marca.offset_left = -1.0
		marca.offset_right = 1.0
		caja.add_child(marca)


## Se engancha a un enemigo. Si no es jefe, no se engancha (queda oculta).
func vigilar(jefe: Entity) -> void:
	desvigilar()
	if jefe == null or not is_instance_valid(jefe):
		return
	if not (jefe is Enemy):
		return
	var e: Enemy = jefe as Enemy
	if not e.es_jefe:
		return
	_jefe = jefe
	if not _jefe.vida_cambiada.is_connected(_al_vida_cambiada):
		_jefe.vida_cambiada.connect(_al_vida_cambiada)
	if not _jefe.murio.is_connected(_al_morir):
		_jefe.murio.connect(_al_morir)
	_nombre.text = e.nombre_mostrado
	jefe_visto.emit(e.nombre_mostrado)
	_actualizar(1.0, false)


func desvigilar() -> void:
	if _jefe != null and is_instance_valid(_jefe):
		if _jefe.vida_cambiada.is_connected(_al_vida_cambiada):
			_jefe.vida_cambiada.disconnect(_al_vida_cambiada)
		if _jefe.murio.is_connected(_al_morir):
			_jefe.murio.disconnect(_al_morir)
	_jefe = null


## ¿Está siguiendo a un jefe ahora mismo?
func vigilando() -> bool:
	return _jefe != null and is_instance_valid(_jefe)


func _al_vida_cambiada(vida: float, vida_max: float) -> void:
	if vida_max <= 0.0:
		return
	_actualizar(clampf(vida / vida_max, 0.0, 1.0), true)


func _al_morir(_f: Entity) -> void:
	visible = false
	_mostrada = false
	desvigilar()


## Actualiza las dos barras. La fantasma baja sola, con retardo, para que se
## vea el golpe que acabás de pegar (Fase 19 ya hace esto en 3D).
func _actualizar(pct: float, animando: bool) -> void:
	_barra.value = pct
	if animando:
		_fantasma.value = maxf(_fantasma.value, pct)
		_reloj = TIEMPO_VISIBLE
	else:
		_fantasma.value = pct
	# Peldaños: el color degrada en pasos, como en BarraVidaMob.
	var color: Color = COLOR_RAGE if _en_rage() else COLOR_NOMINAL
	_barra.add_theme_stylebox_override("fill", TemaFlyFF.relleno(color))
	if not visible:
		visible = true
		_mostrada = true


func _en_rage() -> bool:
	return _jefe is Enemy and (_jefe as Enemy).en_rage()


func _process(delta: float) -> void:
	if not visible:
		return
	# La fantasma persigue a la real: el "damage taken" se ve.
	if _fantasma.value > _barra.value:
		_fantasma.value = maxf(_barra.value, _fantasma.value - delta * 0.35)
	if _en_rage():
		# Late mientras está en rage: es la señal de que el reloj se agotó.
		var pulso: float = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.012)
		_nombre.modulate.a = pulso
	if _reloj > 0.0:
		_reloj -= delta
		if _reloj <= 0.0 and _barra.value >= 1.0 and _fantasma.value >= 1.0:
			# oculta solo si quedó llena (nunca a mitad de pelea)
			if _jefe == null or not _jefe.esta_vivo():
				visible = false
