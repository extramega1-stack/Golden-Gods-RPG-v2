class_name Talar
extends RefCounted
## Fase 55: la lógica de TALAR, pura y sin UI, calcada de `Mineria`.
##
## Igual que la minería: el nodo `Arbol` guarda el estado (usos, respawn) y
## esta clase solo decide SI se puede talar y qué se lleva. Separa el
## "puede" del "lo tiene" para que sea testeable headless sin árbol ni mundo.
##
## Diferencia con la minería: la tala da XP de habilidad, no de personaje
## (eso lo agrega la fase 57, vía `Habilidades`). Acá se mantiene el mismo
## contrato de la fase 45 para no romper `Mineria`.

## Motivos por los que no se puede talar (mismo estilo que `Mineria`).
const MOTIVO_OK: String = ""
const MOTIVO_SIN_HABILIDAD: String = "sin_habilidad"
const MOTIVO_AGOTADO: String = "agotado"
const MOTIVO_EN_RESPAWN: String = "en_respawn"
const MOTIVO_NIVEL: String = "nivel"


## ¿Se puede talar este árbol ahora? `jugador_nivel` es el nivel de personaje,
## que es lo que usa la regla de la región (igual que las vetas).
static func puede_talar(arbol: Veta, jugador_nivel: int, hechos: Hechos = null) -> String:
	if arbol == null or not is_instance_valid(arbol):
		return MOTIVO_SIN_HABILIDAD
	if jugador_nivel < arbol.nivel_min - tolerancia(hechos):
		return MOTIVO_NIVEL
	if not arbol.esta_minable():
		if arbol.respawn_restante > 0.0:
			return MOTIVO_EN_RESPAWN
		return MOTIVO_AGOTADO
	return MOTIVO_OK


## Texto legible del motivo, para el aviso al jugador.
static func texto_motivo(motivo: String) -> String:
	match motivo:
		MOTIVO_OK:
			return ""
		MOTIVO_SIN_HABILIDAD:
			return "No hay ningún árbol talable aquí"
		MOTIVO_AGOTADO:
			return "Este árbol ya está talado"
		MOTIVO_EN_RESPAWN:
			return "El árbol está creciendo de vuelta"
		MOTIVO_NIVEL:
			return "Demasiado nivel para tu nivel"
		_:
			return "No se puede talar"


## Un tajo: gasta un uso del árbol y devuelve qué se sacó.
## El árbol ya se configuró y se verificó con `puede_talar` antes de llamar.
## Fase 59: multiplicador de troce según las banderas de Hechos. `hechos`
## puede ser null (un test, o antes de que el Player los cree).
static func multiplicador(hechos: Hechos) -> int:
	if hechos != null and hechos.tiene("tala_area"):
		return 3
	return 1


## Fase 59: cuántos tramos de nivel puede sobrepasar. Con "Leñador" (tramo 4
## de Tala) tala hasta 2 tramos por encima de su banda.
static func tolerancia(hechos: Hechos) -> int:
	if hechos != null and hechos.tiene("tala_rangos"):
		return 2
	return 0


## Un tajo. Con `tala_area` devuelve la cantidad triplicada, pero GASTA UN
## SOLO USO del árbol: es la sorpresa buena del hecho (más madera por tajo),
## no un multiplicador gratuito de recursos.
static func talar(arbol: Veta, hechos: Hechos = null) -> Dictionary:
	if arbol == null or not is_instance_valid(arbol):
		return {"ok": false, "item_id": "", "cantidad": 0, "xp": 0, "motivo": MOTIVO_SIN_HABILIDAD}
	var item_id: String = arbol.item_id
	var cantidad: int = arbol.cantidad
	var xp: int = arbol.xp
	arbol.consumir_uso()
	return {
		"ok": true,
		"item_id": item_id,
		"cantidad": cantidad * multiplicador(hechos),
		"cantidad_base": cantidad,
		"xp": xp,
		"arbol_id": arbol.veta_id,
		"agotado": arbol.usos <= 0,
		"motivo": MOTIVO_OK,
	}
