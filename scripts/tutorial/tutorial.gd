class_name Tutorial
extends Node
## Tutorial guiado (fase 39): 6 pasos como DATOS que avanzan con eventos
## del juego y anuncian el siguiente por toast. Nunca bloquea ni escribe
## stats: solo sugiere (la UI decide el cómo con el Callable de toast).
##
## Pasos: mover → atacar → skill → poción → hablar → misión. El avance
## escucha señales ya existentes (intencion_atacar, skill_usada,
## inventario.cambiado, hablar_con, QuestLog.cambiada) y la posición para
## el movimiento. Poción y misión comparan foto-antes/foto-ahora (un loot
## no avanza el paso; matar de más tampoco acepta misiones).
## Persiste `hecho` en el save (SaveSystem v11, bloque "tutorial").

const SAVE_VERSION_TUTORIAL: int = 1

const PASOS: Array[Dictionary] = [
	{"id": "mover", "texto": "Muévete con WASD o clic izquierdo"},
	{"id": "atacar", "texto": "Ataca con la tecla T o el slot 1"},
	{"id": "skill", "texto": "Lanza una skill (teclas 2 a 5)"},
	{"id": "pocion", "texto": "Usa una poción de vida"},
	{"id": "hablar", "texto": "Habla con Ilya (tecla E cuando estés cerca)"},
	{"id": "mision", "texto": "Acepta su misión desde el diálogo"},
]

const TEXTO_FINAL: String = "¡Tutorial completado! Buena caza."
const DIST_MOVER: float = 1.5

var _jugador: Player = null
var _misiones: QuestLog = null
var _toast: Callable = Callable()
var _paso: int = 0
var _hecho: bool = false
var _pos0: Vector3 = Vector3.ZERO
var _conteo: Dictionary = {}
var _aceptadas: Dictionary = {}


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


## Tras cargar partida el Inventario es OTRO objeto: re-suscribe su señal
## (el resto de conexiones sobreviven porque jugador y misiones son los
## mismos). La usa la demo en `_cargar_partida_guardada`.
func refrescar_conexiones() -> void:
	if _jugador == null or _jugador.inventario == null:
		return
	if _jugador.inventario.cambiado.is_connected(_al_inventario):
		_jugador.inventario.cambiado.disconnect(_al_inventario)
	_jugador.inventario.cambiado.connect(_al_inventario)


## Arranca desde el paso 0 (nueva partida). Si ya está hecho, no hace nada.
func empezar() -> void:
	if _hecho:
		return
	_paso = 0
	_al_entrar_paso()


## ¿Terminado? Pública para demo y tests.
func hecho() -> bool:
	return _hecho


## Índice del paso actual (-1 si terminado). Pública para tests.
func paso_actual() -> int:
	if _hecho:
		return -1
	return _paso


func _process(_delta: float) -> void:
	if _hecho or _jugador == null or not is_instance_valid(_jugador):
		return
	if _paso_id() != "mover":
		return
	if _jugador.global_position.distance_to(_pos0) >= DIST_MOVER:
		_avanzar()


func _paso_id() -> String:
	if _paso < 0 or _paso >= PASOS.size():
		return ""
	return str(PASOS[_paso].get("id", ""))


func _decir(texto: String) -> void:
	if _toast.is_valid():
		_toast.call(texto)


## Al entrar a un paso se anuncia y se toman las fotos que ese paso compara.
func _al_entrar_paso() -> void:
	if _paso < 0 or _paso >= PASOS.size():
		return
	var id: String = _paso_id()
	if id == "mover" and _jugador != null:
		_pos0 = _jugador.global_position
	elif id == "pocion":
		_foto_pociones()
	elif id == "mision":
		_foto_aceptadas()
	_decir(str(PASOS[_paso].get("texto", "")))


func _avanzar() -> void:
	_paso += 1
	if _paso >= PASOS.size():
		_hecho = true
		_decir(TEXTO_FINAL)
		return
	_al_entrar_paso()


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
	if not _hecho and _paso_id() == "hablar":
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


## Serialización versionada (bloque "tutorial" del save, v11).
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION_TUTORIAL,
		"hecho": _hecho,
		"paso": _paso,
	}


func cargar_estado(d: Dictionary) -> void:
	_hecho = bool(d.get("hecho", false))
	if _hecho:
		_paso = PASOS.size()
	else:
		_paso = clampi(int(d.get("paso", 0)), 0, PASOS.size())
