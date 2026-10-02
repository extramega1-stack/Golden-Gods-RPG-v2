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
		&"panel_tutorial": "PanelTutorial (el objetivo del tutorial, tecla T)",
		&"resultado_partida": "ResultadoPartida (fase 72: victoria y derrota)",
		&"panel_final": "PanelFinal (fase 72: la pantalla de fin, capa 92)",
		&"panel_derrota": "PanelDerrota (fase 72: la pantalla de derrota, capa 93)",
	}
	for id in esperados.keys():
		_chk(registrados.has(id),
			"en la partida: %s" % esperados[id],
			"falta. Hay: %s" % str(registrados.keys()))

	# Lo que el usuario más nota: que ESC tenga algo que cerrar.
	var pausa: Object = _por_id(_demo, &"menu_pausa")
	if pausa != null:
		_chk(pausa.has_method("cerrar_panel") or pausa.has_method("cerrar"),
			"el MenuPausa responde al ESC", "")
		_chk(pausa.is_inside_tree(), "y cuelga del árbol de la partida", "")
		_chk(not pausa.get("visible"), "y nace cerrado (lección 11)", "")

	# Y que el pool de impactos exista de verdad, que sin él el bloque 68 fue
	# medio bloque.
	var pool: Object = _por_id(_demo, &"pool_impacto")
	if pool != null:
		_chk(bool(pool.call("is_inside_tree")), "el PoolImpacto cuelga del árbol", "")

	# Fase 72: los dos finales de partida tienen que estar EN LA PARTIDA y
	# SUSCRITOS al sistema, no solo registrados. El bug que esto previene es el
	# quinto de la serie: un sistema escrito, testeado y no conectado. Acá se
	# comprueba la suscripción mirando el resultado, que es lo único que no se
	# puede fingir: si el panel no está suscrito a la señal, `aperturas()` se
	# queda en 0 después de que el sistema declares la victoria.
	var res: Object = _por_id(_demo, &"resultado_partida")
	var pf: Object = _por_id(_demo, &"panel_final")
	var pd: Object = _por_id(_demo, &"panel_derrota")
	_chk(res != null, "el sistema de resultado de partida está en la partida", "")
	_chk(pf != null, "el PanelFinal está en la partida", "")
	_chk(pd != null, "el PanelDerrota está en la partida", "")
	if res != null and pf != null and pd != null:
		_chk(not pf.get("visible"), "el PanelFinal nace cerrado (lección 11)", "")
		_chk(not pd.get("visible"), "el PanelDerrota nace cerrado (lección 11)", "")
		_chk(int(pf.get("process_mode")) == int(Node.PROCESS_MODE_ALWAYS),
			"el PanelFinal corre con el árbol pausado",
			"process_mode=%d" % int(pf.get("process_mode")))
		_chk(int(pd.get("process_mode")) == int(Node.PROCESS_MODE_ALWAYS),
			"el PanelDerrota corre con el árbol pausado",
			"process_mode=%d" % int(pd.get("process_mode")))
		# La suscripción DE VERDAD: se fuerza una victoria por la API que el
		# juego no usa (los tests la usan para no entregar 5 actos) y se mira
		# que el panel se haya abierto. Un panel registrado pero no suscrito
		# deja `aperturas()` en 0, que es exactamente el fallo.
		var antes: int = int(pf.call("aperturas"))
		res.call("forzar_victoria", "liberty")
		_chk(int(pf.call("aperturas")) == antes + 1,
			"el PanelFinal se abre cuando el sistema declara la victoria",
			"aperturas %d -> %d" % [antes, int(pf.call("aperturas"))])
		_chk(bool(pf.get("visible")), "y queda visible", "")
		pf.call("cerrar")
		_chk(not bool(pf.get("visible")), "y cerrar() lo esconde", "")
		# Y que el NG+ no se ofrezca con un nivel de por medio.
		_chk(not pf.call("ngplus_disponible"),
			"el NG+ no se ofrece en una partida recien empezada", "")

	print("[SMOKE] sistemas registrados en la partida: %d" % registrados.size())

	# El tercer aviso de esta sesion fue un panel escrito, testeado y no
	# cableado. Este chequeo ata la banda: si el Input Map declara una accion
	# "abrir_*" y en la partida no hay ningun sistema con ese nombre, algo se
	# escribio y no se conecto.
	var cfg := ConfigFile.new()
	var err := cfg.load("res://project.godot")
	if err == OK:
		for accion in cfg.get_section_keys("input"):
			var nom := String(accion)
			if not nom.begins_with("abrir_") and not nom.ends_with("_panel"):
				continue
			var base := nom.trim_prefix("abrir_")
			# Se busca un NODO en la escena, no un registro en `Systems`: los 13
			# paneles viejos funcionan sin registrarse en el contenedor, y
			# preguntar por el contenedor daba falsos negativos en todos.
			var hay: bool = false
			for nd in _todos(_demo):
				if String(nd.name).to_lower().find(base) >= 0:
					hay = true
					break
			_chk(hay, "la accion '%s' tiene su panel en la partida" % nom,
				"ningun sistema registrado contiene '%s'. Hay: %s" % [base, str(registrados.keys())])


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


## El sistema con esa `system_id`. Primero por el CONTENEDOR y después por los
## nodos: `ResultadoPartida` (fase 72) es un `RefCounted` y no cuelga del
## árbol, así que una búsqueda solo por nodos lo declararía ausente de la
## partida estando registrado — el mismo falso negativo que ya corrigió
## `_ids_registrados` en este archivo.
func _por_id(n: Node, id: StringName) -> Object:
	var cont: Systems = _contenedor(n)
	if cont != null:
		var por_id: Variant = cont.obtener(id)
		if por_id != null and is_instance_valid(por_id):
			return por_id
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
