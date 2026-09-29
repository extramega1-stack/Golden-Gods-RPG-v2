extends SceneTree
## Bloque 68 (conectado) — el NG+ de verdad: reset, persistencia del
## prestigio y bonificación aplicada al StatBlock.
##
## POR QUÉ ESTE ARCHIVO: `tests/test_bloque68_impacto.gd` ya probaba que
## `NuevoJuegoPlus.multiplicador_prestigio(3) > 1.0`. Eso es cierto y no
## sirve de nada: la función era HUÉRFANA, no había reset, ni guardado, ni
## panel, y el juego no tenía forma de jugar un NG+. Un test que solo mira la
## fórmula no habría detectado NINGUNO de los tres bugs que importan aquí:
##
## 1. el prestigio que se pierde al reiniciar (el clásico: el reset escribe
##    una partida nueva y se lleva el NG+ por delante),
## 2. los multiplicadores que se calculan y no se aplican (el StatBlock del
##    jugador intacto: la UI miente),
## 3. la UI que no se mueve (conectar la señal dentro del test y no mover el
##    dato: el test pasa y el panel está congelado).
##
## Por eso los tres se comprueban de verdad: leyendo el `partida.json` del
## disco, midiendo el `StatBlock` antes y después, y moviendo el estado para
## ver el texto cambiar.

const PL: GDScript = preload("res://scripts/player/player.gd")
const SS: GDScript = preload("res://scripts/save/save_system.gd")
const PT: GDScript = preload("res://scripts/progresion/panel_ngplus.gd")
const TT: GDScript = preload("res://scripts/ui/pantalla_titulo.gd")

const RUTA: String = "user://partida.json"
const RUTA_BAK: String = "user://partida.json.bak"
const RUTA_TMP: String = "user://partida.json.tmp"

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] NG+ — reset, prestigio y bonus al StatBlock")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_limpiar()
	_test_datos()
	_test_estado()
	_test_bonus_al_statblock()
	_test_reset_conserva_prestigio()
	_test_carga_aplica_el_bonus()
	_test_panel_se_mueve()
	_test_titulo()
	DatosSesion.limpiar()
	PilaUI.limpiar()
	_limpiar()
	print("[TEST] ngplus_flujo: %d ok, %d fallos" % [_ok, _fallos])
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


func _jugador(nivel: int = 1) -> Player:
	var p: Player = PL.new()
	p.fijar_identidad("Héroe", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	p.nivel = maxi(1, nivel)
	p.stats.recalc()
	return p


## Deja una partida guardada de un personaje en el tope del mundo, con oro,
## inventario y todo lo demás: el estado que el jugador tiene justo antes de
## pulsar "Nuevo Game+".
func _partida_en_el_tope() -> Dictionary:
	var j: Player = _jugador(NuevoJuegoPlus.tope_nivel())
	j.ganar_oro(1234)
	j.inventario = Inventario.new()
	j.inventario.agregar("pocion_vida", 3)
	var s: SaveSystem = SS.new()
	s.jugador = j
	s.enemigos = []
	s.arboles = null
	s.ngplus.prestigio = 0
	s.ngplus.ciclo = 0
	if not s.guardar():
		_chk(false, "setup: el guardado de partida en el tope funciona")
		return {}
	return _leer_save()


func _leer_save() -> Dictionary:
	if not FileAccess.file_exists(RUTA):
		return {}
	var crudo: Variant = JSON.parse_string(FileAccess.get_file_as_string(RUTA))
	if crudo is Dictionary:
		return crudo
	return {}


func _nivel_de(datos: Dictionary) -> int:
	var dj: Dictionary = datos.get("jugador", {})
	var ent: Dictionary = dj.get("entidad", {})
	return int(ent.get("nivel", 0))


func _prestigio_de(datos: Dictionary) -> int:
	var ng: Dictionary = datos.get("ngplus", {})
	return int(ng.get("prestigio", -1))


func _ciclo_de(datos: Dictionary) -> int:
	var ng: Dictionary = datos.get("ngplus", {})
	return int(ng.get("ciclo", -1))


func _limpiar() -> void:
	for r in [RUTA, RUTA_BAK, RUTA_TMP]:
		DirAccess.remove_absolute(str(r))


# --- (1) los datos: el prestigio por vuelta y el bono al personaje --------

func _test_datos() -> void:
	_chk(NuevoJuegoPlus.prestigio_ganado(0) == 1, "el primer ciclo da 1 de prestigio",
		str(NuevoJuegoPlus.prestigio_ganado(0)))
	_chk(NuevoJuegoPlus.prestigio_ganado(3) == 4, "el cuarto ciclo da 4 (triangular)",
		str(NuevoJuegoPlus.prestigio_ganado(3)))
	_chk(NuevoJuegoPlus.bonificacion_stats(0).is_empty(),
		"prestigio 0 no da bonificación (no cinco ceros)", "")
	var bon: Dictionary = NuevoJuegoPlus.bonificacion_stats(3)
	_chk(is_equal_approx(float(bon.get("ataque", 0.0)), 0.15),
		"3 de prestigio = +15% de ataque", str(bon.get("ataque", -1.0)))
	_chk(bon.has("vida_max") and bon.has("defensa"),
		"la bonificación toca vida y defensa también", str(bon.keys()))
	_chk(is_equal_approx(float(NuevoJuegoPlus.bonificacion_stats(1000).get("ataque", 0.0)),
		NuevoJuegoPlus.BONO_MAX),
		"la bonificación tiene tope: el NG+ no se rompe en 20 vueltas", "")


# --- (2) el estado: ciclo, prestigio y viaje en el diccionario ----------

func _test_estado() -> void:
	var e: EstadoNgPlus = EstadoNgPlus.new()
	_chk(e.ciclo == 0 and e.prestigio == 0, "el NG+ arranca en la primera vuelta", "")
	_chk(not e.puede_prestigiar(69), "en el nivel 69 no se prestigia", "")
	_chk(e.puede_prestigiar(NuevoJuegoPlus.tope_nivel()),
		"en el tope del mundo sí", "")
	_chk(e.prestigiar(10) == -1, "prestigiar por debajo del tope no suma", "")
	_chk(e.ciclo == 0 and e.prestigio == 0, "y no toca el estado", "")

	var ganados: Array[int] = []
	for _i in range(3):
		ganados.append(e.prestigiar(NuevoJuegoPlus.tope_nivel()))
	_chk(ganados == [1, 2, 3], "tres ciclos dan 1+2+3 de prestigio", str(ganados))
	_chk(e.ciclo == 3, "el ciclo cuenta las vueltas", str(e.ciclo))
	_chk(e.prestigio == 6, "el prestigio es la suma de las vueltas", str(e.prestigio))
	_chk(is_equal_approx(e.multiplicador_xp(), 1.9),
		"6 de prestigio = x1.9 de XP", str(e.multiplicador_xp()))
	_chk(e.afijos_extra() == 2, "6 de prestigio = 2 afijos extra", str(e.afijos_extra()))

	# Un save viejo, sin bloque "ngplus", es el juego normal.
	var viejo: EstadoNgPlus = EstadoNgPlus.desde_dict({})
	_chk(viejo.prestigio == 0 and viejo.ciclo == 0, "un save viejo carga sin NG+", "")
	_chk(is_equal_approx(viejo.multiplicador_xp(), 1.0), "y con x1.0 de XP", "")

	var vuelta: EstadoNgPlus = EstadoNgPlus.desde_dict(e.to_dict())
	_chk(vuelta.prestigio == e.prestigio and vuelta.ciclo == e.ciclo,
		"el estado hace viaje redondo por el save", "")
	_chk(vuelta.to_dict().has("ciclo"), "el save guarda también el ciclo", "")


# --- (3) EL BUG DEL SEGUNDO TIPO: el bonus tiene que estar en el StatBlock --

func _test_bonus_al_statblock() -> void:
	var j: Player = _jugador(1)
	var ataque_antes: float = j.stats.ataque
	var vida_antes: float = j.stats.vida_max
	var defensa_antes: float = j.stats.defensa
	_chk(not j.stats.has_mod(EstadoNgPlus.PREFIJO_MOD + "ataque"),
		"el jugador nuevo no tiene mods de NG+", "")

	var e: EstadoNgPlus = EstadoNgPlus.new()
	e.prestigio = 4
	e.aplicar_a(j.stats)
	_chk(j.stats.has_mod(EstadoNgPlus.PREFIJO_MOD + "ataque"),
		"el NG+ pone un mod propio en el StatBlock", "")
	_chk(is_equal_approx(j.stats.ataque, ataque_antes * 1.2),
		"4 de prestigio = +20% de ataque REAL", "%f vs %f" % [j.stats.ataque, ataque_antes * 1.2])
	_chk(is_equal_approx(j.stats.vida_max, vida_antes * 1.12),
		"y +12% de vida máxima", "%f vs %f" % [j.stats.vida_max, vida_antes * 1.12])
	_chk(is_equal_approx(j.stats.defensa, defensa_antes * 1.08),
		"y +8% de defensa", "%f vs %f" % [j.stats.defensa, defensa_antes * 1.08])

	# Idempotente: aplicarlo dos veces NO duplica el bono. Sin esto, cada
	# recarga de partida dejaría al héroe inflado.
	e.aplicar_a(j.stats)
	_chk(is_equal_approx(j.stats.ataque, ataque_antes * 1.2),
		"aplicar dos veces no duplica el bono", str(j.stats.ataque))

	e.quitar_de(j.stats)
	_chk(is_equal_approx(j.stats.ataque, ataque_antes), "quitar lo deja como estaba",
		str(j.stats.ataque))
	_chk(not j.stats.has_mod(EstadoNgPlus.PREFIJO_MOD + "ataque"),
		"y no deja mods colgando", "")

	# Prestigio 0 = el juego normal, sin dejar mods de valor 0 por el medio.
	var e0: EstadoNgPlus = EstadoNgPlus.new()
	e0.aplicar_a(j.stats)
	_chk(is_equal_approx(j.stats.ataque, ataque_antes),
		"prestigio 0 deja el StatBlock intacto", str(j.stats.ataque))
	_chk(not j.stats.has_mod(EstadoNgPlus.PREFIJO_MOD + "ataque"),
		"y sin mods de valor 0", "")


# --- (4) EL BUG DEL PRIMER TIPO: el prestigio tiene que sobrevivir --------

func _test_reset_conserva_prestigio() -> void:
	_limpiar()
	_chk(not SaveSystem.puede_nuevo_game_plus(),
		"sin partida no se puede hacer NG+", "")
	_chk(not SaveSystem.reiniciar_para_ngplus(),
		"y el reset sin partida no inventa una", "")
	_chk(not FileAccess.file_exists(RUTA), "ni deja un save por el camino", "")

	var tope: Dictionary = _partida_en_el_tope()
	_chk(tope.has("jugador"), "setup: hay partida en el tope", "")
	_chk(_nivel_de(tope) == NuevoJuegoPlus.tope_nivel(), "setup: nivel en el tope",
		str(_nivel_de(tope)))
	_chk(SaveSystem.puede_nuevo_game_plus(), "en el tope se puede hacer NG+", "")
	_chk(SaveSystem.nivel_guardado() == NuevoJuegoPlus.tope_nivel(),
		"el título puede leer el nivel del save", str(SaveSystem.nivel_guardado()))

	_chk(SaveSystem.reiniciar_para_ngplus(), "el reset arranca la vuelta nueva", "")
	var tras: Dictionary = _leer_save()
	_chk(tras.has("jugador"), "el save sigue existiendo (no se borra a pelo)", "")
	# EL ASSERT CENTRAL DE ESTE TEST.
	_chk(_prestigio_de(tras) == 1,
		"EL PRESTIGIO SOBREVIVE AL RESET", "quedó %d" % _prestigio_de(tras))
	_chk(_ciclo_de(tras) == 1, "y el ciclo sube a 1", str(_ciclo_de(tras)))
	_chk(SaveSystem.estado_ngplus().prestigio == 1,
		"el estado del NG+ se relee del disco con el prestigio", "")

	_chk(_nivel_de(tras) == 1, "el personaje vuelve al nivel 1", str(_nivel_de(tras)))
	var dj: Dictionary = tras.get("jugador", {})
	_chk(int(dj.get("oro", -1)) == 0, "el oro se reinicia", str(dj.get("oro", -1)))
	_chk(not dj.has("inventario") and not dj.has("equipo"),
		"el inventario y el equipo se vacían", str(dj.keys()))
	_chk(not tras.has("inventario") and not tras.has("misiones"),
		"y no quedan bloques a medias de la vuelta anterior", str(tras.keys()))
	_chk(str(dj.get("nombre", "")) == "Héroe" and str(dj.get("clase_id", "")) == "guerrero",
		"pero el héroe conserva su identidad", str(dj.get("nombre", "")))
	var tutorial: Dictionary = tras.get("tutorial", {})
	_chk(bool(tutorial.get("hecho", false)),
		"el tutorial no se repite en la vuelta nueva", str(tutorial))

	# El mundo NO se borra: es la promesa del 68. Se comprueba con un save que
	# sí traía árboles talados y refugios.
	_limpiar()
	var con_mundo: Dictionary = _partida_en_el_tope()
	var dj_mundo: Dictionary = con_mundo.get("jugador", {})
	dj_mundo["habilidades"] = {"pesca": 420}
	con_mundo["arboles"] = {"a1": {"talado": true}}
	con_mundo["refugios"] = {"r1": {"piezas": 7}}
	_limpiar()
	_escribir(con_mundo)
	_chk(SaveSystem.reiniciar_para_ngplus(), "el reset con mundo guardado arranca", "")
	var tras2: Dictionary = _leer_save()
	var arboles: Dictionary = tras2.get("arboles", {})
	var refugios: Dictionary = tras2.get("refugios", {})
	var dj_tras2: Dictionary = tras2.get("jugador", {})
	var hab: Dictionary = dj_tras2.get("habilidades", {})
	var r1: Dictionary = refugios.get("r1", {})
	_chk(arboles.has("a1"), "el NG+ conserva los árboles talados", str(arboles))
	_chk(int(r1.get("piezas", 0)) == 7, "y los refugios con sus piezas", str(refugios))
	_chk(int(hab.get("pesca", 0)) == 420,
		"y las habilidades de recolección (el bloque 53–62 no se toca)", str(hab))
	_chk(_prestigio_de(tras2) == 1, "con el prestigio intacto en este caso también", "")

	# La segunda vuelta: el prestigio ACUMULA (triangular), no se reinicia.
	_chk(SaveSystem.nivel_guardado() == 1,
		"tras el reset el personaje está en 1, así que no se puede prestigiar aún", "")
	_chk(not SaveSystem.reiniciar_para_ngplus(),
		"no se puede cerrar un ciclo sin llegar al tope", "")
	_chk(_prestigio_de(_leer_save()) == 1,
		"y el save sigue con el prestigio intacto tras el intento fallido", "")

	# Subir el personaje al tope otra vez y cerrar el segundo ciclo. Se edita
	# el save CON `_escribir` y no con un `SaveSystem.guardar()` nuevo: un
	# SaveSystem recién creado tiene el NG+ a cero y su `guardar()` se
	 # llevaría por delante el prestigio del ciclo anterior — que es
	# exactamente el bug que este test existe para cazar.
	var j: Player = _jugador(NuevoJuegoPlus.tope_nivel())
	var en_curso: Dictionary = _leer_save()
	var dj_curso: Dictionary = en_curso.get("jugador", {})
	dj_curso["entidad"] = j.to_dict()
	_escribir(en_curso)
	_chk(SaveSystem.nivel_guardado() == NuevoJuegoPlus.tope_nivel(),
		"el título ve el nivel nuevo", str(SaveSystem.nivel_guardado()))
	_chk(SaveSystem.reiniciar_para_ngplus(), "el segundo ciclo arranca", "")
	var tras3: Dictionary = _leer_save()
	_chk(_prestigio_de(tras3) == 3,
		"dos ciclos = 3 de prestigio (1+2), NO se reinicia a 1", str(_prestigio_de(tras3)))
	_chk(_ciclo_de(tras3) == 2, "y el ciclo va por 2", str(_ciclo_de(tras3)))

	# El save se escribe por el camino ATÓMICO: existe el backup del estado
	# anterior. Un reset que borra el archivo a pelo no deja ninguno.
	_chk(FileAccess.file_exists(RUTA_BAK), "el reset deja el backup del estado bueno", "")
	_chk(not FileAccess.file_exists(RUTA_TMP), "y no deja el temporal a medias", "")


func _escribir(datos: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(RUTA, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(datos))
	f.close()


# --- (5) el camino real: cargar una partida de NG+ bonifica al héroe ------

func _test_carga_aplica_el_bonus() -> void:
	_limpiar()
	var tope: Dictionary = _partida_en_el_tope()
	var dj_tope: Dictionary = tope.get("jugador", {})
	dj_tope["entidad"] = _jugador(1).to_dict()
	tope["ngplus"] = {"prestigio": 5, "ciclo": 2}
	_escribir(tope)

	var j: Player = _jugador(1)
	var ataque_sin_bono: float = j.stats.ataque
	var s: SaveSystem = SS.new()
	s.jugador = j
	s.enemigos = []
	_chk(s.cargar(), "una partida con NG+ carga", "")
	_chk(s.ngplus.prestigio == 5 and s.ngplus.ciclo == 2,
		"el SaveSystem se queda con el NG+ del save", str(s.ngplus.prestigio))
	_chk(j.stats.has_mod(EstadoNgPlus.PREFIJO_MOD + "ataque"),
		"AL CARGAR, el StatBlock del jugador lleva el bono", "")
	_chk(j.stats.ataque > ataque_sin_bono,
		"el héroe de la partida cargada pega más que uno nuevo", str(j.stats.ataque))

	# Y vuelve a guardarlo sin perder nada (el viaje de ida y vuelta).
	_chk(s.guardar(), "el NG+ se puede volver a guardar", "")
	var re: Dictionary = _leer_save()
	_chk(_prestigio_de(re) == 5, "el prestigio sobrevive al guardado", "")
	_chk(_ciclo_de(re) == 2, "y el ciclo también", "")

	# Un save viejo, sin bloque "ngplus", no cambia los stats de nadie.
	_limpiar()
	var viejo: Dictionary = _partida_en_el_tope()
	viejo.erase("ngplus")
	_escribir(viejo)
	var j2: Player = _jugador(1)
	var s2: SaveSystem = SS.new()
	s2.jugador = j2
	s2.enemigos = []
	_chk(s2.cargar(), "un save viejo carga", "")
	_chk(s2.ngplus.prestigio == 0, "con prestige 0", "")
	_chk(not j2.stats.has_mod(EstadoNgPlus.PREFIJO_MOD + "ataque"),
		"y sin tocarle los stats al jugador", "")
	_limpiar()


# --- (6) la UI: se suscribe y SE MUEVE ----------------------------------

func _test_panel_se_mueve() -> void:
	var e: EstadoNgPlus = EstadoNgPlus.new()
	e.prestigio = 2
	e.ciclo = 1
	var panel: PanelNgPlus = PT.new()
	root.add_child(panel)
	_basura.append(panel)
	_chk(not panel.visible, "el panel de NG+ nace cerrado (lección 11)", "")

	_chk(panel.abrir(e), "el panel abre con el estado del NG+", "")
	_chk(panel.visible, "y se ve", "")
	_chk(PilaUI.cima() == panel, "el panel es la cima de la pila de UI", "")
	_chk(panel.textos().has("Ciclo 1"),
		"el panel pinta el ciclo actual", str(panel.textos()))
	_chk(panel.textos().has("2 puntos"),
		"y el prestigio acumulado", str(panel.textos()))
	_chk(panel.textos().has("x1.30"),
		"y el multiplicador de XP", str(panel.textos()))

	# EL BUG DEL TERCER TIPO: conectar la señal NO prueba nada. Hay que MOVER
	# el dato y ver que la UI se mueve sola.
	e.prestigiar(NuevoJuegoPlus.tope_nivel())
	_chk(e.prestigio == 4, "el estado se movió (2+2)", str(e.prestigio))
	_chk(panel.textos().has("Ciclo 2"),
		"la UI se enteró del cambio SIN que nadie la llame", str(panel.textos()))
	_chk(panel.textos().has("4 puntos"),
		"y el prestigio nuevo está pintado", str(panel.textos()))
	_chk(panel.textos().has("x1.60"),
		"y el multiplicador también", str(panel.textos()))
	_chk(panel.textos().has("+20%") and panel.textos().has("+12%"),
		"y el bono al personaje se ve en pantalla (ataque +20%, vida +12%)",
		str(panel.textos()))

	panel.cerrar_panel()
	_chk(not panel.visible, "el panel cierra", "")
	_chk(not e.cambiado.is_connected(panel._al_cambiar),
		"y se desuscribe (nada de signals colgando)", "")
	# Con el panel cerrado, mover el estado no debe reventar.
	e.prestigiar(NuevoJuegoPlus.tope_nivel())
	_chk(true, "mover el estado con el panel cerrado no revienta", "")
	# NOTA sobre `PilaUI.abierta() == 0`: NO se comprueba a propósito.
	# `PilaUI.cerrar()` no borra el panel de la pila (recibe el panel y no lo
	# usa), así que los 13 paneles del juego se quedan en la pila al cerrar.
	# Es un bug preexistente de `scripts/ui/pila_ui.gd`, que no es de este
	# bloque; se reporta aparte en vez de copiarlo a una aserción.


# --- (7) el título: el botón existe, se habilita y el rótulo se lee -------

func _test_titulo() -> void:
	_limpiar()
	_chk(PantallaTitulo.puede_continuar() == false,
		"sin partida no se puede continuar", "")

	var t: PantallaTitulo = TT.new()
	root.add_child(t)
	_basura.append(t)
	_chk(t.boton_ngplus() != null, "el título tiene botón de NG+", "")
	_chk(t.boton_ngplus().disabled,
		"sin partida el botón de NG+ está deshabilitado (no hay nada que prestigiar)", "")
	_chk(t.texto_estado().contains("70"),
		"y el rótulo dice cuál es la puerta de entrada", t.texto_estado())

	_limpiar()
	_partida_en_el_tope()
	t.refrescar_ngplus()
	_chk(not t.boton_ngplus().disabled,
		"con el personaje en el tope, el botón de NG+ se habilita", "")
	_chk(t.texto_estado().contains("NG+"),
		"el rótulo del título habla del NG+", t.texto_estado())

	# El flujo de verdad: el botón reinicia y deja la sesión en "continuar",
	# para que el mundo arranque desde la vuelta nueva.
	_chk(t.empezar_nuevo_game_plus(), "el título arranca el NG+ de verdad", "")
	_chk(DatosSesion.continuar, "y deja la sesión en modo continuar (el mundo carga el reset)", "")
	_chk(SaveSystem.estado_ngplus().prestigio == 1,
		"EL PRESTIGIO SIGUE VIVO DESPUÉS DEL FLUJO COMPLETO",
		str(SaveSystem.estado_ngplus().prestigio))
	_chk(t.texto_estado().contains("Ciclo 1"),
		"el rótulo ya enseña el ciclo 1 sin recargar nada", t.texto_estado())
	_chk(not SaveSystem.puede_nuevo_game_plus(),
		"y el botón se vuelve a deshabilitar hasta el próximo tope", "")

	# Sin personaje en el tope, el rótulo lo explica en vez de mentir.
	_chk(t.texto_estado().contains("70"),
		"el rótulo dice cuál es la puerta de entrada", t.texto_estado())
	_limpiar()
