class_name DropTable
extends RefCounted
## Tablas de botín como DATO + tiradas puras con RNG inyectado.
##
## Formato de tabla (Dictionary):
##   "oro_min": int, "oro_max": int,
##   "items": Array de {"item_id": String, "nombre": String,
##                      "prob": float, "min": int, "max": int}
##
## roll_drops(tabla, rng) -> Array[Dictionary]. Cada drop es:
##   {"tipo": "oro", "cantidad": int}  o
##   {"tipo": "item", "item_id": String, "nombre": String, "cantidad": int}
## Los items quedan como datos listos para el inventario de la fase 5.
## Pura salvo el RNG, que se inyecta: con la misma semilla salen los
## mismos drops (testeable headless).


## Tira los drops de una tabla. Retorna array (vacío si no cayó nada).
static func roll_drops(tabla: Dictionary, rng: RandomNumberGenerator) -> Array:
	var drops: Array = []
	var oro_min: int = int(tabla.get("oro_min", 0))
	var oro_max: int = int(tabla.get("oro_max", 0))
	if oro_max > 0 and oro_min <= oro_max:
		var oro: int = rng.randi_range(oro_min, oro_max)
		if oro > 0:
			drops.append({"tipo": "oro", "cantidad": oro})
	var items: Array = tabla.get("items", [])
	for entrada in items:
		var e: Dictionary = entrada
		var prob: float = float(e.get("prob", 0.0))
		if rng.randf() < prob:
			var cant_min: int = maxi(1, int(e.get("min", 1)))
			var cant_max: int = maxi(cant_min, int(e.get("max", 1)))
			var cant: int = rng.randi_range(cant_min, cant_max)
			drops.append({
				"tipo": "item",
				"item_id": str(e.get("item_id", "item")),
				"nombre": str(e.get("nombre", "Item")),
				"cantidad": cant,
			})
	return drops
