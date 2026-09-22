extends SceneTree
## Tests headless de la Fase 12 (terreno del mundo abierto).
##
## (a) Consts: TAMANO 36864 (escala real, sin reescalar), CELDAS 288,
##     PASO 128, X0/Z0 -18432, LADO 289, N_CHUNKS 6.
## (b) altura_en: en puntos exactos de la grilla coincide con el bin
##     (tolerancia 0.01); el punto medio entre vertices es el promedio
##     (bilineal); en las esquinas coincide con el bin.
## (c) Fuera de bordes: no revienta y devuelve el borde clampeado.
## (d) dentro(): centro y esquinas true, fuera false.
## (e) El nodo construye 36 chunks (6x6) StaticBody3D en capa 1 (misma
##     que el Suelo del demo fase11, para el raycast del clic), cada uno
##     con CollisionShape3D + ConcavePolygonShape3D; 72 MeshInstance3D
##     (LOD0 0-900, LOD1 900-30000) con material vertex_color.
## (f) senal terreno_listo emitida al terminar.
##
## Cómo correrlos (un solo comando):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase12_terreno.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.

const TG: GDScript = preload("res://scripts/mundo/terreno.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []
var _listos: int = 0
var _alturas: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	print("[TEST] Fase 12 - terreno: consts, altura_en, bordes, chunks, LODs")


var _empezo: bool = false


## El arbol existe recien en el primer _process (leccion 13b): el _ready
## del Terreno (parseo del bin + 36 chunks) corre al anadirlo al arbol.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_leer_bin()
	_t_consts()
	var t: Terreno = _terreno()
	_t_altura_grilla(t)
	_t_bilineal(t)
	_t_bordes(t)
	_t_dentro(t)
	_t_chunks(t)
	_t_lods(t)
	_t_material(t)
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	print("[TEST] tiempo de construccion del terreno: %.2f s"
		% [float(t.tiempo_construccion_ms) / 1000.0])
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


## Lee el bin de forma independiente (verificacion cruzada, no reusa el
## parseo del Terreno).
func _leer_bin() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(
		"res://data/terreno.bin")
	_check(bytes.size() > 0, "bin: data/terreno.bin existe y no esta vacio")
	var off: int = 8 + 12
	var n: int = 289 * 289
	_alturas = PackedFloat32Array()
	_alturas.resize(n)
	for i in range(n):
		_alturas[i] = bytes.decode_float(off + i * 4)


func _terreno() -> Terreno:
	_listos = 0
	var t: Terreno = TG.new()
	t.terreno_listo.connect(_al_listo)
	root.add_child(t)
	_basura.append(t)
	_check(_listos == 1, "terreno: senal terreno_listo emitida al terminar")
	return t


func _t_consts() -> void:
	_check(Terreno.TAMANO == 36864.0, "consts: TAMANO 36864 (escala real)")
	_check(Terreno.CELDAS == 288, "consts: CELDAS 288")
	_check(Terreno.PASO == 128.0, "consts: PASO 128")
	_check(Terreno.X0 == -18432.0 and Terreno.Z0 == -18432.0,
		"consts: X0/Z0 -18432")
	_check(Terreno.LADO == 289, "consts: LADO 289")
	_check(Terreno.N_CHUNKS == 6, "consts: 6x6 chunks")
	_check(Terreno.X0 + Terreno.CELDAS * Terreno.PASO == 18432.0,
		"consts: X0 + 288*128 = 18432 (mundo simetrico)")


func _h(ix: int, iz: int) -> float:
	return _alturas[iz * 289 + ix]


func _t_altura_grilla(t: Terreno) -> void:
	# Puntos exactos de la grilla: altura_en == valor del bin.
	var casos: Array = [
		[0, 0], [288, 0], [0, 288], [288, 288], [144, 144], [37, 200],
	]
	for c in casos:
		var ix: int = c[0]
		var iz: int = c[1]
		var x: float = Terreno.X0 + float(ix) * Terreno.PASO
		var z: float = Terreno.Z0 + float(iz) * Terreno.PASO
		var got: float = t.altura_en(x, z)
		_check(absf(got - _h(ix, iz)) <= 0.01,
			"altura: grilla (%d,%d) == bin" % [ix, iz],
			"got=%f bin=%f" % [got, _h(ix, iz)])
	# Esquina (0,0) del bin vive en (X0, Z0).
	_check(absf(t.altura_en(Terreno.X0, Terreno.Z0) - _h(0, 0)) <= 0.01,
		"altura: esquina (X0,Z0) == h[0]")
	# Esquina opuesta: vertice (288,288).
	_check(absf(t.altura_en(18432.0, 18432.0) - _h(288, 288)) <= 0.01,
		"altura: esquina (18432,18432) == h[288*289+288]")


func _t_bilineal(t: Terreno) -> void:
	# Punto medio entre (0,0) y (1,0): promedio de los dos vertices.
	var esperado: float = (_h(0, 0) + _h(1, 0)) / 2.0
	var got: float = t.altura_en(Terreno.X0 + 64.0, Terreno.Z0)
	_check(absf(got - esperado) <= 0.01,
		"altura: bilineal medio horizontal == promedio",
		"got=%f esp=%f" % [got, esperado])
	# Centro de la celda (0,0): promedio de las 4 esquinas.
	var esp2: float = (_h(0, 0) + _h(1, 0) + _h(0, 1) + _h(1, 1)) / 4.0
	var got2: float = t.altura_en(Terreno.X0 + 64.0, Terreno.Z0 + 64.0)
	_check(absf(got2 - esp2) <= 0.01,
		"altura: bilineal centro de celda == promedio 4",
		"got=%f esp=%f" % [got2, esp2])


func _t_bordes(t: Terreno) -> void:
	# Fuera del mundo: no revienta y devuelve el borde clampeado.
	var borde_izq: float = t.altura_en(Terreno.X0, 0.0)
	var got: float = t.altura_en(Terreno.X0 - 1000.0, 0.0)
	_check(absf(got - borde_izq) <= 0.001,
		"bordes: x < X0 clampa al borde izquierdo")
	var borde_der: float = t.altura_en(18432.0, 500.0)
	_check(absf(t.altura_en(18432.0 + 5000.0, 500.0) - borde_der) <= 0.001,
		"bordes: x > 18432 clampa al borde derecho")
	var borde_sup: float = t.altura_en(123.0, Terreno.Z0)
	_check(absf(t.altura_en(123.0, Terreno.Z0 - 42.0) - borde_sup) <= 0.001,
		"bordes: z < Z0 clampa al borde superior")
	var borde_inf: float = t.altura_en(-77.0, 18432.0)
	_check(absf(t.altura_en(-77.0, 18432.0 + 9999.0) - borde_inf) <= 0.001,
		"bordes: z > 18432 clampa al borde inferior")


func _t_dentro(t: Terreno) -> void:
	_check(t.dentro(0.0, 0.0), "dentro: centro")
	_check(t.dentro(Terreno.X0, Terreno.Z0), "dentro: esquina (X0,Z0)")
	_check(t.dentro(18432.0, 18432.0), "dentro: esquina opuesta")
	_check(not t.dentro(Terreno.X0 - 1.0, 0.0), "dentro: fuera a la izquierda")
	_check(not t.dentro(0.0, 18432.0 + 1.0), "dentro: fuera abajo")
	_check(not t.dentro(99999.0, -99999.0), "dentro: muy lejos")


func _t_chunks(t: Terreno) -> void:
	var cuerpos: Array = []
	for h in t.get_children():
		if h is StaticBody3D and str(h.name).begins_with("Chunk_"):
			cuerpos.append(h)
	_check(cuerpos.size() == 36,
		"chunks: 36 StaticBody3D (6x6)", str(cuerpos.size()))
	var con_colision: int = 0
	for c in cuerpos:
		var b: StaticBody3D = c
		_check(b.collision_layer == 1,
			"chunks: capa 1 como el Suelo del demo", str(b.collision_layer))
		for h2 in b.get_children():
			if h2 is CollisionShape3D \
					and (h2 as CollisionShape3D).shape is ConcavePolygonShape3D:
				con_colision += 1
	_check(con_colision == 36,
		"chunks: 36 CollisionShape3D con ConcavePolygonShape3D",
		str(con_colision))


func _t_lods(t: Terreno) -> void:
	var lod0: int = 0
	var lod1: int = 0
	for h in t.get_children():
		if h is MeshInstance3D:
			var mi: MeshInstance3D = h
			if str(mi.name).ends_with("_LOD0"):
				_check(mi.visibility_range_begin == 0.0
						and mi.visibility_range_end == 900.0,
					"lod: LOD0 visible 0-900")
				_check(mi.mesh != null, "lod: LOD0 tiene malla")
				lod0 += 1
			elif str(mi.name).ends_with("_LOD1"):
				_check(mi.visibility_range_begin == 900.0
						and mi.visibility_range_end == 30000.0,
					"lod: LOD1 visible 900-30000")
				_check(mi.mesh != null, "lod: LOD1 tiene malla")
				lod1 += 1
	_check(lod0 == 36, "lod: 36 mallas LOD0", str(lod0))
	_check(lod1 == 36, "lod: 36 mallas LOD1", str(lod1))


func _t_material(t: Terreno) -> void:
	var mat: StandardMaterial3D = null
	for h in t.get_children():
		if h is MeshInstance3D:
			mat = (h as MeshInstance3D).material_override as StandardMaterial3D
			break
	_check(mat != null, "material: los chunks tienen material")
	_check(mat.vertex_color_use_as_albedo,
		"material: vertex_color_use_as_albedo = true")
