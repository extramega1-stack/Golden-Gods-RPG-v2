extends SceneTree
## Smoke fase 16: la demo real (fase14_demo.tscn) con clima activo:
## clima que interpola a lluvia sin romper la demo, los 9 NPCs porteros
## del viaje rápido colocados, el nodo PanelViaje presente y ≥ 400 frames.
## exit code 0 = verde.
##   godot --headless --path . --script res://tests/smoke_fase16_viaje_clima.gd

const TIMEOUT_MS: int = 180000
const LLUVIA_MS: int = 12000

var _demo: Node = null
var _clima: Node = null
var _frames: int = 0
var _errores: int = 0
var _inicio_ms: int = 0
var _lluvia_forzada_ms: int = 0
var _lluvia_ok: bool = false
var _terminado: bool = false


func _init() -> void:
	print("[SMOKE16] arranque: demo real con clima activo + 9 porteros")


func _process(_delta: float) -> bool:
	if _terminado:
		return true
	_frames += 1
	var ahora: int = Time.get_ticks_msec()
	if _demo == null:
		var escena: PackedScene = load("res://scenes/demo/fase14_demo.tscn")
		_demo = escena.instantiate()
		root.add_child(_demo)
		_inicio_ms = ahora
		print("[SMOKE16] demo instanciada")
		return false
	if ahora - _inicio_ms > TIMEOUT_MS:
		printerr("[SMOKE16] TIMEOUT global")
		_errores += 1
		_terminar()
		return true
	if _clima == null:
		_buscar_clima()
		return false
	if _lluvia_forzada_ms == 0:
		_verificar_estructura()
		_clima.fijar_clima("lluvia")
		_lluvia_forzada_ms = ahora
		print("[SMOKE16] clima forzado a lluvia")
		return false
	_rastrear_lluvia(ahora)
	if _frames >= 400 and ahora - _lluvia_forzada_ms >= LLUVIA_MS:
		_verificar_final()
		_terminar()
		return true
	return false


func _buscar_clima() -> void:
	var c: Node = root.find_child("Clima", true, false)
	if c == null:
		return
	_clima = c
	print("[SMOKE16] Clima encontrado (heredado de fase12_demo)")


func _verificar_estructura() -> void:
	# PanelViaje (capa UI del viaje rápido) en la escena.
	if root.find_child("PanelViaje", true, false) == null:
		printerr("[SMOKE16] falta el nodo PanelViaje")
		_errores += 1
	else:
		print("[SMOKE16] PanelViaje presente")
	# Los 9 porteros (npc_id portero_*) colocados por la demo.
	var lista: Array = _demo.get("_lista_npcs")
	var porteros: int = 0
	for n in lista:
		var npc: Object = n
		if npc != null and str(npc.get("npc_id")).begins_with("portero_"):
			porteros += 1
	print("[SMOKE16] porteros encontrados: %d" % porteros)
	if porteros != 9:
		printerr("[SMOKE16] se esperaban 9 porteros, hay %d" % porteros)
		_errores += 1
	# El viaje_id del portero de Moon Town.
	if str(ViajeRapido.viaje_id_de_npc("portero_moon_town")) != "moon_town":
		printerr("[SMOKE16] viaje_id_de_npc(portero_moon_town) != moon_town")
		_errores += 1


func _rastrear_lluvia(ahora: int) -> void:
	if _lluvia_ok:
		return
	# En 12 s con transicion_seg <= 6 la intensidad debe haber interpolado.
	if ahora - _lluvia_forzada_ms >= LLUVIA_MS:
		var i: float = _clima.intensidad_lluvia()
		var fc: float = 1.0
		var ciclo: Node = root.find_child("CicloDia", true, false)
		if ciclo == null:
			ciclo = root.find_child("Ciclo", true, false)
		if ciclo != null:
			fc = float(ciclo.get("factor_clima"))
		print("[SMOKE16] intensidad_lluvia=%.2f factor_clima=%.2f" % [i, fc])
		if i < 0.5:
			printerr("[SMOKE16] la lluvia no interpolo (intensidad=%.2f)" % i)
			_errores += 1
		elif fc >= 1.0:
			printerr("[SMOKE16] factor_clima no atenuo con lluvia (%.2f)" % fc)
			_errores += 1
		else:
			print("[SMOKE16] lluvia interpolando y atenuando el sol")
		_lluvia_ok = true


func _verificar_final() -> void:
	print("[SMOKE16] frames=%d" % _frames)
	if _frames < 400:
		printerr("[SMOKE16] menos de 400 frames")
		_errores += 1


func _terminar() -> void:
	_terminado = true
	if _errores == 0:
		print("[SMOKE16] TODO VERDE")
	else:
		printerr("[SMOKE16] HAY ERRORES: %d" % _errores)
	quit(_errores)
