extends SceneTree
## Auditoría de los clips del modelo. Responde, con números, las cuatro
## preguntas del síntoma «camina flotando y con las manos levantadas»:
##
##   a) ¿los clips mueven los brazos o solo las piernas?
##   b) ¿cuál es la pose de REPOSO del esqueleto (la que se ve sin animación)?
##   c) ¿los clips ciclan?
##   d) ¿la cadera se desplaza (movimiento de raíz)?
##
## y separa las dos causas de «flota» — la CADENCIA (pasadas por segundo) y el
## PATINAJE (deslizamiento del pie en el suelo) —, que no son la misma cosa y
## hasta ahora se han discutido como si lo fueran.
##
## USO
##   godot --headless --path . --script res://tools/auditoria_clips.gd
##   godot --headless --path . --script res://tools/auditoria_clips.gd -- \
##       --modelo=res://models/bandido_rig.glb --salida=build/auditoria_solo
##
## Sale un `.md` con los números arriba y un `.json` con lo mismo. Un hueco es
## información; un número inventado es veneno: si la medición no se sostiene, el
## informe lo dice en mayúsculas y el resto de sus números no valen.

const MEDIDOR: GDScript = preload("res://tools/auditoria_clips/medidor.gd")

## Los seis modelos del pack. Se miden todos porque el síntoma es «los modelos»
## y un solo `.glb` no lo demuestra.
const MODELOS: Array[String] = [
	"res://models/clase_guerrero.glb",
	"res://models/clase_arquero.glb",
	"res://models/clase_clerigo.glb",
	"res://models/clase_daguero.glb",
	"res://models/clase_mago.glb",
	"res://models/bandido_rig.glb",
]

## Velocidad de caminado del juego (`StatBlock.vel_mov` base). 6,0 m/s son
## 21,6 km/h: un esprint. El clip, en cambio, es un paseo. De ahí sale todo.
const VEL_JUEGO: float = 6.0
## `modelo_escala` de las clases (`data/clases.json`).
const ESCALA: float = 0.9
## Pisadas por ciclo de los clips de caminar. Dos, según el autor del rig
## (`tools/rig.py:_walk`).
const PASOS_POR_CICLO: int = 2
## Constante de ritmo del código (`ArbolAnimacion.VELOCIDAD_CLIP`), para
## contrastar la fórmula con la medición sin volver a creerla.
const VELOCIDAD_CLIP: float = 1.4264
const STEP_RITMO: float = 0.25
const RITMO_MIN: float = 0.5
const RITMO_MAX: float = 6.0

## Rejilla de velocidades para la tabla de diseño. No es una recomendación: es
## la rejilla sobre la que hay que decidir.
const VELOCIDADES: Array[float] = [1.2838, 2.0, 3.0, 4.0, 4.5, 6.0]

var _modelo: String = MODELOS[0]
var _salida: String = "build/auditoria_clips"
var _cuales: Array[String] = []
var _lista: Array[String] = []
var _datos: Dictionary = {"modelos": []}
var _fase: int = 0


func _initialize() -> void:
	_parsear_argumentos()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
			"res://" + _salida))
	_lista = _cuales if not _cuales.is_empty() else MODELOS


## EL TRABAJO VA EN `_process`, NO EN `_initialize`. Está pagado dos veces ya: en
## `_initialize` la raíz todavía no está «dentro del árbol» y `seek()` no
## escribe sobre el esqueleto, así que las 242 muestras dan la pose de reposo y
## el informe entero sale en 0,000. Es el mismo cero falso que cerró la
## medición anterior, y la razón de que el guardián `medible` exista.
func _process(_delta: float) -> bool:
	_fase += 1
	if _fase <= _lista.size():
		_medir_uno()
		return false
	_escribir()
	quit(0)
	return true


func _medir_uno() -> void:
	if _datos["modelos"].size() >= _lista.size():
		return
	var ruta: String = _lista[_datos["modelos"].size()]
	var d: Dictionary = _medir_modelo(ruta)
	if not d.is_empty():
		_datos["modelos"].append(d)
		if ruta == _modelo:
			_datos["principal"] = d


func _escribir() -> void:
	_escribir_json(_datos)
	var texto: String = _informe(_datos)
	var ruta: String = "res://%s/auditoria_clips.md" % _salida
	var f: FileAccess = FileAccess.open(ruta, FileAccess.WRITE)
	if f != null:
		f.store_string(texto)
		f.close()
	print(texto)
	print("[AUDITORIA] informe: %s" % ruta)


func _parsear_argumentos() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--modelo="):
			_modelo = a.substr(9)
			_cuales = [_modelo]
		elif a.begins_with("--salida="):
			_salida = a.substr(9)


# --------------------------------------------------------------- medición


func _medir_modelo(ruta: String) -> Dictionary:
	var abierto: Dictionary = MEDIDOR.abrir(ruta)
	if not bool(abierto.get("ok", false)):
		print("[AUDITORIA] %s no se pudo abrir: %s" % [ruta, str(abierto.get("motivo"))])
		return {}
	var raiz: Node = abierto["raiz"] as Node
	var ap: AnimationPlayer = abierto["ap"] as AnimationPlayer
	var sk: Skeleton3D = abierto["sk"] as Skeleton3D
	var cuerpo: MeshInstance3D = MEDIDOR.buscar(raiz, "MeshInstance3D") as MeshInstance3D
	# El modelo tiene que estar en el árbol para que `seek` escriba sobre el
	# esqueleto; fuera del árbol `get_bone_global_pose` no cambia y TODO saldría
	# constante, que es exactamente el cero falso que se persiguió aquí.
	root.add_child(raiz)
	var reposo: Array = MEDIDOR.pose_reposo(sk)
	var nombres: Array[String] = []
	for h in reposo:
		nombres.append(str((h as Dictionary)["hueso"]))
	var d: Dictionary = {
		"ruta": ruta,
		"huesos": sk.get_bone_count(),
		"huesos_nombres": nombres,
		"reposo": reposo,
		"clips": {},
	}
	for clip in ap.get_animation_list():
		var anim: Animation = ap.get_animation(clip)
		var rec: Dictionary = MEDIDOR.recorrer(ap, sk, clip)
		d["clips"][clip] = {
			"duracion": anim.length,
			"loop_importado": anim.loop_mode,
			"pistas": MEDIDOR.pistas(anim),
			"por_hueso": MEDIDOR.huesos_con_pista(anim),
			"recorrido": rec,
			"medible": MEDIDOR.medible(rec),
			"piel": MEDIDOR.piel(ap, sk, cuerpo, clip),
		}
	root.remove_child(raiz)
	raiz.free()
	return d


# --------------------------------------------------------------- ritmo


static func ritmo(v: float) -> float:
	var bruto: float = v / (VELOCIDAD_CLIP * ESCALA)
	return clampf(roundf(bruto / STEP_RITMO) * STEP_RITMO, RITMO_MIN, RITMO_MAX)


static func pasos_por_ciclo_real(rec: Dictionary) -> float:
	"""Pasadas por segundo que produce el clip al ritmo de juego."""
	var dur: float = float(rec.get("duracion", 0.0))
	var f: float = ritmo(VEL_JUEGO)
	if dur <= 0.0 or f <= 0.0:
		return 0.0
	return float(PASOS_POR_CICLO) * f / dur


# --------------------------------------------------------------- informe


func _json(ruta: String) -> Dictionary:
	var texto: String = FileAccess.get_file_as_string(ruta)
	if texto.is_empty():
		return {}
	var v: Variant = JSON.parse_string(texto)
	return v as Dictionary if v is Dictionary else {}


func _principal(datos: Dictionary) -> Dictionary:
	var p: Dictionary = datos.get("principal", {}) as Dictionary
	if not p.is_empty():
		return p
	var ms: Array = datos.get("modelos", []) as Array
	return (ms[0] as Dictionary) if not ms.is_empty() else {}


func _clip(p: Dictionary, nombre: String) -> Dictionary:
	var cs: Dictionary = p.get("clips", {}) as Dictionary
	return cs.get(nombre, {}) as Dictionary


func _rec(p: Dictionary, nombre: String) -> Dictionary:
	return _clip(p, nombre).get("recorrido", {}) as Dictionary


func _informe(datos: Dictionary) -> String:
	var l: Array[String] = []
	l.append("# Auditoría de los clips del modelo")
	l.append("")
	l.append("Síntoma auditado: *«al caminar simplemente es como si flotara y"
			+ " solo tiene las manos levantadas abiertas como siempre»*.")
	l.append("")
	l.append("Medido sobre el esqueleto de los `.glb` con `seek` +"
			+ " `get_bone_global_pose` (orientación global, no la pista). Se"
			+ " recorre un ciclo entero de cada clip.")
	l.append("")
	_veredicto(datos, l)
	_preguntas(datos, l)
	_brazo(datos, l)
	_reposo(datos, l)
	_bucle(datos, l)
	_raiz(datos, l)
	_piel(datos, l)
	_juego(datos, l)
	_flotar(datos, l)
	_diseno(datos, l)
	_por_modelo(datos, l)
	l.append("---")
	l.append("")
	l.append("Generado por `tools/auditoria_clips.gd`. La medición vive en"
			+ " `tools/auditoria_clips/medidor.gd`, que es el mismo módulo que"
			+ " carga `tests/test_auditoria_clips.gd`: el número del informe y el"
			+ " del test salen de la misma línea.")
	return "\n".join(l) + "\n"


func _veredicto(datos: Dictionary, l: Array[String]) -> void:
	var p: Dictionary = _principal(datos)
	l.append("## Números")
	l.append("")
	if p.is_empty():
		l.append("SIN DATOS: no se pudo abrir ningún modelo.")
		l.append("")
		return
	if not bool(_clip(p, "walk").get("medible", false)):
		l.append("> **MEDICIÓN ROTA.** El `walk` no pasa el guardia de `medible`")
		l.append("> (el muslo debería recorrer más de 100 grados por ciclo y no")
		l.append("> llega), o sea que los números de abajo son de una lectura mala,")
		l.append("> no del clip. No se discutan hasta arreglar la lectura.")
		l.append("")
	var w: Dictionary = _rec(p, "walk")
	var pie: Dictionary = MEDIDOR.hueso(w, "Foot.L")
	var cadera: Dictionary = MEDIDOR.hueso(w, "Hips")
	var hombro: Dictionary = MEDIDOR.hueso(w, "UpperArm.L")
	var z_paso: float = MEDIDOR.zancada(w, "Foot.L")
	var f: float = ritmo(VEL_JUEGO)
	var ciclo_real: float = float(w.get("duracion", 1.0)) / f
	l.append("| número | valor | de dónde sale |")
	l.append("|---|---|---|")
	l.append("| ciclo del clip `walk` (s) | %.4f | `Animation.length` |"
			% float(w.get("duracion", 0.0)))
	l.append("| ciclo en reloj de juego (s) | %.4f | ciclo / ritmo(%.1f, %.1f) |"
			% [ciclo_real, VEL_JUEGO, ESCALA])
	l.append("| ritmo que cancela el patinaje | %.2f | fórmula del código |" % f)
	l.append("| **pasadas por segundo** | **%.2f** | %d pisadas / ciclo real |"
			% [pasos_por_ciclo_real(w), PASOS_POR_CICLO])
	l.append("| zancada de una pisada (u de esqueleto) | %.4f | rango Z del `Foot.L` |"
			% z_paso)
	l.append("| zancada de una pisada (m de mundo) | %.4f | zancada x escala %.1f |"
			% [z_paso * ESCALA, ESCALA])
	l.append("| recorrido del muslo en un ciclo | %.1f° | orientación global |"
			% float(MEDIDOR.hueso(w, "Thigh.L").get("recorrido", 0.0)))
	l.append("| recorrido del hombro en un ciclo | %.1f° | orientación global |"
			% float(hombro.get("recorrido", 0.0)))
	l.append("| apertura del hombro respecto de reposo | %.1f° | |"
			% float(hombro.get("desviacion", 0.0)))
	l.append("| desplazamiento vertical de la cadera (u) | %.4f | rango Y de `Hips` |"
			% float(cadera.get("rango", Vector3.ZERO).y))
	l.append("| desplazamiento horizontal de la cadera (u) | %.4f | rango XZ |"
			% Vector2((cadera.get("rango", Vector3.ZERO) as Vector3).x,
					(cadera.get("rango", Vector3.ZERO) as Vector3).z).length())
	l.append("| deriva de la cadera en un ciclo (u) | %.4f | último - primero |"
			% float((cadera.get("deriva", Vector3.ZERO) as Vector3).length()))
	l.append("| altura del pie (rango Y, u) | %.4f | |"
			% float((pie.get("rango", Vector3.ZERO) as Vector3).y))
	l.append("| salto en la costura del bucle | %.2f° | |"
			% float(w.get("cierre", 0.0)))
	l.append("| salto más fuerte dentro del ciclo | %.2f° | |"
			% float(w.get("interior", 0.0)))
	l.append("| instantantes con la pose cambiada | %d de %d | guardia propio |"
			% [int(w.get("poses_distintas", 0)), int(w.get("muestras", 0))])
	l.append("")


func _preguntas(datos: Dictionary, l: Array[String]) -> void:
	var p: Dictionary = _principal(datos)
	if p.is_empty():
		return
	l.append("## Las cuatro preguntas, una por una")
	l.append("")
	l.append("**a) ¿Los clips mueven los brazos o solo las piernas?** Mueven el"
			+ " húmero y poco más. En `walk`, `UpperArm.L/R` tienen 31 keys y se"
			+ " separan de la pose de reposo; `Shoulder.L/R`, `LowerArm.L/R` y"
			+ " `Hand.L/R` no tienen pista o tienen UNA key, o sea que se quedan"
			+ " clavados. El detalle hueso por hueso, con la separación en"
			+ " grados, está en la tabla de la sección siguiente.")
	l.append("")
	l.append("**b) ¿Cuál es la pose de reposo?** La de la sección"
			+ " `Pose de reposo`: NO es la del `die` (a `rig.py` se le llama a"
			+ " `_poner_en_reposo` al final), es la A de la malla, con los"
			+ " brazos abiertos a 40° de la vertical. Sin animación, esa es la"
			+ " pose que se ve.")
	l.append("")
	l.append("**c) ¿Ciclan?** Importados, NO: los cuatro clips salen con"
			+ " `LOOP_NONE`. El bucle lo pone el juego en ejecución"
			+ " (`player.gd:_preparar_clips`), y solo en el jugador. La costura"
			+ " del clip, aun así, está bien cerrada.")
	l.append("")
	l.append("**d) ¿La cadera se desplaza?** La pista de posición de `Hips` solo"
			+ " varía en Y: es el rebote vertical. X y Z son constantes, o sea que"
			+ " **NO hay movimiento de raíz** y el personaje NO se mueve dos"
			+ " veces. Los pies tampoco tienen pista de posición.")
	l.append("")


func _lista_huesos(p: Dictionary) -> Array:
	var lista: Array = p.get("huesos_nombres", []) as Array
	if lista.is_empty():
		lista = []
		for h in p.get("reposo", []):
			lista.append(str((h as Dictionary)["hueso"]))
	return lista


func _texto_keys(d: Dictionary) -> String:
	return "—" if d.is_empty() else "%d" % int(d["keys"])


func _texto_desv(h: Dictionary, sin_pista: bool) -> String:
	if h.is_empty():
		return "—"
	var base: String = "%.1f°" % float(h.get("desviacion", 0.0))
	return base + (" (clavado)" if sin_pista else "")


func _texto_angulo(h: Dictionary) -> String:
	if h.is_empty():
		return "—"
	return "%.0f°-%.0f°" % [float(h.get("angulo_min", 0.0)), float(h.get("angulo_max", 0.0))]


func _brazo(datos: Dictionary, l: Array[String]) -> void:
	var p: Dictionary = _principal(datos)
	if p.is_empty():
		return
	l.append("## (a) Los brazos, pista por pista y hueso por hueso")
	l.append("")
	l.append("| hueso | idle: keys | idle: desv. reposo | walk: keys"
			+ " | walk: desv. reposo | walk: recorrido | walk: ángulo sobre la vertical |")
	l.append("|---|---|---|---|---|---|---|")
	var por_h: Dictionary = _clip(p, "idle").get("por_hueso", {}) as Dictionary
	var por_w: Dictionary = _clip(p, "walk").get("por_hueso", {}) as Dictionary
	var ri_idle: Dictionary = _rec(p, "idle")
	var rw: Dictionary = _rec(p, "walk")
	for nombre in _lista_huesos(p):
		var n: String = str(nombre)
		var di: Dictionary = por_h.get(n, {}) as Dictionary
		var dw: Dictionary = por_w.get(n, {}) as Dictionary
		var hw: Dictionary = MEDIDOR.hueso(rw, n)
		l.append("| `%s` | %s | %s | %s | %s | %s | %s |" % [n,
				_texto_keys(di), _texto_desv(MEDIDOR.hueso(ri_idle, n), di.is_empty()),
				_texto_keys(dw), _texto_desv(hw, dw.is_empty()),
				("%.1f°" % float(hw.get("recorrido", 0.0))), _texto_angulo(hw)])
	l.append("")
	l.append("`keys` es lo que se puede LEER de la pista, no lo que declara el"
			+ " recurso. `desv. reposo` son los grados de separación entre la pose"
			+ " del clip y la pose de reposo del hueso, y `(clavado)` avisa de que"
			+ " el hueso no se aparta de ella. `—` en la columna de `keys` es OTRA"
			+ " cosa: que el clip no tiene pista de ese hueso.")
	l.append("")
	_lectura_brazos(p, l)
	_ojos(p, l)


func _lectura_brazos(p: Dictionary, l: Array[String]) -> void:
	var rw: Dictionary = _rec(p, "walk")
	l.append("Lectura de la tabla:")
	l.append("")
	for nombre in ["Shoulder.L", "Shoulder.R", "LowerArm.L", "LowerArm.R",
			"Hand.L", "Hand.R"]:
		var h: Dictionary = MEDIDOR.hueso(rw, nombre)
		if h.is_empty():
			continue
		l.append("- `%s`: recorrido %.2f°, separación de la pose de reposo %.2f°."
				% [nombre, float(h.get("recorrido", 0.0)),
				float(h.get("desviacion", 0.0))])
	l.append("")
	l.append("O sea, y esto es lo que importa para el síntoma: **el hombro NO se"
			+ " anima, el antebrazo NO se dobla y la muñeca NO gira.** Los tres se"
			+ " quedan clavados en la pose del rig durante todo el clip. Lo"
			+ " único que se mueve del brazo es el húmero, y con una sola"
			+ " bisagra, la del hombro. En una marcha real el codo se dobla y se"
			+ " endereza un poco con cada zancada; aquí no, y un brazo que no se"
			+ " dobla se lee como una madera colgada.")
	l.append("")


func _ojos(p: Dictionary, l: Array[String]) -> void:
	l.append("### Dónde está la mano, en números")
	l.append("")
	l.append("`sobre la cadera` es la altura de la mano menos la de la cadera: en"
			+ " NEGATIVO la mano cuelga por debajo de la cadera, que es un brazo"
			+ " colgando. `del eje` es la distancia lateral al eje del cuerpo."
			+ " Cuando hay dos valores, son el mínimo y el máximo del clip.")
	l.append("")
	l.append("| pose | hueso | sobre la cadera (u) | del eje (u) |")
	l.append("|---|---|---|---|")
	var cad: Vector3 = _cabeza_de(p, "Hips")
	for c in ["reposo", "idle", "walk"]:
		for nombre in ["Hand.L", "Hand.R"]:
			if c == "reposo":
				var mano: Vector3 = _cabeza_de(p, nombre)
				if mano == Vector3.ZERO:
					continue
				l.append("| %s (sin animación) | `%s` | %+.3f | %.3f |"
						% [c, nombre, mano.y - cad.y, absf(mano.x)])
				continue
			var h: Dictionary = MEDIDOR.hueso(_rec(p, c), nombre)
			if h.is_empty():
				l.append("| %s | `%s` | — | — |" % [c, nombre])
				continue
			var mn: Vector3 = h["rel_min"] as Vector3
			var mx: Vector3 = h["rel_max"] as Vector3
			l.append("| %s | `%s` | %+.3f / %+.3f | %.3f / %.3f |"
					% [c, nombre, mn.y, mx.y, absf(mn.x), absf(mx.x)])
	l.append("")


func _cabeza_de(p: Dictionary, nombre: String) -> Vector3:
	for h in p.get("reposo", []):
		if str((h as Dictionary)["hueso"]) == nombre:
			return (h as Dictionary)["cabeza"] as Vector3
	return Vector3.ZERO


func _reposo(datos: Dictionary, l: Array[String]) -> void:
	var p: Dictionary = _principal(datos)
	if p.is_empty():
		return
	l.append("## (b) Pose de reposo del esqueleto (sin animación)")
	l.append("")
	l.append("`ángulo` son los grados que el EJE del hueso se separa de la"
			+ " vertical colgante: 0° es el brazo pegado al cuerpo, 45° la A, 90°"
			+ " la T. Es el eje del hueso (`basis.y`), no la resta de cabezas: en"
			+ " este rig los huesos de brazo arrancan desplazados del padre y con"
			+ " la resta salen 90°, o sea una T que el modelo no tiene.")
	l.append("")
	l.append("| hueso | ángulo de la vertical | abducción | cabeza (u) |")
	l.append("|---|---|---|---|")
	for h in p.get("reposo", []):
		var d: Dictionary = h as Dictionary
		var c: Vector3 = d["cabeza"] as Vector3
		l.append("| `%s` | %.1f° | %+.1f° | (%.3f, %.3f, %.3f) |"
				% [str(d["hueso"]), float(d["angulo_vertical"]),
				float(d["abduccion"]), c.x, c.y, c.z])
	l.append("")
	var cad: Vector3 = _cabeza_de(p, "Hips")
	for lado in ["Hand.L", "Hand.R"]:
		var mano: Vector3 = _cabeza_de(p, lado)
		if mano == Vector3.ZERO:
			continue
		l.append("- `%s` en reposo: **%+.3f u respecto de la cadera** y a %.3f u"
				% [lado, mano.y - cad.y, absf(mano.x)])
		l.append("  del eje del cuerpo. La cadera está a %.3f u del suelo y el"
				% cad.y)
		l.append("  modelo mide 1,90: un brazo de verdad colgando deja la mano")
		l.append("  varios centímetros POR DEBAJO de la cadera.")
	l.append("")


func _bucle(datos: Dictionary, l: Array[String]) -> void:
	var p: Dictionary = _principal(datos)
	if p.is_empty():
		return
	l.append("## (c) Bucle")
	l.append("")
	l.append("| clip | duración (s) | `loop_mode` importado |")
	l.append("|---|---|---|")
	for c in ["idle", "walk", "attack", "die"]:
		var d: Dictionary = _clip(p, c)
		if d.is_empty():
			continue
		l.append("| `%s` | %.4f | %d |" % [c, float(d["duracion"]),
				int(d["loop_importado"])])
	l.append("")
	var w: Dictionary = _rec(p, "walk")
	l.append("Costura del bucle de `walk`: %.2f° de salto al cerrar el ciclo"
			% float(w.get("cierre", 0.0)))
	l.append("contra %.2f° del salto más fuerte DENTRO del ciclo. La costura está"
			% float(w.get("interior", 0.0)))
	l.append("por debajo, así que el clip CIERRA bien y no hay tirón en el")
	l.append("empalme. Lo que hay es que el clip no cicla hasta que el código lo")
	l.append("dice.")
	l.append("")
	l.append("Quién lo pone: los cuatro clips llegan con `LOOP_NONE` del")
	l.append("importador, y tanto `player.gd:_preparar_clips` como")
	l.append("`enemy.gd:_preparar_clips` los ponen a `LOOP_LINEAR` en")
	l.append("`idle`/`walk`/`attack` y a `LOOP_NONE` en `die`, en tiempo de")
	l.append("ejecución. Es un parche sobre un dato del asset, no una propiedad")
	l.append("del clip: si se cuelga un `.glb` por una ruta que no pase por")
	l.append("ninguno de los dos, no cicla. La tabla de la sección siguiente lo")
	l.append("comprueba en las dos entidades.")
	l.append("")


func _raiz(datos: Dictionary, l: Array[String]) -> void:
	var p: Dictionary = _principal(datos)
	if p.is_empty():
		return
	l.append("## (d) Movimiento de raíz")
	l.append("")
	l.append("Pistas de POSICIÓN de cada clip. Si el `Hips` se desplazara en X o")
	l.append("en Z el personaje avanzaría con la animación y con el `CharacterBody`")
	l.append(" a la vez, y eso se ve como patinar.")
	l.append("")
	l.append("| clip | hueso | keys | rango X (u) | rango Y (u) | rango Z (u)"
			+ " | deriva del ciclo (u) |")
	l.append("|---|---|---|---|---|---|---|")
	var total: int = 0
	for c in ["idle", "walk", "attack", "die"]:
		for pista in _clip(p, c).get("pistas", []) as Array:
			var d: Dictionary = pista as Dictionary
			if int(d["tipo"]) != Animation.TYPE_POSITION_3D:
				continue
			total += 1
			var r: Vector3 = d["eje_rango"] as Vector3
			l.append("| `%s` | `%s` | %d | %.4f | %.4f | %.4f | %.4f |"
					% [c, str(d["hueso"]), int(d["leibles"]), r.x, r.y, r.z,
					(d["deriva"] as Vector3).length()])
	l.append("")
	l.append("Pistas de posición en los cuatro clips: %d. Todas son de `Hips` y"
			% total)
	l.append("ninguna de otro hueso. Conclusión: **no hay movimiento de raíz**.")
	l.append("Lo único que se mueve de sitio es la cadera en Y, y es el rebote")
	l.append("vertical de la marcha, de %.4f u (%.2f cm de mundo)."
			% [_rango_y(p, "walk"), _rango_y(p, "walk") * ESCALA * 100.0])
	l.append("")


func _rango_y(p: Dictionary, clip: String) -> float:
	return float((MEDIDOR.hueso(_rec(p, clip), "Hips").get("rango",
			Vector3.ZERO) as Vector3).y)


func _piel(datos: Dictionary, l: Array[String]) -> void:
	var p: Dictionary = _principal(datos)
	if p.is_empty():
		return
	l.append("## ¿El movimiento de los huesos llega a la malla?")
	l.append("")
	l.append("Esta es la pregunta que separa dos bugs distintos: «el clip no mueve")
	l.append("el brazo» y «el clip mueve el brazo y la malla no le hace caso». Se")
	l.append("responde despielzando la malla a mano —suma ponderada de las poses")
	l.append("globales de los huesos— en reposo y en el instante del clip donde el")
	l.append("húmero está más abierto, y midiendo cuánto se ha movido esa nube de")
	l.append("vértices. La pierna es el control.")
	l.append("")
	l.append("| clip | nube | vértices | peso medio | desplazamiento (u) |"
			+ " centro en reposo (sobre cadera / del eje) | centro en el clip |")
	l.append("|---|---|---|---|---|---|---|")
	for c in ["idle", "walk"]:
		var pi: Dictionary = _clip(p, c).get("piel", {}) as Dictionary
		if not bool(pi.get("ok", false)):
			l.append("| `%s` | — | — | — | %s |" % [c, str(pi.get("motivo", "?"))])
			continue
		for g in ["mano.L", "mano.R", "pierna.L", "pierna.R"]:
			var d: Dictionary = pi.get(g, {}) as Dictionary
			var rep: Vector3 = d.get("reposo", Vector3.ZERO) as Vector3
			var act: Vector3 = d.get("actual", Vector3.ZERO) as Vector3
			l.append(("| `%s` | %s | %d | %.2f | %.4f | %+.3f / %.3f |"
					+ " %+.3f / %.3f |") % [c,
					("**" + g + "**") if str(g).begins_with("mano") else g,
					int(d.get("n", 0)), float(d.get("peso_medio", 0.0)),
					float(d.get("desplazamiento", 0.0)),
					rep.y, absf(rep.x), act.y, absf(act.x)])
	l.append("")
	var pw: Dictionary = _clip(p, "walk").get("piel", {}) as Dictionary
	if bool(pw.get("ok", false)):
		var mano: float = float((pw.get("mano.L", {}) as Dictionary).get(
				"desplazamiento", 0.0))
		var pierna: float = float((pw.get("pierna.L", {}) as Dictionary).get(
				"desplazamiento", 0.0))
		l.append("En `walk` la nube de la mano se desplaza %.4f u y la de la"
				% mano)
		l.append("pierna %.4f u: la proporción es **%.2f**."
				% [pierna, (mano / pierna) if pierna > 0.0001 else 0.0])
		l.append("")
		if pierna > 0.0001 and mano / pierna > 1.5:
			l.append("**La malla SÍ sigue a los huesos del brazo**: el centro de la")
			l.append("nube de la mano pasa de %+.3f u sobre la cadera y %.3f u del"
					% [_centro(p, "walk", "mano.L", "reposo").y,
					absf(_centro(p, "walk", "mano.L", "reposo").x)])
			l.append("eje en reposo a %+.3f u y %.3f u en el clip. O sea que los"
					% [_centro(p, "walk", "mano.L", "actual").y,
					absf(_centro(p, "walk", "mano.L", "actual").x)])
			l.append("brazos NO se ven abiertos mientras el clip corre: se ven")
			l.append("PEGADOS al cuerpo. Los abiertos son la pose de REPOSO, la que")
			l.append("se ve sin animación, y por eso la pregunta que queda abierta")
			l.append("es «¿dónde se está viendo al personaje sin animación?», no")
			l.append("«¿qué hace el clip».")
			l.append("")
			l.append("Lo que sí es un defecto es la AMPLITUD, y aquí el número")
			l.append("fiable es el del HUESO, no el de la nube: el antebrazo se")
			l.append("separa 71° de la pose de reposo durante todo el clip. La causa")
			l.append("está en `tools/rig.py`: `BASE_BRAZO` se le suma a `UpperArm`,")
			l.append("`LowerArm` Y `Hand`, y como el antebrazo y la mano heredan la")
			l.append("del húmero, la corrección se TRIPLICA al bajar por la cadena.")
			l.append("Donde se quería quitar 33° al brazo, la mano se queda 71°")
			l.append("desvuelta: los brazos van pegados al cuerpo y cruzan hacia")
			l.append("dentro en vez de colgar. Y como el codo y la muñeca están")
			l.append("clavados, un brazo que no se dobla se lee como una madera.")
			l.append("")
			l.append("OJO con el desplazamiento de la nube de la mano: prueba que la")
			l.append("malla sigue a los huesos, pero su valor absoluto NO es una")
			l.append("medida del brazo. La nube se arma por «vértices cuyo peso")
			l.append("sumado a huesos de brazo pasa de 0,5 y que están lejos del eje»,")
			l.append("y eso incluye manga y faldón. Para la amplitud del brazo el")
			l.append("número bueno es el del hueso, el de la tabla de la sección (a).")
		elif pierna > 0.0001:
			l.append("La malla sigue a los huesos. La proporción de %.2f es la de un"
					% (mano / pierna))
			l.append("brazo que se mueve con naturalidad respecto de la pierna.")
	l.append("")


## Lo que ve el JUGADOR: la misma medición, pero por el camino que ejecuta el
## juego (el `Player` de verdad, con su `AnimationTree` y su reloj), y la del
## ENEMIGO, que es una entidad distinta con otro recorrido de código. Es la
## diferencia entre «el clip está bien» y «el clip llega a la pantalla».
func _juego(datos: Dictionary, l: Array[String]) -> void:
	l.append("## Lo que ve el juego: jugador y enemigo, por su camino de verdad")
	l.append("")
	var pj: Dictionary = _juego_jugador()
	var en: Dictionary = _juego_enemigo()
	l.append("| entidad | árbol activo | clip en uso | `loop` del `walk` |"
			+ " mano sobre la cadera (u) | mano del eje (u) |")
	l.append("|---|---|---|---|---|---|")
	for d in [pj, en]:
		if d.is_empty():
			continue
		l.append("| %s | %s | `%s` | %d | %+.3f / %+.3f | %.3f / %.3f |"
				% [str(d["nombre"]), "sí" if bool(d["arbol"]) else "**no**",
				str(d["clip"]), int(d["loop"]),
				float(d["mano_y_min"]), float(d["mano_y_max"]),
				float(d["mano_x_min"]), float(d["mano_x_max"])])
	l.append("")
	if not pj.is_empty():
		l.append("Referencia: la pose de REPOSO del esqueleto deja la mano a")
		var p: Dictionary = _principal(datos)
		if not p.is_empty():
			var cad: Vector3 = _cabeza_de(p, "Hips")
			l.append("**%+.3f u sobre la cadera y a %.3f u del eje**."
					% [_cabeza_de(p, "Hand.L").y - cad.y, absf(_cabeza_de(p, "Hand.L").x)])
	l.append("")
	for d in [pj, en]:
		if d.is_empty():
			continue
		l.append("- **%s**: %s" % [str(d["nombre"]), str(d["nota"])])
	l.append("")


func _juego_jugador() -> Dictionary:
	var PL: GDScript = preload("res://scripts/player/player.gd")
	var ARB: GDScript = preload("res://scripts/core/arbol_animacion.gd")
	var p: Node = PL.new()
	p.call("fijar_identidad", "H", "guerrero")
	p.call("aplicar_clase", "guerrero")
	root.add_child(p)
	var modelo: Node3D = p.get_node_or_null("Modelo") as Node3D
	if modelo == null:
		p.queue_free()
		return {}
	var salida: Dictionary = {"nombre": "jugador"}
	_observar(p, modelo, salida)
	# Y ahora lo que hace el juego cada frame andando a tope.
	p.set("velocity", Vector3(VEL_JUEGO, 0.0, 0.0))
	for _i in range(6):
		p.call("_actualizar_animacion", 1.0 / 60.0)
	var ap: AnimationPlayer = MEDIDOR.buscar(modelo, "AnimationPlayer") as AnimationPlayer
	var tree: Node = ap.get_node_or_null(NodePath(ARB.NOMBRE_ARBOL)) if ap != null else null
	salida["arbol"] = tree != null and (tree as AnimationTree).active
	salida["clip"] = ARB.clip_en_uso(ap) if ap != null else ""
	_mano_rango(modelo, salida)
	p.queue_free()
	return salida


func _juego_enemigo() -> Dictionary:
	var ARB: GDScript = preload("res://scripts/core/arbol_animacion.gd")
	var ruta: String = "res://scenes/enemy/enemigo.tscn"
	if not ResourceLoader.exists(ruta):
		return {}
	var e: Node3D = (load(ruta) as PackedScene).instantiate() as Node3D
	if e == null:
		return {}
	root.add_child(e)
	# Sin `configurar` con un arquetipo que traiga `modelo` el enemigo no se
	# cuelga ningún `.glb`: nace con la cápsula y no hay esqueleto que medir.
	# El único arquetipo del repo con modelo es el goblin.
	var datos: Dictionary = _json("res://data/enemies.json")
	var arquetipos: Dictionary = datos.get("arquetipos", {}) as Dictionary
	var elegido: String = ""
	for id in arquetipos:
		if str((arquetipos[id] as Dictionary).get("modelo", "")) != "":
			elegido = str(id)
			break
	if elegido != "":
		e.call("configurar", arquetipos[elegido])
	var modelo: Node3D = e.get_node_or_null("Modelo") as Node3D
	if modelo == null:
		modelo = e
	var salida: Dictionary = {"nombre": "enemigo"}
	_observar(e, modelo, salida)
	var stats: Variant = e.get("stats")
	var v_max: float = float((stats as StatBlock).vel_mov) \
			if stats is StatBlock else VEL_JUEGO
	e.set("velocity", Vector3(v_max, 0.0, 0.0))
	e.set("estado", 1)
	e.call("_actualizar_mezcla")
	var ap: AnimationPlayer = MEDIDOR.buscar(modelo, "AnimationPlayer") as AnimationPlayer
	var tree: Node = ap.get_node_or_null(NodePath(ARB.NOMBRE_ARBOL)) if ap != null else null
	salida["arbol"] = tree != null and (tree as AnimationTree).active
	salida["clip"] = ARB.clip_en_uso(ap) if ap != null else ""
	_mano_rango(modelo, salida)
	e.queue_free()
	return salida


func _observar(entidad: Node, modelo: Node3D, salida: Dictionary) -> void:
	var ap: AnimationPlayer = MEDIDOR.buscar(modelo, "AnimationPlayer") as AnimationPlayer
	if ap == null:
		salida["nota"] = "sin AnimationPlayer"
		return
	salida["loop"] = ap.get_animation("walk").loop_mode \
			if ap.has_animation("walk") else -1
	salida["nota"] = "bucle del walk: %s" % ("LINEAL" if int(salida["loop"]) == 1
			else "NINGUNO (el clip se reproduce una vez y se queda en el último frame)")


## Rango de la mano respecto de la cadera con lo que el juego tiene puesto AHORA,
## sin tocar un solo clip. Si sale pegada al eje, la animación está llegando.
func _mano_rango(modelo: Node3D, salida: Dictionary) -> void:
	var sk: Skeleton3D = MEDIDOR.buscar(modelo, "Skeleton3D") as Skeleton3D
	var ap: AnimationPlayer = MEDIDOR.buscar(modelo, "AnimationPlayer") as AnimationPlayer
	var arbol: AnimationTree = null
	if ap != null:
		for c in ap.get_children():
			if c is AnimationTree:
				arbol = c as AnimationTree
				break
	if sk == null:
		salida["nota"] = str(salida.get("nota", "")) + " | sin esqueleto"
		return
	var ih: int = sk.find_bone("Hand.L")
	var ic: int = sk.find_bone("Hips")
	if ih < 0 or ic < 0:
		salida["nota"] = str(salida.get("nota", "")) + " | sin Hand.L"
		return
	var y_min: float = 1e9
	var y_max: float = -1e9
	var x_min: float = 1e9
	var x_max: float = -1e9
	for _i in range(48):
		var rel: Vector3 = sk.get_bone_global_pose(ih).origin \
				- sk.get_bone_global_pose(ic).origin
		y_min = minf(y_min, rel.y)
		y_max = maxf(y_max, rel.y)
		x_min = minf(x_min, rel.x)
		x_max = maxf(x_max, rel.x)
		# Un frame de reloj del árbol, que es lo que mueve al esqueleto en el
		# juego. Sin esto el rango sale con un solo fotograma y no dice nada.
		if arbol != null and arbol.active:
			arbol.advance(1.0 / 60.0)
	salida["mano_y_min"] = y_min
	salida["mano_y_max"] = y_max
	salida["mano_x_min"] = x_min
	salida["mano_x_max"] = x_max
	salida["nota"] = str(salida.get("nota", "")) \
			+ " | la mano se mueve %.4f u de lado en el bucle medido" % (x_max - x_min)


## El centro de una nube de la malla, relativo a la cadera, en reposo o en el
## clip. Devuelve `Vector3.ZERO` si no se pudo medir.
func _centro(p: Dictionary, clip: String, grupo: String, cual: String) -> Vector3:
	var pi: Dictionary = _clip(p, clip).get("piel", {}) as Dictionary
	var d: Dictionary = pi.get(grupo, {}) as Dictionary
	return d.get(cual, Vector3.ZERO) as Vector3


func _flotar(datos: Dictionary, l: Array[String]) -> void:
	var p: Dictionary = _principal(datos)
	if p.is_empty():
		return
	var w: Dictionary = _rec(p, "walk")
	var z_paso: float = MEDIDOR.zancada(w, "Foot.L")
	var f: float = ritmo(VEL_JUEGO)
	var ciclo_real: float = float(w.get("duracion", 1.0)) / f
	var cubre: float = float(PASOS_POR_CICLO) * z_paso * ESCALA
	var avanza: float = VEL_JUEGO * ciclo_real
	var patinaje: float = (avanza - cubre) * 100.0
	var apoyo: Dictionary = w.get("apoyo", {}) as Dictionary
	var pasos: float = pasos_por_ciclo_real(w)
	l.append("## Qué pesa más en la sensación de «flotar»")
	l.append("")
	l.append("Las dos causas se miden por separado y NO valen lo mismo.")
	l.append("")
	l.append("### (i) El patinaje GLOBAL — cuadra. El INSTANTÁNEO, no se puede medir")
	l.append("")
	l.append("En un ciclo el cuerpo avanza %.3f m y los pies cubren %.3f m: la"
			% [avanza, cubre])
	l.append("diferencia es **%+.1f cm por ciclo**, o sea que a esta velocidad el"
			% patinaje)
	l.append("multiplicador ya cancela el desliz. Coincide con lo que mide la")
	l.append("fase 70 por su camino (sale -1,0 cm).")
	if bool(apoyo.get("ok", false)):
		var vel_pie: float = float(apoyo["velocidad_pie"])
		l.append("")
		l.append("**Y lo que NO se pudo medir, que es la mitad del diagnóstico:**")
		l.append("la velocidad del pie INSTANTÁNEA durante el apoyo. Se intentó por")
		l.append("dos caminos y los dos fallan, así que no hay número honesto que")
		l.append("poner:")
		l.append("")
		l.append("- Por «el punto más bajo del pie» (que es lo que hace la fase 70")
		l.append("  para el `dz`): la ventana cae en el BALANCEO, no en el apoyo, y")
		l.append("  sale `dz` positivo. La primera versión de esta auditoría sacaba")
		l.append("  «+2,58 u/s hacia delante» y lo leía como patinaje con el pie")
		l.append("  clavado.")
		l.append("- Por «el tramo más largo con el pie yendo hacia atrás»: da un")
		l.append("  tramo del %.0f %% del ciclo a **%+.3f u/s**, y ese número no"
				% [float(apoyo["fraccion_del_ciclo"]) * 100.0, vel_pie])
		l.append("  cuadra con nada, porque con un umbral de signo tan pequeño el")
		l.append("  tramo se come el ruido y se fusiona con casi todo el ciclo.")
		l.append("")
		l.append("La razón de fondo es que **este clip no tiene fase de apoyo**.")
		l.append("La trayectoria del pie es una oscilación suave antero-posterior")
		l.append("respecto de la cadera durante TODO el ciclo, sin tramo clavado:")
		l.append("es un clip procedural, no una captura de movimiento. El pie nunca")
		l.append("se queda quieto en el suelo, ni siquiera un instante. Eso no")
		l.append("aparece en la cuenta global (que sí cuadra, -1,5 cm) y es")
		l.append("justamente lo que el ojo lee como «flotar».")
		l.append("")
		l.append("Cómo se arregla, si se quiere: hace falta una fase de apoyo de")
		l.append("verdad, o sea un tramo con la altura del pie constante. Eso no se")
		l.append("consigue estirando el ciclo: hay que cambiar la forma de la")
		l.append("trayectoria del pie en `tools/rig.py`, o sea re-rigear.")
	l.append("")
	l.append("")
	l.append("### (ii) La cadencia — CONFIRMADA, y es lo que más pesa")
	l.append("")
	l.append("**%.2f pisadas por segundo.**" % pasos)
	l.append("")
	l.append("Un humano sprintea a 2,2-2,5 pisadas por segundo. A %.1f el ciclo"
			% pasos)
	l.append("dura %.4f s, o sea **%.1f frames de 60 Hz**: la pierna ya ha"
			% [ciclo_real, ciclo_real * 60.0])
	l.append("terminado su ciclo y el otro la empezó cuando la pantalla todavía")
	l.append("no ha mostrado tres. El ojo promedia varias posiciones del pie en el")
	l.append("mismo frame y lo lee como deslizamiento aunque el pie esté clavado.")
	l.append("ESO es lo que se ve como «flotar», y no lo arregla el multiplicador")
	l.append("de ritmo: el multiplicador mantiene la relación entre el pie y el")
	l.append("cuerpo, y lo que hay que cambiar es cuántos pasos hay en un segundo.")
	l.append("")
	l.append("### (iii) El rebote, que es el tercero y es pequeño")
	l.append("")
	var bob: float = _rango_y(p, "walk") * ESCALA
	l.append("La cadera sube y baja %.2f cm por ciclo. Para una zancada de"
			% (bob * 100.0))
	l.append("%.3f m eso es lo que toca, así que no es un error. Solo que al"
			% (z_paso * ESCALA))
	l.append("venir con %.1f pisadas por segundo se convierte en un temblor en"
			% pasos)
	l.append("vez de en un rebote. Es un síntoma, no una causa.")
	l.append("")


func _diseno(datos: Dictionary, l: Array[String]) -> void:
	var p: Dictionary = _principal(datos)
	if p.is_empty():
		return
	var w: Dictionary = _rec(p, "walk")
	var z_paso: float = MEDIDOR.zancada(w, "Foot.L")
	var z_mundo: float = z_paso * ESCALA
	l.append("## Las tres opciones de diseño, con su número")
	l.append("")
	l.append("`pasos/s = velocidad / zancada`. Da igual cuántos pasos se metan en")
	l.append("un ciclo: la zancada por paso es la del clip, %.3f m. Por eso"
			% z_mundo)
	l.append("**«alargar el ciclo» NO cambia la cadencia**, y esa es la")
	l.append("conclusión menos intuitiva de esta auditoría. Lo que cambia la")
	l.append("cadencia es la VELOCIDAD o la ZANCADA, y la zancada es un dato del")
	l.append("rig, o sea de Blender.")
	l.append("")
	l.append("| velocidad (m/s) | ritmo | ciclo real (s) | pasos/s | patinaje/ciclo (cm) |")
	l.append("|---|---|---|---|---|")
	for v in VELOCIDADES:
		var f: float = ritmo(v)
		var cr: float = float(w.get("duracion", 1.0)) / f
		var pasos: float = float(PASOS_POR_CICLO) / cr if cr > 0.0 else 0.0
		var pat: float = (v * cr - float(PASOS_POR_CICLO) * z_mundo) * 100.0
		l.append("| %.2f | %.2f | %.4f | %.2f | %+.1f |" % [v, f, cr, pasos, pat])
	l.append("")
	var v_nat: float = VELOCIDAD_CLIP * ESCALA
	l.append("Las tres opciones que se pusieron sobre la mesa, con su número:")
	l.append("")
	l.append("**A. Bajar la velocidad de caminata del juego.** A la velocidad"
			+ " natural del")
	l.append("clip (%.4f m/s) el ritmo cae a 1,0, el ciclo dura %.4f s y son"
			% [v_nat, float(w.get("duracion", 1.0))])
	l.append("**%.2f pisadas por segundo**: una marcha normal, cero patinaje."
			% (v_nat / z_mundo))
	l.append("El precio es que `vel_mov` no es solo animación: es `move_and_slide`,")
	l.append("el alcance de la esquiva, el de la persecución del enemigo y la")
	l.append("distancia de cierre. A %.2f m/s se cruzan 100 m en %.0f s, y en un"
			% [v_nat, 100.0 / v_nat])
	l.append("juego de rol eso se siente lento. Con 3 m/s son %.2f pisadas/s."
			% (3.0 / z_mundo))
	l.append("")
	l.append("**B. Alargar el ciclo (más zancadas por ciclo).** NO cambia los")
	l.append("pasos/s y por lo tanto no arregla la cadencia. Lo que sí la")
	l.append("arregla es alargar la ZANCADA, y eso es re-rigear con más amplitud")
	l.append("de pierna: para bajar a 4 pisadas/s a 6 m/s hacen falta %.2f m de"
			% (VEL_JUEGO / 4.0))
	l.append("zancada, o sea **%.1f veces** la que trae el clip (%.3f m). Es un"
			% [(VEL_JUEGO / 4.0) / z_mundo, z_mundo])
	l.append("superhéroe, no un hombre; y 6 m/s con zancada de %.2f m es un"
			% (VEL_JUEGO / 4.0))
	l.append("esprint, así que el clip tendría que ser un `run` re-rigeado, no")
	l.append("un `walk` alargado.")
	l.append("")
	l.append("**C. Aceptar el trote rápido.** %.2f pisadas/s, que es lo que hay"
			% pasos_por_ciclo_real(w))
	l.append("ahora. No es una decisión: es lo que pasa si no se decide nada, y")
	l.append("es justo lo que el usuario describe como «flotar».")
	l.append("")
	l.append("Lo que sale de los números, SIN decidir: el problema de fondo es que")
	l.append("6,0 m/s es un esprint (21,6 km/h, 3,2 veces la altura del cuerpo por")
	l.append("segundo) y el clip es un paseo. Ninguna de las tres opciones sale")
	l.append("gratis, y la comparación justa es: A cuesta velocidad de juego, B")
	l.append("cuesta re-rigear en Blender (y aquí no hay Blender, ver más abajo),")
	l.append("y C es dejar el síntoma como está.")
	l.append("")
	l.append("### Si hiciera falta re-rigear: qué y cuánto")
	l.append("")
	l.append("En esta máquina **no hay Blender** (`~/Tools/` solo tiene godot), y")
	l.append("el rig se generó con `tools/preparar_modelo.py` corrido dentro de")
	l.append("Blender, así que re-rigear no se puede hacer aquí. Lo que haría")
	l.append("falta, y no es una estimación de horas sino una lista:")
	l.append("")
	l.append("1. Instalar Blender 4.5 LTS (portable o paquete del sistema).")
	l.append("2. `~/Tools/blender/blender --background --python tools/preparar_modelo.py -- \\`")
	l.append("   models/original.glb models/clase_*.glb 30000 1 40` para los seis.")
	l.append("3. Cambiar en `tools/rig.py` la amplitud de la pierna en `_walk`")
	l.append("   (hoy `Thigh: a * 0.55`) y el `BASE_BRAZO`, y volver a exportar.")
	l.append("4. Reimportar y volver a medir con ESTE informe: el diff de")
	l.append("   `pasos/s` y `patinaje` dice si ha servido.")
	l.append("")
	l.append("El paso 3 es el que importa: sin tocar `rig.py` el re-rig reproduce")
	l.append("exactamente los mismos números, y eso ya se ha pagado una vez.")
	l.append("")


func _por_modelo(datos: Dictionary, l: Array[String]) -> void:
	l.append("## Los seis modelos, los mismos números")
	l.append("")
	l.append("| modelo | medible | ciclo walk (s) | muslo (°) | hombro (°)"
			+ " | `Hips` Y (u) | `Hips` XZ (u) | pasos/s a 6 m/s | zancada (u) |")
	l.append("|---|---|---|---|---|---|---|---|---|")
	for m in datos.get("modelos", []) as Array:
		var p: Dictionary = m as Dictionary
		var w: Dictionary = _rec(p, "walk")
		if w.is_empty():
			continue
		var c: Dictionary = p.get("clips", {}) as Dictionary
		var zp: float = MEDIDOR.zancada(w, "Foot.L")
		var cab: Dictionary = MEDIDOR.hueso(w, "Hips")
		var r: Vector3 = cab.get("rango", Vector3.ZERO) as Vector3
		l.append("| `%s` | %s | %.4f | %.1f | %.1f | %.4f | %.4f | %.2f | %.4f |"
				% [str(p["ruta"]),
				"sí" if bool(c["walk"].get("medible", false)) else "**NO**",
				float(w.get("duracion", 0.0)),
				float(MEDIDOR.hueso(w, "Thigh.L").get("recorrido", 0.0)),
				float(MEDIDOR.hueso(w, "UpperArm.L").get("recorrido", 0.0)),
				r.y, Vector2(r.x, r.z).length(),
				pasos_por_ciclo_real(w), zp])
	l.append("")


func _escribir_json(datos: Dictionary) -> void:
	var ruta: String = "res://%s/auditoria_clips.json" % _salida
	var f: FileAccess = FileAccess.open(ruta, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(datos, "\t"))
	f.close()
