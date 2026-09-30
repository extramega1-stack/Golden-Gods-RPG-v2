extends SceneTree
## Tests headless de la Fase 8 (Misiones / quests data-driven).
##
## Cubre: QuestDB (3 misiones desde data/quests.json, mismo patrón que
## NpcDB/TiendaDB), QuestLog (aceptar con códigos "ok"/"desconocida"/
## "no_disponible"; registrar_muerte x5 → "lista" y progreso_texto "5/5";
## sincronizar_recoleccion con Inventario real → "lista"; entregar da
## oro/XP/items, consume los items recolectados y pasa a "entregada";
## entregar sin completar → "no_lista"; registrar_dialogo completa
## "hablar"; oferta_para_npc disponible/activa/lista; señal `cambiada`;
## round-trip to_dict/from_dict versionado; from_dict({}) tolerante),
## save v5 (misiones persistidas; partida v4 sin bloque "misiones" carga
## con QuestLog vacío), PanelMisiones (arranca oculto; alternar; toast) y
## VentanaDialogo (mostrar_mision: disponible/entregar/ocultar; la señal
## `mision_solicitada` se emite SIN cerrar el diálogo).
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_quests.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const NP: GDScript = preload("res://scripts/npc/npc.gd")
const NDB: GDScript = preload("res://scripts/npc/npc_db.gd")
const QDB: GDScript = preload("res://scripts/quests/quest_db.gd")
const RDR: GDScript = preload("res://scripts/progresion/rotacion_diaria.gd")
const QL: GDScript = preload("res://scripts/quests/quest_log.gd")
const INV: GDScript = preload("res://scripts/inventory/inventory.gd")
const SV: GDScript = preload("res://scripts/save/save_system.gd")
const DLG: GDScript = preload("res://scripts/ui/ventana_dialogo.gd")
const PM: GDScript = preload("res://scripts/ui/panel_misiones.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _cambiadas: int = 0
var _mision_pedida: int = 0


func _init() -> void:
	print("[TEST] Fase 8 — Misiones / quests data-driven")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b): todo lo que
## usa global_position o get_tree() corre aquí.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	NDB.cargar()
	QDB.cargar()
	_t_db()
	_t_aceptar()
	_t_matar()
	_t_recolectar()
	_t_entregar()
	_t_entregar_sin_completar()
	_t_hablar()
	_t_oferta()
	_t_cambiada()
	_t_roundtrip()
	_t_save_v5()
	_t_save_tolerante_v4()
	_t_panel()
	_t_dialogo_mision()
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


func _al_cambiada() -> void:
	_cambiadas += 1


func _al_mision(_npc: NPC) -> void:
	_mision_pedida += 1


func _player(pos: Vector3) -> Player:
	var p: Player = PL.new()
	p.add_to_group("jugador")
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


func _npc(id: String, pos: Vector3) -> NPC:
	var n: NPC = NP.new()
	n.add_to_group("npcs")
	root.add_child(n)
	n.global_position = pos
	n.configurar(NDB.obtener(id))
	_basura.append(n)
	return n


func _log() -> QuestLog:
	return QL.new()


## --- QuestDB: datos puros ---


func _t_db() -> void:
	_check(QDB.existe("goblins_fuera"), "db: existe goblins_fuera")
	_check(QDB.existe("colmillos_forja"), "db: existe colmillos_forja")
	_check(QDB.existe("mensaje_sira"), "db: existe mensaje_sira")
	_check(not QDB.existe("mision_fantasma"), "db: no existe id inventado")
	var ids: Array[String] = QDB.ids()
	# Fase 22: 25 = 3 de Moon Town + 22 de las cadenas por ciudad.
	# Fase 23: 29 = 25 + 4 del Acto I. Fase 24: 32 = 29 + 3 del Acto II.
	# El catálogo ESCRITO, sin la rotación de runtime: `ids()` mezcla las dos
	# cosas porque es lo que necesita el juego, y su total depende de qué día
	# es (60 hoy, 61 mañana). Lo que se afirma acá es que el catálogo escrito
	# no se encogió: 41 del juego base + 15 de NG+.
	_check(QDB.ids_de_archivo().size() == 56,
		"db: 56 misiones escritas (41 base + 15 NG+)",
		str(QDB.ids_de_archivo().size()))
	_check(ids.size() == QDB.ids_de_archivo().size()
			+ RDR.dias_por_dia() + RDR.semanas_por_semana(),
		"db: y el total con la rotación de hoy son esas + los encargos de hoy",
		str(ids.size()))
	var g: Dictionary = QDB.obtener("goblins_fuera")
	_check(str(g.get("nombre", "")) == "Goblins fuera",
		"db: nombre Goblins fuera")
	_check(str(g.get("npc_origen", "")) == "ilya",
		"db: goblins_fuera es de ilya")
	var obj: Array = g.get("objetivos", [])
	_check(obj.size() == 1, "db: goblins_fuera tiene 1 objetivo")
	var o0: Dictionary = obj[0]
	_check(str(o0.get("tipo", "")) == "matar"
		and str(o0.get("arquetipo", "")) == "goblin"
		and int(o0.get("cantidad", 0)) == 5,
		"db: matar 5 goblins")
	var rec: Dictionary = rec_obtener_recompensas("colmillos_forja")
	_check(int(rec.get("oro", 0)) == 100 and int(rec.get("xp", 0)) == 80,
		"db: colmillos_forja recompensa 100 oro / 80 xp")
	var rit: Array = rec.get("items", [])
	_check(rit.size() == 1 and str((rit[0] as Dictionary).get("id", "")) == "espada_hierro",
		"db: colmillos_forja da espada_hierro")
	var m: Dictionary = QDB.obtener("mensaje_sira")
	_check(str(m.get("npc_origen", "")) == "sira",
		"db: mensaje_sira es de sira")
	var mo: Dictionary = (m.get("objetivos", []) as Array)[0]
	_check(str(mo.get("tipo", "")) == "hablar"
		and str(mo.get("npc", "")) == "ilya",
		"db: mensaje_sira pide hablar con ilya")


func rec_obtener_recompensas(qid: String) -> Dictionary:
	return QDB.obtener(qid).get("recompensas", {})


## --- aceptar() ---


func _t_aceptar() -> void:
	var q: QuestLog = _log()
	_check(q.estado("goblins_fuera") == "disponible",
		"aceptar: estado inicial disponible")
	_check(q.aceptar("goblins_fuera") == "ok", "aceptar: ok")
	_check(q.estado("goblins_fuera") == "activa",
		"aceptar: pasa a activa")
	_check(q.aceptar("goblins_fuera") == "no_disponible",
		"aceptar: dos veces -> no_disponible")
	_check(q.aceptar("mision_fantasma") == "desconocida",
		"aceptar: desconocida -> desconocida")
	_check(q.estado("mision_fantasma") == "desconocida",
		"aceptar: estado de desconocida")
	_check(q.estado("colmillos_forja") == "disponible",
		"aceptar: las otras siguen disponibles")
	_check(q.progreso_texto("goblins_fuera") == "Goblins derrotados: 0/5",
		"aceptar: progreso inicial 0/5")
	_check(q.progreso_texto("mision_fantasma") == "",
		"aceptar: progreso_texto de desconocida es \"\"")


## --- registrar_muerte() ---


func _t_matar() -> void:
	var q: QuestLog = _log()
	q.aceptar("goblins_fuera")
	q.registrar_muerte("lobo")
	q.registrar_muerte("lobo")
	_check(q.progreso_texto("goblins_fuera") == "Goblins derrotados: 0/5",
		"matar: lobos no cuentan para goblins")
	for i in 4:
		q.registrar_muerte("goblin")
	_check(q.estado("goblins_fuera") == "activa",
		"matar: con 4/5 sigue activa")
	_check(q.progreso_texto("goblins_fuera") == "Goblins derrotados: 4/5",
		"matar: progreso 4/5")
	q.registrar_muerte("goblin")
	_check(q.estado("goblins_fuera") == "lista",
		"matar: con 5/5 pasa a lista")
	_check(q.progreso_texto("goblins_fuera") == "Goblins derrotados: 5/5",
		"matar: progreso 5/5")
	q.registrar_muerte("goblin")
	_check(q.estado("goblins_fuera") == "lista",
		"matar: de más no saca de lista")
	_check(q.progreso_texto("goblins_fuera") == "Goblins derrotados: 5/5",
		"matar: el progreso no pasa de 5/5")


## --- sincronizar_recoleccion() ---


func _t_recolectar() -> void:
	var q: QuestLog = _log()
	q.aceptar("colmillos_forja")
	var inv: Inventario = INV.new()
	q.sincronizar_recoleccion(inv)
	_check(q.progreso_texto("colmillos_forja") == "Colmillos de lobo: 0/4",
		"recolectar: vacío -> 0/4")
	inv.agregar("colmillo", 2)
	q.sincronizar_recoleccion(inv)
	_check(q.progreso_texto("colmillos_forja") == "Colmillos de lobo: 2/4",
		"recolectar: 2 colmillos -> 2/4")
	_check(q.estado("colmillos_forja") == "activa",
		"recolectar: con 2/4 sigue activa")
	inv.agregar("colmillo", 2)
	q.sincronizar_recoleccion(inv)
	_check(q.estado("colmillos_forja") == "lista",
		"recolectar: con 4/4 pasa a lista")
	# Sincronizar es idempotente: vender/gastar baja el progreso (pero la
	# misión lista ya no se toca: solo las activas se sincronizan).
	inv.quitar("colmillo", 4)
	q.sincronizar_recoleccion(inv)
	_check(q.estado("colmillos_forja") == "lista",
		"recolectar: lista no retrocede al vender")


## --- entregar() ---


func _t_entregar() -> void:
	var q: QuestLog = _log()
	var p: Player = _player(Vector3.ZERO)
	q.aceptar("colmillos_forja")
	p.inventario.agregar("colmillo", 4)
	q.sincronizar_recoleccion(p.inventario)
	_check(q.estado("colmillos_forja") == "lista",
		"entregar: precondición lista")
	var res: Dictionary = q.entregar("colmillos_forja", p)
	_check(str(res.get("resultado", "")) == "ok", "entregar: resultado ok")
	_check(int(res.get("oro", 0)) == 100, "entregar: oro 100")
	_check(int(res.get("xp", 0)) == 80, "entregar: xp 80")
	var items: Array = res.get("items", [])
	_check(items.size() == 1
		and str((items[0] as Dictionary).get("id", "")) == "espada_hierro",
		"entregar: devuelve la espada_hierro")
	_check(p.oro == 100, "entregar: oro sumado al jugador", str(p.oro))
	_check(p.inventario.contar("colmillo") == 0,
		"entregar: consume los 4 colmillos")
	_check(p.inventario.contar("espada_hierro") == 1,
		"entregar: espada_hierro en inventario")
	_check(q.estado("colmillos_forja") == "entregada",
		"entregar: pasa a entregada")
	_check(q.aceptar("colmillos_forja") == "no_disponible",
		"entregar: entregada no se puede re-aceptar")
	# Sobrante: si el jugador traía más colmillos, solo se consumen 4.
	var q2: QuestLog = _log()
	var p2: Player = _player(Vector3.ZERO)
	q2.aceptar("colmillos_forja")
	p2.inventario.agregar("colmillo", 7)
	q2.sincronizar_recoleccion(p2.inventario)
	q2.entregar("colmillos_forja", p2)
	_check(p2.inventario.contar("colmillo") == 3,
		"entregar: sobrante (7-4=3) intacto")


func _t_entregar_sin_completar() -> void:
	var q: QuestLog = _log()
	var p: Player = _player(Vector3.ZERO)
	q.aceptar("goblins_fuera")
	var res: Dictionary = q.entregar("goblins_fuera", p)
	_check(str(res.get("resultado", "")) == "no_lista",
		"entregar: activa sin completar -> no_lista")
	_check(p.oro == 0, "entregar: no_lista no da oro")
	var res2: Dictionary = q.entregar("mision_fantasma", p)
	_check(str(res2.get("resultado", "")) == "desconocida",
		"entregar: desconocida -> desconocida")


## --- registrar_dialogo() ---


func _t_hablar() -> void:
	var q: QuestLog = _log()
	q.aceptar("mensaje_sira")
	q.registrar_dialogo("bram")
	_check(q.estado("mensaje_sira") == "activa",
		"hablar: otro npc no completa")
	q.registrar_dialogo("ilya")
	_check(q.estado("mensaje_sira") == "lista",
		"hablar: registrar_dialogo(ilya) completa mensaje_sira")
	_check(q.progreso_texto("mensaje_sira") == "Mensaje entregado a Ilya: 1/1",
		"hablar: progreso 1/1")
	var p: Player = _player(Vector3.ZERO)
	var res: Dictionary = q.entregar("mensaje_sira", p)
	_check(str(res.get("resultado", "")) == "ok", "hablar: entregar ok")
	_check(p.oro == 50, "hablar: +50 oro", str(p.oro))
	_check(p.inventario.contar("pocion_mana") == 2,
		"hablar: 2 pocion_mana de recompensa")


## --- oferta_para_npc() ---


func _t_oferta() -> void:
	var q: QuestLog = _log()
	var of: Dictionary = q.oferta_para_npc("ilya")
	_check(str(of.get("modo", "")) == "disponible"
		and str(of.get("quest_id", "")) == "goblins_fuera"
		and str(of.get("nombre", "")) == "Goblins fuera"
		and str(of.get("descripcion", "")) != "",
		"oferta: ilya ofrece goblins_fuera (disponible)")
	var ofb: Dictionary = q.oferta_para_npc("bram")
	_check(str(ofb.get("quest_id", "")) == "colmillos_forja",
		"oferta: bram ofrece colmillos_forja")
	_check(q.oferta_para_npc("nadie").is_empty(),
		"oferta: npc sin misiones -> {}")
	_check(q.oferta_para_npc("").is_empty(),
		"oferta: npc vacío -> {}")
	# Con la misión activa ya no se ofrece (ni disponible ni lista).
	# OJO, por qué esto NO afirma que la oferta del NPC quede VACIA. Antes si, y
	# el assertion era correcto; se rompio cuando el contenido le agrego una
	# diaria al mismo NPC (data/diarias.json), y el fallo no era del juego sino
	# del test: la oferta sigue teniendo la diaria, que es lo correcto.
	# La intencion real es que `goblins_fuera` SALGA de la oferta en cada paso, y
	# eso es lo que se comprueba. Un assertion que depende de cuantos quest tiene
	# un NPC se rompe cada vez que se agrega contenido, que es lo que mas se hace.
	q.aceptar("goblins_fuera")
	_check(not _ofrece(q, "ilya", "goblins_fuera"),
		"oferta: al aceptar, goblins_fuera sale de la oferta")
	# Al completarla pasa a modo "entregar".
	for i in 5:
		q.registrar_muerte("goblin")
	_check(_ofrece(q, "ilya", "goblins_fuera"),
		"oferta: al completarla, vuelve a ofrecerse")
	var of2: Dictionary = q.oferta_para_npc("ilya")
	_check(str(of2.get("modo", "")) == "entregar"
		and str(of2.get("quest_id", "")) == "goblins_fuera",
		"oferta: lista -> modo entregar")
	# Entregada: desaparece para siempre.
	q.entregar("goblins_fuera", _player(Vector3.ZERO))
	_check(not _ofrece(q, "ilya", "goblins_fuera"),
		"oferta: entregada, goblins_fuera ya no se ofrece")


## ¿Este NPC tiene ESTA misión en su oferta? Un helper, porque el NPC puede
## tener varias a la vez (una diaria y una de acto) y el test tiene que preguntar
## por la que le importa, no por el total.
func _ofrece(q: QuestLog, npc_id: String, quest_id: String) -> bool:
	return str(q.oferta_para_npc(npc_id).get("quest_id", "")) == quest_id


## --- señal cambiada ---


func _t_cambiada() -> void:
	var q: QuestLog = _log()
	q.cambiada.connect(_al_cambiada)
	_cambiadas = 0
	q.aceptar("goblins_fuera")
	_check(_cambiadas == 1, "cambiada: aceptar emite 1 vez")
	for i in 5:
		q.registrar_muerte("goblin")
	# 5 muertes con cambio + la última también cierra en una sola emisión.
	_check(_cambiadas == 6, "cambiada: 5 muertes emiten 5 veces",
		str(_cambiadas))
	q.registrar_muerte("goblin")
	_check(_cambiadas == 6, "cambiada: sin cambio no emite",
		str(_cambiadas))


## --- Serialización ---


func _t_roundtrip() -> void:
	var q: QuestLog = _log()
	q.aceptar("goblins_fuera")
	for i in 3:
		q.registrar_muerte("goblin")
	q.aceptar("colmillos_forja")
	var d: Dictionary = q.to_dict()
	_check(int(d.get("version", 0)) == 1, "dict: version 1")
	var q2: QuestLog = QL.from_dict(d)
	_check(q2.estado("goblins_fuera") == "activa",
		"dict: goblins_fuera activa tras round-trip")
	_check(q2.progreso_texto("goblins_fuera") == "Goblins derrotados: 3/5",
		"dict: progreso 3/5 sobrevive al round-trip")
	_check(q2.estado("colmillos_forja") == "activa",
		"dict: colmillos_forja activa tras round-trip")
	_check(q2.estado("mensaje_sira") == "disponible",
		"dict: mensaje_sira sigue disponible")
	# Misión lista también sobrevive.
	for i in 2:
		q.registrar_muerte("goblin")
	var q3: QuestLog = QL.from_dict(q.to_dict())
	_check(q3.estado("goblins_fuera") == "lista",
		"dict: estado lista sobrevive al round-trip")
	# Tolerancia: dict vacío, versión distinta y misión desconocida.
	var q4: QuestLog = QL.from_dict({})
	_check(q4.estado("goblins_fuera") == "disponible",
		"dict: from_dict({}) vacío tolerante")
	var q5: QuestLog = QL.from_dict({"version": 99, "misiones": {}})
	_check(q5.estado("goblins_fuera") == "disponible",
		"dict: versión distinta arranca vacío")
	var raro: Dictionary = {"version": 1, "misiones": {
		"mision_fantasma": {"estado": "activa", "progreso": [1]},
		"goblins_fuera": {"estado": "rara", "progreso": [2]},
	}}
	var q6: QuestLog = QL.from_dict(raro)
	_check(q6.estado("goblins_fuera") == "disponible",
		"dict: estado inválido y misión desconocida se ignoran")


## --- Save v5: misiones persistidas ---


func _t_save_v5() -> void:
	var s: SaveSystem = SV.new()
	var p: Player = _player(Vector3.ZERO)
	var q: QuestLog = _log()
	s.jugador = p
	s.enemigos = []
	s.npcs = []
	s.tienda = null
	s.misiones = q
	q.aceptar("goblins_fuera")
	for i in 2:
		q.registrar_muerte("goblin")
	_check(s.guardar(), "save v9: guardar() true")
	var texto: String = FileAccess.get_file_as_string(SaveSystem.RUTA)
	var crudo: Variant = JSON.parse_string(texto)
	_check(crudo is Dictionary and int((crudo as Dictionary).get("version", 0)) == 13,
		"save v13: la partida guarda version 13 (fase 45)")
	# Cambiar el progreso DESPUÉS de guardar: cargar debe restaurarlo.
	for i in 3:
		q.registrar_muerte("goblin")
	_check(q.estado("goblins_fuera") == "lista",
		"save v7: estado lista antes de cargar")
	var s2: SaveSystem = SV.new()
	var p2: Player = _player(Vector3(10, 0, 10))
	var q2: QuestLog = _log()
	s2.jugador = p2
	s2.enemigos = []
	s2.npcs = []
	s2.tienda = null
	s2.misiones = q2
	_check(s2.cargar(), "save v7: cargar() true")
	_check(q2.estado("goblins_fuera") == "activa",
		"save v7: estado restaurado (activa)")
	_check(q2.progreso_texto("goblins_fuera") == "Goblins derrotados: 2/5",
		"save v7: progreso 2/5 restaurado")
	# El QuestLog de la demo es el MISMO objeto (se restaura en sitio).
	_check(s2.misiones == q2, "save v7: misiones restauradas en sitio")


func _t_save_tolerante_v4() -> void:
	# Partida v4 (sin bloque "misiones"): carga sin reventar, QuestLog vacío.
	var s: SaveSystem = SV.new()
	var p: Player = _player(Vector3.ZERO)
	s.jugador = p
	s.enemigos = []
	s.npcs = []
	s.tienda = null
	s.misiones = null
	_check(s.guardar(), "save v4: guardar sin misiones")
	var texto: String = FileAccess.get_file_as_string(SaveSystem.RUTA)
	var d: Variant = JSON.parse_string(texto)
	_check(d is Dictionary and (d as Dictionary).has("misiones"),
		"save v4: el bloque se guarda vacío pero existe")
	var s2: SaveSystem = SV.new()
	var p2: Player = _player(Vector3.ZERO)
	var q2: QuestLog = _log()
	s2.jugador = p2
	s2.enemigos = []
	s2.npcs = []
	s2.tienda = null
	s2.misiones = q2
	_check(s2.cargar(), "save v4: cargar sin misiones no revienta")
	_check(q2.estado("goblins_fuera") == "disponible",
		"save v4: QuestLog vacío tras cargar")
	# Y una partida v4 de verdad: sin el bloque en el JSON.
	var dd: Dictionary = d
	dd.erase("misiones")
	var f: FileAccess = FileAccess.open(SaveSystem.RUTA, FileAccess.WRITE)
	f.store_string(JSON.stringify(dd))
	f.close()
	var q3: QuestLog = _log()
	s2.misiones = q3
	_check(s2.cargar(), "save v4: sin bloque misiones no revienta")
	_check(q3.estado("goblins_fuera") == "disponible",
		"save v4: sin bloque -> QuestLog vacío")


## --- PanelMisiones ---


func _t_panel() -> void:
	var pm: PanelMisiones = PM.new()
	root.add_child(pm)
	_basura.append(pm)
	_check(not pm.esta_abierta(), "panel: arranca oculto")
	var p: Player = _player(Vector3.ZERO)
	var q: QuestLog = _log()
	pm.conectar(p, q)
	pm.alternar()
	_check(pm.esta_abierta(), "panel: alternar abre")
	pm.alternar()
	_check(not pm.esta_abierta(), "panel: alternar cierra")
	# El toast no revienta y se muestra.
	pm.toast("Misión aceptada: Goblins fuera")
	_check(true, "panel: toast no revienta")
	# Conectar de nuevo (tras cargar) no duplica señales: un aceptar
	# reconstruye sin errores.
	pm.conectar(p, q)
	pm.alternar()
	q.aceptar("goblins_fuera")
	_check(pm.esta_abierta(), "panel: sigue abierto tras cambiada")


## --- VentanaDialogo: flujo de misión ---


func _t_dialogo_mision() -> void:
	var dlg: VentanaDialogo = DLG.new()
	root.add_child(dlg)
	_basura.append(dlg)
	var n: NPC = _npc("ilya", Vector3.ZERO)
	dlg.mostrar(n)
	_check(not dlg.tiene_mision(), "dialogo: sin mostrar_mision no hay botón")
	dlg.mision_solicitada.connect(_al_mision)
	_mision_pedida = 0
	dlg.mostrar_mision("disponible", "Goblins fuera", "Limpia las afueras.")
	_check(dlg.tiene_mision(), "dialogo: disponible muestra el botón")
	# Pulsar el botón emite la señal SIN cerrar el diálogo.
	dlg._al_mision()
	_check(_mision_pedida == 1, "dialogo: mision_solicitada emitida")
	_check(dlg.esta_abierta(), "dialogo: sigue abierto tras pedir misión")
	dlg.mostrar_mision("entregar", "Goblins fuera", "")
	_check(dlg.tiene_mision(), "dialogo: entregar muestra el botón")
	dlg.mostrar_mision("", "", "")
	_check(not dlg.tiene_mision(), "dialogo: modo \"\" oculta")
	dlg.mostrar_mision("rara", "X", "Y")
	_check(not dlg.tiene_mision(), "dialogo: modo inválido oculta")
	# mostrar() resetea el botón (no arrastra estado del NPC anterior).
	dlg.mostrar_mision("disponible", "Goblins fuera", "Limpia las afueras.")
	dlg.mostrar(n)
	_check(not dlg.tiene_mision(), "dialogo: mostrar() resetea el botón")
	dlg.cerrar()
