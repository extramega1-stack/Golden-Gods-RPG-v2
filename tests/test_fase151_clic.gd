extends SceneTree
## Tests de regresión de la Fase 15.1 (hotfix: clic izquierdo para caminar).
##
## Causa raíz (ya diagnosticada, no re-diagnosticar): los triángulos de
## `_caras_colision` y `_malla_chunk` en `scripts/mundo/terreno.gd` tenían
## el winding invertido — las caras frontales apuntaban hacia ABAJO (-Y).
## `ConcavePolygonShape3D` tiene `backface_collision=false` por defecto,
## así que los raycasts DESCENDENTES del clic izquierdo del Player
## atravesaban el terreno sin golpear nada y el clic nunca fijaba destino.
## (a) Un rayo descendente sobre el terreno GOLPEA: hay hit, el
##     colisionador es un Chunk y la posición cae a la altura del dato.
## (b) Un rayo ascendente desde debajo NO golpea: las frontales miran +Y.
##     Esto descarta el atajo `backface_collision=true` (golpearía desde
##     ambos lados).
## (c) Las normales de las caras de `_caras_colision` apuntan hacia +Y
##     (convención de ConcavePolygonShape3D: n = (p2-p0)×(p1-p0)).
## (d) La cadena del clic: el hit del rayo en la rama de suelo de
##     `_clic_izquierdo` (`_orden_mover_punto`) fija `_tiene_destino`.
##
## Cómo correrlos (un solo comando):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase151_clic.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const TG: GDScript = preload("res://scripts/mundo/terreno.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []
var _listos: int = 0


func _init() -> void:
	print("[TEST] Fase 15.1 - hotfix clic izquierdo: winding del terreno")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b): el _ready
## del Terreno (parseo del bin + 36 chunks) corre al añadirlo al árbol.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	var t: Terreno = _terreno()
	_t_rayo_descendente_golpea(t, 1000.0, 1000.0)
	_t_rayo_descendente_golpea(t, -9000.0, -9000.0)
	_t_rayo_ascendente_no_golpea(t, 1000.0, 1000.0)
	_t_normales_hacia_arriba(t)
	_t_cadena_clic_fija_destino(t)
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
	return true


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


func _al_listo() -> void:
	_listos += 1


func _terreno() -> Terreno:
	_listos = 0
	var t: Terreno = TG.new()
	t.terreno_listo.connect(_al_listo)
	root.add_child(t)
	_basura.append(t)
	_check(_listos == 1, "terreno: senal terreno_listo emitida")
	return t


func _rayo(desde: Vector3, hasta: Vector3) -> Dictionary:
	var consulta: PhysicsRayQueryParameters3D = \
		PhysicsRayQueryParameters3D.create(desde, hasta)
	var mundo: World3D = root.world_3d
	var espacio: PhysicsDirectSpaceState3D = mundo.direct_space_state
	return espacio.intersect_ray(consulta)


## (a) El rayo descendente —el del clic izquierdo del Player— GOLPEA.
func _t_rayo_descendente_golpea(t: Terreno, x: float, z: float) -> void:
	var h: float = t.altura_en(x, z)
	var hit: Dictionary = _rayo(
		Vector3(x, h + 500.0, z), Vector3(x, h - 500.0, z))
	var donde: String = "(%.0f, %.0f)" % [x, z]
	_check(not hit.is_empty(), "rayo descendente golpea en " + donde, "")
	if hit.is_empty():
		return
	var pos: Vector3 = hit["position"]
	_check(absf(pos.y - h) < 60.0,
		"el golpe cae a la altura del dato en " + donde,
		"y=%.1f dato=%.1f" % [pos.y, h])
	var col: Object = hit["collider"]
	var nombre: String = str((col as Node).name) if col is Node else "?"
	_check(col is StaticBody3D and nombre.begins_with("Chunk_"),
		"el colisionador es un chunk en " + donde, "col=" + nombre)


## (b) El rayo ascendente desde debajo NO golpea: las frontales miran +Y.
## Si alguien "arreglara" esto con backface_collision=true, este test lo
## caza (ese atajo golpearía desde ambos lados).
func _t_rayo_ascendente_no_golpea(t: Terreno, x: float, z: float) -> void:
	var h: float = t.altura_en(x, z)
	var hit: Dictionary = _rayo(
		Vector3(x, h - 300.0, z), Vector3(x, h + 300.0, z))
	_check(hit.is_empty(), "rayo ascendente NO golpea (frontales hacia +Y)",
		"hit=%s" % str(hit.get("position", "?")))


## (c) Normales de `_caras_colision` hacia +Y (no hacia -Y como antes).
func _t_normales_hacia_arriba(t: Terreno) -> void:
	var caras: PackedVector3Array = t._caras_colision(3, 3)
	var total: int = caras.size() / 3
	var malas: int = 0
	for i in range(total):
		var p0: Vector3 = caras[i * 3]
		var p1: Vector3 = caras[i * 3 + 1]
		var p2: Vector3 = caras[i * 3 + 2]
		# Normal de cara de ConcavePolygonShape3D: (p2-p0)×(p1-p0).
		var n: Vector3 = (p2 - p0).cross(p1 - p0).normalized()
		if n.y <= 0.9:
			malas += 1
	_check(malas == 0, "normales de _caras_colision apuntan a +Y",
		"triangulos=%d malos=%d" % [total, malas])


## (d) La cadena del clic: el hit del rayo en la rama de suelo de
## `_clic_izquierdo` (`_orden_mover_punto`) fija `_tiene_destino` y el
## destino es el punto golpeado. (Headless no tiene cámara: el rayo se
## inyecta con los mismos parámetros que usaría `_rayo_clic`.)
func _t_cadena_clic_fija_destino(t: Terreno) -> void:
	var x: float = 1000.0
	var z: float = 1000.0
	var h: float = t.altura_en(x, z)
	var hit: Dictionary = _rayo(
		Vector3(x, h + 500.0, z), Vector3(x, h - 500.0, z))
	_check(not hit.is_empty(), "rayo del clic simulado golpea", "")
	if hit.is_empty():
		return
	var p: Player = PL.new()
	p.add_to_group("jugador")
	root.add_child(p)
	_basura.append(p)
	var punto: Vector3 = hit["position"]
	p._orden_mover_punto(punto)  # rama de suelo de _clic_izquierdo
	_check(p._tiene_destino, "el hit del clic fija _tiene_destino", "")
	_check(p._destino == punto, "el destino es el punto golpeado", "")
