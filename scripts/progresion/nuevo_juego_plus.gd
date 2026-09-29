class_name NuevoJuegoPlus
extends RefCounted
## Bloque 68: el fin de contenido (prestigio / NG+).
##
## POR QUÉ EXISTE, Y POR QUÉ NO ES UNA FASE DE CONTENIDO: la auditoría
## encontró que el techo del juego era el nivel 70, que es el tope de la tabla
## de regiones (data/regiones.json, El Velo 55–70). A partir de ahí no había
## nada: ni prestige, ni NG+, ni daily, ni trofeos. Un jugador que llega al
## final se queda sin nada que hacer, y el ciclo se acaba en ~2 horas.
##
## EL PRESTIGIO es la respuesta más barata y la que más respeta al jugador:
## - reaching el tope reinicia nivel/stats y da PRESTIGIO,
## - cada punto de prestigio da un multiplicador de XP y un desbloqueo de
##   "resistencia" (el mundo se vuelve un poco más fácil de farmear),
## - se puede hacer las veces que quieras: es una espiral, no un techo.
##
## No es "prestigio de Diablo": no borra el mundo, no borra las habilidades de
## recolección. El bloque 53–62 (supervivencia) se queda, porque el jugador
## quiere ver sus árboles y su refugio después de subir. Lo que se reinicia es
## lo de PERSONAJE: nivel, stats de base, y el multiplicador es la progresión.

## El tope de nivel del mundo: el de la banda más alta de data/regiones.json.
const TOPE_NIVEL: int = 70
## Cuanto XP extra da cada punto de prestigio. 1.15 acumulativo: 5 prestigio
## es x2.0, que es suficiente para que NG+ sienta la diferencia sin ser un
## numero inflado.
const XP_POR_PRESTIGIO: float = 0.15
## Cada cuántos niveles baja un poco el enemigo en NG+ (0 = no baja). Es lo
## que hace que farmear en NG+ no sea "el mismo mundo pero lento".
const REDUCCION_ENEMIGO: float = 0.04
## Tope de la reducción: en 25 prestigio el enemigo no baja más de la mitad.
const REDUCCION_MAX: float = 0.5
## El prestige que "compra" un afijo extra por item. Cada 3 de prestigio.
const AFIXO_CADA: int = 3

## Cuánto prestigio da CERRAR un ciclo. La primera vuelta da 1, la segunda 2,
## la tercera 3… (triangular).
##
## POR QUÉ NO 1 FIJO: con +1 siempre, la décima vuelta del NG+ compra
## exactamente lo mismo que la primera, y el jugador para en la segunda o
## tercera. La espiral tiene que ABRIRSE más cada vuelta, o no es una espiral:
## es un techo con pasos.
const PRESTIGIO_POR_CICLO_BASE: int = 1

## La bonificación al PERSONAJE por punto de prestigio, en porcentaje de cada
## derivado. Es el otro lado del soborno y hacía falta: `multiplicador_enemigo`
## abarata el mundo, pero sin esto el héroe del NG+ 3 es un nivel 1 desnudo
## contra el mismo mundo, y la "ventaja" del prestigio es solo XP.
##
## Los cinco derivados, no los atributos base: los atributos los reparte el
## jugador con sus puntos, y un bono invisible sobre ellos no se puede leer
## en ningún sitio. `StatBlock` deriva de los atributos, así que tocar los
## derivados es lo que se ve en la ficha del personaje.
const BONO_ATAQUE_POR_PRESTIGIO: float = 0.05
const BONO_PODER_POR_PRESTIGIO: float = 0.05
const BONO_VIDA_POR_PRESTIGIO: float = 0.03
const BONO_MANA_POR_PRESTIGIO: float = 0.03
const BONO_DEFENSA_POR_PRESTIGIO: float = 0.02
## Tope del bono acumulado, en porcentaje. Sin tope, 40 prestigio de golpe
## deja al héroe con el doble de TODO y el combate deja de importar.
const BONO_MAX: float = 1.0


## El tope del mundo. Dato, no const lógica: si `regiones.json` sube el tope,
## esto lo sigue.
static func tope_nivel() -> int:
	return TOPE_NIVEL


## El prestigio que se gana al cerrar el ciclo `ciclo_actual` (0 = la primera
## partida del mundo). Triangular: 1, 2, 3, 4…
static func prestigio_ganado(ciclo_actual: int) -> int:
	return PRESTIGIO_POR_CICLO_BASE + maxi(0, ciclo_actual)


## El bono al personaje, como {stat -> porcentaje} (ModKind.PORCENTUAL).
## Es lo que `EstadoNgPlus` mete en el `StatBlock` del jugador. Prestigio 0 →
## diccionario VACÍO (no cinco ceros), para que "sin NG+" y "NG+ sin efecto"
## sean literalmente el mismo estado y no dos que se comportan igual.
static func bonificacion_stats(prestigio: int) -> Dictionary:
	var p: float = float(maxi(0, prestigio))
	if p <= 0.0:
		return {}
	return {
		"ataque": minf(BONO_ATAQUE_POR_PRESTIGIO * p, BONO_MAX),
		"poder": minf(BONO_PODER_POR_PRESTIGIO * p, BONO_MAX),
		"vida_max": minf(BONO_VIDA_POR_PRESTIGIO * p, BONO_MAX),
		"mana_max": minf(BONO_MANA_POR_PRESTIGIO * p, BONO_MAX),
		"defensa": minf(BONO_DEFENSA_POR_PRESTIGIO * p, BONO_MAX),
	}


## ¿Le toca prestigiar? Solo al llegar al tope, y solo si no lo hizo ya en
## esta vuelta.
static func puede_prestigiar(nivel: int, prestigio_actual: int) -> bool:
	return nivel >= TOPE_NIVEL


## El multiplicador de XP por prestigio. 0 = x1.0 (el normal).
static func multiplicador_prestigio(prestigio: int) -> float:
	var p: int = maxi(0, prestigio)
	return 1.0 + XP_POR_PRESTIGIO * float(p)


## Qué tan más fácil se vuelve el mundo. Los enemigos bajan su vida y daño.
static func multiplicador_enemigo(prestigio: int) -> float:
	var p: int = maxi(0, prestigio)
	return clampf(1.0 - REDUCCION_ENEMIGO * float(p), 1.0 - REDUCCION_MAX, 1.0)


## Los afijos extra que un item puede llevar por prestigio. Sin esto, el
## NG+ no da nada nuevo que buscar.
static func afijos_extra(prestigio: int) -> int:
	return int(maxi(0, prestigio) / AFIXO_CADA)


## Todo el estado del NG+ en un solo diccionario (para el save).
static func to_dict(prestigio: int) -> Dictionary:
	return {
		"prestigio": prestigio,
		"multiplicador_xp": multiplicador_prestigio(prestigio),
		"multiplicador_enemigo": multiplicador_enemigo(prestigio),
		"afijos_extra": afijos_extra(prestigio),
		"prestigios_totales": maxi(0, prestigio),
	}


## Lee el estado de un save viejo (sin NG+ = 0 prestigio, el normal).
static func desde_dict(d: Dictionary) -> int:
	return maxi(0, int(d.get("prestigio", 0)))
