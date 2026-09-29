class_name GestorArboles
extends Node
## Fase 55: coloca y retira los `Arbol` de la región, por distancia.
##
## Es `GestorVetas` con otro id y otro tipo de nodo. Misma histéresis (dentro
## de `RADIO_ALTA` entra, más allá de `RADIO_BAJA` sale, y en el medio no
## hay churn), mismo intervalo de cerebro y misma puerta de reaparición.
##
## Se podría haber hecho un `GestorRecursos` genérico para los dos. No se
## hizo porque la veta tiene su propio ciclo ya testeado (202 checks en la
## fase 45) y tocarlo metió riesgo dentro de un cambio que es de tala. Si
## aparece una tercera recolección, ese es el momento de unificar.

## Dentro de este radio se coloca el árbol. Fuera de `RADIO_BAJA` se retira.
const RADIO_ALTA: float = 700.0
## Los dos radios viven en `data/streaming.json` (fase 12.1), igual que los
## de las vetas. Si no están, se usan estos.
const FALLBACK_RADIA: float = 900.0
## Cada cuánto piensa el gestor.
const INTERVALO_SEG: float = 0.5
## Cuánto guarda la memoria del árbol que se retira, para que al volver a
## entrar aparezca en el estado en que estaba.
const RESPUESTA_PERSISTIDA: bool = true

## Hotfix 62.1: sin esta declaración `Systems.registrar` rechazaba el gestor
## con un `push_warning` (solo 4 sistemas la declaraban: GestorVetas,
## ViajeRapido, SaveSystem, Arena, RespawnHeros).
var system_id: StringName = &"gestor_arboles"

var radio_alta: float = RADIO_ALTA
var radio_baja: float = FALLBACK_RADIA

var _datos: Dictionary = {}
var _instanciados: Dictionary = {}
var _lejos: Dictionary = {}
var _jugador: Node3D = null
var _reloj: float = 0.0


func _ready() -> void:
	cargar_datos()
	radio_baja = FALLBACK_RADIA


func cargar_datos(ruta: String = "res://data/arboles.json") -> void:
	var texto: String = FileAccess.get_file_as_string(ruta)
	var datos = JSON.parse_string(texto)
	_datos = datos if datos is Dictionary else {}
	# La fase 12.1 dejó los radios en streaming.json; se respetan si están.
	var stream = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/streaming.json"))
	if stream is Dictionary:
		var s: Dictionary = stream
		radio_alta = float(s.get("radio_alta", RADIO_ALTA))
		radio_baja = float(s.get("radio_baja", FALLBACK_RADIA))
	# El streaming de vetas es el que manda: el mismo radio para los dos.
	if radio_baja <= radio_alta:
		radio_baja = radio_alta * 1.35


## Configura el jugador cuya posición manda. Sin él, el gestor no hace nada.
func fijar_jugador(j: Node3D) -> void:
	_jugador = j


func arboles() -> Array:
	return _datos.get("arboles", [])


func total() -> int:
	return (arboles() as Array).size()


func _process(delta: float) -> void:
	_reloj -= delta
	if _reloj > 0.0:
		return
	_reloj = INTERVALO_SEG
	_pensar()


## Coloca y retira según la distancia. Separado de `_process` para poder
## correrlo a mano en un test.
func _pensar() -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var pos: Vector3 = _jugador.global_position
	for a in arboles():
		var d: Dictionary = a
		var aid: String = str(d.get("id", ""))
		if aid == "":
			continue
		var p := Vector3(float(d.get("x", 0.0)), 0.0, float(d.get("z", 0.0)))
		var dist: float = pos.distance_to(p)
		if _instanciados.has(aid):
			if dist > radio_baja:
				_retirar(aid)
		elif dist <= radio_alta:
			_colocar(d)
		elif RESPUESTA_PERSISTIDA and _lejos.has(aid):
			_lejos[aid] = true


func _colocar(d: Dictionary) -> void:
	var aid: String = str(d.get("id", ""))
	if _instanciados.has(aid):
		return
	var arbol := Arbol.new()
	arbol.name = "Arbol_%s" % aid
	arbol.configurar(d)
	arbol.global_position = Vector3(float(d.get("x", 0.0)), 0.0, float(d.get("z", 0.0)))
	# La veta se pega al terreno si lo tiene; el árbol usa el mismo helper.
	if arbol.has_method("_pegar_al_terreno"):
		arbol._pegar_al_terreno()
	add_child(arbol)
	_instanciados[aid] = arbol
	_lejos.erase(aid)


func _retirar(aid: String) -> void:
	var arbol: Node = _instanciados.get(aid)
	if arbol != null and is_instance_valid(arbol):
		if RESPUESTA_PERSISTIDA:
			_lejos[aid] = true
		arbol.queue_free()
	_instanciados.erase(aid)


## Cuántos hay colocados ahora mismo (tests).
func vivos() -> int:
	return _instanciados.size()


# --- bloque 65: el estado del mundo se guarda -------------------------

## Bloque 65: qué árboles están gastados. Antes el `SaveSystem` guardaba las
## VETAS y `Refugio` tenía su `to_dict()`, pero `GestorArboles` no: los árboles
## talados reaparecían al cargar y el refugio perdía sus piezas. Guardar el
## estado del mundo A MEDIAS es peor que no guardarlo, porque el jugador ve que
## "funciona" y no se da cuenta de que pierde lo suyo.
##
## Solo se guardan los árboles que están gastados: uno con sus usos enteros es
## el estado natural y no tiene por qué ocupar espacio en el save.
func estado_para_guardar() -> Dictionary:
	var gastados: Dictionary = {}
	for d in arboles():
		var ad: Dictionary = d
		var aid: String = str(ad.get("id", ""))
		if aid == "":
			continue
		if int(ad.get("usos", 0)) < _usos_max_de(ad):
			gastados[aid] = {"usos": int(ad.get("usos", 0))}
	return {"version": 1, "arboles": gastados}


## Restaura el estado. Los que NO están en el bloque vuelven a su estado
## natural: un save viejo no debe dejar un árbol sin usar para siempre.
func cargar_estado(bloque: Dictionary) -> void:
	if bloque.is_empty():
		return
	var gastados: Dictionary = bloque.get("arboles", {})
	for d in arboles():
		var ad: Dictionary = d
		var aid: String = str(ad.get("id", ""))
		if aid == "":
			continue
		# El dato de la VETA va en la copia de `_datos`, que es la lista.
		ad["usos"] = int(gastados[aid].get("usos", ad.get("usos", 0))) \
			if gastados.has(aid) else int(ad.get("usos", 0))
		# Si el árbol ya está en el mundo, se le aplica; si no, cuando se
		# coloque, porque `_colocar` lee el dato.
		var n: Veta = _instanciados.get(aid) as Veta
		if n != null and is_instance_valid(n):
			n.usos = int(ad["usos"])


## Un árbol recién colocado tiene que herdar los usos guardados, no arrancar
## siempre cheio: si no, se recargan al hacer streaming.
func _usos_de_dato(d: Dictionary) -> int:
	var n: Veta = _instanciados.get(str(d.get("id", ""))) as Veta
	return n.usos if n != null and is_instance_valid(n) else int(d.get("usos", 0))


func _usos_max_de(d: Dictionary) -> int:
	return maxi(1, int(d.get("usos_max", 3)))
