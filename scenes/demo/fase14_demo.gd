extends "res://scenes/demo/fase12_demo.gd"
## Demo de la fase 14: rework 2026 del mapa — ciudad principal "Moon Town".
## Fase 15: ademas construye las 8 ciudades secundarias (desierto, volcan,
## norte, mistica, sombra, furia, tormenta, dorada) con el CiudadLuna
## generalizado (`centro` regional, `luces_reales = false`).
##
## Hereda TODO de fase12_demo (mundo abierto, streaming de mobs, regiones +
## banner, ciclo día/noche, minimapa + brújula, flujo título → creación →
## juego con Continuar y F9/F10) y añade las ciudades:
## - `CiudadLuna` se crea con el terreno asignado ANTES del add_child
##   (contrato de su API); su `_ready` construye los 18 edificios y emite
##   `ciudad_lista`. El ciclo día/noche también se asigna antes (modula las
##   antorchas de la ciudad). Las 8 secundarias (16 edificios c/u) usan
##   FalsaAntorcha en vez de OmniLight3D.
## - El jugador aparece en `punto_aparicion_jugador()` (plaza, sobre el
##   terreno) mirando con `yaw_aparicion()`.
## - Los NPCs Ilya/Bram/Sira se recolocan en `npc_spawn(id)` (data-driven);
##   los 8 ambientales van a su ciudad secundaria.
## Es scaffolding de demo, no un sistema del juego.

## La ciudad construida (data/ciudad_luna.json: 18 edificios procedurales).
var _ciudad: CiudadLuna = null

## Fase 15: las 8 ciudades secundarias (mismo CiudadLuna generalizado,
## con `luces_reales = false` y su `centro` regional). Se construyen en
## _ready() antes de super._ready(), igual que Moon Town.
var _ciudades_sec: Array = []
## Fase 51: sistema de muerte y respawn del héroe (ver respawn_heroe.gd).
var _respawn: RespawnHeros = null
## Fase 51.1: contenedor de sistemas (§9.1). Descubrimiento por `system_id`
## en vez de rutas de nodo hardcodeadas.
var _sistemas: Systems = null
## Fase 53: barra de jefe (UI). La maneja la selección del jugador.
var _barra_jefe: BarraJefe = null
## Hotfix 62.1: feed global de avisos (capa 16), registrado en `Systems`.
var _feed: FeedAvisos = null
## Fase 63: hambre, sed y energía (capa 17).
var _vitales: IndicadorVitales = null
## Fase 64: el rótulo "E — Prender fogata" (capa 18).
var _prompt: PromptInteraccion = null
## Fase 64: el panel de recetas (capa 34).
var _cocina: PanelCocina = null
## Fase 64: el modo construcción (capa 33).
var _construccion: PanelConstruccion = null
## Bloque 68: el CÓDICE / bestiario (capa 35). Nace cerrado y lo abre la tecla L.
var _codice: PanelCodice = null
## FASE 72: el panel del NG+ (capa 36), que existía desde el bloque 68 con sus
## tests en verde y NO estaba en la partida. Con él invisible se perdían los 12
## trofeos de `data/ngplus_trofeos.json` y la lista de encargos del día de
## `data/diarias.json`. Lo abre la tecla N.
var _ngplus: PanelNgPlus = null
## Bloque 65: pausa y opciones.
var _pausa: MenuPausa = null
## Bloque 68: los efectos que hacen que un golpe se sienta.
var _pool_impacto: PoolImpacto = null
var _opciones: PanelOpciones = null
## Ola 2: el panel de objetivo del tutorial. Es el TERCER caso de la misma cosa
## (el panel existe, sus tests pasan, y no estaba en la partida), asi que va
## conectado a mano y con una entrada en el smoke.
var _tutorial_ui: PanelTutorial = null
## Fase 72: victoria y derrota. El sistema (RefCounted) y los dos paneles.
## CUARTO y QUINTO caso de lo mismo — ver el bloque de `_instalar_fase72()`.
var _resultado: ResultadoPartida = null
var _panel_final: PanelFinal = null
var _panel_derrota: PanelDerrota = null
## Fase 55: gestor de arboles talables (streaming por histéresis).
var _arboles: GestorArboles = null
## Fase 70: la vegetación del mundo abierto. Un anillo que sigue al jugador con
## LOD por distancia; NUNCA todo a la vez (serían cientos de miles de mallas
## para las 36.864 u de lado, y el presupuesto de VRAM es 1 GB).
var _vegetacion: Vegetacion = null
## Fase 56: las fogatas de las ciudades (estación de cocina).
var _fogatas: Array = []
## Fase 60: los 9 refugios reclamables.
var _refugios: Array = []

const _SECUNDARIAS: Array = [
	["CiudadDesert", "res://data/ciudad_desert.json", Vector2(9966, 0)],
	["CiudadFire", "res://data/ciudad_fire.json", Vector2(-9966, 0)],
	["CiudadNorth", "res://data/ciudad_north.json", Vector2(0, -5358)],
	["CiudadMystic", "res://data/ciudad_mystic.json", Vector2(0, 9966)],
	["CiudadShadow", "res://data/ciudad_shadow.json", Vector2(9966, -9966)],
	["CiudadRage", "res://data/ciudad_rage.json", Vector2(-9966, -9966)],
	["CiudadFury", "res://data/ciudad_fury.json", Vector2(-9966, 9966)],
	["CiudadGolden", "res://data/ciudad_golden.json", Vector2(9966, 9966)],
]

## Fase 15: a que ciudad secundaria pertenece cada NPC ambiental
## (indice en _ciudades_sec / _SECUNDARIAS). Ilya/Bram/Sira van a Moon Town.
## Fase 16: los 9 porteros de viaje rápido van a su ciudad (el de Moon Town
## cae a Moon Town por defecto, igual que Ilya/Bram/Sira).
const _NPC_CIUDAD_SEC: Dictionary = {
	"yasmina": 0, "durnan": 1, "sella": 2, "elthar": 3,
	"vex": 4, "karg": 5, "maris": 6, "aurelio": 7,
	"portero_desert": 0, "portero_fire": 1, "portero_north": 2,
	"portero_mystic": 3, "portero_shadow": 4, "portero_rage": 5,
	"portero_fury": 6, "portero_golden": 7,
}

## Fase 16: lógica del viaje rápido (sin UI; la UI solo lee).
var _viaje: ViajeRapido = null
@onready var _panel_viaje: PanelViaje = $PanelViaje
## Fase 41: arena PvE (manager de oleadas; los trofeos viajan en el save).
var _arena: Arena = null
## Punto de retorno al salir de la arena (plaza del Maestro).
var _retorno_arena: Vector3 = Vector3.ZERO
## Fase 45: minería (coloca las vetas de la región y las hace minar con E).
var _mineria: GestorVetas = null
## Fase 46: manual de ayuda (controles y mecánicas), con la tecla `?`.
var _ayuda: PanelAyuda = null
const ESCENA_AYUDA: PackedScene = preload("res://scenes/ui/panel_ayuda.tscn")
## Bloque 68: el CÓDICE / bestiario, con la tecla L.
const ESCENA_CODICE: PackedScene = preload("res://scenes/ui/panel_codice.tscn")


func _ready() -> void:
	# La API de CiudadLuna exige `terreno` asignado ANTES del add_child.
	# Se crea primero para que el mundo exista cuando super._ready() pegue
	# al terreno, arranque el streaming y levante la orientación.
	_ciudad = CiudadLuna.new()
	_ciudad.name = "CiudadLuna"
	_ciudad.terreno = $Terreno as Terreno
	_ciudad.ciclo = $CicloDia as CicloDia
	# Fase 20: las 9 ciudades se construyen por partes (pantalla de carga);
	# `npc_spawn`/recolocación esperan a `_al_mundo_listo()`.
	_ciudad.construccion_progresiva = true
	add_child(_ciudad)
	# Fase 15: las 8 ciudades secundarias (mismo contrato de API:
	# terreno/ciclo/centro/cargar_datos ANTES del add_child).
	for spec in _SECUNDARIAS:
		var c := CiudadLuna.new()
		c.name = str(spec[0])
		c.terreno = $Terreno as Terreno
		c.ciclo = $CicloDia as CicloDia
		c.centro = spec[2]
		c.luces_reales = false
		c.cargar_datos(str(spec[1]))
		c.construccion_progresiva = true
		add_child(c)
		_ciudades_sec.append(c)
	super._ready()
	_instalar_respawn()


## Fase 60: los 9 refugios, uno por plaza. Se registran en `Systems` para que
## el jugador (y el respawn) los encuentren por id, no por ruta de nodo.
func _colocar_refugios() -> void:
	for id in RefugioDB.ids():
		var r := Refugio.new()
		r.name = "Refugio_%s" % id
		add_child(r)
		r.configurar_por_id(id)
		if _terreno != null:
			r.position.y = _terreno.altura_en(r.position.x, r.position.z)
		_refugios.append(r)
		_sistemas_de().registrar(r, StringName("refugio:" + id))
		# Fase 64: al reclamar, el refugio pasa a ser punto seguro. Antes el
		# ancla de reaparición venía solo de `CiudadLuna` y reclamar no
		# cambiaba NADA, que era una de las debts del bloque 53–62.
		r.reclamado.connect(_al_reclamar_refugio.bind(r))
		# Fase 64: en un refugio reclamado, la E abre el modo construcción.
		r.construir_solicitado.connect(_al_construir.bind(r))


## Fase 56: una fogata junto a cada plaza. Sin leña no se cocina, y la leña
## sale de los troncos de la tala (fase 55): así la recolección tiene
## consumidor y cocinar es una decisión, no un trámite.
func _colocar_fogatas() -> void:
	var plazas: Array = [Vector3(38.0, 0.0, 52.0)]
	for c in _ciudades_sec:
		plazas.append((c as CiudadLuna).punto_aparicion_jugador()
			+ Vector3(26.0, 0.0, 26.0))
	for i in range(plazas.size()):
		var f := Fogata.new()
		f.name = "Fogata_%d" % i
		# `add_child` ANTES de tocar `global_position`: en un nodo que todavia no
		# esta en el arbol, pedir la transformada global tira nueve
		# "Condition !is_inside_tree() is true" por arranque. Son nueve lineas de
		# ruido que tapan errores de verdad en el log, y el maestro de hoy es
		# justamente ese: hay que poder ver el log limpio para saber si algo roto.
		add_child(f)
		f.global_position = plazas[i]
		if _terreno != null:
			f.position.y = _terreno.altura_en(f.position.x, f.position.z)
		_fogatas.append(f)
		f.add_to_group(&"fogatas")
		# Fase 64: prender una fogata se anuncia, y el panel se abre con un
		# segundo E (la primera vez solo la prende).
		f.llama_encendida.connect(_al_prender_fogata.bind(f))
		f.cocinar_solicitado.connect(_al_pedir_cocina.bind(f))


## Fase 53: barra de jefe. Escucha la selección del jugador: si lo que
## seleccionó es un jefe (`Enemy.es_jefe`), la muestra; si no, la esconde.
## Solo LEE al enemigo por señales.
func _instalar_barra_jefe() -> void:
	_barra_jefe = BarraJefe.new()
	_barra_jefe.name = "BarraJefe"
	add_child(_barra_jefe)
	_jugador.seleccion_cambiada.connect(_al_seleccion_cambiada)


## Hotfix 62.1: el feed global de avisos, y el enganche de los Hechos.
##
## El feed se registra en `Systems` para que lo encuentre CUALQUIER sistema
## (`Systems.obtener(&"feed_avisos")`) sin tener que pasárselo de mano, que es
## lo que §9 quiere. Y los Hechos se escuchan acá y no dentro de `Hechos`,
## para que la lógica no sepa que existe una UI.
## El contenedor `Systems`, creandolo la primera vez que se pide.
##
## BUG REAL (encontrado jugando): antes era un `var` que se asignaba en
## `_al_mundo_listo()`, que corre DESPUES del `_ready` que registra el feed de
## avisos y el pool de impacto.registrar sobre nil reventaba. Al pedirlo por metodo,
## el orden deja de importar: si aun no existe, se crea aqui.
func _sistemas_de() -> Systems:
	if _sistemas == null or not is_instance_valid(_sistemas):
		_sistemas = Systems.new()
		_sistemas.name = "Systems"
		add_child(_sistemas)
	return _sistemas


func _instalar_feed_avisos() -> void:
	_feed = FeedAvisos.new()
	_feed.name = "FeedAvisos"
	add_child(_feed)
	_sistemas_de().registrar(_feed, &"feed_avisos")
	if _jugador.hechos != null:
		_jugador.hechos.hecho_desbloqueado.connect(_al_desbloquear_hecho)
## Fase 64: E sobre un refugio reclamado abre el modo construcción. Es la
## misma tecla que prende la fogata y que reclama el refugio: qué hace la E
## depende de en qué estás parado, y el prompt lo dice.
func _al_construir(r: Refugio) -> void:
	if _construccion != null and _jugador != null and r != null:
		_construccion.abrir(_jugador, r)


## Fase 64: la fogata se prendió. Se anuncia en el feed con el tronco que
## se gastó, que es la información que el jugador necesita para decidir la
## próxima vez ("un tronco = 12 s, y la carne asada gasta 1").
func _al_prender_fogata(f: Fogata) -> void:
	if _feed != null and f != null:
		_feed.aviso("Fogata prendida · %d s de leña" % int(f.lena))


## Fase 64: E sobre la fogata encendida abre las recetas.
func _al_pedir_cocina(f: Fogata) -> void:
	if _cocina != null and _jugador != null and f != null:
		_cocina.abrir(_jugador, f)


## Fase 64: un refugio reclamado se vuelve el ancla de reaparición. Se conecta
## a la SEÑAL y no dentro de `Refugio.reclamar()`, para que la lógica no sepa
## que existe un sistema de respawn.
func _al_reclamar_refugio(_refugio_id: String, r: Refugio) -> void:
	if _respawn != null and r != null:
		_respawn.anclar_refugio(r)
		if _feed != null:
			_feed.logro(r.nombre, "Punto seguro. Ya reaparecés acá.")


func _instalar_fase63_64_ui() -> void:
	# Bloque 68: el pool de impactos y el gestor de proyectiles. Se crean al
	# PRINCIPIO de la escena (antes que el jugador) para que el primer golpe
	# ya tenga efectos: crearlos en el primer impacto es una alloc en el frame
	# que no puede Jump.
	_pool_impacto = PoolImpacto.new()
	_pool_impacto.name = "PoolImpacto"
	add_child(_pool_impacto)
	_sistemas_de().registrar(_pool_impacto, &"pool_impacto")

	# Fase 72: el ambiente por zona y los avisos del jugador.
	#
	# Los dos son sistemas que se SUSCRIBEN a señales de la sesión, y por eso
	# se crean aquí (que es donde la sesión ya está construida) y no dentro de
	# `Player`: `scripts/player/player.gd` no es de esta fase. Sin ellos el bus
	# `Ambiente` seguía sin un solo player y el hambre, la sed, la
	# enfermedad, subir de nivel y desbloquear un Hecho seguían mudos.
	var ambiente := AmbienteZona.new()
	ambiente.name = "AmbienteZona"
	add_child(ambiente)
	ambiente.vigilar(_jugador)
	_sistemas_de().registrar(ambiente, &"ambiente_zona")
	var avisos := AvisosJugador.new()
	avisos.name = "AvisosJugador"
	add_child(avisos)
	avisos.vigilar(_jugador)
	_sistemas_de().registrar(avisos, &"avisos_jugador")

	# Bloque 65: el menú de pausa y el panel de opciones. Se instalan AL FINAL
	# y por encima de todo, y son los únicos que registran el árbol como
	# pausado. La pausa es dueña de la pila de paneles.
	_pausa = MenuPausa.new()
	_pausa.name = "MenuPausa"
	add_child(_pausa)
	_sistemas_de().registrar(_pausa, &"menu_pausa")
	_opciones = PanelOpciones.new()
	_opciones.name = "PanelOpciones"
	add_child(_opciones)
	_sistemas_de().registrar(_opciones, &"panel_opciones")
	# Las opciones se aplican al arrancar: si el jugador guardó un volumen
	# bajo, el juego arranca bajo, no a full hasta que abra el menú.
	Opciones.cargar()
	Opciones.aplicar()

	# Fase 63: los tres vitales en pantalla. `vigilar` se suscribe a las
	# señales de `Vitals`; la UI no lee nada por frame.
	_vitales = IndicadorVitales.new()
	_vitales.name = "IndicadorVitales"
	add_child(_vitales)
	_sistemas_de().registrar(_vitales, &"indicador_vitales")
	_vitales.vigilar(_jugador)
	# Fase 64: el prompt contextual. Se pone junto al feed porque los dos son
	# "capas de información del mundo", no paneles.
	_prompt = PromptInteraccion.new()
	_prompt.name = "PromptInteraccion"
	add_child(_prompt)
	_sistemas_de().registrar(_prompt, &"prompt_interaccion")
	_prompt.vigilar(_jugador)
	# Fase 64: el panel de cocina. Nace cerrado (lección 11) y se abre desde
	# la fogata, no desde el HUD: cocinar es una decisión de sitio.
	_cocina = PanelCocina.new()
	_cocina.name = "PanelCocina"
	add_child(_cocina)
	_sistemas_de().registrar(_cocina, &"panel_cocina")
	# Fase 64: el modo construcción del refugio.
	_construccion = PanelConstruccion.new()
	_construccion.name = "PanelConstruccion"
	add_child(_construccion)
	_sistemas_de().registrar(_construccion, &"panel_construccion")

	# Ola 2: el objetivo del tutorial. Nace oculto: el `Tutorial` de la fase 39
	# lo abre solo en partida nueva y se puede reabrir con T, y un jugador con 20
	# niveles no tiene por qué ver un "camina 30 m" en la esquina.
	_tutorial_ui = PanelTutorial.new()
	_tutorial_ui.name = "PanelTutorial"
	add_child(_tutorial_ui)
	_sistemas_de().registrar(_tutorial_ui, &"panel_tutorial")
	if _tutorial != null:
		_tutorial_ui.conectar(_tutorial)


## FASE 72: victoria y derrota, conectados a la partida.
##
## ESTA FUNCIÓN ES EL CUARTO CASO DE "ESCRITO Y NO CONECTADO", y por eso está
## llamada a mano desde `_instalar_respawn()` en vez de agrupada con el resto de
## la UI. El
## `smoke_fase_escena_completa` mira que los dos paneles estén registrados en
## `Systems`; sin esa entrada, esta función podía dejar de llamarse y nadie se
## enteraría (es EXACTAMENTE lo que pasó con `_instalar_fase63_64_ui()`).
##
## EL ORDEN DE ESTA FUNCIÓN DENTRO DE LA PARTIDA ES LO ÚNICO IMPORTANTE:
## `ResultadoPartida.configurar()` tiene que correr ANTES que
## `RespawnHeros.configurar()` (que está en la línea de abajo de este bloque),
## porque los dos se suscriben a `jugador.murio` y el que se suscribe primero
## es el que se ejecuta primero. Si el respawn corriera antes, el héroe ya
## estaría teletransportado y revivido cuando se cobrara la penalización, y la
## pantalla de derrota se abriría sobre un héroe vivo.
func _instalar_fase72() -> void:
	# El sistema es un `RefCounted` (no vive en el árbol), como `SaveSystem` y
	# `ViajeRapido`: se registra en `Systems` para que los paneles lo encuentren
	# por id y no por una ruta de nodo.
	#
	# Y se TOMA el que ya está en el `SaveSystem` en vez de crear uno nuevo: el
	# `SaveSystem` lo crea al construirse (no es nullable, por el mismo motivo
	# que el NG+) y `cargar()` ya lo restauró ANTES de que esta función corra
	# (super._ready() llama a cargar, y esta función se llama después). Crear
	# uno acá y asignarlo tiraría el resultado cargado por el suelo: una
	# partida ganada se seguiría jugando como si no estuviera ganada.
	_resultado = _guardado.resultado
	_sistemas_de().registrar(_resultado, &"resultado_partida")
	_resultado.configurar(_jugador, _misiones, _respawn)

	# Los dos paneles de final (capa 92) y de derrota (capa 93). Nacen
	# CERRADOS (lección 11) y los abre una señal, no una tecla.
	_panel_final = PanelFinal.new()
	_panel_final.name = "PanelFinal"
	add_child(_panel_final)
	_sistemas_de().registrar(_panel_final, &"panel_final")
	_panel_final.vigilar(_resultado)

	_panel_derrota = PanelDerrota.new()
	_panel_derrota.name = "PanelDerrota"
	add_child(_panel_derrota)
	_sistemas_de().registrar(_panel_derrota, &"panel_derrota")
	_panel_derrota.vigilar(_resultado)

	# Si el guardado ya traía una partida terminada, la señal `victoria` pasó
	# antes de que existiera este sistema: se reemite para que el final se
	# abra también al "Continuar" de una partida ya ganada.
	_resultado.reanudar_tras_carga()


func _al_desbloquear_hecho(hecho_id: String) -> void:
	if _feed == null or _jugador.hechos == null:
		return
	# El título solo ("Leñador") no dice nada; el detalle es lo que explica qué
	# cambió de verdad. Por eso el feed de logros lleva dos líneas.
	_feed.logro(_jugador.hechos.nombre_de(hecho_id),
		_jugador.hechos.descripcion_de(hecho_id))


func _al_seleccion_cambiada(e: Entity) -> void:
	if _barra_jefe == null:
		return
	if e != null and e is Enemy and (e as Enemy).es_jefe:
		_barra_jefe.vigilar(e)
	else:
		_barra_jefe.desvigilar()


## Fase 51: el sistema que revive al héroe. Se registra DESPUÉS de
## super._ready() porque las ciudades y el jugador ya existen: las plazas
## salen de `CiudadLuna.punto_aparicion_jugador()`, que consulta la altura
## real del terreno (las de `viaje_rapido.json` traen un `y = 45.0` que llega
## a estar 175 u por debajo de la superficie).
func _instalar_respawn() -> void:
	_respawn = RespawnHeros.new()
	_respawn.name = "RespawnHeros"
	add_child(_respawn)

	_respawn.registrar_ciudad("moon_town",
		_ciudad.punto_aparicion_jugador(), _ciudad.yaw_aparicion())
	for i in range(_ciudades_sec.size()):
		var c: CiudadLuna = _ciudades_sec[i]
		_respawn.registrar_ciudad(str(_SECUNDARIAS[i][0]),
			c.punto_aparicion_jugador(), c.yaw_aparicion())

	# FASE 72 Y POR QUÉ ESTÁ EN MEDIO DE ESTA FUNCIÓN, Y NO EN
	# `_instalar_fase63_64_ui()`: el ORDEN de los suscriptores a `jugador.murio`
	# es el orden de conexión, y acá importa. `RespawnHeros` teletransporta al
	# héroe dentro de la señal `murio`; si el sistema de derrota se conectara
	# después, la pantalla de derrota se abriría sobre un héroe ya revivido con
	# la vida llena y el coste se aplicaría dos veces. Por eso
	# `ResultadoPartida.configurar()` va ANTES que `RespawnHeros.configurar()`
	# y no en `_al_mundo_listo()`: el respawn se configura en el `_ready` (línea
	# 132), mucho antes de que el mundo esté listo.
	_instalar_fase72()
	_respawn.configurar(_jugador, _arena)
	_instalar_barra_jefe()
	_instalar_feed_avisos()
	# Fase 51: la arena y el respawn se conocen. Mientras corre una partida de
	# arena, el respawn se pone a punto (si no, al morir el heroe se iria a la
	# ciudad a media partida).
	if _arena != null and is_instance_valid(_arena):
		_arena.fijar_respawn(_respawn)


## Fase 20: el mundo terminó de construirse por partes. Aquí (y no en
## _ready) van los pasos que necesitan ciudades completas: recolocar al
## jugador/NPCs (`npc_spawn` se llena al final de construir) y el viaje.
func _al_mundo_listo() -> void:
	# Fase 51.1: el contenedor de sistemas (§9.1). Los sistemas se registran
	# acá, con su id, en vez de que cada uno ande buscándose por rutas de nodo.
	# BUG REAL (encontrado jugando): el contenedor se creaba aquí, pero
	# `_instalar_respawn()` ya corría en el `_ready` del padre y registraba el
	# feed en un `_sistemas` nulo ("Nonexistent function 'registrar' in base
	# 'Nil'"). Se pide por `_sistemas_de()`, que lo crea la primera vez que hace
	# falta, y aquí ya solo se reutiliza.
	_sistemas_de()
	#
	# BUG REAL Y EL MÁS GRAVE QUE HA TENIDO EL JUEGO: la función de abajo
	# instanciaba SIETE sistemas y NO LA LLAMABA NADIE. Estaba escrita, con sus
	# siete vars declaradas, sus tests en verde y su commit; y en la partida no
	# existía: sin `MenuPausa` el ESC no hacía nada, sin `IndicadorVitales` no
	# había barras de hambre/sed/energía, sin `PromptInteraccion` no aparecía el
	# "E — Prender fogata", sin `PoolImpacto` no había chispas, y `PanelCocina` y
	# `PanelConstruccion` tampoco. Fases 63 y 64 enteras más los bloques 65 y 68,
	# invisibles.
	#
	# Por qué ningún test lo cazó: los tests de cada panel lo montan en su
	# propia escena, y ningún test se preguntaba qué hay realmente dentro de la
	# partida. Un test verde por sistema no dice nada sobre si el sistema está
	# conectado. Por eso se agrega `smoke_fase_escena_completa`, que mira la
	# escena real.
	_instalar_fase63_64_ui()
	# El SaveSystem lo crea la demo padre (fase4) en su _ready, que ya
	# corrió: se registra acá, que es el primer punto donde el contenedor
	# existe.
	if _guardado != null and is_instance_valid(_guardado):
		_sistemas_de().registrar(_guardado, &"save_system")

	# Jugador y NPCs a sus puntos data-driven de Moon Town.
	_colocar_en_ciudad()
	# Fase 16: viaje rápido — "Viajar" en el diálogo del portero abre el
	# PanelViaje con la ciudad del portero como origen.
	_viaje = ViajeRapido.new()
	_viaje.cargar_datos()
	_sistemas_de().registrar(_viaje, &"viaje_rapido")
	# Fase 50.4: el panel se fabricaba su propia `ViajeRapido` aparte de esta,
	# y quedaban dos cachés de viaje_rapido.json vivas a la vez. Le pasamos la
	# nuestra, que es la única fuente de verdad.
	_panel_viaje.fijar_viaje(_viaje)
	_dialogo.viaje_solicitado.connect(_al_viaje_dialogo)
	_panel_viaje.viaje_solicitado.connect(_al_destino_viaje)
	# Fase 41: arena — "Entrenar" con el Maestro teletransporta al campo
	# remoto y arranca las oleadas; los trofeos se guardan con la partida.
	_arena = Arena.new()
	_arena.name = "Arena"
	_sistemas_de().registrar(_arena, &"arena")
	add_child(_arena)
	_arena.configurar(_cargar_arena_json())
	_arena.fijar_factory(_crear_enemigo_arena)
	_arena.fijar_pool(_pool)
	_arena.fijar_arquetipos(_arquetipos)
	_arena.fijar_jugador(_jugador)
	_arena.oleada_iniciada.connect(_al_arena_oleada)
	_arena.oleada_superada.connect(_al_arena_superada)
	_arena.arena_terminada.connect(_al_arena_terminada)
	_arena.ayuda_oleada.connect(_al_arena_ayuda)
	_dialogo.arena_solicitada.connect(_al_arena_dialogo)
	_guardado.arena = _arena
	# Fase 45: minería — 12 vetas de `data/vetas.json`, instanciadas por
	# región (histéresis 700/900 m). El jugador las mina con el segundo clic o
	# con E; el estado de cada veta (usos + respawn) viaja en el save.
	_mineria = GestorVetas.new()
	_mineria.name = "GestorVetas"
	_sistemas_de().registrar(_mineria, &"gestor_vetas")
	# Fase 55: tala. Mismo streaming por histéresis que el de vetas.
	_arboles = GestorArboles.new()
	_arboles.name = "GestorArboles"
	add_child(_arboles)
	_arboles.fijar_jugador(_jugador)
	_sistemas_de().registrar(_arboles, &"gestor_arboles")
	# Fase 70: lo mismo para la vegetación, con la diferencia de que NO hay
	# histéresis: no es un recurso que se pueda recolectar (es decorativo y no
	# se guarda) sino un anillo que se replanta cuando el jugador se movió lo
	# bastante. El terreno va PRIMERO porque `altura_en` es lo que pega cada
	# planta al suelo.
	_vegetacion = Vegetacion.new()
	_vegetacion.name = "Vegetacion"
	add_child(_vegetacion)
	_vegetacion.fijar_terreno($Terreno as Terreno)
	_vegetacion.fijar_jugador(_jugador)
	_sistemas_de().registrar(_vegetacion, &"vegetacion")
	# Fase 56: una fogata por ciudad, como los herreros. Es la estación de
	# cocina; las piezas que el jugador coloca llegan en la fase 61.
	_colocar_fogatas()
	_colocar_refugios()
	# Bloque 65: el estado del mundo se guarda (árboles talados, refugios con
	# sus piezas). Va AQUÍ, después de que los refugios existan: antes, cargar
	# una partida devolvía los árboles al estado inicial y vaciaba los refugios.
	if _guardado != null:
		_guardado.arboles = _arboles
		_guardado.refugios = _refugios
		# BUG REAL (playtest de la ola 3): `cargar()` corrió en el `_ready`, cuando
		# estos arrays todavía estaban vacíos, así que el estado del mundo del
		# guardado se aplicó contra listas vacías. Peor: el próximo guardado pisaba
		# lo guardado con lo recién construido y la reclamación del refugio se
		# perdía PARA SIEMPRE. Se reaplica recién acá, cuando ya existen.
		if _guardado.has_method("aplicar_estado_mundo"):
			_guardado.aplicar_estado_mundo()
	add_child(_mineria)
	_mineria.configurar_desde_datos()
	_mineria.fijar_terreno($Terreno as Terreno)
	_mineria.fijar_jugador(_jugador)
	_mineria.minado.connect(_al_minado)
	_guardado.mineria = _mineria
	_mineria.actualizar()
	if _hud != null and is_instance_valid(_hud) and _hud.boton_ayuda() != null:
		print("[Fase46] manual de ayuda listo: botón ? arriba a la derecha, o tecla ?")
	print("[Fase45] minería: %d vetas registradas, %d en el mapa cerca"
			% [_mineria.conteo_registros(), _mineria.conteo_vetas()])
	# Fase 46: el manual de ayuda. Se pone `abrir_al_arrancar = false` porque
	# en la ESCENA va en true (para poder correrla sola con F6 y revisarla).
	_ayuda = ESCENA_AYUDA.instantiate() as PanelAyuda
	_ayuda.abrir_al_arrancar = false
	add_child(_ayuda)
	# El botón "?" del HUD abre el mismo manual que la tecla.
	if _hud != null and is_instance_valid(_hud):
		_hud.ayuda_solicitada.connect(_al_ayuda_hud)
	# Bloque 68: el CÓDICE, al lado del manual, por el mismo motivo y con la
	# misma forma (sale de la ESCENA para poder correrlo suelto con F6, y nace
	# cerrado porque lo abre la tecla L).
	#
	## POR QUÉ AQUÍ Y NO EN `_instalar_fase63_64_ui()`: esa función NO LA LLAMA
	## NADIE (ni el juego ni los tests la invocan desde la escena), así que lo
	# que se cuelgue ahí no existe en la partida. Va en `_al_mundo_listo()`,
	# que es donde vive el resto de la UI que sí se ve.
	_codice = ESCENA_CODICE.instantiate() as PanelCodice
	_codice.abrir_al_arrancar = false
	_codice.name = "PanelCodice"
	add_child(_codice)
	_sistemas_de().registrar(_codice, &"panel_codice")
	# FASE 72: y el panel del NG+, por el mismo motivo y en el mismo lugar. Es
	# el CUARTO sistema escrito, testeado y no conectado (los otros tres
	# estaban en `_instalar_fase63_64_ui()`, que no llama nadie).
	#
	# No sale de una ESCENA porque no tiene una: `PanelNgPlus` se construye
	# entero en su `_init()` (capa, cierre, botón, lista de encargos y de
	# trofeos) y no necesita un `.tscn` para correr suelto, que es como lo
	# montan sus propios tests. Va AQUÍ, en `_al_mundo_listo()`, que es donde
	# vive el resto de la UI que sí se ve.
	_ngplus = PanelNgPlus.new()
	_ngplus.name = "PanelNgPlus"
	add_child(_ngplus)
	_sistemas_de().registrar(_ngplus, &"panel_ngplus")
	super._al_mundo_listo()
	# Fase 45.2: con el mundo ya construido, la pantalla de carga fuera y el
	# jugador colocado en su punto, arranca el tutorial (nueva partida). Es el
	# primer momento en que sus avisos se ven de verdad.
	if _tutorial != null:
		_tutorial.empezar()


## Fase 20: el gate añade las 9 ciudades al terreno de la base.
func _construccion_lista() -> bool:
	if not super._construccion_lista():
		return false
	if _ciudad != null and is_instance_valid(_ciudad):
		if not _ciudad.construccion_terminada():
			return false
	for c in _ciudades_sec:
		var ci: CiudadLuna = c as CiudadLuna
		if ci == null or not is_instance_valid(ci):
			continue
		if not ci.construccion_terminada():
			return false
	return true


## Fase 20: 25% terreno + 75% media de las 9 ciudades.
func _fraccion_carga() -> float:
	var ft: float = super._fraccion_carga()
	return clampf(ft * 0.25 + _fraccion_ciudades() * 0.75, 0.0, 1.0)


func _fraccion_ciudades() -> float:
	var suma: float = 0.0
	var n: int = 0
	var todas: Array = [_ciudad] + _ciudades_sec
	for c in todas:
		var ci: CiudadLuna = c as CiudadLuna
		if ci == null or not is_instance_valid(ci):
			continue
		suma += ci.fraccion_construccion()
		n += 1
	if n <= 0:
		return 1.0
	return suma / float(n)


## Fase 46.1: el botón "?" del HUD abre el manual (la tecla ? también).
func _al_ayuda_hud() -> void:
	if _ayuda != null and is_instance_valid(_ayuda):
		_ayuda.mostrar_manual()


## Fase 45: se	minó un golpe. El aviso flotante de la veta ya lo dice en el
## mundo; aquí solo queda el registro para el playtest.
func _al_minado(veta_id: String, item_id: String, cantidad: int, xp: int) -> void:
	print("[Minería] %s → +%d %s (+%d XP)" % [veta_id, cantidad, item_id, xp])


## Fase 41 — entrada a la arena: guarda el retorno, teletransporta al
## campo remoto y arranca las oleadas.
func _al_arena_dialogo(_npc: NPC) -> void:
	if _arena == null or _jugador == null:
		return
	_retorno_arena = _jugador.global_position
	_teletransportar_arena(_arena.centro_campo())
	_arena.iniciar()
	_panel_misiones.toast("Arena: sobrevive a las 10 oleadas")


## Factory de la arena: como el streaming pero sin vigilancia de respawn
## (la arena cuenta sus muertes y limpia al detener).
func _crear_enemigo_arena(arquetipo_id: String, pos: Vector3) -> Enemy:
	var e: Enemy = _crear_enemigo(arquetipo_id, pos)
	if e == null:
		return null
	if not e.botin_generado.is_connected(_al_botin_generado):
		e.botin_generado.connect(_al_botin_generado)
	if not e.murio.is_connected(_al_morir_enemigo.bind(e)):
		e.murio.connect(_al_morir_enemigo.bind(e))
	e.terreno = _terreno
	e._pegar_al_terreno()
	return e


func _al_arena_oleada(n: int) -> void:
	# Fase 42: dice cuántos enemigos son (antes solo el número y el jugador
	# no sabía si quedaban vivos por los que no hadn't visto).
	_panel_misiones.toast("Oleada %d — %d enemigos" % [n, _arena.vivos() if _arena != null else 0])


func _al_arena_superada(n: int, oro: int, xp: int) -> void:
	var espera: int = int(round(_arena._descanso_seg)) if _arena != null else 0
	_panel_misiones.toast("Oleada %d superada! +%d oro, +%d XP — siguiente en %ds" % [
		n, oro, xp, espera])


## Fase 42: los mobs que quedaban se acercaron (la oleada no puede atascarse).
func _al_arena_ayuda(n: int) -> void:
	_panel_misiones.toast("Te acerco a los %d enemigos restantes" % n)


## Victoria → de vuelta con el Maestro. Derrota: el flujo de muerte sigue
## (el respawn existente devuelve al héroe; la arena ya registró el trofeo).
func _al_arena_terminada(victoria: bool, oleada: int) -> void:
	if victoria:
		_panel_misiones.toast("¡Campeón de la arena! Habla con Renn")
		_teletransportar_arena(_retorno_arena)
	else:
		_panel_misiones.toast("Caíste en la oleada %d — habla con Renn para repetir" % oleada)
		# Fase 51: al perder, el héroe quedaba MUERTO y congelado en el
		# campo, y el aviso le pedía hablar con Renn. La arena se queda con
		# el control durante la partida y al perder hay que devolver al
		# jugador al mundo jugable. Por eso: revive, teletransporta fuera y
		# recién ahí suelta el respawn (`detener`).
		if _jugador != null and is_instance_valid(_jugador):
			_jugador.revivir()
		_teletransportar_arena(_retorno_arena)
		if _arena != null and is_instance_valid(_arena):
			_arena.detener()


## Teletransporte genérico (como el del viaje: sin damping de cámara).
func _teletransportar_arena(dest: Vector3) -> void:
	if _jugador == null:
		return
	var p := Vector3(dest.x, dest.y, dest.z)
	if _terreno != null:
		p.y = _terreno.altura_en(p.x, p.z)
	_jugador.deseleccionar()
	_jugador.global_position = p
	_jugador._pegar_al_terreno()
	if _rig != null:
		_rig.global_position = _jugador.global_position


func _cargar_arena_json() -> Dictionary:
	var texto: String = FileAccess.get_file_as_string("res://data/arena.json")
	if texto.is_empty():
		push_warning("[Fase14] no se pudo leer res://data/arena.json")
		return {}
	var crudo: Variant = JSON.parse_string(texto)
	if crudo is Dictionary:
		return crudo
	push_warning("[Fase14] JSON inválido en res://data/arena.json")
	return {}


## Cargar dentro del campo con la arena apagada te devolvía al vacío:
## al cargar se vuelve a la plaza de Moon Town (la arena se detiene).
func _cargar_partida_guardada() -> bool:
	var cargo: bool = super._cargar_partida_guardada()
	if cargo and _arena != null and _jugador != null:
		_arena.detener()
		var c: Vector3 = _arena.centro_campo()
		var d: Vector2 = Vector2(_jugador.global_position.x - c.x,
			_jugador.global_position.z - c.z)
		if d.length() < 200.0 and _ciudad != null:
			_jugador.global_position = _ciudad.punto_aparicion_jugador()
			_jugador._pegar_al_terreno()
			if _rig != null:
				_rig.global_position = _jugador.global_position
	return cargo


## Fase 16 — "Viajar" en el diálogo de un portero: abre el PanelViaje con
## el origen = ciudad del portero (campo `viaje_id` de data/npcs.json).
func _al_viaje_dialogo(npc: NPC) -> void:
	var origen: String = ViajeRapido.viaje_id_de_npc(npc.npc_id)
	if origen == "" or _panel_viaje == null:
		return
	_panel_viaje.mostrar(origen, _jugador)


## Fase 16 — destino elegido en el PanelViaje: valida, cobra y teletransporta.
func _al_destino_viaje(destino_id: String) -> void:
	if _viaje == null or _jugador == null or _panel_viaje == null:
		return
	var origen: String = _panel_viaje.origen_actual()
	var res: Dictionary = _viaje.viajar(_jugador, origen, destino_id)
	if not bool(res.get("ok", false)):
		# Pudo cambiar algo entre abrir el panel y pulsar (p. ej. entró en
		# combate): se informa sin cerrar.
		_panel_viaje.informar(ViajeRapido.texto_motivo(res))
		return
	_panel_viaje.cerrar_panel()
	var plaza: Vector2 = res.get("plaza", Vector2.ZERO)
	_teletransportar_viaje(plaza, str(res.get("destino", "")), int(res.get("costo", 0)))
	# Fase 51: viajar pasa a ser el punto seguro. Si no,ViajeRapido te deja
	# en la ciudad nueva con el ancla en la vieja y reaparecerías atrás.
	if _respawn != null:
		_respawn.actualizar_ancla()


## Fase 16 — teletransporte del viaje rápido: deselecciona, fija la
## posición en la plaza sobre el terreno y pega la cámara (como el F10).
func _teletransportar_viaje(plaza: Vector2, destino_id: String, costo: int) -> void:
	if _jugador == null:
		return
	var y: float = 0.0
	if _terreno != null:
		y = _terreno.altura_en(plaza.x, plaza.y)
	_jugador.deseleccionar()
	_jugador.global_position = Vector3(plaza.x, y, plaza.y)
	_jugador._pegar_al_terreno()
	if _rig != null:
		_rig.global_position = _jugador.global_position
	var nombre: String = _viaje.nombre_ciudad(destino_id) if _viaje != null else destino_id
	if _panel_misiones != null:
		_panel_misiones.toast("Viaje a %s (-%d oro)" % [nombre, costo])
	print("[Fase16] viaje rápido a %s (-%d oro)" % [nombre, costo])


## Recoloca al jugador y a los NPCs en los puntos de la ciudad.
## (Los NPCs nacen en fase9 con las posiciones viejas de NpcDB; aquí se
## mueven a los puntos data-driven de `data/ciudad_luna.json`.)
func _colocar_en_ciudad() -> void:
	if _ciudad == null or _jugador == null:
		return
	# Fase 20: el jugador como referencia del culling de antorchas (las
	# ~40 OmniLight3D de Moon Town solo alumbran cerca).
	_ciudad.fijar_jugador(_jugador)
	for c in _ciudades_sec:
		var ci: CiudadLuna = c as CiudadLuna
		if ci != null and is_instance_valid(ci):
			ci.fijar_jugador(_jugador)
	_jugador.position = _ciudad.punto_aparicion_jugador()
	_jugador.rotation.y = _ciudad.yaw_aparicion()
	_jugador._pegar_al_terreno()
	for n in _lista_npcs:
		var npc: NPC = n as NPC
		if npc == null:
			continue
		# Fase 15: los ambientales van a su ciudad secundaria; el resto a Moon.
		if _NPC_CIUDAD_SEC.has(npc.npc_id) and int(_NPC_CIUDAD_SEC[npc.npc_id]) < _ciudades_sec.size():
			var c2: CiudadLuna = _ciudades_sec[int(_NPC_CIUDAD_SEC[npc.npc_id])] as CiudadLuna
			npc.position = c2.npc_spawn(npc.npc_id)
		else:
			npc.position = _ciudad.npc_spawn(npc.npc_id)
		npc._pegar_al_terreno()
	# La cámara persigue con damping: colocarla de golpe en el spawn para
	# que no "deslice" desde la posición vieja (mismo truco que el F10).
	if _rig != null:
		_rig.global_position = _jugador.global_position
	print("[Fase14] Moon Town: jugador en %s, %d NPCs recolocados"
		% [_ciudad.punto_aparicion_jugador(), _lista_npcs.size()])
