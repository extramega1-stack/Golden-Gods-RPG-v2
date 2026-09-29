class_name MarcadorObjetivo
extends Node3D
## FASE 69 — la marca en el MUNDO del objetivo del tutorial.
##
## EL PROBLEMA QUE RESUELVE: el tutorial de la fase 39 era una lista de
## textos sueltos por toast. "Atacá con T" no dice a quién; "hablá con Ilya"
## no dice dónde está Ilya. Un jugador nuevo se queda parado en la plaza sin
## saber hacia dónde caminar. Esta clase es el "hacé esto AQUÍ": un haz de
## luz visible desde cualquier punto de la plaza, con el nombre del objetivo
## arriba.
##
## Es una baliza, no un asset: `CylinderMesh` + `TorusMesh` + `Label3D`
## generados por código (el mismo patrón que el "!" de misión de `NPC`).
## Cuesta 3 mallas y una etiqueta.
##
## §9.5: nace OCULTO y se enciende/apaga; nunca se crea ni se destruye en
## caliente. `_process` corre solo mientras está visible, y solo hace girar
## el aro y flotar la etiqueta: no lee nada del juego.
##
## Un nodo 3D normal: cuelga de la escena del juego (el Tutorial lo añade
## como hijo suyo, que a su vez cuelga de la demo, que es un Node3D).

## Altura del haz y del aro, en metros.
const ALTO_HAZ: float = 26.0
const RADIO_HAZ: float = 0.9
const ALTO_ARO: float = 0.18
const RADIO_ARO: float = 1.7
## Alto del texto sobre el suelo.
const ALTO_TEXTO: float = 3.4
## Velocidad de giro del aro (rad/s) y de flotación del texto.
const VEL_GIRO: float = 1.6
const VEL_FLOTACION: float = 1.1
const AMP_FLOTACION: float = 0.22

const COLOR_HAZ: Color = Color(1.0, 0.78, 0.22, 0.30)
const COLOR_ARO: Color = Color(1.0, 0.86, 0.35, 0.85)
const COLOR_TEXTO: Color = Color(1.0, 0.9, 0.5)

var _haz: MeshInstance3D = null
var _aro: MeshInstance3D = null
var _texto: Label3D = null
## Nodo vivo al que seguir (un NPC, un mob). Si es null, el marcador se
## queda clavado en `_punto`.
var _seguir: Node3D = null
var _punto: Vector3 = Vector3.ZERO
var _tiene_punto: bool = false
var _fase: float = 0.0
var _base_texto: float = ALTO_TEXTO


func _ready() -> void:
	# Los nodos se construyen AQUÍ y no en `_init`: un `_init` que cuelga
	# hijos de un `self` que todavía no está en el árbol es exactamente el
	# patrón frágil que la fase 14.1 corrigió en el Toast.
	_construir()
	apagar()
	set_process(false)


func _construir() -> void:
	_haz = MeshInstance3D.new()
	_haz.name = "Haz"
	var cil := CylinderMesh.new()
	cil.top_radius = RADIO_HAZ
	cil.bottom_radius = RADIO_HAZ
	cil.height = ALTO_HAZ
	cil.radial_segments = 10
	cil.rings = 1
	_haz.mesh = cil
	_haz.position = Vector3(0.0, ALTO_HAZ * 0.5, 0.0)
	_haz.material_override = _material(COLOR_HAZ, true)
	_haz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_haz.extra_cull_margin = 40.0
	add_child(_haz)

	_aro = MeshInstance3D.new()
	_aro.name = "Aro"
	var toro := TorusMesh.new()
	toro.inner_radius = RADIO_ARO - RADIO_ARO * 0.12
	toro.outer_radius = RADIO_ARO
	toro.rings = 24
	toro.ring_segments = 8
	_aro.mesh = toro
	_aro.position = Vector3(0.0, 0.12, 0.0)
	_aro.material_override = _material(COLOR_ARO, false)
	_aro.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aro)

	_texto = Label3D.new()
	_texto.name = "Texto"
	_texto.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_texto.font_size = 64
	_texto.outline_size = 14
	_texto.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_texto.no_depth_test = true
	_texto.modulate = COLOR_TEXTO
	_texto.position = Vector3(0.0, ALTO_TEXTO, 0.0)
	_texto.visible = false
	add_child(_texto)


## Material compartido: sin `shading_mode` ni `blend` tocados se ve como
## piedra; el haz tiene que leerse a contraluz. `no_depth_test` lo deja
## verse a través de las murallas de la ciudad (que es justo lo que un
## jugador perdido necesita).
func _material(color: Color, translucido: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = (BaseMaterial3D.TRANSPARENCY_ALPHA
		if translucido else BaseMaterial3D.TRANSPARENCY_DISABLED)
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.disable_receive_shadows = true
	return m


## Enciende la marca siguiendo un nodo (NPC o mob) o, si `nodo` es null, en
## un punto fijo del mundo. `etiqueta` es el texto que flota arriba.
func encender(nodo: Node3D, punto: Vector3, etiqueta: String) -> void:
	_seguir = nodo
	_punto = punto
	_tiene_punto = true
	if _texto != null:
		_texto.text = etiqueta
		_texto.visible = etiqueta != ""
	visible = true
	set_process(true)
	_actualizar_posicion()
	_fase = 0.0


## Apaga la marca. Se usa al terminar o saltar el tutorial, y cuando un paso
## no tiene objetivo (una tecla no se marca en el mapa).
func apagar() -> void:
	_seguir = null
	_tiene_punto = false
	visible = false
	set_process(false)
	if _texto != null:
		_texto.text = ""
		_texto.visible = false


func _process(delta: float) -> void:
	_fase += delta
	if _aro != null:
		_aro.rotate_y(VEL_GIRO * delta)
		_aro.position.y = 0.12 + sin(_fase * 2.0) * 0.06
	if _texto != null:
		_texto.position.y = ALTO_TEXTO + sin(_fase * VEL_FLOTACION) * AMP_FLOTACION
	_actualizar_posicion()


## El marcador se planta donde está el objetivo. Con nodo vivo lo sigue
## (el mob puede caminar); con punto fijo se queda.
func _actualizar_posicion() -> void:
	if not _tiene_punto:
		return
	if _seguir != null and is_instance_valid(_seguir):
		global_position = _seguir.global_position
	else:
		_seguir = null
		global_position = _punto


## ¿Está la marca encendida ahora? (tests + UI).
func esta_encendido() -> bool:
	return visible


## Posición actual de la marca (tests).
func posicion_marca() -> Vector3:
	return global_position


## Texto flotante (tests).
func etiqueta() -> String:
	return "" if _texto == null else _texto.text
