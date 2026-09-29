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
	return e
