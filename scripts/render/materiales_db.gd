class_name MaterialesDB
extends RefCounted
## Fase 69: el catálogo de superficies y materiales del mundo, de
## `data/materiales.json`. Patrón del proyecto (idéntico a `PiezasDB`):
## carga idempotente, lectura tolerante, sin estado.
##
## POR QUÉ UN CATÁLOGO Y NO UN `const` EN CÓDIGO: el mundo tenía 58 sitios
## escribiendo `albedo_color` a mano en `ciudad_luna.gd`. Eso es un color por
## código, y un color por código es un color que nadie puede cambiar sin
## recompilar. Acá el color, el patrón, la rugosidad y la variación son UN
## dato. `_mat("muro_a")` sigue siendo la llamada en el código: lo que cambió
## es que ya no sabe qué color es `muro_a`.

const RUTA: String = "res://data/materiales.json"
## Clave de `_paleta` que representa el "quinto color" de cada ciudad (el que
## rota entre toldos / braseros / cristales / estandartes / empalizadas /
## velas / dorado según el JSON de la ciudad).
const CLAVE_EXTRA: String = "extra"
## Candidatos de `paleta_extra`, en el orden en que se buscan.
const CANDIDATOS_EXTRA: Array[String] = [
	"toldos", "braseros", "cristales", "estandartes", "empalizadas",
	"velas", "dorado",
]

static var _cargado: bool = false
static var _textura: Dictionary = {}
static var _variacion: Dictionary = {}
static var _superficies: Dictionary = {}
static var _orden_superficies: Array[String] = []
static var _paleta_roles: Dictionary = {}
static var _paleta_extra: Dictionary = {}
static var _roles: Dictionary = {}
static var _piezas: Dictionary = {}


static func cargar() -> void:
	if _cargado:
		return
	_cargado = true
	var texto: String = FileAccess.get_file_as_string(RUTA)
	if texto.is_empty():
		push_warning("[MaterialesDB] no se pudo leer " + RUTA)
		return
	var crudo: Variant = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[MaterialesDB] JSON inválido: " + RUTA)
		return
	var d: Dictionary = crudo
	_textura = d.get("textura", {})
	_variacion = d.get("variacion", {})
	_superficies = d.get("superficies", {})
	_orden_superficies.clear()
	for k in _superficies.keys():
		_orden_superficies.append(str(k))
	_orden_superficies.sort()
	_paleta_roles = d.get("paleta_roles", {})
	_paleta_extra = d.get("paleta_extra", {})
	_roles = d.get("roles", {})
	_piezas = d.get("piezas", {})


## Vacía la caché del DB. Los tests lo llaman entre casos; el juego no.
static func limpiar() -> void:
	_cargado = false
	_textura = {}
	_variacion = {}
	_superficies = {}
	_orden_superficies = []
	_paleta_roles = {}
	_paleta_extra = {}
	_roles = {}
	_piezas = {}


# ---------------------------------------------------------------------------
# Textura
# ---------------------------------------------------------------------------

## Lado del tile en px. Presupuesto de VRAM (§9.5): el total de texturas es
## `px² × 4 bytes × 3 mapas × superficies × variantes`.
static func textura_px() -> int:
	cargar()
	return maxi(8, int(_textura.get("px", 128)))


## Semilla maestra del horneado. Cambiarla cambia TODOS los granos del mundo.
static func semilla() -> int:
	cargar()
	return int(_textura.get("semilla", 0))


## Cuántas variantes se hornean por superficie.
static func variantes() -> int:
	cargar()
	return maxi(1, int(_textura.get("variantes", 1)))


static func albedo_base() -> float:
	cargar()
	return float(_textura.get("albedo_base", 0.94))


static func albedo_ganancia() -> float:
	cargar()
	return float(_textura.get("albedo_ganancia", 1.0))


static func normal_fuerza_global() -> float:
	cargar()
	return float(_textura.get("normal_fuerza_global", 1.0))


# ---------------------------------------------------------------------------
# Superficies
# ---------------------------------------------------------------------------

static func superficies() -> Array[String]:
	cargar()
	return _orden_superficies


static func superficie_existe(id: String) -> bool:
	cargar()
	return _superficies.has(id)


static func superficie(id: String) -> Dictionary:
	cargar()
	return _superficies.get(id, {})


static func variacion() -> Dictionary:
	cargar()
	return _variacion


# ---------------------------------------------------------------------------
# Roles del mundo
# ---------------------------------------------------------------------------

static func rol_existe(nombre: String) -> bool:
	cargar()
	return _roles.has(nombre)


static func rol(nombre: String) -> Dictionary:
	cargar()
	return _roles.get(nombre, {})


static func roles() -> Array[String]:
	cargar()
	var a: Array[String] = []
	for k in _roles.keys():
		a.append(str(k))
	a.sort()
	return a


## Superficie de una pieza del Refugio, para que `PiezaVisual` deje de llevar
## su tabla de colores en código.
static func pieza(tipo: String) -> Dictionary:
	cargar()
	return _piezas.get(tipo, {})


# ---------------------------------------------------------------------------
# Paleta por ciudad (fase 15)
# ---------------------------------------------------------------------------

## Datos del rol de `_paleta` para una clave ("muros", "techos", ...).
static func paleta_rol(clave: String) -> Dictionary:
	cargar()
	return _paleta_roles.get(clave, {})


## Las claves de rol de paleta, ordenadas. El código itera esta lista y no
## una suya: si mañana aparece `techos_vidriado` en el JSON, entra solo.
static func paleta_claves() -> Array[String]:
	cargar()
	var a: Array[String] = []
	for k in _paleta_roles.keys():
		a.append(str(k))
	a.sort()
	return a


## Datos del `extra` según QUÉ clave de la ciudad aporta el color. El quinto
## color de cada ciudad es un toldo de tela, un brasero de metal o un dorado:
## sin esto el "extra" sería siempre la misma superficie y el latón de Golden
## Tower saldría de tela.
static func paleta_extra(clave: String) -> Dictionary:
	cargar()
	return _paleta_extra.get(clave, _paleta_roles.get(CLAVE_EXTRA, {}))
