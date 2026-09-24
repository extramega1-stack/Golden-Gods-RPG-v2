extends SceneTree
## Tests headless de la Fase 11 (héroe y presentación).
##
## (a) ClaseDB: 5 ids en orden, 4 jugables (guerrero, arquero, mago,
##     clerigo; daguero no), stats base 45/10/0/0 del guerrero, colores que
##     parsean a Color (default dorado).
## (b) validar_nombre: "" / "   " / 17 caracteres → error; "Ilya" / "A" /
##     16 caracteres → válido.
## (c) Player: _ready aplica la clase guerrero desde datos (45/10);
##     fijar_identidad emite identidad_cambiada; aplicar_clase pone stats y
##     llena vida; aplicar_clase("inexistente") no toca nada ni revienta.
## (d) DatosSesion: nueva_partida / pedir_continuar / limpiar / aplicar_a
##     (con Player real aplica nombre+clase; con continuar=true no toca
##     nada; con null no revienta).
## (e) Save: round-trip guarda y restaura nombre/clase; dict viejo (sin
##     "nombre"/"clase_id") carga con "Héroe"/"guerrero" sin reventar.
## (f) PantallaTitulo.puede_continuar(ruta): false sin archivo, true con
##     archivo (ruta temporal inyectada, no la real).
## (g) RetratoHeroe: conectar pinta nombre/nivel/inicial; die() → modulate
##     de muerto; refrescar() con jugador vivo restaura; identidad_cambiada
##     re-lee el nombre.
## (h) Regresión: HUD.conectar + refrescar con el retrato integrado no
##     revientan y el retrato está en el árbol.
##
## Cómo correrlos (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase11.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const SS: GDScript = preload("res://scripts/save/save_system.gd")
const CP: GDScript = preload("res://scripts/ui/creacion_personaje.gd")
const PT: GDScript = preload("res://scripts/ui/pantalla_titulo.gd")
const RH: GDScript = preload("res://scripts/ui/retrato_heroe.gd")
const HUDS: GDScript = preload("res://scripts/ui/hud.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []
var _identidades: int = 0


func _init() -> void:
	print("[TEST] Fase 11 — heroe y presentacion: clases, identidad, titulo, retrato")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b): los
## _ready de Player/HUD/RetratoHeroe necesitan estar en el árbol.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	DatosSesion.limpiar()
	_t_clasedb()
	_t_validar_nombre()
	_t_identidad()
	_t_datos_sesion()
	_t_save_identidad()
	_t_puede_continuar()
	_t_retrato()
	_t_hud_retrato()
	_t_creacion_stats()
	DatosSesion.limpiar()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	DirAccess.remove_absolute("user://partida.json")
	DirAccess.remove_absolute("user://tmp_fase11_continuar.json")
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


func _al_identidad() -> void:
	_identidades += 1


func _player() -> Player:
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)
	return p


func _t_clasedb() -> void:
	ClaseDB.cargar()
	var ids: Array[String] = ClaseDB.ids()
	_check(ids == ["guerrero", "arquero", "mago", "clerigo", "daguero"],
		"clasedb: 5 ids en orden", str(ids))
	_check(ClaseDB.jugables() == ["guerrero", "arquero", "mago", "clerigo"],
		"clasedb: 4 jugables (daguero fuera)", str(ClaseDB.jugables()))
	_check(ClaseDB.es_jugable("guerrero"), "clasedb: guerrero jugable")
	_check(ClaseDB.es_jugable("mago"), "clasedb: mago jugable")
	_check(ClaseDB.es_jugable("arquero"), "clasedb: arquero jugable")
	_check(ClaseDB.es_jugable("clerigo"), "clasedb: clerigo jugable")
	_check(not ClaseDB.es_jugable("daguero"), "clasedb: daguero no jugable")
	_check(not ClaseDB.es_jugable("inexistente"),
		"clasedb: id desconocido no jugable")
	var base: Dictionary = ClaseDB.stats_base("guerrero")
	_check(float(base.get("fuerza", -1.0)) == 45.0
			and float(base.get("agilidad", -1.0)) == 10.0
			and float(base.get("destreza", -1.0)) == 0.0
			and float(base.get("inteligencia", -1.0)) == 0.0
			and float(base.get("aguante", -1.0)) == 15.0,
		"clasedb: stats base del guerrero 45/10/0/0 + STA 15", str(base))
	_check(ClaseDB.color_primario("guerrero") == Color("b03a2e"),
		"clasedb: color primario del guerrero",
		str(ClaseDB.color_primario("guerrero")))
	_check(ClaseDB.color_secundario("guerrero") == Color("2a2a30"),
		"clasedb: color secundario del guerrero",
		str(ClaseDB.color_secundario("guerrero")))
	var dorado: Color = Color(0.95, 0.75, 0.30)
	_check(ClaseDB.color_primario("inexistente") == dorado,
		"clasedb: color default dorado si falta")
	_check(str(ClaseDB.obtener("guerrero").get("nombre", "")) == "Guerrero",
		"clasedb: nombre del guerrero")


func _t_validar_nombre() -> void:
	_check(CP.validar_nombre("") != "", "nombre: vacio -> error")
	_check(CP.validar_nombre("   ") != "", "nombre: solo espacios -> error")
	_check(CP.validar_nombre("x".repeat(17)) != "",
		"nombre: 17 caracteres -> error")
	_check(CP.validar_nombre("Ilya") == "", "nombre: 'Ilya' valido")
	_check(CP.validar_nombre("A") == "", "nombre: 1 caracter valido")
	_check(CP.validar_nombre("x".repeat(16)) == "",
		"nombre: 16 caracteres valido")
	_check(CP.validar_nombre("  Ilya  ") == "",
		"nombre: con espacios alrededor valido")


func _t_identidad() -> void:
	var j: Player = _player()
	_check(j.stats.fuerza == 45.0 and j.stats.agilidad == 10.0
			and j.stats.destreza == 0.0 and j.stats.inteligencia == 0.0
			and j.stats.aguante == 15.0,
		"player: _ready aplica la clase guerrero desde datos (45/10/0/0 + STA 15)")
	_check(j.nombre == "Héroe" and j.clase_id == "guerrero",
		"player: identidad por defecto Heroe/guerrero")
	_identidades = 0
	j.identidad_cambiada.connect(_al_identidad)
	j.fijar_identidad("Ilya", "guerrero")
	_check(_identidades == 1,
		"player: fijar_identidad emite identidad_cambiada")
	_check(j.nombre == "Ilya" and j.clase_id == "guerrero",
		"player: fijar_identidad asigna nombre y clase")
	j.stats.fuerza = 0.0
	j.stats.agilidad = 0.0
	j.stats.destreza = 0.0
	j.stats.inteligencia = 0.0
	j.aplicar_clase("guerrero")
	_check(j.stats.fuerza == 45.0 and j.stats.agilidad == 10.0
			and j.stats.aguante == 15.0,
		"player: aplicar_clase pone 45/10 + STA 15")
	_check(j.vida_actual == j.stats.vida_max
			and j.mana_actual == j.stats.mana_max,
		"player: aplicar_clase llena vida y mana")
	var antes: float = j.stats.fuerza
	j.aplicar_clase("inexistente")
	_check(j.stats.fuerza == antes,
		"player: aplicar_clase desconocida no toca nada ni revienta")


func _t_datos_sesion() -> void:
	_check(DatosSesion.nombre == "" and DatosSesion.clase_id == "guerrero"
			and not DatosSesion.continuar,
		"sesion: limpiar() deja defaults")
	DatosSesion.nueva_partida("Ilya", "guerrero")
	_check(DatosSesion.nombre == "Ilya",
		"sesion: nueva_partida guarda el nombre")
	_check(DatosSesion.clase_id == "guerrero",
		"sesion: nueva_partida guarda la clase")
	_check(not DatosSesion.continuar,
		"sesion: nueva_partida no es continuar")
	DatosSesion.nueva_partida("X", "inexistente")
	_check(DatosSesion.clase_id == "guerrero",
		"sesion: clase desconocida cae a guerrero")
	var j: Player = _player()
	DatosSesion.nueva_partida("Ilya", "guerrero")
	DatosSesion.aplicar_a(j)
	_check(j.nombre == "Ilya" and j.clase_id == "guerrero",
		"sesion: aplicar_a fija la identidad", j.nombre)
	_check(j.stats.fuerza == 45.0 and j.stats.agilidad == 10.0,
		"sesion: aplicar_a aplica los stats de la clase")
	DatosSesion.pedir_continuar()
	_check(DatosSesion.continuar, "sesion: pedir_continuar()")
	var j2: Player = _player()
	j2.fijar_identidad("Otro", "guerrero")
	DatosSesion.aplicar_a(j2)
	_check(j2.nombre == "Otro",
		"sesion: con continuar=true no toca nada", j2.nombre)
	DatosSesion.aplicar_a(null)
	_check(true, "sesion: aplicar_a(null) no revienta")
	DatosSesion.limpiar()
	_check(DatosSesion.nombre == "" and not DatosSesion.continuar,
		"sesion: limpiar() resetea")


func _t_save_identidad() -> void:
	DirAccess.remove_absolute("user://partida.json")
	var j: Player = _player()
	j.fijar_identidad("Ilya", "guerrero")
	j.ganar_oro(50)
	var s: SaveSystem = SS.new()
	s.jugador = j
	s.enemigos = []
	_check(s.guardar(), "save: guardar() con identidad ok")
	var texto: String = FileAccess.get_file_as_string("user://partida.json")
	var crudo = JSON.parse_string(texto)
	_check(crudo is Dictionary, "save: el JSON es valido")
	var datos: Dictionary = crudo
	var dj: Dictionary = datos.get("jugador", {})
	_check(str(dj.get("nombre", "")) == "Ilya",
		"save: el JSON guarda el nombre")
	_check(str(dj.get("clase_id", "")) == "guerrero",
		"save: el JSON guarda la clase")
	var j2: Player = _player()
	var s2: SaveSystem = SS.new()
	s2.jugador = j2
	s2.enemigos = []
	_check(s2.cargar(), "save: cargar() ok")
	_check(j2.nombre == "Ilya", "save: el nombre se restaura", j2.nombre)
	_check(j2.clase_id == "guerrero",
		"save: la clase se restaura", j2.clase_id)
	# Dict viejo (sin "nombre"/"clase_id"): defaults tolerantes.
	dj.erase("nombre")
	dj.erase("clase_id")
	var f: FileAccess = FileAccess.open("user://partida.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(datos))
	f.close()
	var j3: Player = _player()
	var s3: SaveSystem = SS.new()
	s3.jugador = j3
	s3.enemigos = []
	_check(s3.cargar(), "save: dict viejo carga sin reventar")
	_check(j3.nombre == "Héroe",
		"save: dict viejo -> nombre default", j3.nombre)
	_check(j3.clase_id == "guerrero",
		"save: dict viejo -> clase default", j3.clase_id)
	DirAccess.remove_absolute("user://partida.json")


func _t_puede_continuar() -> void:
	var ruta: String = "user://tmp_fase11_continuar.json"
	DirAccess.remove_absolute(ruta)
	_check(not PT.puede_continuar(ruta),
		"titulo: sin archivo no se puede continuar")
	var f: FileAccess = FileAccess.open(ruta, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	_check(PT.puede_continuar(ruta),
		"titulo: con archivo si se puede continuar")
	DirAccess.remove_absolute(ruta)


func _t_retrato() -> void:
	var j: Player = _player()
	j.fijar_identidad("Ilya", "guerrero")
	var r: RetratoHeroe = RH.new()
	root.add_child(r)
	_basura.append(r)
	r.conectar(j)
	_check(r.nombre_mostrado() == "Ilya",
		"retrato: pinta el nombre", r.nombre_mostrado())
	_check(r.nivel_mostrado() == "Nv 1",
		"retrato: pinta el nivel", r.nivel_mostrado())
	_check(r.inicial_mostrada() == "G",
		"retrato: inicial de la clase", r.inicial_mostrada())
	j.die()
	_check(r.modulate == Color(0.35, 0.35, 0.42),
		"retrato: muerto -> modulate gris", str(r.modulate))
	# refrescar() con jugador vivo restaura el modulate.
	var j2: Player = _player()
	var r2: RetratoHeroe = RH.new()
	root.add_child(r2)
	_basura.append(r2)
	r2.conectar(j2)
	r2.modulate = Color(0.1, 0.1, 0.1)
	r2.refrescar()
	_check(r2.modulate == Color.WHITE,
		"retrato: refrescar() con vivo restaura", str(r2.modulate))
	j2.fijar_identidad("Sira", "guerrero")
	_check(r2.nombre_mostrado() == "Sira",
		"retrato: identidad_cambiada re-lee el nombre", r2.nombre_mostrado())


func _t_hud_retrato() -> void:
	var j: Player = _player()
	j.fijar_identidad("Ilya", "guerrero")
	var hud: HUD = HUDS.new()
	root.add_child(hud)
	_basura.append(hud)
	hud.conectar(j)
	hud.refrescar()
	# Fase 32: el retrato vive dentro del marco FlyFF (búsqueda recursiva).
	var n_retratos: int = 0
	var pila: Array = [hud]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is RetratoHeroe:
			n_retratos += 1
		for h in n.get_children():
			pila.append(h)
	_check(n_retratos == 1,
		"hud: el retrato esta integrado", str(n_retratos))


## Fase 30.1: la creación muestra STR/STA/DEX/INT (sin agilidad) con
## STA 15 de base en todas las clases.
func _t_creacion_stats() -> void:
	var cp: Control = CP.new()
	root.add_child(cp)
	_basura.append(cp)
	cp._al_elegir_clase("guerrero")
	var texto: String = (cp.get("_desc_stats") as Label).text
	_check(texto == "STR 45 · STA 15 · DEX 0 · INT 0",
		"creacion: guerrero en FlyFF", texto)
	_check(not texto.contains("gil") and not texto.contains("Agilidad"),
		"creacion: sin agilidad")
	cp._al_elegir_clase("mago")
	var texto_m: String = (cp.get("_desc_stats") as Label).text
	_check(texto_m.contains("STA 15"),
		"creacion: el mago también parte con STA 15", texto_m)
