extends SceneTree
## Tests headless de la Fase 3 (jugador + cámara: intenciones y movimiento).
##
## Cómo correrlos (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_player.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)
##
## Se testea la matemática pura (Movimiento) y los datos (Intent): la escena
## demo con el game feel se valida con el smoke test del README + playtest
## de Juan Diego en el editor.

const MV: GDScript = preload("res://scripts/player/movimiento.gd")
const IN: GDScript = preload("res://scripts/player/intent.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 3 — jugador + cámara (intenciones)")
	_t_intent_datos()
	_t_direccion_relativa_camara()
	_t_velocidad_meta()
	_t_suavizar()
	_t_yaw_hacia()
	_t_player_base()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


func _cerca(a: Vector3, b: Vector3, eps: float = 0.001) -> bool:
	return a.distance_to(b) <= eps


## Intent: datos puros con valores neutros y limpiar() funcional.
func _t_intent_datos() -> void:
	var i: Intent = IN.new()
	_check(i.move_dir == Vector2.ZERO, "intent: move_dir neutro")
	_check(not i.tiene_destino, "intent: sin destino")
	_check(i.destino == Vector3.ZERO, "intent: destino neutro")
	_check(not i.quiere_atacar, "intent: sin ataque")
	_check(i.objetivo == null, "intent: objetivo null")
	i.move_dir = Vector2(1, 0)
	i.tiene_destino = true
	i.destino = Vector3(5, 0, 5)
	i.quiere_atacar = true
	i.limpiar()
	_check(i.move_dir == Vector2.ZERO and not i.tiene_destino
		and i.destino == Vector3.ZERO and not i.quiere_atacar
		and i.objetivo == null, "intent: limpiar() restaura neutros")


## WASD relativo al yaw de la cámara.
func _t_direccion_relativa_camara() -> void:
	var adelante: Vector3 = MV.direccion_relativa_camara(Vector2(0, -1), 0.0)
	_check(_cerca(adelante, Vector3(0, 0, -1)), "cámara: W con yaw 0 → -Z")
	var derecha: Vector3 = MV.direccion_relativa_camara(Vector2(1, 0), 0.0)
	_check(_cerca(derecha, Vector3(1, 0, 0)), "cámara: D con yaw 0 → +X")
	var atras: Vector3 = MV.direccion_relativa_camara(Vector2(0, 1), 0.0)
	_check(_cerca(atras, Vector3(0, 0, 1)), "cámara: S con yaw 0 → +Z")
	# Cámara girada 90°: el "adelante" ahora es -X.
	var girada: Vector3 = MV.direccion_relativa_camara(Vector2(0, -1), PI * 0.5)
	_check(_cerca(girada, Vector3(-1, 0, 0)), "cámara: W con yaw 90° → -X")
	# Cámara de espaldas (180°): adelante es +Z.
	var vuelta: Vector3 = MV.direccion_relativa_camara(Vector2(0, -1), PI)
	_check(_cerca(vuelta, Vector3(0, 0, 1)), "cámara: W con yaw 180° → +Z")
	var nada: Vector3 = MV.direccion_relativa_camara(Vector2.ZERO, 0.0)
	_check(nada == Vector3.ZERO, "cámara: sin input → cero")
	var diag: Vector3 = MV.direccion_relativa_camara(Vector2(1, -1), 0.0)
	_check(absf(diag.length() - 1.0) < 0.001, "cámara: diagonal normalizada")


## Llegada suave al destino de clic.
func _t_velocidad_meta() -> void:
	var dir: Vector3 = Vector3(1, 0, 0)
	var quieto: Vector3 = MV.velocidad_meta(dir, 0.2, 6.0, 0.35, 2.5)
	_check(quieto == Vector3.ZERO, "meta: dentro del radio de llegada → cero")
	var plena: Vector3 = MV.velocidad_meta(dir, 100.0, 6.0, 0.35, 2.5)
	_check(_cerca(plena, Vector3(6, 0, 0)), "meta: lejos → velocidad máxima")
	# Punto medio del tramo de frenado → mitad de velocidad.
	var media: Vector3 = MV.velocidad_meta(dir, 1.425, 6.0, 0.35, 2.5)
	_check(_cerca(media, Vector3(3, 0, 0)), "meta: mitad del frenado → mitad de vel",
		"salió " + str(media))
	var borde: Vector3 = MV.velocidad_meta(dir, 0.35, 6.0, 0.35, 2.5)
	_check(borde == Vector3.ZERO, "meta: justo en el borde → cero")


## Suavizado exponencial: converge sin sobrepasar.
func _t_suavizar() -> void:
	var actual: Vector3 = Vector3.ZERO
	var meta: Vector3 = Vector3(6, 0, 0)
	for k in 120:
		actual = MV.suavizar(actual, meta, 1.0 / 60.0, 9.0)
	_check(actual.distance_to(meta) < 0.01, "suavizar: converge a la meta en 2 s",
		"dist=" + str(actual.distance_to(meta)))
	# Monótono: cada paso se acerca, nunca se pasa.
	var a2: Vector3 = Vector3.ZERO
	var d_antes: float = a2.distance_to(meta)
	var monotono: bool = true
	for k in 60:
		a2 = MV.suavizar(a2, meta, 1.0 / 60.0, 9.0)
		var d_ahora: float = a2.distance_to(meta)
		if d_ahora > d_antes + 0.0001:
			monotono = false
		d_antes = d_ahora
	_check(monotono, "suavizar: nunca se aleja ni sobrepasa")
	# Tasa 0 = no se mueve; tasa alta converge más rápido en un paso.
	var quieta: Vector3 = MV.suavizar(Vector3.ZERO, meta, 1.0 / 60.0, 0.0)
	_check(quieta == Vector3.ZERO, "suavizar: tasa 0 no cambia nada")
	var rapida: Vector3 = MV.suavizar(Vector3.ZERO, meta, 1.0 / 60.0, 50.0)
	var lenta: Vector3 = MV.suavizar(Vector3.ZERO, meta, 1.0 / 60.0, 2.0)
	_check(rapida.length() > lenta.length(), "suavizar: tasa alta responde más rápido")


## El cuerpo mira hacia donde se mueve.
func _t_yaw_hacia() -> void:
	_check(absf(MV.yaw_hacia(Vector3(0, 0, -1))) < 0.001, "yaw: hacia -Z → 0")
	_check(absf(MV.yaw_hacia(Vector3(1, 0, 0)) - (-PI * 0.5)) < 0.001,
		"yaw: hacia +X → -90°")
	_check(absf(absf(MV.yaw_hacia(Vector3(0, 0, 1))) - PI) < 0.001,
		"yaw: hacia +Z → ±180°")


## Player nace como Entity válida con Intent listo.
func _t_player_base() -> void:
	var p: Player = PL.new()
	_basura.append(p)
	p._ready()  # fuera del árbol: _ready no corre solo; se invoca a mano.
	_check(p.esta_vivo(), "player: nace vivo")
	_check(p.intent != null, "player: intent construido en _ready")
	_check(absf(p.stats.vel_mov - 6.0) < 0.001, "player: vel base 6.0",
		"salió " + str(p.stats.vel_mov))
	_check(p is Entity, "player: es una Entity")
