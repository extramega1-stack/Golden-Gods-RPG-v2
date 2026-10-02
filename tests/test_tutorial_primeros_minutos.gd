extends SceneTree
## FASE 69 — "Que un jugador nuevo entienda el juego sin que se lo expliquen".
##
## Este test existe por la LECCIÓN del proyecto, no por cobertura. El fallo
## que se acaba de encontrar en otra UI fue: el panel existía, el panel
## estaba "conectado", y en la partida no se movía nunca. Un test que
## comprueba `panel != null` y `panel.is_connected(...)` pasa con esa UI
## rota. Con lo que rompe es muoviendo el DATO y mirando si la UI se movió:
##
##   - se mueve el jugador      -> el paso avanza Y el panel cambia de texto
##   - se emite intencion_atacar -> idem
##   - se entra al paso de la poción -> el jugador TIENE poción (fin del
##     bloqueo blando) y el panel lo dice
##   - el jugador se aleja 40 m  -> cambia la distancia en el panel
##   - `saltar()` / `reabrir()` -> el panel cambia de estado
##   - el objetivo cambia        -> la marca 3D se enciende y se apaga, y el
##     minimapa recibe el punto
##
## Y el otro sentido, que es el del enunciado: que los pasos APUNTEN A
## COSAS QUE EXISTAN. `_test_datos_apuntan_a_lo_real` falla si alguien mete
## un objetivo a 10 km, o un NPC que no está en `data/npcs.json`, o un
## arquetipo que no existe.
##
## Cómo correrlo: godot --headless --path . --script res://tests/test_tutorial_primeros_minutos.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
const TU: GDScript = preload("res://scripts/tutorial/tutorial.gd")
const TP: GDScript = preload("res://scripts/tutorial/tutorial_pasos.gd")
const QL: GDScript = preload("res://scripts/quests/quest_log.gd")
const MO: GDScript = preload("res://scripts/ui/minimapa.gd")
const NPCS: GDScript = preload("res://scripts/npc/npc.gd")
const ENM: GDScript = preload("res://scripts/enemy/enemy.gd")

## Punto de aparición del jugador en Moon Town (data/ciudad_luna.json,
## "aparicion_jugador"). La regla de "no mandes al jugador a 10 minutos de
## caminata" se mide contra esto.
const SPAWN: Vector3 = Vector3(0.0, 0.0, 45.0)
## Ningún objetivo del tutorial puede estar más lejos que esto.
const MAX_M: float = 150.0

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []
var _toasts: Array[String] = []


func _init() -> void:
	print("[TEST] Tutorial — los primeros 5 minutos (fase 69)")
	QuestDB.cargar()
	ItemDB.cargar()
	NpcDB.cargar()


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_datos_apuntan_a_lo_real()
	_test_la_ui_se_mueve()
	_test_la_pocion_no_ata()
	_test_cerrar_manda_sobre_la_senal()
	_test_el_esc_no_es_del_tutorial()
	_test_la_tecla_reabre()
	_test_la_distancia_mueve_la_etiqueta()
	_test_la_marca_y_el_minimapa()
	_test_los_botones()
	_test_saltar_y_reabrir()
	_test_guardar()
	print("[TEST] tutorial_primeros_minutos: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _toast(texto: String) -> void:
	_toasts.append(texto)


## Kit: jugador + QuestLog + Tutorial REAL en el árbol (con su panel y su
## marca 3D reales, porque lo que se prueba es que se muevan, no que existan).
func _kit() -> Dictionary:
	var p: Player = PL.new()
	p.fijar_identidad("T", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	var m: QuestLog = QL.new()
	_basura.append(m)
	var t: Tutorial = TU.new()
	t.name = "Tutorial"
	root.add_child(t)
	_basura.append(t)
	_toasts.clear()
	t.conectar(p, m, _toast)
	return {"p": p, "m": m, "t": t, "panel": t.panel(), "marca": t.marcador()}


## Cumple pasos con sus SEÑALES reales hasta PARAR en el paso `hasta` (sin
## cumplir ese paso: el que se va a examinar). Devuelve false si se atascó.
func _avanzar_hasta(p: Player, m: QuestLog, t: Tutorial, hasta: int) -> bool:
	var npc: NPC = NPCS.new()
	_basura.append(npc)
	var n: int = 0
	while t.paso_actual() < hasta and t.paso_actual() >= 0 and n < 12:
		n += 1
		match t.paso_actual():
			0:
				p.global_position += Vector3(4.0, 0.0, 0.0)
				t._process(0.016)
			1:
				p.intencion_atacar.emit(null)
			2:
				p.skills.skill_usada.emit("golpe_heroico")
			3:
				p.inventario.usar("pocion_vida", p)
			4:
				p.hablar_con.emit(npc)
			5:
				var qid: String = QuestDB.ids()[0]
				if m.aceptar(qid) != "ok":
					return false
			_:
				return false
	return t.paso_actual() == hasta


# --- 1) los datos apuntan a cosas que existen de verdad ----------------

## El enunciado: "que apunte a cosas que EXISTAN de verdad: si el tutorial
## manda a un mob que no está cerca del punto de aparición, el jugador camina
## 10 minutos para nada". Estas cuatro comprobaciones son esa regla escrita.
func _test_datos_apuntan_a_lo_real() -> void:
	_chk(Tutorial.PASOS.size() == 6, "datos: 6 pasos", str(Tutorial.PASOS.size()))
	var con_objetivo: int = 0
	for i in range(Tutorial.PASOS.size()):
		var paso: Dictionary = Tutorial.PASOS[i]
		var id: String = str(paso.get("id", ""))
		_chk(str(paso.get("texto", "")) != "", "datos: paso %d tiene texto" % i, id)
		_chk(str(paso.get("detalle", "")) != "",
			"datos: paso %d tiene detalle (el 'por qué', no solo el 'qué')" % i, id)
		# Los pasos de teach tienen que ser 6 y en el orden en que se
		# pueden hacer: no se puede "usar una skill" sin haber attacked.
		_chk(id in ["mover", "atacar", "skill", "pocion", "hablar", "mision"],
			"datos: paso %d con id conocido" % i, id)
		var obj: Dictionary = paso.get("objetivo", {})
		var tipo: String = str(obj.get("tipo", "ninguno"))
		if tipo == "ninguno":
			continue
		con_objetivo += 1
		match tipo:
			"npc":
				var npc_id: String = str(obj.get("npc", ""))
				_chk(NpcDB.existe(npc_id), "datos: el NPC del paso %d existe" % i, npc_id)
				var pos: Vector3 = _pos_npc(npc_id)
				_chk(pos.distance_to(SPAWN) <= MAX_M,
					"datos: el NPC del paso %d está a menos de %dm del spawn" % [i, int(MAX_M)],
					"%s está a %.0f m" % [npc_id, pos.distance_to(SPAWN)])
			"punto":
				var punto := Vector3(float(obj.get("x", 0.0)), 0.0, float(obj.get("z", 0.0)))
				_chk(punto.distance_to(SPAWN) <= MAX_M,
					"datos: el punto del paso %d está a menos de %dm del spawn" % [i, int(MAX_M)],
					"%.0f m" % punto.distance_to(SPAWN))
			"mob":
				var arq: String = str(obj.get("arquetipo", ""))
				_chk(arq != "", "datos: el paso %d de mob dice qué arquetipo" % i)
				var d: float = _dist_mob_mas_cercano(arq)
				_chk(d <= MAX_M, "datos: hay un '%s' a menos de %dm del spawn" % [arq, int(MAX_M)],
					"el más cercano está a %.0f m" % d)
			_:
				_chk(false, "datos: tipo de objetivo conocido en el paso %d" % i, tipo)
	# El tutorial tiene que POINTER algo, no solo decir texto.
	_chk(con_objetivo >= 4, "datos: al menos 4 pasos con objetivo en el mundo",
		"hay %d" % con_objetivo)


## Posición de un NPC tal como la deja la ciudad (data/ciudad_luna.json) o,
## si no está, la de data/npcs.json. Es la misma que vería el jugador.
func _pos_npc(npc_id: String) -> Vector3:
	var ciudad := _leer_json("res://data/ciudad_luna.json") as Dictionary
	var en_ciudad: Dictionary = ciudad.get("npcs", {})
	if en_ciudad.has(npc_id):
		var e: Dictionary = en_ciudad[npc_id]
		return Vector3(float(e.get("x", 0.0)), 0.0, float(e.get("z", 0.0)))
	var datos: Dictionary = NpcDB.obtener(npc_id)
	var arr: Array = datos.get("posicion", [0.0, 0.0, 0.0])
	return Vector3(float(arr[0]), 0.0, float(arr[2]))


func _leer_json(ruta: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(ruta))


## El mobs más cercano del mundo al spawn: `data/spawns.json` (los 5
## primeros son los que la demo pone en la escena; el resto los instancia
## el streaming cerca del jugador).
func _dist_mob_mas_cercano(arquetipo: String) -> float:
	var crudo: Variant = _leer_json("res://data/spawns.json")
	var lista: Array = []
	if crudo is Dictionary:
		lista = (crudo as Dictionary).get("spawns", [])
	elif crudo is Array:
		lista = crudo
	var mejor: float = INF
	for s in lista:
		if not (s is Dictionary):
			continue
		var sd: Dictionary = s
		if str(sd.get("arquetipo", "")) != arquetipo:
			continue
		var d: float = Vector2(float(sd.get("x", 0.0)), float(sd.get("z", 0.0))) \
			.distance_to(Vector2(SPAWN.x, SPAWN.z))
		mejor = minf(mejor, d)
	return mejor


# --- 2) la UI se mueve porque el dato se mueve -------------------------

## EL TEST CENTRAL. Mueve el dato y comprueba que el PANEL se mueva. Un
## `assert(panel != null)` no probaría nada.
func _test_la_ui_se_mueve() -> void:
	var kit: Dictionary = _kit()
	var p: Player = kit["p"]
	var m: QuestLog = kit["m"]
	var t: Tutorial = kit["t"]
	var panel: PanelTutorial = kit["panel"]
	_chk(panel != null, "ui: el Tutorial trae su panel")
	if panel == null:
		return
	_chk(not panel.esta_visible(), "ui: la caja arranca oculta (lección 11)")

	t.empezar()
	_chk(t.paso_actual() == 0, "ui: arranca en el paso 0")
	_chk(panel.esta_visible(), "ui: al arrancar, la caja se ve (no solo un toast de 2 s)")
	_chk(panel.texto_actual() == str(Tutorial.PASOS[0].get("texto", "")),
		"ui: el panel muestra el texto del paso 1", panel.texto_actual())
	_chk(panel.indice_actual() == "1/6", "ui: el panel muestra el contador",
		panel.indice_actual())

	# DATO 1: el jugador camina. El paso avanza Y la etiqueta cambia.
	var texto_antes: String = panel.texto_actual()
	p.global_position += Vector3(3.0, 0.0, 0.0)
	t._process(0.016)
	_chk(t.paso_actual() == 1, "ui: caminar avanza el paso")
	_chk(panel.texto_actual() == str(Tutorial.PASOS[1].get("texto", "")),
		"ui: al caminar, la ETIQUETA se movió al paso 2",
		"antes='%s' ahora='%s'" % [texto_antes, panel.texto_actual()])
	_chk(panel.texto_actual() != texto_antes, "ui: la etiqueta cambió de verdad")

	# DATO 2: atacar.
	_chk(panel.indice_actual() == "2/6", "ui: el contador va 2/6", panel.indice_actual())
	p.intencion_atacar.emit(null)
	_chk(t.paso_actual() == 2, "ui: atacar avanza el paso")
	_chk(panel.texto_actual() == str(Tutorial.PASOS[2].get("texto", "")),
		"ui: al atacar, la etiqueta se movió al paso 3", panel.texto_actual())

	# DATO 3: skill.
	p.skills.skill_usada.emit("golpe_heroico")
	_chk(t.paso_actual() == 3, "ui: la skill avanza el paso")
	_chk(panel.texto_actual() == str(Tutorial.PASOS[3].get("texto", "")),
		"ui: al lanzar la skill, la etiqueta se movió al paso 4", panel.texto_actual())

	# DATO 4: usar la poción.
	p.inventario.usar("pocion_vida", p)
	_chk(t.paso_actual() == 4, "ui: usar la poción avanza el paso")
	_chk(panel.texto_actual() == str(Tutorial.PASOS[4].get("texto", "")),
		"ui: al usar la poción, la etiqueta se movió al paso 5", panel.texto_actual())

	# DATO 5: hablar.
	var npc: NPC = NPCS.new()
	_basura.append(npc)
	p.hablar_con.emit(npc)
	_chk(t.paso_actual() == 5, "ui: hablar avanza el paso")
	_chk(panel.texto_actual() == str(Tutorial.PASOS[5].get("texto", "")),
		"ui: al hablar, la etiqueta se movió al paso 6", panel.texto_actual())

	# DATO 6: aceptar la misión → completado, con el cierre que dice a dónde
	# ir ahora (misiones, inventario, códice, manual, porteadores).
	var qid: String = QuestDB.ids()[0]
	m.aceptar(qid)
	_chk(t.hecho(), "ui: aceptar la misión termina el tutorial")
	_chk(panel.texto_actual() == TutorialPasos.texto_cierre(),
		"ui: el panel muestra el cierre", panel.texto_actual())
	_chk(panel.detalle_actual() == TutorialPasos.detalle_cierre(),
		"ui: el detalle del cierre dice a dónde ir ahora (J, I, L, ?, porteadores)",
		panel.detalle_actual())
	_chk(TutorialPasos.detalle_cierre().contains("Códice"),
		"ui: el cierre menciona el Códice (los 21 NPCs y el bestiario)", "")
	# Y ya NO queda pendiente: avanzar más no rompe nada.
	_chk(not _avanzar_hasta(p, m, t, 99), "ui: terminado, no quedan pasos")
	_chk(t.paso_actual() == -1, "ui: terminado, paso_actual() == -1")


# --- 3) el paso de la poción no puede atrapar al jugador ---------------

## EL BLOQUEO BLANDO. Antes: el paso "usá una poción" exigía TENER una, y
## la única fuente era el botín del goblin con 15% de probabilidad. Sin
## botón de saltar, un jugador podía quedarse sin poder terminar.
func _test_la_pocion_no_ata() -> void:
	var kit: Dictionary = _kit()
	var p: Player = kit["p"]
	var m: QuestLog = kit["m"]
	var t: Tutorial = kit["t"]
	var panel: PanelTutorial = kit["panel"]
	_chk(p.inventario.contar("pocion_vida") == 0, "poción: el jugador arranca sin poción")
	t.empezar()
	_chk(_avanzar_hasta(p, m, t, 3), "poción: se llega al paso de la poción",
		str(t.paso_actual()))
	_chk(t.paso_actual() == 3, "poción: estamos en el paso de la poción",
		str(t.paso_actual()))
	_chk(p.inventario.contar("pocion_vida") >= 1,
		"poción: el tutorial la.regala, así que el paso SIEMPRE se puede cumplir",
		"tiene %d" % p.inventario.contar("pocion_vida"))
	_chk(panel.detalle_actual().contains("mochila"),
		"poción: el panel le dice que se la dejaron en la mochila",
		panel.detalle_actual())
	# Y usarla avanza de verdad (no solo se la regaló).
	p.inventario.usar("pocion_vida", p)
	_chk(t.paso_actual() == 4, "poción: usarla avanza el paso")
	_chk(p.inventario.contar("pocion_vida") == 0, "poción: se consumió")
	# Un segundo tutorial no vuelve a regalar (el mismo item, otra vez no):
	var kit2: Dictionary = _kit()
	var t2: Tutorial = kit2["t"]
	var p2: Player = kit2["p"]
	t2.empezar()
	_avanzar_hasta(p2, kit2["m"], t2, 3)
	_chk(p2.inventario.contar("pocion_vida") == 1,
		"poción: solo regala una (no inunda la mochila)", "")


# --- 3b) cerrar a mano MANDA sobre la señal que reabre -------------------

## EL BUG, medido por la partida completa (`tools/jugar.sh`, P11): la caja se
## cerraba y una señal del tutorial la volvía a abrir en el mismo frame. El
## paso «cerrar con ESC» se quedaba 9001 frames sin terminar: no es que el ESC
## no llegara, es que la caja ganaba siempre.
##
## La regla que sale: **cerrar a mano manda**. Una señal puede ABRIR la caja
## (el jugador no pidió un tutorial y le sirve saber qué hacer), pero no puede
## REABRIR lo que el jugador acaba de cerrar.
##
## Y el ESC NO es de esta caja: lo Runs el menú de pausa. Ver
## `_test_el_esc_no_es_del_tutorial`.
func _test_cerrar_manda_sobre_la_senal() -> void:
	var kit: Dictionary = _kit()
	var p: Player = kit["p"]
	var t: Tutorial = kit["t"]
	var panel: PanelTutorial = kit["panel"]
	t.empezar()
	_chk(panel.esta_visible(), "cerrar: la caja se abre al arrancar el tutorial")
	panel._cerrar_por_esc()
	_chk(not panel.esta_visible(), "cerrar: se cerró")
	# El tutorial avanza (una señal que antes la re-abría).
	p.global_position += Vector3(3.0, 0.0, 0.0)
	t._process(0.016)
	_chk(t.paso_actual() == 1, "cerrar: el paso avanzó de verdad", str(t.paso_actual()))
	_chk(not panel.esta_visible(),
		"cerrar: cambiar de paso NO reabre lo que el jugador cerró")
	p.intencion_atacar.emit(null)
	_chk(not panel.esta_visible(), "cerrar: un segundo cambio tampoco")


## EL ESC NO ES DE ESTA CAJA, y antes lo era. El `PanelTutorial` se cuelga
## antes en el orden del árbol que el `MenuPausa`, así que su
## `set_input_as_handled()` se quedaba con el ESC y el menú de pausa NUNCA lo
## veía: con un ESC solo, en una partida recién creada, el primero no abría la
## pausa y el segundo sí.
##
## El menú de pausa es modal y global —tiene que funcionar SIEMPRE—. Esta caja
## tiene tres salidas propias (tecla 0, pestaña T, botón "Saltar"), así que no
## necesita el ESC para no ser una trampa. Cederlo además elimina dos dueños de
## la misma tecla, que es la causa de la clase entera de bugs.
func _test_el_esc_no_es_del_tutorial() -> void:
	var kit: Dictionary = _kit()
	var t: Tutorial = kit["t"]
	var panel: PanelTutorial = kit["panel"]
	t.empezar()
	_chk(panel.esta_visible(), "esc: la caja está abierta para la prueba")
	# Con la caja abierta y NADA apilado, el ESC no se lo queda la caja.
	panel._unhandled_input(_evento_esc())
	_chk(panel.esta_visible(),
		"esc: la caja NO se queda con el ESC (es del menú de pausa)")
	# Y con un panel apilado tampoco lo tocaba, que es lo de siempre.
	_chk(PilaUI.abierta() == 0, "esc: no hay nada apilado en esta prueba", "")


## LA TECLA QUE NO EXISTÍA. `abrir_tutorial` estaba declarada en el Input Map
## y nadie la escuchaba: la tecla 0 no abría nada. La partida completa la pedía
## como uno de los diez paneles con tecla de apertura, y con razón fallaba.
func _test_la_tecla_reabre() -> void:
	var kit: Dictionary = _kit()
	var t: Tutorial = kit["t"]
	var panel: PanelTutorial = kit["panel"]
	_chk(InputMap.has_action("abrir_tutorial"),
		"tecla: la acción «abrir_tutorial» está en el Input Map", "")
	t.empezar()
	_chk(panel.esta_visible(), "tecla: la caja se abre al arrancar el tutorial")
	# Cerrar y reabrir con la tecla, que es el ciclo del jugador.
	panel._cerrar_por_esc()
	_chk(not panel.esta_visible(), "tecla: se cerró")
	panel._unhandled_input(_evento_tecla())
	_chk(panel.esta_visible(), "tecla: la tecla la volvió a abrir")
	# Y alterna, como la pestaña.
	panel._unhandled_input(_evento_tecla())
	_chk(not panel.esta_visible(), "tecla: la tecla alterna (la segunda la cierra)")


func _evento_esc() -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	return e


func _evento_tecla() -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_0
	e.pressed = true
	return e


# --- 4) los metros mueven la etiqueta (señal, no poll) -----------------

## La UI no lee al jugador por frame: recibe `distancia_actualizada`, que
## el Tutorial emite SOLO cuando cambia el metro entero (el mismo umbral
## TOQUE_MIN de la fase 63).
func _test_la_distancia_mueve_la_etiqueta() -> void:
	var kit: Dictionary = _kit()
	var p: Player = kit["p"]
	var t: Tutorial = kit["t"]
	var panel: PanelTutorial = kit["panel"]
	var metros: Array[int] = []
	t.distancia_actualizada.connect(func(m: int) -> void: metros.append(m))
	t.empezar()
	# Paso 0: objetivo de tipo "punto" en el centro de la plaza.
	_chk(t.objetivo_tipo() == "punto", "distancia: el paso 0 tiene objetivo en el mundo",
		t.objetivo_tipo())
	_chk(panel.esta_visible(), "distancia: el panel está abierto")

	# El jugador está quieto en el origen, a 22 m del punto (0, 22). Un tick.
	t._process(0.016)
	var lejos: int = t.metros_al_objetivo()
	_chk(lejos > 5, "distancia: hay metros que contar", str(lejos))
	_chk(panel.distancia_actual() == "· %d m" % lejos,
		"distancia: la etiqueta muestra los metros", panel.distancia_actual())

	# DATO: el jugador avanza 0,6 m. No completa el paso (pide 1,5) pero
	# cruza un metro entero: 22 -> 21. Es lo que un panel "conectado pero
	# muerto" NO hace.
	var antes: String = panel.distancia_actual()
	p.global_position += Vector3(0.0, 0.0, 0.6)
	t._process(0.016)
	_chk(t.paso_actual() == 0, "distancia: 0,6 m no completa el paso de caminar",
		str(t.paso_actual()))
	_chk(panel.distancia_actual() != antes,
		"distancia: la etiqueta ACOMPAÑÓ al dato (22 m -> 21 m)",
		"'%s' -> '%s'" % [antes, panel.distancia_actual()])
	_chk(panel.distancia_actual() == "· %d m" % t.metros_al_objetivo(),
		"distancia: la etiqueta lleva el valor del dato",
		panel.distancia_actual())

	# Umbral: quieto NO emite. 20 ticks sin moverse -> ni una señal. Un poll
	# por frame emitiría 20 (y el panel se repintaría 20 veces sin motivo).
	var antes_n: int = metros.size()
	for i in range(20):
		t._process(0.016)
	_chk(metros.size() == antes_n,
		"distancia: quieto no emite señales (no es leer por frame)",
		"emitió %d" % (metros.size() - antes_n))
	_chk(metros.size() <= 4, "distancia: un recorrido corto = pocas señales",
		"%d señales" % metros.size())

	# Y con el paso cambiado a un objetivo SIN resolver (aquí no hay mobs), la
	# etiqueta se vacía: la UI no muestra un "0 m" de algo que no existe.
	p.global_position += Vector3(4.0, 0.0, 0.0)
	t._process(0.016)
	_chk(t.paso_actual() == 1, "distancia: caminar 4,6 m completa el paso",
		str(t.paso_actual()))
	_chk(panel.distancia_actual() == "",
		"distancia: sin objetivo resuelto, la etiqueta se vacía (no inventa metros)",
		"'%s'" % panel.distancia_actual())
	_chk(metros[metros.size() - 1] == -1, "distancia: avisa con -1 = sin objetivo",
		str(metros[metros.size() - 1]))

	# Un MOB REAL en el árbol: el paso "atacar" lo resuelve, la marca lo
	# sigue y la distancia cuenta hasta él.
	var goblin: Enemy = _nuevo_goblin(Vector3(0.0, 0.0, 60.0))
	p.global_position = Vector3(0.0, 0.0, 0.0)
	# El reintento de objetivo tiene reloj propio (2 por segundo), así que
	# el goblin no aparece en el mismo frame: se le da medio segundo de
	# juego, que es lo que tardaría el streaming en instanciarlo.
	for i in range(12):
		t._process(0.05)
	_chk(t.objetivo_tipo() == "mob", "distancia: el paso 2 apunta a un mob",
		t.objetivo_tipo())
	_chk(t.marcador().posicion_marca().distance_to(goblin.global_position) < 0.01,
		"distancia: la marca se plantó EN el goblin",
		str(t.marcador().posicion_marca()))
	_chk(panel.distancia_actual() == "· 60 m",
		"distancia: la etiqueta cuenta hasta el mob real", panel.distancia_actual())
	# El mob camina: la marca y la etiqueta lo siguen.
	goblin.position = Vector3(0.0, 0.0, 30.0)
	t._process(0.05)
	t.marcador()._process(0.1)
	_chk(panel.distancia_actual() == "· 30 m",
		"distancia: si el mob se mueve, la etiqueta se mueve con él",
		panel.distancia_actual())
	_chk(t.marcador().posicion_marca().distance_to(Vector3(0.0, 0.0, 30.0)) < 0.01,
		"distancia: la marca sigue al mob que se movió",
		str(t.marcador().posicion_marca()))


## Un goblin real configurado con su arquetipo de `data/enemies.json`, que
## es lo que el Tutorial tiene que encontrar en el árbol.
func _nuevo_goblin(pos: Vector3) -> Enemy:
	var e: Enemy = ENM.new()
	var arq: Dictionary = _leer_json("res://data/enemies.json")
	var lista: Dictionary = (arq as Dictionary).get("arquetipos", {})
	if lista.has("goblin"):
		e.configurar(lista["goblin"])
	else:
		e.configurar({"stats": StatBlock.new(10.0, 8.0, 6.0, 4.0), "loot": {"items": []}})
	e.arquetipo_id = "goblin"
	e.position = pos
	root.add_child(e)
	_basura.append(e)
	return e


# --- 5) la marca en el mundo y el punto en el minimapa ------------------

func _test_la_marca_y_el_minimapa() -> void:
	var kit: Dictionary = _kit()
	var p: Player = kit["p"]
	var t: Tutorial = kit["t"]
	var marca: MarcadorObjetivo = kit["marca"]
	_chk(marca != null, "marca: el Tutorial trae su marca 3D")
	_chk(marca != null and not marca.esta_encendido(),
		"marca: nace apagada (§9.5)")

	# Minimapa real, montado a mano: el Tutorial lo busca en el árbol.
	var mm: Minimapa = MO.new()
	root.add_child(mm)
	_basura.append(mm)

	t.empezar()
	_chk(t.objetivo_tipo() == "punto", "marca: el paso 0 tiene punto")
	_chk(marca.esta_encendido(), "marca: se enciende con objetivo")
	_chk(marca.etiqueta() == str(Tutorial.PASOS[0].get("texto", "")),
		"marca: la etiqueta flotante dice el objetivo", marca.etiqueta())
	_chk(mm.tiene_objetivo_tutorial(), "minimapa: recibió el objetivo")
	var esperado: Vector3 = marca.posicion_marca()
	_chk(Vector2(mm.objetivo_tutorial().x, mm.objetivo_tutorial().z)
		.distance_to(Vector2(esperado.x, esperado.z)) < 0.01,
		"minimapa: el punto es el del objetivo", str(mm.objetivo_tutorial()))

	# La marca sigue a un nodo vivo: si el objetivo es un NPC y el NPC se
	# mueve, la marca va detrás (no se queda clavada en el punto viejo).
	var nodo := Node3D.new()
	nodo.position = Vector3(5.0, 0.0, 5.0)
	root.add_child(nodo)
	_basura.append(nodo)
	marca.encender(nodo, nodo.position, "prueba")
	nodo.position = Vector3(40.0, 0.0, -20.0)
	marca._process(0.1)
	_chk(marca.posicion_marca().distance_to(Vector3(40.0, 0.0, -20.0)) < 0.01,
		"marca: sigue al nodo vivo", str(marca.posicion_marca()))

	# Un paso SIN objetivo (una tecla no se marca en el mapa) apaga la marca.
	marca.apagar()
	_chk(not marca.esta_encendido(), "marca: apagar() la esconde")
	_chk(marca.etiqueta() == "", "marca: apagada no muestra etiqueta")
	# Y el minimapa se limpia con NAN (su "no hay objetivo").
	mm.fijar_objetivo_tutorial(Vector3(NAN, NAN, NAN))
	_chk(not mm.tiene_objetivo_tutorial(), "minimapa: NAN = sin objetivo")


# --- 6) los botones están conectados (no solo la API) -------------------

## Un botón que existe pero no está conectado es el mismo bug que un panel
## que existe pero no se mueve: se pulsa y no pasa nada. Se comprueba por
## EFECTO, no por `is_connected`.
func _test_los_botones() -> void:
	var kit: Dictionary = _kit()
	var p: Player = kit["p"]
	var t: Tutorial = kit["t"]
	var panel: PanelTutorial = kit["panel"]
	t.empezar()
	_chk(panel.esta_visible(), "botones: la caja está abierta al empezar")

	# IR: el objetivo del paso 0 es el punto (0, 22); el jugador (0, 0). Al
	# pulsar, el jugador tiene que EMPEZAR A CAMINAR SOLO hacia allá.
	#
	# Se mira la VELOCIDAD y no `global_position` porque en headless el
	# servidor de físicas no avanza: `move_and_slide()` no integra nada y la
	# posición se queda clavada aunque el héroe esté yendo. Lo que se
	# comprueba es lo que el botón produce de verdad: una orden de destino
	# real y una velocidad horizontal apuntando al objetivo.
	var objetivo: Vector3 = t._pos_objetivo()
	panel._al_pulsar_ir()
	for i in range(20):
		p._physics_process(0.05)
	# `intent.tiene_destino` lo arma `_construir_intent()` dentro del tick
	# de física, así que se mira DESPUÉS de mover, no justo tras el clic.
	_chk(p.intent.tiene_destino, "botones: IR le da un destino al jugador (no solo marca)")
	var hacia := Vector2(objetivo.x - p.global_position.x, objetivo.z - p.global_position.z)
	hacia = hacia.normalized()
	var plano := Vector2(p.velocity.x, p.velocity.z)
	_chk(plano.length() > 1.0, "botones: IR pone al jugador en marcha",
		"|v|=%.2f" % plano.length())
	_chk(plano.normalized().dot(hacia) > 0.9,
		"botones: IR va HACIA el objetivo, no en cualquier dirección",
		"dot=%.2f" % plano.normalized().dot(hacia))
	_chk(p.intent.destino.distance_to(objetivo) < 4.0,
		"botones: el destino es el objetivo (con un margen para no chocar)",
		"%s vs %s" % [str(p.intent.destino), str(objetivo)])

	# La PESTAÑA: cierra y reabre. Reabrir no debe cambiar el paso.
	var paso_antes: int = t.paso_actual()
	panel._al_pulsar_pestana()
	_chk(not panel.esta_visible(), "botones: la pestaña cierra la caja")
	panel._al_pulsar_pestana()
	_chk(panel.esta_visible(), "botones: la pestaña reabre la caja (se puede volver a abrir)")
	_chk(t.paso_actual() == paso_antes,
		"botones: reabrir NO reinicia el tutorial de golpe",
		"%d -> %d" % [paso_antes, t.paso_actual()])

	# SALTAR: el botón, no la API.
	var kit2: Dictionary = _kit()
	var t2: Tutorial = kit2["t"]
	var panel2: PanelTutorial = kit2["panel"]
	t2.empezar()
	panel2._al_pulsar_saltar()
	_chk(t2.hecho() and t2.fue_saltado(), "botones: SALTAR termina el tutorial",
		"hecho=%s saltado=%s" % [str(t2.hecho()), str(t2.fue_saltado())])
	_chk(panel2.indice_actual() == "Saltado", "botones: SALTAR lo dice en el panel",
		panel2.indice_actual())


# --- 7) saltar y volver a abrir -----------------------------------------

## Un jugador que ya sabe no quiere que le repitan. Y el que se saltó
## quiere poder consultarlo.
func _test_saltar_y_reabrir() -> void:
	var kit: Dictionary = _kit()
	var p: Player = kit["p"]
	var m: QuestLog = kit["m"]
	var t: Tutorial = kit["t"]
	var panel: PanelTutorial = kit["panel"]
	t.empezar()
	_chk(panel.pestana_visible(), "saltar: la pestaña T siempre está (es el acceso)")

	t.saltar()
	_chk(t.hecho(), "saltar: el tutorial queda terminado")
	_chk(t.fue_saltado(), "saltar: se distingue de completarlo")
	_chk(t.paso_actual() == -1, "saltar: no queda paso pendiente")
	_chk(panel.indice_actual() == "Saltado", "saltar: el panel lo dice",
		panel.indice_actual())
	_chk(t.marcador() == null or not t.marcador().esta_encendido(),
		"saltar: la marca del mundo se apaga")
	# Un tutorial terminado NO vuelve a arrancar solo:
	t.empezar()
	_chk(t.hecho(), "saltar: empezar() no resucita un tutorial saltado")
	_chk(panel.indice_actual() == "Saltado", "saltar: el panel sigue en saltado")

	# Y se puede volver a abrir (la pestaña T / `reabrir()`).
	t.reabrir()
	_chk(not t.hecho() and not t.fue_saltado(), "reabrir: vuelve a estar activo")
	_chk(t.paso_actual() == 0, "reabrir: arranca en el paso 0", str(t.paso_actual()))
	_chk(panel.texto_actual() == str(Tutorial.PASOS[0].get("texto", "")),
		"reabrir: el panel vuelve al objetivo 1", panel.texto_actual())


# --- 8) el guardado -----------------------------------------------------

func _test_guardar() -> void:
	var kit: Dictionary = _kit()
	var t: Tutorial = kit["t"]
	var p: Player = kit["p"]
	t.empezar()
	_avanzar_hasta(p, kit["m"], t, 3)
	var d: Dictionary = t.to_dict()
	_chk(int(d.get("version", 0)) == Tutorial.SAVE_VERSION_TUTORIAL,
		"save: versión del bloque", str(d))
	_chk(d.has("saltado") and d.has("regalos"),
		"save: la fase 69 suma saltado y regalos (y son aditivos: la versión no se bumpea)")

	# Round-trip a medias: el paso y los regalos sobreviven.
	var t2: Tutorial = TU.new()
	_basura.append(t2)
	t2.cargar_estado(d)
	_chk(t2.paso_actual() == t.paso_actual(), "save: el paso sobrevive",
		"%d vs %d" % [t2.paso_actual(), t.paso_actual()])
	_chk(not t2.hecho(), "save: no hecho")

	# Veterano: el SaveSystem pasa {"hecho": true} cuando el save es previo
	# a la 69. No hay bloque de regalos y no reventa.
	var t3: Tutorial = TU.new()
	_basura.append(t3)
	t3.cargar_estado({"hecho": true})
	_chk(t3.hecho() and t3.paso_actual() == -1, "save: el veterano no recibe prompts")
	_chk(not t3.fue_saltado(), "save: un veterano no está 'saltado'")
	t3.empezar()
	_chk(t3.hecho(), "save: un veterano no ve el tutorial aunque se llame a empezar()")

	# Guardar un tutorial saltado y cargarlo: sigue saltado (no reaparece).
	var t4: Tutorial = TU.new()
	_basura.append(t4)
	t4.cargar_estado({"version": 1, "hecho": true, "paso": 0, "saltado": true})
	_chk(t4.fue_saltado(), "save: saltado sobrevive al guardado")
