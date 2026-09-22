extends SceneTree
## Tests headless de la Fase 12 (ciclo día/noche + antorchas).
##
## (a) Datos: `duracion_dia_seg` y hora inicial salen de data/ciclo.json
##     (720.0 s por día, arranca a las 9.0h).
## (b) `avanzar(dt)` mueve la hora proporcional a `duracion_dia_seg`
##     (inyectable); la hora hace wrap en 0–24 sin salirse del rango.
## (c) A las 12:00 el sol está alto: `oscuridad()≈0`, no es de noche y el
##     DirectionalLight3D "Sol" tiene energía plena.
## (d) A las 0:00 es de noche: `oscuridad()≈1`, el sol se apaga (0) y la
##     "Luna" toma el relevo con energía tenue.
## (e) Las señales `amanecer`/`anochecer` se emiten al cruzar 6h/18h con
##     `avanzar()` (una sola vez por cruce; sin cruce no hay señal).
## (f) `fijar_hora` asigna y hace wrap (25→1, -1→23).
## (g) Antorcha: con `ciclo=null` el brillo es fijo (factor 1.0); con un
##     CicloDia inyectado la energía escala con la oscuridad
##     (0.3 de día → 1.0 de noche); `_process` actualiza la OmniLight3D
##     cálida (flicker dentro de banda).
## (h) `avanzar`/`fijar_hora` sin estar en el árbol no revientan (los
##     visuales se refrescan solo post-_ready).
##
## Cómo correrlos (un solo comando):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase12_ciclo.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const CD: GDScript = preload("res://scripts/mundo/ciclo_dia.gd")
const AN: GDScript = preload("res://scripts/mundo/antorcha.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []
var _amaneceres: int = 0
var _anocheceres: int = 0
var _frame: int = 0


func _init() -> void:
	print("[TEST] Fase 12 — ciclo dia/noche y antorchas")


## Frame 1: montar nodos (sus _ready corren al añadirlos al árbol).
## Frame 2: correr los asserts (lección 13b).
func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		return false  # true pediría salir del main loop
	if _frame > 2:
		return true
	_t_datos()
	_t_avance()
	_t_mediodia()
	_t_medianoche()
	_t_senales()
	_t_fijar_hora()
	_t_antorcha()
	_t_sin_arbol()
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


func _ciclo() -> CicloDia:
	var c: CicloDia = CD.new()
	root.add_child(c)
	_basura.append(c)
	return c


func _al_amanecer() -> void:
	_amaneceres += 1


func _al_anochecer() -> void:
	_anocheceres += 1


func _t_datos() -> void:
	var c: CicloDia = _ciclo()
	_check(c.duracion_dia_seg == 720.0,
		"ciclo: duracion_dia_seg sale de data/ciclo.json (720)",
		str(c.duracion_dia_seg))
	_check(c.hora() == 9.0,
		"ciclo: hora_inicial sale de data/ciclo.json (9.0)",
		str(c.hora()))
	_check(c.has_node("Sol") and c.has_node("Luna") and c.has_node("Cielo"),
		"ciclo: _ready crea Sol, Luna y Cielo (WorldEnvironment)")


func _t_avance() -> void:
	var c: CicloDia = _ciclo()
	c.duracion_dia_seg = 120.0  # día de 2 minutos para el test
	c.fijar_hora(10.0)
	c.avanzar(1.0)
	_check(absf(c.hora() - 10.2) < 0.0001,
		"ciclo: avanzar(1s) con dia de 120s suma 0.2h", str(c.hora()))
	c.avanzar(120.0)
	_check(absf(c.hora() - 10.2) < 0.0001,
		"ciclo: un dia completo vuelve a la misma hora", str(c.hora()))
	c.fijar_hora(23.9)
	c.duracion_dia_seg = 24.0  # 1 hora de juego por segundo real
	c.avanzar(0.5)
	_check(absf(c.hora() - 0.4) < 0.0001,
		"ciclo: la hora hace wrap por la medianoche", str(c.hora()))
	_check(c.hora() >= 0.0 and c.hora() < 24.0,
		"ciclo: la hora siempre queda en [0, 24)")


func _t_mediodia() -> void:
	var c: CicloDia = _ciclo()
	c.fijar_hora(12.0)
	_check(c.oscuridad() < 0.01,
		"ciclo: a las 12:00 oscuridad≈0", str(c.oscuridad()))
	_check(not c.es_de_noche(),
		"ciclo: a las 12:00 no es de noche")
	var sol: DirectionalLight3D = c.get_node("Sol") as DirectionalLight3D
	_check(sol.light_energy > 1.0,
		"ciclo: a las 12:00 el sol esta alto (energia plena)",
		str(sol.light_energy))
	var luna: DirectionalLight3D = c.get_node("Luna") as DirectionalLight3D
	_check(luna.light_energy == 0.0,
		"ciclo: de dia la luna esta apagada", str(luna.light_energy))


func _t_medianoche() -> void:
	var c: CicloDia = _ciclo()
	c.fijar_hora(0.0)
	_check(c.es_de_noche(),
		"ciclo: a las 0:00 es de noche")
	_check(c.oscuridad() > 0.99,
		"ciclo: a las 0:00 oscuridad≈1", str(c.oscuridad()))
	var sol: DirectionalLight3D = c.get_node("Sol") as DirectionalLight3D
	_check(sol.light_energy == 0.0,
		"ciclo: de noche el sol se apaga", str(sol.light_energy))
	var luna: DirectionalLight3D = c.get_node("Luna") as DirectionalLight3D
	_check(luna.light_energy > 0.0 and luna.light_energy < 0.5,
		"ciclo: de noche la luna toma el relevo (tenue)",
		str(luna.light_energy))
	_check(luna.light_color.b > luna.light_color.r,
		"ciclo: la luna es azulada", str(luna.light_color))


func _t_senales() -> void:
	var c: CicloDia = _ciclo()
	c.amanecer.connect(_al_amanecer)
	c.anochecer.connect(_al_anochecer)
	c.duracion_dia_seg = 24.0  # 1h de juego por segundo real
	_amaneceres = 0
	_anocheceres = 0
	c.fijar_hora(5.9)
	c.avanzar(0.2)  # cruza las 6.0
	_check(_amaneceres == 1 and _anocheceres == 0,
		"ciclo: cruzar 6h emite amanecer (una vez)",
		"am=%d an=%d" % [_amaneceres, _anocheceres])
	c.avanzar(0.5)  # sigue de día, sin cruces
	_check(_amaneceres == 1 and _anocheceres == 0,
		"ciclo: sin cruce no hay senales repetidas",
		"am=%d an=%d" % [_amaneceres, _anocheceres])
	c.fijar_hora(17.9)
	c.avanzar(0.2)  # cruza las 18.0
	_check(_anocheceres == 1 and _amaneceres == 1,
		"ciclo: cruzar 18h emite anochecer",
		"am=%d an=%d" % [_amaneceres, _anocheceres])
	# Wrap por medianoche: de 23.9 a 6.1 pasa el amanecer.
	_amaneceres = 0
	_anocheceres = 0
	c.fijar_hora(23.9)
	c.duracion_dia_seg = 720.0
	c.avanzar(185.0)  # 6.166h de juego: 23.9 -> 6.06 (185*24/720)
	_check(_amaneceres == 1,
		"ciclo: el amanecer cruza bien el wrap de medianoche",
		"am=%d hora=%s" % [_amaneceres, str(c.hora())])


func _t_fijar_hora() -> void:
	var c: CicloDia = _ciclo()
	c.fijar_hora(15.5)
	_check(c.hora() == 15.5, "ciclo: fijar_hora asigna", str(c.hora()))
	c.fijar_hora(25.0)
	_check(c.hora() == 1.0, "ciclo: fijar_hora(25) -> 1", str(c.hora()))
	c.fijar_hora(-1.0)
	_check(c.hora() == 23.0, "ciclo: fijar_hora(-1) -> 23", str(c.hora()))
	c.fijar_hora(0.0)
	_check(c.es_de_noche(),
		"ciclo: fijar_hora refresca el estado noche/dia")


func _t_antorcha() -> void:
	var c: CicloDia = _ciclo()
	var a: Antorcha = AN.new()
	root.add_child(a)
	_basura.append(a)
	_check(a._luz != null, "antorcha: _ready crea la OmniLight3D")
	_check(a._luz.light_color == Color(1.0, 0.6, 0.25),
		"antorcha: luz calida naranja", str(a._luz.light_color))
	_check(a._luz.omni_range == a.alcance,
		"antorcha: alcance aplicado", str(a._luz.omni_range))
	# Sin ciclo: brillo fijo.
	_check(a.factor_brillo() == 1.0,
		"antorcha: sin ciclo el factor es 1.0 (fijo)")
	_check(absf(a.energia_objetivo() - a.energia_base) < 0.0001,
		"antorcha: sin ciclo la energia objetivo es la base")
	# Con ciclo: escala con la oscuridad (0.3 de día → 1.0 de noche).
	a.ciclo = c
	c.fijar_hora(12.0)
	_check(absf(a.factor_brillo() - 0.3) < 0.01,
		"antorcha: de dia el factor es 0.3", str(a.factor_brillo()))
	_check(absf(a.energia_objetivo() - a.energia_base * 0.3) < 0.01,
		"antorcha: de dia la energia es base*0.3",
		str(a.energia_objetivo()))
	c.fijar_hora(0.0)
	_check(absf(a.factor_brillo() - 1.0) < 0.01,
		"antorcha: de noche el factor es 1.0", str(a.factor_brillo()))
	# _process aplica el objetivo con flicker leve (banda ±20%).
	a._process(0.016)
	var e: float = a._luz.light_energy
	var obj: float = a.energia_objetivo()
	_check(e > obj * 0.8 and e < obj * 1.2,
		"antorcha: _process actualiza la luz (flicker en banda)",
		"e=%s obj=%s" % [str(e), str(obj)])
	# La noche ilumina ~3.3x más que el día.
	c.fijar_hora(0.0)
	var noche: float = a.energia_objetivo()
	c.fijar_hora(12.0)
	var dia: float = a.energia_objetivo()
	_check(noche / dia > 3.0,
		"antorcha: de noche brilla >3x que de dia",
		"noche=%s dia=%s" % [str(noche), str(dia)])


func _t_sin_arbol() -> void:
	# Puro math sin _ready: no debe reventar aunque no haya visuales.
	var c: CicloDia = CD.new()
	c.fijar_hora(0.0)
	c.avanzar(10.0)
	_check(c.hora() >= 0.0 and c.hora() < 24.0,
		"ciclo: avanzar sin arbol no revienta", str(c.hora()))
	c.queue_free()
