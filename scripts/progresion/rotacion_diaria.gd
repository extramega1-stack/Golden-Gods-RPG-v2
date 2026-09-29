class_name RotacionDiaria
extends RefCounted
## Contenido que se renueva solo: los encargos DIARIOS y SEMANALES.
##
## POR QUÉ ESTE ARCHIVO Y NO UN `if` EN EL QUESTLOG: el NG+ del bloque 68
## abría la espiral pero no había nada nuevo que hacer, y el asesino del
## tiempo largo es la falta de cosas nuevas que descubrir. Una misión escrita
## a mano se hace una vez y nunca más; estas se rehacen cada día. Y se ven
## en el MISMO sitio que las otras, sin una línea de UI nueva: el panel de
## misiones (J) y el diálogo de los NPCs.
##
## POR QUÉ LA SEMILLA ES EL DÍA Y NO UN RANDOM: es la trampa que el encargo
## señalaba. Si la rotación saliera de un `randi()` global, la lista cambiaría
## al guardar y al cargar, y el jugador perdería el progreso del día: una
## diaria a medio hacer desaparecería y volvería distinta. Aquí la semilla
## sale del DÍA (`dia_de`), de la semana (`semana_de`) y del ciclo/prestigio
## del NG+, que vive en el save y no en un reloj. Misma fecha → misma
## rotación, siempre.
##
## DATO PRIMERO (§9.4): los encargos son `data/diarias.json`. Este archivo
## solo decide CUÁLES salen hoy. Cambiar el pool o el ritmo es tocar ese
## JSON, no esto.
##
## Los ids de las misiones concretas llevan la FECHA (`dia_d000738_...`). Eso
## es lo que hace la rotación reproducible y lo que deja que las de ayer se
## apaguen solas: mañana sus ids siguen siendo conocidos pero ya vencieron, y
## el QuestLog deja de ofrecerlas. Una diaria vencida NO puede romper la
## carga de una partida, y menos puede soltar un `push_warning` que nadie
## sabría explicar.

const RUTA: String = "res://data/diarias.json"

## Prefijos de los ids concretos. Distinguen una diaria de una semanal, que
## es lo único que las diferencia: el resto del esquema es el MISMO de
## `data/quests.json`, y por eso se registran en `QuestDB` y las juega el
## `QuestLog` de siempre, sin código propio.
const PREFIJO_DIARIA: String = "dia_"
const PREFIJO_SEMANAL: String = "sem_"

## Segundos de un día. Constante y no un 86400 suelto: el módulo entero del
## calendario depende de ella.
const SEGUNDOS_DIA: int = 86400

## Días por semana. La semana usa el MISMO reloj que el día, no un "lunes".
const DIAS_SEMANA: int = 7

## Red de seguridad para un JSON roto o ausente. El JSON puede mandarlos.
const DIARIAS_POR_DIA_DEF: int = 3
const SEMANALES_POR_SEMANA_DEF: int = 1

## Plantillas (id -> datos) y su orden, cacheados como en `QuestDB`.
static var _plantillas: Dictionary = {}
static var _orden: Array[String] = []
## El diccionario JSON crudo, para leer los números de ritmo sin volver a
## parsear el archivo en cada llamada (`dias_por_dia` se consulta en cada
## rotación, y releer el archivo ahí sería una lectura de disco por frame
## potential: §9.5 no perdona).
static var _datos: Dictionary = {}
static var _cargado: bool = false


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	var texto: String = FileAccess.get_file_as_string(RUTA)
	if texto.is_empty():
		push_warning("[RotacionDiaria] no se pudo leer " + RUTA)
		return
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		push_warning("[RotacionDiaria] " + RUTA + " no es un diccionario JSON válido")
		return
	_datos = datos
	for entrada in (datos as Dictionary).get("plantillas", []):
		if not (entrada is Dictionary):
			continue
		var p: Dictionary = entrada
		var pid: String = str(p.get("id", ""))
		if pid == "":
			continue
		if _plantillas.has(pid):
			push_warning("[RotacionDiaria] plantilla duplicada: %s" % pid)
			continue
		_plantillas[pid] = p
		_orden.append(pid)


static func plantilla(id: String) -> Dictionary:
	cargar()
	return _plantillas.get(id, {})


## Las plantillas de DÍA. Las semanales no entran en la rotación diaria: son
## pools separados, y por eso la semilla de una no perturba la otra.
static func plantillas_diarias() -> Array[String]:
	cargar()
	var salida: Array[String] = []
	for id in _orden:
		if str(_plantillas[id].get("tipo", "diaria")) == "diaria":
			salida.append(id)
	return salida


## Las plantillas de la semana.
static func plantillas_semanales() -> Array[String]:
	cargar()
	var salida: Array[String] = []
	for id in _orden:
		if str(_plantillas[id].get("tipo", "")) == "semanal":
			salida.append(id)
	return salida


static func dias_por_dia() -> int:
	cargar()
	return maxi(0, int(_json_numero("diarias_por_dia", DIARIAS_POR_DIA_DEF)))


static func semanas_por_semana() -> int:
	cargar()
	return maxi(0, int(_json_numero("semanales_por_semana", SEMANALES_POR_SEMANA_DEF)))


static func _json_numero(clave: String, por_defecto: int) -> int:
	cargar()
	return int(_datos.get(clave, por_defecto))


## El número de día del calendario de una fecha. Es LA semilla del sistema y
## la función más importante del archivo: la misma fecha da el mismo día, y
## de ahí sale la misma rotación.
##
## `fecha` son SEGUNDOS DESDE LA ÉPOCA. El día es la división entera, así que
## no depende de la zona horaria ni de la hora: las 3 de la mañana y las 11
## de la noche del mismo día son el mismo día. Un día empieza cuando UTC dice
## que empieza, que es lo único que se puede saber sin un reloj de zona
## horaria del juego.
static func dia_de(fecha: int) -> int:
	return int(floor(float(fecha) / float(SEGUNDOS_DIA)))


## El número de semana. Cuenta semanas de 7 días desde la época con la MISMA
## división, para que el día y la semana no se contradigan nunca.
static func semana_de(fecha: int) -> int:
	return int(floor(float(dia_de(fecha)) / float(DIAS_SEMANA)))


## El día de HOY, leído del reloj del sistema. Envuelto aparte para que un
## test pueda pasar una fecha fija: un test de "hoy" que dependa de qué día
## sea cuando corre es un test que falla un día de cada siete.
static func dia_hoy() -> int:
	return dia_de(ahora())


static func semana_hoy() -> int:
	return semana_de(ahora())


static func ahora() -> int:
	return int(Time.get_unix_time_from_system())


## LAS PLANTILLAS DE LAS DIARIAS DE HOY, en orden. Determinista: mismo
## `dia` + mismo `ciclo` → misma lista, siempre.
##
## El `ciclo` entra en la semilla porque el NG+ tiene que cambiar los
## encargos (si no, el jugador hace las mismas tres diarias trescientas
## vueltas). También es reproducible: el ciclo vive en el save, no en un
## reloj, así que la rotación de la vuelta 3 es la misma cada vez que se
## llega a la vuelta 3.
static func plantillas_del_dia(dia: int, ciclo: int = 0) -> Array[String]:
	return _elegir(plantillas_diarias(), dia, ciclo, dias_por_dia())


## Las semanales de ESTA semana. Misma regla, con el número de semana.
static func plantillas_de_la_semana(semana: int, ciclo: int = 0) -> Array[String]:
	return _elegir(plantillas_semanales(), semana, ciclo, semanas_por_semana())


## Elige `cuantas` plantillas de `candidatas` con una semilla determinista.
##
## POR QUÉ UN BARAJADO Y NO UN "elige uno al azar": si fuera un "elige uno
## cada vez", dos llamadas del mismo día podrían devolver listas distintas y
## una plantilla podría salir dos veces. Barajar una COPIA con un LCG
## sembrado por el día garantiza que (a) dentro del día no se repite ninguna
## y (b) la misma semilla da la misma lista. El LCG va sembrado con
## `semilla` y se avanza en el propio bucle, así que el barajado no depende de
## cuántas veces se llame.
static func _elegir(candidatas: Array[String], dia: int, ciclo: int,
		cuantas: int) -> Array[String]:
	var salida: Array[String] = []
	var n: int = candidatas.size()
	if n == 0 or cuantas <= 0:
		return salida
	# La lista viene YA en el orden DECLARADO en el JSON (por eso
	# `plantillas_diarias()` / `plantillas_semanales()` devuelven en el orden
	# de `_orden` y no el de un Dictionary, que no está garantizado). Se baraja
	# una COPIA: `_orden` es la caché y no se toca.
	var barajado: Array[String] = candidatas.duplicate()
	_barajar(barajado, _semilla(dia, ciclo))
	var cuantos: int = mini(cuantas, barajado.size())
	for k in range(cuantos):
		salida.append(barajado[k])
	return salida


## Fisher-Yates con LCG propio (sembrado, `_siguiente` avanza el estado).
static func _barajar(lista: Array[String], semilla: int) -> void:
	var s: int = maxi(1, semilla)
	var i: int = lista.size() - 1
	while i > 0:
		s = _siguiente(s)
		var j: int = s % (i + 1)
		var tmp: String = lista[i]
		lista[i] = lista[j]
		lista[j] = tmp
		i -= 1


## Un LCG (congruencial lineal) de 31 bits. Determinista y sin `randi()`,
## que es global y cambiaría entre sesiones: justo lo que no se quiere. No es
## criptográfico ni pretende serlo: lo único que importa es que sea ESTABLE
## entre ejecuciones, y que dos días seguidos no den la misma lista.
static func _siguiente(estado: int) -> int:
	return (estado * 1103515245 + 12345) % 2147483648


## La semilla efectiva: mezcla el día con el ciclo y con una constante impar
## (un hash de bits, como el de una cadena) para que el día 1 y el día 2 no
## produzcan rotaciones solapadas. Se fuerza a no negativo porque un residuo
## negativo en GDScript conserva el signo del dividendo, y un `abs` al final
## del bucle no arregla un estado negativo.
static func _semilla(dia: int, ciclo: int) -> int:
	var crudo: int = maxi(0, dia) * 2654435761 + maxi(0, ciclo) * 40503
	return absi(crudo) % 2147483647


## Las misiones concretas de un día. Cada una lleva la fecha en el id, la
## marca `efimera` que le dice al QuestLog que se apaga sola, y
## `vence_dia`: el ÚLTIMO día (en días absolutos) en que se puede aceptar.
## Con un solo número y una sola comparación se decide si una rotación está
## vigente, sin mirar el tipo.
static func misiones_del_dia(dia: int, ciclo: int = 0) -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	for tid in plantillas_del_dia(dia, ciclo):
		var m: Dictionary = _construir(tid, dia, ciclo, false)
		if not m.is_empty():
			salida.append(m)
	return salida


## Las concretas de la semana. `vence_dia` es el último día de esa semana, no
## el día del número de semana: una semanal dura los siete días que le
## tocan, no uno.
static func misiones_de_la_semana(semana: int, ciclo: int = 0) -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	for tid in plantillas_de_la_semana(semana, ciclo):
		var m: Dictionary = _construir(tid, semana, ciclo, true)
		if not m.is_empty():
			salida.append(m)
	return salida


## Todas las misiones de la rotación vigente (diaria + semanal). Es lo que
## `QuestDB` registra en runtime.
static func misiones_vigentes(ciclo: int = 0, momento: int = -1) -> Array[Dictionary]:
	var t: int = ahora() if momento < 0 else momento
	var salida: Array[Dictionary] = misiones_del_dia(dia_de(t), ciclo)
	salida.append_array(misiones_de_la_semana(semana_de(t), ciclo))
	return salida


## La clave que identifica una rotación vigente. `QuestDB` la guarda y la
## compara en cada `sincronizar_rotacion()`: si el día (o el ciclo) cambia,
## hay que registrar las misiones nuevas. Un string corto, sin asignación
## más grande que el propio string.
static func clave_vigente(ciclo: int = 0, momento: int = -1) -> String:
	var t: int = ahora() if momento < 0 else momento
	return "%d|%d|%d" % [dia_de(t), semana_de(t), maxi(0, ciclo)]


## Pasa de PLANTILLA a MISIÓN CONCRETA. La fecha va DENTRO del id (y en un
## campo aparte, para que la UI pueda decir "la de hoy" sin parsear).
##
## El `ngplus_ciclo` de la plantilla se COPIA a la misión concreta: el gate
## del NG+ lee el campo de la MISIÓN, no el de la plantilla, así que una
## diaria que pide el ciclo 1 tampoco aparece en el ciclo 0.
static func _construir(tid: String, semilla_fecha: int, ciclo: int,
		semanal: bool) -> Dictionary:
	var datos: Dictionary = plantilla(tid)
	if datos.is_empty():
		return {}
	var etiqueta: String = _etiqueta_fecha(semilla_fecha, semanal)
	var ultimo_dia: int = (semilla_fecha * DIAS_SEMANA + (DIAS_SEMANA - 1)) \
			if semanal else semilla_fecha
	return {
		"id": (PREFIJO_SEMANAL if semanal else PREFIJO_DIARIA) + etiqueta + "_" + tid,
		"nombre": str(datos.get("nombre", tid)),
		"descripcion": str(datos.get("descripcion", "")),
		"lore": str(datos.get("lore", "")),
		"npc_origen": str(datos.get("npc_origen", "")),
		"objetivos": datos.get("objetivos", []).duplicate(true),
		"recompensas": _recompensas_de(datos, ciclo),
		"ngplus_ciclo": maxi(0, int(datos.get("ngplus_ciclo", 0))),
		# La marca que le dice al QuestLog y a la UI "esta no vuelve mañana".
		"efimera": true,
		"rotacion": "semanal" if semanal else "diaria",
		"fecha": etiqueta,
		"vence_dia": ultimo_dia,
		# El ciclo EXACTO para el que se generó. `ngplus_ciclo` es un mínimo
		# ("desde la vuelta 1 sale"), y este es el valor concreto
		# ("generada para la vuelta 3"). La diferencia importa: con el mínimo
		# solo, prestigiar a media sesión dejaba vivas las diarias de la
		# vuelta anterior Y las de la nueva, y el jugador veía el doble de
		# encargos de los que le tocan.
		"rotacion_ciclo": maxi(0, ciclo),
		"plantilla": tid,
	}


## Las recompensas de una plantilla, ajustadas al NG+. Oro y XP se multiplican
## por el multiplicador de prestigio, para que una diaria valga la pena en la
## vuelta 5 y no sea un regalo de la vuelta 1. La multiplicación es la del
## `NuevoJuegoPlus` que ya existía: mismo número, no uno nuevo.
static func _recompensas_de(datos: Dictionary, ciclo: int) -> Dictionary:
	var r: Dictionary = datos.get("recompensas", {})
	var mult: float = NuevoJuegoPlus.multiplicador_prestigio(ciclo)
	var items: Array = r.get("items", [])
	return {
		"oro": int(round(float(r.get("oro", 0)) * mult)),
		"xp": int(round(float(r.get("xp", 0)) * mult)),
		"items": items.duplicate(true),
	}


## La fecha como etiqueta dentro del id, con ceros a la izquierda para que
## el orden de los ids sea el orden del calendario. Días absolutos desde la
## época: dos días distintos nunca dan la misma etiqueta.
static func _etiqueta_fecha(semilla_fecha: int, semanal: bool) -> String:
	var n: int = maxi(0, semilla_fecha)
	return ("s%06d" % n) if semanal else ("d%06d" % n)
