class_name PaperDoll
extends Node3D
## Muñeco procedural del héroe (fase 36): muestra el equipo equipado en 3D.
##
## Cada slot ocupado de `Equipo` genera una pieza: un modelo GLB si el slot
## tiene `mesh_path` en `data/anclajes.json`, y mientras no lo tenga, el
## RESPALDO PROCEDURAL que la tabla describe (`forma`).
##
## Fase 48: aquí ya NO hay offsets, colores ni formas hardcodeadas. Todo sale
## de `AnclajesDB` (`data/anclajes.json`), la tabla que el spec prometía desde
## la fase 43. Poner un modelo 3D es rellenar `mesh_path` en el JSON, no
## reescribir este script. Los 85 GLB de Meshy están autorizados (CC0/CC-BY)
## pero aún no están en el repo: hoy todas las piezas son procedurales.
##
## Las piezas siguen siendo MeshInstance3D con malla y material COMPARTIDOS,
## con los mismos nombres de nodo de siempre (Arma/Hoja, Escudo, Coraza...).
## Sin equipo no genera nada (solo la cápsula del tscn). Puro visual: nunca
## toca stats (los mods los pone `Equipo`).
##
## Se auto-suscribe a `equipo.cambiado`; como el save REEMPLAZA el objeto
## `Equipo`, cada frame verifica la referencia (comparación barata) y si
## cambió, re-suscribe y reconstruye. `reconstruir()` también es pública
## (demo/tests).
##
## BLOQUE 69 — el muñeco dejó de ser del JUGADOR. Antes `conectar()` tomaba un
## `Player` y el esqueleto se buscaba por `_jugador/Modelo`, así que un enemigo
## con rig (el bandido) no podía llevar arma: no tenía con qué colgar la pieza.
## Ahora hay DOS fuentes de equipo y las dos caen en el mismo código:
##
## - El jugador sigue con el objeto `Equipo` (con su señal `cambiado`).
## - Un mob lleva un LOADOUT DE DATOS: el bloque `equipo` de su arquetipo
##   (`data/enemies.json`, `{slot: item_id}`), que `Enemy` empuja con
##   `fijar_loadout()`. No pasa por `Inventario`/`Equipo`: el equipo de un
##   arquetipo es parte del arquetipo, no algo que el bicho recogió.
##
## Las dos apuntan a la MISMA tabla (`data/anclajes.json`) y al mismo
## esqueleto, así que la geometría y el anclaje a hueso no se duplican.

## Mallas y materiales compartidos por slot (fase 12.1: nada único por pieza).
## La clave incluye el color porque ahora el tinte sale de la tabla.
static var _mats: Dictionary = {}

## Bloque 67: caché del esqueleto y de los BoneAttachment3D. El esqueleto se
## busca una vez (es recursivo sobre toda la malla) y los anclajes, uno por
## hueso: crearlos en cada reconstrucción sería una alloc por pieza.
var _esq_cache: Skeleton3D = null
var _huesos_cache: Dictionary = {}

## La entidad a la que cuelga este muñeco (jugador O enemigo). Solo se usa para
## encontrar el `Skeleton3D` de su rama, así que va tipada por lo común
## (`Node3D`) y no por la clase del jugador.
var _entidad: Node3D = null
## El jugador, solo cuando el muñeco es suyo (de ahí sale el `Equipo`). Null en
## los mobs, que no tienen inventario.
var _jugador: Player = null
var _equipo: Equipo = null
## Loadout del arquetipo: `{slot: item_id}`. Vacío en el jugador (allí manda
## `_equipo`). Se normaliza a los slots de `Equipo.SLOTS` al entrar, para que
## un typo en el JSON no invente una pieza en un slot que no existe.
var _loadout: Dictionary = {}
## Hay que rehacer las piezas aunque el loadout no haya cambiado. Lo levanta
## `limpiar()`: sin esto, un mob del pool que vuelve vacío tras llevar arma se
## quedaría con el estado de la vez anterior.
var _sucio: bool = true


func _ready() -> void:
	reconstruir()


## Conecta al jugador (re-llamable). No duplica suscripciones.
func conectar(j: Player) -> void:
	_entidad = j
	_jugador = j
	_loadout = {}
	# El processed se enciende porque el jugador SÍ hay que vigilarlo: el save
	# reemplaza el objeto `Equipo` y hay que re-suscribirse (ver `_vigilar_equipo`).
	set_process(true)
	_vigilar_equipo(true)


## Bloque 69: conecta a una entidad que NO es el jugador (un enemigo con
## modelo). No hay `Equipo` que vigilar, así que el processed se apaga: un
## `_process` por mob que solo compara dos nulos es ruido en el tick caliente.
func conectar_entidad(e: Node3D) -> void:
	_entidad = e
	_jugador = null
	_equipo = null
	_loadout = {}
	set_process(false)
	reconstruir()


## Bloque 69: el loadout de un arquetipo (`{slot: item_id}`). Reemplaza el
## anterior entero — un mob que vuelve al pool sin `equipo` se queda SIN
## piezas, no con las de su vida anterior.
func fijar_loadout(d: Variant) -> void:
	var nuevo: Dictionary = _slots_validos(d)
	if nuevo == _loadout and not _sucio:
		return
	_loadout = nuevo
	_sucio = false
	reconstruir()


## Solo los slots que existen de verdad (`Equipo.SLOTS`) y con un item
## conocido. Un slot inventado o un item que no está en `data/items.json` se
## avisa y se descarta: el juego nunca se rompe por un dato malo.
func _slots_validos(d: Variant) -> Dictionary:
	var res: Dictionary = {}
	if not (d is Dictionary):
		return res
	for slot in Equipo.SLOTS:
		var item_id: String = str((d as Dictionary).get(slot, ""))
		if item_id == "":
			continue
		if not ItemDB.existe(item_id):
			push_warning("[PaperDoll] el arquetipo pide un item que no existe: '%s'" % item_id)
			continue
		res[slot] = item_id
	return res


## ¿Hay algo que dibujar? Vacío = el muñeco se apaga (no dibuja de todas
## formas, pero visible=false evita el coste de recorrido si mañana lleva
## piezas). Cuenta las de hueso también, que cuelgan del esqueleto y no de
## este nodo. Lo leen los tests.
func tiene_piezas() -> bool:
	if get_child_count() > 0:
		return true
	for clave in _huesos_cache:
		var ba: Node = _huesos_cache[clave] as Node
		if ba != null and is_instance_valid(ba) and ba.get_child_count() > 0:
			return true
	return false


func _process(_delta: float) -> void:
	_vigilar_equipo(false)


## Si el objeto Equipo cambió (save/load lo reemplaza), re-suscribe y
## reconstruye. Comparación de referencia por frame: barata y sin polling.
func _vigilar_equipo(forzar: bool) -> void:
	var eq: Equipo = null
	if _jugador != null and is_instance_valid(_jugador):
		eq = _jugador.equipo
	if eq == _equipo and not forzar:
		return
	if _equipo != null and is_instance_valid(_equipo):
		if _equipo.cambiado.is_connected(reconstruir):
			_equipo.cambiado.disconnect(reconstruir)
	_equipo = eq
	if _equipo != null and is_instance_valid(_equipo):
		if not _equipo.cambiado.is_connected(reconstruir):
			_equipo.cambiado.connect(reconstruir)
	reconstruir()


## Tira las piezas y regenera desde el equipo actual (el del jugador o el
## loadout del arquetipo).
func reconstruir(_arg = null) -> void:
	_limpiar_piezas()
	for slot in _slots_ocupados():
		var pieza: Node3D = _pieza(slot, _item_de(slot))
		if pieza != null:
			pieza.name = slot
			# Bloque 67: `_aplicar_anclaje` ya decidió si la pieza va colgada
			# de un BoneAttachment3D (sigue al hueso) o de este nodo (fallback
			# sin esqueleto). Aquí SOLO se cuelga de este nodo cuando la pieza
			# NO se ha movido de padre, porque `add_child` la volvería a colgar
			# del PaperDoll y el anclaje a hueso se perdería.
			if pieza.get_parent() == null:
				add_child(pieza)
	_sucio = false
	visible = tiene_piezas()


## Bloque 69: los slots con pieza, en el orden de `Equipo.SLOTS` (el orden del
## paper-doll, no el del JSON: así el jugador y el mob dibujan en el mismo
## orden y el `queue_free` del pool es idéntico para los dos).
func _slots_ocupados() -> Array[String]:
	var res: Array[String] = []
	for slot in Equipo.SLOTS:
		if _item_de(slot) != "":
			res.append(slot)
	return res


## El item de un slot: del `Equipo` del jugador o del loadout del arquetipo.
func _item_de(slot: String) -> String:
	if _equipo != null and is_instance_valid(_equipo):
		return _equipo.equipado_en(slot)
	return str(_loadout.get(slot, ""))


## Suelta TODO lo que cuelga de este muñeco: las piezas del fallback (hijas
## directas) y las que viven bajo los `BoneAttachment3D`, más los anclajes.
##
## Bloque 67: solo con los hijos directos NO bastaba. Con el anclaje a hueso las
## piezas cuelgan del esqueleto, no de aquí, así que cada cambio de equipo
## dejaba las anteriores colgando (fuga de nodos y mallas fantasma).
##
## Bloque 69: en un enemigo esto además es OBLIGATORIO en el cambio de
## arquetipo, porque el esqueleto viejo se libera con el modelo viejo y la
## caché apuntaría a huesos y anclajes ya liberados: sin vaciarla, el siguiente
## arquetipo del pool caería para siempre en el offset absoluto.
func limpiar() -> void:
	visible = false
	_limpiar_piezas()
	for hueso in _huesos_cache.keys():
		var ba: Node = _huesos_cache[hueso] as Node
		if ba != null and is_instance_valid(ba):
			var padre: Node = ba.get_parent()
			if padre != null:
				padre.remove_child(ba)
			ba.queue_free()
	_huesos_cache.clear()
	_esq_cache = null
	_sucio = true


## Las piezas sueltas de este nodo y de cada anclaje. Los ANCLAJES se quedan:
## se cachean y recrearlos en cada reconstrucción sería una alloc por pieza.
##
## `remove_child` ANTES del `queue_free` a propósito: el `queue_free` solo saca
## el nodo al final del frame, así que sin esto la pieza vieja seguía colgando
## (y se dibujando) hasta entonces. Fuera del árbol en el acto es lo que
## "no dejar mallas colgando" quiere decir.
func _limpiar_piezas() -> void:
	for h in get_children():
		remove_child(h)
		h.queue_free()
	for hueso in _huesos_cache.keys():
		var ba: Node = _huesos_cache[hueso] as Node
		if ba != null and is_instance_valid(ba):
			for h2 in ba.get_children():
				ba.remove_child(h2)
				h2.queue_free()


## Pieza de un slot, según la tabla de anclajes.
##
## El modelo sale de tres sitios, en este orden de especificidad:
## 1. el campo `modelo` del ITEM (`data/items.json`), que es lo que permite que
##    una daga y una espada se vean distintas en el mismo slot;
## 2. el `mesh_path` del SLOT (`data/anclajes.json`, la vía del jugador);
## 3. la `forma` procedural de la tabla — el respaldo, y lo que se ve hoy.
##
## `item_id` vacío = "la pieza de este slot tal cual", que es la llamada de un
## slot sin item (lo usa `test_fase48_anclajes_bench`): sin item no hay override
## de modelo y sale la pieza por defecto del slot.
##
## Si la ruta no existe (o no hay tabla) avisa y cae al respaldo: el juego nunca
## se rompe por un asset que falta. Ninguna ruta está escrita en el código: las
## dos salen del JSON.
func _pieza(slot: String, item_id: String = "") -> Node3D:
	var anclaje: Dictionary = AnclajesDB.obtener(slot)
	if anclaje.is_empty():
		push_warning("[PaperDoll] slot sin anclaje en data/anclajes.json: '%s'" % slot)
		return null
	var modelo: Node3D = _modelo_de_item(item_id)
	if modelo == null:
		modelo = _pieza_glb(slot)
	if modelo != null:
		_aplicar_anclaje(modelo, slot)
		return modelo
	var forma: Dictionary = AnclajesDB.forma_de(slot)
	var tinte: Color = AnclajesDB.tinte_de(slot)
	var nombre: String = str(forma.get("nombre", slot))
	var metal: float = float(forma.get("metal", 0.0))
	var brillo: bool = bool(forma.get("brillo", false))
	match str(forma.get("tipo", "")):
		"caja":
			var caja := _caja(nombre, _vec3(forma.get("tam", [])), tinte, metal, brillo)
			_aplicar_anclaje(caja, slot)
			return caja
		"esfera":
			var esfe := _esfera(nombre, float(forma.get("radio", 0.1)),
				float(forma.get("alto", 0.2)), tinte, metal, brillo)
			_aplicar_anclaje(esfe, slot)
			return esfe
		"par":
			var par := _par(nombre, _vec3(forma.get("tam", [])), tinte, metal, brillo)
			_aplicar_anclaje(par, slot)
			return par
		"espada":
			var espada := _espada(nombre, forma, tinte, metal, brillo)
			_aplicar_anclaje(espada, slot)
			return espada
		"mesh":
			# Declaraba modelo pero la ruta no se pudo cargar: se cae al
			# respaldo de abajo en vez de dejar el slot vacío.
			pass
	# Sin forma reconocida: respaldo mínimo (una caja) para que el slot no
	# desaparezca en silencio.
	if not str(forma.get("tipo", "")).is_empty():
		push_warning("[PaperDoll] forma desconocida en el slot '%s'" % slot)
	var caja_vacia := _caja(nombre, Vector3(0.12, 0.12, 0.12), tinte, metal, brillo)
	_aplicar_anclaje(caja_vacia, slot)
	return caja_vacia


## Bloque 69: el modelo propio del ITEM, si lo declara (`data/items.json`,
## campo `modelo`). Hoy ningún item lo trae —no hay ni un arma en `models/`— así
## que esto sale null y el respaldo procedural es el que se ve. Es la vía por
## la que entrará el primer arma: rellenar el campo, no tocar este script.
func _modelo_de_item(item_id: String) -> Node3D:
	if item_id == "":
		return null
	var ruta: String = str(ItemDB.obtener(item_id).get("modelo", ""))
	if ruta == "":
		return null
	return _instanciar_glb(ruta, "el item '%s'" % item_id)


## Coloca la pieza donde dice la tabla (offset + rotación + escala).
## Bloque 67: la pieza se cuelga del HUESO que el JSON declara, no de un
## offset absoluto en el mundo.
##
## POR QUÉ: `data/anclajes.json` ya tenía el campo `anclaje` con el nombre del
## hueso ("Hand.R", "Head", "Chest") desde la fase 43, y los 6 GLB del repo
## tienen sus 19 huesos con esos nombres exactos. Pero el código NUNCA leyó
## ese campo: usaba `offset` (metros absolutos: casco a 1,58 m, arma a
## 0,5/1,15/0,1). Consecuencia: el casco flotaba a 1,58 m mientras el
## personaje se agachaba, atacaba o moría, y el arma se quedaba clavada en el
## aire cuando el `walk` movía los brazos. Era la deuda #1 del traspaso.
##
## El `BoneAttachment3D` sigue al hueso en cada frame del motor, así que el
## equipo se mueve CON el personaje sin que este script haga nada por frame.
##
## FALLBACK: si el modelo no trae esqueleto (o el hueso no existe), se usa el
## offset de antes, que es la posición correcta en reposo. Así el equipo
## nunca desaparece ni queda flotando en el origen.
func _aplicar_anclaje(n: Node3D, slot: String) -> void:
	if n == null:
		return
	var hueso: String = AnclajesDB.anclaje_de(slot)
	var padre: BoneAttachment3D = _anclaje_a_hueso(hueso)
	if padre != null:
		_reparentar(n, padre)
		# BoneAttachment3D ya está en la posición del hueso: el offset del JSON
		# pasa a ser un AJUSTE fino respecto al hueso, no una posición absoluta.
		#
		# Para los slots ESPEJADOS (anillo_2, pendiente_2, el otro guante...), el
		# offset viene con la X en negativo porque antes era una posición
		# absoluta. Al colgarlos de un hueso que el rig ya espeja (Hand.L), sumar
		# el offset tal cual invierte el lado. Por eso se invierte la X para que
		# la pieza quede en su sitio.
		var off: Vector3 = AnclajesDB.offset_de(slot)
		if _es_espejado(slot):
			off.x = -off.x
		n.position = off
		n.rotation_degrees = AnclajesDB.rotacion_de(slot)
	else:
		# Sin esqueleto: el offset absoluto de siempre (posición de reposo).
		n.position = AnclajesDB.offset_de(slot)
		n.rotation_degrees = AnclajesDB.rotacion_de(slot)
	var e: float = AnclajesDB.escala_de(slot)
	if not is_equal_approx(e, 1.0):
		n.scale = Vector3(e, e, e)


## El `BoneAttachment3D` del hueso pedido, o null si no hay esqueleto o no
## existe. Cacheado por nombre de hueso: crearlo cada vez sería una alloc por
## pieza y por reconstrucción.
##
## Bloque 69: una entrada de caché INVALIDADA (el pool liberó el modelo y con
## él el anclaje) se BORRA y se rehace. Antes se devolvía null para siempre y el
## siguiente arquetipo del pool caía al offset absoluto para siempre: un bicho
## que llevaba arma podía volver a“他cho de primitivas” y ya no se la pegaba.
func _anclaje_a_hueso(hueso: String) -> BoneAttachment3D:
	if hueso == "":
		return null
	if _huesos_cache.has(hueso):
		var cached: Variant = _huesos_cache[hueso]
		if cached != null and is_instance_valid(cached):
			return cached as BoneAttachment3D
		_huesos_cache.erase(hueso)
	var esq: Skeleton3D = _esqueleto()
	if esq == null or not is_instance_valid(esq):
		return null
	var idx: int = esq.find_bone(hueso)
	if idx < 0:
		# El JSON declara un hueso que este modelo no tiene (ej. "Foot.L +
		# Foot.R" son dos huesos): se prueba con el primero.
		var limpio: String = hueso.get_slice(" ", 0).get_slice("+", 0)
		idx = esq.find_bone(limpio)
		if idx < 0:
			_huesos_cache[hueso] = null
			return null
	var ba := BoneAttachment3D.new()
	ba.name = "Anclaje_%s" % hueso
	ba.bone_idx = idx
	# cuelga del ESQUELETO, no del PaperDoll: es lo que lo hace seguirlo.
	esq.add_child(ba)
	_huesos_cache[hueso] = ba
	return ba


## Mueve un nodo bajo otro padre, conservándolo en la escena (reparent sin
## liberar). `remove_child` + `add_child` lo haria desaparecer un frame.
func _reparentar(n: Node3D, nuevo_padre: Node3D) -> void:
	if n.get_parent() == nuevo_padre:
		return
	var viejo: Node = n.get_parent()
	if viejo != null:
		viejo.remove_child(n)
	nuevo_padre.add_child(n)


## ¿Este slot es la versión espejada de otro? Los slots con sufijo `_2` (anillo_2,
## pendiente_2, ...) van en la mano/cabeza opuesta. Es la convención de la
## tabla, no una heurística: el rig ya los espeja.
func _es_espejado(slot: String) -> bool:
	return slot.ends_with("_2")


## El `Skeleton3D` de la entidad a la que pertenece este muñeco.
##
## Bloque 69: ya no es "el del jugador". Los DOS cuelgan el modelo de la misma
## manera (`<entidad>/Modelo/<Rig>/Skeleton3D`), pero se busca en dos pasos: el
## nodo `Modelo` primero (la vía rápida, la que usa `Enemy` al poner el modelo)
## y, si no aparece, toda la rama de la entidad — para que un rig colgado en
## otro sitio también funcione en vez de caer al offset a ciegas.
##
## Los 6 GLB del repo vienen igual (`<nombre>/Rig/Skeleton3D`): es el mismo
## importador y el mismo `tools/preparar_modelo.py`.
func _esqueleto() -> Skeleton3D:
	if _esq_cache != null and is_instance_valid(_esq_cache):
		return _esq_cache
	_esq_cache = null
	if _entidad == null or not is_instance_valid(_entidad):
		return null
	var modelo: Node = _entidad.get_node_or_null(Cuerpo.NOMBRE_MODELO)
	if modelo != null:
		_esq_cache = _primer_esqueleto(modelo)
	if _esq_cache == null:
		_esq_cache = _primer_esqueleto(_entidad)
	return _esq_cache


func _primer_esqueleto(n: Node) -> Skeleton3D:
	var candidatos: Array[Node] = n.find_children("*", "Skeleton3D", true, false)
	if candidatos.is_empty():
		return null
	return candidatos[0] as Skeleton3D


## Fase 48: el modelo del slot, si lo hay. Es la vía por la que entrará el
## primer GLB: basta con poner la ruta en `mesh_path` del JSON.
func _pieza_glb(slot: String) -> Node3D:
	var ruta: String = str(AnclajesDB.obtener(slot).get("mesh_path", ""))
	if ruta == "":
		return null
	return _instanciar_glb(ruta, "el slot '%s'" % slot)


## Instancia un `.glb` de una ruta del JSON. La ruta NUNCA está escrita en el
## código: sale de `data/items.json` o de `data/anclajes.json`. Si no carga,
## avisa y devuelve null (el que llama cae al respaldo procedural): el juego
## nunca se rompe por un asset que falta.
func _instanciar_glb(ruta: String, de_quien: String) -> Node3D:
	if not ResourceLoader.exists(ruta):
		push_warning("[PaperDoll] el modelo de %s no existe: %s" % [de_quien, ruta])
		return null
	var ps: PackedScene = load(ruta) as PackedScene
	if ps == null:
		push_warning("[PaperDoll] '%s' no es una escena importable: %s" % [de_quien, ruta])
		return null
	return ps.instantiate() as Node3D


## Lee un tamaño [x, y, z] del JSON (Vector3.ZERO si no viene bien).
func _vec3(a: Variant) -> Vector3:
	if not (a is Array):
		return Vector3.ZERO
	var arr: Array = a as Array
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


## Arma de varias piezas (hoja + guarda): la lista `partes` de la tabla.
func _espada(nombre: String, forma: Dictionary, color: Color, metal: float,
		brillo: bool) -> Node3D:
	var raiz := Node3D.new()
	raiz.name = nombre
	for p in (forma.get("partes", []) as Array):
		if not (p is Dictionary):
			continue
		var pd: Dictionary = p
		var tipo: String = str(pd.get("tipo", "caja"))
		var pieza: MeshInstance3D = null
		if tipo == "esfera":
			pieza = _esfera(str(pd.get("nombre", "Pieza")),
				float(pd.get("radio", 0.1)), float(pd.get("alto", 0.2)), color, metal, brillo)
		else:
			pieza = _caja(str(pd.get("nombre", "Pieza")),
				_vec3(pd.get("tam", [])), color, metal, brillo)
		pieza.position = _vec3(pd.get("pos", []))
		raiz.add_child(pieza)
	return raiz


func _caja(nombre: String, tam: Vector3, color: Color, metal: float,
		brillo: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nombre
	var malla := BoxMesh.new()
	malla.size = tam
	mi.mesh = malla
	mi.material_override = _mat(nombre, color, metal, brillo)
	return mi


func _esfera(nombre: String, radio: float, alto: float, color: Color,
		metal: float, brillo: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nombre
	var malla := SphereMesh.new()
	malla.radius = radio
	malla.height = alto
	mi.mesh = malla
	mi.material_override = _mat(nombre, color, metal, brillo)
	return mi


## Par simétrico (guantes, botas): dos cajas espejadas en x. La posición
## viene de la tabla (el `offset.x` es la distancia al centro).
func _par(nombre: String, tam: Vector3, color: Color, metal: float,
		brillo: bool) -> Node3D:
	var raiz := Node3D.new()
	raiz.name = nombre
	for lado in [1.0, -1.0]:
		var mi := MeshInstance3D.new()
		mi.name = "%s_%s" % [nombre, "der" if lado > 0.0 else "izq"]
		var malla := BoxMesh.new()
		malla.size = tam
		mi.mesh = malla
		mi.material_override = _mat(nombre, color, metal, brillo)
		raiz.add_child(mi)
	return raiz


## Material compartido por nombre de pieza. `metal` y `brillo` los decide la
## tabla: el brillo es lo que enciende la emisión (oro y gemas brillan; el
## acero y el cuero no).
static func _mat(nombre: String, color: Color, metal: float,
		brillo: bool) -> StandardMaterial3D:
	var clave: String = "%s|%s|%.2f|%s" % [nombre, color.to_html(false), metal, str(brillo)]
	if _mats.has(clave):
		return _mats[clave] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.55
	mat.emission_enabled = brillo
	if brillo:
		mat.emission = color * 0.6
	_mats[clave] = mat
	return mat
