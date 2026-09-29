extends RefCounted
## MedidorPatinazo — ¿el pie se arrastra por el suelo?
##
## RESPONSABILIDAD ÚNICA: el número de deslizamiento. La distancia que un pie
## recorre POR EL SUELO durante un ciclo, contra la distancia que el personaje
## recorre en ese tiempo, en centímetros y en porcentaje. Nada más.
##
## POR QUÉ ESTE NÚMERO ES EL QUE SÍ O SÍ DECIDE: el patinaje es la causa más
## común de "camina horrible" y es la ÚNICA de las tres que ningún ajuste de
## mezcla arregla. Si el pie patina 20 cm por ciclo hay que tocar `speed_scale`;
## si patina 0 cm y aun así se ve mal, el problema es de dirección, de rig o de
## mezcla, y seguir tocando `speed_scale` es perder el tiempo.
##
## DOS NÚMEROS, Y NO ES DUDOSIDAD ES DISIPAR UNA AMBIGÜEDAD:
## 1. `velocidad_natural_ciclo` — la larga zancada del clip partido por la
##    duración del ciclo. NO depende del umbral de contacto: es la zancada que
##    el pie barre y el tiempo que tarda en barrerla. Es el número de cabecera,
##    porque es el que no se mueve cuando cambia el criterio de pisada.
## 2. `velocidad_natural_ventana` — la misma relación pero medida solo durante
##    la pisada detectada (`Contacto`). Es más fiel si el clip planta bien el
##    pie, y es ruido si no lo planta, y por eso va con su `fraccion` al lado.
## Los dos se calculan y se imprimen. Si discrepan mucho, el clip es raro, y
## eso también es un hallazgo.
##
## LA ESPACIO, dicho otra vez porque es donde se cuelan las equivocaciones: las
## posiciones del `MuestraCiclo` vienen en el espacio del ESQUELETO, sin la
## vuelta ni la escala. Acá se les aplica la vuelta `Cuerpo.GIRO_MODELO` y la
## escala del modelo, y se les suma el avance del personaje. Con eso, el
## resultado está en el mundo de Godot y es el mismo número que vería el ojo.
##
## LO QUE NO SE PUEDE MEDIR, y se dice en vez de inventarlo:
## - Si el pie no se mueve en vertical, no hay contacto y el patinaje no
##   existe como número: se informa `CLAVADA`.
## - Si el juego va a velocidad 0, no hay desplazamiento contra el que comparar.
## - Si la pisada detectada es más corta que el 30% del ciclo, el número de
##   ventana va marcado `fiable: false` y el de ciclo es el que manda.

const CONTACTO: GDScript = preload("res://tools/anim_medida/contacto.gd")

## Por debajo de 2 cm por ciclo el pie no se nota arrastrándose. Entre 2 y 15
## se nota. Arriba de 15 el ojo lo ve aunque no se sepa explicar por qué.
const UMBRAL_BUENO_CM: float = 2.0
const UMBRAL_MALO_CM: float = 15.0

## El avance del juego: el -Z del cuerpo (`Movimiento.yaw_hacia`).
const AVANCE_JUEGO: Vector3 = Vector3(0.0, 0.0, -1.0)


## Patinaje de los dos pies del ciclo que se le pasó.
##
## `muestra` sale de `MuestraCiclo.muestrear`; `velocidad_juego` es la que
## escribe `player.gd` en `stats.vel_mov` (u/s), `giro` y `escala` son los que
## cuelga `Player.aplicar_modelo`. Devuelve el detalle por pie y los promedios.
static func medir(muestra: Dictionary, velocidad_juego: float, giro: float,
		escala: float, direccion: Vector3 = AVANCE_JUEGO,
		origen: Vector3 = Vector3.ZERO) -> Dictionary:
	var salida: Dictionary = {"ok": false, "motivo": "", "veredicto": "SIN_DATOS"}
	if not bool(muestra.get("ok", false)):
		salida["motivo"] = str(muestra.get("motivo", "no hay muestra"))
		return salida
	if is_zero_approx(velocidad_juego):
		salida["motivo"] = "el personaje va a velocidad 0: no hay deslizamiento que medir"
		return salida
	var pos: Dictionary = muestra.get("pos", {}) as Dictionary
	var paso: float = float(muestra.get("paso", 0.0))
	var duracion: float = float(muestra.get("duracion", 0.0))
	if pos.is_empty() or paso <= 0.0:
		salida["motivo"] = "la muestra no trae posiciones de hueso"
		return salida
	var pies: Dictionary = {}
	for clave in pos.keys():
		if not str(clave).ends_with(".pie"):
			continue
		pies[clave] = _pie(clave, pos[clave] as PackedVector3Array, altura_de(pos, clave),
				paso, duracion, velocidad_juego, giro, escala, direccion, origen)
	if pies.is_empty():
		salida["motivo"] = "ningun hueso de pie existe en este rig: " \
				+ "el patinaje no se puede medir"
		return salida
	var naturales: Array[float] = []
	var deslizamientos: Array[float] = []
	var porcentajes: Array[float] = []
	for clave in pies.keys():
		var detalle: Dictionary = pies[clave] as Dictionary
		if bool(detalle.get("ok", false)):
			naturales.append(float(detalle["velocidad_natural_ciclo"]))
			deslizamientos.append(float(detalle["deslizamiento_cm"]))
			porcentajes.append(float(detalle["deslizamiento_pct"]))
	if naturales.is_empty():
		var primero: Dictionary = pies[pies.keys()[0]] as Dictionary
		salida["motivo"] = str(primero.get("motivo", ""))
		salida["pies"] = pies
		return salida
	var natural: float = _promedio(naturales)
	var desliz: float = _promedio(deslizamientos)
	var pct: float = _promedio(porcentajes)
	salida["ok"] = true
	salida["pies"] = pies
	salida["velocidad_juego"] = velocidad_juego
	salida["giro"] = giro
	salida["escala"] = escala
	salida["direccion"] = direccion
	salida["velocidad_natural"] = natural
	salida["velocidad_natural_ventana"] = _promedio(_campo(pies,
			"velocidad_natural_ventana"))
	salida["patinaje_cm"] = desliz
	salida["patinaje_pct"] = pct
	salida["speed_scale_sugerido"] = velocidad_juego / maxf(natural, 0.0001)
	salida["veredicto"] = veredicto_de(desliz)
	return salida


## Veredicto en una palabra, con los umbrales escritos al lado. Los números
## que se puedan discutir (el límite de "mal") van en la constante, no en el
## texto del informe, para que se puedan cambiar sin tocar el informe.
static func veredicto_de(cm: float) -> String:
	if cm <= UMBRAL_BUENO_CM:
		return "BIEN"
	if cm <= UMBRAL_MALO_CM:
		return "TIRABLE"
	return "HORRIBLE"


## Un pie, de punta a punta.
static func _pie(clave: String, local: PackedVector3Array, alturas: PackedFloat32Array,
		paso: float, duracion: float, velocidad: float, giro: float, escala: float,
		direccion: Vector3, origen: Vector3) -> Dictionary:
	var salida: Dictionary = {"ok": false, "motivo": ""}
	if local.size() < 3:
		salida["motivo"] = "menos de 3 instantes no alcanzan para un ciclo"
		return salida
	# El mundo: la pose del esqueleto, con la vuelta y la escala del modelo, y
	# el personaje avanzando. `i` es el índice de la muestra.
	var mundo: PackedVector3Array = PackedVector3Array()
	var base: Basis = Basis(Vector3.UP, giro).scaled(Vector3.ONE * escala)
	for i in local.size():
		var t: float = paso * float(i)
		mundo.append(base * local[i] + origen + direccion * velocidad * t)
	# La pisada la decide `Contacto`, que es el mismo para los dos medidores.
	var pisada: Dictionary = CONTACTO.detectar(alturas, paso, duracion)
	salida["suelo"] = pisada.get("suelo", 0.0)
	salida["excursion"] = pisada.get("excursion", 0.0)
	salida["umbral"] = pisada.get("umbral", 0.0)
	salida["fraccion_de_ciclo"] = pisada.get("fraccion", 0.0)
	salida["fiable"] = bool(pisada.get("fiable", false))
	salida["ventanas"] = pisada.get("ventanas", [] as Array[Dictionary])
	if not bool(pisada.get("ok", false)):
		salida["motivo"] = str(pisada.get("motivo", ""))
		return salida
	# La ZANCADA: el rango de barrido del pie en el eje horizontal dominante.
	# No la ventana de contacto no la cambia. Es la larga que el pie recorre
	# entre su punto más atras y su punto más adelante en UN ciclo.
	var zancada: float = _rango_dominante(local)
	salida["zancada"] = zancada
	salida["eje_dominante"] = "X" if _rango_x(local) > _rango_z(local) else "Z"
	salida["velocidad_natural_ciclo"] = zancada / maxf(duracion, 0.0001)
	# La ventana: la pisada más larga, y lo que pasa en ella.
	var mejor: Dictionary = CONTACTO.mayor(
			pisada.get("ventanas", [] as Array[Dictionary]))
	var i0: int = int(mejor.get("i0", 0))
	var i1: int = int(mejor.get("i1", 0))
	var dt: float = float(mejor.get("dt", 0.0))
	var recorrido: float = 0.0
	for i in range(i0 + 1, i1 + 1):
		recorrido += Vector2(mundo[i].x - mundo[i - 1].x,
				mundo[i].z - mundo[i - 1].z).length()
	var avance: float = velocidad * dt
	var relativo: float = Vector2(local[i1].x - local[i0].x,
			local[i1].z - local[i0].z).length()
	salida["ok"] = true
	salida["i0"] = i0
	salida["i1"] = i1
	salida["dt"] = dt
	salida["contacto_total"] = float(pisada.get("contacto_total", 0.0))
	salida["desplazamiento_relativo"] = relativo
	salida["velocidad_natural_ventana"] = relativo / maxf(dt, 0.0001)
	salida["recorrido_pie"] = recorrido
	salida["avance_personaje"] = avance
	salida["deslizamiento"] = recorrido
	salida["deslizamiento_cm"] = recorrido * 100.0
	salida["deslizamiento_pct"] = recorrido / maxf(avance, 0.0001) * 100.0
	salida["motivo"] = str(pisada.get("motivo", ""))
	return salida


static func altura_de(pos: Dictionary, clave: String) -> PackedFloat32Array:
	var ys: PackedFloat32Array = PackedFloat32Array()
	var serie: PackedVector3Array = pos[clave] as PackedVector3Array
	for p in serie:
		ys.append(p.y)
	return ys


static func _rango_dominante(local: PackedVector3Array) -> float:
	return maxf(_rango_x(local), _rango_z(local))


static func _rango_x(local: PackedVector3Array) -> float:
	var bajo: float = local[0].x
	var alto: float = local[0].x
	for p in local:
		bajo = minf(bajo, p.x)
		alto = maxf(alto, p.x)
	return alto - bajo


static func _rango_z(local: PackedVector3Array) -> float:
	var bajo: float = local[0].z
	var alto: float = local[0].z
	for p in local:
		bajo = minf(bajo, p.z)
		alto = maxf(alto, p.z)
	return alto - bajo


static func _campo(pies: Dictionary, campo: String) -> Array[float]:
	var salida: Array[float] = []
	for clave in pies.keys():
		var detalle: Dictionary = pies[clave] as Dictionary
		if bool(detalle.get("ok", false)):
			salida.append(float(detalle.get(campo, 0.0)))
	return salida


static func _promedio(valores: Array[float]) -> float:
	if valores.is_empty():
		return 0.0
	var total: float = 0.0
	for v in valores:
		total += v
	return total / float(valores.size())
