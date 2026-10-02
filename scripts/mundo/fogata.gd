class_name Fogata
extends Node3D
## Fase 56: la fogata. Es la estación de cocina y la primera pieza
## "colocable" del juego — aunque acá es fija, puesta por la demo.
##
## Las piezas colocables por el jugador llegan en la fase 61 (El Refugio).
## Esta versión es la estación: la demo pone una por ciudad, igual que los
## herreros. Que exista desde ya es lo que permite que la cocina (fase 56) no
## dependa del sistema de construcción (fase 61): si no, el círculo
## recolectar→cocinar→comer quedaría trabado hasta la última fase.
##
## - Lenna: se carga con troncos y se gasta al cocinar. Sin leña no se cocina.
## - Se apaga sola cuando se queda sin leña, y se vuelve a encender al cargarle.
## - `puede_usar()` es lo que consulta el panel y el clic.

const CAPA: int = 4
const RADIO_INTERACCION: float = 3.0
## Segundos de leña que aporta un tronco (mismo valor que `Cocina`).
const LENA_POR_TRONCO: float = 12.0
## Cuánto tarda una fogata sin leña en reintentarse.
const INTERVALO_SEG: float = 5.0

## Emitida cuando cambia la leña (la UI la escucha para pintar el icono).
signal lena_cambiada(segundos: float)
## Emitida al terminar de cocinar algo.
signal cocinado(item_id: String, cantidad: int)
## Fase 64: se acaba de prender. Para el aviso del feed.
signal llama_encendida
## Fase 64: E sobre una fogata YA encendida pide el panel de recetas.
signal cocinar_solicitado

var lena: float = 0.0
## Cuánto falta para volver a intentar encenderse sola.
var _espera: float = 0.0
## FASE 72: los `Hechos` del jugador que usa esta fogata. Los deja
## `interactuar_jugador`; sin ellos, "Fogata perenne" no hace nada.
var _hechos: Hechos = null
var _fuego: OmniLight3D = null
var _llama: MeshInstance3D = null
var _particulas: GPUParticles3D = null


func _ready() -> void:
	_construir()
	set_process(true)
	# Fase 64: el jugador lo encuentra por proximidad, no por selección (no es
	# una `Entity`). El grupo lo pone el `Player._interactuable_mas_cercano`.
	if not is_in_group(Player.GRUPO_INTERACTUABLE):
		add_to_group(Player.GRUPO_INTERACTUABLE)


func _construir() -> void:
	# Anillo de piedras: 5 icosaedros chiquitos, material compartido.
	var mat_piedra := StandardMaterial3D.new()
	mat_piedra.albedo_color = Color(0.32, 0.31, 0.30)
	mat_piedra.roughness = 1.0
	for i in range(5):
		var piedra := MeshInstance3D.new()
		var ico := SphereMesh.new()
		ico.radius = 0.28
		ico.height = 0.42
		ico.radial_segments = 6
		ico.rings = 3
		piedra.mesh = ico
		var ang: float = TAU * float(i) / 5.0
		piedra.position = Vector3(cos(ang) * 0.62, 0.12, sin(ang) * 0.62)
		piedra.material_override = mat_piedra
		add_child(piedra)

	# Llama: cono emisivo. Material propio (una fogata por ciudad, son pocas).
	_llama = MeshInstance3D.new()
	var cono := CylinderMesh.new()
	cono.top_radius = 0.02
	cono.bottom_radius = 0.3
	cono.height = 0.9
	_llama.mesh = cono
	_llama.position = Vector3(0.0, 0.5, 0.0)
	var mat_llama := StandardMaterial3D.new()
	mat_llama.albedo_color = Color(0.9, 0.35, 0.05)
	mat_llama.emission_enabled = true
	mat_llama.emission = Color(1.0, 0.55, 0.1)
	mat_llama.emission_energy_multiplier = 2.5
	_llama.material_override = mat_llama
	add_child(_llama)

	# Brasas: partículas. UNA por fogata y de vida corta (§9.5).
	_particulas = GPUParticles3D.new()
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 12.0
	pmat.initial_velocity_min = 0.7
	pmat.initial_velocity_max = 1.6
	pmat.gravity = Vector3(0, 0.4, 0)
	pmat.scale_min = 0.06
	pmat.scale_max = 0.14
	pmat.color = Color(1.0, 0.6, 0.15)
	_particulas.process_material = pmat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.1, 0.1)
	_particulas.draw_pass_1 = qm
	_particulas.amount = 24
	_particulas.lifetime = 1.2
	_particulas.position = Vector3(0.0, 0.4, 0.0)
	_particulas.emitting = false
	add_child(_particulas)

	_fuego = OmniLight3D.new()
	_fuego.light_color = Color(1.0, 0.55, 0.2)
	_fuego.light_energy = 2.0
	_fuego.omni_range = 7.0
	_fuego.position = Vector3(0.0, 0.9, 0.0)
	add_child(_fuego)

	_aplicar_estado()


## Cargar leña. Devuelve los segundos restantes.
func cargar_lena(segundos: float = LENA_POR_TRONCO) -> float:
	lena = minf(lena + maxf(segundos, 0.0), 300.0)
	_espera = 0.0
	_aplicar_estado()
	lena_cambiada.emit(lena)
	return lena


## ¿Está encendida?
func encendida() -> bool:
	return lena > 0.0


## Se puede cocinar acá (y hayalgo que cocinar).
func puede_usar() -> bool:
	return encendida()


## Gasta leña. Devuelve false si no había.
func gastar_lena(segundos: float) -> bool:
	if lena < segundos:
		return false
	lena = maxf(lena - segundos, 0.0)
	_aplicar_estado()
	lena_cambiada.emit(lena)
	return true


func _aplicar_estado() -> void:
	var on: bool = encendida()
	if _particulas != null:
		_particulas.emitting = on
	if _fuego != null:
		_fuego.light_energy = 2.0 if on else 0.0
	if _llama != null:
		_llama.visible = on


func _process(delta: float) -> void:
	# Parpadeo de la llama, como el de `Antorcha` pero sin luz real.
	if _llama != null and _llama.visible:
		var f: float = 0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.011)
		_llama.scale = Vector3(f, 0.9 + 0.2 * f, f)
	if encendida():
		return
	# Se apaga sola tras un rato sin leña: una fogata muerta no debe quedarse
	# pegando permanente.
	_espera -= delta
	if _espera > 0.0:
		return
	_espera = INTERVALO_SEG
	_reencender_perenne()


## FASE 72: el Hecho "Fogata perenne" (cocina, tramo 4) se calculaba, se
## guardaba y NINGÚN sistema lo consultaba. Esta es su única forma de existir.
##
## Qué significa "perenne": la fogata se vuelve a ENCENDER SOLA cuando se queda
## sin leña, con una carga mínima. Antes la cuenta atrás de `_espera` hacía
## exactamente nada: bajaba, se recargaba, y la fogata se quedaba muerta hasta
## el jugador trajera un tronco. La cuenta atrás ya estaba ahí, esperando.
##
## La carga mínima sale de `data/hechos.json` (`parametros.lena_minima`), no de
## una constante acá, así que el Hecho se reequilibra tocando el dato.
##
## POR QUÉ LOS HECHOS LLEGAN POR `interactuar_jugador` Y NO POR UNA BÚSQUEDA:
## la fogata es un `Node3D` del mundo y no tiene ni debe tener referencia al
## jugador. La E es el único momento en que un jugador y una fogata se conocen,
## y para entonces la fogata ya está encontrada a mano. Cachear el `Hechos` del
## primer jugador que la use es correcto para un juego local de un jugador
## (§7.1), y un `null` aquí solo significa "sin Hechos", o sea el
## comportamiento de siempre.
func _reencender_perenne() -> void:
	var hechos: Hechos = _hechos
	if hechos == null or not is_instance_valid(hechos):
		return
	if not hechos.tiene(Hechos.FLAG_FOGATA_PERENNE):
		return
	var carga: float = hechos.parametro(Hechos.ID_FOGATA_PERENNE, "lena_minima",
		LENA_POR_TRONCO)
	cargar_lena(carga)
	llama_encendida.emit()


# ---------------------------------------------- fase 64: interacción ---

## Fase 64: la fogata pasa a ser interactuable por proximidad.
##
## Antes tenía `CAPA` declarada y NINGÚN cuerpo de colisión: era un adorno
## invisible al jugador, siempre apagada, sin forma de prenderla. SeDeclare
## interactuable para que el prompt aparezca al acercarse y E la use; el
## cuerpo de colisión sigue sin hacer falta porque la distancia se mide
## contra la posición del nodo, no contra un raycast.
func texto_interaccion(j: Player) -> String:
	if encendida():
		return "Cocinar"
	if j != null and j.inventario != null and j.inventario.contar("tronco_roble") <= 0 \
			and j.inventario.contar("tronco_acacia") <= 0 \
			and j.inventario.contar("tronco_picaro") <= 0 \
			and j.inventario.contar("tronco_pino") <= 0 \
			and j.inventario.contar("tronco_sauce") <= 0:
		return "Fogata (sin leña)"
	return "Prender fogata"


## Fase 64: E en la fogata. Prende con un tronco del inventario, o avisa por
## qué no. Devuelve el motivo para que lo testee y lo muestre el feed.
func interactuar_jugador(j: Player) -> String:
	if j == null or not is_instance_valid(j):
		return "sin_jugador"
	# FASE 72: este es el momento en que la fogata y el jugador se conocen, así
	# que es donde se cachean los `Hechos`. Ver `_reencender_perenne`.
	if j.hechos != null:
		_hechos = j.hechos
	if encendida():
		# Ya arde: la E pide el panel, no vuelve a prenderla. Es la misma tecla
		# para las dos cosas y el estado de la fogata decide cuál.
		cocinar_solicitado.emit()
		return "cocinar"
	var tronco: String = _primer_tronco(j)
	if tronco == "":
		return "sin_lena"
	if not j.inventario.quitar(tronco, 1):
		return "sin_lena"
	cargar_lena(LENA_POR_TRONCO)
	llama_encendida.emit()
	return "ok"


## El primer tronco que tenga el jugador. Se prueban los cinco porque la
## tala da madera de especie según el árbol, y no tiene sentido obligar al
## jugador a llevar roble cuando taló un sauce.
func _primer_tronco(j: Player) -> String:
	if j == null or j.inventario == null:
		return ""
	for t in ["tronco_roble", "tronco_acacia", "tronco_picaro", "tronco_pino",
			"tronco_sauce"]:
		if j.inventario.contar(t) > 0:
			return t
	return ""
