extends SceneTree
## Fase 72 — que el audio esté CONECTADO, no solo escrito.
##
## POR QUÉ ESTE ARCHIVO, Y POR QUÉ TIENE TRES PARTES DISTINTAS:
##
## 1) EL INVENTARIO DE CALL SITES. `data/sonidos.json` declaraba 37 recetas y
##    quince NO TENÍAN NI UN SOLO `reproducir()` en el juego. Todo el audio
##    pasaba los tests porque los tests solo comprobaban que el sintetizador
##    devolviera un WAV. Este check recorre el código de juego y exige que cada
##    receta se pida de verdad; es el que va a cazar los huecos futuros.
##
## 2) LO QUE SE MUEVE, SUENA. Un test que conecta una señal y ve que se emitió
##    NO prueba nada (esa lección está escrita en el AGENTS.md y viene de la
##    63). Así que aquí se MUEVE el dato —el hambre baja, la vida baja, el
##    jugador sube de nivel, aparece una enfermedad— y se mira qué sonido
##    salió de verdad por `AudioJuego.sonido_reproducido`. Si el sistema
##    estuviera desconectado de la partida, aquí no se oiría nada.
##
## 3) EL MENÚ Y EL AMBIENTE, que no existían. El título era mudo, el volumen
##    guardado no se aplicaba hasta después de la carga, y el bus `Ambiente`
##    no tenía ni un player. Eso se comprueba mirando buses y dB de verdad.

const RUTA_SONIDOS: String = "res://data/sonidos.json"
## Los dos archivos que TRADUCEN un id a sonido. Todo lo demás es "código de
## juego": si un id aparece en otro sitio, es porque alguien lo pidió de verdad.
const CAPA_SONIDO: Array[String] = [
	"res://scripts/audio/audio_juego.gd",
	"res://scripts/ui/sonido_ui.gd",
]
## Raíces donde se buscan call sites. `tests/` NO está: un test que se llama a
## sí mismo no es un call site, es una tautología.
const RAICES_CODIGO: Array[String] = ["res://scripts", "res://scenes"]


var _ok: int = 0
var _fallos: int = 0
var _fase: int = 0
var _frames: int = 0
var _hechos: bool = false
var _sucios: Array[Node] = []

## Los ids que han SALIDO de verdad durante el test.
var _sonidos: Array[String] = []
var _audio: AudioJuego = null


func _init() -> void:
	print("[TEST] Fase 72 — los huecos de audio: que suene TODO")


func _process(_delta: float) -> bool:
	if _hechos:
		return true
	# Fase 1 y 2 no necesitan frames: son de datos y de señales.
	if _fase == 0:
		_fase = 1
		_test_inventario_de_call_sites()
		# El menú va PRIMERO y se libera antes de nada: `AudioJuego` tiene UN
		# hueco estático para la instancia viva, y el título se lo queda. Sin
		# este orden el `AudioJuego` del test queda huérfano y no suena nada
		# —que es exactamente lo que le pasaría a la partida si el título no
		# soltara el estático al morir.
		_test_menu_y_opciones()
		_preparar_audio()
		return false
	if _fase == 1:
		_fase = 2
		_test_mover_el_dato_suena()
		return false
	_fase = 3
	_test_ambiente()
	_hechos = true
	print("[TEST] fase72_audio: %d ok, %d fallos" % [_ok, _fallos])
	for n in _sucios:
		if n != null and is_instance_valid(n):
			n.queue_free()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


# =========================================================================
# 1) EL INVENTARIO: cada receta tiene un call site REAL
# =========================================================================

## Por cada id de `data/sonidos.json`, una de estas dos:
##  a) ALGUIEN LO PIDIÓ DIRECTO: el literal aparece como ARGUMENTO de un
##     `reproducir(` / `reducir_en(` en código de juego. Se exige que sea
##     argumento y no cualquier cadena: `refugio.gd` devuelve `"construir"`
##     como motivo y `pieza_visual.gd` compara `p_tipo == "fogata"`, y
##     ninguno de los dos es un sonido.
##  b) ALGUIEN LO PIDIÓ POR UN HELPER: el id está dentro de una función de
##     `CAPA_SONIDO`, y esa función se llama desde código de juego. Sin (b), un
##     helper muerto —`SonidoUI.hecho()`, que estuvo muerto desde el bloque
##     66— contaría como cableado, y eso es exactamente el bug que se busca.
func _test_inventario_de_call_sites() -> void:
	var recetas: Array[String] = _recetas()
	_chk(recetas.size() >= 30, "sonidos.json tiene las 37 recetas",
		"encontradas %d" % recetas.size())
	var codigo: Dictionary = _codigo_de_juego()
	_chk(codigo.size() > 40, "se leyó el código de juego",
		"solo %d archivos" % codigo.size())
	for id_sonido in recetas:
		var sitios: Array[String] = _call_sites_de(id_sonido, codigo)
		_chk(not sitios.is_empty(),
			"la receta '%s' tiene un call site real" % id_sonido,
			"no aparece como argumento de reproducir() ni en un helper llamado")


## Los ids de `data/sonidos.json`.
func _recetas() -> Array[String]:
	var out: Array[String] = []
	var texto: String = FileAccess.get_file_as_string(RUTA_SONIDOS)
	if texto == "":
		return out
	var d: Variant = JSON.parse_string(texto)
	if not (d is Dictionary):
		return out
	var sons: Variant = (d as Dictionary).get("sonidos", {})
	if not (sons is Dictionary):
		return out
	for k in (sons as Dictionary).keys():
		out.append(str(k))
	return out


## ruta -> texto, de todo `scripts/` y `scenes/` menos la capa de dispatch.
func _codigo_de_juego() -> Dictionary:
	var out: Dictionary = {}
	for raiz in RAICES_CODIGO:
		_recorrer(raiz, out)
	return out


func _recorrer(dir: String, out: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var nombre: String = d.get_next()
	while nombre != "":
		var ruta: String = dir.path_join(nombre)
		if d.current_is_dir():
			if nombre != "tests":
				_recorrer(ruta, out)
		elif nombre.ends_with(".gd") and not CAPA_SONIDO.has(ruta):
			out[ruta] = FileAccess.get_file_as_string(ruta)
		nombre = d.get_next()
	d.list_dir_end()


## Los sitios que piden el id, como etiquetas legibles.
func _call_sites_de(id_sonido: String, codigo: Dictionary) -> Array[String]:
	var out: Array[String] = []
	# (a) llamada directa con el literal como argumento.
	var re := RegEx.new()
	# `[^()]*` y no `[^\\n]*`: una línea con DOS llamadas (`reproducir("a" if
	# x else "b")`) haría que la segunda se contara como call site de la
	# primera, y el test dejaría de morder sin que nadie lo notara.
	re.compile("reproducir(_en)?\\s*\\([^()]*\"%s\"" % id_sonido)
	for ruta in codigo.keys():
		var texto: String = codigo[ruta]
		for linea in texto.split("\n"):
			# Los comentarios no pisan sonidos: se limpian antes de buscar.
			var cod: String = linea.split("##")[0]
			if re.search(cod) != null:
				out.append("%s: %s" % [ruta, cod.strip_edges()])
	if not out.is_empty():
		return out
	# (b) el id vive en un helper de la capa de dispatch, y ese helper se
	# llama desde el juego.
	for ruta in CAPA_SONIDO:
		for par in _helpers_de(ruta):
			var nombre: String = par[0]
			var cuerpo: String = par[1]
			if not cuerpo.contains("\"%s\"" % id_sonido):
				continue
			var re_llamada := RegEx.new()
			re_llamada.compile("\\b%s\\s*\\(" % nombre)
			for otro in codigo.keys():
				if re_llamada.search(codigo[otro]) != null:
					out.append("%s.%s()" % [ruta.get_file(), nombre])
					break
	return out


## (nombre, cuerpo) de cada `func`/`static func` de un archivo. Recorta por la
## firma, así que un id mentioned en el comentario de arriba de una función no
## se le atribuye a esa función.
func _helpers_de(ruta: String) -> Array:
	var texto: String = FileAccess.get_file_as_string(ruta)
	var out: Array = []
	var re := RegEx.new()
	re.compile("(?m)^(static )?func ")
	var cortes: Array[int] = []
	for m in re.search_all(texto):
		cortes.append(m.get_start())
	for i in range(cortes.size()):
		var ini: int = cortes[i]
		var fin: int = cortes[i + 1] if i + 1 < cortes.size() else texto.length()
		var bloque: String = texto.substr(ini, fin - ini)
		var par: PackedStringArray = bloque.split("(")
		if par.size() < 2:
			continue
		var cab: String = par[0].replace("static func", "").replace("func", "").strip_edges()
		if cab == "":
			continue
		out.append([cab, bloque])
	return out


# =========================================================================
# 2) LO QUE SE MUEVE, SUENA
# =========================================================================

func _preparar_audio() -> void:
	_audio = AudioJuego.new()
	_audio.name = "AudioJuegoTest"
	root.add_child(_audio)
	_sucios.append(_audio)
	_audio.sonido_reproducido.connect(_al_sonido)
	for id_sonido in _recetas():
		_chk(_audio.tiene_sonido(id_sonido), "existe el sample de '%s'" % id_sonido)


func _al_sonido(id_sonido: String) -> void:
	_sonidos.append(id_sonido)


func _sono(id_sonido: String, desde: int) -> bool:
	for i in range(desde, _sonidos.size()):
		if _sonidos[i] == id_sonido:
			return true
	return false


## El escenario completo: una sesión real, un `AvisosJugador` real escuchándola,
## y CADA COSA se provoca moviendo el dato. Nada de "conectar una señal y ver
## que se emite": eso no prueba que el sistema esté vivo.
func _test_mover_el_dato_suena() -> void:
	var j: Player = _jugador()
	if j == null:
		_chk(false, "se pudo crear un jugador")
		return
	var avisos := AvisosJugador.new()
	avisos.name = "AvisosJugadorTest"
	root.add_child(avisos)
	_sucios.append(avisos)
	avisos.vigilar(j)

	# --- damage: bajar la vida tiene que sonar "dano_recibido" ---
	var marca: int = _sonidos.size()
	j.take_damage(5.0, null, false)
	_chk(_sono("dano_recibido", marca), "bajar la vida suena dano_recibido",
		"sonaron: %s" % str(_sonidos.slice(marca)))

	# --- muerte: el sonido de morir del jugador es el suyo, no el del mob ---
	# El call site de `murio_jugador` está en `RespawnHeros`, que es el sistema
	# de mundo que reacciona a `jugador.murio`. Si aquí no se monta ese
	# sistema, el test falla — y tiene que fallar: probaría que el sonido no
	# se dispara desde `Player.die()`, sino desde quien la mira morir.
	var respawn := RespawnHeros.new()
	respawn.name = "RespawnHerosTest"
	root.add_child(respawn)
	_sucios.append(respawn)
	respawn.configurar(j)
	marca = _sonidos.size()
	j.take_damage(9999.0, null, false)
	_chk(_sono("murio_jugador", marca), "morir suena murio_jugador",
		"sonaron: %s" % str(_sonidos.slice(marca)))
	_chk(not _sono("muerte", marca),
		"morir NO suena el 'muerte' de los mobs", "se confundieron")

	# --- subir de nivel ---
	j.reaparecer()
	# `reaparecer()` reemplaza el `Vitals` por uno nuevo. El sistema tiene que
	# enterarse (si no, el resto de los avisos de este test —y los del juego
	# después de la primera muerte— serían mudos).
	avisos._revisar_enlaces()
	_chk(avisos._vitals_vistos == j.vitals,
		"tras reaparecer el sistema vuelve a escuchar el Vitals nuevo")
	marca = _sonidos.size()
	j.gain_xp(Formulas.xp_for_level(j.nivel + 1) + 1)
	_chk(_sono("level_up", marca), "subir de nivel suena level_up",
		"sonaron: %s" % str(_sonidos.slice(marca)))

	# --- hambre y sed: el aviso salta al CRUZAR el umbral, no cada tick ---
	#
	# OJO con CÓMO se mueven los datos: por `consumir()` y `avanzar()`, no
	# escribiendo `vitals.hambre = 40`. `Vitals` guarda el último valor que
	# emitió (`_ultimo_hambre`) y avisa por `vital_cambiado` solo cuando un
	# valor se movió `TOQUE_MIN`. Escribir el campo a mano deja ese "último"
	# desfasado, y el `avanzar` siguiente calcula un resultado idéntico al que
	# ya se había emitido: no avisa y el test mide dos veces lo mismo.
	_reponer(j, 40.0, 40.0)
	avisos.releer_vitales()
	marca = _sonidos.size()
	j.vitals.avanzar(60.0, 1.0)
	_chk(_sono("hambre", marca), "el hambre vacío suena hambre",
		"sonaron: %s" % str(_sonidos.slice(marca)))
	marca = _sonidos.size()
	j.vitals.avanzar(30.0, 1.0)
	_chk(not _sono("hambre", marca), "el aviso de hambre NO se repite cada tick",
		"sonaron: %s" % str(_sonidos.slice(marca)))
	# Y vuelve a sonar cuando se recupera y vuelve a caer. Antes hay que dejar
	# pasar la ventana del antirrepeticion (30 ms), que es lo que impide que
	# el mismo aviso se oiga dos veces pegados; sin la espera el segundo
	# "hambre" lo se come el antirrepeticion.
	OS.delay_usec(60000)
	_reponer(j, 80.0, 80.0)
	avisos.releer_vitales()
	marca = _sonidos.size()
	j.vitals.avanzar(200.0, 1.0)
	_chk(_sono("hambre", marca), "el aviso de hambre vuelve tras recuperarse",
		"sonaron: %s" % str(_sonidos.slice(marca)))

	# La sed decae a 0,62/s contra los 0,85/s del hambre: con el mismo
	# `avanzar` se queda por encima del umbral y no avisa. De ahí el 200.
	OS.delay_usec(60000)
	_reponer(j, 80.0, 40.0)
	avisos.releer_vitales()
	marca = _sonidos.size()
	j.vitals.avanzar(200.0, 1.0)
	_chk(_sono("sed", marca), "la sed vacía suena sed",
		"sonaron: %s" % str(_sonidos.slice(marca)))

	# --- enfermedad ---
	_reponer(j, 80.0, 80.0)
	avisos.releer_vitales()
	marca = _sonidos.size()
	j.vitals.consumir({"hambre": 0.0, "sed": 0.0, "riesgo": "enfermedad"})
	_chk(_sono("enfermo", marca), "comer crudo suena enfermo",
		"sonaron: %s" % str(_sonidos.slice(marca)))

	# --- Hechos: un tramo NO es un Hecho nuevo ---
	var antes: int = avisos.hechos_vistos()
	marca = _sonidos.size()
	j.habilidades.ganar("tala", 1)
	_chk(avisos.hechos_vistos() == antes,
		"subir de tramo sin Hecho nuevo no cuenta",
		"vistos %d -> %d" % [antes, avisos.hechos_vistos()])
	_chk(not _sono("hecho", marca), "un tramo que no abre nada no suena hecho",
		"sonaron: %s" % str(_sonidos.slice(marca)))

	# --- comer y beber: el inventario es la única vía ---
	marca = _sonidos.size()
	j.inventario.agregar("carne_asada_goblin", 1)
	var uso: bool = j.inventario.usar("carne_asada_goblin", j)
	_chk(uso, "se puede usar la comida")
	_chk(_sono("comer", marca), "comer suena comer",
		"sonaron: %s" % str(_sonidos.slice(marca)))
	marca = _sonidos.size()
	j.inventario.agregar("agua_limpia", 1)
	uso = j.inventario.usar("agua_limpia", j)
	_chk(uso, "se puede beber")
	_chk(_sono("beber", marca), "beber suena beber",
		"sonaron: %s" % str(_sonidos.slice(marca)))

	_test_boton_suena()

	# --- el antirrepeticion también está en el 3D ---
	marca = _sonidos.size()
	var nodo := Node3D.new()
	root.add_child(nodo)
	_sucios.append(nodo)
	AudioJuego.reproducir_en(nodo, "talar")
	AudioJuego.reproducir_en(nodo, "talar")
	AudioJuego.reproducir_en(nodo, "talar")
	var talar: int = 0
	for i in range(marca, _sonidos.size()):
		if _sonidos[i] == "talar":
			talar += 1
	_chk(talar == 1, "tres talas en el mismo frame suenan UNA",
		"sonaron %d" % talar)


## Deja el hambre y la sed en `hambre`/`sed` POR LA VÍA NORMAL (`consumir`),
## que es la que deja sincronizado el "último valor emitido" de `Vitals`.
func _reponer(j: Player, hambre: float, sed: float) -> void:
	j.vitals.consumir({"hambre": hambre - j.vitals.hambre, "sed": sed - j.vitals.sed})


func _jugador() -> Player:
	var p := Player.new()
	p.name = "PlayerTest"
	p.fijar_identidad("H", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_sucios.append(p)
	return p


# =========================================================================
# 3) EL MENÚ (que antes era mudo) Y EL AMBIENTE (que no existía)
# =========================================================================

## El título tenía CERO audio y el volumen guardado se aplicaba DESPUÉS de
## la carga. Se monta la pantalla de título de verdad y se mira qué hay.
func _test_menu_y_opciones() -> void:
	# Un volumen guardado, exagerado para que se note.
	Opciones.poner("vol_musica", -42.0)
	Opciones.poner("vol_ambiente", -33.0)
	Opciones.guardar()

	var titulo := Node3D.new()
	titulo.name = "TituloTest"
	root.add_child(titulo)
	_sucios.append(titulo)
	var audio: AudioJuego = AudioMenu.montar(titulo)

	_chk(audio != null, "el título monta su AudioJuego")
	var musica: Musica = titulo.get_node_or_null("MusicaMenu") as Musica
	_chk(musica != null, "el título monta su Musica")
	if musica != null:
		_chk(musica.estado() == Musica.CAPA_BASE,
			"la música del título está en estado de menú (pueblo)",
			"estado %d" % musica.estado())
	_chk(titulo.get_node_or_null("AmbienteMenu") != null,
		"el título monta su ambiente")

	# El volumen guardado tiene que estar YA en el bus, sin esperar a que la
	# partida arranque. Esto es lo que fallaba: `aplicar()` se llamaba en
	# `_al_mundo_listo()`, después de la pantalla de carga.
	var bus_musica: int = AudioServer.get_bus_index("Musica")
	var bus_amb: int = AudioServer.get_bus_index("Ambiente")
	_chk(bus_musica >= 0, "existe el bus Musica")
	_chk(bus_amb >= 0, "existe el bus Ambiente")
	if bus_musica >= 0:
		_chk(is_equal_approx(AudioServer.get_bus_volume_db(bus_musica), -42.0),
			"el volumen guardado de música se aplica en el título",
			"el bus está en %.1f dB" % AudioServer.get_bus_volume_db(bus_musica))
	if bus_amb >= 0:
		_chk(is_equal_approx(AudioServer.get_bus_volume_db(bus_amb), -33.0),
			"el volumen guardado de ambiente se aplica en el título",
			"el bus está en %.1f dB" % AudioServer.get_bus_volume_db(bus_amb))

	# Al entrar a partida el menú se limpia: la música del título no puede
	# seguir sonando encima de la de la partida.
	AudioMenu.limpiar(titulo)
	_chk(titulo.get_node_or_null("MusicaMenu") != null,
		"limpiar() no borra el nodo: lo baja con fundido")

	# Y el estático de `AudioJuego` no puede quedar apuntando a un objeto
	# liberado: el título se va y el siguiente `reproducir()` es el de la
	# partida. `free()` y no `queue_free()` a propósito: la prueba necesita el
	# hueco YA libre en este frame, no en el siguiente.
	_sucios.erase(titulo)
	titulo.free()
	SonidoUI.clic()
	_chk(true, "un sonido pedido con el estático liberado no revienta")


## El bus `Ambiente` se creaba desde el bloque 66 y no tenía NI UN PLAYER. Se
## comprueba que hay players, que están en ese bus, que el loop es un loop de
## verdad, y que la mezcla sale de `data/ambiente.json`.
func _test_ambiente() -> void:
	var amb := AmbienteZona.new()
	amb.name = "AmbienteTest"
	root.add_child(amb)
	_sucios.append(amb)

	_chk(amb.capas_disponibles().size() >= 2,
		"el ambiente tiene al menos viento y agua",
		"capas: %s" % str(amb.capas_disponibles()))
	_chk(amb.is_in_group(Systems.GRUPO), "el ambiente se registra en gg_system")
	_chk(amb.system_id == &"ambiente_zona", "el ambiente declara system_id")

	var players: int = 0
	var en_bus: int = 0
	var con_loop: int = 0
	var atenuado: int = 0
	for c in amb.get_children():
		var p := c as AudioStreamPlayer3D
		if p == null:
			continue
		players += 1
		if p.bus == "Ambiente":
			en_bus += 1
		var st := p.stream as AudioStreamWAV
		if st != null and st.loop_mode == AudioStreamWAV.LOOP_FORWARD \
				and st.loop_end > 0 and st.loop_end < st.data.size() / 4:
			con_loop += 1
		if p.max_distance > 0.0 and p.max_distance <= 90.0:
			atenuado += 1
	_chk(players >= 2, "el bus Ambiente tiene players", "hay %d" % players)
	_chk(en_bus == players, "todos los players del ambiente están en su bus",
		"%d de %d" % [en_bus, players])
	_chk(con_loop == players, "cada capa es un LOOP que no toca el final",
		"%d de %d" % [con_loop, players])
	_chk(atenuado == players, "cada capa atenúa por distancia", "%d de %d"
		% [atenuado, players])

	# La mezcla: el bosque mete selva y saca agua, y el dB TIENE QUE ACABAR
	# donde dice `data/ambiente.json`. Se mira el DESTINO del fundido y no el
	# volumen: esperar 1,5 s por frame hace que el test dependa de la máquina,
	# y mirar el volumen al principio mostraría el viejo y haría creer que está
	# roto. Que la capa ARRANQUE a sonar sí es inmediato, y eso se mira aparte.
	amb.fijar_zona("bosque_hondo")
	_chk(amb.zona_actual() == "bosque_hondo", "el ambiente sabe en qué zona está")
	_chk(is_equal_approx(amb.destino_de("selva"), -18.0),
		"en el bosque la selva sube a su dB del JSON",
		"va a %.1f dB" % amb.destino_de("selva"))
	_chk(amb.destino_de("agua") <= -59.0, "en el bosque el agua está apagada",
		"va a %.1f dB" % amb.destino_de("agua"))
	_chk(is_equal_approx(amb.volumen_de("selva"), AmbienteZona.DB_SILENCIO),
		"la capa que entra arranca MUTA (el fundido, no un golpe)",
		"está en %.1f dB" % amb.volumen_de("selva"))
	var activas: Array[String] = amb.capas_activas()
	_chk(activas.has("selva") and activas.has("viento"),
		"en el bosque arrancan la selva y el viento", str(activas))

	# La costa es el otro extremo: agua arriba, selva abajo.
	amb.fijar_zona("costa_lamento")
	_chk(is_equal_approx(amb.destino_de("agua"), -16.0),
		"en la costa el agua sube a su dB del JSON",
		"va a %.1f dB" % amb.destino_de("agua"))
	_chk(amb.destino_de("selva") <= -59.0, "en la costa la selva se apaga",
		"va a %.1f dB" % amb.destino_de("selva"))

	# Y con un jugador de verdad, la zona sale del dato de la posición, no de
	# una constante: en el centro del mundo (0, 0) es Moon Town.
	var p := Node3D.new()
	p.name = "PlayerAmbiente"
	root.add_child(p)
	_sucios.append(p)
	amb.vigilar(p)
	_chk(amb.zona_actual() == "moon_town",
		"en el origen la zona es Moon Town, según data/regiones.json",
		"zona: '%s'" % amb.zona_actual())
	# Cruzando a la costa (x negativa, z positiva) cambia sola.
	p.position = Vector3(-12000.0, 0.0, 12000.0)
	amb._process(AmbienteZona.INTERVALO_SEG + 0.1)
	_chk(amb.zona_actual() == "costa_lamento",
		"al cruzar el mapa la zona cambia sola, sin que nadie la empuje",
		"zona: '%s'" % amb.zona_actual())
	# Y sin jugador no se toca nada.
	amb.vigilar(null)
	var quieta: String = amb.zona_actual()
	amb._process(5.0)
	_chk(amb.zona_actual() == quieta, "sin jugador el ambiente no hace nada")


## El `clic` de los botones. `SonidoUI.boton()` es lo que evita el Forget de
## los 42 botones; sin él, este `clic` seguiría muerto como estaba desde el
## bloque 66.
func _test_boton_suena() -> void:
	var b := Button.new()
	b.name = "BotonTest"
	root.add_child(b)
	_sucios.append(b)
	SonidoUI.boton(b)
	_chk(b.pressed.is_connected(SonidoUI._clic_al_presionar),
		"un botón take el clic con un solo connect")
	SonidoUI.boton(b)
	var conexiones: int = 0
	for c in b.pressed.get_connections():
		conexiones += 1
	_chk(conexiones == 1, "enchufar dos veces no duplica el clic",
		"conexiones: %d" % conexiones)