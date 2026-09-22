extends SceneTree
## Tests headless de la Fase 16 (viaje rápido con NPC portero).
##
## Cubre: data/viaje_rapido.json (9 ciudades, matriz completa 9x8, costos
## y niveles coherentes con el criterio documentado), ViajeRapido
## (evaluar bloquea sin_oro / sin_nivel / en_combate /
## destino_desconocido; viajar descuenta el oro exacto con gastar_oro y
## devuelve la plaza correcta; viaje_id_de_npc), PanelViaje (lógica
## info_filas sin nodos: 8 destinos, bloqueados atenuados con el motivo
## exacto; arranca oculto en capa 29; mostrar/cerrar; ESC cierra) y
## VentanaDialogo (botón "Viajar" solo en porteros; señal
## viaje_solicitado; comerciar intacto en fase 7).
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase16_viaje.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const NP: GDScript = preload("res://scripts/npc/npc.gd")
const NDB: GDScript = preload("res://scripts/npc/npc_db.gd")
const ENT: GDScript = preload("res://scripts/core/entity.gd")
const VJ: GDScript = preload("res://scripts/mundo/viaje_rapido.gd")
const PV: GDScript = preload("res://scripts/ui/panel_viaje.gd")
const DLG: GDScript = preload("res://scripts/ui/ventana_dialogo.gd")
const UL: GDScript = preload("res://scripts/core/ui_layers.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _viajes_pedidos: Array = []


func _init() -> void:
	print("[TEST] Fase 16 — Viaje rapido con NPC portero")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b): todo lo que
## usa global_position o get_tree() corre aquí.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	NDB.cargar()
	_t_json()
	_t_evaluar()
	_t_viajar()
	_t_viaje_id_npc()
	_t_panel_logica()
	_t_panel_nodos()
	_t_dialogo_viajar()
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


func _player(nivel: int, oro: int) -> Player:
	var p: Player = PL.new()
	root.add_child(p)
	p.nivel = nivel
	p.ganar_oro(oro)
	_basura.append(p)
	return p


func _npc(id: String) -> NPC:
	var n: NPC = NP.new()
	root.add_child(n)
	n.configurar(NDB.obtener(id))
	_basura.append(n)
	return n


func _viaje() -> ViajeRapido:
	# RefCounted: no va a _basura (el conteo de referencias lo libera;
	# queue_free() sobre un "as Node" nulo abortaría el _process).
	return VJ.new()


## --- JSON: 9 ciudades, matriz completa, costos/niveles coherentes ---


func _t_json() -> void:
	var v: ViajeRapido = _viaje()
	_check(v.cargar_datos(), "json: cargar_datos ok")
	var ids: Array[String] = v.ciudades()
	_check(ids.size() == 9, "json: 9 ciudades", str(ids.size()))
	var esperadas: Array = ["moon_town", "desert", "fire", "north", "mystic",
		"shadow", "rage", "fury", "golden"]
	for e in esperadas:
		_check(ids.has(e), "json: ciudad " + e)
	# Nivel mínimo = nivel_min de su región (data/regiones.json).
	var nmin: Dictionary = {"moon_town": 1, "desert": 4, "fire": 10,
		"north": 12, "mystic": 12, "shadow": 22, "rage": 26, "fury": 30,
		"golden": 36}
	for e in esperadas:
		_check(v.nivel_min_ciudad(e) == int(nmin[e]),
			"json: nivel_min %s = %d" % [e, int(nmin[e])])
	# Plazas: punto de aparición de cada ciudad (aparicion_jugador + centro).
	_check(v.plaza_de("moon_town") == Vector2(0, 45), "json: plaza moon_town")
	_check(v.plaza_de("golden") == Vector2(9966, 10011), "json: plaza golden")
	_check(v.nombre_ciudad("fury") == "Fury Town", "json: nombre fury")
	# Matriz: 8 destinos por origen, sin el propio, sin duplicados.
	for o in esperadas:
		var dests: Array = v.destinos_desde(o)
		_check(dests.size() == 8, "json: 8 destinos desde " + o,
			str(dests.size()))
		var vistos: Array = []
		for d in dests:
			var dd: Dictionary = d
			var did: String = str(dd.get("destino_id", ""))
			_check(did != o, "json: %s no se lista a sí misma" % o)
			_check(esperadas.has(did), "json: destino conocido " + did)
			_check(not vistos.has(did), "json: sin duplicados " + did)
			vistos.append(did)
			# TEMPORAL: con GRATIS_TEMPORAL destinos_desde devuelve costo 0
			# (el JSON conserva los costos reales, sin tocar).
			if VJ.GRATIS_TEMPORAL:
				_check(int(dd.get("costo_oro", -1)) == 0,
					"json: GRATIS_TEMPORAL costo=0 %s->%s" % [o, did])
			else:
				_check(int(dd.get("costo_oro", 0)) > 0,
					"json: costo>0 %s->%s" % [o, did])
			_check(int(dd.get("nivel_min", 0)) == int(nmin[did]),
				"json: nivel_min coherente %s->%s" % [o, did])
	# Coherencia del criterio: más lejos / banda mayor => más caro.
	# TEMPORAL: con GRATIS_TEMPORAL ambos son 0.
	if VJ.GRATIS_TEMPORAL:
		_check(v.costo("moon_town", "golden") == 0
			and v.costo("moon_town", "desert") == 0,
			"json: GRATIS_TEMPORAL costos = 0")
	else:
		_check(v.costo("moon_town", "golden") > v.costo("moon_town", "desert"),
			"json: golden más caro que desert desde moon")
	_check(v.costo("moon_town", "moon_town") == -1,
		"json: costo a sí misma = -1 (desconocido)")
	_check(v.destinos_desde("atlantis").is_empty(),
		"json: origen desconocido = sin destinos")


## --- evaluar: bloqueos ---


func _t_evaluar() -> void:
	var v: ViajeRapido = _viaje()
	v.cargar_datos()
	# Destino desconocido (aunque el jugador pueda pagarlo todo).
	var rico: Player = _player(60, 99999)
	var ev: Dictionary = v.evaluar(rico, "moon_town", "atlantis")
	_check(not bool(ev.get("ok", true)) and str(ev.get("motivo", "")) == "destino_desconocido",
		"evaluar: destino_desconocido")
	ev = v.evaluar(rico, "atlantis", "desert")
	_check(str(ev.get("motivo", "")) == "destino_desconocido",
		"evaluar: origen desconocido")
	# Sin nivel (nivel 1 no entra a golden: Nv. 36).
	var novato: Player = _player(1, 99999)
	ev = v.evaluar(novato, "moon_town", "golden")
	_check(not bool(ev.get("ok", true)) and str(ev.get("motivo", "")) == "sin_nivel",
		"evaluar: sin_nivel bloquea")
	_check(int(ev.get("nivel_min", 0)) == 36, "evaluar: nivel_min golden = 36")
	_check(VJ.texto_motivo(ev) == "Requiere nivel 36",
		"evaluar: texto 'Requiere nivel 36'")
	# Sin oro (nivel 10 sí puede ir a desert: Nv. 4, 160 oro).
	# TEMPORAL: con GRATIS_TEMPORAL el viaje es gratis y no bloquea por oro.
	var pelado: Player = _player(10, 0)
	ev = v.evaluar(pelado, "moon_town", "desert")
	if VJ.GRATIS_TEMPORAL:
		_check(bool(ev.get("ok", false)),
			"evaluar: GRATIS_TEMPORAL: sin oro viaja igual")
		_check(int(ev.get("costo", -1)) == 0,
			"evaluar: GRATIS_TEMPORAL: costo = 0")
	else:
		_check(not bool(ev.get("ok", true)) and str(ev.get("motivo", "")) == "sin_oro",
			"evaluar: sin_oro bloquea")
		_check(int(ev.get("oro_faltante", 0)) == v.costo("moon_town", "desert"),
			"evaluar: oro_faltante = costo exacto")
		_check(VJ.texto_motivo(ev) == "Te faltan %d de oro" % v.costo("moon_town", "desert"),
			"evaluar: texto 'Te faltan X de oro'")
	# El nivel se revisa antes que el oro (nivel 1, oro 0 -> sin_nivel).
	ev = v.evaluar(_player(1, 0), "moon_town", "desert")
	_check(str(ev.get("motivo", "")) == "sin_nivel",
		"evaluar: sin_nivel tiene prioridad sobre sin_oro")
	# En combate (objetivo_ataque != null).
	var guerrero: Player = _player(60, 99999)
	var dummy: Entity = ENT.new()
	root.add_child(dummy)
	_basura.append(dummy)
	guerrero.objetivo_ataque = dummy
	ev = v.evaluar(guerrero, "moon_town", "desert")
	_check(not bool(ev.get("ok", true)) and str(ev.get("motivo", "")) == "en_combate",
		"evaluar: en_combate bloquea")
	_check(VJ.texto_motivo(ev) == "No puedes viajar en combate",
		"evaluar: texto en_combate")
	guerrero.objetivo_ataque = null
	# Caso ok.
	ev = v.evaluar(rico, "moon_town", "desert")
	_check(bool(ev.get("ok", false)) and str(ev.get("motivo", "")) == "",
		"evaluar: viaje válido = ok")
	_check(VJ.texto_motivo(ev) == "", "evaluar: texto vacío si ok")


## --- viajar: descuenta el oro exacto, devuelve plaza ---


func _t_viajar() -> void:
	var v: ViajeRapido = _viaje()
	v.cargar_datos()
	# TEMPORAL: con GRATIS_TEMPORAL el costo es 0; si no, 360 (Nv. 22).
	var costo_esperado: int = 0 if VJ.GRATIS_TEMPORAL else 360
	var costo: int = v.costo("moon_town", "shadow")  # 360, Nv. 22
	_check(costo == costo_esperado, "viajar: costo moon->shadow",
		"costo=%d esperado=%d" % [costo, costo_esperado])
	var p: Player = _player(40, 1000)
	var res: Dictionary = v.viajar(p, "moon_town", "shadow")
	_check(bool(res.get("ok", false)), "viajar: ok")
	_check(str(res.get("destino", "")) == "shadow", "viajar: destino shadow")
	_check(p.oro == 1000 - costo, "viajar: descuenta el oro exacto",
		"oro=%d esperado=%d" % [p.oro, 1000 - costo])
	_check(res.get("plaza", Vector2.ZERO) == Vector2(9966, -9921),
		"viajar: plaza de shadow correcta")
	_check(int(res.get("costo", 0)) == costo, "viajar: devuelve el costo")
	# Sin oro: con GRATIS_TEMPORAL viaja igual; si no, falla sin descontar.
	var pelado: Player = _player(40, 0)
	res = v.viajar(pelado, "moon_town", "shadow")
	if VJ.GRATIS_TEMPORAL:
		_check(bool(res.get("ok", false)), "viajar: GRATIS_TEMPORAL: sin oro viaja")
		_check(pelado.oro == 0, "viajar: GRATIS_TEMPORAL: oro intacto")
	else:
		_check(not bool(res.get("ok", true)), "viajar: sin oro falla")
		_check(pelado.oro == 0, "viajar: sin oro no descuenta")
		_check(str(res.get("motivo", "")) == "sin_oro", "viajar: motivo sin_oro")
	# En combate: re-evalúa y no descuenta.
	var g: Player = _player(40, 1000)
	var dummy: Entity = ENT.new()
	root.add_child(dummy)
	_basura.append(dummy)
	g.objetivo_ataque = dummy
	res = v.viajar(g, "moon_town", "shadow")
	_check(not bool(res.get("ok", true)) and str(res.get("motivo", "")) == "en_combate",
		"viajar: en combate re-evalúa y falla")
	_check(g.oro == 1000, "viajar: en combate no descuenta")
	# Destino desconocido: no toca el oro.
	res = v.viajar(p, "moon_town", "atlantis")
	_check(not bool(res.get("ok", true)), "viajar: destino desconocido falla")
	_check(p.oro == 1000 - costo, "viajar: destino desconocido no descuenta")


## --- viaje_id_de_npc ---


func _t_viaje_id_npc() -> void:
	_check(VJ.viaje_id_de_npc("portero_moon_town") == "moon_town",
		"npc: viaje_id portero_moon_town")
	_check(VJ.viaje_id_de_npc("portero_golden") == "golden",
		"npc: viaje_id portero_golden")
	_check(VJ.viaje_id_de_npc("bram") == "", "npc: bram sin viaje_id")
	_check(VJ.viaje_id_de_npc("ilya") == "", "npc: ilya sin viaje_id")
	_check(VJ.viaje_id_de_npc("") == "", "npc: id vacío")
	_check(VJ.viaje_id_de_npc("no_existe") == "", "npc: id desconocido")


## --- PanelViaje: lógica sin nodos ---


func _t_panel_logica() -> void:
	var pv: PanelViaje = PV.new()
	_basura.append(pv)
	# Jugador pobre de nivel 1: todo bloqueado, motivos exactos.
	var novato: Player = _player(1, 0)
	var filas: Array = pv.info_filas("moon_town", novato)
	_check(filas.size() == 8, "panel: 8 destinos en info_filas")
	var por_id: Dictionary = {}
	for f in filas:
		var fd: Dictionary = f
		por_id[str(fd.get("destino_id", ""))] = fd
	var desert: Dictionary = por_id.get("desert", {})
	_check(not bool(desert.get("ok", true)), "panel: desert bloqueado (Nv.1)")
	_check(str(desert.get("motivo", "")) == "sin_nivel",
		"panel: motivo sin_nivel en desert")
	_check(str(desert.get("motivo_texto", "")) == "Requiere nivel 4",
		"panel: texto 'Requiere nivel 4'")
	var golden: Dictionary = por_id.get("golden", {})
	_check(str(golden.get("motivo_texto", "")) == "Requiere nivel 36",
		"panel: texto 'Requiere nivel 36'")
	# Nivel 10 sin oro: con GRATIS_TEMPORAL desert está desbloqueado;
	# si no, bloqueado por oro con el texto exacto.
	var pelado: Player = _player(10, 0)
	filas = pv.info_filas("moon_town", pelado)
	por_id.clear()
	for f in filas:
		var fd2: Dictionary = f
		por_id[str(fd2.get("destino_id", ""))] = fd2
	desert = por_id.get("desert", {})
	if VJ.GRATIS_TEMPORAL:
		_check(bool(desert.get("ok", false)),
			"panel: GRATIS_TEMPORAL: desert desbloqueado sin oro")
		_check(int(desert.get("costo_oro", -1)) == 0,
			"panel: GRATIS_TEMPORAL: costo_oro = 0")
	else:
		_check(str(desert.get("motivo", "")) == "sin_oro",
			"panel: motivo sin_oro en desert")
		_check(str(desert.get("motivo_texto", "")) == "Te faltan 160 de oro",
			"panel: texto 'Te faltan 160 de oro'")
	# Jugador top: todo alcanzable.
	var top: Player = _player(60, 99999)
	filas = pv.info_filas("moon_town", top)
	var todos_ok: bool = true
	for f in filas:
		if not bool((f as Dictionary).get("ok", false)):
			todos_ok = false
	_check(todos_ok and filas.size() == 8, "panel: top desbloquea los 8")
	# Origen desconocido: sin filas.
	_check(pv.info_filas("atlantis", top).is_empty(),
		"panel: origen desconocido = sin filas")


## --- PanelViaje: nodos mínimos ---


func _t_panel_nodos() -> void:
	var pv: PanelViaje = PV.new()
	root.add_child(pv)
	_basura.append(pv)
	_check(not pv.esta_abierta(), "panel: arranca oculto (lección 11)")
	_check(pv.layer == UL.PANEL_VIAJE, "panel: capa 29 (rango 20-69)")
	_check(UL.PANEL_VIAJE == 29, "panel: PANEL_VIAJE = 29")
	var p: Player = _player(60, 99999)
	pv.mostrar("moon_town", p)
	_check(pv.esta_abierta(), "panel: mostrar abre")
	_check(pv.origen_actual() == "moon_town", "panel: origen_actual")
	_check(pv.info_actual().size() == 8, "panel: info_actual con 8 destinos")
	# mostrar con origen desconocido no abre ni revienta.
	pv.cerrar_panel()
	pv.mostrar("atlantis", p)
	_check(not pv.esta_abierta(), "panel: origen desconocido no abre")
	pv.mostrar("moon_town", p)
	# ESC (cancelar_seleccion) cierra el panel.
	var esc: InputEventAction = InputEventAction.new()
	esc.action = "cancelar_seleccion"
	esc.pressed = true
	pv._input(esc)
	_check(not pv.esta_abierta(), "panel: ESC cierra")
	# Cerrado: _input no toca nada.
	pv._input(esc)
	_check(not pv.esta_abierta(), "panel: _input cerrada no reabre")


## --- VentanaDialogo: botón Viajar solo en porteros ---


func _al_viaje(npc: NPC) -> void:
	_viajes_pedidos.append(npc)


func _t_dialogo_viajar() -> void:
	var d: VentanaDialogo = DLG.new()
	root.add_child(d)
	_basura.append(d)
	# Portero: hay botón Viajar y la señal se emite (y cierra el diálogo).
	var portero: NPC = _npc("portero_moon_town")
	d.mostrar(portero)
	_check(d.tiene_viajar(), "dialogo: portero muestra Viajar")
	_check(not d.tiene_comerciar(), "dialogo: portero sin Comerciar")
	_check(d.titulo_texto() == "Portero Anselmo",
		"dialogo: portero muestra su nombre")
	d.viaje_solicitado.connect(_al_viaje)
	d._al_viajar()
	_check(_viajes_pedidos.size() == 1 and _viajes_pedidos[0] == portero,
		"dialogo: viajar emite la señal con el npc")
	_check(not d.esta_abierta(), "dialogo: viajar cierra el dialogo")
	# Bram (vendedor, fase 7): Comerciar sí, Viajar no (fase 7 intacta).
	var d2: VentanaDialogo = DLG.new()
	root.add_child(d2)
	_basura.append(d2)
	d2.mostrar(_npc("bram"))
	_check(d2.tiene_comerciar(), "dialogo: bram sigue con Comerciar (fase 7)")
	_check(not d2.tiene_viajar(), "dialogo: bram sin Viajar")
	d2.cerrar()
	# Ilya (ni tienda ni viaje): ningún botón extra (fase 6 intacta).
	var d3: VentanaDialogo = DLG.new()
	root.add_child(d3)
	_basura.append(d3)
	d3.mostrar(_npc("ilya"))
	_check(not d3.tiene_comerciar(), "dialogo: ilya sin Comerciar")
	_check(not d3.tiene_viajar(), "dialogo: ilya sin Viajar")
	d3.cerrar()
