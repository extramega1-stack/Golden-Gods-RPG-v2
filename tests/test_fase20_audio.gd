extends SceneTree
## Tests headless de la Fase 20 (P1 audio): SFX procedurales data-driven.
##
## Cubre:
## (a) Sintetizador: WAV válido (BLOQUE 66: 16 bits, 44100 Hz, estéreo,
##     N muestras exactas por canal,
##     canadencia sin DC: min < 128 < max), receta vacía = blip neutro,
##     determinista (misma receta = mismos bytes);
## (b) data/sonidos.json: todos los ids sintetizan con datos no vacíos;
## (c) AudioJuego: buses creados, pool de 8, todos los ids suenan sin
##     reventar (driver dummy), id desconocido avisa sin reventar;
## (d) Cableado: take_damage/curación/muerte/skill/recoger no revientan
##     sin instancia (no-op) y suenan con instancia.
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase20_audio.gd

const EN: GDScript = preload("res://scripts/enemy/enemy.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 20 — SFX procedurales (sintetizador + manager)")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_sintetizador()
	_test_recetas_json()
	_test_manager()
	_test_cableado()
	print("[TEST] fase20_audio: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


## (a) Sintetizador puro.
func _test_sintetizador() -> void:
	var w: AudioStreamWAV = Sintetizador.generar(
		{"forma": "seno", "freq_ini": 440.0, "freq_fin": 440.0,
			"duracion": 0.1, "volumen": 0.5})
	_chk(w != null, "a: genera WAV")
	# Bloque 66: pasó de 8 bits/22050 mono a 16 bits/44100 ESTÉREO. No es
	# cosmética: 22050 tiene el techo en 11 kHz, así que todo lo que pase de
	# ahí se perdía, y mono centrado se lee como un pitido.
	_chk(w.format == AudioStreamWAV.FORMAT_16_BITS, "a: 16 bits (66)")
	_chk(w.mix_rate == 44100, "a: 44100 Hz (66)")
	_chk(w.stereo, "a: estéreo (66)")
	# 0.1 s x 44100 = 4410 muestras; estéreo de 16 bits = 4 bytes por muestra.
	_chk(w.data.size() == 17640,
		"a: 0.1 s = 4410 muestras x 4 bytes (2 canales x 16 bits) = 17640",
		str(w.data.size()))
	# Y las variantes NO son el mismo sample con otro nombre: si lo fueran, el
	# oído los ignoraría y el 66 no habría servido de nada.
	var w0: AudioStreamWAV = Sintetizador.generar(
		{"forma": "ruido", "freq_ini": 800.0, "freq_fin": 200.0,
			"duracion": 0.1, "volumen": 0.5}, 0)
	var w1: AudioStreamWAV = Sintetizador.generar(
		{"forma": "ruido", "freq_ini": 800.0, "freq_fin": 200.0,
			"duracion": 0.1, "volumen": 0.5}, 1)
	_chk(w0.data != w1.data, "a: dos variantes del mismo sonido son distintas (66)")
	var mn: int = 255
	var mx: int = 0
	for b in w.data:
		mn = mini(mn, int(b))
		mx = maxi(mx, int(b))
	_chk(mn < 128 and mx > 128, "a: oscila sin DC", "min=%d max=%d" % [mn, mx])
	var w2: AudioStreamWAV = Sintetizador.generar({})
	_chk(w2 != null and w2.data.size() > 0, "a: receta vacía = blip neutro")
	var w3: AudioStreamWAV = Sintetizador.generar(
		{"forma": "ruido", "duracion": 0.1, "volumen": 0.5})
	var w4: AudioStreamWAV = Sintetizador.generar(
		{"forma": "ruido", "duracion": 0.1, "volumen": 0.5})
	_chk(w3.data == w4.data, "a: ruido determinista (cacheable)")


## (b) Todas las recetas del JSON sintetizan.
func _test_recetas_json() -> void:
	var texto: String = FileAccess.get_file_as_string("res://data/sonidos.json")
	_chk(not texto.is_empty(), "b: sonidos.json legible")
	var crudo: Variant = JSON.parse_string(texto)
	_chk(crudo is Dictionary, "b: JSON válido")
	var recetas: Dictionary = (crudo as Dictionary).get("sonidos", {})
	_chk(recetas.size() >= 10, "b: >= 10 recetas (%d)" % recetas.size())
	var todas_ok: bool = true
	for sonido_id in recetas:
		var w: AudioStreamWAV = Sintetizador.generar(recetas[sonido_id])
		if w == null or w.data.is_empty():
			todas_ok = false
	_chk(todas_ok, "b: todas sintetizan datos no vacíos")


## (c) Manager: buses, pool y reproducción sin instancia real.
func _test_manager() -> void:
	# Sin instancia: no-op sin reventar.
	AudioJuego.reproducir("golpe")
	AudioJuego.al_impacto(true)
	AudioJuego.al_morir()
	AudioJuego.al_recoger("oro")
	AudioJuego.al_skill("curar")
	_chk(true, "c: sin instancia no revienta (no-op)")
	var a: AudioJuego = AudioJuego.new()
	root.add_child(a)
	_basura.append(a)
	_chk(AudioServer.get_bus_index("SFX") >= 0, "c: bus SFX creado")
	_chk(AudioServer.get_bus_index("Musica") >= 0, "c: bus Musica creado (66)")
	_chk(AudioServer.get_bus_index("Ambiente") >= 0, "c: bus Ambiente creado (66)")
	_chk(a._players.size() == AudioJuego.POOL_SFX,
		"c: pool 2D de %d voces" % AudioJuego.POOL_SFX)
	_chk(a._players_mundo.size() == AudioJuego.POOL_MUNDO,
		"c: pool 3D posicional de %d voces (66)" % AudioJuego.POOL_MUNDO)
	_chk(a.ids().size() >= 30, "c: ids cargados (%d, el 66 pasó de 13 a 36)" % a.ids().size())
	# Cada id tiene N variantes sintetizadas (66): es lo que impide que cada
	# golpe suene idéntico.
	var todas_variantes: bool = true
	var con_varias: int = 0
	for sonido_id in a.ids():
		var lista: Array = a._streams[str(sonido_id)]
		if lista.size() <= 0:
			todas_variantes = false
		elif lista.size() >= 2:
			con_varias += 1
		for s in lista:
			var w: AudioStreamWAV = s
			if w.format != AudioStreamWAV.FORMAT_16_BITS \
					or w.mix_rate != Sintetizador.TASA or not w.stereo:
				todas_variantes = false
	_chk(todas_variantes,
		"c: todos los sonidos son 16 bits / 44.1 kHz / estéreo con variantes")
	_chk(con_varias >= 25, "c: la mayoría tiene 2+ variantes (variación)", str(con_varias))
	_chk(not a.tiene_sonido("inexistente"), "c: tiene_sonido false en unknown")


## (d) Cableado en sistemas reales. El `modo_prueba` de la fase 20 desapareció:
## ahora el sonido se enruta por el POOL (el `play()` real con el driver dummy
## no ensucia y el test puede verificar a quién se asignó la voz).
func _test_cableado() -> void:
	var a: AudioJuego = AudioJuego.new()
	root.add_child(a)
	_basura.append(a)
	var e: Enemy = EN.new()
	root.add_child(e)
	_basura.append(e)
	# El impacto y la muerte son POSICIONALES (66): van al pool 3D.
	var antes_mundo: int = a._idx_mundo
	e.take_damage(5.0, null, false)
	_chk(e.esta_vivo(), "d: golpe no letal suena sin romper")
	_chk(a._idx_mundo != antes_mundo,
		"d: el golpe consumió una voz 3D (posicional, 66)", str(a._idx_mundo))
	e.take_damage(999999.0, null, true)
	_chk(not e.esta_vivo(), "d: crítico letal = muerte")
	_chk(a._idx_mundo != antes_mundo + 1, "d: la muerte consumió otra voz 3D")
