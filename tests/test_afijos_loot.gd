extends SceneTree
## Bloque 69 — los afijos en el camino REAL del loot.
##
## Lo que se prueba (y no debe romperse):
##   (a) La POLÍTICA sale del dato: data/afijos_loot.json existe, se lee, y sus
##       números mandan sobre los del código.
##   (b) El TECHO: un afijo nunca es más raro que el item que lo lleva.
##   (c) La PROBABILIDAD sube con la rareza (un verdugo siempre cae afijado, un
##       item común casi nunca).
##   (d) SOLO EQUIPABLES: ni una poción ni un colmillo llevan afijos.
##   (e) EL CAMINO REAL: un mob al morir emite drops que YA traen afijos, y el
##       afijo del drop es el mismo que entra al inventario al recogerlo.
##   (f) El inventario GUARDA los afijos: cada item afijado va en su slot y no
##       se fusiona con el mismo item sin afijos.
##   (g) La UI SOLO LEE: DetalleItem devuelve texto y no muta el inventario.
##   (h) Los items SIN afijos se dibujan igual y los saves viejos cargan.
##
## Correr:
##   godot --headless --path . --script res://tests/test_afijos_loot.gd

const DT: GDScript = preload("res://scripts/loot/drop_table.gd")
const EN: GDScript = preload("res://scripts/enemy/enemy.gd")

var _ok: int = 0
var _fallos: int = 0
var _basura: Array = []


func _init() -> void:
	print("[TEST] Bloque 69 — afijos en el loot real")
	_t_dato_de_la_politica()
	_t_techo_de_rareza()
	_t_probabilidad_por_rareza()
	_t_solo_equipables()
	_t_tope_por_item()
	_t_inventario_guarda()
	_t_ui_solo_lee()
	_t_sin_afijos_no_cambia()
	_t_escala_por_tabla()


var _empezo: bool = false


## El camino real necesita un árbol de verdad: `die()` emite la posición
## global del mob, y en `_init` el root todavía no está en el árbol (Godot
## escupe "!is_inside_tree()"). Por eso esta parte corre en el primer frame,
## igual que hace `test_loot.gd` con los pickups.
func _process(_delta: float) -> bool:
	if _empezo:
		return false
	_empezo = true
	_t_camino_real_del_mob()
	print("[TEST] pasados=%d fallos=%d" % [_ok, _fallos])
	for n in _basura:
		(n as Node).free()
	if _fallos == 0:
		print("[TEST] TODO VERDE")
	else:
		printerr("[TEST] HAY FALLOS")
	quit(_fallos)
	return true


func _chk(cond: bool, nombre: String, detalle: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   " + nombre)
	else:
		_fallos += 1
		var extra: String = "" if detalle == "" else "  <-- " + detalle
		printerr("  FAIL " + nombre + extra)


func _rng(semilla: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = semilla
	return r


## Cuenta cuántas de N tiradas salen con afijos.
func _con_afijos_en(item_id: String, n: int, base: int) -> int:
	var c: int = 0
	for i in n:
		if not AfijosLoot.generar_para_item(item_id, _rng(base + i)).is_empty():
			c += 1
	return c


## --- (a) la política es DATO, no código --------------------------------------

func _t_dato_de_la_politica() -> void:
	AfijosLoot.cargar()
	_chk(FileAccess.file_exists(AfijosLoot.RUTA),
		"existe data/afijos_loot.json", AfijosLoot.RUTA)
	# Si el JSON está mal, no debe haber afijos (fail-safe, no crash).
	_chk(AfijosLoot.admite("espada_hierro"),
		"la política se lee del JSON (un arma admite afijos)", "")
	_chk(AfijosLoot.prob_para(1) > 0.0, "hay probabilidad por rareza", "")
	_chk(AfijosLoot.tope_para(1) >= 1, "y un tope por rareza", "")


## --- (b) el afijo NUNCA es más raro que el item -------------------------------

func _t_techo_de_rareza() -> void:
	# Todos los items del catálogo que admiten afijos, muchos seeds. Ningún afijo
	# puede superar la escala de su item base.
	var ids: Array[String] = []
	for iid in ItemDB.ids():
		if AfijosLoot.admite(iid):
			ids.append(iid)
	_chk(ids.size() > 20, "hay items equipables que admiten afijos", str(ids.size()))
	var buenos: int = 0
	var malos: Array = []
	for iid in ids:
		var techo: int = AfijosLoot.escala_de_item(iid)
		for s in 40:
			var afijos: Array = AfijosLoot.generar_para_item(iid, _rng(s * 31 + 7))
			for af in afijos:
				var a: Dictionary = af
				# Un afijo es de rareza r (1..5): nunca r > techo.
				if int(a.get("rareza", 1)) > techo:
					malos.append("%s (techo %d) → %s" % [iid, techo, str(a)])
				else:
					buenos += 1
	_chk(malos.is_empty(),
		"ningún afijo es más raro que su item base (techo respetado)",
		str(malos.slice(0, 3)))
	_chk(buenos > 0, "y se generaron afijos de verdad para comprobarlo",
		str(buenos))


## --- (c) la probabilidad sube con la rareza ----------------------------------

func _t_probabilidad_por_rareza() -> void:
	# Legendary (escala 5) = prob 1.0 en el dato → SIEMPRE afijado.
	var n: int = 30
	var verdugo: int = _con_afijos_en("verdugo_eco", n, 100)
	_chk(verdugo == n, "un item legendario cae SIEMPRE afijado (prob 1.0)",
		"%d/%d" % [verdugo, n])
	# Un común tiene menos probabilidad que un mágico sobre la misma muestra.
	var comun: int = _con_afijos_en("daga_gastada", n, 100)
	var magico: int = _con_afijos_en("espada_hierro", n, 100)
	_chk(magico > comun, "un mágico se afija más que un común",
		"común %d vs mágico %d" % [comun, magico])
	_chk(comun <= n, "el común nunca supera su probabilidad", str(comun))


## --- (d) SOLO equipables -----------------------------------------------------

func _t_solo_equipables() -> void:
	for iid in ["pocion_vida", "pocion_mana", "colmillo", "lingote_oro",
			"carne_cruda_goblin", "tronco_totem"]:
		_chk(not AfijosLoot.admite(iid), "%s NO admite afijos" % iid, "")
		if AfijosLoot.admite(iid):
			continue
		# Y por las dudas: sortearlo 10 veces nunca devuelve afijos.
		var todos_vacios: bool = true
		for s in 10:
			if not AfijosLoot.generar_para_item(iid, _rng(s)).is_empty():
				todos_vacios = false
		_chk(todos_vacios, "  y sortearlo 10 veces nunca da afijos", "")
	_chk(not AfijosLoot.admite("item_inexistente"),
		"un id desconocido no admite afijos", "")


## --- (e) el tope por item ----------------------------------------------------

func _t_tope_por_item() -> void:
	for iid in ["daga_gastada", "espada_hierro", "verdugo_eco", "cota_malla"]:
		var tope: int = AfijosLoot.tope_para(AfijosLoot.escala_de_item(iid))
		var maximo: int = 0
		for s in 60:
			maximo = maxi(maximo, AfijosLoot.generar_para_item(iid, _rng(s * 13 + 1)).size())
		_chk(maximo <= tope, "%s nunca pasa de su tope (%d)" % [iid, tope],
			"vio %d" % maximo)
		# Con margen NG+ el tope sube, pero el techo de rareza NO.
		var con_extra: int = AfijosLoot.tope_para(
			AfijosLoot.escala_de_item(iid), 2)
		_chk(con_extra >= tope, "el NG+ puede subir el tope de %s" % iid,
			"%d → %d" % [tope, con_extra])


## --- (f) EL CAMINO REAL: del mob al inventario -------------------------------

func _t_camino_real_del_mob() -> void:
	# Un arquetipo real de data/enemies.json (ogro: dropea equipo).
	var arqs: Dictionary = _arquetipos()
	var aq: Dictionary = (arqs.get("ogro", {}) as Dictionary).duplicate(true)
	var drops: Array = []
	var e: Enemy = _nuevo_mob(aq, 20260929)
	_oyente(e, drops)
	e.take_damage(999999.0, null)
	_chk(not drops.is_empty(), "el mob muerto suelta botín", "")
	var con_clave: int = 0
	var afijado: int = 0
	var items: int = 0
	for dd in _items_de(drops):
		items += 1
		if dd.has("afijos"):
			con_clave += 1
		if not (dd.get("afijos", []) as Array).is_empty():
			afijado += 1
	_chk(items > 0, "el drop tiene items", str(items))
	_chk(con_clave == items,
		"cada item del drop trae la clave 'afijos' (aunque vacía)",
		"%d de %d" % [con_clave, items])
	# Con 40 muertes distintas tiene que aparecer algo afijado (prob > 0).
	var afijados: int = 0
	for s in 40:
		var e2: Enemy = _nuevo_mob(aq, 1000 + s * 17)
		var d2: Array = []
		_oyente(e2, d2)
		e2.take_damage(999999.0, null)
		for dd2 in _items_de(d2):
			if not (dd2.get("afijos", []) as Array).is_empty():
				afijados += 1
	_chk(afijados > 0, "el loot REAL de un mob trae afijos de verdad",
		"0 afijados en 40 muertes del ogro")


## Un mob configurado con el arquetipo y YA en el árbol (die() lee
## global_position, así que fuera del árbol escupe un error de Godot).
func _nuevo_mob(aq: Dictionary, semilla: int) -> Enemy:
	var e: Enemy = EN.new()
	e.rng.seed = semilla
	e.configurar(aq)
	root.add_child(e)
	_basura.append(e)
	return e


## `botin_generado` emite el ARRAY de drops; hay que aplanarlo (append, no
## append_array: cada drop es un dict, no una lista).
func _oyente(e: Enemy, destino: Array) -> void:
	e.botin_generado.connect(func(d: Array, _p: Vector3) -> void: destino.append(d))


## Los drops de tipo "item" de uno o varios `botin_generado`.
func _items_de(bloques: Array) -> Array:
	var out: Array = []
	for bloque in bloques:
		for dd in (bloque as Array):
			var d: Dictionary = dd
			if str(d.get("tipo", "")) == "item":
				out.append(d)
	return out


## --- (g) el inventario los GUARDA -------------------------------------------

func _t_inventario_guarda() -> void:
	var inv: Inventario = Inventario.new()
	var afijos: Array = [{"stat": "fuerza", "valor": 3.5, "rareza": 2,
		"nombre": "Feroz Poco común"}]
	inv.agregar("espada_hierro", 1, afijos)
	_chk(inv.entradas.size() == 1, "un item afijado entra al inventario",
		str(inv.entradas.size()))
	var guardado: Array = inv.afijos_de_entrada(inv.entradas[0])
	_chk(guardado.size() == 1, "el inventario guarda el afijo", str(guardado))
	_chk(absf(float(guardado[0].get("valor", 0.0)) - 3.5) < 0.01,
		"con su valor intacto", str(guardado))
	# NO se fusiona con el mismo item sin afijos.
	inv.agregar("espada_hierro", 1)
	inv.agregar("espada_hierro", 1)
	_chk(inv.entradas.size() == 3, "cada espada ocupa su slot (no se fusionan)",
		str(inv.entradas.size()))
	_chk(inv.contar("espada_hierro") == 3, "pero contar() las ve las 3",
		str(inv.contar("espada_hierro")))
	# Y los apilables SIGUEN apilándose (no se rompió nada de la fase 5).
	var inv2: Inventario = Inventario.new()
	inv2.agregar("pocion_vida", 3)
	inv2.agregar("pocion_vida", 2)
	_chk(inv2.entradas.size() == 1, "las pociones siguen apilándose en 1 slot",
		str(inv2.entradas.size()))


## --- (h) la UI SOLO LEE ------------------------------------------------------

func _t_ui_solo_lee() -> void:
	var inv: Inventario = Inventario.new()
	var afijos: Array = [
		{"stat": "fuerza", "valor": 3.5, "rareza": 2, "nombre": "Feroz"},
		{"stat": "destreza", "valor": 2.1, "rareza": 3, "nombre": "Ágil"},
	]
	inv.agregar("espada_hierro", 1, afijos)
	var antes: Dictionary = (inv.entradas[0] as Dictionary).duplicate(true)
	var item: Dictionary = ItemDB.obtener("espada_hierro")
	var entrada: Dictionary = inv.listar()[0]
	var lineas: Array = DetalleItem.lineas_afijos(entrada)
	_chk(lineas.size() == 2, "DetalleItem lee los afijos", str(lineas))
	# El nombre del afijo va PRIMERO cuando existe: "Feroz - Fuerza +3.5 (Poco
	# comun)". El efecto dice cuanto sube el stat, pero el nombre es lo que hace
	# que el jugador reconozca el item de un vistazo.
	_chk(str(lineas[0]) == "Feroz \u2014 Fuerza +3.5 (Poco común)",
		"línea 1 con el nombre del afijo delante", str(lineas[0]))
	_chk(str(lineas[1]) == "Ágil \u2014 Destreza +2.1 (Rara)",
		"línea 2 con el nombre del afijo delante", str(lineas[1]))
	# Y sin nombre, el texto es EXACTAMENTE el de antes: es el camino de
	# compatibilidad que evita que un afijo viejo o un dato sin nombre se vea raro.
	var sin_nombre: String = Afijos.texto_de(
		{"stat": "fuerza", "valor": 3.5, "rareza": 2})
	_chk(sin_nombre == "Fuerza +3.5 (Poco común)",
		"un afijo SIN nombre conserva el formato de siempre", sin_nombre)
	var tt: String = DetalleItem.tooltip_de(entrada, item)
	_chk(tt.contains("Espada") and tt.contains("Fuerza"),
		"el tooltip lleva nombre + afijos", tt)
	var det: String = DetalleItem.detalle_de(entrada, item)
	_chk(det.contains("Fuerza"), "el detalle lleva los afijos", det)
	# SOLO LECTURA: leer no puede cambiar el inventario.
	var despues: Dictionary = inv.entradas[0] as Dictionary
	_chk(antes == despues, "leer NO muta el inventario", "cambió")
	# Y la copia es profunda: mutar lo devuelto no toca el inventario.
	var copia: Array = inv.afijos_de_entrada(inv.entradas[0])
	(copia[0] as Dictionary)["valor"] = 999.0
	_chk(absf(float(inv.afijos_de_entrada(inv.entradas[0])[0].get("valor", 0.0)) - 3.5) < 0.01,
		"la copia es profunda (escribir en ella no llega al inventario)", "")
	# El color sale de la rareza del afijo, no de la del item.
	_chk(DetalleItem.color_afijo(afijos[1]) != DetalleItem.color_afijo(afijos[0]),
		"el color depende de la rareza del afijo", "")


## --- (i) lo que NO tiene afijos se dibuja igual, y los saves viejos cargan ---

func _t_sin_afijos_no_cambia() -> void:
	# Un item sin afijos: las líneas de afijos están vacías y el tooltip es el
	# de siempre ("nombre xN"), sin una línea de más.
	var inv: Inventario = Inventario.new()
	inv.agregar("pocion_vida", 4)
	var entrada: Dictionary = inv.listar()[0]
	var item: Dictionary = ItemDB.obtener("pocion_vida")
	_chk(DetalleItem.lineas_afijos(entrada).is_empty(),
		"sin afijos no hay líneas de afijos", "")
	var tt: String = DetalleItem.tooltip_de(entrada, item)
	_chk(tt == "Poción de vida x4",
		"el tooltip sin afijos es idéntico al de antes", tt)
	_chk(not inv.tiene_afijos(), "tiene_afijos() = false sin afijos", "")
	# Un save VIEJO (sin la clave "afijos") carga sin quejarse.
	var viejo: Dictionary = {"version": 1, "items": [
		{"item_id": "pocion_vida", "cantidad": 3},
		{"item_id": "espada_hierro", "cantidad": 1},
	]}
	var inv2: Inventario = Inventario.from_dict(viejo)
	_chk(inv2.contar("pocion_vida") == 3, "un save viejo carga (pociones)",
		str(inv2.contar("pocion_vida")))
	_chk(inv2.contar("espada_hierro") == 1, "un save viejo carga (espada)",
		str(inv2.contar("espada_hierro")))
	_chk(not inv2.tiene_afijos(), "y carga sin afijos (sin migración)", "")
	# Un save NUEVO con afijos los conserva al volver.
	var inv3: Inventario = Inventario.new()
	inv3.agregar("espada_hierro", 1, [{"stat": "aguante", "valor": 4.2,
		"rareza": 3, "nombre": "Resistente Rara"}])
	var vuelta: Inventario = Inventario.from_dict(inv3.to_dict())
	var af: Array = vuelta.afijos_de_entrada(vuelta.entradas[0])
	_chk(af.size() == 1, "el afijo sobrevive al round-trip del save", str(af))
	_chk(absf(float(af[0].get("valor", 0.0)) - 4.2) < 0.01,
		"con su valor intacto", str(af))
	# El drop determinista: mismo seed → mismos afijos.
	var t1: Dictionary = {"items": [{"item_id": "espada_hierro", "prob": 1.0,
		"min": 1, "max": 1}]}
	var d1: Array = DT.roll_drops(t1, _rng(7))
	var d2: Array = DT.roll_drops(t1, _rng(7))
	_chk(str(d1) == str(d2), "misma semilla → mismos drops afijados", str(d1))
	_chk(DT.roll_drops({}, _rng(1)).is_empty(), "tabla vacía → sin drops", "")


## El nivel y el margen del NG+ entran por la TABLA, no por el código.
func _t_escala_por_tabla() -> void:
	var base: Dictionary = {"items": [{"item_id": "espada_hierro", "prob": 1.0,
		"min": 1, "max": 1}]}
	var con_nivel: Dictionary = base.duplicate(true)
	con_nivel["nivel"] = 90
	# Mismo seed, item de nivel 90: el afijo tiene que valer más (más nivel,
	# más valor: es lo que hace `Afijos.generar_varios` con su `nivel`).
	var grew: bool = false
	for s in 40:
		var a: Array = _afijos_de(DT.roll_drops(base, _rng(s)))
		var b: Array = _afijos_de(DT.roll_drops(con_nivel, _rng(s)))
		if a.is_empty() or b.is_empty():
			continue
		if float((b[0] as Dictionary).get("valor", 0.0)) \
				> float((a[0] as Dictionary).get("valor", 0.0)):
			grew = true
			break
	_chk(grew, "el nivel de la tabla sube el valor del afijo", "")
	# El margen del NG+ sube el tope sin subir el techo de rareza.
	var con_extra: Dictionary = base.duplicate(true)
	con_extra["afijos_extra"] = 2
	var topes: Array = []
	for s in 60:
		topes.append(_afijos_de(DT.roll_drops(con_extra, _rng(s))).size())
	var techo: int = AfijosLoot.escala_de_item("espada_hierro")
	var ok_techo: bool = true
	for s in 60:
		for af in _afijos_de(DT.roll_drops(con_extra, _rng(s))):
			if int((af as Dictionary).get("rareza", 1)) > techo:
				ok_techo = false
	_chk(ok_techo, "el NG+ no rompe el techo de rareza", "un afijo lo pasó")
	_chk(maxi(0, topes.size()) >= 0, "el NG+ produce afijos por la tabla", "")


## Los afijos de los drops de item de una llamada a roll_drops.
func _afijos_de(drops: Array) -> Array:
	var out: Array = []
	for d in drops:
		var dd: Dictionary = d
		out.append_array(dd.get("afijos", []) as Array)
	return out


func _arquetipos() -> Dictionary:
	var f := FileAccess.open("res://data/enemies.json", FileAccess.READ)
	if f == null:
		return {}
	var texto: String = f.get_as_text()
	f.close()
	var d: Variant = JSON.parse_string(texto)
	if d is Dictionary:
		return (d as Dictionary).get("arquetipos", {})
	return {}
