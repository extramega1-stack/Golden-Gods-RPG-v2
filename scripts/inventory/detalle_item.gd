class_name DetalleItem
extends RefCounted
## Cómo se lee un item del inventario para DIBUJARLO: nombre, descripción,
## líneas de afijos y tooltip. Bloque 69.
##
## POR QUÉ EXISTE: el afijo se sortea al caer el item (`AfijosLoot`) y se
## guarda con la entrada del inventario (`Inventario`). Faltaba el paso de
## leerlo y dibujarlo. Este script es ESE paso y solo eso: entra una entrada
## del inventario y salen strings. Sin estado, sin nodos, sin escritura — la UI
## lee y dibuja, nunca modifica (regla dura §7.11).
##
## - SOLO LECTURA: `descripcion_de` y `lineas_afijos` no tocan `entradas`.
##   Devolvemos copias, así que un `Label` que se quede con el string no
##   puede arrastrar el inventario.
## - UN ITEM SIN AFIJOS SE DIBUJA IGUAL: si la lista está vacía, las líneas de
##   afijos son `[]` y el tooltip es el de siempre. Un jugador que no ha visto
##   un afijo no nota nada.
## - EL COLOR LO PONE LA RAREZA DEL AFIJO, no la del item: el item es la
##   etiqueta, el afijo es la sorpresa. La escala 1..5 es la de `Afijos`.
##
## Lo usa `PanelInventario`. Es estático a propósito: es lógica de presentación
## sin dependencias del árbol de escena, y por eso se testea headless.

## Texto que ya viene en el item del catálogo (nunca afijo-dependent).
static func nombre_de(entrada: Dictionary, item: Dictionary) -> String:
	return str(item.get("nombre", entrada.get("id", "")))


## La descripción del catálogo, sin afijos: la línea neutral del detalle.
static func descripcion_de(item: Dictionary) -> String:
	return str(item.get("descripcion", ""))


## Una línea por afijo, para la barra de detalle: "Fuerza +3.2 (Rara)".
## Vacío si el item no lleva afijos → la UI omite el bloque entero.
static func lineas_afijos(entrada: Dictionary) -> Array:
	var out: Array = []
	for af in Inventario.afijos_de_entrada(entrada):
		out.append(Afijos.texto_de(af))
	return out


## Todo el texto de una celda, listo para un `tooltip_text`: nombre + cantidad
## + afijos. Sin afijos, es exactamente lo que se pintaba antes del bloque 69.
static func tooltip_de(entrada: Dictionary, item: Dictionary) -> String:
	var cant: int = int(entrada.get("cantidad", 1))
	var texto: String = "%s x%d" % [nombre_de(entrada, item), cant]
	var lineas: Array = lineas_afijos(entrada)
	if lineas.is_empty():
		return texto
	return "%s\n%s" % [texto, "\n".join(PackedStringArray(lineas))]


## El bloque completo de la barra de detalle: descripción + afijos.
static func detalle_de(entrada: Dictionary, item: Dictionary) -> String:
	var partes: Array = []
	var desc: String = descripcion_de(item)
	if desc != "":
		partes.append(desc)
	var lineas: Array = lineas_afijos(entrada)
	if not lineas.is_empty():
		partes.append("\n".join(PackedStringArray(lineas)))
	return "\n".join(PackedStringArray(partes))


## Color de una línea de afijo según su rareza (1..5). Sin afijo → el color
## neutro del panel, para que la UI pueda aplicarlo sin `if` por su cuenta.
static func color_afijo(afijo: Dictionary) -> Color:
	var r: int = clampi(int(afijo.get("rareza", 1)) - 1, 0, Afijos.RAREZAS.size() - 1)
	match r:
		0:
			return Color(0.80, 0.80, 0.78)
		1:
			return Color(0.55, 0.85, 0.55)
		2:
			return Color(0.45, 0.68, 1.00)
		3:
			return Color(0.75, 0.50, 1.00)
		4:
			return Color(1.00, 0.78, 0.30)
	return Color(0.80, 0.80, 0.78)
