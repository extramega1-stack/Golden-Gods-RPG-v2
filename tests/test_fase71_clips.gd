extends SceneTree
## Fase 71 — los cuatro clips, reescritos, y que se lean como una persona.
##
## Por que este test existe: la animación se "arregló" cuatro veces tocando el
## código y el sintoma que ve el usuario no se movió ("al caminar simplemente es
## como si flotara y solo tiene las manos levantadas abiertas COMO SIEMPRE").
## La causa estaba en el `.glb`, y eso no lo mira ningun test: los que hay
## comprueban que el clip EXISTA, que el arbol lo reproduzca y que el pie no
## patine, nunca que el personaje parezca alguien.
##
## Lo que se demuestra aqui, sobre el esqueleto REAL de los seis modelos (no
## sobre formulas):
##
##   (a) Los cuatro clips existen y duran lo que duraban.
##   (b) REPOSO CON LOS BRAZOS ABAJO: el pack llega con el brazo a 40 grados de
##       la vertical (una A tiesa, `tools/rig.py` `POSE_POR_DEFECTO`), y el
##       sintoma del usuario era ese brazo. Ahora esta por debajo de 20, los dos
##       lados iguales, y con el codo doblado.
##   (c) SWING DE BRAZOS: los brazos van al reves del pie, y en contrafase entre
##       ellos. Sin esto el personaje camina como un mueble.
##   (d) El pie NO FLOTA: la deduccion del sintoma. En el ciclo viejo el tobillo
##       se levantaba 14 cm del suelo; ahora la planta no se despega.
##   (e) SIN DESPLAZAMIENTO DE RAIZ: el Hips no se translada en el plano. El
##       CharacterBody mueve al bicho; si ademas lo mueve el clip, patina doble.
##   (f) BUCLE: la primera y la ultima clave son la MISMA pose en idle y walk.
##   (g) attack mueve los DOS brazos (el juego lleva arma en las dos).
##   (h) La invariante de no patinaje se sigue cumpliendo con el clip nuevo, y
##       la cadencia se imprime con numeros, no con una sensacion.
##
## Correrlo:
##   godot --headless --path . --script res://tests/test_fase71_clips.gd

## Modelos que deben llevar los clips nuevos. Se listan a mano y no se
## recorren: si mañana entra un modelo, este test dice "no mirado" en vez de
## dar verde sin haber mirado nada.
const MODELOS: Array = ["clase_guerrero", "clase_arquero", "clase_clerigo",
		"clase_mago", "clase_daguero", "bandido_rig"]
## Las duraciones que traían los clips viejos, a 0,01 s. `idle` y `attack`
## no se pueden cambiar porque el motor los usa igual; el `walk` nuevo dura más
## a propósito (ver `_cadencia`).
const DURACION_ESPERADA: Dictionary = {"idle": 2.042, "walk": 1.5,
		"attack": 0.833, "die": 1.208}
## El pack llega con el brazo a 40 grados: una A tiesa. El margen de 20 es
## "colgado", no "caido de golpe".
const GRADOS_MAX_BRAZO_REPOSO: float = 20.0
## Cuanto puede levantarse la planta del pie en la ventana del APOYO. El ciclo
## viejo levantaba 14 cm, que es justo lo que se ve como flotar; con el pie
## plantado queda el rodillo de 2 cm del talon y de la punta, que es geome-
## tria del pie y no de la animacion.
const FLOTE_MAX_CM: float = 3.0
## El Hips se puede subir y bajar un poco (el peso del paso), pero no travels.
const DESLIZ_MAX_CM: float = 2.0
## Cuanto puede bajar la cadera en el ciclo. Un ciclo viejo con zancada corta
## bajaba 2,8 cm con el pie en el aire; con el pie plantado, bajar más es de
## agacharse.
const BAJADA_MAX_CM: float = 13.0
## Lo que el ARBOL le pone al clip a 6 m/s (`ArbolAnimacion.ritmo`, 0,9 de
## escala). Se recalcula aquí y no se copia, para que el número del informe y
## el del juego no puedan separarse.
const VEL_JUEGO: float = 6.0
const ESCALA: float = 0.9

var _ok: int = 0
var _fallos: int = 0


func _initialize() -> void:
	print("[TEST] Fase 71 — los clips: brazos abajo, brazo que va al revés del pie,")
	print("[TEST]           pie que no flota, sin raiz y con bucle")


func _process(_delta: float) -> bool:
	for nombre in MODELOS:
		_un_modelo(str(nombre))
	print("[TEST] Fase 71 — %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)
	return true


func _un_modelo(nombre: String) -> void:
	var ruta: String = "res://models/%s.glb" % nombre
	if not ResourceLoader.exists(ruta):
		_chk(false, "%s: el modelo existe" % nombre, ruta)
		return
	var inst: Node3D = (load(ruta) as PackedScene).instantiate() as Node3D
	if inst == null:
		_chk(false, "%s: el .glb se puede instanciar" % nombre)
		return
	root.add_child(inst)
	var ap: AnimationPlayer = _buscar(inst, "AnimationPlayer") as AnimationPlayer
	var sk: Skeleton3D = _buscar(inst, "Skeleton3D") as Skeleton3D
	if ap == null or sk == null:
		_chk(false, "%s: trae AnimationPlayer y Skeleton3D" % nombre)
		inst.queue_free()
		return
	var i_pie: int = sk.find_bone("Foot.L")
	var i_cadera: int = sk.find_bone("Hips")
	var i_hombro: int = sk.find_bone("UpperArm.L")
	var i_antebrazo: int = sk.find_bone("LowerArm.L")
	var i_codo: int = sk.find_bone("UpperArm.R")
	if i_pie < 0 or i_cadera < 0 or i_hombro < 0 or i_antebrazo < 0 or i_codo < 0:
		_chk(false, "%s: los huesos de la pierna y del brazo existen" % nombre)
		inst.queue_free()
		return

	_duraciones(nombre, ap)
	_brazos_abajo(nombre, ap, sk, i_hombro, i_antebrazo, i_codo)
	var ciclo: Dictionary = _ciclo(ap, sk, i_pie, i_cadera)
	_swing(nombre, ap, sk, i_hombro, i_codo, i_pie, i_cadera)
	_sin_plantado(nombre, ap, sk, i_pie, i_cadera)
	_sin_raiz(nombre, ap, sk, i_cadera)
	_bucle(nombre, ap, sk)
	_ataque_a_dos_manos(nombre, ap, sk, i_hombro, i_codo)
	if not ciclo.is_empty():
		_invariante(nombre, ap, ciclo)
	inst.queue_free()


# ------------------------------------------------------------------ los clips


func _duraciones(nombre: String, ap: AnimationPlayer) -> void:
	for clave in DURACION_ESPERADA:
		var quiere: float = float(DURACION_ESPERADA[clave])
		if not ap.has_animation(clave):
			_chk(false, "%s: clip '%s' presente" % [nombre, clave])
			continue
		var d: float = ap.get_animation(clave).length
		_chk(absf(d - quiere) < 0.01,
			"%s: el clip '%s' dura lo que duraba" % [nombre, clave],
			"dura %.3f s y se esperaba %.3f" % [d, quiere])


# ------------------------------------------------------- (b) brazos abajo


func _brazo(sk: Skeleton3D, i: int) -> Vector3:
	return sk.get_bone_global_pose(i).basis.y.normalized()


## Grados que el brazo se separa de la vertical, mirando el angulo completo
## (no solo el de la vista de perfil): el pack llega a 40.
func _grados_brazo(sk: Skeleton3D, i: int) -> float:
	var d: Vector3 = _brazo(sk, i)
	var horiz: float = sqrt(d.x * d.x + d.z * d.z)
	return rad_to_deg(atan2(horiz, -d.y))


## Grados hacia DELANTE (+z es la cara del modelo; ver `Cuerpo.GIRO_MODELO`).
func _grados_frente(sk: Skeleton3D, i: int) -> float:
	var d: Vector3 = _brazo(sk, i)
	return rad_to_deg(atan2(d.z, -d.y))


func _brazos_abajo(nombre: String, ap: AnimationPlayer, sk: Skeleton3D,
		i_hombro: int, i_antebrazo: int, i_codo: int) -> void:
	ap.play("idle")
	ap.seek(0.0, true)
	var izq: float = _grados_brazo(sk, i_hombro)
	var der: float = _grados_brazo(sk, i_codo)
	_chk(izq < GRADOS_MAX_BRAZO_REPOSO and der < GRADOS_MAX_BRAZO_REPOSO,
		"%s: en reposo los brazos cuelgan (no A ni T)" % nombre,
		"L %.1f deg, R %.1f deg (el pack llega a 40)" % [izq, der])
	_chk(absf(izq - der) < 2.0,
		"%s: los dos brazos igual (simetria de verdad)" % nombre,
		"L %.2f deg contra R %.2f deg" % [izq, der])
	# El codo: una articulacion, no un palo. Y doblado hacia DELANTE, que es la
	# unica direccion en la que dobla un codo.
	var sup: Vector3 = _brazo(sk, i_hombro)
	var inf: Vector3 = _brazo(sk, i_antebrazo)
	var codo: float = rad_to_deg(sup.angle_to(inf))
	_chk(codo > 5.0 and codo < 30.0,
		"%s: el codo tiene angulacion natural" % nombre,
		"flexion del codo %.1f deg (0 seria un palo, y por encima de 30 una "
		% codo + "mano de zombi)")
	_chk(inf.z > sup.z,
		"%s: el antebrazo dobla hacia delante" % nombre,
		"antebrazo z=%.3f contra brazo z=%.3f" % [inf.z, sup.z])


# ------------------------------------------------- (c) swing de brazos


## Que el brazo vaya al reves que el pie, y los dos brazos en contrafase. Se
## mide sobre el clip CRUDO con `seek`, o sea en el tiempo del `.glb`: el juego
## lo reproduce al reves (`ArbolAnimacion.CAMINAR_AL_REVES`), y por eso el
## criterio se pide con el signo cambiado.
func _swing(nombre: String, ap: AnimationPlayer, sk: Skeleton3D, i_hombro: int,
		i_codo: int, i_pie: int, i_cadera: int) -> void:
	if not ap.has_animation("walk"):
		return
	ap.play("walk")
	var dur: float = ap.get_animation("walk").length
	var n: int = 48
	var frente_l: Array[float] = []
	var frente_r: Array[float] = []
	var pie: Array[float] = []
	for i in range(n + 1):
		ap.seek(dur * float(i) / float(n), true)
		frente_l.append(_grados_frente(sk, i_hombro))
		frente_r.append(_grados_frente(sk, i_codo))
		pie.append(sk.get_bone_global_pose(i_pie).origin.z
				- sk.get_bone_global_pose(i_cadera).origin.z)
	var vaiven_l: float = frente_l.max() - frente_l.min()
	var vaiven_r: float = frente_r.max() - frente_r.min()
	_chk(vaiven_l > 10.0 and vaiven_r > 10.0,
		"%s: los brazos barren hacia delante y atras al caminar" % nombre,
		"vaiven L %.1f deg, R %.1f deg" % [vaiven_l, vaiven_r])
	# En contrafase: los dos brazos van al reves, asi que la SUMA de sus angulos
	# se queda en cero. No se puede pedir que el signo de la diferencia no
	# cambie nunca, porque los dos brazos pasan por el neutro a la vez y ahi la
	# diferencia es cero: eso es la contrafase, no un fallo.
	var suma_max: float = 0.0
	var dif_max: float = 0.0
	for i in range(frente_l.size()):
		suma_max = maxf(suma_max, absf(frente_l[i] + frente_r[i]))
		dif_max = maxf(dif_max, absf(frente_l[i] - frente_r[i]))
	_chk(suma_max < 3.0 and dif_max > 20.0,
		"%s: los dos brazos van en contrafase" % nombre,
		"|suma| llega a %.1f deg (0 = al reves) y |diferencia| a %.1f deg"
		% [suma_max, dif_max])
	# Y el brazo contralateral al pie: en el instante en que el pie adelanta mas,
	# su mismo brazo va atras. En el crudo, al reves del tiempo del juego.
	var i_max: int = pie.find(pie.max())
	var i_min: int = pie.find(pie.min())
	_chk(frente_l[i_max] < frente_l[i_min],
		"%s: el brazo izquierdo va atras cuando su pie adelanta" % nombre,
		"pie +%.3f -> brazo %.1f deg | pie +%.3f -> brazo %.1f deg"
		% [pie[i_max], frente_l[i_max], pie[i_min], frente_l[i_min]])


# ------------------------------------------ (d) el pie no flota


## La deduccion del sintoma, medida. En la pisada el tobillo se queda a su
## altura de reposo; lo que sube es el pie en el VUELO, y solo ahi.
func _sin_plantado(nombre: String, ap: AnimationPlayer, sk: Skeleton3D,
		i_pie: int, i_cadera: int) -> void:
	var dur: float = ap.get_animation("walk").length
	var n: int = 96
	var zs: Array[float] = []
	var ys: Array[float] = []
	for i in range(n + 1):
		ap.seek(dur * float(i) / float(n), true)
		ys.append(sk.get_bone_global_pose(i_pie).origin.y)
		zs.append(sk.get_bone_global_pose(i_pie).origin.z
				- sk.get_bone_global_pose(i_cadera).origin.z)
	var suelo: float = ys.min()
	var i_apoyo: int = ys.find(suelo)
	var ini: int = maxi(0, i_apoyo - 10)
	var fin: int = mini(n, i_apoyo + 10)
	var planta: float = 0.0
	for i in range(ini, fin + 1):
		planta = maxf(planta, ys[i] - suelo)
	_chk(planta * 100.0 < FLOTE_MAX_CM,
		"%s: en el APOYO la planta no se despega (no flota)" % nombre,
		"el tobillo sube %.2f cm en la ventana del apoyo (el ciclo viejo: 14 cm; "
		% (planta * 100.0)
		+ "lo que queda es el rodillo del talon y de la punta)")
	# Y el sentido del apoyo, que es lo que `test_fase70` mide con el arbol: en
	# el crudo el ciclo va espejado, porque el juego lo reproduce al reves.
	var dz: float = zs[fin] - zs[ini]
	_chk(dz > 0.1,
		"%s: el ciclo crudo va espejado (el juego lo da vuelta)" % nombre,
		"en el apoyo el pie va %+.4f u; al reves serian %+.4f"
		% [dz, -dz])
	var zancada: float = zs.max() - zs.min()
	_chk(zancada > 0.8,
		"%s: la zancada es de persona, no depasitos" % nombre,
		"zancada %.4f u (el ciclo viejo: 0,7430, o sea 39%% de la altura)"
		% zancada)


# ------------------------------------------- (e) sin desplazamiento de raiz


func _sin_raiz(nombre: String, ap: AnimationPlayer, sk: Skeleton3D,
		i_cadera: int) -> void:
	ap.play("walk")
	var dur: float = ap.get_animation("walk").length
	var n: int = 48
	var xs: Array[float] = []
	var zs: Array[float] = []
	var ys: Array[float] = []
	for i in range(n + 1):
		ap.seek(dur * float(i) / float(n), true)
		var p: Vector3 = sk.get_bone_global_pose(i_cadera).origin
		xs.append(p.x)
		ys.append(p.y)
		zs.append(p.z)
	_chk((xs.max() - xs.min()) * 100.0 < DESLIZ_MAX_CM,
		"%s: el Hips no se desplaza de lado (lo mueve el CharacterBody)" % nombre,
		"x varia %.2f cm" % ((xs.max() - xs.min()) * 100.0))
	_chk((zs.max() - zs.min()) * 100.0 < DESLIZ_MAX_CM,
		"%s: el Hips no se desplaza hacia delante" % nombre,
		"z varia %.2f cm (el juego avanza hacia -Z; un avance aqui es patinaje"
		% ((zs.max() - zs.min()) * 100.0) + " doble)")
	var bajada: float = (ys.max() - ys.min()) * 100.0
	_chk(bajada < BAJADA_MAX_CM,
		"%s: la cadera solo sube y baja lo que pesa el paso" % nombre,
		"baja %.1f cm en el ciclo" % bajada)


# --------------------------------------------------------- (f) el bucle


func _bucle(nombre: String, ap: AnimationPlayer, sk: Skeleton3D) -> void:
	for clave in ["idle", "walk"]:
		ap.play(clave)
		var dur: float = ap.get_animation(clave).length
		ap.seek(0.0, true)
		var a: Array[Transform3D] = []
		for i in range(19):
			a.append(sk.get_bone_global_pose(i))
		ap.seek(dur, true)
		var peor: float = 0.0
		for i in range(19):
			peor = maxf(peor, (a[i].origin - sk.get_bone_global_pose(i).origin).length())
		_chk(peor < 0.005,
			"%s: el clip '%s' cicla sin tiron" % [nombre, clave],
			"la pose del frame final dista %.5f u de la del inicial" % peor)


# ------------------------------------------ (g) el tajo usa las dos manos


func _ataque_a_dos_manos(nombre: String, ap: AnimationPlayer, sk: Skeleton3D,
		i_hombro: int, i_codo: int) -> void:
	ap.play("attack")
	var dur: float = ap.get_animation("attack").length
	var n: int = 24
	var giro: Array[float] = []
	for i in range(n + 1):
		ap.seek(dur * float(i) / float(n), true)
		giro.append(_grados_frente(sk, i_hombro) + _grados_frente(sk, i_codo))
	var camino: float = giro.max() - giro.min()
	_chk(camino > 40.0,
		"%s: el tajo mueve los DOS brazos" % nombre,
		"recorrido conjunto %.1f deg (con un solo brazo daria la mitad)"
		% camino)
	# Y que los dos brazos hagan lo mismo, que es lo que hace un tajo a dos manos.
	var ambos: int = 0
	for i in range(n + 1):
		ap.seek(dur * float(i) / float(n), true)
		if signf(_grados_frente(sk, i_hombro)) == signf(_grados_frente(sk, i_codo)):
			ambos += 1
	_chk(ambos > n / 2,
		"%s: los dos brazos van al mismo lado en el tajo" % nombre,
		"%d de %d instantes" % [ambos, n + 1])


# ------------------------------- (h) invariante de no patinaje y cadencia


func _ciclo(ap: AnimationPlayer, sk: Skeleton3D, i_pie: int,
		i_cadera: int) -> Dictionary:
	if not ap.has_animation("walk"):
		return {}
	var dur: float = ap.get_animation("walk").length
	if dur <= 0.0:
		return {}
	ap.play("walk")
	var n: int = 96
	var zs: Array[float] = []
	for i in range(n + 1):
		ap.seek(dur * float(i) / float(n), true)
		zs.append(sk.get_bone_global_pose(i_pie).origin.z
				- sk.get_bone_global_pose(i_cadera).origin.z)
	return {"zancada": zs.max() - zs.min(), "duracion": dur}


func _invariante(nombre: String, ap: AnimationPlayer,
		ciclo: Dictionary) -> void:
	var zancada: float = float(ciclo["zancada"])
	var dur: float = float(ciclo["duracion"])
	var natural: float = zancada * 2.0 / dur
	_chk(absf(natural - ArbolAnimacion.VELOCIDAD_CLIP) < 0.02,
		"%s: la velocidad de viaje del clip es la de la constante" % nombre,
		"medida %.4f u/s, ArbolAnimacion.VELOCIDAD_CLIP %.4f u/s"
		% [natural, ArbolAnimacion.VELOCIDAD_CLIP])
	# Y la cadencia, con numeros. El numero grande es el que pide el encargo, y
	# no se puede llegar con este esqueleto: 2,2-3,2 pisadas por segundo a 6 m/s
	# pide una zancada de 1,9 a 2,7 m en un personaje de 1,71 m con una pierna de
	# 0,77 m. Se imprime el de zancadas (dos pasos) y el de pisadas, y el
	# veredicto de por que.
	var ritmo: float = ArbolAnimacion.ritmo(VEL_JUEGO, ESCALA)
	var ciclo_real: float = dur / ritmo
	var pisadas: float = 2.0 * ritmo / dur
	var zancadas: float = pisadas * 0.5
	print("  %-16s zancada %.3f m | zancadas/s %.2f | pisadas/s %.2f | "
		% [nombre, zancada * ESCALA, zancadas, pisadas]
		+ "ciclo real %.3f s | pedal minimo para 3,2 pisadas/s: zancada de "
		% ciclo_real + "%.2f m (imposible con una pierna de 0,77 m)"
		% (VEL_JUEGO / 3.2))
	if nombre == str(MODELOS[0]):
		print("  (pedir 2,2-3,2 PISADAS por segundo a 6 m/s necesita una zancada")
		print("   de 1,88 a 2,73 m: 1,1 a 1,6 veces la altura del personaje. El")
		print("   suelo de este esqueleto son 3,92 pisadas/s con las piernas")
		print("   horizontales. El numero de arriba es el mejor fisicamente posible")
		print("   sin romper la invariante de no patinaje, que es la que manda.)")
	_chk(zancadas > 3.0 and zancadas < 3.4,
		"%s: la cadencia queda en el tope de lo que da este esqueleto" % nombre,
		"%.2f zancadas por segundo (%.2f pisadas)" % [zancadas, pisadas])
	_chk(zancada * ESCALA > 0.9,
		"%s: la zancada crecio frente al ciclo viejo (0,67 m)" % nombre,
		"%.3f m" % (zancada * ESCALA))


# ------------------------------------------------------------------ chores


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] " + nombre + ("" if detalle == "" else "  <-- " + detalle))


func _buscar(n: Node, tipo: String) -> Node:
	if n == null:
		return null
	if n.is_class(tipo):
		return n
	for c in n.get_children():
		var h: Node = _buscar(c, tipo)
		if h != null:
			return h
	return null
