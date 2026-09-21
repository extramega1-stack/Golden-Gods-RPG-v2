extends SceneTree
## Tests headless de la Fase 9.2.
##
## (a) E respeta el radio de interacción: con el NPC lejos NO abre el
## diálogo de inmediato — deja la MISMA interacción pendiente que el
## segundo clic lejano (el jugador camina hasta él y al llegar habla
## solo); nunca fija objetivo de ataque ni emite intencion_atacar.
## (b) E con el NPC cerca abre el diálogo directo (como antes), sin
## dejar interacción pendiente.
## (c) Al completar los objetivos aparece el banner prominente de misión
## completada ("¡Misión completada: <nombre>! Vuelve con <NPC>").
## (d) "?" dorado visible SOLO con entrega pendiente; se oculta al
## entregar; con la misión activa (ni disponible ni lista) no hay
## marcador.
## (e) Prioridad: "?" manda sobre "!" cuando un NPC tiene ambas.
## (f) API del marcador generalizado: fijar_marcador(tipo) con
## TipoMarcador {NINGUNO, DISPONIBLE, ENTREGAR}; los wrappers bool de la
## 9.1 siguen funcionando.
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase92.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const NP: GDScript = preload("res://scripts/npc/npc.gd")
const DEMO: PackedScene = preload("res://scenes/demo/fase9_demo.tscn")
const DEMO_GD: GDScript = preload("res://scenes/demo/fase9_demo.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _hablados: int = 0
var _atacados: int = 0


func _init() -> void:
	print("[TEST] Fase 9.2 — E respeta el radio, banner de completada, '?' dorado")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_marcador_tipos()
	_t_e_lejos_pendiente()
	_t_e_cerca_directo()
	_t_banner_completada()
	_t_signo_interrogacion()
	_t_prioridad()
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


func _al_hablar(_n: NPC) -> void:
	_hablados += 1


func _al_intencion(_e: Entity) -> void:
	_atacados += 1


func _npc(pos: Vector3) -> NPC:
	var n: NPC = NP.new()
	n.add_to_group("npcs")
	root.add_child(n)
	n.global_position = pos
	_basura.append(n)
	return n


func _player(pos: Vector3) -> Player:
	var p: Player = PL.new()
	p.add_to_group("jugador")
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


func _demo() -> Node3D:
	var demo: Node3D = DEMO.instantiate()
	root.add_child(demo)
	_basura.append(demo)
	return demo


func _npc_demo(demo: Node3D, npc_id: String) -> NPC:
	for x in demo.get("_lista_npcs"):
		var n: NPC = x as NPC
		if n != null and n.npc_id == npc_id:
			return n
	return null


## (f) API del marcador generalizado: tipos, texto e idempotencia.
func _t_marcador_tipos() -> void:
	var n: NPC = _npc(Vector3(0, 0, 0))
	_check(n.marcador_tipo() == NPC.TipoMarcador.NINGUNO,
		"el marcador arranca en NINGUNO", "")
	_check(not n.marcador_visible(), "el marcador arranca oculto", "")
	n.fijar_marcador(NPC.TipoMarcador.DISPONIBLE)
	_check(n.marcador_visible(), "DISPONIBLE lo muestra", "")
	_check((n.get_node("MarcadorMision") as Label3D).text == "!",
		"DISPONIBLE muestra '!'", "")
	n.fijar_marcador(NPC.TipoMarcador.ENTREGAR)
	_check(n.marcador_visible(), "ENTREGAR lo muestra", "")
	_check((n.get_node("MarcadorMision") as Label3D).text == "?",
		"ENTREGAR muestra '?'", "")
	_check(n.marcador_tipo() == NPC.TipoMarcador.ENTREGAR,
		"marcador_tipo() refleja ENTREGAR", "")
	var cuantos: int = 0
	for h in n.get_children():
		if h is Label3D:
			cuantos += 1
	_check(cuantos == 1, "cambiar de tipo reusa el mismo Label3D", "hay %d" % cuantos)
	n.fijar_marcador(NPC.TipoMarcador.NINGUNO)
	_check(not n.marcador_visible(), "NINGUNO lo oculta", "")
	_check(n.marcador_tipo() == NPC.TipoMarcador.NINGUNO,
		"marcador_tipo() refleja NINGUNO", "")
	# Compatibilidad con la API bool de la 9.1 (la usan sus tests).
	n.fijar_marcador_mision(true)
	_check((n.get_node("MarcadorMision") as Label3D).text == "!",
		"wrapper bool: fijar_marcador_mision(true) → '!'", "")
	n.fijar_marcador_entrega(true)
	_check((n.get_node("MarcadorMision") as Label3D).text == "?",
		"wrapper: fijar_marcador_entrega(true) → '?'", "")
	n.fijar_marcador_entrega(false)
	_check(not n.marcador_visible(),
		"wrapper: fijar_marcador_entrega(false) lo oculta", "")


## (a) E con el NPC LEJOS: no abre el diálogo, deja interacción pendiente
## (la misma que el segundo clic lejano); al llegar habla solo. Nunca
## ataca ni emite intencion_atacar.
func _t_e_lejos_pendiente() -> void:
	var p: Player = _player(Vector3(0, 0, 0))
	var n: NPC = _npc(Vector3(10, 0, 0))
	p.hablar_con.connect(_al_hablar)
	p.intencion_atacar.connect(_al_intencion)
	_hablados = 0
	_atacados = 0
	p.seleccionar(n)
	p.interactuar() # E con el NPC a 10 m (> RADIO_INTERACCION 3).
	_check(_hablados == 0, "E lejos: NO abre el diálogo de inmediato", "hablados=%d" % _hablados)
	_check(p.tiene_interaccion_pendiente(), "E lejos: deja interacción pendiente", "")
	_check(p.objetivo_ataque == null and _atacados == 0,
		"E nunca fija objetivo de ataque ni emite intencion_atacar", "")
	p._physics_process(0.1)
	_check(p._destino.distance_to(n.global_position) < 0.01,
		"E lejos: el destino de acercamiento es el NPC", "")
	# Llegada simulada (a 2 m del NPC, dentro del radio 3).
	p.global_position = Vector3(8, 0, 0)
	p._physics_process(0.1)
	_check(_hablados == 1, "E lejos: al llegar se abre el diálogo solo", "hablados=%d" % _hablados)
	_check(not p.tiene_interaccion_pendiente(), "E lejos: la interacción pendiente se resolvió", "")


## (b) E con el NPC CERCA: abre el diálogo directo, sin pendiente.
func _t_e_cerca_directo() -> void:
	var p: Player = _player(Vector3(0, 0, 0))
	var n: NPC = _npc(Vector3(2, 0, 0)) # dist 2 < RADIO_INTERACCION 3.
	p.hablar_con.connect(_al_hablar)
	_hablados = 0
	p.seleccionar(n)
	p.interactuar()
	_check(_hablados == 1, "E cerca: abre el diálogo directo", "hablados=%d" % _hablados)
	_check(not p.tiene_interaccion_pendiente(), "E cerca: sin interacción pendiente", "")


## (c) Al completar los objetivos aparece el banner prominente de misión
## completada (integración con la demo: QuestLog.cambiada).
func _t_banner_completada() -> void:
	var demo: Node3D = _demo()
	var log: QuestLog = demo.get("_misiones")
	var panel: PanelMisiones = demo.get("_panel_misiones")
	_check(panel.ultimo_banner == "", "sin banner al arrancar la demo", "")
	_check(log.aceptar("goblins_fuera") == "ok", "aceptar goblins_fuera → ok", "")
	for i in range(5):
		log.registrar_muerte("goblin")
	_check(log.estado("goblins_fuera") == "lista", "5 muertes → misión lista", "")
	_check(panel.banner_visible(), "al completar objetivos aparece el banner", "")
	_check(panel.ultimo_banner == "Goblins fuera",
		"el banner nombra la misión", "ultimo_banner='%s'" % panel.ultimo_banner)
	_check(panel._banner_label.text.contains("Mariscala Ilya Voss"),
		"el banner dice con quién volver", "texto='%s'" % panel._banner_label.text)


## (d) "?" dorado visible SOLO con entrega pendiente; al entregar se
## oculta; con la misión activa (ni disponible ni lista) no hay marcador.
func _t_signo_interrogacion() -> void:
	var demo: Node3D = _demo()
	var log: QuestLog = demo.get("_misiones")
	var ilya: NPC = _npc_demo(demo, "ilya")
	_check(ilya != null, "la demo tiene a Ilya", "")
	_check(ilya.marcador_tipo() == NPC.TipoMarcador.DISPONIBLE,
		"al arrancar: '!' (misión disponible)", "")
	_check(log.aceptar("goblins_fuera") == "ok", "aceptar goblins_fuera → ok", "")
	_check(ilya.marcador_tipo() == NPC.TipoMarcador.NINGUNO,
		"misión activa: sin marcador (ni '!' ni '?')", "")
	_check(not ilya.marcador_visible(), "misión activa: marcador oculto", "")
	for i in range(5):
		log.registrar_muerte("goblin")
	_check(log.estado("goblins_fuera") == "lista", "5 muertes → lista", "")
	_check(ilya.marcador_tipo() == NPC.TipoMarcador.ENTREGAR,
		"entrega pendiente: marcador ENTREGAR", "")
	_check(ilya.marcador_visible(), "'?' visible con entrega pendiente", "")
	_check((ilya.get_node("MarcadorMision") as Label3D).text == "?",
		"el marcador muestra '?'", "")
	var jugador: Player = demo.get_node("Player") as Player
	var res: Dictionary = log.entregar("goblins_fuera", jugador)
	_check(str(res.get("resultado", "")) == "ok", "entregar → ok", "")
	_check(ilya.marcador_tipo() == NPC.TipoMarcador.NINGUNO,
		"al entregar: el '?' desaparece", "")
	_check(not ilya.marcador_visible(), "al entregar: marcador oculto", "")


## (e) Prioridad: la "?" de entrega manda sobre el "!" de disponible.
func _t_prioridad() -> void:
	_check(DEMO_GD._prioridad_marcador(true, true) == NPC.TipoMarcador.ENTREGAR,
		"entrega+disponible → '?'", "")
	_check(DEMO_GD._prioridad_marcador(false, true) == NPC.TipoMarcador.DISPONIBLE,
		"solo disponible → '!'", "")
	_check(DEMO_GD._prioridad_marcador(true, false) == NPC.TipoMarcador.ENTREGAR,
		"solo entrega → '?'", "")
	_check(DEMO_GD._prioridad_marcador(false, false) == NPC.TipoMarcador.NINGUNO,
		"nada → sin marcador", "")
