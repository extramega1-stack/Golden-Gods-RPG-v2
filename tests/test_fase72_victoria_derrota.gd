extends SceneTree
## Tests headless de la Fase 72 (condiciones de victoria y derrota).
##
## POR QUÉ NACE: el juego NO tenía forma de ganar ni de perder. Se podían
## entregar las dos misiones finales (600 oro y 1500 XP) y el juego seguía
## exactamente igual. Y la muerte no mataba: `RespawnHeros` te devolvía a la
## plaza sin penalidad. Cero pantallas de final, cero game over.
##
## Cubre:
## (a) el DATO: `data/derrota.json` declara las dos sendas, los dos finales y
##     el coste de morir, y los ids de misión que declara EXISTEN en el catálogo;
## (b) victoria por la senda canónica (Sello) y por la del Arma, con la señal
##     `victoria` y exactamente una vez;
## (c) derrota: la muerte suspende el respawn, cobra el coste del DATO y avisa;
## (d) el coste de muerte: oro y XP salen de `data/derrota.json`, y morir NUNCA
##     hace bajar de nivel;
## (e) la muerte NO se cobra dos veces, ni con doble clic, ni por un revivir
##     seguido de otro;
## (f) la arena NO es derrota de partida (su derrota es suya);
## (g) persistencia: el bloque "resultado" viaja en el guardado y cargar una
##     partida ya ganada NO pierde el final;
## (h) la UI: `PanelFinal` se abre con la señal y dibuja el texto del dato;
##     `PanelDerrota` se abre con la muerte y muestra lo que costó;
## (i) LA PRUEBA DE QUE ESTÁ CONECTADO: la escena real de la partida tiene el
##     sistema y los dos paneles registrados, y `PanelFinal` se abre DE VERDAD
##     cuando el sistema declara la victoria DENTRO de la partida. Ese es el
##     fallo que el proyecto ya documento en MASTER_SPEC §2487-2493:
##     "un test por sistema no dice nada sobre si el sistema está conectado a
##     nada". Los ocho bloques anteriores de este archivo pasanían igual si nadie
##     llamara a `_instalar_fase72()`; el último no.
##
## Cómo correrlo:
## godot --headless --path <proyecto> --script res://tests/test_fase72_victoria_derrota.gd

const RUTA: String = "res://tests/_test_fase72_partida.json"

const RP: GDScript = preload("res://scripts/core/resultado_partida.gd")
const PF: GDScript = preload("res://scripts/ui/panel_final.gd")
const PD: GDScript = preload("res://scripts/ui/panel_derrota.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const QL: GDScript = preload("res://scripts/quests/quest_log.gd")
const QDB: GDScript = preload("res://scripts/quests/quest_db.gd")
const RH: GDScript = preload("res://scripts/mundo/respawn_heroe.gd")
const SS: GDScript = preload("res://scripts/save/save_system.gd")
const FM: GDScript = preload("res://scripts/core/formulas.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []
## La escena real de la partida, y los frames que se la dejaron armar. Vive en
## variables de la clase porque el bloque (i) necesita CORRER EN VARIOS FRAMES:
## `_al_mundo_listo()` no dispara hasta que el mundo está construido, y un test
## que lo espera con un `while` adentro de un solo `_process` se comería a sí
## mismo. Es el mismo patrón de espera por frames del smoke de la escena.
var _demo: Node = null
var _frames_espera: int = 0
## Después de que aparece el jugador, cuántos frames más se deja construir el
## mundo. `_al_mundo_listo()` (que es donde se registran los sistemas) dispara
## bastante después de que el `Player` cuelgue del árbol: si se mirara en
## cuanto aparece el jugador, este bloque miraría la partida a medio armar y
## daría por ausente lo que todavía no se registró.
const FRAMES_ESPERA: int = 40
const ESPERA_MAX: int = 3000


func _init() -> void:
	print("[TEST] Fase 72 — victoria y derrota")


## La convención del repo: `true` = terminar (con el número de fallos en el
## código de salida), `false` = seguir. Son TRES estados y no dos, y por eso el
## segundo es un enum y no el booleano `_empezo`: con un solo booleano, el
## segundo frame caía directo al `quit()` y el bloque (i) —el que carga la
## escena real— no se ejecutaba nunca. Un test que se salta su propia prueba
## más importante en verde es peor que un test que no existe.
enum _Etapa { SIN_EMPEZAR, EN_CORSO, TERMINADO }


var _etapa: int = _Etapa.SIN_EMPEZAR


func _process(_delta: float) -> bool:
	if _etapa == _Etapa.SIN_EMPEZAR:
		_etapa = _Etapa.EN_CORSO
		_test_dato()
		_test_victoria_por_senda()
		_test_derrota_y_coste()
		_test_no_se_cobra_dos_veces()
		_test_la_arena_no_es_derrota()
		_test_persistencia()
		_test_paneles()
	if not _esperar_la_partida():
		return false
	_etapa = _Etapa.TERMINADO
	return _terminar()


## Carga la escena de la partida y espera a que esté lista. Devuelve `true`
## cuando se terminó.
func _esperar_la_partida() -> bool:
	if _frames_espera > ESPERA_MAX:
		_chk(false, "i2: la partida llega a tener jugador (timeout)", "%d frames" % _frames_espera)
		return true
	if _demo == null:
		var escena: PackedScene = load("res://scenes/demo/fase14_demo.tscn")
		if escena == null:
			_chk(false, "i1: la escena de la partida carga", "")
			return true
		_demo = escena.instantiate()
		root.add_child(_demo)
		_basura.append(_demo)
		return false
	_frames_espera += 1
	# Se espera a que el jugador exista, y DESPUÉS un rato: el `Player` cuelga
	# del árbol en el `_ready`, pero `_al_mundo_listo()` —donde se registran
	# los sistemas— recién dispara cuando las nueve ciudades terminaron de
	# armarse.
	if _frames_espera < FRAMES_ESPERA or _buscar_jugador(_demo) == null:
		return false
	_test_esta_conectado_en_la_partida()
	return true


func _terminar() -> bool:
	print("[TEST] fase72_victoria_derrota: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	print("[CHK] ", nombre)
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


# --- (a) el dato ----------------------------------------------------------

## El coste y los finales son DATO (§9.4), y los ids de misión que el dato
## declara tienen que existir en el catálogo. Un id mal escrito en el JSON
## desactivaría la victoria en silencio: el juego volvería a no tener final, y
## ningún otro test lo notaría.
func _test_dato() -> void:
	# `QuestDB.existe()` y `obtener()` NO cargan el catálogo por su cuenta (solo
	# `ids()` y `ids_de_archivo()` lo hacen), así que sin esta línea el test
	# affirmaría que las misiones finales no existen, cuando lo que no existe
	# es la caché.
	QDB.cargar()
	var d: Dictionary = RP.datos()
	_chk(not d.is_empty(), "a1: data/derrota.json se lee", str(d.keys()))
	_chk(int(d.get("version", 0)) >= 1, "a2: el dato está versionado", "v=%d" % int(d.get("version", 0)))

	var sendas: Array[String] = RP.sendas()
	_chk(sendas.size() == 2, "a3: el dato declara las dos sendas", str(sendas))
	_chk(sendas.has(RP.SENDA_LIBERTY), "a4: está la senda canónica (Sello)", str(sendas))
	_chk(sendas.has(RP.SENDA_ARMA), "a5: está la senda del Arma", str(sendas))
	for s in sendas:
		var mid: String = RP.mision_de_senda(s)
		_chk(mid != "", "a6: la senda '%s' declara su misión" % s, "")
		_chk(QDB.existe(mid), "a7: la misión '%s' de la senda '%s' existe" % [mid, s],
			"el id del JSON no está en data/quests.json")
		var final: Dictionary = RP.final_de(s)
		_chk(not final.is_empty(), "a8: la senda '%s' tiene final" % s, "")
		for campo in ["titulo", "subtitulo", "cuerpo", "cierre", "epigrafe"]:
			_chk(str(final.get(campo, "")) != "", "a9: el final de '%s' tiene '%s'" % [s, campo], "")

	# El canon (§7.4): el Sello es la senda canónica y la del Arma la amarga.
	_chk(RP.mision_de_senda(RP.SENDA_LIBERTY) == "q_final_sello",
		"a10: la senda canónica es q_final_sello (Senda Liberty)", "")
	_chk(RP.mision_de_senda(RP.SENDA_ARMA) == "q_final_espada",
		"a11: la senda del Arma es q_final_espada", "")

	var der: Dictionary = RP.datos_derrota()
	var pct_oro: float = float(der.get("porcentaje_oro", -1.0))
	var pct_xp: float = float(der.get("porcentaje_xp_nivel", -1.0))
	_chk(pct_oro > 0.0 and pct_oro <= 1.0, "a12: el coste de oro está en el dato y es 0<n<=1",
		"porcentaje_oro=%f" % pct_oro)
	_chk(pct_xp > 0.0 and pct_xp <= 1.0, "a13: el coste de XP está en el dato y es 0<n<=1",
		"porcentaje_xp_nivel=%f" % pct_xp)


# --- (b) victoria por cada senda ------------------------------------------

## Entrega la misión final de una senda de verdad — por el `QuestLog` de la
## partida, con su cadena de prerrequisitos — y mira qué pasa. Esta es la
## prueba de que la victoria sale de la lógica de misiones y no de un `if` en la
## UI.
func _test_victoria_por_senda() -> void:
	for s in RP.sendas():
		var mid: String = RP.mision_de_senda(s)
		_test_victoria_de_senda(s, mid)


func _test_victoria_de_senda(s: String, mid: String) -> void:
	var p: Player = _nuevo_jugador()
	var res: Object = RP.new()
	var recibido: Array[String] = []
	res.connect("victoria", func(x: String) -> void: recibido.append(x))
	res.configurar(p, QL.new(), null)
	res.configurar(p, _log_con_final_entregada(mid), null)

	_chk(res.call("hay_victoria"), "b1[%s]: la partida termina" % s, "estado tras entregar")
	_chk(str(res.get("senda")) == s, "b2[%s]: con la senda correcta" % s,
		"senda=%s" % str(res.get("senda")))
	_chk(recibido.size() == 1, "b3[%s]: la señal victoria se emitió UNA vez" % s,
		"veces=%d" % recibido.size())
	_chk(recibido.size() > 0 and recibido[0] == s, "b4[%s]: la señal lleva la senda" % s,
		str(recibido))

	# Idempotente: el log emite `cambiada` muchas veces (aceptar, matar, hablar)
	# y recargar el guardado también pasa por acá. Un final que se reemita
	# reiniciaría la pantalla de fin mientras el jugador la está leyendo.
	res.call("_revisar_victoria")
	res.call("_revisar_victoria")
	_chk(recibido.size() == 1, "b5[%s]: el final no se reemite" % s,
		"veces=%d" % recibido.size())
	_basura.append(p)


## Un `QuestLog` con la cadena de prerrequisitos hasta la misión final, y esa
## misión final en "lista". Se construye con el `cargar_estado` del propio
## `QuestLog` (su API pública de restauración), no metiendo a mano en su
## `_estados`: tocar el estado privado desde un test es como nace el bug de que el
## test pasa y el juego no.
func _log_con_final_entregada(mid: String) -> Object:
	var log: Object = QL.new()
	var cadena: Array[String] = []
	# La cadena real: desde la misión hasta el final, para que `requiere`
	# quede satisfecho de verdad.
	var actual: String = mid
	var guarda: int = 0
	while actual != "" and guarda < 30:
		guarda += 1
		cadena.push_front(actual)
		actual = str(QDB.obtener(actual).get("requiere", ""))
	var misiones: Dictionary = {}
	for qid in cadena:
		# "entregada" para los prerrequisitos, "lista" para la última: es el
		# estado que hace que `entregar()` la acepte.
		misiones[qid] = {"estado": "lista", "progreso": []}
	log.call("cargar_estado", {"version": 1, "misiones": misiones})
	# Entregar de verdad, por la API de la partida.
	var p: Player = _nuevo_jugador()
	log.call("entregar", mid, p)
	_basura.append(p)
	return log


# --- (c)(d) derrota y su coste --------------------------------------------

## El caso que más se nota jugando: morir tiene que costar Y tiene que abrir
## una pantalla. Las dos mitades, en el mismo signal.
func _test_derrota_y_coste() -> void:
	var p: Player = _nuevo_jugador()
	p.ganar_oro(1000)
	# Nivel 5 con XP a mitad de camino: `Formulas.xp_for_level(5)` = 800.
	p.nivel = 5
	p.xp_actual = FM.xp_for_level(5) + 50
	var xp_en_nivel: int = p.xp_actual - FM.xp_for_level(5)

	var res: Object = RP.new()
	var r: RespawnHeros = RH.new()
	root.add_child(r)
	_basura.append(r)
	res.configurar(p, QL.new(), r)
	r.registrar_ciudad("origen", Vector3(0.0, 0.0, 0.0), 0.0)
	r.configurar(p, null)
	p.anclar_en_ciudad(Vector3(0.0, 0.0, 0.0), 0.0)

	var avisos: Array = []
	res.connect("muerte_registrada", func(c: Dictionary) -> void: avisos.append(c))

	var pct_oro: float = float(RP.datos_derrota().get("porcentaje_oro", 0.1))
	var pct_xp: float = float(RP.datos_derrota().get("porcentaje_xp_nivel", 1.0))
	var oro_esperado: int = int(floorf(1000.0 * pct_oro))
	var xp_esperado: int = int(floorf(float(xp_en_nivel) * pct_xp))

	p.take_damage(999999.0, null)

	_chk(not p.esta_vivo(), "c1: el héroe murió", "")
	_chk(avisos.size() == 1, "c2: la muerte abre la pantalla de derrota (una vez)",
		"avisos=%d" % avisos.size())
	_chk(int(res.get("muertes")) == 1, "c3: la muerte se cuenta", "muertes=%d" % int(res.get("muertes")))
	_chk(bool(res.get("derrota_pendiente")), "c4: queda una derrota pendiente de resolver", "")

	# El coste sale del DATO, no de una constante en el código.
	_chk(p.oro == 1000 - oro_esperado, "d1: el oro perdido viene del porcentaje del dato",
		"oro=%d, esperado=%d" % [p.oro, 1000 - oro_esperado])
	_chk(p.xp_actual == FM.xp_for_level(5), "d2: el XP perdido sale del dato y del nivel",
		"xp=%d, esperado=%d" % [p.xp_actual, FM.xp_for_level(5)])

	# LA REGLA QUE IMPORTA: morir no hace bajar de nivel.
	_chk(p.nivel == 5, "d3: morir NO hace bajar de nivel",
		"nivel=%d" % p.nivel)
	_chk(p.xp_actual >= FM.xp_for_level(p.nivel),
		"d4: el XP nunca queda por debajo de lo que cuesta el nivel",
		"xp=%d < piso=%d" % [p.xp_actual, FM.xp_for_level(p.nivel)])
	_chk(xp_esperado > 0, "d5: el cálculo de prueba perdió algo de XP",
		"xp_esperado=%d" % xp_esperado)

	# Y el respawn está en punto: el héroe NO se revivió solo, porque la
	# pantalla de derrota está esperando que el jugador elija.
	_chk(r.suspendido(), "c5: al morir, el respawn queda en punto", "suspendido=%s" % str(r.suspendido()))

	# El coste se mira en el aviso que recibio la UI.
	if avisos.size() > 0:
		var c: Dictionary = avisos[0]
		_chk(int(c.get("oro", -1)) == oro_esperado, "c6: el aviso lleva el oro perdido",
			str(c))
		_chk(int(c.get("xp", -1)) == xp_esperado, "c7: el aviso lleva el XP perdido",
			str(c))

	# El `Player` sin penalidad es de la FASE 51; el del `perder_oro` tiene que
	# llevar a 0 sin volverse negativo, y devolver lo que se llevó.
	var oro_antes: int = p.oro
	var llevado: int = p.perder_oro(999999)
	_chk(llevado == oro_antes, "d6: perder_oro se lleva lo que hay y no más",
		"llevo=%d, habia=%d" % [llevado, oro_antes])
	_chk(p.oro == 0, "d7: el oro no queda en negativo", "oro=%d" % p.oro)
	_chk(p.perder_oro(500) == 0, "d8: perder_oro sin oro no inventa saldo", "")
	_chk(p.perder_xp(999999) == 0, "d9: perder_xp respeta el piso del nivel",
		"nivel=%d xp=%d" % [p.nivel, p.xp_actual])

	_basura.append(p)


# --- (e) no se cobra dos veces -------------------------------------------

## El doble clic en "Revivir" es el bug más fácil de escribir y el más caro: dos
## teletransportes, dos veces el coste. Y `revivir()` sin una muerte pendiente
## tiene que ser un no-op.
func _test_no_se_cobra_dos_veces() -> void:
	var p: Player = _nuevo_jugador()
	p.ganar_oro(1000)
	p.nivel = 5
	p.xp_actual = FM.xp_for_level(5) + 50

	var res: Object = RP.new()
	var r: RespawnHeros = RH.new()
	root.add_child(r)
	_basura.append(r)
	res.configurar(p, QL.new(), r)
	r.configurar(p, null)
	p.anclar_en_ciudad(Vector3.ZERO, 0.0)

	var revividas: Array = []
	res.connect("revivido", func(c: Dictionary) -> void: revividas.append(c))

	p.take_damage(999999.0, null)
	var oro_tras_morir: int = p.oro
	var xp_tras_morir: int = p.xp_actual

	# Doble clic: el segundo tiene que ser no-op.
	res.call("revivir")
	res.call("revivir")
	res.call("revivir")
	_chk(revividas.size() == 1, "e1: tres revivir() seguidos solo revive una vez",
		"veces=%d" % revividas.size())
	_chk(p.esta_vivo(), "e2: el héroe queda vivo", "")
	_chk(not r.suspendido(), "e3: el respawn vuelve a estar operativo", "")
	_chk(p.oro == oro_tras_morir, "e4: el coste NO se cobra dos veces (oro)",
		"oro=%d vs %d" % [p.oro, oro_tras_morir])
	_chk(p.xp_actual == xp_tras_morir, "e5: el coste NO se cobra dos veces (XP)",
		"xp=%d vs %d" % [p.xp_actual, xp_tras_morir])

	# Un `revivir()` sin muerte pendiente (por ejemplo si algo lo llama por
	# error) no hace nada.
	var oro: int = p.oro
	var otra: Dictionary = res.call("revivir")
	_chk(otra.is_empty(), "e6: revivir() sin muerte pendiente es no-op", str(otra))
	_chk(p.oro == oro, "e7: y no cobra nada", "oro=%d vs %d" % [p.oro, oro])

	_basura.append(p)


# --- (f) la arena no es derrota de partida --------------------------------

## La Arena tiene su propia derrota por oleada y su propio trofeo. Si el
## sistema de derrota de partida también le cobrara el XP y el oro, cada muerte
## en la arena costaría el doble: una vez la arena y otra la partida.
func _test_la_arena_no_es_derrota() -> void:
	var p: Player = _nuevo_jugador()
	p.ganar_oro(1000)
	p.nivel = 5
	p.xp_actual = FM.xp_for_level(5) + 50

	var res: Object = RP.new()
	var r: RespawnHeros = RH.new()
	root.add_child(r)
	_basura.append(r)
	res.configurar(p, QL.new(), r)
	r.configurar(p, null)
	p.anclar_en_ciudad(Vector3.ZERO, 0.0)
	# Esto es lo que hace `Arena.iniciar()`: pone a punto el respawn.
	r.suspender(true)

	var avisos: Array = []
	res.connect("muerte_registrada", func(c: Dictionary) -> void: avisos.append(c))
	p.take_damage(999999.0, null)

	_chk(avisos.is_empty(), "f1: morir en la arena NO abre la pantalla de derrota",
		"avisos=%d" % avisos.size())
	_chk(int(res.get("muertes")) == 0, "f2: la muerte de la arena no cuenta como muerte de partida",
		"muertes=%d" % int(res.get("muertes")))
	_chk(p.oro == 1000, "f3: la arena no cobra oro de partida", "oro=%d" % p.oro)
	_chk(p.xp_actual == FM.xp_for_level(5) + 50, "f4: la arena no cobra XP de partida",
		"xp=%d" % p.xp_actual)
	_basura.append(p)


# --- (g) persistencia -----------------------------------------------------

## El resultado de la partida viaja en el guardado. Y sobre todo: CARGAR una
## partida ya ganada no pierde el final, que es el bug que hace que "terminar
## el juego" sea un tramite que se deshace al guardar.
func _test_persistencia() -> void:
	# (g.1) el bloque viaja por el `SaveSystem` de verdad, a disco y de vuelta.
	SaveSystem.ruta = RUTA
	_limpiar_archivos()

	var p: Player = _nuevo_jugador()
	p.ganar_oro(500)
	p.nivel = 20
	var sv: Object = SS.new()
	sv.set("jugador", p)
	var res: Object = RP.new()
	sv.set("resultado", res)
	res.configurar(p, _log_con_final_entregada(RP.mision_de_senda(RP.SENDA_LIBERTY)), null)
	_chk(sv.call("guardar"), "g1: el guardado con el bloque 'resultado' se escribe", "")

	# El bloque está EN el archivo, con su versión.
	var crudo: Variant = JSON.parse_string(FileAccess.get_file_as_string(RUTA))
	_chk(crudo is Dictionary, "g2: el archivo es un diccionario", str(typeof(crudo)))
	if crudo is Dictionary:
		var bloque: Variant = (crudo as Dictionary).get("resultado", null)
		_chk(bloque is Dictionary, "g3: el bloque 'resultado' está en el archivo", str(bloque))
		if bloque is Dictionary:
			_chk(int((bloque as Dictionary).get("version", 0)) == RP.SAVE_VERSION,
				"g4: el bloque va versionado", "v=%d" % int((bloque as Dictionary).get("version", 0)))
			_chk(str((bloque as Dictionary).get("senda", "")) == RP.SENDA_LIBERTY,
				"g5: el archivo recuerda la senda", str(bloque))

	# (g.2) cargar en un sistema NUEVO conserva el resultado. Un `SaveSystem`
	# distinto, como el de la sesión que arranca después de "Continuar".
	var p2: Player = _nuevo_jugador()
	var sv2: Object = SS.new()
	sv2.set("jugador", p2)
	_chk(sv2.call("cargar"), "g6: una partida guardada se carga", "")

	# Ojo acá: el `SaveSystem` CARGA y RESTAURA el resultado en SU PROPIA
	# instancia. Un sistema de partida nuevo tiene que TOMAR esa instancia
	# (como hace el demo), no crear otra: si creara otra, el resultado
	# cargado se quedaría en el `SaveSystem` y nadie lo miraría.
	var res2: Object = sv2.get("resultado")
	_chk(res2 != null, "g7: el SaveSystem tiene el bloque resultado", "")
	if res2 != null:
		_chk(bool(res2.call("hay_victoria")), "g8: recargar NO pierde la victoria",
			"senda=%s" % str(res2.get("senda")))
		_chk(str(res2.get("senda")) == RP.SENDA_LIBERTY, "g9: y conserva la senda", "")
		# Y el `reanudar_tras_carga` es lo que hace que el PanelFinal se abra.
		var reabrio: Array = []
		res2.connect("victoria", func(x: String) -> void: reabrio.append(x))
		res2.call("reanudar_tras_carga")
		_chk(reabrio.size() == 1, "g10: reanudar_tras_carga() reabre el final",
			"veces=%d" % reabrio.size())
		_basura.append(p2)

	# (g.3) un guardado VIEJO (sin el bloque) es una partida en curso. Todos
	# los guardados que existen en el mundo son de antes de esta fase, así que
	# esto NO es un caso teórico: es el caso de cada jugador que vuelve.
	var res3: Object = RP.new()
	res3.call("cargar_estado", {})
	_chk(not bool(res3.call("hay_victoria")), "g11: un guardado sin el bloque es partida en curso", "")
	_chk(str(res3.get("senda")) == "", "g12: y no tiene senda", "")
	_basura.append(res3)

	# (g.4) una derrota a medio resolver NO se reabre al cargar: el coste ya se
	# cobró y está en el guardado (el oro y el XP del jugador). Reabrir el
	# panel sobre un héroe con la vida llena sería mentirle al jugador sobre
	# lo que ya pagó. Lo que sí sobrevive es el conteo.
	var res4: Object = RP.new()
	res4.set("muertes", 7)
	res4.call("cargar_estado", {
		"version": RP.SAVE_VERSION, "senda": "", "terminada": false,
		"muertes": 7, "derrota_pendiente": true, "ultimo_coste": {"oro": 30, "xp": 200},
	})
	_chk(not bool(res4.get("derrota_pendiente")), "g13: la derrota a medio resolver se cierra al cargar", "")
	_chk(int(res4.get("muertes")) == 7, "g14: y el conteo de muertes sobrevive",
		"muertes=%d" % int(res4.get("muertes")))
	_chk(int((res4.get("ultimo_coste") as Dictionary).get("oro", 0)) == 30,
		"g15: y el coste de la última muerte queda registrado", str(res4.get("ultimo_coste")))

	SaveSystem.ruta = ""
	_limpiar_archivos()
	_basura.append(p)
	_basura.append(p2)


func _limpiar_archivos() -> void:
	for ruta in [RUTA, RUTA + ".tmp", RUTA + ".bak"]:
		if FileAccess.file_exists(ruta):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(ruta))


# --- (h) los paneles se abren con la SEÑAL y dibujan el dato --------------

## Un panel que existe y tiene sus botones, pero no está suscrito a nada, no
## es una pantalla. Por eso estos dos tests miran `aperturas()` después de mover
## el DATO (que es lo que la especificación §9.5 llama "mover el dato y ver que
## la UI se mueve").
func _test_paneles() -> void:
	# El final: la señal abre el panel y el texto sale del dato.
	var p: Player = _nuevo_jugador()
	var res: Object = RP.new()
	var panel: CanvasLayer = PF.new()
	root.add_child(panel)
	_basura.append(panel)
	panel.call("vigilar", res)
	_chk(not panel.visible, "h1: el PanelFinal nace cerrado (lección 11)", "")

	for s in RP.sendas():
		var res2: Object = RP.new()
		var panel2: CanvasLayer = PF.new()
		root.add_child(panel2)
		_basura.append(panel2)
		panel2.call("vigilar", res2)
		res2.call("forzar_victoria", s)
		var final: Dictionary = RP.final_de(s)
		var esperado: String = str(final.get("titulo", ""))
		var encontrado: String = _texto_del_panel(panel2)
		_chk(panel2.visible, "h2[%s]: el PanelFinal se abre con la victoria" % s, "")
		_chk(esperado != "" and esperado in encontrado,
			"h3[%s]: dibuja el TÍTULO del dato" % s,
			"buscaba '%s' en '%s'" % [esperado, encontrado])
		var cuerpo: String = str(final.get("cuerpo", ""))
		var trozo: String = cuerpo.substr(0, mini(24, cuerpo.length()))
		_chk(trozo != "" and trozo in encontrado, "h4[%s]: dibuja el CUERPO del dato" % s,
			"buscaba '%s'" % trozo)
		var cierre: String = str(final.get("cierre", ""))
		_chk(cierre != "" and cierre.substr(0, mini(20, cierre.length())) in encontrado,
			"h5[%s]: dibuja el cierre del dato" % s, "")
		_chk(str(panel2.call("senda_mostrada")) == s, "h6[%s]: sabe qué senda muestra" % s, "")

	# Y el NG+: el botón existe y dice por qué no se puede.
	_chk_ngplus(panel)
	_basura.append(p)


func _chk_ngplus(panel: CanvasLayer) -> void:
	# Sin partida en el nivel del tope, el NG+ NO se ofrece. Y el motivo está
	# escrito: un botón muerto sin explicación es peor que un botón que no
	# existe.
	SaveSystem.ruta = ""
	var disponible: bool = bool(panel.call("ngplus_disponible"))
	_chk(not disponible, "h7: sin partida guardada el NG+ no se ofrece", "")
	var motivo: String = str(panel.call("motivo_ngplus"))
	_chk(motivo != "", "h8: y el panel explica por qué", "motivo vacío")
	_chk(str(NuevoJuegoPlus.tope_nivel()) in motivo, "h9: el motivo dice el nivel que hace falta",
		"motivo='%s'" % motivo)


## Todo el texto que el panel está mostrando, para poder buscarlo. Sin esto el
## test tendría que adivinar el nombre de cada `Label`, y ese nombre es un
## detalle de implementación que cambia con cada retoque del panel.
func _texto_del_panel(panel: Node) -> String:
	var salida: String = ""
	for n in _todos(panel):
		if n is Label:
			salida += "\n" + (n as Label).text
	return salida


func _todos(n: Node) -> Array:
	var out: Array = []
	var cola: Array = [n]
	while not cola.is_empty():
		var cur: Node = cola.pop_back()
		out.append(cur)
		for c in cur.get_children():
			cola.append(c)
	return out


# --- (i) LA PRUEBA DE QUE ESTÁ CONECTADO ---------------------------------

## POR QUÉ ESTE BLOQUE ESTÁ SEPARADO Y AL FINAL: los ocho anteriores pasanían
## igual, completos, si la función que instala esto en la partida no se llamara
## NUNCA. Ya paso cuatro veces en este proyecto (MASTER_SPEC §2487-2493) y la
## quinta esta escrita y no va a ser distinta: por eso esto carga la ESCENA REAL
## y mira qué hay adentro, en vez de montar el sistema en su propia escena y
## preguntarse a sí mismo.
func _test_esta_conectado_en_la_partida() -> void:
	var demo: Node = _demo
	_chk(demo != null, "i1: la escena de la partida se instancio", "")

	var sistemas: Object = _sistemas(demo)
	_chk(sistemas != null, "i3: la partida tiene el contenedor de sistemas", "")
	if sistemas == null:
		return
	var ids: Array = sistemas.call("ids")
	for id in [&"resultado_partida", &"panel_final", &"panel_derrota"]:
		_chk(ids.has(id), "i4: en la partida esta registrado '%s'" % id,
			"hay: %s" % str(ids))

	# LA CONEXION DE VERDAD, que es lo que ningun test por sistema comprueba:
	# el PanelFinal se ABRE cuando el sistema de la partida declara la
	# victoria. Si el panel no estuviera suscrito a la senal -porque el
	# `vigilar()` no se llamo, o se llamo con otro sistema, o la conexion se
	# perdio- `aperturas()` se queda en 0.
	var res: Object = _por_id(demo, &"resultado_partida")
	var pf: Object = _por_id(demo, &"panel_final")
	var pd: Object = _por_id(demo, &"panel_derrota")
	_chk(res != null, "i5: el sistema de resultado esta en la partida", "")
	_chk(pf != null, "i5b: el PanelFinal esta en la partida", "")
	_chk(pd != null, "i6: el PanelDerrota esta en la partida", "")
	if res == null or pf == null:
		return

	var antes: int = int(pf.call("aperturas"))
	res.call("forzar_victoria", RP.SENDA_LIBERTY)
	_chk(int(pf.call("aperturas")) == antes + 1,
		"i7: el PanelFinal de la PARTIDA se abre al declarar la victoria",
		"aperturas %d -> %d" % [antes, int(pf.call("aperturas"))])
	_chk(pf.get("visible"), "i8: y queda visible", "")
	var esperado: String = str(RP.final_de(RP.SENDA_LIBERTY).get("titulo", ""))
	_chk(esperado in _texto_del_panel(pf), "i9: y dibuja el titulo del final",
		"buscaba '%s'" % esperado)
	pf.call("cerrar")
	_chk(not pf.get("visible"), "i10: cerrar() lo esconde", "")

	# Los dos paneles nacen cerrados y corren con el arbol pausado (el final
	# pausa el juego: si no corrieran con ALWAYS, no recibirian ni el raton).
	if pd != null:
		_chk(not pd.get("visible"), "i11: el PanelDerrota de la partida nace cerrado", "")
		_chk(pd.get("process_mode") == Node.PROCESS_MODE_ALWAYS,
			"i13: el PanelDerrota corre con el arbol pausado", "")
	_chk(pf.get("process_mode") == Node.PROCESS_MODE_ALWAYS,
		"i12: el PanelFinal corre con el arbol pausado", "")

	# Y el NG+ no se ofrece en una partida recien empezada: un boton de NG+
	# que no hace nada en la pantalla de final seria la peor forma de cerrar
	# el juego.
	SaveSystem.ruta = ""
	_chk(not bool(pf.call("ngplus_disponible")),
		"i14: el NG+ no se ofrece en una partida nueva", "")


func _buscar_jugador(n: Node) -> Node:
	for x in _todos(n):
		if String(x.name) == "Player":
			return x
	return null


func _sistemas(n: Node) -> Object:
	for x in _todos(n):
		if x is Systems:
			return x
	return null


## El sistema con esa `system_id`, donde esté. Primero pregunta al
## CONTENEDOR (`Systems.obtener`), y solo después busca un `system_id` en los
## nodos: `ResultadoPartida` es un `RefCounted` y no cuelga del árbol, así que
## una búsqueda por nodos —que es lo que hacía la primera versión de esta
## función— lo declararía ausente siendo que está registrado. Es el mismo
## motivo por el que el smoke de la escena usa `Systems.ids()` y no adivina
## `_registros`: un sistema puede estar registrado y no ser un nodo.
func _por_id(n: Node, id: StringName) -> Object:
	if n == null:
		return null
	var sistemas: Object = _sistemas(n)
	if sistemas != null:
		var por_id: Variant = sistemas.call("obtener", id)
		if por_id != null and is_instance_valid(por_id):
			return por_id
	if "system_id" in n and n.get("system_id") == id:
		return n
	for x in _todos(n):
		if "system_id" in x and x.get("system_id") == id:
			return x
	return null


# --- helpers --------------------------------------------------------------

func _nuevo_jugador() -> Player:
	var sb: StatBlock = SB.new(10, 8, 6, 4)
	var p: Player = PL.new(sb)
	p.name = "HeroeTest"
	root.add_child(p)
	return p
