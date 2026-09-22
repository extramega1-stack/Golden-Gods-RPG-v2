extends SceneTree
## Tests headless de la Fase 12 (INTEGRACIÓN — Mundo abierto real).
##
## Blinda que las cuatro piezas encajan: cada spawn de data/spawns.json cae
## en una región de data/regiones.json, el Terreno cubre la escala real
## (36.864 u) y la demo fase12 referencia los nodos/sistemas nuevos.
## La lógica fina de cada pieza la cubren sus tests dedicados.
##
## Cómo correrlo:
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase12_integracion.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.

var _ok: int = 0
var _fallos: int = 0


func _init() -> void:
	print("[TEST] Fase 12 — integración del mundo abierto")


func _check(cond: bool, nombre: String) -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		push_error("[FALLO] " + nombre)


func _process(_delta: float) -> bool:
	# El árbol aparece en el primer _process (lección 13b).
	_run()
	print("[TEST] integración: %d ok, %d fallos" % [_ok, _fallos])
	if _fallos == 0:
		print("TODO VERDE")
	quit(_fallos)
	return true


func _run() -> void:
	# 1. Regiones cargan y cada spawn cae en alguna.
	var db := RegionDB.new()
	_check(db.cargar(), "RegionDB.cargar()")
	var texto: String = FileAccess.get_file_as_string("res://data/spawns.json")
	_check(not texto.is_empty(), "spawns.json legible")
	var crudo: Variant = JSON.parse_string(texto)
	_check(crudo is Array, "spawns.json es array")
	var spawns: Array = crudo as Array
	_check(spawns.size() == 1121, "1121 spawns (esperado %d, hay %d)" % [1121, spawns.size()])
	var sin_region: int = 0
	var fuera: int = 0
	var terr := Terreno.new() # dentro() es matemática pura; no necesita el bin
	for s in spawns:
		var sd: Dictionary = s
		var x: float = float(sd.get("x", 0.0))
		var z: float = float(sd.get("z", 0.0))
		if not terr.dentro(x, z):
			fuera += 1
			continue
		if (db.region_en(x, z) as Dictionary).is_empty():
			sin_region += 1
	_check(fuera == 0, "ningún spawn fuera del terreno (fuera=%d)" % fuera)
	_check(sin_region == 0, "todo spawn cae en una región (sin región=%d)" % sin_region)
	# 2. La aldea inicial está en Piedraceniza.
	var aldea: Dictionary = db.region_en(0.0, 0.0)
	_check(str(aldea.get("id", "")) == "piedraceniza",
		"la aldea (0,0) está en Piedraceniza (es %s)" % str(aldea.get("id", "?")))
	# 3. Terreno: escala real del proyecto.
	_check(Terreno.TAMANO == 36864.0, "Terreno.TAMANO == 36864")
	_check(Terreno.PASO == 128.0, "Terreno.PASO == 128")
	# 4. La demo fase12 referencia los sistemas nuevos (contrato de escena).
	var tscn: String = FileAccess.get_file_as_string("res://scenes/demo/fase12_demo.tscn")
	_check(tscn.find("fase12_demo.gd") >= 0, "tscn usa fase12_demo.gd")
	_check(tscn.find("scripts/mundo/terreno.gd") >= 0, "tscn incluye Terreno")
	_check(tscn.find("scripts/mundo/ciclo_dia.gd") >= 0, "tscn incluye CicloDia")
	_check(tscn.find("scripts/mundo/vigia_region.gd") >= 0, "tscn incluye VigiaRegion")
	_check(tscn.find("scripts/ui/banner_region.gd") >= 0, "tscn incluye BannerRegion")
	_check(tscn.find("scripts/mundo/antorcha.gd") >= 0, "tscn incluye Antorchas")
	_check(tscn.find("Goblin1") < 0, "tscn sin enemigos fijos (los da spawns.json)")
	_check(tscn.find("far = 40000.0") >= 0, "cámara con far 40000 para el mundo")
	# 5. El título arranca la demo del mundo abierto.
	var titulo: String = FileAccess.get_file_as_string("res://scripts/ui/pantalla_titulo.gd")
	_check(titulo.find("fase12_demo.tscn") >= 0, "el título abre fase12_demo")
