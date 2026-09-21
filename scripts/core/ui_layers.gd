class_name UiLayers
extends RefCounted
## Capas UI: fuente única de verdad (MASTER_SPEC §9.2).
##
## Rangos reservados — ningún sistema elige su capa a ojo:
## 10–19: HUD y elementos persistentes (barras, feed, brújula…)
## 20–69: paneles de sistemas (inventario, equipo, talentos, mapa…)
## 70–79: sistemas de progresión/mundo · 80–89: tiendas/diálogos
## 90–99: modales críticos (pausa, título, confirmaciones de riesgo).
## El caos del legado (3 sistemas en la capa 87) no se repite.

const HUD: int = 10
const BARRA_SKILLS: int = 12
## (13 reservado: fue BOTON_ATACAR, retirado en fase 6.1 por pedido de
## Juan Diego; el rebind de tecla vuelve con la barra de acciones.)
const PANEL_INVENTARIO: int = 25
const PANEL_EQUIPO: int = 26
## Fase 8: panel de misiones (rango 20–69 = paneles de sistemas).
const PANEL_MISIONES: int = 27
## Fase 9: sub-ventana de detalle de misión (= PANEL_MISIONES + 1, rango
## 20–69). Se abre al pulsar una misión en curso en el PanelMisiones.
const DETALLE_MISION: int = 28
const VENTANA_DIALOGO: int = 81
## Fase 7: panel de tienda (rango 80–89 = tiendas/diálogos).
const PANEL_TIENDA: int = 82
## Fase 11: pantalla de título (rango 90–99 = modales críticos).
const TITULO: int = 90
## Fase 8.1: alto (px) reservado sobre el borde inferior del viewport para
## la barra de skills. La VentanaDialogo lo usa como tope inferior + aire
## para crecer hacia arriba sin solaparla ni salirse de la pantalla.
const ZONA_INFERIOR_RESERVADA: int = 100
