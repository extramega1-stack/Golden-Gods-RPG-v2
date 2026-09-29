class_name PanelCodice
extends CanvasLayer
## Bloque 68: el CÓDICE en pantalla. `CodiceDB` ya tenía los 20 arquetipos con su
## lore y su tabla de drops, testeados, y NO SE MOSTRABAN NUNCA.
##
## POR QUÉ ES BARATO Y VALE LA PENA: la información ya está en
## `data/enemies.json`. Este panel es, literalmente, un lector. Y da al jugador
## las dos cosas que en un RPG importan: saber a qué se está matando, y decidir
## dónde cazar por un drop concreto.
##
## UI QUE SOLO LEE (§7.11). Ni una línea de este archivo escribe en
## `CodiceDB`, en el jugador, en el inventario o en el oro. Los `item_id` que
## suelta un arquetipo se prettifican con `ItemDB`, que también es solo lectura;
## si un item no está en el catálogo sale el id crudo, nunca un hueco.
##
## EL ARREGLO DE LA POSICIÓN (bloque 67, bug encontrado JUGANDO): el panel se
## centra con `AjustaUI.centrar()` y NUNCA tocando `position`. Los ocho paneles
## viejosacentaban con `position` antes de `add_child()`, y en un nodo fuera del
## árbol eso se resuelve contra un padre de tamaño CERO: todos los menús caían en
## la esquina inferior derecha. `centrar()` ya usa offsets, que son relativos
## al ancla y no dependen del padre.
##
## La tecla es `abrir_codice` (L) en el Input Map, y el ESC lo lleva la PILA
## (`PilaUI`), no este archivo: así el orden de cierre entre paneles apilados es
## correcto.

const CAPA: int = UiLayers.PANEL_CODICE
## La acción del Input Map (§9.3: acciones en español, atajos en el mapa).
const ACCION: String = "abrir_codice"
## Fracción del viewport que ocupa, como los demás paneles de sistema.
const ANCHO_REL: float = 0.50
const ALTO_REL: float = 0.78
## Ancho mínimo de cada columna. Es un SUELO (ver `AjustaUI.cabe`): sin esto
## una ventana muy angosta parte las dos columnas en migas de texto.
const ANCHO_LISTA_MIN: float = 148.0
const ANCHO_DETALLE_MIN: float = 190.0

## §9.1
var system_id: StringName = &"panel_codice"

## Fila 0 = todos, 1 = solo jefes, 2 = solo mobs, 3 = solo élites. Los índices
## son los del `OptionButton`, y el dato de qué es qué lo decide `CodiceDB`
## (el bloque `jefe` / `elite` del arquetipo), no una lista en este archivo.
const FILTROS: Array[String] = ["Todos", "Jefes", "Mobs", "Élites"]

var _caja: PanelContainer = null
var _filas: VBoxContainer = null
var _detalle: VBoxContainer = null
var _contador: Label = null
var _buscador: LineEdit = null
var _selector: OptionButton = null
var _raiz_detalle: Control = null
var _scroll_lista: ScrollContainer = null
var _scroll_detalle: ScrollContainer = null

## Los ids que pasan el filtro, ya ordenados por nombre. Es el estado de la
## lista, y lo que pintan los tests.
var _visibles: Array[String] = []
## El arquetipo abierto en la columna de la derecha ("" = ninguno).
var _seleccion: String = ""
var _filtro: String = ""
var _filtro_tipo: int = 0

## Fase 68: si es true, el panel aparece al abrir la escena (así se puede
## correr solo con F6). El juego lo pone en false y lo abre con la tecla.
@export var abrir_al_arrancar: bool = true


func _init() -> void:
	layer = CAPA
	# ALWAYS: el códice se consulta con el juego en pausa, que es justo cuando
	# uno para para leer. Sin esto el árbol pausado se come el ratón.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir()
	# Lección 11: los velos arrancan cerrados. Nadie nace viendo el códice.
	visible = false
	_sincronizar_grupo()


## `abrir_al_arrancar` se lee AQUÍ y no en `_init()` a propósito: así quien lo
## instancia puede ponerlo en false ANTES de `add_child()`, que es como lo hace
## la demo con el manual de la 46. Si se leyera en `_init()` el export ya no
## tendría efecto y el panel aparecería al entrar al juego.
func _ready() -> void:
	# El panel se dimensiona al construirse, y una ventana que cambia de tamaño
	# después lo dejaba con el tamaño viejo. `size_changed` es un EVENTO, no un
	# bucle por frame: se reajusta al redimensionar y nunca entre frames.
	get_viewport().size_changed.connect(_reajustar)
	if abrir_al_arrancar:
		visible = true
		_rellenar()
		_pintar_detalle()


func _reajustar() -> void:
	if _caja == null:
		return
	# Los offsets otra vez, nunca `position`: es el bug de la esquina.
	AjustaUI.centrar(_caja, ANCHO_REL, ALTO_REL)


## §9.1: el panel se registra él mismo en el grupo de sistemas cuando se crea
## suelto (F6, o un test). Cuando lo registra `Systems.registrar` desde la demo
## la llamada es idempotente: `registrar` comprueba `is_in_group` antes de
## añadir, así que no hay doble entrada.
func _sincronizar_grupo() -> void:
	if not is_in_group(Systems.GRUPO):
		add_to_group(Systems.GRUPO)


func _construir() -> void:
	var fondo := ColorRect.new()
	fondo.name = "Fondo"
	fondo.color = Color(0.0, 0.0, 0.0, 0.55)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: es lo que hace que un clic detrás no llegue al mundo.
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fondo)

	_caja = PanelContainer.new()
	_caja.name = "Panel"
	_caja.add_theme_stylebox_override("panel", TemaFlyFF.marco())
	_caja.mouse_filter = Control.MOUSE_FILTER_STOP
	# ANTES de `add_child()`, como los demás paneles, y SIN `position`: es el
	# orden que dispara el bug de la esquina si `centrar()` usara `position`.
	AjustaUI.centrar(_caja, ANCHO_REL, ALTO_REL)
	add_child(_caja)

	var col := VBoxContainer.new()
	col.name = "Caja"
	col.add_theme_constant_override("separation", 6)
	_caja.add_child(col)

	col.add_child(_cabecera())
	col.add_child(_barra_filtro())

	var cuerpo := HBoxContainer.new()
	cuerpo.name = "Cuerpo"
	cuerpo.add_theme_constant_override("separation", 10)
	cuerpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(cuerpo)

	cuerpo.add_child(_columna_lista())
	cuerpo.add_child(_columna_detalle())

	col.add_child(TemaFlyFF.etiqueta(
		"L abre y cierra el códice · ESC cierra · sale de data/enemies.json",
		11, TemaFlyFF.APAGADO))


## Título, contador de arquetipos y botón de cerrar.
func _cabecera() -> Control:
	var caja := HBoxContainer.new()
	caja.name = "Cabecera"
	caja.add_theme_constant_override("separation", 10)
	var titulo: Label = TemaFlyFF.etiqueta("CÓDICE", 22, TemaFlyFF.DORADO_CLARO)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caja.add_child(titulo)
	_contador = TemaFlyFF.etiqueta("", 13, TemaFlyFF.APAGADO)
	caja.add_child(_contador)
	var cerrar := Button.new()
	cerrar.name = "Cerrar"
	cerrar.text = "Cerrar (ESC)"
	cerrar.focus_mode = Control.FOCUS_NONE
	cerrar.pressed.connect(cerrar_panel)
	caja.add_child(cerrar)
	return caja


## Buscador de texto y filtro por tipo. Los dos escriben en la MISMA lista.
func _barra_filtro() -> Control:
	var caja := HBoxContainer.new()
	caja.name = "Filtros"
	caja.add_theme_constant_override("separation", 6)
	caja.add_child(TemaFlyFF.etiqueta("Buscar", 13, TemaFlyFF.APAGADO))

	_buscador = LineEdit.new()
	_buscador.name = "Buscador"
	_buscador.placeholder_text = "nombre, lore o id…"
	_buscador.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buscador.custom_minimum_size = Vector2(140.0, 0.0)
	_buscador.text_changed.connect(_al_texto_cambiado)
	caja.add_child(_buscador)

	_selector = OptionButton.new()
	_selector.name = "Tipo"
	_selector.focus_mode = Control.FOCUS_NONE
	_selector.custom_minimum_size = Vector2(96.0, 0.0)
	for f in FILTROS:
		_selector.add_item(f)
	_selector.item_selected.connect(_al_tipo_cambiado)
	caja.add_child(_selector)
	return caja


## Columna izquierda: un botón por arquetipo que pasa el filtro.
func _columna_lista() -> Control:
	_scroll_lista = ScrollContainer.new()
	_scroll_lista.name = "ScrollLista"
	_scroll_lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_lista.size_flags_stretch_ratio = 0.40
	_scroll_lista.custom_minimum_size = Vector2(ANCHO_LISTA_MIN, 0.0)
	_scroll_lista.clip_contents = true
	_filas = VBoxContainer.new()
	_filas.name = "Filas"
	_filas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filas.add_theme_constant_override("separation", 2)
	_scroll_lista.add_child(_filas)
	return _scroll_lista


## Columna derecha: la ficha del arquetipo seleccionado.
func _columna_detalle() -> Control:
	var caja := VBoxContainer.new()
	caja.name = "Detalle"
	caja.add_theme_constant_override("separation", 4)
	caja.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caja.size_flags_stretch_ratio = 0.60
	caja.custom_minimum_size = Vector2(ANCHO_DETALLE_MIN, 0.0)
	_scroll_detalle = ScrollContainer.new()
	_scroll_detalle.name = "ScrollDetalle"
	_scroll_detalle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_detalle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_detalle.custom_minimum_size = Vector2(ANCHO_DETALLE_MIN, 0.0)
	_scroll_detalle.clip_contents = true
	caja.add_child(_scroll_detalle)
	_raiz_detalle = caja
	_detalle = VBoxContainer.new()
	_detalle.name = "Ficha"
	_detalle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detalle.add_theme_constant_override("separation", 4)
	_scroll_detalle.add_child(_detalle)
	return caja


# --- apertura y cierre (la pila lleva el ESC) ------------------------

## Abre el códice. Idempotente en el contenido: se vuelve a pintar para que un
## cambio en el JSON se vea sin reiniciar.
func abrir_codice() -> void:
	visible = true
	PilaUI.abrir(self)
	_rellenar()
	_pintar_detalle()


func cerrar_panel() -> void:
	visible = false
	PilaUI.cerrar(self)


func esta_abierta() -> bool:
	return visible


func alternar() -> void:
	if visible:
		cerrar_panel()
	else:
		abrir_codice()


## La tecla `L` abre y cierra. NO se comprueba `visible` para abrir: un
## `CanvasLayer` oculto sigue recibiendo `_unhandled_input` (es lo que hace el
## resto de paneles con su tecla), y con la guarda el códice no abriría nunca.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACCION):
		alternar()
		get_viewport().set_input_as_handled()
		return
	if visible and PilaUI.es_cima(self) \
			and event.is_action_pressed("cancelar_seleccion"):
		cerrar_panel()
		get_viewport().set_input_as_handled()


func _al_texto_cambiado(texto: String) -> void:
	_filtro = texto.strip_edges().to_lower()
	_rellenar()


func _al_tipo_cambiado(indice: int) -> void:
	_filtro_tipo = maxi(0, indice)
	_rellenar()


# --- la lista --------------------------------------------------------

## Recalcula la lista desde `CodiceDB` y la pinta. Es la ÚNICA fuente: el
## panel no guarda copia de ningún arquetipo, siempre relee.
func _rellenar() -> void:
	CodiceDB.cargar()
	_visibles.clear()
	for i in CodiceDB.ids():
		var arq_id: String = str(i)
		if _pasa_filtro(arq_id) and _pasa_tipo(arq_id):
			_visibles.append(arq_id)
	# Orden por nombre, no por clave del diccionario: `ids()` devuelve las
	# claves en el orden del JSON, que no es el que se lee.
	_visibles.sort_custom(func(a: String, b: String) -> bool:
		var na: String = CodiceDB.nombre_de(a)
		var nb: String = CodiceDB.nombre_de(b)
		if na == nb:
			return a < b
		return na < nb)
	_pintar_filas()
	_contador.text = "%d de %d arquetipos" % [_visibles.size(), CodiceDB.total()]
	# Si lo que estaba abierto ya no pasa el filtro, se cierra el detalle en
	# vez de dejar una ficha de algo que la lista no muestra.
	if not _visibles.has(_seleccion):
		_seleccion = _visibles[0] if not _visibles.is_empty() else ""


## El buscador mira nombre, lore E id: el jugador escribe "titán" y quiere el
## Titán, pero también escribe "titan" y quiere el que el JSON llama así.
func _pasa_filtro(arq_id: String) -> bool:
	if _filtro == "":
		return true
	return CodiceDB.nombre_de(arq_id).to_lower().contains(_filtro) \
		or CodiceDB.lore_de(arq_id).to_lower().contains(_filtro) \
		or arq_id.to_lower().contains(_filtro)


func _pasa_tipo(arq_id: String) -> bool:
	match _filtro_tipo:
		1: return CodiceDB.es_jefe_de(arq_id)
		2: return not CodiceDB.es_jefe_de(arq_id)
		3: return CodiceDB.es_elite_de(arq_id)
	return true


func _pintar_filas() -> void:
	for hijo in _filas.get_children():
		_filas.remove_child(hijo)
		hijo.queue_free()
	for arq_id in _visibles:
		_filas.add_child(_boton(arq_id))


func _boton(arq_id: String) -> Button:
	var b := Button.new()
	b.name = "Arq_%s" % arq_id
	b.text = CodiceDB.nombre_de(arq_id)
	b.tooltip_text = arq_id
	# `clip_text`: un nombre largo no ensancha la columna y, con ella, el panel
	# entero. Los nombres se cortan, no se desbordan.
	b.clip_text = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(_al_pulsar.bind(arq_id))
	return b


func _al_pulsar(arq_id: String) -> void:
	seleccionar(arq_id)


# --- la ficha --------------------------------------------------------

## Abre el detalle de un arquetipo. Idempotente y con guarda: un id que no
## existe en el JSON deja la ficha como estaba, en vez de dejarla a medias.
func seleccionar(arq_id: String) -> void:
	if arq_id != "" and not CodiceDB.existe(arq_id):
		return
	_seleccion = arq_id
	_pintar_detalle()


## Pinta la ficha del arquetipo seleccionado, con los datos TAL COMO VIENEN.
## Si el JSON no trae nivel o región, no se imprime un "nivel 0" inventado: se
## omite la línea. Un panel que rellena huecos con ceros miente.
func _pintar_detalle() -> void:
	for hijo in _detalle.get_children():
		_detalle.remove_child(hijo)
		hijo.queue_free()
	if _seleccion == "":
		_detalle.add_child(TemaFlyFF.etiqueta(
			"Elegí un arquetipo de la lista.", 14, TemaFlyFF.APAGADO))
		return

	var f: Dictionary = CodiceDB.ficha(_seleccion)
	var nombre: String = str(f.get("nombre", _seleccion))
	var etiquetas: PackedStringArray = PackedStringArray()
	if bool(f.get("jefe", false)):
		etiquetas.append("JEFE")
	if bool(f.get("elite", false)):
		etiquetas.append("élite")
	if not etiquetas.is_empty():
		_etiqueta_pill(" · ".join(etiquetas))
	_detalle.add_child(TemaFlyFF.etiqueta(nombre, 19, TemaFlyFF.DORADO))
	_detalle.add_child(TemaFlyFF.etiqueta(str(_seleccion), 11, TemaFlyFF.APAGADO))

	var nivel: int = int(f.get("nivel", 0))
	if nivel > 0:
		_detalle.add_child(TemaFlyFF.etiqueta("Nivel %d" % nivel, 13, TemaFlyFF.TEXTO))
	var region: String = str(f.get("region", ""))
	if region != "":
		_detalle.add_child(TemaFlyFF.etiqueta("Región: %s" % region, 13, TemaFlyFF.TEXTO))
	_detalle.add_child(HSeparator.new())

	var lore: Label = TemaFlyFF.etiqueta(str(f.get("lore", "")), 14, TemaFlyFF.TEXTO)
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detalle.add_child(lore)

	var drops: Array = f.get("drops", []) as Array
	_detalle.add_child(HSeparator.new())
	_detalle.add_child(TemaFlyFF.etiqueta(
		"Suelta" if not drops.is_empty() else "No documenta drops",
		14, TemaFlyFF.DORADO))
	for d in drops:
		_detalle.add_child(TemaFlyFF.etiqueta("· %s" % _nombre_item(str(d)), 13, TemaFlyFF.TEXTO))


## El `item_id` del loot es una clave, no algo que se pueda leer: "collar_cobre"
## se lee como "Collar Cobre". `ItemDB` (solo lectura) pone el nombre de verdad
## cuando el item existe; si no, el id se prettifica, porque un hueco se lee
## como un fallo y un id feo no.
func _nombre_item(item_id: String) -> String:
	var d: Dictionary = ItemDB.obtener(item_id)
	var nombre: String = str(d.get("nombre", ""))
	if nombre != "":
		return nombre
	var palabras: PackedStringArray = item_id.split("_", false)
	for i in range(palabras.size()):
		palabras[i] = palabras[i].capitalize()
	return " ".join(palabras)


## Una "píldora" para las marcas (JEFE / élite). Un recuadro, no un emoji: el
## texto del panel tiene que ser el del dato, no el del estilo.
func _etiqueta_pill(texto: String) -> Control:
	var p := PanelContainer.new()
	p.name = "Marca"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.35, 0.16, 0.05, 0.85)
	sb.border_color = TemaFlyFF.DORADO
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.add_child(TemaFlyFF.etiqueta(texto, 12, TemaFlyFF.DORADO_CLARO))
	return p


# --- para los tests --------------------------------------------------

## La caja centrada. El test de "cabe en la ventana" mide ESTA, no un
## `Control` inventado: es la que sale en pantalla.
func caja() -> PanelContainer:
	return _caja


func raiz_detalle() -> Control:
	return _raiz_detalle


## El `VBox` con un botón por arquetipo. El test de "nada se sale de la
## ventana" mide las filas, no una caja inventada.
func contenedor_filas() -> VBoxContainer:
	return _filas


## Los dos `ScrollContainer`, que son lo que hay que medir para saber que el
## panel no se sale: las filas de una lista con scroll se laid-out por debajo
## del borde (para poder hacer scroll), así que su rectángulo no dice si se
## ven; el del scroller sí.
func scroll_lista() -> ScrollContainer:
	return _scroll_lista


func scroll_detalle() -> ScrollContainer:
	return _scroll_detalle


## Cuántos arquetipos hay ahora mismo en la lista (ya filtrados).
func filas_visibles() -> int:
	if _filas == null:
		return 0
	var n: int = 0
	for h in _filas.get_children():
		if not h.is_queued_for_deletion():
			n += 1
	return n


## Los ids que pasan el filtro, en el orden en que se pintan.
func ids_visibles() -> Array[String]:
	return _visibles


func arq_seleccionado() -> String:
	return _seleccion


## El texto de la ficha, para comprobar que la info se PINTA y no solo existe
## en el diccionario.
func detalle_texto() -> String:
	var partes: Array[String] = []
	if _detalle == null:
		return ""
	for h in _detalle.get_children():
		var t: String = _texto_de(h)
		if t != "":
			partes.append(t)
	return "\n".join(partes)


func _texto_de(n: Node) -> String:
	if n is Label:
		return (n as Label).text
	if n is PanelContainer:
		for c in n.get_children():
			var t: String = _texto_de(c)
			if t != "":
				return t
	return ""


## El texto del buscador. Los tests escriben por acá en vez de tocar el
## `LineEdit`, que dispara `text_changed` y con eso prueban el camino real.
func escribir_filtro(texto: String) -> void:
	if _buscador == null:
		return
	_buscador.text = texto
	_al_texto_cambiado(texto)


## El filtro por tipo, por su ÍNDICE (0 todos, 1 jefes, 2 mobs, 3 élites).
func filtrar_por_tipo(indice: int) -> void:
	if _selector == null:
		return
	_al_tipo_cambiado(indice)


## El rótulo de un filtro. Para comprobar que el `OptionButton` y la lógica
## hablan el mismo idioma.
static func nombre_filtro(indice: int) -> String:
	if indice < 0 or indice >= FILTROS.size():
		return ""
	return FILTROS[indice]
