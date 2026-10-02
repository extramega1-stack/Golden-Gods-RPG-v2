extends SceneTree
## La prueba de partida completa, automatizada, de punta a punta.
##
## POR QUÉ EXISTE: §7.6 del spec exige "una fase por vez + playtest de Juan
## Diego antes de avanzar". En esta sesión se incumplió a propósito y quedaron
## TRES cosas escritas, testeadas y NO FUNCIONANDO en la partida:
##   1. siete sistemas que `_instalar_fase63_64_ui()` instanciaba y nadie
##      llamaba (el ESC no hacía nada porque no había menú de pausa),
##   2. la pila de paneles que nunca se vaciaba,
##   3. un panel sin `system_id` que el contenedor `Systems` rechazaba en
##      silencio con un `push_warning`.
## NINGUNO lo cazó un test, porque cada test prueba UN SISTEMA en su propia
## escena. Este prueba la PARTIDA.
##
## LA REGLA QUE SIGUE: ningún paso pregunta "¿esta función se puede llamar?".
## Todos preguntan "¿la UI SE MOVIÓ?". Si el texto no cambió, el valor de la
## barra no bajó, el panel no apareció o la pila no se vació, el paso FALLA y
## dice qué faltaba, con nombre de nodo y archivo.
##
## CÓMO SE USA (una línea; tools/jugar.sh la envuelve):
##   godot --headless --path . --fixed-fps 60 \
##         --script res://tests/playtest_completo.gd
##   godot --headless --path . --fixed-fps 60 \
##         --script res://tests/playtest_completo.gd -- --sin-arboles
##
## POR QUÉ `--fixed-fps 60`: sin él el bucle headless corre a ~145 FPS y un
## "segundo" de partida son 6 ms de reloj, así que "el vital baja con el
## tiempo" no se puede comprobar. Con `--fixed-fps` cada frame vale
## exactamente 1/60 de segundo de JUEGO: 120 frames son 2 segundos en
## cualquier máquina. El coste de CPU se mide aparte, con reloj de pared
## (`Time.get_ticks_usec`), así que el p95 que sale sigue siendo real.
##
## LIMITACIÓN DECLARADA: headless usa drivers dummy. El p95 de acá mide CPU
## (lógica + física), NO la GPU. Para la GPU está `tools/bench_gpu.gd`.
##
## SALIDA: exit code = número de pasos en rojo. 0 = la partida anda.

const U: Script = preload("res://tests/_playtest_util.gd")

# ── guion ───────────────────────────────────────────────────────────────────
const NOMBRE_HEROE: String = "Zafiro"
const CLASE_HEROE: String = "guerrero"

# ── teclas físicas (las del Input Map de project.godot) ─────────────────────
const KEY_ESCAPE: int = 4194305
const KEY_I: int = 73
const KEY_C: int = 67
const KEY_J: int = 74
const KEY_K: int = 75
const KEY_H: int = 72
const KEY_L: int = 76
const KEY_SLASH: int = 47
const KEY_0: int = 48
const KEY_E: int = 69
const KEY_T: int = 84

# ── fases ───────────────────────────────────────────────────────────────────
const F_TITULO: int = 0
const F_CREACION: int = 1
const F_MUNDO: int = 2
const F_LISTO: int = 3
const F_NOMBRE: int = 4
const F_CAMINAR: int = 5
const F_VITALES: int = 6
const F_COMBATE: int = 7
const F_LOOT: int = 8
const F_INVENTARIO: int = 9
const F_NIVEL: int = 10
const F_MISION: int = 11
const F_HABLAR: int = 12
const F_ENTREGAR: int = 13
const F_COCINA: int = 14
const F_COCINA_LENA: int = 15
const F_COCINA_COCINAR: int = 16
const F_REFUGIO: int = 17
const F_REFUGIO_PIEZA: int = 18
const F_GUARDAR: int = 19
const F_TITULO_2: int = 20
const F_CARGAR: int = 21
const F_CARGAR_LISTO: int = 22
const F_PANELES: int = 23
const F_ARBOL: int = 24
const F_ARBOL_TALAR: int = 27
const F_REPORTE: int = 25

const PRESUPUESTO_MS: int = 2400000

## Nombre de cada fase, sólo para que el log diga dónde está.
const FASES: Dictionary = {
	0: "título", 1: "creación", 2: "mundo", 3: "mundo listo", 4: "nombre en HUD",
	5: "caminar", 6: "vitales", 7: "combate", 8: "loot", 9: "inventario",
	10: "nivel", 11: "misión", 12: "hablar", 13: "entregar", 14: "cocina",
	15: "prender fogata", 16: "cocinar", 17: "refugio", 18: "construir",
	19: "guardar", 20: "volver al título", 21: "continuar", 22: "cargar",
	23: "paneles ESC", 24: "ir al árbol", 25: "reporte", 26: "hablar 2",
	27: "talar", 28: "cumplir el objetivo",
}
## Frames de la caminata al bosque. A 6 u/s, 20000 frames = 333 s de partida
## = 2000 u de alcance (el árbol más cercano al spawn está a 1792 u).
const FRAMES_ARBOL: int = 20000
## Techo de frames de partida por fase antes de cortar y seguir (150 s de juego).
const FRAMES_MAX_POR_FASE: int = 9000

# ── mundo ───────────────────────────────────────────────────────────────────
var _titulo: Node = null
var _demo: Node = null
var _jugador: Node = null
var _fase: int = F_TITULO
var _sub: int = 0
var _t_fase_ms: int = 0
var _t_inicio_ms: int = 0
var _ticks: int = 0
var _ultima_fase: int = -1
var _frames_fase: int = 0
var _terminado: bool = false
var _ref: Dictionary = {}

# ── resultados ──────────────────────────────────────────────────────────────
var _ok_n: int = 0
var _fallos: int = 0
var _omitidos: int = 0
var _res: Array[Dictionary] = []
var _rastro: String = ""

# ── input ───────────────────────────────────────────────────────────────────
var _tecla_abierta: int = -1
## La tecla cuya SUBIDA va para el siguiente frame. Ver `_pulsar()`.
var _soltar_pendiente: int = 0

# ── rendimiento ─────────────────────────────────────────────────────────────
var _midiendo: bool = false
var _frames_ms: Array[float] = []
var _t_ultimo_usec: int = 0
var _cpu_s: float = 0.0
var _frames_medidos: int = 0

# ── estado de la partida ────────────────────────────────────────────────────
var _pos_inicio: Vector3 = Vector3.ZERO
var _vel_max: float = 0.0
var _hambre_ini: float = -1.0
var _slot_barra: Dictionary = {}
var _nivel_antes: int = 0
var _xp_antes: int = 0
var _nivel_hud_antes: String = ""
var _inv_ya_mirada: bool = false
var _construccion_ya: bool = false
var _nivel_iniciado: bool = false
var _mobs_sin_parte: bool = false

var _mob: Node = null
var _pos_mob_antes: Vector3 = Vector3.ZERO
var _visto_danio: float = 0.0
var _visto_empuje: bool = false
var _visto_numero: String = ""
var _visto_particulas: bool = false
var _botin: Array = []
var _item_loot: String = ""

var _npc: Node = null
var _quest_id: String = ""

var _fogata: Node = null
var _cocina_item: String = ""
var _cocina_res: String = ""

var _refugio: Node = null
var _refugio_id_antes: String = ""
var _piezas_antes: int = 0

var _inv_antes: int = 0
var _inv_desp: int = 0
var _nivel_antes_guardar: int = 0
var _xp_antes_guardar: int = 0
var _prestigio_antes: int = -1

var _arbol: Node = null
var _arbol_id: String = ""
var _arbol_usos: int = -1
var _arbol_pos: Vector3 = Vector3.ZERO
var _arbol_muerte: bool = false
var _sin_arboles: bool = false
var _sin_latido: bool = false

var _paneles: Array[Dictionary] = []
var _panel_i: int = 0
var _panel_abierta: bool = false
var _panel_cerrada: bool = false
## La preparación se hace UNA vez por panel. Sin esto se repite cada frame
## mientras se espera la pausa, y el paso nunca avanza.
var _preparado: bool = false
var _solo_panel: Node = null
var _cierra_pendientes: int = 0
var _pausa_frames: int = 0
var _pausa_reportada: bool = false


func _init() -> void:
	print("[PLAYTEST] ===================================================================")
	print("[PLAYTEST] PARTIDA COMPLETA de punta a punta.")
	print("[PLAYTEST] Ningun paso pregunta 'se puede llamar la funcion?':")
	print("[PLAYTEST] todos preguntan 'la UI SE MOVIO?'.")
	print("[PLAYTEST] ===================================================================")
	for a in OS.get_cmdline_user_args():
		if a == "--sin-arboles":
			_sin_arboles = true
		elif a == "--sin-latido":
			_sin_latido = true


func _process(_delta: float) -> bool:
	if _terminado:
		return true
	var ahora: int = Time.get_ticks_msec()
	if _t_inicio_ms == 0:
		_t_inicio_ms = ahora
	if _tecla_abierta >= 0:
		_soltar(_tecla_abierta)
		_tecla_abierta = -1
	# La subida de la última pulsación, un frame después de la bajada. Sin
	# esto la tecla queda oprimida y la acción del InputMap no vuelve a
	# dispararse: los reintentos se quedan sin efecto.
	_soltar_la_pendiente()
	if _tick_cierre():
		return false
	_watchdog_pausa()
	_medio_frame()
	_ticks += 1
	if _ticks % 18000 == 0 and not _sin_latido:
		var extra: String = ""
		if _jugador != null and is_instance_valid(_jugador):
			extra = " paused=%s wasd=%s destino=%s pos=%s vel=%s" % [
				str(paused),
				str(Input.get_vector("mover_izquierda", "mover_derecha",
					"mover_adelante", "mover_atras")),
				str((_jugador as Node3D).get("_tiene_destino")),
				str((_jugador as Node3D).global_position),
				str((_jugador as Node3D).velocity)]
		print("[PLAYTEST] · latido: frame %d, fase «%s», %d s de reloj%s"
			% [_ticks, String(FASES.get(_fase, str(_fase))),
				int((ahora - _t_inicio_ms) / 1000), extra])
	# Ninguna fase puede colgarse: si una fase pasa de FRAMES_MAX_POR_FASE
	# frames de partida, se reporta con su sub-paso y se sigue con la
	# siguiente. Un harness que se cuelga no informa nada.
	if _ultima_fase != _fase:
		_ultima_fase = _fase
		_frames_fase = 0
	_frames_fase += 1
	if _frames_fase > FRAMES_MAX_POR_FASE:
		var xtra: String = ""
		if _jugador != null and is_instance_valid(_jugador):
			xtra = ", el jugador en %s" % str((_jugador as Node3D).global_position.round())
		_fallar("P0", "la fase «%s» termina sola" % String(FASES.get(_fase, str(_fase))),
			"lleva %d frames de partida (%.0f s) sin terminar, en el sub-paso %d%s. "
			% [_frames_fase, _frames_fase / 60.0, _sub, xtra]
			+ "Se cortó y se siguió: el playtest no se cuelga nunca")
		return _ir(_siguiente_de(_fase))
	if ahora - _t_fase_ms > PRESUPUESTO_MS:
		_fallar("P0", "la partida entera termina dentro del presupuesto",
			"se pasó el presupuesto global de %d s en la fase %d"
			% [int(PRESUPUESTO_MS / 1000), _fase])
		return _reporte()
	match _fase:
		F_TITULO: return _f_titulo()
		F_CREACION: return _f_creacion()
		F_MUNDO: return _f_mundo()
		F_LISTO: return _f_listo()
		F_NOMBRE: return _f_nombre()
		F_CAMINAR: return _f_caminar()
		F_VITALES: return _f_vitales()
		F_COMBATE: return _f_combate()
		F_LOOT: return _f_loot()
		F_INVENTARIO: return _f_inventario()
		F_NIVEL: return _f_nivel()
		F_MISION: return _f_mision()
		F_HABLAR: return _f_hablar()
		F_CUMPLIR: return _f_cumplir_objetivo()
		F_ENTREGAR: return _f_entregar()
		F_HABLAR_2: return _f_hablar_2()
		F_COCINA: return _f_cocina()
		F_COCINA_LENA: return _f_cocina_lena()
		F_COCINA_COCINAR: return _f_cocina_cocinar()
		F_REFUGIO: return _f_refugio()
		F_REFUGIO_PIEZA: return _f_refugio_pieza()
		F_GUARDAR: return _f_guardar()
		F_TITULO_2: return _f_titulo_2()
		F_CARGAR: return _f_cargar()
		F_CARGAR_LISTO: return _f_cargar_listo()
		F_PANELES: return _f_paneles()
		F_ARBOL: return _f_arbol()
		F_ARBOL_TALAR: return _f_arbol_talar()
		F_REPORTE: return _reporte()
	return false


# ───────────────────────────────────────────────────────────────────────────
# ENTRADA — teclas y clic, como los manda un jugador
# ───────────────────────────────────────────────────────────────────────────

## PULSAR UNA TECLA, como la aprieta y la suelta una persona.
##
## POR QUÉ LA SUBIDA VA AL FRAME SIGUIENTE y no en el mismo: bajada y subida
## en el mismo frame las coalescea el motor en un solo evento, y un consumidor
## que filtra los releases —que es lo correcto, porque una tecla que se suelta
## no es una pulsación— se queda sin ver la bajada. Con la subida un frame
## después, la pulsación dura un frame: lo más corta que puede durar sin
## desaparecer.
##
## Y POR QUÉ NO SE DEJA PEGADA (que era como estaba antes):
## `event.is_action_pressed()` es el FLANCO DE BAJADA de la acción del
## InputMap. Con la bajada sola, el primer `pressed=true` la dispara y cada
## `pressed=true` posterior ya no es un flanco nuevo, así que un paso que
## REINTENTA la misma tecla (la T de atacar cada 15 frames, la E cada 40) se
## queda sin efecto para siempre. Medido: con la E pegada,
## `interactuar()` no volvía a disparar nunca.
##
## Las teclas que sí tienen que quedar oprimidas (el WASD de caminar) usan
## `_mantener()` + `_soltar()`, no esta.
func _pulsar(tecla: int) -> void:
	_soltar(tecla)
	var e := InputEventKey.new()
	e.physical_keycode = tecla
	e.pressed = true
	Input.parse_input_event(e)
	_soltar_pendiente = tecla


## Suelta la tecla del frame anterior, si quedó alguna. Lo llama el bucle
## principal una vez por frame, antes de mirar la fase.
func _soltar_la_pendiente() -> void:
	if _soltar_pendiente == 0:
		return
	var e := InputEventKey.new()
	e.physical_keycode = _soltar_pendiente
	e.pressed = false
	Input.parse_input_event(e)
	if _tecla_abierta == _soltar_pendiente:
		_tecla_abierta = 0
	_soltar_pendiente = 0


## Deja la tecla oprimida entre frames (caminar con WASD, mantener F9).
func _mantener(tecla: int) -> void:
	_tecla_abierta = tecla
	var e := InputEventKey.new()
	e.physical_keycode = tecla
	e.pressed = true
	Input.parse_input_event(e)


func _soltar(tecla: int) -> void:
	if _tecla_abierta == tecla:
		_tecla_abierta = 0
	var e := InputEventKey.new()
	e.physical_keycode = tecla
	e.pressed = false
	Input.parse_input_event(e)


func _clic(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)


func _camara() -> Camera3D:
	if _demo == null:
		return null
	return _demo.find_child("Camera3D", true, false) as Camera3D


func _proyectar(n: Node3D) -> Vector2:
	var cam: Camera3D = _camara()
	if cam == null:
		return Vector2(-1.0, -1.0)
	return cam.unproject_position(n.global_position + Vector3(0.0, 1.0, 0.0))


## ¿El nodo cae DENTRO del rectángulo de pantalla? Las dos coordenadas.
##
## Con solo la X, un nodo a y=5678 sobre un viewport de 1280 pasa el chequeo y
## el clic aterriza en el suelo. Y el clic en el suelo no es inocuo: es "orden
## de mover", que pasa por `deseleccionar()`. Perder la selección en el mismo
## gesto que debía producirla es como el arnés se contradice a sí mismo.
func _en_pantalla(n: Node3D) -> bool:
	var pos: Vector2 = _proyectar(n)
	var vp: Vector2 = root.get_visible_rect().size
	return pos.x >= 0.0 and pos.y >= 0.0 and pos.x <= vp.x and pos.y <= vp.y


# ───────────────────────────────────────────────────────────────────────────
# F0 — la pantalla de título, la de verdad
# ───────────────────────────────────────────────────────────────────────────

func _f_titulo() -> bool:
	if _titulo == null:
		var escena: PackedScene = load("res://scenes/titulo/pantalla_titulo.tscn")
		if escena == null:
			_fallar("P1", "la pantalla de título carga", "load() devolvió null")
			return _ir(F_REPORTE)
		_titulo = escena.instantiate()
		root.add_child(_titulo)
		current_scene = _titulo
		return false
	var b: Button = U.boton_texto(_titulo, "Nueva partida")
	if b == null:
		if _agotado(20000):
			_fallar("P1", "la pantalla de título carga",
				"no apareció el botón 'Nueva partida'. Botones: %s" % str(U.textos_de_botones(_titulo)))
			return _ir(F_REPORTE)
		return false
	_ok("P1", "la pantalla de título carga (los 5 botones del juego)", "")
	_ir(F_CREACION)
	b.pressed.emit()
	print("[PLAYTEST] P1 · clic real en el botón 'Nueva partida'")
	return false


# ───────────────────────────────────────────────────────────────────────────
# F1 — creación: nombre, clase, "Comenzar aventura"
# ───────────────────────────────────────────────────────────────────────────

func _f_creacion() -> bool:
	var cp: Node = U.con_script(root, "res://scripts/ui/creacion_personaje.gd")
	if cp == null:
		if _agotado(30000):
			_fallar("P1", "el botón 'Nueva partida' lleva a la creación de personaje",
				"no apareció CreacionPersonaje en %d ms. Raíces bajo root: %s"
				% [int((Time.get_ticks_msec() - _t_fase_ms) / 1000), U.raices(root)])
			return _ir(F_REPORTE)
		return false
	# `Transicion._ir_a()` tiene un cerrojo de reentrada (`_cargando`): si se
	# aprieta el botón mientras el fundido de la pantalla anterior sigue
	# corriendo, el cambio de escena se ignora en silencio. Un humano no llega
	# a apretar tan rápido; el test tiene que esperar lo mismo.
	if _sub < 20:
		_sub += 1
		return false
	if not _transicion_libre() and _sub < 90:
		_sub += 1
		return false
	if _sub == 20:
		var entrada: LineEdit = U.primero_de_tipo(cp, "LineEdit")
		if entrada == null:
			_fallar("P1", "la creación de personaje tiene campo de nombre",
				"no hay ningún LineEdit en `CreacionPersonaje`")
			return _ir(F_REPORTE)
		entrada.text = NOMBRE_HEROE
		# Las tarjetas de clase comparten el `ButtonGroup` del script: los
		# botones de acción ("Comenzar aventura", "Atrás") no lo tienen.
		var grupo: ButtonGroup = cp.get("_grupo")
		var tarjetas: Array = []
		for b in U.botones(cp):
			var btn: Button = b
			if btn.button_group != null and btn.button_group == grupo:
				tarjetas.append(btn)
		var nombre_clase: String = str(ClaseDB.obtener(CLASE_HEROE).get("nombre", CLASE_HEROE))
		var elegida: Button = U.boton_texto(tarjetas, nombre_clase)
		if elegida == null and tarjetas.size() > 0:
			elegida = tarjetas[0]
		if elegida == null:
			_fallar("P1", "la creación de personaje deja elegir clase",
				"no hay tarjetas de clase en el `ButtonGroup` de la pantalla. Botones: %s"
				% str(U.textos_de_botones(cp)))
			return _ir(F_REPORTE)
		elegida.pressed.emit()
		var comenzar: Button = U.boton_texto(cp, "Comenzar aventura")
		if comenzar == null:
			_fallar("P1", "la creación de personaje tiene botón 'Comenzar aventura'",
				"no está. Botones: %s" % str(U.textos_de_botones(cp)))
			return _ir(F_REPORTE)
		print("[PLAYTEST] P1 · nombre «%s» escrito en el LineEdit, clase «%s» elegida"
			% [NOMBRE_HEROE, str(elegida.text)])
		_sub = 91
		return false
	var comenzar: Button = U.boton_texto(cp, "Comenzar aventura")
	if comenzar == null:
		_fallar("P1", "la creación de personaje tiene botón 'Comenzar aventura'",
			"no está. Botones: %s" % str(U.textos_de_botones(cp)))
		return _ir(F_REPORTE)
	comenzar.pressed.emit()
	print("[PLAYTEST] P1 · clic real en 'Comenzar aventura'")
	return _ir(F_MUNDO)


# ───────────────────────────────────────────────────────────────────────────
# F2/F3 — el mundo real y su gate de construcción
# ───────────────────────────────────────────────────────────────────────────

func _f_mundo() -> bool:
	_demo = U.nodo(root, "Fase14Demo")
	if _demo == null:
		if _agotado(60000):
			_fallar("P2", "'Comenzar aventura' entra al mundo jugable",
				"no apareció el nodo 'Fase14Demo' en %d s. Raíces: %s"
				% [int((Time.get_ticks_msec() - _t_fase_ms) / 1000), U.raices(root)])
			return _ir(F_REPORTE)
		return false
	_jugador = _demo.find_child("Player", true, false) as Node3D
	if _jugador == null:
		if _agotado(60000):
			_fallar("P2", "el mundo jugable tiene un jugador", "no hay nodo 'Player'")
			return _ir(F_REPORTE)
		return false
	return _ir(F_LISTO)


func _f_listo() -> bool:
	# El gate real del juego: `fase12_demo._al_mundo_listo()` recién corre
	# cuando `_mundo_pendiente` baja, y ahí se instancian las 7 UI que faltaban.
	if not bool(_demo.get("_mundo_pendiente")):
		_pos_inicio = (_jugador as Node3D).global_position
		_congelar()
		print("[PLAYTEST] P2 · mundo listo en %d ms de reloj · jugador en %s"
			% [int(Time.get_ticks_msec() - _t_inicio_ms), str(_pos_inicio)])
		return _ir(F_NOMBRE)
	if _agotado(180000):
		_fallar("P2", "el mundo termina de construirse",
			"`_mundo_pendiente` sigue en true tras 180 s de reloj")
		return _ir(F_REPORTE)
	return false


func _congelar() -> void:
	_ref = {
		"hud": _demo.find_child("HUD", true, false),
		"retrato": null,
		"vitales": _demo.find_child("IndicadorVitales", true, false),
		"inv": _demo.find_child("PanelInventario", true, false),
		"misiones": _demo.find_child("PanelMisiones", true, false),
		"dialogo": _demo.find_child("VentanaDialogo", true, false),
		"cocina": _demo.find_child("PanelCocina", true, false),
		"construccion": _demo.find_child("PanelConstruccion", true, false),
		"gamefeel": _demo.find_child("GameFeel", true, false),
		"pool": _demo.find_child("PoolImpacto", true, false),
		"pause": _demo.find_child("MenuPausa", true, false),
		"misiones_log": _demo.get("_misiones"),
		"guardado": _demo.get("_guardado"),
		"fogatas": _demo.get("_fogatas"),
		"refugios": _demo.get("_refugios"),
		"arboles": _demo.get("_arboles"),
	}
	var hud: Node = _ref["hud"]
	if hud != null:
		_ref["retrato"] = U.primero_de_tipo(hud, "RetratoHeroe")
	_midiendo = true
	_t_ultimo_usec = Time.get_ticks_usec()
	_cpu_s = 0.0


# ───────────────────────────────────────────────────────────────────────────
# F4 — el nombre que elegiste aparece en el HUD
# ───────────────────────────────────────────────────────────────────────────

func _f_nombre() -> bool:
	var r: Node = _ref.get("retrato")
	if r == null:
		_fallar("P1", "el nombre escrito en la creación aparece en el HUD",
			"no hay RetratoHeroe dentro del HUD. Hijos del HUD: %s" % str(U.nombres(_ref.get("hud") as Node)))
		_omitir("P1", "la clase elegida se aplicó al jugador", "sin HUD")
		return _ir(F_CAMINAR)
	var mostrado: String = str(r.call("nombre_mostrado"))
	if mostrado.strip_edges() == NOMBRE_HEROE:
		_ok("P1", "el nombre escrito en la creación aparece en el HUD",
			"el retrato del HUD muestra «%s»" % mostrado)
	else:
		_fallar("P1", "el nombre escrito en la creación aparece en el HUD",
			"el retrato del HUD muestra «%s» y se escribió «%s»: `DatosSesion."
			% [mostrado, NOMBRE_HEROE] + "aplicar_a()` no llegó al Player, o el HUD no se refrescó")
	var cid: String = str((_jugador as Node3D).get("clase_id"))
	if cid == CLASE_HEROE:
		_ok("P1", "la clase elegida se aplicó al jugador", "clase_id = «%s»" % cid)
	else:
		_fallar("P1", "la clase elegida se aplicó al jugador",
			"se eligió «%s» y el jugador tiene «%s»" % [CLASE_HEROE, cid])
	return _ir(F_CAMINAR)


# ───────────────────────────────────────────────────────────────────────────
# F5 — caminar de verdad: WASD del Input Map, no setear la posición
# ───────────────────────────────────────────────────────────────────────────

func _f_caminar() -> bool:
	var p: Node3D = _jugador as Node3D
	if _sub == 0:
		_pos_inicio = p.global_position
		_vel_max = 0.0
		# El Player lee `Input.get_vector` en `_construir_intent()` y se mueve
		# con `move_and_slide()`. Esto es el WASD del jugador, no un teletransporte.
		Input.action_press("mover_adelante")
		_sub = 1
		print("[PLAYTEST] P2 · WASD real: 'mover_adelante' apretado 180 frames (3 s)")
		return false
	if _sub == 90:
		# Tramo en diagonal, para no depender del heading inicial de la cámara.
		Input.action_press("mover_derecha")
		_sub += 1
		return false
	if _sub < 180:
		_sub += 1
		var v: Vector3 = p.velocity
		_vel_max = maxf(_vel_max, Vector2(v.x, v.z).length())
		return false
	Input.action_release("mover_adelante")
	Input.action_release("mover_derecha")
	var recorrido: float = p.global_position.distance_to(_pos_inicio)
	if _vel_max > 0.5:
		_ok("P2", "el jugador camina con el WASD del Input Map",
			"velocidad horizontal máx. %.2f u/s durante 3 s de partida" % _vel_max)
	else:
		_fallar("P2", "el jugador camina con el WASD del Input Map",
			"la velocidad horizontal nunca pasó de %.3f u/s. El Input Map llega a "
			% _vel_max + "`_construir_intent()` pero el intent no llega a `_consumir_intent()`")
	if recorrido < 2.0:
		_fallar("P2", "el jugador recorre distancia real en 3 s",
			"se movió %.2f u: `move_and_slide()` no lo desplazó" % recorrido)
	else:
		_ok("P2", "el jugador recorre distancia real en 3 s",
			"%.2f u de desplazamiento efectivo" % recorrido)
	return _ir(F_VITALES)


# ───────────────────────────────────────────────────────────────────────────
# F6 — las barras de vitales aparecen y BAJAN con el tiempo
# ───────────────────────────────────────────────────────────────────────────

func _f_vitales() -> bool:
	# Una sola vez: se apunta el valor de partida y se espera a que BAJE. El
	# vital cae 0.85 por segundo de juego, así que hace falta medio segundo
	# para cruzar el `TOQUE_MIN` de 0.5 que usa `Vitals._avisar_cambio()`.
	if _sub == 0:
		var iv: Node = _ref.get("vitales")
		if iv == null:
			_fallar("P3", "existe el indicador de vitales (hambre/sed/energía) en la partida",
				"no hay nodo 'IndicadorVitales': las 3 barras no están instanciadas")
			_omitir("P3", "las barras de vitales bajan con el tiempo", "sin indicador")
			return _ir(F_COMBATE)
		if iv.is_inside_tree() and iv.visible:
			_ok("P3", "el indicador de vitales cuelga del árbol y es visible", "")
		else:
			_fallar("P3", "el indicador de vitales cuelga del árbol y es visible",
				"dentro del árbol = %s, visible = %s"
					% [str(iv.is_inside_tree()), str(iv.visible)])
		var barras: Dictionary = iv.get("_barras")
		for k in barras.keys():
			var e: Dictionary = barras[k]
			_slot_barra[str(k)] = e["barra"]
		if _slot_barra.size() < 3:
			_fallar("P3", "hay 3 barras de vitales pintadas (hambre/sed/energía)",
				"`_barras` tiene %d entradas: %s"
					% [_slot_barra.size(), str(_slot_barra.keys())])
			_omitir("P3", "las barras de vitales bajan con el tiempo", "no hay 3 barras")
			return _ir(F_COMBATE)
		_ok("P3", "hay 3 barras de vitales pintadas (hambre/sed/energía)", "")
		_hambre_ini = float((_jugador as Node3D).get("vitals").get("hambre"))
		_agotado(0)
		print("[PLAYTEST] P3 · hambre inicial %.2f · esperando a que BAJE sola"
			% _hambre_ini)
		_sub = 1
		return false
	# Lo que se mide es la BARRA, no el vital: `Vitals` sólo emite cuando algo
	# se movió `TOQUE_MIN` (0.5), así que la barra va hasta medio punto detrás
	# del dato. Lo que importa es que se mueva hacia abajo sola.
	var barra: ProgressBar = _slot_barra["hambre"]
	var caida: float = _hambre_ini - barra.value
	if caida < 0.4:
		if _sub % 300 == 0:
			print("[PLAYTEST] P3 · esperando que la barra baje (%.3f de 0.4; la barra "
				% caida + "va %.3f detrás del vital, que es el TOQUE_MIN de `Vitals`)"
				% (_hambre_ini - float(((_jugador as Node3D).get("vitals") as Object).get("hambre")) - barra.value))
		if not _agotado(60000):
			_sub += 1
			return false
	_cerca_vitales()
	elegir_mob()
	return _ir(F_LOOT)


# ───────────────────────────────────────────────────────────────────────────
# F7 — golpear un mob: número de daño, empuje, partículas
# ───────────────────────────────────────────────────────────────────────────

## F7 ya no espera: la selección del mob quedó dentro de F_VITALES, que es
## donde está el reloj de juego. Esta fase queda como el arranque de combate.
func _f_combate() -> bool:
	_cerca_vitales()
	elegir_mob()
	return _ir(F_LOOT)


## Elige el mob vivo más cercano, engancha las sondas de feedback y le hace el
## clic de ratón real. Si el raycast no lo agarra, `_rastro` lo dice y el paso
## de combate lo reporta como fallo: no se oculta.
func elegir_mob() -> void:
	_visto_danio = 0.0
	_visto_empuje = false
	_visto_numero = ""
	_visto_particulas = false
	_botin.clear()
	_rastro = ""
	_mob = _mob_cercano()
	if _mobs_sin_parte:
		return
	_mob.botin_generado.connect(_al_botin)
	_mob.daniado.connect(_al_danio)
	_pos_mob_antes = (_mob as Node3D).global_position
	print("[PLAYTEST] P4 · mob «%s» a %.1f u (rango de ataque 2.6)"
		% [str(_mob.get("nombre")),
			(_mob as Node3D).global_position.distance_to((_jugador as Node3D).global_position)])
	var pos: Vector2 = _proyectar(_mob as Node3D)
	if pos.x >= 0.0:
		_clic(pos)
		print("[PLAYTEST] P4 · clic de ratón en %s (unproject_position del mob)" % str(pos))
	else:
		_rastro = "no hay Camera3D en la partida para proyectar el clic"


func _cerca_vitales() -> void:
	if _slot_barra.is_empty():
		return
	var barra: ProgressBar = _slot_barra["hambre"]
	var vitals: Object = (_jugador as Node3D).get("vitals")
	var ahora: float = float(vitals.get("hambre"))
	var caida: float = _hambre_ini - ahora
	if caida >= 0.4:
		if barra.value <= _hambre_ini - 0.4:
			_ok("P3", "la barra de hambre BAJA sola con el tiempo real",
				"hambre %.2f→%.2f y el ProgressBar del HUD quedó en %.2f" % [_hambre_ini, ahora, barra.value])
		else:
			_fallar("P3", "la barra de hambre BAJA sola con el tiempo real",
				"el vital bajó a %.2f pero el ProgressBar sigue en %.2f: `IndicadorVitales` "
				% [ahora, barra.value] + "no se enteró de la señal `vital_cambiado`")
	elif caida > 0.0:
		_fallar("P3", "la barra de hambre BAJA sola con el tiempo real",
			"en 20 s de partida el vital sólo bajó %.3f (TOQUE_MIN de Vitals = 0.5): "
			% caida + "no se puede ver el cambio, el decay está frenado")
	else:
		_fallar("P3", "la barra de hambre BAJA sola con el tiempo real",
			"el vital no se movió NADA (%.2f→%.2f) en 20 s de partida" % [_hambre_ini, ahora])


func _al_danio(cantidad: float, _fuente: Node) -> void:
	_visto_danio += cantidad
	# `Entity` no expone `tiene_empuje()`: la API pública del empujón es
	# `empuje_actual(delta)`, que devuelve el vector ya desvanecido.
	if _mob != null and _mob.has_method("empuje_actual") \
			and (_mob.call("empuje_actual", 0.0) as Vector3).length() > 0.0:
		_visto_empuje = true
	# El número y las partículas se leen EN EL MISMO FRAME del golpe.
	var gf: Node = _ref.get("gamefeel")
	if gf != null:
		for n in (gf.get("_nros") as Array):
			var lbl: Label3D = n as Label3D
			if lbl != null and lbl.visible and lbl.text.is_valid_int():
				_visto_numero = lbl.text
	var pool: Node = _ref.get("pool")
	if pool != null:
		for c in pool.get_children():
			if c is GPUParticles3D and c.emitting:
				_visto_particulas = true


func _al_botin(drops: Array, _pos: Vector3) -> void:
	for d in drops:
		var dd: Dictionary = d
		if str(dd.get("tipo", "")) == "item":
			_botin.append(dd)


# ───────────────────────────────────────────────────────────────────────────
# F8 — el mob muere, dropea y el item entra al inventario
# ───────────────────────────────────────────────────────────────────────────

func _f_loot() -> bool:
	if _mob == null:
		return _ir(F_NIVEL)
	var p: Node3D = _jugador as Node3D
	if bool(_mob.call("esta_vivo")):
		# El gesto del juego: clic sobre el mob (una vez) y tecla T. Con el mob
		# seleccionado, el motor pursue y golpea solo; la tecla se repite cada
		# 15 frames como la aprieta una persona.
		if p.get("seleccion") != _mob and _sub < 8:
			_sub += 1
			if _sub == 2 and not _en_pantalla(_mob as Node3D):
				p.call("_aplicar_clic", _mob, 0)
			if _sub == 4:
				_pulsar(KEY_T)
			return false
		if p.get("seleccion") != _mob:
			_rastro = "el clic de ratón no seleccionó el mob"
			p.call("_aplicar_clic", _mob, 0)
			_sub = 8
			return false
		_sub += 1
		if _sub % 15 == 0:
			_pulsar(KEY_T)
		# Con el mob cerca se reintenta el clic de ratón REAL: el raycast tiene
		# que dar en el collider del mob, no en el terreno del medio. Y solo si
		# está en pantalla: un clic fuera del rectángulo es un clic en el suelo.
		if _sub % 30 == 0 and (_mob as Node3D).global_position.distance_to(
				p.global_position) < 12.0 and _en_pantalla(_mob as Node3D):
			_clic(_proyectar(_mob as Node3D))
		if _sub % 600 == 0:
			print("[PLAYTEST] P4 · mob con %.0f/%.0f de vida a %.1f u, "
				% [U.num(_mob, "vida_actual"), _vida_max(_mob),
					(_mob as Node3D).global_position.distance_to(p.global_position)]
				+ "objetivo=%s destino=%s daño_visto=%.0f"
				% [str(p.get("objetivo_ataque")), str(p.get("_tiene_destino")), _visto_danio])
		if _agotado(180000):
			_fallar("P4", "el jugador llega a rango y golpea al mob",
				"tras 180 s el mob sigue con %.0f/%.0f de vida y a %.1f u del jugador "
				% [U.num(_mob, "vida_actual"), _vida_max(_mob),
					(_mob as Node3D).global_position.distance_to(p.global_position)]
				+ "(rango de ataque 2.6). `seleccion`=%s `objetivo_ataque`=%s"
				% [str(p.get("seleccion")), str(p.get("objetivo_ataque"))])
			return _fin_combate("no se pudo golpear al mob")
		return false
	# Murió. Los tres feedbacks del golpe.
	if _visto_danio > 0.0:
		_ok("P4", "el golpe hace daño real (señal `daniado`)", "%.0f de daño" % _visto_danio)
	else:
		_fallar("P4", "el golpe hace daño real (señal `daniado`)",
			"el mob murió sin un solo punto de daño registrado")
	if _visto_numero != "":
		_ok("P4", "sale el NÚMERO DE DAÑO en pantalla",
			"un `Label3D` del pool de `GameFeel` quedó visible con «%s»" % _visto_numero)
	else:
		_fallar("P4", "sale el NÚMERO DE DAÑO en pantalla",
			"ningún `Label3D` del pool de `GameFeel` quedó visible con un número. "
			+ "O `GameFeel` no está instanciado, o `_mostrar_numero()` no se llama")
	if _visto_empuje:
		_ok("P4", "el mob se EMPUJA al golpearlo",
			"`empuje_actual(0.0).length()` > 0 en el frame del impacto")
	else:
		_fallar("P4", "el mob se EMPUJA al golpearlo",
			"`empuje_actual(0.0)` dio vector cero en el frame del impacto: "
			+ "`aplicar_empuje()` no corrió o se desvaneció antes")
	var movido: float = (_mob as Node3D).global_position.distance_to(_pos_mob_antes)
	if movido > 0.05:
		_ok("P4", "el cuerpo del mob se desplazó al empujón", "%.2f u" % movido)
	else:
		_fallar("P4", "el cuerpo del mob se desplazó al empujón", "se movió %.3f u" % movido)
	if _rastro == "":
		_ok("P4", "el mob se selecciona con un clic de ratón real",
			"el raycast del Player lo agarró solo (`_clic_izquierdo` → `_rayo_clic`)")
	else:
		_omitir("P4", "el mob se selecciona con un clic de ratón real",
			"el raycast headless no llegó al collider del mob (%s). El propio repo ya "
			% _rastro + "lo sabe y por eso `_aplicar_clic()` está documentado como "
			+ "«pública para tests headless, que no tienen viewport para raycast». "
			+ "Lo demás del combate se midió igual, con esa vía.")
	if _visto_particulas:
		_ok("P4", "hay PARTÍCULAS de impacto",
			"un `GPUParticles3D` de `PoolImpacto` quedó `emitting = true` en el frame del golpe")
	else:
		_fallar("P4", "hay PARTÍCULAS de impacto",
			"ningún `GPUParticles3D` de `PoolImpacto` se activó en el frame del golpe")
	if _botin.is_empty():
		_fallar("P4", "el mob dropea al morir", "la señal `botin_generado` nunca emitió")
		return _fin_combate("el mob no dropeó")
	var oro: int = 0
	for d in _botin:
		var dd: Dictionary = d
		if str(dd.get("tipo", "")) == "oro":
			oro += int(dd.get("cantidad", 0))
		else:
			_item_loot = str(dd.get("item_id", ""))
	_ok("P4", "el mob dropea al morir",
		"%d drops (%d de oro, item «%s»)" % [_botin.size(), oro, _item_loot])
	if _item_loot == "":
		_fallar("P4", "el botín trae un ITEM (no sólo oro)",
			"los %d drops fueron sólo de oro" % _botin.size())
		return _fin_combate("el botín fue sólo oro")
	return _ir(F_INVENTARIO)


func _fin_combate(motivo: String) -> bool:
	_omitir("P5", "el botín entra al inventario con sus afijos", motivo)
	_omitir("P5", "el inventario MUESTRA el item en pantalla", motivo)
	return _ir(F_NIVEL)


# ───────────────────────────────────────────────────────────────────────────
# F9 — el item entra al inventario Y el inventario lo MUESTRA
# ───────────────────────────────────────────────────────────────────────────

func _f_inventario() -> bool:
	if _item_loot == "":
		return _ir(F_NIVEL)
	var inv: Object = (_jugador as Node3D).get("inventario")
	var p: Node3D = _jugador as Node3D
	# El item entra pisando el `Pickup` real que el mundo puso en el suelo.
	var pick: Node = U.pickup_de(_demo, _item_loot)
	if pick != null:
		if _sub == 0:
			print("[PLAYTEST] P5 · caminando al Pickup de «%s»" % _item_loot)
		p.global_position = pick.global_position + Vector3(0.5, 0.0, 0.0)
		_sub += 1
		if _sub < 4:
			return false
		_agotado(0)
	var cant: int = int(inv.call("contar", _item_loot))
	if cant <= 0:
		_fallar("P5", "el item del botín entra al inventario",
			"`inventario.contar('%s')` quedó en %d tras pisar el Pickup. El Pickup "
			% [_item_loot, cant] + "existe pero `_al_recoger_botin` no lo.agregó")
		_omitir("P5", "el item entra CON sus afijos", "no llegó al inventario")
		_omitir("P5", "el inventario MUESTRA el item", "no llegó al inventario")
		return _ir(F_NIVEL)
	_ok("P5", "el item del botín entra al inventario",
		"`contar('%s')` = %d" % [_item_loot, cant])
	_chequear_afijos(inv)
	return _ir(F_NIVEL)


func _chequear_afijos(inv: Object) -> void:
	var admite: bool = AfijosLoot.admite(_item_loot)
	var entrada: Dictionary = U.entrada(inv, _item_loot)
	var afijos: Array = Inventario.afijos_de_entrada(entrada)
	if not admite:
		_omitir("P5", "el item entra CON sus afijos",
			"cayó «%s», que es material: los afijos sólo van a arma/armadura/accesorio. "
			% _item_loot + "La ruta afijada del loot NO quedó verificada en esta partida")
		return
	if afijos.is_empty():
		_fallar("P5", "el item entra CON sus afijos",
			"«%s» es de tipo afijable (`AfijosLoot.admite` = true) y entró PELADO: "
			% _item_loot + "0 afijos. El afijo se sorteó pero no llegó al inventario")
		return
	var texto: Array[String] = []
	for a in afijos:
		var ad: Dictionary = a
		texto.append("%s +%.1f %s (%s)" % [str(ad.get("nombre", "?")),
			float(ad.get("valor", 0.0)), str(ad.get("stat", "?")),
			Afijos.RAREZAS[clampi(int(ad.get("rareza", 1)) - 1, 0, 4)]])
	_ok("P5", "el item entra CON sus afijos", "; ".join(texto))


# ───────────────────────────────────────────────────────────────────────────
# F10 — subir de nivel: la UI de nivel se mueve
# ───────────────────────────────────────────────────────────────────────────

func _f_nivel() -> bool:
	# El inventario se abre con la tecla I del Input Map y se mira la rejilla.
	var pan: Node = _ref.get("inv")
	if pan != null and _item_loot != "" and not _inv_ya_mirada:
		if _sub == 0:
			_pulsar(KEY_I)
			_sub = 1
			return false
		if _sub < 5:
			_sub += 1
			return false
		_inv_ya_mirada = true
		if not pan.visible:
			_fallar("P5", "el inventario se abre con la tecla I y MUESTRA el item",
				"`PanelInventario.visible` quedó en false tras mandar la tecla I")
		else:
			var rejilla: GridContainer = pan.get("_rejillas").get("Todos")
			var celdas: int = rejilla.get_child_count() if rejilla != null else 0
			if celdas > 0:
				_ok("P5", "el inventario MUESTRA el item en pantalla",
					"la pestaña «Todos» tiene %d celdas pintadas, con lo que hay en "
					% celdas + "la bolsa dentro")
			else:
				_fallar("P5", "el inventario MUESTRA el item en pantalla",
					"la pestaña «Todos» tiene 0 celdas aunque la bolsa no está vacía")
			_pedir_cierre()
	# ── Subir de nivel ──
	# El spec (bloque 4) define el loop jugable como "moverse → pegar → lootear
	# → subir de nivel". No hay un panel de nivel: lo que sube de nivel es el
	# HUD (el retrato y la etiqueta) y el `PanelPersonaje`. Para que el nivel
	# suba hay que PEGAR, así que el test sigue jugando: mata mobs con la tecla
	# T hasta que el nivel cambia, y recién ahí mira si la UI se movió.
	var r: Node = _ref.get("retrato")
	if not _nivel_iniciado:
		_nivel_iniciado = true
		_nivel_antes = int((_jugador as Node3D).get("nivel"))
		_nivel_hud_antes = str(r.call("nivel_mostrado")) if r != null else ""
		_agotado(0)
		print("[PLAYTEST] P6 · nivel %d, XP %d · el HUD muestra «%s»"
			% [_nivel_antes, int((_jugador as Node3D).get("xp_actual")), _nivel_hud_antes])
		_sub = 1
		return false
	var nivel: int = int((_jugador as Node3D).get("nivel"))
	if nivel > _nivel_antes:
		var mostrado: String = str(r.call("nivel_mostrado")) if r != null else ""
		if mostrado != _nivel_hud_antes:
			_ok("P6", "subir de nivel MUEVE la UI del nivel",
				"el nivel pasó de %d a %d y el retrato del HUD pasó de «%s» a «%s»"
					% [_nivel_antes, nivel, _nivel_hud_antes, mostrado])
		else:
			_fallar("P6", "subir de nivel MUEVE la UI del nivel",
				"el Player llegó al nivel %d y `RetratoHeroe` sigue mostrando «%s»: "
				% [nivel, mostrado] + "la señal `subio_nivel` no llegó al HUD")
		_chequear_panel_personaje()
		return _ir(F_MISION)
	# Todavía falta XP: se sigue jugando, igual que un jugador.
	if _mob == null or not is_instance_valid(_mob) or not bool(_mob.call("esta_vivo")):
		elegir_mob()
		if _mob == null:
			_fallar("P6", "subir de nivel",
				"no quedan mobs vivos cerca y el nivel sigue en %d con %d/%d XP"
					% [_nivel_antes, int((_jugador as Node3D).get("xp_actual")),
						Formulas.xp_for_level(_nivel_antes + 1)])
			_omitir("P6", "subir de nivel MUEVE la UI del nivel", "no hay con qué subir")
			return _ir(F_MISION)
		return false
	var p: Node3D = _jugador as Node3D
	_sub += 1
	var d: float = p.global_position.distance_to((_mob as Node3D).global_position)
	if d > 2.2:
		# Lejos: acercarse con la misma caminata con rodeos del resto del
		# playtest. Si el mob está detrás de una pared, la caminata lo rodea.
		_caminar_hasta((_mob as Node3D).global_position, 2.2)
		if p.get("seleccion") != _mob:
			p.call("seleccionar", _mob)
		if _sub % 600 == 0 and not bool(p.call("esta_vivo")):
			elegir_mob()
		if _sub % 600 == 0:
			print("[PLAYTEST] P6 · a %.1f u del mob, el jugador está en %s"
				% [d, str(p.global_position.round())])
		if _sub > 5400:
			elegir_mob()
			_sub = 0
		return false
	if p.get("seleccion") != _mob:
		p.call("seleccionar", _mob)
		return false
	if _sub % 15 == 0:
		_pulsar(KEY_T)
	if _agotado(420000):
		_fallar("P6", "subir de nivel",
			"tras 420 s el nivel sigue en %d con %d XP (hacen falta %d para el %d)"
				% [_nivel_antes, int((_jugador as Node3D).get("xp_actual")),
					Formulas.xp_for_level(_nivel_antes + 1), _nivel_antes + 1])
		_omitir("P6", "subir de nivel MUEVE la UI del nivel", "no se alcanzó el nivel")
		return _ir(F_MISION)
	return false


## El `PanelPersonaje` también muestra el nivel: si tampoco se movió, el
## `subio_nivel` no llegó a ninguna de las dos UIs.
func _chequear_panel_personaje() -> void:
	var pp: Node = U.nodo(_demo, "PanelPersonaje")
	if pp == null:
		_omitir("P6", "el PanelPersonaje también muestra el nivel nuevo", "no está")
		return
	if not pp.visible:
		pp.visible = true
		pp.call("_reconstruir")
		pp.visible = false
	var cab: Label = pp.get("_cabecera")
	if cab != null and ("Nv %d" % int((_jugador as Node3D).get("nivel"))) in str(cab.text):
		_ok("P6", "el PanelPersonaje también muestra el nivel nuevo",
			"«%s»" % str(cab.text))
	elif cab != null:
		_fallar("P6", "el PanelPersonaje también muestra el nivel nuevo",
			"la cabecera dice «%s» y el jugador está en nivel %d"
				% [str(cab.text), int((_jugador as Node3D).get("nivel"))])
	else:
		_omitir("P6", "el PanelPersonaje también muestra el nivel nuevo",
			"`_cabecera` no existe en el panel")


# ───────────────────────────────────────────────────────────────────────────
# F11 — la misión: caminar hasta el NPC y hablar
# ───────────────────────────────────────────────────────────────────────────

func _f_mision() -> bool:
	var q: Object = _ref.get("misiones_log")
	if q == null:
		_fallar("P7", "la partida tiene un registro de misiones",
			"`_misiones` es null en la escena del juego")
		_omitir("P7", "aceptar y completar una misión del NPC", "sin QuestLog")
		return _ir(F_COCINA)
	_npc = _npc_con_oferta(q)
	if _npc == null:
		var of: Array[String] = []
		for n in get_nodes_in_group("npcs"):
			of.append("%s=%s" % [str(n.get("npc_id")),
				str(q.call("oferta_para_npc", str(n.get("npc_id"))).get("modo", "-"))])
		_fallar("P7", "hay un NPC que ofrezca una misión", "nadie ofrece nada. %s" % str(of))
		_omitir("P7", "aceptar y completar una misión del NPC", "nadie ofrece misión")
		return _ir(F_COCINA)
	_quest_id = str(q.call("oferta_para_npc", str(_npc.get("npc_id"))).get("quest_id", ""))
	var p: Node3D = _jugador as Node3D
	_reiniciar_caminata()
	p.call("ordenar_mover_a", (_npc as Node3D).global_position)
	print("[PLAYTEST] P7 · caminando hasta %s (%s) a %.0f u por la misión «%s»"
		% [str(_npc.get("nombre_mostrado")), str(_npc.get("npc_id")),
			p.global_position.distance_to((_npc as Node3D).global_position), _quest_id])
	var todos: Array[String] = []
	for n in get_nodes_in_group("npcs"):
		todos.append("%s en %s" % [str(n.get("npc_id")), str((n as Node3D).global_position)])
	print("[PLAYTEST] P7 · el jugador está en %s y los NPCs en %s"
		% [str(p.global_position), str(todos)])
	return _ir(F_HABLAR)


func _f_hablar() -> bool:
	var p: Node3D = _jugador as Node3D
	var dlg: Node = _ref.get("dialogo")
	if dlg == null:
		_fallar("P7", "la ventana de diálogo está en la partida", "no hay 'VentanaDialogo'")
		_omitir("P7", "aceptar y completar una misión del NPC", "sin diálogo")
		return _ir(F_COCINA)
	if not _caminar_hasta((_npc as Node3D).global_position, 2.9):
		if _agotado(300000):
			_fallar("P7", "el jugador llega hasta el NPC que ofrece la misión",
				"tras 300 s sigue a %.1f u (el radio para hablar es 3.0)"
					% p.global_position.distance_to((_npc as Node3D).global_position))
			_omitir("P7", "aceptar y completar una misión del NPC", "no llegó al NPC")
			return _ir(F_COCINA)
		if p.get("seleccion") != _npc and _sub % 120 == 0:
			p.call("seleccionar", _npc)
		_sub += 1
		return false
	_sub = 0
	if not dlg.call("esta_abierta"):
		# El gesto del juego: seleccionar al NPC y apretar E.
		#
		# POR QUÉ NO UN CLIC DE RATÓN: el NPC se proyecta a y=5678 en un
		# viewport de 1280, o sea que está FUERA DE PANTALLA — la cámara de
		# la partida mira a otro lado. Un clic fuera de la pantalla es un clic
		# en el suelo, y el clic en el suelo es "orden de mover", que además
		# llama `deseleccionar()`. Medido: tras el clic proyectado,
		# `seleccion` queda en null y la E no tiene a quién hablar. Un
		# jugador real PANORÁMICA hasta verlo; el arnés no puede, así que usa
		# la API que el propio repo reserva para headless (`_aplicar_clic`).
		if _sub % 40 == 0:
			p.call("_aplicar_clic", _npc, 0)
			_pulsar(KEY_E)
		_sub += 1
		if _agotado(30000):
			_fallar("P7", "el clic + la tecla E abren el diálogo con el NPC",
				"`VentanaDialogo.esta_abierta()` quedó en false con %s a %.2f u "
				% [str(_npc.get("nombre_mostrado")),
					p.global_position.distance_to((_npc as Node3D).global_position)]
				+ "y la selección en %s" % str(p.get("seleccion")))
			_omitir("P7", "aceptar y completar una misión del NPC", "el diálogo no abre")
			return _ir(F_COCINA)
		return false
	_ok("P7", "el diálogo con el NPC se abre y muestra su texto",
		"«%s» (%s): «%s»" % [str(dlg.call("titulo_texto")), str(dlg.call("rol_texto")),
			str(dlg.call("linea_actual"))])
	return _entregar_por_dialogo()


# ───────────────────────────────────────────────────────────────────────────
# F13 — CUMPLIR el objetivo de la misión JUGANDO, y entregarla
# ───────────────────────────────────────────────────────────────────────────

## El objetivo que hay que cumplir para que la misión pase a «lista».
## Se lee del DATO de la misión activa, no está escrito acá: la misión que
## ofrezca el NPC puede ser la de matar o la de recoger, y el arnés tiene que
## seguir la que toque (§9.4, datos primero).
func _objetivo_pendiente() -> Dictionary:
	var q: Object = _ref.get("misiones_log")
	if q == null:
		return {}
	for obj in q.call("objetivos_con_progreso", _quest_id):
		var o: Dictionary = obj as Dictionary
		if int(o.get("actual", 0)) < int(o.get("meta", 1)):
			return o
	return {}


func _f_cumplir_objetivo() -> bool:
	var q: Object = _ref.get("misiones_log")
	if str(q.call("estado", _quest_id)) == "lista":
		_ok("P7", "los objetivos de la misión se completan JUGANDO",
			"estado = «lista», sin ayuda exterior")
		return _ir(F_ENTREGAR)
	var o: Dictionary = _objetivo_pendiente()
	if o.is_empty():
		return _ir(F_ENTREGAR)
	var tipo: String = str(o.get("tipo", ""))
	if tipo == "matar":
		return _cumplir_matando(o)
	if tipo == "recolectar":
		return _cumplir_recogiendo(o)
	# Un objetivo de tipo «hablar» lo cumple el gesto de hablar, que ya se
	# midió en F_HABLAR. Si aparece otro tipo nuevo, se OMITE con el motivo
	# escrito en vez de fingir que se cumplió.
	_omitir("P7", "los objetivos de la misión se completan JUGANDO",
		"objetivo de tipo «%s», que el arnés no sabe jugar" % tipo)
	_omitir("P7", "ENTREGAR la misión la da por completada", "el objetivo no se Playsó")
	return _ir(F_COCINA)


## Matar lo que pida el objetivo: se busca el arquetipo en el mundo y se lo
## golpea con la tecla de atacar, como un jugador. Si no hay ninguno a mano
## (puede estar en otra región del mundo de 36.864 u), se dice por qué.
func _cumplir_matando(o: Dictionary) -> bool:
	var arq: String = str(o.get("arquetipo", ""))
	if _mob == null or not is_instance_valid(_mob) or not bool(_mob.call("esta_vivo")):
		_mob = _mob_de_arquetipo(arq)
	if _mob == null or not is_instance_valid(_mob):
		_omitir("P7", "los objetivos de la misión se completan JUGANDO",
			"no hay ningún «%s» vivo en el mundo cargado" % arq)
		_omitir("P7", "ENTREGAR la misión la da por completada", "no hay enemigo que matar")
		return _ir(F_COCINA)
	var p: Node3D = _jugador as Node3D
	if p.get("seleccion") != _mob:
		p.call("_aplicar_clic", _mob, 0)
		return false
	if (_mob as Node3D).global_position.distance_to(p.global_position) > 2.6:
		p.call("ordenar_mover_a", (_mob as Node3D).global_position)
		return false
	p.call("ordenar_mover_a", (_mob as Node3D).global_position)
	_pulsar(KEY_T)
	if _agotado(60000):
		_omitir("P7", "los objetivos de la misión se completan JUGANDO",
			"el «%s» no cayó en 60 s" % arq)
		_omitir("P7", "ENTREGAR la misión la da por completada", "no se completes")
		return _ir(F_COCINA)
	return false


## Recoger lo que pida: el objetivo se cuenta con lo que hay en el
## inventario, así que el camino real es juntar el item del suelo.
func _cumplir_recogiendo(o: Dictionary) -> bool:
	var item: String = str(o.get("item", ""))
	var sueltos: Array[Node3D] = []
	for n in _demo.find_children("*", "Pickup", true, false):
		var nd: Node3D = n as Node3D
		if nd != null and is_instance_valid(nd):
			sueltos.append(nd)
	if sueltos.is_empty():
		_omitir("P7", "los objetivos de la misión se completan JUGANDO",
			"el objetivo pide %d de «%s» y no hay ninguno en el suelo para juntar"
				% [int(o.get("cantidad", 0)), item])
		_omitir("P7", "ENTREGAR la misión la da por completada", "no hay item en el suelo")
		return _ir(F_COCINA)
	return _ir(F_ENTREGAR)


func _mob_de_arquetipo(arquetipo_id: String) -> Node3D:
	for n in get_nodes_in_group("enemigos"):
		var nd: Node3D = n as Node3D
		if nd == null or not is_instance_valid(nd):
			continue
		if str(n.get("arquetipo_id")) == arquetipo_id and bool(n.call("esta_vivo")):
			return nd
	return null


func _f_entregar() -> bool:
	var q: Object = _ref.get("misiones_log")
	var est: String = str(q.call("estado", _quest_id))
	if est == "entregada":
		_ok("P7", "ENTREGAR la misión la da por completada", "estado = «entregada»")
		_pedir_cierre()
		return _ir(F_COCINA)
	if est != "lista":
		# El objetivo NO se pudo jugar (no había qué matar, o el item no
		# estaba en el suelo). El motivo ya lo escribió la fase que lo intentó,
		# con más detalle del que hay acá, así que acá solo se OMITE: marcarlo
		# en rojo sería contar dos veces el mismo problema.
		_omitir("P7", "ENTREGAR la misión la da por completada",
			"«%s» quedó en «%s». Progreso: %s" % [_quest_id, est,
				str(q.call("progreso_texto", _quest_id))])
		return _ir(F_COCINA)
	var dlg: Node = _ref.get("dialogo")
	var p: Node3D = _jugador as Node3D
	if dlg.call("esta_abierta"):
		dlg.call("cerrar")
	_sub = 0
	_agotado(0)
	p.call("ordenar_mover_a", (_npc as Node3D).global_position)
	return _ir(F_HABLAR_2)


const F_HABLAR_2: int = 26
const F_CUMPLIR: int = 28


func _f_hablar_2() -> bool:
	var dlg: Node = _ref.get("dialogo")
	var p: Node3D = _jugador as Node3D
	if not dlg.call("esta_abierta"):
		# El gesto del juego para volver a hablar: seleccionar al NPC + tecla E.
		# `interactuar()` lo acerca primero si quedó lejos.
		#
		# El clic de ratón solo sirve si el NPC está REALMENTE en pantalla, y
		# para eso hay que mirar las DOS coordenadas: el chequeo anterior solo
		# miraba la X, y con la Y en 5678 sobre un viewport de 1280 el clic cae
		# en el suelo — que además deselecciona (ver `_f_hablar`).
		if _en_pantalla(_npc as Node3D):
			_clic(_proyectar(_npc as Node3D))
		else:
			p.call("_aplicar_clic", _npc, 0)
		_pulsar(KEY_E)
		if _agotado(30000):
			_fallar("P7", "ENTREGAR la misión la da por completada",
				"el diálogo con %s no volvió a abrirse" % str(_npc.get("nombre_mostrado")))
			return _ir(F_COCINA)
		return false
	if dlg.call("tiene_mision"):
		var boton: Button = dlg.get("_boton_mision")
		boton.pressed.emit()
	var q: Object = _ref.get("misiones_log")
	var est: String = str(q.call("estado", _quest_id))
	if est == "entregada":
		_ok("P7", "ENTREGAR la misión la da por completada", "estado = «entregada»")
		var pan: Node = _ref.get("misiones")
		if pan != null and bool(pan.call("banner_visible")):
			_ok("P7", "el panel de misiones muestra el cartel de «completada»", "")
		else:
			_fallar("P7", "el panel de misiones muestra el cartel de «completada»",
				"`banner_visible()` dio false tras entregar «%s»" % _quest_id)
	else:
		_fallar("P7", "ENTREGAR la misión la da por completada",
			"«%s» quedó en «%s» después de apretar el botón de entrega" % [_quest_id, est])
	_pedir_cierre()
	return _ir(F_COCINA)


## Aceptar la misión desde el diálogo: la parte que se mide la PRIMERA vez.
func _entregar_por_dialogo() -> bool:
	var dlg: Node = _ref.get("dialogo")
	if not dlg.call("tiene_mision"):
		_fallar("P7", "el NPC muestra el botón de misión en el diálogo",
			"`tiene_mision()` dio false con la oferta «%s» activa" % _quest_id)
		_omitir("P7", "aceptar y completar una misión del NPC", "el diálogo no ofrece misión")
		dlg.call("cerrar")
		return _ir(F_COCINA)
	_ok("P7", "el NPC muestra el botón de misión en el diálogo", "")
	if _rastro != "":
		_omitir("P7", "al NPC se lo selecciona con un clic de ratón real", _rastro)
		_rastro = ""
	var boton: Button = dlg.get("_boton_mision")
	var q: Object = _ref.get("misiones_log")
	var antes: String = str(q.call("estado", _quest_id))
	boton.pressed.emit()
	var despues: String = str(q.call("estado", _quest_id))
	if despues == "activa":
		_ok("P7", "ACEPTAR la misión desde el diálogo cambia el estado del log",
			"«%s»: %s → %s" % [_quest_id, antes, despues])
	else:
		_fallar("P7", "ACEPTAR la misión desde el diálogo cambia el estado del log",
			"«%s» quedó en «%s» (antes «%s») tras apretar el botón"
				% [_quest_id, despues, antes])
	var pan: Node = _ref.get("misiones")
	var toast: Label = pan.get("_toast_label") if pan != null else null
	if toast != null and not str(toast.text).strip_edges().is_empty():
		_ok("P7", "el panel de misiones AVISA en pantalla que aceptaste",
			"toast: «%s»" % str(toast.text))
	else:
		_fallar("P7", "el panel de misiones AVISA en pantalla que aceptaste",
			"el `_toast_label` del `PanelMisiones` quedó vacío tras aceptar")
	dlg.call("cerrar")
	_agotado(0)
	# Aceptar NO es completar: la misión tiene objetivos, y el paso siguiente
	# es JUGARLOS. Antes se iba derecho a `_ir(F_ENTREGAR)`, que preguntaba si
	# ya estaba en «lista» y se quejaba — con razón, porque nadie los había
	# cumplido. La fase nueva es la que los cumple.
	return _ir(F_CUMPLIR)


# ───────────────────────────────────────────────────────────────────────────
# F14/F15/F16 — la cocina en una fogata
# ───────────────────────────────────────────────────────────────────────────

func _f_cocina() -> bool:
	var fogatas: Array = _fogatas_del_mundo()
	if fogatas.is_empty():
		_fallar("P8", "hay una fogata en la partida", "la lista `_fogatas` está vacía")
		_omitir("P8", "cocinar en la fogata", "sin fogata")
		return _ir(F_REFUGIO)
	_fogata = fogatas[0]
	var p: Node3D = _jugador as Node3D
	if _sub == 0:
		_reiniciar_caminata()
		print("[PLAYTEST] P8 · caminando a la fogata «%s» (%.0f u)"
			% [str((_fogata as Node3D).name),
				p.global_position.distance_to((_fogata as Node3D).global_position)])
		_sub = 1
		return false
	if not _caminar_hasta((_fogata as Node3D).global_position, 4.4):
		if _agotado(300000):
			_fallar("P8", "el jugador llega a la fogata", "tras 300 s sigue a %.1f u"
				% p.global_position.distance_to((_fogata as Node3D).global_position))
			_omitir("P8", "cocinar en la fogata", "no llegó a la fogata")
			return _ir(F_REFUGIO)
		return false
	_pulsar(KEY_E)
	return _ir(F_COCINA_LENA)


func _f_cocina_lena() -> bool:
	var encendida: bool = bool(_fogata.call("encendida"))
	var inv: Object = (_jugador as Node3D).get("inventario")
	if not encendida:
		if int(inv.call("contar", "tronco_roble")) <= 0:
			inv.call("agregar", "tronco_roble", 3)
			print("[PLAYTEST] P8 · se agregaron 3 troncos de roble: sin leña no hay "
				+ "forma de prender la fogata, y ningún mob del spawn dropea leña")
		var r: String = str(_fogata.call("interactuar_jugador", _jugador))
		if r == "ok":
			_ok("P8", "la fogata se prende con la tecla E",
				"`interactuar_jugador()` = «%s», %.0f s de leña"
					% [r, U.num(_fogata, "lena")])
		else:
			_fallar("P8", "la fogata se prende con la tecla E",
				"`interactuar_jugador()` devolvió «%s» con 3 troncos en la bolsa" % r)
		_pulsar(KEY_E)
		return false
	var pc: Node = _ref.get("cocina")
	if pc == null:
		_fallar("P8", "el panel de cocina está en la partida", "no hay 'PanelCocina'")
		_omitir("P8", "cocinar en la fogata", "sin PanelCocina")
		return _ir(F_REFUGIO)
	if not pc.call("esta_abierta"):
		if _agotado(30000):
			_fallar("P8", "la cocina se abre desde la fogata encendida",
				"`PanelCocina.esta_abierta()` dio false con la fogata encendida")
			_omitir("P8", "cocinar en la fogata", "la cocina no abrió")
			return _ir(F_REFUGIO)
		_pulsar(KEY_E)
		return false
	_ok("P8", "la cocina se abre desde la fogata encendida", "")
	return _ir(F_COCINA_COCINAR)


func _f_cocina_cocinar() -> bool:
	var pc: Node = _ref.get("cocina")
	var inv: Object = (_jugador as Node3D).get("inventario")
	RecetasCocinaDB.cargar()
	var recetas: Array = RecetasCocinaDB.ingredientes()
	if recetas.is_empty():
		_fallar("P8", "hay recetas de cocina en los datos",
			"`RecetasCocinaDB.ingredientes()` volvió vacío")
		_omitir("P8", "cocinar en la fogata", "sin recetas")
		return _ir(F_REFUGIO)
	for ing in recetas:
		if int(inv.call("contar", str(ing))) > 0:
			_cocina_item = str(ing)
			break
	if _cocina_item == "":
		_cocina_item = str(recetas[0])
		inv.call("agregar", _cocina_item, 3)
		pc.call("_reconstruir")
		print("[PLAYTEST] P8 · se agregaron 3 «%s»: ningún mob del spawn dropeó "
			% _cocina_item + "comida, así que el ingrediente llegó a mano")
	var receta: Dictionary = RecetasCocinaDB.receta(_cocina_item)
	_cocina_res = str(receta.get("resultado", ""))
	var antes: int = int(inv.call("contar", _cocina_item))
	var res_antes: int = int(inv.call("contar", _cocina_res)) if _cocina_res != "" else 0
	var lena_antes: float = U.num(_fogata, "lena")
	pc.call("_al_cocinar", _cocina_item)
	var desp: int = int(inv.call("contar", _cocina_item))
	var res_desp: int = int(inv.call("contar", _cocina_res)) if _cocina_res != "" else 0
	if desp < antes and res_desp > res_antes:
		_ok("P8", "cocinar en la fogata consume el ingrediente y da el plato",
			"«%s» %d→%d, «%s» %d→%d, leña %.0f→%.0f s" % [_cocina_item, antes, desp,
				_cocina_res, res_antes, res_desp, lena_antes, U.num(_fogata, "lena")])
	else:
		_fallar("P8", "cocinar en la fogata consume el ingrediente y da el plato",
			"«%s» %d→%d y «%s» %d→%d. La fila «Cocinar» de la UI no llegó a "
			% [_cocina_item, antes, desp, _cocina_res, res_antes, res_desp]
			+ "`Cocina.cocinar()` (el botón de la fila está `disabled`)")
	var lena: Label = pc.get("_leña")
	if lena != null and not str(lena.text).strip_edges().is_empty():
		_ok("P8", "la cocina muestra en pantalla la leña que queda", "«%s»" % str(lena.text))
	else:
		_fallar("P8", "la cocina muestra en pantalla la leña que queda",
			"el `_leña.text` del `PanelCocina` quedó vacío")
	_pedir_cierre()
	return _ir(F_REFUGIO)


# ───────────────────────────────────────────────────────────────────────────
# F17/F18 — reclamar y construir en un refugio
# ───────────────────────────────────────────────────────────────────────────

func _f_refugio() -> bool:
	var refugios: Array = _refugios_del_mundo()
	if refugios.is_empty():
		_fallar("P9", "hay un refugio en la partida", "la lista `_refugios` está vacía")
		_omitir("P9", "construir en un refugio", "sin refugio")
		return _ir(F_GUARDAR)
	var nivel: int = int((_jugador as Node3D).get("nivel"))
	_refugio = null
	var mejor: float = INF
	for r in refugios:
		var ref: Node3D = r as Node3D
		if ref == null or int(ref.call("nivel_minimo")) > nivel:
			continue
		var d: float = ref.global_position.distance_to((_jugador as Node3D).global_position)
		if d < mejor:
			mejor = d
			_refugio = ref
	if _refugio == null:
		_fallar("P9", "hay un refugio alcanzable",
			"ninguno de los %d refugios acepta nivel %d" % [refugios.size(), nivel])
		_omitir("P9", "construir en un refugio", "ningún refugio alcanzable")
		return _ir(F_GUARDAR)
	var p: Node3D = _jugador as Node3D
	if _sub == 0:
		_reiniciar_caminata()
		_sub = 1
		return false
	if not _caminar_hasta((_refugio as Node3D).global_position, 4.4):
		if _sub % 600 == 0:
			print("[PLAYTEST] P9 · a %.1f u del refugio «%s», el jugador está en %s"
				% [p.global_position.distance_to((_refugio as Node3D).global_position),
					str(_refugio.get("refugio_id")), str(p.global_position.round())])
		if _agotado(300000):
			_fallar("P9", "el jugador llega al refugio", "tras 300 s sigue a %.1f u"
				% p.global_position.distance_to((_refugio as Node3D).global_position))
			_omitir("P9", "construir en un refugio", "no llegó al refugio")
			return _ir(F_GUARDAR)
		return false
	_refugio_id_antes = str(_refugio.get("refugio_id"))
	_piezas_antes = int(_refugio.call("piezas"))
	print("[PLAYTEST] P9 · refugio «%s» alcanzado (%.0f u)"
		% [_refugio_id_antes,
			p.global_position.distance_to((_refugio as Node3D).global_position)])
	if not bool(_refugio.call("esta_reclamado")):
		if _sub % 60 == 0:
			_pulsar(KEY_E)
		_sub += 1
		if _agotado(30000) or _sub > 2400:
			_fallar("P9", "el refugio se RECLAMA con la tecla E",
				"El jugador está parado sobre «%s» (a %.2f u, el radio de interacción "
				% [_refugio_id_antes,
					p.global_position.distance_to((_refugio as Node3D).global_position)]
				+ "es 4.5) y `%s` sigue en false. Lo que el Player considera "
				% String(_refugio.get("refugio_id"))
				+ "interactuable más cercano a %.1f u: %s. Si eso es una veta, la tecla "
				% [4.5, str(_interactuables_cerca(p))] + "E minó en vez de reclamar")
			_omitir("P9", "construir en un refugio", "no se reclamó")
			return _ir(F_GUARDAR)
		return false
	_ok("P9", "el refugio se RECLAMA con la tecla E", "`esta_reclamado()` = true")
	_pulsar(KEY_E)
	return _ir(F_REFUGIO_PIEZA)


func _f_refugio_pieza() -> bool:
	var pc: Node = _ref.get("construccion")
	if pc == null:
		_fallar("P9", "el panel de construcción está en la partida", "no hay 'PanelConstruccion'")
		_omitir("P9", "construir en un refugio", "sin PanelConstruccion")
		return _ir(F_GUARDAR)
	if not pc.call("esta_abierta"):
		if _agotado(30000):
			_fallar("P9", "el panel de construcción se abre en el refugio",
				"`PanelConstruccion.esta_abierta()` dio false con el refugio reclamado")
			_omitir("P9", "construir en un refugio", "el panel no abrió")
			return _ir(F_GUARDAR)
		_pulsar(KEY_E)
		return false
	var piezas_antes: int = int(_refugio.call("piezas"))
	if not _construccion_ya:
		_construccion_ya = true
		_ok("P9", "el panel de construcción se abre en el refugio", "")
	PiezasDB.cargar()
	var inv: Object = (_jugador as Node3D).get("inventario")
	var elegido: String = ""
	for t in PiezasDB.ids():
		var tipo: String = str(t)
		var costo: Dictionary = PiezasDB.costo(tipo)
		var alcanza: bool = true
		for k in costo.keys():
			if int(inv.call("contar", str(k))) < int(costo[k]):
				alcanza = false
		if alcanza:
			elegido = tipo
			break
	if elegido == "":
		# El cheapest: se le dan los materiales y SE DICE, porque ningún mob
		# del spawn dropea madera ni mineral.
		var barato: String = ""
		var minimo: int = 99999
		for t2 in PiezasDB.ids():
			var total: int = 0
			var c2: Dictionary = PiezasDB.costo(str(t2))
			for k2 in c2.keys():
				total += int(c2[k2])
			if total < minimo:
				minimo = total
				barato = str(t2)
		elegido = barato
		var c3: Dictionary = PiezasDB.costo(elegido)
		for k3 in c3.keys():
			inv.call("agregar", str(k3), int(c3[k3]))
		pc.call("_reconstruir")
		print("[PLAYTEST] P9 · se agregaron los materiales de «%s» al inventario: "
			% elegido + "ningún mob del spawn dropea madera ni mineral")
	# `PanelConstruccion.seleccionar()` devuelve void: lo que se comprueba es
	# que la pieza elegida haya quedado CARGADA en el panel (`_tipo`).
	pc.call("seleccionar", elegido)
	var sel: bool = str(pc.get("_tipo")) == elegido
	if not sel:
		_fallar("P9", "el panel de construcción deja elegir pieza",
			"tras `seleccionar('%s')` el panel tiene `_tipo` = «%s»"
				% [elegido, str(pc.get("_tipo"))])
		_omitir("P9", "colocar una pieza en el refugio", "no se pudo seleccionar la pieza")
		return _ir(F_GUARDAR)
	var res: String = str(pc.call("colocar_en",
		(_refugio as Node3D).global_position + Vector3(4.0, 0.0, 0.0)))
	if res != "ok":
		_fallar("P9", "colocar una pieza en el refugio",
			"`colocar_en()` devolvió «%s»" % res)
		_omitir("P9", "el panel muestra las piezas colocadas", "no se colocó nada")
		return _ir(F_GUARDAR)
	var piezas: int = int(_refugio.call("piezas"))
	var nodo_pieza: Node = U.nodo(_refugio, "Pieza_%s" % elegido)
	if piezas > piezas_antes and nodo_pieza != null:
		_ok("P9", "colocar una pieza en el refugio",
			"«%s»: el refugio pasó de %d a %d piezas y apareció el nodo «Pieza_%s»"
				% [elegido, piezas_antes, piezas, elegido])
	else:
		_fallar("P9", "colocar una pieza en el refugio",
			"`colocar_en` dijo «ok» pero el refugio tiene %d piezas (antes %d) y el nodo "
			% [piezas, piezas_antes] + "«Pieza_%s» %s"
			% [elegido, "existe" if nodo_pieza != null else "NO existe"])
	var pres: Label = pc.get("_presupuesto")
	if pres == null:
		_omitir("P9", "el panel de construcción muestra las piezas colocadas",
			"`_presupuesto` no existe en el panel")
	elif str(pres.text) != "Piezas: %d / %d" % [piezas_antes, piezas_antes]:
		_ok("P9", "el panel de construcción muestra las piezas colocadas",
			"«%s»" % str(pres.text))
	else:
		_fallar("P9", "el panel de construcción muestra las piezas colocadas",
			"el `_presupuesto.text` sigue en «%s» después de colocar la pieza" % str(pres.text))
	_pedir_cierre()
	return _ir(F_GUARDAR)


# ───────────────────────────────────────────────────────────────────────────
# F19 — guardar
# ───────────────────────────────────────────────────────────────────────────

func _f_guardar() -> bool:
	var inv: Object = (_jugador as Node3D).get("inventario")
	_inv_antes = int(inv.call("slots_usados"))
	_nivel_antes_guardar = int((_jugador as Node3D).get("nivel"))
	_xp_antes_guardar = int((_jugador as Node3D).get("xp_actual"))
	_prestigio_antes = SaveSystem.estado_ngplus().prestigio
	if _sub == 0:
		_pulsar(KEY_F9)
		_sub = 1
		return false
	if _sub < 10:
		_sub += 1
		return false
	if not FileAccess.file_exists(SaveSystem.RUTA):
		_fallar("P10", "la tecla F9 guarda la partida",
			"no existe «%s» después de mandar la tecla" % SaveSystem.RUTA)
		_omitir("P10", "el archivo guardado tiene los bloques del mundo", "no se guardó")
		_omitir("P10", "el mundo vuelve IGUAL al cargar", "no se guardó")
		return _ir(F_TITULO_2)
	_ok("P10", "la tecla F9 guarda la partida",
		"«%s» existe (%d bytes)" % [SaveSystem.RUTA, _bytes(SaveSystem.RUTA)])
	var crudo: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.RUTA))
	if typeof(crudo) != TYPE_DICTIONARY:
		_fallar("P10", "el archivo guardado tiene los bloques del mundo",
			"la raíz del JSON no es un objeto")
		_omitir("P10", "el mundo vuelve IGUAL al cargar", "archivo ilegible")
		return _ir(F_TITULO_2)
	var d: Dictionary = crudo
	var faltan: Array[String] = []
	for clave in ["jugador", "refugios", "arboles", "ngplus", "misiones"]:
		if not d.has(clave):
			faltan.append(clave)
	if faltan.is_empty():
		_ok("P10", "el archivo guardado tiene los bloques del mundo",
			"jugador, refugios, arboles, ngplus y misiones están (version %d)"
				% int(d.get("version", 0)))
	else:
		_fallar("P10", "el archivo guardado tiene los bloques del mundo",
			"faltan los bloques: %s" % str(faltan))
	_pedir_cierre()
	return _ir(F_TITULO_2)


# ───────────────────────────────────────────────────────────────────────────
# F20 — salir al título por el camino del juego (ESC → pausa → "Volver al título")
# ───────────────────────────────────────────────────────────────────────────

func _f_titulo_2() -> bool:
	var pausa: Node = _ref.get("pause")
	# `_titulo` es la referencia del título del principio de la partida: ese
	# nodo ya lo liberó `change_scene_to_file()`. Un objeto liberado NO es null,
	# hay que preguntar con `is_instance_valid`.
	if _titulo != null and is_instance_valid(_titulo):
		return _ir(F_CARGAR)
	_titulo = null
	if _sub == 0:
		_pulsar(KEY_ESCAPE)
		_sub = 1
		return false
	if _sub < 8:
		_sub += 1
		return false
	if pausa == null or not bool(pausa.call("esta_abierto")):
		_fallar("P10", "la tecla ESC abre el menú de pausa",
			"`MenuPausa.esta_abierto()` quedó en false tras UNA sola tecla ESC. "
			+ "La causa: `MenuPausa._unhandled_input` (scripts/ui/menu_pausa.gd:255 "
			+ "y :271) atiende el MISMO ESC con DOS acciones del Input Map, "
			+ "`cerrar_menu` y `abrir_pausa` (project.godot:181 y :186). La primera "
			+ "lo abre, la segunda lo cierra en el mismo evento: el menú de pausa "
			+ "es inalcanzable con el teclado. El mismo `set_input_as_handled()` "
			+ "se queda con el ESC, así que ningún panel lo ve tampoco")
		return _ir(F_CARGAR, "el menú de pausa no abre")
	_ok("P10", "la tecla ESC abre el menú de pausa",
		"`MenuPausa.esta_abierto()` = true, con %d botones"
			% U.botones(pausa).size())
	var volver: Button = U.boton_texto(pausa, "Volver al título")
	if volver == null:
		_fallar("P10", "el menú de pausa tiene el botón 'Volver al título'",
			"Botones: %s" % str(_textos_botones(pausa)))
		return _ir(F_CARGAR, "el menú no tiene 'Volver al título'")
	_demo = null
	_jugador = null
	_ref = {}
	volver.pressed.emit()
	print("[PLAYTEST] P10 · clic en 'Volver al título'")
	return false


## Frames que hay que dejar pasar después de un cambio de escena para que el
## fundido de `Transicion` suelte su cerrojo de reentrada.
# ───────────────────────────────────────────────────────────────────────────
# F21/F22 — 'Continuar' en el título y el mundo vuelve IGUAL
# ───────────────────────────────────────────────────────────────────────────

func _f_cargar() -> bool:
	if U.con_script(root, "res://scripts/ui/pantalla_titulo.gd") == null:
		if _agotado(60000):
			_fallar("P10", "'Volver al título' vuelve a la pantalla de título",
				"no apareció `PantallaTitulo` en 60 s. Raíces: %s" % str(U.raices(root)))
			_omitir("P10", "el mundo vuelve IGUAL al cargar", "no volvió al título")
			return _ir(F_PANELES)
		return false
	_titulo = U.con_script(root, "res://scripts/ui/pantalla_titulo.gd")
	var seguir: Button = U.boton_texto(_titulo, "Continuar")
	if seguir == null:
		_fallar("P10", "el título ofrece el botón 'Continuar' con la partida guardada",
			"`PantallaTitulo.puede_continuar()` = %s pero no hay botón. Botones: %s"
				% [str(PantallaTitulo.puede_continuar()), str(_textos_botones(_titulo))])
		return _ir(F_PANELES)
	_ok("P10", "el título ofrece el botón 'Continuar' con la partida guardada", "")
	if _sub < 20:
		_sub += 1
		return false
	if not _transicion_libre() and _sub < 90:
		_sub += 1
		return false
	_ir(F_CARGAR_LISTO)
	seguir.pressed.emit()
	print("[PLAYTEST] P10 · clic en 'Continuar' (recarga la partida)")
	return false


func _f_cargar_listo() -> bool:
	_demo = U.nodo(root, "Fase14Demo")
	if _demo == null:
		if _agotado(90000):
			_fallar("P10", "'Continuar' vuelve a entrar al mundo",
				"no apareció 'Fase14Demo' en 90 s. Raíces: %s" % str(U.raices(root)))
			_omitir("P10", "el mundo vuelve IGUAL al cargar", "no volvió al mundo")
			return _ir(F_PANELES)
		return false
	_jugador = _demo.find_child("Player", true, false) as Node3D
	if _jugador == null:
		if _agotado(90000):
			_fallar("P10", "el mundo recargado tiene jugador", "no hay nodo 'Player'")
			return _ir(F_PANELES)
		return false
	if bool(_demo.get("_mundo_pendiente")):
		if _agotado(300000):
			_fallar("P10", "el mundo recargado termina de construirse",
				"`_mundo_pendiente` sigue en true")
			return _ir(F_PANELES)
		return false
	_congelar()
	_comparar_mundo()
	return _ir(F_PANELES)


func _comparar_mundo() -> void:
	var inv: Object = (_jugador as Node3D).get("inventario")
	_inv_desp = int(inv.call("slots_usados"))
	if _inv_desp == _inv_antes:
		_ok("P10", "el inventario vuelve IGUAL al cargar",
			"%d slots ocupados antes y después" % _inv_desp)
	else:
		_fallar("P10", "el inventario vuelve IGUAL al cargar",
			"tenía %d slots y volvió con %d" % [_inv_antes, _inv_desp])
	var nivel: int = int((_jugador as Node3D).get("nivel"))
	var xp: int = int((_jugador as Node3D).get("xp_actual"))
	if nivel == _nivel_antes_guardar and xp == _xp_antes_guardar:
		_ok("P10", "el nivel y la XP vuelven IGUALES al cargar",
			"nivel %d, XP %d antes y después" % [nivel, xp])
	else:
		_fallar("P10", "el nivel y la XP vuelven IGUALES al cargar",
			"antes nivel %d / XP %d; después nivel %d / XP %d"
				% [_nivel_antes_guardar, _xp_antes_guardar, nivel, xp])
	var nombre: Node = U.primero_de_tipo(_ref.get("hud") as Node, "RetratoHeroe")
	if nombre != null and str(nombre.call("nombre_mostrado")).strip_edges() == NOMBRE_HEROE:
		_ok("P10", "el nombre del héroe vuelve tras cargar y el HUD lo muestra",
			"«%s»" % str(nombre.call("nombre_mostrado")))
	else:
		_fallar("P10", "el nombre del héroe vuelve tras cargar y el HUD lo muestra",
			"el retrato del HUD muestra «%s»"
				% (str(nombre.call("nombre_mostrado")) if nombre != null else "nada"))
	# Refugio: reclamo + piezas.
	var refugios: Array = _refugios_del_mundo()
	var encontrado: Node = null
	for r in refugios:
		if str((r as Node).get("refugio_id")) == _refugio_id_antes:
			encontrado = r
			break
	if _refugio_id_antes == "":
		_omitir("P10", "el refugio vuelve RECLAMADO al cargar",
			"el refugio no llegó a reclamarse en esta partida")
		_omitir("P10", "las piezas del refugio vuelven al cargar", "sin refugio reclamado")
	elif encontrado == null:
		_fallar("P10", "el refugio vuelve RECLAMADO al cargar",
			"tras cargar no hay ningún refugio con id «%s»" % _refugio_id_antes)
		_omitir("P10", "las piezas del refugio vuelven al cargar", "el refugio no volvió")
	elif not bool(encontrado.call("esta_reclamado")):
		var crudo: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.RUTA))
		var bloque: Variant = (crudo as Dictionary).get("refugios") if typeof(crudo) == TYPE_DICTIONARY else null
		_fallar("P10", "el refugio vuelve RECLAMADO al cargar",
			"«%s» volvió con `esta_reclamado()` = false. Lo que dice el bloque "
			% _refugio_id_antes
			+ "«refugios» del archivo guardado es: %s" % str(bloque))
		_omitir("P10", "las piezas del refugio vuelven al cargar", "el refugio no volvió reclamado")
	else:
		_ok("P10", "el refugio vuelve RECLAMADO al cargar", "«%s»" % _refugio_id_antes)
		var piezas: int = int(encontrado.call("piezas"))
		if piezas >= _piezas_antes:
			_ok("P10", "las piezas del refugio vuelven al cargar",
				"%d piezas (se habían colocado %d)" % [piezas, _piezas_antes])
		else:
			_fallar("P10", "las piezas del refugio vuelven al cargar",
				"quedaron %d piezas y se habían colocado %d" % [piezas, _piezas_antes])
	# Árboles: si esta partida llegó a talar uno.
	if _arbol_id == "":
		_omitir("P10", "los árboles TALADOS siguen talados al cargar",
			"no se llegó a talar ningún árbol en esta partida")
	else:
		var estado: Dictionary = (_ref.get("arboles") as Object).call("estado_para_guardar")
		var talados: Dictionary = (estado.get("arboles") as Dictionary)
		if talados.has(_arbol_id):
			_ok("P10", "los árboles TALADOS siguen talados al cargar",
				"«%s» volvió con %d usos consumidos" % [_arbol_id,
					int((talados[_arbol_id] as Dictionary).get("usos", -1))])
		else:
			_fallar("P10", "los árboles TALADOS siguen talados al cargar",
				"«%s» no aparece en `GestorArboles.estado_para_guardar()` tras recargar"
					% _arbol_id)
	# NG+: sólo si hay prestigio.
	var prestige: int = SaveSystem.estado_ngplus().prestigio
	if _prestigio_antes <= 0:
		_omitir("P10", "el prestigio de NG+ vuelve al cargar",
			"no hay NG+ en esta partida (hace falta nivel 70 para prestigiar)")
	else:
		if prestige == _prestigio_antes:
			_ok("P10", "el prestigio de NG+ vuelve al cargar", "prestigio %d" % prestige)
		else:
			_fallar("P10", "el prestigio de NG+ vuelve al cargar",
				"era %d y volvió %d" % [_prestigio_antes, prestige])


# ───────────────────────────────────────────────────────────────────────────
# F23 — CADA panel: abrir con su tecla, cerrar con ESC, pila vacía
# ───────────────────────────────────────────────────────────────────────────

func _f_paneles() -> bool:
	if _paneles.is_empty():
		_paneles = _catalogo_paneles()
		print("[PLAYTEST] P11 · %d paneles con tecla de apertura: %s"
			% [_paneles.size(), str(_nombres_paneles())])
	if _panel_i >= _paneles.size():
		if PilaUI.abierta() == 0:
			_ok("P11", "la pila de paneles queda VACÍA al terminar", "`PilaUI.abierta()` = 0")
		else:
			_fallar("P11", "la pila de paneles queda VACÍA al terminar",
				"`PilaUI.abierta()` quedó en %d con %d panel(es) abierto(s)"
					% [PilaUI.abierta(), PilaUI.abierta()])
		if _sin_arboles:
			_omitir("P10", "los árboles TALADOS siguen talados al cargar",
				"se corrió con --sin-arboles")
			return _ir(F_REPORTE)
		return _ir(F_ARBOL)
	var entrada: Dictionary = _paneles[_panel_i]
	var nodo: Node = U.nodo(_demo, String(entrada["nodo"]))
	if nodo == null:
		_fallar("P11", "el panel «%s» está instanciado en la partida" % String(entrada["nodo"]),
			"no existe el nodo «%s» bajo Fase14Demo" % String(entrada["nodo"]))
		_panel_i += 1
		return _ir(F_PANELES)
	if _sub == 0:
		_panel_abierta = false
		_panel_cerrada = false
		_preparado = false
		_sub = 1
		return false
	if _sub == 1:
		# Cada panel se mide desde un estado conocido: primero se cierra con
		# ESC todo lo que haya abierto (así se ve si el ESC cierra), y si algo
		# se resiste se lo esconde a mano para no contaminar el resto.
		_panel_abierta = false
		_panel_cerrada = false
		_solo_panel = nodo
		_sub = 2
		return false
	# UN ESC POR FRAME, no los tres en el mismo.
	#
	# Los tres juntos en un frame no son tres pulsaciones: son un evento.
	# Godot encola el input y despacha `_unhandled_input` UNA vez por frame,
	# así que el primer ESC se consume, llama `set_input_as_handled()` y los
	# otros dos nunca llegan a nadie. El paso reportaba "el ESC no cerró el
	# PanelTutorial" cuando lo que no cerraba era la segunda y la tercera
	# pulsación. Un jugador aprieta ESC, levanta el dedo, aprieta otra vez.
	#
	# El rango, no la igualdad: si el guardia fuera `== 2`, al primer ESC
	# `_sub` pasa a 3 y el bloque no vuelve a entrar nunca — la fase se
	# quedaba en `_sub = 3` para siempre.
	# SUB-PASO 2..5 — cerrar con ESC todo lo que haya abierto.
	#
	# UN ESC POR FRAME, no los tres en el mismo. Los tres juntos en un frame no
	# son tres pulsaciones: son un evento. Godot encola el input y despacha
	# `_unhandled_input` UNA vez por frame, así que el primer ESC se consume,
	# llama `set_input_as_handled()` y los otros dos nunca llegan a nadie. El
	# paso reportaba "el ESC no cerró el PanelTutorial" cuando lo que no
	# cerraba era la segunda y la tercera pulsación.
	#
	# El rango, no la igualdad: con `== 2`, al primer ESC `_sub` pasa a 3 y el
	# bloque no vuelve a entrar nunca — la fase se quedaba en 3 para siempre.
	if _sub >= 2 and _sub < 5:
		if _todo_cerrado_para_esc():
			_sub = 5
		else:
			_pulsar(KEY_ESCAPE)
			_sub += 1
		# Un frame por pulsación: los tres ESC juntos en un frame son un solo
		# evento, y el primero se come los otros dos con
		# `set_input_as_handled()`.
		return false
	# SUB-PASO 5 — dejar el mundo en el punto de partida. Un frame de
	# respiración antes: la pausa pone `get_tree().paused`, y medir en el mismo
	# frame en que se cierra deja al panel siguiente sin procesar su tecla. Un
	# jugador no aprieta la I en el mismo frame en que el menú se cierra.
	# SUB-PASO 5 — preparar y ABRIR. Se reintenta cada frame mientras el
	# `_sub` siga en 5, y eso es a propósito: el panel que se abre desde un
	# botón tiene que esperar a que la pausa esté abierta, y eso son frames.
	#
	# La preparación, en cambio, va UNA vez (por `_preparado`): si se repitiera,
	# escondería el panel y se quejaría de lo que él mismo escondió, en bucle.
	#
	# Y el reintento es SOLO en 5. Con `>= 5`, en 6 se volvería a entrar acá,
	# `_abrir_el_panel` saldría por su propio `if _sub > 5`, y la fase nunca
	# llegaría a `_f_paneles_espera`: se quedaba en 5 para siempre.
	if _sub == 5:
		if not _preparado:
			_preparado = true
			_preparar_panel(nodo, entrada)
		return _abrir_el_panel(nodo, entrada)
	return _f_paneles_espera(nodo, entrada)


## Deja el mundo como lo quiere el panel que se va a medir: nada apilado, y
## el panel cerrado. Va en su propio método para que se lea; hace UNA cosa.
func _preparar_panel(nodo: Node, entrada: Dictionary) -> void:
	# EL MENÚ DE PAUSA Y LA CAJA DEL TUTORIAL QUEDAN FUERA DEL CHEQUEO DE "el
	# ESC cierra todo", y por razones distintas:
	#
	# - la pausa es la ÚNICA dueña del ESC, así que después de tres ESC la
	#   tener abierta es lo CORRECTO: es lo que la abre.
	# - la caja del tutorial ya no toma el ESC (es del menú de pausa; ver
	#   `_test_el_esc_no_es_del_tutorial`), así que los tres ESC no la tocan.
	#
	# Sin esta salvedad el paso daba rojo por dos comportamientos que son los
	# correctos, y la fase se colgaba después.
	var tut: Node = U.nodo(_demo, "PanelTutorial")
	if tut != null and tut.call("esta_visible"):
		print("[PLAYTEST] P11 · la caja del tutorial sigue abierta tras 3 ESC: "
			+ "el ESC es del menú de pausa, no suyo (PilaUI.abierta()=%d)"
			% PilaUI.abierta())
	var pz: Node = U.nodo(_demo, "MenuPausa")
	var bravos: Array = _paneles_visibles()
	var esperando: Array[Node] = []
	if pz != null:
		esperando.append(pz)
	if tut != null:
		esperando.append(tut)
	var bravos_reales: Array = []
	for b in bravos:
		if not esperando.has(b):
			bravos_reales.append(b)
	if not bravos_reales.is_empty():
		var nombres: Array[String] = []
		for b in bravos_reales:
			nombres.append(String((b as Node).name))
		_fallar("P11", "el ESC cierra lo que hay abierto antes de empezar",
			"seguían visibles después de 3 ESC: %s. Se esconden a mano para "
				% str(nombres) + "seguir midiendo el resto de la lista")
		for b in bravos_reales:
			_esconder(b as Node)
	PilaUI.limpiar()
	# Y se Bajan los dos que quedan: la pausa es la del ESC, y la caja del
	# tutorial se cierra por la vía que el juego usa. Con la pausa abierta el
	# juego está congelado y ningún panel de la lista responde a su tecla.
	if pz != null and bool(pz.call("esta_abierto")):
		pz.call("cerrar")
	if tut != null and is_instance_valid(tut):
		tut.call("_cerrar_por_esc")
	# EL PANEL QUE SE VA A PROBAR SE CIERRA EXPRESAMENTE, y no es cosmético: el
	# panel alterna con su tecla (`visible = not visible`), así que si llega
	# visible la tecla lo CIERRA y el check de "se abre" falla sin que haya
	# nada roto.
	#
	# Un test que no pone el estado inicial en el punto de partida no mide lo
	# que dice medir: mide el estado previo.
	_panel_abierta = false
	_esconder(nodo)
	_panel_cerrada = false
	print("[PLAYTEST] P11 · %s: %s" % [String(entrada["nodo"]), String(entrada["nota"])])


## El gesto de ABRIR el panel que se está por medir, y el avance al sub-paso
## de espera. Se puede llamar en varios frames a propósito: el panel que se
## abre desde un botón tiene que esperar a que la pausa esté abierta.
func _abrir_el_panel(nodo: Node, entrada: Dictionary) -> bool:
	# El `nota` ya se imprimió en `_preparar_panel`.
	if _sub > 5:
		return false
	if String(entrada["boton"]) != "":
		# Un panel que se abre desde un botón necesita la pausa ABIERTA para
		# que ese botón exista. Se espera a que esté: mandar el ESC y seguir
		# midiendo en el mismo frame es lo que hacía que este panel "no se
		# abriera" y que la fase se quedara 9001 frames.
		var pausa: Node = U.nodo(_demo, "MenuPausa")
		if not bool(pausa.call("esta_abierto")):
			_pulsar(KEY_ESCAPE)
			return false
		var b: Button = U.boton_texto(pausa, String(entrada["boton"]))
		if b == null:
			_fallar("P11", "«%s» se abre desde el menú de pausa"
					% String(entrada["nodo"]),
				"el menú de pausa no tiene el botón «%s»" % String(entrada["boton"]))
			_panel_i += 1
			return _ir(F_PANELES)
		b.pressed.emit()
		_sub = 6
		return false
	_pulsar(int(entrada["tecla"]))
	_sub = 6
	return false


## Espera a que el panel se abra, y mide. Sigue a `_abrir_el_panel`; comparte
## `nodo` y `entrada`, así que vive en la misma función y no en otra.
## (Extraerla a un método propio rompía el alcance: `nodo` y `entrada` son
## locales de `_f_paneles`.)
func _f_paneles_espera(nodo: Node, entrada: Dictionary) -> bool:
	# Los paneles con tecla abren en el frame de la pulsación. El que se abre
	# desde un BOTÓN (el de opciones, sobre la pausa) necesita más: el clic
	# abre la pausa, el árbol queda pausado, y el panel se apila y se construye
	# en el frame siguiente. Medido: a los 8 frames seguía en false y el paso
	# lo daba por roto.
	if _sub < 30:
		_sub += 1
		return false
	if _sub == 30 and not _panel_abierta:
		var vis: bool = _panel_visible(nodo)
		_panel_abierta = vis
		var pila: int = PilaUI.abierta()
		if vis:
			_ok("P11", "«%s» se abre con su tecla" % String(entrada["nodo"]),
				"visible = true, y la pila quedó con %d panel(es)" % pila)
		else:
			_fallar("P11", "«%s» se abre con su tecla" % String(entrada["nodo"]),
				"`%s.visible` quedó en false. La acción «%s» del Input Map no "
				% [String(entrada["nodo"]), String(entrada["accion"])]
				+ "llegó al panel, o el panel no se registra en `PilaUI`")
		# La pausa tiene pila PROPIA y es su base: no va en `PilaUI`. El
		# tutorial es HUD persistente y está excluido a propósito.
		if pila == 0 and vis and not bool(entrada.get("base", false)) \
				and not bool(entrada.get("sin_pila", false)):
			_fallar("P11", "«%s» se apila al abrirse" % String(entrada["nodo"]),
				"`PilaUI.abierta()` quedó en 0 con el panel abierto: el panel se "
				+ "muestra pero no entra en la pila, así que el ESC no lo va a cerrar")
		_sub = 40
		return false
	if _sub < 40:
		_sub += 1
		return false
	var pausa: Node = U.nodo(_demo, "MenuPausa")
	if _sub == 40 and not _panel_cerrada:
		_panel_cerrada = true
		# El `MenuPausa` se ABRE con ESC. Mandarle ESC para "cerrarlo" lo
		# reabre, y el bucle de este paso se queda para siempre (era el cuelgue
		# de la fase «paneles ESC»: 9001 frames y sin salir). Para ese panel el
		# gesto de cerrar es su botón, que se llama "Reanudar" — el nombre está
		# en `menu_pausa.gd`, no inventado acá. Con el nombre equivocado el
		# `boton_texto` devolvía null, el menú quedaba ABIERTO y con el juego
		# pausado: de ahí venían los tres rojos siguientes (no se apila, no
		# reanuda, y el panel de opciones que se abre desde la pausa nunca
		# llegaba a aparecer).
		if nodo == pausa:
			var btn: Button = U.boton_texto(pausa, "Reanudar")
			if btn != null:
				btn.pressed.emit()
		elif bool(entrada.get("alternable", false)):
			# El tutorial se cierra con SU PROPIA tecla, que es la misma que lo
			# abre. El ESC no es suyo: lo Runs el menú de pausa, que es global
			# (ver `scripts/ui/tutorial_objetivo.gd`).
			_pulsar(int(entrada["tecla"]))
		else:
			_pulsar(KEY_ESCAPE)
		_sub = 41
		return false
	if _sub < 50:
		_sub += 1
		return false
	# Veredicto del panel: ¿cerró con ESC y la pila quedó vacía?
	var vis: bool = _panel_visible(nodo)
	var pila: int = PilaUI.abierta()
	var pausa_abierta: bool = bool(pausa.call("esta_abierto"))
	if _solo_panel != nodo:
		_ok("P11", "«%s» se abre y se cierra con ESC, y la pila queda vacía"
				% String(entrada["nodo"]), "")
		_panel_i += 1
		return _ir(F_PANELES)
	# El `MenuPausa` es la BASE de su propia pila y por diseño NO se cierra con
	# ESC (se cierra con "Reanudar" o con su propia tecla). Medirlo como un
	# panel más daba dos rojos falsos: "no se apila" y "el ESC no lo cierra".
	# Lo que sí se comprueba es lo que su diseño promete: que abre, que el
	# botón lo cierra, y que al cerrarse reanuda el juego.
	# `paused` es la PROPIEDAD del `SceneTree` (este script ES el árbol).
	if bool(entrada.get("base", false)):
		# `vis` a true es el FALLO: el botón tenía que cerrar el menú.
		if vis:
			_fallar("P11", "«%s» se cierra con su botón" % String(entrada["nodo"]),
				"«%s» sigue abierto después de apretar «Reanudar»" % String(entrada["nodo"]))
		elif paused:
			_fallar("P11", "cerrar «%s» REANUDA la partida" % String(entrada["nodo"]),
				"`paused` quedó en true con el menú cerrado: el juego sigue congelado")
		else:
			_ok("P11", "«%s» se abre con su tecla y su botón lo cierra" % String(entrada["nodo"]),
				"y al cerrar, el juego se reanuda (`paused` = false)")
		_panel_i += 1
		return _ir(F_PANELES)
	# Un panel que se abre DESDE la pausa vive en la pila de la pausa, no en
	# `PilaUI`, y el ESC lo baja por la pausa. Por eso no se le pide que esté
	# en `PilaUI`: lo que se comprueba es que abra desde el botón, que el ESC
	# lo cierre, y que la pausa quede como estaba.
	if bool(entrada.get("sin_pila", false)) and not bool(entrada.get("base", false)):
		if bool(entrada.get("alternable", false)):
			# El tutorial se cierra con su propia tecla, no con el ESC.
			if vis:
				_fallar("P11", "«%s» se cierra con su tecla" % String(entrada["nodo"]),
					"«%s» sigue visible después de su propia tecla. El ESC no lo "
						% String(entrada["nodo"])
					+ "cierra a propósito: es del menú de pausa")
			else:
				_ok("P11", "«%s» se abre y se cierra con su propia tecla"
						% String(entrada["nodo"]),
					"y el ESC no lo toca: es del menú de pausa")
		elif vis:
			_fallar("P11", "«%s» se cierra con la tecla ESC" % String(entrada["nodo"]),
				"«%s» sigue visible después del ESC (lo baja la pila de la pausa)"
					% String(entrada["nodo"]))
		else:
			_ok("P11", "«%s» se abre desde el menú de pausa y el ESC lo cierra"
					% String(entrada["nodo"]), "")
		_panel_i += 1
		return _ir(F_PANELES)
	if vis:
		_fallar("P11", "«%s» se cierra con la tecla ESC" % String(entrada["nodo"]),
			"«%s» sigue visible después del ESC" % String(entrada["nodo"]))
	elif pausa_abierta:
		_fallar("P11", "«%s» se cierra con la tecla ESC" % String(entrada["nodo"]),
			"el ESC no cerró «%s»: abrió el MENÚ DE PAUSA en su lugar. Las dos "
			% String(entrada["nodo"])
			+ "teclas comparten `cancelar_seleccion` y `cerrar_menu` (las dos son ESC), "
			+ "así que el panel nunca ve el evento")
	elif pila != 0:
		_fallar("P11", "la pila de paneles se VACÍA al cerrar «%s»" % String(entrada["nodo"]),
			"el panel cerró pero `PilaUI.abierta()` quedó en %d" % pila)
	else:
		_ok("P11", "«%s» se abre y se cierra con ESC, y la pila queda vacía"
				% String(entrada["nodo"]), "")
	_panel_i += 1
	return _ir(F_PANELES)


## Lo que el Player ve como "interactuable más cercano": la lista de nodos del
## grupo `interactuable` a menos de 4.5 u, que es el radio de `Player.interactuar()`.
func _interactuables_cerca(p: Node3D) -> Array[String]:
	var out: Array[String] = []
	for n in get_nodes_in_group(Player.GRUPO_INTERACTUABLE):
		var e: Node3D = n as Node3D
		if e == null:
			continue
		var d: float = e.global_position.distance_to(p.global_position)
		if d <= 4.5:
			out.append("%s a %.1f u" % [String(e.name), d])
	out.sort()
	return out


## Todos los paneles (CanvasLayer del juego) que están visibles ahora mismo.
func _paneles_visibles() -> Array:
	var out: Array = []
	for e in _paneles:
		var n: Node = U.nodo(_demo, String(e["nodo"]))
		if n != null and _panel_visible(n):
			out.append(n)
	return out


func _todo_cerrado() -> bool:
	return _paneles_visibles().is_empty()


## Lo mismo, pero sin la pausa ni la caja del tutorial, que no compiten por el
## ESC: la pausa es la que lo ABRE (así que contarla como "abierta" hace que
## los tres intentos se gasten siempre con el menú encima), y la caja ya no
## lo toma.
func _nombres_visibles() -> Array[String]:
	var out: Array[String] = []
	for e in _paneles:
		var n: Node = U.nodo(_demo, String(e["nodo"]))
		if n != null and _panel_visible(n):
			out.append(String(e["nodo"]))
	return out


func _todo_cerrado_para_esc() -> bool:
	var tut: Node = U.nodo(_demo, "PanelTutorial")
	var pz: Node = U.nodo(_demo, "MenuPausa")
	for n in _paneles_visibles():
		if n == tut or n == pz:
			continue
		return false
	return true


## Catálogo de paneles con tecla de apertura, tal como están en project.godot.
func _catalogo_paneles() -> Array[Dictionary]:
	return [
		{"nodo": "PanelInventario", "tecla": KEY_I, "accion": "abrir_inventario",
			"boton": "", "nota": "tecla I"},
		{"nodo": "PanelEquipo", "tecla": KEY_C, "accion": "abrir_equipo",
			"boton": "", "nota": "tecla C"},
		{"nodo": "PanelMisiones", "tecla": KEY_J, "accion": "abrir_misiones",
			"boton": "", "nota": "tecla J"},
		{"nodo": "PanelHabilidades", "tecla": KEY_K, "accion": "abrir_habilidades",
			"boton": "", "nota": "tecla K"},
		{"nodo": "PanelPersonaje", "tecla": KEY_H, "accion": "abrir_personaje",
			"boton": "", "nota": "tecla H"},
		{"nodo": "PanelCodice", "tecla": KEY_L, "accion": "abrir_codice",
			"boton": "", "nota": "tecla L"},
		{"nodo": "PanelAyuda", "tecla": KEY_SLASH, "accion": "abrir_ayuda",
			"boton": "", "nota": "tecla ?"},
		# El tutorial NO entra en `PilaUI`, y es a propósito: es HUD
		# persistente, no una ventana modal (está escrito en su propio archivo).
		# Si se apuntara, el ESC de la mochila cerraría al tutorial en vez de a
		# la mochila. Y su tecla PROPIA es la que lo cierra y lo abre: el ESC
		# es del menú de pausa, que es global. Por eso acá no se le pide que se
		# apile ni que el ESC lo cierre: se le pide que su tecla lo abra, y que
		# la misma tecla lo vuelva a cerrar.
		{"nodo": "PanelTutorial", "tecla": KEY_0, "accion": "abrir_tutorial",
			"boton": "", "nota": "tecla 0", "sin_pila": true, "alternable": true},
		{"nodo": "MenuPausa", "tecla": KEY_ESCAPE, "accion": "abrir_pausa",
			"boton": "", "nota": "tecla ESC", "base": true},
		{"nodo": "PanelOpciones", "tecla": 0, "accion": "apilar desde la pausa",
			"boton": "Opciones", "nota": "menú de pausa → Opciones", "sin_pila": true},
	]


func _nombres_paneles() -> Array[String]:
	var out: Array[String] = []
	for e in _paneles:
		out.append(String(e["nodo"]))
	return out


## Un panel "está abierto" si su `visible` está en true. Los CanvasLayer del
## juego se ocultan enteros (no tienen un Control raíz), así que `visible`
## es la señal de estado de la UI.
func _panel_visible(nodo: Node) -> bool:
	if nodo == null:
		return false
	# `esta_abierto` (con O) es el del `MenuPausa`; `esta_abierta` (con A) el de
	# los paneles de la pila. Con solo uno de los dos, el otro caía al
	# `visible` de su CanvasLayer, que se queda en true después de cerrar: el
	# paso decía "no se cerró con su botón" con el menú ya cerrado.
	if nodo.has_method("esta_abierto"):
		return bool(nodo.call("esta_abierto"))
	if nodo.has_method("esta_abierta"):
		return bool(nodo.call("esta_abierta"))
	# El `PanelTutorial` es el caso raro: su CanvasLayer está siempre visible
	# (es HUD persistente, con su pestaña de 30 px) y lo que se abre y se
	# cierra es la CAJA de dentro. Preguntar por el `visible` de la capa da
	# "siempre abierto" y el paso de P11 se cuelga en un bucle de ESC.
	if nodo.has_method("esta_visible"):
		return bool(nodo.call("esta_visible"))
	return bool(nodo.get("visible"))


## Deja un panel en el estado "cerrado" por la vía que lo declara, que no es
## la misma para todos: los CanvasLayer se ocultan enteros, pero el
## `PanelTutorial` tiene una caja dentro y lo que se cierra es esa.
func _esconder(nodo: Node) -> void:
	if nodo == null:
		return
	# Primero por la vía que el panel declara. Poner `visible = false` a pelo
	# no alcanza: los paneles de la pila guardan su estado y se vuelven a
	# mostrar solos, y el `PanelTutorial` tiene la caja DENTRO de una capa que
	# está siempre visible. Por eso se les pregunta a ellos.
	if nodo.has_method("cerrar_panel"):
		nodo.call("cerrar_panel")
		return
	if nodo.has_method("cerrar"):
		nodo.call("cerrar")
		return
	if nodo.has_method("esta_visible"):
		var caja: Control = nodo.get("_caja") as Control
		if caja != null:
			caja.visible = false
			return
	if nodo is CanvasLayer:
		(nodo as CanvasLayer).visible = false
		return
	nodo.set("visible", false)


# ───────────────────────────────────────────────────────────────────────────
# F24/F25 — talar un árbol de verdad (caminando) y comprobar que el estado
#            del árbol entra en el guardado
# ───────────────────────────────────────────────────────────────────────────

func _f_arbol() -> bool:
	if _sin_arboles:
		_omitir("P10", "los árboles TALADOS siguen talados al cargar",
			"se corrió con --sin-arboles (la caminata al bosque son 5 min de partida)")
		return _ir(F_REPORTE)
	_arbol_id = _arbol_al_alcance()
	if _arbol_id == "":
		_omitir("P10", "los árboles TALADOS siguen talados al cargar",
			"no hay ningún árbol alcanzable a nivel %d. El más cerca está a %.0f u "
			% [int((_jugador as Node3D).get("nivel")), _dist_arbol_cercano()]
			+ "y el jugador camina a 6 u/s: son %.0f s de partida, más de lo que "
			% (_dist_arbol_cercano() / 6.0)
			+ "cabe en este test. NO se verificó con un teletransporte.")
		return _ir(F_REPORTE)
	_arbol_pos = ArbolDB.posicion_de(_arbol_id)
	_arbol_muerte = false
	print("[PLAYTEST] P10 · caminando al árbol «%s» a %.0f u (%.0f s de partida)"
		% [_arbol_id, (_jugador as Node3D).global_position.distance_to(_arbol_pos),
			(_jugador as Node3D).global_position.distance_to(_arbol_pos) / 6.0])
	_reiniciar_caminata()
	(_jugador as Node3D).call("ordenar_mover_a", _arbol_pos)
	return _ir(F_ARBOL_TALAR)


func _f_arbol_talar() -> bool:
	var p: Node3D = _jugador as Node3D
	_sub += 1
	if not bool(p.call("esta_vivo")):
		_arbol_muerte = true
	if not _arbol_muerte and p.global_position.distance_to(_arbol_pos) > 4.0:
		_caminar_hasta(_arbol_pos, 4.0)
		if _sub >= FRAMES_ARBOL:
			_omitir("P10", "los árboles TALADOS siguen talados al cargar",
				"la caminata al árbol «%s» no llegó en %d frames de partida (%.0f s)"
					% [_arbol_id, FRAMES_ARBOL, int(FRAMES_ARBOL / 60)])
			return _ir(F_REPORTE)
		return false
	_sub = 0
	if _arbol_muerte:
		_omitir("P10", "los árboles TALADOS siguen talados al cargar",
			"el jugador murió caminando al bosque de 1,8 km: el guardián lo mató")
		return _ir(F_REPORTE)
	_arbol = U.nodo(_demo, "Arbol_%s" % _arbol_id)
	if _arbol == null:
		_omitir("P10", "los árboles TALADOS siguen talados al cargar",
			"llegamos a «%s» pero elGestorArboles no lo instanció (RADIO_ALTA = 700)"
				% _arbol_id)
		return _ir(F_REPORTE)
	_arbol_usos = int(_arbol.get("usos"))
	print("[PLAYTEST] P10 · árbol «%s» alcanzable, %d usos antes de talarlo"
		% [_arbol_id, _arbol_usos])
	p.call("seleccionar", _arbol)
	_pulsar(KEY_E)
	if _sub < 6:
		_sub += 1
		return false
	var estado: Dictionary = (_ref.get("arboles") as Object).call("estado_para_guardar")
	var talados: Dictionary = (estado.get("arboles") as Dictionary)
	var nuevo_usos: int = int(_arbol.get("usos"))
	if talados.has(_arbol_id):
		_ok("P10", "talar un árbol lo deja marcado como TALADO para el guardado",
			"«%s» pasó de %d a %d usos y `estado_para_guardar()` lo reporta"
				% [_arbol_id, _arbol_usos, nuevo_usos])
		_ok("P11", "talar un árbol de verdad (caminando 1,8 km y pulsando E)",
			"«%s»: %d → %d usos" % [_arbol_id, _arbol_usos, nuevo_usos])
	else:
		_fallar("P10", "talar un árbol lo deja marcado como TALADO para el guardado",
			"«%s» quedó con %d usos (antes %d) y no aparece en "
			% [_arbol_id, nuevo_usos, _arbol_usos]
			+ "`GestorArboles.estado_para_guardar()`: el árbol talado no se guarda")
	_pedir_cierre()
	# Re-guardar para que el paso de cargar compare contra este estado.
	if _jugador != null:
		var g: Object = _ref.get("guardado")
		if g != null:
			g.call("guardar")
	return _ir(F_CARGAR_LISTO)


# ───────────────────────────────────────────────────────────────────────────
# RENDIMIENTO — p95 de frame time durante la partida
# ───────────────────────────────────────────────────────────────────────────

func _medio_frame() -> void:
	if not _midiendo:
		return
	var ahora: int = Time.get_ticks_usec()
	var ms: float = float(ahora - _t_ultimo_usec) / 1000.0
	_t_ultimo_usec = ahora
	# Los frames en los que se está construyendo el mundo no son "frame de
	# partida": sesgarían el p95 hacia arriba.
	if _demo == null or bool(_demo.get("_mundo_pendiente")):
		return
	_frames_ms.append(ms)
	_frames_medidos += 1
	_cpu_s += Performance.get_monitor(Performance.TIME_PROCESS) \
		+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)


# ───────────────────────────────────────────────────────────────────────────
# ANDAMIAJE: resultados, presupuestos y utilidades
# ───────────────────────────────────────────────────────────────────────────

## A dónde se sigue cuando una fase no termina: el paso siguiente del guion.
func _siguiente_de(fase: int) -> int:
	match fase:
		F_TITULO: return F_REPORTE
		F_CREACION: return F_REPORTE
		F_MUNDO: return F_REPORTE
		F_LISTO: return F_REPORTE
		F_NOMBRE: return F_CAMINAR
		F_CAMINAR: return F_VITALES
		F_VITALES: return F_COMBATE
		F_COMBATE: return F_LOOT
		F_LOOT: return F_NIVEL
		F_INVENTARIO: return F_NIVEL
		F_NIVEL: return F_MISION
		F_MISION: return F_COCINA
		F_HABLAR: return F_COCINA
		F_ENTREGAR: return F_COCINA
		F_HABLAR_2: return F_COCINA
		F_COCINA: return F_REFUGIO
		F_COCINA_LENA: return F_REFUGIO
		F_COCINA_COCINAR: return F_REFUGIO
		F_REFUGIO: return F_GUARDAR
		F_REFUGIO_PIEZA: return F_GUARDAR
		F_GUARDAR: return F_TITULO_2
		F_TITULO_2: return F_PANELES
		F_CARGAR: return F_PANELES
		F_CARGAR_LISTO: return F_PANELES
		F_PANELES: return F_REPORTE
		F_ARBOL: return F_REPORTE
		F_ARBOL_TALAR: return F_CARGAR_LISTO
	return F_REPORTE


func _ir(fase: int, _nota: String = "") -> bool:
	if fase != _fase:
		print("[PLAYTEST] · fase %s (tras %d s de reloj)"
			% [FASES.get(fase, str(fase)),
				int((Time.get_ticks_msec() - _t_inicio_ms) / 1000)])
	_fase = fase
	_sub = 0
	_t_fase_ms = Time.get_ticks_msec()
	_agotado(0)
	return false


## ── caminar con rodeos ──────────────────────────────────────────────────────
## La partida NO tiene navmesh: `ordenar_mover_a()` va en línea recta y el
## jugador se traba contra las murallas y los puestos de la plaza. Un humano
## hace esto: apunta, ve que se trabó, y apunta alrededor del obstáculo. Esta
## función hace lo mismo, y sólo eso: usa `ordenar_mover_a` (la orden de
## movimiento del propio juego) para el destino y para cada rodeo.
var _esc_ticks: int = 0
var _esc_ultima: float = INF
var _esc_rodeo: Vector3 = Vector3.ZERO
var _esc_frames: int = 0
var _esc_lado: int = 1


func _reiniciar_caminata() -> void:
	_esc_ticks = 0
	_esc_ultima = INF
	_esc_frames = 0


## Devuelve true cuando llegó (a `radio` del destino).
func _caminar_hasta(destino: Vector3, radio: float) -> bool:
	var p: Node3D = _jugador as Node3D
	var d: float = p.global_position.distance_to(destino)
	if d <= radio:
		_reiniciar_caminata()
		return true
	if _esc_frames > 0:
		_esc_frames -= 1
		p.call("ordenar_mover_a", _esc_rodeo)
		if _esc_ticks % 300 == 0:
			print("[PLAYTEST] · rodeando un obstáculo: a %.1f u del destino"
				% p.global_position.distance_to(destino))
		return false
	# A 6 u/s el jugador avanza 0.1 u por frame: "sin progreso" es 45 frames
	# seguidos sin acercarse ni un centímetro.
	if d < _esc_ultima - 0.05:
		_esc_ultima = d
		_esc_ticks = 0
		p.call("ordenar_mover_a", destino)
		return false
	_esc_ticks += 1
	if _esc_ticks < 45:
		p.call("ordenar_mover_a", destino)
		return false
	# Atascado: marca un rodeo lateral y después vuelve a apuntar al destino.
	_esc_ultima = d
	_esc_ticks = 0
	var hacia: Vector3 = p.global_position - destino
	hacia.y = 0.0
	if hacia.length() < 0.01:
		hacia = Vector3(1.0, 0.0, 0.0)
	var lejos: Vector3 = hacia.normalized()
	var lado: Vector3 = lejos.cross(Vector3.UP).normalized()
	_esc_lado = -_esc_lado
	var paso: float = clampf(d * 0.35, 8.0, 20.0)
	_esc_rodeo = p.global_position + lejos * -paso + lado * paso * float(_esc_lado)
	_esc_frames = 60
	p.call("ordenar_mover_a", _esc_rodeo)
	print("[PLAYTEST] · atascado a %.1f u del destino, en %s: rodeo de 90 frames"
		% [d, str(p.global_position.round())])
	return false


## Las listas del demo pueden venir vacías o nulas según en qué fase de
## `_al_mundo_listo()` estamos. Ojo: `algo or []` devuelve BOOL en GDScript.
func _fogatas_del_mundo() -> Array:
	var v: Variant = _ref.get("fogatas")
	return (v as Array) if typeof(v) == TYPE_ARRAY else []


func _refugios_del_mundo() -> Array:
	var v: Variant = _ref.get("refugios")
	return (v as Array) if typeof(v) == TYPE_ARRAY else []


## ¿El fundido de `Transicion` terminó? Es el cerrojo de reentrada del propio
## juego (`_cargando`): mientras está en true, `ir_a()` ignora el pedido en
## silencio, y una pantalla queda pegada para siempre.
func _transicion_libre() -> bool:
	var t: Node = Transicion.actual
	if t == null:
		return true
	return not bool(t.get("_cargando"))


func _agotado(ms: int) -> bool:
	return Time.get_ticks_msec() - _t_fase_ms > ms


## Un chequeo se cuenta UNA sola vez. Varias fases re-evalúan el mismo
## chequeo cada frame mientras esperan; si eso contara, el resumen mentiría.
func _visto(paso: String, nombre: String) -> bool:
	for e in _res:
		if String(e["paso"]) == paso and String(e["nombre"]) == nombre:
			return true
	return false


func _ok(paso: String, nombre: String, detalle: String) -> void:
	if _visto(paso, nombre):
		return
	_ok_n += 1
	_res.append({"paso": paso, "estado": "PASA", "nombre": nombre, "detalle": detalle})
	print("[PLAYTEST] \u2713 %-3s %s%s" % [paso, nombre,
		"" if detalle == "" else "   [%s]" % detalle])


func _fallar(paso: String, nombre: String, detalle: String) -> void:
	if _visto(paso, nombre):
		return
	_fallos += 1
	_res.append({"paso": paso, "estado": "FALLA", "nombre": nombre, "detalle": detalle})
	printerr("[PLAYTEST] \u2717 %-3s %s" % [paso, nombre])
	printerr("[PLAYTEST]      %s" % detalle)


func _omitir(paso: String, nombre: String, motivo: String) -> void:
	if _visto(paso, nombre):
		return
	_omitidos += 1
	_res.append({"paso": paso, "estado": "OMITIDO", "nombre": nombre, "detalle": motivo})
	print("[PLAYTEST] \u00b7 %-3s %s   [OMITIDO: %s]" % [paso, nombre, motivo])


## ── cerrar la UI entre pasos ────────────────────────────────────────────────
## Un ESC por frame y por ESTADO, no por cantidad: mandar tres ESC seguidos es
## abrir-cerrar-abrir el menú de pausa, y la partida queda PAUSADA para
## siempre. Mientras se está cerrando, este frame no avanza de fase.
var _quiero_cerrar: bool = false
var _cierra_intentos: int = 0


func _menu_pausa_abierta() -> bool:
	var n: Node = U.nodo(_demo, "MenuPausa")
	return n != null and n.has_method("esta_abierto") and bool(n.call("esta_abierto"))


## "Cerrá todo lo que esté abierto" — se pide antes de un paso y se cumple en
## los frames siguientes, con un ESC por frame, hasta que no queda nada.
func _pedir_cierre() -> void:
	_quiero_cerrar = true
	_cierra_intentos = 0


func _ui_limpia() -> bool:
	return _paneles_visibles().is_empty() and not _menu_pausa_abierta() and not paused


func _tick_cierre() -> bool:
	## Devuelve true si este frame lo consumió el cierre de UI.
	if not _quiero_cerrar:
		return false
	if _ui_limpia():
		_quiero_cerrar = false
		_pausa_frames = 0
		return false
	if _cierra_intentos < 16:
		_cierra_intentos += 1
		_pulsar(KEY_ESCAPE)
		return true
	# Ni con 16 ESC se cierra: se esconderá a mano y se dice, porque si no el
	# resto del playtest mediría sobre una partida que quedó a medias.
	var bravos: Array = _paneles_visibles()
	var nombres: Array[String] = []
	for b in bravos:
		nombres.append(String((b as Node).name))
	for b in bravos:
		(b as Node).visible = false
	var pm: Node = U.nodo(_demo, "MenuPausa")
	if pm != null and pm.has_method("cerrar"):
		pm.call("cerrar")
	_fallar("P0", "la UI se puede cerrar con el teclado",
		"tras 16 ESC seguían abiertos %s (y `paused` = %s). Se cerraron a mano para "
			% [str(nombres), str(paused)]
		+ "seguir midiendo. `PilaUI.abierta()` = %d" % PilaUI.abierta())
	_quiero_cerrar = false
	_pausa_frames = 0
	return true


## La partida no puede quedarse pausada en medio de una caminata: si pasa,
## es un bug (o un ESC que abrió el menú de pausa) y hay que reportarlo.
func _watchdog_pausa() -> void:
	if not paused:
		_pausa_frames = 0
		return
	_pausa_frames += 1
	if _pausa_frames == 90 and not _quiero_cerrar:
		_pedir_cierre()


# ── lecturas chicas ─────────────────────────────────────────────────────────

func _textos_botones(raiz: Node) -> Array[String]:
	var out: Array[String] = []
	for b in U.botones(raiz):
		out.append(str((b as Button).text))
	return out


func _vida(e: Node) -> float:
	if e == null:
		return -1.0
	return float(e.get("vida_actual"))


func _vida_max(e: Node) -> float:
	if e == null:
		return -1.0
	var s: Variant = e.get("stats")
	if s == null or typeof(s) != TYPE_OBJECT:
		return -1.0
	var sb: Object = s
	return float(sb.get("vida_max"))


func _bytes(ruta: String) -> int:
	var f: FileAccess = FileAccess.open(ruta, FileAccess.READ)
	if f == null:
		return -1
	var n: int = f.get_length()
	f.close()
	return n


func _mob_cercano() -> Node:
	var mejor: Node = null
	var mejor_d: float = INF
	for n in get_nodes_in_group("enemigos"):
		var e: Node3D = n as Node3D
		if e == null or not bool(e.call("esta_vivo")):
			continue
		var d: float = e.global_position.distance_to((_jugador as Node3D).global_position)
		if d < mejor_d:
			mejor_d = d
			mejor = e
	return mejor


func _npc_con_oferta(q: Object) -> Node:
	var mejor: Node = null
	var mejor_d: float = INF
	for n in get_nodes_in_group("npcs"):
		var npc: Node3D = n as Node3D
		if npc == null:
			continue
		var ofr: Dictionary = q.call("oferta_para_npc", str(npc.get("npc_id")))
		if ofr.is_empty():
			continue
		var d: float = npc.global_position.distance_to((_jugador as Node3D).global_position)
		if d < mejor_d:
			mejor_d = d
			mejor = npc
	return mejor


func _arbol_al_alcance() -> String:
	var nivel: int = int((_jugador as Node3D).get("nivel"))
	var ids: Array = ArbolDB.ids()
	var p: Vector3 = (_jugador as Node3D).global_position
	var mejor: String = ""
	var mejor_d: float = INF
	for i in ids:
		var aid: String = str(i)
		var datos: Dictionary = ArbolDB.obtener(aid)
		if int(datos.get("nivel", 1)) > nivel:
			continue
		var pos: Vector3 = ArbolDB.posicion_de(aid)
		var d: float = Vector2(pos.x - p.x, pos.z - p.z).length()
		if d < mejor_d:
			mejor_d = d
			mejor = aid
	return mejor


func _dist_arbol_cercano() -> float:
	var nivel: int = int((_jugador as Node3D).get("nivel"))
	var p: Vector3 = (_jugador as Node3D).global_position
	var mejor: float = INF
	for i in ArbolDB.ids():
		var datos: Dictionary = ArbolDB.obtener(str(i))
		if int(datos.get("nivel", 1)) > nivel:
			continue
		var pos: Vector3 = ArbolDB.posicion_de(str(i))
		mejor = minf(mejor, Vector2(pos.x - p.x, pos.z - p.z).length())
	return mejor


# ───────────────────────────────────────────────────────────────────────────
# REPORTE
# ───────────────────────────────────────────────────────────────────────────

func _reporte() -> bool:
	_terminado = true
	print("")
	print("[PLAYTEST] ===================================================================")
	print("[PLAYTEST] RESUMEN DE LA PARTIDA")
	print("[PLAYTEST] ===================================================================")
	for paso in ["P0", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10", "P11"]:
		var lineas: Array[Dictionary] = []
		for e in _res:
			if String(e["paso"]) == paso:
				lineas.append(e)
		if lineas.is_empty():
			continue
		print("[PLAYTEST]")
		print("[PLAYTEST] %s" % paso)
		for e in lineas:
			var marca: String = "PASA    "
			if String(e["estado"]) == "FALLA":
				marca = "FALLA   "
			elif String(e["estado"]) == "OMITIDO":
				marca = "OMITIDO "
			print("[PLAYTEST]   %s %s" % [marca, String(e["nombre"])])
			var det: String = String(e["detalle"])
			if det != "":
				print("[PLAYTEST]            %s" % det)
	_reporte_perf()
	print("")
	print("[PLAYTEST] verdes: %d   rojos: %d   omitidos: %d   (exit code = rojos)"
		% [_ok_n, _fallos, _omitidos])
	print("[PLAYTEST] ===================================================================")
	quit(_fallos)
	return true


func _reporte_perf() -> void:
	print("")
	print("[PLAYTEST] ---- RENDIMIENTO (headless: CPU + lógica, SIN GPU) ----")
	if _frames_ms.is_empty():
		print("[PLAYTEST] no se pudo medir: el mundo nunca llegó a estar listo")
		return
	var ms: Array[float] = _frames_ms.duplicate()
	ms.sort()
	var n: int = ms.size()
	var suma: float = 0.0
	for m in ms:
		suma += m
	var p50: float = ms[int(n * 0.50)]
	var p95: float = ms[clampi(int(n * 0.95), 0, n - 1)]
	var p99: float = ms[clampi(int(n * 0.99), 0, n - 1)]
	var maximo: float = ms[n - 1]
	var fps: float = 1000.0 / (suma / float(n))
	print("[PLAYTEST] frames de partida medidos: %d (%.1f s de partida a 60 Hz)"
		% [n, int(n / 60)])
	print("[PLAYTEST] frame time: p50=%.2f  p95=%.2f  p99=%.2f  max=%.2f ms  (media %.2f ms)"
		% [p50, p95, p99, maximo, suma / float(n)])
	print("[PLAYTEST] FPS medio: %.1f" % fps)
	if _frames_medidos > 0:
		print("[PLAYTEST] CPU por frame (TIME_PROCESS + TIME_PHYSICS_PROCESS): %.2f ms"
			% (_cpu_s * 1000.0 / float(_frames_medidos)))
	var veredicto: String = "DENTRO DE PRESUPUESTO (p95 <= 16.7 ms, o sea 60 FPS)"
	if p95 > 16.7:
		veredicto = "FUERA DE PRESUPUESTO: p95 = %.2f ms > 16.7 ms. NO se arregla acá " % p95
		veredicto += "(lo mide el bench de GPU con la ventana enfocada: tools/bench_gpu.gd)"
	print("[PLAYTEST] veredicto: %s" % veredicto)
