extends SceneTree
## Tests headless de la Fase 6 (NPCs data-driven completos + interacción).
##
## Cubre: NpcDB (nombre/rol/líneas desde data/npcs.json, mismo patrón que
## ItemDB/SkillDB), NPC.configurar (incluye tolerancia a campos ausentes),
## Player.interactuar (emite hablar_con solo con un NPC vivo seleccionado;
## sin selección o con un enemigo no hace nada), VentanaDialogo (mostrar
## con nombre/rol/líneas correctas, avanzar por líneas, cerrar al final,
## ESC/E la consumen antes que el Player; arranca oculta y no se come
## clics), save/load v3 con NPCs (id + posición; partidas v2 sin NPCs
## cargan igual) y regresión de la REGLA DURA (NPCs siguen no atacables).
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_npcs.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const NP: GDScript = preload("res://scripts/npc/npc.gd")
const NDB: GDScript = preload("res://scripts/npc/npc_db.gd")
const ENT: GDScript = preload("res://scripts/core/entity.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const SV: GDScript = preload("res://scripts/save/save_system.gd")
const DLG: GDScript = preload("res://scripts/ui/ventana_dialogo.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _hablados: Array = []
var _cerrados: int = 0


func _init() -> void:
	print("[TEST] Fase 6 — NPCs data-driven + dialogo + save v3")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b): todo lo que
## usa global_position o get_tree() corre aquí.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	NDB.cargar()
	_t_db()
	_t_configurar()
	_t_interactuar()
	_t_interactuar_sin_seleccion()
	_t_interactuar_con_enemigo()
	_t_dialogo()
	_t_dialogo_input()
	_t_save_npcs()
	_t_save_tolerante_v2()
	_t_regla_dura()
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


func _al_hablar(npc: NPC) -> void:
	_hablados.append(npc)


func _al_cerrar() -> void:
	_cerrados += 1


func _player(pos: Vector3) -> Player:
	var p: Player = PL.new()
	p.add_to_group("jugador")
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


func _enemigo(pos: Vector3) -> Enemy:
	var e: Enemy = EN.new()
	e.add_to_group("enemigos")
	root.add_child(e)
	e.global_position = pos
	_basura.append(e)
	return e


func _npc(id: String, pos: Vector3) -> NPC:
	var n: NPC = NP.new()
	n.add_to_group("npcs")
	root.add_child(n)
	n.global_position = pos
	n.configurar(NDB.obtener(id))
	_basura.append(n)
	return n


func _dialogo() -> VentanaDialogo:
	var d: VentanaDialogo = DLG.new()
	root.add_child(d)
	_basura.append(d)
	return d


## --- NpcDB: datos puros ---


func _t_db() -> void:
	_check(NDB.existe("ilya"), "db: existe ilya")
	_check(NDB.existe("bram"), "db: existe bram")
	_check(not NDB.existe("nadie"), "db: no existe id inventado")
	var ilya: Dictionary = NDB.obtener("ilya")
	_check(str(ilya.get("nombre", "")) == "Mariscala Ilya Voss",
		"db: nombre de ilya", str(ilya.get("nombre", "")))
	_check(str(ilya.get("rol", "")) == "Mariscala de Liberty",
		"db: rol de ilya", str(ilya.get("rol", "")))
	var lineas: Array = ilya.get("dialogo", [])
	_check(lineas.size() == 4, "db: ilya tiene 4 líneas", str(lineas.size()))
	_check(str(lineas[0]).contains("Piedraceniza"),
		"db: primera línea de ilya menciona Piedraceniza")
	var bram: Dictionary = NDB.obtener("bram")
	_check(str(bram.get("rol", "")) == "Herrero de Piedraceniza",
		"db: rol de bram", str(bram.get("rol", "")))
	_check((bram.get("dialogo", []) as Array).size() == 3,
		"db: bram tiene 3 líneas")
	_check(NDB.obtener("nadie").is_empty(), "db: obtener() id malo = {}")
	var ids: Array[String] = NDB.ids()
	_check(ids.has("ilya") and ids.has("bram"), "db: ids() incluye ambos")


## --- NPC.configurar: data-driven + tolerante ---


func _t_configurar() -> void:
	var n: NPC = _npc("bram", Vector3(-5, 0, 5))
	_check(n.npc_id == "bram", "npc: npc_id bram")
	_check(n.nombre_mostrado == "Herrero Bram", "npc: nombre_mostrado bram")
	_check(n.rol == "Herrero de Piedraceniza", "npc: rol bram")
	_check(n.lineas_dialogo.size() == 3, "npc: 3 líneas de bram")
	_check(not n.combatible, "npc: no combatible (regla dura)")
	# Tolerancia: campos ausentes no revientan.
	var vacio: NPC = NP.new()
	root.add_child(vacio)
	_basura.append(vacio)
	vacio.configurar({})
	_check(vacio.npc_id == "", "npc: configurar({}) npc_id vacío")
	_check(vacio.lineas_dialogo.is_empty(), "npc: configurar({}) sin líneas")


## --- Player.interactuar: intención de hablar ---


func _t_interactuar() -> void:
	_hablados.clear()
	var p: Player = _player(Vector3.ZERO)
	var n: NPC = _npc("ilya", Vector3(5, 0, 5))
	p.hablar_con.connect(_al_hablar)
	p.seleccionar(n)
	p.interactuar()
	_check(_hablados.size() == 1, "interactuar: emite hablar_con una vez")
	_check(_hablados[0] == n, "interactuar: emite el NPC seleccionado")


func _t_interactuar_sin_seleccion() -> void:
	_hablados.clear()
	var p: Player = _player(Vector3.ZERO)
	p.hablar_con.connect(_al_hablar)
	p.interactuar()
	_check(_hablados.is_empty(), "interactuar: sin selección no emite nada")
	# Selección muerta/tonta tampoco falla.
	p.interactuar()
	_check(_hablados.is_empty(), "interactuar: repetido sin selección no falla")


func _t_interactuar_con_enemigo() -> void:
	_hablados.clear()
	var p: Player = _player(Vector3.ZERO)
	var e: Enemy = _enemigo(Vector3(3, 0, 0))
	p.hablar_con.connect(_al_hablar)
	p.seleccionar(e)
	p.interactuar()
	_check(_hablados.is_empty(), "interactuar: con enemigo no abre diálogo")


## --- VentanaDialogo: solo lee datos del NPC ---


func _t_dialogo() -> void:
	_cerrados = 0
	var d: VentanaDialogo = _dialogo()
	# Lección 11: arranca oculta y sin comerse clics.
	_check(not d.esta_abierta(), "dialogo: arranca cerrada")
	_check(not d.visible, "dialogo: visible=false al arrancar")
	d.dialogo_cerrado.connect(_al_cerrar)
	var n: NPC = _npc("ilya", Vector3(5, 0, 5))
	d.mostrar(n)
	_check(d.esta_abierta(), "dialogo: mostrar() la abre")
	_check(d.npc_actual() == n, "dialogo: npc_actual es el NPC")
	_check(d.titulo_texto() == "Mariscala Ilya Voss",
		"dialogo: título con el nombre", d.titulo_texto())
	_check(d.rol_texto() == "Mariscala de Liberty",
		"dialogo: rol", d.rol_texto())
	_check(d.indice() == 0, "dialogo: arranca en la línea 0")
	_check(d.linea_actual().contains("Piedraceniza"),
		"dialogo: primera línea de ilya")
	# Avance por líneas.
	d.avanzar()
	_check(d.indice() == 1, "dialogo: avanzar → línea 1")
	d.avanzar()
	d.avanzar()
	_check(d.indice() == 3, "dialogo: línea 3 (última)")
	_check(d.linea_actual().contains("vuelve a hablarme"),
		"dialogo: última línea de ilya")
	d.avanzar()
	_check(not d.esta_abierta(), "dialogo: tras la última se cierra")
	_check(_cerrados == 1, "dialogo: emite dialogo_cerrado una vez")
	_check(d.linea_actual() == "", "dialogo: cerrada → línea vacía")
	_check(d.indice() == -1, "dialogo: cerrada → índice -1")
	# mostrar(null) no hace nada (sin errores).
	d.mostrar(null)
	_check(not d.esta_abierta(), "dialogo: mostrar(null) no abre")
	# Bram: 3 líneas.
	d.mostrar(_npc("bram", Vector3(-5, 0, 5)))
	d.avanzar()
	d.avanzar()
	d.avanzar()
	_check(not d.esta_abierta(), "dialogo: bram cierra tras 3 líneas")


func _t_dialogo_input() -> void:
	var d: VentanaDialogo = _dialogo()
	var n: NPC = _npc("bram", Vector3(-5, 0, 5))
	d.mostrar(n)
	# E (acción interactuar) avanza; se consume antes que el Player.
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "interactuar"
	ev.pressed = true
	d._input(ev)
	_check(d.indice() == 1, "dialogo: E avanza (consumida en _input)")
	# ESC (acción cancelar_seleccion) cierra el diálogo.
	var esc: InputEventAction = InputEventAction.new()
	esc.action = "cancelar_seleccion"
	esc.pressed = true
	d._input(esc)
	_check(not d.esta_abierta(), "dialogo: ESC cierra")
	# Con el diálogo cerrado, _input no toca nada.
	d._input(ev)
	_check(not d.esta_abierta(), "dialogo: _input cerrada no reabre")


## --- Save v3: NPCs (id + posición); v2 sin NPCs carga igual ---


func _t_save_npcs() -> void:
	var s: SaveSystem = SV.new()
	var p: Player = _player(Vector3.ZERO)
	var n1: NPC = _npc("ilya", Vector3(5, 0, 5))
	var n2: NPC = _npc("bram", Vector3(-5, 0, 5))
	s.jugador = p
	s.enemigos = []
	s.npcs = [n1, n2]
	_check(s.guardar(), "save v3: guardar() true")
	# Mover los NPCs: al cargar deben volver a la posición guardada.
	n1.global_position = Vector3(20, 0, 20)
	n2.global_position = Vector3(-20, 0, -20)
	_check(s.cargar(), "save v3: cargar() true")
	_check(n1.global_position.distance_to(Vector3(5, 0, 5)) < 0.01,
		"save v3: ilya vuelve a su posición", str(n1.global_position))
	_check(n2.global_position.distance_to(Vector3(-5, 0, 5)) < 0.01,
		"save v3: bram vuelve a su posición", str(n2.global_position))
	# Guardar sin NPCs asignados no falla.
	var s2: SaveSystem = SV.new()
	s2.jugador = p
	_check(s2.guardar(), "save v3: npcs vacío también guarda")


func _t_save_tolerante_v2() -> void:
	# Partida vieja (v2): sin bloque "npcs". Debe cargar igual y los NPCs
	# quedan donde los dejó la escena.
	var s: SaveSystem = SV.new()
	var p: Player = _player(Vector3.ZERO)
	var n: NPC = _npc("ilya", Vector3(5, 0, 5))
	s.jugador = p
	s.enemigos = []
	s.npcs = [n]
	n.global_position = Vector3(11, 0, 12)
	_check(s.guardar(), "save v2: guardar v3 primero")
	# Quitar el bloque "npcs" para simular una partida de la fase 5.1.
	var texto: String = FileAccess.get_file_as_string(SV.RUTA)
	var datos = JSON.parse_string(texto)
	_check(datos is Dictionary, "save v2: JSON legible")
	(datos as Dictionary).erase("npcs")
	var f: FileAccess = FileAccess.open(SV.RUTA, FileAccess.WRITE)
	f.store_string(JSON.stringify(datos))
	f.close()
	n.global_position = Vector3(30, 0, 30)
	_check(s.cargar(), "save v2: cargar() true sin bloque npcs")
	_check(n.global_position.distance_to(Vector3(30, 0, 30)) < 0.01,
		"save v2: NPC conserva su posición de escena", str(n.global_position))


## --- Regresión: REGLA DURA (los NPCs no se atacan) ---


func _t_regla_dura() -> void:
	var p: Player = _player(Vector3.ZERO)
	var n: NPC = _npc("ilya", Vector3(2, 0, 0))
	var vida0: float = n.vida_actual
	n.take_damage(50.0, p)
	_check(is_equal_approx(n.vida_actual, vida0),
		"regla dura: take_damage no toca al NPC")
	_check(n.esta_vivo(), "regla dura: el NPC sigue vivo")
	p.seleccionar(n)
	_check(p.seleccion == n, "regla dura: el NPC sí se puede seleccionar")
	p.solicitar_ataque()
	_check(p.objetivo_ataque == null,
		"regla dura: solicitar_ataque ignora el NPC seleccionado")
