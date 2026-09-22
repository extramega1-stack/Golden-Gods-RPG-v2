extends SceneTree
## Tests headless de la Fase 16 (sistema de clima: lluvia + niebla).
##
## (a) Datos: data/clima.json es válido — 4 estados (despejado, lluvia,
##     niebla, lluvia_niebla), intensidades en [0,1], transicion_seg > 0,
##     pesos de "siguientes" >= 0 con suma > 0, y bloques lluvia/niebla.
## (b) `fijar_clima` + `avanzar` (tiempo simulado, SIN nodos en el árbol):
##     la intensidad de lluvia interpola 0→1 en transicion_seg;
##     `intensidad()` es el máximo entre lluvia y niebla.
## (c) Estado desconocido: `fijar_clima("tornado")` devuelve false y no
##     cambia nada.
## (d) Transiciones sin saltos: con dt=0.05 la intensidad nunca cambia más
##     de dt/transicion_seg por paso.
## (e) La lluvia se activa/desactiva por datos (con nodos): al fijar
##     "lluvia" el GPUParticles3D emite con amount_ratio≈1 y el ciclo se
##     atenúa (factor_clima, gris_tormenta, fog); al volver a "despejado"
##     todo vuelve a 0/off.
## (f) Cambio automático: con semilla fija las revisiones ponderadas solo
##     producen estados válidos y el clima varía con el tiempo.
## (g) La señal `cambio_clima` se emite al cambiar de estado.
## (h) CicloDia: factor_clima=1.0 y gris_tormenta=0.0 por defecto (el look
##     diurno existente no cambia sin clima).
##
## Cómo correrlos (un solo comando):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase16_clima.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const CL: GDScript = preload("res://scripts/mundo/clima.gd")
const CD: GDScript = preload("res://scripts/mundo/ciclo_dia.gd")

const ESTADOS_VALIDOS: Array[String] = ["despejado", "lluvia", "niebla", "lluvia_niebla"]

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []
var _frame: int = 0
var _senales: Array = []


func _init() -> void:
	print("[TEST] Fase 16 — sistema de clima")


## Frame 1: montar nodos (sus _ready corren al añadirlos al árbol).
## Frame 2: correr los asserts (lección 13b).
func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		return false  # true pediría salir del main loop
	if _frame > 2:
		return true
	_t_json()
	_t_sin_nodos()
	_t_estado_desconocido()
	_t_sin_saltos()
	_t_lluvia_por_datos()
	_t_cambio_automatico()
	_t_senal()
	_t_ciclo_defaults()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
	return true


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


## Clima puro, sin añadir al árbol (avanzar es testeable sin nodos).
func _clima_puro() -> Clima:
	var w: Clima = CL.new()
	w.cambio_automatico = false
	return w


## Clima montado en el árbol con ciclo y jugador inyectados (frame 1).
func _montar() -> Clima:
	var ciclo: CicloDia = CD.new()
	root.add_child(ciclo)
	_basura.append(ciclo)
	var jugador := Node3D.new()
	jugador.position = Vector3(10.0, 5.0, -7.0)
	root.add_child(jugador)
	_basura.append(jugador)
	var w: Clima = CL.new()
	w.ciclo = ciclo
	w.jugador = jugador
	w.cambio_automatico = false
	root.add_child(w)
	_basura.append(w)
	return w


func _t_json() -> void:
	var texto: String = FileAccess.get_file_as_string("res://data/clima.json")
	_check(texto != "", "clima: data/clima.json existe y se lee")
	var crudo = JSON.parse_string(texto)
	_check(crudo is Dictionary, "clima: el JSON es un diccionario")
	if not (crudo is Dictionary):
		return
	var datos: Dictionary = crudo
	var estados: Dictionary = datos.get("estados", {})
	_check(estados.size() == 4, "clima: hay 4 estados", str(estados.size()))
	for id in ESTADOS_VALIDOS:
		_check(estados.has(id), "clima: existe el estado '%s'" % id)
		if not estados.has(id):
			continue
		var e: Dictionary = estados[id]
		var ll: float = float(e.get("lluvia", -1.0))
		var nb: float = float(e.get("niebla", -1.0))
		_check(ll >= 0.0 and ll <= 1.0, "clima: %s.lluvia en [0,1]" % id, str(ll))
		_check(nb >= 0.0 and nb <= 1.0, "clima: %s.niebla en [0,1]" % id, str(nb))
		_check(float(e.get("transicion_seg", 0.0)) > 0.0,
			"clima: %s.transicion_seg > 0" % id)
		var pesos: Dictionary = e.get("siguientes", {})
		var suma: float = 0.0
		var pesos_ok: bool = true
		for k in pesos:
			var p: float = float(pesos[k])
			if p < 0.0:
				pesos_ok = false
			if not estados.has(str(k)):
				pesos_ok = false
			suma += p
		_check(pesos_ok and suma > 0.0,
			"clima: %s.siguientes válidos y con suma > 0" % id, str(suma))
	var ll_cfg: Dictionary = datos.get("lluvia", {})
	_check(int(ll_cfg.get("gotas", 0)) >= 1000, "clima: lluvia.gotas >= 1000",
		str(ll_cfg.get("gotas", 0)))
	_check(float(ll_cfg.get("preprocess_seg", 0.0)) > 0.0,
		"clima: lluvia.preprocess_seg > 0")
	var nb_cfg: Dictionary = datos.get("niebla", {})
	_check(float(nb_cfg.get("densidad_max", 0.0)) > 0.0,
		"clima: niebla.densidad_max > 0")
	var rev: Dictionary = datos.get("intervalo_revision_seg", {})
	_check(float(rev.get("min", 0.0)) > 0.0 and float(rev.get("max", 0.0)) >= float(rev.get("min", 0.0)),
		"clima: intervalo_revision_seg válido")


func _t_sin_nodos() -> void:
	var w: Clima = _clima_puro()
	_check(w.clima_actual() == "despejado", "clima: arranca en despejado",
		w.clima_actual())
	_check(w.intensidad() == 0.0, "clima: intensidad inicial 0")
	_check(w.fijar_clima("lluvia"), "clima: fijar_clima('lluvia') acepta")
	_check(w.clima_actual() == "lluvia", "clima: clima_actual() == 'lluvia'")
	# transicion_seg de lluvia = 6.0: con 6 s simulados llega al objetivo.
	w.avanzar(3.0)
	var mitad: float = w.intensidad_lluvia()
	_check(mitad > 0.3 and mitad < 0.7,
		"clima: a mitad de la transición la intensidad va a medias", str(mitad))
	w.avanzar(3.0)
	_check(absf(w.intensidad_lluvia() - 1.0) < 0.001,
		"clima: tras transicion_seg la lluvia llega a 1.0",
		str(w.intensidad_lluvia()))
	_check(absf(w.intensidad() - 1.0) < 0.001,
		"clima: intensidad() == 1.0 con lluvia plena", str(w.intensidad()))
	# lluvia_niebla: intensidad() es el máximo (0.8 y 0.8).
	w.fijar_clima("lluvia_niebla")
	w.avanzar(30.0)
	_check(absf(w.intensidad_lluvia() - 0.8) < 0.01,
		"clima: lluvia_niebla → lluvia≈0.8", str(w.intensidad_lluvia()))
	_check(absf(w.intensidad_niebla() - 0.8) < 0.01,
		"clima: lluvia_niebla → niebla≈0.8", str(w.intensidad_niebla()))
	_check(absf(w.intensidad() - 0.8) < 0.01,
		"clima: intensidad() es el máximo (0.8)", str(w.intensidad()))
	# niebla pura: la lluvia baja a 0 y la niebla sube a 1.
	w.fijar_clima("niebla")
	w.avanzar(30.0)
	_check(w.intensidad_lluvia() < 0.01, "clima: niebla → lluvia≈0",
		str(w.intensidad_lluvia()))
	_check(absf(w.intensidad_niebla() - 1.0) < 0.01, "clima: niebla → niebla≈1",
		str(w.intensidad_niebla()))


func _t_estado_desconocido() -> void:
	var w: Clima = _clima_puro()
	w.fijar_clima("lluvia")
	var antes: String = w.clima_actual()
	_check(not w.fijar_clima("tornado"),
		"clima: fijar_clima('tornado') devuelve false")
	_check(w.clima_actual() == antes,
		"clima: el estado no cambia con id desconocido", w.clima_actual())


func _t_sin_saltos() -> void:
	var w: Clima = _clima_puro()
	w.fijar_clima("lluvia")  # transicion_seg = 6.0
	var dt: float = 0.05
	var max_paso: float = dt / 6.0 + 0.0001
	var prev: float = w.intensidad_lluvia()
	var salto_max: float = 0.0
	for i in range(150):
		w.avanzar(dt)
		var cur: float = w.intensidad_lluvia()
		salto_max = maxf(salto_max, absf(cur - prev))
		prev = cur
	_check(salto_max <= max_paso,
		"clima: ningún paso salta más de dt/transicion_seg",
		"saltó %f (máx %f)" % [salto_max, max_paso])
	_check(absf(w.intensidad_lluvia() - 1.0) < 0.01,
		"clima: tras 150 pasos la transición completó", str(w.intensidad_lluvia()))
	# También al apagar: de vuelta a despejado sin cortes.
	w.fijar_clima("despejado")  # transicion_seg = 4.0
	max_paso = dt / 4.0 + 0.0001
	prev = w.intensidad_lluvia()
	salto_max = 0.0
	for i in range(120):
		w.avanzar(dt)
		var cur2: float = w.intensidad_lluvia()
		salto_max = maxf(salto_max, absf(cur2 - prev))
		prev = cur2
	_check(salto_max <= max_paso,
		"clima: al despejar tampoco hay saltos",
		"saltó %f (máx %f)" % [salto_max, max_paso])


func _t_lluvia_por_datos() -> void:
	var w: Clima = _montar()
	var ciclo: CicloDia = w.ciclo
	_check(not w.emitiendo_lluvia(), "clima: despejado no emite lluvia")
	_check(w.proporcion_lluvia() == 0.0, "clima: despejado amount_ratio 0")
	w.fijar_clima("lluvia")
	w.avanzar(30.0)  # más que transicion_seg (6.0)
	_check(w.emitiendo_lluvia(), "clima: con 'lluvia' el GPUParticles3D emite")
	_check(absf(w.proporcion_lluvia() - 1.0) < 0.01,
		"clima: con 'lluvia' amount_ratio≈1", str(w.proporcion_lluvia()))
	_check(absf(ciclo.factor_clima - 0.45) < 0.01,
		"clima: la lluvia atenúa el sol (factor_clima≈0.45)",
		str(ciclo.factor_clima))
	_check(absf(ciclo.gris_tormenta - 0.75) < 0.01,
		"clima: la lluvia agrisa el cielo (gris_tormenta≈0.75)",
		str(ciclo.gris_tormenta))
	_check(w.densidad_niebla() > 0.0,
		"clima: 'lluvia' trae algo de niebla (0.25)", str(w.densidad_niebla()))
	# La lluvia sigue al jugador (se recentra, no se recrea).
	var gotas: GPUParticles3D = w.get_node("Lluvia") as GPUParticles3D
	_check(gotas != null, "clima: el nodo Lluvia existe y es único")
	w.jugador.position = Vector3(100.0, 5.0, 50.0)
	w.avanzar(0.1)
	var d: Vector3 = gotas.global_position - (w.jugador.global_position + Vector3(0.0, 14.0, 0.0))
	_check(d.length() < 0.01, "clima: la lluvia se recentra sobre el jugador",
		str(d.length()))
	# Al despejar: todo vuelve a 0/off.
	w.fijar_clima("despejado")
	w.avanzar(30.0)
	_check(not w.emitiendo_lluvia(), "clima: despejado apaga la lluvia")
	_check(w.proporcion_lluvia() == 0.0, "clima: despejado amount_ratio 0")
	_check(absf(ciclo.factor_clima - 1.0) < 0.001,
		"clima: despejado restaura el sol (factor_clima=1)", str(ciclo.factor_clima))
	_check(ciclo.gris_tormenta == 0.0,
		"clima: despejado quita el gris (gris_tormenta=0)")
	_check(w.densidad_niebla() == 0.0, "clima: despejado sin niebla")


func _t_cambio_automatico() -> void:
	var w: Clima = _clima_puro()
	w.cambio_automatico = true
	w.fijar_semilla(1234)
	var vistos: Dictionary = {}
	# Forzar 60 revisiones: solo deben salir estados válidos y el clima
	# debe variar (no quedarse pegado en uno solo).
	for i in range(60):
		w._revision_en = 0.01
		w.avanzar(0.02)
		var e: String = w.clima_actual()
		vistos[e] = true
		_check(ESTADOS_VALIDOS.has(e),
			"clima: la revisión automática solo da estados válidos", e)
	_check(vistos.size() >= 2,
		"clima: el clima automático varía con el tiempo",
		str(vistos.keys()))


func _t_senal() -> void:
	var w: Clima = _clima_puro()
	_senales.clear()
	w.cambio_clima.connect(_al_cambio)
	w.fijar_clima("niebla")
	_check(_senales == ["niebla"], "clima: cambio_clima se emite al fijar",
		str(_senales))


func _al_cambio(estado: String) -> void:
	_senales.append(estado)


func _t_ciclo_defaults() -> void:
	var c: CicloDia = CD.new()
	_check(c.factor_clima == 1.0,
		"clima: CicloDia.factor_clima=1.0 por defecto (look intacto)")
	_check(c.gris_tormenta == 0.0,
		"clima: CicloDia.gris_tormenta=0.0 por defecto (look intacto)")
	_check(c.ambiente() == null,
		"clima: CicloDia.ambiente() es null pre-_ready (no revienta)")
