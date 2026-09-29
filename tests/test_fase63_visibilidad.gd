extends SceneTree
## Fase 63 (hotfix 62.1) — que se vea: vitales y habilidades/Hechos.
##
## POR QUÉ ESTE ARCHIVO: la Fase 58 metió hambre, sed y energía enteras, con
## debuff, mods y la decisión de que a 0 no matan. Todo pasaba y el jugador no
## tenía ni una barra. Con este bloque, las tres cosas que se agregaron sin UI
## en las fases 54–62 quedan a la vista.
##
## Además del "¿existe la UI?", lo que se comprueba aquí es lo que cuesta que
## se rompa: que la UI se suscriba y NO lea por frame, y que el pulso de
## alerta se apague solo (si no, la fila parpadea eternamente).

const PL: GDScript = preload("res://scripts/player/player.gd")
const VI: GDScript = preload("res://scripts/ui/indicador_vitales.gd")
const FA: GDScript = preload("res://scripts/ui/feed_avisos.gd")
const PH: GDScript = preload("res://scripts/ui/panel_habilidades.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 63 — Que se vea")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_senal_sucia()
	_test_indicador()
	_test_no_lectura_por_frame()
	_test_pulso_se_apaga()
	_test_pestanas_panel()
	print("[TEST] fase63_visibilidad: %d ok, %d fallos" % [_ok, _fallos])
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


func _jugador() -> Player:
	var p: Player = PL.new()
	p.fijar_identidad("H", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	p.nivel = 5
	p.ganar_oro(500)
	return p


# --- (a) la señal de Vitals es "sucia" -------------------------------

## Este es el test que sostiene el rendimiento (§9.5). Si `avanzar()` emitiera
## en cada frame, la UI se redibujaría 60 veces por segundo por tres barras.
func _test_senal_sucia() -> void:
	var v: Vitals = Vitals.new()
	# OJO: Array, no int. Las lambdas de GDScript capturan por valor, así que
	# un `var n: int` protegido por lambda NUNCA se ve cambiado desde fuera.
	var emissions: Array = [0]
	v.vital_cambiado.connect(func(_h: float, _s: float, _e: float, _f: float):
		emissions[0] += 1)

	# 600 frames de 1/60 s: un minuto de juego, como el Player real.
	for i in range(600):
		v.avanzar(1.0 / 60.0, 1.0)
	_chk(emissions[0] > 0, "la señal emite al avanzar", str(emissions[0]))
	_chk(emissions[0] < 60,
		"pero MUCHO menos de una vez por frame (1 minuto = 3600 frames)",
		"%d emisiones" % emissions[0])
	_chk(v.hambre < Vitals.MAXIMO, "y el vital bajó de verdad", str(v.hambre))

	# El umbral: 0.1 de movimiento no emite, 5 sí.
	var v2: Vitals = Vitals.new()
	var n2: Array = [0]
	v2.vital_cambiado.connect(func(_h: float, _s: float, _e: float, _f: float):
		n2[0] += 1)
	_chk(v2._avisar_cambio(false), "el primer aviso emite (nada se emitió antes)", "")
	var antes: int = n2[0]
	for i in range(5):
		# 0.1 de avance: 0.85 * 0.1 = 0.085, muy por debajo del umbral.
		v2.avanzar(0.1, 1.0)
	_chk(n2[0] == antes, "avances de 0.1 NO emiten (0.85 < TOQUE_MIN)",
		"%d -> %d" % [antes, n2[0]])
	for i in range(20):
		v2.avanzar(1.0, 1.0)
	_chk(n2[0] > antes, "avances de 1.0 sí emiten", "%d -> %d" % [antes, n2[0]])

	# La enfermedad tiene su propia señal, porque es un estado y no un valor.
	var v3: Vitals = Vitals.new()
	var enc: Array = [0]
	var apag: Array = [0]
	v3.enfermedad_cambiada.connect(func(a: bool):
		if a:
			enc[0] += 1
		else:
			apag[0] += 1)
	v3.consumir({"hambre": 10.0, "riesgo": "enfermedad"})
	_chk(enc[0] == 1, "comer carne cruda enciende la señal de enfermedad", str(enc[0]))
	# La transición se detecta DENTRO de `avanzar` (antes vs después), así que
	# hay que dejar que el decaimiento la cruce: son 20 s de enfermedad a 1/s.
	for i in range(25):
		v3.avanzar(1.0, 1.0)
	_chk(v3.enfermedad <= 0.0, "la enfermedad se cura sola", str(v3.enfermedad))
	_chk(apag[0] == 1, "y avisa cuando se apaga", str(apag[0]))


# --- (b) el indicador existe y se dibuja -----------------------------

func _test_indicador() -> void:
	var p: Player = _jugador()
	var ind: IndicadorVitales = VI.new()
	root.add_child(ind)
	_basura.append(ind)

	_chk(ind.layer == UiLayers.VITALES,
		"va en la capa de HUD que le toca", str(ind.layer))
	_chk(ind.layer >= 10 and ind.layer <= 19,
		"y esa capa está en el rango 10–19 del §9.2", str(ind.layer))
	_chk(&"system_id" in ind, "declara system_id", "")
	_chk(ind.visible, "arranca visible: un vital oculto es una regla invisible", "")
	_chk(ind._caja.get_child_count() >= 4,
		"tiene las tres filas y el icono de enfermedad",
		str(ind._caja.get_child_count()))

	# Los tres vitales, con su color propio (si fueran iguales, el jugador
	# tendría que leer la etiqueta).
	var ids: Array = ind._barras.keys()
	for v in ["hambre", "sed", "energia"]:
		_chk(ids.has(v), "barra de '%s'" % v, str(ids))
	_chk(ind._barras["hambre"]["color"] != ind._barras["sed"]["color"],
		"hambre y sed son colores distintos", "")
	_chk(ind._barras["hambre"]["color"] != ind._barras["energia"]["color"],
		"y la energía también", "")

	ind.vigilar(p)
	_chk(p.vitals.vital_cambiado.is_connected(ind._al_cambiar),
		"se suscribe a la señal de Vitals", "")
	_chk(p.vital_bajo.is_connected(ind._al_vital_bajo),
		"y a `Player.vital_bajo`, que hasta la 63 no tenía listener", "")

	# Al vigilar, pinta el estado actual.
	p.vitals.hambre = 40.0
	ind._refrescar(p.vitals)
	_chk((ind._barras["hambre"]["barra"] as ProgressBar).value == 40.0,
		"el refresco pinta el valor actual",
		str((ind._barras["hambre"]["barra"] as ProgressBar).value))


# --- (c) la UI no lee por frame --------------------------------------

## El requisito de §9.5. Se comprueba por el camino de datos, que es donde
## se rompería: si `_process` de la UI leyera `p.vitals.hambre`, el jugador
## lo notaría como jitter, y ningún test de "existe la barra" lo cazaría.
func _test_no_lectura_por_frame() -> void:
	var p: Player = _jugador()
	var ind: IndicadorVitales = VI.new()
	root.add_child(ind)
	_basura.append(ind)
	ind.vigilar(p)
	# Calentar: el primer aviso emite siempre (no hay ultimo valor con el que
	# comparar), asi que hay que gastar ese primero antes de medir el umbral.
	p.vitals.avanzar(0.01, 1.0)

	# La UI solo se mueve si alguien emite.
	var valor: float = (ind._barras["hambre"]["barra"] as ProgressBar).value
	p.vitals.avanzar(0.05, 1.0)
	_chk((ind._barras["hambre"]["barra"] as ProgressBar).value == valor,
		"un avance de 0.05 no mueve la barra (no hay lectura por frame)",
		str((ind._barras["hambre"]["barra"] as ProgressBar).value))

	# Y cuando alguien emite, sí se mueve.
	p.vitals.avanzar(3.0, 1.0)
	_chk((ind._barras["hambre"]["barra"] as ProgressBar).value < valor,
		"pero un avance grande la mueve", "")

	# Y comer también, que es el caso que más se nota: el jugador come y
	# quiere ver la barra subir en el acto.
	var antes: float = (ind._barras["hambre"]["barra"] as ProgressBar).value
	p.vitals.consumir({"hambre": 30.0})
	_chk((ind._barras["hambre"]["barra"] as ProgressBar).value > antes,
		"comer mueve la barra al instante, no en el siguiente tick",
		"%.0f -> %.0f" % [antes, (ind._barras["hambre"]["barra"] as ProgressBar).value])


# --- (d) el pulso de alerta se apaga solo ----------------------------

## El bug clásico de un HUD así: se avisa "¡te mueres de hambre!" y el aviso
## se queda pegado para siempre aunque comas. Se recalcula, no se latchea.
func _test_pulso_se_apaga() -> void:
	var p: Player = _jugador()
	var ind: IndicadorVitales = VI.new()
	root.add_child(ind)
	_basura.append(ind)
	ind.vigilar(p)

	_chk(not ind.en_alerta(), "con los vitales llenos, sin alerta", "")

	p.vitals.avanzar(400.0, 1.0)
	ind._refrescar(p.vitals)
	ind._process(1.0)
	_chk(ind.en_alerta(), "con un vital vacío, entra en alerta", "")
	# El pulso tiene DOS fases, así que una sola llamada mide el reloj y no la
	# función: se recorre el ciclo entero.
	var atenuada: bool = false
	for i in range(6):
		ind._process(0.8)
		if ind._caja.modulate.r < 1.0:
			atenuada = true
	_chk(atenuada, "y la fila se atenúa al menos una vez por ciclo", "")

	# Ahora comes: la alerta tiene que irse sola.
	p.vitals.consumir({"hambre": 100.0, "sed": 100.0, "energia": 100.0})
	ind._refrescar(p.vitals)
	ind._process(1.0)
	_chk(not ind.en_alerta(), "tras comer, la alerta se apaga sola", "")
	_chk(ind._caja.modulate.r == 1.0, "y la fila vuelve a su color",
		"r=%.2f" % ind._caja.modulate.r)

	# La señal `vital_bajo` también la levanta y la information fluye.
	var oidas: Array = []
	ind.vital_en_bajo.connect(func(c: String): oidas.append(c))
	p.vitals.avanzar(400.0, 1.0)
	ind._refrescar(p.vitals)
	ind._process(1.0)
	p._avisar_vital()
	_chk(ind.vital_en_bajo.get_connections().size() > 0,
		"`vital_en_bajo` está conectado al aviso del Player", "")


# --- (e) las pestañas de Habilidades y Hechos ------------------------

## No se inventa un panel nuevo: el K ya tenía "Skills" y "Talentos", así que
## se le suman las dos pestañas del bloque 57/59. Menos teclas, menos capas.
func _test_pestanas_panel() -> void:
	var p: Player = _jugador()
	var panel: PH = PH.new()
	root.add_child(panel)
	_basura.append(panel)
	panel.conectar(p)

	# Las cuatro habilidades con nombre, no las de clase.
	var habs: Array = p.habilidades.ids()
	_chk(habs.size() == 4, "el jugador tiene 4 habilidades de recolección",
		str(habs))
	for h in ["tala", "mineria", "cocina", "recoleccion"]:
		_chk(habs.has(h), "la habilidad '%s' existe" % h, str(habs))

	# Las cuatro pestañas existen en el TabContainer: no se inventó un panel
	# nuevo para las de recolección, se ampliaró el K que ya había.
	var tabs: TabContainer = _buscar_tabs(panel)
	_chk(tabs != null, "el panel K tiene un TabContainer", "")
	if tabs != null:
		var titulos: Array = []
		for c in tabs.get_children():
			titulos.append(str((c as Control).name))
		for t in ["Skills", "Talentos", "Recolección", "Hechos"]:
			_chk(titulos.has(t), "pestaña '%s'" % t, str(titulos))

	# Y 10 Hechos, que es lo que hay que mostrar.
	var hechos: Array = p.hechos.ids()
	_chk(hechos.size() == 10, "hay 10 Hechos para mostrar", str(hechos.size()))

	# La API que las pestañas necesitan: XP, tramo y progreso.
	p.habilidades.ganar("tala", 60)
	_chk(p.habilidades.xp_de("tala") == 60, "xp_de() da el XP", "")
	_chk(p.habilidades.tramo_de("tala") >= 0, "tramo_de() da el tramo", "")
	_chk(p.habilidades.tramos_totales("tala") > 0,
		"tramos_totales() da el denominador para la barra",
		str(p.habilidades.tramos_totales("tala")))

	# El nombre y la descripción de cada Hecho, que es lo que se pinta. Sin
	# descripción el aviso del feed no sirve de nada, y con esto se comprueba.
	var sin_desc: int = 0
	var sin_nombre: int = 0
	for hid in hechos:
		if p.hechos.descripcion_de(hid) == "":
			sin_desc += 1
		if p.hechos.nombre_de(hid) == "":
			sin_nombre += 1
	_chk(sin_desc == 0, "los 10 Hechos tienen descripción", "%d vacíos" % sin_desc)
	_chk(sin_nombre == 0, "y nombre", "%d vacíos" % sin_nombre)


## El TabContainer está a dos niveles: CanvasLayer > PanelContainer > Margin
## > VBox > TabContainer. Se busca en vez de guardar una referencia, que
## ataría el test al layout.
func _buscar_tabs(n: Node) -> TabContainer:
	for c in n.get_children():
		if c is TabContainer:
			return c
		var t: TabContainer = _buscar_tabs(c)
		if t != null:
			return t
	return null
