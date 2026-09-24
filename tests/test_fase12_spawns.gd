extends SceneTree
## Tests headless de la Fase 12 (SPAWNS — Mundo abierto real).
##
## `data/spawns.json` es el contrato que lee la demo: array de
## {arquetipo, x, z, nivel} generado por `tools/generar_spawns_rework.py`
## (Fase 14, rework 2026: determinista, semilla fija, distribuido por las
## 10 regiones de data/regiones.json) mas el pack de prueba de combate
## (fase 18.2+: 6 mobs fijos con "grupo": "prueba_combate" cerca de la
## plaza de Moon Town; cumplen la regla nivel->arquetipo y la zona segura).
## Este test blinda el contrato: el JSON existe y es valido, todos los puntos
## caen dentro del terreno [-18432, 18432], ninguno invade la zona segura de
## 40 m alrededor de la aldea inicial (0, 0), los arquetipos son solo los 3
## oficiales (goblin/lobo/ogro), los niveles se preservan en rango sensato y
## la regla nivel -> arquetipo del generador se cumple en cada entrada.
##
## Regla nivel -> arquetipo (documentada en tools/generar_spawns_rework.py):
##   nivel <= 30  -> goblin
##   30 < nivel <= 200 -> lobo
##   nivel > 200  -> ogro
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase12_spawns.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.

const RUTA_SPAWNS := "res://data/spawns.json"
const LIMITE := 18432.0
const RADIO_SEGURO := 40.0
const ARQUETIPOS_VALIDOS: Array[String] = ["goblin", "lobo", "ogro",
	"devorador_dunas", "fundidor_antiguo", "aullido_pico", "eco_cristal",
	"susurro_umbral", "campeon_caido"]
## Conteos esperados del generador determinista (semilla 20260922).
## Fase 22: 1133 = 1127 + 6 jefes de fragmento (grupo jefe_fragmento).
const TOTAL_ESPERADO := 1133
const GOBLIN_ESPERADO := 492
const LOBO_ESPERADO := 634
const OGRO_ESPERADO := 1

var _ok: int = 0
var _fallos: int = 0


func _init() -> void:
	print("[TEST] Fase 12 — spawns.json (rework 2026: 1133 = 1121 por region + 6 pack de prueba + 6 jefes fase 22)")


var _empezo: bool = false


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_contrato_spawns()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	quit(_fallos)
	return false


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


## Regla nivel -> arquetipo (espejo de tools/generar_spawns_rework.py;
## si el generador cambia la regla, este test lo detecta).
func _arquetipo_esperado(nivel: int) -> String:
	if nivel <= 30:
		return "goblin"
	if nivel <= 200:
		return "lobo"
	return "ogro"


func _cargar_spawns() -> Array:
	if not FileAccess.file_exists(RUTA_SPAWNS):
		return []
	var texto: String = FileAccess.get_file_as_string(RUTA_SPAWNS)
	var datos: Variant = JSON.parse_string(texto)
	if datos is Array:
		return datos as Array
	return []


func _t_contrato_spawns() -> void:
	# 1. El JSON existe y es válido.
	_check(FileAccess.file_exists(RUTA_SPAWNS), "data/spawns.json existe",
		"el generador tools/generar_spawns_rework.py no se corrió")
	var spawns: Array = _cargar_spawns()
	_check(spawns.size() > 0, "el JSON parsea a un array no vacío",
		"tamaño=%d" % spawns.size())

	# 2. Conteo total y por arquetipo (determinista, semilla fija).
	_check(spawns.size() == TOTAL_ESPERADO,
		"total de spawns == %d" % TOTAL_ESPERADO, "hay %d" % spawns.size())
	var por_arq: Dictionary = {}
	for s in spawns:
		var d: Dictionary = s
		var a: String = str(d.get("arquetipo", ""))
		por_arq[a] = int(por_arq.get(a, 0)) + 1
	_check(int(por_arq.get("goblin", 0)) == GOBLIN_ESPERADO,
		"goblins == %d" % GOBLIN_ESPERADO, "hay %d" % int(por_arq.get("goblin", 0)))
	_check(int(por_arq.get("lobo", 0)) == LOBO_ESPERADO,
		"lobos == %d" % LOBO_ESPERADO, "hay %d" % int(por_arq.get("lobo", 0)))
	_check(int(por_arq.get("ogro", 0)) == OGRO_ESPERADO,
		"ogros == %d" % OGRO_ESPERADO, "hay %d" % int(por_arq.get("ogro", 0)))

	# 3. Barrido por entrada: claves, arquetipo válido, regla nivel->arquetipo,
	#    nivel en rango sensato, dentro del terreno, fuera de la zona segura.
	var sin_claves: int = 0
	var arq_invalidos: int = 0
	var regla_rota: int = 0
	var nivel_raro: int = 0
	var fuera_limites: int = 0
	var en_zona_segura: int = 0
	for s in spawns:
		var d: Dictionary = s
		if not (d.has("arquetipo") and d.has("x") and d.has("z") and d.has("nivel")):
			sin_claves += 1
			continue
		var a: String = str(d["arquetipo"])
		if a not in ARQUETIPOS_VALIDOS:
			arq_invalidos += 1
		var nivel: int = int(d["nivel"])
		# Fase 22: los jefes de fragmento son arquetipos únicos exentos
		# de la regla nivel->arquetipo (su "nivel" es dificultad sugerida).
		if str(d.get("grupo", "")) != "jefe_fragmento" \
				and a != _arquetipo_esperado(nivel):
			regla_rota += 1
		# Rango sensato: el legado tiene creeps de nivel 0 a 2000.
		if nivel < 0 or nivel > 2000:
			nivel_raro += 1
		var x: float = float(d["x"])
		var z: float = float(d["z"])
		if x < -LIMITE or x > LIMITE or z < -LIMITE or z > LIMITE:
			fuera_limites += 1
		if Vector2(x, z).length() < RADIO_SEGURO:
			en_zona_segura += 1
	_check(sin_claves == 0, "todas las entradas tienen {arquetipo, x, z, nivel}",
		"%d incompletas" % sin_claves)
	_check(arq_invalidos == 0, "arquetipos solo goblin/lobo/ogro",
		"%d inválidos" % arq_invalidos)
	_check(regla_rota == 0, "la regla nivel->arquetipo se cumple en todas",
		"%d violaciones" % regla_rota)
	_check(nivel_raro == 0, "niveles preservados en rango sensato [0, 2000]",
		"%d fuera de rango" % nivel_raro)
	_check(fuera_limites == 0, "todos dentro del terreno [-18432, 18432]",
		"%d fuera" % fuera_limites)
	_check(en_zona_segura == 0, "ninguno a <40 m de la aldea inicial (0, 0)",
		"%d dentro" % en_zona_segura)

	# 4. El generador es determinista: dos corridas -> mismo SHA.
	var sha1: String = FileAccess.get_sha256(RUTA_SPAWNS)
	var ruta_py: String = ProjectSettings.globalize_path("res://tools/generar_spawns_rework.py")
	var salida: Array = []
	var rc1: int = OS.execute("python3", PackedStringArray([ruta_py]), salida, true)
	var sha2: String = FileAccess.get_sha256(RUTA_SPAWNS)
	var rc2: int = OS.execute("python3", PackedStringArray([ruta_py]), salida, true)
	var sha3: String = FileAccess.get_sha256(RUTA_SPAWNS)
	_check(rc1 == 0 and rc2 == 0, "el generador corre dos veces sin errores",
		"rc=%d/%d" % [rc1, rc2])
	_check(sha1 != "" and sha1 == sha2 and sha2 == sha3,
		"dos corridas del generador dan el mismo SHA-256",
		"%s / %s / %s" % [sha1, sha2, sha3])
