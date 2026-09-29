extends SceneTree
## Tests headless de la Fase 9 (detalle de misión).
##
## Cubre: `QuestDB.lore()` para las 3 misiones (lores del canon Liberty
## en data/quests.json); `VentanaDetalleMision` (arranca oculta, `mostrar`
## abre con nombre/lore/objetivos con progreso "x/y"/recompensas con oro,
## XP e items con cantidad; misión desconocida no abre ni revienta; ESC,
## clic fuera y `cerrar_detalle` la cierran; `mision_actual()`); y la
## integración en `PanelMisiones` (el nombre de cada misión en curso es un
## botón clicable que abre el detalle; ESC con el detalle abierto no
## cierra el panel; cerrar el panel cierra el detalle).
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_detalle_mision.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const QDB: GDScript = preload("res://scripts/quests/quest_db.gd")
const QL: GDScript = preload("res://scripts/quests/quest_log.gd")
const DM: GDScript = preload("res://scripts/ui/ventana_detalle_mision.gd")
const PM: GDScript = preload("res://scripts/ui/panel_misiones.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 9 — Detalle de misión")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	QDB.cargar()
	_t_lore()
	_t_ventana()
	_t_esc_y_velo()
	_t_panel()
	_t_orden_esc()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
	return true


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


func _player(pos: Vector3) -> Player:
	var p: Player = PL.new()
	p.add_to_group("jugador")
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


func _log() -> QuestLog:
	return QL.new()


func _ventana() -> VentanaDetalleMision:
	var v: VentanaDetalleMision = DM.new()
	root.add_child(v)
	_basura.append(v)
	return v


## --- QuestDB.lore() ---


func _t_lore() -> void:
	_check(QDB.lore("goblins_fuera") != "", "lore: Goblins fuera tiene lore")
	_check("Liberty" in QDB.lore("goblins_fuera"), "lore: Goblins fuera menciona Liberty")
	_check(QDB.lore("colmillos_forja") != "", "lore: Colmillos para la forja tiene lore")
	_check("Bram" in QDB.lore("colmillos_forja") or "fragua" in QDB.lore("colmillos_forja"),
		"lore: Colmillos para la forja menciona a Bram/la fragua")
	_check(QDB.lore("mensaje_sira") != "", "lore: Un mensaje urgente tiene lore")
	_check("Ilya" in QDB.lore("mensaje_sira"), "lore: Un mensaje urgente menciona a Ilya")
	_check(QDB.lore("inexistente") == "", "lore: misión desconocida da \"\"")


## --- VentanaDetalleMision ---


func _t_ventana() -> void:
	var v: VentanaDetalleMision = _ventana()
	_check(not v.esta_abierta(), "detalle: arranca oculta")
	_check(v.mision_actual() == "", "detalle: sin misión actual al arrancar")
	var q: QuestLog = _log()
	q.aceptar("goblins_fuera")
	q.registrar_muerte("goblin")
	q.registrar_muerte("goblin")
	q.registrar_muerte("goblin")
	v.mostrar("goblins_fuera", q)
	_check(v.esta_abierta(), "detalle: mostrar abre")
	_check(v.mision_actual() == "goblins_fuera", "detalle: mision_actual()")
	_check(v._lbl_nombre.text == "Goblins fuera", "detalle: muestra el nombre")
	_check(v._lbl_lore.text == QDB.lore("goblins_fuera"), "detalle: muestra el lore")
	_check(v._lbl_lore.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
		"detalle: el lore tiene autowrap")
	_check("Goblins derrotados: 3/5" in v._lbl_objetivos.text,
		"detalle: objetivos con progreso 3/5", v._lbl_objetivos.text)
	_check("+150 oro" in v._lbl_recompensas.text, "detalle: recompensa de oro")
	_check("+120 XP" in v._lbl_recompensas.text, "detalle: recompensa de XP")
	_check("Poción de vida" in v._lbl_recompensas.text and "2" in v._lbl_recompensas.text,
		"detalle: recompensa de items con cantidad", v._lbl_recompensas.text)
	v.cerrar_detalle()
	_check(not v.esta_abierta(), "detalle: cerrar_detalle cierra")
	# Misión desconocida: no abre ni revienta.
	v.mostrar("inexistente", q)
	_check(not v.esta_abierta(), "detalle: misión desconocida no abre")
	v.mostrar("goblins_fuera", null)
	_check(not v.esta_abierta(), "detalle: log null no abre")
	# Otra misión: objetivos y recompensas distintos.
	q.aceptar("mensaje_sira")
	v.mostrar("mensaje_sira", q)
	_check("Mensaje entregado a Ilya: 0/1" in v._lbl_objetivos.text,
		"detalle: objetivo hablar con progreso", v._lbl_objetivos.text)
	_check("+50 oro" in v._lbl_recompensas.text and "Poción de maná" in v._lbl_recompensas.text,
		"detalle: recompensas del mensaje", v._lbl_recompensas.text)
	v.cerrar_detalle()


## --- ESC y clic fuera ---


func _esc() -> InputEventAction:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = &"cancelar_seleccion"
	ev.pressed = true
	return ev


func _t_esc_y_velo() -> void:
	var v: VentanaDetalleMision = _ventana()
	var q: QuestLog = _log()
	q.aceptar("goblins_fuera")
	v.mostrar("goblins_fuera", q)
	# Bloque 65: la ventana también tiene que ser la cima para su ESC.
	PilaUI.abrir(v)
	# ESC cierra el detalle.
	v._input(_esc())
	_check(not v.esta_abierta(), "detalle: ESC cierra")
	# ESC con el detalle cerrado no hace nada (ni revienta).
	v._input(_esc())
	_check(not v.esta_abierta(), "detalle: ESC cerrado no revienta")
	# Clic fuera (velo propio) cierra.
	v.mostrar("goblins_fuera", q)
	var clic: InputEventMouseButton = InputEventMouseButton.new()
	clic.button_index = MOUSE_BUTTON_LEFT
	clic.pressed = true
	v._al_clic_velo(clic)
	_check(not v.esta_abierta(), "detalle: clic fuera cierra")
	# Clic derecho en el velo NO cierra.
	v.mostrar("goblins_fuera", q)
	var clic2: InputEventMouseButton = InputEventMouseButton.new()
	clic2.button_index = MOUSE_BUTTON_RIGHT
	clic2.pressed = true
	v._al_clic_velo(clic2)
	_check(v.esta_abierta(), "detalle: clic derecho no cierra")
	v.cerrar_detalle()


## --- Integración en PanelMisiones ---


func _t_panel() -> void:
	var pm: PanelMisiones = PM.new()
	root.add_child(pm)
	_basura.append(pm)
	_check(not pm.esta_abierta(), "panel: arranca oculto")
	_check(pm._detalle != null, "panel: tiene sub-ventana de detalle")
	_check(not pm._detalle.esta_abierta(), "panel: el detalle arranca oculto")
	var p: Player = _player(Vector3.ZERO)
	var q: QuestLog = _log()
	pm.conectar(p, q)
	q.aceptar("goblins_fuera")
	pm.alternar()
	_check(pm.esta_abierta(), "panel: alternar abre")
	# El nombre de la misión en curso es un botón clicable.
	var boton: Button = null
	for h in pm._lista_activas.get_children():
		if h is Button and (h as Button).name == "Detalle_goblins_fuera":
			boton = h as Button
	_check(boton != null, "panel: el nombre es un botón clicable")
	boton.pressed.emit()
	_check(pm._detalle.esta_abierta(), "panel: el botón abre el detalle")
	_check(pm._detalle.mision_actual() == "goblins_fuera",
		"panel: el detalle muestra la misión pulsada")
	_check("Goblins derrotados: 0/5" in pm._detalle._lbl_objetivos.text,
		"panel: el detalle lee el progreso del QuestLog")


## --- Orden de ESC: el detalle cierra antes que el panel ---


func _t_orden_esc() -> void:
	var pm: PanelMisiones = PM.new()
	root.add_child(pm)
	_basura.append(pm)
	var p: Player = _player(Vector3.ZERO)
	var q: QuestLog = _log()
	pm.conectar(p, q)
	q.aceptar("goblins_fuera")
	pm.alternar()
	pm._abrir_detalle("goblins_fuera")
	_check(pm._detalle.esta_abierta(), "orden: detalle abierto sobre el panel")
	# El _input del panel NO cierra el panel si el detalle está abierto.
	pm._input(_esc())
	_check(pm.esta_abierta(), "orden: ESC no cierra el panel con el detalle abierto")
	_check(pm._detalle.esta_abierta(), "orden: el panel no tocó el detalle")
	# El _input del detalle (que corre antes por ser hijo) sí lo cierra.
	pm._detalle._input(_esc())
	_check(not pm._detalle.esta_abierta(), "orden: ESC cierra el detalle")
	_check(pm.esta_abierta(), "orden: el panel sigue abierto tras cerrar el detalle")
	# Ahora ESC sí cierra el panel. Bloque 65: el panel tiene que ser la CIMA
	# de la pila para reaccionar, así que se registra como hace la demo. Sin
	# esto `es_cima` es false y el ESC ya no cerraría nada.
	PilaUI.abrir(pm)
	pm._input(_esc())
	_check(not pm.esta_abierta(), "orden: ESC cierra el panel sin detalle")
	# Cerrar el panel cierra también el detalle (no queda colgado).
	pm.alternar()
	pm._abrir_detalle("goblins_fuera")
	pm.cerrar_panel()
	_check(not pm._detalle.esta_abierta(), "orden: cerrar el panel cierra el detalle")
