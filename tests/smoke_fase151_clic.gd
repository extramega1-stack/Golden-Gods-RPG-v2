extends SceneTree
## Smoke fase 15.1: el jugador camina POR CLIC (orden de mover, la rama de
## suelo de `_clic_izquierdo` que el winding roto dejaba sin destino) y por
## WASD sobre el terreno ya corregido. Verifica que con la colisión real
## del terreno (frontales hacia +Y) el héroe no se hunde, no flota y el
## `move_and_slide` no se atasca.
##
## Fases: CLIC (hasta 4 candidatos de 60 u en la plaza; si el jugador no
## avanza con uno, prueba el siguiente) → WASD (3 s de "mover_adelante"
## simulado con Input.action_press) → verificación final.
## Mínimo 400 frames; exit code 0 = verde.
##   godot --headless --path . --script res://tests/smoke_fase151_clic.gd

const TIMEOUT_MS: int = 120000
const FASE_CLIC_MAX_MS: int = 8000
const FASE_WASD_MS: int = 3000
const DIST_CLIC: float = 60.0

var _demo: Node = null
var _jugador: Node3D = null
var _terreno: Terreno = null
var _inicio_ms: int = 0
var _frames: int = 0
var _errores: int = 0
var _terminado: bool = false

var _fase: int = 0  # 0=arranque, 1=clic, 2=wasd, 3=fin
var _fase_t0_ms: int = 0
var _candidatos: Array = []
var _cand_i: int = 0
var _base_clic: Vector3 = Vector3.ZERO
var _dest_clic: Vector3 = Vector3.ZERO
var _clic_ok: bool = false
var _wasd_base: Vector3 = Vector3.ZERO
var _wasd_ok: bool = false
var _desv_max: float = 0.0
var _hundido: bool = false


func _init() -> void:
	print("[SMOKE151] arranque: caminar por clic y WASD con winding corregido")


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
		print("[SMOKE151] demo instanciada")
		return false
	if ahora - _inicio_ms > TIMEOUT_MS:
		printerr("[SMOKE151] TIMEOUT global")
		_errores += 1
		_terminar()
		return true
	if _jugador == null:
		_buscar_nodos()
		return false
	_rastrear_desvio()
	match _fase:
		1:
			_avanzar_clic(ahora)
		2:
			_avanzar_wasd(ahora)
		3:
			_verificar_final()
			_terminar()
			return true
	return false


func _buscar_nodos() -> void:
	var j: Node = root.find_child("Player", true, false)
	if j == null:
		return
	var tn: Node = root.find_child("Terreno", true, false)
	if tn == null:
		return
	_jugador = j as Node3D
	_terreno = tn as Terreno
	_base_clic = _jugador.global_position
	_candidatos = [
		_base_clic + Vector3(DIST_CLIC, 0, 0),
		_base_clic + Vector3(0, 0, DIST_CLIC),
		_base_clic + Vector3(-DIST_CLIC, 0, 0),
		_base_clic + Vector3(0, 0, -DIST_CLIC),
	]
	_cand_i = 0
	_ordenar_candidato()
	_fase = 1
	_fase_t0_ms = Time.get_ticks_msec()
	print("[SMOKE151] jugador + terreno listos; fase CLIC")


func _ordenar_candidato() -> void:
	var plano: Vector3 = _candidatos[_cand_i]
	var h: float = _terreno.altura_en(plano.x, plano.z)
	_dest_clic = Vector3(plano.x, h, plano.z)
	(_jugador as Player).ordenar_mover_a(_dest_clic)
	_fase_t0_ms = Time.get_ticks_msec()
	print("[SMOKE151] clic → candidato %d/4: %s" % [_cand_i + 1, str(_dest_clic)])


func _dist_xz(a: Vector3, b: Vector3) -> float:
	var d: Vector3 = a - b
	d.y = 0.0
	return d.length()


## Fase CLIC: el jugador debe llegar al destino (o avanzar ≥ 25 u). Si en
## 8 s no avanza, el candidato estaba bloqueado: se prueba el siguiente.
func _avanzar_clic(ahora: int) -> void:
	var pos: Vector3 = _jugador.global_position
	if _dist_xz(pos, _dest_clic) < 3.0 or _dist_xz(pos, _base_clic) > 25.0:
		_clic_ok = true
		print("[SMOKE151] CLIC ok (avance=%.1f u)" % _dist_xz(pos, _base_clic))
		_iniciar_wasd()
		return
	if ahora - _fase_t0_ms > FASE_CLIC_MAX_MS:
		_cand_i += 1
		if _cand_i >= _candidatos.size():
			printerr("[SMOKE151] CLIC: ningun candidato avanzo (atascado)")
			_errores += 1
			_iniciar_wasd()
			return
		_ordenar_candidato()


func _iniciar_wasd() -> void:
	Input.action_press("mover_adelante")
	_wasd_base = _jugador.global_position
	_fase = 2
	_fase_t0_ms = Time.get_ticks_msec()
	print("[SMOKE151] fase WASD: 3 s de mover_adelante")


## Fase WASD: el héroe debe desplazarse (el WASD cancela la orden de clic
## por diseño; aquí solo importa que camina sin hundirse).
func _avanzar_wasd(ahora: int) -> void:
	if ahora - _fase_t0_ms >= FASE_WASD_MS:
		Input.action_release("mover_adelante")
		var av: float = _dist_xz(_jugador.global_position, _wasd_base)
		_wasd_ok = av > 3.0
		print("[SMOKE151] WASD: avance=%.1f u ok=%s" % [av, str(_wasd_ok)])
		if not _wasd_ok:
			printerr("[SMOKE151] WASD: el jugador no avanzo")
			_errores += 1
		_fase = 3


## Cada frame: el héroe debe ir pegado al dato de altura (ni hundido ni
## flotando) aunque `move_and_slide` ahora colisione de verdad.
func _rastrear_desvio() -> void:
	if _jugador == null or _terreno == null:
		return
	var pos: Vector3 = _jugador.global_position
	var h: float = _terreno.altura_en(pos.x, pos.z)
	var d: float = pos.y - h
	_desv_max = maxf(_desv_max, absf(d))
	if d < -2.0:
		_hundido = true


func _verificar_final() -> void:
	print("[SMOKE151] frames=%d desv_max=%.2f hundido=%s clic=%s wasd=%s"
		% [_frames, _desv_max, str(_hundido), str(_clic_ok), str(_wasd_ok)])
	if _frames < 400:
		printerr("[SMOKE151] menos de 400 frames")
		_errores += 1
	if not _clic_ok:
		printerr("[SMOKE151] la fase CLIC no logro caminar")
		_errores += 1
	if _hundido:
		printerr("[SMOKE151] el jugador se hundio bajo el terreno")
		_errores += 1
	if _desv_max >= 4.0:
		printerr("[SMOKE151] desvio vertical excesivo: %.2f" % _desv_max)
		_errores += 1


func _terminar() -> void:
	_terminado = true
	Input.action_release("mover_adelante")
	if _errores == 0:
		print("[SMOKE151] TODO VERDE")
	else:
		printerr("[SMOKE151] HAY ERRORES: %d" % _errores)
	quit(_errores)
