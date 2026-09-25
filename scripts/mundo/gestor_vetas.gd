class_name GestorVetas
extends Node
## Gestor de vetas mineras (fase 45): coloca los nodos `Veta` de la región
## donde está el jugador, escucha su intención de minar y guarda el estado.
##
## REGLA DURA: los 12 nodos no viven todos en el mapa. Como el streaming de
## mobs (fase 12.1) pero con histéresis propia: se instancia la veta al entrar
## en `RADIO_ALTA` y se libera al salir de `RADIO_BAJA`. Doce son pocos, así
## que no hay pool: se crean y se liberan con `queue_free()`.
##
## La Y de cada veta la pone el terreno (`Terreno.altura_en`), no el JSON: el
## `data/vetas.json` solo trae x/z.
##
## Sin UI y sin referencias a la UI: el mundo avisa por señales y el jugador
## solo aporta su posición. El guardado va en su propio bloque (`mineria`).

## Se	minó un golpe con éxito (lo escucha la UI de la demo).
signal minado(veta_id: String, item_id: String, cantidad: int, xp: int)
## Una veta se agotó (empezó su cuenta atrás de 180 s).
signal veta_agotada(veta_id: String)
## Una veta volvió a estar minable.
signal veta_reaparecida(veta_id: String)

## Radio de entrada: a menos de esto la veta existe en el mapa.
const RADIO_ALTA: float = 700.0
## Radio de salida (mayor que el de entrada: histéresis, como el streaming).
const RADIO_BAJA: float = 900.0
## Segundos entre revisiones de posición (las vetas no se mueven: 0.5 va sobra).
const INTERVALO_SEG: float = 0.5

const SAVE_VERSION: int = 1

var _jugador: Player = null
var _terreno: Terreno = null
var _logica: Mineria = null
## [{id, origen: Vector3, nodo: Veta}] — mismo contrato que StreamingMobs.
var _registros: Array = []
var _acum: float = 0.0
## Estados de vetas lejanas (usos + respawn) que aún no tienen nodo: si el
## jugador vuelve antes de que termine el reloj, la veta aparece agotada.
var _lejanas: Dictionary = {}


func _ready() -> void:
	_logica = Mineria.new()
	_logica.minado.connect(_al_minado)


## Registra las vetas a colocar. Cada entrada: {id, origen: Vector3} o
## {id, x, z}. Las que no existen en `VetaDB` se ignoran con aviso.
func configurar(entradas: Array, terreno: Terreno = null) -> void:
	_terreno = terreno
	_registros.clear()
	for e in entradas:
		if not (e is Dictionary):
			continue
		var ed: Dictionary = e
		var vid: String = str(ed.get("id", ""))
		if vid == "" or not VetaDB.existe(vid):
			push_warning("[GestorVetas] veta desconocida: '%s'" % vid)
			continue
		var origen: Vector3 = ed.get("origen", VetaDB.posicion_de(vid))
		_registros.append({"id": vid, "origen": origen, "nodo": null})


## Registra todas las vetas de `data/vetas.json` (atajo: el generador ya dejó
## las 12 colocadas, no hace falta filtrar por región).
func configurar_desde_datos() -> void:
	var entradas: Array = []
	for vid in VetaDB.ids():
		entradas.append({"id": vid, "origen": VetaDB.posicion_de(vid)})
	configurar(entradas, _terreno)


func fijar_jugador(j: Player) -> void:
	_jugador = j
	if _jugador == null:
		return
	if not _jugador.minar_solicitado.is_connected(_al_minar_solicitado):
		_jugador.minar_solicitado.connect(_al_minar_solicitado)


func fijar_terreno(t: Terreno) -> void:
	_terreno = t


## Crea la veta en su punto (con la Y del terreno) y devuelve el nodo.
## `configurar` va ANTES de `add_child`: el cuerpo se construye en `_ready`
## y necesita el tinte del mineral.
func instanciar(veta_id: String, origen: Vector3) -> Veta:
	var v: Veta = Veta.new()
	v.name = "Veta_%s" % veta_id
	v.configurar(VetaDB.obtener(veta_id))
	add_child(v)
	if _terreno != null:
		v.global_position = Vector3(origen.x, _terreno.altura_en(origen.x, origen.z), origen.z)
	else:
		v.global_position = origen
	v.agotada.connect(_al_veta_agotada)
	v.reaparecida.connect(_al_veta_reaparecida)
	return v


func conteo_registros() -> int:
	return _registros.size()


func conteo_vetas() -> int:
	var n: int = 0
	for r in _registros:
		if _nodo_de(r) != null:
			n += 1
	return n


## Minar por id (la vía que usan los tests y el mundo). Delega en `Mineria`.
func minar(veta_id: String, jugador: Player) -> String:
	var v: Veta = veta(veta_id)
	if v == null:
		return "veta_nula"
	return _logica.minar(v, jugador)


## Nodo de una veta si está en el mapa (null si está lejos del jugador).
func veta(veta_id: String) -> Veta:
	for r in _registros:
		var rd: Dictionary = r
		if str(rd.get("id", "")) == veta_id:
			return _nodo_de(rd)
	return null


## Veta minable más cercana al jugador ("" si no hay ninguna a tiro).
func veta_minable_mas_cercana() -> String:
	if _jugador == null:
		return ""
	var mejor: String = ""
	var mejor_d: float = INF
	for r in _registros:
		var rd: Dictionary = r
		var v: Veta = _nodo_de(rd)
		if v == null or not v.esta_minable():
			continue
		var d: float = _dist_plana(_jugador.global_position, rd["origen"])
		if d < mejor_d:
			mejor_d = d
			mejor = str(rd.get("id", ""))
	return mejor


## Vuelca el estado de TODAS las vetas (con nodo o no) para el guardado.
func estado_para_guardar() -> Dictionary:
	var vetas: Dictionary = {}
	for r in _registros:
		var rd: Dictionary = r
		var vid: String = str(rd.get("id", ""))
		var v: Veta = _nodo_de(rd)
		if v != null:
			vetas[vid] = v.to_dict()
		elif _lejanas.has(vid):
			vetas[vid] = _lejanas[vid]
	return {"version": SAVE_VERSION, "vetas": vetas}


## Restaura el estado guardado. Las vetas sin nodo quedan en `_lejanas` y se
## aplican al instanciarse (así un guardado a mitad de respawn no regala la
## veta). Nunca borra usos: restaura como máximo lo que había.
func cargar_estado(bloque: Dictionary) -> void:
	if bloque.is_empty():
		return
	var version: int = int(bloque.get("version", 0))
	if version != SAVE_VERSION:
		push_warning("[GestorVetas] versión de guardado no soportada: %d (esperada %d)"
			% [version, SAVE_VERSION])
	var vetas: Dictionary = bloque.get("vetas", {})
	for vid in vetas:
		if not (vetas[vid] is Dictionary):
			continue
		var vd: Dictionary = vetas[vid]
		var v: Veta = veta(str(vid))
		if v != null:
			v.restaurar(vd)
		else:
			_lejanas[str(vid)] = vd
	aplicar_estado_lejano()


## Aplica a los nodos vivos lo que se guardó de vetas lejanas y limpia lo ya
## aplicado (se llama al instanciar y tras cargar).
func aplicar_estado_lejano() -> void:
	if _lejanas.is_empty():
		return
	for r in _registros:
		var rd: Dictionary = r
		var vid: String = str(rd.get("id", ""))
		var v: Veta = _nodo_de(rd)
		if v == null or not _lejanas.has(vid):
			continue
		v.restaurar(_lejanas[vid])
		_lejanas.erase(vid)


func _process(delta: float) -> void:
	_acum += delta
	if _acum < INTERVALO_SEG:
		return
	_acum = 0.0
	actualizar()


## Instancia las vetas cercanas y libera las lejanas (con histéresis).
func actualizar() -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	var jp: Vector3 = _jugador.global_position
	for r in _registros:
		var rd: Dictionary = r
		var nodo: Veta = _nodo_de(rd)
		var origen: Vector3 = rd["origen"]
		var d: float = _dist_plana(jp, origen)
		if nodo == null:
			if d <= RADIO_ALTA:
				rd["nodo"] = instanciar(str(rd.get("id", "")), origen)
		elif d > RADIO_BAJA:
			# Antes de liberar se guarda SIEMPRE su estado: si no, una veta
			# a la que le quedaban usos (sin estar agotada) volvería llena al
			# regresar y minarla sería infinito.
			_lejanas[nodo.veta_id] = nodo.to_dict()
			nodo.queue_free()
			rd["nodo"] = null
	# Una veta recién instanciada puede tener estado pendiente (estaba lejos
	# cuando se cargó la partida, o se liberó con usos gastados).
	aplicar_estado_lejano()


## El jugador llegó a una veta y/minó (o, si estaba lejos, ya caminó hasta
## ella). `Mineria` pone el motivo; la UI de la demo muestra el error si no
## fue "ok".
func _al_minar_solicitado(v: Veta) -> void:
	if v == null or _jugador == null:
		return
	var motivo: String = _logica.minar(v, _jugador)
	if motivo != "ok":
		v.mostrar_aviso(Mineria.texto_motivo(motivo))


func _al_minado(veta_id: String, item_id: String, cantidad: int, xp: int) -> void:
	minado.emit(veta_id, item_id, cantidad, xp)


func _al_veta_agotada(veta_id: String) -> void:
	veta_agotada.emit(veta_id)


func _al_veta_reaparecida(veta_id: String) -> void:
	veta_reaparecida.emit(veta_id)


## Nodo del registro, o null si está liberado (puede estar en la cola de
## borrado tras un `queue_free`).
func _nodo_de(registro: Dictionary) -> Veta:
	var n: Variant = registro.get("nodo", null)
	if n == null:
		return null
	var v: Veta = n as Veta
	if v == null or not is_instance_valid(v):
		registro["nodo"] = null
		return null
	return v


## Distancia en el plano (la Y del terreno no cuenta: el jugador y la veta
## están los dos pegados al suelo).
func _dist_plana(a: Vector3, b: Vector3) -> float:
	var d: Vector3 = a - b
	d.y = 0.0
	return d.length()
