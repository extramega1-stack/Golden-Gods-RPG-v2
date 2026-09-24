class_name Herreria
extends RefCounted
## Lógica de forja (fase 44): valida, consume y entrega. SIN estado y SIN
## nodo — la UI la usa y la DB le da los datos (`RecetasDB`).
##
## Regla dura: la forja NUNCA escribe stats; solo mueve inventario y oro
## (el equipo sigue aplicando sus mods por `Equipo`). Fabricar es
## instantáneo (sin timers) y no da XP: el oro y los materiales son el coste.

signal forjado(receta_id: String, item_id: String)


## Motivos: "ok", "desconocida", "materiales", "oro", "nivel", "sin_oro".
## `puede_forjar` no consume nada.
func puede_forjar(receta_id: String, jugador: Player) -> String:
	if jugador == null:
		return "desconocida"
	var r: Dictionary = RecetasDB.obtener(receta_id)
	if r.is_empty():
		return "desconocida"
	if jugador.nivel < int(r.get("nivel", 1)):
		return "nivel"
	if jugador.oro < int(r.get("oro", 0)):
		return "oro"
	for m in _materiales(r):
		var md: Dictionary = m
		if jugador.inventario.contar(str(md.get("item_id", ""))) < int(md.get("cantidad", 0)):
			return "materiales"
	return "ok"


## Intenta forjar. Consume materiales y oro, entrega el item y emite
## `forjado`. Retorna el mismo motivo que `puede_forjar` si no puede.
func forjar(receta_id: String, jugador: Player) -> String:
	var motivo: String = puede_forjar(receta_id, jugador)
	if motivo != "ok":
		return motivo
	var r: Dictionary = RecetasDB.obtener(receta_id)
	for m in _materiales(r):
		var md: Dictionary = m
		jugador.inventario.quitar(str(md.get("item_id", "")), int(md.get("cantidad", 0)))
	var oro: int = int(r.get("oro", 0))
	if oro > 0:
		jugador.gastar_oro(oro)
	var res: Dictionary = r.get("resultado", {})
	var item_id: String = str(res.get("item_id", ""))
	jugador.inventario.agregar(item_id, int(res.get("cantidad", 1)))
	forjado.emit(receta_id, item_id)
	return "ok"


## Lista de materiales de una receta con lo que tienes y lo que falta
## (para el panel: "Carina de Escorpión 2/3"). Vacía si la receta no existe.
func estado_materiales(receta_id: String, jugador: Player) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	var r: Dictionary = RecetasDB.obtener(receta_id)
	if r.is_empty() or jugador == null:
		return res
	for m in _materiales(r):
		var md: Dictionary = m
		var iid: String = str(md.get("item_id", ""))
		var need: int = int(md.get("cantidad", 0))
		var tiene: int = jugador.inventario.contar(iid)
		res.append({
			"item_id": iid,
			"nombre": _nombre_de(iid),
			"necesario": need,
			"tiene": tiene,
			"falta": maxi(need - tiene, 0),
		})
	return res


## Texto "2/3" de la lista de estado (para el panel).
static func texto_materiales(lista: Array[Dictionary]) -> String:
	var partes: PackedStringArray = []
	for m in lista:
		partes.append("%d/%d" % [int((m as Dictionary).get("tiene", 0)),
			int((m as Dictionary).get("necesario", 0))])
	return " · ".join(partes)


## Motivo en texto humano para el panel.
static func texto_motivo(motivo: String) -> String:
	match motivo:
		"materiales":
			return "Te faltan materiales"
		"oro":
			return "No te alcanza el oro"
		"nivel":
			return "Nivel de herrero insuficiente"
		"desconocida":
			return "Receta desconocida"
		"sin_oro":
			return "No tienes oro"
	return "Puedes forjar"


func _materiales(receta: Dictionary) -> Array:
	var cruda: Array = receta.get("materiales", [])
	var res: Array = []
	for m in cruda:
		if m is Dictionary:
			res.append(m)
	return res


func _nombre_de(item_id: String) -> String:
	return str(ItemDB.obtener(item_id).get("nombre", item_id))
