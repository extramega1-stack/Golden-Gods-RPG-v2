class_name Sintetizador
extends RefCounted
## Sintetizador procedural de SFX (fase 20, P1 audio).
##
## Genera AudioStreamWAV mono de 8 bits a 22050 Hz desde una receta
## data-driven (`data/sonidos.json`): forma (seno/cuadrado/ruido), barrido
## de frecuencia ini→fin, envolvente de decaimiento y ataque corto (sin
## clic). El ruido usa semilla fija: el mismo id siempre suena igual
## (cacheable). Puro y testeable, sin árbol ni AudioServer.

## Tasa de muestreo de todos los SFX.
const TASA: int = 22050
## Semilla del ruido (determinista por diseño).
const SEMILLA_RUIDO: int = 12345


## Genera el WAV de una receta. Nunca retorna null: con receta vacía usa
## un blip neutro; los campos ausentes usan sus defaults.
static func generar(receta: Dictionary) -> AudioStreamWAV:
	var dur: float = maxf(float(receta.get("duracion", 0.15)), 0.02)
	var n: int = int(TASA * dur)
	var f0: float = float(receta.get("freq_ini", 440.0))
	var f1: float = float(receta.get("freq_fin", f0))
	var vol: float = clampf(float(receta.get("volumen", 0.5)), 0.0, 1.0)
	var forma: String = str(receta.get("forma", "seno"))
	var datos := PackedByteArray()
	datos.resize(n)
	var fase: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = SEMILLA_RUIDO
	var ataque: float = 0.005 * float(TASA)
	for i in range(n):
		var t: float = float(i) / float(n)
		fase += TAU * lerpf(f0, f1, t) / float(TASA)
		var s: float = 0.0
		match forma:
			"cuadrado":
				s = 1.0 if sin(fase) >= 0.0 else -1.0
			"ruido":
				s = rng.randf_range(-1.0, 1.0)
			_:
				s = sin(fase)
		var env: float = pow(1.0 - t, 1.5)
		var atk: float = minf(float(i) / ataque, 1.0)
		datos[i] = int(clampf(s * vol * env * atk, -1.0, 1.0) * 127.0 + 128.0)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = TASA
	stream.stereo = false
	stream.data = datos
	return stream
