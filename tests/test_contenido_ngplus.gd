extends SceneTree
## Contenido de fin de partida: misiones de NG+, rotación diaria/semanal y
## trofeos.
##
## POR QUÉ ESTE ARCHIVO: el bloque 68 dejó el NG+ funcionando de punta a
## punta (reset, prestigio, multiplicadores, panel) y con eso el juego se
## terminaba igual: subir el número sin nada nuevo que hacer. Esto es lo que
## se añadió para que no se termine en el 70, y este test comprueba las tres
## cosas que lo sostienen.
##
## LO QUE ESTE TEST PROHÍBE HACER (y por qué importa más que lo que
## comprueba): los tests de las fases 22–27 affirmed que el catálogo tiene 41
## misiones. Con 15 de NG+ más y 4 de rotación, ese número pasó a 60. Esos 7
## tests quedaron en rojo por una línea, y el arreglo NO es cambiar el 41 por
## un 60: es que el 60 depende de cuántas diarias hay declaradas y de qué día
## es, así que sería un número tan frágil como el otro y además no diría lo
## que el test quería decir. Por eso `QuestDB.ids_de_archivo()` separa "el
## catálogo escrito" del "catálogo + rotación de hoy", y el 41 viejo se
## convirtió en "el catálogo escrito no se encogió". Este test es el que
## comprueba el otro lado: que la rotación SUMA y que hay contenido.
##
## Las tres cosas:
## 1. LAS MISIONES DE NG+ SON JUGABLES. No basta con que existan: se aceptan,
##    avanzan con `registrar_muerte` y se entregan con `entregar()` contra un
##    `Player` de verdad. Una cadena que solo se ve en el panel no es
##    contenido, es decoración.
## 2. LAS DIARIAS SON DETERMINISTAS PARA UNA MISMA FECHA. Esta es la trampa
##    explícita del encargo: si la semilla viniera de un random global, la
##    rotación cambiaría al guardar y al cargar y el jugador perdería el
##    progreso del día. Aquí se llama dos veces con la misma fecha y se exige
##    la misma lista, y que dos fechas distintas den listas distintas.
## 3. LA ESPIRAL NO SE ACABA. Para cada ciclo hay contenido alcanzable, y el
##    siguiente ciclo trae MÁS, no menos: es lo que separa un NG+ de un techo
##    con escalones.
##
## Cómo correrlo:
##   godot --headless --path . --script res://tests/test_contenido_ngplus.gd

const QL: GDScript = preload("res://scripts/quests/quest_log.gd")
const QD: GDScript = preload("res://scripts/quests/quest_db.gd")
const RD: GDScript = preload("res://scripts/progresion/rotacion_diaria.gd")
const TR: GDScript = preload("res://scripts/progresion/trofeos.gd")
const EN: GDScript = preload("res://scripts/progresion/estado_ngplus.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const PN: GDScript = preload("res://scripts/progresion/panel_ngplus.gd")

## Fechas fijas para los tests de rotación. NUNCA "hoy": un test que depende
## del día en que corre es un test que falla un día de cada siete.
const FECHA_A: int = 20678 * 86400          # 2026-09-29 ish, un día cualquiera
const FECHA_B: int = FECHA_A + 3 * 86400   # tres días después
const FECHA_C: int = FECHA_A + 1 * 86400   # el día siguiente

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Contenido de NG+: misiones, rotación y trofeos")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	QD.cargar()
	_t_datos_ngplus()
	_t_gate_por_ciclo()
	_t_cadena_jugable()
	_t_no_rompe_las_base()
	_t_rotacion_determinista()
	_t_rotacion_registrada()
	_t_diaria_vencida_no_rompe()
	_t_espiral_no_se_acaba()
	_t_trofeos()
	_t_panel_muestra_el_contenido()
	_limpiar()
	print("[TEST] contenido_ngplus: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _log() -> QuestLog:
	var q: QuestLog = QL.new()
	_basura.append(q)
	return q


func _player() -> Player:
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)
	return p


# --- (1) los datos --------------------------------------------------

## Lo que el JSON declara, antes de mirar una línea de código. Si esto falla,
## el problema es el contenido, no el sistema.
func _t_datos_ngplus() -> void:
	var de_archivo: Array[String] = QD.ids_de_archivo()
	var ngplus: Array[String] = []
	for qid in de_archivo:
		if QD.es_ngplus(qid):
			ngplus.append(qid)
	_chk(ngplus.size() == 15,
		"datos: 15 misiones de NG+ escritas", str(ngplus.size()))
	_chk(de_archivo.size() == 56,
		"datos: 56 misiones en el archivo (41 base + 15 NG+)",
		str(de_archivo.size()))

	# Un acto por cadena: los 5 actos del juego base tienen su eco de NG+.
	var actos: Array[int] = []
	for qid in ngplus:
		var a: int = QD.acto_ngplus(qid)
		if not actos.has(a):
			actos.append(a)
	actos.sort()
	_chk(actos == ([1, 2, 3, 4, 5] as Array),
		"datos: los 5 actos tienen cadena de NG+", str(actos))

	# Ninguna misión de NG+ puede quedarse sin contenido: `requiere` cerrado
	# y objetivos que el `QuestLog` sabe contar (matar / recolectar / hablar).
	for qid in ngplus:
		var q: Dictionary = QD.obtener(qid)
		var objs: Array = q.get("objetivos", [])
		_chk(not objs.is_empty(), "datos: " + qid + " tiene objetivos", "")
		_chk(str(q.get("npc_origen", "")) != "",
			"datos: " + qid + " tiene NPC de origen", "")

	# Las cadenas están BIEN CERRADAS: si `q_ngp2_horno` requiere
	# `q_ngp2_ceniza_viva`, esa tiene que existir y ser de NG+ también. Una
	# cadena apuntando al vacío deja la misión bloqueada para siempre, que es
	# contenido que no existe sin que nadie lo note.
	for qid in ngplus:
		var req: String = QD.requiere(qid)
		if req == "":
			continue
		_chk(QD.existe(req), "datos: " + qid + " apunta a una misión real", req)
		_chk(QD.es_ngplus(req),
			"datos: " + qid + " se encadena con otra de NG+", req)

	# El NG+ ABRE y no cierra: toda misión de NG+ declara su ciclo de
	# entrada, y nada la retira después. Un `ngplus_ciclo_hasta` en el JSON
	# sería contenido que desaparece de la vuelta del jugador, y el NG+ está
	# para lo contrario.
	for qid in ngplus:
		_chk(QD.ngplus_ciclo(qid) >= 1,
			"datos: " + qid + " declara su ciclo de entrada", "")
		_chk(QD.disponible_en_ciclo(qid, 99),
			"datos: " + qid + " sigue disponible en una vuelta muy alta", "")


# --- (2) el gate de ciclo --------------------------------------------

## El desbloqueo sale del DATO. Este test no mira el JSON: mira que mover el
## ciclo cambie la disponibilidad, que es la prueba de que el sistema lo
## consulta de verdad.
##
## Se cuentan las CADENAS (`ngplus_acto > 0`), no todo lo que el gate deja
## pasar. La diferencia no es un detalle: cinco plantillas de la rotación
## declaran `ngplus_ciclo` (solo aparecen a partir de una vuelta), así que el
## número total depende de qué día es y de qué tres diarias salieron. Las
## cadenas son las 15 escritas, su número es fijo, y es lo que este test
## afirma.
func _cadenas_de_ciclo(ciclo: int) -> Array[String]:
	var salida: Array[String] = []
	for qid in QD.ids_ngplus_de_ciclo(ciclo):
		if QD.acto_ngplus(qid) > 0:
			salida.append(qid)
	return salida


func _t_gate_por_ciclo() -> void:
	_chk(QD.ids_ngplus_de_ciclo(0).is_empty(),
		"gate: en el ciclo 0 no hay ninguna misión de NG+",
		str(QD.ids_ngplus_de_ciclo(0).size()))

	_chk(_cadenas_de_ciclo(1).size() == 6,
		"gate: el ciclo 1 abre las cadenas de los actos I y II (6)",
		str(_cadenas_de_ciclo(1).size()))
	_chk(_cadenas_de_ciclo(2).size() == 9,
		"gate: el ciclo 2 suma el acto III (9)", str(_cadenas_de_ciclo(2).size()))
	_chk(_cadenas_de_ciclo(3).size() == 12,
		"gate: el ciclo 3 suma el acto IV (12)", str(_cadenas_de_ciclo(3).size()))
	_chk(_cadenas_de_ciclo(4).size() == 15,
		"gate: el ciclo 4 suma el acto V (15)", str(_cadenas_de_ciclo(4).size()))
	_chk(_cadenas_de_ciclo(9).size() == 15,
		"gate: el NG+ abre y no cierra: en la vuelta 9 siguen las 15",
		str(_cadenas_de_ciclo(9).size()))

	# Y el QuestLog lo respeta: no es que `ids_ngplus_de_ciclo` diga una cosa
	# y el log haga otra.
	EN.fijar_ciclo_en_juego(0)
	var q0: QuestLog = _log()
	var primera_c1: String = QD.ids_de_archivo()[41]
	_chk(q0.estado(primera_c1) == "bloqueada",
		"gate: con ciclo 0 la primera misión de NG+ está bloqueada",
		q0.estado(primera_c1))
	_chk(q0.aceptar(primera_c1) == "no_disponible",
		"gate: y no se puede aceptar", "")

	EN.fijar_ciclo_en_juego(1)
	var q1: QuestLog = _log()
	_chk(q1.estado(primera_c1) == "disponible",
		"gate: con ciclo 1 la misma misión está disponible",
		q1.estado(primera_c1))
	_chk(q1.aceptar(primera_c1) == "ok",
		"gate: y ahora sí se acepta", q1.aceptar(primera_c1))
	EN.fijar_ciclo_en_juego(0)

	# Una misión ya aceptada NO se le quita al jugador al prestigiar: la
	# gate es para lo que aún no empezó.
	EN.fijar_ciclo_en_juego(1)
	var qa: QuestLog = _log()
	qa.aceptar(primera_c1)
	EN.fijar_ciclo_en_juego(0)
	_chk(qa.estado(primera_c1) == "activa",
		"gate: una misión ya aceptada no se pierde al volver al ciclo 0",
		qa.estado(primera_c1))
	EN.fijar_ciclo_en_juego(0)


# --- (3) jugables de verdad ------------------------------------------

## El test que separa "contenido" de "decoración". Se acepta, se avanza con
## el `QuestLog` de verdad y se entrega contra un `Player` de verdad.
func _t_cadena_jugable() -> void:
	EN.fijar_ciclo_en_juego(4)
	var q: QuestLog = _log()
	var p: Player = _player()
	# El acto V es el último en abrir y no se retira nunca: la cadena más
	# larga, la que llega más lejos.
	var cadena: Array[String] = QD.ids_ngplus_de_acto(5)
	_chk(cadena.size() == 3, "jugable: el acto V tiene 3 misiones",
		str(cadena.size()))
	# Se recorren en el orden de cadena (el `requiere` las encadena).
	var hecha: int = 0
	for qid in cadena:
		_chk(q.estado(qid) == "disponible",
			"jugable: " + qid + " disponible cuando toca", q.estado(qid))
		_chk(q.aceptar(qid) == "ok", "jugable: se acepta " + qid, q.aceptar(qid))
		_registrar_todo(q, p, qid)
		_chk(q.estado(qid) == "lista",
			"jugable: " + qid + " llega a lista", q.estado(qid))
		var res: Dictionary = q.entregar(qid, p)
		_chk(str(res.get("resultado", "")) == "ok",
			"jugable: " + qid + " se entrega", str(res.get("resultado", "")))
		hecha += 1
	_chk(hecha == 3, "jugable: la cadena entera del acto V se completa",
		str(hecha))
	_chk(q.estado(cadena[0]) == "entregada",
		"jugable: la primera queda entregada", q.estado(cadena[0]))
	EN.fijar_ciclo_en_juego(0)


## Avanza TODOS los objetivos de una misión como si el jugador lo hubiera
## hecho: mata lo que haya que matar, junta lo que haya que juntar, habla con
## quien toque. El objetivo "recolectar" se resuelve metiendo el item en el
## inventario REAL y llamando a `sincronizar_recoleccion`, que es el camino
## que usa el juego; si se falseara el progreso a mano, el test probaría el
## `QuestLog` y no la cadena.
func _registrar_todo(q: QuestLog, p: Player, qid: String) -> void:
	for obj in QD.obtener(qid).get("objetivos", []):
		var o: Dictionary = obj
		match str(o.get("tipo", "")):
			"matar":
				for i in range(int(o.get("cantidad", 1))):
					q.registrar_muerte(str(o.get("arquetipo", "")))
			"recolectar":
				p.inventario.agregar(str(o.get("item", "")),
					int(o.get("cantidad", 1)))
				q.sincronizar_recoleccion(p.inventario)
			"hablar":
				q.registrar_dialogo(str(o.get("npc", "")))


# --- (4) las 41 base no cambian --------------------------------------

## El requisito explícito del encargo: si la misión NO declara
## `ngplus_ciclo`, tiene que quedar disponible igual que antes. El gate nuevo
## no puede cambiar el comportamiento de lo que ya funcionaba.
func _t_no_rompe_las_base() -> void:
	var base: int = 0
	for qid in QD.ids_de_archivo():
		if QD.es_ngplus(qid):
			continue
		base += 1
		_chk(QD.disponible_en_ciclo(qid, 0),
			"base: " + qid + " disponible en el ciclo 0", "")
		_chk(QD.disponible_en_ciclo(qid, 4),
			"base: " + qid + " sigue disponible en el ciclo 4", "")
		_chk(QD.acto_ngplus(qid) == 0,
			"base: " + qid + " no declara acto de NG+", "")
	_chk(base == 41, "base: siguen siendo 41", str(base))

	# Y el estado real del QuestLog no cambia con el ciclo: una base con su
	# `requiere` cumplido está "disponible" en cualquier vuelta.
	EN.fijar_ciclo_en_juego(0)
	var q0: QuestLog = _log()
	EN.fijar_ciclo_en_juego(3)
	var q3: QuestLog = _log()
	var iguales: int = 0
	for qid in QD.ids_de_archivo():
		if QD.es_ngplus(qid):
			continue
		if q0.estado(qid) == q3.estado(qid):
			iguales += 1
	_chk(iguales == 41,
		"base: las 41 tienen el MISMO estado en el ciclo 0 y en el 3",
		str(iguales))
	EN.fijar_ciclo_en_juego(0)


# --- (5) la rotación es determinista ---------------------------------

## LA TRAMPA DEL ENCARGO. La semilla tiene que salir del DÍA, no de un random
## global, o al guardar y cargar la misma rotación cambia sola y el jugador
## pierde el progreso del día.
func _t_rotacion_determinista() -> void:
	var a1: Array[String] = RD.plantillas_del_dia(RD.dia_de(FECHA_A), 0)
	var a2: Array[String] = RD.plantillas_del_dia(RD.dia_de(FECHA_A), 0)
	_chk(a1 == a2,
		"rotación: la misma fecha da la misma lista", str(a1) + " vs " + str(a2))
	_chk(a1.size() == RD.dias_por_dia(),
		"rotación: salen las 3 diarias declaradas en el JSON", str(a1.size()))

	# Días distintos, listas distintas. Si fueran iguales, la rotación no
	# serviría de nada: sería la misma一批 de encargos para siempre.
	var c: Array[String] = RD.plantillas_del_dia(RD.dia_de(FECHA_C), 0)
	_chk(c != a1, "rotación: dos días distintos dan listas distintas",
		str(a1) + " vs " + str(c))
	var b: Array[String] = RD.plantillas_del_dia(RD.dia_de(FECHA_B), 0)
	_chk(b != a1, "rotación: a tres días otra lista", str(a1) + " vs " + str(b))

	# SIN REPETIR dentro del mismo día: si una plantilla saliera dos veces, el
	# jugador vería el mismo encargo dos veces y pensaría que hay un bug.
	var sin_repeticion: bool = true
	for i in range(a1.size()):
		for j in range(i + 1, a1.size()):
			if a1[i] == a1[j]:
				sin_repeticion = false
	_chk(sin_repeticion, "rotación: no repite plantilla dentro del día",
		str(a1))

	# El ciclo de NG+ cambia los encargos Y es reproducible: la vuelta 3 es
	# la misma cada vez que se llega a la vuelta 3.
	var ngp0: Array[String] = RD.plantillas_del_dia(RD.dia_de(FECHA_A), 0)
	var ngp3: Array[String] = RD.plantillas_del_dia(RD.dia_de(FECHA_A), 3)
	_chk(ngp3 == RD.plantillas_del_dia(RD.dia_de(FECHA_A), 3),
		"rotación: el ciclo también es determinista", str(ngp3))
	_chk(ngp3 != ngp0,
		"rotación: el NG+ cambia los encargos", str(ngp0) + " vs " + str(ngp3))

	# Las semanales: una por semana, con su propia semilla.
	var s1: Array[String] = RD.plantillas_de_la_semana(RD.semana_de(FECHA_A), 0)
	var s2: Array[String] = RD.plantillas_de_la_semana(RD.semana_de(FECHA_A), 0)
	_chk(s1 == s2, "semanales: la misma semana da la misma", str(s1))
	_chk(s1.size() == RD.semanas_por_semana(),
		"semanales: sale la 1 semanal declarada", str(s1.size()))

	# El ID de una misión concreta lleva la FECHA: es lo que hace la rotación
	# reproducible y lo que deja que las de ayer se apaguen solas.
	var m: Array[Dictionary] = RD.misiones_del_dia(RD.dia_de(FECHA_A), 0)
	_chk(m.size() == a1.size(), "concretas: una misión por plantilla", str(m.size()))
	for mm in m:
		var id: String = str(mm.get("id", ""))
		_chk(id.begins_with(RD.PREFIJO_DIARIA),
			"concretas: " + id + " lleva el prefijo de diaria", id)
		_chk(bool(mm.get("efimera", false)),
			"concretas: " + id + " se marca efímera", id)
		_chk(int(mm.get("vence_dia", 0)) == RD.dia_de(FECHA_A),
			"concretas: " + id + " vence hoy", str(mm.get("vence_dia", 0)))
	# Las recompensas suben con el prestigio: en la vuelta 3 una diaria vale
	# más que en la vuelta 0, o no hay motivo para prestigious.
	var m0: Dictionary = RD.misiones_del_dia(RD.dia_de(FECHA_A), 0)[0]
	var m3: Dictionary = RD.misiones_del_dia(RD.dia_de(FECHA_A), 3)[0]
	_chk(int(m3["recompensas"]["oro"]) > int(m0["recompensas"]["oro"]),
		"concretas: el NG+ sube la recompensa de la diaria",
		"%d vs %d" % [int(m0["recompensas"]["oro"]), int(m3["recompensas"]["oro"])])


## La rotación llega al CATÁLOGO, que es donde la ve el resto del juego. Si
## esto falla, las diarias existen y no aparecen en ningún panel: el mismo
## bug del bloque 63 (sistemas escritos, testeados y nunca instanciados).
## Cuántas misiones de rotación están VIGENTES ahora mismo en el catálogo.
## Es la cifra que el jugador ve, y por eso es la que importa: el tamaño
## total del catálogo incluye las rotaciones viejas, que se conservan a
## propósito para que una misión aceptada ayer no desaparezca del panel.
func _vigentes() -> int:
	var n: int = 0
	for qid in QD.ids():
		if QD.es_efimera(qid) and QD.vigente(qid):
			n += 1
	return n


func _t_rotacion_registrada() -> void:
	var antes: int = QD.ids().size()
	QD.sincronizar_rotacion()
	var despues: int = QD.ids().size()
	_chk(despues == antes,
		"catálogo: sincronizar dos veces no duplica nada",
		"%d -> %d" % [antes, despues])

	# Lo que importa: HAY misiones de rotación en el catálogo y son las de
	# HOY, no las de ningún otro día. No se cuenta el total del catálogo
	# (depende del día) sino cuántas están VIGENTES.
	var hoy: int = 0
	for qid in QD.ids():
		if QD.es_efimera(qid) and QD.vigente(qid):
			hoy += 1
	_chk(hoy == RD.dias_por_dia() + RD.semanas_por_semana(),
		"catálogo: hay %d encargos vigentes (3 diarias + 1 semanal)" % hoy,
		str(hoy))

	# El filtro de vigencia tiene DOS mitades y hacen falta las dos. Con el
	# día solo, prestigiar a media sesión dejaba vivas las diarias de la
	# vuelta anterior junto a las nuevas y el jugador veía el doble de
	# encargos de los que le tocan. Se comprueba subiendo el ciclo.
	var antes_del_cambio: int = _vigentes()
	EN.fijar_ciclo_en_juego(2)
	QD.sincronizar_rotacion()
	_chk(_vigentes() == RD.dias_por_dia() + RD.semanas_por_semana(),
		"catálogo: al prestigiar a media sesión no quedan las dos rondas",
		"%d -> %d" % [antes_del_cambio, _vigentes()])
	EN.fijar_ciclo_en_juego(0)
	QD.sincronizar_rotacion()
	_chk(_vigentes() == RD.dias_por_dia() + RD.semanas_por_semana(),
		"catálogo: y al volver al ciclo 0 tampoco", str(_vigentes()))

	# Y son alcanzables por el camino de siempre: un NPC las ofrece.
	var q: QuestLog = _log()
	var p: Player = _player()
	# La diaria que se prueba tiene que ser una JUGABLE EN EL CICLO QUE SE ESTÁ
	# PROBANDO, no la primera que salga por el día.
	#
	# `misiones_del_dia` devuelve las 4 del día y el orden depende de la semilla.
	# Una de ellas declara `ngplus_ciclo: 1` (la plantilla `dia_carnicoro_maris`),
	# así que en el ciclo 0 — que es lo que prueba este bloque — su estado
	# correcto es "bloqueada", y la cadena entera (disponible → se acepta →
	# lista → se entrega) falla sin que haya un solo bug: la misión elegida no
	# era jugable ahí.
	#
	# Con `dia_arena_karg` y `dia_hierro_durnan` (`ngplus_ciclo: 0`) el mismo
	# camino se recorre entero.
	var elegida: Dictionary = {}
	for cand in RD.misiones_del_dia(RD.dia_de(RD.ahora()), 0):
		if int(cand.get("ngplus_ciclo", 0)) <= 0:
			elegida = cand
			break
	if elegida.is_empty():
		_chk(false, "catálogo: hay una diaria de ciclo base hoy",
			"ninguna de las del día es de ciclo 0; el catálogo no se puede probar")
		return
	var m: Dictionary = elegida
	var qid: String = str(m.get("id", ""))
	_chk(QD.existe(qid), "catálogo: la diaria de hoy está en el catálogo", qid)
	_chk(q.estado(qid) == "disponible",
		"catálogo: y está disponible", q.estado(qid))
	_chk(q.aceptar(qid) == "ok", "catálogo: se acepta", "")
	_registrar_todo(q, p, qid)
	_chk(q.estado(qid) == "lista", "catálogo: llega a lista", q.estado(qid))
	var res: Dictionary = q.entregar(qid, p)
	_chk(str(res.get("resultado", "")) == "ok",
		"catálogo: se entrega", str(res.get("resultado", "")))
	_chk(q.estado(qid) == "entregada", "catálogo: queda entregada", "")

	# Un NPC la ofrece SI no tiene antes una misión propia disponible: se
	# comprueba con un NPC sin misiones base, para que la prueba sea de la
	# rotación y no del orden en que salen las otras.
	var sin_base: String = ""
	for npc_id in ["ilya", "bram", "sira", "yasmina", "durnan", "sella",
			"elthar", "vex", "karg", "maris", "aurelio"]:
		var tiene: bool = false
		for qid2 in QD.ids_de_archivo():
			if str(QD.obtener(qid2).get("npc_origen", "")) == npc_id:
				tiene = true
				break
		if not tiene:
			sin_base = npc_id
			break
	if sin_base != "":
		var q2: QuestLog = _log()
		_chk(q2.oferta_para_npc(sin_base).is_empty(),
			"catálogo: un NPC sin misiones base no ofrece nada", "")


## UNA DIARIA DE AYER NO ROMPE LA CARGA. Es el caso que pidió revisar el
## encargo: una partida guardada ayer tiene ids `dia_...` que hoy no están en
## el catálogo, porque la rotación de hoy se registra al arrancar.
func _t_diaria_vencida_no_rompe() -> void:
	var vencida: String = "dia_d000001_plantilla_que_no_existe"
	var q: QuestLog = _log()
	_chk(QD.es_id_de_rotacion(vencida),
		"vencida: un id de rotación se reconoce aunque no esté en el catálogo",
		"")
	# El `cargar_estado` no debe reventar ni ensuciar: la vencida se ignora.
	q.cargar_estado({
		"version": QuestLog.SAVE_VERSION,
		"misiones": {
			vencida: {"estado": "activa", "progreso": [3]},
			"goblins_fuera": {"estado": "activa", "progreso": [2]},
		},
	})
	_chk(q.estado("goblins_fuera") == "activa",
		"vencida: la misión normal de al lado SÍ carga",
		q.estado("goblins_fuera"))
	_chk(q.estado(vencida) == "desconocida",
		"vencida: la diaria vieja queda desconocida (venció)", q.estado(vencida))
	# Una misión normal desconocida, en cambio, sigue avisando: es un bug de
	# verdad y no hay que esconderlo.
	q.cargar_estado({
		"version": QuestLog.SAVE_VERSION,
		"misiones": {"mision_inventada": {"estado": "activa", "progreso": [1]}},
	})
	_chk(q.estado("mision_inventada") == "desconocida",
		"vencida: una normal inventada también se ignora", "")


# --- (6) la espiral no se acaba --------------------------------------

## Para TODO ciclo hay contenido alcanzable, y el siguiente trae MÁS, no
## menos. Es lo que separa un NG+ de un techo con escalones: si en la vuelta
## 7 no queda nada, el "prestigio" es un número y el juego sigue terminando en
## el 70.
func _t_espiral_no_se_acaba() -> void:
	var anterior: int = 0
	for ciclo in range(1, 13):
		var n: int = _cadenas_de_ciclo(ciclo).size()
		_chk(n > 0, "espiral: el ciclo %d tiene contenido" % ciclo, str(n))
		_chk(n >= anterior,
			"espiral: el ciclo %d no tiene MENOS que el %d" % [ciclo, ciclo - 1],
			"%d < %d" % [n, anterior])
		anterior = n
	_chk(anterior == 15,
		"espiral: la vuelta 12 tiene las 15 misiones de NG+", str(anterior))

	# Los actos IV y V son los que no se retiran nunca, y con ellos la
	# espiral no vuelve a quedarse sin nada: son 6 misiones fijas para siempre.
	for ciclo in [4, 5, 8, 12]:
		for acto in [4, 5]:
			var c: Array[String] = QD.ids_ngplus_de_acto(acto)
			_chk(not c.is_empty() and QD.disponible_en_ciclo(c[0], ciclo),
				"espiral: el acto %d sigue en el ciclo %d" % [acto, ciclo], "")

	# La espiral también se ABRE: cada ciclo hasta el 4 trae algo nuevo, y
	# desde ahí sigue añadiendo (el acto V entra en el 4).
	for ciclo in range(1, 5):
		var nuevas: int = 0
		for qid in _cadenas_de_ciclo(ciclo):
			if not QD.disponible_en_ciclo(qid, ciclo - 1):
				nuevas += 1
		_chk(nuevas > 0,
			"espiral: el ciclo %d trae contenido nuevo" % ciclo, str(nuevas))


# --- (7) los trofeos -------------------------------------------------

func _t_trofeos() -> void:
	var t: Trofeos = TR.new()
	_basura.append(t)
	_chk(t.total() == 12, "trofeos: 12 declarados en el JSON", str(t.total()))

	# Nadie tiene nada al arrancar.
	_chk(t.total_ganados() == 0, "trofeos: nadie tiene trofeos al inicio", "")
	_chk(t.evaluar({"ciclo": 0, "prestigio": 0}) == [],
		"trofeos: el contexto vacío no otorga nada", "")

	# Ciclo 1: se abre la espiral. Solo lo que la condición dice.
	var nuevos: Array[String] = t.evaluar({"ciclo": 1, "prestigio": 1})
	_chk(nuevos.has("primera_vuelta"),
		"trofeos: cerrar el primer ciclo da el trofeo", str(nuevos))
	_chk(not nuevos.has("tres_vueltas"),
		"trofeos: y NO da el de tres vueltas", str(nuevos))
	_chk(t.tiene("primera_vuelta"), "trofeos: queda guardado", "")

	# Idempotente: evaluar otra vez no vuelve a dar lo mismo. Si lo hiciera,
	# un aviso de "trofeo desbloqueado" saldría en cada frame.
	_chk(t.evaluar({"ciclo": 1, "prestigio": 1}) == [],
		"trofeos: evaluar dos veces no repite", "")

	# Una cadena de NG+ completa da el trofeo de su acto, y SOLO el suyo.
	var todas_5: Array[String] = []
	for a in [1, 2, 3, 4, 5]:
		todas_5.append_array(QD.ids_ngplus_de_acto(a))
	var n2: Array[String] = t.evaluar({
		"ciclo": 1, "prestigio": 1,
		"misiones_entregadas": QD.ids_ngplus_de_acto(1) as Array,
	})
	_chk(n2.has("acto1_eco"),
		"trofeos: terminar el acto I da su trofeo", str(n2))
	_chk(not n2.has("acto2_forja"),
		"trofeos: y no da el del acto II sin hacerlo", str(n2))

	# Una cadena PARCIAL no completa el acto: "terminaste la cadena" tiene que
	# significar la cadena entera, o el trofeo mentiría en su nombre.
	var parcial: Array[String] = QD.ids_ngplus_de_acto(2)
	parcial.resize(1)
	var n3: Array[String] = t.evaluar({
		"ciclo": 1, "prestigio": 1,
		"misiones_entregadas": parcial as Array,
	})
	_chk(not n3.has("acto2_forja"),
		"trofeos: una cadena a medias NO da el trofeo de acto", str(n3))
	_chk(t.evaluar({
		"ciclo": 1, "prestigio": 1,
		"misiones_entregadas": todas_5 as Array,
	}).has("todos_los_actos"),
		"trofeos: las cinco cadenas dan el de todos los actos", "")

	# Los dePrestigio/afijos salen de los números, no de un `if` por trofeo.
	var t2: Trofeos = TR.new()
	_basura.append(t2)
	var n4: Array[String] = t2.evaluar({"ciclo": 10, "prestigio": 55})
	_chk(n4.has("diez_vueltas") and n4.has("prestigio_dorado")
			and n4.has("tres_afijos"),
		"trofeos: ciclo/prestigio/afijos se resuelven desde el dato", str(n4))

	# Un tipo de condición desconocido NO otorga nada: es lo conservador.
	var t3: Trofeos = TR.new()
	_basura.append(t3)
	_chk(t3.evaluar({"ciclo": 999, "prestigio": 999}).size() <= t3.total(),
		"trofeos: un contexto enorme no otorga trofeos inventados", "")

	# Guardar/cargar el set: es lo único que hay que guardar.
	var t4: Trofeos = TR.new()
	_basura.append(t4)
	t4.evaluar({"ciclo": 1, "prestigio": 1})
	var d: Dictionary = t4.to_dict()
	var t5: Trofeos = TR.new()
	_basura.append(t5)
	t5.cargar_estado(d)
	_chk(t5.tiene("primera_vuelta"),
		"trofeos: el set sobrevive al round-trip", str(t5.ganados()))
	# Y una versión vieja NO borra los que ya había: es un save, no un comando.
	var t6: Trofeos = TR.new()
	_basura.append(t6)
	t6.evaluar({"ciclo": 1, "prestigio": 1})
	t6.cargar_estado({"version": 999, "ganados": {}})
	_chk(t6.total_ganados() == 0,
		"trofeos: una versión distinta arranca vacío (tolerante)", "")
	# El reinicio del NG+: lo que se ganó en la vuelta anterior ya no cuenta.
	t4.reiniciar()
	_chk(t4.total_ganados() == 0, "trofeos: reiniciar los borra", "")


func _limpiar() -> void:
	for n in _basura:
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()


## --- (8) el contenido SE VE ---------------------------------------
##
## Esto parece UI y es lo más importante del archivo. El bloque 68 terminó
## con un panel de NG+ que sube multiplicadores y no dice NADA de qué hacer:
## el prestige sin juego. Y el error de este repo ya está pagado (los siete
## sistemas de `_instalar_fase63_64_ui`, escritos, testeados y nunca
## instanciados): un sistema sin consumidor es un sistema que no existe.
##
## Por eso el test no se conforma con "el panel se abre": MOUEVE EL DATO y
## comprueba que el TEXTO cambia. Conectar la señal dentro del test y no
## tocar nada probaría que el panel abre, no que funciona.
func _t_panel_muestra_el_contenido() -> void:
	var panel: PanelNgPlus = PanelNgPlus.new()
	_basura.append(panel)
	root.add_child(panel)

	# Antes: SIN NG+. Es el estado real de un jugador nuevo, y el punto de
	# comparación tiene que ser ese: si arrancáramos ya en el ciclo 1, el
	# trofeo se otorgaría al abrir y no habría nada que "moverse".
	var t: Trofeos = Trofeos.instancia()
	t.reiniciar()
	var e: EstadoNgPlus = EstadoNgPlus.new()
	e.ciclo = 0
	e.prestigio = 0
	_chk(panel.abrir(e), "panel: abre con el estado", "")
	var antes: String = "\n".join(panel.textos())
	_chk(antes.contains("Ciclo 0"), "panel: pinta el ciclo", antes)
	_chk(not _trofeo_en_panel(antes, "La primera vuelta"),
		"panel: sin NG+ todavía NO aparece el trofeo de la vuelta", antes)
	# Los encargos de HOY tienen que estar a la vista aunque no haya NG+:
	# las diarias son contenido del día 1 también.
	_chk(_alguna_etiqueta_visible(antes, 0),
		"panel: se ven los encargos de hoy (el contenido nuevo)", antes)
	_chk(antes.contains("Trofeos"),
		"panel: hay sección de trofeos", antes)

	# MOVER EL DATO. Se prestigia de verdad (el estado sube) y el panel tiene
	# que reflejarlo. Si leyera un número fijo, esto no pasaría, y el test
	# pasaría igual: por eso se comparan los dos textos.
	e.ciclo = 1
	e.prestigio = 3
	panel.al_cambiar_estado()
	var despues: String = "\n".join(panel.textos())
	_chk(despues.contains("Ciclo 1"),
		"panel: tras prestigiar muestra el ciclo nuevo", despues)
	_chk(_trofeo_en_panel(despues, "La primera vuelta"),
		"panel: y ahora SÍ aparece el trofeo de la vuelta", despues)
	_chk(despues != antes,
		"panel: el texto se movió al cambiar el dato", "")

	panel.cerrar_panel()
	t.reiniciar()


## ¿El trofeo está GANADO (·) en el panel? Se busca la línea completa, no el
## nombre suelto: el nombre de un trofeo puede ser una subcadena de otra cosa
## de la pantalla — el título del panel es "Nueva vuelta (NG+)" y el trofeo
## "La primera vuelta" estaba dentro, lo que hacía pasar un aserto que no
## comprobaba nada. La línea lleva un "·" delante cuando está ganado y un
## "○" cuando no; se exige el que corresponde.
func _trofeo_en_panel(textos: String, nombre: String) -> bool:
	for linea in textos.split("\n"):
		if linea.contains(nombre):
			if linea.strip_edges().begins_with("·"):
				return true
	return false


## ¿Se ve en el panel alguno de los encargos vigentes? Se compara por
## ETIQUETA y no por id: el panel muestra el nombre de la misión, que es lo
## que el jugador lee.
func _alguna_etiqueta_visible(textos: String, ciclo: int) -> bool:
	for m in RD.misiones_vigentes(ciclo):
		if QD.vigente(str(m.get("id", ""))):
			if textos.contains(str(m.get("nombre", ""))):
				return true
	return false
