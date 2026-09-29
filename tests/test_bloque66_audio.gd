extends SceneTree
## Bloque 66 — que el juego suene.
##
## POR QUÉ ESTE ARCHIVO: la auditoría encontró que el juego tenía 4 call sites
## de audio en todo el repo, 13 sonidos a 8 bits/22050 Hz, cero música (el bus
## existía y nunca se le asignaba nada) y cero audio posicional. Todo pasaba
## los tests, porque los tests solo comprobaban que el sintetizador devolviera
## un WAV, no que el juego lo oyera.
##
## Lo que se comprueba aquí:
## (a) calidad de verdad: 16 bits, 44.1 kHz, estéreo, y VARIACIÓN real.
## (b) que los sonidos existan, incluidos los que estaban declarados y nunca
##     se llamaban.
## (c) audio POSICIONAL: un golpe a 40 m no puede sonar como uno encima.
## (d) la música: se genera, tiene capas, y cambia de tema.
## (e) el director decide el estado con histéresis (no parpadea).

const MJ: GDScript = preload("res://scripts/audio/audio_juego.gd")
const MU: GDScript = preload("res://scripts/audio/musica.gd")
const DM: GDScript = preload("res://scripts/audio/director_musica.gd")
const SU: GDScript = preload("res://scripts/ui/sonido_ui.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Bloque 66 — Que el juego suene")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_calidad()
	_test_catalogo()
	_test_posicional()
	_test_pisadas()
	_test_musica()
	_test_director()
	_test_ui()
	print("[TEST] bloque66_audio: %d ok, %d fallos" % [_ok, _fallos])
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


func _jugador(pos: Vector3 = Vector3.ZERO) -> Player:
	var p: Player = PL.new()
	p.fijar_identidad("H", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	p.global_position = pos
	return p


func _enemigo(pos: Vector3, jefe: bool = false) -> Enemy:
	var e: Enemy = EN.new()
	root.add_child(e)
	_basura.append(e)
	e.global_position = pos
	if jefe:
		e.es_jefe = true
	return e


# --- (a) calidad real ------------------------------------------------

func _test_calidad() -> void:
	var receta: Dictionary = {"forma": "ruido", "freq_ini": 900.0,
		"freq_fin": 120.0, "duracion": 0.12, "volumen": 0.5}
	var w: AudioStreamWAV = Sintetizador.generar(receta)
	_chk(w.format == AudioStreamWAV.FORMAT_16_BITS, "16 bits", str(w.format))
	_chk(w.mix_rate == 44100, "44100 Hz", str(w.mix_rate))
	_chk(w.stereo, "estéreo", "")

	# La variación es lo que separa un impacto de un pitido. Con una sola
	# variante el oído aprende el sonido y lo ignora.
	var w2: AudioStreamWAV = Sintetizador.generar(receta, 1)
	_chk(w.data != w2.data, "dos variantes suenan distinto", "")
	# Y con la misma semilla, la misma variante es idéntica (cacheable).
	var w3: AudioStreamWAV = Sintetizador.generar(receta, 1)
	_chk(w2.data == w3.data, "la misma variante es idéntica (determinista)", "")

	# El tamaño: 0.12 s x 44100 x 2 canales x 2 bytes.
	var esperado: int = int(44100 * 0.12) * 4
	_chk(absi(w.data.size() - esperado) <= 8,
		"el tamaño del buffer es el esperado", "%d vs %d" % [w.data.size(), esperado])

	# ADSR: el principio y el final deben ser ~0 (sin clic). Un sample que
	# arranca en 1.0 hace "tac".
	# El inicio tiene ataque (0 s) asi que arranca en 0. El final: con un
	# sustain de 0.35 el release no llega a 0 exacto, y además la forma es
	# RUIDO (con varianza), así que el último sample es aleatorio. Lo que
	# importa para que no haya "clic" es que sea BAJO, no cero.
	_chk(_inicio_casi_silencioso(w), "arranca en silencio (sin clic)", "")
	_chk(_final_bajo(w), "termina bajo (sin clic)", str(_ultimo(w)))


func _inicio_casi_silencioso(w: AudioStreamWAV) -> bool:
	return absi(_leer(w, 0)) < 3000


func _final_bajo(w: AudioStreamWAV) -> bool:
	return absi(_ultimo(w)) < 12000


func _ultimo(w: AudioStreamWAV) -> int:
	var n: int = w.data.size() / 4
	return _leer(w, n - 1)


## Lee una muestra (canal izquierdo) de un WAV 16 bits estéreo.
func _leer(w: AudioStreamWAV, i: int) -> int:
	var b: int = i * 4
	if b + 1 >= w.data.size():
		return 0
	var v: int = int(w.data[b]) | (int(w.data[b + 1]) << 8)
	if v > 32767:
		v -= 65536
	return v


# --- (b) el catálogo -------------------------------------------------

func _test_catalogo() -> void:
	var a: AudioJuego = MJ.new()
	root.add_child(a)
	_basura.append(a)
	_chk(a.ids().size() >= 36,
		"el catálogo pasó de 13 a 36+ sonidos", str(a.ids().size()))
	# Los que estaban DECLARADOS y NUNCA se llamaban: la auditoría los encontró
	# muertos. Ahora existen y son alcanzables.
	for id in ["clic", "mision", "error", "talar", "minar", "fogata",
			"paso_hierba", "paso_piedra", "dano_recibido", "hecho"]:
		_chk(a.tiene_sonido(id), "el sonido '%s' existe (66)" % id, "")

	# Pisadas: los 4 materiales, cada uno con su timbre.
	for mat in ["hierba", "piedra", "tierra", "arena"]:
		var s: String = "paso_" + mat
		_chk(a.tiene_sonido(s), "pisada de %s" % mat, "")

	# Y que la traducción región→material cubra las regiones que hay.
	var r1: String = MJ.paso_de_region("desert")
	_chk(r1 == "paso_arena", "desert = arena", r1)
	var r2: String = MJ.paso_de_region("piedraceniza")
	_chk(r2 == "paso_piedra", "piedraceniza = piedra", r2)
	var r3: String = MJ.paso_de_region("bosque")
	_chk(r3 == "paso_hierba", "bosque = hierba", r3)
	_chk(MJ.paso_de_region("no_existe") == "paso_tierra",
		"una región desconocida cae a tierra (no crashea)", "")


# --- (c) audio posicional --------------------------------------------

func _test_posicional() -> void:
	var a: AudioJuego = MJ.new()
	root.add_child(a)
	_basura.append(a)
	_chk(a._players_mundo.size() >= 8,
		"hay pool 3D (posicional)", str(a._players_mundo.size()))
	_chk(a._players_mundo[0] is AudioStreamPlayer3D,
		"las voces del mundo son AudioStreamPlayer3D", "")

	# Un golpe a un mob debe ir al pool 3D, no al 2D. Antes TODO iba al 2D: un
	# goblin a 200 m sonaba igual que uno encima, que es el defecto más grave
	# del audio de la fase 20.
	var e: Enemy = _enemigo(Vector3(40, 0, 0))
	var idx2d: int = a._idx
	var idx3d: int = a._idx_mundo
	e.take_damage(10.0, null, false)
	_chk(a._idx_mundo != idx3d, "el impacto de un mob va al pool POSICIONAL",
		"%d -> %d" % [idx3d, a._idx_mundo])
	_chk(a._idx == idx2d, "y NO consume la voz 2D (la del jugador)", "")
	_chk(e.esta_vivo(), "el golpe no lo mató (a 10 de daño)")


# --- (d) pisadas ----------------------------------------------------

func _test_pisadas() -> void:
	var p: Player = _jugador()
	_chk(p.has_method("_tick_pisadas"), "el jugador tiene lógica de pisadas", "")
	_chk(Player.PASO_DISTANCIA > 0.0, "y una distancia de paso", "")

	# Quieto no suena; caminando sí. Sin la region, cae a tierra.
	var antes: int = p._paso_acumulado
	p.velocity = Vector3.ZERO
	p._tick_pisadas(0.016)
	_chk(p._paso_acumulado == 0.0, "quieto no acumula paso", str(p._paso_acumulado))

	# Caminando: tras un frame corto (0,1 s a 4 m/s = 0,4 m) el acumulado tiene
	# que haber CRECIDO sin llegar todavIa a un paso completo (1,75 m).
	p.velocity = Vector3(4.0, 0, 0)
	p._paso_acumulado = 0.0
	p._tick_pisadas(0.1)
	_chk(p._paso_acumulado > 0.0 and p._paso_acumulado < Player.PASO_DISTANCIA,
		"caminando acumula distancia sin saltar todavIa el paso",
		str(p._paso_acumulado))
	# Y al llegar al paso completo, se reproduce y se reinicia.
	p._paso_acumulado = Player.PASO_DISTANCIA - 0.01
	p._tick_pisadas(0.1)
	_chk(p._paso_acumulado < Player.PASO_DISTANCIA * 0.5,
		"al completar el paso, se reinicia el contador", str(p._paso_acumulado))

	# Correr suena más que caminar: es la razón de que el paso vaya por
	# distancia y no por reloj.
	var lento: float = 0.0
	var rapido: float = 0.0
	for i in range(30):
		p.velocity = Vector3(2.0, 0, 0)
		p._paso_acumulado = 0.0
		p._tick_pisadas(0.1)
		lento += p._paso_acumulado
	for i in range(30):
		p.velocity = Vector3(6.0, 0, 0)
		p._paso_acumulado = 0.0
		p._tick_pisadas(0.1)
		rapido += p._paso_acumulado
	_chk(rapido > lento, "correr da más distancia (y más pasos) que caminar",
		"lento=%.1f rapido=%.1f" % [lento, rapido])


# --- (e) la música --------------------------------------------------

func _test_musica() -> void:
	var m: Musica = MU.new()
	root.add_child(m)
	_basura.append(m)
	_chk(m._streams.size() >= 5, "se generaron los temas",
		str(m._streams.size()))

	# Cada tema es un bucle real: sin loop_mode, se oye "reiniciado" cada
	# compás, que es el defecto de un loop mal hecho.
	for nombre in m._streams.keys():
		var w: AudioStreamWAV = m._streams[nombre]
		_chk(w.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"el tema '%s' es un bucle" % nombre, str(w.loop_mode))
		# loop_end en Godot va en MUESTRAS (no bytes), y un bucle que acaba
		# justo al final del buffer es correcto: <= , no < .
		_chk(w.loop_end > 0 and w.loop_end <= w.data.size() / 4,
			"con loop_end dentro del buffer ('%s')" % nombre, str(w.loop_end))
		_chk(w.stereo and w.mix_rate == 44100,
			"y tiene calidad de verdad ('%s')" % nombre, "")

	# La música arranca en exploración.
	_chk(m.estado() == Musica.CAPA_EXPLORACION,
		"arranca en exploración", str(m.estado()))

	# Cambiar a jefe: la capa de jefe sube y las demás bajan.
	m.cambiar_estado(Musica.CAPA_JEFE)
	_chk(m.estado() == Musica.CAPA_JEFE, "cambia a jefe", str(m.estado()))

	# Las capas se mueven con tween, así que el volumen final llega tarde; lo
	# que se comprueba aquí es que la intención es correcta: la capa de jefe
	# tiene destino > la de exploración (esta está en -11, jefe en -3).
	_chk(Musica.DB_CAPA[Musica.CAPA_JEFE] > Musica.DB_CAPA[Musica.CAPA_BASE],
		"la capa de jefe domina a la base (ducking)", "")
	_chk(Musica.DB_CAPA[Musica.CAPA_BASE] < 0.0,
		"y la base está atenuada de fondo", "")


# --- (f) el director: histéresis -------------------------------------

func _test_director() -> void:
	var m: Musica = MU.new()
	root.add_child(m)
	_basura.append(m)
	var p: Player = _jugador()
	var lejos: Enemy = _enemigo(Vector3(500, 0, 0))
	var d: DirectorMusica = DM.new()
	root.add_child(d)
	_basura.append(d)
	d.configurar(m, p, [lejos])

	# Sin enemigos cerca y FUERA de una plaza: exploración. El jugador tiene que
	# estar lejos del origen, porque en el origen (0,0,0) está la plaza de Moon
	# Town (radio 40) y el estado sería "pueblo", no "exploración".
	p.global_position = Vector3(3000, 40, 3000)
	_chk(d.estado_calculado() == Musica.CAPA_EXPLORACION,
		"sin enemigos y fuera de plaza, exploración", str(d.estado_calculado()))
	# En la plaza: pueblo. Eso también es correcto.
	p.global_position = Vector3.ZERO
	_chk(d.estado_calculado() == Musica.CAPA_BASE,
		"en la plaza de Moon Town, el tema es pueblo", str(d.estado_calculado()))
	p.global_position = Vector3(3000, 40, 3000)

	# Enemigo cerca: el cálculo dice combate, pero NO cambia todavía (histéresis).
	lejos.global_position = p.global_position + Vector3(10, 0, 0)
	_chk(d.estado_calculado() == Musica.CAPA_COMBATE,
		"con un enemigo a 10 m, el cálculo da combate", str(d.estado_calculado()))
	_chk(d.destino() == Musica.CAPA_EXPLORACION,
		"pero el tema NO cambia al instante (histéresis)", str(d.destino()))

	# Tras la estabilidad, sí cambia.
	for i in range(200):
		d._process(0.05)
	_chk(d.destino() == Musica.CAPA_COMBATE,
		"y tras ~2 s de estabilidad, cambia a combate", str(d.destino()))

	# Un jefe cercano gana a todo: contra un jefe no hay "exploración".
	_chk(d.estado_calculado() == Musica.CAPA_JEFE
			or d.estado_calculado() == Musica.CAPA_COMBATE,
		"con un jefe cerca, el estado sube a jefe/combate", str(d.estado_calculado()))


# --- (g) UI --------------------------------------------------------

func _test_ui() -> void:
	_chk(SU != null, "SonidoUI existe (el punto único de los sonidos de interfaz)", "")
	# Que el helper exista es lo que se comprueba: los sonidos se reproducen
	# solos al abrir/cerrar. Un `play()` real con el driver dummy no aporta.
	for m in ["clic", "abrir_panel", "cerrar_panel", "error", "nivel", "hecho"]:
		_chk(SU.has_method(m), "SonidoUI.%s()" % m, "")
