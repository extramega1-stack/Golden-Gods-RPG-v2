class_name Habilidades
extends RefCounted
## Fase 57: XP POR HABILIDAD, en paralelo al nivel de personaje.
##
## DECISIÓN DE JUAN DIEGO: el nivel de personaje NO se toca. Sigue siendo el
## del `StatBlock` y el que manda en combate, equipo y StatBlock. Acá hay un
## segundo eje, más chico, que es el que abre los Talentos de Habilidad de
## la fase 59.
##
## Por qué NO niveles 1-99: esa decisión arrastraría StatBlock, el save, la
## UI de personaje y las fórmulas de combate, que es un sistema grande para
## el 20% de la sensación. Con un contador por habilidad se consigue casi
## todo lo que importa ("mi Tala está al 40") sin tocar la progresión que ya
## funciona.
##
## Es PURA (sin nodos ni reloj): la recolectora y la cocinera llaman a
## `ganar()` y el Player la hace avanzar. Testeable headless.
##
## Curve extra: cada habilidad puede declarar una curva propia en
## `data/habilidades.json`. La de arriba es la genérica (8 tramos).

const RUTA: String = "res://data/habilidades.json"

## Emitida cuando una habilidad sube de tramo. La UI la escucha.
signal tramo_ganado(habilidad: String, tramo: int)

var _xp: Dictionary = {}
var _curvas: Dictionary = {}
var _nombres: Dictionary = {}
var _datos: Dictionary = {}


static func crear_desde_datos(ruta: String = RUTA) -> Habilidades:
	var h := Habilidades.new()
	h.cargar(ruta)
	return h


func cargar(ruta: String = RUTA) -> bool:
	_xp.clear()
	_curvas.clear()
	_nombres.clear()
	_datos = {}
	var texto: String = FileAccess.get_file_as_string(ruta)
	if texto.is_empty():
		push_warning("[Habilidades] no se pudo leer " + ruta)
		return false
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		push_warning("[Habilidades] JSON inválido: " + ruta)
		return false
	_datos = datos
	for id in (datos as Dictionary).get("habilidades", {}).keys():
		var hid: String = str(id)
		var d: Dictionary = (datos as Dictionary)["habilidades"][id]
		_curvas[hid] = d.get("curva", [])
		_nombres[hid] = str(d.get("nombre", hid))
		_xp[hid] = 0
	return not _curvas.is_empty()


func ids() -> Array[String]:
	var salida: Array[String] = []
	for k in _curvas.keys():
		salida.append(str(k))
	salida.sort()
	return salida


func nombre_de(habilidad: String) -> String:
	return str(_nombres.get(habilidad, habilidad))


func xp_de(habilidad: String) -> int:
	return int(_xp.get(habilidad, 0))


## XP que falta para el siguiente tramo. 0 si ya está en el tope.
func xp_para_siguiente(habilidad: String) -> int:
	var i: int = tramo_de(habilidad)
	var curva: Array = _curvas.get(habilidad, [])
	if curva.is_empty() or i >= curva.size():
		return 0
	return maxi(0, int(curva[i]) - xp_de(habilidad))


## Tramo actual (0-based). El tope es `curva.size() - 1`.
func tramo_de(habilidad: String) -> int:
	var curva: Array = _curvas.get(habilidad, [])
	if curva.is_empty():
		return 0
	var xp: int = xp_de(habilidad)
	for i in range(curva.size()):
		if xp < int(curva[i]):
			return i
	return maxi(0, curva.size() - 1)


func tramos_totales(habilidad: String) -> int:
	var curva: Array = _curvas.get(habilidad, [])
	return maxi(1, curva.size())


func en_tope(habilidad: String) -> bool:
	var curva: Array = _curvas.get(habilidad, [])
	return not curva.is_empty() and xp_de(habilidad) >= int(curva[curva.size() - 1])


## Suma XP. Si el salto cruza uno o más umbrales, emite `tramo_ganado` una
## vez por tramo (un tajo que da 400 XP puede abrir dos de golpe).
func ganar(habilidad: String, cantidad: int) -> int:
	if not _curvas.has(habilidad) or cantidad <= 0:
		return 0
	var antes: int = tramo_de(habilidad)
	_xp[habilidad] = xp_de(habilidad) + cantidad
	var despues: int = tramo_de(habilidad)
	for t in range(antes + 1, despues + 1):
		tramo_ganado.emit(habilidad, t)
	return tramo_de(habilidad) - antes


## ¿La habilidad ya llegó al tramo que pide un talento?
func alcanza(habilidad: String, tramo_requerido: int) -> bool:
	return tramo_de(habilidad) >= tramo_requerido


func total_xp() -> int:
	var t: int = 0
	for k in _xp.keys():
		t += int(_xp[k])
	return t


## Progreso 0..1 dentro del tramo actual, para la barra de la UI.
func progreso_tramo(habilidad: String) -> float:
	var i: int = tramo_de(habilidad)
	var curva: Array = _curvas.get(habilidad, [])
	if curva.is_empty():
		return 0.0
	var base: float = float(curva[maxi(0, i - 1)]) if i > 0 else 0.0
	var tope: float = float(curva[i])
	if tope <= base:
		return 1.0
	return clampf((float(xp_de(habilidad)) - base) / (tope - base), 0.0, 1.0)


# --- save ---------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"version": 1, "xp": _xp.duplicate()}


func cargar_estado(d: Dictionary) -> void:
	_xp.clear()
	var guardado: Dictionary = d.get("xp", {})
	for hid in _curvas.keys():
		_xp[hid] = maxi(0, int(guardado.get(hid, 0)))
	for hid in guardado.keys():
		# Una habilidad guardada que ya no existe en el JSON se descarta: el
		# dato manda, no un save viejo.
		if _curvas.has(hid):
			_xp[hid] = maxi(0, int(guardado[hid]))
