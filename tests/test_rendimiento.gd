extends SceneTree
## Fase 69.1 — que el ajuste de calidad HAGA algo, y que el bench no mienta.
##
## POR QUÉ EXISTE ESTE ARCHIVO: dos cosas se descubrieron midiendo, no leyendo.
##
## (1) LA CALIDAD NO SE APLICABA AL MUNDO VIVO. `PostProceso.aplicar()` lo
##     llamaba SOLO `ciclo_dia`, al construir el mundo. Mover "Calidad gráfica"
##     en el panel guardaba el número y no tocaba ni el glow ni la SSAO hasta
##     que se saliera y volviera a entrar. El panel prometía un ajuste que no
##     se veía al moverlo. `test_bloque67_visual` NO lo detectaba porque arma
##     un `Environment` nuevo y le pasa `aplicar()` a mano: prueba la función,
##     no el camino que el jugador recorre. Estos tests montan el mundo de
##     verdad y mueven el ajuste como lo mueve el panel.
##
## (2) EL BENCH MEDÍA EL COMPOSITOR. Bajo Wayland, una ventana sin el foco la
##     estrangula el compositor a 7,5 Hz: 133,3 ms clavados en cada frame, y el
##     veredicto "FUERA DE PRESUPUESTO" no era del juego. Peor: el
##     `has_focus()` no sirve para detectarlo (da `false` con el presenting
##     sano), así que el aviso nuevo mira la FORMA de la distribución.
##
## LO QUE NO SE PUEDE TESTEAR EN HEADLESS, DICHO CLARO: que la GTX 1660
## sostenga 60 fps. Eso necesita una GPU real y una ventana, y sale de
## `tools/bench_gpu.gd` (ver `docs/bench_gtx1660.md`). Acá se verifica lo que
## SÍ es lógica: que bajar la calidad baje el coste, que el ajuste llegue al
## mundo, y que el bench distinga "lento" de "estrangulado".

const VEREDICTO: GDScript = preload("res://scripts/render/veredicto_render.gd")
const PP: GDScript = preload("res://scripts/core/post_proceso.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 69.1 — Rendimiento: la calidad tiene que hacer algo")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_calidad_llega_al_mundo()
	_test_calidad_cuesta_menos()
	_test_escala_de_render_llega()
	_test_sombra_por_calidad()
	_test_compositor_no_es_el_juego()
	_test_presupuesto()
	print("[TEST] rendimiento: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	Opciones.restablecer()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


## El mundo de verdad: un `WorldEnvironment` con su `Environment` y un sol, los
## dos EN el árbol, que es lo que estaba pasando el bug.
func _mundo() -> Array:
	Opciones.cargar()
	var env := Environment.new()
	var we := WorldEnvironment.new()
	we.name = "WE_TEST"
	we.environment = env
	root.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.name = "SolTEST"
	root.add_child(sol)
	_basura.append(we)
	_basura.append(sol)
	return [we, sol, env]


# --- (1) el ajuste tiene que LLEGAR al mundo, no solo guardarse -----------

## LA REGRESIÓN DEL BUG. Mover la calidad y no cambiar el `Environment` vivo
## es exactamente el fallo que había; este test mueve el ajuste por la misma
## puerta que el panel (`Opciones.aplicar()`) y mira el mundo.
func _test_calidad_llega_al_mundo() -> void:
	var mundo: Array = _mundo()
	var env: Environment = mundo[2]
	# El panel arranca en la calidad del usuario; se fuerza a la más baja.
	Opciones.poner("calidad", 0)
	Opciones.aplicar()
	var baja_ssao: bool = env.ssao_enabled
	var baja_glow: bool = env.glow_enabled
	# Ahora el jugador sube a Ultra con el deslizador.
	Opciones.poner("calidad", 3)
	Opciones.aplicar()
	_chk(baja_ssao != env.ssao_enabled,
		"subir la calidad reencende la SSAO del mundo VIVO (no solo la guardada)",
		"antes=%s despues=%s" % [str(baja_ssao), str(env.ssao_enabled)])
	_chk(baja_glow != env.glow_enabled,
		"y el glow también (era lo que no se veía al mover el deslizador)",
		"antes=%s despues=%s" % [str(baja_glow), str(env.glow_enabled)])
	_chk(PP.aplicar_al_mundo(),
		"aplicar_al_mundo() encuentra el WorldEnvironment y el sol del árbol",
		"devolvió false: no encontró el mundo")
	# Y un SEGUNDO mundo vivo también se re-arma. Se intentó memoizar el nodo
	# encontrado y el nodo cacheado se quedaba con el primero: el segundo
	# mundo (que es lo que hace un test, y lo que hace un viaje rápido que
	# aún no liberó el anterior) se quedan sin aplicar el ajuste. Con dos
	# mundos vivos tienen que quedar los dos al día.
	var otro: Array = _mundo()
	Opciones.poner("calidad", 0)
	Opciones.aplicar()
	_chk(not (otro[2] as Environment).ssao_enabled,
		"con DOS mundos vivos, el ajuste llega a los dos (no solo al primero)",
		"el segundo sigue con ssao=%s" % str((otro[2] as Environment).ssao_enabled))


## Bajar la calidad tiene que BAJAR el coste, no solo cambiar un número. Se
## compara el `Environment` resultante de dos niveles: si los campos que
## deciden el coste en la GPU son los mismos, el ajuste es decorativo.
func _test_calidad_cuesta_menos() -> void:
	var mundo: Array = _mundo()
	Opciones.poner("calidad", 3)
	Opciones.aplicar()
	var ultra: Environment = mundo[2]
	var ultra_detalle: float = ultra.ssao_detail
	var ultra_ssao: bool = ultra.ssao_enabled
	Opciones.poner("calidad", 2)
	Opciones.aplicar()
	var alta: Environment = mundo[2]
	_chk(alta.ssao_enabled and ultra_ssao,
		"Alta y Ultra tienen SSAO (es la pasada más cara del post-proceso)", "")
	_chk(ultra_detalle > alta.ssao_detail,
		"Ultra usa MÁS muestras de SSAO que Alta (o sea, cuesta más)",
		"alta=%.2f ultra=%.2f" % [alta.ssao_detail, ultra_detalle])
	# Y el extremo: en Baja no hay SSAO, que es lo que la hace desaparecer.
	Opciones.poner("calidad", 0)
	Opciones.aplicar()
	_chk(not (mundo[2] as Environment).ssao_enabled,
		"en Baja la SSAO está apagada de verdad", "")
	# El glow arranca en Media, no en Baja: es el escalón intermedio.
	Opciones.poner("calidad", 1)
	Opciones.aplicar()
	_chk((mundo[2] as Environment).glow_enabled,
		"en Media el glow ya está", "")


## La resolución de render es el ajuste que más se nota, y también es la vía
## de escape si a un equipo le falta GPU. Si no llega al viewport, es otro
## número decorativo.
func _test_escala_de_render_llega() -> void:
	_mundo()
	Opciones.poner("escala_render", 0)  # 66 %
	Opciones.aplicar_video()
	_chk(is_equal_approx(root.scaling_3d_scale, 0.66),
		"escala de render al 66 % llega al viewport",
		"vale %.2f" % root.scaling_3d_scale)
	Opciones.poner("escala_render", 3)  # 100 %
	Opciones.aplicar_video()
	_chk(is_equal_approx(root.scaling_3d_scale, 1.0),
		"y vuelve al 100 %", "vale %.2f" % root.scaling_3d_scale)


## La sombra del sol es un atlas que se dibuja aparte: el desenfoque y las
## divisiones se pagan. La calidad tiene que moverlos, porque son de lo poco
## que queda cuando la SSAO ya está apagada.
func _test_sombra_por_calidad() -> void:
	var mundo: Array = _mundo()
	var sol: DirectionalLight3D = mundo[1]
	Opciones.poner("calidad", 0)
	Opciones.aplicar()
	var baja_blur: float = sol.shadow_blur
	var baja_normal: float = sol.shadow_normal_bias
	Opciones.poner("calidad", 3)
	Opciones.aplicar()
	_chk(sol.shadow_blur > baja_blur,
		"la calidad alta desenfoca la sombra y la baja no (cuesta una pasada)",
		"baja=%.2f alta=%.2f" % [baja_blur, sol.shadow_blur])
	_chk(sol.shadow_normal_bias != baja_normal,
		"y el sesgo normal acompaña al nivel", "")
	_chk(sol.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"Ultra usa la cuarta división del atlas (la más cara)",
		str(sol.directional_shadow_mode))
	Opciones.poner("calidad", 2)
	Opciones.aplicar()
	_chk(sol.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"y Alta se queda con dos (el enum no tiene una: el mínimo es 2)", "")
	_chk(sol.shadow_enabled, "la sombra nunca se apaga del todo: sin ella el "
		+ "edificio flota", "")


# --- (2) el bench: distinguir "lento" de "estrangulado" -------------------

## LA TRAMPA DE AGENTS.md, CON LOS NÚMEROS DE LA CORRIDA QUE LA SUFRÓ. La
## firma del compositor es una línea (p50 = p95 clavados) a 7,5 Hz. La de un
## juego que no llega es una cola. Con la regla anterior (foco) el caso
## "presenting sano pero la ventana no reporta foco" se daba por inválido y
## se perdía una medición buena; con esta no.
func _test_compositor_no_es_el_juego() -> void:
	# La corrida real que se descartó: 133,3 ms clavados a 7,5 Hz.
	_chk(VEREDICTO.estrangulado(134.72, 134.85, 7.4),
		"133 ms clavados a 7,5 Hz = compositor, NO el juego", "")
	_chk(VEREDICTO.nota(134.72, 134.85, 7.4, true) != "",
		"y el bench avisa que ese número no cuenta", "")
	# Presenting sano, ventana sin foco (este setup): el número SÍ cuenta.
	_chk(not VEREDICTO.estrangulado(4.17, 4.17, 220.0),
		"240 Hz sin foco NO es estrangulamiento", "")
	_chk(VEREDICTO.nota(4.17, 4.17, 220.0, false) != "",
		"pero se anota el foco para que el número venga con contexto", "")
	_chk(VEREDICTO.nota(16.67, 16.67, 60.0, true) == "",
		"una corrida limpia no dice nada", "")
	# Un juego LENTO de verdad: p50 bien, p95 arriba, y hay picos. Eso NO es
	# el compositor, por mucho que tarde: hay que decirlo así.
	_chk(not VEREDICTO.estrangulado(8.0, 34.74, 8.6),
		"p50 8 / p95 35 es carga sostenida, no estrangulamiento", "")
	_chk(VEREDICTO.estrangulado(120.0, 120.4, 4.0),
		"y 120 ms clavados a 4 fps también lo sería", "")


func _test_presupuesto() -> void:
	_chk(VEREDICTO.entra_en_presupuesto(16.67), "16,67 ms entra (60 fps)", "")
	_chk(not VEREDICTO.entra_en_presupuesto(16.8), "16,8 ms no", "")
	_chk(is_equal_approx(VEREDICTO.PRESUPUESTO_MS, 16.7),
		"el presupuesto son 16,7 ms (60 Hz)", "")
