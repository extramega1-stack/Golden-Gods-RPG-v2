extends SceneTree
## Tests headless de la Fase 60 (el Refugio: reclamar).
##
## POR QUÉ NACE: el "refugio del Verdugo" es CANON del proyecto desde el
## spec §6 Dominio 7 y hasta la fase 60 no existía. Reclamarlo da un ancla
## de respawn, un nodo de viaje rápido sin costo y el presupuesto de piezas
## de la fase 61.
##
## Cubre:
## (a) el DATO: 9 refugios, uno por plaza, con techo de piezas;
## (b) reclamar es idempotente y respeta el nivel;
## (c) el techo de piezas es un dato, no una constante;
## (d) un save manipulado no puede meter más piezas que el techo;
## (e) el refugio es zona de respawn: se conecta con `RespawnHeros`;
## (f) la altura sale del terreno, no del JSON (el bug de las 175 u).

const RD: GDScript = preload("res://scripts/mundo/refugio_db.gd")
const RF: GDScript = preload("res://scripts/mundo/refugio.gd")
const RH: GDScript = preload("res://scripts/mundo/respawn_heroe.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const TB: GDScript = preload("res://scripts/mundo/terreno.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 60 — el Refugio (reclamar)")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_dato()
	_test_reclamar()
	_test_nivel()
	_test_presupuesto()
	_test_save_manipulado()
	_test_respawn()
	print("[TEST] fase60_refugio: %d ok, %d fallos" % [_ok, _fallos])
	for n in _basura:
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("[FALLO] " + nombre + extra)


func _refugio(id: String) -> Refugio:
	var r: Refugio = RF.new()
	root.add_child(r)
	_basura.append(r)
	r.configurar_por_id(id)
	return r


# --- (a) el dato ------------------------------------------------------

func _test_dato() -> void:
	RD.cargar()
	var ids: Array[String] = RD.ids()
	_chk(ids.size() == 9, "hay 9 refugios (uno por plaza)", str(ids.size()))

	# Las coordenadas coinciden con las 9 plazas de viaje_rapido.json, que es
	# la misma fuente de verdad de la fase 55.
	var viaje = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/viaje_rapido.json"))
	var plazas: Dictionary = (viaje as Dictionary).get("ciudades", {})
	var datos = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/refugios.json"))
	for r in (datos as Dictionary).get("refugios", []):
		var rd: Dictionary = r
		var ciudad: String = str(rd.get("ciudad", ""))
		_chk(plazas.has(ciudad),
			"el refugio '%s' apunta a una ciudad real" % ciudad, str(plazas.keys()))
		if plazas.has(ciudad):
			var plaza: Array = (plazas[ciudad] as Dictionary).get("plaza", [])
			_chk(is_equal_approx(float(rd["x"]), float(plaza[0]))
					and is_equal_approx(float(rd["z"]), float(plaza[1])),
				"el refugio de '%s' está en su plaza" % ciudad,
				"%s,%s vs %s,%s" % [rd["x"], rd["z"], plaza[0], plaza[1]])
		_chk(int(rd.get("piezas_max", 0)) > 0,
			"'%s' tiene presupuesto de piezas" % ciudad, str(rd))
		_chk(str(rd.get("lugar", "")) != "",
			"'%s' tiene texto de lugar (lore)" % ciudad, "")

	# Y la altura NO viene del dato: es la misma trampa que la fase 55.
	var con_y: int = 0
	for r in (datos as Dictionary).get("refugios", []):
		if (r as Dictionary).has("y"):
			con_y += 1
	_chk(con_y == 0,
		"ningún refugio trae `y` en el dato (la altura la consulta el terreno)",
		"%d con y" % con_y)


# --- (b) reclamar -----------------------------------------------------

func _test_reclamar() -> void:
	var r: Refugio = _refugio("refugio_moon_town")
	_chk(r.refugio_id == "refugio_moon_town", "configura por id", r.refugio_id)
	_chk(r.nombre != "" and r.nombre != "refugio_moon_town", "trae nombre", r.nombre)
	_chk(not r.esta_reclamado(), "arranca sin reclamar", "")
	_chk(not r.puede_colocar(), "y sin reclamar no se construye", "")

	var avisos: Array = []
	r.reclamado.connect(func(id: String): avisos.append(id))

	_chk(r.reclamar(50), "se reclama con nivel de sobra", "")
	_chk(r.esta_reclamado(), "queda reclamado", "")
	_chk(avisos.size() == 1, "y avisa una vez", str(avisos))
	_chk(r.puede_colocar(), "ya se puede construir", "")

	# Idempotente: reclamar dos veces no vuelve a avisar.
	_chk(not r.reclamar(50), "reclamar de nuevo devuelve false", "")
	_chk(avisos.size() == 1, "y no avisa dos veces", str(avisos))


func _test_nivel() -> void:
	var r: Refugio = _refugio("refugio_golden")
	var minimo: int = r.nivel_minimo()
	_chk(minimo > 1, "el refugio del Sol pide nivel", str(minimo))
	_chk(not r.reclamar(minimo - 1),
		"con un nivel menos no se puede reclamar", "")
	_chk(not r.esta_reclamado(), "y no queda reclamado a medias", "")
	_chk(r.reclamar(minimo), "con el nivel justo, sí", "")
	_chk(r.esta_reclamado(), "", "")


# --- (c) el presupuesto -----------------------------------------------

func _test_presupuesto() -> void:
	var r: Refugio = _refugio("refugio_moon_town")
	r.reclamar(50)
	_chk(r.piezas() == 0, "arranca sin piezas", str(r.piezas()))
	_chk(r.piezas_restantes() == r.piezas_max, "y con el techo libre", "")

	# Colocar hasta el tope.
	for i in range(r.piezas_max):
		_chk(r.colocar("fogata", Vector3(i, 0, 0), 0.0) or i < 0,
			"coloca la pieza %d" % i, "")
	_chk(r.piezas() == r.piezas_max, "llega al techo", str(r.piezas()))
	_chk(not r.puede_colocar(), "y no deja seguir", "")
	_chk(r.piezas_restantes() == 0, "no quedan huecos", "")

	# Una pieza de más se rechaza (esto es el presupuesto de VRAM, §9.5).
	_chk(not r.colocar("yunque", Vector3(0, 0, 0), 0.0),
		"una pieza de más NO se coloca", "")
	_chk(r.piezas() == r.piezas_max, "y el tope no se mueve", str(r.piezas()))

	# Deshacer.
	_chk(r.quitar_ultima(), "se puede deshacer la última", "")
	_chk(r.piezas() == r.piezas_max - 1, "y libera un hueco", "")
	_chk(r.puede_colocar(), "ya se puede volver a colocar", "")


# --- (d) un save manipulado no rompe el techo ------------------------

func _test_save_manipulado() -> void:
	var r: Refugio = _refugio("refugio_moon_town")
	var muchos: Array = []
	for i in range(500):
		muchos.append({"tipo": "fogata", "x": float(i), "z": 0.0, "rot": 0.0})
	r.cargar_piezas(muchos)
	_chk(r.piezas() == r.piezas_max,
		"un save con 500 piezas se recorta al techo", str(r.piezas()))

	# Y uno con piezas pero no reclamado: no se puede construir encima.
	var r2: Refugio = _refugio("refugio_fire")
	var tres: Array = []
	for i in range(3):
		tres.append(muchos[i])
	r2.cargar_piezas(tres)
	_chk(not r2.esta_reclamado(), "cargar piezas no reclama el refugio", "")
	_chk(not r2.puede_colocar(), "y sin reclamar no se construye", "")


# --- (e) es el ancla de respawn ---------------------------------------

func _test_respawn() -> void:
	# Reclamar un refugio lo convierte en el punto seguro del jugador. Esa
	# conexión es la que hace que un refugio valga la pena.
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)

	var res: RespawnHeros = RH.new()
	root.add_child(res)
	_basura.append(res)
	var plaza := Vector3(0.0, 40.0, 45.0)
	res.registrar_ciudad("moon_town", plaza, 0.0)
	p.global_position = plaza
	res.configurar(p)
	_chk(p.ancla() == plaza, "el ancla arranca en la ciudad", str(p.ancla()))

	# El refugioel punto de aparición: mismo x/z que la plaza.
	var r: Refugio = _refugio("refugio_moon_town")
	_chk(Vector2(r.global_position.x, r.global_position.z)
			== Vector2(plaza.x, plaza.z),
		"el refugio de Moon Town está en la misma plaza que el ancla",
		"%s vs %s" % [r.global_position, plaza])

	# Morir y reaparecer: vuelve a la plaza, y el refugio no lo rompe.
	p.take_damage(999999.0, null)
	_chk(p.esta_vivo(), "el respawn sigue funcionando con refugios puestos", "")
	_chk(p.global_position.distance_to(plaza) < 1.0, "y vuelve al ancla", "")

	# La zona del refugio: `contiene` con el radio del dato.
	_chk(r.contiene(plaza), "el refugio contiene su plaza", "")
	_chk(not r.contiene(plaza + Vector3(r.radio * 3.0, 0.0, 0.0)),
		"pero no el mundo entero", "")


# --- (f) la altura la consulta el terreno ----------------------------

func _test_altura() -> void:
	# El dato trae [x, z]; la y es 0 hasta que el terreno la pone. Un refugio
	# con y = 0 quedaría enterrado o flotando, que es EXACTAMENTE el bug que
	# se encontró en la 55 con las plazas de viaje_rapido.
	var r: Refugio = _refugio("refugio_rage")
	_chk(is_equal_approx(r.global_position.y, 0.0),
		"el refugio no inventa la altura", str(r.global_position.y))

	# Con terreno, la altura real es la del suelo — y en `rage` son ~220 u.
	var terreno := Terreno.new()
	root.add_child(terreno)
	_basura.append(terreno)
	_chk(terreno.cargar(), "el terreno carga", "")
	var y: float = terreno.altura_en(r.global_position.x, r.global_position.z)
	_chk(y > 100.0,
		"la altura real de la plaza de Rage es alta (por eso el y fijo fallaba)",
		"y=%.1f" % y)
	_chk(not is_equal_approx(y, 45.0),
		"y NO es el 45.0 constante que traía viaje_rapido.json", "y=%.1f" % y)
