extends SceneTree
## Fase 64 — que se pueda usar: fogata, cocina, refugio y construcción.
##
## POR QUÉ ESTE ARCHIVO: hasta la 63 el bloque 53–62 tenía la lógica entera y
## testersa, pero `Fogata.cargar_lena()`, `Refugio.reclamar()` y
## `Constructor` no los llamaba NADA fuera de los tests. Aquí se comprueba que
## el camino de juego existe: E prende la fogata, E cocina, E reclama, y C
## construye.
##
## Y sobre todo se comprueba lo caro de romper: que los MATERIALES se gasten
## de verdad. `Constructor.descontar` muta una copia del inventario, y si nadie
## vuelca esa copia al `Inventario` real las piezas salen gratis. Ese era el
## agujero que tenía el panel al escribirse.

const PL: GDScript = preload("res://scripts/player/player.gd")
const FG: GDScript = preload("res://scripts/mundo/fogata.gd")
const RF: GDScript = preload("res://scripts/mundo/refugio.gd")
const PV: GDScript = preload("res://scripts/mundo/pieza_visual.gd")
const PC: GDScript = preload("res://scripts/ui/panel_cocina.gd")
const PB: GDScript = preload("res://scripts/ui/panel_construccion.gd")
const PI: GDScript = preload("res://scripts/ui/prompt_interaccion.gd")
const CD: GDScript = preload("res://scripts/mundo/recetas_cocina_db.gd")
const PDB: GDScript = preload("res://scripts/mundo/piezas_db.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 64 — Que se pueda usar")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_alcance()
	_test_fogata()
	_test_cocina()
	_test_refugio()
	_test_respawn()
	_test_construccion()
	_test_materiales()
	_test_prompt()
	print("[TEST] fase64_uso: %d ok, %d fallos" % [_ok, _fallos])
	PV.limpiar_cache()
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
	p.nivel = 60
	p.ganar_oro(500)
	return p


func _fogata(pos: Vector3 = Vector3.ZERO) -> Fogata:
	var f: Fogata = FG.new()
	f.global_position = pos
	root.add_child(f)
	_basura.append(f)
	return f


## Un refugio REAL del catálogo: el nivel mínimo viene del dato, no de un
## override, para que el test no se pruebe a sí mismo con una propiedad que
## solo existe en el test.
func _refugio(id: String = "refugio_moon_town") -> Refugio:
	var r: Refugio = RF.new()
	root.add_child(r)
	_basura.append(r)
	r.configurar_por_id(id)
	return r


# --- (a) el alcance de la mano ---------------------------------------

func _test_alcance() -> void:
	var p: Player = _jugador()
	var f: Fogata = _fogata(Vector3(p.global_position.x + 2.0, 0.0, 0.0))
	_chk(p._interactuable_mas_cercano() == f,
		"la fogata a 2 m está al alcance", "")

	var lejos: Fogata = _fogata(Vector3(p.global_position.x + 40.0, 0.0, 0.0))
	_chk(p._interactuable_mas_cercano() == f,
		"la de 40 m no compite", "")
	lejos.queue_free()

	# Y que la E del jugador la use de verdad, sin selección de por medio.
	var otro: Fogata = _fogata(Vector3(p.global_position.x + 2.5, 0.0, 0.0))
	p.seleccion = null
	p.inventario.agregar("tronco_roble", 1)
	p.interactuar()
	_chk(f.encendida() and not otro.encendida(),
		"y la E prende la MÁS CERCANA, no cualquiera",
		"f=%s otro=%s" % [f.encendida(), otro.encendida()])


# --- (b) la fogata ---------------------------------------------------

func _test_fogata() -> void:
	var p: Player = _jugador()
	var f: Fogata = _fogata()
	_chk(f.is_in_group(Player.GRUPO_INTERACTUABLE),
		"la fogata está en el grupo de interactuables", "")

	# Apagada y sin leña: no se puede.
	_chk(f.interactuar_jugador(p) == "sin_lena",
		"sin troncos, no se prende", "")
	_chk(not f.encendida(), "y sigue apagada", "")

	# Con un tronco: se prende y GASTA el tronco.
	p.inventario.agregar("tronco_roble", 2)
	var leña_antes: int = p.inventario.contar("tronco_roble")
	_chk(f.interactuar_jugador(p) == "ok", "con tronco, se prende", "")
	_chk(f.encendida(), "queda encendida", "")
	_chk(p.inventario.contar("tronco_roble") == leña_antes - 1,
		"y GASTA un tronco (no lo clona)", "")
	_chk(f.lena > 0.0, "con leña", str(f.lena))

	# Encendida, la E ya no prende: pide cocinar.
	_chk(f.interactuar_jugador(p) == "cocinar",
		"encendida, la E pide cocinar en vez de prender", "")

	# Las otras especies de tronco también valen: la tala da madera varied.
	var p2: Player = _jugador()
	var f2: Fogata = _fogata()
	p2.inventario.agregar("tronco_sauce", 1)
	_chk(f2.interactuar_jugador(p2) == "ok",
		"un tronco de sauce también sirve (la tala da de varias especies)", "")

	# Y el texto del prompt cambia con el estado.
	_chk(f.texto_interaccion(p) == "Cocinar",
		"encendida, el prompt dice 'Cocinar'", f.texto_interaccion(p))
	var p3: Player = _jugador()
	var f3: Fogata = _fogata()
	_chk(f3.texto_interaccion(p3) == "Fogata (sin leña)",
		"sin leña, avisa que no hay", f3.texto_interaccion(p3))
	p3.inventario.agregar("tronco_roble", 1)
	_chk(f3.texto_interaccion(p3) == "Prender fogata",
		"con tronco, ofrece prenderla", f3.texto_interaccion(p3))


# --- (c) la cocina: el círculo completo ------------------------------

func _test_cocina() -> void:
	CD.cargar()
	var p: Player = _jugador()
	var f: Fogata = _fogata()
	var panel: PC = PC.new()
	root.add_child(panel)
	_basura.append(panel)

	_chk(panel.layer == UiLayers.PANEL_COCINA, "en su capa de panel", "")
	_chk(not panel.esta_abierta(), "arranca CERRADO (lección 11)", "")

	# Sin fogata no abre: no hay dónde gastar la leña.
	_chk(not panel.abrir(p, null), "no abre sin fogata", "")

	# Fogata apagada: no se puede cocinar aunque tengas la carne.
	p.inventario.agregar("carne_cruda_lobo", 3)
	_chk(panel.abrir(p, f), "abre con fogata", "")
	_chk(panel.esta_abierta(), "y queda abierta", "")

	# Se prende y se cocina DE VERDAD, por la API del panel.
	f.cargar_lena(60.0)
	var carne_antes: int = p.inventario.contar("carne_cruda_lobo")
	var asado_antes: int = p.inventario.contar("carne_asada_lobo")
	var xp_antes: int = p.habilidades.xp_de("cocina")
	panel._reconstruir()
	panel._al_cocinar("carne_cruda_lobo")

	_chk(p.inventario.contar("carne_cruda_lobo") == carne_antes - 1,
		"cocinar GASTA el ingrediente", str(p.inventario.contar("carne_cruda_lobo")))
	_chk(p.inventario.contar("carne_asada_lobo") == asado_antes + 1,
		"y ENTREGA el asado (esto antes no pasaba de ningún lado)",
		str(p.inventario.contar("carne_asada_lobo")))
	_chk(p.habilidades.xp_de("cocina") > xp_antes,
		"y sube la habilidad de cocina (fase 57)",
		str(p.habilidades.xp_de("cocina")))
	_chk(f.lena < 60.0, "y gasta leña de la fogata", str(f.lena))

	# El item cocinado no enferma: ese es TODO el punto de cocinar.
	ItemDB.cargar()
	var cocido: Dictionary = ItemDB.obtener("carne_asada_lobo")
	_chk(str(cocido.get("riesgo", "")) != "enfermedad",
		"el asado NO enferma (la carne cruda sí)", str(cocido.get("riesgo", "")))

	panel.cerrar_panel()
	_chk(not panel.esta_abierta(), "ESC cierra", "")


# --- (d) el refugio se reclama jugando --------------------------------

func _test_refugio() -> void:
	var p: Player = _jugador()
	var r: Refugio = _refugio()
	_chk(r.is_in_group(Player.GRUPO_INTERACTUABLE),
		"el refugio está en el grupo de interactuables", "")

	_chk(r.texto_interaccion(p) == "Reclamar refugio",
		"el prompt ofrece reclamarlo", r.texto_interaccion(p))
	_chk(r.interactuar_jugador(p) == "ok", "la E lo reclama", "")
	_chk(r.esta_reclamado(), "y queda reclamado", "")

	# Reclamado, la E ya no reclama: construye.
	_chk(r.interactuar_jugador(p) == "construir",
		"reclamado, la E pasa a construir", "")

	# Un refugio de nivel alto no se puede reclamar con un nivel bajo.
	var p2: Player = _jugador()
	p2.nivel = 1
	# El refugio dorado pide nivel 36 de verdad.
	var r2: Refugio = _refugio("refugio_golden")
	_chk(r2.nivel_minimo() == 36, "el dorado pide nivel 36", str(r2.nivel_minimo()))
	_chk(r2.interactuar_jugador(p2) == "nivel",
		"uno de nivel 50 no se reclama con nivel 1", "")
	_chk(not r2.esta_reclamado(), "y sigue sin reclamar", "")
	_chk(r2.texto_interaccion(p2) == "Refugio (nivel 36)",
		"y el prompt avisa del nivel que falta", r2.texto_interaccion(p2))


# --- (e) el refugio cambia el punto seguro ---------------------------

## El bug que dejó la 60 abierta: reclamar no movía el ancla, así que el
## refugio era un adorno.
func _test_respawn() -> void:
	var RH: GDScript = preload("res://scripts/mundo/respawn_heroe.gd")
	var p: Player = _jugador()
	var res: Node = RH.new()
	root.add_child(res)
	_basura.append(res)
	res.configurar(p)
	res.registrar_ciudad("moon_town", Vector3(0, 40, 0), 0.0)

	var r: Refugio = _refugio()
	r.global_position = Vector3(0, 40, 45)
	_chk(res._refugios.is_empty(), "sin anclar, no hay refugios registrados", "")

	# Sin reclamar, el refugio NO es punto seguro.
	res.anclar_refugio(r)
	p.global_position = r.global_position
	res.actualizar_ancla()
	_chk(p.ancla().distance_to(r.global_position) > 0.1,
		"sin reclamar, el refugio NO mueve el ancla", str(p.ancla()))

	# Reclamado, sí.
	r.reclamar(1)
	res.actualizar_ancla()
	_chk(p.ancla().distance_to(r.global_position) < 0.1,
		"reclamado, el refugio ES el punto seguro", str(p.ancla()))

	# Y si se va a otra ciudad, el ancla va con él (es la fase 51): el
	# refugio deja de mandar en cuanto no estás dentro.
	res.registrar_ciudad("desert", Vector3(9966, 40, 0), 0.0)
	p.global_position = Vector3(9966, 40, 0)
	res.actualizar_ancla()
	_chk(p.ancla().distance_to(Vector3(9966, 40, 0)) < 0.1,
		"al caminar a otra ciudad, el ancla la sigue", str(p.ancla()))
	# Lejos de toda ciudad, el ancla se QUEDA donde estaba: no hay adónde
	# mandar al jugador, y mandarlo al origen del mundo es lo que la 51
	# arregló.
	var quieta: Vector3 = p.ancla()
	p.global_position = Vector3(30000, 40, 30000)
	res.actualizar_ancla()
	_chk(p.ancla().distance_to(quieta) < 0.1,
		"lejos de todo, el ancla no se mueve sola", str(p.ancla()))


# --- (f) construcción: la lógica de la 61, con UI ---------------------

func _test_construccion() -> void:
	PDB.cargar()
	var p: Player = _jugador()
	var r: Refugio = _refugio()
	var panel: PB = PB.new()
	root.add_child(panel)
	_basura.append(panel)

	_chk(panel.layer == UiLayers.PANEL_CONSTRUCCION, "en su capa de panel", "")
	# Un refugio SIN reclamar no abre: no hay presupuesto de piezas.
	_chk(not panel.abrir(p, r), "no abre sobre un refugio sin reclamar", "")

	r.reclamar(1)
	_chk(panel.abrir(p, r), "abre sobre uno reclamado", "")
	_chk(panel.esta_abierta(), "y queda abierto", "")

	# Selección y fantasma.
	panel.seleccionar("antorcha")
	_chk(panel._fantasma != null, "seleccionar crea el fantasma", "")
	_chk(panel._fantasma.fantasma, "que es fantasma, no pieza real", "")

	# Rotación: la antorcha NO admite rotación (el dato manda).
	panel.rotar()
	_chk(is_zero_approx(panel._rot),
		"una pieza que no rota no rota", str(panel._rot))
	panel.seleccionar("mesa")
	panel.rotar()
	_chk(not is_zero_approx(panel._rot), "una que sí, rota", str(panel._rot))

	# Colocación. La Antorcha cuesta 1 tronco de roble.
	p.inventario.agregar("tronco_roble", 20)
	panel.seleccionar("antorcha")
	var pos: Vector3 = r.global_position + Vector3(4.0, 0.0, 0.0)
	var antes: int = r.piezas()
	var motivo: String = panel.colocar_en(pos)
	_chk(motivo == "ok", "coloca una pieza válida", motivo)
	_chk(r.piezas() == antes + 1, "y el refugio la cuenta", str(r.piezas()))
	_chk(panel._visuales.size() == antes + 1,
		"y se instancia su malla 3D (esto antes no pasaba)", str(panel._visuales.size()))

	# Fuera del radio del refugio: no.
	_chk(panel.colocar_en(r.global_position + Vector3(9999.0, 0.0, 0.0)) == "no_puede",
		"lejos del refugio, no se puede", "")

	# Deshacer devuelve la pieza Y los materiales.
	var troncos: int = p.inventario.contar("tronco_roble")
	panel.seleccionar("estante")  # 5 de tronco_roble
	panel.colocar_en(r.global_position + Vector3(8.0, 0.0, 0.0))
	_chk(p.inventario.contar("tronco_roble") < troncos,
		"el estante gastó 5 troncos", str(p.inventario.contar("tronco_roble")))
	panel.quitar_ultima()
	_chk(p.inventario.contar("tronco_roble") == troncos,
		"y deshacer los devuelve (si no, se perdían para siempre)",
		str(p.inventario.contar("tronco_roble")))

	panel.cerrar_panel()
	_chk(not panel.esta_abierta(), "ESC cierra", "")
	_chk(panel._visuales.is_empty(), "y las mallas se liberan", "")


# --- (g) EL AGUJERO: los materiales tienen que gastarse de verdad ----

## `Constructor.descontar` muta el Dictionary que se le pasa, y el panel le
## pasa una COPIA del inventario. Si no se vuelca la diferencia al `Inventario`
## real, la pieza se coloca y el material no se descuenta: la construcción
## entera sale gratis.
func _test_materiales() -> void:
	PDB.cargar()
	var p: Player = _jugador()
	var r: Refugio = _refugio()
	var panel: PB = PB.new()
	root.add_child(panel)
	_basura.append(panel)
	r.reclamar(1)
	panel.abrir(p, r)

	# Materiales JUSTOS para una columna (6 mineral_cobre + 2 tronco_roble).
	p.inventario.agregar("mineral_cobre", 6)
	p.inventario.agregar("tronco_roble", 2)
	var cobre: int = p.inventario.contar("mineral_cobre")
	var tronco: int = p.inventario.contar("tronco_roble")
	panel.seleccionar("columna")
	var motivo: String = panel.colocar_en(r.global_position + Vector3(10.0, 0.0, 0.0))
	_chk(motivo == "ok", "coloca la columna con material justo", motivo)
	_chk(p.inventario.contar("mineral_cobre") == cobre - 6,
		"DESCUENTA los 6 de mineral_cobre del inventario REAL",
		"%d -> %d" % [cobre, p.inventario.contar("mineral_cobre")])
	_chk(p.inventario.contar("tronco_roble") == tronco - 2,
		"y los 2 de tronco_roble", "%d -> %d" % [tronco, p.inventario.contar("tronco_roble")])

	# Sin material, no coloca NADA: ni pieza ni gasto.
	panel.seleccionar("yunque")  # 4 de mineral_cobre
	var piezas_antes: int = r.piezas()
	var cobre2: int = p.inventario.contar("mineral_cobre")
	_chk(panel.colocar_en(r.global_position + Vector3(12.0, 0.0, 0.0)) == "sin_materiales",
		"sin material, no se puede", "")
	_chk(r.piezas() == piezas_antes, "y no se coloca la pieza", "")
	_chk(p.inventario.contar("mineral_cobre") == cobre2,
		"y no se toca el inventario", "")


# --- (h) el prompt contextual ----------------------------------------

## Los tests anteriores dejaron fogatas y refugios en escena (la limpieza es
## al final de todo, para no perder referencias). El escaneo de proximidad los
## encuentra, así que hay que despejar el grupo: si no, este test mide el
## estado de una fogata de hace tres tests.
func _limpiar_grupo_interactuable() -> void:
	for n in get_nodes_in_group(Player.GRUPO_INTERACTUABLE):
		var nd: Node = n as Node
		if nd != null and is_instance_valid(nd):
			# `remove_from_group` INMEDIATO, no `queue_free`: el free se
			# difiere al final del frame, así que durante este frame el escaneo
			# de proximidad seguiría viendo los nodos viejos.
			nd.remove_from_group(Player.GRUPO_INTERACTUABLE)
			nd.queue_free()


func _test_prompt() -> void:
	_limpiar_grupo_interactuable()
	var p: Player = _jugador()
	var pr: PI = PI.new()
	root.add_child(pr)
	_basura.append(pr)

	_chk(pr.layer == UiLayers.PROMPT, "en la capa de prompt", "")
	_chk(not pr.mostrado(), "arranca oculto (no hay nada que prometer)", "")

	# Con algo al alcance, aparece.
	var f: Fogata = _fogata(p.global_position + Vector3(1.5, 0.0, 0.0))
	pr.vigilar(p)
	p._tick_interactuable(1.0)
	_chk(pr.mostrado(), "al acercarse a la fogata, el prompt aparece", "")
	_chk(pr.texto() != "", "con texto", pr.texto())

	# Al alejarse, se va (después de la gracia).
	f.global_position = Vector3(9000.0, 0.0, 9000.0)
	p._reloj_interactuable = 0.0
	p._tick_interactuable(1.0)
	# Se oculta en el `_process` del PROMPT, con su gracia, no en el del jugador.
	_chk(pr.mostrado(), "al alejarse, aguanta la gracia (no parpadea)", "")
	pr._process(1.0)
	_chk(not pr.mostrado(), "y al pasar la gracia, desaparece", "")

	# Y la acción del Input Map existe: la regla §5.3/§9.3 es que ningún
	# atajo se compara con un keycode en el código.
	_chk(InputMap.has_action("construir"),
		"la acción 'construir' está en el Input Map", "")
	var eventos: Array = InputMap.action_get_events("construir")
	_chk(eventos.size() > 0, "y tiene tecla", "")
