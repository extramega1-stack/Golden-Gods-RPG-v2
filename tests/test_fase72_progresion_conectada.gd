extends SceneTree
## FASE 72 — la progresión que estaba escrita y era inalcanzable.
##
## POR QUÉ ESTE TEST EXISTE Y POR QUÉ NO ES UN TEST MÁS POR SISTEMA:
## los cuatro fallos que cierra la fase 72 son UN SOLO fallo con cuatro
## síntomas: un sistema escrito, testeado y no conectado a la partida. Y la
## lección ya está pagada dos veces en este repo (`MASTER_SPEC.md:2487` y el
## `smoke_fase_escena_completa`): un test que monta el sistema en su propia
## escena pasa con el sistema desconectado del todo.
##
## Por eso este test tiene DOS mitades y ambas hacen falta:
##
## 1. MOVIMIENTOS REALES. Se mueve el dato y se mira qué cambió: se tala un
##    árbol y se mira la habilidad, se junta un botín y se mira la habilidad,
##    se agota una veta con el Hecho puesto y se mira si le quedaron usos, se
##    digna el NG+ y se mira si el loot trae más afijos, se prestigia y se mira
##    si el TEXTO del panel se repinta. Un test que solo conecta una señal y
##    comprueba que se conectó no prueba nada (§9.5).
##
## 2. CHEQUEOS DE CALL SITE. Se relee el código de la partida y se pregunta si
##    la conexión existe de verdad. Esta es la mitad que habría atrapado los
##    cuatro fallos, y es la que falla si mañana alguien desconecta algo.
##    Se grepa `scripts/` y `scenes/`, no el `.tscn`: el wiring de la fase 63/64
##    está en el `.gd` de la escena y no en el archivo de Godot.
##
## Los cinco fallos, según el encargo:
##   (a) Tala y minería: cada una sube SU habilidad, no la de la otra.
##   (b) Recolección: el cuarto eje, que solo subía desde un test.
##   (c) Los 4 Hechos sin consumidor ahora los leen sistemas.
##   (d) `PanelNgPlus` está en la partida, con tecla y en `gg_system`.
##   (e) El afijo del botín escala con el nivel del arquetipo y con el NG+.

const PL: GDScript = preload("res://scripts/player/player.gd")
const FG: GDScript = preload("res://scripts/mundo/fogata.gd")
const PICKUP: GDScript = preload("res://scripts/loot/pickup.gd")

## La fila del panel que dice cuántos afijos extra da el prestigio. Es la
## MISMA que lee el loot (`EstadoNgPlus.afijos_extra_en_juego`), no una
## decoración: si el panel dice +2 y el loot no, el test lo atrapa.
const FILA_AFIJOS: String = "Afijos extra por item"
## La escena de la partida. Es la que se relee para probar que el panel está
## ENCARNADO y no solamente escrito.
const RUTA_PARTIDA: String = "res://scenes/demo/fase14_demo.gd"
const RUTA_INPUTMAP: String = "res://project.godot"

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 72 — la progresión conectada")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_tala_da_xp_de_habilidad()
	_test_recoleccion_da_xp_de_habilidad()
	_test_hechos_tienen_consumidor()
	_test_veta_persistente()
	_test_doble_yacimiento()
	_test_cocina_lote()
	_test_fogata_perenne()
	_test_panel_ngplus_en_la_partida()
	_test_panel_reacciona_al_dato()
	_test_afijos_escalan()
	_test_llamadas_reales()
	for n in _basura:
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	print("[TEST] fase72_progresion_conectada: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


# ---------------------------------------------------------------------
# (a) Las cuatro habilidades suben jugando
# ---------------------------------------------------------------------

## Tala, minería, cocina y recolección. Antes de la 72 la cuarta solo subía
## desde un test, y con ella sus dos Hechos quedaban bloqueados para siempre.
func _test_tala_da_xp_de_habilidad() -> void:
	var p: Player = _jugador()
	var arbol: Arbol = _arbol({"xp": 6, "usos": 2, "nivel": 1, "tinte": "#4a7a3a"})
	var logica: Mineria = Mineria.new()
	var motivo: String = logica.minar(arbol, p)
	_chk(motivo == "ok", "talar un árbol pasa por la vía normal", motivo)
	_chk(p.habilidades.xp_de("tala") == 6, "y sube la habilidad TALA",
		str(p.habilidades.xp_de("tala")))
	_chk(p.habilidades.xp_de("mineria") == 0,
		"y NO la de minería (la declara el nodo, no la lógica)", "")
	# El talar pasa por `Mineria.minar`, no por una vía paralela: si alguien
	# cablea la tala por otro lado y se olvida de esta llamada, el Hecho deja
	# de funcionar sin que ningún test lo note.
	_chk(_tiene(_leer(MINERIA_GD), "habilidades.ganar(veta.habilidad_id"),
		"Mineria da el XP con la habilidad que DECLARA el nodo", "")


func _test_recoleccion_da_xp_de_habilidad() -> void:
	_chk(FileAccess.file_exists(Recoleccion.RUTA),
		"existe el dato de la recolección", Recoleccion.RUTA)
	_chk(Recoleccion.habilidad() == "recoleccion",
		"y dice a qué habilidad da el XP (sale del JSON)", Recoleccion.habilidad())

	# (1) El dato manda: lo que el JSON dice es lo que se da.
	var por_item: int = Recoleccion.xp_de({"tipo": "item", "item_id": "x", "cantidad": 1})
	var por_oro: int = Recoleccion.xp_de({"tipo": "oro", "cantidad": 600})
	_chk(por_item > 0, "un item da XP de recolección", str(por_item))
	_chk(por_oro > 0, "y el oro también", str(por_oro))
	_chk(Recoleccion.xp_de({}) == 0, "un drop vacío no da nada", "")
	_chk(por_item == Recoleccion.xp_de(
			{"tipo": "item", "item_id": "y", "cantidad": 9}),
		"el XP es por PICKUP y no por unidad", "")

	# (2) El CAMINO REAL: un `Pickup` de verdad, con el jugador de verdad encima.
	# No se llama a `Recoleccion.otorgar` a mano: eso probaría la función, no
	# que esté enganchada. Acá lo que se prueba es que juntar algo sube la
	# habilidad, que es lo que el jugador hace.
	var p: Player = _jugador()
	# `Pickup` busca al jugador por el grupo "jugador" y ese grupo lo pone
	# `fase14_demo.tscn` (`groups=["jugador"]`), no el `_ready` del Player. Un
	# Player creado a mano hay que colgarlo en el grupo a mano, igual que hace
	# la escena.
	p.add_to_group("jugador")
	var antes: int = p.habilidades.xp_de("recoleccion")
	var pk: Pickup = PICKUP.new()
	pk.drop = {"tipo": "item", "item_id": "colmillo", "cantidad": 1}
	pk.name = "Pickup72"
	root.add_child(pk)
	_basura.append(pk)
	var recogida: Array = []
	pk.recogido.connect(func(_d: Dictionary) -> void: recogida.append(1))
	pk.global_position = p.global_position
	pk._revisar_recogida()
	_chk(recogida.size() == 1, "juntar el botín emite `recogido`", str(recogida.size()))
	_chk(p.habilidades.xp_de("recoleccion") > antes,
		"y sube la habilidad RECOLECCIÓN",
		"%d -> %d" % [antes, p.habilidades.xp_de("recoleccion")])
	_chk(p.habilidades.xp_de("tala") == 0 and p.habilidades.xp_de("mineria") == 0,
		"juntar NO toca las otras tres habilidades", "")


# ---------------------------------------------------------------------
# (c) Los 4 Hechos huérfanos
# ---------------------------------------------------------------------

## El chequeo GENÉRICO, y el que habría atrapado los cuatro fallos de una.
## Recorre `data/hechos.json` y, por cada bandera, pregunta si ALGÚN archivo de
## `scripts/` la menciona. Una bandera que nadie lee es una recompensa que el
## jugador no puede ganar, y esta es la forma de que eso no vuelva a pasar sin
## que haga falta una fase para descubrirlo.
func _test_hechos_tienen_consumidor() -> void:
	var h: Hechos = Hechos.crear_desde_datos()
	_chk(h.total() >= 10, "hay al menos 10 Hechos", str(h.total()))
	# SIN el archivo donde se declaran. Si se buscara también ahí, cada
	# bandera se encontraría a sí misma en su propia `const` y el chequeo
	# pasar��a siempre: un test que no puede fallar no es un test.
	var todo: String = _codigo_de("scripts", ["res://scripts/skills/hechos.gd"])
	for id in h.ids():
		var flag: String = h.flag_de(id)
		if flag == "":
			# Los de tipo `mod` no necesitan consumidor: los mete
			# `Hechos.aplicar()` en el StatBlock, que es su consumidor.
			continue
		# Se acepta cualquiera de las dos formas: la bandera literal (un
		# `tiene("cocina_lote")`) o su constante (`Hechos.FLAG_COCINA_LOTE`,
		# que es lo que se usa para no repetir la cadena en cuatro archivos).
		var aguja: String = "FLAG_" + flag.to_upper()
		_chk(_tiene(todo, flag) or _tiene(todo, "Hechos." + aguja),
			"la bandera '%s' (Hecho '%s') la lee un sistema" % [flag, id],
			"nadie menciona '%s' fuera de scripts/skills/hechos.gd" % flag)


## "Veta persistente" (minería, tramo 2): la veta nunca se agota DEL TODO.
func _test_veta_persistente() -> void:
	var p: Player = _jugador()
	p.habilidades.ganar("mineria", 100_000)
	p.hechos.aplicar(p.stats)
	_chk(p.hechos.tiene(Hechos.FLAG_VETA_PERSISTENTE),
		"con Minería en tramo 2+, el Hecho 'veta_persistente' está", "")

	# Una veta de UN uso: sin el Hecho se seca, con el Hecho no.
	var seca: Veta = _veta({"xp": 5, "usos": 1, "nivel": 1})
	Mineria.new().minar(seca, p)
	_chk(seca.usos > 0,
		"el Hecho deja la veta con usos: no se agota del todo",
		"usos=%d" % seca.usos)
	_chk(not seca.respawn_restante > 0.0 or seca.usos > 0,
		"y no queda con la cuenta atrás corriendo", "")

	var p2: Player = _jugador()
	var seca2: Veta = _veta({"xp": 5, "usos": 1, "nivel": 1})
	Mineria.new().minar(seca2, p2)
	_chk(seca2.usos == 0,
		"SIN el Hecho la veta sí se agota (el default no cambió nada)",
		"usos=%d" % seca2.usos)


## "Doble yacimiento" (minería, tramo 3): la cuenta atrás del respawn corre al
## doble de velocidad.
func _test_doble_yacimiento() -> void:
	var p: Player = _jugador()
	var g: GestorVetas = GestorVetas.new()
	g.name = "GestorVetas72"
	root.add_child(g)
	_basura.append(g)
	g.fijar_jugador(p)
	_chk(is_equal_approx(g.factor_respawn_actual(), 1.0),
		"sin el Hecho el respawn va a velocidad normal",
		str(g.factor_respawn_actual()))
	p.habilidades.ganar("mineria", 100_000)
	p.hechos.aplicar(p.stats)
	var f: float = g.factor_respawn_actual()
	_chk(f > 1.0, "con 'doble_yacimiento' el respawn se acelera", str(f))

	# Y que el número esté en el dato, no quemado en el código: el factor que
	# usa el gestor es EXACTAMENTE el que declara `data/hechos.json`.
	var declarado: float = p.hechos.parametro(Hechos.ID_DOBLE_YACIMIENTO,
		"factor_respawn", -1.0)
	_chk(declarado > 0.0, "el factor está declarado en data/hechos.json",
		str(declarado))
	_chk(is_equal_approx(f, clampf(declarado, 0.05, 8.0)),
		"y el gestor usa ese número, no uno escrito en el código",
		"gestor=%f json=%f" % [f, declarado])

	# El efecto de verdad sobre el reloj: media cuenta atrás y la veta volvió.
	var v: Veta = _veta({"xp": 5, "usos": 1, "nivel": 1, "respawn_s": 100.0})
	v.factor_respawn = f
	v.consumir_uso()
	_chk(v.usos == 0, "la veta se agotó", str(v.usos))
	# 100 s de dato con factor 2.0 son 50 s de reloj. Con el factor normal
	# (1.0) 60 s NO alcanzan, y eso es lo que mide el contraste de abajo: los
	# dos casos con el MISMO reloj y la misma veta.
	v.tick(60.0)
	_chk(v.usos > 0,
		"con el factor del Hecho, 60 s de reloj repone una veta de 100 s",
		"usos=%d restante=%.1f" % [v.usos, v.respawn_restante])
	var v2: Veta = _veta({"xp": 5, "usos": 1, "nivel": 1, "respawn_s": 100.0})
	v2.consumir_uso()
	v2.tick(60.0)
	_chk(v2.usos == 0,
		"sin el factor, 60 s NO alcanzan (el Hecho es lo que aceleró)",
		"restante=%.1f" % v2.respawn_restante)


## "Cocina de lote" (cocina, tramo 2): 2 raciones por vez.
func _test_cocina_lote() -> void:
	var receta: Dictionary = {
		"resultado": "carne_asada", "cantidad": 1, "xp": 4, "lena": 1.0,
		"segundos": 2.0,
	}
	var p: Player = _jugador()
	_chk(int(Cocina.cocinar("carne_cruda_lobo", receta, {"carne_cruda_lobo": 1})
		.get("cantidad", 0)) == 1, "sin Hechos sale 1 ración", "")
	p.habilidades.ganar("cocina", 100_000)
	p.hechos.aplicar(p.stats)
	_chk(p.hechos.tiene(Hechos.FLAG_COCINA_LOTE),
		"con Cocina en tramo 2+, el Hecho 'cocina_lote' está", "")
	var con_hecho: Dictionary = Cocina.cocinar("carne_cruda_lobo", receta,
		{"carne_cruda_lobo": 1}, p.hechos)
	_chk(int(con_hecho.get("cantidad", 0)) == 2,
		"y salen 2 raciones", str(con_hecho))
	_chk(Cocina.multiplicador(p.hechos) == 2,
		"el multiplicador es el del dato (2)", str(Cocina.multiplicador(p.hechos)))
	_chk(Cocina.multiplicador(null) == 1, "sin Hechos el multiplicador es 1", "")
	# Y que el dato manda: el multiplicador se lee de `parametros`.
	_chk(Cocina.multiplicador(p.hechos) == p.hechos.parametro_int(
			Hechos.ID_COCINA_LOTE, "multiplicador_cantidad", -1),
		"la cantidad sale de data/hechos.json", "")


## "Fogata perenne" (cocina, tramo 4): la fogata se vuelve a encender sola.
func _test_fogata_perenne() -> void:
	var p: Player = _jugador()
	var f: Fogata = _fogata()
	# La E es el momento en que fogata y jugador se conocen, y ahí se cachean
	# los Hechos. Devuelve "sin_lena" y da igual: lo que importa es que la
	# fogata ya sepa de quién es. Con esto ya tiene el Hecho abierto.
	p.habilidades.ganar("cocina", 100_000)
	p.hechos.aplicar(p.stats)
	_chk(p.hechos.tiene(Hechos.FLAG_FOGATA_PERENNE),
		"con Cocina en tramo 4+, el Hecho 'fogata_perenne' está", "")
	_chk(f.interactuar_jugador(p) == "sin_lena",
		"sin troncos la E avisa que no hay leña (y la fogata ya sabe de quién es)",
		"")
	f.cargar_lena(1.0)
	f.gastar_lena(1.0)
	_chk(not f.encendida(), "la fogata se apagó: se le acabó la leña", "")
	f._process(Fogata.INTERVALO_SEG + 0.1)
	_chk(f.encendida(),
		"con 'fogata_perenne' se vuelve a encender sola (sin tronco)",
		"lena=%.1f" % f.lena)
	_chk(is_equal_approx(f.lena, p.hechos.parametro(
			Hechos.ID_FOGATA_PERENNE, "lena_minima", -1.0)),
		"y la leña del reencendido es la del dato",
		"%.1f" % f.lena)

	# Y sin el Hecho no: es el comportamiento de siempre.
	var p2: Player = _jugador()
	var f2: Fogata = _fogata()
	f2.interactuar_jugador(p2)
	f2.cargar_lena(1.0)
	f2.gastar_lena(1.0)
	f2._process(Fogata.INTERVALO_SEG + 0.1)
	_chk(not f2.encendida(), "sin el Hecho la fogata se queda apagada", "")

	# Y el Hecho se abre de verdad: Cocina en tramo 4.
	p.habilidades.ganar("cocina", 100_000)
	p.hechos.aplicar(p.stats)
	_chk(p.hechos.tiene(Hechos.FLAG_FOGATA_PERENNE),
		"con Cocina en tramo 4+, el Hecho 'fogata_perenne' está", "")



# ---------------------------------------------------------------------
# (d) El PanelNgPlus, en la partida
# ---------------------------------------------------------------------

## El fallo más caro de los cinco: el panel existía con sus tests en verde y
## no había forma de abrirlo. Estas son las tres mitades de "está en la
## partida": el wiring en la escena, el `system_id`, y la tecla en el Input Map.
func _test_panel_ngplus_en_la_partida() -> void:
	var partida: String = _leer(RUTA_PARTIDA)
	_chk(not partida.is_empty(), "se puede leer el código de la partida", RUTA_PARTIDA)
	_chk(_tiene(partida, "PanelNgPlus.new()"),
		"la partida instancia un PanelNgPlus", "")
	_chk(_tiene(partida, "registrar(_ngplus"),
		"y lo registra en el contenedor de sistemas (§9.1)", "")
	_chk(_tiene(partida, "add_child(_ngplus"),
		"y lo cuelga del árbol (un panel registrado y no colgado no se ve)", "")

	# El grupo y el id, que es lo que la UI usa para descubrirlo.
	_chk(UiLayers.PANEL_NGPLUS >= 20 and UiLayers.PANEL_NGPLUS <= 69,
		"su capa está en el rango de paneles (20-69)", str(UiLayers.PANEL_NGPLUS))

	# La tecla: acción en el Input Map, en español (§9.3), con un evento real.
	_chk(InputMap.has_action(PanelNgPlus.ACCION),
		"la acción '%s' existe en el Input Map" % PanelNgPlus.ACCION, "")
	_chk(not InputMap.action_get_events(PanelNgPlus.ACCION).is_empty(),
		"y tiene al menos una tecla", "")
	_chk(_tiene(_leer(RUTA_INPUTMAP), PanelNgPlus.ACCION + "={"),
		"y está declarada en project.godot", "")

	# La conexión que hacía imposible abrirlo: `alternar()` resolvía el estado
	# por su cuenta. Un panel que solo se abre si alguien le pasa un estado no
	# se abre nunca la primera vez.
	var panel: PanelNgPlus = _panel()
	_chk(panel.system_id == &"panel_ngplus", "el system_id es el suyo",
		str(panel.system_id))
	_chk(panel.layer == UiLayers.PANEL_NGPLUS,
		"y cuelga en la capa que dice UiLayers", str(panel.layer))
	_chk(not panel.visible, "el panel nace cerrado (lección 11)", "")
	_chk(panel.alternar(), "la PRIMERA pulsación lo abre", "")
	_chk(panel.visible, "y queda visible", "")
	_chk(not panel.alternar(), "la segunda lo cierra", "")
	_chk(not panel.visible, "y deja de verse", "")


## La UI se suscribe a una señal, así que conectar no prueba nada: hay que
## mover el DATO y ver el TEXTO cambiar (§9.5).
func _test_panel_reacciona_al_dato() -> void:
	var panel: PanelNgPlus = _panel()
	var e: EstadoNgPlus = EstadoNgPlus.new()
	_chk(panel.abrir(e), "abre con un estado", "")
	var antes: String = "\n".join(panel.textos())
	_chk(antes.find("Ciclo 0") >= 0, "muestra el ciclo 0", antes.substr(0, 120))
	_chk(antes.find("Prestigio") >= 0 or antes.find("prestigio") >= 0,
		"y el prestigio", "")

	# Se prestigious. El panel tiene que repintarse SOLO, sin que nadie le
	# avise: está suscrito a `EstadoNgPlus.cambiado`.
	e.prestigiar(NuevoJuegoPlus.tope_nivel())
	var despues: String = "\n".join(panel.textos())
	_chk(despues != antes, "el texto se repinta cuando el dato se movió", "")
	_chk(despues.find("Ciclo 1") >= 0,
		"y ahora dice Ciclo 1", despues.substr(0, 160))
	# Con UN ciclo el prestigio es 1 y el margen de afijos sigue en 0
	# (son 3 de prestigio por afijo). Se cierran tres ciclos y la fila TIENE
	# que cambiar: es la misma fila que el loot lee, no una decoracion.
	_chk(_valor_de_fila(despues, FILA_AFIJOS) == "+0",
		"con 1 de prestigio el margen de afijos sigue en 0 (son 3 por afijo)",
		_valor_de_fila(despues, FILA_AFIJOS))
	for _vuelta in range(2):
		e.prestigiar(NuevoJuegoPlus.tope_nivel())
	_chk(_valor_de_fila("\n".join(panel.textos()), FILA_AFIJOS) == "+2",
		"y con 6 de prestigio el panel muestra +2 afijos (3 ciclos)",
		_valor_de_fila("\n".join(panel.textos()), FILA_AFIJOS))

	# Los dos contenidos que se perdían con el panel invisible: los trofeos y
	# los encargos del día. No se comprueba que haya ganado trofeos (eso es
	# otro test), sino que el panel los LEE.
	_chk(despues.find("Trofeos") >= 0, "el panel tiene su sección de Trofeos", "")
	_chk(despues.find("Encargos") >= 0, "y la de Encargos de hoy", "")
	_chk(Trofeos.total() > 0, "y el catálogo de trofeos no está vacío",
		str(Trofeos.total()))
	_chk(not RotacionDiaria.misiones_vigentes(0).is_empty(),
		"y la rotación de hoy trae misiones", "")
	panel.cerrar_panel()


# ---------------------------------------------------------------------
# (e) El afijo del botín escala
# ---------------------------------------------------------------------

## El quinto fallo: `DropTable` leía `nivel` y `afijos_extra` de la tabla y los
## arquetipos no los declaraban, así que el escalado iba a CERO y todos los
## bots del mundo soltaban el mismo afijo para siempre.
func _test_afijos_escalan() -> void:
	# (1) El DATO: todos los arquetipos declaran los dos números.
	var arq: Dictionary = _arquetipos()
	_chk(arq.size() >= 20, "hay arquetipos de enemigos", str(arq.size()))
	var sin_nivel: Array[String] = []
	var sin_extra: Array[String] = []
	for id in arq.keys():
		var a: Dictionary = arq[id]
		if not a.has("nivel") or int(a.get("nivel", 0)) <= 0:
			sin_nivel.append(str(id))
		if not a.has("afijos_extra"):
			sin_extra.append(str(id))
	_chk(sin_nivel.is_empty(),
		"todos declaran 'nivel' (sin eso el afijo escala a 0)", str(sin_nivel))
	_chk(sin_extra.is_empty(),
		"todos declaran 'afijos_extra'", str(sin_extra))

	# (2) El CAMINO: la tabla de loot del mob lleva los dos números. Un `Enemy`
	# de verdad, configurado con el arquetipo REAL del JSON.
	var primero: String = str(arq.keys()[0])
	var e: Enemy = _enemigo(arq[primero])
	_chk(int(e._tabla_loot.get("nivel", 0)) > 0,
		"la tabla de loot del mob lleva el nivel del arquetipo",
		str(e._tabla_loot))
	_chk(e._tabla_loot.has("afijos_extra"),
		"y el margen de afijos", str(e._tabla_loot))

	# (3) El EFECTO: el mismo item con y sin nivel da afijos distintos.
	var item: String = _item_equipable()
	_chk(item != "", "hay un item que admite afijos", "")
	if item == "":
		return
	var sin: Array = _afijos_de_item(item, 0, 4242)
	var con: Array = _afijos_de_item(item, 30, 4242)
	_chk(not con.is_empty(), "con nivel salen afijos", str(con))
	_chk(not sin.is_empty(), "y sin nivel también", str(sin))
	_chk(_valor_total(con) > _valor_total(sin),
		"el afijo de un nivel 30 vale MÁS que el de un nivel 0",
		"%.1f vs %.1f" % [_valor_total(con), _valor_total(sin)])

	# (4) El NG+: el margen de prestigio sube la CANTIDAD de afijos. Antes
	# `EstadoNgPlus.afijos_extra()` lo calculaba y lo mostraba el panel, y
	# nadie más lo leía: el botín era idéntico en la vuelta 1 y en la 9.
	EstadoNgPlus.fijar_prestigio_en_juego(0)
	_chk(EstadoNgPlus.afijos_extra_en_juego() == 0,
		"sin prestigio no hay afijos extra", "")
	EstadoNgPlus.fijar_prestigio_en_juego(9)
	_chk(EstadoNgPlus.afijos_extra_en_juego() > 0,
		"con prestigio 9 el NG+ da afijos extra",
		str(EstadoNgPlus.afijos_extra_en_juego()))
	# El margen llega al loot de verdad, no solo al número del panel.
	var tabla_prestigio: Dictionary = _tabla_con_item(item, 0)
	var con_ngplus: int = 0
	for s in range(40):
		var r: RandomNumberGenerator = _rng(1000 + s)
		var d: Array = DropTable.roll_drops(tabla_prestigio, r)
		for dd in d:
			if (dd as Dictionary).get("item_id", "") == item \
					and not ((dd as Dictionary).get("afijos", []) as Array).is_empty():
				con_ngplus += 1
				break
	_chk(con_ngplus > 0, "y el loot con prestigio trae afijos afijados",
		str(con_ngplus))
	EstadoNgPlus.fijar_prestigio_en_juego(0)


## La lista de call sites REALES. El smoke `smoke_fase_escena_completa` ya
## carga la escena entera y pregunta qué hay adentro; esto es lo mismo pero
## sobre el TEXTO del wiring, para que el fallo salga rápido y sin 3 minutos de
## carga de mundo.
func _test_llamadas_reales() -> void:
	var partida: String = _leer(RUTA_PARTIDA)
	_chk(_tiene(_leer("res://scripts/loot/pickup.gd"), "Recoleccion.otorgar"),
		"el botín del mundo da XP de recolección al juntarlo", "")
	_chk(_tiene(_leer("res://scripts/mundo/mineria.gd"),
			"Hechos.FLAG_VETA_PERSISTENTE"),
		"la minería lee la bandera de 'veta_persistente'", "")
	_chk(_tiene(_leer("res://scripts/mundo/gestor_vetas.gd"),
			"Hechos.FLAG_DOBLE_RESPAWN"),
		"el gestor de vetas lee la bandera de 'doble_yacimiento'", "")
	_chk(_tiene(_leer("res://scripts/mundo/cocina.gd"),
			"Hechos.FLAG_COCINA_LOTE"),
		"la cocina lee la bandera de 'cocina_lote'", "")
	_chk(_tiene(_leer("res://scripts/mundo/fogata.gd"),
			"Hechos.FLAG_FOGATA_PERENNE"),
		"la fogata lee la bandera de 'fogata_perenne'", "")
	_chk(_tiene(_leer("res://scripts/ui/panel_cocina.gd"), "_jugador.hechos"),
		"y el panel de cocina le pasa los Hechos a `Cocina`", "")
	_chk(_tiene(_leer("res://scripts/loot/drop_table.gd"),
			"EstadoNgPlus.afijos_extra_en_juego"),
		"el botín lee el margen de afijos del NG+", "")
	_chk(_tiene(_leer("res://scripts/save/save_system.gd"), "\"trofeos\""),
		"los trofeos se guardan con la partida", "")
	# Y que el guardado NO lose el NG+ que ahora usa el loot.
	_chk(_tiene(_leer("res://scripts/progresion/estado_ngplus.gd"),
			"fijar_prestigio_en_juego(prestigio)"),
		"y cargar la partida publica el prestigio para el loot", "")
	_chk(_tiene(partida, "_sistemas_de().registrar(_ngplus"),
		"la partida registra el panel del NG+ (la línea exacta)", "")


# ---------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------

const MINERIA_GD: String = "res://scripts/mundo/mineria.gd"


## El contenido de un archivo, o "" si no se pudo leer.
func _leer(ruta: String) -> String:
	return FileAccess.get_file_as_string(ruta)


## ¿Aparece este texto en el código? Es el "grep" del test: la mitad que
## falla si la conexión desaparece, que es justo lo que un test de COMPORTAMIENTO
## no ve (un sistema desconectado se comporta perfectamente en aislamiento).
func _tiene(texto: String, aguja: String) -> bool:
	return texto.find(aguja) >= 0


## Todo el código de `scripts/` en una sola cadena, para la comprobación
## genérica de banderas. Se arma UNA vez: son 300+ archivos y esto corre en un
## bucle sobre 10 Hechos.
##
## `excluir` son rutas `res://` completas. Hace falta para que una bandera no
## se encuentre a sí misma en la línea donde se declara.
func _codigo_de(directorio: String, excluir: Array = []) -> String:
	var acc: String = ""
	var stack: Array[String] = [directorio]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d: DirAccess = DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var n: String = d.get_next()
		while n != "":
			var ruta: String = dir.path_join(n)
			if d.current_is_dir():
				if not n.begins_with("."):
					stack.append(ruta)
			elif n.ends_with(".gd") and not excluir.has(ruta):
				acc += FileAccess.get_file_as_string(ruta)
			n = d.get_next()
		d.list_dir_end()
	return acc


## El VALOR de una fila "etiqueta / valor" del panel.
##
## `PanelNgPlus._nueva_linea` pone la etiqueta y el valor en DOS Labels
## distintos, así que `textos()` los devuelve en líneas separadas: la fila no
## es una línea sino dos. Por eso se mide el valor y no "apareció la palabra":
## un "apareció" no distingue el +0 del +2.
func _valor_de_fila(texto: String, etiqueta: String) -> String:
	var lineas: PackedStringArray = texto.split("\n")
	for i in range(lineas.size()):
		if lineas[i].strip_edges() != etiqueta:
			continue
		for j in range(i + 1, lineas.size()):
			var v: String = lineas[j].strip_edges()
			if not v.is_empty():
				return v
	return ""


func _jugador() -> Player:
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)
	return p


func _arbol(d: Dictionary) -> Arbol:
	var completo: Dictionary = {
		"id": "arbol_72", "item_id": "tronco_roble", "cantidad": 2, "usos": 2,
		"respawn_s": 180.0, "xp": 6, "nivel": 1, "tinte": "#4a7a3a",
	}
	for k in d.keys():
		completo[k] = d[k]
	var a: Arbol = Arbol.new()
	a.configurar(completo)
	root.add_child(a)
	_basura.append(a)
	return a


func _veta(d: Dictionary) -> Veta:
	var completo: Dictionary = {
		"id": "veta_72", "item_id": "mineral_cobre", "cantidad": 1, "usos": 3,
		"respawn_s": 180.0, "xp": 5, "nivel": 1, "tinte": "#b87333",
	}
	for k in d.keys():
		completo[k] = d[k]
	var v: Veta = Veta.new()
	v.configurar(completo)
	root.add_child(v)
	_basura.append(v)
	return v


func _fogata() -> Fogata:
	var f: Fogata = FG.new()
	f.name = "Fogata72"
	root.add_child(f)
	_basura.append(f)
	return f


func _panel() -> PanelNgPlus:
	var p: PanelNgPlus = PanelNgPlus.new()
	p.name = "PanelNgPlus72"
	root.add_child(p)
	_basura.append(p)
	return p


func _enemigo(arquetipo: Dictionary) -> Enemy:
	var e: Enemy = Enemy.new()
	e.name = "Enemy72"
	root.add_child(e)
	_basura.append(e)
	e.configurar(arquetipo)
	return e


func _arquetipos() -> Dictionary:
	var texto: String = _leer("res://data/enemies.json")
	var d: Variant = JSON.parse_string(texto)
	if not (d is Dictionary):
		return {}
	return (d as Dictionary).get("arquetipos", {})


## Un item del catálogo que ADMITE afijos, tomado del dato y no inventado: si
## mañana `afijos_loot.json` cambia los tipos, el test se entera.
func _item_equipable() -> String:
	for i in ItemDB.ids():
		if AfijosLoot.admite(str(i)):
			return str(i)
	return ""


func _rng(semilla: int) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = semilla
	return r


## Los afijos que llevaría un item a ese `nivel`, con la MISMA semilla en los
## dos casos: así la única variable es el nivel, y la comparación de valores
## mide de verdad el escalado y no dos tiradas distintas.
func _afijos_de_item(item: String, nivel: int, semilla: int) -> Array:
	return Afijos.generar_varios("", AfijosLoot.escala_de_item(item), semilla, nivel)


func _valor_total(afijos: Array) -> float:
	var t: float = 0.0
	for a in afijos:
		t += float((a as Dictionary).get("valor", 0.0))
	return t


## Una tabla de loot con UN item, para pasar por `DropTable.roll_drops` de
## verdad (que es donde se suma el margen del NG+).
func _tabla_con_item(item: String, nivel: int) -> Dictionary:
	return {
		"oro_min": 0, "oro_max": 0,
		"items": [{"item_id": item, "nombre": item, "prob": 1.0,
			"min": 1, "max": 1}],
		"nivel": nivel, "afijos_extra": 0,
	}
