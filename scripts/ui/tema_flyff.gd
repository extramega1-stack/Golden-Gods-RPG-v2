class_name TemaFlyFF
extends RefCounted
## Paleta y fábricas de estilo FlyFF Universe (fase 32, SOLO visual).
##
## Unifica el cromo de HUD, minimapa, inventario y barra: fondo oscuro
## azulado, borde dorado, barras HP rosa-rojo / MP azul / XP verde lima y
## texto marfil. Lógica cero: colores + StyleBox + etiquetas.

const DORADO: Color = Color(0.85, 0.68, 0.25)
const DORADO_CLARO: Color = Color(0.95, 0.82, 0.45)
const FONDO: Color = Color(0.05, 0.05, 0.09, 0.92)
const FONDO_BARRA: Color = Color(0.02, 0.02, 0.04, 0.92)
const HP: Color = Color(0.87, 0.28, 0.38)
const MP: Color = Color(0.28, 0.47, 0.95)
const XP: Color = Color(0.45, 0.80, 0.25)
const TEXTO: Color = Color(0.95, 0.90, 0.75)
const APAGADO: Color = Color(0.70, 0.68, 0.60)


## Marco de ventana: fondo oscuro + borde dorado 2 px + esquinas 6.
static func marco() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = FONDO
	sb.border_color = DORADO
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


## Fondo de barra de progreso (pista oscura con filo dorado fino).
static func fondo_barra() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = FONDO_BARRA
	sb.border_color = Color(0.35, 0.28, 0.12)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	return sb


## Relleno de barra en el color dado (esquinas 3, sin borde).
static func relleno(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(3)
	return sb


## Etiqueta marfil con sombra (no intercepta el ratón).
static func etiqueta(texto: String, tam: int, color: Color = TEXTO) -> Label:
	var l := Label.new()
	l.text = texto
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l
