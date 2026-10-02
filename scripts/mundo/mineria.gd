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
	# Hotfix 62.1: un árbol no obeyece la banda de nivel de la veta, la de
	# `Talar`, que perdona 2 tramos con el Hecho "Leñador". Pregunta a quien
	# corresponde según el tipo de nodo, en vez de asumir que es veta.
	if veta is Arbol:
		var motivo_tala: String = Talar.puede_talar(veta, jugador.nivel, jugador.hechos)
		match motivo_tala:
			Talar.MOTIVO_NIVEL:
				return "nivel"
			Talar.MOTIVO_EN_RESPAWN, Talar.MOTIVO_AGOTADO:
				return "agotada"
	elif jugador.nivel < veta.nivel_min:
		return "nivel"
	if _espacios_libres(jugador, veta.item_id) < UMBRAL_LLENO:
		return "inventario_lleno"
	return "ok"


## Intenta minar un golpe. Gasta un uso de la veta, mete el mineral en el
## inventario, da el XP y muestra el aviso flotante. Retorna el mismo motivo
## que `puede_minar` si no se puede, sin tocar nada.
##
## FASE 72: el Hecho "veta_persistente" (minería, tramo 2) se calculaba y se
## guardaba, y NINGÚN sistema lo consultaba: era una recompensa que el jugador
## no podía ganar. Acá es donde cobra efecto —después de gastar el uso, que es
## el único punto donde una veta puede quedarse seca— y el número de usos que
## deja sale de `data/hechos.json` (`parametros.usos_min`), no de acá.
func minar(veta: Veta, jugador: Player) -> String:
	var motivo: String = puede_minar(veta, jugador)
	if motivo != "ok":
		return motivo
	var item_id: String = veta.item_id
	var cantidad: int = maxi(1, veta.cantidad)
	var xp: int = maxi(0, veta.xp)
	# Hotfix 62.1: un árbol pasa por `Talar.talar`, que es quien sabe aplicar
	# el Hecho "tala_area" (3 troncos por un solo uso). Sin este desvío el Hecho
	# se calculaba y se guardaba, pero nunca se usaba jugando.
	if veta is Arbol:
		var t: Dictionary = Talar.talar(veta, jugador.hechos)
		if not bool(t.get("ok", false)):
			return "agotada"
		cantidad = int(t.get("cantidad", cantidad))
	else:
		# La veta se gasta ANTES de entregar: si el item no existiera en el
		# catálogo el golpe se pierde, pero el mundo nunca queda con usos gratis.
		veta.consumir_uso()
	_sostener_veta(veta, jugador.hechos)
	jugador.inventario.agregar(item_id, cantidad)
	if xp > 0:
		jugador.gain_xp(xp)
		# Fase 57: la recolección da su propio XP de habilidad, aparte del de
		# personaje. Los dos suben: el de personaje manda en StatBlock.
		# Hotfix 62.1: la habilidad la declara el nodo (`Veta.habilidad_id`),
		# así que talar sube `tala` y minar sube `mineria`.
		if jugador.habilidades != null:
			jugador.habilidades.ganar(veta.habilidad_id, xp)
	veta.mostrar_aviso(texto_minado(item_id, cantidad, xp))
	minado.emit(veta.veta_id, item_id, cantidad, xp)
	return "ok"


## FASE 72: "Veta persistente" deja la veta con al menos `usos_min` usos, así
## que nunca se agota DEL TODO. Es el equivalente en vetas del Hecho de Tala
## "tala_area": más por golpe, no usos infinitos.
##
## APLICA TAMBIÉN A LOS ÁRBOLES, y a propósito: un `Arbol` es una `Veta` (hereda
## de ella) y el Hecho se llama "veta persistente", no "veta y árbol". Decirlo
## acá es mejor que dejarlo como efecto colateral sin nombre: un jugador con
## Minería en tramo 2 ve que los árboles tampoco se secan del todo, y si en
## algún momento se quiere limitar a las vetas, el corte es una línea.
##
## Idempotente y barato: solo hace algo si la veta se secó en este golpe, y el
## número sale del dato. Con la bandera apagada es una comparación y nada más.
func _sostener_veta(veta: Veta, hechos: Hechos) -> void:
	if veta == null or not is_instance_valid(veta) or hechos == null:
		return
	if not hechos.tiene(Hechos.FLAG_VETA_PERSISTENTE):
		return
	if veta.usos > 0:
		return
	var minimo: int = hechos.parametro_int(Hechos.ID_VETA_PERSISTENTE,
		"usos_min", 1)
	veta.reponer_usos(minimo)


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
