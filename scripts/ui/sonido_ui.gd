class_name SonidoUI
extends RefCounted
## Bloque 66: el punto único para los sonidos de interfaz.
##
## POR QUÉ UNA clase y no `AudioJuego.reproducir("clic")` en cada botón: había
## 20 sitios donde haría falta y se olvidaría la mitad. Con un helper, "abrir
## un panel suena" es una regla del sistema, no una decisión de cada panel.
##
## Todos son 2D (el sonido de interfaz es del jugador, no del mundo) y pasan
## por el antirepeticion, así que arrastrar un deslizador rápido no suena
## como una ráfaga de ametralladora.
##
## Es estática y sin estado: se llama desde cualquier panel sin cablearlo.

## Un clic genérico de botón. El sonido de UI más característico del juego.
static func clic() -> void:
	AudioJuego.reproducir("clic")


static func abrir_panel() -> void:
	AudioJuego.reproducir("abrir_panel")


static func cerrar_panel() -> void:
	AudioJuego.reproducir("cerrar_panel")


static func error() -> void:
	AudioJuego.reproducir("error")


static func exito() -> void:
	AudioJuego.reproducir("mision")


static func nivel() -> void:
	AudioJuego.reproducir("level_up")


static func hecho() -> void:
	AudioJuego.reproducir("hecho")


## El aviso del jugador al recibir daño. Distinto del "golpe" del atacante:
## este es grave y propio, porque lo recibe el jugador y tiene que distinguirlo.
static func jugador_danio() -> void:
	AudioJuego.reproducir("dano_recibido")


## El mismo "clic", pero de una vez: Conecta el sonido al botón y lo devuelve,
## para poder escribir `caja.add_child(SonidoUI.boton(Button.new()))` sin que
## el panel tenga que acordarse del `pressed.connect`.
##
## POR QUÉ ES UN HELPER Y NO UNA REGLA GLOBAL: Godot no tiene "clic de botón"
## global (un `Theme` no emite señales), así que sin esto hay 42 botones
## repartidos en 20 archivos y la mitad se olvidaría. Con esto hay UN lugar
## donde se enchufa y el resto del panel no se entera.
static func boton(b: Button) -> Button:
	if b == null:
		return b
	if not b.pressed.is_connected(_clic_al_presionar):
		b.pressed.connect(_clic_al_presionar)
	return b


static func _clic_al_presionar() -> void:
	clic()
