extends RefCounted
## Medición de los clips de los `.glb` del pack, sobre el esqueleto real.
##
## POR QUÉ ESTE MÓDULO EXISTE Y POR QUÉ NO ES UN `extends SceneTree`: la
## auditoría y el test tienen que decir LO MISMO. Si el número saliera de dos
## sitios distintos, el informe y la regresión podrían contradecirse y no
## habría forma de saber cuál miente. Aquí vive la medición; el que la cuenta
## (informe) y el que la juzga (test) la piden con `preload`, sin `class_name`
## para no obligar a reimportar el proyecto en cada worktree.
##
## LAS TRAMPAS DE LA LECTURA, todas pagadas aquí (esta es la parte que no se
## puede deducir, hay que haberlas pisado):
##
## 1. `Animation` NO tiene `track_get_count()`: se llama `get_track_count()`. La
##    versión con `track_` delante no existe en 4.7 y revienta el script.
##
## 2. "57 canales por clip" es FALSO. 57 = 19 huesos x 3 canales, o sea el
##    máximo teórico. Lo que trae el `.glb` son 17: una de posición (Hips) y
##    dieciséis de rotación. Los huesos sin pista no es que valgan cero: es que
##    NO EXISTEN, y eso es una categoría distinta, porque un hueso sin pista se
##    queda en la pose de reposo para siempre.
##
## 3. Una key NO es "constante" por casualidad: `rig.py` escribe manyimas
##    rotaciones de brazo como tuplas fijas (`LowerArm.L: (-0.25, 0, 0)`), así
##    que el exportador legitimately las hornea a una sola key. Y al revés:
##    `Hand.L`/`Hand.R` tienen una key con un valor FUERA de la identidad, o sea
##    que la pose del rig sí quedó marcada, aunque ningún clip la anime.
##
## 4. La rotación de un hueso NO se lee con `get_bone_pose` (esa devuelve la
##    pose de REPOSO, y sale 0,000 en todo: es el error que ya se cometió una
##    vez). Se lee con `get_bone_global_pose` DESPUÉS de `ap.seek(t, true)`, y
##    se recorre hueso a hueso. `caminar()` trae la prueba de que ese camino mide
##    de verdad: si `Thigh.L` no supera los 100 grados de recorrido, la
##    medición está rota y `medible()` lo dice en vez de devolver ceros.
##
## 5. `seek()` da el ciclo CRUDO. La inversión que usa el juego vive en el
##    `play_mode` del nodo del árbol, no en el clip, así que el sentido de la
##    marcha hay que medirlo por el árbol (`con_arbol`). Para todo lo demás
##    (keys, pose de reposo, bucle, raíz) el clip crudo es la fuente.

## Muestras por ciclo. 241 es impar para que caiga una muestra exacta en el
## cierre del bucle, que es lo que hay que comparar contra el interior.
const MUESTRAS: int = 241

## Los tres canales que el exportador puede escribir por hueso, por nombre de
## hueso, para poder decir "este clip no tiene pista de este hueso".
static func huesos_de_ruta(ruta: String) -> String:
	var i: int = ruta.rfind(":")
	return ruta.substr(i + 1) if i >= 0 else ruta


static func abrir(ruta_glb: String) -> Dictionary:
	"""Instancia el modelo y devuelve `{raiz, ap, sk}`. `ok` false si no hay."""
	if not ResourceLoader.exists(ruta_glb):
		return {"ok": false, "motivo": "no existe " + ruta_glb}
	var ps: PackedScene = load(ruta_glb) as PackedScene
	if ps == null:
		return {"ok": false, "motivo": "no se pudo cargar " + ruta_glb}
	var raiz: Node = ps.instantiate()
	if raiz == null:
		return {"ok": false, "motivo": "instancia nula de " + ruta_glb}
	var ap: AnimationPlayer = buscar(raiz, "AnimationPlayer") as AnimationPlayer
	var sk: Skeleton3D = buscar(raiz, "Skeleton3D") as Skeleton3D
	if ap == null or sk == null:
		raiz.free()
		return {"ok": false, "motivo": "sin AnimationPlayer o sin Skeleton3D"}
	return {"ok": true, "raiz": raiz, "ap": ap, "sk": sk, "ruta": ruta_glb}


static func buscar(n: Node, clase: String) -> Node:
	if n == null:
		return null
	if n.is_class(clase):
		return n
	for c in n.get_children():
		var h: Node = buscar(c, clase)
		if h != null:
			return h
	return null


# --------------------------------------------------------------- pistas


## Inventario de pistas de un clip. Por cada pista: cuántas keys DECLARA el
## recurso, cuántas se pueden LEER, y cuánto se mueve el valor.
##
## ElDeclared-vs-leíble sale porque en 4.7 no siempre coinciden y la diferencia
## es información: si se midiera solo con lo declarado, el recorrido saldría
## inflado. Aquí se lee hasta el primer fallo y se cuenta lo que hay de verdad.
static func pistas(anim: Animation) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(anim.get_track_count()):
		var ruta: String = str(anim.track_get_path(i))
		var tipo: int = anim.track_get_type(i)
		var declaradas: int = anim.track_get_key_count(i)
		var valores: Array = []
		for k in range(declaradas):
			var v: Variant = anim.track_get_key_value(i, k)
			if v == null:
				break
			valores.append(v)
		var d: Dictionary = {
			"ruta": ruta,
			"hueso": huesos_de_ruta(ruta),
			"tipo": tipo,
			"declaradas": declaradas,
			"leibles": valores.size(),
			"recorrido": 0.0,
			"desviacion": 0.0,
			"eje_rango": Vector3.ZERO,
			"deriva": Vector3.ZERO,
		}
		if tipo == Animation.TYPE_ROTATION_3D:
			_anotar_rotacion(d, valores)
		elif tipo == Animation.TYPE_POSITION_3D:
			_anotar_posicion(d, valores)
		out.append(d)
	return out


static func _anotar_rotacion(d: Dictionary, valores: Array) -> void:
	if valores.is_empty():
		return
	var primero: Quaternion = valores[0] as Quaternion
	var previo: Quaternion = primero
	var desvio: float = 0.0
	var camino: float = 0.0
	for v in valores:
		var q: Quaternion = v as Quaternion
		camino += previo.angle_to(q)
		desvio = maxf(desvio, primero.angle_to(q))
		previo = q
	d["recorrido"] = rad_to_deg(camino)
	d["desviacion"] = rad_to_deg(desvio)


static func _anotar_posicion(d: Dictionary, valores: Array) -> void:
	if valores.is_empty():
		return
	var primero: Vector3 = valores[0] as Vector3
	var minimo: Vector3 = primero
	var maximo: Vector3 = primero
	for v in valores:
		var p: Vector3 = v as Vector3
		minimo = minimo.min(p)
		maximo = maximo.max(p)
	d["eje_rango"] = maximo - minimo
	d["deriva"] = (valores[valores.size() - 1] as Vector3) - primero


## Qué huesos se mueven de verdad en este clip: los que tienen una pista con
## recorrido, y los que tienen pista pero NO se mueven (una key, o todas
## iguales). La lista completa de los 19 huesos sale de `pose_reposo`.
static func huesos_con_pista(anim: Animation) -> Dictionary:
	var con: Dictionary = {}
	for p in pistas(anim):
		var h: String = str(p["hueso"])
		if not con.has(h):
			con[h] = {"pistas": 0, "keys": 0, "recorrido": 0.0}
		con[h]["pistas"] = int(con[h]["pistas"]) + 1
		con[h]["keys"] = int(con[h]["keys"]) + int(p["leibles"])
		con[h]["recorrido"] = float(con[h]["recorrido"]) + float(p["recorrido"])
	return con


# ------------------------------------------------------------ pose de reposo


## La pose del esqueleto SIN animación: la que se ve si no se reproduce nada, y
## la que hereda todo hueso al que el clip no le da pista.
##
## `angulo_vertical` son los grados que el hueso se separa de la vertical
## colgante: 0 es el brazo pegado al cuerpo, 45 la A, 90 la T. `mano_sobre_cadera`
## es lo que el ojo lee como "manos levantadas": cuánto está la mano por encima
## de la cadera, en unidades de esqueleto.
static func pose_reposo(sk: Skeleton3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(sk.get_bone_count()):
		var pose: Transform3D = sk.get_bone_global_rest(i)
		var direccion: Vector3 = pose.basis.y.normalized()
		out.append({
			"hueso": sk.get_bone_name(i),
			"padre": sk.get_bone_parent(i),
			"cabeza": pose.origin,
			# La dirección de un hueso es SU eje, `basis.y` (cola - cabeza), y
			# NO la resta cabeza - cabeza_del_padre. En este rig los huesos de
			# brazo arrancan desplazados del padre (el `Shoulder` va de x=0,05 a
			# x=0,17 en horizontal), así que la resta da 90° —una T— donde el
			# hueso real va a 40°. Con esa resta el informe decía «T-pose» y
			# el modelo, de pie, no lo está.
			"angulo_vertical": angulo_de_vertical(direccion),
			"abduccion": rad_to_deg(atan2(direccion.x, -direccion.y)),
		})
	return out


static func angulo_de_vertical(direccion: Vector3) -> float:
	return rad_to_deg(acos(clampf(-direccion.normalized().y, -1.0, 1.0)))


# -------------------------------------------------------------- recorrido


## Recorre un ciclo del clip CRUDO por `seek` y mide, por hueso, el recorrido
## de rotación acumulado en grados, cuánto se aparta de la pose de reposo, y
## para la cadera y los pies, cuánto se desplaza.
##
## Se recorre ORIENTACIÓN GLOBAL, no la pista: es lo que deforma la malla y lo
## que se ve. Con 30 mil triángulos y cuatro huesos por vértice, un hueso puede
## tener keys y no mover ni un vértice si los pesos no le llegan; la
## orientación global no tiene ese problema.
static func recorrer(ap: AnimationPlayer, sk: Skeleton3D, clip: String,
		muestras: int = MUESTRAS) -> Dictionary:
	if not ap.has_animation(clip):
		return {"ok": false, "motivo": "no hay clip " + clip}
	var anim: Animation = ap.get_animation(clip)
	var dur: float = anim.length
	if dur <= 0.0:
		return {"ok": false, "motivo": "clip sin duracion"}
	var n: int = maxi(3, muestras)
	var nb: int = sk.get_bone_count()
	var i_cadera: int = sk.find_bone("Hips")
	var i_pie: int = sk.find_bone("Foot.L")
	# Reposo: la referencia contra la que se mide la desviación.
	var reposo: Array[Transform3D] = []
	for i in range(nb):
		reposo.append(sk.get_bone_global_rest(i))
	# Se lee la pose en reposo ANTES de reproducir, porque `seek` la pisa.
	ap.play(clip)
	ap.seek(0.0, true)
	ap.advance(0.0)
	var anterior: Array[Transform3D] = reposo.duplicate()
	var recorrido: Array[float] = []
	var desvio: Array[float] = []
	var min_desv: Array[float] = []
	var ang_min: Array[float] = []
	var ang_max: Array[float] = []
	for i in range(nb):
		recorrido.append(0.0)
		desvio.append(0.0)
		min_desv.append(1e9)
		ang_min.append(1e9)
		ang_max.append(-1e9)
	var origen_min: Array[Vector3] = []
	var origen_max: Array[Vector3] = []
	var primer_origen: Array[Vector3] = []
	var ultimo_origen: Array[Vector3] = []
	# Lo mismo, pero RELATIVO A LA CADERA, que es como lo lee el ojo: la
	# pregunta «¿la mano está levantada?» es «¿cuánto está la mano por encima
	# de la cadera y a cuánto está del eje?».
	var rel_min: Array[Vector3] = []
	var rel_max: Array[Vector3] = []
	for i in range(nb):
		origen_min.append(Vector3(1e9, 1e9, 1e9))
		origen_max.append(Vector3(-1e9, -1e9, -1e9))
		primer_origen.append(Vector3.ZERO)
		ultimo_origen.append(Vector3.ZERO)
		rel_min.append(Vector3(1e9, 1e9, 1e9))
		rel_max.append(Vector3(-1e9, -1e9, -1e9))
	var tiempos: Array[float] = []
	var pie_z: Array[float] = []
	var pie_y: Array[float] = []
	var pasitos: Array[float] = []
	var poses_distintas: int = 0
	for paso in range(n + 1):
		var pose_movida: bool = false
		ap.seek(dur * float(paso) / float(n), true)
		# ESTE `advance(0.0)` ES LO QUE FALTA SI DA CERO. Con `seek` solo, el
		# mixer no avanza su reloj interno y no aplica NADA sobre el esqueleto:
		# `get_bone_global_pose` devuelve la pose de reposo en las 242 muestras y
		# el informe entero sale en 0,000 sin que se note. Con el `advance` de
		# paso, el clip se escribe sobre los huesos. Es la diferencia entre
		# medir y no medir, y no se deduce: hay que haber dado en ella.
		ap.advance(0.0)
		for i in range(nb):
			var ahora: Transform3D = sk.get_bone_global_pose(i)
			var prev: Transform3D = anterior[i]
			var quina: Quaternion = ahora.basis.get_rotation_quaternion()
			var quina_prev: Quaternion = prev.basis.get_rotation_quaternion()
			var salto: float = rad_to_deg(quina_prev.angle_to(quina))
			recorrido[i] += salto
			var d: float = rad_to_deg(Quaternion(reposo[i].basis.orthonormalized().inverse() \
					* ahora.basis.orthonormalized()).get_angle())
			desvio[i] = maxf(desvio[i], d)
			min_desv[i] = minf(min_desv[i], d)
			var ang: float = angulo_de_vertical(ahora.basis.y)
			ang_min[i] = minf(ang_min[i], ang)
			ang_max[i] = maxf(ang_max[i], ang)
			origen_min[i] = origen_min[i].min(ahora.origin)
			origen_max[i] = origen_max[i].max(ahora.origin)
			var cadera: Vector3 = sk.get_bone_global_pose(i_cadera).origin
			var rel: Vector3 = ahora.origin - cadera
			rel_min[i] = rel_min[i].min(rel)
			rel_max[i] = rel_max[i].max(rel)
			if paso == 0:
				primer_origen[i] = ahora.origin
			ultimo_origen[i] = ahora.origin
			anterior[i] = ahora
			if paso > 0:
				pasitos.append(salto)
				if salto > 0.0005:
					pose_movida = true
		if pose_movida:
			poses_distintas += 1
		if i_pie >= 0 and i_cadera >= 0:
				tiempos.append(dur * float(paso) / float(n))
				pie_z.append(sk.get_bone_global_pose(i_pie).origin.z
						- sk.get_bone_global_pose(i_cadera).origin.z)
				pie_y.append(sk.get_bone_global_pose(i_pie).origin.y)
	var huesos: Array[Dictionary] = []
	for i in range(nb):
		huesos.append({
			"hueso": sk.get_bone_name(i),
			"recorrido": recorrido[i],
			"desviacion": desvio[i],
			"desviacion_min": 0.0 if min_desv[i] > 1e8 else min_desv[i],
			"angulo_min": ang_min[i],
			"angulo_max": ang_max[i],
			"rango": origen_max[i] - origen_min[i],
			"deriva": ultimo_origen[i] - primer_origen[i],
			"rel_min": rel_min[i],
			"rel_max": rel_max[i],
		})
	ap.stop()
	ap.seek(0.0, true)
	ap.advance(0.0)
	var cierre: float = 0.0
	var interior: float = 0.0
	if pasitos.size() >= 4:
		cierre = pasitos[pasitos.size() - 1]
		var acc: float = 0.0
		for k in range(1, pasitos.size() - 1):
			acc = maxf(acc, pasitos[k])
		interior = acc
	return {
		"ok": true,
		"clip": clip,
		"duracion": dur,
		"muestras": n,
		"loop": anim.loop_mode,
		"huesos": huesos,
		"cierre": cierre,
		"interior": interior,
		"poses_distintas": poses_distintas,
		"apoyo": _apoyo(tiempos, pie_y, pie_z),
	}


## ¿EL MOVIMIENTO DE LOS HUESOS LLEGA A LA MALLA?
##
## Esta es la pregunta que separa «el clip no mueve el brazo» de «el clip mueve
## el brazo y la malla no le hace caso», y son dos bugs distintos con dos
## arreglos distintos. Los pesos del pack se calculan a mano (`rig.pesos_proprios`)
## y ya se ha pagado una vez que el brazo se quedaba con el pecho y la cadera y
## no se movía: 2 grados cuando se le pedían 23.
##
## Se mide con LA PIEL, no con los huesos: se coge la nube de vértices que
## pesa a los huesos del brazo, se despielza a mano (suma ponderada de las
## poses globales de los huesos) en reposo y en un instante del clip, y se mide
## cuánto se ha movido esa nube. La pierna sale de control: si la pierna se
## mueve y la mano no, el esqueleto está bien y la malla no.
static func piel(ap: AnimationPlayer, sk: Skeleton3D, malla: MeshInstance3D,
		clip: String) -> Dictionary:
	if malla == null or malla.mesh == null:
		return {"ok": false, "motivo": "el modelo no trae malla"}
	var arrays: Array = malla.mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return {"ok": false, "motivo": "la malla no tiene superficie 0"}
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var huesos: PackedInt32Array = arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var pesos: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	if vertices.is_empty() or huesos.size() != pesos.size() or huesos.is_empty():
		return {"ok": false, "motivo": "la malla no trae datos de piel"}
	var por_hueso: int = maxi(1, huesos.size() / maxi(vertices.size(), 1))
	# Los índices de hueso de la malla son sobre los BONES del skin, no sobre
	# los del esqueleto; aquí son los mismos, pero se comprueba en vez de
	# suponerlo, porque si no lo fueran la suma se calcularía con el hueso
	# equivocado y saldría «la malla no se mueve» sin motivo.
	var nb: int = sk.get_bone_count()
	var limites: Dictionary = {}
	for nombre in ["Hips", "UpperArm.L", "LowerArm.L", "Hand.L", "UpperArm.R",
			"LowerArm.R", "Hand.R", "Thigh.L", "Shin.L", "Foot.L",
			"Thigh.R", "Shin.R", "Foot.R"]:
		limites[nombre] = sk.find_bone(nombre)
	# A esqueleto: la malla es hija del esqueleto y puede tener escala propia.
	var a_malla: Transform3D = malla.global_transform * sk.global_transform.affine_inverse()
	var reposo: Array[Transform3D] = []
	for i in range(nb):
		reposo.append(a_malla * sk.get_bone_global_rest(i))
	var grupos: Dictionary = {
		"mano.L": [], "mano.R": [], "pierna.L": [], "pierna.R": [],
	}
	var peso_mano: Dictionary = {"L": 0.0, "R": 0.0}
	for v in range(vertices.size()):
		var x: float = vertices[v].x
		var lejos: bool = absf(x) > 0.30 * _ancho(vertices)
		for lado in ["L", "R"]:
			var suma: float = 0.0
			for k in range(por_hueso):
				var bi: int = huesos[v * por_hueso + k]
				if bi < 0 or bi >= nb:
					continue
				var nombre: String = sk.get_bone_name(bi)
				if nombre.ends_with("." + lado) and (nombre.begins_with("UpperArm")
						or nombre.begins_with("LowerArm")
						or nombre.begins_with("Hand")):
					suma += pesos[v * por_hueso + k]
			if suma > 0.5 and lejos:
				var g: Array = grupos["mano." + lado] as Array
				g.append(v)
				peso_mano[lado] = float(peso_mano[lado]) + suma
				break
		for lado in ["L", "R"]:
			var sp: float = 0.0
			for k in range(por_hueso):
				var bi: int = huesos[v * por_hueso + k]
				if bi < 0 or bi >= nb:
					continue
				var nombre: String = sk.get_bone_name(bi)
				if nombre.ends_with("." + lado) and (nombre.begins_with("Thigh")
						or nombre.begins_with("Shin") or nombre.begins_with("Foot")):
					sp += pesos[v * por_hueso + k]
			if sp > 0.5:
				var g: Array = grupos["pierna." + lado] as Array
				g.append(v)
				break
	var total: Dictionary = {}
	for g in grupos:
		total[g] = (grupos[g] as Array).size()
	ap.play(clip)
	# Dos instantes: el de mayor apertura del húmero y el inicial, para que la
	# comparación sea contra la pose de la malla y no contra el frame 0.
	var dur: float = ap.get_animation(clip).length
	var mejor: float = -1.0
	var t_mejor: float = 0.0
	for k in range(49):
		ap.seek(dur * float(k) / 48.0, true)
		ap.advance(0.0)
		var d: float = _sep_arbol(ap, sk, "UpperArm.L", "Shoulder.L")
		if d > mejor:
			mejor = d
			t_mejor = dur * float(k) / 48.0
	ap.seek(t_mejor, true)
	ap.advance(0.0)
	var actual: Array[Transform3D] = []
	for i in range(nb):
		actual.append(a_malla * sk.get_bone_global_pose(i))
	var salida: Dictionary = {
		"ok": true,
		"clip": clip,
		"t": t_mejor,
		"vertices": vertices.size(),
		"influencias": por_hueso,
		"tamanos": total,
	}
	for g in grupos:
		var indices: Array = grupos[g] as Array
		if indices.is_empty():
			salida[g] = {"n": 0, "desplazamiento": 0.0, "peso_medio": 0.0}
			continue
		var acum: float = 0.0
		var w: float = 0.0
		var centro_rep: Vector3 = Vector3.ZERO
		var centro_act: Vector3 = Vector3.ZERO
		for v in indices:
			var vi: int = int(v)
			acum += _despliegue(vertices, huesos, pesos, por_hueso, vi, nb,
					reposo, actual).length()
			centro_rep += _centro(vertices, huesos, pesos, por_hueso, vi, nb, reposo)
			centro_act += _centro(vertices, huesos, pesos, por_hueso, vi, nb, actual)
			for k in range(por_hueso):
				w += pesos[vi * por_hueso + k]
		var n: float = float(indices.size())
		centro_rep /= n
		centro_act /= n
		# La cadera en el mismo espacio, para poder decir «la mano está por
		# encima o por debajo de la cadera» sobre la MALLA y no sobre el hueso.
		var cadera: Vector3 = a_malla * sk.get_bone_global_pose(
				sk.find_bone("Hips")).origin
		salida[g] = {
			"n": indices.size(),
			"desplazamiento": acum / n,
			"peso_medio": w / (n * float(por_hueso)),
			"reposo": centro_rep - cadera,
			"actual": centro_act - cadera,
		}
	ap.stop()
	ap.seek(0.0, true)
	ap.advance(0.0)
	return salida


static func _ancho(vertices: PackedVector3Array) -> float:
	var x: float = 0.0
	for v in vertices:
		x = maxf(x, absf(v.x))
	return maxf(x, 0.0001)


## Cuánto se abre el húmero respecto de su padre en el instante actual, en
## grados: el «cuánto se ha movido el brazo» sin mirar la pista.
static func _sep_arbol(ap: AnimationPlayer, sk: Skeleton3D, hijo: String,
		padre: String) -> float:
	var ih: int = sk.find_bone(hijo)
	var ip: int = sk.find_bone(padre)
	if ih < 0 or ip < 0:
		return 0.0
	var a: Vector3 = sk.get_bone_global_pose(ih).basis.y
	var b: Vector3 = sk.get_bone_global_pose(ip).basis.y
	return rad_to_deg(a.angle_to(b))


## El centro despiezado de un vértice, en el espacio de la malla.
static func _centro(vertices: PackedVector3Array, huesos: PackedInt32Array,
		pesos: PackedFloat32Array, por_hueso: int, v: int, nb: int,
		poses: Array[Transform3D]) -> Vector3:
	var p: Vector3 = Vector3.ZERO
	var total: float = 0.0
	for k in range(por_hueso):
		var bi: int = huesos[v * por_hueso + k]
		var w: float = pesos[v * por_hueso + k]
		if bi < 0 or bi >= nb or w <= 0.0:
			continue
		total += w
		p += w * (poses[bi] * vertices[v])
	return p / total if total > 0.0 else vertices[v]


## Un vértice despiezado a mano: suma de `peso * (pose_del_hueso * v)`.
static func _despliegue(vertices: PackedVector3Array, huesos: PackedInt32Array,
		pesos: PackedFloat32Array, por_hueso: int, v: int, nb: int,
		reposo: Array[Transform3D], actual: Array[Transform3D]) -> Vector3:
	var p_rep: Vector3 = Vector3.ZERO
	var p_act: Vector3 = Vector3.ZERO
	var total: float = 0.0
	for k in range(por_hueso):
		var bi: int = huesos[v * por_hueso + k]
		var w: float = pesos[v * por_hueso + k]
		if bi < 0 or bi >= nb or w <= 0.0:
			continue
		total += w
		p_rep += w * (reposo[bi] * vertices[v])
		p_act += w * (actual[bi] * vertices[v])
	if total <= 0.0:
		return Vector3.ZERO
	return p_act / total - p_rep / total


## El APOYO y el desliz del pie, medidos y no deducidos.
##
## La fase de contacto, y por qué NO se puede buscar por «el punto más bajo».
##
## La primera versión de esta medida cogía la ventana alrededor del mínimo de la
## altura del pie, que es lo que hace `test_fase70` para el `dz`. Aquí da
## `dz` POSITIVO —el pie yendo hacia delante— lo que significa que en este clip
## el punto más bajo NO es el apoyo sino la fase de balanceo. Con esa ventana la
## medida affirmative habría dicho «el pie patina» con el pie clavado, o sea al
## revés, y por eso la ventana se define por la DEFINICIÓN de la fase de
## apoyo: el tramo más largo en el que el pie va hacia ATRÁS respecto de la
## cadera. Un pie en el suelo va atrás mientras el cuerpo pasa por encima; un pie
## en el aire va hacia delante. No hay más que mirar el signo.
##
## Se mide en unidades de esqueleto por segundo y se compara con `v / escala`,
## que es lo que el cuerpo avanza en ese espacio. Si coinciden, el pie está
## clavado; si el pie va a 0, está patinando.
static func _apoyo(tiempos: Array[float], ys: Array[float],
		zs: Array[float]) -> Dictionary:
	if ys.size() < 8:
		return {"ok": false}
	var n: int = ys.size()
	# Tramos con el pie yendo hacia atrás respecto de la cadera.
	var tramos: Array[Vector2i] = []
	var ini: int = -1
	for k in range(1, n):
		var va: bool = zs[k] - zs[k - 1] < -0.00005
		if va and ini < 0:
			ini = k - 1
		elif not va and ini >= 0:
			tramos.append(Vector2i(ini, k - 1))
			ini = -1
	if ini >= 0:
		tramos.append(Vector2i(ini, n - 1))
	var mejor: Vector2i = Vector2i(-1, -1)
	for t in tramos:
		if t.y - t.x > mejor.y - mejor.x:
			mejor = t
	if mejor.x < 0:
		return {"ok": false, "motivo": "el pie nunca va hacia atras en el ciclo"}
	var dt: float = maxf(tiempos[mejor.y] - tiempos[mejor.x], 0.0001)
	var dz: float = zs[mejor.y] - zs[mejor.x]
	return {
		"ok": true,
		"i": mejor.x,
		"inicio": tiempos[mejor.x],
		"fin": tiempos[mejor.y],
		"altura": ys[mejor.x],
		"ventana_s": dt,
		"fraccion_del_ciclo": (mejor.y - mejor.x) / float(n),
		# Negativo = el pie va hacia atrás mientras el cuerpo pasa por encima.
		"dz": dz,
		"velocidad_pie": dz / dt,
		"minimo_a": ys.min(),
	}


## ¿La medición sirve de algo? Si el hueso que SE SABE que se mueve (el muslo:
## el ciclo de marcha le da 0,55 rad de balanceo) no supera los 100 grados de
## recorrido, el número que sale es cero por una lectura mala, no porque el clip
## esté quieto. Es el guardia que faltaba la vez que todo dio 0,000.
static func medible(rec: Dictionary) -> bool:
	if not bool(rec.get("ok", false)):
		return false
	for h in rec.get("huesos", []):
		if str(h["hueso"]) == "Thigh.L" and float(h["recorrido"]) > 100.0:
			return true
	return false


static func hueso(rec: Dictionary, nombre: String) -> Dictionary:
	for h in rec.get("huesos", []):
		if str(h["hueso"]) == nombre:
			return h
	return {}


# ------------------------------------------------------------- ritmo y pisadas


## Pisadas por segundo de este clip a esta velocidad de juego.
##
## steps/s = velocidad / zancada, y la zancada es del clip. Da IGUAL cuantos
## pasos se metan en un ciclo: dos o cuatro, el pie tiene que recorrer la misma
## zancada por paso. Por eso "alargar el ciclo" no arregla la cadencia, y
## conviene tenerlo escrito porque es la conclusión menos intuitiva de la
## auditoría.
static func pisadas_por_segundo(velocidad: float, zancada_unidades: float,
		escala: float = 1.0) -> float:
	var z: float = zancada_unidades * escala
	if z <= 0.0001:
		return 0.0
	return velocidad / z


## Zancada de un pie por paso, en unidades de esqueleto, medida: el recorrido
## antero-posterior del hueso del pie a lo largo de un ciclo, dividido por las
## pisadas que da ese ciclo.
static func zancada(rec: Dictionary, hueso_pie: String) -> float:
	"""Zancada de UNA pisada, en unidades de esqueleto.
##
	El rango Z del hueso del pie a lo largo del ciclo es la distancia de suelo
	que esa pisada cubre, y NO hay que dividirlo por las pisadas del ciclo. Es
	la misma cuenta que hace la fase 70 (`zancada * 2 / duracion ==
	VELOCIDAD_CLIP`): con dos pisadas por ciclo, el ciclo cubre dos zancadas.
	Dividirlo otra vez da la mitad y con eso los pasos por segundo salen
	doblados: 18 en vez de 9, sin que nada en el rig se haya movido.
	"""
	var h: Dictionary = hueso(rec, hueso_pie)
	if h.is_empty():
		return 0.0
	return float(h["rango"].z)
