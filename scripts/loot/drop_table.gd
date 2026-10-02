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
	# FASE 72 — el escalado de afijos ya NO va a cero.
	#
	# Venía así: "los dos son opcionales y salen de la TABLA, no del código: hoy
	# ningún arquetipo los declara (van 0)". O sea que el afijo escalaba solo por
	# rareza, y TODOS los bots del mundo soltaban el mismo afijo para siempre:
	# el +fuerza de un goblin de nivel 3 y el de un titán de nivel 70 pesaban
	# exactamente lo mismo. El camino de datos ya estaba entero
	# (`nivel` → valor, `afijos_extra` → cantidad); lo que faltaba era que
	# alguien lo llenara.
	#
	# - `nivel` lo DECLARA el arquetipo en `data/enemies.json`, como la mediana
	#   del nivel de sus spawns: es el nivel del mundo donde vive ese bicho.
	# - `afijos_extra` es el margen PROPIO del arquetipo (0 en un mob normal, más
	#   en un jefe) MÁS el del NG+ de ahora, leído del estado vivo.
	#
	# El margen del NG+ se lee de un estático en RAM (`EstadoNgPlus`), nunca del
	# disco: `roll_drops` corre en cada muerte de mob y una lectura de archivo
	# ahí es justo lo que §9.5 prohíbe.
	var nivel: int = maxi(0, int(tabla.get("nivel", 0)))
	var afijos_extra: int = maxi(0, int(tabla.get("afijos_extra", 0))) \
			+ maxi(0, EstadoNgPlus.afijos_extra_en_juego())
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
