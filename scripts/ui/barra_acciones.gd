class_name BarraAcciones
extends CanvasLayer
## Barra de acciones estilo Flyff (fase 17): 8 slots arrastrables abajo-centro.
##
## Cada slot puede tener: ataque básico, un skill (SkillDB) o un consumible
## (ItemDB). Las teclas F1..F8 ejecutan lo asignado (acciones del Input Map
## `barra_1`..`barra_8`). Fuentes arrastrables: chip "Ataque", libro de
## habilidades (botón del libro) y las filas de consumibles del inventario.
## Clic izquierdo en un slot ocupado lo ejecuta; clic derecho o la tecla
## Supr (acción `limpiar_slot`) limpia el slot bajo el cursor; arrastrar
## entre slots los intercambia. Overlay de cooldown por slot + contador
## de unidades en consumibles.
##
## REGLA DURA (directriz de Juan Diego): la UI solo LEE datos y ejecuta a
## través de la API del Player (solicitar_ataque, lanzar_skill_id,
## inventario.usar); nunca toca StatBlock. La barra contenedora y el libro
## oculto llevan mouse_filter IGNORE (lección 11 de AGENTS.md); solo los
## slots y los chips visibles usan STOP. Un clic izquierdo en un slot VACÍO
## no se consume: el clic-para-moverse sigue funcionando a través de él.

const NUM_SLOTS: int = 8
const TECLAS: Array[String] = ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8"]
const SAVE_VERSION_BARRA: int = 1

## Etiqueta pequeña arrastrable (fuente de drag & drop). La usan el chip de
## ataque, el libro de habilidades y las filas de consumibles del inventario.
class ChipArrastre extends Label:
	var datos: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if datos.is_empty():
			return null
		var previo: PanelContainer = PanelContainer.new()
		var estilo: StyleBoxFlat = StyleBoxFlat.new()
		estilo.bg_color = Color(0.08, 0.08, 0.12, 0.9)
		estilo.border_color = Color(0.75, 0.62, 0.3)
		estilo.set_border_width_all(2)
		previo.add_theme_stylebox_override("panel", estilo)
		var lab: Label = Label.new()
		lab.text = text
		lab.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
		lab.add_theme_font_size_override("font_size", 14)
		previo.add_child(lab)
		set_drag_preview(previo)
		return datos


## Casilla de la barra: acepta drops, es fuente de drag si está ocupada,
## clic izquierdo ejecuta (solo si hay algo), clic derecho limpia.
class Casilla extends PanelContainer:
	var indice: int = 0
	var barra: BarraAcciones = null

	func _gui_input(event: InputEvent) -> void:
		if barra == null:
			return
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event
			if not mb.pressed:
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				barra._clic_casilla(indice)
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				barra._clic_derecho_casilla(indice)

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if barra == null:
			return null
		var datos: Dictionary = barra._drag_desde_casilla(indice)
		if datos.is_empty():
			return null
		var previo: PanelContainer = PanelContainer.new()
		var estilo: StyleBoxFlat = StyleBoxFlat.new()
		estilo.bg_color = Color(0.08, 0.08, 0.12, 0.9)
		estilo.border_color = Color(0.75, 0.62, 0.3)
		estilo.set_border_width_all(2)
		previo.add_theme_stylebox_override("panel", estilo)
		var lab: Label = Label.new()
		lab.text = barra._nombre_slot(datos)
		lab.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
		previo.add_child(lab)
		set_drag_preview(previo)
		return datos

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if barra == null:
			return false
		return barra._puede_soltar(data)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if barra == null:
			return
		barra._soltar_en(indice, data)


var _jugador: Player = null
## 8 dicts: {} = vacío; {"tipo":"ataque"}; {"tipo":"skill","id":sid};
## {"tipo":"item","id":iid}.
var _slots: Array[Dictionary] = []
var _casillas: Array = []
var _overlays: Array[Label] = []
var _nombres: Array[Label] = []
var _cantidades: Array[Label] = []
var _libro: PanelContainer = null
## Fase 18: la caja del libro (el primer hijo es el título; los chips se
## reconstruyen al filtrar por clase).
var _libro_caja: VBoxContainer = null
var _slot_bajo_raton: int = -1


## Los accesos públicos pueden llegar antes del _ready (tests, carga):
## si los slots no están inicializados, se restauran al defecto.
func _slots_ok() -> bool:
	if _slots.size() != NUM_SLOTS:
		restablecer_defecto()
	return _slots.size() == NUM_SLOTS


func _ready() -> void:
	layer = UiLayers.BARRA_SKILLS
	_construir()
	restablecer_defecto()


func _construir() -> void:
	var barra: HBoxContainer = HBoxContainer.new()
	barra.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	barra.grow_horizontal = Control.GROW_DIRECTION_BOTH
	barra.grow_vertical = Control.GROW_DIRECTION_BEGIN
	barra.offset_top = -float(UiLayers.ZONA_INFERIOR_RESERVADA)
	barra.offset_bottom = -24.0
	barra.add_theme_constant_override("separation", 6)
	barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(barra)
	# Fuentes arrastrables a la izquierda de los slots.
	var fuentes: VBoxContainer = VBoxContainer.new()
	fuentes.add_theme_constant_override("separation", 4)
	fuentes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barra.add_child(fuentes)
	var chip_ataque: ChipArrastre = _nuevo_chip("⚔ Ataque")
	chip_ataque.datos = {"origen": "fuente", "tipo": "ataque"}
	chip_ataque.tooltip_text = "Arrastra a un slot: ataque básico"
	fuentes.add_child(chip_ataque)
	var btn_libro: Button = Button.new()
	btn_libro.text = "📖 Skills"
	btn_libro.tooltip_text = "Libro de habilidades (arrastra a un slot)"
	btn_libro.pressed.connect(_alternar_libro)
	fuentes.add_child(btn_libro)
	for i in range(NUM_SLOTS):
		var c: Casilla = _nueva_casilla(i)
		barra.add_child(c)
		_casillas.append(c)
	_construir_libro()


func _nuevo_chip(texto: String) -> ChipArrastre:
	var chip: ChipArrastre = ChipArrastre.new()
	chip.text = texto
	chip.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	chip.add_theme_font_size_override("font_size", 14)
	chip.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	chip.add_theme_constant_override("shadow_offset_x", 1)
	chip.add_theme_constant_override("shadow_offset_y", 1)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return chip


func _nueva_casilla(i: int) -> Casilla:
	var marco: Casilla = Casilla.new()
	marco.indice = i
	marco.barra = self
	marco.custom_minimum_size = Vector2(76, 68)
	marco.mouse_filter = Control.MOUSE_FILTER_STOP
	# Fase 32: casilla FlyFF — fondo oscuro + borde dorado + esquinas.
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(0.05, 0.05, 0.09, 0.92)
	estilo.border_color = TemaFlyFF.DORADO
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(4)
	marco.add_theme_stylebox_override("panel", estilo)
	var caja: VBoxContainer = VBoxContainer.new()
	caja.set_anchors_preset(Control.PRESET_FULL_RECT)
	caja.alignment = BoxContainer.ALIGNMENT_CENTER
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_theme_constant_override("separation", 0)
	marco.add_child(caja)
	var tecla: Label = _etiqueta("[%s]" % TECLAS[i], 12, Color(0.7, 0.65, 0.55))
	tecla.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(tecla)
	var nom: Label = _etiqueta("", 14, Color(0.95, 0.9, 0.75))
	nom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(nom)
	_nombres.append(nom)
	# Contador de consumibles (esquina inferior derecha).
	var cant: Label = _etiqueta("", 12, Color(0.8, 0.85, 1.0))
	cant.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cant.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cant.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cant.offset_left = -30.0
	cant.offset_top = -18.0
	cant.offset_right = -4.0
	cant.offset_bottom = -2.0
	marco.add_child(cant)
	_cantidades.append(cant)
	# Overlay de cooldown: velo oscuro con los segundos restantes.
	var overlay: Label = _etiqueta("", 20, Color(1, 1, 1))
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.visible = false
	var velo: StyleBoxFlat = StyleBoxFlat.new()
	velo.bg_color = Color(0.02, 0.02, 0.05, 0.78)
	overlay.add_theme_stylebox_override("normal", velo)
	marco.add_child(overlay)
	_overlays.append(overlay)
	marco.mouse_entered.connect(_al_raton_entra.bind(i))
	marco.mouse_exited.connect(_al_raton_sale.bind(i))
	return marco


func _etiqueta(texto: String, tam: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = texto
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", tam)
	return l


func _construir_libro() -> void:
	_libro = PanelContainer.new()
	_libro.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_libro.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_libro.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_libro.offset_top = -float(UiLayers.ZONA_INFERIOR_RESERVADA) - 180.0
	_libro.offset_bottom = -float(UiLayers.ZONA_INFERIOR_RESERVADA) - 8.0
	_libro.offset_left = -140.0
	_libro.offset_right = 140.0
	_libro.mouse_filter = Control.MOUSE_FILTER_STOP
	_libro.visible = false
	# Fase 32: marco FlyFF compartido.
	_libro.add_theme_stylebox_override("panel", TemaFlyFF.marco())
	add_child(_libro)
	var caja: VBoxContainer = VBoxContainer.new()
	caja.add_theme_constant_override("separation", 4)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_libro.add_child(caja)
	_libro_caja = caja
	var titulo: Label = _etiqueta("Libro de habilidades  (arrastra a un slot)", 15, Color(0.95, 0.9, 0.75))
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(titulo)
	_reconstruir_libro()


## Fase 18 — reconstruye los chips del libro filtrando por la clase del
## jugador conectado (sin conexión: guerrero por defecto). Pública: la
## demo la llama tras aplicar/cargar la clase (el orden de _ready no
## garantiza que `conectar` llegue con la clase ya puesta).
func reconstruir_libro() -> void:
	_reconstruir_libro()


func _reconstruir_libro() -> void:
	if _libro_caja == null:
		return
	# Se conserva el título (hijo 0); se tiran los chips viejos.
	for h in _libro_caja.get_children():
		if h is ChipArrastre:
			_libro_caja.remove_child(h)
			h.queue_free()
	for sid in SkillDB.skills_por_clase(_clase_jugador()):
		var sk: Dictionary = SkillDB.obtener(sid)
		var chip: ChipArrastre = _nuevo_chip(str(sk.get("nombre", sid)))
		chip.datos = {"origen": "libro", "tipo": "skill", "id": sid}
		chip.tooltip_text = str(sk.get("descripcion", ""))
		_libro_caja.add_child(chip)


func _alternar_libro() -> void:
	if _libro != null:
		_libro.visible = not _libro.visible


## Conecta la barra al jugador (solo lectura + API de acciones).
## Reconstruye el libro con los skills de su clase.
func conectar(j: Player) -> void:
	_jugador = j
	_reconstruir_libro()
	_refrescar_nombres()


## Clase del jugador conectado ("guerrero" si aún no hay conexión).
func _clase_jugador() -> String:
	if _jugador != null and _jugador.clase_id != "":
		return _jugador.clase_id
	return "guerrero"


func _unhandled_input(event: InputEvent) -> void:
	for i in range(NUM_SLOTS):
		if event.is_action_pressed("barra_%d" % [i + 1]):
			ejecutar(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("limpiar_slot"):
		if _slot_bajo_raton >= 0 and _slot_bajo_raton < NUM_SLOTS:
			limpiar(_slot_bajo_raton)
			get_viewport().set_input_as_handled()


func _al_raton_entra(i: int) -> void:
	_slot_bajo_raton = i


func _al_raton_sale(i: int) -> void:
	if _slot_bajo_raton == i:
		_slot_bajo_raton = -1


## --- Asignación / limpieza / ejecución (públicas para tests y save) ---

## Valida datos de arrastre o de guardado. Solo acepta ataque, skill
## existente o consumible existente.
func validar_datos(d: Variant) -> bool:
	if not (d is Dictionary):
		return false
	var dd: Dictionary = d
	var tipo: String = str(dd.get("tipo", ""))
	match tipo:
		"ataque":
			return true
		"skill":
			return SkillDB.existe(str(dd.get("id", "")))
		"item":
			var iid: String = str(dd.get("id", ""))
			if not ItemDB.existe(iid):
				return false
			return str(ItemDB.obtener(iid).get("tipo", "")) == "consumible"
	return false


func asignar(i: int, datos: Dictionary) -> bool:
	if not _slots_ok():
		return false
	if i < 0 or i >= NUM_SLOTS:
		return false
	if not validar_datos(datos):
		return false
	var tipo: String = str(datos.get("tipo", ""))
	var slot: Dictionary = {"tipo": tipo}
	if tipo != "ataque":
		slot["id"] = str(datos.get("id", ""))
	_slots[i] = slot
	_refrescar_nombres()
	return true


func limpiar(i: int) -> void:
	if not _slots_ok():
		return
	if i < 0 or i >= NUM_SLOTS:
		return
	_slots[i] = {}
	_refrescar_nombres()


func obtener(i: int) -> Dictionary:
	if not _slots_ok():
		return {}
	if i < 0 or i >= NUM_SLOTS:
		return {}
	return _slots[i]


## Ejecuta lo asignado al slot i a través de la API del Player.
func ejecutar(i: int) -> void:
	if not _slots_ok():
		return
	if _jugador == null or i < 0 or i >= NUM_SLOTS:
		return
	var slot: Dictionary = _slots[i]
	var tipo: String = str(slot.get("tipo", ""))
	match tipo:
		"ataque":
			_jugador.solicitar_ataque()
		"skill":
			_jugador.lanzar_skill_id(str(slot.get("id", "")))
		"item":
			if _jugador.inventario != null:
				_jugador.inventario.usar(str(slot.get("id", "")), _jugador)


## --- Drag & drop ---

func _puede_soltar(data: Variant) -> bool:
	return validar_datos(data)


func _soltar_en(i: int, data: Variant) -> void:
	if not _slots_ok():
		return
	if not (data is Dictionary):
		return
	var dd: Dictionary = data
	if not validar_datos(dd):
		return
	# Arrastrar entre slots los intercambia.
	if str(dd.get("origen", "")) == "barra":
		var j: int = int(dd.get("slot", -1))
		if j == i or j < 0 or j >= NUM_SLOTS:
			return
		var tmp: Dictionary = _slots[i]
		_slots[i] = _slots[j]
		_slots[j] = tmp
		_refrescar_nombres()
		return
	asignar(i, dd)


## Datos de arrastre de una casilla ocupada ({} si está vacía). La casilla
## que inicia el drag fija su propio preview con set_drag_preview.
func _drag_desde_casilla(i: int) -> Dictionary:
	if not _slots_ok():
		return {}
	if i < 0 or i >= NUM_SLOTS:
		return {}
	var slot: Dictionary = _slots[i]
	if slot.is_empty():
		return {}
	var datos: Dictionary = slot.duplicate()
	datos["origen"] = "barra"
	datos["slot"] = i
	return datos


func _clic_casilla(i: int) -> void:
	# Solo se consume el clic si el slot tiene algo: ejecutar. Un slot
	# vacío deja pasar el clic (el héroe se mueve con clic izquierdo).
	if i < 0 or i >= NUM_SLOTS:
		return
	if _slots[i].is_empty():
		return
	ejecutar(i)
	get_viewport().set_input_as_handled()


func _clic_derecho_casilla(i: int) -> void:
	if i < 0 or i >= NUM_SLOTS:
		return
	if _slots[i].is_empty():
		return
	limpiar(i)
	get_viewport().set_input_as_handled()


## --- Nombres, cooldowns, contadores ---

func _nombre_slot(slot: Dictionary) -> String:
	var tipo: String = str(slot.get("tipo", ""))
	match tipo:
		"ataque":
			return "Ataque"
		"skill":
			var sk: Dictionary = SkillDB.obtener(str(slot.get("id", "")))
			return _corto(str(sk.get("nombre", "Skill")))
		"item":
			var it: Dictionary = ItemDB.obtener(str(slot.get("id", "")))
			return _corto(str(it.get("nombre", "Item")))
	return ""


func _corto(nombre: String) -> String:
	var partes: PackedStringArray = nombre.split(" ")
	if partes.size() > 0 and str(partes[0]) != "":
		return str(partes[0])
	return nombre


func _refrescar_nombres() -> void:
	if not _slots_ok():
		return
	for i in range(NUM_SLOTS):
		if i < _nombres.size():
			_nombres[i].text = _nombre_slot(_slots[i])


func _process(_delta: float) -> void:
	if not _slots_ok():
		return
	for i in range(NUM_SLOTS):
		if i >= _overlays.size() or i >= _cantidades.size():
			continue
		var slot: Dictionary = _slots[i]
		var tipo: String = str(slot.get("tipo", ""))
		var ov: Label = _overlays[i]
		var rest: float = 0.0
		if tipo == "skill" and _jugador != null and _jugador.skills != null:
			rest = _jugador.skills.cooldown_restante(str(slot.get("id", "")))
		if rest > 0.0:
			ov.visible = true
			ov.text = "%.1f" % rest
		else:
			ov.visible = false
			ov.text = ""
		var cant: Label = _cantidades[i]
		if tipo == "item" and _jugador != null and _jugador.inventario != null:
			var n: int = _jugador.inventario.contar(str(slot.get("id", "")))
			cant.text = "x%d" % n if n > 0 else ""
		else:
			cant.text = ""


## --- Persistencia versionada (la guarda/carga el SaveSystem) ---

func to_dict() -> Dictionary:
	if not _slots_ok():
		return {}
	return {"version": SAVE_VERSION_BARRA, "slots": _slots.duplicate(true)}


func cargar_estado(d: Dictionary) -> void:
	# Parte de slots vacíos (no del defecto): un slot que se guardó vacío
	# se restaura vacío; solo los ids inválidos se descartan.
	_slots.clear()
	for i in range(NUM_SLOTS):
		_slots.append({})
	var lista: Array = d.get("slots", [])
	for i in range(mini(lista.size(), NUM_SLOTS)):
		var s: Variant = lista[i]
		if validar_datos(s):
			var sd: Dictionary = s
			var slot: Dictionary = {"tipo": str(sd.get("tipo", ""))}
			if str(slot["tipo"]) != "ataque":
				slot["id"] = str(sd.get("id", ""))
			_slots[i] = slot
	_refrescar_nombres()


## Layout por defecto: ataque en F1 y los skills DE LA CLASE DEL JUGADOR
## en F2..F8 (fase 18: `skills_por_clase`; antes eran los primeros del
## JSON global).
func restablecer_defecto() -> void:
	_slots.clear()
	for i in range(NUM_SLOTS):
		_slots.append({})
	_slots[0] = {"tipo": "ataque"}
	var ids: Array[String] = SkillDB.skills_por_clase(_clase_jugador())
	for k in range(mini(ids.size(), NUM_SLOTS - 1)):
		_slots[k + 1] = {"tipo": "skill", "id": ids[k]}
	_refrescar_nombres()
