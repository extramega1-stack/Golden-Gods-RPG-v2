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
const PANEL_INVENTARIO: int = 25
const PANEL_EQUIPO: int = 26
