extends RefCounted
## MedidorCiclo — ¿esto es un ciclo o una foto clavada?
##
## RESPONSABILIDAD ÚNICA: convertir la serie de giros de `MuestraCiclo` en un
## veredicto y en los grados por frame que lo sostienen. No mide deslizamiento
## ni dirección; son otros dos medidores, porque son tres preguntas que se
## pueden fallar por separado.
##
## POR QUÉ ESTE NÚMERO Y NO "SE VE RARO": la diferencia entre "camina horrible"
## y "no camina" es de un orden de magnitud. Un ciclo de marcha real gira el
## muslo 15-35 grados por ciclo; una pose clavada gira 0,0 grados y sigue
## teniendo el mismo aspecto en los 12 frames de la tira de PNGs. Con el
## número, esa diferencia se discute; con el ojo, se opina.
##
## UNIDAD, y esto importa para comparar dos corridas: se reporta GRADOS POR
## FRAME a 60 fps, no por segundo. El motor puede correr a 30 o a 144 fps y
## el ángulo entre dos instantes del mismo clip no cambia; los grados por
## segundo sí. Con `paso` de muestreo distinto los grados por frame salen
## distintos aunque la animación sea idéntica, y sin normalizar el informe de
## la tira de 12 frames no se podría comparar con el de 60 muestras.

## Umbral de "hay ciclo": la suma de giros de las tres piernas en un ciclo
## completo. Un humano da entre 90 y 250; uncycle de export de Meshy, 40-120.
const GRADOS_CICLO_MIN: float = 5.0
## Por debajo de esto la pose está clavada: el número no es "camina mal", es
## "no camina".
const GRADOS_CLAVADA_MAX: float = 1.0

## FPS de referencia para normalizar a "por frame".
const FPS_REFERENCIA: float = 60.0


## Dictamen del ciclo a partir de la salida de `MuestraCiclo.muestrear`.
##
## Devuelve `ok`, `motivo`, `veredicto` ("CICLO" | "CICLO_DEBIL" | "CLAVADA" |
## "SIN_DATOS"), `giro_por_frame` (grados/frame@60 por hueso), `giro_total`
## (grados acumulados en un ciclo), `giro_max`, `excursion` (recorrido vertical
## en u) y `instantes_movidos`.
static func medir(muestra: Dictionary) -> Dictionary:
	var salida: Dictionary = {"ok": false, "motivo": "", "veredicto": "SIN_DATOS"}
	if not bool(muestra.get("ok", false)):
		salida["motivo"] = str(muestra.get("motivo", "no hay muestra"))
		return salida
	var paso: float = float(muestra.get("paso", 0.0))
	if paso <= 0.0:
		salida["motivo"] = "el clip tiene duracion cero: no hay ciclo que medir"
		return salida
	# Grados por frame a 60 fps: el ángulo entre dos instantes del clip no
	# depende del fps real, pero sí del paso de muestreo. Se normaliza para
	# que dos informes con distinto número de muestras sean comparables.
	var factor: float = (1.0 / FPS_REFERENCIA) / paso
	var por_frame: Dictionary = {}
	var total: float = 0.0
	var maximo: float = 0.0
	var girando: int = 0
	var giros: Dictionary = muestra.get("giro", {}) as Dictionary
	for clave in giros.keys():
		var serie: PackedFloat32Array = giros[clave] as PackedFloat32Array
		var acumulado: float = 0.0
		var pico: float = 0.0
		for g in serie:
			acumulado += g
			pico = maxf(pico, g)
		var por_frame_valor: float = pico * factor
		por_frame[clave] = por_frame_valor
		maximo = maxf(maximo, por_frame_valor)
		if acumulado > GRADOS_CLAVADA_MAX:
			girando += 1
		# El total solo suma las DOS piernas: los otros huesos (caderas, brazos,
		# cabeza) no dicen si hay marcha y ensucian el número.
		if str(clave).ends_with(".pie") or str(clave).ends_with(".muslo") \
				or str(clave).ends_with(".espinilla"):
			total += acumulado
	var excursion: Dictionary = {}
	for clave in (muestra.get("excursion", {}) as Dictionary).keys():
		excursion[clave] = float((muestra.get("excursion", {}) as Dictionary)[clave])
	var veredicto: String = "CLAVADA"
	if girando == 0:
		veredicto = "CLAVADA"
	elif total >= GRADOS_CICLO_MIN:
		veredicto = "CICLO"
	else:
		veredicto = "CICLO_DEBIL"
	salida["ok"] = true
	salida["veredicto"] = veredicto
	salida["giro_por_frame"] = por_frame
	salida["giro_total"] = total
	salida["giro_max"] = maximo
	salida["excursion"] = excursion
	salida["instantes_movidos"] = int(muestra.get("posiciones_reales", 0))
	salida["muestras"] = int(muestra.get("muestras", 0))
	salida["motivo"] = "" if girando > 0 else \
			"ningun hueso cambio de pose en todo el ciclo: el clip no se esta reproducciendo"
	return salida


## Una línea por hueso con sus grados por frame. El orden es el del
## `muestra`, que es fijo, para que el `diff` de dos informes no ensucie.
static func lineas(diccionario: Dictionary) -> Array[String]:
	var salida: Array[String] = []
	var por_frame: Dictionary = diccionario.get("giro_por_frame", {}) as Dictionary
	for clave in por_frame.keys():
		salida.append("giro %-12s %7.2f grados/frame" % [clave,
				float(por_frame[clave])])
	return salida
