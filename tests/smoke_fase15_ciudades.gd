extends SceneTree
## Smoke fase 15: instancia la demo fase14 (Moon Town + 8 ciudades
## secundarias), teletransporta al jugador a la plaza de cada ciudad
## secundaria y termina sin errores con el streaming sano.
##   godot --headless --path . --script res://tests/smoke_fase15_ciudades.gd
## Exit code 0 = todo verde. Los errores del motor salen por stderr
## (el runner los busca con grep); este script cuenta los suyos propios.

const INTERVALO_TP_MS: int = 900
const TIMEOUT_MS: int = 180000
const NPCS_ESPERADOS: int = 11  # ilya/bram/sira + 8 ambientales

var _demo: Node = null
var _jugador: Node3D = null
var _ciudades: Array = []
var _inicio_ms: int = 0
var _siguiente_tp_ms: int = 0
var _visitas: int = 0
var _terminado: bool = false
var _errores: int = 0


func _init() -> void:
	print("[SMOKE15] arranque")


func _process(_delta: float) -> bool:
	if _terminado:
		return true
	var ahora: int = Time.get_ticks_msec()
	if _demo == null:
		var escena: PackedScene = load("res://scenes/demo/fase14_demo.tscn")
		_demo = escena.instantiate()
		root.add_child(_demo)
		_inicio_ms = ahora
		print("[SMOKE15] demo instanciada (9 ciudades)")
		return false
	if ahora - _inicio_ms > TIMEOUT_MS:
		printerr("[SMOKE15] TIMEOUT")
		_errores += 1
		_terminado = true
		quit(_errores)
		return true
	if _jugador == null:
		var j: Node = root.find_child("Player", true, false)
		if j == null:
			return false
		_jugador = j as Node3D
		var lista: Variant = _demo.get("_ciudades_sec")
		if lista is Array:
			_ciudades = lista
		if _ciudades.size() != 8:
			printerr("[SMOKE15] se esperaban 8 ciudades secundarias")
			_errores += 1
			_terminado = true
			quit(_errores)
			return true
		_siguiente_tp_ms = ahora + 1500
		print("[SMOKE15] jugador y 8 ciudades listos")
		return false
	if _visitas < _ciudades.size():
		if ahora >= _siguiente_tp_ms:
			_teletransportar(_visitas)
			_visitas += 1
			_siguiente_tp_ms = ahora + INTERVALO_TP_MS
		return false
	# Ultimas visitas hechas: verificaciones finales.
	if ahora >= _siguiente_tp_ms:
		_verificar_final()
		_terminado = true
		quit(_errores)
		return true
	return false


func _teletransportar(i: int) -> void:
	var ciudad: Variant = _ciudades[i]
	var sp: Vector3 = (ciudad.call("punto_aparicion_jugador") as Vector3)
	if _jugador.has_method("deseleccionar"):
		_jugador.call("deseleccionar")
	_jugador.global_position = sp
	print("[SMOKE15] visita %d/8: %s" % [i + 1, str(sp)])


func _verificar_final() -> void:
	var n_npcs: int = get_nodes_in_group("npcs").size()
	if n_npcs != NPCS_ESPERADOS:
		printerr("[SMOKE15] npcs=%d, se esperaban %d" % [n_npcs, NPCS_ESPERADOS])
		_errores += 1
	var sm: Node = root.find_child("StreamingMobs", true, false)
	var inst: int = -1
	if sm != null and sm.has_method("conteo_instanciados"):
		inst = int(sm.call("conteo_instanciados"))
	else:
		printerr("[SMOKE15] StreamingMobs no encontrado/sin API")
		_errores += 1
	# El jugador debe seguir en la plaza de la ultima ciudad visitada.
	var ultima: Variant = _ciudades[_ciudades.size() - 1]
	var sp: Vector3 = (ultima.call("punto_aparicion_jugador") as Vector3)
	var dist: float = _jugador.global_position.distance_to(sp)
	if dist > 15.0:
		printerr("[SMOKE15] jugador lejos de la ultima plaza: %f" % dist)
		_errores += 1
	print("[SMOKE15] visitas=%d npcs=%d mobs_instanciados=%d errores=%d"
		% [_visitas, n_npcs, inst, _errores])
	if _errores == 0:
		print("[SMOKE15] TODO VERDE")
