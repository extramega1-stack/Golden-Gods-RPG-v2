class_name RegionDB
extends RefCounted
## Base de datos de regiones del mundo abierto (Fase 12).
##
## Lógica pura, sin nodos: carga `res://data/regiones.json` (10 rectángulos
## que cubren el mapa x,z ∈ [-18432, 18432] sin huecos ni solapes) y resuelve
## qué región contiene un punto del mapa.
##
## Los rectángulos se evalúan como intervalos semiabiertos
## [x0, x1) × [z0, z1): un punto sobre un borde compartido pertenece a la
## región que empieza ahí (la del "lado alto"), nunca a dos a la vez.
## El borde máximo del mapa (18432) sí se incluye.

const RUTA: String = "res://data/regiones.json"
const BORDE_MAX: float = 18432.0

var _regiones: Array = []
var _cargado: bool = false


## Carga el JSON de regiones. Idempotente por instancia: recarga desde cero.
## Devuelve true si se cargó al menos el formato (array, aunque vacío).
func cargar(ruta: String = RUTA) -> bool:
	_regiones = []
	_cargado = false
	var texto: String = FileAccess.get_file_as_string(ruta)
	if texto == "":
		push_warning("[RegionDB] no se pudo leer " + ruta)
		return false
	# parse_string retorna Variant: NUNCA `:=` aquí (warning como error).
	var datos = JSON.parse_string(texto)
	if not (datos is Array):
		push_warning("[RegionDB] regiones.json no es un array JSON válido")
		return false
	var vistos: Dictionary = {}
	var lista: Array = datos
	for entrada in lista:
		if not (entrada is Dictionary):
			push_warning("[RegionDB] entrada no-diccionario ignorada")
			continue
		var r: Dictionary = entrada
		var rid: String = str(r.get("id", ""))
		if rid == "" or vistos.has(rid):
			push_warning("[RegionDB] id inválido o duplicado: " + rid)
			continue
		vistos[rid] = true
		_regiones.append(r)
	_cargado = true
	return true


func esta_cargado() -> bool:
	return _cargado


## Región que contiene el punto (x, z). {} si ninguna (p.ej. fuera del mapa).
func region_en(x: float, z: float) -> Dictionary:
	for r in _regiones:
		var x0: float = float(r.get("x0", 0.0))
		var z0: float = float(r.get("z0", 0.0))
		var x1: float = float(r.get("x1", 0.0))
		var z1: float = float(r.get("z1", 0.0))
		var dentro_x: bool = x >= x0 and (x < x1 or (x1 >= BORDE_MAX and x <= BORDE_MAX))
		var dentro_z: bool = z >= z0 and (z < z1 or (z1 >= BORDE_MAX and z <= BORDE_MAX))
		if dentro_x and dentro_z:
			return r
	return {}


## Todas las regiones en el orden del JSON (copia superficial).
func todas() -> Array:
	return _regiones.duplicate()


## Región por id. {} si no existe.
func por_id(region_id: String) -> Dictionary:
	for r in _regiones:
		if str(r.get("id", "")) == region_id:
			return r
	return {}
