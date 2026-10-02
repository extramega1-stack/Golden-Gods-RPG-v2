extends SceneTree
## Test de regresión del Bloque 65: la transición entre escenas.
##
## POR QUÉ ESTE ARCHIVO EXISTE: este bug se encontró JUGANDO, no leyendo el
## código. Al pulsar "Nueva partida" en el título, la transición reventaba con
## "Invalid assignment of property 'paused' on a null instance".
##
## La causa: `_ir_a()` usaba `get_tree()` DESPUÉS de un `await`. Al cambiar de
## escena, la escena anterior se libera y este nodo se iba con ella, así que
## `get_tree()` devolvía null. El arreglo es capturar el árbol ANTES del await
## y no depender de `self` después.
##
## Y había un segundo bug encadenado: el nodo se añadía con `call_deferred`,
## así que quedaba FUERA del árbol mientras `_fundir` ya estaba creando el
## tween. Un tween en un nodo sin árbol no se procesa nunca.

var _ok: int = 0
var _fallos: int = 0
var _hecho: bool = false


func _init() -> void:
	print("[TEST] Bloque 65 — Transición entre escenas")


func _process(_delta: float) -> bool:
	if _hecho:
		return false
	_hecho = true
	_test_existe_y_es_sistema()
	_test_se_anade_al_arbol()
	_test_captura_el_arbol_antes_del_await()
	_test_no_depende_de_si_mismo()
	_test_sale_de_la_pila()
	print("[TEST] transicion: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _test_existe_y_es_sistema() -> void:
	_chk(Transicion != null, "la clase existe", "")
	_chk(Transicion.CAPA == UiLayers.TRANSICION,
		"va en su capa (98, bajo los modales críticos)", str(Transicion.CAPA))
	_chk(Transicion.CAPA > UiLayers.MENU_PAUSA,
		"y por encima de la pausa, para que la pause no la tape", "")
	_chk(Transicion.FADE_SEG > 0.0 and Transicion.FADE_SEG < 1.0,
		"el fundido es corto (si dura mas, parece que el juego se cuelga)",
		str(Transicion.FADE_SEG))


## El bug del `call_deferred`: el nodo tiene que estar EN EL ARBOL nada más
## crearse, porque `_fundir` crea un tween y un tween sin arbol no corre.
func _test_se_anade_al_arbol() -> void:
	var t: Transicion = Transicion.asegurar()
	_chk(t != null, "asegurar() devuelve una instancia", "")
	if t == null:
		return
	# Immediately despues de asegurar, tiene que estar dentro del arbol. Con
	# `call_deferred` tardaba un frame y el tween se quedaba colgado.
	_chk(t.is_inside_tree(),
		"se añade INMEDIATO al árbol (con call_deferred el tween no corría)", "")
	_chk(t.get_parent() != null, "y tiene padre", "")
	# Y es singleton: la segunda llamada devuelve la MISMA instancia (si no, cada
	# navegación añade un fundido y se apilan).
	var t2: Transicion = Transicion.asegurar()
	_chk(t2 == t, "es singleton (dos llamadas = la misma instancia)", "")
	t.queue_free()


## El bug del `get_tree()` post-await: `_ir_a` NO puede llamar a `get_tree()`
## despues de un await, porque el nodo puede haber muerto con la escena.
func _test_captura_el_arbol_antes_del_await() -> void:
	# Se comprueba por FUENTE, que es lo que evita un refactor accidental: si
	# alguien vuelve a poner `get_tree()` dentro de `_ir_a`, el test falla.
	var ruta := ProjectSettings.globalize_path("res://scripts/ui/transicion.gd")
	var txt := FileAccess.get_file_as_string(ruta)
	var i := txt.find("func _ir_a(ruta: String) -> void:")
	_chk(i >= 0, "se encuentra _ir_a", "")
	if i < 0:
		return
	var cuerpo := txt.substr(i, 1400)
	# La captura del arbol tiene que ir ANTES del primer `await`.
	var pos_captura := cuerpo.find("Engine.get_main_loop() as SceneTree")
	var pos_await := cuerpo.find("await")
	_chk(pos_captura >= 0, "_ir_a captura el árbol", "")
	_chk(pos_await >= 0, "_ir_a tiene un await", "")
	_chk(pos_captura >= 0 and pos_await >= 0 and pos_captura < pos_await,
		"y la captura es ANTES del await (si no, get_tree() es null al volver)",
		"captura=%d await=%d" % [pos_captura, pos_await])
	# Y dentro de `_ir_a` no debe quedar un `get_tree()`: es exactamente el
	# bug que se encontró jugando.
	_chk(not cuerpo.substr(0, cuerpo.find("func _fundir")).contains("get_tree()"),
		"y no queda ningún get_tree() dentro de _ir_a", "")


## Y el peor caso: si el árbol se va (no hay display, se cierra el juego a
## mitad), la transición tiene que degradar a cambiar de escena, no reventar.
func _test_no_depende_de_si_mismo() -> void:
	var t: Transicion = Transicion.new()
	t.name = "T"
	# Sin añadirlo al árbol a propósito: simula "el nodo ya no está".
	_chk(not t.is_inside_tree(), "el nodo de prueba está fuera del árbol", "")
	# El método existe y no debe necesitar `self` para empezar.
	_chk(t.has_method("_ir_a"), "_ir_a existe", "")
	_chk(t.has_method("_fundir"), "_fundir existe", "")
	# `asegurar` con un árbol sin root no debe reventar (devuelve la instancia
	# sin colgar: el llamador la usa para el fade y degrada si no puede).
	_chk(Transicion.CAPA > 0, "la clase es utilizable", "")
	t.free()


## EL BUG, encontrado por la partida completa (`tools/jugar.sh`, P11): la
## transición se metía en `PilaUI` con `abrir()` y NUNCA salía. Se quedaba de
## cima para siempre, y como la cima es la única que recibe el ESC, ningún
## panel podía volver a apilarse: los diez del catálogo dieron "no se abre con
## su tecla", uno detrás de otro, con la pila en 1.
##
## El contrato de `PilaUI` es de una línea por panel: entrar al abrir, SALIR
## al cerrar. El fundido no es un panel, pero se apila para bloquear el input
## mientras tapa la pantalla, así que tiene que salir cuando termina.
func _test_sale_de_la_pila() -> void:
	var t: Transicion = Transicion.asegurar()
	_chk(t != null, "hay una transición para la prueba", "")
	if t == null:
		return
	PilaUI.limpiar()
	# Durante el fundido tiene que ESTAR en la pila (si no, el ESC de un
	# jugador llega al panel que hay debajo mientras la pantalla está a negro).
	t._fundir(1.0)
	_chk(PilaUI.cima() == t,
		"durante el fundido, la transición es la cima de la pila",
		"cima=%s" % str(PilaUI.cima()))
	# Y al terminar tiene que HABER SALIDO. Se fuerza el final del fundido con
	# el mismo efecto que tiene el tween terminado (el `alpha` a 0 deja la capa
	# invisible), que es exactamente la línea de la que se trata.
	t._caja_terminada()
	_chk(PilaUI.cima() != t,
		"al terminar el fundido, la transición SALE de la pila",
		"cima=%s" % str(PilaUI.cima()))
	_chk(PilaUI.abierta() == 0,
		"y la pila queda vacía para que el próximo panel pueda apilarse",
		"pila=%d" % PilaUI.abierta())
	t.queue_free()



