extends RefCounted
## Contacto — cuándo está un pie en el suelo, y cuándo no.
##
## RESPONSABILIDAD ÚNICA: decidir, sobre la serie de alturas de un hueso, qué
## instante es pisada y cuál es vuelo. La usan los dos medidores que dependen de
## eso (el patinaje y la dirección) y, sobre todo, la comparten para que no
## puedan discrepar: si cada uno tivesse su umbral, un informe podría decir
## "el pie patina 100 cm" y "el pie va al revés" con dos verdadés
## incompatibles, y eso ya pasó.
##
## EL UMBRAL Y POR QUÉ ES UNA FRACCIÓN, no un centímetro fijo: cada modelo
## viene a una escala y con un esqueleto distinto, así que "el pie está a 3 cm
## del suelo" no significa nada entre modelos. Lo que sí significa lo mismo en
## todos es "está en el 30% más bajo de lo que este pie levanta". Con 30% se
## agarra el apoyo plano del ciclo sin comerse el primer dedo del despegue.
##
## LO QUE ESTA CLASE NO PUEDE DECIDIR, y por eso el número que sale se lee con
## la fracción de pisada al lado: un clip en el que el pie baja poco tiene
## pocas muestras en contacto, y a partir de una pisada demasiado corta el
## número de deslizamiento deja de ser una medida y pasa a ser ruido. El
## informe lo dice en vez de dejar que se lea solo.

## Fracción de la excursión vertical del hueso que se considera apoyo.
const FRACCION_CONTACTO: float = 0.30
## Suelo absoluto por debajo del cual el hueso está plantado, en u. Cubre los
## clips con muy poca elevación de pie.
const CONTACTO_MIN: float = 0.010
## Excursión vertical mínima para que un hueso pueda "tocar el suelo" en algún
## momento del ciclo. Por debajo de esto la pose está clavada y no hay pisada
## que medir.
const EXCURSION_MIN: float = 0.005
## Pisada más corta que esto, en fracción del ciclo, y el número se declara no
## confiable. Un pie supported en el 20% del ciclo no es una pisada, es el
## frame que rozó el suelo.
const FRACCION_FIABLE: float = 0.30


## Las ventanas de apoyo de un hueso, sobre su serie de alturas.
##
## `alturas` es la Y de cada instante (en el mismo espacio que se quiera: el
## threshold es una fracción de la excursión, que es invariante de escala).
## Devuelve `ok`, `motivo`, `suelo`, `alto`, `excursion`, `umbral`, `ventanas`
## (lista de `{i0, i1, t0, t1, dt}`), `contacto_total` (segundos) y
## `fraccion` (contacto sobre la duración del ciclo), y `fiable`.
static func detectar(alturas: PackedFloat32Array, paso: float,
		duracion: float) -> Dictionary:
	var salida: Dictionary = {"ok": false, "motivo": "", "fiable": false,
			"ventanas": [] as Array[Dictionary]}
	if alturas.size() < 3:
		salida["motivo"] = "menos de 3 instantes no alcanzan para un ciclo"
		return salida
	var suelo: float = alturas[0]
	var alto: float = alturas[0]
	for v in alturas:
		suelo = minf(suelo, v)
		alto = maxf(alto, v)
	var excursion: float = alto - suelo
	salida["suelo"] = suelo
	salida["alto"] = alto
	salida["excursion"] = excursion
	if excursion < EXCURSION_MIN:
		salida["motivo"] = "el hueso no se levanta en vertical (%0.4f u): " \
				% excursion + "no hay pisada"
		return salida
	var umbral: float = suelo + maxf(CONTACTO_MIN, FRACCION_CONTACTO * excursion)
	salida["umbral"] = umbral
	var ventanas: Array[Dictionary] = _ventanas(alturas, umbral, paso)
	salida["ventanas"] = ventanas
	if ventanas.is_empty():
		salida["motivo"] = "el hueso nunca baja del umbral de contacto en este clip"
		return salida
	var total: float = 0.0
	for v in ventanas:
		total += float(v["dt"])
	salida["contacto_total"] = total
	var fraccion: float = total / maxf(duracion, 0.0001)
	salida["fraccion"] = fraccion
	salida["fiable"] = fraccion >= FRACCION_FIABLE
	salida["ok"] = true
	if not bool(salida["fiable"]):
		salida["motivo"] = "el pie solo esta en contacto el %.0f %% del ciclo " \
				% (fraccion * 100.0) + \
				"(el umbral exige el %.0f %%): el deslizamiento por ventana es " \
				% (FRACCION_FIABLE * 100.0) + \
				"poco confiable; el número de ciclo, si"
	return salida


## La ventana de apoyo MÁS LARGA: es la pisada, no el roce. Devuelve un
## `Dictionary` vacío si no hay ninguna.
static func mayor(ventanas: Array[Dictionary]) -> Dictionary:
	if ventanas.is_empty():
		return {}
	var mejor: Dictionary = ventanas[0]
	for v in ventanas:
		if float(v["dt"]) > float(mejor["dt"]):
			mejor = v
	return mejor


## Rachas de instantes por debajo del umbral, con los índices y los segundos.
static func _ventanas(alturas: PackedFloat32Array, umbral: float,
		paso: float) -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	var dentro: bool = false
	var i0: int = 0
	for i in alturas.size():
		var plantado: bool = alturas[i] <= umbral
		if plantado and not dentro:
			dentro = true
			i0 = i
		elif not plantado and dentro:
			dentro = false
			_suma_ventana(salida, i0, maxi(i - 1, i0), paso)
	if dentro:
		_suma_ventana(salida, i0, alturas.size() - 1, paso)
	return salida


static func _suma_ventana(destino: Array[Dictionary], i0: int, i1: int,
		paso: float) -> void:
	destino.append({"i0": i0, "i1": i1, "dt": paso * float(i1 - i0),
			"t0": paso * float(i0), "t1": paso * float(i1)})
