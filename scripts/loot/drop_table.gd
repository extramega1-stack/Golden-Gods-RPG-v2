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
##   {"tipo": "item", "item_id": String, "nombre": String, "cantidad": int,
##    "afijos": Array}
## Los items quedan como datos listos para el inventario de la fase 5.
## Pura salvo el RNG, que se inyecta: con la misma semilla salen los mismos
## drops (testeable headless).
##
## Bloque 69 (afijos): el drop de un item lleva `"afijos"`, ya sorteado por
## `AfijosLoot` con la semilla de ESTE rng. Siempre presente (vacío si no
## lleva) para que quien recoja no tenga que preguntar si la clave existe.
## El item sigue siendo un dict: un item sin afijos se dibuja igual que antes.


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
	# El afijo escala con el nivel del que cae y con el margen del NG+. Los dos
	# son opcionales y salen de la TABLA, no del código: hoy ningún arquetipo los
	# declara (van 0) y el afijo escala solo por rareza; el día que un arquetipo
	# los traiga, el afijo sube solo, sin tocar esta función.
	var nivel: int = maxi(0, int(tabla.get("nivel", 0)))
	var afijos_extra: int = maxi(0, int(tabla.get("afijos_extra", 0)))
	for entrada in items:
		var e: Dictionary = entrada
		var prob: float = float(e.get("prob", 0.0))
		if rng.randf() < prob:
			var cant_min: int = maxi(1, int(e.get("min", 1)))
			var cant_max: int = maxi(cant_min, int(e.get("max", 1)))
			var cant: int = rng.randi_range(cant_min, cant_max)
			var item_id: String = str(e.get("item_id", "item"))
			drops.append({
				"tipo": "item",
				"item_id": item_id,
				"nombre": str(e.get("nombre", "Item")),
				"cantidad": cant,
				# Bloque 69: los afijos se sortean AQUÍ, no al recoger. Si se
				# sortearan más tarde, dos mobs con la misma semilla podrían dar
				# loot distinto y el test de determinismo mentiría.
				"afijos": AfijosLoot.generar_para_item(item_id, rng, nivel,
					afijos_extra),
			})
	return drops
