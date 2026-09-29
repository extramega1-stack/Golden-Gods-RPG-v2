class_name Inventario
extends RefCounted
## Inventario del jugador: 20 slots; los items apilables ocupan un solo slot.
##
## `entradas` es pública SOLO para lectura de la UI:
## [{"item_id": String, "cantidad": int}]. Ningún otro sistema la escribe.
## Los ids se validan contra ItemDB; un id desconocido se rechaza con warning.

signal cambiado()

const CAPACIDAD: int = 20
const SAVE_VERSION: int = 1

## Solo-lectura para la UI. No escribir desde fuera.
var entradas: Array = []


## Agrega items. Retorna lo que NO cupo (0 = todo entró).
## Si el id no existe en ItemDB: push_warning y retorna `cantidad` intacta.
func agregar(item_id: String, cantidad: int = 1) -> int:
	if cantidad <= 0:
		return 0
	if not ItemDB.existe(item_id):
		push_warning("[Inventario] item desconocido: %s" % item_id)
		return cantidad
	var item: Dictionary = ItemDB.obtener(item_id)
	var restante: int = cantidad
	if bool(item.get("apilable", false)):
		var idx: int = _indice_de(item_id)
		if idx >= 0:
			var e: Dictionary = entradas[idx]
			e["cantidad"] = int(e.get("cantidad", 0)) + restante
			restante = 0
		elif entradas.size() < CAPACIDAD:
			entradas.append({"item_id": item_id, "cantidad": restante})
			restante = 0
	else:
		while restante > 0 and entradas.size() < CAPACIDAD:
			entradas.append({"item_id": item_id, "cantidad": 1})
			restante -= 1
	if restante < cantidad:
		cambiado.emit()
	return restante


## Lista enriquecida para la UI: [{id, cantidad, item}].
func listar() -> Array:
	var out: Array = []
	for e in entradas:
		if not (e is Dictionary):
			continue
		var iid: String = str(e.get("item_id", ""))
		if iid == "" or not ItemDB.existe(iid):
			continue
		out.append({"id": iid, "cantidad": int(e.get("cantidad", 1)),
			"item": ItemDB.obtener(iid)})
	return out


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
func to_dict() -> Dictionary:
	var lista: Array = []
	for e in entradas:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		lista.append({
			"item_id": str(d.get("item_id", "")),
			"cantidad": int(d.get("cantidad", 0)),
		})
	return {"version": SAVE_VERSION, "items": lista}


## Reconstruye desde un dict; tolera campos ausentes e ignora ids inválidos.
static func from_dict(d: Dictionary) -> Inventario:
	var inv: Inventario = Inventario.new()
	var lista: Array = d.get("items", [])
	for e in lista:
		if not (e is Dictionary):
			continue
		var item_id: String = str(e.get("item_id", ""))
		var cantidad: int = int(e.get("cantidad", 0))
		if item_id == "" or cantidad <= 0:
			continue
		if not ItemDB.existe(item_id):
			push_warning("[Inventario] from_dict ignora id desconocido: %s" % item_id)
			continue
		inv.agregar(item_id, cantidad)
	return inv
