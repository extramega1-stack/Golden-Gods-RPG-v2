class_name VeredictoRender
extends RefCounted
## Fase 69.1: las dos preguntas que el bench tiene que responder ANTES de
## decir que el juego va lento.
##
## 1) ¿ESTÁ ESTRANGULADO EL COMPOSITOR? La trampa que ya se pagó una vez en
##    este proyecto (AGENTS.md): bajo Wayland, una ventana a la que no se le
##    da el foco la estrangula el compositor y el presenting cae a 7,5 Hz, o
##    sea 133,3 ms clavados en CADA frame. El bench anterior reportaba
##    "p95 134,85 ms — FUERA DE PRESUPUESTO" y ese número no era del juego:
##    era el compositor. Con eso se descartó una GTX 1660 que después resultó
##    dar 60 fps con 2,7× de margen.
##
##    LA REGLA NO ES EL FLAG DE FOCO. `Window.has_focus()` no es de fiar: en un
##    setup donde la ventana nueva nunca queda enfocada da `false` mientras el
##    presenting va a 240 Hz, y al revés. Lo que delata el estrangulamiento es
##    la FORMA de la distribución: si el motor no puede con lo que le piden,
##    el reloj de presentación manda y todos los frames caen en el mismo
##    múltiplo de 1/7,5 s. Un juego lento tiene una distribución con cola
##    (p50 bajo y p95 arriba); uno estrangulado tiene una línea.
##
## 2) ¿QUÉ NIVEL DE CALIDAD SE ESTÁ MIRANDO? Para que el informe diga con qué
##    calidad se midió, no la que tenía guardada el que lo corrió.
##
## Todo son funciones PURAS sobre números: sin GPU, sin ventana y sin árbol de
## escena, que es lo que permite verificarlas en el test suite headless. Los
## valores de GPU salen de `tools/bench_gpu.gd`, que hay que lanzar SIN
## `--headless`.
## El compositor estrangula a 7,5 Hz, no a 60: 1000/7,5 = 133,3 ms.
## Tolerancias en ms y en fps, con margen para el ruido de un frame perdido.
const ESTRANGULADO_MS: float = 100.0
const ESTRANGULADO_TOL_MS: float = 1.0
const ESTRANGULADO_FPS_MIN: float = 9.0

## Presupuesto de render de §9.5: 60 fps son 16,7 ms por frame.
const PRESUPUESTO_MS: float = 16.7


## ¿La distribución dice que el presenting va estrangulado y no que el juego
## sea lento?
##
## Las tres condiciones a la vez, porque cualquiera sola mintaría:
## - el frame mediano es larguísimo (>100 ms): a 240 fps libres son 4,17 ms;
## - el p95 es INDISTINGUIBLE del p50 (<1 ms de diferencia): no hay cola, hay
##   un reloj;
## - ni un frame llegó a 9 fps: un juego lento de verdad tiene picos.
static func estrangulado(p50_ms: float, p95_ms: float, fps_min: float) -> bool:
	return p50_ms > ESTRANGULADO_MS \
		and absf(p95_ms - p50_ms) < ESTRANGULADO_TOL_MS \
		and fps_min < ESTRANGULADO_FPS_MIN


## Un renglón para el informe: qué hacer con este número. Un `válido` en
## `false` significa "no lo tomes en cuenta, no es del juego", y es la única
## condición por la que el bench NO puede decir "FUERA DE PRESUPUESTO" sin
## estar midiendo el compositor.
static func nota(p50_ms: float, p95_ms: float, fps_min: float,
		ventana_en_foco: bool) -> String:
	if estrangulado(p50_ms, p95_ms, fps_min):
		return ("AVISO: p50 %.2f / p95 %.2f ms clavados y ni un frame a 9 fps: "
			% [p50_ms, p95_ms]
			+ "el compositor estrangula el presenting y el número mide el "
			+ "compositor, NO el juego. No lo tomes en cuenta.")
	if not ventana_en_foco:
		return ("nota: la ventana no reporta foco, pero la distribución no está "
			+ "estrangulada (p50 %.2f ms); el número SÍ cuenta." % p50_ms)
	return ""


## ¿El p95 entra en el presupuesto de 60 fps?
static func entra_en_presupuesto(p95_ms: float) -> bool:
	return p95_ms <= PRESUPUESTO_MS
