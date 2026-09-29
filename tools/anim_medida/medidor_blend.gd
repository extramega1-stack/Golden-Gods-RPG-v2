extends RefCounted
## MedidorBlend — qué valor REAL toma `parameters/locomocion/blend_position`
## mientras el jugador camina lento, trotando y corriendo.
##
## RESPONSABILIDAD ÚNICA: barrer velocidades, pedirle al JUEGO que actualice su
## animación a cada una, y leer de vuelta lo que quedó publicado. No sabe
## cómo se calcula la mezcla ni cuál es la fórmula: se la pide al código real
## con un `Callable` y lee el árbol real. Si el juego no publica el parámetro,
## lo dice; si el parámetro se queda clavado en 1.0 para cualquier velocidad,
## lo dice, y eso es un hallazgo.
##
## POR QUÉ BARRER Y NO MEDIR UN PUNTO: el bloque 67 se arregló porque
## `blend_amount` no existía en la API de 4.7 y el error salía cada frame. El
## síntoma de un barrido donde el valor se va pegado a un extremo es el mismo
## (la mezcla no pasa por donde debería) y solo se ve con la curva.
##
## EL `Callable` RECIBE UNA VELOCIDAD Y DEVUELVE UN DICTIONARY con:
##   `blend`     float  — el valor leído del parámetro (NAN si no existe)
##   `actual`    String — el `current_animation` del reproductor
##   `speed`     float  — el `speed_scale` con el que está sonando
##   `arbol`     bool   — si hay un AnimationTree activo detrás

## Debajo de esta diferencia el valor de la mezcla se considera "clavado":
## cualquier cambio menor es indistinguible del redondeo.
const DIFERENCIA_MIN: float = 0.005
## Lo que se considera "tope": el BlendSpace1D va de 0.0 a 1.0, y en 1.0 el
## cross-fade terminó.
const TOPE: float = 1.0
## Si la mezcla llega a 1.0 antes de este porcentaje del barrido, el resto del
## barrido es un solo valor: la mezcla está SATURADA y en el juego no se
## mezcla nada, se elige. Es el caso del `UMBRAL_CAMINAR` de 0,45 en un
## jugador que corre a 6: a los 0,9 u/s ya vale 1,0.
const FRACCION_SATURADA: float = 0.25


## Barre `velocidades` con el lector del juego y arma la curva.
##
## Devuelve `ok`, `motivo`, `arbol` (si había `AnimationTree`), `muestras`
## (una por velocidad, en el mismo orden), `saturado_desde` (la primera
## velocidad en la que la mezcla llega a 1.0, o NAN si nunca llega),
## `rango_util` (de qué porcentaje del barrido es el tramo en el que la mezcla
## se mueve de verdad) y `veredicto`.
static func barrer(lector: Callable, velocidades: PackedFloat32Array) -> Dictionary:
	var salida: Dictionary = {"ok": false, "motivo": "", "muestras": PackedFloat32Array()}
	if not lector.is_valid():
		salida["motivo"] = "no hay lector del juego: no se puede preguntar al código real"
		return salida
	if velocidades.is_empty():
		salida["motivo"] = "el barrido no tiene velocidades"
		return salida
	var muestras: Array[Dictionary] = []
	for v in velocidades:
		var estado: Dictionary = lector.call(v) as Dictionary
		muestras.append({
			"velocidad": v,
			"blend": float(estado.get("blend", NAN)),
			"actual": str(estado.get("actual", "")),
			"speed": float(estado.get("speed", NAN)),
			"arbol": bool(estado.get("arbol", false)),
		})
	var primer_blend: float = float(muestras[0]["blend"])
	if is_nan(primer_blend):
		salida["motivo"] = "el juego no publica parameters/locomocion/blend_position: " \
				+ "la mezcla no se puede medir (y por lo tanto no se puede ver)"
		salida["muestras"] = muestras
		return salida
	# ¿Cuánto del barrido mueve la mezcla de verdad? Se cuenta cuántas
	# muestras consecutivas cambian más que el mínimo, sobre el total.
	var cambios: int = 0
	for i in range(1, muestras.size()):
		if absf(float(muestras[i]["blend"]) - float(muestras[i - 1]["blend"])) \
				> DIFERENCIA_MIN:
			cambios += 1
	var saturado_desde: float = NAN
	for i in muestras.size():
		if float(muestras[i]["blend"]) >= TOPE - DIFERENCIA_MIN:
			saturado_desde = float(muestras[i]["velocidad"])
			break
	var rango_util: float = 0.0
	if cambios > 0:
		rango_util = float(cambios) / float(maxi(muestras.size() - 1, 1)) * 100.0
	var tope_barrido: float = float(velocidades[velocidades.size() - 1])
	var veredicto: String = "MEZCLA_VIVA"
	if cambios == 0:
		veredicto = "MEZCLA_CLAVADA"
	elif not is_nan(saturado_desde) and tope_barrido > 0.0 \
			and saturado_desde <= tope_barrido * FRACCION_SATURADA:
		veredicto = "MEZCLA_SATURADA"
	salida["ok"] = true
	salida["muestras"] = muestras
	salida["cambios"] = cambios
	salida["saturado_desde"] = saturado_desde
	salida["rango_util"] = rango_util
	salida["tope_barrido"] = tope_barrido
	_anotar_arbol(salida, muestras)
	salida["veredicto"] = veredicto
	return salida


## Si todas las muestras coinciden en si hay árbol, se anota. Un solo `true` es
## la señal de que el jugador SÍ está mezclando, y es lo que se lee primero.
static func _anotar_arbol(salida: Dictionary, muestras: Array[Dictionary]) -> void:
	var con_arbol: bool = false
	for m in muestras:
		if bool(m["arbol"]):
			con_arbol = true
			break
	salida["arbol"] = con_arbol


## Las tres velocidades que nombra el encargo, en función de la velocidad real
## del jugador. Son PORCENTAJES a propósito: el número que sale es "el 25% de
## lo que corre este jugador", y por eso vale para el goblin y para el mago.
## Sin esto, un 6,0 fijo solo mide una cosa.
const LENTO: float = 0.25
const TROTE: float = 0.60
const CARRERA: float = 1.30


## El nombre de cada una de las tres, en el orden en que se pide.
static func nombres_de_ritmo() -> Array[String]:
	return ["lento", "trote", "carrera"]


## Los tres ritmos en u/s, desde la velocidad real del jugador. El barrido
## completo es del 0 a 1,6 veces esa velocidad, que es donde se ve el tope.
static func barrido_completo(velocidad_juego: float) -> PackedFloat32Array:
	var salida: PackedFloat32Array = PackedFloat32Array()
	for i in 17:
		salida.append(velocidad_juego * 1.6 * float(i) / 16.0)
	return salida


## Los tres ritmos sueltos, que son los que se leen en la tabla del informe.
static func tres_ritmos(velocidad_juego: float) -> PackedFloat32Array:
	return PackedFloat32Array([
		velocidad_juego * LENTO,
		velocidad_juego * TROTE,
		velocidad_juego * CARRERA,
	])


## Una línea por velocidad del barrido: `v=1.50  blend=1.000  walk  1.00x`.
## Formato de ancho fijo para que dos informes se alineen en el `diff`.
static func lineas_barrido(resultado: Dictionary) -> Array[String]:
	var salida: Array[String] = []
	if not bool(resultado.get("ok", false)):
		return salida
	for m in (resultado.get("muestras", []) as Array[Dictionary]):
		var blend: float = float(m["blend"])
		salida.append("v=%5.2f u/s  blend=%5.3f  %-6s %sx" % [float(m["velocidad"]),
				blend, str(m["actual"]), str(m["speed"])])
	return salida
