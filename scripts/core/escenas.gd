class_name Escenas
extends RefCounted
## Fuente única de verdad para las escenas del flujo principal.
##
## La escena de juego es SIEMPRE la más actualizada ("demo real"):
## hoy es fase14_demo.tscn (vigente desde fase 14 hasta fase 18).
## Cuando una fase futura la reemplace, se cambia SOLO esta constante
## y el título, la creación de personaje y los tests siguen apuntando
## a la escena correcta sin divergir.

const JUEGO: String = "res://scenes/demo/fase14_demo.tscn"
const TITULO: String = "res://scenes/titulo/pantalla_titulo.tscn"
const CREACION: String = "res://scenes/creacion/creacion_personaje.tscn"
