extends SceneTree
## Tests headless de la Fase 13 (Brújula).
##
## Cubre: `offset_para` (N centrado con yaw 0, E a la derecha, O a la
## izquierda, wrap en ±PI, equivalencia +TAU, el yaw desplaza la rosa),
## `offset_marcador` (dentro del rango no toca nada; detrás se pega al
## borde ~±75° con el signo correcto), resolución del objetivo con
## QuestLog real (sin misión → sin marcador; activa+matar → mob vivo más
## cercano del arquetipo pedido; lista → NPC npc_origen; activa+hablar →
## NPC del objetivo; activa+recolectar → NPC npc_origen; NPC inexistente →
## sin marcador), refresco automático con la señal `cambiada` de QuestLog,
## configurar() totalmente nullable sin reventar, y el pipeline completo
## objetivo-detrás → diamante pegado al borde + distancia en metros.
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase13_brujula.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const BRU: GDScript = preload("res://scripts/ui/brujula.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const NP: GDScript = preload("res://scripts/npc/npc.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const QL: GDScript = preload("res://scripts/quests/quest_log.gd")
const QDB: GDScript = preload("res://scripts/quests/quest_db.gd")
const SM: GDScript = preload("res://scripts/mundo/streaming_mobs.gd")

const ANCHO: float = 420.0

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 13 — Brújula")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	QDB.cargar()
	_t_offset_para()
	_t_offset_marcador()
	_t_resolver()
	_t_cambiada_refresca()
	_t_pipeline_detras()
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


func _cerca(a: float, b: float, tol: float = 0.001) -> bool:
	return absf(a - b) <= tol


## --- Fixtures ---


func _player_en(pos: Vector3) -> Player:
	var p: Player = PL.new()
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


func _npc_con(npc_id: String, pos: Vector3) -> NPC:
	var n: NPC = NP.new()
	n.npc_id = npc_id
	root.add_child(n)
	n.global_position = pos
	_basura.append(n)
	return n


func _factory_mob(arquetipo: String, pos: Vector3) -> Enemy:
	var e: Enemy = EN.new()
	e.arquetipo_id = arquetipo
	# En el árbol ANTES de fijar global_position: fuera del árbol Godot
	# reporta (0,0,0) (lección 13b); en el juego real los añade la demo.
	root.add_child(e)
	e.global_position = pos
	_basura.append(e)
	return e


func _streaming_con(jugador: Player, datos: Array) -> StreamingMobs:
	var sm: StreamingMobs = SM.new()
	sm.configurar(datos)
	sm.fijar_factory(_factory_mob)
	sm.fijar_jugador(jugador)
	sm.fijar_radios(1000.0, 2000.0)
	sm.actualizar()
	_basura.append(sm)
	return sm


func _brujula(camara: CameraRig, jugador: Player, q: QuestLog,
		sm: StreamingMobs, npcs: Array) -> Brujula:
	var b: Brujula = BRU.new()
	b.configurar(camara, jugador, q, sm)
	b.fijar_npcs(npcs)
	_basura.append(b)
	return b


## --- offset_para: la rosa gira con la cámara ---


func _t_offset_para() -> void:
	# N centrado con yaw 0 (norte del mundo = -Z = ángulo 0).
	_check(_cerca(Brujula.offset_para(0.0, 0.0, ANCHO), 0.0),
		"offset: N centrado con yaw 0")
	# E a la derecha con yaw 0 (+90° → +X → borde derecho).
	_check(_cerca(Brujula.offset_para(PI / 2.0, 0.0, ANCHO), 210.0),
		"offset: E a la derecha con yaw 0")
	# O a la izquierda.
	_check(_cerca(Brujula.offset_para(-PI / 2.0, 0.0, ANCHO), -210.0),
		"offset: O a la izquierda con yaw 0")
	# 45° → mitad del semiancho (proporcionalidad).
	_check(_cerca(Brujula.offset_para(PI / 4.0, 0.0, ANCHO), 105.0),
		"offset: 45° -> 105 px")
	# El yaw desplaza la rosa: con la cámara mirando al este, el norte
	# queda a la izquierda.
	_check(_cerca(Brujula.offset_para(0.0, PI / 2.0, ANCHO), -210.0),
		"offset: yaw 90° pone el N a la izquierda")
	# S centrado cuando la cámara mira al sur.
	_check(_cerca(Brujula.offset_para(PI, PI, ANCHO), 0.0),
		"offset: S centrado con yaw 180°")
	# Wrap en ±PI: PI+0.5 envuelve a 0.5-PI (negativo, lado izquierdo).
	var w: float = Brujula.offset_para(PI + 0.5, 0.0, ANCHO)
	_check(_cerca(w, -353.155, 0.05), "offset: wrap PI+0.5", str(w))
	# Sumar una vuelta completa no cambia nada.
	var a: float = Brujula.offset_para(1.2, 0.3, ANCHO)
	var b: float = Brujula.offset_para(1.2 + TAU, 0.3, ANCHO)
	_check(_cerca(a, b), "offset: +TAU es idéntico")


## --- offset_marcador: detrás se pega al borde ---


func _t_offset_marcador() -> void:
	# Dentro del rango (~75°) no se toca: idéntico a offset_para.
	var dentro: float = Brujula.offset_marcador(0.5, 0.0, ANCHO)
	_check(_cerca(dentro, Brujula.offset_para(0.5, 0.0, ANCHO)),
		"marcador: dentro del rango no se recorta")
	# Justo detrás (θ=±PI): wrapf devuelve -PI (intervalo [-PI, PI)),
	# así que se pega al borde IZQUIERDO; lo importante es que quede
	# pegado a un borde, no cuál.
	var detras: float = Brujula.offset_marcador(PI, 0.0, ANCHO)
	_check(_cerca(absf(detras), 175.0, 0.5) and absf(detras) < 210.0,
		"marcador: detrás se pega a un borde", str(detras))
	# Detrás a la izquierda: borde izquierdo con signo negativo.
	var detras_izq: float = Brujula.offset_marcador(-PI, 0.0, ANCHO)
	_check(_cerca(detras_izq, -175.0, 0.5) and detras_izq > -210.0,
		"marcador: detrás-izquierda pega al borde izquierdo", str(detras_izq))
	# En el límite (~75°) no se recorta todavía.
	var borde: float = Brujula.offset_marcador(1.3090, 0.0, ANCHO)
	_check(_cerca(borde, Brujula.offset_para(1.3090, 0.0, ANCHO)),
		"marcador: en 75° no se recorta")


## --- resolver_objetivo: misión activa → marcador ---


func _t_resolver() -> void:
	var p: Player = _player_en(Vector3.ZERO)
	var ilya: NPC = _npc_con("ilya", Vector3(50, 0, 0))
	var sm: StreamingMobs = _streaming_con(p, [
		{"arquetipo": "goblin", "origen": Vector3(30, 0, 0)},
		{"arquetipo": "goblin", "origen": Vector3(10, 0, 0)},
		{"arquetipo": "lobo", "origen": Vector3(5, 0, 0)},
	])
	# configurar() totalmente nullable no revienta.
	var b0: Brujula = BRU.new()
	b0.configurar(null, null, null, null)
	b0.fijar_npcs([])
	_basura.append(b0)
	_check(b0.resolver_objetivo() == null,
		"resolver: todo null -> sin marcador")

	# Sin misión aceptada → sin marcador.
	var qvacia: QuestLog = QL.new()
	var bv: Brujula = _brujula(null, p, qvacia, sm, [ilya])
	_check(bv.resolver_objetivo() == null,
		"resolver: sin misión -> sin marcador")

	# Activa + matar → mob vivo MÁS CERCANO del arquetipo pedido
	# (el lobo a 5 m no cuenta: pide goblin).
	var q: QuestLog = QL.new()
	_check(q.aceptar("goblins_fuera") == "ok", "resolver: aceptar goblins ok")
	var b: Brujula = _brujula(null, p, q, sm, [ilya])
	var t: Node3D = b.resolver_objetivo()
	_check(t != null, "resolver: matar -> hay objetivo")
	_check(t is Enemy and (t as Enemy).arquetipo_id == "goblin",
		"resolver: matar filtra por arquetipo")
	_check(t.global_position.distance_to(Vector3(10, 0, 0)) < 0.01,
		"resolver: matar -> el goblin más cercano (10 m)")

	# Lista → NPC npc_origen (ilya). La señal `cambiada` ya refrescó.
	for i in 5:
		q.registrar_muerte("goblin")
	_check(q.estado("goblins_fuera") == "lista",
		"resolver: precondición lista")
	_check(b.resolver_objetivo() == ilya, "resolver: lista -> NPC origen")
	_check(b.objetivo_actual() == ilya,
		"resolver: objetivo_actual tras lista")

	# Activa + hablar → NPC del objetivo (ilya, no el origen sira).
	var q2: QuestLog = QL.new()
	q2.aceptar("mensaje_sira")
	var b2: Brujula = _brujula(null, p, q2, sm, [ilya])
	_check(b2.resolver_objetivo() == ilya,
		"resolver: hablar -> NPC del objetivo")

	# Lista cuyo npc_origen NO está fijado → sin marcador.
	q2.registrar_dialogo("ilya")
	_check(q2.estado("mensaje_sira") == "lista",
		"resolver: mensaje_sira lista")
	_check(b2.resolver_objetivo() == null,
		"resolver: NPC origen inexistente -> sin marcador")

	# Activa + recolectar (otro tipo) → NPC npc_origen (bram).
	var q3: QuestLog = QL.new()
	q3.aceptar("colmillos_forja")
	var bram: NPC = _npc_con("bram", Vector3(-20, 0, 0))
	var b3: Brujula = _brujula(null, p, q3, sm, [ilya, bram])
	_check(b3.resolver_objetivo() == bram,
		"resolver: recolectar -> NPC origen")


## --- La señal `cambiada` refresca el objetivo ---


func _t_cambiada_refresca() -> void:
	var p: Player = _player_en(Vector3.ZERO)
	var ilya: NPC = _npc_con("ilya", Vector3(50, 0, 0))
	var sm: StreamingMobs = _streaming_con(p, [
		{"arquetipo": "goblin", "origen": Vector3(12, 0, 0)},
	])
	var q: QuestLog = QL.new()
	var b: Brujula = _brujula(null, p, q, sm, [ilya])
	_check(b.objetivo_actual() == null,
		"cambiada: sin misión no hay objetivo")
	# aceptar() emite `cambiada`: la brújula re-resuelve sola.
	q.aceptar("goblins_fuera")
	var t: Node3D = b.objetivo_actual()
	_check(t != null and t is Enemy,
		"cambiada: aceptar refresca al mob")
	# Completarla emite `cambiada`: el objetivo pasa al NPC origen.
	for i in 5:
		q.registrar_muerte("goblin")
	_check(b.objetivo_actual() == ilya,
		"cambiada: completar mueve el objetivo al NPC origen")
	# Entregarla (terminal) emite `cambiada`: se apaga el marcador.
	q.entregar("goblins_fuera", p)
	_check(b.objetivo_actual() == null,
		"cambiada: entregar apaga el marcador")


## --- Pipeline: objetivo detrás → diamante al borde + "50 m" ---


func _t_pipeline_detras() -> void:
	var p: Player = _player_en(Vector3.ZERO)
	var ilya: NPC = _npc_con("ilya", Vector3(50, 0, 0))
	# Mob a ~50 m casi justo detrás (+Z con yaw 0; un poco a la derecha
	# para evitar la ambigüedad de signo de wrapf en exactamente ±PI).
	var sm: StreamingMobs = _streaming_con(p, [
		{"arquetipo": "goblin", "origen": Vector3(5, 0, 50)},
	])
	var q: QuestLog = QL.new()
	q.aceptar("goblins_fuera")
	var b: Brujula = _brujula(null, p, q, sm, [ilya])
	var t: Node3D = b.resolver_objetivo()
	_check(t != null, "pipeline: hay objetivo detrás")
	var ang: float = b._angulo_hacia(t)
	_check(_cerca(absf(ang), PI, 0.12), "pipeline: ángulo ~PI (detrás)",
		str(ang))
	var off: float = Brujula.offset_marcador(ang, 0.0, ANCHO)
	_check(_cerca(absf(off), 175.0, 0.5) and absf(off) < ANCHO / 2.0,
		"pipeline: diamante pegado al borde", str(off))
	var dist: float = b._distancia_hacia(t)
	_check(_cerca(dist, 50.25, 0.05) and int(dist) == 50,
		"pipeline: distancia ~50 m", str(dist))
