extends SceneTree
## BancadaAnimacion — la corrida que produce el informe.
##
## POR QUÉ EXISTE: la animación se "arregló" tres veces y en las tres se
## cambiaron líneas sin mirar un solo número. Esto arma el instrumento que
## faltaba: carga el modelo REAL, le pregunta al CÓDIGO REAL qué pone, y
## escribe un informe con números arriba que se puede diffear contra otra
## corrida. No arregla nada y no toca el juego: mide.
##
## Lo que hace, en orden:
## 1. Instancia el modelo de la clase (o el que se le pase) en una rama
##    LIMPIA, sin `AnimationTree`: ahí manda el `seek()` y se puede medir el
##    clip crudo sin que el árbol lo esté sobreescribiendo.
## 2. Inventaria los clips (`MedidorClips`).
## 3. Barre el ciclo del `walk` y saca grados por frame (`MedidorCiclo`).
## 4. Calcula el patinaje del pie (`MedidorPatinazo`) con la velocidad REAL
##    que escribe `stats.vel_mov`, no con una inventada.
## 5. Calcula el eje de la marcha en crudo y con la vuelta (`MedidorDireccion`).
## 6. Levanta un `Player` de verdad, lo hace "caminar" a tres ritmos con su
##    propio `_actualizar_animacion` y lee de vuelta el
##    `parameters/locomocion/blend_position` que queda publicado (`MedidorBlend`).
## 7. Escribe el informe y el JSON.
##
## USO
##   godot --headless --path . --script res://tools/anim_medida/bancada_animacion.gd
##   godot --headless --path . --script res://tools/anim_medida/bancada_animacion.gd -- \
##       --clase=guerrero --salida=build/informe_animacion --muestras=60 --linea-base
##
## Opciones
##   --clase=id        clase de data/clases.json (por defecto `guerrero`)
##   --modelo=ruta     un .glb suelto, gana sobre --clase
##   --escala=n        fuerza la escala del modelo
##   --salida=carpeta  dónde se escriben informe_animacion.md y .json
##   --muestras=n      instantes por ciclo del `walk` (mínimo 12, por defecto 60)
##   --tira=archivo    JSON de la tira de PNGs para pegarlo al informe
##   --linea-base      copia el .md a docs/INFORME_ANIMACION.md
##
## LIMITACIÓN DECLARADA: el exit code es SIEMPRE 0. Esto es un instrumento, no
## un test: que el patinaje sea de 500 cm es un hallazgo, no un fallo. El rojo
## es para cuando el instrumento no pudo medir, y eso sale impreso.

const LOCALIZADOR: GDScript = preload("res://tools/anim_medida/localizador.gd")
const MUESTRA: GDScript = preload("res://tools/anim_medida/muestra_ciclo.gd")
const MEDIDOR_CLIPS: GDScript = preload("res://tools/anim_medida/medidor_clips.gd")
const MEDIDOR_CICLO: GDScript = preload("res://tools/anim_medida/medidor_ciclo.gd")
const MEDIDOR_PATINAZO: GDScript = preload("res://tools/anim_medida/medidor_patinazo.gd")
const MEDIDOR_DIRECCION: GDScript = preload("res://tools/anim_medida/medidor_direccion.gd")
const MEDIDOR_BLEND: GDScript = preload("res://tools/anim_medida/medidor_blend.gd")
const INFORME: GDScript = preload("res://tools/anim_medida/informe_animacion.gd")
const CUERPO: GDScript = preload("res://scripts/core/cuerpo.gd")
const ARBOL: GDScript = preload("res://scripts/core/arbol_animacion.gd")
const PLAYER: GDScript = preload("res://scripts/player/player.gd")

const RUTA_CLASES: String = "res://data/clases.json"
const RUTA_MODELOS: String = "res://data/modelos.json"
const SALIDA_POR_DEFECTO: String = "build/informe_animacion"
const RUTA_TIRA_POR_DEFECTO: String = "build/tira_animacion/tira.json"
const RUTA_LINEA_BASE: String = "docs/INFORME_ANIMACION.md"
const CLIP_MEDIDO: String = "walk"
## El `UMBRAL_CAMINAR` del jugador (scripts/player/player.gd). Va aquí para
## poder cambiarlo sin romper, y el informe lo dice si no coincide.
const UMBRAL_CAMINAR_ESPERADO: float = 0.45

var _clase: String = "guerrero"
var _modelo: String = ""
var _escala: float = -1.0
var _salida: String = SALIDA_POR_DEFECTO
var _muestras: int = 60
var _tira: String = RUTA_TIRA_POR_DEFECTO
var _linea_base: bool = false
var _frame: int = 0
var _datos: Dictionary = {}
var _limpio: Node3D = null
var _fase: int = 0


func _initialize() -> void:
	_leer_argumentos()
	print("[BANCADA] modelo: %s  ·  muestras: %d  ·  salida: %s" % [
			_clase if _modelo == "" else _modelo, _muestras, _salida])


func _leer_argumentos() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clase="):
			_clase = a.get_slice("=", 1)
		elif a.begins_with("--modelo="):
			_modelo = a.get_slice("=", 1)
		elif a.begins_with("--escala="):
			_escala = float(a.get_slice("=", 1))
		elif a.begins_with("--salida="):
			_salida = a.get_slice("=", 1)
		elif a.begins_with("--muestras="):
			_muestras = maxi(int(a.get_slice("=", 1)), 12)
		elif a.begins_with("--tira="):
			_tira = a.get_slice("=", 1)
		elif a == "--linea-base":
			_linea_base = true


## El trabajo heavy va en `_process`, NO en `_initialize`: en `_initialize` el
## nodo raíz todavía no está "dentro del árbol" y `seek()`/`to_global()` tiran
## `Condition "!is_inside_tree()" is true`. Está pagado: ya se perdió una
## corrida entera por esto.
func _process(_delta: float) -> bool:
	_frame += 1
	match _fase:
		0:
			_preparar()
			_fase = 1
		1:
			_medir()
			_fase = 2
		2:
			_escribir()
			_fase = 3
		_:
			quit(0)
			return true
	return false


## Monta el modelo limpio (sin `AnimationTree`) y el `Player` real, y averigua
## de dónde salen el modelo y la escala.
func _preparar() -> void:
	var datos_clase: Dictionary = _datos_de_clase()
	if _modelo == "":
		_modelo = str(datos_clase.get("modelo", ""))
	if _escala < 0.0:
		_escala = float(datos_clase.get("modelo_escala", 1.0))
	if _modelo == "" or not ResourceLoader.exists(_modelo):
		_datos = {"meta": {"modelo": _modelo, "escala": _escala, "clase": _clase,
				"error": "el modelo no existe o no se pudo cargar"},
				"clips": {"ok": false, "motivo": "sin modelo no hay nada que medir"}}
		print("[BANCADA] el modelo '%s' no existe" % _modelo)
		return
	var ps: PackedScene = load(_modelo) as PackedScene
	_limpio = ps.instantiate() as Node3D
	if _limpio == null:
		_datos = {"meta": {"modelo": _modelo, "escala": _escala, "clase": _clase,
				"error": "el .glb no instancia a un Node3D"},
				"clips": {"ok": false, "motivo": "sin modelo no hay nada que medir"}}
		return
	_limpio.name = "ModeloLimpio"
	root.add_child(_limpio)


## Todas las mediciones. Se mide primero la rama limpia (donde el clip manda)
## y después el `Player` real (donde manda el árbol y donde se lee lo que el
## juego realmente publica).
func _medir() -> void:
	if _limpio == null:
		return
	var anim: AnimationPlayer = LOCALIZADOR.reproductor(_limpio)
	var skel: Skeleton3D = LOCALIZADOR.esqueleto(_limpio)
	var giro: float = float(CUERPO.GIRO_MODELO)
	# La pose del clip crudo, en el espacio del esqueleto. La vuelta y la
	# escala NO van aquí: las pone el que mide, en operaciones puras.
	var muestra: Dictionary = MUESTRA.muestrear(_limpio, anim, skel, CLIP_MEDIDO,
			_muestras)
	var velocidad: float = _velocidad_del_juego()
	var patinazo: Dictionary = MEDIDOR_PATINAZO.medir(muestra, velocidad, giro, _escala)
	var ciclo: Dictionary = MEDIDOR_CICLO.medir(muestra)
	var direccion: Dictionary = MEDIDOR_DIRECCION.medir(muestra, giro)
	var real: Dictionary = _con_jugador_real(velocidad)
	_datos = {
		"meta": _metadata(velocidad, giro),
		"clips": real.get("clips", {"ok": false,
				"motivo": "no se pudo levantar el jugador real"}),
		"ciclo": ciclo,
		"patinazo": patinazo,
		"direccion": direccion,
		"blend": real.get("blend", {"ok": false, "motivo": "sin jugador real"}),
		"tira": _leer_tira(),
	}


## La velocidad REAL del jugador, no una inventada. Se levanta un `Player`
## de verdad con la clase pedida y se lee su `stats.vel_mov`, que es lo
## mismo que escribe en `Player._consumir_intent`.
func _velocidad_del_juego() -> float:
	var p: Node = PLAYER.new()
	p.set("nombre", "H")
	p.call("fijar_identidad", "H", _clase)
	root.add_child(p)
	p.call("aplicar_clase", _clase)
	var stats: Object = p.get("stats") as Object
	var v: float = 0.0
	if stats != null:
		v = float(stats.get("vel_mov"))
	var modelo: Node3D = p.get_node_or_null("Modelo") as Node3D
	if modelo != null:
		# La escala del MODELO la pone el jugador; si la bandera la pasó por
		# arriba, manda la del jugador: lo que se mide es lo que se juega.
		# Se redondea a cuatro decimales porque el `float` de Godot no es
		# exacto y el informe iba a decir 0,89999997615814 en vez de 0,9.
		_escala = snappedf(modelo.scale.x, 0.0001)
	p.queue_free()
	return v


## El inventario de clips y el barrido de la mezcla salen de UN `Player` de
## verdad, y salen del mismo: el inventario dice qué está sonando en el juego
## de verdad (con su `AnimationTree` ya colgado), y el barrido pregunta a su
## propio `_actualizar_animacion`.
func _con_jugador_real(velocidad: float) -> Dictionary:
	var p: Node = PLAYER.new()
	p.set("nombre", "H")
	p.call("fijar_identidad", "H", _clase)
	root.add_child(p)
	p.call("aplicar_clase", _clase)
	var modelo: Node3D = p.get_node_or_null("Modelo") as Node3D
	if modelo == null:
		p.queue_free()
		return {"clips": {"ok": false, "motivo": "el jugador no colgó ningún modelo"},
				"blend": {"ok": false, "motivo": "sin modelo no hay AnimationTree"}}
	var anim: AnimationPlayer = LOCALIZADOR.reproductor(modelo)
	# El inventario, ANTES del barrido: el barrido deja el árbol mezclando y
	# el estado "qué clip suena" que interesa es el de arranque.
	var clips: Dictionary = MEDIDOR_CLIPS.medir(anim)
	clips["arbol_activo"] = MEDIDOR_CLIPS.hay_arbol_activo(anim)
	clips["escala_del_juego"] = modelo.scale.x
	clips["giro_del_juego"] = modelo.rotation.y
	# El lector: le poner la velocidad, pedirle al JUEGO que mezcle, y leer el
	# árbol. La mezcla va en el -Z porque es el forward del cuerpo.
	var lector: Callable = func(v: float) -> Dictionary:
		var sentido: Vector3 = Vector3(0.0, 0.0, -1.0)
		(p as CharacterBody3D).velocity = sentido * v
		p.call("_actualizar_animacion", 0.0)
		var arbol: AnimationTree = MEDIDOR_CLIPS.arbol(anim)
		return {
			"blend": MEDIDOR_CLIPS.parametro(arbol,
					"parameters/locomocion/blend_position"),
			"actual": str(anim.current_animation),
			"speed": anim.speed_scale,
			"arbol": arbol != null and arbol.active,
		}
	var base: float = maxf(velocidad, 0.01)
	var barrido: Dictionary = MEDIDOR_BLEND.barrer(lector,
			MEDIDOR_BLEND.barrido_completo(base))
	if bool(barrido.get("ok", false)):
		# Los tres ritmos del encargo van aparte, porque son los que se leen
		# en la tabla; el barrido completo queda de telón de fondo.
		var ritmos: Dictionary = MEDIDOR_BLEND.barrer(lector,
				MEDIDOR_BLEND.tres_ritmos(base))
		if bool(ritmos.get("ok", false)):
			barrido["tres_ritmos"] = ritmos["muestras"]
	p.queue_free()
	# `ARBOL.limpiar_cache()` ya NO EXISTE: el `static var _trees` que
	# justificaba se quitó de `ArbolAnimacion` porque era una FUGA (el pool de
	# enemigos liberaba los nodos y el diccionario se quedaba apuntándolos).
	# La llamada se quedó colgando, y `limpiar_cache` no existía: la excepción
	# se comía el `return` de abajo, así que la corrida terminaba sin
	# `clips`/`blend` y el informe salía con "no se pudo levantar el jugador
	# real" y los `blend_position` en blanco. MEDIDO: con la línea, los tres
	# `blend_position` salían "—"; sin ella, 0.189 / 0.568 / 1.000.
	return {"clips": clips, "blend": barrido}


func _leer_tira() -> Dictionary:
	if not FileAccess.file_exists(_tira):
		return {}
	var f: FileAccess = FileAccess.open(_tira, FileAccess.READ)
	if f == null:
		return {}
	var crudo: String = f.get_as_text()
	f.close()
	var datos: Variant = JSON.parse_string(crudo)
	return datos as Dictionary if datos is Dictionary else {}


func _escribir() -> void:
	if _datos.is_empty():
		_datos = {"meta": {"modelo": _modelo}, "clips": {"ok": false,
				"motivo": "la bancada no llegó a medir"}}
	var escrito: Dictionary = INFORME.guardar(_datos, _ruta_de_salida())
	if not bool(escrito.get("ok", false)):
		print("[BANCADA] %s" % str(escrito.get("motivo", "")))
	if _linea_base:
		_escribir_linea_base()
	print("")
	print(INFORME.texto(_datos))


## La línea base es el mismo informe, con los mismos números, escrito donde se
## lee sin abrir el juego. `res://` porque el proyecto se está corrriendo con
## `--path .` y así no depende del directorio de trabajo.
func _escribir_linea_base() -> void:
	var f: FileAccess = FileAccess.open("res://" + RUTA_LINEA_BASE, FileAccess.WRITE)
	if f == null:
		print("[BANCADA] no se pudo escribir la linea base %s" % RUTA_LINEA_BASE)
		return
	f.store_string(INFORME.texto(_datos))
	f.close()
	print("[BANCADA] linea base: res://%s" % RUTA_LINEA_BASE)


func _metadata(velocidad: float, giro: float) -> Dictionary:
	return {
		"modelo": _modelo,
		"clase": _clase,
		"escala": _escala,
		"giro_modelo_rad": giro,
		"velocidad_juego_u_s": velocidad,
		"umbral_caminar_en_juego": UMBRAL_CAMINAR_ESPERADO,
		"clip_medido": CLIP_MEDIDO,
		"muestras_por_ciclo": _muestras,
		"godot": "%d.%d.%d" % [
				Engine.get_version_info().get("major", 0),
				Engine.get_version_info().get("minor", 0),
				Engine.get_version_info().get("patch", 0)],
		"fecha": Time.get_datetime_string_from_system(false, true),
		"herramienta": "tools/anim_medida/bancada_animacion.gd",
	}


## Datos de la clase del `data/clases.json`: el modelo y su escala salen de
## ahí, igual que salen en `Player.aplicar_modelo`. Si la clase no existe se
## cae al primer `.glb` con `jugador:clase` en `data/modelos.json`, para que la
## herramienta no se quede muda con un id mal escrito.
func _datos_de_clase() -> Dictionary:
	var crudo: String = _leer_json(RUTA_CLASES)
	if not crudo.is_empty():
		var datos: Variant = JSON.parse_string(crudo)
		if datos is Dictionary:
			var clases: Dictionary = (datos as Dictionary).get("clases", {}) as Dictionary
			var entrada: Dictionary = clases.get(_clase, {}) as Dictionary
			if not entrada.is_empty():
				return {
					"modelo": str(entrada.get("modelo", "")),
					"modelo_escala": float(entrada.get("modelo_escala", 1.0)),
				}
	var manifiesto: String = _leer_json(RUTA_MODELOS)
	if not manifiesto.is_empty():
		var datos: Variant = JSON.parse_string(manifiesto)
		if datos is Dictionary:
			for m in (datos as Dictionary).get("modelos", []) as Array:
				var modelo: Dictionary = m as Dictionary
				var anclajes: Array = modelo.get("anclajes", []) as Array
				if anclajes.has("jugador:clase"):
					return {"modelo": "res://models/%s" % str(modelo.get("archivo", "")),
							"modelo_escala": 1.0}
	return {}


## La carpeta de salida tal y como la entiende el motor: `build/...` sale
## como `res://build/...`, para que funcione con el mismo `--path` que los
## tests y no dependa del directorio desde donde se invocó.
func _ruta_de_salida() -> String:
	if _salida.begins_with("res://") or _salida.begins_with("user://") \
			or _salida.begins_with("/"):
		return _salida
	return "res://" + _salida


func _leer_json(ruta: String) -> String:
	if not FileAccess.file_exists(ruta):
		return ""
	var f: FileAccess = FileAccess.open(ruta, FileAccess.READ)
	if f == null:
		return ""
	var texto: String = f.get_as_text()
	f.close()
	return texto
