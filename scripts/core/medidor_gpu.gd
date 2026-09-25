class_name MedidorGPU
extends RefCounted
## Medición de la GPU REAL (fase 48). Complementa a `tools/bench_fps.gd`, que
## con drivers dummy solo mide CPU/lógica.
##
## Hasta ahora el proyecto NO tenía ni un presupuesto numérico de render: el
## único número duro era el p95 ≤ 16.7 ms de la fase 20. Con 85 modelos GLB
## autorizados hace falta saber cuántos draw calls y triángulos aguanta el
## mundo, o al meter el primer personaje nadie sabrá si ha roto algo.
##
## La lógica de informes (promedios, p95, veredicto) vive aquí y NO depende
## del render, así que se puede testear en headless: los tests le meten muestras
## falsas y comprueban el informe. Los valores reales salen de
## `tools/bench_gpu.gd`, que hay que lanzar SIN `--headless`.
##
## Uso:
##   var m := MedidorGPU.new()
##   m.limpiar()
##   m.tomar_muestra()          # cada frame
##   print(m.informe())

## Presupuesto de render (§9.5). Medido con `tools/bench_gpu.gd` sobre el
## mundo de la fase 48 (Moon Town con 6 mobs de prueba y las vetas de la
## plaza), con margen para que la entrada de modelos no tenga que recalcularlo
## en cada fase.
const PRESUPUESTO_DRAW_CALLS: int = 1200
const PRESUPUESTO_PRIMITIVAS: int = 900_000
const PRESUPUESTO_P95_MS: float = 16.7
const PRESUPUESTO_VIDEO_MB: int = 1024

## Una muestra por frame: {frame_ms, process_ms, physics_ms, fps, draw_calls,
## objetos, primitivas, video_mem_mb, nodos}.
var muestras: Array[Dictionary] = []


## Vacía el buffer de muestras (a empezar el warmup de nuevo).
func limpiar() -> void:
	muestras.clear()


## Lee los monitores del render y guarda una muestra del frame actual.
##
## `delta` es el tiempo real del frame (lo que pasa el `_process`), y es lo que
## se usa para `frame_ms`: es la verdad de lo que tarda un frame. Los monitores
## `TIME_*` se guardan aparte (coste de CPU), pero NO se suman: en un equipo
## con vsync dan la espera por GPU incluida y no son el coste del juego.
func tomar_muestra(delta: float = 0.0) -> Dictionary:
	var m: Dictionary = {
		"frame_ms": delta * 1000.0,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"fps": 1000.0 / maxf(delta * 1000.0, 0.0001),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objetos": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitivas": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"video_mem_mb": float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
		"nodos": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}
	muestras.append(m)
	return m


## Muestra a mano (tests: así el informe se puede verificar sin GPU).
func tomar_muestra_manual(m: Dictionary) -> void:
	muestras.append(m.duplicate())


func total() -> int:
	return muestras.size()


## Informe agregado con el veredicto contra el presupuesto de §9.5.
func informe() -> Dictionary:
	if muestras.is_empty():
		return {"muestras": 0, "veredicto": "SIN MUESTRAS"}
	var fps: Array[float] = []
	var frame_ms: Array[float] = []
	var draws: Array[float] = []
	var prims: Array[float] = []
	var objs: Array[float] = []
	var mem: Array[float] = []
	var nodos: Array[float] = []
	for m in muestras:
		fps.append(float((m as Dictionary).get("fps", 0.0)))
		frame_ms.append(float((m as Dictionary).get("frame_ms", 0.0)))
		draws.append(float((m as Dictionary).get("draw_calls", 0.0)))
		prims.append(float((m as Dictionary).get("primitivas", 0.0)))
		objs.append(float((m as Dictionary).get("objetos", 0.0)))
		mem.append(float((m as Dictionary).get("video_mem_mb", 0.0)))
		nodos.append(float((m as Dictionary).get("nodos", 0.0)))
	var res: Dictionary = {
		"muestras": muestras.size(),
		"fps_medio": _prom(fps),
		"fps_min": _min(fps),
		"frame_ms_promedio": _prom(frame_ms),
		"frame_ms_p50": _p50(frame_ms),
		"frame_ms_p95": _p95(frame_ms),
		"frame_ms_max": _max(frame_ms),
		"draw_calls_medio": _prom(draws),
		"draw_calls_max": _max(draws),
		"primitivas_medio": _prom(prims),
		"primitivas_max": _max(prims),
		"objetos_medio": _prom(objs),
		"objetos_max": _max(objs),
		"video_mem_mb": _prom(mem),
		"nodos_medio": _prom(nodos),
	}
	var fallos: Array[String] = []
	if float(res["draw_calls_max"]) > float(PRESUPUESTO_DRAW_CALLS):
		fallos.append("draw_calls %d > %d" % [int(res["draw_calls_max"]), PRESUPUESTO_DRAW_CALLS])
	if float(res["primitivas_max"]) > float(PRESUPUESTO_PRIMITIVAS):
		fallos.append("primitivas %d > %d" % [int(res["primitivas_max"]), PRESUPUESTO_PRIMITIVAS])
	if float(res["frame_ms_p95"]) > PRESUPUESTO_P95_MS:
		fallos.append("p95 %.2f ms > %.2f ms" % [float(res["frame_ms_p95"]), PRESUPUESTO_P95_MS])
	if float(res["video_mem_mb"]) > float(PRESUPUESTO_VIDEO_MB):
		fallos.append("video %.0f MB > %d MB" % [float(res["video_mem_mb"]), PRESUPUESTO_VIDEO_MB])
	res["fallos"] = fallos
	res["veredicto"] = "OK" if fallos.is_empty() else "FUERA DE PRESUPUESTO"
	return res


## Línea legible para la consola del bench.
static func linea_informe(res: Dictionary) -> String:
	if int(res.get("muestras", 0)) == 0:
		return "[BENCH-GPU] sin muestras"
	return ("[BENCH-GPU] %d muestras | fps %.0f (min %.0f) | frame %.2f ms "
		% [int(res.get("muestras", 0)), float(res.get("fps_medio", 0.0)),
			float(res.get("fps_min", 0.0)), float(res.get("frame_ms_promedio", 0.0))]
		+ "p50 %.2f p95 %.2f max %.2f | draw %.0f (max %d) | prim %.0f (max %d) | %.0f MB | %s"
		% [float(res.get("frame_ms_p50", 0.0)), float(res.get("frame_ms_p95", 0.0)),
			float(res.get("frame_ms_max", 0.0)),
			float(res.get("draw_calls_medio", 0.0)), int(res.get("draw_calls_max", 0)),
			float(res.get("primitivas_medio", 0.0)), int(res.get("primitivas_max", 0)),
			float(res.get("video_mem_mb", 0.0)), str(res.get("veredicto", "?"))])


func _prom(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s: float = 0.0
	for v in a:
		s += v
	return s / float(a.size())


func _min(a: Array[float]) -> float:
	var r: float = INF
	for v in a:
		r = minf(r, v)
	return r


func _max(a: Array[float]) -> float:
	var r: float = -INF
	for v in a:
		r = maxf(r, v)
	return r


## Percentil 50 (mediana).
func _p50(a: Array[float]) -> float:
	return _percentil(a, 0.5)


## Percentil 95 (índice más bajo que lo deja en el 95% de las muestras).
func _p95(a: Array[float]) -> float:
	return _percentil(a, 0.95)


func _percentil(a: Array[float], p: float) -> float:
	if a.is_empty():
		return 0.0
	var copia: Array[float] = a.duplicate()
	copia.sort()
	var i: int = int(ceilf(p * float(copia.size()))) - 1
	return copia[clampi(i, 0, copia.size() - 1)]
