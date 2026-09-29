class_name PanelConstruccion
extends CanvasLayer
## Fase 64: el modo construcción del Refugio (la UI de la Fase 61).
##
## POR QUÉ EXISTE: `Constructor` de la 61 es lógica pura y está testeada, pero
## no había nada que la llamara. Este panel es lo que la hace jugable: catálogo,
## preview fantasma, rotación, colocación, deshacer.
##
## LO QUE NO ES, A PROPÓSITO: un editor de construcción libre. No hay terreno
## (las piezas van sobre la rejilla de 2 u de `Constructor`), ni rotación
## continua, ni preview de colisión. Es un sistema acotado que no se come la
## VRAM, que es la restricción que puso la 61 y que sigue valiendo.
##
## - Capas: este panel va en `UiLayers.PANEL_CONSTRUCCION` (33) y el fantasma
##   3D vive en el mundo, no en la UI.
## - UI que solo LEE: valida con `Constructor.puede_colocar` (que es donde
##   está la regla, con sus tests) y escribe por `Refugio.colocar` y
##   `Constructor.descontar`.
## - El material se descuenta ANTES de instanciar, igual que el presupuesto de
##   piezas: si el item no estuviera en el catálogo, el golpe se pierde pero el
##   inventario nunca queda con materiales que no salieron de ahí.

const CAPA: int = UiLayers.PANEL_CONSTRUCCION
## Cuánto mira el raycast desde la cámara paracolocar el la pieza.
const ALCANCE_RAYO: float = 1000.0
## Capas contra las que se busca el suelo para el preview.
const CAPA_SUELO: int = 1

## §9.1
var system_id: StringName = &"panel_construccion"

var _jugador: Player = null
var _refugio: Refugio = null
var _tipo: String = ""
var _rot: float = 0.0
var _fantasma: PiezaVisual = null
var _visuales: Array = []

var _caja: VBoxContainer = null
var _filas: VBoxContainer = null
var _presupuesto: Label = null
var _ayuda: Label = null


func _init() -> void:
	layer = CAPA
	_construir()
	visible = false


func _construir() -> void:
	var fondo := PanelContainer.new()
	fondo.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fondo.size = Vector2(300.0, 430.0)
	fondo.position = Vector2(16.0, 120.0)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.add_theme_constant_override("margin_left", 12)
	margen.add_theme_constant_override("margin_right", 12)
	margen.add_theme_constant_override("margin_top", 10)
	margen.add_theme_constant_override("margin_bottom", 10)
	fondo.add_child(margen)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	margen.add_child(caja)
	_caja = caja

	var titulo := Label.new()
	titulo.text = "Construir refugio"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 18)
	titulo.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	caja.add_child(titulo)

	_presupuesto = Label.new()
	_presupuesto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_presupuesto.add_theme_font_size_override("font_size", 13)
	caja.add_child(_presupuesto)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(scroll)
	_filas = VBoxContainer.new()
	_filas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filas.add_theme_constant_override("separation", 5)
	scroll.add_child(_filas)

	_ayuda = Label.new()
	_ayuda.text = "R rota · clic coloca · Supr quita la última"
	_ayuda.add_theme_font_size_override("font_size", 11)
	_ayuda.add_theme_color_override("font_color", Color(0.65, 0.65, 0.6))
	_ayuda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(_ayuda)

	var cerrar := Button.new()
	cerrar.text = "Salir (ESC)"
	cerrar.pressed.connect(cerrar_panel)
	caja.add_child(cerrar)


## Abre el modo construcción sobre un refugio RECLAMADO. Un refugio sin reclamar
## no tiene presupuesto de piezas, así que no tiene sentido abrirlo.
func abrir(j: Player, r: Refugio) -> bool:
	if j == null or not is_instance_valid(j):
		return false
	if r == null or not is_instance_valid(r) or not r.esta_reclamado():
		return false
	_jugador = j
	_refugio = r
	visible = true
	_tipo = ""
	_rot = 0.0
	_reconstruir_visuales()
	_crear_fantasma()
	return true


func cerrar_panel() -> void:
	visible = false
	_tipo = ""
	_jugador = null
	_refugio = null
	_destruir_fantasma()
	for v in _visuales:
		var n: Node = v as Node
		if n != null and is_instance_valid(n):
			n.queue_free()
	_visuales.clear()


func esta_abierta() -> bool:
	return visible


## Selecciona el tipo de pieza a colocar. Vacío deselecciona.
func seleccionar(tipo: String) -> void:
	if tipo != "" and not PiezasDB.existe(tipo):
		return
	_tipo = tipo
	# La rotación se ajusta a la pieza: si no se hace, quedarse mirando una
	# Antorcha (que no rota) con los 90 grados de la Mesa de antes la hace
	# INCLAZABLE, sin explicación en pantalla.
	if _tipo != "":
		var rs: Array[float] = Constructor.rotaciones(_tipo)
		var valida: bool = false
		for r in rs:
			if is_equal_approx(fposmod(r, 360.0), fposmod(_rot, 360.0)):
				valida = true
				break
		if not valida and not rs.is_empty():
			_rot = fposmod(rs[0], 360.0)
	_crear_fantasma()


## Empuja la rotación al siguiente ángulo que la pieza admita. Si la pieza no
## admite rotación, no hace nada: es el dato el que manda.
func rotar() -> void:
	if _tipo == "":
		return
	var rs: Array[float] = Constructor.rotaciones(_tipo)
	if rs.size() <= 1:
		return
	var i: int = 0
	for k in range(rs.size()):
		if is_equal_approx(fposmod(rs[k], 360.0), fposmod(_rot, 360.0)):
			i = (k + 1) % rs.size()
			break
	_rot = fposmod(rs[i], 360.0)
	_destruir_fantasma()
	_crear_fantasma()


## Coloca la pieza seleccionada en `pos` (que ya viene ajustada a la rejilla
## por quien llama, o se ajusta aquí). Devuelve el motivo del fallo.
func colocar_en(pos: Vector3) -> String:
	if _jugador == null or _refugio == null or _tipo == "":
		return "nada"
	var piezas: Array = _refugio.piezas_lista()
	if not Constructor.puede_colocar(_refugio, _tipo, pos, _rot, piezas):
		return "no_puede"
	var antes: Dictionary = _inventario_plano()
	if not Constructor.tiene_materiales(_tipo, antes):
		return "sin_materiales"
	# `descontar` muta el diccionario que se le pasa, que es una COPIA. Sin
	# volcar el diff al `Inventario` real, los materiales se gastaban en un
	# diccionario que se tiraba a la basura: las piezas salian gratis.
	var copia: Dictionary = antes.duplicate(true)
	if not bool(Constructor.descontar(_tipo, copia).get("ok", false)):
		return "sin_materiales"
	_aplicar_descuento(antes, copia)
	if not _refugio.colocar(_tipo, pos, _rot):
		return "no_puede"
	_instanciar(_tipo, pos, _rot, false)
	_refrescar_preview()
	return "ok"


## Quita la última pieza colocada y devuelve los materiales. Es el des-hacer:
## sin él, un clic mal puesto era un material perdido para siempre.
func quitar_ultima() -> String:
	if _jugador == null or _refugio == null:
		return "nada"
	var piezas: Array = _refugio.piezas_lista()
	if piezas.is_empty():
		return "vacio"
	var ultima: Dictionary = piezas[piezas.size() - 1]
	if not _refugio.quitar_ultima():
		return "vacio"
	devolver_materiales(str(ultima.get("tipo", "")))
	_reconstruir_visuales()
	_reconstruir()
	return "ok"


func _inventario_plano() -> Dictionary:
	var d: Dictionary = {}
	if _jugador == null or _jugador.inventario == null:
		return d
	for e in _jugador.inventario.listar():
		var ed: Dictionary = e
		d[str(ed.get("id", ""))] = int(ed.get("cantidad", 0))
	return d


## Vuelca al `Inventario` real lo que `Constructor.descontar` hizo en la copia.
## Se recorre el costo, que es una lista corta y conocida, en vez de diffing
## dos diccionarios: el diff daria igual de bien y es mas codigo.
func _aplicar_descuento(antes: Dictionary, despues: Dictionary) -> void:
	if _jugador == null or _jugador.inventario == null:
		return
	for item in PiezasDB.costo(_tipo).keys():
		var antes_i: int = int(antes.get(item, 0))
		var despues_i: int = int(despues.get(item, 0))
		var gastado: int = antes_i - despues_i
		if gastado > 0:
			_jugador.inventario.quitar(item, gastado)


## Fase 64: deshacer devuelve los materiales. Sin esto, un clic mal puesto era
## un material perdido para siempre, que es la forma de hacer que el jugador
## deje de construir por miedo a equivocar el clic.
func devolver_materiales(tipo: String) -> void:
	if _jugador == null or _jugador.inventario == null or tipo == "":
		return
	for item in PiezasDB.costo(tipo).keys():
		_jugador.inventario.agregar(item, int(PiezasDB.costo(tipo)[item]))


func _reconstruir() -> void:
	for h in _filas.get_children():
		h.queue_free()
	PiezasDB.cargar()
	if _refugio != null:
		_presupuesto.text = "Piezas: %d / %d" % [_refugio.piezas(), _refugio.piezas_max]
	for tid in PiezasDB.ids():
		_filas.add_child(_fila(String(tid)))


func _fila(tipo: String) -> HBoxContainer:
	var inv: Dictionary = _inventario_plano()
	var falta: Array = Constructor.materiales_faltantes(tipo, inv)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 6)
	var btn := Button.new()
	btn.text = PiezasDB.nombre_de(tipo)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.disabled = _refugio != null and not _refugio.puede_colocar()
	btn.pressed.connect(_al_seleccionar.bind(tipo))
	fila.add_child(btn)
	if not falta.is_empty():
		var aviso := Label.new()
		aviso.text = "faltan: %d" % falta.size()
		aviso.add_theme_font_size_override("font_size", 11)
		aviso.add_theme_color_override("font_color", Color(0.9, 0.5, 0.4))
		fila.add_child(aviso)
	return fila


func _al_seleccionar(tipo: String) -> void:
	seleccionar(tipo)


func _crear_fantasma() -> void:
	_destruir_fantasma()
	if _tipo == "" or _refugio == null or _jugador == null:
		return
	_fantasma = PiezaVisual.new()
	_fantasma.name = "Fantasma"
	_fantasma.construir(_tipo, true)
	_fantasma.position = _pos_actual()
	_refugio.add_child(_fantasma)


func _destruir_fantasma() -> void:
	if _fantasma != null and is_instance_valid(_fantasma):
		_fantasma.queue_free()
	_fantasma = null


func _refrescar_preview() -> void:
	_destruir_fantasma()
	_crear_fantasma()
	_reconstruir()


## La posición del preview: delante del jugador, sobre la rejilla. Es
## deliberadamente automática y no por raycast de ratón: con el panel abierto
## el ratón está encima de los botones, así que un preview que lo persiguiera
## saltaría cada vez que el jugador busca una pieza.
func _pos_actual() -> Vector3:
	if _jugador == null:
		return Vector3.ZERO
	var d: Vector3 = -_jugador.global_transform.basis.z
	d.y = 0.0
	if d.length() < 0.001:
		d = Vector3.FORWARD
	d = d.normalized() * 4.0
	return Constructor.ajustar(_jugador.global_position + d)


func _instanciar(tipo: String, pos: Vector3, rot: float, fantasma: bool) -> void:
	var v := PiezaVisual.new()
	v.name = "Pieza_%s" % tipo
	v.construir(tipo, fantasma)
	v.position = pos
	v.rotation.y = deg_to_rad(rot)
	_refugio.add_child(v)
	_visuales.append(v)


## Reconstruye las mallas de las piezas ya colocadas. Se llama al abrir: si el
## refugio se guardó y se recargó, las piezas siguen en `piezas_lista()` pero
## sus mallas son de la sesión anterior.
func _reconstruir_visuales() -> void:
	for v in _visuales:
		var n: Node = v as Node
		if n != null and is_instance_valid(n):
			n.queue_free()
	_visuales.clear()
	if _refugio == null:
		return
	for p in _refugio.piezas_lista():
		var pd: Dictionary = p
		_instanciar(str(pd.get("tipo", "")), pd.get("pos", Vector3.ZERO) as Vector3,
			float(pd.get("rot", 0.0)), false)
