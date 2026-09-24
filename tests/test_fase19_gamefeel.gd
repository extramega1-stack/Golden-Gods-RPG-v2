extends SceneTree
## Tests headless de la Fase 19 (game feel de combate): números de daño
## flotantes, hit-stop, screen shake y barra de vida sobre los mobs.
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase19_gamefeel.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const GF: GDScript = preload("res://scripts/combate/game_feel.gd")
const BV: GDScript = preload("res://scripts/combate/barra_vida_mob.gd")
const RIG: GDScript = preload("res://scripts/player/camera_rig.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 19 — game feel: numeros de dano, hit-stop, shake, barra de vida")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_sin_instancia_no_truena()
	_t_numero_danio()
	_t_numero_crit()
	_t_hitstop()
	_t_barra_vida()
	_t_shake()
	_t_integracion_golpe()
	# Seguridad: ningún test deja el tiempo congelado.
	Engine.time_scale = 1.0
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


func _enemigo(pos: Vector3) -> Enemy:
	var e: Enemy = EN.new()
	e.add_to_group("enemigos")
	root.add_child(e)
	e.global_position = pos
	_basura.append(e)
	return e


func _jugador(pos: Vector3) -> Player:
	var p: Player = PL.new()
	p.add_to_group("jugador")
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


func _gamefeel() -> GameFeel:
	var gf: GameFeel = GF.new()
	root.add_child(gf)
	_basura.append(gf)
	return gf


## Sin instancia en el árbol, los estáticos son no-op (no truenan).
func _t_sin_instancia_no_truena() -> void:
	GameFeel.inst = null
	var e: Enemy = _enemigo(Vector3(100, 0, 100))
	e.take_damage(10.0, null)
	_check(Engine.time_scale == 1.0, "sin instancia: take_damage no congela el tiempo", "")
	GameFeel.sacudir(0.5)
	GameFeel.hit_stop()
	_check(Engine.time_scale == 1.0, "sin instancia: los estaticos no hacen nada", "")


## take_damage muestra un número flotante (visible en el pool).
func _t_numero_danio() -> void:
	var gf: GameFeel = _gamefeel()
	_check(not gf.hay_numero_visible(), "setup: pool arranca sin numeros visibles", "")
	var e: Enemy = _enemigo(Vector3(200, 0, 200))
	e.take_damage(25.0, null, false)
	_check(gf.hay_numero_visible(), "take_damage muestra un numero de dano", "")
	_check(not gf.ultimo_fue_crit, "golpe normal no marca crit", "")
	# Flota hacia arriba y se apaga solo.
	gf._process(0.5)
	_check(gf.hay_numero_visible(), "a mitad de vida el numero sigue visible", "")
	gf._process(1.0)
	_check(not gf.hay_numero_visible(), "al expirar el tiempo el numero se oculta", "")


## El crítico se registra y dispara hit-stop (el tiempo se congela).
func _t_numero_crit() -> void:
	var gf: GameFeel = _gamefeel()
	var e: Enemy = _enemigo(Vector3(300, 0, 300))
	e.take_damage(10.0, null, true)
	_check(gf.ultimo_fue_crit, "el critico queda registrado", "")
	_check(gf.hay_numero_visible(), "el critico tambien muestra numero", "")
	_check(Engine.time_scale < 1.0, "el critico congela el tiempo (hit-stop)", "")
	# El temporizador del hit-stop lo restauraría en runtime; aquí se
	# verifica la restauración directa y se deja el tiempo normal.
	gf._restaurar_tiempo()
	_check(Engine.time_scale == 1.0, "restaurar_tiempo devuelve el tiempo normal", "")


## Hit-stop: congela de inmediato y no se re-encima.
func _t_hitstop() -> void:
	var gf: GameFeel = _gamefeel()
	gf._hit_stop(0.05, 0.2)
	_check(Engine.time_scale == 0.2, "hit_stop congela el tiempo de inmediato", "")
	gf._hit_stop(0.05, 0.5) # re-entrada: se ignora
	_check(Engine.time_scale == 0.2, "hit-stop activo ignora el segundo", "")
	gf._restaurar_tiempo()
	_check(Engine.time_scale == 1.0, "tras restaurar el tiempo vuelve a 1", "")


## Barra de vida: aparece al dañar, refleja el porcentaje, se oculta a
## vida llena y al morir.
func _t_barra_vida() -> void:
	var e: Enemy = _enemigo(Vector3(400, 0, 400))
	var b: BarraVidaMob = BV.new()
	e.add_child(b)
	_check(not b.visible, "setup: la barra arranca oculta", "")
	e.take_damage(30.0, null, false)
	_check(b.visible, "al recibir dano la barra aparece", "")
	var fg: MeshInstance3D = b.get("_fg") as MeshInstance3D
	var qf: QuadMesh = fg.mesh
	var pct: float = e.vida_actual / e.stats.vida_max
	# Fase 42: el frente se mide por la MALLA (el billboard ignora el scale
	# del nodo y por eso la barra se veía duplicada).
	_check(absf(qf.size.x / BarraVidaMob.ANCHO - pct) < 0.01,
		"la barra refleja el porcentaje de vida",
		"ancho=%f pct=%f" % [qf.size.x / BarraVidaMob.ANCHO, pct])
	e.heal(99999.0)
	b._process(0.6)
	_check(not b.visible, "a vida llena la barra se oculta", "")
	e.take_damage(30.0, null, false)
	_check(b.visible, "tras curarse, otro golpe la muestra de nuevo", "")
	e.take_damage(999999.0, null, false)
	_check(not b.visible, "al morir la barra se oculta", "")


## Screen shake: el trauma suma, decae y resetea los offsets.
func _t_shake() -> void:
	var rig: CameraRig = RIG.new()
	var pitch: Node3D = Node3D.new()
	pitch.name = "Pitch"
	var brazo: SpringArm3D = SpringArm3D.new()
	brazo.name = "SpringArm3D"
	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(pitch)
	pitch.add_child(brazo)
	brazo.add_child(cam)
	root.add_child(rig)
	_basura.append(rig)
	_check(rig.trauma == 0.0, "setup: sin trauma inicial", "")
	rig.agregar_trauma(0.5)
	_check(rig.trauma == 0.5, "agregar_trauma suma", "")
	rig.agregar_trauma(0.8)
	_check(rig.trauma == 1.0, "el trauma se clamp a 1", "")
	rig._process(0.016)
	_check(rig.trauma < 1.0, "el trauma decae con el tiempo", "")
	rig._process(2.0)
	_check(rig.trauma == 0.0, "el trauma llega a 0", "")
	_check(cam.h_offset == 0.0 and cam.v_offset == 0.0,
		"sin trauma los offsets se resetean", "")
	rig.remove_from_group("camera_rig") # no robarle el shake al siguiente test


## Integración: golpe crítico del jugador al mob → número + shake vía el
## grupo camera_rig (camino real de GameFeel._sacudir).
func _t_integracion_golpe() -> void:
	var gf: GameFeel = _gamefeel()
	var rig: CameraRig = RIG.new()
	var pitch: Node3D = Node3D.new()
	pitch.name = "Pitch"
	var brazo: SpringArm3D = SpringArm3D.new()
	brazo.name = "SpringArm3D"
	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(pitch)
	pitch.add_child(brazo)
	brazo.add_child(cam)
	root.add_child(rig)
	_basura.append(rig)
	var p: Player = _jugador(Vector3(500, 0, 500))
	var e: Enemy = _enemigo(Vector3(500, 0, 502))
	e.take_damage(20.0, p, true) # crítico del jugador
	_check(gf.hay_numero_visible(), "integracion: el crit muestra numero", "")
	_check(rig.trauma > 0.0, "integracion: el crit del jugador sacude la camara", "")
	gf._restaurar_tiempo()
	rig._process(2.0)
	_check(cam.h_offset == 0.0, "integracion: la camara se estabiliza", "")
