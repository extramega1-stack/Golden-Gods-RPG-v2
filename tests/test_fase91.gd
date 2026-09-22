extends SceneTree
## Tests headless de la Fase 9.1.
##
## (a) "!" dorado sobre NPCs con misión disponible (pedido de Juan Diego):
## `NPC.fijar_marcador_mision` crea un Label3D con billboard, dorado,
## flotando sobre la cabeza, oculto al inicio; la demo refresca los
## marcadores con la señal `cambiada` del QuestLog (al aceptar, el "!"
## desaparece; solo "disponible" muestra el marcador).
## (b) Segundo clic en NPC lejano = caminar y hablar al llegar: el
## resolver devuelve INTERACTUAR, `_aplicar_clic` deja una interacción
## pendiente si está lejos (o habla directo si está cerca), el jugador
## camina y al llegar dentro de RADIO_INTERACCION emite `hablar_con`;
## se cancela al deseleccionar; nunca ataca ni emite intencion_atacar.
## (c) Respawn en la escena demo REAL (repro del bug reportado en la fase
## 9.1): matar un mob en `fase9_demo.tscn`, avanzar el tiempo más allá de
## `respawn_seg` y el mob reaparece. (El repro demostró que el spawner SÍ
## estaba instanciado —el grep original buscó el path del archivo y el
## código usa el class_name `SpawnerMobs`—; este test lo blinda.)
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase91.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const NP: GDScript = preload("res://scripts/npc/npc.gd")
const ENT: GDScript = preload("res://scripts/core/entity.gd")
const DEMO: PackedScene = preload("res://scenes/demo/fase9_demo.tscn")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _hablados: int = 0
var _atacados: int = 0


func _init() -> void:
	print("[TEST] Fase 9.1 — '!' dorado, segundo clic en NPC lejano, respawn en demo real")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b).
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_marcador_api()
	_t_marcador_demo()
	_t_segundo_clic_npc_cerca()
	_t_segundo_clic_npc_lejos_camina()
	_t_interaccion_se_cancela_al_deseleccionar()
	_t_respawn_demo_real()
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


func _enemigo(pos: Vector3) -> Enemy:
	var e: Enemy = EN.new()
	e.add_to_group("enemigos")
	root.add_child(e)
	e.global_position = pos
	_basura.append(e)
	return e


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


## (a.1) El marcador: API del NPC.
func _t_marcador_api() -> void:
	var n: NPC = _npc(Vector3(0, 0, 0))
	_check(not n.marcador_visible(), "el '!' arranca oculto", "")
	n.fijar_marcador_mision(true)
	_check(n.marcador_visible(), "fijar_marcador_mision(true) lo muestra", "")
	var label: Label3D = n.get_node_or_null("MarcadorMision") as Label3D
	_check(label != null, "el marcador es un Label3D hijo del NPC", "")
	_check(label.text == "!", "el marcador muestra '!'", "texto='%s'" % label.text)
	_check(label.billboard == BaseMaterial3D.BILLBOARD_ENABLED,
		"el marcador tiene billboard activado", "")
	_check(label.modulate == NPC.COLOR_MARCADOR, "el marcador es dorado", "")
	_check(label.position.y >= 2.0, "el marcador flota sobre la cabeza", "y=%.2f" % label.position.y)
	n.fijar_marcador_mision(true)
	var cuantos: int = 0
	for h in n.get_children():
		if h is Label3D:
			cuantos += 1
	_check(cuantos == 1, "fijar(true) dos veces no duplica el Label3D", "hay %d" % cuantos)
	n.fijar_marcador_mision(false)
	_check(not n.marcador_visible(), "fijar_marcador_mision(false) lo oculta", "")


## (a.2) La demo refresca los marcadores con QuestLog.cambiada: solo
## "disponible" muestra el "!"; al aceptar desaparece.
func _t_marcador_demo() -> void:
	var demo: Node3D = DEMO.instantiate()
	root.add_child(demo)
	_basura.append(demo)
	var npcs: Array = demo.get("_lista_npcs")
	# Fase 16: 20 NPCs (ilya/bram/sira con misiones + 8 ambientales sin + 9 porteros).
	_check(npcs.size() == 20, "la demo crea 20 NPCs", "hay %d" % npcs.size())
	var por_id: Dictionary = {}
	for x in npcs:
		var q: NPC = x as NPC
		por_id[q.npc_id] = q
	for k in ["ilya", "bram", "sira"]:
		_check(por_id.has(k), "demo: npc con mision %s" % k)
		_check((por_id[k] as NPC).marcador_visible(),
			"al arrancar hay misión disponible: '!' visible (%s)" % str(k), "")
	for k in ["yasmina", "durnan", "sella", "elthar", "vex", "karg", "maris", "aurelio"]:
		_check(por_id.has(k), "demo: npc ambiental %s" % k)
		_check(not (por_id[k] as NPC).marcador_visible(),
			"el ambiental %s no tiene mision: sin '!'" % k)
	var log: QuestLog = demo.get("_misiones")
	_check(log.aceptar("goblins_fuera") == "ok", "aceptar goblins_fuera → ok", "")
	_check(not (por_id["ilya"] as NPC).marcador_visible(),
		"al aceptar, el '!' de Ilya desaparece (ya no está disponible)", "")
	_check((por_id["bram"] as NPC).marcador_visible(),
		"el '!' de Bram sigue (su misión sigue disponible)", "")
	_check((por_id["sira"] as NPC).marcador_visible(),
		"el '!' de Sira sigue (su misión sigue disponible)", "")


## (b.1) Segundo clic en NPC cercano: habla directo, sin moverse.
func _t_segundo_clic_npc_cerca() -> void:
	var p: Player = _player(Vector3(300, 0, 300))
	var n: NPC = _npc(Vector3(302, 0, 300))
	p.hablar_con.connect(_al_hablar)
	p.intencion_atacar.connect(_al_intencion)
	_hablados = 0
	_atacados = 0
	p.seleccionar(n)
	var a: int = p._resolver_clic_entidad(n)
	_check(a == PL.AccionClic.INTERACTUAR, "segundo clic en NPC → INTERACTUAR", "accion=%d" % a)
	p._aplicar_clic(n, a)
	_check(_hablados == 1, "NPC cercano: el segundo clic abre el diálogo directo", "hablados=%d" % _hablados)
	_check(not p.tiene_interaccion_pendiente(), "NPC cercano: sin interacción pendiente", "")
	_check(p.objetivo_ataque == null and _atacados == 0,
		"hablar con NPC nunca ataca ni emite intencion_atacar", "")


## (b.2) Segundo clic en NPC lejano: camina hasta él y al llegar habla solo.
## (Determinista: move_and_slide() en el harness --script no integra
## movimiento real —convención de test_seleccion.gd—, así que la llegada
## se simula; el movimiento físico ya lo cubren test_player + el playtest.)
func _t_segundo_clic_npc_lejos_camina() -> void:
	var p: Player = _player(Vector3(0, 0, 0))
	var n: NPC = _npc(Vector3(10, 0, 0))
	p.hablar_con.connect(_al_hablar)
	p.intencion_atacar.connect(_al_intencion)
	_hablados = 0
	_atacados = 0
	p.seleccionar(n)
	var a: int = p._resolver_clic_entidad(n)
	_check(a == PL.AccionClic.INTERACTUAR, "segundo clic en NPC lejano → INTERACTUAR", "accion=%d" % a)
	p._aplicar_clic(n, a)
	_check(p.tiene_interaccion_pendiente(), "NPC lejano: queda interacción pendiente", "")
	_check(_hablados == 0, "NPC lejano: aún no habla (está caminando)", "")
	# La orden de acercamiento apunta al NPC…
	p._physics_process(0.1)
	_check(p.tiene_interaccion_pendiente(), "lejos: el pendiente persiste", "")
	_check(p._destino.distance_to(n.global_position) < 0.01,
		"el destino de acercamiento es el NPC", "")
	# …y lo sigue si se mueve.
	n.global_position = Vector3(12, 0, 0)
	p._physics_process(0.1)
	_check(p._destino.distance_to(Vector3(12, 0, 0)) < 0.01,
		"el destino sigue al NPC en movimiento", "")
	# Al llegar al radio de interacción (llegada simulada), habla solo.
	p.global_position = Vector3(10, 0, 0) # a 2 del NPC (radio 3)
	p._physics_process(0.1)
	_check(_hablados == 1, "al llegar al NPC se abre el diálogo solo", "hablados=%d" % _hablados)
	_check(not p.tiene_interaccion_pendiente(), "la interacción pendiente se resolvió", "")
	_check(p.objetivo_ataque == null and _atacados == 0,
		"caminar a un NPC nunca ataca ni emite intencion_atacar", "")


## (b.3) Deseleccionar cancela la interacción pendiente.
func _t_interaccion_se_cancela_al_deseleccionar() -> void:
	var p: Player = _player(Vector3(50, 0, 50))
	var n: NPC = _npc(Vector3(60, 0, 50))
	p.hablar_con.connect(_al_hablar)
	_hablados = 0
	p.seleccionar(n)
	p._aplicar_clic(n, p._resolver_clic_entidad(n))
	_check(p.tiene_interaccion_pendiente(), "hay interacción pendiente antes de cancelar", "")
	p.deseleccionar()
	for i in range(10):
		p._physics_process(1.0 / 60.0)
	_check(not p.tiene_interaccion_pendiente(), "deseleccionar cancela la interacción pendiente", "")
	_check(_hablados == 0, "cancelada: el diálogo nunca se abre", "")


## Enemigos que cuelgan de un nodo (el grupo "enemigos" es global y puede
## haber más de una demo instanciada en el mismo árbol).
func _enemigos_de(nodo: Node) -> Array:
	var res: Array = []
	var pila: Array = [nodo]
	while not pila.is_empty():
		var actual: Node = pila.pop_back()
		for h in actual.get_children():
			if h is Enemy:
				res.append(h)
			pila.append(h)
	return res


## (c) Respawn en la escena demo REAL: matar un mob, avanzar el tiempo más
## allá de `respawn_seg` y el mob reaparece (repro guardado como test).
func _t_respawn_demo_real() -> void:
	var demo: Node3D = DEMO.instantiate()
	root.add_child(demo)
	_basura.append(demo)
	var bichos: Array = _enemigos_de(demo)
	_check(bichos.size() == 15, "la demo tiene 15 mobs (5 por arquetipo)", "hay %d" % bichos.size())
	var cuenta: Dictionary = {"goblin": 0, "lobo": 0, "ogro": 0}
	for b in bichos:
		var aid: String = str((b as Enemy).arquetipo_id)
		cuenta[aid] = int(cuenta.get(aid, 0)) + 1
	_check(int(cuenta.get("goblin", 0)) == 5, "5 goblins en la demo", "")
	_check(int(cuenta.get("lobo", 0)) == 5, "5 lobos en la demo", "")
	_check(int(cuenta.get("ogro", 0)) == 5, "5 ogros en la demo", "")
	# Fuera del aggro inicial (máx radio_aggro = 14, lobo).
	var jugador: Entity = demo.get_node("Player") as Entity
	var todos_fuera: bool = true
	for b in bichos:
		var dd: Vector3 = (b as Node3D).global_position - jugador.global_position
		dd.y = 0.0
		if dd.length() <= 14.0:
			todos_fuera = false
	_check(todos_fuera, "los 15 mobs arrancan fuera del aggro del jugador", "")
	# Matar un goblin en la demo real.
	var victima: Enemy = null
	for b in bichos:
		if str((b as Enemy).arquetipo_id) == "goblin":
			victima = b as Enemy
			break
	_check(victima != null, "hay un goblin para matar", "")
	var origen: Vector3 = victima.global_position
	victima.take_damage(victima.stats.vida_max + 1000.0, jugador)
	_check(not victima.esta_vivo(), "el goblin murió", "")
	var spawner: SpawnerMobs = demo.get("_spawner")
	_check(spawner != null, "la demo tiene su SpawnerMobs instanciado", "")
	_check(spawner.pendientes() == 1, "el spawner programó el respawn", "")
	# Avanzar más allá de respawn_seg (goblin = 15 s).
	spawner.avanzar(16.0)
	var vivos: int = 0
	var nuevo_cerca: bool = false
	for b2 in _enemigos_de(demo):
		var e2: Enemy = b2 as Enemy
		if e2.esta_vivo():
			vivos += 1
			if e2.arquetipo_id == "goblin":
				var dp: Vector3 = e2.global_position - origen
				dp.y = 0.0
				if dp.length() <= 5.0:
					nuevo_cerca = true
	_check(vivos == 15, "el goblin reapareció (15 vivos otra vez)", "vivos=%d" % vivos)
	_check(nuevo_cerca, "el reaparecido está cerca de su punto de origen", "")
	_check((demo.get("_lista_enemigos") as Array).size() == 15,
		"la lista del guardado vuelve a tener 15",
		"hay %d" % (demo.get("_lista_enemigos") as Array).size())
