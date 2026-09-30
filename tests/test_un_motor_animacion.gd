extends SceneTree
## UN SOLO MOTOR DE ANIMACIÓN. Antes había DOS y se pisaban.
##
## SÍNTOMA DEL USUARIO, textual: "cuando termino de matar a un enemigo se queda
## bugeado haciendo la animación de atacar". El clip de ataque se quedaba
## sonando y no volvía ni a idle ni a caminar.
##
## LA CAUSA, medida antes de arreglar nada (sonda sobre
## `models/clase_guerrero.glb` de verdad, 19 huesos, Σ|Δpose| = cuánto se movió
## el esqueleto en el frame):
##
##   · el `AnimationTree` mezclaba idle↔walk con Σ|Δpose| de 0,15 a 0,38 (se ve
##     la marcha);
##   · en el frame en que entraba `play("attack")` con `soltar()`, el Σ|Δpose| caía
##     a 0,00: el tajo NO se veía, porque el árbol dejaba de escribir;
##   · y al volver a la locomoción, `current_animation` seguía siendo "attack"
##     durante 100+ frames después de acabar el tajo, con el árbol ya activo
##     otra vez. Dos relojes contando cosas distintas, un solo esqueleto.
##
## QUÉ COMPRUEBA ESTE ARCHIVO, en el orden en que importa:
##
##   1. **EL CASO EXACTO DEL USUADOR**: caminas, golpeas, el bicho muere, y
##      después de N frames el estado es de locomoción y NO de attack. Es el
##      bug reportado, con sus palabras.
##   2. **LA MUERTE GANA Y SE QUEDA**: tras morir, el estado es `die` y no
##      vuelve a caminar solo, ni aunque el código insista cada frame.
##   3. **EL `play()` DE AFUERA ES INERTE**: no es que "no lo usamos", es que
##      medido no mueve el esqueleto ni una micra. Esta es la prueba de que el
##      bug no puede volver por la misma puerta.
##   4. **HAY UN SOLO MOTOR**: existe UN AnimationTree, y el `AnimationPlayer`
##      tiene el reloj en manual, o sea que no puede ser un segundo conductor.
##   5. **LA MÁQUINA, ADEMÁS**: los cuatro clips son estados, y el estado se
##      puede LEER (que es lo que permite que un test afirme sobre él).
##
## Y dos cosas que este test NO puede hacer y por eso se dicen: no mide si el
## `attack` se VE bien (eso es de otro worker y de `tools/anim_medida.sh`), y
## no mide al enemigo con modelo si el `.glb` no está importado — en ese caso lo
## dice, no se lo salta en silencio.
##
## CÓMO CORRERLO
##   godot --headless --path . --script res://tests/test_un_motor_animacion.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.

const LOCALIZADOR: GDScript = preload("res://tools/anim_medida/localizador.gd")
const ARBOL: GDScript = preload("res://scripts/core/arbol_animacion.gd")
const PLAYER: GDScript = preload("res://scripts/player/player.gd")
const ESCENA_ENEMIGO: PackedScene = preload("res://scenes/enemy/enemigo.tscn")

const CLASE: String = "guerrero"
## El único arquetipo con rig (`data/enemies.json`). Sin modelo no hay esqueleto
## y el caso del enemigo no se puede reproducir; se avisa, no se finge.
const ARQ_GOBLIN: Dictionary = {
	"nombre": "Goblin", "color": [0.35, 0.75, 0.35],
	"fuerza": 10.0, "destreza": 12.0, "inteligencia": 2.0,
	"radio_aggro": 12.0, "rango_ataque": 2.2, "cooldown_ataque": 1.6,
	"xp": 40, "oro_min": 5, "oro_max": 15, "loot": {"items": []},
	"modelo": "res://models/bandido_rig.glb", "modelo_escala": 0.62,
}
## 60 fps, como el juego. Los frames se cuentan con esto, no con `delta` real,
## porque en headless el delta no es estable y un test de frames tiene que
## decir cuántos frames son.
const DT: float = 1.0 / 60.0
## Frames que se le dan a la locomoción antes del tajo, y después. Suficiente
## para que la mezcla se estabilice y para que se note un cambio de estado.
const FRAMES_CAMINAR: int = 30
const FRAMES_TRAS_TAJO: int = 40
## Cuánto dura el tajo en frames: 0,32 s de `_t_swing` a 60 fps son ~19.
const FRAMES_TAJO: int = 25

var _ok: int = 0
var _fallos: int = 0
var _fase: int = 0

var _p: Player = null
var _e: Node = null
var _anim: AnimationPlayer = null
var _skel: Skeleton3D = null
## La pose de los 19 huesos del frame anterior. El Δ contra esto es "cuánto se
## movió el muñeco", que es lo que el jugador ve. Un nombre de clip no lo es.
var _pose: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	print("[TEST] un solo motor de animación — el bug del tajo pegado")


## Si esta pieza de la API no existe, el test tiene que MORIR, no seguir.
##
## POR QUÉ, y es una lección pagada: la primera versión de este test, corrida
## contra el código VIEJO (que no tenía máquina de estados), imprimía
## "7 ok, 0 fallos" en VERDE. Cada fase reventaba con "Nonexistent function
## 'estado_actual'" y la excepción se comía el resto de la fase, así que
## `_chk` no llegaba a contar ni un fallo: el test se PASABA A SÍ MISMO
## mientras no comprobaba absolutamente nada. Un test que no falla cuando el
## código está roto no es un test: es un testigo mudo. La defensa es una: si
## falta la API, se aborta el proceso con código 1, que el `run_tests.sh` lee
## como ROJO.
func _api(anim: AnimationPlayer, que: String) -> void:
	if not ARBOL.has_method(que):
		printerr("[FATAL] ArbolAnimacion no tiene '%s'. El motor de animación no es" % que)
		printerr("[FATAL] el de este test, así que NO se puede comprobar nada. Si esto")
		printerr("[FATAL] aparece, el test está viejo o el motor se ha cambiado de API.")
		quit(1)
		return
	if anim == null or not is_instance_valid(anim):
		printerr("[FATAL] este test necesita un AnimationPlayer con modelo; sin él no")
		printerr("[FATAL] se puede reproducir el caso del usuario. No se salta en")
		printerr("[FATAL] silencio: un hueco aquí es información, y hay que verla.")
		quit(1)


func _process(_delta: float) -> bool:
	match _fase:
		0:
			_armar()
			_fase = 1
		1:
			_api(_anim, "estado_actual")
			_api(_anim, "reproductor_en_manual")
			_caso_del_usuario()
			_fase = 2
		2:
			_api(_anim, "estado_actual")
			_muerte_gana()
			_fase = 3
		3:
			_api(_anim, "reproductor_en_manual")
			_play_externo_es_inerte()
			_fase = 4
		4:
			_api(_anim, "arbol")
			_solo_un_motor()
			_fase = 5
		5:
			_api(_anim, "arbol")
			_la_maquina()
			_fase = 6
		6:
			_enemigo_con_rig()
			_fase = 7
		_:
			_limpiar()
			print("[TEST] un_motor_animacion: %d ok, %d fallos" % [_ok, _fallos])
			quit(_fallos)
			return true
	return false


# --- ARMAR ---------------------------------------------------------------

func _armar() -> void:
	_p = PLAYER.new()
	# EL ORDEN IMPORTA y no es cosmético: el nodo tiene que estar DENTRO del
	# árbol de escenas ANTES de que se cuelgue el modelo. El `AnimationTree`
	# resuelve `root_node` y `anim_player` como rutas RELATIVAS a sí mismo, y
	# si se monta con el reproductor todavía fuera de la escena esas rutas no
	# existen: el árbol queda activo, los estados cambian, las transiciones
	# corren... y ninguna pista escribe el esqueleto. MEDIDO: con este orden
	# invertido los estados cambiaban bien y el Σ|Δpose daba 0,00000 en los
	# cuatro sitios. Un fallo así no dice "no encuentro el esqueleto": dice
	# "todo funciona" mientras el muñeco no se mueve. Por eso este test mide la
	# POSE y no solo el nombre del estado.
	root.add_child(_p)
	_p.fijar_identidad("H", CLASE)
	_p.aplicar_clase(CLASE)
	var modelo: Node3D = _p.get_node_or_null("Modelo") as Node3D
	_chk(modelo != null, "el jugador cuelga su modelo 3D", "sin modelo no hay caso")
	if modelo == null:
		return
	_anim = LOCALIZADOR.reproductor(modelo)
	_skel = LOCALIZADOR.esqueleto(modelo)
	_chk(_anim != null, "el modelo tiene AnimationPlayer")
	_chk(_skel != null and _skel.get_bone_count() > 0, "el modelo tiene esqueleto")
	if _anim == null or _skel == null:
		return
	_chk(_anim.has_animation("idle") and _anim.has_animation("walk") \
			and _anim.has_animation("attack") and _anim.has_animation("die"),
		"el rig trae los cuatro clips (idle/walk/attack/die)",
		"clips=%s" % str(_anim.get_animation_list()))
	_pose = _huella()


## Los cuatro estados que el reproductor tiene en su librería.
func _huella() -> PackedFloat32Array:
	var salida: PackedFloat32Array = PackedFloat32Array()
	if _skel == null:
		return salida
	for i in _skel.get_bone_count():
		var q: Quaternion = _skel.get_bone_pose_rotation(i)
		salida.append(q.x)
		salida.append(q.y)
		salida.append(q.z)
		salida.append(q.w)
	return salida


## Σ|Δpose| sobre los 19 huesos. Es "cuánto se movió el muñeco este frame", y es
## la ÚNICA medida que separa "se ve el tajo" de "se ve la marcha": los dos
## clips mueven huesos, los dos dejando el mismo nombre de clip puesto.
func _movimiento() -> float:
	var ahora: PackedFloat32Array = _huella()
	var d: float = 0.0
	for i in mini(ahora.size(), _pose.size()):
		d += absf(ahora[i] - _pose[i])
	_pose = ahora
	return d


## Un frame del juego: el jugador se mueve y su `_physics_process` corre, que
## es lo que mueve la animación. Se llama a SU método, no a una imitación.
func _frame_jugador(velocidad: float) -> float:
	_p.velocity = Vector3(0.0, 0.0, -velocidad)
	_p.call("_actualizar_animacion", DT)
	return _movimiento()


## Frames hasta que el estado de la máquina sea `wanted`, o se agoten.
## Devuelve los frames que tardó, o -1 si no llegó. El tope es lo que evita
## que un test que espera algo imposible se quede colgado para siempre.
func _frames_hasta(estado_wanted: String, tope: int) -> int:
	for i in tope:
		if ARBOL.estado_actual(_anim) == estado_wanted:
			return i
		_frame_jugador(_velocidad())
	return -1


## La velocidad de locomoción REAL de este jugador, no un número inventado.
func _velocidad() -> float:
	return float(_p.stats.vel_mov)


# --- (1) EL CASO EXACTO DEL USUARIO --------------------------------------
## "caminas, golpeas, el mob muere" → después de N frames LOCOMOCIÓN, no attack.

func _caso_del_usuario() -> void:
	if _anim == null or _skel == null:
		_chk(false, "caso del usuario: sin rig no se puede reproducir")
		return
	# --- caminas
	var mov_caminando: float = 0.0
	for i in FRAMES_CAMINAR:
		mov_caminando += _frame_jugador(_velocidad())
	var estado_caminando: String = ARBOL.estado_actual(_anim)
	_chk(estado_caminando == "locomocion",
		"caminando, el estado es locomocion", "estado=%s" % estado_caminando)
	_chk(mov_caminando / float(FRAMES_CAMINAR) > 0.01,
		"caminando, el esqueleto se mueve de verdad (no es un muñeco tieso)",
		"Σ|Δpose| medio=%.5f" % (mov_caminando / float(FRAMES_CAMINAR)))
	# --- golpeas
	_p.set("_t_swing", 0.32)
	var mov_tajo: float = 0.0
	var viste_tajo: bool = false
	var estado_durante_tajo: String = ""
	for i in FRAMES_TAJO:
		var mov: float = _frame_jugador(_velocidad())
		mov_tajo += mov
		estado_durante_tajo = ARBOL.estado_actual(_anim)
		if estado_durante_tajo == "attack":
			viste_tajo = true
	_chk(viste_tajo, "el tajo PASA POR EL ESTADO attack (es un estado, no un play())",
		"estados vistos=%s" % estado_durante_tajo)
	_chk(mov_tajo / float(FRAMES_TAJO) > 0.01,
		"durante el tajo el esqueleto se mueve (el tajo se VE)",
		"Σ|Δpose| medio=%.5f" % (mov_tajo / float(FRAMES_TAJO)))
	# --- Y AQUÍ ESTÁ EL BUG: después del tajo tiene que volver a caminar.
	var mov_tras: float = 0.0
	for i in FRAMES_TRAS_TAJO:
		mov_tras += _frame_jugador(_velocidad())
	var estado_final: String = ARBOL.estado_actual(_anim)
	_chk(estado_final == "locomocion",
		"BUG DEL USUARIO: tras el tajo vuelve a LOCOMOCION, no se queda en attack",
		"estado=%s  (si dice 'attack', el bug volvió)" % estado_final)
	_chk(mov_tras / float(FRAMES_TRAS_TAJO) > 0.01,
		"y vuelve a ANDAR de verdad, no solo a cambiar de nombre de estado",
		"Σ|Δpose| medio=%.5f" % (mov_tras / float(FRAMES_TRAS_TAJO)))
	# Y una comprobación del CONTRARIO explícito, que es la que lembra el
	# síntoma: el estado `attack` tiene que ser TRANSITORIO. Si el tajo no se
	# suelta nunca, el tiempo que se dura en attack no tiene tope.
	_p.set("_t_swing", 0.32)
	var frame_salida: int = _frames_hasta("locomocion", 120)
	_chk(frame_salida >= 0,
		"el estado attack es TRANSITORIO: se sale solo sin que nadie lo ordene",
		"tras 120 frames seguía en %s" % ARBOL.estado_actual(_anim))


# --- (2) LA MUERTE GANA Y SE QUEDA ---------------------------------------

func _muerte_gana() -> void:
	if _anim == null or _skel == null:
		_chk(false, "muerte: sin rig no se puede reproducir")
		return
	# Un frame para que esté en locomoción antes de morir.
	_frame_jugador(_velocidad())
	_p.call("take_damage", 99999.0, null, false)
	_chk(not _p.esta_vivo(), "el jugador está muerto")
	var vio_die: bool = false
	for i in FRAMES_TAJO:
		_frame_jugador(0.0)
		if ARBOL.estado_actual(_anim) == "die":
			vio_die = true
	_chk(vio_die, "al morir pasa por el estado die (no es un play() suelto)")
	# Y ahora lo importante: que NO se levante solo. El `_actualizar_animacion`
	# del jugador sigue corriendo y `mezclar` sigue pidiendo locomoción cada
	# frame; aun así tiene que quedarse en `die`.
	var tras_muerte: String = ""
	for i in 120:
		_frame_jugador(_velocidad())
		if i == 119:
			tras_muerte = ARBOL.estado_actual(_anim)
	_chk(tras_muerte == "die",
		"BUENO: tras morir el estado es die, y NO vuelve a caminar solo",
		"estado=%s  (si dice 'locomocion', el cadaver camina)" % tras_muerte)
	# La muerte es un clip que TERMINA. El `die` dura 1,208 s: al cabo de un
	# rato el cadaver llega a su pose final y SE QUEDA ahí, quieto. Eso no es el
	# bug del tajo pegado al revés: es lo contrario, es que el clip acabó.
	#
	# Lo que hay que comprobar es que el `die` AVANZÓ, no que siga moviéndose:
	# un cadaver que no se movió NADA es un clip que no se reprodujo.
	var tree_d: AnimationTree = ARBOL.arbol(_anim)
	var pos_die: float = 0.0
	if tree_d != null:
		pos_die = float(tree_d.get("parameters/die/current_position"))
	_chk(pos_die > 0.0,
		"el clip die AVANZÓ (el cadaver se tiró al suelo, no se quedó en el origen)",
		"pos_die=%.3f de %.3f" % [pos_die, 1.208])
	# Y ahora bien: un cadaver que se moviera para SIEMPRE sería un bucle, que
	# es el mismo tipo de bug (un estado del que no se sale). El `die` no cicla.
	if tree_d != null:
		var largo: float = _anim.get_animation("die").length
		_chk(absf(pos_die - largo) < 0.05,
			"...y se QUEDA en la pose final (un cadaver no hace un bucle)",
			"pos_die=%.3f  largo del clip=%.3f" % [pos_die, largo])


# --- (3) EL `play()` DE FUERA ES INERTE -----------------------------------
## No es que "no lo usamos": es que medido no mueve el esqueleto. Por eso el
## bug no puede volver por la misma puerta.

func _play_externo_es_inerte() -> void:
	if _anim == null or _skel == null:
		_chk(false, "play() inerte: sin rig no se puede comprobar")
		return
	_chk(ARBOL.reproductor_en_manual(_anim),
		"el reloj del AnimationPlayer está en MANUAL (no es un segundo conductor)")
	# Estado antes, para no medir el cross-fade que estuviera de paso.
	_pose = _huella()
	# Todo lo que el código OLD hacía para pegarle un tajo por la puerta de
	# atrás: `play()` del clip entero.
	_anim.play("attack")
	var mov: float = 0.0
	for i in 20:
		mov += _movimiento()
	_chk(mov < 0.0001,
		"UN `play('attack')` de fuera NO escribe el esqueleto: es INERTE",
		"Σ|Δpose| sobre 20 frames=%.8f  (si sale >0, el play() todavía manda)" % mov)
	# Y el motor de verdad sigue escribiendo, que es lo otro que hay que probar:
	# que el muñeco no se quedó tieso por haber puesto el reloj en manual.
	#
	# OJO: primero hay que REVIVIR. El test va en orden y para aquí el jugador
	# sigue muerto del caso anterior, así que el estado es `die`: su clip ya
	# acabó (1,208 s) y el cadaver está en su pose final, quieto y muy
	# correctamente. Medir eso y concluir "el motor no mueve" sería un test que
	# se pasa a sí mismo por el motivo equivocado. Y de paso queda probado que
	# `revivir` abre la puerta del `die`.
	_p.call("revivir")
	_chk(_p.esta_vivo(), "el jugador revivió")
	_pose = _huella()
	var mov_motor: float = 0.0
	for i in 20:
		mov_motor += _frame_jugador(_velocidad())
	_chk(mov_motor > 0.01,
		"...pero el motor (el árbol) sigue moviendo el muñeco",
		"Σ|Δpose| sobre 20 frames=%.5f  (si sale 0, el reloj manual lo congeló)" % mov_motor)
	_chk(ARBOL.estado_actual(_anim) == "locomocion",
		"y al revivir vuelve a locomoción (el die tenía una salida)",
		"estado=%s" % ARBOL.estado_actual(_anim))


# --- (4) HAY UN SOLO MOTOR -----------------------------------------------

func _solo_un_motor() -> void:
	if _anim == null:
		_chk(false, "un solo motor: sin AnimationPlayer no se puede comprobar")
		return
	var arboles: int = 0
	for n in _anim.get_children():
		if n is AnimationTree:
			arboles += 1
	_chk(arboles == 1, "hay UN AnimationTree, no dos motores peleando",
		"encontrados=%d" % arboles)
	var tree: AnimationTree = ARBOL.arbol(_anim)
	_chk(tree != null, "el árbol existe")
	if tree == null:
		return
	_chk(tree.active, "el árbol está activo")
	_chk(tree.tree_root is AnimationNodeStateMachine,
		"la raíz del árbol es una MÁQUINA DE ESTADOS, no un BlendTree suelto",
		"tipo=%s" % tree.tree_root.get_class())


# --- (5) LA MÁQUINA, ADEMÁS ----------------------------------------------
## Los cuatro clips son estados y el estado se puede LEER. Que se pueda leer
## es lo que permite que un test afirme sobre él, y lo que va a permitir que el
## HUD o el debug digan "está pegado en attack" sin inventarlo.

func _la_maquina() -> void:
	if _anim == null:
		_chk(false, "la maquina: sin AnimationPlayer no se puede comprobar")
		return
	var tree: AnimationTree = ARBOL.arbol(_anim)
	if tree == null:
		_chk(false, "la maquina: no hay arbol")
		return
	var sm: AnimationNodeStateMachine = tree.tree_root as AnimationNodeStateMachine
	_chk(sm != null, "la raiz es un AnimationNodeStateMachine")
	if sm == null:
		return
	for estado in ["locomocion", "attack", "die"]:
		_chk(sm.has_node(StringName(estado)),
			"la maquina tiene el estado '%s'" % estado,
			"nodos=%s" % str(sm.get_node_list()))
	# El `attack -> locomocion` tiene que ser AUTOMÁTICO. Si fuera manual,
	# haría falta que alguien lo pidiera, y "nadie lo pide" es el bug original.
	var auto: bool = false
	for i in 8:
		var tr: AnimationNodeStateMachineTransition = sm.get_transition(i) as AnimationNodeStateMachineTransition
		if tr == null:
			break
		if str(sm.get_transition_from(i)) == "attack" \
				and str(sm.get_transition_to(i)) == "locomocion" \
				and tr.advance_mode == AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO:
			auto = true
	_chk(auto,
		"la transicion attack -> locomocion es AUTOMATICA (el tajo se suelta solo)",
		"sin esto, alguien tiene que acordarse de devolver al personaje a caminar")
	# Y el `die` NO tiene salida: es terminal por construcción, no por cortesía.
	var die_sale: bool = false
	for i in 8:
		var tr: AnimationNodeStateMachineTransition = sm.get_transition(i) as AnimationNodeStateMachineTransition
		if tr == null:
			break
		if str(sm.get_transition_from(i)) == "die":
			die_sale = true
	_chk(not die_sale, "el estado die NO tiene transicion de salida (es terminal)")
	# La mezcla sigue en la ruta de siempre, porque tres tests la leen.
	_frame_jugador(_velocidad())
	var b: Variant = tree.get("parameters/locomocion/blend_position")
	_chk(b != null and absf(float(b)) > 0.5,
		"la mezcla se sigue publicando en parameters/locomocion/blend_position",
		"valor=%s  (los tests 49/50/70 y la herramienta lo leen)" % str(b))


# --- (6) EL ENEMIGO CON RIG ------------------------------------------------
## El mismo bug, del otro lado: el bicho ataca, y cuando muere no se levanta.

func _enemigo_con_rig() -> void:
	if ESCENA_ENEMIGO == null:
		_chk(true, "enemigo: sin escena, la parte se salta")
		return
	_e = ESCENA_ENEMIGO.instantiate()
	root.add_child(_e)
	_e.call("configurar", ARQ_GOBLIN)
	var modelo: Node3D = _e.get_node_or_null("Modelo") as Node3D
	var eanim: AnimationPlayer = LOCALIZADOR.reproductor(modelo)
	if eanim == null:
		# El goblin es el ÚNICO arquetipo con rig. Si su `.glb` no está, esta
		# parte no se puede reproducir y NO se puede fingir que sí: el marco es
		# un bool, se pasa, y el motivo queda impreso arriba del todo.
		print("[AVISO] el goblin no trae modelo 3D en este entorno: la parte del")
		print("[AVISO] enemigo con rig NO se ha comprobado (el resto del test sí).")
		print("[AVISO] motivo: %s" % str(modelo))
		_chk(true, "enemigo: sin rig, la parte del enemigo se salta")
		return
	var eskel: Skeleton3D = LOCALIZADOR.esqueleto(modelo)
	_chk(eskel != null, "el goblin colgó su esqueleto")
	if eskel == null:
		return
	_chk(ARBOL.has_method("arbol") and ARBOL.arbol(eanim) != null,
		"el goblin tiene su motor de animación")
	# El bicho camina → ataca → muere.
	var skel_viejo: Skeleton3D = _skel
	var anim_viejo: AnimationPlayer = _anim
	var pose_vieja: PackedFloat32Array = _pose
	_skel = eskel
	_anim = eanim
	_pose = _huella()
	for i in 20:
		_e.set("velocity", Vector3(0.0, 0.0, -6.0))
		_e.call("_actualizar_mezcla")
		_movimiento()
	_chk(ARBOL.estado_actual(_anim) == "locomocion",
		"el goblin caminando está en locomocion",
		"estado=%s" % ARBOL.estado_actual(_anim))
	# Se asigna la PROPIEDAD `estado`, no el `_estado` de backing: la propiedad
	# es la que dispara `_reproducir_estado`, que es la que le pide el estado al
	# motor. Poner el `_estado` por debajo deja al motor sin saber nada, y este
	# test medía un caso que el juego no tiene.
	_e.set("estado", 2)  # ATACAR
	var vio_attack: bool = false
	for i in 20:
		_e.set("velocity", Vector3.ZERO)
		_e.call("_actualizar_mezcla")
		if ARBOL.estado_actual(_anim) == "attack":
			vio_attack = true
	_chk(vio_attack, "el goblin atacando pasa por el estado attack",
		"estado=%s" % ARBOL.estado_actual(_anim))
	_e.call("die")
	_chk(not _e.call("esta_vivo"), "el goblin esta muerto")
	var vio_die: bool = false
	for i in 90:
		# El bicho muerto y con velocidad: si el árbol volviera a mandar, el
		# cadaver se LEVANTARÍA. Es el mismo bug del jugador, del revés.
		_e.set("velocity", Vector3(0.0, 0.0, -6.0))
		_e.call("_actualizar_mezcla")
		if ARBOL.estado_actual(_anim) == "die":
			vio_die = true
	_chk(vio_die, "el goblin muerto pasa por el estado die")
	_chk(ARBOL.estado_actual(_anim) == "die",
		"el cadaver NO se levanta solo: se queda en die",
		"estado=%s" % ARBOL.estado_actual(_anim))
	_skel = skel_viejo
	_anim = anim_viejo
	_pose = pose_vieja


# --- CIERRE ---------------------------------------------------------------

func _limpiar() -> void:
	if _e != null and is_instance_valid(_e):
		_e.queue_free()
	_e = null
	if _p != null and is_instance_valid(_p):
		_p.queue_free()
	_p = null
	_anim = null
	_skel = null
	_pose = PackedFloat32Array()


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] " + nombre + ("" if detalle == "" else "  <-- " + detalle))
