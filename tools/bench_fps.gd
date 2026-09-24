extends SceneTree
## Bench de rendimiento headless (fase 20, harness FPS).
##
## Instancia la demo principal, espera el gate de carga, calienta y mide N
## frames: FPS medio, ms medios/p95/máx por frame y mobs instanciados.
## OJO: headless usa drivers dummy (mide CPU/lógica, NO la GPU real).
## Para la GPU usa el MonitorFPS en el juego (build debug).
##
## Uso:
##   godot --headless --path . --script res://tools/bench_fps.gd -- --frames=600 --warmup=120
## Exit code 0 siempre (es bench, no test); el veredicto sale en texto.

var _demo: Node = null
var _fase: int = 0
var _frames_muestras: Array[float] = []
var _n_frames: int = 600
var _n_warmup: int = 120
var _espera: int = 0


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--frames="):
			_n_frames = maxi(int(a.get_slice("=", 1)), 10)
		elif a.begins_with("--warmup="):
			_n_warmup = maxi(int(a.get_slice("=", 1)), 0)
	print("[BENCH] frames=%d warmup=%d (headless = solo CPU)" % [_n_frames, _n_warmup])


func _process(delta: float) -> bool:
	match _fase:
		0:
			var escena: PackedScene = load("res://scenes/demo/fase14_demo.tscn")
			_demo = escena.instantiate()
			root.add_child(_demo)
			_fase = 1
			return false
		1:
			# Esperar el gate de carga (máx ~60 s).
			_espera += 1
			if not bool(_demo.get("_mundo_pendiente")):
				_fase = 2
				_espera = 0
			elif _espera > 3600:
				printerr("[BENCH] TIMEOUT esperando mundo_listo")
				quit(1)
				return true
			return false
		2:
			# Calentamiento (caches, shaders dummy, pools).
			_espera += 1
			if _espera >= _n_warmup:
				_fase = 3
			return false
		3:
			_frames_muestras.append(delta * 1000.0)
			if _frames_muestras.size() >= _n_frames:
				_reporte()
				quit(0)
				return true
			return false
	return false


func _reporte() -> void:
	var ms: Array[float] = _frames_muestras.duplicate()
	ms.sort()
	var suma: float = 0.0
	for m in ms:
		suma += m
	var media: float = suma / float(ms.size())
	var p95: float = ms[int(float(ms.size()) * 0.95)]
	var p99: float = ms[int(float(ms.size()) * 0.99)]
	var maximo: float = ms[ms.size() - 1]
	var mobs: int = -1
	var sm: Node = root.find_child("StreamingMobs", true, false)
	if sm != null and sm.has_method("conteo_instanciados"):
		mobs = int(sm.call("conteo_instanciados"))
	var jug: Node = root.find_child("Player", true, false)
	var jp: String = str((jug as Node3D).global_position) if jug != null else "?"
	print("[BENCH] ---- reporte ----")
	print("[BENCH] frames: %d | FPS medio: %.1f" % [ms.size(), 1000.0 / media])
	print("[BENCH] ms/frame: media=%.2f p95=%.2f p99=%.2f max=%.2f"
		% [media, p95, p99, maximo])
	print("[BENCH] mobs instanciados: %d | jugador en %s" % [mobs, jp])
	var veredicto: String = "OK (p95 <= 16.7 ms)"
	if p95 > 16.7:
		veredicto = "FOCO CPU: p95 > 16.7 ms (headless, sin GPU)"
	print("[BENCH] veredicto: " + veredicto)
