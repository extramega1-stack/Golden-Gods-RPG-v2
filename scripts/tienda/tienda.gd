class_name Tienda
extends RefCounted
## Lógica PURA de transacciones de tienda (fase 7). SIN UI.
##
## Estado mutable de stock: `tienda_id -> {item_id: cantidad}`, inicializado
## desde TiendaDB. La única forma de mutarlo es `comprar()`/`vender()`; la
## UI (PanelTienda) SOLO LEE con `stock_de()`/`precio_compra()`/
## `precio_venta()`. Cada transacción exitosa emite `cambiada` para que la
## UI se reconstruya (también se emiten `inventario.cambiado` y
## `oro_cambiado` del jugador por sus propios caminos).
##
## Precios data-driven: `precio_compra` por tienda/item en data/tiendas.json;
## `precio_venta` explícito por item, y si falta el default es
## `precio_compra / 2` entero (del primer precio de compra encontrado; si
## el item no está en ninguna tienda, del campo `precio` de items.json).

signal cambiada()

const SAVE_VERSION: int = 1

## tienda_id -> {item_id -> cantidad restante} (mutable).
var _stock: Dictionary = {}
## tienda_id -> {item_id -> precio_compra}.
var _compra: Dictionary = {}
## item_id -> precio_venta explícito en datos (cualquier tienda).
var _venta: Dictionary = {}


func _init() -> void:
	_inicializar_desde_datos()


## Restablece el stock completo desde TiendaDB (lo usa el constructor y
## `cargar_estado` antes de aplicar el guardado).
func _inicializar_desde_datos() -> void:
	TiendaDB.cargar()
	_stock.clear()
	_compra.clear()
	_venta.clear()
	for tid in TiendaDB.ids():
		var t: Dictionary = TiendaDB.obtener(tid)
		var items: Dictionary = {}
		var compras: Dictionary = {}
		var lista: Array = t.get("stock", [])
		for entrada in lista:
			if not (entrada is Dictionary):
				continue
			var e: Dictionary = entrada
			var item_id: String = str(e.get("item_id", ""))
			if item_id == "" or not ItemDB.existe(item_id):
				push_warning("[Tienda] stock ignora item inválido: '%s' (%s)" % [item_id, tid])
				continue
			var precio_c: int = maxi(0, int(e.get("precio_compra", _precio_base(item_id))))
			items[item_id] = maxi(0, int(e.get("cantidad", 0)))
			compras[item_id] = precio_c
			if e.has("precio_venta") and not _venta.has(item_id):
				_venta[item_id] = maxi(0, int(e.get("precio_venta")))
		_stock[tid] = items
		_compra[tid] = compras


## Compra 1 unidad de `item_id` en `tienda_id` para el jugador.
## Códigos: "ok" · "tienda_desconocida" · "item_desconocido" ·
## "sin_stock" · "sin_oro" · "sin_espacio" (el oro se revierte si el
## inventario no pudo recibir el item).
func comprar(jugador: Player, tienda_id: String, item_id: String) -> String:
	if jugador == null:
		push_warning("[Tienda] comprar sin jugador")
		return "tienda_desconocida"
	if not TiendaDB.existe(tienda_id):
		return "tienda_desconocida"
	if not ItemDB.existe(item_id):
		return "item_desconocido"
	var items: Dictionary = _stock.get(tienda_id, {})
	if not items.has(item_id):
		return "item_desconocido"
	if int(items.get(item_id, 0)) <= 0:
		return "sin_stock"
	if jugador.inventario == null:
		return "sin_espacio"
	var precio: int = precio_compra(tienda_id, item_id)
	if jugador.oro < precio:
		return "sin_oro"
	if not jugador.gastar_oro(precio):
		return "sin_oro"
	var resto: int = jugador.inventario.agregar(item_id, 1)
	if resto > 0:
		# Inventario lleno: se revierte el oro (nada cambió de verdad).
		jugador.ganar_oro(precio)
		return "sin_espacio"
	items[item_id] = int(items[item_id]) - 1
	cambiada.emit()
	return "ok"


## Vende `cantidad` unidades de `item_id` del inventario del jugador.
## Códigos: "ok" · "item_desconocido" · "equipado" (rechazado si el item
## está en algún slot del Equipo) · "sin_stock" (no lo tiene en la
## mochila). El oro se suma con `ganar_oro` (emite `oro_cambiado`).
func vender(jugador: Player, item_id: String, cantidad: int = 1) -> String:
	if jugador == null:
		push_warning("[Tienda] vender sin jugador")
		return "item_desconocido"
	if not ItemDB.existe(item_id):
		return "item_desconocido"
	if cantidad <= 0:
		return "sin_stock"
	if _equipado_en_algun_slot(jugador, item_id):
		return "equipado"
	if jugador.inventario == null or jugador.inventario.contar(item_id) < cantidad:
		return "sin_stock"
	if not jugador.inventario.quitar(item_id, cantidad):
		return "sin_stock"
	jugador.ganar_oro(precio_venta(item_id) * cantidad)
	cambiada.emit()
	return "ok"


## Precio de compra en esa tienda (0 si la tienda/item no existen).
func precio_compra(tienda_id: String, item_id: String) -> int:
	var compras: Dictionary = _compra.get(tienda_id, {})
	return int(compras.get(item_id, 0))


## Precio al que la tienda paga el item al jugador: el explícito en datos,
## o `precio_compra / 2` entero si el item no lo declara.
func precio_venta(item_id: String) -> int:
	if _venta.has(item_id):
		return int(_venta[item_id])
	for tid in _compra:
		var compras: Dictionary = _compra[tid]
		if compras.has(item_id):
			return int(compras[item_id]) / 2
	return _precio_base(item_id) / 2


## Stock legible para la UI: [{"item_id", "precio_compra",
## "precio_venta", "cantidad"}]. Solo lectura (no mutar lo devuelto).
func stock_de(tienda_id: String) -> Array:
	var resultado: Array = []
	var items: Dictionary = _stock.get(tienda_id, {})
	for item_id in items:
		var iid: String = str(item_id)
		resultado.append({
			"item_id": iid,
			"precio_compra": precio_compra(tienda_id, iid),
			"precio_venta": precio_venta(iid),
			"cantidad": int(items.get(item_id, 0)),
		})
	return resultado


func _equipado_en_algun_slot(jugador: Player, item_id: String) -> bool:
	if jugador.equipo == null:
		return false
	for slot in Equipo.SLOTS:
		if jugador.equipo.equipado_en(slot) == item_id:
			return true
	return false


static func _precio_base(item_id: String) -> int:
	if not ItemDB.existe(item_id):
		return 0
	return maxi(0, int(ItemDB.obtener(item_id).get("precio", 0)))


## Serialización versionada (la usa el save/load v4).
func to_dict() -> Dictionary:
	var tiendas: Dictionary = {}
	for tid in _stock:
		var items: Dictionary = _stock[tid]
		var copia: Dictionary = {}
		for item_id in items:
			copia[str(item_id)] = int(items[item_id])
		tiendas[str(tid)] = copia
	return {"version": SAVE_VERSION, "tiendas": tiendas}


## Aplica un dict guardado: primero restablece el stock completo desde
## datos y luego aplica las cantidades. Tolerante: tiendas/items
## desconocidos se ignoran con warning (nunca revienta).
func cargar_estado(d: Dictionary) -> void:
	_inicializar_desde_datos()
	var tiendas: Dictionary = d.get("tiendas", {})
	for tid in tiendas:
		var s: String = str(tid)
		if not _stock.has(s):
			push_warning("[Tienda] cargar_estado ignora tienda desconocida: %s" % s)
			continue
		var entrada: Variant = tiendas[tid]
		if not (entrada is Dictionary):
			continue
		var items: Dictionary = _stock[s]
		var guardados: Dictionary = entrada
		for item_id in guardados:
			var iid: String = str(item_id)
			if not items.has(iid):
				push_warning("[Tienda] cargar_estado ignora item desconocido: %s (%s)" % [iid, s])
				continue
			items[iid] = maxi(0, int(guardados[item_id]))


## Reconstruye desde un dict; tolera campos ausentes (stock completo).
static func from_dict(d: Dictionary) -> Tienda:
	var t: Tienda = Tienda.new()
	t.cargar_estado(d)
	return t
