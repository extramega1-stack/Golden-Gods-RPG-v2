extends SceneTree
## Fase 45.2: los avisos tienen que verse DE VERDAD.
##
## El bug: el `CanvasLayer` del toast (capa 15, el feed global de avisos) era
## hijo del `PanelMisiones`, que arranca `visible = false` → NINGÚN aviso se
## veía nunca (tutorial de la fase 39, avisos de arena y de viaje incluidos).
## Y al colgarlo de la escena, `add_child` directo falla porque la escena está
## ocupada añadiendo sus hijos: tiene que ser diferido.
##
## Este test monta el panel REAL y el tutorial REAL (no un Callable de
## mentira, que es como el bug pasó desapercibido) y comprueba que el aviso se
## enciende, se ve con el panel cerrado y se apaga solo.
##
## Cómo correrlo:
##   godot --headless --path <proyecto> --script res://tests/test_fase45_2_toast.gd

const PM: GDScript = preload("res://scripts/ui/panel_misiones.gd")
const TU: GDScript = preload("res://scripts/tutorial/tutorial.gd")

var _ok: int = 0
var _fallos: int = 0
var _f: int = 0
var _hecho: bool = false
var _escena: Node3D = null
var _panel: PanelMisiones = null


func _init() -> void:
	ItemDB.cargar()
	_escena = Node3D.new()
	root.add_child(_escena)
	_panel = PM.new()
	_panel.name = "PanelMisiones"
	_escena.add_child(_panel)


func _process(_d: float) -> bool:
	if _hecho:
		return false
	_f += 1
	# Frame 3: el add_child diferido del layer ya se ha aplicado.
	if _f < 3:
		return false
	_hecho = true
	_comprobar()
	print("[TEST] fase45.2_toast: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)
	return true


func _comprobar() -> void:
	var panel: PanelMisiones = _panel
	_chk(panel.visible == false, "el panel de misiones arranca oculto")
	_chk(panel._toast_layer != null, "existe el layer del toast")
	_chk(panel._toast_layer.is_inside_tree(),
		"el layer del toast CUELGA del árbol (antes se quedaba huérfano)")
	_chk(panel._toast_layer.get_parent() == _escena,
		"el toast cuelga de la ESCENA, no del panel (si no, no se ve nunca)",
		"padre=%s" % str(panel._toast_layer.get_parent()))
	_chk(panel._toast_layer.layer == 15, "el toast va en la capa 15 (rango HUD)")
	_chk(panel._toast_layer.visible == false, "y arranca apagado")

	# El tutorial REAL, con el panel REAL como destino de los avisos.
	var tut: Tutorial = TU.new()
	_escena.add_child(tut)
	tut.conectar(null, null, Callable(panel, "toast"))
	tut.empezar()
	_chk(tut.paso_actual() == 0, "el tutorial arranca en el paso 0")
	_chk(panel._toast_layer.visible, "al empezar, se enciende el layer del toast")
	_chk(panel._toast_panel.visible, "y se enciende el panel del aviso")
	_chk(str(panel._toast_label.text) == "Muévete con WASD o clic izquierdo",
		"el texto del paso 1 es el de 'mover'", str(panel._toast_label.text))

	# Y con el panel de misiones CERRADO (que es como se juega): el aviso
	# sigue visible, porque cuelga de la escena y no del panel.
	panel.cerrar_panel()
	_chk(panel.visible == false, "el panel de misiones está cerrado")
	_chk(panel._toast_layer.visible, "con el panel cerrado, el aviso SIGUE visible")
	_chk(panel._toast_panel.visible, "y sigue en pantalla")

	# Y se apaga solo cuando acaba su temporizador.
	panel._ocultar_toast()
	_chk(panel._toast_layer.visible == false, "el aviso se apaga solo")
	_chk(panel._toast_panel.visible == false, "y el panel del aviso también")


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] " + nombre + ("" if detalle == "" else "  <-- " + detalle))
