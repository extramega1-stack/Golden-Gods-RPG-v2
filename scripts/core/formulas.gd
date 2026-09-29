class_name Formulas
extends RefCounted
## Fórmulas de combate y progresión como funciones PURAS y estáticas.
##
## Reglas de esta clase (directriz de Juan Diego):
## - Sin nodos, sin estado global, sin RNG oculto. El azar se INYECTA:
##   `crit_roll` y `variance_roll` los genera quien llama (el futuro Entity).
## - Mismas entradas → misma salida, siempre. Por eso se puede probar
##   headless en ~2 segundos (ver tests/test_stats.gd).
## - Las curvas y constantes viven aquí como datos con nombre, no regadas
##   en el código de los sistemas.

## Curva de XP: XP_BASE * (nivel - 1) ^ XP_EXPONENTE = XP acumulada para nivel.
const XP_BASE: float = 100.0
const XP_EXPONENTE: float = 1.5

## Mitigación: multiplicador = K / (K + defensa). defensa=100 → 0.5 (mitad).
const MITIGACION_K: float = 100.0


## Multiplicador de daño tras defensa. Siempre en (0, 1]. Sin defensa = 1.0.
static func mitigation(defensa: float) -> float:
	var d: float = maxf(defensa, 0.0)
	return MITIGACION_K / (MITIGACION_K + d)


## XP total acumulada necesaria para estar en `nivel` (nivel >= 1).
## xp_for_level(1) = 0. Estrictamente creciente: cada nivel cuesta más.
static func xp_for_level(nivel: int) -> int:
	if nivel <= 1:
		return 0
	var n: float = float(nivel - 1)
	var xp: float = XP_BASE * pow(n, XP_EXPONENTE)
	return int(xp)


class ResultadoDano extends RefCounted:
	## Fase 51: el resultado de un golpe, como OBJETO y no como Dictionary.
	##
	## Antes `damage()` devolvía un Dictionary literal, o sea UNA ASIGNACIÓN
	## DE MEMORIA POR GOLPE. Con 6 mobs peleando a 1.6 s de cooldown son ~10
	## por segundo, y en una región densa, cientos. Un RefCounted también
	## se asigna en el heap, pero es UN solo objeto por tipo, sus campos son
	## escrituras directas (sin hashtable) y no hay claves string que
	## hashear. El hot path usa este tipo; `damage()` sigue existiendo y
	## devuelve Dictionary para los tests y las llamadas viejas.
	var base: float = 0.0
	var mitigado: float = 0.0
	var crit: bool = false
	var final: int = 0


static var _pool: ResultadoDano = ResultadoDano.new()


## El resultado de un golpe SIN asignar memoria: reutiliza un objeto de la
## pool y lo rellena. Solo válido hasta la siguiente llamada.
static func damage_sin_alloc(atacante: StatBlock, defensor: StatBlock, skill: Dictionary,
		crit_roll: float, variance_roll: float) -> ResultadoDano:
	var power: float = float(skill.get("power", 1.0))
	var magica: bool = bool(skill.get("magica", false))
	var bonus_crit: float = float(skill.get("bonus_crit", 0.0))
	var varianza: float = float(skill.get("varianza", 0.10))

	var stat_ataque: float = atacante.poder if magica else atacante.ataque
	var base: float = stat_ataque * power
	var mitigado: float = base * mitigation(defensor.defensa)

	var prob_crit: float = clampf(atacante.crit_prob + bonus_crit, 0.0, 1.0)
	var es_crit: bool = crit_roll < prob_crit
	var con_crit: float = mitigado * (atacante.crit_dmg if es_crit else 1.0)

	var variado: float = con_crit * (1.0 + varianza * variance_roll)

	var r: ResultadoDano = _pool
	r.base = base
	r.mitigado = mitigado
	r.crit = es_crit
	r.final = maxi(1, roundi(variado))
	return r


## Daño de una habilidad. Pura: sin RNG interno.
##
## `skill` es DATO con claves (todas opcionales):
##   "power"      float  multiplicador de daño (default 1.0)
##   "magica"     bool   usa `poder` en vez de `ataque` (default false)
##   "bonus_crit" float  probabilidad de crítico extra (default 0.0)
##   "varianza"   float  fracción ± de variación (default 0.10)
## `crit_roll` en [0, 1): hay crítico si crit_roll < prob. de crítico.
## `variance_roll` en [-1, 1]: -1 = golpe bajo, 1 = golpe alto.
##
## Retorna {"base": float, "mitigado": float, "crit": bool, "final": int}.
## El daño mínimo es 1: un golpe que conecta siempre hace algo.
##
## Envoltura de `damage_sin_alloc` que devuelve un Dictionary (una alloc por
## golpe). Se mantiene porque los tests y las llamadas viejas la usan; los
## tres call sites del hot path usan `damage_sin_alloc`.
static func damage(atacante: StatBlock, defensor: StatBlock, skill: Dictionary, crit_roll: float, variance_roll: float) -> Dictionary:
	var r: ResultadoDano = damage_sin_alloc(atacante, defensor, skill, crit_roll, variance_roll)
	return {"base": r.base, "mitigado": r.mitigado, "crit": r.crit, "final": r.final}
