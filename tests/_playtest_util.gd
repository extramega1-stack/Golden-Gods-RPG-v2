extends RefCounted
## Utilidades de LECTURA para `tests/playtest_completo.gd`.
##
## Sin `class_name` A PROPÓSITO: el harness lo preloadea con `const U = preload(...)`,
## así que este archivo no agrega un tipo nuevo al caché global de Godot y no
## obliga a correr `--import` antes de la suite (la trampa de AGENTS.md).
##
## Todo lo de acá SOLO lee. Ninguna función toca el juego: si el playtest pasa,
## es porque el juego se movió solo, no porque el test lo movió.

## Recorre todo el subárbol en profundidad (BFS iterativo, sin recursión).
static func todos(raiz: Node) -> Array:
	var out: Array = []
	if raiz == null:
		return out
	var cola: Array = [raiz]
	while not cola.is_empty():
		var cur: Node = cola.pop_back()
		if not is_instance_valid(cur):
			continue
		out.append(cur)
		for c in cur.get_children():
			cola.append(c)
	return out


## Busca un nodo por nombre exacto en todo el subárbol.
static func nodo(raiz: Node, nombre: String) -> Node:
	for n in todos(raiz):
		if String(n.name) == nombre:
			return n
	return null


## Nombres de los hijos directos, para que un fallo diga qué hay y qué falta.
static func nombres(raiz: Node) -> Array[String]:
	var out: Array[String] = []
	if raiz == null:
		return out
	for c in raiz.get_children():
		out.append(String(c.name))
	return out


## Primer nodo del tipo pedido. Godot 4 permite comparar con un `class_name`
## o con el nombre del script: `RetratoHeroe` y "RetratoHeroe" funcionan.
static func primero_de_tipo(raiz: Node, tipo: String) -> Node:
	for n in todos(raiz):
		if n.is_class(tipo) or n.get_class() == tipo:
			return n
		if _clase_de_script(n) == tipo:
			return n
	return null


## El `class_name` global del script del nodo, o "" si no lo tiene. Es la
## única forma fiable de encontrar, por ejemplo, un `RetratoHeroe`: el nodo es
## un `PanelContainer`, se llama `@PanelContainer@148` y su archivo es
## `retrato_heroe.gd`. Ninguna de las tres cosas coincide con "RetratoHeroe".
static func clase_de_script(n: Node) -> String:
	var s: Script = n.get_script() if n != null else null
	if s == null:
		return ""
	return String(s.get_global_name())


## Todos los nodos de un tipo, en orden de árbol.
static func todos_de_tipo(raiz: Node, tipo: String) -> Array:
	var out: Array = []
	for n in todos(raiz):
		if n.is_class(tipo) or n.get_class() == tipo or clase_de_script(n) == tipo:
			out.append(n)
	return out


## Busca el nodo cuyo script es el de una ruta res:// exacta.
static func con_script(raiz: Node, ruta: String) -> Node:
	for n in todos(raiz):
		var s: Script = n.get_script()
		if s != null and String(s.resource_path) == ruta:
			return n
	return null


static func _clase_de_script(n: Node) -> String:
	return clase_de_script(n)


## Todos los botones descendientes, para buscar por texto (la UI del juego
## construye sus botones en código y no les pone nombre).
## Normaliza: si le pasás un Array de botones, lo devuelve tal cual; si le
## pasás un Node, los busca en el subárbol.
static func _botones_de(raiz: Variant) -> Array:
	if raiz == null:
		return []
	if typeof(raiz) == TYPE_ARRAY:
		var ya: Array = raiz
		return ya
	return botones(raiz as Node)


static func botones(raiz: Node) -> Array:
	var out: Array = []
	if raiz == null:
		return out
	for n in todos(raiz):
		if n is Button:
			out.append(n)
	return out


## Acepta un Node (se busca en su subárbol) o un Array de Buttons ya sacados.
static func boton_texto(raiz: Variant, texto: String) -> Button:
	for b in _botones_de(raiz):
		var btn: Button = b
		if btn.text.strip_edges() == texto:
			return btn
	return null


## Un botón cuyo texto CONTENGA el fragmento (los nombres de clase llevan
## detalle: "Guerrero · Fuerza 12" y no "Guerrero").
static func boton_que_contiene(raiz: Variant, fragmento: String) -> Button:
	for b in _botones_de(raiz):
		var btn: Button = b
		if btn.text.to_lower().find(fragmento.to_lower()) >= 0:
			return btn
	return null


## Los textos de todos los botones de un subárbol, para un mensaje de fallo
## que diga qué hay y qué falta.
static func textos_de_botones(raiz: Variant) -> Array[String]:
	var out: Array[String] = []
	for b in _botones_de(raiz):
		out.append(str((b as Button).text))
	return out


## Nombres de los nodos hijos directos de `root` (las escenas del juego).
static func raices(root: Node) -> Array[String]:
	var out: Array[String] = []
	for c in root.get_children():
		out.append(String(c.name))
	return out


## Todos los textos painted (Label/Label3D) de un subárbol: sirve para
## capturar un estado de UI antes de mover algo y compararlo después.
static func textos(raiz: Node) -> Array[String]:
	var out: Array[String] = []
	for n in todos(raiz):
		if n is Label:
			out.append(str((n as Label).text))
		elif n is Label3D:
			out.append(str((n as Label3D).text))
	return out


## Celdas pintadas de una pestaña del PanelInventario (lo que el jugador ve).
static func celdas(panel: Node, pestana: String) -> int:
	if panel == null:
		return -1
	var rejillas: Variant = panel.get("_rejillas")
	if typeof(rejillas) != TYPE_DICTIONARY:
		return -1
	var rejilla: Variant = (rejillas as Dictionary).get(pestana)
	if rejilla == null:
		return -1
	return (rejilla as Node).get_child_count()


## La entrada cruda del inventario para un item (con sus afijos).
static func entrada(inv: Object, item_id: String) -> Dictionary:
	if inv == null:
		return {}
	for e in (inv.call("listar") as Array):
		var ed: Dictionary = e
		if str(ed.get("id", "")) == item_id:
			return ed
	return {}


## Lee una propiedad numérica sin romper si el nodo no la tiene.
static func num(obj: Object, prop: String) -> float:
	if obj == null:
		return -1.0
	return float(obj.get(prop))


## Cierra un panel con SU propio protocolo (el que declara `PilaUI._cerrar_via`)
## y devuelve qué método atendió. Sirve para distinguir "el panel se cerró" de
## "lo cerró el juego por su cuenta".
static func cerrar_panel(panel: Node) -> String:
	if panel == null:
		return "null"
	if panel.has_method("cerrar_panel"):
		panel.call("cerrar_panel")
		return "cerrar_panel()"
	if panel.has_method("cerrar"):
		panel.call("cerrar")
		return "cerrar()"
	panel.visible = false
	return "visible = false"


## Cuántos `Label3D` visibles hay bajo un nodo con un texto dado. Lo usa el
## paso de "sale el número de daño": tiene que haber un número EN PANTALLA.
static func etiqueta3d_visible(raiz: Node, prefijo: String) -> String:
	for n in todos(raiz):
		var l: Label3D = n as Label3D
		if l != null and l.visible and l.text.begins_with(prefijo):
			return l.text
	return ""


## El `Pickup` del mundo que lleva un item_id, si sigue en el suelo.
static func pickup_de(raiz: Node, item_id: String) -> Node:
	for n in todos(raiz):
		var s: Script = n.get_script()
		if s == null:
			continue
		if String(s.resource_path).get_file() != "pickup.gd":
			continue
		var drop: Dictionary = n.get("drop")
		if str(drop.get("item_id", "")) == item_id:
			return n
	return null


## ¿Hay algún `GPUParticles3D` emitting por debajo del nodo?
static func alguna_particula(raiz: Node) -> bool:
	for n in todos(raiz):
		if n is GPUParticles3D and n.emitting:
			return true
	return false
