class_name PoolMobs
extends Node
## Pool de enemigos por arquetipo (fase 20, P0-1 de performance).
##
## Antes cada stream-in/respawn hacía `load(enemigo.tscn)` + `instantiate()`
## + `add_child(SkillFX.new())` y cada stream-out/cadáver hacía
## `queue_free()`: churn en el tick caliente al cruzar el borde del
## streaming. Ahora la escena se precarga UNA vez y los nodos se reciclan
## por arquetipo (freelist): obtener saca uno libre (o instancia si no hay)
## y devolver lo desactiva bajo este nodo para reutilizarlo.
##
## - `configurar_arquetipos(d)`: diccionario de data/enemies.json (para
##   reconfigurar al reutilizar vía `Enemy.reiniciar`).
## - `obtener(arquetipo_id, posicion) -> Enemy`: libre del pool o nuevo.
## - `devolver(e)`: lo saca de circulación (sin colisión, sin proceso,
##   invisible, hijo del pool). Idempotente y nulo-seguro.
## - `libres_de(arq)`, `total_libres()`, `creados`, `reutilizados`: tests.
##
## El pool NO conecta señales ni vigila respawns: eso sigue en la demo, el
## streaming y el spawner. Las conexiones de la demo persisten entre usos
## (la demo las guarda con `is_connected`).

const ESCENA_ENEMIGO: PackedScene = preload("res://scenes/enemy/enemigo.tscn")

## Cuántos enemigos nuevos puede crear como máximo (0 = sin tope).
## Existe para tests de presión; el juego lo deja en 0.
var tope_creados: int = 0

var _arquetipos: Dictionary = {}
## Freelist por arquetipo: Array[Enemy] listos para reutilizar.
var _libres: Dictionary = {}
## Enemigos creados (instantiate) desde que existe el pool.
var creados: int = 0
## Veces que se reutilizó uno libre en vez de instanciar.
var reutilizados: int = 0
## Veces que se devolvió uno al pool.
var devueltos: int = 0


func configurar_arquetipos(arqs: Dictionary) -> void:
	_arquetipos = arqs


## Saca un enemigo del pool (o lo instancia si no hay libre del
## arquetipo), reconfigurado y vivo en `posicion`. Retorna null si el
## arquetipo es desconocido o se alcanzó `tope_creados`.
func obtener(arquetipo_id: String, posicion: Vector3) -> Enemy:
	var arq: Dictionary = _arquetipos.get(arquetipo_id, {})
	if arq.is_empty():
		push_warning("[PoolMobs] arquetipo desconocido: '%s'" % arquetipo_id)
		return null
	var lista: Array = _libres.get(arquetipo_id, [])
	while not lista.is_empty():
		var candidato: Variant = lista.pop_back()
		if is_instance_valid(candidato):
			var e: Enemy = candidato as Enemy
			if e != null:
				_sacar(e, arq, posicion)
				reutilizados += 1
				return e
	# Sin libre válido: instanciar (respetando el tope si hay).
	if tope_creados > 0 and creados >= tope_creados:
		push_warning("[PoolMobs] tope de creados alcanzado (%d)" % tope_creados)
		return null
	var nuevo: Enemy = ESCENA_ENEMIGO.instantiate() as Enemy
	if nuevo == null:
		push_warning("[PoolMobs] no se pudo instanciar el enemigo")
		return null
	nuevo.arquetipo_id = arquetipo_id
	nuevo.add_to_group("enemigos")
	_asegurar_skillfx(nuevo)
	add_child(nuevo)
	creados += 1
	_sacar(nuevo, arq, posicion)
	return nuevo


## Devuelve un enemigo al pool: sin colisión, sin proceso, invisible e
## hijo de este nodo. Los muertos llegan con colisión 0 (die) y los vivos
## liberados por distancia con la suya: ambos quedan en 0.
func devolver(e: Enemy) -> void:
	if e == null or not is_instance_valid(e):
		return
	var lista: Array = _libres.get(e.arquetipo_id, [])
	if lista.has(e):
		return
	e.set_deferred("collision_layer", 0)
	e.set_deferred("collision_mask", 0)
	e.set_process(false)
	e.set_physics_process(false)
	e.visible = false
	if e.get_parent() != self:
		var padre: Node = e.get_parent()
		if padre != null:
			padre.remove_child(e)
		add_child(e)
	e.position = Vector3.ZERO
	lista.append(e)
	_libres[e.arquetipo_id] = lista
	devueltos += 1


## Libres listos del arquetipo (limpia referencias liberadas al contar).
func libres_de(arquetipo_id: String) -> int:
	var lista: Array = _libres.get(arquetipo_id, [])
	var n: int = 0
	for c in lista:
		if is_instance_valid(c):
			n += 1
	return n


## Total de enemigos aparcados en el pool.
func total_libres() -> int:
	var n: int = 0
	for arq in _libres:
		n += libres_de(str(arq))
	return n


## Activa un enemigo (nuevo o reutilizado): reconfigura, coloca y enciende.
func _sacar(e: Enemy, arq: Dictionary, posicion: Vector3) -> void:
	e.reiniciar(arq)
	# Los devueltos que nacieron en la escena (no en el pool) aún no
	# tienen el gancho de skills: se asegura al sacar, no al devolver.
	_asegurar_skillfx(e)
	if e.get_parent() != self:
		var padre: Node = e.get_parent()
		if padre != null:
			padre.remove_child(e)
		add_child(e)
	e.global_position = posicion
	e.visible = true


## El gancho visual de skills (fase 18) se crea UNA vez por instancia y se
## reutiliza con ella (antes se hacía `SkillFX.new()` por cada spawn).
func _asegurar_skillfx(e: Enemy) -> void:
	for h in e.get_children():
		if h is SkillFX:
			return
	e.add_child(SkillFX.new())
