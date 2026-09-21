class_name RetratoHeroe
extends PanelContainer
## Retrato del héroe (fase 11): emblema procedural + nombre + nivel.
##
## Emblema: Panel 64×64 con StyleBoxFlat (fondo = color_secundario de la
## clase, borde 3 px = color_primario) + Label centrado con la inicial del
## nombre de la clase (dorada, 28 px). Sin texturas.
##
## REGLA DURA: la UI solo LEE el Player (señales + vars públicas: nombre,
## clase_id, nivel, esta_vivo); nunca escribe stats.
## - `subio_nivel` → actualiza el nivel.
## - `murio` → modo muerto (modulate gris oscuro).
## - `identidad_cambiada` → re-lee nombre/clase/emblema.
## - `refrescar()` re-lee todo y restaura el modulate según `esta_vivo()`
##   (para tras cargar partida).

var _jugador: Player = null
var _conectado: bool = false

var _emblema: Panel = null
var _inicial: Label = null
var _etiqueta_nombre: Label = null
var _etiqueta_nivel: Label = null


func _ready() -> void:
	_construir()


func _construir() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caja: HBoxContainer = HBoxContainer.new()
	caja.add_theme_constant_override("separation", 10)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caja)

	_emblema = Panel.new()
	_emblema.custom_minimum_size = Vector2(64, 64)
	_emblema.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(_emblema)

	_inicial = Label.new()
	_inicial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inicial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_inicial.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inicial.add_theme_font_size_override("font_size", 28)
	_inicial.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	_inicial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblema.add_child(_inicial)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(col)

	_etiqueta_nombre = Label.new()
	_etiqueta_nombre.add_theme_font_size_override("font_size", 20)
	_etiqueta_nombre.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
	_etiqueta_nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_etiqueta_nombre)

	_etiqueta_nivel = Label.new()
	_etiqueta_nivel.add_theme_font_size_override("font_size", 16)
	_etiqueta_nivel.add_theme_color_override("font_color", Color(0.75, 0.72, 0.66))
	_etiqueta_nivel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_etiqueta_nivel)


## Conecta el retrato al jugador (solo lectura). Idempotente.
func conectar(j: Player) -> void:
	if _conectado:
		return
	_jugador = j
	j.subio_nivel.connect(_al_nivel)
	j.murio.connect(_al_morir)
	j.identidad_cambiada.connect(_al_identidad)
	_conectado = true
	refrescar()


## Relee todo (tras cargar partida, por ejemplo) y restaura el modulate
## según `esta_vivo()`.
func refrescar() -> void:
	if _jugador == null:
		return
	_etiqueta_nombre.text = _jugador.nombre
	_etiqueta_nivel.text = "Nv %d" % _jugador.nivel
	_pintar_emblema()
	if _jugador.esta_vivo():
		modulate = Color.WHITE
	else:
		modulate = Color(0.35, 0.35, 0.42)


## Getters para tests (leen lo pintado, no el Player).
func nombre_mostrado() -> String:
	if _etiqueta_nombre == null:
		return ""
	return _etiqueta_nombre.text


func nivel_mostrado() -> String:
	if _etiqueta_nivel == null:
		return ""
	return _etiqueta_nivel.text


func inicial_mostrada() -> String:
	if _inicial == null:
		return ""
	return _inicial.text


func _pintar_emblema() -> void:
	var cid: String = "guerrero"
	if _jugador != null:
		cid = _jugador.clase_id
	var datos: Dictionary = ClaseDB.obtener(cid)
	var nombre_clase: String = str(datos.get("nombre", cid))
	if nombre_clase == "":
		_inicial.text = "?"
	else:
		_inicial.text = nombre_clase.left(1).to_upper()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = ClaseDB.color_secundario(cid)
	sb.border_color = ClaseDB.color_primario(cid)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	_emblema.add_theme_stylebox_override("panel", sb)


func _al_nivel(nivel: int) -> void:
	_etiqueta_nivel.text = "Nv %d" % nivel


func _al_morir(_fuente: Entity) -> void:
	modulate = Color(0.35, 0.35, 0.42)


func _al_identidad() -> void:
	refrescar()
