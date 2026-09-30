class_name Opciones
extends RefCounted
## Bloque 65: ajustes del juego, persistidos en `user://opciones.json`.
##
## POR QUÉ EXISTE: hasta acá los ajustes eran `const` compilados. La
## sensibilidad de cámara (`camera_rig.gd`), la distancia máxima, el volumen y
## la calidad no se podían cambiar sin recompilar. Para un juego que se va a
## jugar en una pantalla de 2560×1440 con un monitor de 144 Hz y auriculares,
## eso no es un detalle: es no poder jugar como uno quiere.
##
## - PERSISTE en `user://`, no en el save: las opciones son de la MÁQUINA (la
##   resolución y el volumen no viajan con la partida). Un save copiado a otra
##   PC no debe arrastrar la resolución de la anterior.
## - Data-driven: cada ajuste declara su tipo, su default, su mínimo y su
##   máximo, y la UI se construye leyendo la lista. Añadir un ajuste es una
##   línea, no un widget a mano.
## - Aplicación inmediata: `aplicar()` se llama en cada cambio, así que
##   mover el deslizador de volumen se OYE mientras se mueve.

## Un ajuste. El tipo decide el widget que la UI le pone.
const TIPO_VOLUMEN: String = "volumen"
const TIPO_SLIDER: String = "slider"
const TIPO_BOOL: String = "bool"
const TIPO_ENUM: String = "enum"
const TIPO_ACCION: String = "accion"

## Volúmenes, en dB. -60 es casi silencio (es el piso de Godot, por debajo no
## hay señal). 0 es el máximo sin clipear.
const DB_MIN: float = -60.0
const DB_MAX: float = 0.0

## Factores de escala de la distancia de cámara, de más cerca a más lejos.
const ESCALA_CAMARA: Array[float] = [0.7, 0.85, 1.0, 1.25, 1.5]
## Niveles de calidad. El nombre es el que se ve en el panel; el valor va al
## renderer.
const CALIDAD_NOMBRES: Array[String] = ["Baja", "Media", "Alta", "Ultra"]
## Escalas de render. Menos de 1.0 = supersampling (más nitidez, más GPU).
const RENDER_ESCALAS: Array[float] = [0.66, 0.75, 0.85, 1.0]

const RUTA: String = "user://opciones.json"

## La lista de ajustes, cada uno como diccionario. ES LA ÚNICA FUENTE: la UI
## no tiene ni un nombre de ajuste hardcodeado.
static func catalogo() -> Array:
	return [
		# --- audio (bloque 66 los usa) ---
		{"id": "vol_master", "tipo": TIPO_VOLUMEN, "def": 0.0,
			"etq": "Volumen general", "grupo": "audio"},
		{"id": "vol_musica", "tipo": TIPO_VOLUMEN, "def": -6.0,
			"etq": "Música", "grupo": "audio"},
		{"id": "vol_sfx", "tipo": TIPO_VOLUMEN, "def": -3.0,
			"etq": "Efectos", "grupo": "audio"},
		{"id": "vol_ambiente", "tipo": TIPO_VOLUMEN, "def": -8.0,
			"etq": "Ambiente", "grupo": "audio"},
		{"id": "musica", "tipo": TIPO_BOOL, "def": true,
			"etq": "Música", "grupo": "audio"},
		{"id": "sfx", "tipo": TIPO_BOOL, "def": true,
			"etq": "Efectos de sonido", "grupo": "audio"},

		# --- vídeo ---
		{"id": "calidad", "tipo": TIPO_ENUM, "def": 2,
			"etq": "Calidad gráfica", "grupo": "video",
			"opciones": CALIDAD_NOMBRES},
		{"id": "escala_render", "tipo": TIPO_ENUM, "def": 3,
			"etq": "Resolución de render", "grupo": "video",
			"opciones": ["66 %", "75 %", "85 %", "100 %"]},
		# El interruptor que apaga la CAUSA del parpadeo al moverse (fase 152),
		# no un número: con la decoración apagada el anillo entero sale de la
		# imagen y el sistema deja de escribir en el búfer. Es lo que hace el
		# diagnóstico ("apagá una cosa a la vez") un ajuste del juego de verdad,
		# y la respuesta a "todo parpadea cuando me muevo" si el anillo es la
		# causa: se desactiva y el mundo se ve sin pasto.
		{"id": "vegetacion", "tipo": TIPO_BOOL, "def": true,
			"etq": "Vegetación (si parpadea, apagala)", "grupo": "video"},
		{"id": "vsync", "tipo": TIPO_BOOL, "def": true,
			"etq": "Sincronización vertical", "grupo": "video"},
		{"id": "fps_max", "tipo": TIPO_SLIDER, "def": 0.0, "min": 0.0, "max": 240.0,
			"paso": 30.0, "etq": "Tope de FPS (0 = sin tope)", "grupo": "video"},

		# --- cámara ---
		{"id": "sensibilidad", "tipo": TIPO_SLIDER, "def": 0.0042,
			"min": 0.0010, "max": 0.0150, "paso": 0.0002,
			"etq": "Sensibilidad del ratón", "grupo": "camara"},
		{"id": "invertir_y", "tipo": TIPO_BOOL, "def": false,
			"etq": "Invertir eje Y", "grupo": "camara"},
		{"id": "escala_camara", "tipo": TIPO_ENUM, "def": 2,
			"etq": "Distancia de cámara", "grupo": "camara",
			"opciones": ["Muy cerca", "Cerca", "Normal", "Lejos", "Muy lejos"]},
		{"id": "fov", "tipo": TIPO_SLIDER, "def": 65.0,
			"min": 50.0, "max": 95.0, "paso": 1.0,
			"etq": "Campo de visión", "grupo": "camara"},

		# --- interfaz y accesibilidad ---
		{"id": "escala_ui", "tipo": TIPO_SLIDER, "def": 1.0,
			"min": 0.75, "max": 1.5, "paso": 0.05,
			"etq": "Tamaño del texto", "grupo": "interfaz"},
		{"id": "alto_contraste", "tipo": TIPO_BOOL, "def": false,
			"etq": "Alto contraste", "grupo": "interfaz"},
		{"id": "mostrar_fps", "tipo": TIPO_BOOL, "def": false,
			"etq": "Mostrar FPS", "grupo": "interfaz"},
		{"id": "ayuda_contextual", "tipo": TIPO_BOOL, "def": true,
			"etq": "Ayuda de teclas en pantalla", "grupo": "interfaz"},
	]


static var _valores: Dictionary = {}
static var _cargado: bool = false


## Los valores actuales, con los defaults rellenados. Cacheado: se lee en cada
## input de cámara, no en cada frame.
static func valores() -> Dictionary:
	if not _cargado:
		cargar()
	return _valores


static func cargar() -> bool:
	_valores.clear()
	for a in catalogo():
		_valores[str(a["id"])] = a.get("def")
	_cargado = true
	if not FileAccess.file_exists(RUTA):
		return false
	var texto: String = FileAccess.get_file_as_string(RUTA)
	if texto == "":
		return false
	var d: Variant = JSON.parse_string(texto)
	if d is Dictionary:
		var dd: Dictionary = d
		var guardados: Dictionary = dd.get("opciones", {})
		for id in guardados.keys():
			# Un save viejo con un ajuste que ya no existe se IGNORA, no se
			# cuela: el catálogo manda.
			if _valores.has(id):
				_valores[id] = guardados[id]
	return true


static func guardar() -> bool:
	var f: FileAccess = FileAccess.open(RUTA, FileAccess.WRITE)
	if f == null:
		push_warning("[Opciones] no se pudo escribir " + RUTA)
		return false
	f.store_string(JSON.stringify({"version": 1, "opciones": _valores}, "  "))
	f.close()
	return true


static func obtener(id: String) -> Variant:
	return valores().get(id, null)


static func flotante(id: String, def: float = 0.0) -> float:
	var v: Variant = obtener(id)
	return float(v) if v != null else def


static func entero(id: String, def: int = 0) -> int:
	var v: Variant = obtener(id)
	return int(v) if v != null else def


static func booleano(id: String, def: bool = false) -> bool:
	var v: Variant = obtener(id)
	return bool(v) if v != null else def


## Pone un valor y lo guarda. No valida el rango: quien llama es la UI, que
## ya lo ha limitado con el widget.
static func poner(id: String, valor: Variant) -> void:
	if not valores().has(id):
		push_warning("[Opciones] ajuste desconocido: '%s'" % id)
		return
	_valores[id] = valor


## Los valores por defecto, para el botón "Restablecer".
static func restablecer() -> void:
	_valores.clear()
	for a in catalogo():
		_valores[str(a["id"])] = a.get("def")
	guardar()
	aplicar()


## Pasa un ajuste a los dB del bus de audio correspondiente. Silencioso si el
## bus no existe todavía (el audio se inicializa después que las opciones).
static func aplicar_volumenes() -> void:
	_aplicar_bus("Master", booleano("sfx", true) or booleano("musica", true),
		flotante("vol_master"))
	_aplicar_bus("Musica", booleano("musica", true), flotante("vol_musica"))
	_aplicar_bus("SFX", booleano("sfx", true), flotante("vol_sfx"))
	_aplicar_bus("Ambiente", true, flotante("vol_ambiente"))


static func _aplicar_bus(nombre: String, activo: bool, db: float) -> void:
	if db <= DB_MIN:
		db = DB_MIN
	# Un bus muteado se pone a -60, que es el silencio de Godot. No existe un
	# "muted" de verdad y fingirlo con dB sería una sorpresa para quien lo lea.
	for i in range(AudioServer.get_bus_count()):
		if AudioServer.get_bus_name(i) == nombre:
			AudioServer.set_bus_volume_db(i, db if activo else DB_MIN)
			return


static func aplicar_video() -> void:
	var q: int = entero("calidad", 2)
	# La escala de render es lo que más se nota: sube nitidez y baja FPS.
	var escalas: Array = RENDER_ESCALAS
	var esc: float = float(escalas[clampi(entero("escala_render", 3), 0, escalas.size() - 1)])
	var vp: Viewport = _raiz()
	if vp != null:
		vp.scaling_3d_scale = esc
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if booleano("vsync", true)
			else DisplayServer.VSYNC_DISABLED)
	var tope: float = flotante("fps_max", 0.0)
	Engine.max_fps = int(tope) if tope > 0.0 else 0
	if vp != null:
		vp.set_meta("calidad_grafica", q)
	# Y ACÁ ESTÁ LO QUE FALTABA (fase 152): el ajuste de calidad del panel se
	# guardaba y no le llegaba a nadie. El `meta` de arriba no lo lee ningún
	# sistema, así que mover el deslizador no apagaba ni el SSAO ni el glow ni
	# cambiaba una sola sombra: era un número decorativo. Ahora el ajuste se
	# propaga a los tres que dependen de él, y la calidad BAJA EL TRABAJO DE
	# VERDAD, que es lo que el encargo pide.
	aplicar_calidad_al_mundo(vp)


## Propaga el ajuste de calidad a lo que la lee. Son tres, y cada uno es
## opcional (un mundo sin Shader ni sin Vegetación no tiene por qué tenerlos):
## el post-proceso de cada `WorldEnvironment`, las sombras de cada sol
## direccional, y los sistemas registrados en `gg_system` que expongan
## `aplicar_calidad()`.
##
## POR QUÉ EL GRUPO Y NO UNA RUTA DE NODO: el proyecto tiene una escena de demo
## con una cadena de seis niveles de herencia y once rutas `$Player`/`$Terreno`
## hardcodeadas (§9.1). Un `find_child` más acá sería la séptima. El grupo
## `gg_system` es el índice que el spec ya definió para esto.
static func aplicar_calidad_al_mundo(vp: Viewport) -> void:
	if vp == null or vp.get_tree() == null:
		return
	var raiz: Node = vp.get_tree().root
	if raiz == null:
		return
	for n in raiz.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (n as WorldEnvironment).environment
		if env != null:
			PostProceso.reaplicar_calidad(env)
	PostProceso.reaplicar_calidad_a_luces(raiz)
	for s in vp.get_tree().get_nodes_in_group(Systems.GRUPO):
		if s.has_method("aplicar_calidad"):
			s.call("aplicar_calidad")


static func _raiz() -> Viewport:
	var arbol: SceneTree = Engine.get_main_loop() as SceneTree
	return arbol.root if arbol != null else null


## La calidad como NOMBRE, para el post-proceso. El mapeo vive en un solo
## sitio: cambiarlo acá lo cambia para todo el juego.
static func calidad_nombre() -> String:
	var n: Array = CALIDAD_NOMBRES
	return str(n[clampi(entero("calidad", 2), 0, n.size() - 1)])


static func calidad_alta() -> bool:
	return entero("calidad", 2) >= 3


## Todo de golpe, para cuando el panel de opciones se cierra.
static func aplicar() -> void:
	aplicar_volumenes()
	aplicar_video()


static func etiqueta_de(id: String) -> String:
	for a in catalogo():
		if str(a["id"]) == id:
			return str(a["etq"])
	return id


## Los ids de un grupo, en orden de catálogo (para agrupar la UI).
static func grupo(nombre: String) -> Array:
	var out: Array = []
	for a in catalogo():
		if str(a.get("grupo", "")) == nombre:
			out.append(str(a["id"]))
	return out


## El factor de escala de la cámara que eligió el jugador.
static func escala_camara() -> float:
	var e: Array = ESCALA_CAMARA
	return float(e[clampi(entero("escala_camara", 2), 0, e.size() - 1)])
