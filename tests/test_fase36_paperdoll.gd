extends SceneTree
## Tests headless de la Fase 36 (paper-doll 3D procedural).
##
## Cubre (skills `godot-3d-essentials` + `rpg`: mallas + materiales en
## MeshInstance3D, equipo como datos):
## (a) cableado: el Player trae PaperDoll; desnudo no genera piezas;
## (b) los 6 slots de equipo generan pieza con malla; al desequipar
##     desaparece; la joyería genera gemas doradas emissive;
## (c) si el save reemplaza el objeto Equipo, el muñeco re-suscribe y
##     reconstruye (sin duplicar suscripciones);
## (d) materiales compartidos entre reconstrucciones; puro visual
##     (los stats no cambian al reconstruir).
##
## Cómo correrlo: godot --headless --path <proyecto> --script res://tests/test_fase36_paperdoll.gd

const PL: GDScript = preload("res://scripts/player/player.gd")

var _ok: int = 0
var _fallos: int = 0
var _empezo: bool = false
var _basura: Array = []


func _init() -> void:
	print("[TEST] Fase 36 — paper-doll 3D")


func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_test_cableado()
	_test_piezas()
	_test_joyeria()
	_test_reemplazo()
	_test_materiales()
	print("[TEST] fase36_paperdoll: %d ok, %d fallos" % [_ok, _fallos])
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


func _player() -> Player:
	var p: Player = PL.new()
	p.fijar_identidad("T", "guerrero")
	p.aplicar_clase("guerrero")
	root.add_child(p)
	_basura.append(p)
	return p


func _doll(p: Player) -> PaperDoll:
	return p.get_node("PaperDoll") as PaperDoll


func _equipar(p: Player, item_id: String) -> void:
	p.inventario.agregar(item_id, 1)
	_chk(p.equipo.equipar(item_id, p.stats, p.inventario),
		"setup: equipa " + item_id)


func _mallas(nodo: Node) -> int:
	var n: int = 0
	var pila: Array = [nodo]
	while not pila.is_empty():
		var x: Node = pila.pop_back()
		if x is MeshInstance3D:
			n += 1
		for h in x.get_children():
			pila.append(h)
	return n


## (a) Cableado.
func _test_cableado() -> void:
	var p: Player = _player()
	var d: PaperDoll = _doll(p)
	_chk(d != null, "a: el Player trae PaperDoll")
	_chk(d.get_child_count() == 0, "a: desnudo sin piezas")


## Bloque 67: la pieza de un slot, este donde este. Con anclaje a hueso cuelga
## del `BoneAttachment3D` (bajo el esqueleto) y NO del `PaperDoll`.
func _pieza_de(p: Player, ruta: String) -> Node:
	var partes: PackedStringArray = ruta.split("/")
	var actual: Node = p
	for parte in partes:
		if actual == null:
			return null
		var siguiente: Node = actual.get_node_or_null(parte)
		if siguiente == null:
			siguiente = _buscar(actual, parte)
			if siguiente == null:
				return null
		actual = siguiente
	return actual


func _buscar(n: Node, nombre: String) -> Node:
	for c in n.get_children():
		if c.name == nombre:
			return c
		var r: Node = _buscar(c, nombre)
		if r != null:
			return r
	return null


## (b) Piezas por slot.
func _test_piezas() -> void:
	var p: Player = _player()
	var d: PaperDoll = _doll(p)
	var pares: Array = [["espada_corta", "arma"], ["escudo_madera", "escudo"],
		["casco_cuero", "casco"], ["armadura_cuero", "armadura"],
		["guantes_cuero", "guantes"], ["botas_cuero", "botas"]]
	for par in pares:
		_equipar(p, str(par[0]))
	for par in pares:
		var pieza: Node = _pieza_de(p, str(par[1]))
		_chk(pieza != null, "b: pieza " + str(par[1]))
		_chk(_mallas(pieza) >= 1, "b: %s con malla" % str(par[1]))
	# Bloque 67: las piezas cuelgan del esqueleto (vía BoneAttachment3D), no
	# del PaperDoll, así que se cuenta el subarbol del JUGADOR.
	_chk(_mallas(p) >= 7, "b: al menos 7 mallas con equipo", str(_mallas(p)))
	_chk(p.equipo.desequipar("arma", p.stats, p.inventario), "b: desequipa arma")
	# queue_free es diferido: vale ausente o en cola de borrado.
	var vieja: Node = _pieza_de(p, "arma")
	_chk(vieja == null or vieja.is_queued_for_deletion(),
		"b: la pieza desaparece")


## (c) Joyería emissive.
func _test_joyeria() -> void:
	var p: Player = _player()
	var d: PaperDoll = _doll(p)
	_equipar(p, "anillo_poder")
	_equipar(p, "collar_cobre")
	var anillo: Node = _pieza_de(p, "anillo_1")
	_chk(anillo != null, "c: anillo_1 genera gema")
	var collar: Node = _pieza_de(p, "collar")
	_chk(collar != null, "c: collar genera gema")
	var gema: MeshInstance3D = anillo as MeshInstance3D
	var mat: StandardMaterial3D = gema.material_override as StandardMaterial3D
	_chk(mat != null and mat.emission_enabled, "c: la joyería brilla")


## (d) Reemplazo del objeto Equipo (save/load).
func _test_reemplazo() -> void:
	var p: Player = _player()
	var d: PaperDoll = _doll(p)
	_equipar(p, "espada_corta")
	_chk(_pieza_de(p, "arma") != null, "d: setup con arma")
	var viejo: Equipo = p.equipo
	p.equipo = Equipo.new()
	d._vigilar_equipo(false)
	_chk(d._equipo == p.equipo, "d: re-suscribe al nuevo")
	var sin_arma: Node = _pieza_de(p, "arma")
	_chk(sin_arma == null or sin_arma.is_queued_for_deletion(),
		"d: reconstruye vacío")
	p.inventario.agregar("casco_cuero", 1)
	_chk(p.equipo.equipar("casco_cuero", p.stats, p.inventario), "d: equipa en el nuevo")
	_chk(_pieza_de(p, "casco") != null, "d: el nuevo manda")
	_chk(not viejo.cambiado.is_connected(d.reconstruir),
		"d: el viejo desconectado")


## (e) Materiales compartidos + visual puro.
func _test_materiales() -> void:
	var p: Player = _player()
	var d: PaperDoll = _doll(p)
	_equipar(p, "espada_corta")
	var hoja: MeshInstance3D = d.get_node("arma/Hoja") as MeshInstance3D
	var mat0: Material = hoja.material_override
	d.reconstruir()
	var hoja2: MeshInstance3D = d.get_node("arma/Hoja") as MeshInstance3D
	_chk(hoja2.material_override == mat0, "e: materiales compartidos")
	var atk: float = p.stats.ataque
	d.reconstruir()
	_chk(is_equal_approx(p.stats.ataque, atk), "e: reconstruir no toca stats")
