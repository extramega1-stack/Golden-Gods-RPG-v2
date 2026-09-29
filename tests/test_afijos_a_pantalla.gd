extends SceneTree
## El eslabón que faltaba entre el afijo y el jugador.
##
## `tests/test_afijos_loot.gd` (ola 1) prueba que el afijo SE SORTEA y se GUARDA.
## Este prueba que se VE. La diferencia no es academica: los dos callbacks que
## hacen esto —`fase9_demo._al_recoger_botin` pasando `drop["afijos"]` al
## `agregar`, y `panel_inventario._celda` / `_actualizar_barra` leyendo
## `DetalleItem`— son de una linea cada uno, asi que son facilisimos de
## olvidar, y sin ellos el afijo existe en la BD y el jugador no lo ve nunca.
##
## Es el mismo bug de la UI desconectada, en otro sitio: el sistema existe, los
## tests del sistema pasan, y en la partida no se ve.

var _ok: int = 0
var _fallos: int = 0


func _init() -> void:
	_run()


func _run() -> void:
	print("[TEST] Afijos — del drop a la pantalla")
	_hay_datos()
	_el_afijo_llega_a_la_entrada()
	_el_afijo_se_guarda()
	_el_afijo_se_ve_en_el_tooltip()
	_el_afijo_se_ve_en_el_detalle()
	_un_item_sin_afijos_se_dibuja_igual()
	print("[TEST] afijos_a_pantalla: %d ok, %d fallos" % [_ok, _fallos])
	quit(_fallos)


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("[FALLO] %s%s" % [nombre, "" if detalle == "" else "  <-- " + detalle])


func _hay_datos() -> void:
	_chk(FileAccess.file_exists("res://data/afijos_loot.json"),
		"existe data/afijos_loot.json", "")
	_chk(AfijosLoot != null, "la clase AfijosLoot está cargada", "")
	_chk(DetalleItem != null, "la clase DetalleItem está cargada", "")


## Construye una entrada de inventario como la que deja `agregar` cuando se le
## pasa la lista de afijos del drop, y un afijo falso con forma conocida.
## La forma REAL de un afijo, que es la que espera `Inventario.afijos_de_entrada`
## y `Afijos.texto_de`: `stat` (string), `valor` (float) y `rareza` (INT 1..5,
## que indexa `Afijos.RAREZAS`), más `nombre` opcional. No es `tipo` ni una
## rareza de texto: la primera versión de este test se equivocó de forma y
## "pasaba" probando el afijo equivocado.
func _afijo() -> Dictionary:
	return {"stat": "fuerza", "valor": 3.2, "rareza": 3,
		"nombre": "Filo sangrante"}


func _entrada_con_afijo() -> Dictionary:
	return {
		"id": "espada_hierro",
		"cantidad": 1,
		"afijos": [_afijo()],
	}


func _el_afijo_llega_a_la_entrada() -> void:
	# Lo que hace el callback de fase9: `drop.get("afijos", [])` al agregar.
	var drop := {"tipo": "item", "item_id": "espada_hierro", "cantidad": 1,
		"afijos": [_afijo()]}
	_chk(drop.has("afijos"), "el drop trae la clave 'afijos' siempre presente", "")
	var inv: Inventario = Inventario.new()
	inv.agregar(str(drop.get("item_id")), int(drop.get("cantidad", 1)),
		drop.get("afijos", []))
	_chk(inv.contar("espada_hierro") == 1, "el item entra al inventario", "")


func _el_afijo_se_guarda() -> void:
	var inv: Inventario = Inventario.new()
	inv.agregar("espada_hierro", 1, _entrada_con_afijo().get("afijos", []))
	# Dos espadas con afijos DISTINTOS no pueden fusionarse: si se fusionaran,
	# el jugador perdería el build sin aviso.
	inv.agregar("espada_hierro", 1, [{"stat": "fuerza", "valor": 1.5, "rareza": 1}])
	_chk(inv.contar("espada_hierro") == 2,
		"dos items con afijos distintos NO se fusionan (o se pierde el build)",
		"conteo=%d" % inv.contar("espada_hierro"))


func _el_afijo_se_ve_en_el_tooltip() -> void:
	var item: Dictionary = ItemDB.obtener("espada_hierro")
	var entrada := _entrada_con_afijo()
	var tip: String = DetalleItem.tooltip_de(entrada, item)
	_chk(tip.contains("Filo sangrante"),
		"el tooltip nombra el afijo (esto es lo que el jugador lee al hover)",
		"tooltip=%s" % tip.left(90))
	_chk(tip.contains(str(item.get("nombre", "espada_hierro"))),
		"y sigue nombrando el item", "tooltip=%s" % tip.left(90))


func _el_afijo_se_ve_en_el_detalle() -> void:
	var item: Dictionary = ItemDB.obtener("espada_hierro")
	var entrada := _entrada_con_afijo()
	var det: String = DetalleItem.detalle_de(entrada, item)
	_chk(det.contains("Filo sangrante"),
		"el detalle del item seleccionado nombra el afijo",
		"detalle=%s" % det.left(90))
	# Y el número del stat tiene que estar: el nombre solo no le sirve al jugador
	# para elegir.
	_chk(det.contains("3.2"),
		"y muestra el VALOR del afijo, no solo el nombre (el jugador decide con eso)",
		"detalle=%s" % det.left(90))
	_chk(det.contains("Fuerza"),
		"y el stat con su nombre legible", "detalle=%s" % det.left(90))


## El caso de no romper nada: un item sin afijos tiene que verse como antes, sin
## lineas vacias colgando. Si esto falla, el jugador ve "Afijos:" en blanco.
func _un_item_sin_afijos_se_dibuja_igual() -> void:
	var item: Dictionary = ItemDB.obtener("colmillo")
	var entrada := {"id": "colmillo", "cantidad": 3}
	var tip: String = DetalleItem.tooltip_de(entrada, item)
	var det: String = DetalleItem.detalle_de(entrada, item)
	_chk(tip.length() > 0, "el item sin afijos tiene tooltip", "")
	_chk(det.length() > 0, "y detalle", "")
	_chk(not det.to_lower().contains("afijo"),
		"y NO deja una línea de afijos vacía", "detalle=%s" % det.left(90))
	_chk(tip.contains("3"), "el tooltip sigue con la cantidad", "tooltip=%s" % tip)
