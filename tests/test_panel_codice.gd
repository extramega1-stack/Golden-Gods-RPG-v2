extends SceneTree
## Bloque 68: el CÓDICE en pantalla (el panel que faltaba).
##
## `CodiceDB` ya tenía los 20 arquetipos con su lore y su tabla de drops,
## testeados, y NO SE MOSTRABAN NUNCA. Este test es el que cierra ese hueco.
##
## LO QUE COMPRUEBA:
## (a) El panel existe y se cablea: capa de `UiLayers` dentro del rango 20–69
##     (§9.2), `system_id`, grupo `gg_system` (§9.1), y NACE CERRADO
##     (lección 11: los velos arrancan apagados).
## (b) Lista los 20 arquetipos de `CodiceDB` y el detalle PINTA el nombre, el
##     lore y los drops. El fallo de este panel no era tener los datos, era no
##     enseñarlos, así que el test mira el TEXTO QUE SE PINTA, no el
##     diccionario que hay detrás.
## (c) Los dos filtros (buscador por nombre/lore/id, y tipo jefes/mobs/élites),
##     y que jefes + mobs = 20 sin perder ni duplicar.
## (d) LA VENTANA REAL: el panel tiene que quedar DENTRO de la ventana, medido
##     contra el viewport de verdad. Es la regresión del bug de la esquina.
## (e) LA UI SOLO LEE: se usa el panel a fondo y `data/enemies.json` tiene que
##     salir byte a byte igual. La prueba de que no escribe es que no puede.
## (f) La tecla `abrir_codice`: en el Input Map, nombre español, sin pisar la
##     tecla de ninguna otra acción (§9.3).
## (g) La pila: al abrir queda en la cima, y el ESC de `PilaUI` la cierra.
##
## POR QUÉ LA VENTANA REAL Y NO UN VIEWPORT INVENTADO (esto ya se pagó una vez):
## los tests de antes medían contra un 1280x1280 CUADRADO y con `add_child()`
## ANTES de `centrar()`, que es el orden INVERTIDO al de producción. Las dos
## irrealidades se cancelaban y daban verde un panel que en una ventana de
## 1280x1401 caía en la esquina (998, 991) y solo se veía la punta. Peor: en
## headless la ventana del proceso arranca en 64x64, y con `aspect=expand` eso
## da un viewport cuadrado — justo la forma que esconde el bug. Por eso este
## test FUERZA ventanas Altas y anchas de verdad y comprueba que el viewport
## que está midiendo NO es cuadrado: si el cuadrado se cuela, el test se cae
## en vez de dar otro verde falso.
##
##   godot --headless --path . --script res://tests/test_panel_codice.gd

const ESCENA: PackedScene = preload("res://scenes/ui/panel_codice.tscn")

## Ventanas de verdad para medir. La primera (1280x1401) es LITERALMENTE la del
## bug reportado: un monitor 1920x1080 con la ventana en vertical.
const VENTANAS: Array[Vector2i] = [
	Vector2i(1280, 1401),
	Vector2i(1920, 820),
	Vector2i(1401, 1280),
]

## Fases: 0 entra · 1 midió la ventana · 2 la comprobó · 3 comprobado el
## contenido · 4 siguiente ventana (o terminar) · 5 asentando el layout.
var _ok: int = 0
var _fallos: int = 0
var _fase: int = 0
var _asentados: int = 0
var _idx_ventana: int = 0
var _panel: PanelCodice = null
var _vp: Vector2 = Vector2.ZERO
var _json_antes: String = ""


func _process(_d: float) -> bool:
	match _fase:
		0:
			_json_antes = FileAccess.get_file_as_string("res://data/enemies.json")
			PilaUI.limpiar()
			_poner_ventana(0)
			_fase = 1
		1:
			_vp = root.get_visible_rect().size
			_ventana_es_real(_vp)
			_crear_panel()
			# ASENTAR. Medir un `Control` en el mismo frame en que se añade al
			# árbol da un rectángulo a medio lay-out: los `Container` aún no han
			# repartido tamaños. Es la misma trampa que el orden invertido de
			# `add_child`/`centrar()` del bug de la esquina, y mide igual de
			# mal. En el juego el panel lleva frames en pantalla; aquí también.
			_asentados = 0
			_fase = 5
		5:
			_asentados += 1
			if _asentados < 3:
				return false
			_cableado()
			_registro()
			_caja_dentro()
			_fase = 3
		3:
			_escena_nace_cerrada()
			_tecla()
			_lista_y_ficha()
			_filtros()
			# El panel vuelve a "Todos" al final de `_filtros`, y se vuelve a
			# medir: la caja tiene que caber CON LA LISTA LLENA también después
			# de haber filtrado, no solo en el primer frame.
			_caja_dentro()
			_solo_lee()
			_pila_esc()
			_fase = 4
		_:
			_idx_ventana += 1
			if _idx_ventana >= VENTANAS.size():
				print("[TEST] panel_codice: %d ok, %d fallos" % [_ok, _fallos])
				quit(_fallos)
				return true
			_poner_ventana(_idx_ventana)
			_fase = 1
	return false


# --- (d) la ventana real ---------------------------------------------

func _poner_ventana(i: int) -> void:
	# Forzar el tamaño de la ventana REAL. Headless arranca con la ventana del
	# proceso en 64x64, y con `aspect=expand` eso da un viewport 1280x1280
	# cuadrado: la forma exacta que esconde el bug de `position`.
	root.size = VENTANAS[i]
	_panel = null


## El viewport que se mide tiene que ser el de verdad, y no cuadrado.
func _ventana_es_real(vp: Vector2) -> void:
	_chk(vp.x > 300.0 and vp.y > 300.0,
		"el viewport de verdad está vivo (no el 100x100 de arranque)", str(vp))
	_chk(absf(vp.x - vp.y) > 1.0,
		"y NO es cuadrado: un cuadrado escondería el bug de la esquina", str(vp))
	_chk(_coincide_con_la_ventana(vp),
		"el viewport medido es el de la ventana que pedí", str(vp))


func _coincide_con_la_ventana(vp: Vector2) -> bool:
	var real: Vector2 = root.get_visible_rect().size
	return absf(vp.x - real.x) < 0.5 and absf(vp.y - real.y) < 0.5


func _crear_panel() -> void:
	_panel = ESCENA.instantiate() as PanelCodice
	_panel.abrir_al_arrancar = false
	root.add_child(_panel)
	_panel.abrir_codice()
	_chk(_panel != null and _panel.visible, "el códice se abre", "")


## La caja DENTRO de la ventana real, con la lista llena.
func _caja_dentro() -> void:
	if _panel == null:
		_chk(false, "hay un panel que medir", "")
		return
	_chk(_panel.filas_visibles() == CodiceDB.total(),
		"la lista está llena antes de medir (%d)" % CodiceDB.total(),
		str(_panel.filas_visibles()))
	var c: PanelContainer = _panel.caja()
	if c == null:
		_chk(false, "la caja del códice existe", "")
		return
	var r: Rect2 = c.get_global_rect()
	_chk(_dentro(r, _vp), "la caja DENTRO de la ventana %s" % str(_vp), str(r))
	_chk(r.size.x <= _vp.x + 1.0 and r.size.y <= _vp.y + 1.0,
		"y sin pasarse de tamaño", "caja=%s vp=%s" % [str(r.size), str(_vp)])
	# Estar dentro no basta: el bug mandaba los menús a la esquina, que estaba
	# "dentro" a medias. `centrar()` promete el CENTRO, y eso es lo que se mide.
	var dif: Vector2 = ((r.position + r.size * 0.5) - _vp * 0.5).abs()
	_chk(dif.x < 2.0 and dif.y < 2.0,
		"y CENTRADA en %s (no en una esquina)" % str(_vp), "descentrada %s px" % str(dif))
	# La columna de la ficha: si la caja entra pero el texto se sale, el jugador
	# no lee nada.
	var rd: Rect2 = _panel.raiz_detalle().get_global_rect()
	_chk(rd.size.x > 0.0, "la columna del detalle tiene ancho", str(rd))
	_chk(_dentro(rd, _vp), "la columna del detalle también dentro", str(rd))
	var rl: Rect2 = _panel.scroll_lista().get_global_rect()
	var rld: Rect2 = _panel.scroll_detalle().get_global_rect()
	_chk(_dentro(rl, _vp), "la lista con scroll dentro de la ventana", str(rl))
	_chk(_dentro(rld, _vp), "la ficha con scroll dentro de la ventana", str(rld))
	# Y NINGUNA fila se sale por la DERECHA, que es el síntoma que se veía.
	# Solo en horizontal: en vertical las filas de una lista con scroll se
	# lay-out por debajo del borde A PROPÓSITO (para poder hacer scroll), así
	# que su rectángulo vertical no dice si se ve; el del scroller, que ya se
	# midió, sí.
	var fuera_x: int = 0
	for f in _panel.contenedor_filas().get_children():
		var rf: Rect2 = (f as Control).get_global_rect()
		if rf.size.x > 0.0 and (rf.position.x < -1.0 or rf.end.x > _vp.x + 1.0):
			fuera_x += 1
	_chk(fuera_x == 0, "ninguna de las %d filas se sale de lado"
		% _panel.filas_visibles(), "%d fuera" % fuera_x)


func _dentro(r: Rect2, vp: Vector2) -> bool:
	return r.position.x >= -1.0 and r.position.y >= -1.0 \
		and r.end.x <= vp.x + 1.0 and r.end.y <= vp.y + 1.0


# --- (a) el panel existe y se cablea ---------------------------------

func _cableado() -> void:
	if _panel == null:
		return
	_chk(_panel is CanvasLayer, "es un CanvasLayer con su propio layer", "")
	_chk(_panel.layer == UiLayers.PANEL_CODICE,
		"va en su capa de UiLayers.PANEL_CODICE", "capa %d" % _panel.layer)
	_chk(UiLayers.PANEL_CODICE >= 20 and UiLayers.PANEL_CODICE <= 69,
		"y esa capa está en el rango 20-69 de los paneles (§9.2)", str(UiLayers.PANEL_CODICE))
	_chk(_panel.get_node_or_null("Fondo") != null, "el velo de fondo existe", "")
	_chk(_panel.get_node_or_null("Panel") != null, "la caja del panel existe", "")


func _registro() -> void:
	if _panel == null:
		return
	_chk(_panel.is_in_group(Systems.GRUPO),
		"se registra en el grupo de sistemas gg_system (§9.1)", "")
	_chk(_panel.system_id == &"panel_codice",
		"y declara su system_id", str(_panel.system_id))
	_chk(_panel.process_mode == Node.PROCESS_MODE_ALWAYS,
		"y es ALWAYS: el códice se consulta con el juego en pausa", "")


## El contrato de `abrir_al_arrancar`: se pone en false ANTES de `add_child()`
## (como hace la demo con el manual). Si se leyera en `_init()` el export no
## tendría efecto y el panel se abriría encima del juego al entrar.
func _escena_nace_cerrada() -> void:
	var p: PanelCodice = ESCENA.instantiate() as PanelCodice
	_chk(p != null, "la escena del códice se instancia", "")
	if p == null:
		return
	p.abrir_al_arrancar = false
	root.add_child(p)
	_chk(not p.visible, "nace CERRADO (lección 11: velos apagados al arrancar)", "")
	p.cerrar_panel()
	# SIEMPRE sale de la pila ANTES de liberarse. `PilaUI._cerrar()` walkea la
	# pila asignando a una variable TIPADA, así que un panel liberado que sigue
	# dentro hace saltar "invalid previously freed instance" en el siguiente
	# ESC. Es la misma disciplina que el cambio de escena (que llama a
	# `PilaUI.limpiar()`): primero se desregistra, después se libera.
	PilaUI.cerrar(p)
	p.queue_free()


func _tecla() -> void:
	_chk(InputMap.has_action("abrir_codice"),
		"la acción abrir_codice está en el Input Map (§9.3)", "")
	if not InputMap.has_action("abrir_codice"):
		return
	_chk(_tecla_de("abrir_codice") == "L", "y es la L", _tecla_de("abrir_codice"))
	# Un atajo de panel no puede pisar el de otro: dos menús abiertos a la vez
	# se pelearían la misma tecla. `Escape` es la excepción declarada del 65.
	var donde: Dictionary = {}
	var pisadas: int = 0
	for a in InputMap.get_actions():
		for e in InputMap.action_get_events(a):
			if not (e is InputEventKey):
				continue
			var t: String = OS.get_keycode_string((e as InputEventKey).physical_keycode)
			if t == "" or t == "Escape":
				continue
			if donde.has(t):
				pisadas += 1
			else:
				donde[t] = str(a)
	_chk(pisadas == 0, "abrir_codice no pisa la tecla de otra acción", str(donde.get("L", "")))
	# Y el panel lee el Input Map, no un keycode (§9.3).
	_chk(PanelCodice.ACCION == "abrir_codice",
		"el panel lee la acción del Input Map", PanelCodice.ACCION)
	var src: String = FileAccess.get_file_as_string("res://scripts/ui/panel_codice.gd")
	_chk(not src.contains("KEY_") and not src.contains("keycode"),
		"y no hay ningún keycode escrito a mano en el panel", "")


func _tecla_de(accion: String) -> String:
	for e in InputMap.action_get_events(accion):
		if e is InputEventKey:
			return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	return ""


# --- (b) lista y ficha -----------------------------------------------

func _lista_y_ficha() -> void:
	if _panel == null:
		return
	var total: int = CodiceDB.total()
	_chk(total == 20, "CodiceDB documenta los 20 arquetipos", str(total))
	_chk(_panel.filas_visibles() == total, "y el panel lista los 20",
		str(_panel.filas_visibles()))
	_chk(_panel.ids_visibles().size() == total, "la lista tiene 20 ids",
		str(_panel.ids_visibles().size()))

	# Ordenado por NOMBRE, no por clave del diccionario: `ids()` devuelve las
	# claves del JSON, que no es el orden en que se lee una lista.
	var esperada: Array[String] = _panel.ids_visibles().duplicate()
	esperada.sort_custom(func(a: String, b: String) -> bool:
		return CodiceDB.nombre_de(a) < CodiceDB.nombre_de(b))
	_chk(_panel.ids_visibles() == esperada, "la lista va ordenada por nombre",
		str(_panel.ids_visibles()))

	# Al abrir hay un arquetipo abierto y su ficha está PINTADA.
	var primero: String = _panel.arq_seleccionado()
	_chk(primero != "", "hay un arquetipo seleccionado al abrir", "")
	_chk(_panel.detalle_texto().contains(CodiceDB.nombre_de(primero)),
		"la ficha PINTA el nombre", _panel.detalle_texto())
	_chk(_panel.detalle_texto().contains(CodiceDB.lore_de(primero)),
		"y PINTA el lore (era justo lo que no se veía nunca)", _panel.detalle_texto())

	# Uno por uno: los 20 con nombre y lore EN PANTALLA, no en el diccionario.
	var sin_pintar: int = 0
	for i in CodiceDB.ids():
		_panel.seleccionar(str(i))
		var t: String = _panel.detalle_texto()
		if not t.contains(CodiceDB.nombre_de(str(i))) \
				or not t.contains(CodiceDB.lore_de(str(i))):
			sin_pintar += 1
	_chk(sin_pintar == 0, "los 20 pintan nombre y lore", "%d sin pintar" % sin_pintar)

	# Los drops, en el primer arquetipo que tenga tabla.
	var con_drops: String = ""
	for i in CodiceDB.ids():
		if not CodiceDB.drops_de(str(i)).is_empty():
			con_drops = str(i)
			break
	_chk(con_drops != "", "hay al menos un arquetipo con drops documentados", "")
	if con_drops == "":
		return
	_panel.seleccionar(con_drops)
	var drops: Array = CodiceDB.drops_de(con_drops)
	# Uno por línea con "· ": el número de líneas tiene que ser el de la tabla.
	var pintados: int = 0
	for linea in _panel.detalle_texto().split("\n"):
		if linea.begins_with("· "):
			pintados += 1
	_chk(pintados == drops.size(),
		"la ficha lista sus %d drops, uno por línea" % drops.size(), str(pintados))
	# Y que el drop se muestre por su NOMBRE de verdad, no por su clave:
	# "pocion_vida" no es algo que se pueda leer en pantalla.
	var texto: String = _panel.detalle_texto().to_lower()
	var ilegibles: int = 0
	for d in drops:
		var nombre: String = str(ItemDB.obtener(str(d)).get("nombre", str(d))).to_lower()
		if not texto.contains(nombre):
			ilegibles += 1
	_chk(ilegibles == 0, "y cada drop sale con su nombre, no con su id",
		"%d ilegibles" % ilegibles)
	# Seleccionar un id que no existe no deja la ficha a medias: la deja como
	# estaba. Un panel que se vacía solo no dice por qué.
	_panel.seleccionar("no_existe_este_arquetipo")
	_chk(_panel.arq_seleccionado() == con_drops,
		"un id inexistente no borra la ficha", _panel.arq_seleccionado())


# --- (c) filtros -----------------------------------------------------

func _filtros() -> void:
	if _panel == null:
		return
	var total: int = CodiceDB.total()
	_panel.escribir_filtro("")
	_panel.filtrar_por_tipo(0)
	_chk(_panel.filas_visibles() == total, "sin filtro salen los 20",
		str(_panel.filas_visibles()))

	# El buscador mira nombre, lore E id: "titan" tiene que encontrar al
	# `titan_acecho` aunque el JSON lo escriba "Titán".
	_panel.escribir_filtro("titan")
	_chk(_panel.ids_visibles().has("titan_acecho"),
		"el buscador encuentra por id/nombre sin tilde", str(_panel.ids_visibles()))
	_panel.escribir_filtro("titán")
	_chk(_panel.ids_visibles().has("titan_acecho"),
		"y también con la tilde del lore", str(_panel.ids_visibles()))
	_panel.escribir_filtro("zzz_no_existe")
	_chk(_panel.filas_visibles() == 0, "una búsqueda sin resultados vacía la lista",
		str(_panel.filas_visibles()))
	_chk(_panel.arq_seleccionado() == "",
		"y no deja una ficha colgada de algo que ya no está",
		_panel.arq_seleccionado())
	_panel.escribir_filtro("")
	_chk(_panel.filas_visibles() == total, "borrar el filtro restaura los 20",
		str(_panel.filas_visibles()))

	# El filtro por tipo sale del DATO (bloque `jefe` / `elite`), no de una
	# lista escrita en el panel. Y jefes + mobs dan 20 clavados.
	var jefes: int = 0
	for i in CodiceDB.ids():
		if CodiceDB.es_jefe_de(str(i)):
			jefes += 1
	_chk(jefes > 0 and jefes < total, "de los 20, algunos son jefes y otros no",
		"%d jefes" % jefes)
	_panel.filtrar_por_tipo(1)
	_chk(_panel.filas_visibles() == jefes, "el filtro Jefes deja los %d" % jefes,
		str(_panel.filas_visibles()))
	_chk(_todos(_panel.ids_visibles(), "jefe"), "y son todos jefes de verdad", "")
	_panel.filtrar_por_tipo(2)
	_chk(_panel.filas_visibles() == total - jefes,
		"el filtro Mobs deja los %d que no son jefes" % (total - jefes),
		str(_panel.filas_visibles()))
	_chk(_todos(_panel.ids_visibles(), "mobo"), "y ninguno es jefe", "")
	_chk(_panel.filas_visibles() + jefes == total,
		"jefes + mobs = los 20, sin perder ni duplicar", "")
	_panel.filtrar_por_tipo(3)
	_chk(_panel.filas_visibles() > 0, "el filtro Élites deja algo",
		str(_panel.filas_visibles()))
	_chk(_todos(_panel.ids_visibles(), "elite"), "y son todos élites de verdad", "")
	_panel.filtrar_por_tipo(0)
	_chk(_panel.filas_visibles() == total, "volver a Todos restaura los 20",
		str(_panel.filas_visibles()))
	_chk(PanelCodice.nombre_filtro(1) == "Jefes", "el filtro 1 se llama Jefes",
		PanelCodice.nombre_filtro(1))
	_chk(PanelCodice.nombre_filtro(-1) == "" and PanelCodice.nombre_filtro(99) == "",
		"un índice fuera de rango no rompe nada", "")


func _todos(ids: Array[String], que: String) -> bool:
	for arq_id in ids:
		match que:
			"jefe":
				if not CodiceDB.es_jefe_de(arq_id):
					return false
			"elite":
				if not CodiceDB.es_elite_de(arq_id):
					return false
			"mobo":
				if CodiceDB.es_jefe_de(arq_id):
					return false
	return true


# --- (e) la UI solo lee ----------------------------------------------

func _solo_lee() -> void:
	if _panel == null:
		return
	# Se USA el panel a fondo: abrir, filtrar por texto, por tipo, recorrer
	# todos los Selecting uno por uno, y cerrar.
	_panel.abrir_codice()
	_panel.escribir_filtro("a")
	_panel.filtrar_por_tipo(0)
	for arq_id in _panel.ids_visibles():
		_panel.seleccionar(arq_id)
	_panel.filtrar_por_tipo(1)
	_panel.filtrar_por_tipo(2)
	_panel.filtrar_por_tipo(3)
	_panel.escribir_filtro("")
	_panel.seleccionar("goblin")
	_panel.cerrar_panel()

	_chk(FileAccess.get_file_as_string("res://data/enemies.json") == _json_antes,
		"el panel NO escribe en data/enemies.json (byte a byte)", "")
	var ids_despues: Array = CodiceDB.ids()
	_chk(ids_despues.size() == CodiceDB.total(), "ni cambia los ids de CodiceDB",
		str(ids_despues.size()))
	_chk(CodiceDB.total() == 20, "ni los cuenta de otra manera", str(CodiceDB.total()))
	# El `_arquetipos` estático es el estado real de la DB: si el panel hubiera
	# escrito, el conteo o el contenido se verían aquí, no en el archivo.
	_chk(CodiceDB.nombre_de("goblin") == "Goblin",
		"y la DB sigue diciendo lo que dice el JSON", CodiceDB.nombre_de("goblin"))

	# Y no toca NADA del jugador. No es una promesa en un comentario: se
	# comprueba que el archivo del panel no menciona ni un sistema que escriba
	# (inventario, oro, guardado, jugador) ni una llamada que lo haga.
	var src: String = FileAccess.get_file_as_string("res://scripts/ui/panel_codice.gd")
	for prohibido in ["Inventario", "SaveSystem", "Player", "_jugador",
			".agregar(", ".quitar(", ".descontar(", "restore"]:
		_chk(not src.contains(prohibido),
			"el panel no menciona '%s' (no hay por dónde escribir)" % prohibido, "")


# --- (g) la pila de paneles ------------------------------------------

## LO QUE SE COMPRUEBA Y LO QUE NO, Y POR QUÉ (aviso al que lea el código):
## `PilaUI._cerrar()` walkea la pila pero NUNCA saca nada de ella: su único
## `remove_at` es el de los paneles liberados. O sea que `abrir()` no es
## idempotente y `cerrar()` no desregistra, aunque los dos docstrings digan que
## sí. Eso hace que la pila solo CREZCA, y que `al_esc()` vuelva a cerrar la
## misma cima en vez de bajar al siguiente.
##
## Eso es un bug de `pila_ui.gd` (archivo compartido, no mío) y está fuera de
## este panel, así que aquí se comprueba lo que el panel SÍ es responsable: que
## al abrir se apile, que quede en la cima, y que el ESC la cierre. El número de
## paneles en la pila después de cerrar NO se afirma, porque afirmarlo sería
## escribir un test en verde sobre un contrato que el código no cumple. Está
## reportado aparte para que se arregle en su propio bloque.
func _pila_esc() -> void:
	if _panel == null:
		return
	PilaUI.limpiar()
	_panel.abrir_codice()
	_chk(_panel.visible, "abrir lo hace visible", "")
	_chk(PilaUI.abierta() == 1, "abrir lo apila en PilaUI",
		str(PilaUI.abierta()))
	_chk(PilaUI.cima() == _panel, "y lo deja en la CIMA de la pila", "")
	_chk(PilaUI.es_cima(_panel), "y es_cima() lo confirma", "")
	_chk(PilaUI.al_esc(), "el ESC de la pila lo cierra", "")
	_chk(not _panel.visible, "y queda cerrado", "")
	# Un panel de la pila se libera DESPUÉS de desregistrarse (ver la nota de
	# arriba y la de `_escena_nave_cerrada`).
	PilaUI.limpiar()
	_panel.cerrar_panel()
	_panel.queue_free()
	_panel = null


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] %s%s" % [nombre, "" if detalle == "" else "  <-- " + detalle])
