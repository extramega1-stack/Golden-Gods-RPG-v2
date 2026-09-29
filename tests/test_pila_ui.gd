extends SceneTree
## Regresión de `PilaUI`: la pila de paneles nunca se vaciaba.
##
## POR QUÉ ESTE ARCHIVO EXISTE: dos workers independientes lo beneficiation
## reportando en el mismo día, y no había NINGÚN test sobre la pila. El bug:
##
## `_cerrar(panel)` no cerraba el panel — solo purgaba los nodos liberados de
## la escena anterior. Nunca hacía `remove_at` del panel que se le pasaba. Con
## eso:
##   - `abrir(p)` dos veces metía el mismo panel DOS veces, así que el comentario
##     "idempotente" era falso;
##   - `cerrar(p)` no desregistraba nada, el panel cerrado seguía en la cima;
##   - `al_esc()` sacaba la misma cima para siempre y nunca bajaba al panel de
##     abajo. O sea: con dos paneles abiertos, el ESC no bajaba un nivel, y con
##     el mismo panel abierto dos veces había que apretar ESC dos veces para
##     llegar a nada.
##
## Por eso `PilaUI` era el UNICO consumidor del ESC en todo el repo y aun así
## no tenía un solo test.

var _ok: int = 0
var _fallos: int = 0


func _init() -> void:
	_run()


func _run() -> void:
	print("[TEST] PilaUI — la pila de paneles")
	_ciclo_basico()
	_idempotencia_al_abrir()
	_cerrar_desregistra()
	_esc_baja_de_un_nivel()
	_esc_sin_panel()
	_esc_con_panel_sin_manejador()
	_limpiar()
	print("[TEST] pila_ui: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] %s%s" % [nombre, "" if detalle == "" else "  <-- " + detalle])


## Un panel de mentira: alcanza con que sea un CanvasLayer con los mismos
## métodos que usan los 13 paneles reales.
func _panel(nombre: String) -> CanvasLayer:
	var c := CanvasLayer.new()
	c.name = nombre
	c.visible = false
	c.set_script(load("res://tests/_panel_falso.gd"))
	return c


func _ciclo_basico() -> void:
	PilaUI.limpiar()
	var a := _panel("A")
	PilaUI.abrir(a)
	_chk(PilaUI.abierta() == 1, "abrir uno deja la pila con 1", str(PilaUI.abierta()))
	_chk(PilaUI.cima() == a, "y ese uno es la cima", "")
	_chk(PilaUI.es_cima(a), "es_cima() lo reconoce", "")
	a.free()


func _idempotencia_al_abrir() -> void:
	PilaUI.limpiar()
	var a := _panel("A")
	PilaUI.abrir(a)
	PilaUI.abrir(a)
	PilaUI.abrir(a)
	# ESTE es el bug: sin `_sacar`, tres `abrir` dejaban tres entradas y había
	# que apretar ESC tres veces.
	_chk(PilaUI.abierta() == 1,
		"abrir el mismo panel 3 veces deja 1, no 3 (era el bug)",
		"pila=%d" % PilaUI.abierta())
	a.free()


func _cerrar_desregistra() -> void:
	PilaUI.limpiar()
	var a := _panel("A")
	PilaUI.abrir(a)
	PilaUI.cerrar(a)
	_chk(PilaUI.abierta() == 0, "cerrar() saca el panel de la pila (era el bug)",
		"pila=%d" % PilaUI.abierta())
	_chk(PilaUI.cima() == null, "y la cima queda vacía", "")
	# Idempotente: cerrar dos veces no rompe.
	PilaUI.cerrar(a)
	_chk(PilaUI.abierta() == 0, "cerrar dos veces sigue dejando 0", "")
	a.free()


## El caso que reportaba el usuario sin saberlo: dos paneles abiertos, ESC tiene
## que bajar UN nivel, no quedarse pegado en la misma cima.
func _esc_baja_de_un_nivel() -> void:
	PilaUI.limpiar()
	var a := _panel("A")
	var b := _panel("B")
	PilaUI.abrir(a)
	PilaUI.abrir(b)
	_chk(PilaUI.abierta() == 2, "hay 2 paneles en la pila", str(PilaUI.abierta()))
	_chk(PilaUI.cima() == b, "el último abierto es la cima", "")

	_chk(PilaUI.al_esc(), "el primer ESC devuelve true (cerró algo)", "")
	_chk(PilaUI.abierta() == 1, "y baja a 1 panel", "pila=%d" % PilaUI.abierta())
	_chk(PilaUI.cima() == a,
		"la cima AHORA es el de abajo, no el mismo otra vez (era el bug)", "")

	_chk(PilaUI.al_esc(), "el segundo ESC también", "")
	_chk(PilaUI.abierta() == 0, "y la pila queda vacía", "pila=%d" % PilaUI.abierta())
	a.free()
	b.free()


func _esc_sin_panel() -> void:
	PilaUI.limpiar()
	_chk(not PilaUI.al_esc(), "ESC con la pila vacía devuelve false", "")
	_chk(PilaUI.cima() == null, "y no hay cima", "")


## Un panel sin `cerrar_panel` ni `cerrar` tiene que igual dejar de tapar la
## pila, o el ESC se queda atascado en él para siempre.
func _esc_con_panel_sin_manejador() -> void:
	PilaUI.limpiar()
	var mudo := CanvasLayer.new()
	mudo.name = "Mudo"
	var a := _panel("A")
	PilaUI.abrir(mudo)
	PilaUI.abrir(a)
	_chk(PilaUI.cima() == a, "el que se abrio ultimo es la cima", "")
	_chk(PilaUI.al_esc(), "el primer ESC cierra la cima (el que tiene manejador)", "")
	_chk(PilaUI.cima() == mudo, "y ahora la cima es el mudo", "")
	_chk(mudo.visible, "el mudo sigue visible: nadie lo ocultó todavía", "")
	# Segundo ESC: ahora le toca al mudo, que no tiene `cerrar_panel` ni
	# `cerrar`. El fallback tiene que ocultarlo Y sacarlo de la pila; si solo lo
	# oculta, el tercero se queda atascado en él.
	_chk(PilaUI.al_esc(), "el segundo ESC también devuelve true (fallback)", "")
	_chk(not mudo.visible, "el panel mudo queda oculto", "")
	_chk(PilaUI.abierta() == 0,
		"y el mudo NO queda atascado en la cima tapando a los de abajo",
		"pila=%d" % PilaUI.abierta())
	_chk(not PilaUI.al_esc(), "el tercero ya no encuentra nada", "")
	mudo.free()
	a.free()


## El cambio de escena llama `limpiar()`: los paneles de la escena anterior
## mueren con ella y no deben quedar apuntando a nodos liberados.
func _limpiar() -> void:
	PilaUI.limpiar()
	var a := _panel("A")
	PilaUI.abrir(a)
	PilaUI.limpiar()
	_chk(PilaUI.abierta() == 0, "limpiar() vacia la pila", "")
	_chk(PilaUI.cima() == null, "y no queda cima colgando a un nodo muerto", "")
	a.free()
