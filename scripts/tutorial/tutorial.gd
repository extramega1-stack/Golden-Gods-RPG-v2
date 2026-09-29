class_name Tutorial
extends Node
## FASE 39, rearmado en la 69: tutorial guiado de los primeros 5 minutos.
##
## QUÉ ES: 6 pasos COMO DATOS (`data/tutorial.json`, leídos por
## `TutorialPasos`) que el jugador cumple y que se marcan solos. Cada paso
## tiene un "hacé esto ahora" con un objetivo real en el mundo.
##
## CÓMO AVANZA (regla dura): POR SEÑALES. Nada de que la UI pregunte cada
## frame si el jugador ya hizo algo. Las señales que ya existían en el
## proyecto, sin tocar un solo sistema de juego:
##   `intencion_atacar`  → el paso "atacar"
##   `skills.skill_usada` → el paso "skill"
##   `inventario.cambiado` → el paso "pocion" (con foto antes/después, para
##     que LOOTEAR no cuente como usar)
##   `hablar_con`        → el paso "hablar"
##   `QuestLog.cambiada` → el paso "mision" (foto antes/después, para que
##     matar de más no acepte una misión)
## La posición se lee para el paso "mover" y para saber los metros que hay
## hasta el objetivo; es la única lectura por frame del proyecto y está
## detrás de `if not hay_objetivo(): return`.
##
## LO QUE NO HACE: no escribe stats, no bloquea, no pausa, no inventa
## enemigos ni NPCs. Solo sugiere, marca y regala un item de tutorial.
##
## PERSISTENCIA: bloque "tutorial" del save (SaveSystem, v11). `hecho` y
## `paso` son los de la fase 39; la 69 suma `saltado` y `regalos` (campos
## nuevos con default, por eso la versión del bloque NO se bumpea: un save
## viejo se lee igual).

# --- señales: la UI se SUSCRIBE a estas, no al revés --------------------
## Un paso nuevo empezó. `paso` es el diccionario de data/tutorial.json.
signal paso_cambiado(indice: int, paso: Dictionary)
## El tutorial terminó: el jugador hizo el último paso.
signal completado()
## El jugador lo saltó a propósito (y no lo terminó).
signal saltado()
## Volvió a abrirlo a mano (o se reinició).
signal reanudado()
## Metros hasta el objetivo. SOLO cuando cambia el metro entero: es el
## mismo umbral que `Vitals.TOQUE_MIN` (§9.5 y la fase 63). -1 = sin
## objetivo.
signal distancia_actualizada(metros: int)
## Aviso para la línea de detalle del panel ("te dejé una poción", etc).
signal destacado(texto: String)
## El jugador pidió volver a ver el panel (pulsó la pestaña).
signal abierto()

const SAVE_VERSION_TUTORIAL: int = 1
## Texto de "terminaste". Lo pisa `data/tutorial.json` (campo "cierre.texto")
## en `_init`; el valor de aquí es el respaldo si el JSON no trae ese campo.
## Es `static var` y no `const` por eso: Godot no deja escribir en un const.
static var TEXTO_FINAL: String = "¡Tutorial completado! Buena caza."
## Distancia mínima (m) para que el paso "mover" cuente como cumplido.
const DIST_MOVER: float = 1.5
## Radio de llegada (m) del botón "Ir": se corta un poco antes del objetivo
## para no meterse dentro del NPC ni chocar con el mob.
const DESVIO_IR: float = 2.0
## Distancia a la que el botón "Ir" deja de tener sentido.
const UMBRAL_CERCANO: float = 4.0
## Cada cuánto se reintenta resolver un objetivo perdido (s). Nunca por
## frame: el recorrido del árbol no puede ir en el tick.
const INTERVALO_REINTENTO: float = 0.5
## Tipos de objetivo que se pueden marcar.
const TIPO_NINGUNO: String = "ninguno"
const TIPO_PUNTO: String = "punto"
const TIPO_NPC: String = "npc"
const TIPO_MOB: String = "mob"

## Los 6 pasos. Se LLENAN de `data/tutorial.json` en `_init`; se mantienen
## como `const`-like (en la práctica es un `static var` reasignable, Godot no
## permite escribir en un `const`) porque el test de la fase 39 y el
## `SaveSystem` leen `Tutorial.PASOS` directamente. Antes era un `const`
## escrito a mano: 6 textos que para cambiar había que tocar código.
static var PASOS: Array[Dictionary] = []

var _jugador: Player = null
var _misiones: QuestLog = null
var _toast: Callable = Callable()
var _paso: int = 0
var _hecho: bool = false
var _saltado: bool = false
var _pos0: Vector3 = Vector3.ZERO
var _conteo: Dictionary = {}
var _aceptadas: Dictionary = {}
## Items ya regalados por el tutorial (para no regalar dos veces).
var _regalos: Dictionary = {}
## Nodos resueltos del paso actual: objetivo en el mundo.
var _obj_nodo: Node3D = null
var _obj_punto: Vector3 = Vector3.ZERO
var _obj_tiene: bool = false
## Cache de una sola vez para no recorrer el árbol por frame.
var _npcs: Dictionary = {}
var _minimapa: Minimapa = null
## Último metro emitido, para el umbral de `distancia_actualizada`.
var _ultimo_metro: int = -1
## Reloj del reintento de objetivo.
var _acum_reintento: float = 0.0
## UI propia: se construye sola (el Tutorial cuelga de la demo, no al revés).
var _panel: PanelTutorial = null
var _marcador: MarcadorObjetivo = null


## Carga los pasos UNA vez, al cargarse la clase. Sin esto `PASOS` solo
## existe después del primer `Tutorial.new()`, y cualquiera que lea
## `Tutorial.PASOS` sin instanciar (un test, el `SaveSystem`, una
## herramienta de datos) vería una lista vacía.
static func _static_init() -> void:
	_cargar_pasos()


## Idempotente: el primero que llega la arma.
static func _cargar_pasos() -> void:
	if not PASOS.is_empty():
		return
	TutorialPasos.cargar()
	PASOS = TutorialPasos.pasos()
	var cierre: String = TutorialPasos.texto_cierre()
	if cierre != "":
		TEXTO_FINAL = cierre


func _init() -> void:
	_cargar_pasos()


# --- construcción de la UI propia ---------------------------------------

## El Tutorial trae su panel y su marca consigo. Motivo: la cadena de demos
## (`fase14` → `fase12` → `fase9`) la crea con `Tutorial.new()` y NO la
## registra en ningún sitio, así que si la UI viviera en la demo habría que
## tocar 3 demos para mostrar un "hacé esto ahora". Aquí se cuelga del
## propio Tutorial y ya sale.
func _ready() -> void:
	if _panel == null:
		_panel = PanelTutorial.new()
		_panel.name = "PanelTutorial"
		add_child(_panel)
		_panel.conectar(self)
	if _marcador == null:
		_marcador = MarcadorObjetivo.new()
		_marcador.name = "MarcadorObjetivo"
		add_child(_marcador)
		_marcador.apagar()


## Conecta señales (solo lectura) y guarda el toast. Idempotente.
func conectar(j: Player, misiones: QuestLog, toast: Callable) -> void:
	if _jugador != null:
		return
	_jugador = j
	_misiones = misiones
	_toast = toast
	j.intencion_atacar.connect(_al_atacar)
	if j.skills != null:
		j.skills.skill_usada.connect(_al_skill)
	if j.inventario != null:
		j.inventario.cambiado.connect(_al_inventario)
	j.hablar_con.connect(_al_hablar)
	misiones.cambiada.connect(_al_misiones)
	if _panel != null:
		_panel.conectar(self)


## Tras cargar partida el Inventario es OTRO objeto: re-suscribe su señal
## (el resto de conexiones sobreviven porque jugador y misiones son los
## mismos). La usa la demo en `_cargar_partida_guardada`.
func refrescar_conexiones() -> void:
	if _jugador == null or _jugador.inventario == null:
		return
	if _jugador.inventario.cambiado.is_connected(_al_inventario):
		_jugador.inventario.cambiado.disconnect(_al_inventario)
	_jugador.inventario.cambiado.connect(_al_inventario)


## Arranca desde el paso 0 (nueva partida). Si ya está hecho, no hace nada:
## un veterano no recibe prompts.
func empezar() -> void:
	if _hecho:
		return
	_paso = 0
	_al_entrar_paso()


## ¿Terminado? Pública para demo y tests. Da igual si terminó o lo saltó.
func hecho() -> bool:
	return _hecho


## ¿Lo saltó el jugador a propósito (a diferencia de completarlo)?
func fue_saltado() -> bool:
	return _saltado


## Índice del paso actual (-1 si terminado). Pública para tests.
func paso_actual() -> int:
	if _hecho:
		return -1
	return _paso


## Salta el tutorial. Un jugador que ya sabe no quiere que le repitan: esto
## es el botón "Saltar" del panel. Deja el bloque del save en
## `hecho=true, saltado=true` para que no vuelva a arrancar solo.
func saltar() -> void:
	if _hecho:
		return
	_hecho = true
	_saltado = true
	_paso = PASOS.size()
	_apagar_objetivo()
	saltado.emit()
	_decir("Tutorial saltado. La pestaña T lo reabre cuando quieras.")


## Vuelve a empezar desde el paso 0 (el botón de la pestaña). No borra el
## estado guardado: es "reabrir", no "empezar de cero la partida".
func reabrir() -> void:
	_hecho = false
	_saltado = false
	_paso = 0
	_ultimo_metro = -1
	_al_entrar_paso()
	reanudado.emit()


## Reabre el panel sin tocar el paso (lo usa la pestaña "T"). Si el tutorial
## sigue vivo, reemite el paso; si terminó, no hace falta nada más porque el
## panel ya está suscrito a `completado`/`saltado` y tiene el cierre en
## pantalla. En los dos casos solo se pide que la caja vuelva a verse: eso
## va por `abierto`, no llamando a un método del panel desde acá.
func mostrar_resumen() -> void:
	if not _hecho:
		_al_entrar_paso()
	abierto.emit()


# --- avance por señales -------------------------------------------------

## La ÚNICA lectura por frame del tutorial, y está detrás de dos guardias:
## que el tutorial esté vivo y que el paso actual tenga objetivo. Con eso lo
## que se lee es un Vector3 y una distancia; no se recorre ningún árbol.
func _process(delta: float) -> void:
	if _hecho or _jugador == null or not is_instance_valid(_jugador):
		return
	if _paso_id() == "mover":
		_tick_mover()
	_reintentar_objetivo(delta)
	_tick_distancia()


## El paso "mover": cualquier desplazamiento del punto de entrada. No
## necesita un objetivo concreto (el del paso es informativo: el centro de
## la plaza), así que el jugador lo cumple con la primera tecla que toque.
func _tick_mover() -> void:
	if _jugador.global_position.distance_to(_pos0) >= DIST_MOVER:
		_avanzar()


## Los metros que faltan. Se emiten SOLO cuando cambia el metro entero: la
## UI recibe tres o cuatro señales en un recorrido de 125 m, no 60 por
## segundo. Y si el paso no tiene objetivo, avisa una vez con -1 y se calla
## (así el panel no enciende un "· 0 m" fantasma).
func _tick_distancia() -> void:
	if not _obj_tiene:
		if _ultimo_metro != -1:
			_ultimo_metro = -1
			distancia_actualizada.emit(-1)
		return
	var metros: int = int(round(_jugador.global_position.distance_to(_pos_objetivo())))
	if metros == _ultimo_metro:
		return
	_ultimo_metro = metros
	distancia_actualizada.emit(metros)


func _paso_id() -> String:
	if _paso < 0 or _paso >= PASOS.size():
		return ""
	return str(PASOS[_paso].get("id", ""))


func _paso_actual() -> Dictionary:
	if _paso < 0 or _paso >= PASOS.size():
		return {}
	return PASOS[_paso]


func _decir(texto: String) -> void:
	if texto == "":
		return
	if _toast.is_valid():
		_toast.call(texto)


## Al entrar a un paso: se anuncia, se marca el objetivo en el mundo y se
## toman las fotos que ese paso compara.
func _al_entrar_paso() -> void:
	if _paso < 0 or _paso >= PASOS.size():
		return
	var paso: Dictionary = PASOS[_paso]
	var id: String = str(paso.get("id", ""))
	if id == "mover" and _jugador != null:
		_pos0 = _jugador.global_position
	elif id == "pocion":
		_foto_pociones()
	elif id == "mision":
		_foto_aceptadas()
	_decir(str(paso.get("texto", "")))
	_marcar_objetivo(paso)
	paso_cambiado.emit(_paso, paso)
	# El regalo va AL FINAL a propósito: su aviso ("te dejé una poción")
	# viaja por `destacado`, que el panel pinta en la línea de detalle. Si
	# fuera antes, el `paso_cambiado` de arriba la pisaría.
	if id == "pocion":
		_regalar(paso)


func _avanzar() -> void:
	_paso += 1
	if _paso >= PASOS.size():
		_completar()
		return
	_al_entrar_paso()


func _completar() -> void:
	_hecho = true
	_paso = PASOS.size()
	_apagar_objetivo()
	completado.emit()
	_decir(TEXTO_FINAL)


func _al_atacar(_objetivo: Entity) -> void:
	if not _hecho and _paso_id() == "atacar":
		_avanzar()


func _al_skill(_skill_id: String) -> void:
	if not _hecho and _paso_id() == "skill":
		_avanzar()


func _al_inventario() -> void:
	if _hecho or _paso_id() != "pocion":
		return
	# La foto se duplica: _foto_pociones vacía y rellena _conteo in situ.
	var antes: Dictionary = _conteo.duplicate()
	_foto_pociones()
	for id in antes:
		if int(_conteo.get(id, 0)) < int(antes.get(id, 0)):
			_avanzar()
			return


func _al_hablar(_npc: NPC) -> void:
	if _hecho or _paso_id() != "hablar":
		return
	# Hablar con CUALQUIER NPC cuenta: este paso enseña la tecla, no el
	# mapa. Quien tiene que ser Ilya es la misión del paso siguiente, y esa
	# la marcan sola la brújula y el panel de misiones.
	_avanzar()


func _al_misiones() -> void:
	if _hecho or _paso_id() != "mision" or _misiones == null:
		return
	for qid in QuestDB.ids():
		if _misiones.estado(qid) == "activa" and not _aceptadas.has(qid):
			_avanzar()
			return


func _foto_pociones() -> void:
	_conteo.clear()
	for iid in ItemDB.ids():
		if str(ItemDB.obtener(iid).get("tipo", "")) != "consumible":
			continue
		if _jugador != null and _jugador.inventario != null:
			_conteo[iid] = _jugador.inventario.contar(iid)


func _foto_aceptadas() -> void:
	_aceptadas.clear()
	if _misiones == null:
		return
	for qid in QuestDB.ids():
		if _misiones.estado(qid) == "activa":
			_aceptadas[qid] = true


## REGALO DE TUTORIAL — el arreglo del bloqueo blando.
##
## El paso "usá una poción" exigía antes que el jugador TUVIERA una: la
## única fuente era el botín del goblin, y el goblin suelta poción con 15%
## de probabilidad. Un jugador nuevo podía matar seis goblins sin que le
## tocara una y quedarse sin forma de terminar el tutorial — y sin botón
## para saltarlo. Eso es un tutorial que puede dejarte atrapado.
##
## Ahora, al entrar al paso, si no tiene el item, se lo da el tutorial y se
## lo dice por la línea de detalle. Es un regalo de visita guiada, no un
## reclamo al botín: una sola poción, no altera la economía ni el loot, y
## queda anotada en el save para no repetirla.
func _regalar(paso: Dictionary) -> void:
	var item_id: String = str(paso.get("regalo", ""))
	if item_id == "" or _jugador == null or _jugador.inventario == null:
		return
	if not ItemDB.existe(item_id):
		push_warning("[Tutorial] item de regalo desconocido: " + item_id)
		return
	if _jugador.inventario.contar(item_id) > 0:
		return
	if _jugador.inventario.agregar(item_id, 1) == 0:
		_regalos[item_id] = true
		destacado.emit("Te dejé una %s en la mochila: abrí I y tocá USAR."
			% str(ItemDB.obtener(item_id).get("nombre", item_id)))


# --- el objetivo en el mundo --------------------------------------------

## Traduce el `objetivo` del paso a un nodo/punto real y enciende la marca.
## SOLO lo que existe de verdad:
##  - "punto": coordenadas del mundo (de `data/tutorial.json`).
##  - "npc": el NPC con ese `npc_id` de `data/npcs.json`, buscando en el
##    árbol (las demos los crean con `add_child`, no hay grupo).
##  - "mob": el arquetipo VIVO más cercano al jugador. Si lo matan, en el
##    siguiente tick se re-resuelve y salta al siguiente.
## Un objetivo que no se encuentra NO es un error: la marca se apaga y el
## paso sigue siendo cumplible por su señal.
func _marcar_objetivo(paso: Dictionary) -> void:
	_obj_nodo = null
	_obj_tiene = false
	var obj: Dictionary = paso.get("objetivo", {})
	match str(obj.get("tipo", TIPO_NINGUNO)):
		TIPO_PUNTO:
			_obj_tiene = true
			_obj_punto = Vector3(float(obj.get("x", 0.0)), 0.0, float(obj.get("z", 0.0)))
		TIPO_NPC:
			var npc: Node3D = _npc(str(obj.get("npc", "")))
			if npc != null:
				_obj_nodo = npc
				_obj_punto = npc.global_position
				_obj_tiene = true
		TIPO_MOB:
			var mob: Node3D = _mob_cercano(str(obj.get("arquetipo", "")))
			if mob != null:
				_obj_nodo = mob
				_obj_punto = mob.global_position
				_obj_tiene = true
		_:
			pass
	if not _obj_tiene:
		_apagar_objetivo()
		return
	if _obj_nodo == null and _jugador != null:
		_obj_punto.y = _altura_en(_obj_punto.x, _obj_punto.z)
	if _marcador != null and is_instance_valid(_marcador):
		_marcador.encender(_obj_nodo, _obj_punto, str(paso.get("texto", "")))
	_avisar_minimapa()


## Re-resuelve el objetivo cuando se pierde: el mob al que apuntaba
## murió (y el pool lo liberó) o todavía no había ninguno cerca y el
## streaming acaba de instanciar uno.
##
## CON RELOJ PROPIO, no en cada frame: recorrer el árbol buscando NPCs y
## mobs cuesta, así que como mucho se intenta dos veces por segundo
## (`INTERVALO_REINTENTO`). Un punto fijo no se reintenta nunca (no se
## pierde) y si el nodo sigue vivo no se hace nada.
func _reintentar_objetivo(delta: float) -> void:
	if _nodo_objetivo_vivo():
		return
	var tipo: String = objetivo_tipo()
	if tipo == TIPO_PUNTO or tipo == TIPO_NINGUNO:
		# Un punto fijo no se pierde y un paso sin objetivo no tiene nada
		# que reintentar: reintentarlo sería un recorrido inútil por segundo.
		return
	_acum_reintento += delta
	if _acum_reintento < INTERVALO_REINTENTO:
		return
	_acum_reintento = 0.0
	_marcar_objetivo(_paso_actual())


## ¿El objetivo sigue apuntando a algo real?
func _nodo_objetivo_vivo() -> bool:
	if not _obj_tiene:
		return false
	return _obj_nodo == null or is_instance_valid(_obj_nodo)


func _apagar_objetivo() -> void:
	_obj_nodo = null
	_obj_tiene = false
	if _marcador != null and is_instance_valid(_marcador):
		_marcador.apagar()
	if _minimapa != null and is_instance_valid(_minimapa):
		_minimapa.fijar_objetivo_tutorial(Vector3(NAN, NAN, NAN))


## El botón "Ir" del panel. Caminar al objetivo es la diferencia entre "hacé
## esto ahora" y "sabés que hay algo que hacer".
func ir_al_objetivo() -> void:
	if _jugador == null or not is_instance_valid(_jugador) or not _obj_tiene:
		return
	# Si el objetivo se perdió justo antes del clic, un reintento ya.
	_acum_reintento = INTERVALO_REINTENTO
	_reintentar_objetivo(0.0)
	var destino: Vector3 = _pos_objetivo()
	# Se corta un poco antes: llegar encima del NPC no hace falta para
	# hablar (basta con el radio de interacción) y esquiva la colisión.
	var hacia: Vector3 = _jugador.global_position - destino
	hacia.y = 0.0
	if hacia.length() > 0.01:
		destino += hacia.normalized() * DESVIO_IR
	destino.y = _altura_en(destino.x, destino.z)
	_jugador.ordenar_mover_a(destino)


## Posición del objetivo (a la del nodo si lo sigue). Para la distancia, el
## marcador y el minimapa.
func _pos_objetivo() -> Vector3:
	if _obj_nodo != null and is_instance_valid(_obj_nodo):
		return _obj_nodo.global_position
	return _obj_punto


## ¿El jugador ya estállegó? (Para el botón "Ir" y los tests.)
func objetivo_al_alcance() -> bool:
	if not _obj_tiene or _jugador == null or not is_instance_valid(_jugador):
		return false
	return _jugador.global_position.distance_to(_pos_objetivo()) <= UMBRAL_CERCANO


## Metros hasta el objetivo, o -1 si este paso no tiene objetivo (tests).
func metros_al_objetivo() -> int:
	if not _obj_tiene or _jugador == null or not is_instance_valid(_jugador):
		return -1
	return int(round(_jugador.global_position.distance_to(_pos_objetivo())))


## Tipo de objetivo del paso actual: "punto"/"npc"/"mob"/"ninguno" (tests).
func objetivo_tipo() -> String:
	return str(_paso_actual().get("objetivo", {}).get("tipo", TIPO_NINGUNO))


## La marca del mundo (tests). Puede ser null si el Tutorial no está en el
## árbol todavía.
func marcador() -> MarcadorObjetivo:
	return _marcador


## El panel (tests).
func panel() -> PanelTutorial:
	return _panel


# --- resolución de nodos reales -----------------------------------------

## Altura del terreno si el jugador la tiene a mano (el minimapa de la fase
## 13 hace lo mismo). Sin terreno, 0.
func _altura_en(x: float, z: float) -> float:
	if _jugador == null or not is_instance_valid(_jugador):
		return 0.0
	var terreno: Terreno = _jugador.terreno
	if terreno == null or not is_instance_valid(terreno):
		return 0.0
	return terreno.altura_en(x, z)


## El NPC con ese id, del árbol. Cacheado: el recorrido del árbol se hace
## UNA vez y no por frame. Los NPCs no se crean ni se destruen en partida
## (los reposiciona la ciudad al cargar), así que el caché es válido; si
## algún día no lo fuera, `npcs_registrados()` lo rehace a mano.
func _npc(npc_id: String) -> Node3D:
	if npc_id == "":
		return null
	if _npcs.has(npc_id):
		var guardado: Node3D = _npcs[npc_id]
		if guardado != null and is_instance_valid(guardado):
			return guardado
		_npcs.erase(npc_id)
	_escandir_npcs()
	if _npcs.has(npc_id):
		return _npcs[npc_id]
	push_warning("[Tutorial] no encontré el NPC '%s' en la escena" % npc_id)
	return null


## Reconstruye el índice npc_id -> NPC con un recorrido del árbol (las demos
## crean los NPCs con `add_child`; no hay grupo al que colgar).
func _escandir_npcs() -> void:
	if not is_inside_tree():
		return
	var base: Node = get_parent()
	if base == null:
		base = get_tree().current_scene
	if base == null:
		return
	for n in _hojas(base):
		var npc: NPC = n as NPC
		if npc == null:
			continue
		if npc.npc_id != "":
			_npcs[npc.npc_id] = npc


## Los mobs VIVOS de ese arquetipo, ordenados por cercanía al jugador. Los
## StreamingMobs solo instancian los que el jugador tiene cerca, así que
## esto también se resuelve solo cuando el jugador se acerca.
func _mob_cercano(arquetipo: String) -> Node3D:
	if not is_inside_tree():
		return null
	var base: Node = get_parent()
	if base == null:
		base = get_tree().current_scene
	if base == null or _jugador == null or not is_instance_valid(_jugador):
		return null
	var mejor: Node3D = null
	var mejor_d: float = INF
	var jp: Vector3 = _jugador.global_position
	for n in _hojas(base):
		var e: Enemy = n as Enemy
		if e == null or not e.esta_vivo():
			continue
		if arquetipo != "" and e.arquetipo_id != arquetipo:
			continue
		var d: float = jp.distance_squared_to(e.global_position)
		if d < mejor_d:
			mejor_d = d
			mejor = e
	return mejor


## Recorrido en profundidad sin `find_children` con `owned=true`: los NPCs y
## los mobs de la demo se crean en RUNTIME, así que no tienen `owner` y
## `find_children` no los encontraría.
func _hojas(base: Node) -> Array:
	var salida: Array = []
	var pila: Array = [base]
	while not pila.is_empty():
		var actual: Node = pila.pop_back()
		for h in actual.get_children():
			salida.append(h)
			pila.append(h)
	return salida


## El minimapa, para dibujarle el objetivo. Se busca UNA vez y se cachea;
## `fase12_demo` lo crea en su `_ready()`, antes de que el mundo esté listo
## (que es cuando arranca el tutorial), así que para cuando hace falta ya
## está. Puede ser null (demos viejas sin minimapa): el tutorial funciona
## igual, solo que sin el punto en el mapa.
func _buscar_minimapa() -> Minimapa:
	if _minimapa != null and is_instance_valid(_minimapa):
		return _minimapa
	if not is_inside_tree():
		return null
	var base: Node = get_parent()
	if base == null:
		base = get_tree().current_scene
	if base == null:
		return null
	for n in _hojas(base):
		var mm: Minimapa = n as Minimapa
		if mm != null:
			_minimapa = mm
			return mm
	return null


func _avisar_minimapa() -> void:
	var mm: Minimapa = _buscar_minimapa()
	if mm == null:
		return
	mm.fijar_objetivo_tutorial(_pos_objetivo())


# --- guardado -----------------------------------------------------------

## Serialización versionada (bloque "tutorial" del save, v11).
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION_TUTORIAL,
		"hecho": _hecho,
		"paso": _paso,
		# Campos de la fase 69. Un save v1 (sin ellos) los carga con
		# default: el bloque NO se bumpea a propósito, para que el assert
		# de versión del test de la fase 39 siga valiendo y porque los
		# campos nuevos son aditivos.
		"saltado": _saltado,
		"regalos": _regalos.duplicate(),
	}


func cargar_estado(d: Dictionary) -> void:
	_hecho = bool(d.get("hecho", false))
	_saltado = bool(d.get("saltado", false))
	_regalos.clear()
	for k in d.get("regalos", {}).keys():
		_regalos[str(k)] = true
	if _hecho:
		_paso = PASOS.size()
	else:
		_paso = clampi(int(d.get("paso", 0)), 0, PASOS.size())
