class_name Sintetizador
extends RefCounted
## Bloque 66: sintetizador procedural de SFX.
##
## QUÉ CAMBIA Y POR QUÉ (esto es lo importante, no el número de bits):
##
## El de la fase 20 generaba mono 8 bits a 22050 Hz con un `pow(1-t, 1.5)`
## de envolvente. Eso no es "audio de juego", es un zumbido de Game Boy: poco
## rango dinámico, 11 kHz de techo (Nyquist) y, sobre todo, CERO variación.
##
## La variación es lo que separa un sonido de un asset. Si cada golpe suena
## exactamente igual, el oído aprende la forma y la ignora; con tres o cuatro
## variaciones por sonido, cada impacto se siente como un evento. Es la misma
## razón por la que un motor usa 4-5 samples de impact y no uno.
##
## - 16 bits, 44100 Hz, ESTÉREO. El estéreo no es porque el SFX suene "ancho",
##   es porque un golpe seco mono centrado es molesto: el oído lo lee como un
##   pitido. Con un poco de diferencia entre canales suena a "golpe".
## - Ruido con filtro: el ruido blanco puro es un siseo. Un pasabajos le da
##   cuerpo (el golpe de un arma tiene graves, no agudos).
## - Envolvente de ADSR real (ataque, decaimiento, sustain, release) en vez de
##   una potencia. El release es lo que evita el "clic" al final.
## - Variación: `variantes` (2-4) de cada sonido, con tono, fase y envolvente
##   ligeramente distintos. Se cachean todas al arrancar (barato, son cortas).
##
## Sigue siendo PURO: sin árbol, sin AudioServer, sin estado. Los tests lo
## pueden llamar sin nada montado.

## Tasa de muestreo. 44100 es el estándar y lo que espera Godot por defecto.
const TASA: int = 44100
## Semilla base del ruido. Determinista por diseño: el mismo `id` con la misma
## semilla da el mismo sample, que es lo que hace cacheable el sonido.
const SEMILLA_RUIDO: int = 12345


## Genera el WAV de una receta. `variante` (0..N) cambia sutilmente el timbre.
## Nunca retorna null: con receta vacía usa un blip neutro.
static func generar(receta: Dictionary, variante: int = 0) -> AudioStreamWAV:
	var dur: float = maxf(float(receta.get("duracion", 0.15)), 0.02)
	var n: int = int(TASA * dur)
	if n < 2:
		n = 2
	var f0: float = float(receta.get("freq_ini", 440.0))
	var f1: float = float(receta.get("freq_fin", f0))
	var vol: float = clampf(float(receta.get("volumen", 0.5)), 0.0, 1.0)
	var forma: String = str(receta.get("forma", "seno"))
	# --- la variación: el corazón de que no suene a loops ---
	var deriva: float = 1.0 + float(variante) * float(receta.get("deriva_tono", 0.06))
	var fase0: float = float(variante) * 0.7

	# ADSR. El release es lo que quita el clic: sin él, la onda se corta en
	# seco y se oye un "tac".
	var atk: float = clampf(float(receta.get("ataque", 0.005)), 0.0005, dur * 0.5)
	var rel: float = clampf(float(receta.get("release", 0.04)), 0.005, dur * 0.6)
	var sustain: float = clampf(float(receta.get("sustain", 0.35)), 0.0, 1.0)

	var datos := PackedByteArray()
	# 4 bytes por muestra: 2 canales x 16 bits. Dimensionar a n*2 (mono)
	# truncaba el buffer a la mitad y el bucle de escritura abortaba.
	datos.resize(n * 4)
	var rng := RandomNumberGenerator.new()
	# La semilla depende de la variante: dos golpes suenan distintos pero el
	# mismo "golpe 2" siempre suena igual (cacheable).
	rng.seed = SEMILLA_RUIDO + variante * 7919

	var lp: float = 0.0  # estado del pasabajos del ruido
	var corte: float = clampf(float(receta.get("ruido_corte", 0.25)), 0.01, 1.0)
	var fase: float = fase0
	for i in range(n):
		var t: float = float(i) / float(n)
		var ff: float = lerpf(f0, f1, t) * lerpf(1.0, deriva, 0.5)
		fase += TAU * ff / float(TASA)
		if fase > TAU:
			fase -= TAU

		var s: float = 0.0
		match forma:
			"cuadrada":
				# Cuadrada con algo de sine en la componente fundamental: la
				# cuadrada pura suena a altavoz roto a este sample rate.
				s = 0.7 * (1.0 if sin(fase) >= 0.0 else -1.0) + 0.3 * sin(fase)
			"ruido":
				var blanco: float = rng.randf_range(-1.0, 1.0)
				lp = lerpf(lp, blanco, corte)
				s = lp * 2.0
			"sierra":
				s = (fmod(fase, TAU) / TAU) * 2.0 - 1.0
			"triangular":
				var x: float = fmod(fase, TAU) / TAU
				s = 4.0 * absf(x - 0.5) - 1.0
			_:
				s = sin(fase)

		# ADSR: ataque, luego decaimiento a sustain, y un release al final.
		#
		# OJO (bloque 66): los tres tiempos van NORMALIZADOS a 0..1, porque
		# `t` lo está. La versión de la fase 21 usaba `atk` y `dur - rel` en
		# SEGUNDOS contra un `t` normalizado, así que con un sonido de 0,12 s
		# el umbral de release (0,08) nunca se alcanzaba: el release era
		# código muerto y TODO sonido se cortaba en sustain, que es
		# precisamente el "clic" que la fase 21 decía evitar.
		var env: float = 0.0
		var t_a: float = atk / dur
		var t_r: float = maxf(dur - rel, 0.0) / dur
		if t < t_a:
			env = t / maxf(t_a, 0.0001)
		elif t < t_r:
			var x2: float = (t - t_a) / maxf(t_r - t_a, 0.0001)
			env = lerpf(1.0, sustain, x2)
		else:
			var x3: float = (t - t_r) / maxf(rel / dur, 0.0001)
			env = sustain * (1.0 - x3)

		var amp: float = clampf(s * vol * env, -1.0, 1.0)
		# Estéreo: la diferencia entre canales es lo que da cuerpo al golpe sin
		# necesitar reverb. Se invierte ligeramente el canal derecho.
		var der: float = amp
		var izq: float = amp
		if forma == "ruido":
			der = clampf(amp * 0.9 + rng.randf_range(-0.05, 0.05) * env, -1.0, 1.0)
		_escribir(datos, i, izq, der)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = TASA
	stream.stereo = true
	stream.data = datos
	return stream


## Genera un LOOP de ambiente. `duracion` en segundos (la receta lo ignora:
## un bed de viento son 6 s, no 0,3).
##
## POR QUÉ NO PUEDE SER `generar()` CON `loop_mode`: un loop que empieza y
## termina en el mismo sample se oye como un corte cada 6 segundos, y con
## ruido eso es un "clic" de siseo. El truco es el CRUCE DE EXTREMOS: los
## últimos FUNDIDO muestras se mezclan con las primeras y el bucle
## `loop_end` cae ANTES del tramo ya mezclado. Lo que se repite es una curva
## que ya entra y sale sola.
##
## Además el ruido tiene que ir filtrado y con la envolvente MUY lenta
## (ruido_ataque de 0,5 s o más). Con el ADSR de un golpe (5 ms) un loop de
## ruido suena a un siseo que se corta, no a viento.
static func generar_bucle(receta: Dictionary, duracion: float = 6.0) -> AudioStreamWAV:
	var seg: float = maxf(duracion, 0.5)
	var n: int = int(TASA * seg)
	if n < TASA / 2:
		n = TASA / 2
	var fundido: int = clampi(n / 8, 256, TASA / 2)
	var loop_end: int = maxi(n - fundido, fundido)

	var f0: float = float(receta.get("freq_ini", 300.0))
	var f1: float = float(receta.get("freq_fin", f0))
	var vol: float = clampf(float(receta.get("volumen", 0.3)), 0.0, 1.0)
	var forma: String = str(receta.get("forma", "ruido"))
	# Envolvente LENTA a propósito: es lo que separa "viento" de "siseo".
	var atk: float = clampf(float(receta.get("ruido_ataque", 0.8)), 0.05, seg * 0.45)
	var rel: float = clampf(float(receta.get("ruido_release", 0.8)), 0.05, seg * 0.45)
	var corte: float = clampf(float(receta.get("ruido_corte", 0.06)), 0.002, 1.0)

	var datos := PackedByteArray()
	datos.resize(n * 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEMILLA_RUIDO + 9173

	var lp: float = 0.0
	var fase: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(TASA)
		var ff: float = lerpf(f0, f1, t / seg)
		fase += TAU * ff / float(TASA)
		if fase > TAU:
			fase -= TAU

		# --- el cuerpo del sonido ---
		var s: float = 0.0
		match forma:
			"agua":
				# Agua: ruido de banda (dos pasabajos en cascada, uno abierto y
				# otro cerrado) + un "burbujeo" de seno grave modulado. La
				# diferencia con el viento es el bubbling: es lo que el oído lee
				# como agua y no como aire en movimiento.
				var lp2: float = lp
				var blanco: float = rng.randf_range(-1.0, 1.0)
				lp = lerpf(lp, blanco, corte)
				lp2 = lerpf(lp2, lp, corte * 0.5)
				var burbuja: float = sin(TAU * maxf(f1, 40.0) * t
					+ sin(TAU * 0.35 * t) * 2.2) * 0.35
				s = (lp - lp2) * 2.4 + burbuja
			"ruido":
				var blanco2: float = rng.randf_range(-1.0, 1.0)
				lp = lerpf(lp, blanco2, corte)
				s = lp * 2.0
			_:
				for g in [0, 7, 12]:
					s += sin(fase + TAU * float(g) / 12.0) / 3.0

		# --- envolvente lenta: entra, sostiene, sale ---
		var env: float = 0.0
		var t_a: float = atk / seg
		var t_r: float = maxf(1.0 - rel / seg, t_a + 0.05)
		if t < t_a:
			env = t / maxf(t_a, 0.0001)
		elif t < t_r:
			env = 1.0
		else:
			env = maxf(1.0 - (t - t_r) / maxf(1.0 - t_r, 0.0001), 0.0)
		# Un pulso lentísimo de volumen (0,07 Hz) es lo que hace que el viento
		# "respire" en vez de ser un muro de ruido constante.
		var respiro: float = 0.75 + 0.25 * sin(TAU * 0.07 * t)

		var amp: float = clampf(s * vol * env * respiro, -1.0, 1.0)
		_escribir(datos, i, amp, amp)

	# --- el cruce de extremos: lo que hace que el bucle no se oiga ---
	for k in range(fundido):
		var a: float = float(k) / float(fundido)
		var i_ini: int = k
		var i_fin: int = loop_end + k
		if i_fin >= n:
			break
		_mezclar(datos, i_fin, datos[i_ini * 4], datos[i_ini * 4 + 1],
			datos[i_ini * 4 + 2], datos[i_ini * 4 + 3], a)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = TASA
	stream.stereo = true
	stream.data = datos
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = loop_end
	return stream


## Mezcla el sample `idx` con los bytes del sample `fuente` (4 bytes: LI,LD,
## RI,RD) con peso `peso` (0 = solo el original, 1 = solo la fuente).
static func _mezclar(buf: PackedByteArray, idx: int, li: int, ld: int,
		ri: int, rd: int, peso: float) -> void:
	var w: float = clampf(peso, 0.0, 1.0)
	var base: int = idx * 4
	buf[base] = int(lerpf(float(buf[base]), float(li & 0xFF), w)) & 0xFF
	buf[base + 1] = int(lerpf(float(buf[base + 1]), float(li >> 8), w)) & 0xFF
	buf[base + 2] = int(lerpf(float(buf[base + 2]), float(ri & 0xFF), w)) & 0xFF
	buf[base + 3] = int(lerpf(float(buf[base + 3]), float(ri >> 8), w)) & 0xFF


## Escribe un sample estéreo de 16 bits con signo en el buffer, en little-endian
## (que es como Godot guarda FORMAT_16_BITS). Manual, no con `encode_s16`,
## porque se escribe en un `PackedByteArray` ya dimensionado y `encode_s16`
## crea un array nuevo por sample (GC en un bucle de audio = tirones).
static func _escribir(buf: PackedByteArray, i: int, izq: float, der: float) -> void:
	var li: int = int(clampf(izq, -1.0, 1.0) * 32767.0)
	var ri: int = int(clampf(der, -1.0, 1.0) * 32767.0)
	var base: int = i * 4
	buf[base] = li & 0xFF
	buf[base + 1] = (li >> 8) & 0xFF
	buf[base + 2] = ri & 0xFF
	buf[base + 3] = (ri >> 8) & 0xFF


## Cuántas variantes tiene un sonido. Lo decide la receta (`variantes`) con un
## default de 3: menos de 2 no se nota la variación, más de 4 es tirar samples.
static func variantes_de(receta: Dictionary) -> int:
	return maxi(1, mini(8, int(receta.get("variantes", 3))))
