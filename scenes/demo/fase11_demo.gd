extends "res://scenes/demo/fase9_demo.gd"
## Demo de la fase 11: el flujo título → creación → juego.
##
## Hereda TODO de fase9_demo (scaffolding compartido; su comportamiento no
## cambia) y al arrancar resuelve la sesión:
## - `DatosSesion.continuar` (botón "Continuar" del título) → carga la
##   partida guardada con `_cargar_partida_guardada()` (el flujo del F10:
##   reconecta paneles, recoloca la cámara y refresca el HUD).
## - Si no (nueva partida desde la creación) → `DatosSesion.aplicar_a`
##   fija nombre + clase en el jugador.
## Después limpia la sesión: nada persiste entre partidas.


func _ready() -> void:
	super._ready()
	_al_iniciar()


func _al_iniciar() -> void:
	if DatosSesion.continuar:
		_cargar_partida_guardada()
	else:
		DatosSesion.aplicar_a(_jugador)
		# Fase 18: la barra se conectó en super._ready() con la clase por
		# defecto; tras aplicar la clase elegida se refrescan el layout
		# (skills de la clase) y el libro de habilidades.
		_barra.restablecer_defecto()
		_barra.reconstruir_libro()
	DatosSesion.limpiar()
