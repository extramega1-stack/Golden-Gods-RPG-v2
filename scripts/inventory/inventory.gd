class_name Inventario
extends RefCounted
## Inventario del jugador: 20 slots; los items apilables ocupan un solo slot.
##
## `entradas` es pública SOLO para lectura de la UI:
## [{"item_id": String, "cantidad": int, "afijos": Array}]. Ningún otro
## sistema la escribe. Los ids se validan contra ItemDB; un id desconocido se
## rechaza con warning.
##
## Bloque 69 (afijos): una entrada puede llevar `"afijos"` — la lista que
## `AfijosLoot` sorteó cuando el item cayó. La clave SIEMPRE existe (vacía si
## el item no lleva), así que la UI no tiene que preguntar. Un item con afijos
## NUNCA se fusiona con uno sin afijos del mismo id: son dos objetos distintos.
## Los afijos solo van a equipables (arma/armadura/accesorio), que además son
## no-apilables, así que cada uno ocupa su slot.

signal cambiado()

const CAPACIDAD: int = 20
const SAVE_VERSION: int = 1

## Solo-lectura para la UI. No escribir desde fuera.
var entradas: Array = []


## Agrega items. Retorna lo que NO cupo (0 = todo entró).
## Si el id no existe en ItemDB: push_warning y retorna `cantidad` intacta.
## `afijos` es la lista ya sorteada en el drop (vacía = item normal).
func agregar(item_id: String, cantidad: int = 1, afijos: Array = []) -> int:
	if cantidad <= 0:
		return 0
	if not ItemDB.existe(item_id):
		push_warning("[Inventario] item desconocido: %s" % item_id)
		return cantidad
	var item: Dictionary = ItemDB.obtener(item_id)
	var restante: int = cantidad
	var lleva_afijos: bool = not afijos.is_empty()
	if bool(item.get("apilable", false)) and not lleva_afijos:
		var idx: int = _indice_de(item_id)
		if idx >= 0:
			var e: Dictionary = entradas[idx]
			e["cantidad"] = int(e.get("cantidad", 0)) + restante
			restante = 0
		elif entradas.size() < CAPACIDAD:
			entradas.append({"item_id": item_id, "cantidad": restante, "afijos": []})
			restante = 0
	else:
		# Un item con afijos va SIEMPRE en su propio slot, uno por unidad: dos
		# dagas del mismo nivel con afijos distintos son dos dagas distintas.
		while restante > 0 and entradas.size() < CAPACIDAD:
			entradas.append({
				"item_id": item_id,
				"cantidad": 1,
				"afijos": afijos.duplicate(true),
			})
			restante -= 1
	if restante < cantidad:
		cambiado.emit()
	return restante


## Lista enriquecida para la UI: [{id, cantidad, item, afijos}].
func listar() -> Array:
	var out: Array = []
	for e in entradas:
		if not (e is Dictionary):
			continue
		var iid: String = str(e.get("item_id", ""))
		if iid == "" or not ItemDB.existe(iid):
			continue
		out.append({"id": iid, "cantidad": int(e.get("cantidad", 1)),
			"item": ItemDB.obtener(iid),
			"afijos": afijos_de_entrada(e)})
	return out


## Los afijos de una entrada del inventario, SIEMPRE como Array (vacío si no
## lleva). Copia profunda: la UI no puede escribir en el inventario por
## accidente. Única puerta de lectura para el afijo, y es de solo lectura.
## Estática porque no depende de ESTE inventario: lee la entrada que le pasan.
static func afijos_de_entrada(entrada: Dictionary) -> Array:
	var af: Variant = entrada.get("afijos", [])
	if not (af is Array) or (af as Array).is_empty():
		return []
	var limpio: Array = []
	for a in (af as Array):
		if a is Dictionary:
			limpio.append((a as Dictionary).duplicate(true))
	return limpio


## ¿Alguna entrada del inventario lleva afijos? Para la UI: si es false, se
## dibuja exactamente igual que antes del bloque 69.
func tiene_afijos() -> bool:
	for e in entradas:
		if e is Dictionary and not afijos_de_entrada(e).is_empty():
			return true
	return false



## Quita items. Retorna false (sin tocar nada) si no hay stock suficiente.
func quitar(item_id: String, cantidad: int = 1) -> bool:
	if cantidad <= 0:
		return false
	if contar(item_id) < cantidad:
		return false
	var restante: int = cantidad
	for i in range(entradas.size() - 1, -1, -1):
		if restante <= 0:
			break
		var e: Dictionary = entradas[i]
		if str(e.get("item_id", "")) != item_id:
			continue
		var tiene: int = int(e.get("cantidad", 0))
		var saca: int = mini(tiene, restante)
		restante -= saca
		tiene -= saca
		if tiene <= 0:
			entradas.remove_at(i)
		else:
			e["cantidad"] = tiene
	cambiado.emit()
	return true


## Total de unidades de un item en todo el inventario.
func contar(item_id: String) -> int:
	var total: int = 0
	for e in entradas:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		if str(d.get("item_id", "")) == item_id:
			total += int(d.get("cantidad", 0))
	return total


## Usa un consumible sobre `objetivo`: "curar" → heal, "mana" → restaurar_mana.
## Descuenta 1 unidad y retorna true. No consumible o sin stock → false.
func usar(item_id: String, objetivo: Entity) -> bool:
	if not ItemDB.existe(item_id):
		return false
	if contar(item_id) <= 0:
		return false
	var item: Dictionary = ItemDB.obtener(item_id)
	if str(item.get("tipo", "")) != "consumible":
		return false
	var efecto: Dictionary = item.get("efecto", {})
	match str(efecto.get("tipo", "")):
		"curar":
			objetivo.heal(float(efecto.get("cantidad", 0.0)))
		"mana":
			objetivo.restaurar_mana(float(efecto.get("cantidad", 0.0)))
		# Fase 54: comida y bebida van a los vitales, no a vida/maná. Es el
		# "tick-eat" de Dragonwilds: se consume al instante desde la barra.
		"comida", "bebida":
			objetivo.vitals.consumir(efecto)
			# Fase 72: el sonido va AQUÍ y no en `Vitals` porque `Vitals` es una
			# clase pura (sin nodos, sin reloj, testeable sola) y meterse un
			# `AudioJuego` la rompe. Además esta es la única vía por la que se
			# come o se bebe, así que es el punto sin duplicados. Son distintos
			# porque el oído los distingue sin mirar nada.
			if str(efecto.get("tipo", "")) == "comida":
				AudioJuego.al_comer()
			else:
				AudioJuego.al_beber()
		_:
			return false
	quitar(item_id, 1)
	return true


## Slots ocupados (un apilable con N unidades = 1 slot).
func slots_usados() -> int:
	return entradas.size()


func _indice_de(item_id: String) -> int:
	for i in entradas.size():
		var e: Dictionary = entradas[i]
		if str(e.get("item_id", "")) == item_id:
			return i
	return -1


## Serialización versionada (la usará el save/load).
## Bloque 69: los afijos viajan con la entrada (sin ellos, un item afijado
## perdería su identidad al guardar). SAVE_VERSION sigue en 1 a propósito: el
## campo es aditivo y `from_dict` lo tolera ausente, así que una partida vieja
## carga igual sin migración manual.
func to_dict() -> Dictionary:
	var lista: Array = []
	for e in entradas:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		lista.append({
			"item_id": str(d.get("item_id", "")),
			"cantidad": int(d.get("cantidad", 0)),
			"afijos": afijos_de_entrada(d),
		})
	return {"version": SAVE_VERSION, "items": lista}


## Reconstruye desde un dict; tolera campos ausentes (incluido "afijos", que
## es lo que hace que un save anterior al bloque 69 cargue sin tocar nada) e
## ignora ids inválidos.
static func from_dict(d: Dictionary) -> Inventario:
	var inv: Inventario = Inventario.new()
	var lista: Array = d.get("items", [])
	for e in lista:
		if not (e is Dictionary):
			continue
		var ed: Dictionary = e
		var item_id: String = str(ed.get("item_id", ""))
		var cantidad: int = int(ed.get("cantidad", 0))
		if item_id == "" or cantidad <= 0:
			continue
		if not ItemDB.existe(item_id):
			push_warning("[Inventario] from_dict ignora id desconocido: %s" % item_id)
			continue
		inv.agregar(item_id, cantidad, inv.afijos_de_entrada(ed))
	return inv
