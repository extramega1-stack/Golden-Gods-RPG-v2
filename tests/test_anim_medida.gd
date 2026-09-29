extends SceneTree
## Test de la BANDA DE MEDIR de la animación.
##
## POR QUÉ ESTE ARCHIVO Y NO SOLO LA HERRAMIENTA: una herramienta de medición
## que no se testea es una herramienta que un día imprime un número falso y
## nadie se entera. Lo que se prueba aquí, en orden de importancia:
##
## 1. QUE EL INSTRUMENTO ACIERTA. Se construye una marcha CORRECTA a mano,
##    con números conocidos, y se le pasa por los tres medidores. Si el
##    patinaje de una marcha correcta no da cero, o una marcha correcta no da
##    `ACUERDO`, el medidor está mal y sus salidas sobre los `.glb` no valen.
##    Es el test que separa "el modelo camina mal" de "el medidor mide mal".
## 2. QUE DICE "NO SE PUEDE MEDIR" CUANDO NO PUEDE. Sin AnimationPlayer, sin
##    esqueleto, clip inexistente, pie clavado: en todos esos casos tiene que
##    devolver `ok: false` CON MOTIVO, no un 0,0 que parece una medición.
## 3. QUE EL INFORME TIENE LOS NÚMEROS ARRIBA y una sección de huecos, porque
##    de eso depende el "antes y después" que va a hacer el otro worker.
## 4. QUE LA BANCADA CORRE DE PRINCIPIO A FINO sobre un `.glb` de verdad, que
##    es la prueba de que las piezas encajan (y la que se rompe el día que
##    alguien renombra un hueso).

const LOCALIZADOR: GDScript = preload("res://tools/anim_medida/localizador.gd")
const MUESTRA: GDScript = preload("res://tools/anim_medida/muestra_ciclo.gd")
const CONTACTO: GDScript = preload("res://tools/anim_medida/contacto.gd")
const MEDIDOR_CLIPS: GDScript = preload("res://tools/anim_medida/medidor_clips.gd")
const MEDIDOR_CICLO: GDScript = preload("res://tools/anim_medida/medidor_ciclo.gd")
const MEDIDOR_PATINAZO: GDScript = preload("res://tools/anim_medida/medidor_patinazo.gd")
const MEDIDOR_DIRECCION: GDScript = preload("res://tools/anim_medida/medidor_direccion.gd")
const MEDIDOR_BLEND: GDScript = preload("res://tools/anim_medida/medidor_blend.gd")
const INFORME: GDScript = preload("res://tools/anim_medida/informe_animacion.gd")

const MODELO: String = "res://models/clase_guerrero.glb"
const ZANCADA: float = 1.0
const DURACION: float = 1.0
const MUESTRAS: int = 60
## El personaje avanza en +Z del esqueleto y la vuelta del modelo es 0, para
## que la marcha sintética sea una marcha correcta y no haya que|Giirar nada.
const AVANCE: Vector3 = Vector3(0.0, 0.0, 1.0)

var _ok: int = 0
var _fallos: int = 0
var _n: int = 0
var _inst: Node3D = null
var _fase: int = 0


func _init() -> void:
	print("[TEST] instrumentación de animación — que mida bien y que avise cuando no puede")


func _process(_delta: float) -> bool:
	_n += 1
	match _fase:
		0:
			_ciclo_sintetico()
			_patinaje_de_marcha_correcta()
			_direccion_de_los_cuatro_casos()
			_huecos()
			_informe()
			_fase = 1
		1:
			_agregar_modelo()
			_fase = 2
		2:
			_sobre_un_modelo_real()
			_fase = 3
		_:
			_limpiar()
			print("[TEST] anim_medida: %d ok, %d fallos" % [_ok, _fallos])
			quit(_fallos)
			return true
	return false


# --- (1) LA MARCHA SINTÉTICA, que es la que valida al instrumento --------

## Una marcha construida a mano, con la zancada, la duración y el orden de las
## fases SABIDOS. El pie pasa medio ciclo plantado y medio ciclo en el aire, y
## la zancada es de 1 u en 1 s, así que la velocidad natural del ciclo es
## 1 u/s, que es el número que después hay que recuperar con el medidor.
##
## SOLO HAY DOS MODOS, y no es pereza: en un ciclo CERRADO la fase de apoyo y
## la de vuelo tienen que ir en sentidos OPUESTOS, porque si no el pie no
## vuelve al punto de donde salió y el clip no cicla. Los cuatro pares de
## signos se prueban aparte, en la tabla de `MedidorDireccion`, porque la tabla
## tiene que saber diagnosticar los cuatro igual.
##
## - `correcta`: apoyo yendo hacia ATRÁS, vuelo yendo hacia ADELANTE. Es como
##   camina la gente.
## - `espejo`: apoyo yendo hacia ADELANTE, vuelo yendo hacia ATRÁS. Toda la
##   marcha del otro lado, que es lo mismo que un modelo mirando al revés.
func _sintetica(modo: String) -> Dictionary:
	var espejo: bool = modo == "espejo"
	var pos: Array[Vector3] = []
	var mitad: float = DURACION * 0.5
	var medio: float = ZANCADA * 0.5
	for i in MUESTRAS:
		var t: float = DURACION * float(i) / float(MUESTRAS - 1)
		var z: float = 0.0
		var y: float = 0.0
		if t < mitad:
			# El apoyo: el pie esta en el suelo (Y = 0) y recorre la zancada
			# entera, de un extremo al otro.
			var avance: float = t / mitad
			z = lerpf(-medio, medio, avance) if espejo else lerpf(medio, -medio, avance)
			y = 0.0
		else:
			# El vuelo: el pie esta arriba del umbral de contacto y vuelve al
			# punto de donde salio el ciclo, para que el clip ciclee.
			var avance: float = (t - mitad) / mitad
			z = lerpf(medio, -medio, avance) if espejo else lerpf(-medio, medio, avance)
			y = 0.30
		pos.append(Vector3(0.0, y, z))
	return {
		"ok": true, "motivo": "", "clip": "sintetica", "duracion": DURACION,
		"muestras": MUESTRAS, "paso": DURACION / float(MUESTRAS - 1),
		"pos": {"izq.pie": PackedVector3Array(pos)},
		"posiciones_reales": MUESTRAS - 1,
		"huesos": {"izq.pie": {"indice": 0, "nombre": "Foot.L"}},
	}


## El ciclo: una serie clavada tiene que dar `CLAVADA`, no un número chico.
func _ciclo_sintetico() -> void:
	var clavada: Dictionary = {
		"ok": true, "duracion": DURACION, "muestras": MUESTRAS,
		"paso": DURACION / float(MUESTRAS - 1),
		"giro": {"izq.pie": PackedFloat32Array()},
		"excursion": {"izq.pie": 0.0},
		"posiciones_reales": 0,
	}
	var c: Dictionary = MEDIDOR_CICLO.medir(clavada)
	_chk(str(c.get("veredicto", "")) == "CLAVADA",
			"una pose clavada se reporta CLAVADA, no como un ciclo chico",
			str(c.get("veredicto", "")))
	_chk(str(c.get("motivo", "")) != "",
			"y además dice POR QUÉ (que ningún hueso se movió)", "")


## La prueba que importa: una marcha correcta por construcción tiene que dar
## CERO patinaje a su velocidad natural, y `speed_scale` 1 tiene que dar cero
## también si el juego corre a esa velocidad. Si esto falla, el medidor está
## mal y ninguna de sus salidas sobre los `.glb` sirve.
func _patinaje_de_marcha_correcta() -> void:
	var muestra: Dictionary = _sintetica("correcta")
	# Primera pasada: a velocidad de sobra (6 u/s), solo para leer la velocidad
	# natural que declara el propio medidor.
	var primera: Dictionary = MEDIDOR_PATINAZO.medir(muestra, 6.0, 0.0, 1.0, AVANCE)
	_chk(bool(primera.get("ok", false)), "marcha correcta: el patinaje se mide",
			str(primera.get("motivo", "")))
	var natural: float = float(primera.get("velocidad_natural", 0.0))
	_chk(absf(natural - ZANCADA / DURACION) < 0.02,
			"la velocidad natural del ciclo es la zancada partida por el ciclo",
			"%.3f u/s, esperado %.3f" % [natural, ZANCADA / DURACION])
	# Segunda pasada: a la velocidad natural, el patinaje tiene que ser cero.
	var pie: Dictionary = (primera.get("pies", {}) as Dictionary)["izq.pie"] as Dictionary
	var natural_ventana: float = float(pie.get("velocidad_natural_ventana", 0.0))
	_chk(natural_ventana > natural,
			"la velocidad natural de la pisada es MAYOR que la del ciclo "
			+ "(el pie sólo se apoya una parte del ciclo)", "%.3f vs %.3f" % [
			natural_ventana, natural])
	var en_su_velocidad: Dictionary = MEDIDOR_PATINAZO.medir(muestra,
			natural_ventana, 0.0, 1.0, AVANCE)
	var cm: float = float(en_su_velocidad.get("patinaje_cm", 999.0))
	_chk(cm < 1.0,
			"una marcha correcta que corre a su velocidad natural NO patina",
			"%.3f cm de patinaje" % cm)
	_chk(str(en_su_velocidad.get("veredicto", "")) == "BIEN",
			"y el veredicto es BIEN", str(en_su_velocidad.get("veredicto", "")))
	# Tercera pasada: si el juego corre 3 veces más rápido de lo que el clip
	# fue hecho, el pie tiene que patinar, y el numero tiene que crecer.
	var rapido: Dictionary = MEDIDOR_PATINAZO.medir(muestra, 6.0, 0.0, 1.0, AVANCE)
	var cm_rapido: float = float(rapido.get("patinaje_cm", 0.0))
	_chk(cm_rapido > 100.0,
			"y a 6 u/s (6 veces su velocidad) patina como un perro",
			"%.1f cm" % cm_rapido)
	_chk(str(rapido.get("veredicto", "")) == "HORRIBLE",
			"veredicto HORRIBLE a 6 u/s", str(rapido.get("veredicto", "")))
	var sugerido: float = float(rapido.get("speed_scale_sugerido", 0.0))
	_chk(absf(sugerido - 6.0 / natural) < 0.05,
			"el speed_scale sugerido es velocidad de juego sobre velocidad natural",
			"%.2f, esperado %.2f" % [sugerido, 6.0 / natural])


## Los dos casos que un ciclo cerrado puede dar de verdad, y los cuatro pares
## de signos de la tabla. Esta tabla es la que decide si se gira el modelo o se
## cambia el clip, así que se prueba entera.
func _direccion_de_los_cuatro_casos() -> void:
	var esperado: Dictionary = {
		"correcta": "ACUERDO",
		"espejo": "AL_REVES",
	}
	for modo in esperado.keys():
		var d: Dictionary = MEDIDOR_DIRECCION.medir(_sintetica(str(modo)), 0.0, AVANCE)
		var pie: Dictionary = (d.get("pies", {}) as Dictionary).get("izq.pie", {}) as Dictionary
		_chk(str(pie.get("veredicto", "")) == str(esperado[modo]),
				"direccion: la marcha '%s' da %s" % [str(modo), str(esperado[modo])],
				"dio %s (vuelo %+.3f, contacto %+.3f)" % [str(pie.get("veredicto", "")),
				float(pie.get("vuelo_hacia_adelante", 0.0)),
				float(pie.get("contacto_hacia_adelante", 0.0))])
	# La tabla de signos, directo, sin pasar por el resto: son cuatro números
	# y cuatro palabras, y es la parte que se relee cuando el modelo anda raro.
	_chk(MEDIDOR_DIRECCION.tabla_de_signos(-1.0, 1.0) == "ACUERDO",
			"tabla: (-) contacto y (+) vuelo = ACUERDO", "")
	_chk(MEDIDOR_DIRECCION.tabla_de_signos(1.0, -1.0) == "AL_REVES",
			"tabla: (+) contacto y (-) vuelo = AL_REVES (espejo)", "")
	_chk(MEDIDOR_DIRECCION.tabla_de_signos(1.0, 1.0) == "PATINA_ADELANTE",
			"tabla: los dos + = PATINA_ADELANTE (moon walk)", "")
	_chk(MEDIDOR_DIRECCION.tabla_de_signos(-1.0, -1.0) == "PATINA_ATRAS",
			"tabla: los dos - = PATINA_ATRAS", "")
	_chk(MEDIDOR_DIRECCION.tabla_de_signos(0.0, 0.0) == "PERDIDO",
			"tabla: sin movimiento = PERDIDO, no un veredicto inventado", "")


## La honestidad del instrumento: cuando no puede medir, TIENE que decirlo.
## Un 0,0 silencioso es peor que un hueco, porque el 0,0 se lee como "no
## patina" y eso es exactamente el error que hay que evitar.
func _huecos() -> void:
	# Sin AnimationPlayer.
	var sin_reproductor: Dictionary = MEDIDOR_CLIPS.medir(null)
	_chk(not bool(sin_reproductor.get("ok", true)),
			"sin AnimationPlayer no se dice que se midió", "")
	_chk(str(sin_reproductor.get("motivo", "")) != "",
			"sin AnimationPlayer hay motivo escrito", str(sin_reproductor.get("motivo", "")))
	# Muestra que no existe.
	var muestra: Dictionary = MUESTRA.muestrear(null, null, null, "walk", 12)
	_chk(str(muestra.get("motivo", "")) != "",
			"sin modelo hay motivo escrito (2)", "")
	_chk(not bool(muestra.get("ok", true)), "sin modelo la muestra no dice que se midió", "")
	_chk(str(muestra.get("motivo", "")) != "",
			"sin modelo hay motivo escrito", str(muestra.get("motivo", "")))
	# Patinaje a velocidad 0: no hay nada contra qué comparar.
	var quieto: Dictionary = MEDIDOR_PATINAZO.medir(_sintetica("correcta"), 0.0, 0.0, 1.0, AVANCE)
	_chk(not bool(quieto.get("ok", true)),
			"a velocidad 0 el patinaje no se mide", "")
	_chk(str(quieto.get("motivo", "")) != "", "y lo dice", str(quieto.get("motivo", "")))
	# Pie que no se levanta: no hay pisada, no hay patinaje.
	var clavada: Dictionary = {
		"ok": true, "motivo": "", "duracion": DURACION, "muestras": MUESTRAS,
		"paso": DURACION / float(MUESTRAS - 1),
		"pos": {"izq.pie": PackedVector3Array()},
	}
	var pie_plano: PackedVector3Array = PackedVector3Array()
	for i in MUESTRAS:
		pie_plano.append(Vector3(0.0, 0.5, 0.0))
	clavada["pos"] = {"izq.pie": pie_plano}
	var sin_pisada: Dictionary = MEDIDOR_PATINAZO.medir(clavada, 6.0, 0.0, 1.0, AVANCE)
	_chk(not bool(sin_pisada.get("ok", true)),
			"un pie que no se levanta no tiene patinaje que medir", "")
	_chk(str(sin_pisada.get("motivo", "")) != "",
			"y el motivo nombra la excusa (que no hay pisada)",
			str(sin_pisada.get("motivo", "")))
	# El mezclador sin árbol: el parámetro no existe y hay que decirlo.
	var sin_arbol: float = MEDIDOR_CLIPS.parametro(null,
			"parameters/locomocion/blend_position")
	_chk(is_nan(sin_arbol), "sin AnimationTree el parametro de mezcla es NaN", "")
	var barrido_vacio: Dictionary = MEDIDOR_BLEND.barrer(Callable(),
			PackedFloat32Array([1.0, 2.0]))
	_chk(not bool(barrido_vacio.get("ok", true)),
			"sin lector, el barrido de mezcla no dice que se midió", "")
	_chk(str(barrido_vacio.get("motivo", "")) != "",
			"y dice que no hay lector del juego", str(barrido_vacio.get("motivo", "")))


## El informe: los números arriba, los huecos con su sección y los veredictos
## de los medidores en las filas. Sin esto el "antes y después" no se puede
## hacer, que es para lo que existe todo esto.
func _informe() -> void:
	var datos: Dictionary = {
		"meta": {"modelo": "sintetico", "fecha": "2026-01-01T00:00:00"},
		"clips": {"ok": false, "motivo": "sin AnimationPlayer"},
		"patinazo": MEDIDOR_PATINAZO.medir(_sintetica("correcta"), 6.0, 0.0, 1.0, AVANCE),
		"direccion": MEDIDOR_DIRECCION.medir(_sintetica("correcta"), 0.0, AVANCE),
	}
	var texto: String = INFORME.texto(datos)
	_chk(texto.contains("## Números"), "el informe tiene el bloque de números", "")
	var pos_numeros: int = texto.find("## Números")
	var pos_huecos: int = texto.find("## No se pudo medir")
	_chk(pos_numeros >= 0 and pos_numeros < pos_huecos,
			"los números van ANTES que cualquier otra cosa",
			"números en %d, huecos en %d" % [pos_numeros, pos_huecos])
	_chk(texto.contains("clips: sin AnimationPlayer"),
			"el hueco de una sección sale en la sección de huecos", "")
	_chk(texto.contains("patinaje por ciclo (cm)"),
			"el patinaje por ciclo sale en la tabla de números", "")
	_chk(texto.contains("ACUERDO"),
			"el veredicto de dirección sale escrito", "")
	_chk(texto.contains("NaN") or texto.contains("nan"),
			"un número que no se pudo medir sale como NaN y no como 0", "")
	_chk(INFORME.json(datos).contains("velocidad_natural"),
			"el JSON trae los números crudos para comparar con diff", "")
	# Un informe entero, sin un solo hueco, tiene que decirlo.
	var limpio: Dictionary = {
		"meta": {"modelo": "x"},
		"patinazo": {"ok": true, "motivo": "", "patinaje_cm": 0.0, "pies": {}},
	}
	_chk(INFORME.texto(limpio).contains("- nada: se midió todo lo pedido"),
			"sin huecos, el informe lo dice", "")
	# Y dos corridas con los mismos números dan el MISMO texto arriba: de eso
	# depende el diff antes/después.
	var otra: Dictionary = datos.duplicate(true)
	_chk(INFORME.texto(datos) == INFORME.texto(otra),
			"el bloque de arriba es idéntico entre corridas con los mismos datos", "")


# --- (2) SOBRE UN `.glb` DE VERDAD -------------------------------------

func _agregar_modelo() -> void:
	_inst = (load(MODELO) as PackedScene).instantiate() as Node3D
	_inst.name = "ModeloDePrueba"
	root.add_child(_inst)


## La cadena entera, de punta a punta, sobre un modelo real. Es la prueba de
## que las piezas encajan: si alguien renombra `Thigh.L`, o cambia el nombre
## de un clip, o deja de venir el `Skeleton3D`, esto se pone rojo y dice por
## qué, en vez de que el informe salga con un hueco que nadie lee.
func _sobre_un_modelo_real() -> void:
	var anim: AnimationPlayer = LOCALIZADOR.reproductor(_inst)
	var skel: Skeleton3D = LOCALIZADOR.esqueleto(_inst)
	_chk(anim != null, "el modelo de prueba tiene AnimationPlayer", MODELO)
	_chk(skel != null, "el modelo de prueba tiene Skeleton3D", MODELO)
	if anim == null or skel == null:
		return
	var piernas: Dictionary = LOCALIZADOR.piernas(skel)
	_chk(int((piernas.get("izq", {}) as Dictionary).get("pie", -1)) >= 0,
			"y se le encuentra el hueso del pie izquierdo por nombre", "")
	_chk(int((piernas.get("der", {}) as Dictionary).get("pie", -1)) >= 0,
			"y el derecho", "")
	var clips: Dictionary = MEDIDOR_CLIPS.medir(anim)
	_chk(bool(clips.get("ok", false)), "el inventario de clips se mide",
			str(clips.get("motivo", "")))
	_chk(int((clips.get("faltan", []) as Array).size()) == 0,
			"el modelo trae los cuatro clips del juego",
			"faltan %s" % str(clips.get("faltan", [])))
	var detalle: Dictionary = clips.get("detalle", {}) as Dictionary
	_chk(int((detalle.get("walk", {}) as Dictionary).get("keys_pierna", 0)) > 0,
			"y el clip `walk` tiene keys sobre los huesos de las piernas", "")
	var muestra: Dictionary = MUESTRA.muestrear(_inst, anim, skel, "walk", MUESTRAS)
	_chk(bool(muestra.get("ok", false)), "el ciclo se muestrea",
			str(muestra.get("motivo", "")))
	_chk(int(muestra.get("posiciones_reales", 0)) >= MUESTRAS - 2,
			"y la pose REALMENTE se mueve en el ciclo (si no, el seek no manda)",
			"solo %d de %d instantes" % [int(muestra.get("posiciones_reales", 0)), MUESTRAS])
	var ciclo: Dictionary = MEDIDOR_CICLO.medir(muestra)
	_chk(bool(ciclo.get("ok", false)), "el ciclo se mide",
			str(ciclo.get("motivo", "")))
	_chk(float(ciclo.get("giro_total", 0.0)) > 0.0,
			"y los huesos giran algo en un ciclo de marcha", "%.2f grados" %
			float(ciclo.get("giro_total", 0.0)))
	var patinazo: Dictionary = MEDIDOR_PATINAZO.medir(muestra, 6.0, PI, 0.9)
	_chk(bool(patinazo.get("ok", false)), "el patinaje se mide",
			str(patinazo.get("motivo", "")))
	_chk(float(patinazo.get("velocidad_natural", 0.0)) > 0.0,
			"y la velocidad natural del clip es un número positivo", "%.3f u/s" %
			float(patinazo.get("velocidad_natural", 0.0)))
	var direccion: Dictionary = MEDIDOR_DIRECCION.medir(muestra, PI)
	_chk(bool(direccion.get("ok", false)) or
			str(direccion.get("veredicto", "")) != "SIN_DATOS",
			"la dirección se mide o se dice que no se puede",
			str(direccion.get("motivo", "")))
	# El informe entero, con datos de verdad, tiene que salir escrito sin romperse.
	var informe: Dictionary = {
		"meta": {"modelo": MODELO, "giro_modelo_rad": PI},
		"clips": clips, "ciclo": ciclo, "patinazo": patinazo,
		"direccion": direccion,
	}
	var texto: String = INFORME.texto(informe)
	_chk(texto.contains("## Números") and texto.contains("## Patinaje"),
			"el informe de un modelo real tiene todas sus secciones", "")
	_chk(JSON.parse_string(INFORME.json(informe)) != null,
			"y su JSON es parseable", "")


func _limpiar() -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst.queue_free()
		_inst = null


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)
