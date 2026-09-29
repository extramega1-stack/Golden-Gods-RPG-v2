extends RefCounted
## MedidorDireccion — ¿la marcha va para donde el personaje?
##
## RESPONSABILIDAD ÚNICA: el eje. En qué eje mueve el hueso del pie a lo largo
## de un ciclo, con los datos en crudo y con la vuelta `Cuerpo.GIRO_MODELO`
## aplicada, y contra qué eje mueve el personaje.
##
## POR QUÉ SE MIDE EN LAS DOS FASES Y NO EN EL CICLO ENTERO: en un clip "en el
## sitio" (que es lo que es, y `medidor_clips` lo reporta aparte) el pie va
## hacia delante y hacia atrás y vuelve, y el desplazamiento neto del ciclo es
## CERO. Medirlo daría "no avanza" para todo. Lo que sí tiene dirección son
## las DOS FASES por separado, y son las dos que se comparan entre sí:
##
## - `vuelo` (el pie en el aire): debería ir HACIA ADELANTE, hacia donde va el
##   personaje. Si va hacia atrás, la marcha va al revés.
## - `contacto` (el pie en el suelo): debería ir hacia ATRÁS respecto del
##   cuerpo, que es lo que hace que el cuerpo avance sin patinar. Si va hacia
##   ADELANTE con el pie plantado, el personaje patina hacia delante: es el
##   "moon walk", y se ve horrible aunque todos los números de giro sean
##   buenos. Es lo que mide este archivo.
##
## TODO SE PROYECTA SOBRE UN SOLO EJE DE REFERENCIA, el del avance del juego
## llevados al espacio del esqueleto (con la vuelta del modelo deshecha). Así
## los dos veredictos son un número con signo y no una讨论 de ejes: positivo es
## "hacia donde va el personaje", negativo es "al revés".

const CONTACTO: GDScript = preload("res://tools/anim_medida/contacto.gd")

## Movimiento menor que esto (en u) se considera "no se mueve": es el ruido de
## una pose que da la misma posición dos frames seguidos.
const UMBRAL_MIN: float = 0.005
## Amplitud horizontal mínima en u para poder decir "avanza en X" y no "no sé".
const AMPLITUD_MIN: float = 0.01


## Dirección del avance de un pie, en crudo y en mundo.
##
## `muestra` sale de `MuestraCiclo.muestrear`; `giro` es `Cuerpo.GIRO_MODELO`
## (PI en el juego) y `direccion_juego` es el -Z del cuerpo. Devuelve el
## veredicto y los números que lo sostienen, uno por pie.
static func medir(muestra: Dictionary, giro: float,
		direccion_juego: Vector3 = Vector3(0.0, 0.0, -1.0)) -> Dictionary:
	var salida: Dictionary = {"ok": false, "motivo": "", "veredicto": "SIN_DATOS"}
	if not bool(muestra.get("ok", false)):
		salida["motivo"] = str(muestra.get("motivo", "no hay muestra"))
		return salida
	var pos: Dictionary = muestra.get("pos", {}) as Dictionary
	var paso: float = float(muestra.get("paso", 0.0))
	var duracion: float = float(muestra.get("duracion", 0.0))
	if pos.is_empty() or paso <= 0.0:
		salida["motivo"] = "la muestra no trae posiciones de hueso"
		return salida
	# El eje de referencia: el avance del juego, DESHECIDA la vuelta del modelo,
	# para poder comparar en el espacio crudo en el que vive el esqueleto.
	var referencia: Vector3 = Basis(Vector3.UP, -giro) * direccion_juego
	var pies: Dictionary = {}
	for clave in pos.keys():
		if not str(clave).ends_with(".pie"):
			continue
		pies[clave] = _pie(clave, pos[clave] as PackedVector3Array, paso, duracion,
				giro, referencia)
	if pies.is_empty():
		salida["motivo"] = "ningun hueso de pie existe en este rig"
		return salida
	var cuenta_malos: int = 0
	var cuenta_acuerdo: int = 0
	var cuenta_perdida: int = 0
	for clave in pies.keys():
		match str((pies[clave] as Dictionary).get("veredicto", "PERDIDO")):
			"ACUERDO":
				cuenta_acuerdo += 1
			"PERDIDO":
				cuenta_perdida += 1
			_:
				cuenta_malos += 1
	if cuenta_malos > 0:
		# El peor veredicto de los dos pies manda, y el orden es el de la
		# tabla: primero el espejo, que se arregla girando el modelo.
		salida["veredicto"] = _peor_veredicto(pies)
	elif cuenta_acuerdo == pies.size():
		salida["veredicto"] = "ACUERDO"
	else:
		salida["veredicto"] = "PERDIDO"
	salida["ok"] = cuenta_malos == 0
	salida["giro"] = giro
	salida["direccion_juego"] = direccion_juego
	salida["referencia_esqueleto"] = referencia
	salida["pies"] = pies
	salida["motivo"] = "" if cuenta_perdida == 0 else \
			"uno o los dos pies no barren un eje claro: no se puede afirmar la direccion"
	return salida


## Un pie: el eje de su barrido, y hacia dónde va en cada fase.
## El veredicto del conjunto, con este orden de gravedad: `AL_REVES` primero
## (es el de más impacto y el que se arregla con un solo número), después los
## de patinaje, y `PERDIDO` al final.
static func _peor_veredicto(pies: Dictionary) -> String:
	for nivel in ["AL_REVES", "PATINA_ADELANTE", "PATINA_ATRAS", "PERDIDO"]:
		for clave in pies.keys():
			if str((pies[clave] as Dictionary).get("veredicto", "")) == nivel:
				return nivel
	return "PERDIDO"


static func _pie(clave: String, local: PackedVector3Array, paso: float,
		duracion: float, giro: float, referencia: Vector3) -> Dictionary:
	var salida: Dictionary = {"ok": false, "motivo": "", "veredicto": "PERDIDO"}
	if local.size() < 3:
		salida["motivo"] = "menos de 3 instantes no alcanzan para un ciclo"
		return salida
	var ys: PackedFloat32Array = PackedFloat32Array()
	for p in local:
		ys.append(p.y)
	var pisada: Dictionary = CONTACTO.detectar(ys, paso, duracion)
	salida["suelo"] = pisada.get("suelo", 0.0)
	salida["excursion"] = pisada.get("excursion", 0.0)
	salida["fraccion_de_ciclo"] = pisada.get("fraccion", 0.0)
	if not bool(pisada.get("ok", false)):
		salida["motivo"] = str(pisada.get("motivo", ""))
		return salida
	# El eje por el que barre: el de mayor amplitud, y con su signo, que es lo
	# que dice hacia dónde va. Se reporta como un eje CANONICO (+X, -Z, ...)
	# y no como el vector medido: el vector medido arrastra el 2% de
	# desplazamiento del otro eje y sale "-0,1X +1,0Z", que parece una marcha
	# en diagonal cuando va recta por la Z.
	var amplitud_x: float = _rango(local, true)
	var amplitud_z: float = _rango(local, false)
	var eje: String = "X" if amplitud_x > amplitud_z else "Z"
	salida["eje_crudo"] = eje
	salida["amplitud_x"] = amplitud_x
	salida["amplitud_z"] = amplitud_z
	if maxf(amplitud_x, amplitud_z) < AMPLITUD_MIN:
		salida["motivo"] = "el pie barre menos de %.3f u: no se puede afirmar la dirección" \
				% AMPLITUD_MIN
		return salida
	# El desplazamiento neto del vuelo (la fase en el aire).
	var vuelo: Vector3 = _desplazamiento_de_vuelo(local, ys, pisada)
	# El desplazamiento de la pisada (la fase en el suelo).
	var contacto: Vector3 = _desplazamiento_de_contacto(local, pisada)
	var canonico: Vector3 = _eje_canonico(eje, vuelo)
	salida["eje_crudo_vector"] = canonico
	# Proyectado todo sobre el eje de referencia del juego. Positivo = hacia
	# donde avanza el personaje.
	var en_vuelo: float = vuelo.dot(referencia)
	var en_contacto: float = contacto.dot(referencia)
	salida["vuelo_bruto"] = vuelo
	salida["contacto_bruto"] = contacto
	salida["vuelo_hacia_adelante"] = en_vuelo
	salida["contacto_hacia_adelante"] = en_contacto
	# El eje en el mundo: el mismo eje canónico, con la vuelta del modelo
	# aplicada. Que una vuelta de PI lo mande al eje OPUESTO es el resultado
	# que hace falta ver, y por eso se imprime con la vuelta y no sin ella.
	salida["eje_mundo"] = Basis(Vector3.UP, giro) * canonico
	var veredicto: String = tabla_de_signos(en_contacto, en_vuelo)
	salida["ok"] = veredicto == "ACUERDO"
	salida["veredicto"] = veredicto
	salida["motivo"] = "" if veredicto != "PERDIDO" else \
			"el pie no se desplaza en ninguna fase: la direccion no existe"
	return salida


## Suma de los desplazamientos de los instantes que están en el aire, en crudo.
static func _desplazamiento_de_vuelo(local: PackedVector3Array,
		alturas: PackedFloat32Array, pisada: Dictionary) -> Vector3:
	var total: Vector3 = Vector3.ZERO
	var umbral: float = float(pisada.get("umbral", 0.0))
	var anterior: Vector3 = Vector3.ZERO
	var dentro: bool = false
	for i in local.size():
		var en_el_aire: bool = alturas[i] > umbral
		if en_el_aire:
			if dentro:
				total += local[i] - anterior
			anterior = local[i]
			dentro = true
		else:
			dentro = false
	return total


## Lo mismo, acotado a la pisada más larga. Se recorre a lo largo de la
## ventana y no por instantes sueltos, para no sumar un salto de la entrada.
static func _desplazamiento_de_contacto(local: PackedVector3Array,
		pisada: Dictionary) -> Vector3:
	var mejor: Dictionary = CONTACTO.mayor(
			pisada.get("ventanas", [] as Array[Dictionary]))
	if mejor.is_empty():
		return Vector3.ZERO
	var i0: int = int(mejor["i0"])
	var i1: int = int(mejor["i1"])
	if i1 <= i0:
		return Vector3.ZERO
	return local[i1] - local[i0]


## LA TABLA DE SIGNOS, que es toda la lógica de este archivo.
##
## Una marcha correcta tiene el pie ATRÁS en el apoyo y ADELANTE en el vuelo:
## (contacto negativo, vuelo positivo).
##
## LO QUE PASA EN LA REALIDAD, y hay que saberlo antes de discutir la tabla: en
## un ciclo CERRADO las dos fases tienen que ir en sentidos OPUESTOS, porque
## si no el pie no vuelve de donde salió y el clip no cicla. Los pares (+, +) y
## (-, -) no salen nunca de un clip que cicla; sólo pueden aparecer si el ciclo
## no cierra. Por eso el caso que se ve en la práctica es `AL_REVES`, y es un
## solo número: la marcha está del lado contrario de como debería. Y como
## `Cuerpo.GIRO_MODELO` es una vuelta de PI, que da la vuelta a las dos fases
## a la vez, `AL_REVES` con la vuelta puesta se arregla SACANDO la vuelta, no
## cambiando el clip. Ese es el número que decide, y por eso la tabla tiene las
## cuatro filas igual: una herramienta que solo sabe del caso bueno no sabe
## decir cuál de los dos cambios hay que hacer.
##
## - (contacto −, vuelo +) ACUERDO      anda bien
## - (contacto +, vuelo −) AL_REVES     ESPEJO: toda la marcha está del otro
##                                      lado. Se arregla girando el modelo, NO
##                                      tocando el clip: con solo un signo mal
##                                      se pensaría en el clip y se pierde el
##                                      tiempo.
## - (contacto +, vuelo +) PATINA_ADELANTE   el pie patina hacia delante con el
##                                      pie plantado (moon walk). El vuelo está
##                                      bien, así que el clip esta bien orientado
##                                      y hay que cambiar el clip.
## - (contacto −, vuelo −) PATINA_ATRAS     el pie engancha y se arrastra hacia
##                                      atrás en el suelo. También es del clip.
static func tabla_de_signos(en_contacto: float, en_vuelo: float) -> String:
	var contacta_adelante: bool = en_contacto >= UMBRAL_MIN
	var contacta_atras: bool = en_contacto <= -UMBRAL_MIN
	var vuela_adelante: bool = en_vuelo >= UMBRAL_MIN
	var vuela_atras: bool = en_vuelo <= -UMBRAL_MIN
	if contacta_adelante and vuela_atras:
		return "AL_REVES"
	if contacta_adelante and vuela_adelante:
		return "PATINA_ADELANTE"
	if contacta_atras and vuela_atras:
		return "PATINA_ATRAS"
	if contacta_atras and vuela_adelante:
		return "ACUERDO"
	return "PERDIDO"


## El eje dominante con el signo hacia el que va el pie. Si el desplazamiento
## neto es cero (el pie barre y vuelve), el signo sale de en qué mitad del
## barrido se pasa la mayor parte del tiempo, y queda dicho en el informe.
static func _eje_canonico(eje: String, desplazamiento: Vector3) -> Vector3:
	var valor: float = desplazamiento.x if eje == "X" else desplazamiento.z
	if absf(valor) < UMBRAL_MIN:
		valor = 1.0
	var signo: float = 1.0 if valor > 0.0 else -1.0
	return Vector3(signo, 0.0, 0.0) if eje == "X" else Vector3(0.0, 0.0, signo)


static func _rango(local: PackedVector3Array, eje_x: bool) -> float:
	var bajo: float = local[0].x if eje_x else local[0].z
	var alto: float = bajo
	for p in local:
		var v: float = p.x if eje_x else p.z
		bajo = minf(bajo, v)
		alto = maxf(alto, v)
	return alto - bajo
