class_name Vitals
extends RefCounted
## Fase 54: los tres vitales de supervivencia. Fase 58 les agrega el decaimiento
## por tiempo; acá está el dato y la API para que la comida tenga a dónde ir.
##
## DECISIÓN DE JUAN DIEGO: a 0 NO matan. Noriegan al jugador a 1 de vida y le
## dejan un debuff. La muerte sigue viniendo de los enemigos y de los jefes.
## Es el tono "wholesome" que eligió la propia Jagex con Dragonwilds, y evita
## pelear con el respawn sin penalidad de la fase 51.
##
## Rango 0..100 en los tres, donde 100 = lleno.
##
## Es una clase PURA (sin nodos, sin reloj): el decaimiento lo empuja el
## Player con el delta de `_process`. Así es testeable headless con
## `avanzar(dt)` como ya se hace con `SpawnerMobs` y `Arena`.

## Los tres, en 0..100.
const MAXIMO: float = 100.0
## Umbral bajo el cual se considera "vacío" (el juego avisa, el debuff entra).
const UMBRAL_VACIO: float = 15.0

var hambre: float = MAXIMO
var sed: float = MAXIMO
## Energía = cansancio. Baja con el tiempo y con la actividad; al caer
## reduce la velocidad de ataque y la de movimiento (Fase 58), así que
## tiene efecto en combate de verdad y no es decorativa.
var energia: float = MAXIMO
## Fase 54: comer algo crudo o beber sin hervir puede enfermar. Mientras
## hay enfermedad, el hambre baja más rápido. Es el riesgo que hace que
## "cocinar" valga algo sin que el sistema sea letal.
var enfermedad: float = 0.0


## se llama cada frame, así que sin un umbral la señal sería 60 veces por
## segundo; el coste no es la señal, es el `queue_redraw` de cada barra detrás.
##
signal vital_cambiado(hambre: float, sed: float, energia: float, enfermedad: float)
## Fase 63: la enfermedad aparece y desaparece. Es un dato BOOLEANO, no un
## valor, así que va en su propia señal: la UI tiene que poder poner y quitar
## un icono, no interpolar nada.
signal enfermedad_cambiada(activa: bool)

## Umbral de movimiento para que la UI se entere (Fase 63).
const TOQUE_MIN: float = 0.5

## Lo que se emitió la última vez. Si no, el primer `avanzar` dispararía la
## señal de todas formas sin que nada haya cambiado de verdad.
var _ultimo_hambre: float = MAXIMO
var _ultimo_sed: float = MAXIMO
var _ultimo_energia: float = MAXIMO
var _ya_emitido: bool = false

var mult_hambre: float = 1.0
var mult_sed: float = 1.0


func _init(p_hambre: float = MAXIMO, p_sed: float = MAXIMO,
		p_energia: float = MAXIMO) -> void:
	hambre = clampf(p_hambre, 0.0, MAXIMO)
	sed = clampf(p_sed, 0.0, MAXIMO)
	energia = clampf(p_energia, 0.0, MAXIMO)


## Consume un alimento o bebida. Devuelve qué se movió (para el feedback).
## `efecto` es el bloque `efecto` de un item de data/items.json.
func consumir(efecto: Dictionary) -> Dictionary:
	var antes := {"hambre": hambre, "sed": sed, "energia": energia}
	hambre = clampf(hambre + float(efecto.get("hambre", 0.0)), 0.0, MAXIMO)
	sed = clampf(sed + float(efecto.get("sed", 0.0)), 0.0, MAXIMO)
	energia = clampf(energia + float(efecto.get("energia", 0.0)), 0.0, MAXIMO)
	var antes_enfermedad: bool = enfermedad > 0.0
	var riesgo: String = str(efecto.get("riesgo", ""))
	if riesgo == "enfermedad":
		enfermedad = maxf(enfermedad, 20.0)
	# Fase 63: comer se refleja en las barras al instante, no en el siguiente
	# `avanzar`. Y la enfermedad que causa la carne cruda enciende su propia
	# señal, que es la que pone el icono.
	_avisar_cambio(antes_enfermedad)
	return antes


## Fase 58: el decaimiento por tiempo. `mult_actividad` sube el gasto (pegar,
## correr, minar). Devuelve true si algún vital cruzó el umbral de vacío en
## este tick, para que el Player avise una sola vez.
## Fase 59: multiplicadores de decaimiento que escriben los Hechos. Vienen
## como parámetros y NO como referencia a `Hechos`: `Vitals` es puro y no
## debe depender de un sistema de talentos para contar el tiempo. El Player
## se los pasa cada frame.


## Fase 58: el decaimiento por tiempo. `mult_actividad` sube el gasto (pegar,
## correr, minar). Devuelve true si algún vital cruzó el umbral de vacío en
## este tick, para que el Player avise una sola vez.
## Fase 59: multiplicadores de decaimiento que escriben los Hechos. Vienen
## como parámetros y NO como referencia a `Hechos`: `Vitals` es puro y no
## debe depender de un sistema de talentos para contar el tiempo. El Player
## se los pasa cada frame.
func avanzar(dt: float, mult_actividad: float = 1.0) -> bool:
	var d: float = maxf(dt, 0.0)
	var m: float = maxf(mult_actividad, 0.0)
	# Rates base: una barra cada ~2 minutos de juego, suben con la actividad.
	# Con enfermedad el hambre se va el doble de rápido.
	var extra: float = 1.0 + (0.6 if enfermedad > 0.0 else 0.0)
	var antes_enfermedad: bool = enfermedad > 0.0
	hambre = clampf(hambre - d * 0.85 * m * extra * maxf(mult_hambre, 0.0), 0.0, MAXIMO)
	sed = clampf(sed - d * 0.62 * m * maxf(mult_sed, 0.0), 0.0, MAXIMO)
	energia = clampf(energia - d * 0.40 * m, 0.0, MAXIMO)
	if enfermedad > 0.0:
		enfermedad = maxf(enfermedad - d, 0.0)
	_avisar_cambio(antes_enfermedad)
	return vacio()


## Fase 63: si algún valor se movió lo bastante, emite. Devuelve si emitió, que
## es lo que usan los tests para comprobar que NO emite en cada frame.
func _avisar_cambio(antes_enfermedad: bool) -> bool:
	var ahora_enfermedad: bool = enfermedad > 0.0
	if ahora_enfermedad != antes_enfermedad:
		enfermedad_cambiada.emit(ahora_enfermedad)
	var movido: bool = not _ya_emitido \
			or absf(hambre - _ultimo_hambre) >= TOQUE_MIN \
			or absf(sed - _ultimo_sed) >= TOQUE_MIN \
			or absf(energia - _ultimo_energia) >= TOQUE_MIN
	if not movido:
		return false
	_ya_emitido = true
	_ultimo_hambre = hambre
	_ultimo_sed = sed
	_ultimo_energia = energia
	vital_cambiado.emit(hambre, sed, energia, enfermedad)
	return true


## ¿Alguno de los tres está en la franja baja?
func vacio() -> bool:
	return hambre < UMBRAL_VACIO or sed < UMBRAL_VACIO or energia < UMBRAL_VACIO


## Nombre del vital más bajo, para el aviso. "" si nada está bajo.
func mas_bajo() -> String:
	var peor: String = ""
	var valor: float = MAXIMO
	if hambre < valor:
		valor = hambre
		peor = "hambre"
	if sed < valor:
		valor = sed
		peor = "sed"
	if energia < valor:
		peor = "energia"
	return peor if valor < UMBRAL_VACIO else ""


## Multiplicador de velocidad de movimiento por energía (Fase 58).
func mult_velocidad() -> float:
	if energia >= 50.0:
		return 1.0
	return lerpf(0.72, 1.0, clampf(energia / 50.0, 0.0, 1.0))


## Multiplicador de velocidad de ataque por energía (Fase 58).
func mult_ataque() -> float:
	if energia >= 50.0:
		return 1.0
	return lerpf(0.75, 1.0, clampf(energia / 50.0, 0.0, 1.0))


func esta_lleno() -> bool:
	return is_equal_approx(hambre, MAXIMO) and is_equal_approx(sed, MAXIMO) \
			and is_equal_approx(energia, MAXIMO)


func to_dict() -> Dictionary:
	return {
		"hambre": hambre,
		"sed": sed,
		"energia": energia,
		"enfermedad": enfermedad,
	}


static func from_dict(d: Dictionary) -> Vitals:
	var v := Vitals.new(
		float(d.get("hambre", MAXIMO)),
		float(d.get("sed", MAXIMO)),
		float(d.get("energia", MAXIMO)))
	v.enfermedad = clampf(float(d.get("enfermedad", 0.0)), 0.0, 999.0)
	return v
