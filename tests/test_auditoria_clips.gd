extends SceneTree
## Auditoría de los clips: la regresión de los números del informe.
##
## `tools/auditoria_clips.gd` mide y escribe el informe. Este test mide con el
## MISMO módulo (`tools/auditoria_clips/medidor.gd`, por `preload`) y
## comprueba que los números no cambien solos. Si el informe y el test salieran
## de dos sitios distintos, un `diff` del informe podría mentir y la regresión
## no lo cazaría.
##
## LO QUE ESTE TEST PROTEGE, y por qué cada línea está aquí:
##
## 1. **El cero falso.** La medición de rotación por hueso ya dio 0,000 en todo
##    una vez, y no porque el clip estuviera quieto: `seek()` sin `advance(0.0)`
##    no escribe sobre el esqueleto, y `get_bone_pose` (que devuelve la pose de
##    REPOSO, no la animada) tampoco. Aquí se comprueba el ciclo entero del
##    `walk` con `medible()`, que exige que el MUSLO —que sí se mueve, en
##    `rig.py` con 0,55 rad de balanceo— pase de 100 grados por ciclo. Con el
##    número a cero, el test se pone rojo en vez de pasar sin comprobar nada.
##
## 2. **La cadencia.** Es la causa de «flotar» y sale de dos datos que se
##    pueden mover por separado: la duración del clip y la zancada. Se
##    comprueban los dos contra lo que el código afirma (`VELOCIDAD_CLIP`).
##
## 3. **Los brazos.** El síntoma «manos levantadas abiertas» NO es que el clip
##    no los mueva: los mueve y de más. Se fija la amplitud del húmero, la
##    amplitud del antebrazo y el hecho de que el hombro, el antebrazo y la
##    muñeca NO tienen pista en `walk`. Si alguien «arregla» el rig y mete una
##    pista de codo, esta línea avisa de que el número ha cambiado.
##
## 4. **La pose de reposo.** Es la que se ve sin animación, y es la A de la
##    malla: 40° de la vertical, con la mano POR ENCIMA de la cadera. Se fija
##    con margen, porque es un número que viene de la malla de Meshy y puede
##    cambiar si se re-rigea; lo que no puede cambiar sin que alguien lo
##    decida es irse a una T (90°).
##
## 5. **El bucle y la raíz.** `LOOP_NONE` importado en los cuatro clips, y
##    ninguna pista de posición que no sea la de `Hips` en Y. Un movimiento de
##    raíz en X o Z haría que el personaje se moviera dos veces.
##
## Correrlo:
##   godot --headless --path . --script res://tests/test_auditoria_clips.gd

const MEDIDOR: GDScript = preload("res://tools/auditoria_clips/medidor.gd")

## `ArbolAnimacion.VELOCIDAD_CLIP`. Se repite aquí a propósito: si el código
## cambia la constante y el clip no, este test tiene que ponerse rojo.
const VELOCIDAD_CLIP: float = 1.4264
## `modelo_escala` de las cinco clases (`data/clases.json`).
const ESCALA: float = 0.9
## Pisadas por ciclo del clip de caminar (`tools/rig.py:_walk`).
const PASOS_POR_CICLO: int = 2
## Velocidad de caminado del juego (`StatBlock.vel_mov` base).
const VEL_JUEGO: float = 6.0
## Muestreo del ciclo. 121 es impar para que caiga una muestra en la costura.
const MUESTRAS: int = 121

## Los seis modelos del pack. Se miden todos: el síntoma dice «los modelos» y
## un solo `.glb` no lo demuestra.
const MODELOS: Array[String] = [
	"res://models/clase_guerrero.glb",
	"res://models/clase_arquero.glb",
	"res://models/clase_clerigo.glb",
	"res://models/clase_daguero.glb",
	"res://models/clase_mago.glb",
	"res://models/bandido_rig.glb",
]

var _ok: int = 0
var _fallos: int = 0
var _fase: int = 0


func _initialize() -> void:
	print("[TEST] Auditoría de los clips — brazos, pose de reposo, bucle y raíz")


## Va en `_process` y no en `_initialize`, como en `tools/anim_medida`: en
## `_initialize` la raíz todavía no está dentro del árbol y `seek()` no escribe
## sobre el esqueleto. Es el mismo cero falso, y por eso el trabajo pesado
## espera a un frame.
func _process(_delta: float) -> bool:
	_fase += 1
	if _fase > MODELOS.size():
		_finalizar()
		quit(_fallos)
		return true
	_uno(MODELOS[_fase - 1])
	return false


func _uno(ruta: String) -> void:
	var abierto: Dictionary = MEDIDOR.abrir(ruta)
	if not bool(abierto.get("ok", false)):
		_chk(false, "%s: el modelo se abre" % ruta, str(abierto.get("motivo")))
		return
	var raiz: Node = abierto["raiz"] as Node
	var ap: AnimationPlayer = abierto["ap"] as AnimationPlayer
	var sk: Skeleton3D = abierto["sk"] as Skeleton3D
	root.add_child(raiz)
	var nombre: String = ruta.get_file()
	# (1) EL GUARDIÁN. Sin esto, todo lo de abajo puede salir en cero y
	# pasar: es el error que ya se cometió.
	var walk: Dictionary = MEDIDOR.recorrer(ap, sk, "walk", MUESTRAS)
	_chk(MEDIDOR.medible(walk),
		"%s: la medicion mide (el muslo se mueve de verdad)" % nombre,
		"muslo=%.1f grados por ciclo" % float(MEDIDOR.hueso(walk, "Thigh.L")
				.get("recorrido", 0.0)))
	if not MEDIDOR.medible(walk):
		root.remove_child(raiz)
		raiz.free()
		return
	_zancada(nombre, walk)
	_brazo(nombre, ap, walk)
	_reposo(nombre, sk)
	_bucle(nombre, ap)
	_raiz_movimiento(nombre, ap)
	root.remove_child(raiz)
	raiz.free()


## (2) La cadencia sale de la duración y de la zancada, y las dos se comparan
## con lo que el código afirma. La relación es la del skating: si el clip se
## reproduce al ritmo que cancela el patinaje, la zancada por segundo tiene que
## ser la velocidad natural del clip, y no la del juego.
func _zancada(nombre: String, walk: Dictionary) -> void:
	var dur: float = float(walk["duracion"])
	var z: float = MEDIDOR.zancada(walk, "Foot.L")
	_chk(absf(dur - 1.0417) < 0.02, "%s: el walk dura 1,04 s" % nombre,
			"dur=%.4f s" % dur)
	_chk(z > 0.5, "%s: el pie cubre una zancada de verdad" % nombre,
			"zancada=%.4f u" % z)
	# La constante del código es la velocidad natural del clip, en unidades de
	# esqueleto: `zancada * pisadas_por_ciclo / duracion`.
	var natural: float = z * float(PASOS_POR_CICLO) / dur
	_chk(absf(natural - VELOCIDAD_CLIP) < 0.05,
			"%s: la constante VELOCIDAD_CLIP es la zancada REAL del clip" % nombre,
			"medida=%.4f  codigo=%.4f u/s" % [natural, VELOCIDAD_CLIP])
	# Y la cadencia con la que se JUEGA, que es el número del síntoma.
	var ritmo: float = _ritmo(VEL_JUEGO)
	var pasos_s: float = float(PASOS_POR_CICLO) * ritmo / dur
	# Un humano sprintea a 2,2-2,5 pisadas por segundo. Si este número baja de
	# 6 sin que nadie lo haya decidido, alguien ha arreglado la cadencia y el
	# informe está viejo.
	_chk(pasos_s > 6.0,
			"%s: la cadencia sigue siendo la alta (a 6 m/s)" % nombre,
			"pasos/s=%.2f  ciclo real=%.4f s  ritmo=%.2f" % [pasos_s,
			dur / ritmo, ritmo])
	# Y el pie no patina: en un ciclo el cuerpo avanza `v * ciclo` y los pies
	# cubren `pisadas * zancada`. Con el ritmo puesto, la diferencia es pequeña.
	var slip: float = (VEL_JUEGO * dur / ritmo
			- float(PASOS_POR_CICLO) * z * ESCALA) * 100.0
	_chk(absf(slip) < 15.0, "%s: el pie no patina con el ritmo puesto" % nombre,
			"patinaje=%+.1f cm por ciclo" % slip)


## (3) Los brazos. El húmero se mueve; el hombro, el antebrazo y la muñeca no
## tienen pista en `walk`; y la amplitud del antebrazo sale de la cadena
## heredada, no de su propia pista (que tiene una sola key).
func _brazo(nombre: String, ap: AnimationPlayer, walk: Dictionary) -> void:
	var por_hueso: Dictionary = MEDIDOR.huesos_con_pista(ap.get_animation("walk"))
	for clavado in ["Shoulder.L", "Shoulder.R", "LowerArm.L", "LowerArm.R",
			"Hand.L", "Hand.R"]:
		var d: Dictionary = por_hueso.get(clavado, {}) as Dictionary
		var keys: int = int(d.get("keys", 0))
		_chk(keys <= 1, "%s: '%s' no se anima en el walk" % [nombre, clavado],
				"keys=%d" % keys)
	for movil in ["UpperArm.L", "UpperArm.R"]:
		var d: Dictionary = por_hueso.get(movil, {}) as Dictionary
		_chk(int(d.get("keys", 0)) > 8, "%s: '%s' SI se anima" % [nombre, movil],
				"keys=%d" % int(d.get("keys", 0)))
		var h: Dictionary = MEDIDOR.hueso(walk, movil)
		# La apertura del húmero respecto de la pose de reposo. Con el
		# multiplicador de `rig.py` son unos 36 grados; el margen es para que
		# un retoque deDegrees no rompa la suite, no para tapar un cambio grande.
		_chk(float(h.get("desviacion", 0.0)) > 15.0,
				"%s: '%s' se separa de la pose de reposo" % [nombre, movil],
				"desviacion=%.1f grados" % float(h.get("desviacion", 0.0)))
	# La cadena del brazo: el antebrazo se separa MÁS que el húmero porque
	# hereda su rotación. Es la compensación de `BASE_BRAZO` aplicándose tres
	# veces (húmero, antebrazo y mano) y trips up, y por eso los brazos quedan
	# pegados al cuerpo en vez de colgados.
	var humero: float = float(MEDIDOR.hueso(walk, "UpperArm.L").get("desviacion", 0.0))
	var ante: float = float(MEDIDOR.hueso(walk, "LowerArm.L").get("desviacion", 0.0))
	_chk(ante > humero * 1.4,
			"%s: el antebrazo hereda la rotacion del humero" % nombre,
			"humero=%.1f grados  antebrazo=%.1f grados" % [humero, ante])
	# Y la mano, en el mundo del esqueleto, termina MUY cerca del cuerpo: el
	# ojo la lee como brazo pegado, no como brazo abierto. La referencia es la
	# pose de reposo, donde la mano está a 0,51 u del eje.
	var mano: Dictionary = MEDIDOR.hueso(walk, "Hand.L")
	var lejos: float = float((mano.get("rel_max", Vector3.ZERO) as Vector3).x)
	_chk(lejos < 0.30, "%s: en el walk la mano queda pegada al cuerpo" % nombre,
			"mano a %.3f u del eje (en reposo esta a 0,512)" % lejos)
	# Y por encima de la cadera NO está, o sea que tampoco está «levantada».
	var alto: float = float((mano.get("rel_max", Vector3.ZERO) as Vector3).y)
	_chk(alto < 0.10, "%s: en el walk la mano no queda levantada" % nombre,
			"mano a %+.3f u de la cadera (en reposo esta a +0,094)" % alto)


## (4) La pose de reposo: la A de la malla. El fallo caro es que se vaya a una
## T (90°) o a brazos colgando (0°), porque las dos se ven igual de mal y por
## motivos distintos; por eso la banda es [25, 60] y no un punto.
func _reposo(nombre: String, sk: Skeleton3D) -> void:
	var reposo: Array = MEDIDOR.pose_reposo(sk)
	for h in reposo:
		var d: Dictionary = h as Dictionary
		if str(d["hueso"]) == "UpperArm.L":
			var ang: float = float(d["angulo_vertical"])
			_chk(ang > 25.0 and ang < 60.0,
					"%s: el brazo de reposo es la A, ni T ni colgando" % nombre,
					"UpperArm.L a %.1f grados de la vertical" % ang)
		if str(d["hueso"]) == "Hips":
			var c: Vector3 = d["cabeza"] as Vector3
			# La cadera a 0,95 u del suelo en un modelo de 1,90: el rig se
			# escala con la altura de la malla (`rig.enrutar`), y este número
			# se mueve si `PROP` cambia.
			_chk(c.y > 0.70 and c.y < 1.25, "%s: la cadera esta a media altura" % nombre,
					"Hips a %.3f u" % c.y)


## (5) El bucle. Importados vienen lineales y el bucle lo pone el código; si
## alguien arregla el asset o el importador, el número cambia y hay que saberlo.
func _bucle(nombre: String, ap: AnimationPlayer) -> void:
	for clip in ["idle", "walk", "attack", "die"]:
		if not ap.has_animation(clip):
			_chk(false, "%s: hay clip %s" % [nombre, clip])
			continue
		var anim: Animation = ap.get_animation(clip)
		_chk(anim.loop_mode == Animation.LOOP_NONE,
				"%s: '%s' llega lineal (el bucle lo pone el codigo)" % [nombre, clip],
				"loop_mode=%d" % anim.loop_mode)
		_chk(anim.length > 0.0, "%s: '%s' tiene duracion" % [nombre, clip],
				"length=%.4f" % anim.length)


## (6) La raíz. Si el `Hips` se desplazara en X o Z, el personaje avanzaría con
## la animación y con el `CharacterBody` a la vez, y eso se vería como patinar
## dos veces. Aquí no hay desplazamiento: solo el rebote vertical de la cadera.
func _raiz_movimiento(nombre: String, ap: AnimationPlayer) -> void:
	for clip in ["idle", "walk", "attack", "die"]:
		if not ap.has_animation(clip):
			continue
		for pista in MEDIDOR.pistas(ap.get_animation(clip)):
			var d: Dictionary = pista as Dictionary
			if int(d["tipo"]) != Animation.TYPE_POSITION_3D:
				continue
			_chk(str(d["hueso"]) == "Hips",
					"%s/'%s': solo el Hips tiene pista de posicion" % [nombre, clip],
					"hueso=%s" % str(d["hueso"]))
			var r: Vector3 = d["eje_rango"] as Vector3
			_chk(r.x < 0.001 and r.z < 0.001,
					"%s/'%s': la cadera NO se desplaza en X ni en Z" % [nombre, clip],
					"rango=(%.4f, %.4f, %.4f) u" % [r.x, r.y, r.z])


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] " + nombre + ("" if detalle == "" else "  <-- " + detalle))


static func _ritmo(v: float) -> float:
	var bruto: float = v / (VELOCIDAD_CLIP * ESCALA)
	return clampf(roundf(bruto / 0.25) * 0.25, 0.5, 6.0)


func _finalizar() -> void:
	print("[TEST] Auditoría de los clips — %d ok, %d fallos" % [_ok, _fallos])
