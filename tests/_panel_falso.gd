extends CanvasLayer
## Panel de mentira para test_pila_ui.gd: replica el contrato de los 13 paneles
## reales (un `cerrar_panel()` que se desregistra de la pila y se oculta).

func cerrar_panel() -> void:
	visible = false
	PilaUI.cerrar(self)
