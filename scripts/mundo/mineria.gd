class_name Mineria
extends RefCounted
## Lógica de minado (fase 45): valida, consume un uso y entrega. SIN estado y
## SIN nodo — la `Veta` guarda el estado y `GestorVetas` coloca los nodos
## (`VetaDB` le da los datos).
##
## Igual que la `Herreria` de la fase 44: la UI y el mundo no escriben reglas,
## llaman a esta API. Minar es INSTANTÁNEO (sin timers, sin canales), da XP
## pequeño y data-driven, y NO da oro ni toca stats: el oro es de las recetas
## y el equipo sigue aplicando sus mods.

## Se	minó un golpe con éxito (lo reemite `GestorVetas` para la UI).
signal minado(veta_id: String, item_id: String, cantidad: int, xp: int)

## Cuántos slots del inventario quedan libres (mismo umbral que la UI: 20).
const UMBRAL_LLENO: int = 3


## Motivos: "ok", "veta_nula", "agotada", "nivel", "inventario_lleno",
## "sin_espacio". `puede_minar` no consume nada.
func puede_minar(veta: Veta, jugador: Player) -> String:
	if veta == null or not is_instance_valid(veta):
		return "veta_nula"
	if jugador == null or jugador.inventario == null:
		return "veta_nula"
	if not veta.esta_minable():
		return "agotada"
	if jugador.nivel < veta.nivel_min:
		return "nivel"
	if _espacios_libres(jugador, veta.item_id) < UMBRAL_LLENO:
		return "inventario_lleno"
	return "ok"


## Intenta minar un golpe. Gasta un uso de la veta, mete el mineral en el
## inventario, da el XP y muestra el aviso flotante. Retorna el mismo motivo
## que `puede_minar` si no se puede, sin tocar nada.
func minar(veta: Veta, jugador: Player) -> String:
	var motivo: String = puede_minar(veta, jugador)
	if motivo != "ok":
		return motivo
	var item_id: String = veta.item_id
	var cantidad: int = maxi(1, veta.cantidad)
	var xp: int = maxi(0, veta.xp)
	# La veta se gasta ANTES de entregar: si el item no existiera en el
	# catálogo el golpe se pierde, pero el mundo nunca queda con usos gratis.
	veta.consumir_uso()
	jugador.inventario.agregar(item_id, cantidad)
	if xp > 0:
		jugador.gain_xp(xp)
	veta.mostrar_aviso(texto_minado(item_id, cantidad, xp))
	minado.emit(veta.veta_id, item_id, cantidad, xp)
	return "ok"


## Texto del aviso flotante: "+2 Mineral de Cobre (+9 XP)".
static func texto_minado(item_id: String, cantidad: int, xp: int) -> String:
	var nombre: String = str(ItemDB.obtener(item_id).get("nombre", item_id))
	var txt: String = "+%d %s" % [cantidad, nombre]
	if xp > 0:
		txt += " (+%d XP)" % xp
	return txt


## Motivo en texto humano (el aviso del mundo y los tests).
static func texto_motivo(motivo: String) -> String:
	match motivo:
		"agotada":
			return "La veta está agotada"
		"nivel":
			return "Necesitas más nivel para esta veta"
		"inventario_lleno":
			return "No te cabe en la mochila"
		"veta_nula":
			return "No hay veta aquí"
	return "Puedes minar"


## Slots que le quedan al jugador. Si el mineral ya está en la mochila y es
## apilable, su entrada ya cuenta: minar no ocuparía un slot nuevo.
func _espacios_libres(jugador: Player, item_id: String) -> int:
	var inv: Inventario = jugador.inventario
	if inv == null:
		return 0
	var libres: int = maxi(0, Inventario.CAPACIDAD - inv.slots_usados())
	var item: Dictionary = ItemDB.obtener(item_id)
	if bool(item.get("apilable", false)) and inv.contar(item_id) > 0:
		libres += 1
	return libres
