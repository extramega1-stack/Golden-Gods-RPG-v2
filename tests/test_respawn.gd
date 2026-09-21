extends SceneTree
## Tests headless de la Fase 9 (respawn de mobs).
##
## Cubre: `SpawnerMobs` (vigila enemigos; ante `murio` programa el
## respawn tras `respawn_seg` del arquetipo; NO reaparece antes de tiempo;
## el reaparecido tiene el mismo `arquetipo_id`, está vivo y cerca de su
## punto de origen; el default `RESPAWN_DEFAULT_SEG` = 20 s aplica si el
## arquetipo no declara `respawn_seg`; varios pendientes a la vez; el
## reaparecido se auto-vigila —su muerte también respawnea—; la señal
## `reaparecido` se emite) y que el guardado no persiste timers
## (runtime): el save guarda los enemigos vivos/muertos como siempre y la
## carga no rompe.
##
## El timer es testeable: los tests llaman a `avanzar(dt)` con tiempo
## simulado (el `_process` real se desactiva en los tests).
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_respawn.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const SP: GDScript = preload("res://scripts/mundo/spawner_mobs.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const SS: GDScript = preload("res://scripts/save/save_system.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

## La factory de los tests crea enemigos con el arquetipo pedido.
var _arq_actual: Dictionary = {}
var _creados: Array = []
var _reaparecidos: int = 0


func _init() -> void:
	print("[TEST] Fase 9 — Respawn de mobs")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_respawn_basico()
	_t_default_20()
	_t_varios_pendientes()
	_t_auto_vigilar()
	_t_sin_factory_no_revienta()
	_t_save_sin_timers()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
	return true


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


func _arquetipo(respawn: Variant) -> Dictionary:
	var a: Dictionary = {
		"nombre": "Goblin",
		"fuerza": 10.0,
		"agilidad": 8.0,
		"destreza": 4.0,
		"inteligencia": 2.0,
	}
	if respawn != null:
		a["respawn_seg"] = respawn
	return a


func _spawner() -> SpawnerMobs:
	var s: SpawnerMobs = SP.new()
	s.set_process(false)  # los tests usan avanzar(dt) con tiempo simulado
	root.add_child(s)
	_basura.append(s)
	_arq_actual = {"goblin": _arquetipo(15.0), "ogro": _arquetipo(30.0)}
	s.configurar_arquetipos(_arq_actual)
	s.fijar_factory(Callable(self, "_fabrica"))
	_creados = []
	_reaparecidos = 0
	s.reaparecido.connect(_al_reaparecido)
	return s


func _fabrica(arquetipo_id: String, posicion: Vector3) -> Enemy:
	var e: Enemy = EN.new()
	e.arquetipo_id = arquetipo_id
	e.configurar(_arq_actual.get(arquetipo_id, {}))
	root.add_child(e)
	e.global_position = posicion
	_creados.append(e)
	_basura.append(e)
	return e


func _enemigo(arquetipo_id: String, pos: Vector3) -> Enemy:
	var e: Enemy = EN.new()
	e.arquetipo_id = arquetipo_id
	e.configurar(_arq_actual.get(arquetipo_id, {}))
	root.add_child(e)
	e.global_position = pos
	_basura.append(e)
	return e


func _al_reaparecido(_nuevo: Enemy) -> void:
	_reaparecidos += 1


## --- Respawn básico con tiempo simulado ---


func _t_respawn_basico() -> void:
	var s: SpawnerMobs = _spawner()
	var origen: Vector3 = Vector3(6, 0, -6)
	var e: Enemy = _enemigo("goblin", origen)
	s.vigilar(e)
	_check(s.pendientes() == 0, "respawn: sin muertes no hay pendientes")
	e.take_damage(99999.0, null)
	_check(not e.esta_vivo(), "pre: el enemigo murió")
	_check(s.pendientes() == 1, "respawn: la muerte programa 1 pendiente")
	# No reaparece antes de tiempo (15 s del arquetipo).
	s.avanzar(14.9)
	_check(s.pendientes() == 1, "respawn: a los 14.9 s sigue pendiente")
	_check(_creados.is_empty(), "respawn: no reaparece antes de tiempo")
	_check(_reaparecidos == 0, "respawn: la señal no se emitió antes")
	# Al cumplirse el timer, reaparece.
	s.avanzar(0.2)
	_check(s.pendientes() == 0, "respawn: a los 15.1 s ya no hay pendientes")
	_check(_creados.size() == 1, "respawn: el enemigo reapareció")
	_check(_reaparecidos == 1, "respawn: se emitió reaparecido(nuevo)")
	var nuevo: Enemy = _creados[0]
	_check(nuevo.arquetipo_id == "goblin", "respawn: mismo arquetipo")
	_check(nuevo.esta_vivo(), "respawn: el reaparecido está vivo")
	var dist: float = nuevo.global_position.distance_to(origen)
	_check(dist <= SpawnerMobs.RADIO_VARIACION + 0.05,
		"respawn: reaparece cerca del punto de origen", str(dist))
	# La factory la llamó el spawner con (arquetipo, posición).
	_check(nuevo.is_inside_tree(), "respawn: el reaparecido está en el árbol")


## --- Default de 20 s si falta respawn_seg ---


func _t_default_20() -> void:
	_check(SpawnerMobs.RESPAWN_DEFAULT_SEG == 20.0,
		"respawn: el default es 20 s (constante con nombre)")
	var s: SpawnerMobs = _spawner()
	_arq_actual["goblin"] = _arquetipo(null)  # sin respawn_seg
	s.configurar_arquetipos(_arq_actual)
	var e: Enemy = _enemigo("goblin", Vector3.ZERO)
	s.vigilar(e)
	e.take_damage(99999.0, null)
	s.avanzar(19.9)
	_check(_creados.is_empty(), "respawn: sin campo, a los 19.9 s no reaparece")
	s.avanzar(0.2)
	_check(_creados.size() == 1, "respawn: sin campo, a los 20.1 s reaparece")
	# respawn_seg <= 0 también cae al default (dato malo no rompe).
	var s2: SpawnerMobs = _spawner()
	_arq_actual["goblin"] = _arquetipo(0.0)
	s2.configurar_arquetipos(_arq_actual)
	var e2: Enemy = _enemigo("goblin", Vector3.ZERO)
	s2.vigilar(e2)
	e2.take_damage(99999.0, null)
	s2.avanzar(19.9)
	_check(_creados.is_empty(), "respawn: respawn_seg 0 usa el default (no reaparece a 19.9 s)")


## --- Varios pendientes a la vez ---


func _t_varios_pendientes() -> void:
	var s: SpawnerMobs = _spawner()
	var g: Enemy = _enemigo("goblin", Vector3(1, 0, 1))
	var o: Enemy = _enemigo("ogro", Vector3(-1, 0, -1))
	s.vigilar(g)
	s.vigilar(o)
	g.take_damage(99999.0, null)
	o.take_damage(99999.0, null)
	_check(s.pendientes() == 2, "respawn: 2 muertes = 2 pendientes")
	s.avanzar(15.0)
	_check(_creados.size() == 1, "respawn: a los 15 s solo reapareció el goblin")
	_check(_creados[0].arquetipo_id == "goblin", "respawn: el reaparecido es el goblin")
	_check(s.pendientes() == 1, "respawn: el ogro sigue pendiente")
	s.avanzar(15.0)
	_check(_creados.size() == 2, "respawn: a los 30 s reapareció el ogro")
	_check(s.pendientes() == 0, "respawn: sin pendientes al final")


## --- El reaparecido se auto-vigila ---


func _t_auto_vigilar() -> void:
	var s: SpawnerMobs = _spawner()
	var e: Enemy = _enemigo("goblin", Vector3(2, 0, 2))
	s.vigilar(e)
	e.take_damage(99999.0, null)
	s.avanzar(15.0)
	_check(_creados.size() == 1, "pre: el goblin reapareció")
	var nuevo: Enemy = _creados[0]
	nuevo.take_damage(99999.0, null)
	_check(s.pendientes() == 1, "respawn: la muerte del reaparecido también programa")
	s.avanzar(15.0)
	_check(_creados.size() == 2, "respawn: el reaparecido vuelve a reaparecer")
	# Vigilar dos veces no duplica la programación.
	var e2: Enemy = _enemigo("goblin", Vector3(3, 0, 3))
	s.vigilar(e2)
	s.vigilar(e2)
	e2.take_damage(99999.0, null)
	_check(s.pendientes() == 1, "respawn: vigilar 2 veces no duplica pendientes")


## --- Sin factory no revienta ---


func _t_sin_factory_no_revienta() -> void:
	var s: SpawnerMobs = SP.new()
	s.set_process(false)
	root.add_child(s)
	_basura.append(s)
	_arq_actual = {"goblin": _arquetipo(15.0)}
	s.configurar_arquetipos(_arq_actual)
	var e: Enemy = _enemigo("goblin", Vector3.ZERO)
	s.vigilar(e)
	e.take_damage(99999.0, null)
	s.avanzar(20.0)
	_check(s.pendientes() == 0, "respawn: sin factory el pendiente se descarta sin reventar")


## --- El save no persiste timers (runtime) ---


func _t_save_sin_timers() -> void:
	var j: Player = PL.new(SB.new(10.0, 8.0, 6.0, 4.0))
	root.add_child(j)
	_basura.append(j)
	_arq_actual = {"goblin": _arquetipo(15.0)}
	var vivo: Enemy = _enemigo("goblin", Vector3(1, 0, 1))
	var muerto: Enemy = _enemigo("goblin", Vector3(2, 0, 2))
	muerto.take_damage(99999.0, null)
	var s: SaveSystem = SS.new()
	s.jugador = j
	s.enemigos = [vivo, muerto]
	_check(s.guardar(), "save: guardar con un muerto no revienta")
	var texto: String = FileAccess.get_file_as_string(SaveSystem.RUTA)
	_check(not ("respawn" in texto), "save: el JSON no guarda timers de respawn")
	_check(not ("pendiente" in texto), "save: el JSON no guarda pendientes")
	# La carga restaura vivos/muertos como siempre (los muertos pendientes
	# de respawn simplemente no están en la lista de la demo).
	var j2: Player = PL.new(SB.new(10.0, 8.0, 6.0, 4.0))
	root.add_child(j2)
	_basura.append(j2)
	var vivo2: Enemy = _enemigo("goblin", Vector3.ZERO)
	var muerto2: Enemy = _enemigo("goblin", Vector3.ZERO)
	var s2: SaveSystem = SS.new()
	s2.jugador = j2
	s2.enemigos = [vivo2, muerto2]
	_check(s2.cargar(), "save: cargar no rompe")
	_check(vivo2.esta_vivo(), "save: el vivo sigue vivo tras cargar")
	_check(not muerto2.esta_vivo(), "save: el muerto sigue muerto tras cargar")
