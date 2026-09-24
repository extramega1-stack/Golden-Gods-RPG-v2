class_name StatBlock
extends RefCounted
## Bloque de estadísticas puro: atributos base → derivados calculados.
##
## Sin nodos, sin escena, sin estado global. Es solo DATOS.
## Principio de la rebuild (directriz de Juan Diego): todo cuelga de aquí;
## ningún sistema escribe stats a mano. Equipo, talentos y efectos futuros solo
## aportan MODIFICADORES identificados por fuente (ver add_mod), y la UI solo
## LEE estos valores, nunca los escribe.
##
## Fórmulas de derivados (documentadas para balance, fase 34/42):
## - vida_max   = 100 + fuerza * 20 + aguante * 15   (tanques viven más)
## - mana_max   = 50 + inteligencia * 15
## - ataque     = 5 + stat_daño * coef_ataque         (FASE 42: el stat
##   principal de la clase, no siempre fuerza)
## - poder      = 5 + stat_daño * coef_poder          (mismo stat principal:
##   subir DEX al arquero/daguero sube también su poder; subir INT al
##   mago/clérigo sube su poder y su canal físico)
## - defensa    = fuerza * 0.5 + aguante * 1.0       (placas resisten más)
## - crit_prob  = 0.05 + destreza * 0.004            (tope 0.60)
## - crit_dmg   = 1.50 + destreza * 0.010            (multiplicador)
## - vel_ataque = 1.0 + destreza * 0.008             (tope 2.0; el arquero
##   pega más rápido por DEX, no por AGI)
## - vel_mov    = 6.0                                (plano para todos)
##
## Fase 34: la agilidad SE ELIMINÓ. El modelo es STR/STA/DEX/INT (FlyFF):
## cada clase parte de 15 en todo + 15 extra en sus stats de rol
## (presupuestos iguales de 90 pts).
##
## Fase 42: `stat_daño` es el atributo que escala el daño de la clase (lo
## fija data/clases.json: guerrero STR, arquero/daguero DEX, mago/clérigo
## INT). Las skills ya leen `ataque`/`poder` (Formulas.damage), así que
## escalan solas con el stat principal; las curas escalan con `poder`.
##
## Los coeficientes lineales viven en DERIVACION (datos, no constantes regadas);
## los topes y bases especiales, en consts con nombre.

enum ModKind { PLANO, PORCENTUAL }

const SAVE_VERSION: int = 2

## Atributos base válidos (fuente única de nombres).
const STATS_BASE: Array[String] = ["fuerza", "aguante", "destreza", "inteligencia"]

## Nombres de stats derivados (fuente única; también los aceptan add_mod/get_stat).
const STATS_DERIVADOS: Array[String] = [
	"vida_max", "mana_max", "ataque", "poder", "defensa",
	"crit_prob", "crit_dmg", "vel_ataque", "vel_mov",
]

## Coeficientes lineales por stat: {"base": b, "<atributo>": coef, ...}.
## Lo que no está aquí (crítico, vel. de ataque, daño) se calcula aparte.
const DERIVACION: Dictionary = {
	"vida_max": {"base": 100.0, "fuerza": 20.0, "aguante": 15.0},
	"mana_max": {"base": 50.0, "inteligencia": 15.0},
	"ataque": {"base": 5.0},
	"poder": {"base": 5.0},
	"defensa": {"base": 0.0, "fuerza": 0.5, "aguante": 1.0},
	"vel_mov": {"base": 6.0},
}

## Fase 42: cuánto daño da 1 punto del stat PRINCIPAL de la clase.
## Fuerza pega más fuerte que finesse (DEX) e inteligencia sube más el
## canal mágico. Se puede tocar aquí para rebalancear todas las clases.
const COEF_ATAQUE_POR_STAT: Dictionary = {
	"fuerza": 2.0, "aguante": 1.0, "destreza": 1.75, "inteligencia": 2.0,
}
const COEF_PODER_POR_STAT: Dictionary = {
	"fuerza": 2.0, "aguante": 1.0, "destreza": 1.75, "inteligencia": 2.5,
}

const CRIT_PROB_BASE: float = 0.05
const CRIT_PROB_POR_DESTREZA: float = 0.004
const CRIT_PROB_MAX: float = 0.60
const CRIT_DMG_BASE: float = 1.50
const CRIT_DMG_POR_DESTREZA: float = 0.010
const VEL_ATAQUE_BASE: float = 1.0
const VEL_ATAQUE_POR_DESTREZA: float = 0.008
const VEL_ATAQUE_MAX: float = 2.0

# --- Atributos base (los escribe el dueño del bloque; luego llama a recalc) ---
# Fase 34: STR/STA/DEX/INT. Sin agilidad.
var fuerza: float = 0.0
var aguante: float = 0.0
var destreza: float = 0.0
var inteligencia: float = 0.0
## Fase 42: atributo que escala `ataque` y `poder` (lo fija la clase desde
## data/clases.json; default fuerza para enemigos y stats genéricos).
var stat_daño: String = "fuerza"

# --- Derivados (SOLO los escribe recalc(); el resto del código los LEE) ---
var vida_max: float = 0.0
var mana_max: float = 0.0
var ataque: float = 0.0
var poder: float = 0.0
var defensa: float = 0.0
var crit_prob: float = 0.0
var crit_dmg: float = 0.0
var vel_ataque: float = 0.0
var vel_mov: float = 0.0

## Modificadores por fuente: id -> {"stat": String, "kind": int, "value": float}.
var _mods: Dictionary = {}
## Snapshot de derivados antes de aplicar modificadores.
var _base: Dictionary = {}


## Orden FlyFF: STR, STA, DEX, INT (fase 34).
func _init(p_fuerza: float = 0.0, p_aguante: float = 0.0, p_destreza: float = 0.0, p_inteligencia: float = 0.0) -> void:
	fuerza = p_fuerza
	aguante = p_aguante
	destreza = p_destreza
	inteligencia = p_inteligencia
	recalc()


## Cambia un atributo base y recalcula. nombre: fuerza|aguante|destreza|inteligencia.
func set_base(nombre: String, valor: float) -> void:
	match nombre:
		"fuerza":
			fuerza = valor
		"aguante":
			aguante = valor
		"destreza":
			destreza = valor
		"inteligencia":
			inteligencia = valor
		_:
			push_warning("[StatBlock] atributo base desconocido: %s" % nombre)
			return
	recalc()


## Fase 42: fija el atributo principal de daño (fuerza|aguante|destreza|
## inteligencia) y recalcula. Nombre inválido → warning, no cambia nada.
func set_stat_daño(nombre: String) -> bool:
	if not STATS_BASE.has(nombre):
		push_warning("[StatBlock] stat principal de daño desconocido: %s" % nombre)
		return false
	stat_daño = nombre
	recalc()
	return true


## Valor de un atributo base por nombre ("" o inválido → 0.0).
func valor_de(nombre: String) -> float:
	match nombre:
		"fuerza":
			return fuerza
		"aguante":
			return aguante
		"destreza":
			return destreza
		"inteligencia":
			return inteligencia
	return 0.0


## Etiqueta corta del stat principal para la UI ("Fuerza", "Destreza"...).
func stat_daño_etiqueta() -> String:
	match stat_daño:
		"fuerza":
			return "Fuerza"
		"aguante":
			return "Aguante"
		"destreza":
			return "Destreza"
		"inteligencia":
			return "Inteligencia"
	return ""


## Añade (o reemplaza) un modificador identificado por su fuente.
## kind: ModKind.PLANO suma directo; ModKind.PORCENTUAL multiplica (0.10 = +10%).
## Orden de aplicación: final = (base + suma_planos) * (1 + suma_porcentuales).
func add_mod(mod_id: String, stat: String, kind: int, valor: float) -> void:
	if not STATS_DERIVADOS.has(stat):
		push_warning("[StatBlock] stat derivado desconocido: %s" % stat)
		return
	_mods[mod_id] = {"stat": stat, "kind": kind, "value": valor}
	_aplicar_mods()


func remove_mod(mod_id: String) -> void:
	if _mods.erase(mod_id):
		_aplicar_mods()


func has_mod(mod_id: String) -> bool:
	return _mods.has(mod_id)


func clear_mods() -> void:
	_mods.clear()
	_aplicar_mods()


## Lectura genérica de un derivado (la UI usa esta o las vars tipadas).
func get_stat(nombre: String) -> float:
	if not STATS_DERIVADOS.has(nombre):
		push_warning("[StatBlock] stat desconocido: %s" % nombre)
		return 0.0
	return float(get(nombre))


## Recalcula derivados desde los atributos base y reaplica modificadores.
func recalc() -> void:
	for nombre in STATS_DERIVADOS:
		_base[nombre] = _derivar_lineal(nombre)
	var cp: float = clampf(CRIT_PROB_BASE + destreza * CRIT_PROB_POR_DESTREZA, 0.0, CRIT_PROB_MAX)
	_base["crit_prob"] = cp
	var cd: float = CRIT_DMG_BASE + destreza * CRIT_DMG_POR_DESTREZA
	_base["crit_dmg"] = cd
	var va: float = clampf(VEL_ATAQUE_BASE + destreza * VEL_ATAQUE_POR_DESTREZA, 0.0, VEL_ATAQUE_MAX)
	_base["vel_ataque"] = va
	_aplicar_mods()


## Derivación lineal desde la tabla DERIVACION. Sin entrada → 0.0.
## Fase 42: `ataque` y `poder` escalan con el stat principal de la clase.
func _derivar_lineal(nombre: String) -> float:
	var coefs: Dictionary = DERIVACION.get(nombre, {})
	if coefs.is_empty():
		return 0.0
	var total: float = float(coefs.get("base", 0.0))
	if nombre == "ataque":
		total += float(COEF_ATAQUE_POR_STAT.get(stat_daño, 0.0)) * valor_de(stat_daño)
		return total
	if nombre == "poder":
		total += float(COEF_PODER_POR_STAT.get(stat_daño, 0.0)) * valor_de(stat_daño)
		return total
	total += float(coefs.get("fuerza", 0.0)) * fuerza
	total += float(coefs.get("aguante", 0.0)) * aguante
	total += float(coefs.get("destreza", 0.0)) * destreza
	total += float(coefs.get("inteligencia", 0.0)) * inteligencia
	return total


## Aplica los modificadores sobre el snapshot base y escribe las vars públicas.
func _aplicar_mods() -> void:
	for nombre in STATS_DERIVADOS:
		var base: float = float(_base.get(nombre, 0.0))
		var plano: float = 0.0
		var pct: float = 0.0
		for mod_id in _mods:
			var m: Dictionary = _mods[mod_id]
			if str(m.get("stat", "")) != nombre:
				continue
			if int(m.get("kind", 0)) == ModKind.PLANO:
				plano += float(m.get("value", 0.0))
			else:
				pct += float(m.get("value", 0.0))
		set(nombre, (base + plano) * (1.0 + pct))


## Serialización versionada (la usará el save/load de la Fase 4).
func to_dict() -> Dictionary:
	var mods: Array = []
	for mod_id in _mods:
		var m: Dictionary = _mods[mod_id]
		mods.append({
			"id": str(mod_id),
			"stat": str(m.get("stat", "")),
			"kind": int(m.get("kind", 0)),
			"value": float(m.get("value", 0.0)),
		})
	return {
		"version": SAVE_VERSION,
		"base": {
			"fuerza": fuerza,
			"aguante": aguante,
			"destreza": destreza,
			"inteligencia": inteligencia,
		},
		"stat_daño": stat_daño,
		"mods": mods,
	}


static func from_dict(d: Dictionary) -> StatBlock:
	var b: Dictionary = d.get("base", {})
	var sb: StatBlock = StatBlock.new(
		float(b.get("fuerza", 0.0)),
		float(b.get("aguante", 0.0)),
		float(b.get("destreza", 0.0)),
		float(b.get("inteligencia", 0.0))
	)
	# Fase 42: saves v1 (sin stat_daño) → "fuerza" (comportamiento previo).
	var sd: String = str(d.get("stat_daño", "fuerza"))
	sb.set_stat_daño(sd if STATS_BASE.has(sd) else "fuerza")
	var mods: Array = d.get("mods", [])
	for m in mods:
		var md: Dictionary = m
		sb.add_mod(str(md.get("id", "")), str(md.get("stat", "")), int(md.get("kind", 0)), float(md.get("value", 0.0)))
	return sb
