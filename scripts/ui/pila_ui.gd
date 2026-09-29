class_name PilaUI
extends RefCounted
## Bloque 65: el ÚNICO consumidor del ESC, y la pila de paneles abiertos.
##
## POR QUÉ EXISTE: TRECE scripts de UI se apropiaban del `cancelar_seleccion`
## por su cuenta, cada uno en su `_input`. Con un panel abierto funcionaba. Con
## dos — y abrir inventario y equipo a la vez es fácil — el ESC cerraba los dos
## a la vez o ninguno, según el orden del árbol. Es el bug clásico de "cada
## panel resuelve su propio teclado", y no se podía arreglar sin tocar los 13.
##
## El contrato nuevo es de UNA línea por panel: al abrir, `PilaUI.abrir(self)`;
## al cerrar, `PilaUI.cerrar(self)`. El ESC lo lee UNO —el de la cima— a través
## de `PilaUI.al_esc()`.
##
## Es estática a propósito: el problema que resolvió `Systems` en la 51.1 era
## justamente no tener una ruta única, y un panel colgado de un `CanvasLayer`
## deep en la escena no tiene a nadie a quien preguntarle.

## Orden de apertura. La cima es la última.
static var _pila: Array = []
## Guardamos el árbol de la escena para poder validar que el nodo sigue vivo.
static var _arbol: SceneTree = null


static func _arbol_vivo() -> SceneTree:
	if _arbol != null and is_instance_valid(_arbol):
		return _arbol
	_arbol = Engine.get_main_loop() as SceneTree
	return _arbol


## Registra un panel abierto. Idempotente: abrir dos veces el mismo panel no lo
## duplica en la pila (que es lo que pasaba con `PanelOpciones`, que se abría
## desde la pausa y desde `abrir()`).
static func abrir(panel: CanvasLayer) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	_cerrar(panel)
	_pila.append(panel)


## Desregistra. Idempotente.
static func cerrar(panel: CanvasLayer) -> void:
	_cerrar(panel)


static func _cerrar(panel: CanvasLayer) -> void:
	for i in range(_pila.size() - 1, -1, -1):
		var p: CanvasLayer = _pila[i]
		# Un panel liberado (cambio de escena) sale de la pila solo.
		if p == null or not is_instance_valid(p):
			_pila.remove_at(i)


## Cuántos paneles hay abiertos. Para los tests.
static func abierta() -> int:
	_purgar()
	return _pila.size()


static func cima() -> CanvasLayer:
	_purgar()
	if _pila.is_empty():
		return null
	return _pila[_pila.size() - 1]


static func _purgar() -> void:
	_cerrar(null)


## ¿Está este panel en la cima? Un panel que NO lo está no debe reaccionar al
## ESC: si el de arriba está abierto, el de abajo espera.
static func es_cima(panel: CanvasLayer) -> bool:
	return cima() == panel


## El ESC. Cierra SOLO el panel de la cima, y devuelve si cerró algo. La
## iteración va de la cima hacia abajo porque un panel puede cerrar otro al
## cerrarse (un submenú que cierra su padre), y eso tiene que verse al
## siguiente intento, no al siguiente frame.
static func al_esc() -> bool:
	for intento in range(_pila.size()):
		var c: CanvasLayer = cima()
		if c == null:
			return false
		if _cerrar_via(c):
			return true
		# El panel no se cerró (no tenía ESC propio): se ignora y se sigue
		# hacia abajo, para no quedarse atascado.
		_cerrar(c)
	return false


static func _cerrar_via(p: CanvasLayer) -> bool:
	# La vía preferida es un método propio, que es lo que usan los 13 paneles.
	if p.has_method("cerrar_panel"):
		p.call("cerrar_panel")
	elif p.has_method("cerrar"):
		p.call("cerrar")
	else:
		p.visible = false
	_cerrar(p)
	return true


## Vacía la pila. Lo llama el cambio de escena: los paneles de la escena
## anterior mueren con ella y no deben quedar apuntando a nodos liberados.
static func limpiar() -> void:
	_pila.clear()
