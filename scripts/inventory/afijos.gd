class_name Afijos
extends RefCounted
## Bloque 68: los afijos del loot. Un item ya no es "espada +10" fijo.
##
## POR QUÉ EXISTE: la auditoría encontró que los 77 items del catálogo eran
## TODOS fijos: el mismo yunque da siempre los mismos +4 de cobre. Eso no es
## una build, es un disfraz. Con afijos, dos yunquees del mismo nivel pueden
## ser distintos, y la decisióninteresting es cuáles buscar.
##
## - DATA-DRIVEN: los afijos posibles viven en `data/afijos.json` (stat, rango
##   por rareza, nombre), no en el código. Añadir un afijo es una línea.
## - DETERMINISTA POR SEMILLA: el mismo loot con la misma semilla da el mismo
##   item. Sin eso no se puede testear ni guardar/reproducir un mundo.
## - RAREZA ESCALA: un afijo raro no es "el mismo +X", es un número mayor. Por
##   eso el valor depende de la rareza, no del stat.
##
## Las rarezas siguen la convención de la 33 (común, pocion, elite, jefe...) y
## se amplían aquí a una escala 1–5 para el loot generated.

const RUTA: String = "res://data/afijos.json"
## Escala de rareza 1..5. El valor del afijo crece con ella.
const RAREZAS: Array[String] = ["Común", "Poco común", "Rara", "Épica", "Legendaria"]
## Cuántos afijos puede llevar un item por rareza (1..5).
const AFIXOS_POR_RAREZA: Array[int] = [1, 1, 2, 3, 4]
## Multiplicador de valor por rareza. Legendario ~5x un afijo común.
const VALOR_POR_RAREZA: Array[float] = [1.0, 1.4, 2.0, 3.0, 5.0]
## Los stats que un afijo puede tocar. Deliberadamente NO toca vida/mana
## directos: el stat block los deriva de los 4 (fase 34), así que un afijo de
## "vida" sería un atajo que rompe la derivación.
const STATS: Array[String] = ["fuerza", "aguante", "destreza", "inteligencia"]

static var _datos: Dictionary = {}


static func cargar() -> void:
	if not _datos.is_empty():
		return
	var texto: String = FileAccess.get_file_as_string(RUTA)
	var d: Variant = JSON.parse_string(texto)
	if d is Dictionary:
		_datos = (d as Dictionary).get("afijos", {})


## Genera UN afijo del `stat` pedido, para un item de `rareza` (1..5).
## `semilla` hace que sea determinista.
static func generar_afijo(stat: String, rareza: int, semilla: int) -> Dictionary:
	cargar()
	var r: int = clampi(rareza - 1, 0, RAREZAS.size() - 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	# El stat se elige si no se pide uno concreto.
	var st: String = stat
	if st == "" or not STATS.has(st):
		st = str(STATS[rng.randi() % STATS.size()])
	var base: float = 1.0
	if _datos.has(st):
		base = float((_datos[st] as Dictionary).get("base", 1.0))
	# El valor escala con la rareza y tiene un poco de variación (semilla).
	var mult: float = VALOR_POR_RAREZA[r]
	var variacion: float = rng.randf_range(0.85, 1.15)
	return {
		"stat": st,
		"valor": roundf(base * mult * variacion * 10.0) / 10.0,
		"rareza": r + 1,
		"nombre": _nombre_de(st, r),
	}


## Genera N afijos para un item. No se repiten (dos "Fuerza +3" en el mismo
## item es ruido, no una build).
static func generar_varios(stat: String, rareza: int, rng_semilla: int,
		nivel: int) -> Array:
	var r: int = clampi(rareza - 1, 0, RAREZAS.size() - 1)
	var n: int = AFIXOS_POR_RAREZA[r]
	var out: Array = []
	var usados: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_semilla
	for i in range(n):
		var st: String = ""
		# El stat pedido (si lo hay) va primero; los siguientes se eligen de
		# los que queden libres. La version anterior exigia "fuerza" y luego
		# descartaba los repetidos, asi que un item de rareza epica con 3
		# afijos devolvia UNO solo.
		if i == 0 and stat != "" and STATS.has(stat):
			st = stat
		else:
			var intentos: int = 0
			while intentos < 12:
				var cand: String = str(STATS[rng.randi() % STATS.size()])
				if not usados.has(cand):
					st = cand
					break
				intentos += 1
		if st == "" or usados.has(st):
			break
		usados.append(st)
		var af: Dictionary = generar_afijo(st, rareza, rng_semilla + i * 7)
		# El nivel sube un poco el valor: dos afijos del mismo stat en niveles
		# distintos se distinguen.
		af["valor"] = roundf(float(af["valor"]) * (1.0 + float(nivel) * 0.02) * 10.0) / 10.0
		out.append(af)
	return out


static func _nombre_de(stat: String, r: int) -> String:
	var base: String = {
		"fuerza": "Feroz", "aguante": "Resistente",
		"destreza": "Ágil", "inteligencia": "Sagaz",
	}.get(stat, stat)
	return "%s %s" % [base, RAREZAS[r]]


## El texto que se ve en el inventario: "Fuerza +3,2 (Rara)".
static func texto_de(afijo: Dictionary) -> String:
	if afijo.is_empty():
		return ""
	var r: int = clampi(int(afijo.get("rareza", 1)) - 1, 0, RAREZAS.size() - 1)
	# El NOMBRE primero cuando existe. "Fuerza +3.2 (Poco comun)" dice cuanto sube
	# el stat, pero no dice que objeto es: en un ARPG el nombre del afijo es lo que
	# hace que un item sea memorable y lo que el jugador compara de un vistazo
	# ("el de Filo sangrante" y no "el que da +3.2 de fuerza"). El efecto sigue
	# estando, que es lo que hace falta para decidir.
	var efecto := "%s +%.1f (%s)" % [
		str(afijo.get("stat", "?")).capitalize(),
		float(afijo.get("valor", 0.0)),
		RAREZAS[r],
	]
	var nombre: String = str(afijo.get("nombre", "")).strip_edges()
	if nombre == "":
		return efecto
	return "%s \u2014 %s" % [nombre, efecto]


## Compara dos afijos para el tooltip de comparación (▲ mejor, ▼ peor). Lo
## llama el panel de inventario del bloque 68.
static func comparar(a: Dictionary, b: Dictionary) -> int:
	if b.is_empty():
		return 1
	if a.is_empty():
		return -1
	if str(a.get("stat", "")) != str(b.get("stat", "")):
		return 0  # distintos stats: no se comparan
	var d: float = float(a.get("valor", 0.0)) - float(b.get("valor", 0.0))
	return 1 if d > 0.01 else (-1 if d < -0.01 else 0)
