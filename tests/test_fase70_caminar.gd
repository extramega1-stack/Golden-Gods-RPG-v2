extends SceneTree
## Fase 70 — que camine, y que no patine.
##
## "Caminan horrible" son cinco cosas distintas y esta fase las MIDIO una por
## una en vez de suponer. Lo que salió, con números sobre el esqueleto real de
## los `.glb` del pack:
##
## (1) El clip mal elegido — DESCARTADO. Los 6 modelos traen `attack`, `die`,
##     `idle`, `walk`, que son los cuatro que se piden, en ese orden. No hay
##     ningún quinto clip ni ninguno con el nombre movido.
##
## (2) La mezcla saturada — CONFIRMADO, y era la causa de que el blend fuera
##     un disfraz. La mezcla pedía `clampf((v - 0,45) / 0,45, 0, 1)`, que
##     satura en 1,0 a los 0,90 m/s. El jugador anda a 6,0 m/s
##     (`StatBlock.vel_mov`) y los enemigos igual, así que `blend_position`
##     estaba clavado en 1,0 siempre que te movieras y en 0,0 parado: no
##     había mezcla, había un corte con dos valores. Los enemigos lo tenían
##     peor, con su `v / 3,0` (satura a 3,0 m/s y persiguen a 6,0).
##
## (3) El rango del BlendSpace — era lo mismo que (2) por el otro lado: el
##     rango del espacio es correcto (0..1), lo que no cubría la velocidad era
##     la NORMALIZACIÓN. Ahora es `mezcla_por_velocidad(v, stats.vel_mov)`.
##
## (4) La marcha al revés — DESCARTADO, con números y no por copia del
##     bandido. En el clip de caminar el pie recorre su arco hacia el +Z local
##     del modelo (de -0,4449 a +0,2981 respecto de la cadera), y el +Z local
##     es la CARA del modelo (ver `Cuerpo.GIRO_MODELO`), que con el PI de
##     vuelta apunta al -Z del juego, que es donde anda el jugador. La zancada
##     va hacia donde mira. El esqueleto y la malla miran igual.
##
## (5) El pie que patina — CONFIRMADO, y era LA causa. El clip de caminar
##     viaja 1,4264 m/s por su cuenta (zancada 0,7430 m, 2 pasos por ciclo de
##     1,0417 s) y el juego va a 6,0 m/s. A `speed_scale` 1 —como estaba—
##     los pies patinan 4,2 veces. Y no se arregla con un blend: se arregla con
##     el RITMO del clip.
##
## (6) El árbol contra el reproductor — CONFIRMADO, y era un bug aparte: con el
##     árbol activo es él el que escribe las pistas, así que el `play()` del
##     tajo lo pisaba la mezcla al frame siguiente y el tajo no se veía.
##
## (7) Los clips sin bucle — DESCARTADO. `_preparar_clips` marca
##     `LOOP_LINEAR` en idle/walk/attack y `LOOP_NONE` en `die`, y el clip
##     horneado se lleva el bucle puesto.
##
## Qué demuestra este test, y por qué NO alcanza con mirar el código:
##   (a) la mezcla toma valores INTERMEDIOS y es monótona en la velocidad;
##   (b) el clip de caminar viaja a la velocidad REAL: se mide el hueso del pie
##       sobre el esqueleto, no la fórmula;
##   (c) la marcha va hacia donde se desplaza el cuerpo, en números;
##   (d) el tajo sobrevive al árbol.
##
## Correrlo:
##   godot --headless --path . --script res://tests/test_fase70_caminar.gd

const PL: GDScript = preload("res://scripts/player/player.gd")
## El juego corre a esto (`StatBlock` "vel_mov" base). Si cambia, el
## diagnóstico de arriba cambia con él: por eso está en una constante y no
## escrito en los mensajes.
const VEL_JUEGO: float = 6.0
## Margen del invariante de no patinazo. El multiplicador va cuantizado a 0,25
## (ArbolAnimacion.PASO_RITMO), así que el error permitido es medio paso.
const TOL_RITMO: float = 0.125 * ArbolAnimacion.VELOCIDAD_CLIP
## `modelo_escala` de las cinco clases (data/clases.json). El enemigo con modelo
## usa 0,62; el ritmo depende de esto, asi que el test lo declara.
const ESCALA_MODELO: float = 0.9

var _ok: int = 0
var _fallos: int = 0
var _fase_espera: int = 0


func _initialize() -> void:
	print("[TEST] Fase 70 — la caminata: mezcla, ritmo y dirección")


func _process(delta: float) -> bool:
	if _fase_espera > 0:
		_esperar_frames(delta)
		return false
	_test_api()
	_test_invariante_ritmo()
	_test_mezcla_intermedia()
	if _fase_espera == 0:
		_informe()
		_test_zancada_real()
		_test_jugador()
		_test_enemigo()
		_test_tajo()
		_finalizar()
	return false


## (0) La API que se sostiene. Es lo que el bloque 67 se rompió dos veces
## (`AnimationNodeBlend2.blend_amount` y `AnimationNodeTimeScale.scale` no
## existen en 4.7), así que se comprueba contra los parámetros que el propio
## árbol publica, no contra lo que el código cree que escribe.
func _test_api() -> void:
	_chk(ArbolAnimacion.VELOCIDAD_CLIP > 0.0,
		"0: la velocidad del clip es un número medido, no cero",
		"VELOCIDAD_CLIP=%f" % ArbolAnimacion.VELOCIDAD_CLIP)
	# Ni el nodo de blend ni el de tiempo tienen ya las propiedades de 4.3.
	_chk(not (AnimationNodeBlend2.new() as Object).get_property_list().any(
			func(p: Dictionary) -> bool: return str(p.get("name", "")) == "blend_amount"),
		"0: AnimationNodeBlend2 no tiene blend_amount (no se usa)")
	_chk(not (AnimationNodeTimeScale.new() as Object).get_property_list().any(
			func(p: Dictionary) -> bool: return str(p.get("name", "")) == "scale"),
		"0: AnimationNodeTimeScale no tiene scale (no se usa)")


## (b-1) El invariante del ritmo, sobre la fórmula. La forma Medida del
## hueso la hace `_test_zancada_real`; esta es la que hace cheaply y para
## todas las velocidades de golpe.
func _test_invariante_ritmo() -> void:
	var peor: float = 0.0
	var peor_v: float = 0.0
	var v: float = 0.0
	while v <= VEL_JUEGO + 0.001:
		var f: float = ArbolAnimacion.ritmo(v, ESCALA_MODELO)
		# Y que el multiplicador no se dispare ni se hunda.
		_chk(f >= ArbolAnimacion.RITMO_MIN - 0.001 and f <= ArbolAnimacion.RITMO_MAX + 0.001,
			"0: el ritmo de %.2f m/s esta acotado" % v, "ritmo=%f" % f)
		# El invariante solo importa donde el clip entra en juego. Por debajo
		# del umbral la mezcla es idle puro: el pie no toca el suelo, y un
		# multiplicador congelado ahi es lo correcto, no un fallo.
		if v >= ArbolAnimacion.UMBRAL_CAMINAR:
			var err: float = absf(f * ArbolAnimacion.VELOCIDAD_CLIP * ESCALA_MODELO - v)
			if err > peor:
				peor = err
				peor_v = v
		v += 0.25
	_chk(peor <= TOL_RITMO,
		"b: el clip se reproduce a la velocidad real (el pie no patina)",
		"peor error=%.4f m/s a v=%.2f (tolerancia=%.4f, es medio paso de "
		% [peor, peor_v, TOL_RITMO]
		+ "ArbolAnimacion.PASO_RITMO)")
	# Y el caso del bug, dicho con el numero viejo: el multiplicador de antes
	# era 1.0 fijo, o sea el pie a 1,4264 m/s con el cuerpo a 6,0.
	_chk(ArbolAnimacion.ritmo(VEL_JUEGO, ESCALA_MODELO) > 2.5,
		"b: a velocidad de juego el clip va MULTIPLICADO (antes iba a 1.0)",
		"ritmo=%.2f  (con speed_scale 1 el pie iba a %.4f m/s y el cuerpo a %.1f)"
		% [ArbolAnimacion.ritmo(VEL_JUEGO, ESCALA_MODELO),
			ArbolAnimacion.VELOCIDAD_CLIP * ESCALA_MODELO, VEL_JUEGO])


## (a) La mezcla tiene que tomar valores INTERMEDIOS. Este es el test que
## falta: el de la 50 afirmaba "caminando la mezcla va a ~1" y PASABA con el
## bug, porque la mezcla saturada da exactamente 1. Un test que solo mira los
## extremos no puede distinguir "mezclo" de "cambio de clip".
func _test_mezcla_intermedia() -> void:
	var previos: Array[float] = []
	var intermedios: int = 0
	var v: float = 0.0
	while v <= VEL_JUEGO + 0.001:
		var n: float = ArbolAnimacion.mezcla_por_velocidad(v, VEL_JUEGO)
		previos.append(n)
		if n > 0.02 and n < 0.98:
			intermedios += 1
		v += 0.25
	_chk(intermedios >= 4,
		"a: la mezcla toma valores intermedios entre 0 y 1",
		"intermedios=%d de %d muestras" % [intermedios, previos.size()])
	var monotona: bool = true
	for i in range(1, previos.size()):
		if previos[i] < previos[i - 1] - 0.0001:
			monotona = false
	_chk(monotona, "a: la mezcla crece con la velocidad (no da saltos)",
		"valores=%s" % str(previos))
	# Y el caso que estaba roto: 4 m/s NO es lo mismo que 6 m/s.
	_chk(absf(ArbolAnimacion.mezcla_por_velocidad(4.0, VEL_JUEGO)
			- ArbolAnimacion.mezcla_por_velocidad(VEL_JUEGO, VEL_JUEGO)) > 0.2,
		"a: 4 m/s y 6 m/s dan mezclas distintas (ya no satura)",
		"4->%.3f  6->%.3f" % [ArbolAnimacion.mezcla_por_velocidad(4.0, VEL_JUEGO),
			ArbolAnimacion.mezcla_por_velocidad(VEL_JUEGO, VEL_JUEGO)])
	_chk(ArbolAnimacion.mezcla_por_velocidad(0.0, VEL_JUEGO) < 0.001,
		"a: quieto es idle puro")
	_chk(ArbolAnimacion.mezcla_por_velocidad(VEL_JUEGO, VEL_JUEGO) > 0.999,
		"a: a tope es walk puro")


## (b-2) LA MEDICIÓN DE VERDAD: se recorre el esqueleto y se mide cuanto
## avanza el pie. Nada de la fórmula: el numero sale del hueso.
##
## Antes: el clip a `speed_scale` 1 viaja a 1,4264 m/s con el cuerpo a 6,0, así
## que el pie se adelantaba 4,2 veces y el bicho se deslizaba. Después: el pie
## viaja a la velocidad del cuerpo.
func _test_zancada_real() -> void:
	var modelo: Node3D = _modelo_colgado()
	if modelo == null:
		return
	var ap: AnimationPlayer = _buscar_anim(modelo)
	var sk: Skeleton3D = _buscar_hueso(modelo)
	if ap == null or sk == null:
		_chk(false, "b: el modelo de prueba tiene reproductor y esqueleto")
		return
	var crudo: Dictionary = _trayectoria(ap, sk, "walk")
	_chk(not crudo.is_empty() and float(crudo.get("zancada", 0.0)) > 0.05,
		"b: el clip de caminar mueve el pie (no es una pose quieta)",
		"zancada=%.4f m" % float(crudo.get("zancada", 0.0)))
	if crudo.is_empty() or float(crudo["zancada"]) <= 0.0:
		return
	var zancada: float = float(crudo["zancada"])
	var dur: float = float(crudo["duracion"])
	# El invariante, medido: zancada * 2 pasos / duracion == la velocidad a la
	# que el pie tiene que viajar para no patinar. En espacio de esqueleto.
	var natural: float = zancada * 2.0 / dur
	_chk(absf(natural - ArbolAnimacion.VELOCIDAD_CLIP) < 0.02,
		"b: la constante del codigo es la zancada REAL del clip",
		"medida=%.4f m/s  constante=%.4f m/s" % [natural, ArbolAnimacion.VELOCIDAD_CLIP])
	# Y ahora el árbol que el juego USA de verdad: al revés y con el reloj a
	# ritmo.
	var ritmo: float = ArbolAnimacion.ritmo(VEL_JUEGO, ESCALA_MODELO)
	var en_uso: String = _clip_horneado(ap, "walk", ritmo, ESCALA_MODELO)
	_chk(en_uso != "", "b: el arbol de mezcla existe y tiene el clip de caminar")
	if en_uso == "":
		return
	# El clip NO se toca: el ritmo lo pone el reloj del árbol, así que la
	# zancada del clip es exactamente la de antes. Si alguien volviera a
	# "acelerar el clip" reescribiendo el `Animation`, esto lo caza.
	_chk(en_uso == "walk",
		"b: el clip de caminar no se reescribe (el ritmo va en el reloj)",
		"el arbol esta usando '%s'" % en_uso)
	_chk(ap.get_animation("walk").loop_mode == Animation.LOOP_LINEAR
			and is_equal_approx(ap.get_animation("walk").length, dur),
		"b: el clip de caminar cicla y no se ha tocado",
		"loop_mode=%d dur=%.4f (esperado %.4f)" % [ap.get_animation("walk").loop_mode,
				ap.get_animation("walk").length, dur])
	# LA MEDICIÓN QUE IMPORTA, y con el árbol conduciendo: el pie tiene que
	# viajar en el MUNDO a la misma velocidad a la que el cuerpo se desplaza.
	# `zancada` viene en unidades de esqueleto, así que al mundo va por
	# `modelo_escala`; y un ciclo son dos zancadas.
	var con_arbol: Dictionary = _tiquera_arbol(ap, sk)
	_chk(not con_arbol.is_empty(), "b: el arbol mueve el esqueleto (root_node bien)")
	if con_arbol.is_empty():
		return
	var largo_ciclo: float = dur / ritmo
	var pie: float = float(con_arbol["zancada"]) * ESCALA_MODELO * 2.0 / largo_ciclo
	_chk(pie >= VEL_JUEGO - TOL_RITMO and pie <= VEL_JUEGO + TOL_RITMO,
		"b: el pie viaja a la velocidad del cuerpo (medido con el ARBOL)",
		"pie=%.4f m/s  cuerpo=%.4f m/s  (zancada=%.4f u ciclo=%.4f s ritmo=%.2f "
		% [pie, VEL_JUEGO, float(con_arbol["zancada"]), largo_ciclo, ritmo]
		+ "escala=%.2f)" % ESCALA_MODELO)
	# Y el patinaje, que es el sintoma que se ve: en un ciclo el cuerpo avanza
	# `v * duracion_del_ciclo` y los pies cubren `2 * zancada`. Lo que sobra es
	# desliz. (Son DOS zancadas por ciclo: contar una sola da 65 cm de patinaje
	# falso con el arreglo ya puesto, que es como se sabe que el número está bien.)
	var patinaje: float = (VEL_JUEGO * largo_ciclo
			- 2.0 * float(con_arbol["zancada"]) * ESCALA_MODELO) * 100.0
	_chk(absf(patinaje) < 10.0,
		"b: el patinaje por ciclo esta por debajo de 10 cm",
		"patinaje=%.1f cm por ciclo" % patinaje)


## (c) LA DIRECCIÓN, en números y para el JUGADOR (no por copia del bandido).
## El pie tiene que decidedly el arco hacia la CARA del modelo, y la cara
## tiene que apuntar donde el cuerpo se desplaza.
func _test_jugador() -> void:
	var p: Player = _jugador()
	if p == null:
		return
	var modelo: Node3D = p.get_node_or_null("Modelo") as Node3D
	var ap: AnimationPlayer = _buscar_anim(modelo)
	var sk: Skeleton3D = _buscar_hueso(modelo) if modelo != null else null
	if ap == null or sk == null:
		_chk(false, "c: el jugador trae modelo con esqueleto")
		return
	# (c0) El ciclo CRUDO del pack está espejado: en el punto más bajo del pie
	# (el apoyo) el pie avanza hacia DELANTE. En una marcha tiene que ir hacia
	# ATRÁS, porque es el cuerpo el que pasa por encima de él. Eso es un
	# moonwalk, y queda constancia de que se midió y no se supuso.
	var crudo: Dictionary = _trayectoria(ap, sk, "walk")
	var dz_crudo: float = float(crudo.get("pie_dz", 0.0))
	_chk(dz_crudo > 0.1,
		"c: el ciclo crudo del pack esta espejado (de ahi el play_mode al reves)",
		"en el apoyo el pie va %+.4f u (hacia delante = al reves)" % dz_crudo)
	# (c1) Y el ÁRBOL, que es lo que ejecuta el juego, da el pie hacia atrás.
	#
	# Esto tiene que medirse por el árbol y no con `ap.seek()` sobre el clip,
	# porque la inversión NO está en el clip: está en el `play_mode` del nodo
	# del árbol. Un `seek` no la ve, y mediría el ciclo crudo otra vez — que es
	# como un test puede pasar mirando justo lo que no se está ejecutando.
	#
	# Y necesita el `root_node` bien puesto: sin él el esqueleto no se mueve,
	# `pie_dz` da 0, y el test passaría sin comprobar nada.
	if _clip_horneado(ap, "walk", ArbolAnimacion.ritmo(VEL_JUEGO, ESCALA_MODELO),
			ESCALA_MODELO) == "":
		_chk(false, "c: hay clip de caminar para mirar la direccion")
		return
	var con_arbol: Dictionary = _tiquera_arbol(ap, sk)
	_chk(not con_arbol.is_empty(), "c: el arbol mueve el esqueleto (root_node bien)")
	if con_arbol.is_empty():
		return
	var dz: float = float(con_arbol["pie_dz"])
	_chk(dz < -0.1,
		"c: con el ARBOL conduciendo, en el APOYO el pie va atras (no moonwalk)",
		"en el apoyo el pie va %+.4f u (si fuera positivo, camina de espaldas)" % dz)
	_chk(float(con_arbol["zancada"]) > 0.5,
		"c: y el pie da la zancada entera (no se pierde al invertir)",
		"zancada por el arbol=%.4f u" % float(con_arbol["zancada"]))
	# (c2) y la cara del modelo apunta donde el jugador se desplaza
	var destino: Vector3 = Vector3(0.0, 0.0, -1.0) * 40.0
	var intent: Intent = p.intent
	intent.move_dir = Vector2(0.0, 1.0)  # "adelante" de la camara
	intent.destino = destino
	intent.tiene_destino = true
	p.velocity = destino - p.global_position
	p.rotation.y = 0.0
	for i in range(3):
		p.call("_actualizar_animacion", 1.0 / 60.0)
	_chk(is_equal_approx(modelo.rotation.y, Cuerpo.GIRO_MODELO),
		"c: el modelo sigue con la vuelta de GIRO_MODELO")
	var cara: Vector3 = modelo.global_transform.basis.z
	var anda: Vector3 = -p.global_transform.basis.z
	_chk(Vector3(cara.x, 0.0, cara.z).normalized().dot(
			Vector3(anda.x, 0.0, anda.z).normalized()) > 0.99,
		"c: la cara del modelo mira donde mira el jugador")
	# (c3) la mezcla YA NO satura con el jugador en movimiento
	var tree: AnimationTree = ap.get_node_or_null(
			NodePath(ArbolAnimacion.NOMBRE_ARBOL)) as AnimationTree
	_chk(tree != null, "c: el jugador tiene arbol de animacion")
	if tree == null:
		return
	p.velocity = Vector3(3.0, 0.0, 0.0)
	p.call("_actualizar_animacion", 1.0 / 60.0)
	var b3: float = float(tree.get("parameters/locomocion/blend_position"))
	p.velocity = Vector3(VEL_JUEGO, 0.0, 0.0)
	p.call("_actualizar_animacion", 1.0 / 60.0)
	var b6: float = float(tree.get("parameters/locomocion/blend_position"))
	_chk(b3 > 0.05 and b3 < 0.95,
		"c: a media velocidad la mezcla es intermedia (no 1.0)",
		"blend_position=%.4f a 3 m/s" % b3)
	_chk(b6 > b3 + 0.2, "c: y a tope sube hacia walk",
		"3 m/s->%.4f  6 m/s->%.4f" % [b3, b6])


## El enemigo tenía la misma saturación, con un 3,0 de adivinza. Mismo
## arquetipo, misma comprobación.
func _test_enemigo() -> void:
	var ruta: String = "res://scenes/enemy/enemigo.tscn"
	if not ResourceLoader.exists(ruta):
		_chk(true, "d: sin escena de enemigo, la parte se salta")
		return
	var e: Node3D = (load(ruta) as PackedScene).instantiate() as Node3D
	root.add_child(e)
	_fase_espera = 2
	_test_enemigo_tras_crecer(e)


func _test_enemigo_tras_crecer(e: Node3D) -> void:
	var ap: AnimationPlayer = _buscar_anim(e)
	if ap == null:
		_chk(true, "d: el enemigo de prueba no trae modelo, la parte se salta")
		e.queue_free()
		return
	_chk(bool(e.get("stats") != null), "d: el enemigo tiene stats")
	var v_max: float = float((e.get("stats") as StatBlock).vel_mov)
	var mitad: float = ArbolAnimacion.mezcla_por_velocidad(v_max * 0.5, v_max)
	_chk(mitad > 0.2 and mitad < 0.8,
		"d: el enemigo mezcla en el rango de SU velocidad, no en el de otro",
		"v_max=%.2f  a la mitad=%.4f" % [v_max, mitad])
	# Y con el enemigo en movimiento la mezcla es intermedia.
	e.set("velocity", Vector3(v_max * 0.5, 0.0, 0.0))
	e.set("estado", 1)
	e.call("_actualizar_mezcla")
	var tree: AnimationTree = ap.get_node_or_null(
			NodePath(ArbolAnimacion.NOMBRE_ARBOL)) as AnimationTree
	if tree != null:
		var b: float = float(tree.get("parameters/locomocion/blend_position"))
		_chk(b > 0.05 and b < 0.95,
			"d: el enemigo a media velocidad mezcla de verdad",
			"blend_position=%.4f" % b)
	e.queue_free()


## (6) El tajo tiene que SOBREVIVIR al arbol. Con el árbol activo es él el que
## escribe las pistas del esqueleto, así que si no se suelta, el `play()` del
## tajo lo pisa la mezcla al frame siguiente y el tajo no se ve. Esto ya estaba
## roto y ningún test lo miraba.
func _test_tajo() -> void:
	var p: Player = _jugador()
	if p == null:
		return
	p.aplicar_clase(_clase_con_modelo())
	var ap: AnimationPlayer = _buscar_anim(p.get_node_or_null("Modelo") as Node3D)
	if ap == null:
		_chk(false, "e: el jugador tiene reproductor para el tajo")
		return
	# Primero camina: eso crea y ACTIVA el arbol.
	p.velocity = Vector3(VEL_JUEGO, 0.0, 0.0)
	p.call("_actualizar_animacion", 1.0 / 60.0)
	var tree: AnimationTree = ap.get_node_or_null(
			NodePath(ArbolAnimacion.NOMBRE_ARBOL)) as AnimationTree
	if tree == null:
		_chk(false, "e: hay arbol antes del tajo")
		return
	_chk(tree.active, "e: caminando el arbol manda")
	# Ahora el tajo.
	p.set("_t_swing", 0.3)
	p.call("_actualizar_animacion", 1.0 / 60.0)
	_chk(str(ap.current_animation) == "attack",
		"e: el tajo se reproduce (el arbol no lo pisa)", "reproduciendo '%s'"
		% str(ap.current_animation))
	_chk(not tree.active, "e: y el arbol se suelta mientras dura el tajo")
	# Al volver a caminar, el tajo puede volver a dispararse.
	p.set("_t_swing", 0.0)
	p.velocity = Vector3(VEL_JUEGO, 0.0, 0.0)
	p.call("_actualizar_animacion", 1.0 / 60.0)
	_chk(tree.active, "e: al volver a caminar el arbol vuelve a mandar")
	p.set("_t_swing", 0.3)
	p.call("_actualizar_animacion", 1.0 / 60.0)
	_chk(str(ap.current_animation) == "attack",
		"e: y el tajo se puede repetir (no se queda clavado)")


## Los mismos numeros que pide el informe de animación, calculados aquí desde
## el mismo esqueleto, para que se puedan comparar sin creer a nadie:
## patinaje por ciclo en centímetros, y hacia dónde va el pie en el contacto.
func _informe() -> void:
	# Su propio jugador: el informe corre antes que los tests, y si buscara una
	# entidad ya montada no encontraria ninguna todavia.
	var modelo: Node3D = _modelo_colgado()
	if modelo == null:
		return
	var ap: AnimationPlayer = _buscar_anim(modelo)
	var sk: Skeleton3D = _buscar_hueso(modelo)
	if ap == null or sk == null:
		return
	var horneado: String = _clip_horneado(ap, "walk",
			ArbolAnimacion.ritmo(VEL_JUEGO, ESCALA_MODELO), ESCALA_MODELO)
	if horneado == "":
		return
	var dur: float = ap.get_animation("walk").length
	var antes: Dictionary = _trayectoria(ap, sk, "walk")
	# DESPUES, por el árbol: es lo que el juego ejecuta de verdad (el `play_mode`
	# al revés y el clip a ritmo). Medido con `seek` saldría el ciclo crudo y el
	# informe mentiría justo en lo que se viene a mirar.
	var ahora: Dictionary = _tiquera_arbol(ap, sk)
	if ahora.is_empty():
		return
	var v_clip: float = ArbolAnimacion.VELOCIDAD_CLIP * ESCALA_MODELO
	# El clip NO se reescribe: lo que se acorta es el TIEMPO en que el árbol lo
	# reproduce. El ciclo, en tiempo de reloj, pasa de 1,042 s a 1,042/ritmo.
	var f: float = ArbolAnimacion.ritmo(VEL_JUEGO, ESCALA_MODELO)
	var dur_ciclo: float = dur / f
	var zancada: float = float(antes["zancada"]) * ESCALA_MODELO
	# ANTES el ciclo era el CRUDO (el clip a `speed_scale` 1) y DESPUÉS el del
	# árbol a ritmo. Comparar los dos con el mismo ciclo no dice nada: por eso el
	# avance de cada uno se multiplica por SU ciclo.
	var avance_antes: float = VEL_JUEGO * dur
	var avance_despues: float = VEL_JUEGO * dur_ciclo
	print("  ciclo del clip en reloj real (s)         %.4f" % dur_ciclo)
	print("[INFORME] res://models/clase_*.glb")
	print("  clip walk (s)                        %.3f" % dur)
	print("  escala del modelo                    %.3f" % ESCALA_MODELO)
	print("  velocidad natural del clip (m/s)     %.3f" % v_clip)
	print("  velocidad del juego (m/s)            %.3f" % VEL_JUEGO)
	print("  ritmo que cancela el patinaje        %.2f" % f)
	print("  zancada del pie por ciclo (m)        %.3f" % zancada)
	# El patinaje: en un ciclo el cuerpo avanza `v * duracion` y los pies
	# cubren `2 * zancada` (DOS pisadas por ciclo, no una).
	print("  patinaje por ciclo ANTES (cm)        %.1f  HORRIBLE"
		% ((avance_antes - 2.0 * zancada) * 100.0))
	print("  patinaje por ciclo DESPUES (cm)      %.1f"
		% ((avance_despues - 2.0 * float(ahora["zancada"]) * ESCALA_MODELO) * 100.0))
	print("  pie en contacto ANTES (m, +adelante) %+.3f  %s"
		% [float(antes["pie_dz"]) * ESCALA_MODELO,
			"AL_REVES" if float(antes["pie_dz"]) > 0.0 else "bien"])
	print("  pie en contacto DESPUES (m)         %+.3f  %s"
		% [float(ahora["pie_dz"]) * ESCALA_MODELO,
			"AL_REVES" if float(ahora["pie_dz"]) > 0.0 else "bien"])
	# La PRIMERA velocidad a la que la mezcla se queda en 1,0 para siempre: con
	# la normalizacion vieja era 0,90 m/s, o sea que el 93% del juego entero
	# iba en blend puro.
	var sat: float = -1.0
	var v: float = 0.0
	while v <= VEL_JUEGO + 0.001:
		if ArbolAnimacion.mezcla_por_velocidad(v, VEL_JUEGO) >= 0.999 \
				and sat < 0.0:
			sat = v
		v += 0.05
	print("  blend se satura desde (m/s)          %.2f" % sat)
	print("  blend_position caminando lento       %.3f"
		% ArbolAnimacion.mezcla_por_velocidad(1.0, VEL_JUEGO))
	print("  blend_position trotando (3 m/s)      %.3f"
		% ArbolAnimacion.mezcla_por_velocidad(3.0, VEL_JUEGO))


# ---------------------------------------------------------------- medidas


## Recorre un ciclo y devuelve lo que hay que mirar del pie: su altura (para
## encontrar el apoyo) y su desplazamiento antero-posterior a lo largo de él.
##
## Se mide con `get_bone_global_pose` SIN multiplicar por
## `sk.global_transform`, o sea en el espacio del ESQUELETO. Importa, y no por
## gusto: si se le multiplica el transform global, la vuelta de
## `Cuerpo.GIRO_MODELO` (que invierte el eje Z) y la escala del modelo entran en
## la medida, y el signo del desplazamiento antero-posterior sale del reves y
## la zancada sale en unidades equivocadas. "Global" en un hueso significa
## global DENTRO del esqueleto, no en el mundo.
##
## Y no se puede usar `get_bone_pose`: esa devuelve la pose de REPOSO, y en
## este rig las pistas de los huesos son de rotacion, no de posicion. Medida
## con `get_bone_pose` la zancada da 0,0000 y el test pasa sin comprobar nada.
func _trayectoria(ap: AnimationPlayer, sk: Skeleton3D, clip: String) -> Dictionary:
	if not ap.has_animation(clip):
		return {}
	var dur: float = ap.get_animation(clip).length
	if dur <= 0.0:
		return {}
	ap.play(clip)
	var i_pie: int = sk.find_bone("Foot.L")
	var i_cad: int = sk.find_bone("Hips")
	if i_pie < 0 or i_cad < 0:
		return {}
	var ys: Array[float] = []
	var zs: Array[float] = []
	for i in range(97):
		ap.seek(dur * i / 96.0, true)
		ys.append(sk.get_bone_global_pose(i_pie).origin.y)
		zs.append(sk.get_bone_global_pose(i_pie).origin.z
				- sk.get_bone_global_pose(i_cad).origin.z)
	# El apoyo es el punto más bajo. Se mira el desplazamiento a su alrededor
	# (±2 muestras ≈ ±4% del ciclo) para no depender de una sola.
	# Ventana de ±8% del ciclo. Angosta (±2 muestras de 97) el resultado
	# depende de la curvatura local y sale unstable; ancha promedia la fase
	# entera y el signo es el que es.
	var i_apoyo: int = ys.find(ys.min())
	var ini: int = maxi(0, i_apoyo - 8)
	var fin: int = mini(96, i_apoyo + 8)
	# Y que la zancada exista de verdad: sin esto el criterio de arriba no
	# distinguiría un ciclo derecho de un personaje con las piernas tiesas.
	var zancada: float = zs.max() - zs.min()
	return {
		"altura_apoyo": ys.min(),
		"t_apoyo": dur * i_apoyo / 96.0,
		# Negativo = el cuerpo pasa por encima del pie = el ciclo va bien.
		"pie_dz": zs[fin] - zs[ini],
		"zancada": zancada,
		"duracion": dur,
	}


## Recorre un ciclo con el RELOJ DEL ÁRBOL y mide el pie. Esto es lo que hace
## el juego de verdad, y solo se puede medir porque el árbol tiene el
## `root_node` bien puesto: con el de por defecto (`".."`) ninguna pista
## resuelve, el esqueleto no se mueve, y cualquier medición da cero y el test
## pasa sin comprobar nada. Por eso el test mide POR AQUÍ y no solo sobre el
## `Animation` con `seek`.
func _tiquera_arbol(ap: AnimationPlayer, sk: Skeleton3D) -> Dictionary:
	var largo: float = 0.0
	var tree: AnimationTree = ap.get_node_or_null(
			NodePath(ArbolAnimacion.NOMBRE_ARBOL)) as AnimationTree
	if tree == null:
		return {}
	tree.set("parameters/locomocion/blend_position", 1.0)
	tree.active = true
	# El largo sale del clip que el árbol está USANDO, no del crudo: el árbol
	# apunta al clip a ritmo, que es `factor` veces más corto. Medir un ciclo
	# del crudo sobre un clip horneado mete 4,75 ciclos en la "ventana", la
	# ventana se come casi un ciclo entero y el signo del `dz` sale sin sentido.
	var bs: AnimationNodeBlendSpace1D = (tree.tree_root as AnimationNodeBlendTree
			).get_node("locomocion") as AnimationNodeBlendSpace1D
	var nodo: AnimationNodeAnimation = bs.get_blend_point_node(1) as AnimationNodeAnimation
	if nodo == null or not ap.has_animation(nodo.animation):
		return {}
	largo = ap.get_animation(nodo.animation).length
	# 480 Hz: un ciclo a 6 m/s dura 0,22 s, o sea ~105 muestras. A 240 Hz eran
	# 52 y la ventana de ±8% se comía parte de la curvatura local.
	# Se avanza por `ArbolAnimacion.avanzar`, que es la MISMA llamada que hace
	# el juego cada frame con la velocidad real. Si el test se moviese por su
	# cuenta (`tree.advance`) estaría midiendo un reloj que el juego no usa.
	var f: float = ArbolAnimacion.ritmo(VEL_JUEGO, ESCALA_MODELO)
	var dt_real: float = 1.0 / 240.0
	var n: int = maxi(2, int(largo / (dt_real * f)))
	var ys: Array[float] = []
	var zs: Array[float] = []
	for i in range(n + 1):
		ArbolAnimacion.avanzar(ap, dt_real, VEL_JUEGO, ESCALA_MODELO)
		ys.append(sk.get_bone_global_pose(sk.find_bone("Foot.L")).origin.y)
		zs.append(_pie_menos_cadera(sk))
	return _resumen(ys, zs, n, largo)


## Resumen de una trayectoria: apoyo, hacia donde va el pie en el apoyo, y
## zancada. La ventana del `dz` es de ±8% del ciclo porque angosta el resultado
## depende de la curvatura local y sale inestable.
func _resumen(ys: Array[float], zs: Array[float], n: int, largo: float) -> Dictionary:
	if ys.is_empty():
		return {}
	var i_apoyo: int = ys.find(ys.min())
	var ini: int = maxi(0, i_apoyo - maxi(2, int(n * 0.08)))
	var fin: int = mini(n, i_apoyo + maxi(2, int(n * 0.08)))
	return {
		"altura_apoyo": ys.min(),
		"t_apoyo": largo * i_apoyo / maxf(float(n), 1.0),
		# Negativo = el cuerpo pasa por encima del pie = el ciclo va bien.
		"pie_dz": zs[fin] - zs[ini],
		"zancada": zs.max() - zs.min(),
		"duracion": largo,
	}


func _pie_menos_cadera(sk: Skeleton3D) -> float:
	var i: int = sk.find_bone("Foot.L")
	var j: int = sk.find_bone("Hips")
	if i < 0 or j < 0:
		return 0.0
	var p: Vector3 = sk.get_bone_global_pose(i).origin
	var c: Vector3 = sk.get_bone_global_pose(j).origin
	return p.z - c.z


## El clip que el ÁRBOL está usando. No se construye a mano: se le pregunta al
## árbol, que es quien decide. Y el ritmo ya no va dentro del clip (el árbol va
## en modo manual y su reloj lo pone `ArbolAnimacion.avanzar`), así que lo
## único que hay que comprobar es que el árbol existe y que su blend tiene los
## dos clips.
func _clip_horneado(ap: AnimationPlayer, base: String, factor: float,
		escala: float) -> String:
	# Se pide por el camino REAL del juego (que es el que monta el árbol con el
	# `root_node` bien) y se devuelve el clip que ha elegido. Si `mezclar`
	# dejara de montar el árbol, esto no lo taparía.
	ArbolAnimacion.mezclar(ap, "idle", base, 1.0,
			factor * ArbolAnimacion.VELOCIDAD_CLIP * escala, escala)
	return ArbolAnimacion.clip_en_uso(ap)


# ------------------------------------------------------------------ chores


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] " + nombre + ("" if detalle == "" else "  <-- " + detalle))


func _jugador() -> Player:
	var p: Player = PL.new()
	p.fijar_identidad("H", _clase_con_modelo())
	p.aplicar_clase(_clase_con_modelo())
	root.add_child(p)
	p.velocity = Vector3.ZERO
	return p


func _modelo_colgado() -> Node3D:
	var p: Player = _jugador()
	if p == null:
		return null
	return p.get_node_or_null("Modelo") as Node3D


func _clase_con_modelo() -> String:
	var datos: Dictionary = _json("res://data/clases.json")
	var clases: Dictionary = datos.get("clases", {}) as Dictionary
	for id in clases:
		var c: Dictionary = clases[id] as Dictionary
		var ruta: String = str(c.get("modelo", ""))
		if ruta != "" and ResourceLoader.exists(ruta):
			return str(id)
	return "guerrero"


func _json(ruta: String) -> Dictionary:
	var texto: String = FileAccess.get_file_as_string(ruta)
	if texto.is_empty():
		return {}
	var v: Variant = JSON.parse_string(texto)
	return v if v is Dictionary else {}


func _buscar_anim(n: Node) -> AnimationPlayer:
	if n == null:
		return null
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var h: AnimationPlayer = _buscar_anim(c)
		if h != null:
			return h
	return null


func _buscar_hueso(n: Node) -> Skeleton3D:
	if n == null:
		return null
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var h: Skeleton3D = _buscar_hueso(c)
		if h != null:
			return h
	return null


func _esperar_frames(delta: float) -> void:
	_fase_espera -= 1
	if delta < 0.0:
		return


func _finalizar() -> void:
	print("[TEST] Fase 70 — %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)
