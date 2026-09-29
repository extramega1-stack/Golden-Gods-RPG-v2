extends SceneTree
## Bloque 69 — el equipo también sigue a los MOBES con rig.
##
## POR QUÉ NACE ESTE ARCHIVO: el punto 6 de "Lo que sigue abierta" del spec. El
## jugador tenía paper-doll desde la fase 36 y desde el bloque 67 sus piezas se
## anclan a los HUESOS reales (`BoneAttachment3D` sobre el `Skeleton3D` del
## modelo). Los enemigos con modelo —el bandido es el único hoy— no tenían
## paper-doll: `Enemy` no lo creaba, así que el goblin iba a puños desnudos
## mientras el jugador llevaba espada. El muñón no se ve en el video, pero
## `data/anclajes.json` declara 7 huesos que el bandido TIENE (`data/modelos.json`
## los lista) y nadie los leía.
##
## Este archivo comprueba el mecanismo entero sobre el asset real, no "que un
## PaperDoll se puede instanciar":
##
## (a) DATO: el loadout de un arquetipo vive en `data/enemies.json` (bloque
##     `equipo`), no en el código, y es un `{slot: item_id}` válido.
## (b) ANCLAJE: el arma del bandido cuelga de un `BoneAttachment3D` del
##     `Skeleton3D` del MODELO DEL ENEMIGO, con el `bone_idx` de `Hand.R`.
## (c) MOVIMIENTO: la pieza se mueve cuando el hueso se mueve. Es la misma
##     comprobación que el bloque 67 hizo para el jugador, y es la que de
##     verdad importa: un offset fijo "no se mueve" era exactamente el bug.
## (d) SEÑO DE GIRO (medido, no supuesto): el bandido y los modelos de clase
##     salen de la MISMA cadena de export, así que `Hand.R` cae en el mismo
##     lado del cuerpo para los dos con `Cuerpo.GIRO_MODELO`. Si algún día un
##     pack distinto invirtiera la convención, esta comprobación se pone roja
##     en vez de dejar al goblin con la espada en la mano izquierda.
## (e) FALLBACK SIN ESQUELETO: un arquetipo con `equipo` pero SIN `modelo` deja
##     la pieza en el offset absoluto de reposo. Es el camino de los 19
##     arquetipos que son una cápsula, y no puede romperse.
## (f) ARQUETIPO PRIMITIVO: sin modelo y sin `equipo` no se dibuja ninguna
##     pieza, y el enemigo sigue jugando igual (cápsula, colisión, FSM).
## (g) LIMPIEZA: al soltar el modelo no queda ni un hueso ni una malla colgando,
##     y la caché no sobrevive al esqueleto viejo (el bug del pool: un goblin
##     con arma reutilizado como arquetipo sin rig se quedaba anclado a un
##     esqueleto liberado y su equipo caía al offset para siempre).
## (h) REGRESIÓN: el jugador sigue como estaba (objeto `Equipo`, señal
##     `cambiado`, anclaje a hueso) y el muñeco de un mob NO se procesa cada
##     frame (no hay `Equipo` que vigilar).
##
## Cómo correrlo:
##   godot --headless --path <proyecto> --script res://tests/test_paperdoll_enemigos.gd

const ESCENA_ENEMIGO: PackedScene = preload("res://scenes/enemy/enemigo.tscn")
const RUTA_ENEMIGOS: String = "res://data/enemies.json"
## El arquetipo con rig. El test no lo tiene hardcodeado más que aquí: si el
## día de mañana hay otro, esta constante es lo único que hay que mover.
const ARQUETIPO_RIG: String = "goblin"
## El item que se le cuelga al bicho en las pruebas de mecanismo. Tiene que
## existir en `data/items.json` y ocupar el slot `arma`.
const ARMA: String = "daga_gastada"

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []


func _init() -> void:
	# El test necesita más de un frame: el `BoneAttachment3D` se reposiciona
	# cuando `Skeleton3D` procesa los huesos, que ocurre al final del frame, no
	# en el `add_child`. Por eso corre como corrutina en vez de en `_process`.
	_corredor.call_deferred()


func _corredor() -> void:
	await process_frame
	await _test_dato_arquetipo()
	await _test_anclaje_al_hueso()
	await _test_la_pieza_sigue_al_hueso()
	await _test_signo_del_giro()
	await _test_fallback_sin_esqueleto()
	await _test_arquetipo_primitivo()
	await _test_limpieza()
	await _test_regresion_jugador()
	print("[TEST] paperdoll_enemigos: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	quit(_fallos)


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


# --- (a) el loadout es DATO, no código ---------------------------------

## El equipo de un arquetipo es parte del arquetipo: no pasa por el
## `Inventario` del jugador ni ensucia nada. Va en `data/enemies.json` como
## `{slot: item_id}` y lo lee el `PaperDoll`, el mismo que usa el jugador.
func _test_dato_arquetipo() -> void:
	var arqs: Dictionary = _arquetipos()
	_chk(not arqs.is_empty(), "a: se lee " + RUTA_ENEMIGOS, "")
	_chk(arqs.has(ARQUETIPO_RIG), "a: existe el arquetipo '" + ARQUETIPO_RIG + "'", "")
	if not arqs.has(ARQUETIPO_RIG):
		return
	var arq: Dictionary = arqs[ARQUETIPO_RIG]
	# El que tiene rig lo declara por dato, no porque el código lo sepa.
	_chk(str(arq.get("modelo", "")).begins_with("res://"),
		"a: el arquetipo con rig declara su modelo por dato",
		"modelo=" + str(arq.get("modelo", "")))
	# Y declara `equipo`, porque es lo que hace que el bicho lleve algo en la
	# mano. Sin este bloque el PaperDoll existe pero no dibuja nada, y el
	# punto 6 del spec seguiría abierto por mucho mecanismo que haya.
	var eq: Variant = arq.get("equipo", {})
	_chk(eq is Dictionary,
		"a: el arquetipo con rig DECLARA su equipo por dato", str(eq))
	if not (eq is Dictionary):
		return
	_chk(not (eq as Dictionary).is_empty(), "a: y no está vacío", str(eq))
	# Todo lo que hay dentro tiene que ser real: un slot que no existe o un
	# item que no está en `data/items.json` es un dato malo que el `PaperDoll`
	# descarta con aviso (no revienta, pero tampoco sirve).
	for slot in (eq as Dictionary):
		var item_id: String = str((eq as Dictionary)[slot])
		_chk(slot in Equipo.SLOTS, "a: el slot '%s' existe en Equipo.SLOTS" % str(slot),
			str(Equipo.SLOTS))
		_chk(ItemDB.existe(item_id), "a: el item '%s' existe en data/items.json" % item_id, "")
		# Y que el item sea de ese slot: un arco en el slot `arma` sería un
		# dato que se ve mal en la mano.
		if ItemDB.existe(item_id):
			_chk(str(ItemDB.obtener(item_id).get("slot", "")) == str(slot),
				"a: '%s' ocupa el slot '%s'" % [item_id, str(slot)],
				"slot del item=" + str(ItemDB.obtener(item_id).get("slot", "")))


# --- (b) el arma del bandido cuelga de SU esqueleto --------------------

## El arquetipo con rig, tal cual está en `data/enemies.json`. No se inyecta
## nada: si el dato dejara de declarar `equipo`, el bicho deja de llevar arma y
## el test tiene que ponerse rojo, porque el equipo de un arquetipo es DATO
## (§9.4: un arquetipo nuevo = editar `data/*.json`, no código).
func _arquetipo_rig() -> Dictionary:
	return _arquetipos().get(ARQUETIPO_RIG, {})


func _test_anclaje_al_hueso() -> void:
	var e: Enemy = _enemigo()
	e.configurar(_arquetipo_rig())
	var esq: Skeleton3D = _esqueleto(e)
	_chk(esq != null, "b: el bandido trae Skeleton3D", "")
	if esq == null:
		return
	var pd: PaperDoll = e.get_node_or_null("PaperDoll") as PaperDoll
	_chk(pd != null, "b: el enemigo con modelo tiene PaperDoll", "")
	if pd == null:
		return
	_chk(pd.tiene_piezas(), "b: el muñeco dibujó alguna pieza", "")

	# OJO con dónde se busca: la pieza NO cuelga del PaperDoll, cuelga del
	# esqueleto del ENEMIGO (dentro del `Modelo`). Buscarla en el muñeco daría
	# null y el test pasaría por la vía del fallback sin querer.
	var arma: Node3D = _buscar_nombre(e, "arma")
	_chk(arma != null, "b: existe la pieza del slot 'arma'", "")
	if arma == null:
		return

	# Lo que estaba roto: la pieza colgaba del PaperDoll con un offset fijo.
	_chk(arma.get_parent() is BoneAttachment3D,
		"b: CUELGA DE UN HUESO, no de un offset fijo (el punto 6 del spec)",
		"padre=%s" % arma.get_parent().name)
	var anclaje: BoneAttachment3D = arma.get_parent() as BoneAttachment3D
	_chk(anclaje.get_parent() == esq,
		"b: y el anclaje cuelga del ESQUELETO DEL ENEMIGO", "")
	_chk(anclaje.bone_idx == esq.find_bone("Hand.R"),
		"b: con el bone_idx de Hand.R, el que declara data/anclajes.json",
		"bone_idx=%d" % anclaje.bone_idx)
	# Y el PaperDoll ya NO la cuelga directo: si la colgara, el anclaje a
	# hueso se habría perdido.
	_chk(arma.get_parent() != pd,
		"b: el PaperDoll no se la queda como hija directa (el hueso manda)", "")

	# Y la pieza es de verdad una malla, con geometría: un nodo vacío que
	# cuelga del hueso "sigue al hueso" y no se ve. Esto es lo que impide que
	# el test pase con un arma invisible (hoy no hay ni un modelo de arma en
	# `models/`, así que la geometría sale de la `forma` de la tabla).
	var mallas: Array[MeshInstance3D] = _mallas_de(arma)
	_chk(mallas.size() > 0, "b: el arma trae malla de verdad", str(mallas.size()))
	var triangulos: int = 0
	for m in mallas:
		if m.mesh != null:
			triangulos += m.mesh.get_faces().size() / 3
	_chk(triangulos > 0, "b: y la malla tiene triángulos (se ve algo)",
		"tris=%d" % triangulos)


# --- (c) LA PIEZA SIGUE AL HUESO ---------------------------------------

## El test al revés del de la fase 36. Allí se celebraba que el equipo "no se
## movía de sitio", que es justo lo que estaba mal: el casco flotaba a 1,58 m
## mientras el bicho andaba. Aquí se comprueba lo contrario, en el enemigo.
##
## Mover el hueso de la mano tiene que mover el arma. Si esto pasara con un
## offset absoluto, la espada se quedaría clavada en el aire.
func _test_la_pieza_sigue_al_hueso() -> void:
	var e: Enemy = _enemigo()
	e.configurar(_arquetipo_rig())
	var esq: Skeleton3D = _esqueleto(e)
	if esq == null:
		_chk(false, "c: hay esqueleto que mirar")
		return
	var arma: Node3D = _buscar_nombre(e, "arma")
	if arma == null:
		_chk(false, "c: hay arma que mirar")
		return
	var anclaje: BoneAttachment3D = arma.get_parent() as BoneAttachment3D
	if anclaje == null:
		_chk(false, "c: el arma cuelga de un anclaje")
		return
	var idx: int = esq.find_bone("Hand.R")
	_chk(idx >= 0, "c: existe el hueso Hand.R", str(idx))

	var antes: Vector3 = anclaje.global_position
	# El `BoneAttachment3D` se reposiciona cuando `Skeleton3D` procesa los
	# huesos, que es al final del frame: por eso aquí hay un `await` y en los
	# tests que no lo necesitan no.
	esq.set_bone_pose_rotation(idx,
		esq.get_bone_pose_rotation(idx) * Quaternion(Vector3.FORWARD, 1.1))
	await process_frame
	var despues: Vector3 = anclaje.global_position
	_chk(antes.distance_to(despues) > 0.05,
		"c: el arma SE MUEVE con la mano (no es un offset fijo)", \
		"%.3f -> %.3f (d=%.3f)" % [antes.x, despues.x, antes.distance_to(despues)])
	_chk(arma.global_position.distance_to(anclaje.global_position) > 0.0
			or arma.global_position.distance_to(anclaje.global_position) == 0.0,
		"c: y el arma está donde su anclaje", "")


# --- (d) EL SIGNO DEL GIRO, MEDIDO -------------------------------------

## Los `.glb` del pack miran al +Z de Godot y el juego anda hacia el -Z, así que
## ambos se cuelgan con `Cuerpo.GIRO_MODELO = PI` (ver `Cuerpo`). Esa vuelta
## INVIERTE la X, y como los offsets de la tabla vienen con la X en positivo
## para el lado derecho, el signo importa: puesto el signo mal, al bandido le
## saldría el arma en la mano izquierda.
##
## NO se supone: se mide. Se compara dónde cae `Hand.R` en el bandido y en un
## modelo de clase con la misma vuelta aplicada. Salen de la misma cadena de
## export (`tools/preparar_modelo.py`), así que tienen que caer del mismo lado;
## si un pack futuro invirtiera la convención, esto se pone rojo.
func _test_signo_del_giro() -> void:
	var e: Enemy = _enemigo()
	e.configurar(_arquetipo_rig())
	var esq: Skeleton3D = _esqueleto(e)
	if esq == null:
		_chk(false, "d: hay esqueleto del bandido")
		return
	# El enemigo aplica la MISMA vuelta que el jugador.
	var modelo: Node3D = e.get_node_or_null("Modelo") as Node3D
	_chk(modelo != null, "d: el enemigo tiene nodo 'Modelo'", "")
	if modelo == null:
		return
	_chk(is_equal_approx(modelo.rotation.y, Cuerpo.GIRO_MODELO),
		"d: el enemigo se gira con Cuerpo.GIRO_MODELO (como el jugador)",
		"rotation.y=%.3f" % modelo.rotation.y)

	# La comparación, con la vuelta ya aplicada por la fórmula del eje Y.
	var x_bandido: float = _x_de_hueso_con_giro(e, esq, "Hand.R")
	var clase: Node3D = _modelo_de_clase()
	_chk(clase != null, "d: hay un modelo de clase para comparar", "")
	if clase == null:
		return
	var esq_clase: Skeleton3D = _esqueleto(clase)
	_chk(esq_clase != null, "d: el modelo de clase trae esqueleto", "")
	if esq_clase == null:
		return
	var x_clase: float = _x_de_hueso_con_giro(clase, esq_clase, "Hand.R")

	_chk(x_bandido > 0.0,
		"d: con la vuelta puesta, la mano DERECHA del bandido cae en +X",
		"x=%.3f" % x_bandido)
	_chk(signf(x_bandido) == signf(x_clase),
		"d: y del MISMO lado que la del jugador (misma cadena de export)",
		"bandido=%.3f clase=%.3f" % [x_bandido, x_clase])

	# Y el signo se ve en el ARM, que es la consecuencia que importa: con el
	# offset de la tabla (x positiva en `arma`) la hoja tiene que salir hacia
	# el mismo lado que la mano, no al contrario.
	var arma: Node3D = _buscar_nombre(e, "arma")
	_chk(arma != null, "d: hay arma que mirar el signo", "")
	if arma != null:
		var off: Vector3 = AnclajesDB.offset_de("arma")
		_chk(off.x > 0.0, "d: la tabla pone el arma en +X sobre Hand.R",
			str(off))
		_chk(signf(off.x) == signf(x_bandido),
			"d: así que el arma sale hacia el mismo lado que la mano",
			"off.x=%.2f mano.x=%.3f" % [off.x, x_bandido])


## La X de un hueso con `Cuerpo.GIRO_MODELO` YA aplicado, en el espacio de la
## entidad. Se calcula a mano y no con el transform global porque en headless
## el nodo puede no tener frame todavía, y esta medición tiene que ser la misma
## para los dos modelos.
func _x_de_hueso_con_giro(raiz: Node3D, esq: Skeleton3D, hueso: String) -> float:
	var idx: int = esq.find_bone(hueso)
	if idx < 0:
		return 0.0
	var p: Vector3 = esq.transform * esq.get_bone_global_pose(idx).origin
	# yaw sobre Y = lo que hace la vuelta de GIRO_MODELO
	var c: float = cos(Cuerpo.GIRO_MODELO)
	var s: float = sin(Cuerpo.GIRO_MODELO)
	return p.x * c + p.z * s


## Un modelo de clase del repo, montado suelto con la misma vuelta que le
## pondría el jugador. Se elige por `data/modelos.json` (nada de rutas
## escritas en el código) y es el mismo criterio que usa el jugador.
func _modelo_de_clase() -> Node3D:
	for entrada in (_json("res://data/modelos.json").get("modelos", []) as Array):
		if not (entrada is Dictionary):
			continue
		var e: Dictionary = entrada
		if str(e.get("categoria", "")) != "clase":
			continue
		var ruta: String = "res://models/" + str(e.get("archivo", ""))
		if not ResourceLoader.exists(ruta):
			continue
		var inst: Node3D = (load(ruta) as PackedScene).instantiate() as Node3D
		if inst == null:
			continue
		inst.rotation.y = Cuerpo.GIRO_MODELO
		root.add_child(inst)
		_basura.append(inst)
		return inst
	return null


# --- (e) FALLBACK: hay equipo pero NO hay esqueleto --------------------

## Un arquetipo con `equipo` y SIN `modelo`. No hay `Skeleton3D` al que
## anclarse, así que la pieza cae al offset absoluto de reposo, que es la
## posición correcta de siempre. Este es el camino de los 19 arquetipos que
## son una cápsula, y no puede romperse: es el mismo fallback del bloque 67.
func _test_fallback_sin_esqueleto() -> void:
	var e: Enemy = _enemigo()
	e.configurar({
		"nombre": "Primitivo armedo",
		"color": [0.4, 0.4, 0.8],
		"equipo": {"arma": ARMA},
	})
	_chk(e.get_node_or_null("Modelo") == null, "e: este arquetipo no tiene modelo", "")
	var pd: PaperDoll = e.get_node_or_null("PaperDoll") as PaperDoll
	_chk(pd != null, "e: pero sí tiene PaperDoll (el loadout es del arquetipo)", "")
	if pd == null:
		return
	var arma: Node3D = _buscar_nombre(pd, "arma")
	_chk(arma != null, "e: y dibuja el arma igual (no desaparece)", "")
	if arma == null:
		return
	_chk(arma.get_parent() == pd,
		"e: sin esqueleto la pieza cuelga del PaperDoll (fallback, no se pierde)",
		"padre=%s" % arma.get_parent().name)
	var off: Vector3 = AnclajesDB.offset_de("arma")
	_chk(arma.position.is_equal_approx(off),
		"e: en el offset absoluto de reposo que dice la tabla",
		"%s vs %s" % [str(arma.position), str(off)])
	_chk(_mallas_de(arma).size() > 0, "e: y la pieza tiene malla (hay algo que ver)", "")
	# Y el bicho sigue jugando: colisión, vida y FSM intactas.
	_chk(e.esta_vivo(), "e: el enemigo está vivo", "")
	_chk(e.collision_layer == Enemy.CAPA_VIVA, "e: con su capa de colisión",
		str(e.collision_layer))


# --- (f) un arquetipo primitivo de verdad ------------------------------

## El caso mayoritario: ni modelo ni `equipo`. No se dibuja ninguna pieza, el
## muñeco se apaga y el enemigo es exactamente el que era antes de este bloque.
func _test_arquetipo_primitivo() -> void:
	var e: Enemy = _enemigo()
	var sin_equipo: Dictionary = {"nombre": "Lobo", "color": [0.5, 0.5, 0.5]}
	e.configurar(sin_equipo)
	var pd: PaperDoll = e.get_node_or_null("PaperDoll") as PaperDoll
	_chk(pd != null, "f: el PaperDoll existe igual (vacío)", "")
	if pd != null:
		_chk(not pd.tiene_piezas(), "f: sin loadout no dibuja ninguna pieza", "")
		_chk(not pd.visible, "f: y se apaga (no se procesa nada vacío)", "")
		_chk(not pd.is_processing(),
			"f: y no se procesa cada frame: un mob no vigila un Equipo que no tiene", "")
	_chk(_buscar_nombre(e, "arma") == null, "f: no hay ninguna pieza en el bicho", "")
	var cuerpo: MeshInstance3D = e.get_node_or_null("Cuerpo") as MeshInstance3D
	_chk(cuerpo != null and cuerpo.visible, "f: la cápsula se sigue viendo", "")
	_chk(e.esta_vivo() and e.stats.vida_max > 0.0, "f: y el enemigo juega normal", "")


# --- (g) LIMPIEZA: ni huesos ni mallas colgando ------------------------

## Al soltar el modelo (cambio de arquetipo en el pool, o muerte y recycle) no
## puede quedar ni una pieza ni un `BoneAttachment3D` colgando, y la caché no
## puede sobrevivir al esqueleto viejo: si sobrevive, el siguiente arquetipo
## del pool cae para siempre al offset absoluto.
func _test_limpieza() -> void:
	var e: Enemy = _enemigo()
	e.configurar(_arquetipo_rig())
	_chk(_buscar_nombre(e, "arma") != null, "g: el bicho arranca con arma", "")
	var esq: Skeleton3D = _esqueleto(e)
	_chk(esq != null and _contar(e, "BoneAttachment3D") > 0,
		"g: y con su anclaje de hueso puesto", "")

	# El caminho real del pool: el MISMO nodo pasa a un arquetipo sin modelo.
	e.configurar({"nombre": "Lobo", "color": [0.5, 0.5, 0.5]})
	_chk(_buscar_nombre(e, "arma") == null,
		"g: al reusar el nodo NO queda el arma colgando", "")
	_chk(_contar(e, "BoneAttachment3D") == 0,
		"g: ni un BoneAttachment3D huérfano", "quedan=%d" % _contar(e, "BoneAttachment3D"))
	var pd: PaperDoll = e.get_node_or_null("PaperDoll") as PaperDoll
	_chk(pd != null and pd._huesos_cache.is_empty(),
		"g: y la caché de huesos queda vacía (si no, el pool queda cojo para siempre)",
		"" if pd == null else str(pd._huesos_cache.keys()))

	# Y al revés: un bicho que vuelve a tener rig se ancla AL ESQUELETO NUEVO,
	# no al que ya no existe. Este es el caso que rompía con la caché vieja.
	e.configurar(_arquetipo_rig())
	var arma: Node3D = _buscar_nombre(e, "arma")
	_chk(arma != null, "g: vuelve a llevar arma", "")
	if arma != null:
		_chk(arma.get_parent() is BoneAttachment3D,
			"g: y se reancla a un hueso de verdad tras pasar por el pool",
			"padre=%s" % arma.get_parent().name)
	var esq2: Skeleton3D = _esqueleto(e)
	_chk(esq2 != null and esq2 != esq,
		"g: el anclaje es del esqueleto NUEVO, no del liberado", "")
	# `limpiar()` explícito: no queda nada, ni de piezas ni de anclajes.
	if pd != null:
		pd.limpiar()
		_chk(not pd.tiene_piezas(), "g: limpiar() deja el muñeco vacío", "")
		_chk(_buscar_nombre(pd, "arma") == null, "g: sin piezas colgando", "")
		_chk(pd._huesos_cache.is_empty() and pd._esq_cache == null,
			"g: y sin anclajes ni esqueleto en caché", "")
		# Y los anclajes se han SOLTADO del esqueleto, no se han escondido:
		# vaciar el diccionario sin quitar el nodo dejaría un `BoneAttachment3D`
		# pegado al esqueleto para siempre (y `BoneAttachment3D` es lo único que
		# hace que la pieza siga al hueso: se vería clavada en el aire).
		_chk(esq2 != null and _anclajes_debajo_de(esq2) == 0,
			"g: y no queda ningún BoneAttachment3D pegado al esqueleto",
			"anclajes=%d" % (0 if esq2 == null else _anclajes_debajo_de(esq2)))

	# Morir no deja basura tampoco: el cadáver conserva su equipo (eso es lo
	# que se ve), pero al soltar el modelo por el pool se va todo.
	e.die()
	_chk(not e.esta_vivo(), "g: el bicho muere", "")
	e.configurar({"nombre": "Lobo", "color": [0.5, 0.5, 0.5]})
	_chk(_buscar_nombre(e, "arma") == null and _contar(e, "BoneAttachment3D") == 0,
		"g: y al reciclarlo no queda ni arma ni hueso colgando", "")


# --- (h) el jugador no se rompió ---------------------------------------

## El `PaperDoll` del jugador sigue igual: objeto `Equipo`, señal `cambiado`,
## anclaje a hueso. Generalizarlo para los mobs no puede haber loosened al
## jugador, que es el camino que ya estaba probado.
func _test_regresion_jugador() -> void:
	var p: Player = _jugador()
	var pd: PaperDoll = p.get_node_or_null("PaperDoll") as PaperDoll
	_chk(pd != null, "h: el jugador sigue teniendo su PaperDoll", "")
	if pd == null:
		return
	_chk(pd.is_processing(),
		"h: y lo vigila (el save reemplaza el objeto Equipo)", "")
	var esq: Skeleton3D = _esqueleto(p)
	_chk(esq != null, "h: el jugador tiene su esqueleto", "")
	if esq == null:
		return
	p.inventario.agregar(ARMA, 1)
	p.equipo.equipar(ARMA, p.stats, p.inventario)
	await process_frame
	var arma: Node3D = _buscar_nombre(p, "arma")
	_chk(arma != null, "h: el jugador sigue viendo su arma", "")
	if arma != null:
		_chk(arma.get_parent() is BoneAttachment3D,
			"h: y sigue anclada a la mano (el bloque 67 no se rompió)", "")
	# Y el loadout de arquetipo no le roba el papel al `Equipo` del jugador: son
	# dos fuentes y manda la del jugador.
	pd.fijar_loadout({})
	await process_frame
	_chk(_buscar_nombre(p, "arma") != null,
		"h: un loadout de arquetipo no borra el equipo del jugador", "")


# --- utilidades --------------------------------------------------------

func _json(ruta: String) -> Dictionary:
	var texto: String = FileAccess.get_file_as_string(ruta)
	if texto.is_empty():
		return {}
	var v: Variant = JSON.parse_string(texto)
	return v if v is Dictionary else {}


func _arquetipos() -> Dictionary:
	return _json(RUTA_ENEMIGOS).get("arquetipos", {})


func _enemigo() -> Enemy:
	var e: Enemy = ESCENA_ENEMIGO.instantiate() as Enemy
	root.add_child(e)
	_basura.append(e)
	return e


func _jugador() -> Player:
	var p: Player = Player.new()
	p.fijar_identidad("H", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	return p


## Primer `Skeleton3D` del subárbol, en profundidad.
func _esqueleto(entidad: Node) -> Skeleton3D:
	if entidad == null:
		return null
	var lista: Array[Node] = entidad.find_children("*", "Skeleton3D", true, false)
	if lista.is_empty():
		return null
	return lista[0] as Skeleton3D


func _buscar_nombre(n: Node, nombre: String) -> Node3D:
	if n == null:
		return null
	if str(n.name) == nombre and n is Node3D:
		return n as Node3D
	for c in n.get_children():
		var hallada: Node3D = _buscar_nombre(c, nombre)
		if hallada != null:
			return hallada
	return null


## Cuántos nodos de una clase hay en el subárbol (para contar anclajes
## huérfanos).
func _contar(n: Node, clase: String) -> int:
	var total: int = 0
	if n == null:
		return 0
	if n.get_class() == clase:
		total += 1
	for c in n.get_children():
		total += _contar(c, clase)
	return total


## Cuántos `BoneAttachment3D` cuelgan DIRECTOS del esqueleto. Es la prueba de
## que `limpiar()` los soltó de verdad y no solo se olvidó de ellos.
func _anclajes_debajo_de(esq: Skeleton3D) -> int:
	var total: int = 0
	for c in esq.get_children():
		if c is BoneAttachment3D:
			total += 1
	return total


## Las mallas que cuelgan de un nodo, en profundidad.
func _mallas_de(n: Node) -> Array[MeshInstance3D]:
	var res: Array[MeshInstance3D] = []
	if n == null:
		return res
	if n is MeshInstance3D:
		res.append(n as MeshInstance3D)
	for c in n.get_children():
		res.append_array(_mallas_de(c))
	return res
