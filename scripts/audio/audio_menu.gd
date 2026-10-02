class_name AudioMenu
extends RefCounted
## Fase 72: el audio del MENÚ, que era CERO.
##
## EL HECHO QUE ARREGLA: `AudioJuego`, `Musica` y `DirectorMusica` se creaban
## en `fase9_demo.gd`, que es la escena de JUEGO. `pantalla_titulo.gd` solo
## construía su 3D y sus botones. El juego arrancaba en silencio: el menú
## principal, la pantalla de carga y el primer segundo de partida no tenían
## ni un ruido. Y como `Opciones.cargar()` + `aplicar()` se llamaban en
## `_al_mundo_listo()` —DESPUÉS de la pantalla de carga—, un jugador que
## guardó la música a -20 dB escuchaba el título y la carga a volumen lleno.
##
## Son tres cosas en un solo sitio, y por eso es una clase y no tres:
## - El `AudioJuego` + `Musica` del menú, con la música en estado de menú.
## - `Opciones.cargar()` + `aplicar_volumenes()`, ANTES de que suene nada:
##   el volumen guardado vale desde el PRIMER sonido.
## - `limpiar()`, que se llama al entrar a partida. El nodo cuelga de la
##   escena del título y muere con ella, pero sin esto la música se corta en
##   seco en pleno fundido a negro.
##
## POR QUÉ ES ESTÁTICA Y SIN ESTADO, como `SonidoUI`: se llama desde un
## `_ready` de pantalla, sin cablearlo, y su trabajo termina al construirse.

const M_ZONA_MENU: String = "titulo"


## Monta el audio del menú bajo `padre`. Idempotente por padre: si ya hay un
## `AudioMenu` colgando, lo devuelve en vez de crear un segundo bus de música.
static func montar(padre: Node) -> AudioJuego:
	if padre == null or not is_instance_valid(padre):
		return null
	var ya: Node = padre.get_node_or_null(NOMBRE)
	if ya != null and is_instance_valid(ya):
		return ya as AudioJuego

	# 1. Las opciones PRIMERO. Los buses no existen hasta que hay un
	# `AudioJuego`, así que cargar va antes y aplicar después: al revés, el
	# título arranca a volumen lleno y recién se corrige un frame después.
	Opciones.cargar()

	var audio := AudioJuego.new()
	audio.name = NOMBRE
	padre.add_child(audio)

	var musica := Musica.new()
	musica.name = "MusicaMenu"
	padre.add_child(musica)
	# El estado de menú es el de pueblo: la capa `base` sola, sin percusión de
	# combate. Es lo que un menú tiene que sonar (calmo, sin urgencia) y ya
	# está generado y testeado; no hace falta un quinto tema.
	musica.cambiar_estado(Musica.CAPA_BASE)

	# 3. El fondo del menú: viento de la mezcla "titulo" de `data/ambiente.json`.
	# Es la respuesta al bus `Ambiente` que el bloque 66 creaba y nunca tuvo
	# un solo player.
	var ambiente := AmbienteZona.new()
	ambiente.name = "AmbienteMenu"
	padre.add_child(ambiente)
	ambiente.fijar_zona(M_ZONA_MENU)

	# 4. Y ahora sí: los buses existen, así que el volumen guardado entra.
	Opciones.aplicar_volumenes()
	return audio


## Corta el audio del menú antes de cambiar de escena. La música baja en
## 0,35 s en vez de morir en seco: el corte seco se oye POR ENCIMA del fundido
## a negro, y el fundido a negro es justo lo que tapa el cambio de escena.
static func limpiar(padre: Node) -> void:
	if padre == null or not is_instance_valid(padre):
		return
	var m: Node = padre.get_node_or_null("MusicaMenu")
	if m == null or not is_instance_valid(m):
		return
	var musica: Musica = m as Musica
	if musica != null:
		musica.silenciar(FUNDIDO_SALIDA)


## El nodo del `AudioJuego` del menú, o null si esta pantalla no lo montó.
static func audio_de(padre: Node) -> AudioJuego:
	if padre == null or not is_instance_valid(padre):
		return null
	var n: Node = padre.get_node_or_null(NOMBRE)
	return n as AudioJuego


const NOMBRE: String = "AudioJuegoMenu"
const FUNDIDO_SALIDA: float = 0.35