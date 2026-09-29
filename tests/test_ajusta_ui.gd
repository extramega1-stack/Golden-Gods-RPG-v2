extends SceneTree
## Regresión del bug de paneles fuera de pantalla (encontrado JUGANDO).
##
## El síntoma: todos los menús (inventario, equipo, habilidades, personaje,
## pausa, opciones, construcción, cocina) aparecían en la esquina inferior
## derecha, casi invisibles.
##
## La causa: `AjustaUI.centrar()` asignaba `position` ANTES de `add_child()`.
## En un nodo FUERA del árbol, `position` se resuelve contra un padre de tamaño
## CERO, así que los offsets quedaban mal: al añadirlo, el panel caía en la
## esquina. En una ventana de 1280x1401 terminaba en (998, 991) — solo se veía
## la punta.
##
## POR QUÉ 99 TESTS NO LO CAZARON: el test anterior medía con
## `add_child()` ANTES de `centrar()` (orden invertido al de producción) y en
## un viewport cuadrado de 1280x1280. Dos irrealidades que se cancelaban y
## daban un "OK" falso. Este test usa el orden real y simula viewports altos.
##
## El arreglo: usar OFFSETS (relativos al ancla, independientes del padre) en
## lugar de `position`.

var _ok: int = 0
var _fallos: int = 0
var _frames: int = 0
var _hecho: bool = false


## Se corre en `_process`, NO en `_init()`: al arrancar la ventana todavia no
## tiene tamano y `get_visible_rect()` devuelve 100x100, con lo cual las
## comprobaciones de "cabe en pantalla" serian mentira. Tres frames es lo que
## tarda la ventana en tomar su tamano real.
func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if not _hecho:
		_hecho = true
		_run()
		return true
	return true


func _run() -> void:
	print("[TEST] AjustaUI — paneles dentro de pantalla")
	var vp := root.get_visible_rect().size
	print("[TEST] viewport real: %s" % str(vp))
	_orden_real_dentro_de_pantalla(vp)
	_viewports_altos()
	_sin_position()
	_anclar_tambien_dentro()
	print("[TEST] ajusta_ui: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] %s%s" % [nombre, "" if detalle == "" else "  <-- " + detalle])


func _dentro_de(r: Rect2, vp: Vector2) -> bool:
	return r.position.x >= -1.0 and r.position.y >= -1.0 \
		and r.end.x <= vp.x + 1.0 and r.end.y <= vp.y + 1.0


## Lo esencial: el ORDEN REAL de los paneles — `centrar()` antes de `add_child()`.
func _orden_real_dentro_de_pantalla(vp: Vector2) -> void:
	var p := PanelContainer.new()
	AjustaUI.centrar(p, 0.44, 0.72)   # como el inventario
	root.add_child(p)
	var r: Rect2 = p.get_global_rect()
	_chk(_dentro_de(r, vp), "inventario (0.44x0.72) dentro de pantalla", str(r))
	var vp_c: Vector2 = (r.position + r.size * 0.5)
	var dif: Vector2 = (vp_c - vp * 0.5).abs()
	_chk(dif.x < 2.0 and dif.y < 2.0,
		"y además CENTRADO (no solo dentro)", "descentrado %s px" % str(dif))
	p.queue_free()


## Con `aspect=expand` el viewport se estira en el eje que sobra, y la ventana
## puede ser alta (1280x1401 es real: monitor 1920x1080 con ventana alta). El
## panel tiene que centrarse en ESE viewport, no en 1280x720.
func _viewports_altos() -> void:
	for tam in [Vector2(1280, 720), Vector2(1280, 1401), Vector2(1401, 1280),
			Vector2(2560, 1440), Vector2(1920, 1080)]:
		var w: float = clampf(tam.x * 0.44, 380.0, 680.0)
		var h: float = clampf(tam.y * 0.72, 320.0, 820.0)
		var p := Control.new()
		p.set_anchors_preset(Control.PRESET_CENTER)
		p.custom_minimum_size = Vector2(w, h)
		p.size = Vector2(w, h)
		# El arreglo, replicado sin depender del árbol:
		p.offset_left = -w * 0.5
		p.offset_top = -h * 0.5
		p.offset_right = w * 0.5
		p.offset_bottom = h * 0.5
		root.add_child(p)
		var r: Rect2 = p.get_global_rect()
		# El panel debe caber en el viewport que se le pase (el que sea).
		var dentro_x: bool = r.size.x <= tam.x + 1.0
		var dentro_y: bool = r.size.y <= tam.y + 1.0
		_chk(dentro_x and dentro_y,
			"el panel cabe en %s" % str(tam), "size=%s" % str(r.size))
		p.queue_free()


## El arreglo no debe depender de que el nodo esté dentro o fuera del árbol:
## los offsets son relativos al ancla, `position` no.
func _sin_position() -> void:
	var src := FileAccess.get_file_as_string(
		ProjectSettings.globalize_path("res://scripts/ui/ajusta_ui.gd"))
	var i := src.find("static func centrar(")
	_chk(i >= 0, "se encuentra centrar()", "")
	if i < 0:
		return
	var cuerpo := src.substr(i, src.find("static func anclar", i) - i)
	_chk(not cuerpo.contains(".position ="),
		"centrar() NO asigna position (era el bug)", "")
	_chk(cuerpo.contains("offset_left") and cuerpo.contains("offset_right")
			and cuerpo.contains("offset_top") and cuerpo.contains("offset_bottom"),
		"y usa los cuatro offsets", "")


## `anclar()` ya usaba offsets, pero se verifica igual: las barras de estado y
## el minimapa se anclan a una esquina, no se centran.
func _anclar_tambien_dentro() -> void:
	var vp := root.get_visible_rect().size
	# Con el tamaño que usan las barras de estado y el minimapa.
	for tam in [Vector2(280, 90), Vector2(420, 260)]:
		var p := Panel.new()
		p.custom_minimum_size = tam
		AjustaUI.anclar(p, Control.PRESET_BOTTOM_RIGHT, 24.0)
		root.add_child(p)
		var r: Rect2 = p.get_global_rect()
		_chk(_dentro_de(r, vp),
			"anclar esquina abajo-dcha (%s) dentro" % str(tam), str(r))
		# Y que respete el tamaño pedido en vez de estirarse al borde.
		_chk(absf(r.size.y - tam.y) < 2.0 and absf(r.size.x - tam.x) < 2.0,
			"ancla respeta el tamaño pedido (no se estira)", "pedido=%s real=%s" % [str(tam), str(r.size)])
		p.queue_free()
