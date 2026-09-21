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

const SAVE_VERSION: int = 2
const RUTA: String = "user://partida.json"

## Se asignan desde fuera (la escena demo). Sin referencias a UI.
var jugador: Player = null
var enemigos: Array = []


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
			"inventario": jugador.inventario.to_dict() if jugador.inventario != null else {},
			"equipo": jugador.equipo.to_dict() if jugador.equipo != null else {},
			"pos": [jugador.global_position.x, jugador.global_position.y, jugador.global_position.z],
		},
		"enemigos": _enemigos_a_datos(),
	}
	var f: FileAccess = FileAccess.open(RUTA, FileAccess.WRITE)
	if f == null:
		push_warning("[SaveSystem] no se pudo abrir %s para escribir" % RUTA)
		return false
	f.store_string(JSON.stringify(datos))
	f.close()
	return true


func cargar() -> bool:
	if jugador == null:
		push_warning("[SaveSystem] sin jugador asignado; no se carga")
		return false
	if not FileAccess.file_exists(RUTA):
		return false
	var texto: String = FileAccess.get_file_as_string(RUTA)
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
	return true


func _enemigos_a_datos() -> Array:
	var lista: Array = []
	for e in enemigos:
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
	jugador.oro = maxi(0, int(dj.get("oro", 0)))
	jugador.oro_cambiado.emit(jugador.oro)
	_cargar_inventario(dj)
	_cargar_equipo(dj)
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


func _cargar_enemigos(lista: Array) -> void:
	var n: int = mini(lista.size(), enemigos.size())
	if lista.size() != enemigos.size():
		push_warning("[SaveSystem] enemigos guardados (%d) != en escena (%d); se cargan %d" % [lista.size(), enemigos.size(), n])
	for i in range(n):
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
