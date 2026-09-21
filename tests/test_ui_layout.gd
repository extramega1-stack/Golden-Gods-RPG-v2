extends SceneTree
## Tests headless de layout responsivo (hotfix Fase 8.1).
##
## Bug reportado por Juan Diego (monitor 21:9, 3440x1440): el diálogo con
## NPCs se abría pero el panel se cortaba por el borde inferior (los
## botones no se veían) y la barra de skills [1]-[5] tapaba el texto.
##
## El fix (scripts/ui/ventana_dialogo.gd): el panel va anclado abajo-centro
## con grow_horizontal BOTH + grow_vertical BEGIN (crece hacia ARRIBA) y su
## borde inferior queda en -(ZONA_INFERIOR_RESERVADA + 16) = -116 px, por
## encima de la barra de skills (que ocupa los 100 px inferiores).
##
## Cubre, en 3440x1440 (21:9) y 1920x1080 (16:9): el panel del diálogo
## queda DENTRO del viewport, NO solapa la barra de skills, su borde
## inferior queda por encima de la barra, las capas son dialogo(81) >
## barra(12), todas las barras del HUD quedan dentro del viewport y la
## descripción de la misión no se encima con la fila de botones.
## (En 3440x1440 se abre con Bram —el texto de misión más largo— y en
## 1920x1080 con Ilya.)
##
## Cómo correrlo (un solo comando, ~2 segundos):
##   ~/workspace/tools/godot/godot --headless --path ~/workspace/godot-rpg-remake --script res://tests/test_ui_layout.gd
## Exit code 0 = todo verde; distinto de 0 = número de fallos.
## (Si agregaste scripts con class_name, corre antes el --import del README.)

const HUDS: GDScript = preload("res://scripts/ui/hud.gd")
const BSK: GDScript = preload("res://scripts/ui/barra_skills.gd")
const DLG: GDScript = preload("res://scripts/ui/ventana_dialogo.gd")
const NP: GDScript = preload("res://scripts/npc/npc.gd")
const NDB: GDScript = preload("res://scripts/npc/npc_db.gd")
const QDB: GDScript = preload("res://scripts/quests/quest_db.gd")
const UI: GDScript = preload("res://scripts/core/ui_layers.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []

var _frame: int = 0
var _res_actual: String = ""
var _tam_esperado: Vector2i = Vector2i.ZERO
var _hud: CanvasLayer = null
var _barra: CanvasLayer = null
var _dlg: CanvasLayer = null
var _npc: NPC = null


func _init() -> void:
	print("[TEST] Fase 8.1 — Layout responsivo del dialogo (21:9 y 16:9)")


## El árbol existe recién en el primer _process (lección 13b); el layout
## de los Containers necesita un par de frames para asentarse, y el
## resize del viewport otro par: por eso los asserts corren en frames 3 y 6.
func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_preparar(Vector2i(3440, 1440), "bram", "colmillos_forja")
	elif _frame == 3:
		_assert_layout()
	elif _frame == 4:
		_preparar(Vector2i(1920, 1080), "ilya", "goblins_fuera")
	elif _frame == 6:
		_assert_layout()
	elif _frame == 7:
		_resumen()
		return true
	return false


func _check(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		if detalle != "":
			printerr("[FALLO] %s :: %s" % [nombre, detalle])
		else:
			printerr("[FALLO] %s" % nombre)


func _preparar(tam: Vector2i, npc_id: String, quest_id: String) -> void:
	_tam_esperado = tam
	_res_actual = "%dx%d" % [tam.x, tam.y]
	root.size = tam
	if _hud == null:
		_hud = HUDS.new()
		root.add_child(_hud)
		_basura.append(_hud)
		_barra = BSK.new()
		root.add_child(_barra)
		_basura.append(_barra)
		_dlg = DLG.new()
		root.add_child(_dlg)
		_basura.append(_dlg)
	if _npc != null:
		_npc.queue_free()
		_basura.erase(_npc)
	var n: NPC = NP.new()
	n.add_to_group("npcs")
	root.add_child(n)
	n.configurar(NDB.obtener(npc_id))
	_npc = n
	_basura.append(n)
	_dlg.cerrar()
	_dlg.mostrar(n)
	_check(_dlg.esta_abierta(),
		"%s: el dialogo se abre" % _res_actual)
	var q: Dictionary = QDB.obtener(quest_id)
	_dlg.mostrar_mision("disponible", str(q.get("nombre", "")),
		str(q.get("descripcion", "")))
	_check(_dlg.tiene_mision(),
		"%s: la mision se muestra" % _res_actual)


func _assert_layout() -> void:
	_check(Vector2i(root.size) == _tam_esperado,
		"%s: el viewport tiene el tamano pedido" % _res_actual,
		"root.size=%s esperado=%s" % [root.size, _tam_esperado])
	var vp: Rect2 = Rect2(Vector2.ZERO, Vector2(root.size))
	var panel: Control = _dlg.get_node("Panel") as Control
	var r_panel: Rect2 = panel.get_global_rect()
	_check(vp.encloses(r_panel),
		"%s: el panel queda DENTRO del viewport" % _res_actual,
		"panel=%s viewport=%s" % [r_panel, vp])
	# La barra de skills es el HBoxContainer hijo directo de la CanvasLayer.
	var cont_barra: Control = _barra.get_child(0) as Control
	var r_barra: Rect2 = cont_barra.get_global_rect()
	_check(vp.encloses(r_barra),
		"%s: la barra de skills queda dentro del viewport" % _res_actual,
		"barra=%s" % r_barra)
	_check(not r_panel.intersects(r_barra),
		"%s: el panel NO solapa la barra de skills" % _res_actual,
		"panel=%s barra=%s" % [r_panel, r_barra])
	_check(r_panel.end.y <= r_barra.position.y,
		"%s: el borde inferior del panel queda por encima de la barra"
		% _res_actual,
		"panel.bottom=%.1f barra.top=%.1f"
		% [r_panel.end.y, r_barra.position.y])
	_check(_dlg.layer == UI.VENTANA_DIALOGO
		and _barra.layer == UI.BARRA_SKILLS
		and UI.VENTANA_DIALOGO > UI.BARRA_SKILLS,
		"%s: capas dialogo(%d) > barra(%d)" % [_res_actual,
			UI.VENTANA_DIALOGO, UI.BARRA_SKILLS],
		"dlg.layer=%d barra.layer=%d" % [_dlg.layer, _barra.layer])
	# HUD: vida/mana abajo-izquierda, XP de ancho completo al filo inferior,
	# etiquetas arriba-izquierda: todo dentro del viewport.
	for c in _controles(_hud):
		var rc: Rect2 = (c as Control).get_global_rect()
		_check(vp.encloses(rc),
			"%s: HUD '%s' dentro del viewport" % [_res_actual, c.name],
			"rect=%s" % rc)
	# La descripción de la misión va en su propia fila antes de los botones:
	# con el separation del VBox no se enciman.
	var desc: Label = _dlg._desc_mision as Label
	_check(desc != null and desc.visible,
		"%s: la descripcion de mision esta visible" % _res_actual)
	if desc != null:
		var fila: HBoxContainer = null
		for h in (desc.get_parent() as Container).get_children():
			if h is HBoxContainer:
				fila = h as HBoxContainer
		_check(fila != null,
			"%s: existe la fila de botones" % _res_actual)
		if fila != null:
			_check(not desc.get_global_rect().intersects(fila.get_global_rect()),
				"%s: la descripcion no se encima con los botones"
				% _res_actual,
				"desc=%s fila=%s"
				% [desc.get_global_rect(), fila.get_global_rect()])


func _controles(n: Node) -> Array:
	var res: Array = []
	for h in n.get_children():
		if h is Control:
			res.append(h)
			res.append_array(_controles(h))
	return res


func _resumen() -> void:
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).queue_free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
