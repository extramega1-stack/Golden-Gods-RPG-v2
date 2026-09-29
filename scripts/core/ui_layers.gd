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
## Fase 13: minimapa estilo WC3 (rango 10–19 = HUD persistente).
## Fase 50.4: estos dos son capas DE VERDAD, no z_index. El minimapa cuelga
## de su propio CanvasLayer (antes colgaba del CanvasLayer del HUD y usaba
## `z_index = MINIMAPA`, que es usar una capa como si fuera orden entre
## hermanos: funcionaba por casualidad de orden de árbol). Los anhade
## `fase12_demo._instalar_orientacion`.
const MINIMAPA: int = 11
## Fase 13: brújula superior (rango 10–19 = HUD persistente).
const BRUJULA: int = 14
## Fase 8: feed global de avisos (rango 10–19 = HUD persistente). Lo crea
## `PanelMisiones` pero es del juego entero, no del panel (fase 45.2).
const TOAST: int = 15
## Hotfix 62.1: feed global de avisos de cualquier sistema (capa 16, libre
## dentro del rango 10–19 de HUD). Es la 15 —el toast de misiones— en versión
## propia: la 15 está entrelazada con el banner de "misión completada" de
## `PanelMisiones`, y desarmar ese ovillo es un refactor aparte. Cuando se
## unifique, esta pasa a la 15.
const FEED_AVISOS: int = 16
## Fase 63 (hotfix 62.1): los tres vitales —hambre, sed, energía— arriba a la
## izquierda, al lado del retrato. Es HUD persistente, así que rango 10–19.
const VITALES: int = 17
## Fase 64: el prompt contextual ("E — Prender fogata"). Vive en la 18 para
## que se dibuje por encima de los vitales y no se pise con ellos.
const PROMPT: int = 18
## Bloque 65: el fundido a negro entre escenas. Va en 98, por debajo de los
## modales críticos (90–99) para que un "cargando" pueda taparlo, y con
## `process_mode = ALWAYS` porque tiene que correr con el árbol pausado.
const TRANSICION: int = 98
## Bloque 65: menú de pausa y panel de opciones. Es un modal: va arriba de
## todo, en 96 y 95 (dos capas distintas para que las opciones puedan quedar
## ENCIMA de la pausa, como settings dentro de un menú).
const MENU_PAUSA: int = 96
const PANEL_OPCIONES: int = 97
## Bloque 65: cinemática a pantalla completa. Por debajo de la transición (98)
## y por encima de todo lo demás.
const CINEMATICA: int = 99
## Fase 64: catálogo de construcción del refugio. Panel de sistema, así que
## rango 20–69, justo detrás de PANEL_AYUDA (32).
const PANEL_CONSTRUCCION: int = 33
## Fase 64: recetas de la fogata. Mismo rango de panel de sistema.
const PANEL_COCINA: int = 34
## Fase 53: barra de jefe, arriba-centro (rango 10–19 = HUD persistente).
## UI pura, a diferencia de `BarraVidaMob` que es 3D sobre el mob.
const BARRA_JEFE: int = 13
## Fase 12: banner de región descubierta. Rango 70–79 = progresión/mundo.
## Ojo: `fase14_demo.tscn` pone este número a mano en el CanvasLayer
## `CapaBanner`; si cambia una cosa hay que cambiar la otra.
const BANNER_REGION: int = 70
## (13 reservado: fue BOTON_ATACAR, retirado en fase 6.1 por pedido de
## Juan Diego; el rebind de tecla vuelve con la barra de acciones.)
const PANEL_INVENTARIO: int = 25
const PANEL_EQUIPO: int = 26
## Fase 8: panel de misiones (rango 20–69 = paneles de sistemas).
const PANEL_MISIONES: int = 27
## Fase 9: sub-ventana de detalle de misión (= PANEL_MISIONES + 1, rango
## 20–69). Se abre al pulsar una misión en curso en el PanelMisiones.
const DETALLE_MISION: int = 28
## Fase 16: panel de viaje rápido (rango 20–69 = paneles de sistemas).
const PANEL_VIAJE: int = 29
## Fase 28: panel de talentos (rango 20–69 = paneles de sistemas).
## Fase 31: rework a panel de habilidades (pestañas Skills + Talentos).
const PANEL_HABILIDADES: int = 30
## Fase 30: ventana de personaje estilo FlyFF (rango 20–69).
const PANEL_PERSONAJE: int = 31
## Fase 46: manual de ayuda — controles y mecánicas (rango 20–69).
const PANEL_AYUDA: int = 32
const VENTANA_DIALOGO: int = 81
## Fase 7: panel de tienda (rango 80–89 = tiendas/diálogos).
const PANEL_TIENDA: int = 82
## Fase 44: panel de herrería (rango 80–89, junto a la tienda).
const PANEL_HERRERIA: int = 83
## Fase 11: pantalla de título (rango 90–99 = modales críticos).
const TITULO: int = 90
## Fase 20: pantalla de carga del mundo (lo más alto: tapa todo).
const CARGA: int = 99
## Fase 8.1: alto (px) reservado sobre el borde inferior del viewport para
## la barra de skills. La VentanaDialogo lo usa como tope inferior + aire
## para crecer hacia arriba sin solaparla ni salirse de la pantalla.
const ZONA_INFERIOR_RESERVADA: int = 100
