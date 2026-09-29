class_name ArbolAnimacion
extends RefCounted
## La locomoción: idle ↔ walk mezclados por velocidad, el clip de caminar
## reproducido A RITMO para que el pie no patine, y el ciclo del pack
## reproducido AL REVÉS porque viene espejado.
##
## SON CUATRO FALLOS DISTINTOS, y con los cuatro arreglados recién entonces se
## ve caminar. Ninguno se Sokoló: todos están medidos sobre el esqueleto de los
## `.glb` del pack (ver `tests/test_fase70_caminar.gd`, que imprime los mismos
## números).
##
## 1. EL ÁRBOL NO ANIMABA NADA. `AnimationTree.root_node` viene por defecto a
##    `".."`, y el árbol cuelga del `AnimationPlayer`, así que `".."` es el
##    propio reproductor — donde no existe `Rig/Skeleton3D`. Todas las pistas
##    del clip son `Rig/Skeleton3D:<hueso>`, así que ninguna resolvía y el
##    esqueleto se quedaba en la pose de reposo mientras el personaje se
##    desplazaba. El aviso del motor es "couldn't resolve track", que pasa
##    desapercibido en un log. Por eso dos intentos de arreglar la API del
##    blend no cambiaron nada: el `blend_position` se escribía perfecto y el
##    blend no tenía a quién OUTPUTEARLE.
## 2. LA MEZCLA SATURABA. Se pedía `clampf((v - 0,45) / 0,45, 0, 1)`, que llega
##    a 1,0 a los 0,90 m/s. El juego va a 6,0 (`StatBlock.vel_mov`), así que
##    `blend_position` estaba clavado en 1,0 siempre que te movieras: un corte
##    disfrazado de mezcla, con dos valores. Los enemigos lo tenían peor con su
##    `v / 3,0` (satura a 3,0 y persiguen a 6,0).
## 3. LA MARCHA IBA AL REVÉS. El ciclo de caminar del pack está espejado: al
##    medir el punto más bajo del pie (el apoyo) sale que el pie avanza hacia
##    DELANTE mientras está en el suelo (dz = +0,4277), y en una marcha el pie
##    en el suelo va hacia ATRÁS, porque es el cuerpo el que pasa por encima
##    (dz = -0,4277). Eso es un moonwalk.
## 4. EL PIE PATINABA 4,2 VECES. El clip viaja 1,4264 u/s por su cuenta y el
##    juego va a 6,0 m/s. A `speed_scale` 1 (que era como estaba) el pie patina
##    más de lo que camina: 492 cm por ciclo.
##
## El (3) se arregla con el `play_mode` del nodo, que sí existe en 4.7. El (4)
## con el reloj del árbol en modo manual: ver `avanzar`.

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


## Multiplicador de ritmo que hace que el pie no patine a `velocidad_real`.
##
## Es la fórmula que sostiene el invariante: `ritmo(v) * VELOCIDAD_CLIP *
## escala == v`, o sea, el pie avanza en el mundo a la misma velocidad a la que
## el cuerpo se traslada. Con eso, y solo con eso, el personaje camina en vez de
## deslizarse.
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
## `AnimationNodeBlendTree` con un `AnimationNodeBlendSpace1D` (idle en 0.0,
## walk a ritmo en 1.0) es la forma más barata de cross-fade: no necesita
## `StateMachine` y son dos clips en vez de una máquina de estados.
##
## LA API, verificada leyendo los parámetros que genera el propio AnimationTree
## en 4.7.2, y lo que NO existe, que es la mitad del trabajo:
##   - `AnimationNodeBlendSpace1D` con `min_space=0`, `max_space=1`
##   - `add_blend_point(nodo, posicion)`; el tercer argumento es un ÍNDICE
##     (`at_index`), no un nombre, y `AnimationNode` no tiene propiedad `name`.
##     El nombre se pone después con `set_blend_point_name`, que además es lo
##     único que quita el aviso de "No name provided" de cada entidad.
##   - `AnimationNodeBlendTree.new()` YA trae un nodo `output` (añadir otro
##     revienta con "Condition nodes.has(p_name) is true")
##   - la mezcla se escribe por parámetro:
##     `tree.set("parameters/locomocion/blend_position", valor)`
##   - NO existe `AnimationNodeBlend2.blend_amount` (era de 4.3) ni
##     `AnimationNodeTimeScale.scale` (también era de 4.3). Los dos dan
##     "Invalid assignment" por frame. Este archivo no los toca.
static func tree_de(anim: AnimationPlayer, idle: String, walk: String) -> AnimationTree:
	if anim == null or not is_instance_valid(anim):
		return null
	var ya: Node = anim.get_node_or_null(NodePath(NOMBRE_ARBOL))
	if ya is AnimationTree:
		return ya as AnimationTree
	var tree := AnimationTree.new()
	tree.name = NOMBRE_ARBOL
	# `animation_player` es la ruta al AnimationPlayer desde el árbol: el
	# AnimationTree es hermano del AnimationPlayer, cuelga del mismo padre.
	tree.anim_player = anim.get_path() if anim.get_parent() != null else NodePath()
	# ESTO ES LO QUE HACÍA QUE EL ÁRBOL NO ANIMARA NADA (punto 1 de la
	# cabecera). `root_node` viene a `".."`, y como el árbol cuelga del
	# reproductor, `".."` es el reproductor: ahí no existe `Rig/Skeleton3D`, que
	# es donde apuntan todas las pistas del clip, y ninguna resolvía. El árbol
	# tiene que apuntar al MISMO sitio que `AnimationPlayer.root_node`, un nivel
	# más arriba. Medido: con `".."` el pie no se mueve ni 0,00001 en 0,1 s de
	# reloj; con `"../.."` se mueve 0,058.
	tree.root_node = NodePath("../" + str(anim.root_node))
	var root: AnimationNodeBlendTree = AnimationNodeBlendTree.new()
	# BlendSpace1D: 0.0 = idle, 1.0 = walk, y lo de en medio se interpola. Es el
	# cross-fade, sin maquina de estados.
	var espacio := AnimationNodeBlendSpace1D.new()
	espacio.min_space = 0.0
	espacio.max_space = 1.0
	var n_idle := AnimationNodeAnimation.new()
	n_idle.animation = idle
	var n_walk := AnimationNodeAnimation.new()
	n_walk.animation = walk
	# El ciclo del pack viene espejado (punto 3). Medido con el árbol ya
	# conectado: el `dz` del apoyo pasa de +0,4277 (al revés) a -0,4277 (bien).
	n_walk.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD if CAMINAR_AL_REVES \
			else AnimationNodeAnimation.PLAY_MODE_FORWARD
	espacio.add_blend_point(n_idle, 0.0)
	espacio.add_blend_point(n_walk, 1.0)
	# Sin el prefijo de biblioteca: `set_blend_point_name` rechaza los nombres
	# con "/" ("new_name.contains_char('/')").
	espacio.set_blend_point_name(0, StringName(idle))
	espacio.set_blend_point_name(1, StringName(
			walk.get_slice("/", walk.get_slice_count("/") - 1)))
	root.add_node("locomocion", espacio, Vector2(200, 0))
	# `AnimationNodeBlendTree.new()` ya viene con un nodo `output`: añadir otro
	# falla con "Condition nodes.has(p_name) is true".
	root.connect_node("output", 0, "locomocion")
	tree.tree_root = root
	anim.add_child(tree)
	# El reloj es NUESTRO: sin esto el bucle principal avanza el árbol por su
	# cuenta a velocidad 1 y `avanzar` no puede darle un ritmo. Con el modo manual
	# solo avanza cuando se le llama, y el ritmo lo pone quien llama.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	return tree


## Pone la mezcla según la velocidad.
##
## `norm` va de 0 (quieto) a 1 (corriendo): es la velocidad normalizada con
## `mezcla_por_velocidad`, NO la velocidad cruda. `velocidad_real` es la
## velocidad horizontal en m/s y decide el RITMO del clip, que es lo que mata el
## patinazo. `escala` es la del modelo colgado (`modelo_escala`), que es lo que
## convierte la zancada del esqueleto en zancada en el mundo. Devuelve si usó el
## árbol o el fallback, que los tests usan para comprobar ambos caminos.
static func mezclar(anim: AnimationPlayer, idle: String, walk: String,
		norm: float, velocidad_real: float, escala: float = 1.0) -> bool:
	if anim == null or not is_instance_valid(anim):
		return false
	if not anim.has_animation(walk):
		# Sin modelo, sin ese clip, o sin esqueleto que medir: el `play()` de
		# siempre. Es el comportamiento de un mob sin modelo, y no se pierde nada.
		# Un rigido es preferible a no animar.
		anim.play(idle if norm <= 0.0 else walk)
		return false
	var tree: AnimationTree = tree_de(anim, idle, walk)
	if tree == null:
		anim.play(idle if norm <= 0.0 else walk)
		return false
	var bt: AnimationNodeBlendTree = tree.tree_root as AnimationNodeBlendTree
	if bt == null:
		return false
	var espacio: AnimationNodeBlendSpace1D = bt.get_node("locomocion") as AnimationNodeBlendSpace1D
	if espacio == null:
		return false
	tree.set("parameters/locomocion/blend_position", clampf(norm, 0.0, 1.0))
	# Volver a locomoción después de un tajo o una muerte: el árbol vuelve a
	# mandar (ver `soltar`).
	tree.active = true
	return true


## Deja el árbol y le devuelve el reproductor al control directo, para los clips
## que NO son locomoción (tajo, muerte).
##
## SIN ESTO el `play()` se deshace: con el árbol activo es él el que escribe las
## pistas del esqueleto, y el `attack` que puso `_poner_clip` lo pisaba el
## `locomocion` al frame siguiente. El tajo no se veía. El bloque 67 lo dejó
## pasar porque el árbol —hasta ahora- no animaba nada.
static func soltar(anim: AnimationPlayer) -> void:
	if anim == null or not is_instance_valid(anim):
		return
	var n: Node = anim.get_node_or_null(NodePath(NOMBRE_ARBOL))
	if n is AnimationTree:
		(n as AnimationTree).active = false


## Qué clip de caminar está usando el árbol. Se mira por el nodo del punto de
## mezcla, no por el `Animation` suelto: el árbol es el que decide qué se
## reproduce, y el `play_mode` (la inversión) vive ahí y no en el clip.
static func clip_en_uso(anim: AnimationPlayer) -> String:
	if anim == null or not is_instance_valid(anim):
		return ""
	var n: Node = anim.get_node_or_null(NodePath(NOMBRE_ARBOL))
	if not (n is AnimationTree):
		return ""
	var bt: AnimationNodeBlendTree = (n as AnimationTree).tree_root as AnimationNodeBlendTree
	if bt == null:
		return ""
	var bs: AnimationNodeBlendSpace1D = bt.get_node("locomocion") as AnimationNodeBlendSpace1D
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
## avanza cuando se le llama a `advance(delta)`. Multiplicando ese `delta` por el
## ritmo, el clip de caminar va `ritmo` veces más rápido y el pie deja de patinar
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
static func avanzar(anim: AnimationPlayer, delta: float,
		velocidad_real: float, escala: float = 1.0) -> void:
	if anim == null or not is_instance_valid(anim):
		return
	var n: Node = anim.get_node_or_null(NodePath(NOMBRE_ARBOL))
	if not (n is AnimationTree):
		return
	var tree: AnimationTree = n as AnimationTree
	if not tree.active:
		# Tajo o muerte: el reproductor manda y el árbol está parado a propósito.
		return
	var f: float = maxf(ritmo(velocidad_real, escala), RITMO_REPOSO)
	tree.advance(delta * f)