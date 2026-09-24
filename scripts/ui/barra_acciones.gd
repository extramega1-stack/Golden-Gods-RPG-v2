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
## Fase 38: cada slot se dispara por su acción propia `slot_1..slot_8`
## (defecto = F + número) y su tecla es reasignable: clic en la etiqueta
## y pulsar la tecla; clic derecho en la etiqueta vuelve al defecto.
##
## REGLA DURA (directriz de Juan Diego): la UI solo LEE datos y ejecuta a
## través de la API del Player (solicitar_ataque, lanzar_skill_id,
## inventario.usar); nunca toca StatBlock. La barra contenedora y el libro
## oculto llevan mouse_filter IGNORE (lección 11 de AGENTS.md); solo los
## slots y los chips visibles usan STOP. Un clic izquierdo en un slot VACÍO
## no se consume: el clic-para-moverse sigue funcionando a través de él.

const NUM_SLOTS: int = 8
## Etiqueta por defecto de cada slot (la reasignación la pisa).
const TECLAS: Array[String] = ["1/F1", "2/F2", "3/F3", "4/F4", "5/F5", "F6", "F7", "F8"]
## Teclas numéricas 1-5 → slots visibles 0-4 (lo que se ve es lo que suena).
const TECLAS_NUMERO: Array[String] = [
	"habilidad_1", "habilidad_2", "habilidad_3", "habilidad_4", "habilidad_5",
]
## Fase 38: acciones propias por slot (vía única de disparo). Se crean en
## runtime si faltan; el rebind solo muta ESTAS acciones (nunca las del
## proyecto). El gameplay lee acciones con nombre, no teclas (§9.3).
const PREFIJO_SLOT: String = "slot_"
const SAVE_VERSION_BARRA: int = 2

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
## Fase 38: etiquetas de tecla por slot (clic = reasignar) + override de
## tecla por slot (physical_keycode; 0 = atajo por defecto).
var _teclas: Array[Label] = []
var _atajos: Array[int] = []
## Slot en escucha de rebind (-1 = ninguno) + aviso temporal de conflicto.
var _escuchando: int = -1
var _aviso_slot: int = -1
var _aviso_hasta: float = 0.0


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
	_asegurar_acciones_slot()
	_refrescar_teclas()


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
	# Fase 38: la etiqueta es el botón de rebind (clic = escuchar tecla,
	# clic derecho = volver al defecto). Solo ella usa STOP en la casilla.
	tecla.mouse_filter = Control.MOUSE_FILTER_STOP
	tecla.tooltip_text = "Clic: reasignar tecla · Clic derecho: defecto"
	tecla.gui_input.connect(_al_tecla_gui.bind(i))
	caja.add_child(tecla)
	_teclas.append(tecla)
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
	_asegurar_acciones_slot()
	# Fase 38: captura del rebind (ESC = acción cancelar_seleccion: aborta).
	if _escuchando >= 0 and _escuchando < NUM_SLOTS:
		if event.is_action_pressed("cancelar_seleccion"):
			cancelar_escucha()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey:
			var tecla: InputEventKey = event
			if tecla.pressed and not tecla.echo:
				_al_tecla_rebind(tecla)
				get_viewport().set_input_as_handled()
			return
		return
	# Vía única de disparo (fase 37): los slots se escuchan por sus
	# acciones propias slot_1..8 (defecto = barra_N + habilidad_N).
	for i in range(NUM_SLOTS):
		if event.is_action_pressed(PREFIJO_SLOT + str(i + 1)):
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


## --- Rebind por slot (fase 38) ---
##
## Cada slot se dispara por su acción propia `slot_1..slot_8` (creadas en
## runtime; el proyecto no se toca). El defecto copia los eventos de
## `barra_N` (+ `habilidad_N` en 1-5, herencia de la fase 37). Reasignar
## reemplaza los eventos del slot; el physical queda en `_atajos` y se
## persiste en el save (0 = defecto). Con conflicto (otra acción u otro
## slot usa la tecla) se rechaza con "conflicto" y aviso en la etiqueta.

func _accion_slot(i: int) -> String:
	return PREFIJO_SLOT + str(i + 1)


## Crea las 8 acciones si faltan y siembra el defecto donde no hay eventos
## (no pisa rebinds: un slot con eventos se deja intacto).
func _asegurar_acciones_slot() -> void:
	while _atajos.size() < NUM_SLOTS:
		_atajos.append(0)
	for i in range(NUM_SLOTS):
		var acc: String = _accion_slot(i)
		if not InputMap.has_action(acc):
			InputMap.add_action(acc)
		if InputMap.action_get_events(acc).is_empty():
			for ev in _eventos_defecto(i):
				InputMap.action_add_event(acc, ev)


## Eventos por defecto del slot i: barra_{i+1} + habilidad_{i+1} (si existe).
func _eventos_defecto(i: int) -> Array[InputEvent]:
	var res: Array[InputEvent] = []
	var acc_barra: String = "barra_%d" % [i + 1]
	if InputMap.has_action(acc_barra):
		for ev in InputMap.action_get_events(acc_barra):
			res.append(ev)
	if i < TECLAS_NUMERO.size():
		var acc_num: String = TECLAS_NUMERO[i]
		if InputMap.has_action(acc_num):
			for ev in InputMap.action_get_events(acc_num):
				res.append(ev)
	return res


## Reasigna el slot i a la tecla del evento. Retorna "ok", "conflicto",
## "tipo" (no es tecla) o "indice". Pública para UI y tests.
func fijar_atajo(i: int, evento: InputEvent) -> String:
	if i < 0 or i >= NUM_SLOTS:
		return "indice"
	if not (evento is InputEventKey):
		return "tipo"
	var tecla: InputEventKey = evento
	var codigo: int = int(tecla.physical_keycode)
	if codigo == 0:
		return "tipo"
	var choque: String = _conflicto(i, codigo)
	if choque != "":
		_mostrar_aviso(i)
		return "conflicto"
	_asegurar_acciones_slot()
	var acc: String = _accion_slot(i)
	InputMap.action_erase_events(acc)
	var nuevo: InputEventKey = InputEventKey.new()
	nuevo.physical_keycode = codigo
	InputMap.action_add_event(acc, nuevo)
	_atajos[i] = codigo
	_refrescar_teclas()
	return "ok"


## ¿Qué usa ya este physical? "" = libre. Revisa otros slots y el resto
## de acciones del proyecto (moverse con la misma tecla sería un doble).
func _conflicto(i: int, codigo: int) -> String:
	for j in range(NUM_SLOTS):
		if j == i:
			continue
		for ev in InputMap.action_get_events(_accion_slot(j)):
			var k: InputEventKey = ev as InputEventKey
			if k != null and int(k.physical_keycode) == codigo:
				return _accion_slot(j)
	for acc in InputMap.get_actions():
		var nombre: String = str(acc)
		if nombre.begins_with(PREFIJO_SLOT):
			continue
		if nombre == "barra_%d" % [i + 1]:
			continue
		if i < TECLAS_NUMERO.size() and nombre == TECLAS_NUMERO[i]:
			continue
		for ev in InputMap.action_get_events(nombre):
			var k2: InputEventKey = ev as InputEventKey
			if k2 != null and int(k2.physical_keycode) == codigo:
				return nombre
	return ""


## Vuelve el slot i a su defecto (eventos + etiqueta). Siempre funciona.
func restablecer_atajo(i: int) -> void:
	if i < 0 or i >= NUM_SLOTS:
		return
	_asegurar_acciones_slot()
	var acc: String = _accion_slot(i)
	InputMap.action_erase_events(acc)
	for ev in _eventos_defecto(i):
		InputMap.action_add_event(acc, ev)
	_atajos[i] = 0
	if _escuchando == i:
		_escuchando = -1
	_refrescar_teclas()


## Todos los slots al defecto (nunca falla; no toca el contenido).
func restablecer_atajos() -> void:
	for i in range(NUM_SLOTS):
		restablecer_atajo(i)
	_escuchando = -1


## Texto de la etiqueta: override ([Q]) o defecto ([1/F1]).
func atajo_texto(i: int) -> String:
	if i < 0 or i >= NUM_SLOTS:
		return ""
	if i < _atajos.size() and _atajos[i] != 0:
		return OS.get_keycode_string(_atajos[i])
	return TECLAS[i]


## Slot en escucha (-1 = ninguno). Pública para tests.
func escuchando() -> int:
	return _escuchando


func cancelar_escucha() -> void:
	_escuchando = -1
	_refrescar_teclas()


func _empezar_escucha(i: int) -> void:
	if i < 0 or i >= NUM_SLOTS:
		return
	_escuchando = i
	_aviso_slot = -1
	_refrescar_teclas()


func _al_tecla_gui(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_empezar_escucha(i)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			restablecer_atajo(i)
			get_viewport().set_input_as_handled()


func _al_tecla_rebind(tecla: InputEventKey) -> void:
	var i: int = _escuchando
	_escuchando = -1
	if i < 0 or i >= NUM_SLOTS:
		_refrescar_teclas()
		return
	fijar_atajo(i, tecla)
	_refrescar_teclas()


func _mostrar_aviso(i: int) -> void:
	_aviso_slot = i
	_aviso_hasta = Time.get_ticks_msec() / 1000.0 + 1.2
	_refrescar_teclas()


func _refrescar_teclas() -> void:
	for i in range(mini(_teclas.size(), NUM_SLOTS)):
		var lab: Label = _teclas[i]
		if _escuchando == i:
			lab.text = "[…]"
		elif _aviso_slot == i and Time.get_ticks_msec() / 1000.0 < _aviso_hasta:
			lab.text = "[¡En uso!]"
		else:
			lab.text = "[%s]" % atajo_texto(i)


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
	# Fase 38: el aviso de conflicto vuelve solo a la etiqueta real.
	if _aviso_slot >= 0 and _aviso_slot < NUM_SLOTS \
			and Time.get_ticks_msec() / 1000.0 >= _aviso_hasta:
		_aviso_slot = -1
		_refrescar_teclas()


## --- Persistencia versionada (la guarda/carga el SaveSystem) ---

func to_dict() -> Dictionary:
	if not _slots_ok():
		return {}
	_asegurar_acciones_slot()
	return {
		"version": SAVE_VERSION_BARRA,
		"slots": _slots.duplicate(true),
		"atajos": _atajos.duplicate(),
	}


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
	# Fase 38: atajos v2 (array de physicals, 0 = defecto). Un save v1
	# (sin clave) conserva el defecto intacto.
	restablecer_atajos()
	var version: int = int(d.get("version", 1))
	if version >= 2:
		var guardados: Array = d.get("atajos", [])
		for i in range(mini(guardados.size(), NUM_SLOTS)):
			var codigo: int = int(guardados[i])
			if codigo == 0:
				continue
			var ev: InputEventKey = InputEventKey.new()
			ev.physical_keycode = codigo
			if fijar_atajo(i, ev) != "ok":
				restablecer_atajo(i)
	_refrescar_nombres()
	_refrescar_teclas()


## Layout por defecto: ataque en F1 y los skills DE LA CLASE DEL JUGADOR
## en F2..F8 (fase 18: `skills_por_clase`; antes eran los primeros del
## JSON global). Fase 38: no toca los atajos de tecla (son preferencia
## del jugador y sobreviven a la nueva partida).
func restablecer_defecto() -> void:
	_slots.clear()
	for i in range(NUM_SLOTS):
		_slots.append({})
	_slots[0] = {"tipo": "ataque"}
	var ids: Array[String] = SkillDB.skills_por_clase(_clase_jugador())
	for k in range(mini(ids.size(), NUM_SLOTS - 1)):
		_slots[k + 1] = {"tipo": "skill", "id": ids[k]}
	_refrescar_nombres()
