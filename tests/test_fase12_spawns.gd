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
## Fase 43: el arquetipo lo decide la REGIÓN (no el nivel) — 10 mobs
## regionales nuevos + los 3WAS de siempre + 6 jefes de fragmento.
const ARQUETIPOS_VALIDOS: Array[String] = ["goblin", "lobo", "ogro",
	"escorpion_dunas", "slog_volcan", "golem_ascua", "yeti_hielo",
	"arana_sombra", "espectro_velo", "carnicoro_rio", "mimo_hoja",
	"centinela_oro", "sombra_vacia",
	# Fase 62: el Titán Acecho. No es de la fauna de una región (es único y
	# acecha), por eso va exento de la regla región→arquetipo, igual que los
	# jefes de fragmento.
	"titan_acecho",
	"devorador_dunas", "fundidor_antiguo", "aullido_pico", "eco_cristal",
	"susurro_umbral", "campeon_caido"]
## Conteos esperados del generador determinista (semilla 20260922).
## 1133 = 1113 trash + 6 jefes de fragmento (grupo jefe_fragmento)
## + 6 de prueba (grupo prueba_combate) + 8 titanes (grupo titan, fase 62).
## Fase 43: 795 spawns reasignados a la fauna de su región.
const TOTAL_ESPERADO := 1133
const GOBLIN_ESPERADO := 49
const LOBO_ESPERADO := 290  # fase 62: 8 cupos se fueron a los titanes
const OGRO_ESPERADO := 1

var _ok: int = 0
var _fallos: int = 0
## Fase 43: la regla del spawn es REGIÓN → arquetipo (no nivel → arquetipo).
var _region_db: RegionDB = null


func _init() -> void:
	print("[TEST] Fase 12 — spawns.json (rework 2026: 1133 = 1121 por region + 6 pack de prueba + 6 jefes fase 22)")


var _empezo: bool = false


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_region_db = RegionDB.new()
	_region_db.cargar()
	_check(_region_db.esta_cargado(), "regiones cargadas para el chequeo región→arquetipo")
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
	# Fase 43: cada region aporta su mob de identidad (y no solo goblin/lobo).
	var regionales: int = 0
	for a in por_arq:
		if a in ["goblin", "lobo", "ogro", "devorador_dunas", "fundidor_antiguo",
				"aullido_pico", "eco_cristal", "susurro_umbral", "campeon_caido",
				# Fase 62: el titán tampoco es un mob regional.
				"titan_acecho"]:
			continue
		if int(por_arq.get(a, 0)) > 0:
			regionales += 1
	_check(regionales == 10, "los 10 mobs regionales aparecen en el mundo",
		"%d presentes" % regionales)

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
		# Fase 43: la regla es REGIÓN → arquetipo. Cada spawn trash debe
		# tener un arquetipo de la fauna de la región donde está (los
		# jefes de fragmento quedan exentos: son únicos por diseño).
		var grupo: String = str(d.get("grupo", ""))
		# Fase 62: el grupo "titan" está exento, igual que "jefe_fragmento" y
		# "prueba_combate": son arquetipos únicos, no fauna de la región.
		if grupo != "jefe_fragmento" and grupo != "prueba_combate" and grupo != "titan":
			var reg: Dictionary = _region_db.region_en(float(d["x"]), float(d["z"]))
			var fauna: Array = reg.get("mobs", [])
			if fauna.is_empty() or a not in fauna:
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
	_check(arq_invalidos == 0, "arquetipos conocidos (19: 13 trash + 6 jefes)",
		"%d inválidos" % arq_invalidos)
	_check(regla_rota == 0, "el arquetipo pertenece a la fauna de su región",
		"%d violaciones" % regla_rota)
	_check(nivel_raro == 0, "niveles preservados en rango sensato [0, 2000]",
		"%d fuera de rango" % nivel_raro)
	_check(fuera_limites == 0, "todos dentro del terreno [-18432, 18432]",
		"%d fuera" % fuera_limites)
	_check(en_zona_segura == 0, "ninguno a <40 m de la aldea inicial (0, 0)",
		"%d dentro" % en_zona_segura)

	# 4. El generador es determinista: dos corridas -> mismo SHA.
	#    Fase 50.4: se ejecuta sobre una COPIA en user://. Antes escribía
	#    sobre data/spawns.json real: si el generador fallaba a mitad, el
	#    test dejaba 1133 entradas corruptas en el repo. Además se compara
	#    contra el SHA del archivo real, que debe coincidir con el generado.
	var sha_repo: String = FileAccess.get_sha256(RUTA_SPAWNS)
	var ruta_py: String = ProjectSettings.globalize_path("res://tools/generar_spawns_rework.py")
	# OJO: `user://` es una ruta virtual de Godot; hay que globalizarla antes
	# de pasársela a un proceso de Python, que no la entiende.
	var prueba: String = ProjectSettings.globalize_path("user://spawns_prueba.json")
	var salida: Array = []
	var rc1: int = OS.execute("python3", PackedStringArray([ruta_py, prueba]), salida, true)
	var sha1: String = FileAccess.get_sha256(prueba)
	var rc2: int = OS.execute("python3", PackedStringArray([ruta_py, prueba]), salida, true)
	var sha2: String = FileAccess.get_sha256(prueba)
	_check(rc1 == 0 and rc2 == 0, "el generador corre dos veces sin errores",
		"rc=%d/%d" % [rc1, rc2])
	_check(sha1 != "" and sha1 == sha2,
		"dos corridas del generador dan el mismo SHA-256",
		"%s / %s" % [sha1, sha2])
	_check(sha1 == sha_repo,
		"el generador reproduce el spawns.json del repo byte a byte",
		"repo=%s generado=%s" % [sha_repo, sha1])
	_check(FileAccess.get_sha256(RUTA_SPAWNS) == sha_repo,
		"el test NO dejó data/spawns.json modificado", "")
	DirAccess.remove_absolute(prueba)
