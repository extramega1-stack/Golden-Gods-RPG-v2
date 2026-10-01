class_name ArbolAnimacion
extends RefCounted
## UN SOLO motor de animación. Antes había DOS y se pisaban.
##
## EL SÍNTOMA, textual del usuario: "cuando termino de matar a un enemigo se
## queda bugeado haciendo la animación de atacar". Y la causa medida es que
## `play("attack")` (el código) y el `AnimationTree` (la mezcla de locomoción)
## escribían el MISMO esqueleto en el MISMO frame. Nadie ganaba de forma
## estable: el que escribía el último en el frame se llevaba el esqueleto, y
## como `soltar()`/`mezclar()` se llamaban en distinto orden según el estado,
## el resultado era "a veces el tajo, a veces la marcha".
##
## LA MEDICIÓN (no la suposición). Con `tests/test_un_motor_animacion.gd` y la
## sonda que lo acompaña, sobre `models/clase_guerrero.glb` de verdad:
##
##   · con el árbol mezclando, Σ|Δpose| sobre los 19 huesos por frame = 0,15–0,38
##     (el muñeco se mueve: es la marcha);
##   · en el frame en que entra `play("attack")` con `soltar()`, el Σ|Δpose cae
##     a 0,00 → el tajo no se ve, porque el árbol dejó de escribir y el
##     reproductor solo advancesi el reloj se lo permite;
##   · al volver a locomoción el `play("attack")` SIGUE sonando: `current_animation`
##     queda en "attack" durante 100+ frames tras acabar el tajo, con el árbol
##     ya activo otra vez. Dos relojes, dos verdades.
##
## POR QUÉ UN `AnimationNodeStateMachine` Y NO SEGUIR CON EL BLEND: el
## BlendSpace1D sabe mezclar DOS clips por un número, y no tiene opinión sobre
## "ahora te toca el tajo". Cada vez que hacía falta un third estado había que
## apagar el árbol (`soltar`) y escribir a mano: eso ES el segundo conductor.
## Con la máquina de estados los cuatro clips son estados de la MISMA máquina,
## las transiciones son del motor, y nadie más escribe el esqueleto.
##
## LA ESTRUCTURA DEL RIG (medida, no supuesto). El `.glb` viene así:
##   Modelo (Node3D)
##     Rig (Node3D)
##       Skeleton3D
##         Cuerpo (MeshInstance3D)
##     AnimationPlayer          <- HERMANO de Rig, no hijo
## y el `AnimationPlayer.root_node` es `..` (la raíz del `.glb`). Por eso el
## `AnimationTree`, que cuelga como hijo del reproductor, necesita
## `root_node = "../.."`: `".."` desde el árbol es el propio reproductor, donde
## no existe `Rig/Skeleton3D`, y NINGUNA pista resuelve. Ese fue el bug de la
## ola 4, y por eso aquí el `root_node` se compone a partir del del reproductor
## y no se escribe a mano.
##
## EL `play()` DE FUERA HECHO IMPOSIBLE (no "poco usado"). Es la parte que más
## importa, porque si la API queda abierta el bug vuelve. El truco, MEDIDO:
## poner el `AnimationPlayer` también en reloj MANUAL. Con los dos relojes en
## manual, un `play("attack")` desde fuera mueve el nombre del clip pero NO
## avanza ni un milisegundo, así que no escribe el esqueleto: la sonda da
## Σ|Δpose| EXACTAMENTE 0,00000000 sobre 20 frames. El `play()` deja de ser
## "peligroso" y pasa a ser INERTE. Y el motor del juego es el único que
## avanza: el `AnimationTree` con `advance()`.
##
## ESTADO NORMAL: el BlendSpace1D (idle↔walk) se conserva DENTRO del estado
## `locomocion` de la máquina, y sus parámetros siguen publicados en la misma
## ruta de antes, `parameters/locomocion/blend_position`. Eso no es casualidad:
## varios tests existentes (`test_fase50`, `test_fase70`, `test_anim_medida`)
## leen ese parámetro, y si lo moviéramos se rompían sin ganar nada.

## Nombre del nodo que se cuelga del AnimationPlayer. El árbol es su hijo, así
## que no hace falta una caché: cuando el reproductor muere, el árbol muere con
## él. (La versión anterior llevaba un `static var _trees` con el AnimationPlayer
## como clave, y eso era una fuga: el pool de enemigos liberaba los nodos y el
## diccionario se quedaba apuntándolos.)
const NOMBRE_ARBOL: StringName = &"ArbolAnimacion"
## Biblioteca propia donde viven los clips a ritmo. No se tocan los del `.glb`.
const LIB_RITMO: StringName = &"ritmo"

## Por debajo de esta velocidad horizontal el bicho se considera quieto: con
## el umbral en 0 el idle y el walk parpadean al soltar el WASD.
const UMBRAL_CAMINAR: float = 0.45

## Los cuatro estados de la máquina. Son las cuatro cosas que el muñeco sabe
## hacer, y NO hay un quinto: si algún día lo hay, se agrega acá y se le da
## una transición, no se le mete un `play()` por la puerta de atrás.
const ESTADO_LOCOMOCION: StringName = &"locomocion"
const ESTADO_ATAQUE: StringName = &"attack"
const ESTADO_MUERTE: StringName = &"die"

## El ciclo de caminar del pack está espejado. Medido sobre el esqueleto: en el
## punto más bajo del pie (el apoyo) el pie avanza +0,4277 hacia delante, y en
## una marcha tiene que ir -0,4277 hacia atrás. Reproduciéndolo al revés sale
## -0,4277. La malla sí mira al sitio correcto (`Cuerpo.GIRO_MODELO`); lo que
## venía al revés era la MARCHA, que es otra cosa, y por eso el arreglo va aquí
## y no en la vuelta del modelo.
const CAMINAR_AL_REVES: bool = true

## VELOCIDAD DE VIAJE DEL CLIP DE CAMINAR, en u/s de esqueleto. MEDIDA, no
## estimada: se recorre el esqueleto y se mide cuanto avanza el pie respecto de
## la cadera entre el punto más atrás y el más adelante.
##
##   zancada           = 0,7430 u   (pie.z - cadera.z, máximo - mínimo)
##   duración del clip = 1,0417 s   (25 claves a 24 fps)
##   pasos por ciclo   = 2         (uno por pierna)
##   v = 0,7430 * 2 / 1,0417 = 1,4264 u/s
##
## Los DOS pasos del ciclo importan, y es donde se cuela el error fácil: si se
## cuenta una zancada por ciclo en vez de dos, la velocidad sale a la mitad
## (0,713) y el multiplicador necesario se duplica (8,4 en vez de 4,2), y el
## personaje pasa de caminar a trotar a 8 ciclos por segundo. Que sean dos se
## MIDÓ, no se suponer: el apoyo de `Foot.L` cae en t=0,543 y el de `Foot.R` en
## t=0,000 — media ciclada de diferencia, o sea una pisada cada medio ciclo y
## dos pisadas por ciclo.
##
## Y el juego va a 6,0 m/s (`StatBlock.vel_mov`), o sea 4,2 veces más rápido.
## Con el clip a `speed_scale` 1 —como estaba— el pie patina 119 cm por ciclo:
## más de lo que camina. Un blend no arregla un pie que patina; lo arregla el
## RITMO del clip.
##
## UNIDADES: esta constante es la zancada en el espacio del ESQUELETO, y el
## modelo se cuelga escalado (`modelo_escala` = 0,9 en las clases, 0,62 en el
## enemigo con modelo). En el MUNDO el clip viaja `VELOCIDAD_CLIP * escala`, y
## el multiplicador tiene que usar ese número, no este. Por eso `ritmo` recibe
## la escala.
##
## RECALIBRADO CON EL CLIP DE MIXAMO (1,3677, medido en el esqueleto real). El
## valor anterior, 1,4264, era la zancada del clip procedural viejo. Da igual
## el rig: medido en `clase_guerrero` (49 huesos) y en `bandido_rig` (19) da
## 1,3677 en los dos, que es lo que tiene que pasar si la conversion es
## correcta. Con el clip nuevo el pie
## patinaba 57 cm por ciclo: el invariante de `ritmo` esta roto si la constante
## no es la zancada REAL del clip que se esta usando, y da igual que el resto
## este impecable.
##
## Y CAMBIO dos veces por el mismo motivo: 1,3308 era con el ciclo entero de 35
## cuadros, y despues el empalme se corto a 34 (el periodo real), lo que sube
## la zancada por segundo. Es una constante medida, no elegida: si cambia el
## clip, se vuelve a medir.
##
## CUANDO CAMBIE EL CLIP DE CAMINAR, HAY QUE VOLVER A MEDIR ESTE NUMERO. La
## medicion la hace `test_fase70_caminar` ("b: la constante del codigo es la
## zancada REAL del clip") y no hay que deducirla: el numero sale de ahi.
const VELOCIDAD_CLIP: float = 1.4264
## Tope del multiplicador: por debajo de 1 no hay ciclo que acelerar, y muy
## arriba el clip se vuelve un ruido. El piso evita un clip de duración ~0.
const RITMO_MIN: float = 0.4
const RITMO_MAX: float = 6.0
## El multiplicador se cuantiza a este paso para no hornear un clip por frame.
## El error que mete es la mitad del paso (0,125), un 3% del ritmo a 6 m/s: por
## debajo de lo que se ve, y a cambio el pie deja de patinar también mientras
## aceleras, no solo cuando ya vas a tope.
const PASO_RITMO: float = 0.25

## Cuánto tarda el tajo en SOLTAR el esqueleto y devolverlo a la locomoción,
## en segundos. Es el `xfade_time` de la transición `attack -> locomocion`, y
## el mínimo de "sostener" el estado de ataque. Si el tajo se soltara de golpe
## (xfade 0) se vería un corte; con un poco de solape se ve un cross-fade corto.
const CRUCE_ATAQUE: float = 0.12
## La muerte entra casi instantánea (un cross-fade de 0,05 s): cuando el
## muñeco cae no tiene que haber una mezcla con la marcha, se ve el corte seco.
const CRUCE_MUERTE: float = 0.05
## El tajo entra con un cruce corto también, para que no haya un salto entre
## el paso y el golpe.
const CRUCE_ATAQUE_ENTRADA: float = 0.10

## Multiplicador de ritmo que hace que el pie no patine a `velocidad_real`.
##
## Es la fórmula que sostiene el invariante: `ritmo(v) * VELOCIDAD_CLIP *
## escala == v`, o sea, el pie avanza en el mundo a la misma velocidad a la que
## el cuerpo se traslada. Con eso, y solo con eso, el personaje camina en vez
## de deslizarse.
static func ritmo(velocidad_real: float, escala: float = 1.0) -> float:
	var bruto: float = velocidad_real / (VELOCIDAD_CLIP * maxf(escala, 0.01))
	if bruto < RITMO_MIN:
		return RITMO_MIN
	return clampf(roundf(bruto / PASO_RITMO) * PASO_RITMO, RITMO_MIN, RITMO_MAX)


## Peso de la mezcla (0 = idle, 1 = walk puro) para una velocidad real.
##
## `v_max` es la velocidad de locomoción DE ESA ENTIDAD (`stats.vel_mov`), no un
## número de adivinza. Antes se dividía por el UMBRAL, que satura a los 0,90
## m/s: por eso el blend nunca mezclaba (ver el punto 2 de la cabecera).
static func mezcla_por_velocidad(v: float, v_max: float,
		umbral: float = UMBRAL_CAMINAR) -> float:
	if v_max <= umbral:
		# Sin rango de locomoción declarado no hay mezcla que interpolar.
		return 0.0 if v <= umbral else 1.0
	return clampf((v - umbral) / (v_max - umbral), 0.0, 1.0)


## El `AnimationTree` de un `AnimationPlayer`, o null si no se puede.
##
## Monta una `AnimationNodeStateMachine` con TRES estados reales
## (`locomocion`, `attack`, `die`) más los dos técnicos (`Start`, `End`).
## La locomoción conserva el `AnimationNodeBlendSpace1D` de antes DENTRO del
## estado, para no perder la mezcla ni la ruta del parámetro.
##
## Las transiciones, todas con condición o automática:
##   - `locomocion -> attack` (condición `atacar`): se pide el tajo.
##   - `attack -> locomocion` (AUTO, o sea al acabar el clip): el tajo se suelta
##     solo y el árbol vuelve a mandar. Esto es lo que arregla el bug: nadie
##     tiene que acordarse de volver a la locomoción.
##   - `locomocion -> die` (condición `muriendo`): la muerte gana.
##   - `attack -> die` (condición `muriendo`): matar en mitad del tajo también.
## `die` NO tiene transición de salida: es terminal. Por eso "el die gana y se
## queda" no depende de que nadie llame a algo, depende de que no exista camino.
##
## LO QUE NO EXISTE, verificado leyendo los parámetros que el propio árbol
## genera en 4.7.2:
##   - `AnimationNodeBlend2.blend_amount` (era de 4.3) y
##     `AnimationNodeTimeScale.scale` (también de 4.3): dan "Invalid
##     assignment" por frame. Este archivo no los toca.
##   - las condiciones NO se publican en `parameters/<n>`, sino en
##     `parameters/conditions/<n>`. Leído del árbol real.
static func tree_de(anim: AnimationPlayer, idle: String, walk: String) -> AnimationTree:
	if anim == null or not is_instance_valid(anim):
		return null
	var ya: Node = anim.get_node_or_null(NodePath(NOMBRE_ARBOL))
	if ya is AnimationTree:
		return ya as AnimationTree
	# Sin `walk` no hay máquina que valga (un rig con un solo clip). Se deja
	# el árbol fuera y el llamador cae al `play()` de siempre.
	if not anim.has_animation(walk):
		return null
	var tree := AnimationTree.new()
	tree.name = NOMBRE_ARBOL
	# `animation_player` es la ruta al AnimationPlayer DESDE EL ÁRBOL: el
	# AnimationTree cuelga del reproductor, así que es `..`.
	#
	# Y aquí hay un caso que parece improbable y no lo es: hay callers que
	# montan el modelo ANTES de colgar el nodo en la escena (los tests de la
	# 49 y la 50 lo hacen, y `aplicar_clase` puede correr en un `_ready` que
	# aún no ha entrado al árbol). `get_path()` de un nodo que no está en la
	# escena es un ERROR, no un NodePath vacío: revienta con "Cannot get path
	# of node as it is not in a scene tree" y el árbol se queda a medio
	# construir. Por eso se pregunta por `is_inside_tree()`.
	if anim.is_inside_tree():
		tree.anim_player = anim.get_path()
	else:
		# Fuera de la escena todavía. Se deja VACÍO a propósito y se rellena
		# en `montar`, que es quien sabe cuándo ya está colgado. Un `NodePath()`
		# vacío no rompe nada: el árbol no resuelve pistas hasta que se le da
		# la ruta buena.
		tree.anim_player = NodePath()
	# `root_node` TIENE que apuntar al mismo sitio que `AnimationPlayer.root_node`,
	# un nivel más arriba (el árbol cuelga del reproductor). Con `".."` sería el
	# propio reproductor y ninguna pista `Rig/Skeleton3D:<hueso>` resolvería.
	tree.root_node = NodePath("../" + str(anim.root_node))
	var sm := AnimationNodeStateMachine.new()
	# La locomoción: el mismo BlendSpace1D de siempre, con idle en 0 y walk a
	# ritmo en 1. Es el cross-fade, ahora DENTRO de un estado.
	var espacio := AnimationNodeBlendSpace1D.new()
	espacio.min_space = 0.0
	espacio.max_space = 1.0
	var n_idle := AnimationNodeAnimation.new()
	n_idle.animation = idle if anim.has_animation(idle) else walk
	var n_walk := AnimationNodeAnimation.new()
	n_walk.animation = walk
	# El ciclo del pack viene espejado. Medido con el árbol ya conectado: el
	# `dz` del apoyo pasa de +0,4277 (al revés) a -0,4277 (bien).
	n_walk.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD if CAMINAR_AL_REVES \
			else AnimationNodeAnimation.PLAY_MODE_FORWARD
	espacio.add_blend_point(n_idle, 0.0)
	espacio.add_blend_point(n_walk, 1.0)
	# Sin el prefijo de biblioteca: `set_blend_point_name` rechaza los nombres
	# con "/" ("new_name.contains_char('/')").
	espacio.set_blend_point_name(0, StringName(
			idle.get_slice("/", idle.get_slice_count("/") - 1)))
	espacio.set_blend_point_name(1, StringName(
			walk.get_slice("/", walk.get_slice_count("/") - 1)))
	sm.add_node(ESTADO_LOCOMOCION, espacio, Vector2(260, 0))
	if anim.has_animation("attack"):
		var n_attack := AnimationNodeAnimation.new()
		n_attack.animation = "attack"
		sm.add_node(ESTADO_ATAQUE, n_attack, Vector2(260, 140))
	if anim.has_animation("die"):
		var n_die := AnimationNodeAnimation.new()
		n_die.animation = "die"
		sm.add_node(ESTADO_MUERTE, n_die, Vector2(520, 70))
	# Las transiciones. Se agregan solo si los estados existen, para que un rig
	# con menos clips no se rompa al pedir la transición.
	if sm.has_node(ESTADO_ATAQUE):
		sm.add_transition(ESTADO_LOCOMOCION, ESTADO_ATAQUE,
				_transicion(CRUCE_ATAQUE_ENTRADA, "atacar"))
		# El tajo se suelta SOLO al acabar el clip (ADVANCE_MODE_AUTO). Nadie
		# tiene que acordarse de volver a la locomoción: es la transición la
		# que lo decide, y por eso el ataque es interrumpible por diseño.
		sm.add_transition(ESTADO_ATAQUE, ESTADO_LOCOMOCION,
				_transicion(CRUCE_ATAQUE, ""))
	if sm.has_node(ESTADO_MUERTE):
		sm.add_transition(ESTADO_LOCOMOCION, ESTADO_MUERTE,
				_transicion(CRUCE_MUERTE, "muriendo"))
		if sm.has_node(ESTADO_ATAQUE):
			# Matar en mitad del tajo: el `die` también gana desde el ataque.
			sm.add_transition(ESTADO_ATAQUE, ESTADO_MUERTE,
					_transicion(CRUCE_MUERTE, "muriendo"))
	tree.tree_root = sm
	anim.add_child(tree)
	# Los DOS relojes, MANUAL. El del árbol para que `avanzar` le imponga el
	# ritmo, y EL DEL REPRODUCTOR para que ningún `play()` de fuera pueda
	# escribir el esqueleto por su cuenta (ver la cabecera). Es lo que hace el
	# bug IMPOSIBLE y no solo improbable.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	# La máquina arranca en `Start`, que es un estado TÉCNICO: no tiene clip, no
	# escribe nada y no tiene por dónde salir (no le pusimos transición). Sin
	# esto el muñeco se queda en la pose de reposo para siempre: MEDIDO, el
	# `get_current_node()` daba "Start" y el Σ|Δpose| era 0,0000 por frame. Es
	# la diferencia entre un árbol que funciona y uno que no hace NADA.
	_iniciar_en_locomocion(tree, sm)
	return tree


## Pone la máquina en `locomocion` al montarla. Va por `playback.start()`, que
## es el reloj de la máquina, y no por una transición: `Start` no tiene a nadie
## que lo llame.
static func _iniciar_en_locomocion(tree: AnimationTree,
		sm: AnimationNodeStateMachine) -> void:
	var pb: AnimationNodeStateMachinePlayback = _playback(tree)
	if pb != null:
		pb.start(String(ESTADO_LOCOMOCION))


## El `AnimationNodeStateMachinePlayback`, o null si aún no existe.
static func _playback(tree: AnimationTree) -> AnimationNodeStateMachinePlayback:
	if tree == null:
		return null
	return tree.get("parameters/playback") as AnimationNodeStateMachinePlayback


## Que la máquina esté SALIDA de `Start`, y que se atienda lo que se le pidió antes
## de que estuviera lista.
##
## POR QUÉ HACE FALTA, y no es paranoia. `Start` y `End` son estados técnicos:
## no tienen clip, no escriben el esqueleto y no tienen a nadie que los llame.
## Si la máquina se queda ahí, el muñeco es un mueble: los estados cambian, las
## transiciones corren, y Σ|Δpose| da 0,00000 durante todo el recorrido. Es un
## fallo que NO dice "no encuentro nada", dice "todo bien".
##
## El problema es CUÁNDO se puede arrancar. `playback` (`parameters/playback`)
## no existe en el instante de `tree.active = true`: lo publica el motor en el
## primer procesado. MEDIDO: en el jugador el arranque funciona en el
## `aplicar_modelo` (que corre dentro del `_ready`), y en el ENEMIGO el primer
## `estado_actual()` daba literalmente "Start" — el `configurar` del pool corre
## en un momento distinto y el `playback` todavía no estaba.
##
## Y PEOR: si a esa altura llega una petición de estado (el bicho entra en
## ATACAR en su primer frame), la petición se PIERDE. MEDIDO: en el test de la
## 49, entrar en `attack` antes de que existiera el `playback` dejaba el bicho
## en `locomocion` para siempre, porque el estado no volvía a cambiar y nadie
## lo volvía a pedir. Por eso el pedido se ANOTA en el árbol (`_pedido`) y se
## atiende en cuanto hay `playback`: la petición no se pierde nunca, por
# temprano que llegue.
static func _asegurar_arranque(tree: AnimationTree) -> void:
	if tree == null:
		return
	var pb: AnimationNodeStateMachinePlayback = _playback(tree)
	if pb == null:
		return
	var actual: String = str(pb.get_current_node())
	if actual == "Start":
		pb.start(String(ESTADO_LOCOMOCION))
		return
	# ¿Quedó algo pedido que todavía no ha aterrizado?
	#
	# ESTE BUCLE ES LA MITAD DEL ARREGLO, y la otra mitad es que el pedido se
	# guarde hasta que aterrice. `travel()` se PIERDE si hay un cross-fade en
	# curso (ver el comentario largo de `estado_poner`), y hay un cross-fade
	# en curso siempre que acabamos de arrancar la máquina: se entra en
	# `locomocion` y, en el MISMO frame, se pide `attack`. MEDIDO: en el test
	# de la 49 el bicho se quedaba en `locomocion` para siempre, con el pedido
	# aplicado y sin error ninguno.
	#
	# Así que el pedido no se borra al emitirse: se borra al LLEGAR. Cada frame
	# se reintenta, y en cuanto el cross-fade anterior se acaba entra a la
	# primera. El coste es un `get_meta` por frame; el beneficio es que ningún
	# pedido se puede perder, por pronto que llegue.
	var pendiente: Variant = tree.get_meta(PEDIDO, "")
	if str(pendiente) == "" or str(pendiente) == actual:
		if str(pendiente) != "":
			tree.remove_meta(PEDIDO)
		return
	_viajar(pb, str(pendiente))


## La clave con la que un pedido de estado pendiente se anota en el árbol. Va
## como metadata del propio árbol, y no en un diccionario estático: el árbol es
## hijo del reproductor y muere con él, así que no hay fuga cuando el pool
## libera los nodos.
const PEDIDO: StringName = &"_gg_estado_pedido"


## Pide un cambio de estado, dejando ANOTADO el destino para cuando la máquina
## esté lista. Devuelve si la pidió; `false` solo si no hay máquina.
static func _viajar(pb: AnimationNodeStateMachinePlayback, destino: String) -> void:
	# La muerte entra con `start()` (corta el cross-fade) y el resto con
	# `travel()` (que lo respeta). Ver el comentario largo de `estado_poner`.
	if destino == str(ESTADO_MUERTE):
		pb.start(destino)
	else:
		pb.travel(destino)


## Una transición. Con `condition` es MANUAL (espera al parámetro
## `parameters/conditions/<condition>`), sin ella es AUTO (avanza al acabar el
## clip de origen). Medido: las condiciones se publican bajo
## `parameters/conditions/`, no bajo `parameters/`.
static func _transicion(xfade: float, condition: String) -> AnimationNodeStateMachineTransition:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	if condition == "":
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	else:
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
		t.advance_condition = StringName(condition)
	return t


## Monta el motor de una vez, sin esperar al primer frame. Lo llama la entidad
## en cuanto cuelga el modelo.
##
## POR QUÉ EXISTE, y no solo por comodidad: `tree_de` es lo que pone el reloj
## del REPRODUCTOR en manual, y con eso es lo que vuelve INERTE cualquier
## `play()` de fuera. Si el montaje se hiciera recién en el primer
## `_actualizar_animacion`, entre colgar el modelo y ese primer frame habría una
## ventana en la que el reproductor todavía avanza por su cuenta. Montándolo
## aquí, la ventana no existe.
## Reemplaza los clips del `.glb` por los convertidos de Mixamo.
##
## POR QUE SE SUSTITUYEN Y NO SE AGREGAN: el `AnimationTree` referencia los
## clips por NOMBRE dentro de una biblioteca. Si los de Mixamo se agregan con
## otro nombre, habria dos "walk" y habria que tocar el arbol entero. Al
## reemplazar el contenido de la biblioteca con los MISMOS cuatro nombres, el
## arbol, el `BlendSpace1D` y el codigo del juego siguen hablando los nombres de
## siempre y no se entera de nada.
##
## SI FALTA UN `.tres`, SE DEJA EL DEL GLB. Un error al convertir una animacion
## no puede dejar a todos los personajes con los brazos clavados.
## Los clips de Mixamo que entran al juego.
##
## `walk` NO esta en la lista, y no por forgetting. El juego mueve al personaje
## a 6,0 m/s (`StatBlock.vel_mov`), que es velocidad de sprint: una caminata
## humana de Mixamo esta diseñada para ~1,4 m/s y hay que reproducirla ~4,9
## veces mas rapido. Medido con el clip de Mixamo:
##
##   · el pie viaja a 5,82 m/s con el cuerpo a 6,0 -> la zancada no alcanza;
##   · en el APOYO el pie va -0,0422 u, o sea moonwalk;
##   · 8,57 pisadas por segundo, cuando lo normal son 3,0 a 3,4.
##
## Ninguno de esos tres se arregla retimeando: son la firma de correr una
## caminata a velocidad de carrera. La salida correcta es una de dos, y es una
## decision del JUEGO, no del conversor: bajar la velocidad de caminata, o tray
## ciclos de carrera de verdad. Por ahora la caminata sigue siendo la del `.glb`,
## que aguanta el ritmo. Cuando se decida, es agregar "walk" a esta lista.
const CLIPS_MIXAMO: Array[String] = []

## Y el `idle` tampoco entra, por otra incompatibilidad REAL y medida. El idle de
## Mixamo llega con los brazos separados del cuerpo (L 51,9 grados, R 60,3
## grados), y el juego exige que en reposo los brazos CUELGUEN (menos de 20) y
## que los dos sean iguales (diferencia menor a 2). Un idle de Mixamo esta
## pensado para un personaje de manos caidas a lo Andersen, no para un guerrero
## medieval. Se podria aceptar el nuevo reposo, pero eso cambia el modelo de
## TODOS los personajes y hay que verlo antes de decidirlo.
##
## VACIA A PROPOSITO, y ahora por una razon MEDIDA y no theoretica: la
## conversion anda (los cuatro `.tres` salen con las rutas correctas, el delta
## contra la pose de reposo, el root motion descartado y el periodo real del
## ciclo), pero al reproducirla sobre estos modelos el resultado es peor que la
## animacion procedural que ya estaba.
##
## LA RAZON, vista en render: las mallas estan troceadas por hueso, con cortes
## duros de color en hombro, codo y rodilla. Una caminata real flexiona esa
## articulacion en cada cuadro, y las costuras se abren: el codo se separa del
## brazo. La animacion procedural esta escrita para estos cuerpos y con sus
## movimientos chicos no abre las costuras.
##
## O sea: el mocap es correcto y el cuerpo no lo aguanta. Arreglar esto es
## trabajo de MODELO (malla continua,Weights, subdivisiones), no de conversor.
## Los clips quedan generados en anim/clips/ por si sirven cuando el modelo
## aguante. Para probarlos: ["walk"] y mirar.


static func inyectar_clips_mixamo(anim: AnimationPlayer) -> int:
	var lib: AnimationLibrary = anim.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		anim.add_animation_library("", lib)
	var puestos := 0
	for nombre in CLIPS_MIXAMO:
		var ruta := "res://anim/clips/%s.tres" % nombre
		if not ResourceLoader.exists(ruta):
			continue
		var a: Resource = load(ruta)
		if not (a is Animation):
			continue
		if lib.has_animation(nombre):
			lib.remove_animation(nombre)
		lib.add_animation(nombre, a)
		puestos += 1
	return puestos


static func montar(anim: AnimationPlayer, idle: String, walk: String) -> bool:
	# Los clips de Mixamo entran POR ACA, y no en otro lado a proposito: esta
	# es la unica funcion por la que pasa todo personaje que se anima, el jugador
	# (`player.gd`) y cada enemigo (`enemy.gd`). Inyectar en el punto de uso los
	# dejaria fuera a los enemigos, que es donde mas se nota una caminata que
	# patina.
	inyectar_clips_mixamo(anim)
	var tree: AnimationTree = tree_de(anim, idle, walk)
	if tree == null:
		return false
	# Si el reproductor se montó FUERA de la escena, su ruta quedó vacía y
	# ahora sí se puede rellenar. Sin esto el árbol queda construido pero
	# apuntando a nada, y sus estados cambian sin que ninguna pista escriba el
	# esqueleto: un fallo que no dice "no encuentro el esqueleto", dice "todo
	# funciona" mientras el muñeco es un mueble.
	if tree.anim_player.is_empty() and anim.is_inside_tree():
		tree.anim_player = anim.get_path()
	return true


## Escribe el estado pedido en la máquina. Es la ÚNICA vía: el llamador dice
## QUÉ quiere (locomocion / tajo / muerte) y la máquina decide el cuándo.
##
## `atacando` y `muriendo` son banderas, no clips: la máquina es dueña del
## esqueleto y estas solo abren la puerta. El reproductor nunca se toca.
##
## POR QUÉ `playback.travel()` Y NO LAS CONDICIONES. La vía obvia sería una
## transición con `advance_mode = ENABLED` y `advance_condition = "atacar"`, y
## eso NO FUNCIONA en 4.7. MEDIDO, con la condición puesta a `true` y SOSTENIDA
## durante 25 frames: la máquina se quedó en `locomocion` los 25 frames y
## `parameters/attack/current_position` no se movió de 0,000. Con el MISMO árbol
## y la misma transición declarada, un `playback.travel("attack")` entra en
## `attack` en el frame siguiente y `current_position` avanza. No es que la
## condición esté mal escrita: es que el motor no la consulta. Como el
## `set()` a una ruta que no existe NO da error (tampoco
## `parameters/conditions/atacar` antes de que la máquina se inicialice), el
## síntoma de este error es que NADA PASA y no se ve por qué: el muñeco camina
## —el estado `locomocion` funciona— pero el tajo y la muerte no ocurren nunca.
##
## La ruta de las condiciones, por si algún día se arregla, es
## `parameters/conditions/<nombre>` y NO `parameters/<nombre>` (leído del árbol
## real, no de la documentación).
##
## Con `travel` la máquina decide el CUÁNDO igual: la transición
## `attack -> locomocion` es AUTOMÁTICA, o sea que el tajo se suelta solo al
## acabarse el clip sin que nadie lo ordene. Por eso el ataque es
## interrumpible y no depende de que el código se acuerde.
static func estado_poner(anim: AnimationPlayer, atacando: bool, muriendo: bool) -> bool:
	var tree: AnimationTree = _arbol(anim)
	if tree == null:
		return false
	_asegurar_arranque(tree)
	var pb: AnimationNodeStateMachinePlayback = _playback(tree)
	if pb == null:
		# Todavía no hay `playback` (el motor lo publica en el primer procesado).
		# El pedido NO se pierde: se anota en el árbol y se atiende en cuanto
		# exista, en `_asegurar_arranque`. Perderlo sería la diferencia entre
		# "el bicho entra en attack un frame tarde" y "el bicho nunca entra".
		tree.set_meta(PEDIDO, destino_calculada(atacando, muriendo))
		return false
	# La muerte es terminal: si alguien sigue diciendo "atacando" después de
	# morir, la muerte gana igual, porque `die` no tiene transición de salida.
	var destino: String = destino_calculada(atacando, muriendo)
	var actual: String = str(pb.get_current_node())
	# ESTADO MUERTO ES ABSORBENTE. No es que "nadie llama": es que esta función
	# se NIEGA a salir de `die` sin que se lo pida explícitamente con
	# `revivir()`. Así el cadaver no se levanta aunque el código siga pidiendo
	# locomoción cada frame (que es justo lo que hace el jugador al morir: su
	# `_actualizar_animacion` corre igual y pediría caminar). Y como la máquina
	# además no tiene transición de salida desde `die`, son DOS barreras
	# independientes: ni el código ni el motor pueden sacar al muerto de ahí.
	if actual == str(ESTADO_MUERTE) and not muriendo:
		return true
	# Si el estado pedido no existe en este rig (un `.glb` sin `attack`), se
	# queda donde está: es preferible una pose congelada a un estado inexistente.
	var sm: AnimationNodeStateMachine = tree.tree_root as AnimationNodeStateMachine
	if sm != null and not sm.has_node(StringName(destino)):
		return true
	# `travel`/`start` ENCOLAN el cambio: si se pide el mismo destino cada
	# frame, el cross-fade se reinicia sin acabar nunca. Solo se pide cuando
	# el estado actual NO es el que se quiere.
	if actual == destino:
		return true
	#
	# ---- Y AQUÍ ESTÁ UNA TRAMPA MEDIDA, DE LAS QUE COGEN A TODOS ----
	#
	# `playback.travel()` se PIERDE si se pide mientras hay un cross-fade en
	# curso. No avisa, no falla: simplemente no pasa, y el pedido se cae al
	# suelo. MEDIDO: se entra en `attack`, y dos frames después (con el
	# cross-fade de 0,10 s todavía en marcha) se pide `die`: el estado se quedó
	# en `attack` y el cadaver no se caía. En el juego eso es MORIR EN PLENO
	# TAJO, que es justo lo que pasó: el bicho te contesta y tu muerte se come.
	# Con los dos casos de este test pasando (morir andando y morir pegando), es
	# un hueco que no se ve mirando solo un caso.
	#
	# La salida: `start()` SÍ corta el cross-fade (medido: `start("die")` en
	# pleno cross-fade entra en `die` en el frame siguiente). Y para lo que no
	# es muerte, que sí quiere cross-fade, el viaje se REINTENTA cada frame
	# mientras no haya aterrizado: como `estado_poner` se llama cada frame, en
	# cuanto el cross-fade anterior se acaba el pedido entra a la primera.
	# El pedido se ANOTA antes de emitirlo, y no se borra aquí: se borra en
	# `_asegurar_arranque`, cuando el estado es de verdad el pedido. Si se
	# borrara al emitirlo, un `travel()` perdido se perdería con él.
	tree.set_meta(PEDIDO, destino)
	_viajar(pb, destino)
	return true

## Qué estado corresponde a lo que se pide. La muerte pisa al tajo: pedir las
## dos cosas a la vez es una CONFUSIÓN, y el cadaver gana.
static func destino_calculada(atacando: bool, muriendo: bool) -> String:
	if muriendo:
		return str(ESTADO_MUERTE)
	if atacando:
		return str(ESTADO_ATAQUE)
	return str(ESTADO_LOCOMOCION)


## La única puerta de salida de la muerte. Sin esto, `die` es para siempre.
## Lo llama el respawn del jugador y el `reiniciar` del enemigo del pool.
static func revivir(anim: AnimationPlayer) -> bool:
	var tree: AnimationTree = _arbol(anim)
	if tree == null:
		return false
	_asegurar_arranque(tree)
	var pb: AnimationNodeStateMachinePlayback = _playback(tree)
	if pb == null:
		tree.set_meta(PEDIDO, destino_calculada(false, false))
		return false
	if str(pb.get_current_node()) == str(ESTADO_MUERTE):
		pb.travel(str(ESTADO_LOCOMOCION))
	return true


## Pone la mezcla de locomoción por velocidad y deja la máquina en
## locomoción (que es donde se mezcla). Devuelve si usó el árbol o el fallback
## de `play()`, que los tests usan para comprobar ambos caminos.
static func mezclar(anim: AnimationPlayer, idle: String, walk: String,
		norm: float, velocidad_real: float, escala: float = 1.0) -> bool:
	if anim == null or not is_instance_valid(anim):
		return false
	# `montar` y no `tree_de`: además de crear el árbol, repara la ruta del
	# reproductor si se construyó antes de que el nodo entrara en la escena.
	if not montar(anim, idle, walk):
		# Sin modelo, sin ese clip, o sin esqueleto que medir: el `play()` de
		# siempre. Es el comportamiento de un mob sin modelo, y no se pierde
		# nada. Un rigido es preferible a no animar. Y como el reloj del
		# reproductor quedó en manual, este `play()` tampoco avanza solo: el
		# llamador tiene que hacer `avanzar` para que se vea. Para un
		# mob sin modelo eso da igual: no hay esqueleto que ver.
		anim.play(idle if norm <= 0.0 else walk)
		return false
	var tree: AnimationTree = _arbol(anim)
	if tree == null:
		anim.play(idle if norm <= 0.0 else walk)
		return false
	var sm: AnimationNodeStateMachine = tree.tree_root as AnimationNodeStateMachine
	if sm == null:
		return false
	var espacio: AnimationNodeBlendSpace1D = sm.get_node(
			String(ESTADO_LOCOMOCION)) as AnimationNodeBlendSpace1D
	if espacio == null:
		return false
	tree.set("parameters/locomocion/blend_position", clampf(norm, 0.0, 1.0))
	# Volver a locomoción. Va por el mismo `estado_poner` que el tajo: una sola
	# forma de pedir un estado, para que no haya dos caminos y uno se olvide.
	#
	# Aquí SÍ se fuerza el regreso aunque la transición automática todavía no
	# haya terminado su cross-fade: `mezclar` se llama cada frame, así que el
	# tajo se interrumpe en cuanto el jugador vuelve a caminar, que es
	# exactamente lo que se pidió ("si el jugador mata a un enemigo mientras
	# camina, tiene que volver a caminar, no quedarse pegado").
	#
	# PERO la muerte no: si el estado es `die`, `mezclar` no hace nada. La
	# muerte es terminal por construcción y no por cortesía del llamador: ni
	# aunque el código INSISTA cada frame en pedir locomoción, el cadaver no se
	# levanta. MEDIDO por qué importa: antes, con el `play()` suelto, el bicho
	# se quedaba clavado en el `attack` porque NADIE lo sacaba; el mismo
	# "nadie lo saca" en el otro extremo es un cadaver que revive solo.
	estado_poner(anim, false, false)
	tree.active = true
	return true


## El `AnimationTree` del reproductor, o null. No lo crea.
static func _arbol(anim: AnimationPlayer) -> AnimationTree:
	if anim == null or not is_instance_valid(anim):
		return null
	var n: Node = anim.get_node_or_null(NodePath(NOMBRE_ARBOL))
	return n as AnimationTree if n is AnimationTree else null


## El `AnimationTree` del reproductor, creándolo si hace falta. Es lo que
## usan los tests para inspeccionar el estado sin ir por el código de la IA.
static func arbol(anim: AnimationPlayer) -> AnimationTree:
	return _arbol(anim)


## En qué estado está la máquina ahora mismo. `""` si no hay máquina.
static func estado_actual(anim: AnimationPlayer) -> String:
	var tree: AnimationTree = _arbol(anim)
	if tree == null:
		return ""
	_asegurar_arranque(tree)
	var pb: AnimationNodeStateMachinePlayback = _playback(tree)
	return "" if pb == null else str(pb.get_current_node())


## Qué clip de caminar está usando el árbol. Se mira por el nodo del punto de
## mezcla, no por el `Animation` suelto: el árbol es el que decide qué se
## reproduce, y el `play_mode` (la inversión) vive ahí y no en el clip.
static func clip_en_uso(anim: AnimationPlayer) -> String:
	var tree: AnimationTree = _arbol(anim)
	if tree == null:
		return ""
	var sm: AnimationNodeStateMachine = tree.tree_root as AnimationNodeStateMachine
	if sm == null:
		return ""
	var bs: AnimationNodeBlendSpace1D = sm.get_node(
			String(ESTADO_LOCOMOCION)) as AnimationNodeBlendSpace1D
	if bs == null or bs.get_blend_point_count() < 2:
		return ""
	var punto: AnimationNodeAnimation = bs.get_blend_point_node(1) as AnimationNodeAnimation
	return "" if punto == null else str(punto.animation)


## POR QUÉ NO SE TOCA EL `Animation` (las tres vías, medidas):
##   - `AnimationNodeTimeScale` existe pero NO tiene la propiedad `scale` (era
##     de 4.3). Comprobado: su lista de propiedades son las cuatro de
##     `Resource` y nada más. `AnimationMixer`, la base del árbol, tampoco tiene
##     ninguna propiedad de velocidad.
##   - `AnimationNodeBlendSpace1D.sync_mode` + `cyclic_length` SUENAN a lo que
##     se busca, pero resamplean el clip y destrozan la marcha. Con el árbol ya
##     conectado y el ciclo forzado a 1/4,25 del original: la zancada cae de
##     0,7395 a 0,3830 (SYNC_MODE_CYCLIC_CONSTANT) y a 0,1914 (los otros
##     modos), y el `dz` del apoyo deja de tener signo claro. El paso se pierde.
##   - Reescribir el `Animation` a mano es un callejón en 4.7:
##     `track_get_key_count` NO coincide con el vector interno de datos. En el
##     clip de caminar la pista de posición de `Hips` declara 30 claves y tiene
##     26, y la de rotación de `Foot.L` declara 33 y tiene 20. Escribir los
##     tiempos a mano revienta con
##     "Index p_key_idx = 26 is out of bounds (positions.size() = 26)" y
##     corrompe la pista.
##
## LA VÍA QUE SÍ FUNCIONA: el reloj del propio árbol.
## `AnimationMixer.callback_mode_process = ANIMATION_CALLBACK_MODE_PROCESS_MANUAL`
## saca al árbol del bucle principal: deja de avanzar solo y únicamente
## avanza cuando se le llama a `advance(delta)`. Multiplicando ese `delta` por
## el ritmo, el clip de caminar va `ritmo` veces más rápido y el pie deja de patinar
## SIN tocar un solo byte del `.glb`. Es la misma API que usa el test para
## medir, así que lo que el test mide es lo que el juego ejecuta.
##
## OJO: el multiplicador se aplica a TODO lo que cuelgue del árbol, el idle
## incluido. Por eso `avanzar` nunca baja de 1,0: quieto el árbol va a ritmo
## natural y la mezcla esta en idle puro (0), asi que el idle respira a lo suyo
## y no se ve raro. En marcha la mezcla sube y el idle pesa cada vez menos.
const RITMO_REPOSO: float = 1.0


## Hace avanzar el reloj del árbol al ritmo que corresponde a la velocidad.
## Es lo que hay que llamar CADA FRAME desde el sistema que anima a la entidad.
##
## Ahora el reloj del REPRODUCTOR también es manual, así que `avanzar` tiene que
## pasarle el reloj a los dos: al árbol (que escribe el esqueleto) y, si no hay
## máquina (mob sin rig), al reproductor (que es su único reloj). Con la máquina
## puesta, el reproductor NO se advance: su reloj es el del árbol, y tocarlo
## sería volver a meter el segundo conductor por la ventana de atrás.
static func avanzar(anim: AnimationPlayer, delta: float,
		velocidad_real: float, escala: float = 1.0) -> void:
	if anim == null or not is_instance_valid(anim):
		return
	var f: float = maxf(ritmo(velocidad_real, escala), RITMO_REPOSO)
	var tree: AnimationTree = _arbol(anim)
	if tree == null:
		# Sin máquina: el reproductor es el motor (fallback sin rig).
		anim.advance(delta * f)
		return
	if not tree.active:
		return
	_asegurar_arranque(tree)
	tree.advance(delta * f)


## ¿El reloj del reproductor quedó puesto a manual por nosotros? Lo usan los
## tests para probar que el `play()` de fuera es inerte.
static func reproductor_en_manual(anim: AnimationPlayer) -> bool:
	if anim == null or not is_instance_valid(anim):
		return false
	return anim.callback_mode_process \
			== AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
