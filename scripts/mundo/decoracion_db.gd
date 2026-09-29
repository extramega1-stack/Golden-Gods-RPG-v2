class_name DecoracionDB
extends RefCounted
## Fase 70: el catálogo de DECORACIÓN del mundo, desde `data/decoracion.json`.
## Mismo patrón que `MaterialesDB` (carga idempotente, lectura tolerante, sin
## nodos) y por la misma razón: la fase 69 demostró que un color o una
## densidad escrito en el `.gd` es un valor que nadie puede cambiar sin
## recompilar, y además es un valor que nadie puede auditar de un vistazo.
##
## LO QUE RESUELVE ACÁ:
## - la grilla de la vegetación (paso, radios, tipos altos) y qué especie se
##   siembra en cada celda del anillo;
## - el tinte POR ZONA (el mismo arbusto es verde en el Bosque Hondo y gris en
##   la Ceniza y Forja): la zona sale de `data/regiones.json`, no de un mapa
##   escrito a mano acá;
## - las recetas de FORMA: cada pieza es una primitiva de Godot con un tamaño,
##   una posición y un slot de material. No hay modelado;
## - los props de calle y su densidad por tipo;
## - las siluetas de los edificios (3 por tipo + un jitter) y el zócalo.
##
## EL DETERMINISMO (lo más importante de este archivo, junto al hash):
## TODO lo que se siembra o se coloca se decide con `dado(semilla, indice)`,
## donde la semilla sale de la POSICIÓN por el FNV-1a de
## `BibliotecaMateriales.semilla_de`. Jamás un `rand`, jamás un contador, jamás
## el orden de iteración de un `Dictionary`. Si no fuera así, cargar un save
## reconstruye el mundo con el pasto en otros metros y el jugador pierde de
## vista todo lo que construyó alrededor de su casa.

const RUTA: String = "res://data/decoracion.json"
## Zona usada cuando el punto cae fuera de `data/regiones.json` (o antes de
## que el bin del terreno exista): pradera genérica, no un hueco.
const ZONA_DEFAULT: String = "default"
## Separadores de slot dentro de una forma de vegetación. Los props de calle
## usan en su lugar las claves de `ciudad_paleta` / la paleta de la ciudad.
const SLOT_FOLLAJE: String = "follaje"
const SLOT_FLOR: String = "flor"
const SLOT_LENO: String = "leno"
const SLOT_LENO_SECO: String = "leno_seco"
const SLOT_ROCA: String = "roca"
## Mezcla de bits: el tope de los índices que salen de `dado`.
const MASCARA: int = 0x3FFFFFFF
## 2^30, el divisor para bajar un hash de 30 bits a [0, 1).
const UNO: float = 1073741824.0

static var _cargado: bool = false
static var _vegetacion: Dictionary = {}
static var _tintes: Dictionary = {}
static var _formas: Dictionary = {}
static var _vegetales: Dictionary = {}
static var _orden_vegetales: Array[String] = []
static var _tipos_altos: Dictionary = {}
static var _zonas: Dictionary = {}
static var _ciudad: Dictionary = {}
static var _ciudad_paleta: Dictionary = {}
static var _bordes: Dictionary = {}
static var _siluetas: Dictionary = {}
static var _regiones: RegionDB = null
## Cache de la última región resuelta. La mayoría de las celdas de un anillo
## caen en la misma región, así que el filtro evita 9 comparaciones por celda.
## El id empieza en un centinela y NO en `""` a propósito: `""` es el id
## LEGÍTIMO de "el punto cae fuera de toda región" (y entonces la zona es
## `default`), así que con `""` de arranque el primer punto fuera del mapa
## devolvería una cache vacía en vez de `default`, y `tinte_de` no encontraría
## nada y la planta saldría con el material de repuesto.
static var _zona_cache_id: String = "?"
static var _zona_cache: Dictionary = {}


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	var texto: String = FileAccess.get_file_as_string(RUTA)
	if texto.is_empty():
		push_warning("[DecoracionDB] no se pudo leer " + RUTA)
		return
	var crudo: Variant = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[DecoracionDB] JSON inválido: " + RUTA)
		return
	var d: Dictionary = crudo
	_vegetacion = d.get("vegetacion", {})
	_tintes = d.get("tintes", {})
	_formas = d.get("formas", {})
	_vegetales = d.get("vegetales", {})
	_orden_vegetales.clear()
	for k in _vegetales.keys():
		_orden_vegetales.append(str(k))
	_orden_vegetales.sort()
	for k in _vegetacion.get("tipos_altos", []):
		_tipos_altos[str(k)] = true
	_zonas = d.get("zonas", {})
	_ciudad = d.get("ciudad", {})
	_ciudad_paleta = d.get("ciudad_paleta", {})
	_bordes = d.get("bordes", {})
	_siluetas = d.get("siluetas", {})
	_regiones = RegionDB.new()
	_regiones.cargar()


## Vacía la caché. Los tests lo llaman; el juego, nunca.
static func limpiar() -> void:
	_cargado = false
	_vegetacion = {}
	_tintes = {}
	_formas = {}
	_vegetales = {}
	_orden_vegetales = []
	_tipos_altos = {}
	_zonas = {}
	_ciudad = {}
	_ciudad_paleta = {}
	_bordes = {}
	_siluetas = {}
	_regiones = null
	_zona_cache_id = "?"
	_zona_cache = {}


# ---------------------------------------------------------------------------
# El hash: TODO lo aleatorio del mundo sale de acá
# ---------------------------------------------------------------------------

## La semilla de un punto del mundo. Delegada en la Biblioteca para que sea LA
## MISMA función que usa el material de los edificios: un prop y la pared que
## tiene al lado tienen que salir de la misma familia de números.
static func semilla(x: float, z: float) -> int:
	return BibliotecaMateriales.semilla_de(x, z)


## Un entero de 30 bits derivado de (semilla, índice). Es una función pura: sin
## estado, sin reloj, sin `rand`. La misma celda da el mismo número en cualquier
## máquina y en cualquier versión de Godot, que es lo que hace que un save
## reconstruya el mundo igual.
static func dado(semilla: int, indice: int) -> int:
	var h: int = (semilla ^ ((indice + 1) * 374761393)) & MASCARA
	h = ((h ^ (h >> 13)) * 1274126177) & MASCARA
	return (h ^ (h >> 16)) & MASCARA


## `dado` normalizado a [0, 1). Para azar de verdad (giros, escalas) esto es
## mejor que `randf()`: no consume el estado global, así que el orden en que se
## construyen dos ciudades deja de importar.
static func unidad(semilla: int, indice: int) -> float:
	return float(dado(semilla, indice)) / UNO


## Un flotante en `[lo, hi)` derivado de (semilla, índice).
static func entre(semilla: int, indice: int, lo: float, hi: float) -> float:
	return lo + (hi - lo) * unidad(semilla, indice)


## Un entero en `[0, n)` derivado de (semilla, índice). `n <= 0` devuelve 0.
static func eleccion(semilla: int, indice: int, n: int) -> int:
	if n <= 1:
		return 0
	return dado(semilla, indice) % n


# ---------------------------------------------------------------------------
# Vegetación
# ---------------------------------------------------------------------------

static func paso() -> float:
	cargar()
	return maxf(1.0, float(_vegetacion.get("paso", 14.0)))


static func radio_cerca() -> float:
	cargar()
	return maxf(0.0, float(_vegetacion.get("radio_cerca", 52.0)))


static func radio_lejos() -> float:
	cargar()
	return maxf(paso(), float(_vegetacion.get("radio_lejos", 140.0)))


static func celdas_por_frame() -> int:
	cargar()
	return maxi(1, int(_vegetacion.get("celdas_por_frame", 44)))


static func reconstruir_tras_m() -> float:
	cargar()
	return maxf(0.0, float(_vegetacion.get("reconstruir_tras_m", 9.0)))


## Radio de la zona segura alrededor de (0, 0): la aldea inicial. Es la misma
## regla que vigilan `test_fase12_spawns` y `test_fase14_terreno`, y acá se usa
## para NO plantar nada alto: un árbol en el punto de aparición tape la plaza y
## empuja al jugador.
static func radio_zona_segura() -> float:
	cargar()
	return maxf(0.0, float(_vegetacion.get("radio_zona_segura", 40.0)))


static func es_tipo_alto(tipo: String) -> bool:
	cargar()
	return _tipos_altos.has(tipo)


static func vegetales() -> Array[String]:
	cargar()
	return _orden_vegetales


static func vegetal(tipo: String) -> Dictionary:
	cargar()
	return _vegetales.get(tipo, {})


## El nombre de la forma de una especie.
static func forma_de_vegetal(tipo: String) -> String:
	return str(vegetal(tipo).get("forma", ""))


# ---------------------------------------------------------------------------
# Formas
# ---------------------------------------------------------------------------

## Las partes de una forma, en orden. Cada parte trae `prim`, `tam`, `pos`,
## `giro` y `tinte`.
static func forma(id: String) -> Dictionary:
	cargar()
	return _formas.get(id, {})


static func partes(id: String) -> Array:
	cargar()
	var f: Dictionary = _formas.get(id, {})
	return f.get("partes", [])


static func formas() -> Array[String]:
	cargar()
	var a: Array[String] = []
	for k in _formas.keys():
		a.append(str(k))
	a.sort()
	return a


# ---------------------------------------------------------------------------
# Zonas (la parte que hace que el bosque sea verde y la ceniza gris)
# ---------------------------------------------------------------------------

## El id de la región del mundo en (x, z). `""` si el punto cae fuera del mapa.
static func zona_en(x: float, z: float) -> String:
	cargar()
	if _regiones == null:
		return ZONA_DEFAULT
	return str(_regiones.region_en(x, z).get("id", ""))


## La zona de (x, z) YA RESUELTA (con su cache de AABB). Devuelve la entrada de
## `zonas`; si el punto cae fuera de toda región, la de `default`.
static func zona_resuelta(x: float, z: float) -> Dictionary:
	cargar()
	var id: String = ""
	if _regiones != null:
		var r: Dictionary = _regiones.region_en(x, z)
		if not r.is_empty():
			id = str(r.get("id", ""))
	if id == _zona_cache_id:
		return _zona_cache
	_zona_cache_id = id
	_zona_cache = zona_por_id(id)
	return _zona_cache


## La entrada de `zonas` para un id de región. Una región que no declara su
## bloque (o el `default`) cae en `default`: es lo que hace que agregar una
## región nueva al mundo no rompa la vegetación.
static func zona_por_id(id: String) -> Dictionary:
	cargar()
	if id != "" and _zonas.has(id):
		return _zonas[id]
	return _zonas.get(ZONA_DEFAULT, {})


static func zonas() -> Array[String]:
	cargar()
	var a: Array[String] = []
	for k in _zonas.keys():
		a.append(str(k))
	a.sort()
	return a


## Qué tan probable es que la especie `tipo` caiga en una celda de esta zona.
## 0 = nunca; 1 = en toda celda posible.
static func peso_de(zona: Dictionary, tipo: String) -> float:
	cargar()
	var tipos: Dictionary = zona.get("tipos", {})
	return clampf(float(tipos.get(tipo, 0.0)), 0.0, 1.0)


## Cada cuántas celdas puede caer. El dato de la ZONA pisa al de la especie:
## el Bosque Hondo duplica la densidad del monte y la ceniza la baja, sin tocar
## la especie.
static func uno_cada_de(zona: Dictionary, tipo: String) -> int:
	cargar()
	var override: Dictionary = zona.get("uno_cada", {})
	if override.has(tipo):
		return maxi(1, int(override[tipo]))
	return maxi(1, int(vegetal(tipo).get("uno_cada", 1)))


## El tinte (superficie + hex) que usa una especie en una zona. Devuelve `{}`
## si la zona no declara ese slot, para que el llamador avise en vez de pintar
## de negro.
static func tinte_de(zona: Dictionary, slot: String) -> Dictionary:
	cargar()
	var clave: String = str(zona.get(slot, ""))
	if clave == "":
		return {}
	if _tintes.has(clave):
		return _tintes[clave]
	return {"superficie": "hoja", "tinte": clave}


# ---------------------------------------------------------------------------
# Props de calle
# ---------------------------------------------------------------------------

static func ciudad_paso() -> float:
	cargar()
	return maxf(1.0, float(_ciudad.get("paso", 11.0)))


static func ciudad_margen() -> float:
	return float(_ciudad.get("margen", 3.4))


## Radio interior del anillo de props, relativo al centro de la ciudad. La
## plaza y sus 30 m alrededor quedan limpios: el monumento y los NPCs viven ahí.
static func ciudad_r_desde() -> float:
	cargar()
	return maxf(0.0, float(_ciudad.get("r_desde", 90.0)))


## Radio exterior. 0 = "hasta la muralla menos lo que pida `distancia_puerta`",
## que es el valor por defecto.
static func ciudad_r_hasta() -> float:
	cargar()
	return maxf(0.0, float(_ciudad.get("r_hasta", 0.0)))


static func ciudad_distancia_puerta() -> float:
	cargar()
	return maxf(0.0, float(_ciudad.get("distancia_puerta", 26.0)))


## A qué distancia el `MultiMesh` de los props se apaga solo. Las 9 ciudades
## viven en el mismo árbol de escena: sin esto, el motor dibujaría los props de
## Shadow Town desde el otro extremo del mundo.
static func ciudad_alcance() -> float:
	cargar()
	return maxf(0.0, float(_ciudad.get("alcance", 420.0)))


## Cuánto se hunde en el suelo cada prop de calle. La misma regla que el
## `hundir` de un vegetal y por el mismo motivo: la vereda no es plana (la ciudad
## se apoya en el terreno) y un banco que solo roza el suelo tiene la pata de
## abajo en el aire. Sale del dato, no del código.
static func ciudad_hundir() -> float:
	cargar()
	return maxf(0.0, float(_ciudad.get("hundir", 0.16)))


static func ciudad_props() -> Array:
	cargar()
	return _ciudad.get("props", [])


static func ciudad_prop(id: String) -> Dictionary:
	cargar()
	for p in ciudad_props():
		if p is Dictionary and str((p as Dictionary).get("id", "")) == id:
			return p
	return {}


## El `tinte` fijo de un slot de prop (`"madera"`, `"acero"`, `"farol"`, ...).
## Los slots que empiezan con `pal_` NO están acá: son la paleta de la ciudad.
static func ciudad_slot(id: String) -> Dictionary:
	cargar()
	return _ciudad_paleta.get(id, {})


# ---------------------------------------------------------------------------
# Bordes y siluetas
# ---------------------------------------------------------------------------

static func borde(id: String) -> Dictionary:
	cargar()
	return _bordes.get(id, {})


static func zocalo() -> Dictionary:
	return borde("zocalo")


## Las 3 siluetas de un tipo de edificio. `[]` si el tipo no declara ninguna
## (el `match` del constructor cae entonces en su forma base, que es lo que
## hace que un edificio nuevo no necesite tocar este archivo para existir).
static func siluetas(tipo: String) -> Array:
	cargar()
	var v: Variant = _siluetas.get(tipo, [])
	return v if v is Array else []


## El jitter de medidas, común a todos los tipos.
static func silueta_jitter() -> Dictionary:
	cargar()
	return _siluetas.get("jitter", {})


## Cuánto alto come el remate de un tipo POR ENCIMA del muro: el tejado, la
## cornisa, la variante regional más alta y la tapa. El constructor lo descuenta
## del tope de 28 u antes de decidir la silueta, porque la silueta se elige
## mirando el alto del muro y el remate se apoya en él.
static func reserva(tipo: String) -> float:
	cargar()
	var r: Dictionary = _siluetas.get("reserva", {})
	return maxf(0.0, float(r.get(tipo, 6.0)))


## Cuánto puede variar el jitter de las medidas (fracción). Sale del dato: si
## algún día se quiere una ciudad de房屋 idénticos, es acá y no en el código.
static func jitter_de(campo: String, defecto: float) -> float:
	cargar()
	return clampf(float(silueta_jitter().get(campo, defecto)), 0.0, 0.5)
