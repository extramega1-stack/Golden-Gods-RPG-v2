extends SceneTree
## Tests headless de la Fase 46 (manual de ayuda).
##
## (a) La acción `abrir_ayuda` existe en el Input Map y está en una tecla
##     libre (la de "/" y "?", 47).
## (b) `MecanicasDB`: el JSON es válido, con secciones y entradas con texto.
## (c) El panel arranca oculto, es un CanvasLayer en la capa 32 y tiene dos
##     pestañas (Controles y Mecánicas).
## (d) CONTROLES: se generan del Input Map (no de un JSON): toda acción del
##     juego con tecla aparece, ninguna acción interna `ui_*` aparece, y las
##     teclas coinciden con las del Input Map.
## (e) MECÁNICAS: salen las 9 secciones del JSON, en orden, con su título.
## (f) Abrir/cerrar: `mostrar_manual`, `cerrar_panel`, `alternar` y la tecla.
## (g) La UI no toca nada: ni stats, ni inventario, ni oro (solo lee).

const PA: GDScript = preload("res://scripts/ui/panel_ayuda.gd")
const MDB: GDScript = preload("res://scripts/ui/mecanicas_db.gd")

const CAPA_AYUDA: int = 32

var _ok: int = 0
var _fallos: int = 0
var _f: int = 0
var _hecho: bool = false
var _panel: PanelAyuda = null


func _init() -> void:
	ItemDB.cargar()
	MecanicasDB.cargar()


func _process(_d: float) -> bool:
	if _hecho:
		return false
	_f += 1
	if _f < 2:
		return false
	_hecho = true
	_test_accion()
	_test_datos()
	_panel = PA.new()
	_panel.name = "PanelAyudaTest"
	_panel.abrir_al_arrancar = false
	root.add_child(_panel)
	_test_panel()
	_test_controles()
	_test_mecanicas()
	_test_teclas()
	_test_solo_lectura()
	print("[TEST] fase46_ayuda: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] " + nombre + ("" if detalle == "" else "  <-- " + detalle))


## (a) La acción y su tecla.
func _test_accion() -> void:
	_chk(InputMap.has_action("abrir_ayuda"), "a: la acción abrir_ayuda existe")
	var teclas: Array[String] = _panel_teclas("abrir_ayuda")
	_chk(teclas.size() == 1, "a: tiene una sola tecla", str(teclas))
	# El motor llama "Slash" a la tecla 47: sirve / y también ? (con Shift).
	_chk(teclas.size() > 0 and teclas[0] == "Slash",
		"a: está en la tecla de / y ? (47)", str(teclas))
	# La tecla no puede estar usada por otra acción del juego.
	for a in InputMap.get_actions():
		var accion: String = str(a)
		if accion == "abrir_ayuda" or accion.begins_with("ui_"):
			continue
		var otras: Array[String] = _panel_teclas(accion)
		_chk(not otras.has("Slash"), "a: / no choca con " + accion, str(otras))


func _panel_teclas(accion: String) -> Array[String]:
	var res: Array[String] = []
	for e in InputMap.action_get_events(accion):
		if e is InputEventKey:
			res.append(OS.get_keycode_string((e as InputEventKey).physical_keycode))
	return res


## (b) Los datos.
func _test_datos() -> void:
	var secs: Array[Dictionary] = MecanicasDB.secciones()
	_chk(secs.size() == 9, "b: 9 secciones de mecánicas", "hay %d" % secs.size())
	_chk(MecanicasDB.total_entradas() >= 20,
		"b: al menos 20 entradas", str(MecanicasDB.total_entradas()))
	var con_texto: int = 0
	var con_titulo: int = 0
	for s in secs:
		if str(s.get("titulo", "")) != "":
			con_titulo += 1
		for e in (s.get("entradas", []) as Array):
			if str((e as Dictionary).get("texto", "")) != "":
				con_texto += 1
	_chk(con_titulo == secs.size(), "b: todas las secciones tienen título")
	_chk(con_texto >= 20, "b: todas las entradas tienen texto", "con texto=%d" % con_texto)


## (c) El panel.
func _test_panel() -> void:
	_chk(_panel is CanvasLayer, "c: es un CanvasLayer")
	_chk(_panel.layer == CAPA_AYUDA, "c: va en la capa 32 (paneles de sistema)",
		"capa=%d" % _panel.layer)
	_chk(_panel.visible == false, "c: arranca oculto (lección 11)")
	_chk(not _panel.esta_abierta(), "c: esta_abierta() = false al inicio")
	var pestanas: TabContainer = _panel.get_node("Raiz/Panel/Caja/Pestanas") as TabContainer
	_chk(pestanas != null, "c: tiene las dos pestañas")
	_chk(pestanas.get_tab_count() == 2, "c: dos pestañas",
		"hay %d" % pestanas.get_tab_count())
	_chk(pestanas.get_tab_title(0) == "Controles", "c: la primera es Controles")
	_chk(pestanas.get_tab_title(1) == "Mecánicas", "c: la segunda es Mecánicas")


## (d) La columna de controles sale del Input Map.
func _test_controles() -> void:
	var lista: Array[Dictionary] = _panel.lista_controles()
	_chk(lista.size() >= 28, "d: al menos 28 acciones con tecla", "hay %d" % lista.size())
	var nombres: Dictionary = {}
	for c in lista:
		nombres[str(c.get("accion", ""))] = true
		_chk(str(c.get("etiqueta", "")) != "", "d: " + str(c.get("accion")) + " tiene etiqueta")
	_chk(not nombres.has("ui_accept"), "d: no salen las acciones internas de Godot")
	# Toda acción del juego con tecla tiene que estar en la lista.
	for a in InputMap.get_actions():
		var accion: String = str(a)
		if accion.begins_with("ui_") or _panel_teclas(accion).is_empty():
			continue
		_chk(nombres.has(accion), "d: " + accion + " aparece en el manual")
	# Las teclas del manual coinciden con las del motor.
	var w: Dictionary = {}
	for c in lista:
		if str(c.get("accion", "")) == "mover_adelante":
			w = c
	_chk((w.get("teclas", []) as Array).has("W"), "d: WASD sale del Input Map",
		str(w.get("teclas", [])))
	# Ordenadas por tecla (para encontrar de un vistazo).
	var anterior: String = ""
	for c in lista:
		var t: String = str((c.get("teclas", []) as Array)[0])
		_chk(t >= anterior, "d: ordenadas por tecla (%s tras %s)" % [t, anterior])
		anterior = t
	_chk(_panel.controles_visibles() == lista.size(),
		"d: la pestaña dibuja una fila por control",
		"%d filas vs %d acciones" % [_panel.controles_visibles(), lista.size()])


## (e) La pestaña de mecánicas.
func _test_mecanicas() -> void:
	_chk(_panel.secciones_visibles() == MecanicasDB.secciones().size(),
		"e: una sección por entrada del JSON")
	var textos: String = ""
	var caja: VBoxContainer = _panel.get_node(
		"Raiz/Panel/Caja/Pestanas/Mecánicas") as VBoxContainer
	for c in caja.get_children():
		textos += _texto_de(c)
	_chk(textos.contains("PRIMEROS PASOS"), "e: sale la sección de primeros pasos")
	_chk(textos.contains("MINER"), "e: sale la sección de minería/herrería")
	_chk(textos.contains("MOVIMIENTO"), "e: sale la de movimiento")


func _texto_de(n: Node) -> String:
	var s: String = ""
	if n is Label:
		return (n as Label).text
	for c in n.get_children():
		s += _texto_de(c)
	return s


## (f) Abrir y cerrar.
func _test_teclas() -> void:
	_panel.mostrar_manual()
	_chk(_panel.esta_abierta(), "f: mostrar_manual() la abre")
	_panel.cerrar_panel()
	_chk(not _panel.esta_abierta(), "f: cerrar_panel() la cierra")
	_panel.alternar()
	_chk(_panel.esta_abierta(), "f: alternar() la abre")
	_panel.alternar()
	_chk(not _panel.esta_abierta(), "f: alternar() la cierra")
	# La tecla ? la abre (evento real, no llamada directa).
	_panel.mostrar_manual()
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "abrir_ayuda"
	ev.pressed = true
	_panel._unhandled_input(ev)
	_chk(not _panel.esta_abierta(), "f: la tecla ? la cierra")
	_panel._unhandled_input(ev)
	_chk(_panel.esta_abierta(), "f: y la vuelve a abrir")
	# ESC también la cierra.
	var esc: InputEventAction = InputEventAction.new()
	esc.action = "cancelar_seleccion"
	esc.pressed = true
	_panel._unhandled_input(esc)
	_chk(not _panel.esta_abierta(), "f: ESC la cierra")
	# Y con el panel CERRADO la misma tecla lo abre: es como se entra al
	# manual en el juego. Un CanvasLayer oculto sigue recibiendo
	# _unhandled_input, que es justo lo que lo hace posible.
	_panel._unhandled_input(ev)
	_chk(_panel.esta_abierta(), "f: cerrada, la tecla ? la abre (así se entra en el juego)")
	# Y ESC con el panel cerrado no hace nada (no cierra lo que no está abierto).
	_panel.cerrar_panel()
	_panel._unhandled_input(esc)
	_chk(not _panel.esta_abierta(), "f: ESC con el panel cerrado no hace nada")


## (g) La UI solo lee: el panel no toca el juego.
func _test_solo_lectura() -> void:
	var p: Player = preload("res://scripts/player/player.gd").new()
	p.fijar_identidad("H", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	var oro0: int = p.oro
	var atk0: float = p.stats.ataque
	var slots0: int = p.inventario.slots_usados()
	_panel.mostrar_manual()
	_panel.mostrar_manual()
	_panel.cerrar_panel()
	_chk(p.oro == oro0, "g: no toca el oro")
	_chk(is_equal_approx(p.stats.ataque, atk0), "g: no toca los stats")
	_chk(p.inventario.slots_usados() == slots0, "g: no toca el inventario")
	_chk(p.inventario.slots_usados() == 0, "g: el inventario sigue vacío")
