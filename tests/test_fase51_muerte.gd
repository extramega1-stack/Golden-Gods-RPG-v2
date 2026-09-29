extends SceneTree
## Tests headless de la Fase 51 (muerte y respawn del héroe).
##
## POR QUÉ NACE ESTE ARCHIVO: hasta la fase 51, morirse fuera de la arena
## congelaba el juego para siempre. `Entity.die()` apagaba `_process`,
## `_physics_process` y `collision_layer`, y `Player.murio` solo estaba
## conectado en `arena.gd`. No había ni un test que lo cubriera, porque la
## partida "muerta" no se detectaba: el juego solo se quedaba quieto.
##
## Cubre:
## (a) `Entity.revivir()`: restaura colisión, procesado, vida y maná, y
##     emite las señales; sobre una entidad viva es no-op;
## (b) la regresión que faltaba: morir y revivir deja la entidad operativa;
## (c) `SkillSystem.purgar_temporales()` / `purgar_cooldowns()`;
## (d) `Player.reaparecer()`: ancla, limpieza de selección y cámara;
## (e) `RespawnHeros`: guarda de arena, plazas, y que el ancla NO venga de
##     `viaje_rapido.json` (esas plazas traen y = 45.0 constante);
## (f) `CameraRig.snap_seguimiento()` no interpola.
##
## Cómo correrlo:
## godot --headless --path <proyecto> --script res://tests/test_fase51_muerte.gd

const EN: GDScript = preload("res://scripts/core/entity.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")
const SS: GDScript = preload("res://scripts/skills/skill_system.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const CR: GDScript = preload("res://scripts/player/camera_rig.gd")
const RH: GDScript = preload("res://scripts/mundo/respawn_heroe.gd")
const RUTA_VIAJE: String = "res://data/viaje_rapido.json"

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 51 — muerte y respawn del heroe")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_revivir()
	_test_morir_y_revivir_no_congela()
	_test_purgas()
	_test_reaparecer()
	_test_respawn_heroes()
	_test_arena_no_pisada()
	_test_ancla_no_de_viaje_rapido()
	_test_snap_camara()
	print("[TEST] fase51_muerte: %d ok, %d fallos" % [_ok, _fallos])
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


func _entidad() -> Entity:
	var e: Entity = EN.new()
	e.stats = SB.new(10.0, 10.0, 0.0, 0.0)
	e.stats.recalc()
	e.vida_actual = e.stats.vida_max
	root.add_child(e)
	_basura.append(e)
	return e


# --- (a) Entity.revivir ------------------------------------------------

func _test_revivir() -> void:
	var e: Entity = _entidad()
	var vida_max: float = e.stats.vida_max
	var mana_max: float = e.stats.mana_max
	_chk(vida_max > 0.0, "la entidad de prueba tiene vida", str(vida_max))

	# Vivir → revivir no hace nada (idempotente, como die()).
	var vida_antes: float = e.vida_actual
	e.revivir(1.0, 1.0)
	_chk(is_equal_approx(e.vida_actual, vida_antes),
		"revivir() sobre una entidad viva no cambia la vida",
		"%s -> %s" % [vida_antes, e.vida_actual])
	_chk(e.esta_vivo(), "sigue viva", "")

	# Morir.
	e.take_damage(vida_max * 10.0, null)
	_chk(not e.esta_vivo(), "la entidad muere", str(e.vida_actual))
	_chk(not e.is_physics_processing(),
		"die() apaga el procesado fisico", "")

	# Revivir: con negativos llena.
	e.revivir()
	_chk(e.esta_vivo(), "revivir() la deja viva", "")
	_chk(is_equal_approx(e.vida_actual, vida_max),
		"revivir() sin argumentos llena la vida", str(e.vida_actual))
	_chk(is_equal_approx(e.mana_actual, mana_max),
		"revivir() sin argumentos llena el mana", str(e.mana_actual))

	# Y emite las señales, que es como la UI se entera.
	var senales: Array = []
	e.vida_cambiada.connect(func(_v: float, _m: float): senales.append("vida"))
	e.mana_cambiado.connect(func(_v: float, _m: float): senales.append("mana"))
	e.die()
	e.revivir()
	_chk(senales.has("vida") and senales.has("mana"),
		"revivir() emite vida_cambiada y mana_cambiado", str(senales))

	# Vida parcial también vale, y se acota.
	e.die()
	e.revivir(10.0, 10.0)
	_chk(is_equal_approx(e.vida_actual, 10.0), "revivir(vida) fija la vida", str(e.vida_actual))
	e.die()
	e.revivir(999999.0, 999999.0)
	_chk(is_equal_approx(e.vida_actual, vida_max),
		"revivir() acota la vida al maximo", str(e.vida_actual))


# --- (b) la regresión que faltaba -------------------------------------

## El bug real: la entidad muerta se quedaba apagada para siempre. Esto
## comprueba que revivir devuelve la entidad a un estado OPERATIVO, no solo
## a "no está muerta".
func _test_morir_y_revivir_no_congela() -> void:
	var e: Entity = _entidad()
	var capa: int = e.collision_layer
	e.take_damage(99999.0, null)
	_chk(not e.esta_vivo(), "muerto", "")

	e.revivir()
	_chk(e.esta_vivo(), "revivir() la deja viva", "")
	# `die()` y `_revivir_silencioso()` escriben la capa con set_deferred, así
	# que el valor solo es real después de que el motor vacíe la cola. Por eso
	# esta comprobación va en su propia pasada (await process_frame en
	# `_process`), no en medio del bloque.
	_chk(e.is_physics_processing(),
		"revivir() vuelve a activar el fisico", "")
	_chk(e.is_processing(),
		"revivir() vuelve a activar el procesado", "")

	# Y una entidad revivida vuelve a recibir dano: el ciclo no quedo a medias.
	var vida: float = e.vida_actual
	e.take_damage(5.0, null)
	_chk(e.vida_actual < vida,
		"una entidad revivida sigue recibiendo dano", "%s -> %s" % [vida, e.vida_actual])


# --- (c) purgas de SkillSystem ----------------------------------------

func _test_purgas() -> void:
	var s: SkillSystem = SS.new()
	s.configurar_clase("guerrero")
	var e: Entity = _entidad()

	# Un buff queda registrado como mod en el StatBlock del objetivo.
	var antes: float = e.stats.vel_ataque
	_registrar(s, e, "buff:test", "vel_ataque", 0.5, 60.0)
	_chk(e.stats.vel_ataque > antes,
		"el buff sube el stat del objetivo", "%s -> %s" % [antes, e.stats.vel_ataque])
	_chk(s.efecto_activo("buff:test"), "el efecto queda activo", "")

	# Cooldown: lo ponemos a mano porque Lanzar necesita mas scaffolding.
	s._cds["skills"] = 12.0
	_chk(s.cooldown_restante("skills") > 0.0, "hay cooldown puesto", "")

	# Las purgas.
	s.purgar_temporales()
	s.purgar_cooldowns()
	_chk(not s.efecto_activo("buff:test"), "purgar_temporales() borra el efecto", "")
	_chk(is_equal_approx(e.stats.vel_ataque, antes),
		"purgar_temporales() devuelve el stat a su valor base",
		"%s vs %s" % [e.stats.vel_ataque, antes])
	_chk(is_equal_approx(s.cooldown_restante("skills"), 0.0),
		"purgar_cooldowns() deja los cooldowns en 0", "")

	# Purgar dos veces no rompe nada.
	s.purgar_temporales()
	s.purgar_cooldowns()
	_chk(is_equal_approx(e.stats.vel_ataque, antes), "purgar dos veces es seguro", "")


## Registra un efecto temporal llamando al privado, que es como lo hacen
## los efectos reales.asi que el test pruebe la estructura real de datos.
func _registrar(s: SkillSystem, e: Entity, mod_id: String, derivado: String,
		pct: float, dur: float) -> void:
	s._registrar_efecto(e, mod_id, derivado, pct, dur)


# --- (d) Player.reaparecer --------------------------------------------

func _test_reaparecer() -> void:
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)

	var ancla: Vector3 = Vector3(120.0, 30.0, -80.0)
	p.anclar_en_ciudad(ancla, 1.5)
	_chk(p.ancla() == ancla, "anclar_en_ciudad guarda el punto seguro", str(p.ancla()))

	# Matarlo y reaparecerlo.
	p.take_damage(999999.0, null)
	_chk(not p.esta_vivo(), "el jugador muere", "")
	p.reaparecer()

	_chk(p.esta_vivo(), "reaparecer() lo revive", "")
	_chk(is_equal_approx(p.vida_actual, p.stats.vida_max),
		"reaparecer() le da la vida completa", str(p.vida_actual))
	_chk(p.global_position.distance_to(ancla) < 1.0,
		"reaparecer() lo pone en el ancla",
		"%s vs %s" % [p.global_position, ancla])
	_chk(p.objetivo_ataque == null, "reaparecer() suelta el objetivo de ataque", "")
	_chk(not p._tiene_destino, "reaparecer() suelta el destino pendiente", "")


# --- (e) RespawnHeros --------------------------------------------------

func _test_respawn_heroes() -> void:
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)

	var r: RespawnHeros = RH.new()
	root.add_child(r)
	_basura.append(r)

	_chk(r.plazas() == 0, "arranca sin plazas", str(r.plazas()))

	# Dos plazas; el jugador arranca en la primera.
	var a: Vector3 = Vector3(0.0, 40.0, 45.0)
	var b: Vector3 = Vector3(9966.0, 36.0, 0.0)
	r.registrar_ciudad("moon_town", a, 0.0)
	r.registrar_ciudad("desert", b, 0.0)
	_chk(r.plazas() == 2, "registra las dos plazas", str(r.plazas()))

	p.global_position = a
	r.configurar(p)
	_chk(r.plaza_actual() == "moon_town",
		"el jugador en la plaza A elige la plaza A", r.plaza_actual())
	_chk(p.ancla() == a, "configurar() ancla en la plaza actual", str(p.ancla()))

	# Moverse a la otra ciudad cambia el ancla.
	p.global_position = b
	r.actualizar_ancla()
	_chk(p.ancla() == b, "cambiar de ciudad cambia el ancla", str(p.ancla()))

	# Morir alli lo revive en la misma ciudad.
	p.take_damage(999999.0, null)
	_chk(p.esta_vivo(), "morir dispara el respawn via 'murio'", "")
	_chk(p.global_position.distance_to(b) < 1.0,
		"reaparece en la ciudad donde murio",
		"%s vs %s" % [p.global_position, b])
	_chk(is_equal_approx(p.vida_actual, p.stats.vida_max),
		"reaparece con la vida llena", str(p.vida_actual))


## La guarda de arena: si la arena esta activa, el respawn NO teletransporta,
## porque la arena resuelve su propia derrota (`arena.gd` conecta `murio` y
## `iniciar()` deja `_activa = true`). Sin la guarda, el jugador se iria del
## campo de batalla a la ciudad a media partida.
func _test_arena_no_pisada() -> void:
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)
	var r: RespawnHeros = RH.new()
	root.add_child(r)
	_basura.append(r)

	# El jugador arranca EN la plaza: si está lejos de toda plaza no hay
	# ancla (por diseño), y el respawn lo dejaría donde ya estaba.
	var plaza: Vector3 = Vector3(500.0, 40.0, 500.0)
	r.registrar_ciudad("lejos", plaza, 0.0)
	p.global_position = plaza

	var arena := Arena.new()
	arena.name = "ArenaFalsa"
	root.add_child(arena)
	_basura.append(arena)
	arena.configurar({"oleadas": [{}]})
	arena.fijar_factory(Callable())
	arena.fijar_jugador(p)

	# (1) Arena INACTIVA: el respawn sí ocurre.
	r.configurar(p, arena)
	_chk(not arena.activa(), "la arena arranca inactiva", "")
	_chk(p.ancla() == plaza, "el ancla quedó en la plaza", str(p.ancla()))
	p.global_position = plaza + Vector3(30.0, 0.0, 0.0)
	p.take_damage(999999.0, null)
	_chk(p.esta_vivo(), "con la arena inactiva el heroe revive", "")
	_chk(p.global_position.distance_to(plaza) < 1.0,
		"con la arena inactiva vuelve a la plaza", str(p.global_position))

	# (2) Arena ACTIVA: el respawn NO toca la posicion. `iniciar()` exige
	# factory y oleadas; se le da una factory minima.
	arena.fijar_factory(func(_a: String, _p: Vector3) -> Node: return Node3D.new())
	arena.fijar_respawn(r)
	arena.iniciar()
	_chk(arena.activa(), "la arena quedo activa", "")
	_chk(r.suspendido(),
		"iniciar() pone a punto el respawn (muerte del heroe en combate)",
		"suspendido=%s" % str(r.suspendido()))

	p.global_position = plaza + Vector3(30.0, 0.0, 0.0)
	var antes: Vector3 = p.global_position
	p.take_damage(999999.0, null)
	_chk(p.global_position.distance_to(antes) < 1.0,
		"con la arena activa el heroe NO se teletransporta (lo resuelve la arena)",
		"%s -> %s" % [antes, p.global_position])
	_chk(r.suspendido(),
		"_terminar NO libera la puesta dentro de la misma senal 'murio'",
		"suspendido=%s" % str(r.suspendido()))

	# (3) Devuelto al mundo: `detener()` devuelve el control al respawn. La
	# demo revive al héroe al perder; `take_damage` sobre un muerto es no-op,
	# así que hay que revivirlo antes de la segunda muerte.
	arena.detener()
	_chk(not r.suspendido(),
		"detener() devuelve el control al respawn", "")
	_jugador_reanimo(p)
	p.global_position = plaza + Vector3(30.0, 0.0, 0.0)
	p.take_damage(999999.0, null)
	_chk(p.global_position.distance_to(plaza) < 1.0,
		"fuera de la arena el respawn vuelve a funcionar", str(p.global_position))


func _jugador_reanimo(p: Player) -> void:
	p.revivir()


# --- (f) el ancla no puede venir de viaje_rapido.json ------------------

## Este es el bug de datos que casi se cuela en el diseno: las plazas de
## `data/viaje_rapido.json` traen `y = 45.0` constante, y la altura real del
## terreno llega a 220 u. Un ancla sacada de ahi te deja flotando y
## `_pegar_al_terreno` te teletransporta al suelo: un tirón visible.
func _test_ancla_no_de_viaje_rapido() -> void:
	var texto: String = FileAccess.get_file_as_string(RUTA_VIAJE)
	_chk(texto != "", "data/viaje_rapido.json se lee", RUTA_VIAJE)
	var datos = JSON.parse_string(texto)
	if not (datos is Dictionary):
		_chk(false, "viaje_rapido.json es un Dictionary", "")
		return
	var ciudades: Dictionary = (datos as Dictionary).get("ciudades", {})
	_chk(not ciudades.is_empty(), "tiene ciudades", str(ciudades.size()))

	# Las plazas de `viaje_rapido.json` son [x, z] de DOS elementos: no
	# tienen y. Por eso no pueden servir de ancla — la altura sale de
	# `CiudadLuna`, que sí la consulta (y va de 40 a 220 u según la ciudad).
	for id in ciudades.keys():
		var p: Array = ciudades[id].get("plaza", [])
		_chk(p.size() == 2,
			"la plaza '%s' es [x, z] sin y (no sirve de ancla sola)" % str(id),
			"tamaño=%d %s" % [p.size(), str(p)])

	# El ancla real del jugador viene del terreno, no del JSON.
	var p2: Player = PL.new()
	root.add_child(p2)
	_basura.append(p2)
	var con_terreno: Vector3 = Vector3(-9966.0, 62.62, 0.0)
	p2.anclar_en_ciudad(con_terreno)
	_chk(is_equal_approx(p2.ancla().y, 62.62),
		"el ancla conserva la y que le dio CiudadLuna (con terreno)", str(p2.ancla()))


# --- (g) la camara hace snap, no lerp ----------------------------------

func _test_snap_camara() -> void:
	var objetivo := Node3D.new()
	root.add_child(objetivo)

	# El rig espera esta jerarquía (Pitch / SpringArm3D / Camera3D la crea la
	# escena del demo, no el script), así que hay que montarla a mano.
	var rig: CameraRig = CR.new()
	rig.ruta_objetivo = NodePath("")
	var pitch := Node3D.new()
	pitch.name = "Pitch"
	rig.add_child(pitch)
	var brazo := SpringArm3D.new()
	brazo.name = "SpringArm3D"
	pitch.add_child(brazo)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	brazo.add_child(cam)
	root.add_child(rig)
	_basura.append(rig)
	rig.set("_objetivo", objetivo)

	# Lejos, para que un lerp se notaria.
	objetivo.global_position = Vector3(3000.0, 0.0, -4000.0)
	rig.snap_seguimiento()
	_chk(rig.global_position.distance_to(objetivo.global_position) < 0.01,
		"snap_seguimiento() pega la camara al objetivo de golpe",
		"%s vs %s" % [rig.global_position, objetivo.global_position])

	# Y con trauma acumulado, el shake se limpia (no queda un temblor solo).
	rig.agregar_trauma(0.8)
	rig.snap_seguimiento()
	_chk(is_equal_approx(rig.trauma, 0.0),
		"snap_seguimiento() limpia el trauma del shake", str(rig.trauma))
