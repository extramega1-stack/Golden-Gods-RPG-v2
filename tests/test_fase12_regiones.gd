extends SceneTree
## Tests headless de la Fase 12 (mundo abierto: regiones data-driven).
##
## (a) RegionDB: cargar() -> true, 10 regiones, ids únicos en orden, campos
##     completos, tintes "#rrggbb" válidos, bandas de nivel coherentes,
##     cargar() idempotente.
## (b) Cobertura total por muestreo: 625 puntos de todo el mapa caen en
##     alguna región (incluye las 4 esquinas del mundo).
## (c) Sin solapes por muestreo: cada punto cae en exactamente 1 región.
## (d) Moon Town contiene al (0,0); region_en en bordes compartidos.
## (e) por_id: existente/desconocido; fuera del mapa -> {}.
## (f) VigiaRegion: emite `descubierta` una sola vez por región por sesión;
##     region_actual(); sin jugador/db no revienta; reiniciar_descubrimientos.
## (g) BannerRegion: arranca oculto, mouse_filter IGNORE (él y sus hijos);
##     mostrar() abre con el texto correcto; fundido y auto-ocultado ~3.5 s.
##
## Cómo correrlos (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase12_regiones.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

## Rework 2026 (Fase 14): ids Liberty remapeados a la geografia nueva.
const IDS_ESPERADOS: Array[String] = [
	"moon_town", "tierras_francas", "ceniza_forja", "tierras_trueno",
	"bosque_hondo", "umbral_ladon", "abismo_lloroso", "costa_lamento",
	"corona_quebrada", "velo",
]

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []
var _descubiertas: Array = []


func _init() -> void:
	print("[TEST] Fase 12 — regiones: db data-driven, vigia, banner")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b): el jugador
## de mentira necesita estar en el árbol para que global_position valga.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	var db: RegionDB = RegionDB.new()
	_t_db(db)
	_t_cobertura(db)
	_t_solapes(db)
	_t_bordes(db)
	_t_por_id(db)
	_t_vigia(db)
	_t_banner()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
	return true


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


func _al_descubierta(region: Dictionary) -> void:
	_descubiertas.append(str(region.get("id", "")))


func _es_hex6(s: String) -> bool:
	if s.length() != 7 or not s.begins_with("#"):
		return false
	for i in range(1, 7):
		if not "0123456789abcdefABCDEF".contains(s.substr(i, 1)):
			return false
	return true


func _t_db(db: RegionDB) -> void:
	_check(db.cargar(), "db: cargar() devuelve true")
	_check(db.esta_cargado(), "db: esta_cargado() tras cargar")
	var todas: Array = db.todas()
	_check(todas.size() == 10, "db: 10 regiones", str(todas.size()))
	var ids: Array = []
	for r in todas:
		ids.append(str((r as Dictionary).get("id", "")))
	var ids_t: Array[String] = []
	for i in ids:
		ids_t.append(str(i))
	_check(ids_t == IDS_ESPERADOS, "db: 10 ids únicos en orden",
		str(ids_t))
	var campos: Array[String] = ["id", "nombre", "x0", "z0", "x1", "z1",
		"nivel_min", "nivel_max", "tinte", "descripcion"]
	var sin_campos: Array = []
	var tintes_malos: Array = []
	var niveles_malos: Array = []
	for r in todas:
		var d: Dictionary = r
		for c in campos:
			if not d.has(c):
				sin_campos.append("%s.%s" % [str(d.get("id", "?")), c])
		if not _es_hex6(str(d.get("tinte", ""))):
			tintes_malos.append(str(d.get("id", "?")))
		var nmin: int = int(d.get("nivel_min", 0))
		var nmax: int = int(d.get("nivel_max", 0))
		if nmin < 1 or nmax < nmin:
			niveles_malos.append(str(d.get("id", "?")))
	_check(sin_campos.is_empty(), "db: todas con los 10 campos",
		str(sin_campos))
	_check(tintes_malos.is_empty(), "db: tintes '#rrggbb' válidos",
		str(tintes_malos))
	_check(niveles_malos.is_empty(), "db: 1 <= nivel_min <= nivel_max",
		str(niveles_malos))
	var piedra: Dictionary = db.por_id("moon_town")
	_check(int(piedra.get("nivel_min", -1)) == 1
		and int(piedra.get("nivel_max", -1)) == 5,
		"db: Moon Town banda 1-5")
	var velo: Dictionary = db.por_id("velo")
	_check(int(velo.get("nivel_min", -1)) == 45
		and int(velo.get("nivel_max", -1)) == 70,
		"db: El Velo banda 45-70 (la más dura)")
	_check(db.cargar(), "db: cargar() idempotente (segunda vez true)")
	_check(db.todas().size() == 10, "db: sigue habiendo 10 tras recargar")


func _t_cobertura(db: RegionDB) -> void:
	var huecos: Array = []
	for xi in range(-18432, 18433, 1536):
		for zi in range(-18432, 18433, 1536):
			var r: Dictionary = db.region_en(float(xi), float(zi))
			if r.is_empty():
				huecos.append("(%d,%d)" % [xi, zi])
	_check(huecos.is_empty(), "db: cobertura total por muestreo (625 pts)",
		"huecos: " + str(huecos.slice(0, 5)))


func _cuantas_contienen(db: RegionDB, x: float, z: float) -> int:
	var n: int = 0
	for r in db.todas():
		var d: Dictionary = r
		var x0: float = float(d.get("x0", 0.0))
		var z0: float = float(d.get("z0", 0.0))
		var x1: float = float(d.get("x1", 0.0))
		var z1: float = float(d.get("z1", 0.0))
		var dx: bool = x >= x0 and (x < x1 or (x1 >= 18432.0 and x <= 18432.0))
		var dz: bool = z >= z0 and (z < z1 or (z1 >= 18432.0 and z <= 18432.0))
		if dx and dz:
			n += 1
	return n


func _t_solapes(db: RegionDB) -> void:
	var mal: Array = []
	for xi in range(-18432, 18433, 1536):
		for zi in range(-18432, 18433, 1536):
			var n: int = _cuantas_contienen(db, float(xi), float(zi))
			if n != 1:
				mal.append("(%d,%d)->%d" % [xi, zi, n])
	_check(mal.is_empty(), "db: sin solapes por muestreo (625 pts)",
		"mal: " + str(mal.slice(0, 5)))


func _region_id(db: RegionDB, x: float, z: float) -> String:
	return str(db.region_en(x, z).get("id", "<ninguna>"))


func _t_bordes(db: RegionDB) -> void:
	_check(_region_id(db, 0.0, 0.0) == "moon_town",
		"db: (0,0) en Moon Town")
	_check(_region_id(db, 1500.0, 0.0) == "tierras_francas",
		"db: borde x=1500 -> Tierras Francas (semiabierto)")
	_check(_region_id(db, -1500.0, 0.0) == "moon_town",
		"db: borde x=-1500 -> Moon Town")
	_check(_region_id(db, 0.0, 1500.0) == "bosque_hondo",
		"db: borde z=1500 -> Bosque Hondo (semiabierto)")
	_check(_region_id(db, 0.0, -1500.0) == "moon_town",
		"db: borde z=-1500 -> Moon Town")
	_check(_region_id(db, 6144.0, -2000.0) == "umbral_ladon",
		"db: (6144,-2000) -> Umbral de Ladón (noreste)")
	_check(_region_id(db, -6144.0, -2000.0) == "abismo_lloroso",
		"db: borde x=-6144 norte -> Abismo Lloroso")
	_check(_region_id(db, 18432.0, 18432.0) == "corona_quebrada",
		"db: esquina (18432,18432) incluida -> Corona Quebrada")
	_check(_region_id(db, -18432.0, -18432.0) == "abismo_lloroso",
		"db: esquina (-18432,-18432) -> Abismo Lloroso")
	_check(db.region_en(20000.0, 0.0).is_empty(),
		"db: fuera del mapa (x) -> {}")
	_check(db.region_en(0.0, -20000.0).is_empty(),
		"db: fuera del mapa (z) -> {}")


func _t_por_id(db: RegionDB) -> void:
	_check(str(db.por_id("velo").get("nombre", "")) == "El Velo",
		"db: por_id('velo') nombre")
	_check(int(db.por_id("velo").get("nivel_min", -1)) == 45,
		"db: por_id('velo') nivel_min 45")
	_check(str(db.por_id("moon_town").get("nombre", "")) == "Moon Town",
		"db: por_id('moon_town') nombre")
	_check(db.por_id("inexistente").is_empty(),
		"db: por_id desconocido -> {}")
	var copia: Array = db.todas()
	copia.clear()
	_check(db.todas().size() == 10,
		"db: todas() devuelve copia (mutarla no afecta)")


func _t_vigia(db: RegionDB) -> void:
	var vigia: VigiaRegion = VigiaRegion.new()
	var jugador: Node3D = Node3D.new()
	root.add_child(jugador)
	_basura.append(jugador)
	vigia.jugador = jugador
	vigia.region_db = db
	vigia.descubierta.connect(_al_descubierta)
	_descubiertas.clear()
	_check(vigia.region_actual().is_empty(),
		"vigia: region_actual vacía al inicio")
	vigia._process(0.1)
	_check(_descubiertas.is_empty() and vigia.region_actual().is_empty(),
		"vigia: no sondea antes de 0.5 s")
	jugador.position = Vector3(0.0, 0.0, 0.0)
	vigia._process(0.6)
	_check(_descubiertas == ["moon_town"],
		"vigia: emite descubierta al entrar a Moon Town",
		str(_descubiertas))
	_check(str(vigia.region_actual().get("id", "")) == "moon_town",
		"vigia: region_actual = moon_town")
	vigia._process(0.6)
	vigia._process(0.6)
	vigia._process(0.6)
	_check(_descubiertas == ["moon_town"],
		"vigia: no re-emite en la misma región", str(_descubiertas))
	jugador.position = Vector3(10000.0, 0.0, 100.0)
	vigia._process(0.6)
	_check(_descubiertas == ["moon_town", "tierras_francas"],
		"vigia: emite al entrar a Tierras Francas", str(_descubiertas))
	_check(str(vigia.region_actual().get("id", "")) == "tierras_francas",
		"vigia: region_actual = tierras_francas")
	jugador.position = Vector3(0.0, 0.0, 0.0)
	vigia._process(0.6)
	_check(_descubiertas.size() == 2,
		"vigia: una sola vez por región por sesión", str(_descubiertas))
	vigia.reiniciar_descubrimientos()
	vigia._process(0.6)
	_check(_descubiertas == ["moon_town", "tierras_francas", "moon_town"],
		"vigia: reiniciar_descubrimientos permite re-descubrir",
		str(_descubiertas))
	var sordo: VigiaRegion = VigiaRegion.new()
	sordo.region_db = db
	sordo._process(0.6)
	_check(_descubiertas.size() == 3,
		"vigia: sin jugador no revienta ni emite", str(_descubiertas))
	var ciego: VigiaRegion = VigiaRegion.new()
	ciego.jugador = jugador
	ciego._process(0.6)
	_check(_descubiertas.size() == 3,
		"vigia: sin region_db no revienta ni emite", str(_descubiertas))


func _ignoran_todos(nodo: Node) -> bool:
	if nodo is Control and (nodo as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for h in nodo.get_children():
		if not _ignoran_todos(h):
			return false
	return true


func _t_banner() -> void:
	var banner: BannerRegion = BannerRegion.new()
	_basura.append(banner)
	_check(not banner.visible, "banner: arranca oculto")
	_check(banner.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"banner: mouse_filter IGNORE")
	_check(_ignoran_todos(banner), "banner: hijos también IGNORE")
	banner.mostrar("Moon Town", "Nivel recomendado 1–5")
	_check(banner.visible, "banner: mostrar() lo hace visible")
	_check(banner.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"banner: sigue IGNORE tras mostrar()")
	_check(str(banner._titulo.text) == "Has descubierto: Moon Town",
		"banner: título correcto", banner._titulo.text)
	_check(str(banner._subtitulo.text) == "Nivel recomendado 1–5",
		"banner: subtítulo correcto", banner._subtitulo.text)
	banner._process(0.1)
	_check(banner.visible and banner.modulate.a < 1.0 and banner.modulate.a > 0.0,
		"banner: fundido de entrada", str(banner.modulate.a))
	banner._process(1.0)
	_check(banner.visible and banner.modulate.a == 1.0,
		"banner: opaco durante la muestra", str(banner.modulate.a))
	banner._process(2.0)
	_check(banner.visible and banner.modulate.a < 1.0 and banner.modulate.a > 0.0,
		"banner: fundido de salida", str(banner.modulate.a))
	banner._process(1.0)
	_check(not banner.visible, "banner: se oculta solo tras ~3.5 s")
	banner.mostrar("El Velo", "Nivel recomendado 55–70")
	_check(banner.visible
		and str(banner._titulo.text) == "Has descubierto: El Velo",
		"banner: reutilizable tras ocultarse", banner._titulo.text)
