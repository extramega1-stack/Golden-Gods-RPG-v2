extends SceneTree
## Captura la escena del juego con el MISMO encuadre, para comparar dos looks.
##
## Por que una herramienta y no una foto a mano: para probar que un cambio de
## iluminacion funciona hay que comparar la MISMA vista antes y despues. Con
## encuadres distintos no se puede afirmar nada, y el ojo se deja engañar por el
## zoom.
##
## Uso:
##   godot --path . --script res://tools/captura_luz.gd -- --salida=build/capturas --etiqueta=antes
##
## Por que NO se puede testear en headless: un driver dummy no renderiza nada.
## Con `--headless` sale un PNG negro y uno podria concluir que el cambio rompio
## la imagen, cuando en realidad no se dibujo. Con ventana de verdad.

const DEMO := "res://scenes/demo/fase14_demo.tscn"
const ESPERAR := 900          # frames antes de capturar: el mundo tarda en armar
const ANCHO := 1600
const ALTO := 900


var _n: int = 0
var _hecho: bool = false
var _salida: String = "build/capturas"
var _etiqueta: String = "antes"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--salida="):
			_salida = a.get_slice("=", 1)
		elif a.begins_with("--etiqueta="):
			_etiqueta = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_salida))
	root.content_scale_size = Vector2i(ANCHO, ALTO)

	var ps: PackedScene = load(DEMO)
	if ps == null:
		push_error("[CAPTURA] no se pudo cargar la escena")
		quit(1)
		return
	var mundo: Node = ps.instantiate()
	root.add_child(mundo)
	print("[CAPTURA] mundo instanciado, esperando %d frames" % ESPERAR)


func _process(_delta: float) -> bool:
	_n += 1
	if _n < ESPERAR or _hecho:
		return false
	_hecho = true
	# Un frame mas despues de _process para que el buffer este completo.
	var vp: Viewport = root
	var img: Image = vp.get_texture().get_image()
	if img == null:
		push_error("[CAPTURA] la imagen vino nula: no hay ventana")
		quit(1)
		return true
	var ruta: String = "%s/%s.png" % [_salida, _etiqueta]
	img.save_png(ruta)
	# El histograma es lo que hace util la captura: dice si la imagen esta
	# quemada (todo en 255) o apagada (todo en 0), que es el fallo tipico al
	# tocar el tonemap. Un PNG mirando no siempre se nota.
	print("[CAPTURA] %s  %dx%d" % [ruta, img.get_width(), img.get_height()])
	print("[CAPTURA] brillo medio=%.3f  min=%d  max=%d" % [
		_brillo(img), _min(img), _max(img)])
	quit(0)
	return true


func _brillo(img: Image) -> float:
	var suma: float = 0.0
	var n: int = 0
	var paso: int = maxi(1, img.get_width() / 160)
	for y in range(0, img.get_height(), paso):
		for x in range(0, img.get_width(), paso):
			suma += img.get_pixel(x, y).get_luminance()
			n += 1
	return suma / maxf(float(n), 1.0)


func _min(img: Image) -> int:
	var v: int = 255
	var paso: int = maxi(1, img.get_width() / 160)
	for y in range(0, img.get_height(), paso):
		for x in range(0, img.get_width(), paso):
			v = mini(v, int(img.get_pixel(x, y).get_luminance() * 255.0))
	return v


func _max(img: Image) -> int:
	var v: int = 0
	var paso: int = maxi(1, img.get_width() / 160)
	for y in range(0, img.get_height(), paso):
		for x in range(0, img.get_width(), paso):
			v = maxi(v, int(img.get_pixel(x, y).get_luminance() * 255.0))
	return v
