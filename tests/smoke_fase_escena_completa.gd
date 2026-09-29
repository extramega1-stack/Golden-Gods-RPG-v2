extends SceneTree
## ¿Está todo CONECTADO en la partida, o solo escrito?
##
## POR QUÉ EXISTE: `_instalar_fase63_64_ui()` de scenes/demo/fase14_demo.gd
## instanciaba siete sistemas —`MenuPausa`, `PanelOpciones`, `IndicadorVitales`,
## `PromptInteraccion`, `PanelCocina`, `PanelConstruccion`, `PoolImpacto`— y NO LA
## LLAMABA NADIE. Estaba escrita, con sus tests en verde, y en la partida no
## existía nada de eso: el ESC no hacía nada porque no había menú de pausa, no
## había barras de vitales, ni prompt, ni chispas.
##
## POR QUÉ 104 TESTS NO LO CAZARON: cada panel tiene su propio test que lo monta
## en su propia escena. Todos verdes. Y ninguno se preguntaba qué hay
## realmente dentro de la escena del juego. Un test por sistema no dice nada
## sobre si el sistema está conectado a nada.
##
## Este test hace esa pregunta: carga la escena de la partida de verdad y mira
## qué hay adentro. Mismo patrón de espera que los otros smokes (por tiempo y
## buscando al Player), porque la escena se construye por fases y `_al_mundo_
## listo()` corre recién cuando el mundo está listo.

const TIMEOUT_MS: int = 180000
const FRAMES_ESPERA: int = 40

var _demo: Node = null
var _jugador: Node3D = null
var _inicio_ms: int = 0
var _frames: int = 0
var _ok: int = 0
var _fallos: int = 0
var _terminado: bool = false


func _init() -> void:
	print("[SMOKE] escena completa: ¿está todo conectado de verdad?")


func _process(_delta: float) -> bool:
	if _terminado:
		return true
	var ahora: int = Time.get_ticks_msec()
	if _demo == null:
		var escena: PackedScene = load("res://scenes/demo/fase14_demo.tscn")
		if escena == null:
			_chk(false, "la escena de la partida carga")
			return _terminar()
		_demo = escena.instantiate()
		root.add_child(_demo)
		_inicio_ms = ahora
		print("[SMOKE] demo instanciada")
		return false
	if ahora - _inicio_ms > TIMEOUT_MS:
		_chk(false, "la partida llega a estar lista (timeout)")
		return _terminar()
	if _jugador == null:
		_jugador = root.find_child("Player", true, false) as Node3D
		return false
	# El jugador existe: `_al_mundo_listo()` ya corrió o está por correr. Se
	# espera un rato igual, porque varios paneles se registran justo después.
	_frames += 1
	if _frames < FRAMES_ESPERA:
		return false
	_revisar()
	return _terminar()


func _revisar() -> void:
	var registrados := _ids_registrados(_demo)
	var esperados := {
		&"menu_pausa": "MenuPausa (sin esto el ESC no hace nada)",
		&"panel_opciones": "PanelOpciones (volumen, calidad, FOV, sensibilidad)",
		&"indicador_vitales": "IndicadorVitales (las 3 barras de hambre/sed/energia)",
		&"prompt_interaccion": "PromptInteraccion (el texto E - Prender fogata)",
		&"panel_cocina": "PanelCocina (se abre desde la fogata)",
		&"panel_construccion": "PanelConstruccion (modo construccion del refugio)",
		&"pool_impacto": "PoolImpacto (chispas al golpear, bloque 68)",
		&"panel_codice": "PanelCodice (tecla L, ola 1)",
		&"feed_avisos": "FeedAvisos (el log de avisos en pantalla)",
	}
	for id in esperados.keys():
		_chk(registrados.has(id),
			"en la partida: %s" % esperados[id],
			"falta. Hay: %s" % str(registrados.keys()))

	# Lo que el usuario más nota: que ESC tenga algo que cerrar.
	var pausa: Node = _por_id(_demo, &"menu_pausa")
	if pausa != null:
		_chk(pausa.has_method("cerrar_panel") or pausa.has_method("cerrar"),
			"el MenuPausa responde al ESC", "")
		_chk(pausa.is_inside_tree(), "y cuelga del árbol de la partida", "")
		_chk(pausa.visible == false, "y nace cerrado (lección 11)", "")

	# Y que el pool de impactos exista de verdad, que sin él el bloque 68 fue
	# medio bloque.
	var pool: Node = _por_id(_demo, &"pool_impacto")
	if pool != null:
		_chk(pool.is_inside_tree(), "el PoolImpacto cuelga del árbol", "")

	print("[SMOKE] sistemas registrados en la partida: %d" % registrados.size())


## Los system_id registrados, usando la API pública de `Systems` (`ids()`).
## Se busca el nodo que sea un `Systems`, no se adivinan nombres de propiedades
## internas: la primera versión de este test adivinaba `_registros` y por eso
## reportaba "Hay: []" con la partida llena de sistemas.
func _ids_registrados(n: Node) -> Dictionary:
	var out := {}
	for hijo in _todos(n):
		if hijo is Systems:
			for id in (hijo as Systems).ids():
				out[id] = true
	return out


func _contenedor(n: Node) -> Systems:
	for hijo in _todos(n):
		if hijo is Systems:
			return hijo
	return null


func _por_id(n: Node, id: StringName) -> Node:
	for hijo in _todos(n):
		if "system_id" in hijo and hijo.get("system_id") == id:
			return hijo
	return null


func _todos(n: Node) -> Array:
	var out: Array = []
	var cola: Array = [n]
	while not cola.is_empty():
		var cur: Node = cola.pop_back()
		out.append(cur)
		for c in cur.get_children():
			cola.append(c)
	return out


func _terminar() -> bool:
	_terminado = true
	print("[SMOKE] escena completa: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[SMOKE] FALLA: %s%s" % [nombre, "" if detalle == "" else "  <-- " + detalle])
