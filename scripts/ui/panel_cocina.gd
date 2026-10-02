class_name PanelCocina
extends CanvasLayer
## Fase 64: el panel que cierra el círculo recolectar → cocinar → comer.
##
## POR QUÉ EXISTE: la Fase 56 dejó `Cocina` y `RecetasCocinaDB` enteras y
## testeadas, y las fogatas puestas en las nueve plazas. Pero
## `Fogata.cargar_lena()`, `gastar_lena()` y `puede_usar()` NO LOS LLAMABA
## NADIE fuera de los tests: no había forma de prender una fogata ni de
## cocinar. El círculo más interesante del bloque (decidir siSpends el riesgo de
## la carne cruda o caminás hasta la fogata) era, literalmente, inalcanzable.
##
## - Capa propia (`UiLayers.PANEL_COCINA`, rango de panel de sistema).
## - UI que solo LEE: pregunta a `Cocina.puede_cocinar` si puede, y escribe
##   por las APIs (`Inventario`, `Player.gain_xp`, `Fogata.gastar_lena`).
## - Las recetas salen de los DATOS: `RecetasCocinaDB` indexa por ingrediente,
##   así que el panel recorre los ingredientes conocidos y no una lista fija.
##   Añadir una receta es tocar `data/recetas_cocina.json`.

const CAPA: int = UiLayers.PANEL_COCINA
const ANCHO: float = 420.0

## §9.1
var system_id: StringName = &"panel_cocina"

var _jugador: Player = null
var _fogata: Fogata = null
var _caja: VBoxContainer = null
var _filas: VBoxContainer = null
var _titulo: Label = null
var _leña: Label = null


func _init() -> void:
	layer = CAPA
	_construir()
	visible = false



func _construir() -> void:
	var fondo := PanelContainer.new()
	fondo.set_anchors_preset(Control.PRESET_CENTER)
	# Bloque 67: tamaño y posicion del viewport, no numeros duros.
	AjustaUI.centrar(fondo, 0.33, 0.53)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.add_theme_constant_override("margin_left", 14)
	margen.add_theme_constant_override("margin_right", 14)
	margen.add_theme_constant_override("margin_top", 10)
	margen.add_theme_constant_override("margin_bottom", 10)
	fondo.add_child(margen)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	margen.add_child(caja)
	_caja = caja

	_titulo = Label.new()
	_titulo.text = "Cocinar"
	_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titulo.add_theme_font_size_override("font_size", 20)
	_titulo.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	caja.add_child(_titulo)

	_leña = Label.new()
	_leña.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leña.add_theme_font_size_override("font_size", 13)
	_leña.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
	caja.add_child(_leña)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(scroll)
	_filas = VBoxContainer.new()
	_filas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filas.add_theme_constant_override("separation", 6)
	scroll.add_child(_filas)

	var cerrar := Button.new()
	cerrar.text = "Cerrar (ESC)"
	cerrar.pressed.connect(cerrar_panel)
	caja.add_child(cerrar)


## Abre con una fogata concreta. Si no hay ninguna al alcance, no abre: el
## panel sin fogata no tiene sentido porque no hay dónde gastar la leña.
func abrir(j: Player, f: Fogata) -> bool:
	if j == null or not is_instance_valid(j):
		return false
	if f == null or not is_instance_valid(f):
		return false
	_jugador = j
	_fogata = f
	visible = true
	PilaUI.abrir(self)
	_reconstruir()
	return true


func cerrar_panel() -> void:
	visible = false
	PilaUI.cerrar(self)
	_jugador = null
	_fogata = null


func esta_abierta() -> bool:
	return visible


## El inventario como `Dictionary` plano, que es lo que habla `Cocina`.
## Se construye bajo demanda y SOLO cuando hay que cocinar o preguntar: por
## frame sería un diccionario nuevo 60 veces por segundo (§9.5).
func _inventario_plano() -> Dictionary:
	var d: Dictionary = {}
	if _jugador == null or _jugador.inventario == null:
		return d
	for e in _jugador.inventario.listar():
		var ed: Dictionary = e
		d[str(ed.get("id", ""))] = int(ed.get("cantidad", 0))
	return d


func _reconstruir() -> void:
	for h in _filas.get_children():
		h.queue_free()
	RecetasCocinaDB.cargar()
	if _fogata != null:
		_leña.text = "Leña: %d s" % int(_fogata.lena)
	for ing in RecetasCocinaDB.ingredientes():
		_filas.add_child(_fila(String(ing)))


func _fila(ingrediente: String) -> HBoxContainer:
	var receta: Dictionary = RecetasCocinaDB.receta(ingrediente)
	var inv: Dictionary = _inventario_plano()
	var tengo: int = int(inv.get(ingrediente, 0))
	var lena: float = float(_fogata.lena) if _fogata != null else 0.0
	var motivo: String = Cocina.puede_cocinar(ingrediente, receta, inv, lena)

	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	var textos := VBoxContainer.new()
	textos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(textos)

	var nombre := Label.new()
	var res_nombre: String = _nombre_item(str(receta.get("resultado", "")))
	nombre.text = "%s → %s x%d" % [_nombre_item(ingrediente), res_nombre,
		int(receta.get("cantidad", 1))]
	nombre.add_theme_font_size_override("font_size", 15)
	# El color delata el estado sin leer: lo que podés cocinar y lo que no.
	nombre.add_theme_color_override("font_color",
		Color(0.85, 0.82, 0.75) if motivo == Cocina.MOTIVO_OK
			else Color(0.5, 0.5, 0.48))
	textos.add_child(nombre)

	var nota := Label.new()
	nota.text = "Tenés %d · %s" % [tengo, _nota_motivo(motivo, receta, lena)]
	nota.add_theme_font_size_override("font_size", 12)
	nota.add_theme_color_override("font_color", Color(0.68, 0.66, 0.6))
	textos.add_child(nota)

	var btn := Button.new()
	btn.text = "Cocinar"
	btn.custom_minimum_size = Vector2(90.0, 38.0)
	btn.disabled = motivo != Cocina.MOTIVO_OK
	btn.tooltip_text = "" if motivo == Cocina.MOTIVO_OK \
			else Cocina.texto_motivo(motivo)
	btn.pressed.connect(_al_cocinar.bind(ingrediente))
	fila.add_child(btn)
	return fila


func _nombre_item(item_id: String) -> String:
	if item_id == "":
		return "?"
	ItemDB.cargar()
	return str(ItemDB.obtener(item_id).get("nombre", item_id))


func _nota_motivo(motivo: String, receta: Dictionary, lena: float) -> String:
	if motivo == Cocina.MOTIVO_SIN_LEÑA:
		return "Faltan %.0f s de leña" % float(receta.get("lena", 1.0))
	if motivo == Cocina.MOTIVO_SIN_INGREDIENTE:
		return "No tenés el ingrediente"
	return "%.0f s de leña" % float(receta.get("lena", 1.0))


## Cocinar. Todo el gasto pasa por `Cocina` (que es quien decide) y después se
## APLICA al inventario real: la función pura no puede tocar el `Inventario`
## porque es un nodo con señales.
func _al_cocinar(ingrediente: String) -> void:
	if _jugador == null or _fogata == null:
		return
	var receta: Dictionary = RecetasCocinaDB.receta(ingrediente)
	var inv: Dictionary = _inventario_plano()
	# FASE 72: los `hechos` del jugador son lo que hace que "Cocina de lote"
	# sirva 2 raciones. Sin pasarlos, el Hecho se guardaba y no se usaba.
	var r: Dictionary = Cocina.cocinar(ingrediente, receta, inv, _jugador.hechos)
	if not bool(r.get("ok", false)):
		return
	# El ingrediente sale del inventario REAL (el dict era una copia).
	_jugador.inventario.quitar(ingrediente, 1)
	var salida: String = str(r.get("item_id", ""))
	var cantidad: int = int(r.get("cantidad", 1))
	_jugador.inventario.agregar(salida, cantidad)
	# Y la leña se gasta de la fogata, no del dict.
	_fogata.gastar_lena(float(r.get("lena", 1.0)))
	_fogata.cocinado.emit(salida, cantidad)
	var xp: int = int(r.get("xp", 0))
	if xp > 0:
		_jugador.gain_xp(xp)
		# Fase 57: cocinar también sube su habilidad, como talar y minar.
		if _jugador.habilidades != null:
			_jugador.habilidades.ganar("cocina", xp)
	_reconstruir()


func _unhandled_input(event: InputEvent) -> void:
	if visible and PilaUI.es_cima(self) \
			and event.is_action_pressed("cancelar_seleccion"):
		cerrar_panel()
		get_viewport().set_input_as_handled()
