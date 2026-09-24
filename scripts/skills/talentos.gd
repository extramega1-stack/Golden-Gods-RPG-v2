class_name Talentos
extends RefCounted
## Lógica PURA de talentos (fase 28). SIN UI y SIN datos hardcodeados: las
## definiciones viven en TalentoDB (`data/talentos.json`).
##
## - `puntos`: disponibles para gastar (el Player suma 1 por nivel).
## - `rangos`: talento_id -> rango actual (0 = sin comprar).
## - `subir(id, stats, nivel, clase)`: valida (clase, nivel, tope, puntos),
##   gasta 1 punto y aplica los mods × rango con fuente "talento:<id>".
## - Los mods viven en el StatBlock (se guardan con la entidad); este
##   objeto guarda puntos+rangos (bloque propio en el save).
## Cada cambio emite `cambiada` (la UI solo lee).

signal cambiada()

## Versión del bloque "talentos" del guardado.
const SAVE_VERSION: int = 1

var puntos: int = 0
var _rangos: Dictionary = {}


## Rango actual de un talento (0 si no existe o sin comprar).
func rango_de(talento_id: String) -> int:
	return maxi(0, int(_rangos.get(talento_id, 0)))


## ¿Se puede subir? Misma validación que subir(), sin mutar.
func puede_subir(talento_id: String, nivel_jugador: int, clase_id: String) -> String:
	if not TalentoDB.existe(talento_id):
		return "desconocido"
	var tal: Dictionary = TalentoDB.obtener(talento_id)
	if str(tal.get("clase", "")) != clase_id:
		return "clase"
	if nivel_jugador < int(tal.get("requiere_nivel", 1)):
		return "nivel"
	if rango_de(talento_id) >= maxi(1, int(tal.get("max_rango", 3))):
		return "max_rango"
	if puntos <= 0:
		return "sin_puntos"
	return "ok"


## Gasta 1 punto y aplica. Retorna "ok" o el motivo de puede_subir().
func subir(talento_id: String, stats: StatBlock, nivel_jugador: int,
		clase_id: String) -> String:
	var motivo: String = puede_subir(talento_id, nivel_jugador, clase_id)
	if motivo != "ok":
		return motivo
	puntos -= 1
	_rangos[talento_id] = rango_de(talento_id) + 1
	_aplicar_uno(stats, talento_id)
	cambiada.emit()
	return "ok"


## Reaplica todos los rangos sobre unos stats (tras cargar o cambiar de
## clase). Idempotente: quita y repone los mismos valores.
func aplicar_todos(stats: StatBlock) -> void:
	if stats == null:
		return
	for tid in _rangos:
		_aplicar_uno(stats, str(tid))


## Puntos totales invertidos (tests/UI).
func invertidos() -> int:
	var n: int = 0
	for tid in _rangos:
		n += rango_de(str(tid))
	return n


## Retira los talentos de otra clase (al cambiar de clase): quita sus
## mods y devuelve los puntos. Retorna cuántos rangos purgó.
func purgar_clase(stats: StatBlock, clase_id: String) -> int:
	var purgados: int = 0
	for tid in _rangos.keys():
		var talento_id: String = str(tid)
		if str(TalentoDB.obtener(talento_id).get("clase", "")) != clase_id:
			purgados += rango_de(talento_id)
			puntos += rango_de(talento_id)
			_rangos.erase(talento_id)
			if stats != null:
				stats.remove_mod("talento:" + talento_id)
	if purgados > 0:
		cambiada.emit()
	return purgados


func _aplicar_uno(stats: StatBlock, talento_id: String) -> void:
	if stats == null:
		return
	var tal: Dictionary = TalentoDB.obtener(talento_id)
	var r: int = rango_de(talento_id)
	var fuente: String = "talento:" + talento_id
	stats.remove_mod(fuente)
	if r <= 0:
		return
	for m in (tal.get("mods", []) as Array):
		var md: Dictionary = m
		stats.add_mod(fuente, str(md.get("stat", "")),
			int(md.get("kind", 0)), float(md.get("valor", 0.0)) * float(r))


## Serialización versionada (bloque "talentos" del save).
func to_dict() -> Dictionary:
	var bloque: Dictionary = {}
	for tid in _rangos:
		bloque[str(tid)] = rango_de(str(tid))
	return {"version": SAVE_VERSION, "puntos": puntos, "rangos": bloque}


static func from_dict(d: Dictionary) -> Talentos:
	var t: Talentos = Talentos.new()
	t.cargar_estado(d)
	return t


## Restaura puntos+rangos (tolerante: versión distinta → vacío con aviso).
## Los mods del StatBlock viajan en el bloque de entidad: aquí NO se
## re-aplican (la demo llama aplicar_todos si hace falta).
func cargar_estado(d: Dictionary) -> void:
	_rangos.clear()
	puntos = 0
	var ver: int = int(d.get("version", 0))
	if ver != SAVE_VERSION:
		push_warning("[Talentos] versión %d (esperada %d); se arranca vacío"
			% [ver, SAVE_VERSION])
		return
	puntos = maxi(0, int(d.get("puntos", 0)))
	var bloque: Dictionary = d.get("rangos", {})
	for tid in bloque:
		var talento_id: String = str(tid)
		if not TalentoDB.existe(talento_id):
			push_warning("[Talentos] ignora talento desconocido: %s" % talento_id)
			continue
		var r: int = maxi(0, int(bloque[tid]))
		var mx: int = maxi(1, int(TalentoDB.obtener(talento_id).get("max_rango", 3)))
		if r > 0:
			_rangos[talento_id] = mini(r, mx)
