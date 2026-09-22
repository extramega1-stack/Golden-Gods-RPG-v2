class_name ViajeRapido
extends RefCounted
## Fase 16: viaje rápido con NPC portero (decisión de Juan Diego: costo de
## oro + límites de niveles). Lógica PURA, sin UI: la UI solo lee.
##
## Datos: `res://data/viaje_rapido.json` — las 9 ciudades con su plaza
## [x, z] y la matriz de destinos (costo_oro, nivel_min por destino).
## Los NPCs portero ligan con su ciudad origen por el campo `viaje_id`
## en data/npcs.json (mismo patrón que `tienda_id` en fase 7).
##
## - `destinos_desde(origen_id)`: las 8 ciudades destino con nombre,
##   costo y nivel mínimo.
## - `evaluar(jugador, origen_id, destino_id)`: {ok, motivo, costo,
##   nivel_min, oro_faltante}. Motivos: "destino_desconocido",
##   "en_combate" (jugador.objetivo_ataque != null), "sin_nivel",
##   "sin_oro".
## - `viajar(jugador, origen_id, destino_id)`: re-evalúa y descuenta con
##   `jugador.gastar_oro(costo)` (única vía, como la tienda). Devuelve
##   {ok, motivo, destino, plaza, costo}.
##
## Nota GDScript: JSON.parse_string retorna Variant — NUNCA `:=` aquí
## (warning como error en este proyecto).

const RUTA_DATOS: String = "res://data/viaje_rapido.json"

var _datos: Dictionary = {}
var _ciudades: Dictionary = {}


## Carga el JSON (idempotente). Devuelve false si no hay datos útiles.
func cargar_datos(ruta: String = RUTA_DATOS) -> bool:
	_datos = {}
	_ciudades = {}
	var texto: String = FileAccess.get_file_as_string(ruta)
	if texto == "":
		push_warning("[ViajeRapido] no se pudo leer " + ruta)
		return false
	# parse_string retorna Variant: NUNCA `:=` aquí.
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		push_warning("[ViajeRapido] JSON inválido: " + ruta)
		return false
	_datos = datos
	var ciudades: Variant = _datos.get("ciudades", {})
	if ciudades is Dictionary:
		_ciudades = ciudades
	return not _ciudades.is_empty()


## ¿Hay datos cargados?
func cargado() -> bool:
	return not _ciudades.is_empty()


## Ids de las 9 ciudades (orden del JSON).
func ciudades() -> Array[String]:
	var resultado: Array[String] = []
	for k in _ciudades:
		resultado.append(str(k))
	return resultado


## Nombre visible de una ciudad ("" si no existe).
func nombre_ciudad(ciudad_id: String) -> String:
	var c: Dictionary = _ciudad(ciudad_id)
	return str(c.get("nombre", ""))


## Plaza [x, z] de una ciudad (Vector2.ZERO si no existe).
func plaza_de(ciudad_id: String) -> Vector2:
	var c: Dictionary = _ciudad(ciudad_id)
	var p: Array = c.get("plaza", [])
	if p.size() < 2:
		return Vector2.ZERO
	return Vector2(float(p[0]), float(p[1]))


## Nivel mínimo de la región de una ciudad (-1 si no existe).
func nivel_min_ciudad(ciudad_id: String) -> int:
	var c: Dictionary = _ciudad(ciudad_id)
	if c.is_empty():
		return -1
	return int(c.get("nivel_min", 1))


## Destinos desde un origen: los otros 8 con nombre, costo y nivel mínimo.
## Array de Dictionary {destino_id, nombre, costo_oro, nivel_min}.
## Vacío si el origen es desconocido.
func destinos_desde(origen_id: String) -> Array:
	_asegurar()
	var resultado: Array = []
	var matriz: Variant = _datos.get("matriz", {})
	if not (matriz is Dictionary):
		return resultado
	var filas: Variant = (matriz as Dictionary).get(origen_id, [])
	if not (filas is Array):
		return resultado
	for f in (filas as Array):
		if not (f is Dictionary):
			continue
		var fd: Dictionary = f
		var did: String = str(fd.get("destino_id", ""))
		if did == "" or did == origen_id:
			continue
		resultado.append({
			"destino_id": did,
			"nombre": nombre_ciudad(did),
			"costo_oro": int(fd.get("costo_oro", 0)),
			"nivel_min": int(fd.get("nivel_min", 1)),
		})
	return resultado


## Costo en oro de un viaje (-1 si el par es desconocido).
func costo(origen_id: String, destino_id: String) -> int:
	for d in destinos_desde(origen_id):
		var dd: Dictionary = d
		if str(dd.get("destino_id", "")) == destino_id:
			return int(dd.get("costo_oro", 0))
	return -1


## Valida un viaje SIN mutar nada. Devuelve {ok, motivo, costo,
## nivel_min, oro_faltante}. En combate = objetivo_ataque != null.
func evaluar(jugador: Player, origen_id: String, destino_id: String) -> Dictionary:
	_asegurar()
	var eval_base: Dictionary = {"ok": false, "motivo": "destino_desconocido",
		"costo": 0, "nivel_min": 1, "oro_faltante": 0}
	var costo_viaje: int = costo(origen_id, destino_id)
	if costo_viaje < 0:
		return eval_base
	var nmin: int = nivel_min_ciudad(destino_id)
	if nmin < 0:
		return eval_base
	eval_base["costo"] = costo_viaje
	eval_base["nivel_min"] = nmin
	if jugador == null:
		eval_base["motivo"] = "destino_desconocido"
		return eval_base
	if jugador.objetivo_ataque != null:
		eval_base["motivo"] = "en_combate"
		return eval_base
	if jugador.nivel < nmin:
		eval_base["motivo"] = "sin_nivel"
		return eval_base
	if jugador.oro < costo_viaje:
		eval_base["motivo"] = "sin_oro"
		eval_base["oro_faltante"] = costo_viaje - jugador.oro
		return eval_base
	eval_base["ok"] = true
	eval_base["motivo"] = ""
	return eval_base


## Ejecuta el viaje: re-evalúa y descuenta el oro con gastar_oro
## (única vía, como la tienda). Devuelve {ok, motivo, destino, plaza,
## costo} — en fallo, lo mismo que evaluar().
func viajar(jugador: Player, origen_id: String, destino_id: String) -> Dictionary:
	var ev: Dictionary = evaluar(jugador, origen_id, destino_id)
	if not bool(ev.get("ok", false)):
		return ev
	var costo_viaje: int = int(ev.get("costo", 0))
	# gastar_oro ya valida fondos; si falla, no se viaja (sin_oro).
	if not jugador.gastar_oro(costo_viaje):
		ev["ok"] = false
		ev["motivo"] = "sin_oro"
		ev["oro_faltante"] = costo_viaje - jugador.oro
		return ev
	return {
		"ok": true,
		"motivo": "",
		"destino": destino_id,
		"plaza": plaza_de(destino_id),
		"costo": costo_viaje,
	}


## Ciudad origen del NPC portero (campo `viaje_id` de data/npcs.json;
## "" si el NPC no es portero). Mismo patrón que tienda_de_npc.
static func viaje_id_de_npc(npc_id: String) -> String:
	NpcDB.cargar()
	if npc_id == "":
		return ""
	return str(NpcDB.obtener(npc_id).get("viaje_id", ""))


## Texto legible del motivo de bloqueo ("" si ok).
## "Te faltan X de oro" / "Requiere nivel N" (textos exactos de fase 16).
static func texto_motivo(ev: Dictionary) -> String:
	if bool(ev.get("ok", false)):
		return ""
	var motivo: String = str(ev.get("motivo", ""))
	match motivo:
		"sin_oro":
			return "Te faltan %d de oro" % int(ev.get("oro_faltante", 0))
		"sin_nivel":
			return "Requiere nivel %d" % int(ev.get("nivel_min", 1))
		"en_combate":
			return "No puedes viajar en combate"
		_:
			return "Destino desconocido"


func _ciudad(ciudad_id: String) -> Dictionary:
	_asegurar()
	var c: Variant = _ciudades.get(ciudad_id, {})
	if c is Dictionary:
		return c
	return {}


func _asegurar() -> void:
	if _ciudades.is_empty():
		cargar_datos()
