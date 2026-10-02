class_name EstadoNgPlus
extends RefCounted
## Bloque 68, conectado: el ESTADO VIVO del NG+ (la espiral), no sus fórmulas.
##
## POR QUÉ ESTE ARCHIVO: `NuevoJuegoPlus` (el hermano) es matemática pura y
## estaba testeada desde el 68, pero era HUÉRFANA: nadie la llamaba, no había
## reset, ni guardado, ni panel. Se podían calcular los multiplicadores en un
## test y no verlos jamás en el juego. Este archivo es la pieza que falta
## entre la fórmula y el `StatBlock` del jugador:
##
## - guarda los dos números del NG+ (`ciclo` y `prestigio`),
## - decide si toca prestigiar,
## - APLICA la bonificación al `StatBlock` de verdad (mods con id propio), y
## - se serializa al save en un solo diccionario.
##
## "CICLO" y "PRESTIGIO" son DOS números y no uno, y no es redundancia:
## `ciclo` es cuántas vueltas dio el jugador (1, 2, 3…) y `prestigio` es la
## suma de lo que dio cada una (1, 3, 6, 10…). El panel muestra los dos
## porque el jugador cuenta las vueltas, pero el efecto lo ve en los
## multiplicadores, y son números distintos.
##
## NO borra el mundo: el NG+ reinicia el personaje (nivel, atributos, oro,
## equipo), no los árboles talados, ni los refugios, ni las habilidades de
## recolección. Eso lo hace `SaveSystem.reiniciar_para_ngplus()`.

## La UI se suscribe a esto; nadie lee el estado por frame (§9.5).
signal cambiado

## Cuántas vueltas NG+ lleva completadas. 0 = todavía en la primera partida.
var ciclo: int = 0
## Puntos de prestigio acumulados. Es lo que da XP, enemigo débil y afijos.
var prestigio: int = 0

## Prefijo de los ids de modificador en el `StatBlock` ("ngplus:ataque"). Con
## prefijo propio, `quitar_de` sabe cuáles son suyos y no toca los mods de
## equipo, talentos ni hechos.
const PREFIJO_MOD: String = "ngplus:"

## El ciclo que el JUEGO está jugando ahora, para los sistemas que lo
## consultan sin tener una instancia a mano (el catálogo de misiones, sobre
## todo: `QuestDB` es estático y le pregunta "¿esta misión es de la vuelta
## que estoy jugando?").
##
## POR QUÉ UN ESTÁTICO Y NO `SaveSystem.estado_ngplus()` EN CADA CONSULTA:
## esestaticmethod LEE EL DISCO, y el catálogo se consulta desde el bucle de
## la UI, desde `oferta_para_npc` y desde `estado()`. Leer un archivo por
## frame es justo lo que §9.5 prohíbe.
##
## POR QUÉ SE ACTUALIZA EN `desde_dict()` Y EN `prestigiar()` Y NO EN OTRO
## SITIO: son los DOS únicos momentos en los que el NG+ entra al juego. Todo
## el que lee el NG+ de la partida pasa por `SaveSystem._cargar_ngplus` o por
## `SaveSystem.reiniciar_para_ngplus`, y los dos llaman a uno de estos dos.
## Ponerlo en un tercer sitio sería ponerlo en el sitio equivocado.
static var _ciclo_en_juego: int = 0

## FASE 72: el prestigio en juego, por el mismo motivo que el ciclo. Sin esto
## el margen de afijos del NG+ (`NuevoJuegoPlus.afijos_extra`) lo calculaba
## `PanelNgPlus` para MOSTRARLO y nadie más lo usaba: el loot escalaba a 0 y la
## bonificación se leía en una pantalla mientras el botín era idéntico en la
## vuelta 1 y en la vuelta 9.
static var _prestigio_en_juego: int = 0

## El ciclo de la vuelta en juego. 0 = la primera partida (sin NG+ todavía).
static func ciclo_en_juego() -> int:
	return _ciclo_en_juego


## El prestigio de la vuelta en juego, y el margen de afijos que implica. Lo
## lee `DropTable.roll_drops` en cada tirada: es un número en RAM, no una
## lectura de disco, así que no cuesta nada (§9.5).
static func prestigio_en_juego() -> int:
	return _prestigio_en_juego


## El margen de afijos extra que el NG+ le pone al loot AHORA. 0 sin NG+.
static func afijos_extra_en_juego() -> int:
	return NuevoJuegoPlus.afijos_extra(_prestigio_en_juego)


## Fija el ciclo en juego. Lo usan `desde_dict` y `prestigiar`; el test lo usa
## para simular una vuelta sin escribir una partida.
static func fijar_ciclo_en_juego(ciclo: int) -> void:
	_ciclo_en_juego = maxi(0, ciclo)
	_prestigio_en_juego = 0


## Fija el prestigio en juego SIN tocar el ciclo. Lo usan `desde_dict` (que
## publica los dos a la vez) y los tests. `fijar_ciclo_en_juego` lo pone a cero
## porque cambiar de vuelta reinicia el prestigio: son los dos números del NG+
## y se mueven juntos.
static func fijar_prestigio_en_juego(prestigio: int) -> void:
	_prestigio_en_juego = maxi(0, prestigio)


## ¿Le toca prestigiar a este personaje? El tope del mundo y no un umbral
## inventado: hasta llegar al final del contenido no se ofrece la espiral.
func puede_prestigiar(nivel: int) -> bool:
	return nivel >= NuevoJuegoPlus.tope_nivel()


## Cierra el ciclo: sube el contador y suma el prestigio de la vuelta. Emite
## `cambiado` UNA vez (no uno por campo) y devuelve el prestigio ganado, o -1
## si no tocaba. -1 y no 0 para que "no se pudo" no se confunda con "se ganó
## prestige pero el total no cambió" (que no puede pasar, pero no hace falta
## que el que llame lo adivine).
func prestigiar(nivel: int) -> int:
	if not puede_prestigiar(nivel):
		return -1
	var ganado: int = NuevoJuegoPlus.prestigio_ganado(ciclo)
	ciclo += 1
	prestigio += ganado
	# El ciclo nuevo es el que se está jugando: se publica antes de la señal,
	# para que quien escuche `cambiado` ya vea el catálogo de misiones con la
	# vuelta nueva. Al revés, un panel que se repintara con la señal leería el
	# contenido de la vuelta anterior.
	# `fijar_ciclo_en_juego` publica el ciclo y deja el prestigio en 0 (es lo
	# mismo que hace `desde_dict`): prestige y ciclo se mueven juntos.
	fijar_ciclo_en_juego(ciclo)
	fijar_prestigio_en_juego(prestigio)
	cambiado.emit()
	return ganado


## Los multiplicadores, LEÍDOS del hermano puro. Viven en getters y no en
## variables propias para que no puedan desincronizarse: si `AFIXO_CADA`
## cambia en `NuevoJuegoPlus`, esto cambia con él en el mismo frame.
func multiplicador_xp() -> float:
	return NuevoJuegoPlus.multiplicador_prestigio(prestigio)


func multiplicador_enemigo() -> float:
	return NuevoJuegoPlus.multiplicador_enemigo(prestigio)


func afijos_extra() -> int:
	return NuevoJuegoPlus.afijos_extra(prestigio)


## La bonificación al personaje, {stat -> porcentaje}. Vacía con prestigio 0.
func bonificacion() -> Dictionary:
	return NuevoJuegoPlus.bonificacion_stats(prestigio)


## PONE la bonificación del NG+ en el `StatBlock` del jugador. Es el punto
## donde el prestigio deja de ser un número y se convierte en un stat de
## verdad: sin esta llamada el NG+ se calcularía y se mostraría, y el héroe
## pelearía EXACTAMENTE igual que en la vuelta anterior.
##
## Idempotente: `add_mod` reemplaza por id, así que llamarla dos veces (al
## cargar y al re-aplicar) no duplica el bono. Con prestigio 0 QUITA los mods
## en vez de poner ceros: "prestigio 0 = x1.0" tiene que ser el mismo estado
## que un save viejo, no un estado con cinco mods de valor 0.
func aplicar_a(stats: StatBlock) -> void:
	if stats == null:
		return
	quitar_de(stats)
	var bon: Dictionary = bonificacion()
	for stat in bon:
		stats.add_mod(PREFIJO_MOD + str(stat), str(stat), StatBlock.ModKind.PORCENTUAL,
			float(bon[stat]))


## Saca los mods del NG+ y deja el `StatBlock` como estaba. Lo llama `aplicar_a`
## antes de reponerlos. Recorre la lista cerrada de stats derivados (la misma
## que usa la bonificación) y no la del estado actual: si un save trae un mod
## de NG+ de un stat que hoy ya no se bonifica, también tiene que salir.
func quitar_de(stats: StatBlock) -> void:
	if stats == null:
		return
	for stat in StatBlock.STATS_DERIVADOS:
		stats.remove_mod(PREFIJO_MOD + str(stat))


## Todo el NG+ en un solo diccionario, TAL como se guarda. La forma es la de
## `NuevoJuegoPlus.to_dict` (que ya era "el estado del NG+ para el save") más
## `ciclo`, que es lo único que el hermano no podía saber.
func to_dict() -> Dictionary:
	var d: Dictionary = NuevoJuegoPlus.to_dict(prestigio)
	d["ciclo"] = maxi(0, ciclo)
	return d


## Lee el estado de un save. Un save viejo (sin bloque "ngplus", o anterior a
## esta fase) = 0 prestigio y 0 ciclo, que es el juego normal sin NG+: los
## multiplicadores dan 1.0 y la bonificación al personaje es un diccionario
## vacío. Nunca lanza.
static func desde_dict(d: Dictionary) -> EstadoNgPlus:
	var e: EstadoNgPlus = EstadoNgPlus.new()
	e.prestigio = NuevoJuegoPlus.desde_dict(d)
	e.ciclo = maxi(0, int(d.get("ciclo", 0)))
	# Un save con prestigio y sin ciclo no puede existir (solo lo escribe esta
	# clase), pero si aparece se asume UNA vuelta: el multiplicador es lo que
	# importa y sale del prestigio, no del contador.
	if e.ciclo == 0 and e.prestigio > 0:
		e.ciclo = 1
	# Publicar el ciclo: TODO el NG+ que entra al juego pasa por aquí, así que
	# este es el punto donde `QuestDB` se entera de qué vuelta está el
	# jugador. Ver `ciclo_en_juego()`.
	fijar_ciclo_en_juego(e.ciclo)
	# Y el prestigio, que es lo que le da margen de afijos al loot.
	fijar_prestigio_en_juego(e.prestigio)
	return e
