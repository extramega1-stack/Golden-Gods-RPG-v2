class_name ResultadoPartida
extends RefCounted
## Fase 72: LAS DOS CONDICIONES DE FIN DE PARTIDA. Victoria y derrota.
##
## POR QUÉ ESTA FASE EXISTE: el juego no tenía forma de ganar ni de perder. Se
## podían entregar las dos misiones finales (600 oro y 1500 XP la una) y el
## juego seguía exactamente igual: cero pantallas de final, cero game over. Con
## cinco actos jugables, un jugador que llegaba al Acto V y entregaba el Sello
## no tenía ninguna señal de haber terminado. Eso no es un juego "completo y
## jugable de principio a fin", es un mundo con contenido.
##
## QUÉ ES Y QUÉ NO ES:
## - Es la única fuente de verdad de "cómo terminó esta partida". La UI
##   (`PanelFinal`, `PanelDerrota`) se SUSCRIBE a sus señales y dibuja; no
##   consulta ni decide (§9.5: la UI nunca lee por frame).
## - NO toca el combate (§7.2). No cambia una fórmula de daño, ni la curva de
##   niveles, ni el StatBlock. Escucha `jugador.murio` y el estado del
##   `QuestLog`, que ya existían.
## - NO cambia el canon (§7.4). No inventa un final nuevo ni cambia el tono de
##   los dos que hay: el texto de cada final sale de `data/derrota.json`, y el
##   Sello sigue siendo la senda canónica.
##
## LA VICTORIA NO SE DETECTA DENTRO DE `QuestLog.entregar()`. Se detecta AQUÍ,
## suscribiéndose a `misiones.cambiada` y preguntando por el estado de las dos
## misiones finales. Por qué así y no con un `if quest_id == ...` en
## `entregar()`: (a) `QuestLog` es lógica pura de misiones y no tiene por qué
## saber que existe un final; (b) si mañana otra cosa entrega la misión final
## (un script, un test, el NG+), esta comprobación la ve igual y la de
## `entregar()` no; (c) el estado se LEE de un solo lado, que es el `QuestLog`,
## y por eso cargar una partida ya ganada vuelve a mostrar el final en vez de
## perderlo (ver `reanudar_tras_carga`).
##
## LA DERROTA, Y POR QUÉ TIENE QUE CUIDAR EL ORDEN DE LAS SEÑALES: al morir,
## `RespawnHeros` teletransporta al héroe al ancla y lo revive AL INSTANTE,
## dentro de la misma señal `murio`. Si este sistema se conectara después, la
## pantalla de derrota se abriría sobre un héroe ya revivido: el castigo se
## aplicaría sobre una vida nueva y el jugador nunca vería el panel. Por eso
## el demo llama a `configurar()` ANTES que `RespawnHeros.configurar()`, y acá
## se PUESTA A PUNTO el respawn antes de que su handler corra. Es la misma
## puesta a punto explícita que usa la Arena, y por el mismo motivo: el orden
## de los suscriptores a una señal es el orden de conexión, y depender de él
## para decidir una penalización es frágil.
##
## LAS MUERTES DE LA ARENA NO SON DERROTA DE PARTIDA: la arena tiene su propia
## derrota por oleadas y su propio trophy. Si el respawn ya estaba suspendido
## cuando llegó la muerte, la puso la Arena, y acá no se toca nada.

## §9.1
var system_id: StringName = &"resultado_partida"

## La versión del bloque "resultado" del guardado. Cambia si cambia la forma.
##
## El `SaveSystem.SAVE_VERSION` GLOBAL no se sube en esta fase, y es a
## propósito: el bloque "resultado" es OPCIONAL y su ausencia significa
## "partida en curso" —el mismo criterio que "mineria" y "refugios" cuando no
## están—, así que un guardado viejo carga sin tocar nada y un guardado nuevo lo
## carga un build viejo descartando la clave que no conoce. Subir la versión
## global no cambiaría una sola cosa de lo que se guarda y pondría en rojo los
## tres tests de otras fases que la pinean a 13.
const SAVE_VERSION: int = 1

const RUTA: String = "res://data/derrota.json"

## Final canónico (el Sello) y final alternativo (la Espada). Los valores son
## las keys de `data/derrota.json`, no los ids de misión: el id de cada una se
## LEE del dato (`mision_de_senda`), para que cambiar de misión sea tocar el
## JSON (§9.4).
const SENDA_LIBERTY: String = "liberty"
const SENDA_ARMA: String = "arma"

## La partida cambió de estado (victoria, muerte, revived).
signal cambiada()
## Se entregó una de las dos misiones finales. Se emite UNA vez por partida.
signal victoria(senda: String)
## El héroe murió en el mundo (no en la arena), se cobró el coste y se abrió
## la pantalla de derrota. `coste` es lo que se perdió.
signal muerte_registrada(coste: Dictionary)
## El jugador eligió revivir. El coste ya se había cobrado al morir, así que acá
## solo hay revivir.
signal revivido(coste: Dictionary)

## "liberty" / "arma" si la partida terminó, "" si sigue.
var senda: String = ""
## ¿Ya terminó? El final es terminal: nunca vuelve a false.
var terminada: bool = false
## Muertes de partida (fuera de la arena). Va al guardado: es el récord local
## que el jugador se lleva.
var muertes: int = 0
## Hay una muerte registrada y el jugador todavía no eligió revivir. Es lo que
## hace que el guardado sepa que había un final de derrota en el aire.
var derrota_pendiente: bool = false
## Lo que costó la última muerte; lo que muestra la pantalla de derrota.
var ultimo_coste: Dictionary = {}

var _jugador: Player = null
var _misiones: QuestLog = null
var _respawn: RespawnHeros = null

# --- los datos (§9.4: la pérdida y los finales son DATO, no código) -------

static var _datos: Dictionary = {}
static var _datos_cargados: bool = false


## Los datos de `derrota.json`, cacheados. Estático como los `*DB` del
## proyecto: el mismo dato lo leen el sistema, los dos paneles y los tests, y
## leer un archivo por frame es justo lo que §9.5 prohíbe.
static func datos() -> Dictionary:
	if _datos_cargados:
		return _datos
	_datos_cargados = true
	_datos = {}
	var texto: String = FileAccess.get_file_as_string(RUTA)
	if texto.is_empty():
		push_warning("[ResultadoPartida] no se pudo leer " + RUTA)
		return _datos
	var crudo: Variant = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[ResultadoPartida] JSON inválido: " + RUTA)
		return _datos
	_datos = crudo
	return _datos


## El bloque de derrota, o `{}`. Es donde vive el coste de morir.
static func datos_derrota() -> Dictionary:
	var d: Dictionary = datos()
	var bloque: Variant = d.get("derrota", {})
	return bloque if bloque is Dictionary else {}


static func datos_victoria() -> Dictionary:
	var d: Dictionary = datos()
	var bloque: Variant = d.get("victoria", {})
	return bloque if bloque is Dictionary else {}


## El id de misión de una senda, o "" si el dato no lo declara.
static func mision_de_senda(s: String) -> String:
	var sendas: Dictionary = datos_victoria().get("sendas", {})
	return str(sendas.get(s, ""))


## Las dos sendas, en el orden del dato.
static func sendas() -> Array[String]:
	var salida: Array[String] = []
	var sendas: Dictionary = datos_victoria().get("sendas", {})
	for s in sendas:
		salida.append(str(s))
	return salida


## El texto de un final, o `{}`. Lo lee la UI; el sistema nunca escribe en
## pantalla.
static func final_de(s: String) -> Dictionary:
	var finales: Dictionary = datos_victoria().get("finales", {})
	var bloque: Variant = finales.get(s, {})
	return bloque if bloque is Dictionary else {}


# --- configuración ---------------------------------------------------------

## Inyecta las dependencias y abre las dos suscripciones. La llama el demo
## ANTES de `RespawnHeros.configurar()`: ver el docstring de la clase.
func configurar(jugador: Player, misiones: QuestLog, respawn: RespawnHeros = null) -> void:
	desconectar()
	_jugador = jugador
	_misiones = misiones
	_respawn = respawn
	if _misiones != null and not _misiones.cambiada.is_connected(_revisar_victoria):
		_misiones.cambiada.connect(_revisar_victoria)
	if _jugador != null and is_instance_valid(_jugador):
		if not _jugador.murio.is_connected(_al_morir):
			_jugador.murio.connect(_al_morir)
	# UNA MIRADA INMEDIATA, y no es un detalle: en la partida, cuando este
	# sistema se configura, la misión final puede YA estar entregada — es lo que
	# pasa al "Continuar" de una partida ganada, porque `SaveSystem.cargar()`
	# restauró el `QuestLog` en el `_ready` de la demo, mucho antes de que el
	# mundo terminara de armarse. Sin esta llamada, la señal `cambiada` de esa
	# entrega ya pasó y no vuelve a pasar: el final se guardaba y no se
	# mostraba, que es la peor forma de perderlo.
	_revisar_victoria()


func desconectar() -> void:
	if _misiones != null and _misiones.cambiada.is_connected(_revisar_victoria):
		_misiones.cambiada.disconnect(_revisar_victoria)
	if _jugador != null and is_instance_valid(_jugador):
		if _jugador.murio.is_connected(_al_morir):
			_jugador.murio.disconnect(_al_morir)


## Lo llama el demo DESPUÉS de configurar, al terminar de arrancar el mundo.
## Reemite la victoria si el guardado ya traía una partida terminada, para que
## el panel se abra también al continuar una partida que ya ganó. Sin esto,
## cargar una partida ganada perdía el final en pantalla (el estado seguía
## guardado, pero nadie lo miraba).
func reanudar_tras_carga() -> void:
	if not terminada:
		return
	victoria.emit(senda)


# --- consultas -------------------------------------------------------------

func hay_victoria() -> bool:
	return terminada


## ¿La partida terminó con esta senda? Lo consulta el `PanelFinal`.
func es_senda(s: String) -> bool:
	return terminada and senda == s


# --- victoria --------------------------------------------------------------

## ¿Alguna de las dos misiones finales ya está entregada? Se llama sola con
## cada `cambiada` del log de misiones.
func _revisar_victoria() -> void:
	if terminada or _misiones == null:
		return
	for s in sendas():
		var mid: String = mision_de_senda(s)
		if mid == "":
			continue
		if _misiones.estado(mid) == "entregada":
			_registrar_victoria(s)
			return


## Registra el final y avisa. Idempotente: la segunda llamada no hace nada, así
## que da igual que la disparen dos señales del log, o una señal y una carga.
func _registrar_victoria(s: String) -> void:
	if terminada or s == "":
		return
	senda = s
	terminada = true
	derrota_pendiente = false
	cambiada.emit()
	victoria.emit(s)


## Fuerza el final sin pasar por el `QuestLog`. Para los tests: es la única
## forma de probar el `PanelFinal` sin entregar 5 actos de misiones.
func forzar_victoria(s: String) -> bool:
	if s == "" or not sendas().has(s):
		return false
	_registrar_victoria(s)
	return true


# --- derrota ---------------------------------------------------------------

## Lo que costaría morir AHORA, según `data/derrota.json`. FUNCIÓN PURA: no
## toca al jugador. Sirve para que la pantalla muestre la cifra, y para que el
## test verifique que el coste sale del dato y no de una constante en el código.
##
## El XP perdido sale de la parte del XP que todavía NO se gastó en el nivel
## actual: `xp_actual - Formulas.xp_for_level(nivel)`. El piso es ese mismo
## valor, o sea que morir JAMÁS hace bajar de nivel: se pierde el progreso del
## nivel en el que estás, no el nivel entero. Hacer bajar de nivel por morir
## sería la única forma de que la muerte destruyera el trabajo de las horas
## anteriores, y el juego ya es duro con los jefes de fragmento.
func coste_de(jugador: Player) -> Dictionary:
	var d: Dictionary = datos_derrota()
	var pct_oro: float = clampf(float(d.get("porcentaje_oro", 0.1)), 0.0, 1.0)
	var pct_xp: float = clampf(float(d.get("porcentaje_xp_nivel", 1.0)), 0.0, 1.0)
	if jugador == null or not is_instance_valid(jugador):
		return {"oro": 0, "xp": 0}
	var oro: int = int(floorf(float(jugador.oro) * pct_oro))
	var piso_xp: int = Formulas.xp_for_level(jugador.nivel)
	var en_nivel: int = maxi(0, jugador.xp_actual - piso_xp)
	var xp: int = int(floorf(float(en_nivel) * pct_xp))
	return {"oro": mini(oro, maxi(0, jugador.oro)), "xp": xp}


## Cobra el coste. Lo llama `_al_morir`, NUNCA la UI: la UI pide, el sistema
## cobra. Se cobra AL MORIR y no al revivir, por dos razones: el jugador ve el
## oro y el XP bajar en el HUD en el mismo frame en que muere (si se cobrara al
## revivir, la pantalla de derrota mentiría), y si cierra el juego desde la
## pantalla de derrota no se escapa del castigo.
func aplicar_coste(jugador: Player) -> Dictionary:
	var coste: Dictionary = coste_de(jugador)
	var xp: int = int(coste.get("xp", 0))
	var oro: int = int(coste.get("oro", 0))
	if xp > 0:
		jugador.perder_xp(xp)
	if oro > 0:
		jugador.perder_oro(oro)
	return coste


## El héroe murió. Corre ANTES que el handler del `RespawnHeros` (ver el
## docstring): cobra, pone a punto el respawn para que no teletransporte todavía
## y avisa.
func _al_morir(_fuente: Entity) -> void:
	if terminada or derrota_pendiente:
		return
	if _jugador == null or not is_instance_valid(_jugador):
		return
	# El respawn ya estaba suspenso: lo puso la Arena, cuya derrota por oleada
	# es suya y no nuestra. No se cobra nada ni se abre nada.
	if _respawn != null and is_instance_valid(_respawn) and _respawn.suspendido():
		return
	derrota_pendiente = true
	muertes += 1
	ultimo_coste = aplicar_coste(_jugador)
	if _respawn != null and is_instance_valid(_respawn):
		_respawn.suspender(true)
	cambiada.emit()
	muerte_registrada.emit(ultimo_coste)


## El jugador eligió revivir: vuelve el control al respawn y se teletransporta
## al último refugio. El coste ya se cobró al morir, así que acá no se cobra
## otra vez; el `derrota_pendiente` a false es lo que hace idempotente el doble
## clic en el botón.
func revivir() -> Dictionary:
	if not derrota_pendiente:
		return {}
	if _jugador == null or not is_instance_valid(_jugador):
		return {}
	derrota_pendiente = false
	liberar_respawn()
	var coste: Dictionary = ultimo_coste.duplicate()
	_jugador.reaparecer()
	cambiada.emit()
	revivido.emit(coste)
	return coste


## Devuelve el control al respawn. Para el guardado: si se recargó con una
## derrota a medio resolver, el héroe vuelve al mundo vivo y el respawn tiene
## que volver a estar operativo, o el próximo Stuck no tiene a dónde ir.
func liberar_respawn() -> void:
	if _respawn != null and is_instance_valid(_respawn):
		_respawn.suspender(false)


# --- guardado --------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"senda": senda,
		"terminada": terminada,
		"muertes": maxi(0, muertes),
		"derrota_pendiente": derrota_pendiente,
		"ultimo_coste": ultimo_coste.duplicate(),
	}


## Restaura el estado desde el bloque "resultado". Un guardado viejo (sin
## bloque, o `{}`) es una partida en curso, que es lo correcto: antes de esta
## fase no había forma de ganar ni de perder, así que todos los guardados que
## existen son partidas en curso.
##
## Una derrota a medio resolver se RESUELVE al cargar, no se reabre: el coste ya
## se cobró y ya está en el guardado (el oro y el XP del jugador), y el héroe
## vuelve vivo. Reabrir el panel de derrota sobre un héroe con la vida llena
## sería mentirle al jugador sobre lo que ya pagó. Lo que sí se conserva es el
## resultado: la cuenta de muertes, y el final si lo había.
func cargar_estado(bloque: Dictionary) -> void:
	if bloque.is_empty():
		return
	var version: int = int(bloque.get("version", 0))
	if version != SAVE_VERSION:
		# Tolerante, como el resto del save: se carga igual y se avisa. Un
		# bloque de otra versión con campos conocidos sigue siendo mejor que
		# perderle la partida al jugador.
		push_warning("[ResultadoPartida] versión de bloque %d (esperada %d); se carga igual"
			% [version, SAVE_VERSION])
	senda = str(bloque.get("senda", ""))
	terminada = bool(bloque.get("terminada", false)) and senda != ""
	muertes = maxi(0, int(bloque.get("muertes", 0)))
	derrota_pendiente = bool(bloque.get("derrota_pendiente", false))
	var coste: Variant = bloque.get("ultimo_coste", {})
	ultimo_coste = coste if coste is Dictionary else {}
	# Un final guardado sin el flag (un bloque a mano, o de otra versión) sigue
	# siendo un final: la senda es la prueba.
	if senda != "" and not terminada:
		terminada = true
	if derrota_pendiente:
		derrota_pendiente = false
		liberar_respawn()
	cambiada.emit()
