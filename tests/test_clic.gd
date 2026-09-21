extends SceneTree
## Tests headless de la Fase 6.2 (modelo Flyff de clic izquierdo, por pedido
## de Juan Diego: el primer clic selecciona, el SEGUNDO clic sobre el mismo
## enemigo seleccionado ataca — dos clics rápidos o lentos valen igual; el
## flag double_click del motor ya no decide nada).
##
## `Player._resolver_clic_entidad` es PURA (decide sin raycast) y
## `Player._aplicar_clic` ejecuta la decisión; `Player._orden_mover_punto`
## cubre la rama de suelo. Fase 9.1: el segundo clic en un NPC ya
## seleccionado INTERACTÚA (cerca habla directo, lejos camina hasta él y
## habla al llegar). Los tests headless no tienen viewport/cámara,
## así que el rayo real (`_clic_izquierdo`) solo se prueba en su rama "nada"
## (sin cámara no hay rayo → deselecciona).
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_clic.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const PL: GDScript = preload("res://scripts/player/player.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")
const NP: GDScript = preload("res://scripts/npc/npc.gd")
const ENT: GDScript = preload("res://scripts/core/entity.gd")
const SB: GDScript = preload("res://scripts/core/stat_block.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _atacados: int = 0
var _atacado_ultimo: Entity = null
var _hablados: int = 0


func _init() -> void:
	print("[TEST] Fase 6.2 — modelo Flyff de clic izquierdo (seleccionar vs atacar)")


var _empezo: bool = false


## El árbol existe recién en el primer _process (lección 13b): todo lo que
## usa global_position o get_tree() corre aquí.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_primer_clic_selecciona()
	_t_segundo_clic_ataca()
	_t_clic_otro_mob_cambia_seleccion()
	_t_segundo_clic_npc_interactua()
	_t_resolver_pura_no_muta()
	_t_clic_suelo_mueve_y_deselecciona()
	_t_clic_nada_deselecciona()
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


func _al_intencion(e: Entity) -> void:
	_atacados += 1
	_atacado_ultimo = e


func _al_hablar(_n: NPC) -> void:
	_hablados += 1


func _enemigo(pos: Vector3) -> Enemy:
	var e: Enemy = EN.new()
	e.add_to_group("enemigos")
	root.add_child(e)
	e.global_position = pos
	_basura.append(e)
	return e


func _npc(pos: Vector3) -> NPC:
	var n: NPC = NP.new()
	n.add_to_group("npcs")
	root.add_child(n)
	n.global_position = pos
	_basura.append(n)
	return n


func _player(pos: Vector3) -> Player:
	var p: Player = PL.new()
	p.add_to_group("jugador")
	root.add_child(p)
	p.global_position = pos
	_basura.append(p)
	return p


## Primer clic en un mob no seleccionado: lo selecciona, NO ataca.
func _t_primer_clic_selecciona() -> void:
	var p: Player = _player(Vector3.ZERO)
	var en: Enemy = _enemigo(Vector3(3, 0, 0))
	p.intencion_atacar.connect(_al_intencion)
	_atacados = 0
	var accion: int = p._resolver_clic_entidad(en)
	_check(accion == PL.AccionClic.SELECCIONAR, "primer clic en mob → SELECCIONAR",
		"accion=%d" % accion)
	p._aplicar_clic(en, accion)
	_check(p.seleccion == en, "primer clic selecciona el mob", "")
	_check(p.objetivo_ataque == null, "primer clic NO fija objetivo_ataque", "")
	_check(p.intent.quiere_atacar == false, "primer clic NO marca quiere_atacar", "")
	_check(p.intent.objetivo == null, "primer clic NO fija intent.objetivo", "")
	_check(_atacados == 0, "primer clic NO emite intencion_atacar", "")


## Segundo clic en el MISMO mob seleccionado: ataca.
func _t_segundo_clic_ataca() -> void:
	var p: Player = _player(Vector3(100, 0, 100))
	var en: Enemy = _enemigo(Vector3(103, 0, 100))
	p.intencion_atacar.connect(_al_intencion)
	_atacados = 0
	_atacado_ultimo = null
	p.seleccionar(en)
	var accion: int = p._resolver_clic_entidad(en)
	_check(accion == PL.AccionClic.ATACAR, "segundo clic en el mismo mob → ATACAR",
		"accion=%d" % accion)
	p._aplicar_clic(en, accion)
	_check(p.objetivo_ataque == en, "segundo clic fija objetivo_ataque", "")
	_check(p.intent.objetivo == en, "segundo clic fija intent.objetivo", "")
	_check(p.intent.quiere_atacar, "segundo clic marca quiere_atacar", "")
	_check(_atacados == 1 and _atacado_ultimo == en,
		"segundo clic emite intencion_atacar con el mob", "")
	# La orden de acercamiento apunta al objetivo (como el doble clic antes).
	var d: Vector3 = p._destino
	_check(d.distance_to(en.global_position) < 0.01,
		"el destino de persecución es el objetivo", "")
	_check(p.seleccion == en, "al atacar la selección se mantiene", "")


## Clic en otro mob distinto: cambia la selección, NO ataca.
func _t_clic_otro_mob_cambia_seleccion() -> void:
	var p: Player = _player(Vector3(200, 0, 200))
	var en1: Enemy = _enemigo(Vector3(203, 0, 200))
	var en2: Enemy = _enemigo(Vector3(200, 0, 206))
	p.intencion_atacar.connect(_al_intencion)
	_atacados = 0
	p.seleccionar(en1)
	var accion: int = p._resolver_clic_entidad(en2)
	_check(accion == PL.AccionClic.SELECCIONAR,
		"clic en otro mob → SELECCIONAR (no ATACAR)", "accion=%d" % accion)
	p._aplicar_clic(en2, accion)
	_check(p.seleccion == en2, "cambia la selección al nuevo mob", "")
	_check(p.objetivo_ataque == null, "clic en otro mob NO ataca", "")
	_check(p.intent.quiere_atacar == false, "clic en otro mob NO marca quiere_atacar", "")
	_check(_atacados == 0, "clic en otro mob NO emite intencion_atacar", "")


## Segundo clic en el NPC seleccionado: no hace nada (ni atacar ni mover);
## la selección se mantiene (REGLA DURA intacta en el modelo nuevo).
func _t_segundo_clic_npc_interactua() -> void:
	var p: Player = _player(Vector3(300, 0, 300))
	var n: NPC = _npc(Vector3(302, 0, 300))
	p.intencion_atacar.connect(_al_intencion)
	p.hablar_con.connect(_al_hablar)
	_hablados = 0
	_atacados = 0
	# Primer clic en NPC: SÍ se selecciona (los NPCs son seleccionables).
	var a1: int = p._resolver_clic_entidad(n)
	_check(a1 == PL.AccionClic.SELECCIONAR, "primer clic en NPC → SELECCIONAR", "")
	p._aplicar_clic(n, a1)
	_check(p.seleccion == n, "el NPC se selecciona con el primer clic", "")
	# Segundo clic en el mismo NPC: INTERACTUAR (fase 9.1). Aquí está
	# cerca (dist 2 < RADIO_INTERACCION 3) → habla directo, sin moverse.
	var a2: int = p._resolver_clic_entidad(n)
	_check(a2 == PL.AccionClic.INTERACTUAR, "segundo clic en NPC → INTERACTUAR", "accion=%d" % a2)
	p._aplicar_clic(n, a2)
	_check(_hablados == 1, "segundo clic en NPC cercano abre el diálogo", "hablados=%d" % _hablados)
	_check(not p.tiene_interaccion_pendiente(), "NPC cercano: sin interacción pendiente", "")
	_check(p.seleccion == n, "la selección del NPC se mantiene", "")
	_check(p.objetivo_ataque == null, "segundo clic en NPC NO ataca", "")
	_check(p.intent.quiere_atacar == false, "segundo clic en NPC NO marca quiere_atacar", "")
	_check(_atacados == 0, "segundo clic en NPC NO emite intencion_atacar", "")


## `_resolver_clic_entidad` es pura: decidir no muta nada.
func _t_resolver_pura_no_muta() -> void:
	var p: Player = _player(Vector3(400, 0, 400))
	var en: Enemy = _enemigo(Vector3(403, 0, 400))
	var muerto: Enemy = _enemigo(Vector3(406, 0, 400))
	muerto.die()
	_check(p._resolver_clic_entidad(null) == PL.AccionClic.NADA,
		"resolver(null) → NADA", "")
	_check(p._resolver_clic_entidad(muerto) == PL.AccionClic.NADA,
		"resolver(muerto) → NADA", "")
	var a: int = p._resolver_clic_entidad(en)
	_check(a == PL.AccionClic.SELECCIONAR, "resolver decide sin aplicar", "")
	_check(p.seleccion == null and p.objetivo_ataque == null
		and p.intent.quiere_atacar == false,
		"decidir no muta selección ni objetivo ni intent", "")


## Clic en suelo: deselecciona y ordena mover (destino fijado).
func _t_clic_suelo_mueve_y_deselecciona() -> void:
	var p: Player = _player(Vector3(500, 0, 500))
	var en: Enemy = _enemigo(Vector3(503, 0, 500))
	p.seleccionar(en)
	p.objetivo_ataque = en
	var punto: Vector3 = Vector3(510, 0, 515)
	p._orden_mover_punto(punto)
	_check(p.seleccion == null, "clic en suelo deselecciona", "")
	_check(p.objetivo_ataque == null, "clic en suelo cancela el objetivo de ataque", "")
	_check(p._tiene_destino, "clic en suelo fija orden de mover", "")
	_check(p._destino == punto, "el destino es el punto clicado", "")


## Sin cámara (headless) el rayo no existe: `_clic_izquierdo` toma la rama
## "nada" → deselecciona sin moverse (igual que el legado).
func _t_clic_nada_deselecciona() -> void:
	var p: Player = _player(Vector3(600, 0, 600))
	var en: Enemy = _enemigo(Vector3(603, 0, 600))
	p.seleccionar(en)
	p.objetivo_ataque = en
	p._clic_izquierdo(Vector2(100, 100))
	_check(p.seleccion == null, "clic sin rayo deselecciona", "")
	_check(p.objetivo_ataque == null, "clic sin rayo cancela el ataque", "")
	_check(not p._tiene_destino, "clic sin rayo no ordena moverse", "")
