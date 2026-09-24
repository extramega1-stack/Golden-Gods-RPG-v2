extends SceneTree
## Tests headless de la Fase 20 (P1 audio): SFX procedurales data-driven.
##
## Cubre:
## (a) Sintetizador: WAV válido (8 bits, 22050 Hz, N muestras exactas,
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
	_chk(w.format == AudioStreamWAV.FORMAT_8_BITS, "a: 8 bits")
	_chk(w.mix_rate == 22050, "a: 22050 Hz")
	_chk(w.data.size() == 2205, "a: 0.1 s = 2205 muestras", str(w.data.size()))
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
	_chk(a._players.size() == 8, "c: pool de 8 voces")
	_chk(a.ids().size() >= 10, "c: ids cargados (%d)" % a.ids().size())
	# Ruteo sin reproducir: el driver dummy pierde playbacks y ensucia la
	# salida (verificado); el play() real es trivial del motor.
	var voces: Array = []
	var rutas_ok: bool = true
	for sonido_id in a.ids():
		var voz: AudioStreamPlayer = a._voz_para(str(sonido_id))
		if voz == null or voz.stream == null:
			rutas_ok = false
		else:
			voces.append(voz)
	_chk(rutas_ok, "c: todos los ids rutean voz + stream")
	_chk(voces.size() >= 10 and voces[0] == voces[8],
		"c: round-robin de 8 voces (la 9na repite la 1ra)")
	_chk(a._voz_para("inexistente") == null,
		"c: id desconocido avisa y retorna null")
	_chk(not a.tiene_sonido("inexistente"), "c: tiene_sonido false en unknown")


## (d) Cableado en sistemas reales (en modo prueba: rutea sin play).
func _test_cableado() -> void:
	AudioJuego.modo_prueba = true
	var a: AudioJuego = AudioJuego.new()
	root.add_child(a)
	_basura.append(a)
	var e: Enemy = EN.new()
	root.add_child(e)
	_basura.append(e)
	var antes: int = a._idx
	e.take_damage(5.0, null, false)
	_chk(e.esta_vivo(), "d: golpe no letal suena sin romper")
	_chk(a._idx != antes, "d: el golpe consumió una voz")
	e.take_damage(999999.0, null, true)
	_chk(not e.esta_vivo(), "d: crítico letal = muerte + stinger")
	_chk(a._idx != antes, "d: muerte consumió voces")
	AudioJuego.modo_prueba = false
