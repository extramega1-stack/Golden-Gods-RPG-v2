class_name Terreno
extends Node3D
## Fase 12 — terreno del mundo abierto: heightmap porteado del legado
## (`data/terreno.bin`, copia exacta de `~/workspace/godot-rpg/data/
## terrain_data.bin`), a escala REAL 1:1: 36.864 unidades, sin reescalar.
##
## El bin: u32 vw (=289), u32 vh (=289), 12 bytes a ignorar, luego
## 289x289 float32 de alturas en row-major (indice = iz*289+ix) y luego
## 289x289x3 u8 de colores RGB por vertice.
##
## Visual por chunks 6x6 (48x48 celdas cada uno) con 2 LODs por chunk:
## LOD0 malla completa (0-900 u), LOD1 paso 2 (900-30000 u), cambio por
## distancia con `visibility_range_begin/end`. Material compartido
## StandardMaterial3D con los colores RGB del bin como albedo.
## Colision: un StaticBody3D por chunk (capa 1, como el Suelo del demo)
## con ConcavePolygonShape3D cocinado de la malla LOD1 (cocina mas rapido).
## `altura_en(x, z)` (bilineal con clamp) es la API para caminar sobre el
## terreno; senal `terreno_listo` al terminar la construccion.

signal terreno_listo

## Escala real del mundo (1:1 con el legado; NO reescalar).
const TAMANO: float = 36864.0
## Celdas por lado: (289-1) vertices.
const CELDAS: int = 288
## Distancia entre vertices adyacentes (36864 / 288).
const PASO: float = 128.0
## Esquina del mundo: el vertice (0,0) vive aqui.
const X0: float = -18432.0
const Z0: float = -18432.0
## Lado del heightmap en vertices.
const LADO: int = 289
## Chunks por lado; 6x6 = 36 chunks de 48x48 celdas.
const N_CHUNKS: int = 6
const CELDAS_CHUNK: int = 48
## Distancia de cambio de LOD.
const LOD_CAMBIO: float = 900.0
const LOD_MAX: float = 30000.0

const RUTA_BIN: String = "res://data/terreno.bin"

var _alturas: PackedFloat32Array = PackedFloat32Array()
var _colores: PackedColorArray = PackedColorArray()
var _material: StandardMaterial3D = null
## Tiempo de construccion en ms (lo mide _ready; los tests lo leen).
var tiempo_construccion_ms: int = 0


func _ready() -> void:
	var t0: int = Time.get_ticks_msec()
	if not _cargar_bin():
		push_error("[Terreno] no se pudo cargar " + RUTA_BIN)
		terreno_listo.emit()
		return
	_material = _hacer_material()
	for cz in range(N_CHUNKS):
		for cx in range(N_CHUNKS):
			_construir_chunk(cx, cz)
	tiempo_construccion_ms = int(Time.get_ticks_msec() - t0)
	print("[Terreno] construido: %d chunks en %.2f s"
			% [N_CHUNKS * N_CHUNKS, float(tiempo_construccion_ms) / 1000.0])
	terreno_listo.emit()


## Lee el bin a `_alturas` y `_colores`. false = archivo invalido.
func _cargar_bin() -> bool:
	if not FileAccess.file_exists(RUTA_BIN):
		return false
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(RUTA_BIN)
	if bytes.size() < 8:
		return false
	var vw: int = int(bytes.decode_u32(0))
	var vh: int = int(bytes.decode_u32(4))
	if vw != LADO or vh != LADO:
		push_error("[Terreno] bin inesperado: %dx%d" % [vw, vh])
		return false
	var off: int = 8 + 12
	var n: int = LADO * LADO
	if bytes.size() < off + n * 4 + n * 3:
		return false
	_alturas = PackedFloat32Array()
	_alturas.resize(n)
	for i in range(n):
		_alturas[i] = bytes.decode_float(off + i * 4)
	var coff: int = off + n * 4
	_colores = PackedColorArray()
	_colores.resize(n)
	for i in range(n):
		var b: int = coff + i * 3
		_colores[i] = Color(
			float(bytes[b]) / 255.0,
			float(bytes[b + 1]) / 255.0,
			float(bytes[b + 2]) / 255.0)
	return true


## Altura del terreno en (x, z): interpolacion bilineal de los 4 vertices
## vecinos, con clamp a los bordes (fuera del mundo devuelve el borde, no
## revienta).
func altura_en(x: float, z: float) -> float:
	var fx: float = clampf((x - X0) / PASO, 0.0, float(CELDAS))
	var fz: float = clampf((z - Z0) / PASO, 0.0, float(CELDAS))
	var ix: int = mini(int(fx), CELDAS - 1)
	var iz: int = mini(int(fz), CELDAS - 1)
	var tx: float = clampf(fx - float(ix), 0.0, 1.0)
	var tz: float = clampf(fz - float(iz), 0.0, 1.0)
	var h00: float = _alturas[iz * LADO + ix]
	var h10: float = _alturas[iz * LADO + ix + 1]
	var h01: float = _alturas[(iz + 1) * LADO + ix]
	var h11: float = _alturas[(iz + 1) * LADO + ix + 1]
	var a: float = lerpf(h00, h10, tx)
	var b: float = lerpf(h01, h11, tx)
	return lerpf(a, b, tz)


## Color del terreno en (x, z): muestra el vertice mas cercano del bin
## (para el minimapa de la fase 13; no interpola, es solo orientacion).
func color_en(x: float, z: float) -> Color:
	if _colores.is_empty():
		return Color(0.1, 0.1, 0.12)
	var fx: float = clampf((x - X0) / PASO, 0.0, float(LADO - 1))
	var fz: float = clampf((z - Z0) / PASO, 0.0, float(LADO - 1))
	return _colores[int(round(fz)) * LADO + int(round(fx))]


## ¿El punto (x, z) esta dentro del mundo caminable?
func dentro(x: float, z: float) -> bool:
	return x >= X0 and x <= X0 + TAMANO and z >= Z0 and z <= Z0 + TAMANO


func _hacer_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	# El winding es correcto, pero con cull desactivado el terreno es
	# robusto ante cualquier vertice degenerado del bin.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Normal por gradiente del heightmap (paso = separacion de muestra).
func _normal_en(ix: int, iz: int, paso: int) -> Vector3:
	var ixm: int = maxi(ix - paso, 0)
	var ixp: int = mini(ix + paso, CELDAS)
	var izm: int = maxi(iz - paso, 0)
	var izp: int = mini(iz + paso, CELDAS)
	var nx: float = (_alturas[iz * LADO + ixm] - _alturas[iz * LADO + ixp]) \
		/ float(maxi(ixp - ixm, 1))
	var nz: float = (_alturas[izm * LADO + ix] - _alturas[izp * LADO + ix]) \
		/ float(maxi(izp - izm, 1))
	return Vector3(nx, 2.0 * PASO, nz).normalized()


## Grilla de vertices (posiciones, normales, colores) para un chunk con un
## paso de muestreo dado (1 = LOD0, 2 = LOD1).
func _grilla_chunk(cx: int, cz: int, paso: int, lado: int,
		verts: PackedVector3Array, normales: PackedVector3Array,
		colores: PackedColorArray) -> void:
	var ix0: int = cx * CELDAS_CHUNK
	var iz0: int = cz * CELDAS_CHUNK
	var k: int = 0
	for j in range(lado):
		for i in range(lado):
			var ix: int = ix0 + i * paso
			var iz: int = iz0 + j * paso
			verts[k] = Vector3(
				X0 + float(ix) * PASO,
				_alturas[iz * LADO + ix],
				Z0 + float(iz) * PASO)
			normales[k] = _normal_en(ix, iz, paso)
			colores[k] = _colores[iz * LADO + ix]
			k += 1


func _malla_chunk(cx: int, cz: int, paso: int) -> ArrayMesh:
	var pasos: int = CELDAS_CHUNK / paso
	var lado: int = pasos + 1
	var verts := PackedVector3Array()
	verts.resize(lado * lado)
	var normales := PackedVector3Array()
	normales.resize(lado * lado)
	var colores := PackedColorArray()
	colores.resize(lado * lado)
	_grilla_chunk(cx, cz, paso, lado, verts, normales, colores)
	var indices := PackedInt32Array()
	indices.resize(pasos * pasos * 6)
	var q: int = 0
	for j in range(pasos):
		for i in range(pasos):
			var a: int = j * lado + i
			var b: int = a + 1
			var c: int = a + lado
			var d: int = c + 1
			indices[q] = a
			indices[q + 1] = c
			indices[q + 2] = b
			indices[q + 3] = c
			indices[q + 4] = d
			indices[q + 5] = b
			q += 6
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normales
	arr[Mesh.ARRAY_COLOR] = colores
	arr[Mesh.ARRAY_INDEX] = indices
	var malla: ArrayMesh = ArrayMesh.new()
	malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return malla


## Caras (triangulos sueltos) para el ConcavePolygonShape3D, cocinadas de
## la grilla LOD1 (paso 2): cocina mas rapido que la malla completa.
func _caras_colision(cx: int, cz: int) -> PackedVector3Array:
	var paso: int = 2
	var pasos: int = CELDAS_CHUNK / paso
	var lado: int = pasos + 1
	var verts := PackedVector3Array()
	verts.resize(lado * lado)
	var normales := PackedVector3Array()
	normales.resize(lado * lado)
	var colores := PackedColorArray()
	colores.resize(lado * lado)
	_grilla_chunk(cx, cz, paso, lado, verts, normales, colores)
	var caras := PackedVector3Array()
	caras.resize(pasos * pasos * 6)
	var q: int = 0
	for j in range(pasos):
		for i in range(pasos):
			var a: int = j * lado + i
			var b: int = a + 1
			var c: int = a + lado
			var d: int = c + 1
			caras[q] = verts[a]
			caras[q + 1] = verts[c]
			caras[q + 2] = verts[b]
			caras[q + 3] = verts[c]
			caras[q + 4] = verts[d]
			caras[q + 5] = verts[b]
			q += 6
	return caras


## Un chunk: dos MeshInstance3D (LOD0 0-900, LOD1 900-30000) + un
## StaticBody3D en la capa 1 (igual que el Suelo del demo fase11, para que
## el raycast del clic izquierdo del Player siga resolviendo el punto).
func _construir_chunk(cx: int, cz: int) -> void:
	var nombre: String = "Chunk_%d_%d" % [cx, cz]
	var lod0: MeshInstance3D = MeshInstance3D.new()
	lod0.name = nombre + "_LOD0"
	lod0.mesh = _malla_chunk(cx, cz, 1)
	lod0.material_override = _material
	lod0.visibility_range_begin = 0.0
	lod0.visibility_range_end = LOD_CAMBIO
	add_child(lod0)
	var lod1: MeshInstance3D = MeshInstance3D.new()
	lod1.name = nombre + "_LOD1"
	lod1.mesh = _malla_chunk(cx, cz, 2)
	lod1.material_override = _material
	lod1.visibility_range_begin = LOD_CAMBIO
	lod1.visibility_range_end = LOD_MAX
	add_child(lod1)
	var cuerpo: StaticBody3D = StaticBody3D.new()
	cuerpo.name = nombre
	cuerpo.collision_layer = 1
	var forma: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	forma.set_faces(_caras_colision(cx, cz))
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = forma
	cuerpo.add_child(col)
	add_child(cuerpo)
