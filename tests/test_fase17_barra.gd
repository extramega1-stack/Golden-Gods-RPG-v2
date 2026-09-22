extends SceneTree
## Tests headless de la Fase 17 (barra de acciones estilo Flyff).
##
## Cómo correrlos (un solo comando):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_fase17_barra.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)
##
## Cubre: validar_datos, layout por defecto, asignar/limpiar/obtener,
## intercambio entre slots, ejecutar (skill/item/ataque) y persistencia
## (to_dict/cargar_estado, ids inválidos descartados). El drag & drop real
## con el ratón se valida en el playtest de Juan Diego.

const BA: GDScript = preload("res://scripts/ui/barra_acciones.gd")
const SDB: GDScript = preload("res://scripts/skills/skill_db.gd")
const IDB: GDScript = preload("res://scripts/inventory/item_db.gd")
const PL: GDScript = preload("res://scripts/player/player.gd")
const SS: GDScript = preload("res://scripts/save/save_system.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []
var _usadas: Array[String] = []


func _init() -> void:
	print("[TEST] Fase 17 — barra de acciones")
	SDB.cargar()
	IDB.cargar()
	_t_validar()
	_t_defecto()
	_t_asignar_limpiar()
	_t_swap()
	_t_persistencia()


var _empezo: bool = false


## Player y barra necesitan el árbol (lección 13b de AGENTS.md): el
## _ready corre en el primer _process. Los tests de ejecución van aquí.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_ejecutar()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).free()
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


func _nueva_barra() -> BarraAcciones:
	var b: BarraAcciones = BA.new()
	_basura.append(b)
	return b


## validar_datos: solo ataque, skill existente o consumible existente.
func _t_validar() -> void:
	var b: BarraAcciones = _nueva_barra()
	_check(b.validar_datos({"tipo": "ataque"}), "validar: ataque ok")
	_check(b.validar_datos({"tipo": "skill", "id": "golpe_heroico"}),
		"validar: skill existente ok")
	_check(not b.validar_datos({"tipo": "skill", "id": "no_existe"}),
		"validar: skill inexistente no")
	_check(b.validar_datos({"tipo": "item", "id": "pocion_vida"}),
		"validar: consumible ok")
	_check(not b.validar_datos({"tipo": "item", "id": "espada_corta"}),
		"validar: arma no es asignable")
	_check(not b.validar_datos({"tipo": "item", "id": "no_existe"}),
		"validar: item inexistente no")
	_check(not b.validar_datos({}), "validar: vacío no")
	_check(not b.validar_datos("hola"), "validar: no-dict no")
	_check(not b.validar_datos({"tipo": "rareza"}), "validar: tipo raro no")
	# Con origen de arrastre también valida (el drop lo recibe así).
	_check(b.validar_datos({"origen": "libro", "tipo": "skill", "id": "bola_fuego"}),
		"validar: datos de arrastre del libro ok")
	_check(b.validar_datos({"origen": "inventario", "tipo": "item", "id": "pocion_mana"}),
		"validar: datos de arrastre del inventario ok")


## Layout por defecto: F1 = ataque, F2..F6 = skills, F7/F8 vacíos.
func _t_defecto() -> void:
	var b: BarraAcciones = _nueva_barra()
	b.restablecer_defecto()
	_check(str(b.obtener(0).get("tipo", "")) == "ataque", "defecto: F1 ataque")
	var ids: Array[String] = SDB.lista()
	var n: int = mini(ids.size(), 5)
	for k in range(n):
		var s: Dictionary = b.obtener(k + 1)
		_check(str(s.get("tipo", "")) == "skill" and str(s.get("id", "")) == ids[k],
			"defecto: F%d = %s" % [k + 2, ids[k]])
	_check(b.obtener(6).is_empty() and b.obtener(7).is_empty(),
		"defecto: F7/F8 vacíos")
	_check(b.obtener(99).is_empty(), "defecto: índice fuera de rango = {}")


## asignar / limpiar / obtener.
func _t_asignar_limpiar() -> void:
	var b: BarraAcciones = _nueva_barra()
	b.restablecer_defecto()
	_check(b.asignar(7, {"tipo": "item", "id": "pocion_vida"}),
		"asignar: pocion en F8")
	var s: Dictionary = b.obtener(7)
	_check(str(s.get("tipo", "")) == "item" and str(s.get("id", "")) == "pocion_vida",
		"obtener: refleja lo asignado")
	_check(not b.asignar(7, {"tipo": "skill", "id": "no_existe"}),
		"asignar: inválido retorna false")
	_check(str(b.obtener(7).get("id", "")) == "pocion_vida",
		"asignar: inválido no pisa")
	_check(not b.asignar(99, {"tipo": "ataque"}), "asignar: índice malo false")
	b.limpiar(7)
	_check(b.obtener(7).is_empty(), "limpiar: F8 queda vacío")
	b.limpiar(99)  # no revienta
	_check(true, "limpiar: índice malo no revienta")


## _soltar_en con origen "barra": intercambia los slots.
func _t_swap() -> void:
	var b: BarraAcciones = _nueva_barra()
	b.restablecer_defecto()
	b.asignar(7, {"tipo": "item", "id": "pocion_vida"})
	# Arrastra F8 -> F7: intercambio.
	b._soltar_en(6, {"origen": "barra", "slot": 7, "tipo": "item", "id": "pocion_vida"})
	_check(str(b.obtener(6).get("id", "")) == "pocion_vida", "swap: F7 recibe poción")
	_check(b.obtener(7).is_empty(), "swap: F8 queda vacío")
	# Soltar sobre sí mismo no hace nada.
	b._soltar_en(6, {"origen": "barra", "slot": 6, "tipo": "item", "id": "pocion_vida"})
	_check(str(b.obtener(6).get("id", "")) == "pocion_vida", "swap: soltar en sí mismo no-op")
	# Drop del libro asigna directo.
	b._soltar_en(7, {"origen": "libro", "tipo": "skill", "id": "ejecucion"})
	_check(str(b.obtener(7).get("id", "")) == "ejecucion", "drop: libro asigna skill")
	# Drop inválido se ignora.
	b._soltar_en(7, {"origen": "libro", "tipo": "skill", "id": "no_existe"})
	_check(str(b.obtener(7).get("id", "")) == "ejecucion", "drop: inválido se ignora")
	# _drag_desde_casilla: vacía -> {}, ocupada -> datos con origen/slot.
	_check(b._drag_desde_casilla(0).get("origen", "") == "barra",
		"drag: casilla ocupada da origen barra")
	b.limpiar(0)
	_check(b._drag_desde_casilla(0).is_empty(), "drag: casilla vacía da {}")


## Persistencia: to_dict / cargar_estado con roundtrip e ids inválidos.
func _t_persistencia() -> void:
	var b: BarraAcciones = _nueva_barra()
	b.restablecer_defecto()
	b.asignar(6, {"tipo": "item", "id": "pocion_mana"})
	b.limpiar(0)
	var d: Dictionary = b.to_dict()
	_check(int(d.get("version", 0)) == 1, "save: version 1")
	_check((d.get("slots", []) as Array).size() == 8, "save: 8 slots")
	var b2: BarraAcciones = _nueva_barra()
	b2.cargar_estado(d)
	_check(b2.obtener(0).is_empty(), "load: F1 vacío restaurado")
	_check(str(b2.obtener(6).get("id", "")) == "pocion_mana", "load: F7 poción")
	_check(str(b2.obtener(1).get("id", "")) == str(b.obtener(1).get("id", "")),
		"load: skills intactos")
	# Ids inválidos en el guardado se descartan (vuelven al defecto).
	var b3: BarraAcciones = _nueva_barra()
	b3.cargar_estado({"version": 1, "slots": [
		{"tipo": "skill", "id": "no_existe"}, {"tipo": "item", "id": "espada_corta"},
		{"tipo": "rareza"}, {}, {}, {}, {}, {},
	]})
	_check(b3.obtener(0).is_empty(),
		"load: id inválido -> vacío")
	_check(b3.obtener(2).is_empty(), "load: tipo raro -> vacío")
	# Guardado viejo sin slots: cargar_estado deja todo vacío (la
	# tolerancia al bloque ausente vive en SaveSystem._cargar_barra,
	# que restaura el defecto).
	var b4: BarraAcciones = _nueva_barra()
	b4.cargar_estado({})
	_check(b4.obtener(0).is_empty(), "load: sin slots -> vacío")
	var ss: SaveSystem = SS.new()
	ss.barra_acciones = b4
	ss._cargar_barra({})
	_check(str(b4.obtener(0).get("tipo", "")) == "ataque",
		"load: bloque ausente -> SaveSystem restaura defecto")


## Ejecución real contra un Player (necesita el árbol).
func _t_ejecutar() -> void:
	var p: Player = PL.new()
	root.add_child(p)
	_basura.append(p)
	var b: BarraAcciones = BA.new()
	root.add_child(b)
	_basura.append(b)
	b.conectar(p)
	_usadas.clear()
	p.skills.skill_usada.connect(_al_skill_usada)
	# Skill de curación en F2: al ejecutar debe emitirse skill_usada.
	b.asignar(1, {"tipo": "skill", "id": "curacion_menor"})
	b.ejecutar(1)
	_check(_usadas.has("curacion_menor"), "ejecutar: skill emite skill_usada")
	_check(p.skills.cooldown_restante("curacion_menor") > 0.0,
		"ejecutar: skill entra en cooldown")
	# Consumible: dañar, ejecutar, verificar cura + descuento.
	p.inventario.agregar("pocion_vida", 2)
	b.asignar(6, {"tipo": "item", "id": "pocion_vida"})
	p.take_damage(60.0, null)
	var antes: float = p.vida_actual
	b.ejecutar(6)
	_check(p.vida_actual > antes, "ejecutar: poción cura")
	_check(p.inventario.contar("pocion_vida") == 1, "ejecutar: poción se descuenta")
	# Ataque sin objetivo no revienta.
	b.ejecutar(0)
	_check(true, "ejecutar: ataque sin objetivo no revienta")
	# Slot vacío no hace nada.
	b.limpiar(7)
	b.ejecutar(7)
	_check(true, "ejecutar: slot vacío no revienta")
	# Sin jugador no revienta.
	var b2: BarraAcciones = _nueva_barra()
	b2.ejecutar(0)
	_check(true, "ejecutar: sin jugador no revienta")


func _al_skill_usada(skill_id: String) -> void:
	_usadas.append(skill_id)
