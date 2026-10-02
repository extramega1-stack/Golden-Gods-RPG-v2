class_name Cocina
extends RefCounted
## Fase 56: cocinar. Lógica PURA, sin UI, calcada de `Mineria` y `Talar`.
##
## Cierra el círculo de la recolección: talar/minar → cocina → comer. Sin
## esto la comida cruda es solo penalización, y la fase 58 (hambre) sería
## un castigo sin contrajuego.
##
## Por qué la cruda tiene `riesgo: enfermedad` en `data/items.json`: comer
## crudo enferma y con enfermo el hambre baja más rápido (`Vitals`). Cocinar
## es lo que convierte un riesgo en una decisión.
##
## Una fogata sin leña no cocina: la leña es `tronco_*` (fase 55). Así la tala
## tiene un consumidor y el combustible no es gratis.

## Motivos por los que no se puede cocinar.
const MOTIVO_OK: String = ""
const MOTIVO_SIN_RECETA: String = "sin_receta"
const MOTIVO_SIN_INGREDIENTE: String = "sin_ingrediente"
const MOTIVO_SIN_LEÑA: String = "sin_lena"
const MOTIVO_TIEMPO: String = "tiempo"

## Segundos de leña que da un tronco (constante con nombre, no magia).
const LENA_POR_TRONCO: float = 12.0
## Tiempo de cocción por receta (el `data/recetas_cocina.json` lo define).
const TIEMPO_BASE: float = 3.0


## Verifica si se puede cocinar. `inventario` es un `Dictionary` de
## `{item_id: cantidad}` — NO el Inventario: así la función queda pura y se
## prueba sin nodos.
static func puede_cocinar(item_id: String, receta: Dictionary,
		inventario: Dictionary, lena: float) -> String:
	if receta.is_empty():
		return MOTIVO_SIN_RECETA
	if int(inventario.get(item_id, 0)) <= 0:
		return MOTIVO_SIN_INGREDIENTE
	var necesidad: float = float(receta.get("lena", 1.0))
	if lena < necesidad:
		return MOTIVO_SIN_LEÑA
	return MOTIVO_OK


## Cocina: gasta el ingrediente y la leña, devuelve el resultado.
## Quien llama es responsable de mover el item al inventario.
##
## FASE 72: `hechos` es lo que hace que el Hecho "Cocina de lote" (cocina,
## tramo 2) exista. Antes se calculaba, se guardaba y no lo leía nadie: una
## recompensa que el jugador no podía ganar. Multiplica la cantidad de
## raciones, y el multiplicador sale de `data/hechos.json`
## (`parametros.multiplicador_cantidad`), no de acá. Es opcional y con default
## para que un test pueda cocinar sin montar Hechos.
static func cocinar(item_id: String, receta: Dictionary,
		inventario: Dictionary, hechos: Hechos = null) -> Dictionary:
	var motivo: String = puede_cocinar(item_id, receta, inventario, LENA_POR_TRONCO)
	if motivo != MOTIVO_OK:
		return {"ok": false, "motivo": motivo, "item_id": "", "cantidad": 0}
	inventario[item_id] = int(inventario.get(item_id, 0)) - 1
	if int(inventario[item_id]) <= 0:
		inventario.erase(item_id)
	return {
		"ok": true,
		"motivo": MOTIVO_OK,
		"item_id": str(receta.get("resultado", "")),
		"cantidad": maxi(1, int(receta.get("cantidad", 1))) * multiplicador(hechos),
		"xp": maxi(0, int(receta.get("xp", 0))),
		"lena": float(receta.get("lena", 1.0)),
		"segundos": maxf(float(receta.get("segundos", TIEMPO_BASE)), 0.1),
	}


## FASE 72: por cuántas salen las raciones. 1 sin el Hecho.
##
## Se calcula sobre la ración BASE de la receta, no sobre el resultado de la
## llamada anterior: `cocinar` es pura y se puede llamar dos veces con la misma
## receta, y multiplicar un resultado ya multiplicado sacaría raciones
## gratis sin haber cocinado el ingrediente nuevo.
static func multiplicador(hechos: Hechos) -> int:
	if hechos == null or not hechos.tiene(Hechos.FLAG_COCINA_LOTE):
		return 1
	return maxi(1, hechos.parametro_int(Hechos.ID_COCINA_LOTE,
		"multiplicador_cantidad", 2))


## Texto legible del motivo.
static func texto_motivo(motivo: String) -> String:
	match motivo:
		MOTIVO_OK:
			return ""
		MOTIVO_SIN_RECETA:
			return "No sé cocinar eso"
		MOTIVO_SIN_INGREDIENTE:
			return "No tenés el ingrediente"
		MOTIVO_SIN_LEÑA:
			return "No hay leña suficiente en la fogata"
		MOTIVO_TIEMPO:
			return "Tarda demasiado"
		_:
			return "No se puede cocinar"
