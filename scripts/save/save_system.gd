class_name SaveSystem
extends RefCounted
## Guardado/carga versionado y tolerante: nunca rompe la carga.
##
## API chica: guardar() -> bool, cargar() -> bool, hay_partida() -> bool.
## Guarda el jugador (entidad versionada + oro + inventario + equipo +
## posición) y la lista de enemigos (entidad + posición; vivo/muerto se
## deduce de la vida).
## El archivo vive en user://partida.json. Ante versiones desconocidas o
## JSON corrupto: push_warning y la carga no revienta (retorna false).

const SAVE_VERSION: int = 13
const RUTA: String = "user://partida.json"
## Bloque 65: cada cuánto se guarda solo. 5 minutos es un término medio: ni tan
## seguido como para tocar el disco en cada morte, ni tan espaciado como para
## perder dos horas de juego.
const INTERVALO_AUTOSAVE: float = 300.0
## El autosave no guarda en la pantalla de título ni en el menú de pausa (el
## juego está parado: no hay nada nuevo que guardar y solo se pisa el guardado
## manual del jugador con el mismo estado).

## Se asignan desde fuera (la escena demo). Sin referencias a UI.
## Fase 51.1 (§9.1): identidad del sistema para el contenedor `Systems`.
## El grupo `gg_system` + este `system_id` sustituyen a las rutas de nodo
## hardcodeadas que usaba la demo para encontrarlo.
var system_id: StringName = &"save_system"
var jugador: Player = null
## Bloque 65: el estado del MUNDO, que hasta acá solo cubría las vetas.
## Un `RefCounted` o un `Node`: se asigna desde la demo.
var arboles: Object = null
var refugios: Array = []
## Bloque 65: si hubo cambios sin guardar. Lo consulta el menú de pausa para
## no perder la partida al salir, y el autosave para no gastar escrituras.
var _dirty: bool = false
var _reloj_autosave: float = 0.0
## Desactiva el autosave mientras la partida está parada (menú de pausa) o
## mientras se está cargando (un guardado a medio de cargar escribiría encima
## del estado que se está restaurando).
var _autosave_activo: bool = true
var enemigos: Array = []
## Fase 6: NPCs en escena (id + posición; los NPCs no mueren, así que no se
## guarda vida: el estado básico es su posición).
var npcs: Array = []
## Fase 7: tienda viva (stock restante). Sin asignar, el bloque "tiendas"
## se guarda vacío y la carga avisa sin reventar.
var tienda: Tienda = null
## Fase 8: misiones (estados + progreso). Sin asignar, el bloque
## "misiones" se guarda vacío y la carga avisa sin reventar.
var misiones: QuestLog = null
## Fase 17: barra de acciones (asignaciones de slots). Sin asignar, el
## bloque "barra_acciones" se guarda vacío y la carga avisa sin reventar.
var barra_acciones: BarraAcciones = null
## Fase 39: tutorial guiado (paso + hecho). Sin asignar, el bloque
## "tutorial" se guarda sin hacer y la carga avisa sin reventar.
var tutorial: Tutorial = null
## Fase 41: arena PvE (mejor oleada + victorias). Sin asignar, el bloque
## "arena" se guarda a cero y la carga avisa sin reventar.
var arena: Arena = null
## Fase 45: minería (usos que le quedan a cada veta + cuenta atrás de
## respawn). Sin asignar, el bloque "mineria" se guarda vacío y la carga
## avisa sin reventar.
var mineria: GestorVetas = null


func hay_partida() -> bool:
	return FileAccess.file_exists(RUTA)


func guardar() -> bool:
	if jugador == null:
		push_warning("[SaveSystem] sin jugador asignado; no se guarda")
		return false
	var datos: Dictionary = {
		"version": SAVE_VERSION,
		"jugador": {
			"entidad": jugador.to_dict(),
			"oro": jugador.oro,
			# Fase 11: identidad del héroe (nombre + clase).
			"nombre": jugador.nombre,
			"clase_id": jugador.clase_id,
			"inventario": jugador.inventario.to_dict() if jugador.inventario != null else {},
			"equipo": jugador.equipo.to_dict() if jugador.equipo != null else {},
			# Fase 28: talentos (puntos + rangos; los mods viajan en "entidad").
			"talentos": jugador.talentos.to_dict() if jugador.talentos != null else {},
			# Fase 30: puntos de atributo sin gastar (los base ya van en "entidad").
			"puntos_atributo": jugador.puntos_atributo,
			# Fase 31: niveles de skill + puntos sin gastar.
			"skills": jugador.skills.to_dict() if jugador.skills != null else {},
			# Fase 57: XP por habilidad. Los saves viejos (sin el bloque)
			# cargan con todo en 0, que es lo correcto.
			"habilidades": jugador.habilidades.to_dict() if jugador.habilidades != null else {},
			"pos": [jugador.global_position.x, jugador.global_position.y, jugador.global_position.z],
		},
		"enemigos": _enemigos_a_datos(),
		"npcs": _npcs_a_datos(),
		"tiendas": tienda.to_dict() if tienda != null else {"version": Tienda.SAVE_VERSION, "tiendas": {}},
		"misiones": misiones.to_dict() if misiones != null else {"version": QuestLog.SAVE_VERSION, "misiones": {}},
		"barra_acciones": barra_acciones.to_dict() if barra_acciones != null else {},
		"tutorial": tutorial.to_dict() if tutorial != null else {"version": Tutorial.SAVE_VERSION_TUTORIAL, "hecho": false, "paso": 0},
		"arena": arena.to_dict() if arena != null else {"version": Arena.SAVE_VERSION_ARENA, "mejor_oleada": 0, "victorias": 0},
		# Fase 45: bloque "mineria" — usos y respawn de cada veta.
		"mineria": mineria.estado_para_guardar() if mineria != null else {},
		# Bloque 65: el estado del mundo. Los árboles talados y los refugios
		# (con sus piezas) son del jugador, no del mundo: si no se guardan, se
		# pierden al cargar.
		"arboles": _arboles_para_guardar(),
		"refugios": _refugios_para_guardar(),
	}
	# Bloque 65: escritura ATÓMICA. Antes se escribía directamente sobre
	# `partida.json`: un corte de luz (o un crash, o cerrar la laptop) a mitad
	# de escritura dejaba un JSON truncado, y como no había backup, la partida
	# se perdía entera. Es la peor clase de bug: no se ve hasta que ya es
	# tarde, y no tiene arreglo.
	#
	# El patrón es escribir a un temporal, cerrarlo, y RENOMBRAR encima, que en
	# el mismo sistema de archivos es atómico. Si el temporal se quedó a medias,
	# el `partida.json` viejo sigue intacto.
	var temporal: String = RUTA + ".tmp"
	var f: FileAccess = FileAccess.open(temporal, FileAccess.WRITE)
	if f == null:
		push_warning("[SaveSystem] no se pudo abrir %s para escribir" % temporal)
		return false
	f.store_string(JSON.stringify(datos))
	# `flush()` antes de cerrar: sin él, el SO puede tener los bytes en su
	# buffer y el rename Puede beat-ear un power loss justo aquí.
	f.flush()
	f.close()
	# Backup ANTES del rename: si el rename deja algo raro, todavía hay una
	# copia buena del estado anterior.
	if FileAccess.file_exists(RUTA):
		var b: FileAccess = FileAccess.open(RUTA + ".bak", FileAccess.WRITE)
		if b != null:
			b.store_string(FileAccess.get_file_as_string(RUTA))
			b.close()
	var err: int = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporal), ProjectSettings.globalize_path(RUTA))
	if err != OK:
		push_warning("[SaveSystem] no se pudo renombrar el temporal (err %d)" % err)
		return false
	_dirty = false
	return true


## Bloque 65: si el `partida.json` está corrupto (o no existe), se intenta el
## `.bak`, que es el estado bueno anterior. Perder la última partida por un
## guardado a medias es la peor forma de perderla.
func _leer_con_respaldo() -> String:
	if FileAccess.file_exists(RUTA):
		var t: String = FileAccess.get_file_as_string(RUTA)
		if _json_valido(t):
			return t
		push_warning("[SaveSystem] partida.json ilegible; se intenta el respaldo")
	if FileAccess.file_exists(RUTA + ".bak"):
		var tb: String = FileAccess.get_file_as_string(RUTA + ".bak")
		if _json_valido(tb):
			return tb
	return ""


static func _json_valido(texto: String) -> bool:
	if texto == "":
		return false
	return JSON.parse_string(texto) is Dictionary


## Bloque 65: ¿hay cambios sin guardar? Lo consulta el menú de pausa antes de
## volver al título o salir. Con el guardado atómico y el backup, perder la
## partida es casi imposible; perder lo de los ÚLTIMOS 5 minutos, no.
func hay_cambios() -> bool:
	return _dirty


## Bloque 65: se marca "hay cambios" con las SEÑALES que ya existen, no
## comparando el estado (que sería un diff de un diccionario entero cada
## frame). Conectar a las señales es gratis: el dirty ya está pasando por ahí.
func vigilar_cambios() -> void:
	if jugador == null or not is_instance_valid(jugador):
		return
	_conectar(jugador.subio_nivel, _marcar)
	_conectar(jugador.oro_cambiado, _marcar_oro)
	_conectar(jugador.murio, _marcar)
	if jugador.inventario != null:
		_conectar(jugador.inventario.cambiado, _marcar)
	if jugador.misiones != null:
		_conectar(jugador.misiones.cambiada, _marcar)
	if jugador.talentos != null:
		_conectar(jugador.talentos.cambiada, _marcar)
	if jugador.skills != null:
		_conectar(jugador.skills.cambiada, _marcar)
	if jugador.habilidades != null:
		_conectar(jugador.habilidades.tramo_ganado, _marcar)


func _conectar(sen: Signal, destino: Callable) -> void:
	if not sen.is_connected(destino):
		sen.connect(destino)


func _marcar(_a = null, _b = null) -> void:
	_dirty = true


## El oro se cambia mucho (cada venta, cada recompensa), pero `oro_cambiado`
## emite con el valor: no hace falta Comparing.
func _marcar_oro(_oro: int) -> void:
	_dirty = true


func cargar() -> bool:
	if jugador == null:
		push_warning("[SaveSystem] sin jugador asignado; no se carga")
		return false
	# Durante la carga el autosave calla: escribir mientras se restaura
	# sobreescribiría el estado bueno con uno a medias.
	_autosave_activo = false
	_dirty = false
	var texto: String = _leer_con_respaldo()
	if texto == "":
		return false
	var crudo: Variant = JSON.parse_string(texto)
	if not (crudo is Dictionary):
		push_warning("[SaveSystem] partida corrupta: JSON inválido")
		return false
	var datos: Dictionary = crudo
	var version: int = int(datos.get("version", 0))
	if version != SAVE_VERSION:
		push_warning("[SaveSystem] versión %d (esperada %d); se intenta cargar igual" % [version, SAVE_VERSION])
	_cargar_jugador(datos.get("jugador", {}))
	_cargar_enemigos(datos.get("enemigos", []))
	_cargar_npcs(datos.get("npcs", []))
	_cargar_tiendas(datos.get("tiendas", {}))
	_cargar_misiones(datos.get("misiones", {}))
	_cargar_barra(datos.get("barra_acciones", {}))
	_cargar_tutorial(datos.get("tutorial", {}), version)
	_cargar_arena(datos.get("arena", {}))
	_cargar_mineria(datos.get("mineria", {}))
	_cargar_arboles(datos.get("arboles", {}))
	_cargar_refugios(datos.get("refugios", {}))
	_autosave_activo = true
	return true


func _enemigos_a_datos() -> Array:
	var lista: Array = []
	for e in enemigos:
		# Fase 19.1: validar antes de castear (la lista puede contener una
		# referencia liberada si un cadáver se liberó entre ticks).
		if not is_instance_valid(e):
			continue
		var en: Enemy = e as Enemy
		if en == null:
			continue
		lista.append({
			"entidad": en.to_dict(),
			"pos": [en.global_position.x, en.global_position.y, en.global_position.z],
		})
	return lista


func _cargar_jugador(dj: Dictionary) -> void:
	jugador.restaurar(dj.get("entidad", {}))
	# Fase 11/18: identidad del héroe. Las partidas viejas (v6, sin
	# "nombre"/"clase_id") cargan con los defaults ("Héroe"/"guerrero"),
	# tolerante como siempre. Los stats NO se re-aplican: ya vienen del
	# dict de entidad restaurado.
	jugador.nombre = str(dj.get("nombre", "Héroe"))
	var cid: String = str(dj.get("clase_id", "guerrero"))
	jugador.clase_id = cid if ClaseDB.existe(cid) else "guerrero"
	# Fase 42: la clase es la fuente de verdad del stat principal de daño
	# (saves previos a la fase 42 vienen sin él en el bloque entidad).
	jugador.stats.set_stat_daño(ClaseDB.stat_daño(jugador.clase_id))
	jugador.identidad_cambiada.emit()
	jugador.oro = maxi(0, int(dj.get("oro", 0)))
	jugador.oro_cambiado.emit(jugador.oro)
	_cargar_inventario(dj)
	_cargar_equipo(dj)
	_cargar_talentos(dj)
	_cargar_skills(dj)
	_cargar_habilidades(dj)
	var pos: Array = dj.get("pos", [])
	if pos.size() >= 3:
		jugador.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))


## Inventario (formato v2: dict de to_dict/from_dict). Tolerancia: si no hay
## "inventario" pero hay "items" del formato viejo de la fase 4 (array de
## {item_id, cantidad}), se importa item por item.
func _cargar_inventario(dj: Dictionary) -> void:
	if dj.has("inventario"):
		jugador.inventario = Inventario.from_dict(dj.get("inventario", {}))
		return
	var inv: Inventario = Inventario.new()
	var viejos: Array = dj.get("items", [])
	for it in viejos:
		if not (it is Dictionary):
			continue
		var di: Dictionary = it
		var iid: String = str(di.get("item_id", ""))
		if iid == "":
			continue
		inv.agregar(iid, maxi(1, int(di.get("cantidad", 1))))
	jugador.inventario = inv


## Equipo (formato v2). Ojo con la doble aplicación: restaurar() ya re-aplicó
## los mods guardados en el dict de stats, así que se retiran los de fuente
## "equipo:<slot>:<stat>" antes de que Equipo.from_dict los reaplique.
## Sin "equipo" (partidas viejas): equipo vacío, sin tocar stats.
func _cargar_equipo(dj: Dictionary) -> void:
	var dj_equipo: Dictionary = dj.get("equipo", {})
	var slots: Dictionary = dj_equipo.get("slots", {})
	for slot in Equipo.SLOTS:
		var item_id: String = str(slots.get(slot, ""))
		if item_id == "" or not ItemDB.existe(item_id):
			continue
		var item: Dictionary = ItemDB.obtener(item_id)
		var mods: Array = item.get("mods", [])
		for m in mods:
			if not (m is Dictionary):
				continue
			var md: Dictionary = m
			jugador.stats.remove_mod("equipo:%s:%s" % [slot, str(md.get("stat", ""))])
	jugador.equipo = Equipo.from_dict(dj_equipo, jugador.stats)


## Fase 28 — Talentos. Los mods ya vinieron en el bloque "entidad": aquí
## solo se restauran puntos+rangos (reaplicar es idempotente y cubre
## rarezas). Sin bloque (partidas v7): puntos retroactivos nivel-1.
func _cargar_talentos(dj: Dictionary) -> void:
	if jugador.talentos == null:
		jugador.talentos = Talentos.new()
	if dj.has("talentos"):
		jugador.talentos.cargar_estado(dj.get("talentos", {}))
	else:
		jugador.talentos.puntos = maxi(0, jugador.nivel - 1)
	jugador.talentos.aplicar_todos(jugador.stats)
	# Fase 30: puntos de atributo (v8 sin bloque: retroactivo 2/nivel).
	if dj.has("puntos_atributo"):
		jugador.puntos_atributo = maxi(0, int(dj.get("puntos_atributo", 0)))
	else:
		jugador.puntos_atributo = maxi(0, (jugador.nivel - 1) * 2)


## Fase 31 — Skills. Sin bloque (partidas v9): niveles default de la
## clase actual (sus skills en 1, 0 puntos). Con bloque: se restaura.
func _cargar_skills(dj: Dictionary) -> void:
	if jugador.skills == null:
		jugador.skills = SkillSystem.new()
	if dj.has("skills"):
		jugador.skills.cargar_estado(dj.get("skills", {}), jugador.clase_id)
	else:
		jugador.skills.configurar_clase(jugador.clase_id)


## Fase 57: restaura el XP por habilidad. Un save viejo (sin el bloque)
## deja las habilidades en 0, no en un estado raro.
##
## Hotfix 62.1: al final recalcula los Hechos. `Habilidades.cargar_estado`
## escribe el XP en silencio y NO emite `tramo_ganado`, así que el
## `Player._al_subir_tramo` que dispara `hechos.aplicar()` no corría y los mods
## `hecho:*` se perdían en cada F10: se ganaba un Hecho, se guardaba, y al
## recargar el juego se perdía el bonus.
##
## No hace falta guardar los Hechos: `Hechos.desbloqueado()` es exactamente
## `habilidades.alcanza(habilidad, tramo)`, así que son datos DERIVADOS del
## bloque que ya se guarda. Recalcularlos es la única forma de que no puedan
## desincronizarse, y evita tocar el formato del save.
func _cargar_habilidades(dj: Dictionary) -> void:
	if jugador.habilidades == null:
		jugador.habilidades = Habilidades.crear_desde_datos()
	if jugador.hechos != null:
		jugador.hechos.fijar_habilidades(jugador.habilidades)
	if dj.has("habilidades"):
		jugador.habilidades.cargar_estado(dj.get("habilidades", {}))
	if jugador.hechos != null:
		jugador.hechos.aplicar(jugador.stats)


func _cargar_enemigos(lista: Array) -> void:
	var n: int = mini(lista.size(), enemigos.size())
	if lista.size() != enemigos.size():
		push_warning("[SaveSystem] enemigos guardados (%d) != en escena (%d); se cargan %d" % [lista.size(), enemigos.size(), n])
	for i in range(n):
		if not is_instance_valid(enemigos[i]):
			continue
		var en: Enemy = enemigos[i] as Enemy
		if en == null:
			continue
		var de: Dictionary = lista[i]
		en.restaurar(de.get("entidad", {}))
		var pos: Array = de.get("pos", [])
		if pos.size() >= 3:
			en.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		if en.esta_vivo():
			en.mostrar_cuerpo()
		else:
			en.ocultar_cuerpo()


## Fase 7 — Tiendas: se guarda el stock restante por tienda/item.
## Tolerante: las partidas v3 (sin bloque "tiendas") cargan con el stock
## completo desde los datos (cargar_estado restablece primero).
func _cargar_tiendas(bloque: Dictionary) -> void:
	if tienda == null:
		push_warning("[SaveSystem] sin tienda asignada; el stock queda sin cargar")
		return
	tienda.cargar_estado(bloque)


## Fase 8 — Misiones: se guardan los estados y el progreso por objetivo.
## Tolerante: las partidas v4 (sin bloque "misiones") cargan con el
## QuestLog vacío; una versión distinta también arranca vacío
## (cargar_estado avisa y no revienta). El QuestLog se restaura EN SITIO
## (como Tienda): las referencias de la demo y del panel siguen válidas.
func _cargar_misiones(bloque: Dictionary) -> void:
	if misiones == null:
		push_warning("[SaveSystem] sin QuestLog asignado; las misiones quedan sin cargar")
		return
	misiones.cargar_estado(bloque)


## Fase 17 — barra de acciones: se guardan las asignaciones de slots.
## Tolerante: las partidas v5 (sin bloque) cargan con el layout por defecto;
## los ids inválidos se descartan en cargar_estado.
func _cargar_barra(bloque: Dictionary) -> void:
	if barra_acciones == null:
		push_warning("[SaveSystem] sin barra asignada; las asignaciones quedan sin cargar")
		return
	if bloque.is_empty():
		barra_acciones.restablecer_defecto()
		return
	barra_acciones.cargar_estado(bloque)


## Fase 39 — tutorial. Tolerante: sin bloque o save anterior a v11 (era
## pre-tutorial) se marca hecho — un veterano que carga no recibe prompts.
## Los saves v11+ respetan su bloque.
func _cargar_tutorial(bloque: Dictionary, version_raiz: int) -> void:
	if tutorial == null:
		push_warning("[SaveSystem] sin tutorial asignado; el estado queda sin cargar")
		return
	if bloque.is_empty() or version_raiz < 11:
		tutorial.cargar_estado({"hecho": true})
		return
	tutorial.cargar_estado(bloque)


## Fase 41 — arena. Tolerante: sin bloque se queda a cero (trofeos frescos).
func _cargar_arena(bloque: Dictionary) -> void:
	if arena == null:
		push_warning("[SaveSystem] sin arena asignada; los trofeos quedan sin cargar")
		return
	if bloque.is_empty():
		arena.cargar_estado({})
		return
	arena.cargar_estado(bloque)


## Fase 45 — minería. Tolerante: sin bloque (partidas v12 y anteriores, cuando
## las vetas no existían) TODAS las vetas vuelven a sus usos completos: es el
## mismo criterio que "trofeos frescos" en la arena.
func _cargar_mineria(bloque: Dictionary) -> void:
	if mineria == null:
		push_warning("[SaveSystem] sin gestor de vetas asignado; el estado de las vetas queda sin cargar")
		return
	if bloque.is_empty():
		return
	mineria.cargar_estado(bloque)


## Fase 6 — NPCs: se guarda solo id + posición (no mueren, no hay vida que
## guardar). Al cargar se busca cada NPC en escena por npc_id (independiente
## del orden) y se restaura la posición sin emitir ninguna señal.
func _npcs_a_datos() -> Array:
	var lista: Array = []
	for n in npcs:
		var npc: NPC = n as NPC
		if npc == null:
			continue
		lista.append({
			"npc_id": npc.npc_id,
			"pos": [npc.global_position.x, npc.global_position.y, npc.global_position.z],
		})
	return lista


## Tolerante: las partidas viejas (v2) no traen el bloque "npcs" y cargan
## igual (los NPCs quedan donde los dejó la escena).
func _cargar_npcs(lista: Array) -> void:
	if lista.is_empty():
		return
	var por_id: Dictionary = {}
	for n in npcs:
		var npc: NPC = n as NPC
		if npc != null and npc.npc_id != "":
			por_id[npc.npc_id] = npc
	for d in lista:
		if not (d is Dictionary):
			continue
		var dd: Dictionary = d
		var npc: NPC = por_id.get(str(dd.get("npc_id", "")), null)
		if npc == null:
			push_warning("[SaveSystem] NPC guardado no está en escena: %s" % str(dd.get("npc_id", "")))
			continue
		var pos: Array = dd.get("pos", [])
		if pos.size() >= 3:
			npc.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))


# --- bloque 65: autosave -------------------------------------------

## Bloque 65: el reloj del autosave. Un `RefCounted` no tiene `_process`
## (no vive en el árbol), así que el tiempo lo aporta quien SÍ está en el árbol:
## `MenuPausa` y la demo llaman a `avanzar_autosave(delta)` cada frame.
func avanzar_autosave(delta: float) -> void:
	if not _autosave_activo:
		return
	_reloj_autosave += delta
	if _reloj_autosave < INTERVALO_AUTOSAVE:
		return
	_reloj_autosave = 0.0
	if not _dirty:
		return
	guardar()


## Lo llama `MenuPausa`: con el juego parado no hay nada nuevo que guardar.
func fijar_autosave(activo: bool) -> void:
	_autosave_activo = activo
	if not activo:
		# Al reanudar, el reloj se pone a cero: el jugador no quiere un
		# guardado a los 3 segundos de volver al juego.
		_reloj_autosave = 0.0


# --- bloque 65: el estado del mundo ---------------------------------

func _arboles_para_guardar() -> Dictionary:
	if arboles == null or not is_instance_valid(arboles):
		return {}
	if not arboles.has_method("estado_para_guardar"):
		return {}
	return arboles.call("estado_para_guardar")


func _cargar_arboles(bloque: Dictionary) -> void:
	if arboles == null or not is_instance_valid(arboles):
		return
	if not arboles.has_method("cargar_estado"):
		return
	if bloque.is_empty():
		return
	arboles.call("cargar_estado", bloque)


func _refugios_para_guardar() -> Dictionary:
	var out: Dictionary = {}
	for r in refugios:
		if r == null or not is_instance_valid(r):
			continue
		if r.has_method("to_dict"):
			out[str(r.get("refugio_id"))] = r.call("to_dict")
	return out


func _cargar_refugios(bloque: Dictionary) -> void:
	if bloque.is_empty():
		return
	for r in refugios:
		if r == null or not is_instance_valid(r):
			continue
		var rid: String = str(r.get("refugio_id"))
		if not bloque.has(rid):
			continue
		if r.has_method("cargar_estado"):
			r.call("cargar_estado", bloque[rid])
