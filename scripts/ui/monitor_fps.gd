class_name MonitorFPS
extends Label
## Monitor de rendimiento en pantalla (fase 20, harness FPS).
##
## Etiqueta pequeña arriba-izquierda con FPS + ms por frame + mobs
## instanciados (del streaming, si se configura). Se refresca a 2 Hz para
## no costar nada. La demo lo añade solo en builds de debug
## (`OS.is_debug_build()`); en release no existe.
##
## Uso:
##   var mon := MonitorFPS.new()
##   mon.configurar(streaming)
##   hud.add_child(mon)

## Veces por segundo que se refresca el texto.
const FRECUENCIA: float = 2.0

var _streaming: StreamingMobs = null
var _acum: float = 0.0
var _frames: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(8.0, 8.0)
	add_theme_font_size_override("font_size", 13)
	add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	add_theme_constant_override("shadow_offset_x", 1)
	add_theme_constant_override("shadow_offset_y", 1)
	text = "…"


## Fuente opcional del conteo de mobs (solo lectura).
func configurar(streaming: StreamingMobs) -> void:
	_streaming = streaming


func _process(delta: float) -> void:
	_acum += delta
	_frames += 1
	if _acum < 1.0 / FRECUENCIA:
		return
	var fps: float = float(_frames) / _acum
	var ms: float = 1000.0 * _acum / float(maxi(_frames, 1))
	_acum = 0.0
	_frames = 0
	var mobs: String = "?"
	if _streaming != null and is_instance_valid(_streaming):
		mobs = str(_streaming.conteo_instanciados())
	text = "%d FPS · %.1f ms · %s mobs" % [int(fps), ms, mobs]
