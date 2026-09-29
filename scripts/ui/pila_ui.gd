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
	_sacar(panel)
	_pila.append(panel)


## Desregistra. Idempotente.
static func cerrar(panel: CanvasLayer) -> void:
	_sacar(panel)


## Saca UN panel de la pila.
static func _sacar(panel: CanvasLayer) -> void:
	if panel == null:
		return
	_purgar()
	for i in range(_pila.size() - 1, -1, -1):
		if _pila[i] == panel:
			_pila.remove_at(i)


## Saca los paneles MUERTOS (los de la escena anterior, al cambiar de escena).
static func _purgar() -> void:
	for i in range(_pila.size() - 1, -1, -1):
		# Sin tipar a propósito: una referencia liberada no es asignable a un
		# `CanvasLayer` tipado sin quejarse en GDScript, y el chequeo de vida es
		# lo único que importa acá.
		var p = _pila[i]
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


## ¿Está este panel en la cima? Un panel que NO lo está no debe reaccionar al
## ESC: si el de arriba está abierto, el de abajo espera.
static func es_cima(panel: CanvasLayer) -> bool:
	return cima() == panel


## El ESC. Cierra SOLO el panel de la cima, y devuelve si cerró algo. La
## iteración va de la cima hacia abajo porque un panel puede cerrar otro al
## cerrarse (un submenú que cierra su padre), y eso tiene que verse al
## siguiente intento, no al siguiente frame.
static func al_esc() -> bool:
	for _intento in range(_pila.size()):
		_purgar()
		if _pila.is_empty():
			return false
		var c: CanvasLayer = _pila[_pila.size() - 1]
		if _cerrar_via(c):
			return true
		# `c` no se dejó cerrar: se lo saca igual, o el próximo ESC vuelve a
		# pegarle al mismo y el de abajo no llega a cerrarse nunca.
		_sacar(c)
	return false


static func _cerrar_via(p: CanvasLayer) -> bool:
	# La vía preferida es un método propio, que es lo que usan los 13 paneles.
	if p.has_method("cerrar_panel"):
		p.call("cerrar_panel")
	elif p.has_method("cerrar"):
		p.call("cerrar")
	else:
		p.visible = false
	# Saca el panel de la pila: si no, el ESC siguiente vuelve a pegarle al
	# mismo y nunca baja al de abajo. Aunque el panel ya se haya desregistrado
	# solo desde su `cerrar_panel()`, sacarlo otra vez es inofensivo.
	_sacar(p)
	return true


## Vacía la pila. Lo llama el cambio de escena: los paneles de la escena
## anterior mueren con ella y no deben quedar apuntando a nodos liberados.
static func limpiar() -> void:
	_pila.clear()
