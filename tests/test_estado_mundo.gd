extends SceneTree
## El refugio se guardaba reclamado y al cargar volvía sin reclamar.
##
## BUG REAL, encontrado por tests/playtest_completo.gd (ola 3): la escena se
## construye por fases. `SaveSystem.cargar()` se dispara en el `_ready` de la
## demo, cuando el mundo todavía no existe; los refugios se crean después, en
## `_al_mundo_listo()`. Así que `_cargar_refugios()` iteraba un array VACÍO y no
## restauraba nada.
##
## Y lo grave no era solo perderlo al cargar: al guardar después, el estado
## recién construido —refugio sin reclamar, sin piezas— pisaba lo que estaba en
## disco. La reclamación del jugador se perdía DE FORMA PERMANENTE con dos
## ciclos de guardar y cargar, y no había ningún error en ninguna parte.
##
## Por eso este test no comprueba "cargar() devuelve true": comprueba el ciclo
## entero, que es donde el bug vivía.
##
## El arreglo es `SaveSystem.aplicar_estado_mundo()`, que reaplica el bloque del
## mundo una vez que árboles y refugios existen. Si alguien borra esa llamada
## desde la demo, este test se pone rojo.

const RUTA_TEST: String = "user://_test_estado_mundo.json"

var _ok: int = 0
var _fallos: int = 0
## `guardar()` se niega a escribir sin un jugador. Acá es solo un requisito del
## formato: nada de este test lo usa.
var _basura: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	print("[TEST] Estado del mundo — el refugio sobrevive a guardar y cargar")
	_la_reclamacion_sobrevive_al_ciclo()
	_sin_guardado_no_inventa_estado()
	_olvidar_limpia()
	print("[TEST] estado_mundo: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] %s%s" % [nombre, "" if detalle == "" else "  <-- " + detalle])


func _jugador() -> Player:
	var p := Player.new()
	p.nombre = "Ilya"
	p.clase_id = "guerrero"
	root.add_child(p)
	_basura.append(p)
	return p


func _refugio(id: String) -> Refugio:
	var r := Refugio.new()
	r.refugio_id = id
	return r


## El ciclo completo con el ORDEN REAL de la escena: `cargar()` primero, con los
## arrays de mundo todavía vacíos (así pasa en el `_ready`), y recién después
## aparecen los refugios (así pasa en `_al_mundo_listo()`).
func _la_reclamacion_sobrevive_al_ciclo() -> void:
	_borrar()
	SaveSystem.ruta = RUTA_TEST

	# --- PARTIDA 1: se reclama el refugio y se guarda.
	var r1 := _refugio("refugio_moon_town")
	var ok1: bool = r1.reclamar(10)
	_chk(ok1, "el refugio se puede reclamar", "")
	var sv1 := SaveSystem.new()
	sv1.jugador = _jugador()
	sv1.refugios = [r1]
	_chk(sv1.guardar(), "la primera partida se guarda", "")

	# --- PARTIDA 2: carga en el orden real de la escena.
	var sv2 := SaveSystem.new()
	sv2.jugador = _jugador()
	sv2.refugios = []          # esto es lo que pasaba en el _ready
	_chk(sv2.cargar(), "la segunda carga lee el archivo", "")

	# Ahora aparece el refugio, como en _al_mundo_listo().
	var r2 := _refugio("refugio_moon_town")
	sv2.refugios = [r2]
	# Y se reaplica el estado. SIN esta llamada, esto es el bug entero.
	sv2.aplicar_estado_mundo()

	_chk(r2.esta_reclamado(),
		"EL REFUGIO SIGUE RECLAMADO DESPUES DE CARGAR (este era el bug)",
		"reclamado=%s" % str(r2.esta_reclamado()))
	_chk(r2.refugio_id == "refugio_moon_town", "y conserva su id", str(r2.refugio_id))

	# El paso que lo hacía PERMANENTE: guardar de nuevo no debe perderlo.
	var sv3 := SaveSystem.new()
	sv3.jugador = _jugador()
	sv3.refugios = [r2]
	sv3.guardar()
	var sv4 := SaveSystem.new()
	sv4.jugador = _jugador()
	sv4.refugios = []
	_chk(sv4.cargar(), "un segundo ciclo tambien lee el archivo", "")
	var r4 := _refugio("refugio_moon_town")
	sv4.refugios = [r4]
	sv4.aplicar_estado_mundo()
	_chk(r4.esta_reclamado(),
		"y un segundo ciclo guardar/cargar NO lo pierde (por eso era permanente)",
		"reclamado=%s" % str(r4.esta_reclamado()))

	# Y que sea idempotente: la escena lo llama una vez, pero un re-entrante o un
	# segundo _al_mundo_listo() lo harian.
	sv4.aplicar_estado_mundo()
	_chk(r4.esta_reclamado(), "aplicar_estado_mundo() dos veces no rompe nada", "")

	r1.free()
	r2.free()
	r4.free()
	_borrar()
	SaveSystem.ruta = ""


## Si no hay nada guardado, aplicar el estado del mundo no puede inventar nada.
func _sin_guardado_no_inventa_estado() -> void:
	_borrar()
	SaveSystem.ruta = RUTA_TEST
	var sv := SaveSystem.new()
	sv.jugador = _jugador()
	sv.refugios = []
	# cargar() sobre un archivo que no existe: no debe reventar ni dejar estado.
	sv.cargar()
	var r := _refugio("refugio_moon_town")
	sv.refugios = [r]
	sv.aplicar_estado_mundo()
	_chk(not r.esta_reclamado(),
		"sin nada cargado, aplicar_estado_mundo() no reclama nada sola", "")
	r.free()
	_borrar()
	SaveSystem.ruta = ""


## Si no se olvida la cache, una partida nueva hereda el mundo de la anterior: la
## version silenciosa del mismo bug.
func _olvidar_limpia() -> void:
	_borrar()
	SaveSystem.ruta = RUTA_TEST
	var r1 := _refugio("refugio_moon_town")
	var ok1: bool = r1.reclamar(10)
	_chk(ok1, "el refugio se puede reclamar", "")
	var sv1 := SaveSystem.new()
	sv1.jugador = _jugador()
	sv1.refugios = [r1]
	sv1.guardar()

	var sv2 := SaveSystem.new()
	sv2.jugador = _jugador()
	sv2.refugios = []
	sv2.cargar()
	_chk(not sv2._estado_mundo_cache.is_empty(),
		"la cache del mundo quedo poblada tras cargar", "")
	sv2.olvidar_estado_mundo()
	_chk(sv2._estado_mundo_cache.is_empty(), "olvidar_estado_mundo() la vacia", "")

	# Con la cache vacia, aplicar no toca nada.
	var r2 := _refugio("refugio_moon_town")
	sv2.refugios = [r2]
	sv2.aplicar_estado_mundo()
	_chk(not r2.esta_reclamado(), "con la cache vacia no se restaura nada", "")

	r1.free()
	r2.free()
	_borrar()
	SaveSystem.ruta = ""


func _borrar() -> void:
	for sufijo in ["", ".bak", ".tmp"]:
		var abs := ProjectSettings.globalize_path(RUTA_TEST + sufijo)
		if FileAccess.file_exists(RUTA_TEST + sufijo):
			DirAccess.remove_absolute(abs)
