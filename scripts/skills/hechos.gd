class_name Hechos
extends RefCounted
## Fase 59: Talentos de Habilidad. La mejor idea de Dragonwilds, traída al
## proyecto: subir una habilidad no te da "+5% de daño", te da un HECHO que
## TRANSFORMA la recolección.
##
## Diferencia con los talentos de clase (fase 28, `talentos.gd`): aquellos
## suman stats al StatBlock. Estos hacen dos cosas distintas:
## - `tipo: "mod"`     → un MOD del StatBlock, con fuente `hecho:<id>`.
## - `tipo: "bandera"` → una bandera que LEEN los sistemas (tala, veta,
##   cocina, vitals). No escribe stats: transforma el comportamiento.
##
## Se desbloquean por el XP de habilidad (fase 57): es el único puente entre
## el segundo eje y el juego.
##
## PURA, salvo `aplicar()` que recibe el StatBlock del jugador.

const RUTA: String = "res://data/hechos.json"
## Prefijo de la fuente de los mods, para que se distinguan de los talentos
## de clase (`talento:<id>`) y de los efectos temporales (`buff:<id>`).
const FUENTE: String = "hecho:"

## FASE 72 — los Hechos que hasta ahora NINGÚN sistema consultaba. Cuatro
## recompensas que el juego calculaba, guardaba y mostraba, y que no se podían
## ganar.
##
## POR QUÉ HAY DOS CONSTANTES POR HECHO (`ID_` y `FLAG_`) Y POR QUÉ LA DE LA
## BANDERA SIGUE LA REGLA MECÁNICA `FLAG_<FLAGS EN MAYÚSCULAS>`: el `id` es lo
## que nombra al Hecho en `data/hechos.json` (y lo usan `parametros`), y la
## bandera es lo que la respuesta dice (`"veta_persistente"`,
## `"doble_respawn"`). Que la bandera tenga el nombre derivable del valor es lo
## que permite el test genérico de "todo Hecho tiene consumidor", que la fase 72
## escribió para que esta clase de fallo no vuelva a hacer falta una fase para
## descubrirla.
const ID_VETA_PERSISTENTE: String = "veta_persistente"
const FLAG_VETA_PERSISTENTE: String = "veta_persistente"
const ID_DOBLE_YACIMIENTO: String = "doble_yacimiento"
const FLAG_DOBLE_RESPAWN: String = "doble_respawn"
const ID_COCINA_LOTE: String = "cocina_lote"
const FLAG_COCINA_LOTE: String = "cocina_lote"
const ID_FOGATA_PERENNE: String = "fogata_perenne"
const FLAG_FOGATA_PERENNE: String = "fogata_perenne"

## Emitida cuando un hecho se desbloquea. La UI la escucha.
signal hecho_desbloqueado(hecho_id: String)

var _hechos: Dictionary = {}
var _orden: Array[String] = []
var _banderas: Dictionary = {}
## Las habilidades del jugador: es el único puente entre el segundo eje (fase
## 57) y los hechos. Se inyecta; `Hechos` no lo busca por su cuenta.
var habilidades: Habilidades = null


static func crear_desde_datos(ruta: String = RUTA) -> Hechos:
	var h := Hechos.new()
	h.cargar(ruta)
	return h


func cargar(ruta: String = RUTA) -> bool:
	_hechos.clear()
	_orden.clear()
	var texto: String = FileAccess.get_file_as_string(ruta)
	if texto.is_empty():
		push_warning("[Hechos] no se pudo leer " + ruta)
		return false
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		push_warning("[Hechos] JSON inválido: " + ruta)
		return false
	for h in (datos as Dictionary).get("hechos", []):
		if not (h is Dictionary):
			continue
		var hd: Dictionary = h
		var hid: String = str(hd.get("id", ""))
		if hid == "":
			continue
		_hechos[hid] = hd
		_orden.append(hid)
	return not _hechos.is_empty()


func ids() -> Array[String]:
	return _orden.duplicate()


func hecho(id: String) -> Dictionary:
	return _hechos.get(id, {})


func nombre_de(id: String) -> String:
	return str(_hechos.get(id, {}).get("nombre", id))


func descripcion_de(id: String) -> String:
	return str(_hechos.get(id, {}).get("descripcion", ""))


## ¿El hecho pide esta habilidad y este tramo?
func requisito_de(id: String) -> Array:
	var h: Dictionary = hecho(id)
	return [str(h.get("habilidad", "")), int(h.get("tramo", 0))]


## ¿Está desbloqueado este hecho, según las habilidades del jugador?
func desbloqueado(id: String) -> bool:
	var h: Dictionary = hecho(id)
	if h.is_empty():
		return false
	var hab: String = str(h.get("habilidad", ""))
	var tramo: int = int(h.get("tramo", 0))
	if habilidades == null:
		return false
	return habilidades.alcanza(hab, tramo)


## Todos los desbloqueados ahora mismo.
func desbloqueados() -> Array[String]:
	var salida: Array[String] = []
	for id in _orden:
		if desbloqueado(id):
			salida.append(id)
	return salida


func total() -> int:
	return _orden.size()


# --- banderas ---------------------------------------------------------

## ¿Tengo esta bandera? La leen los sistemas de recolección.
func tiene(flag: String) -> bool:
	return bool(_banderas.get(flag, false))


## Pone o saca una bandera. La usan `aplicar()` y el guardado.
func fijar_bandera(flag: String, valor: bool = true) -> void:
	if flag == "":
		return
	_banderas[flag] = valor


func banderas() -> Dictionary:
	return _banderas.duplicate()


## Las banderas de un hecho ("" si no es de bandera).
func flag_de(id: String) -> String:
	var h: Dictionary = hecho(id)
	if str(h.get("tipo", "")) != "bandera":
		return ""
	return str(h.get("flag", ""))


## Un número de `hecho(id).parametros`, o `por_defecto` si el Hecho no existe,
## no lo tiene, o el valor no es un número.
##
## POR QUÉ EXISTE: los Hechos que antes no los leía nadie necesitan
## números (cuántos usos deja la veta, por cuánto se acelera el respawn, cuántas
## raciones sale, cuánta leña se reencende), y esos números son DATO. Sin esta
## función cada consumidor haría su propio `hecho(id).get("parametros", {}).get(
## "x", 7)` con un default escrito a mano en el código, que es exactamente el
## número quemado que §9.4 prohíbe.
func parametro(id: String, clave: String, por_defecto: float = 0.0) -> float:
	var h: Dictionary = hecho(id)
	if h.is_empty():
		return por_defecto
	var p: Variant = h.get("parametros", {})
	if not (p is Dictionary):
		return por_defecto
	return float((p as Dictionary).get(clave, por_defecto))


## El mismo número, entero. `maxi(0, ...)` porque un parámetro negativo en un
## multiplicador de usos o de raciones es un dato roto, no un caso de uso.
func parametro_int(id: String, clave: String, por_defecto: int = 0) -> int:
	return maxi(0, int(roundf(parametro(id, clave, float(por_defecto)))))


func fijar_habilidades(h: Habilidades) -> void:
	habilidades = h


## Aplica al StatBlock los hechos desbloqueados de tipo `mod`, y recalcula las
## banderas. Es idempotente: se puede llamar cada vez que cambia una cosa.
##
## IMPORTANTE: los de tipo `mod` se aplican SOLO si están desbloqueados, y
## los bloqueados se quitan. Así el StatBlock nunca arrastra un mod de un
## hecho que ya no cumple.
func aplicar(stats: StatBlock) -> void:
	if habilidades == null:
		return
	_banderas.clear()
	for id in _orden:
		var h: Dictionary = _hechos[id]
		var abierto: bool = desbloqueado(id)
		match str(h.get("tipo", "")):
			"mod":
				var fuente: String = FUENTE + id
				if abierto:
					stats.add_mod(fuente, str(h.get("stat", "")),
						StatBlock.ModKind.PORCENTUAL, float(h.get("valor", 0.0)))
				elif stats.has_mod(fuente):
					stats.remove_mod(fuente)
			"bandera":
				_banderas[str(h.get("flag", ""))] = abierto


## Nombres de los hechos desbloqueados, para la UI.
func nombres_desbloqueados() -> Array[String]:
	var salida: Array[String] = []
	for id in desbloqueados():
		salida.append(nombre_de(id))
	return salida


# --- save -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"version": 1, "banderas": _banderas.duplicate()}


## El guardado guarda SOLO las banderas: los mods se recalculan desde
## `aplicar()` al cargar, así que un save viejo no puede dejar un mod
## fantasma de un hecho que el jugador ya no cumple.
func cargar_estado(d: Dictionary) -> void:
	_banderas.clear()
	for k in d.get("banderas", {}).keys():
		_banderas[str(k)] = bool(d["banderas"][k])
