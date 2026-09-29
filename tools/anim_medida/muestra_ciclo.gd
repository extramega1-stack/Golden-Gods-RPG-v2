extends RefCounted
## MuestraCiclo — la foto de una animación: N instantes de un clip, medidos.
##
## RESPONSABILIDAD ÚNICA: recorrer un clip de principio a fin, poner el rig en
## cada instante y devolver los números crudos de las patas. No juzga nada (eso
## es `MedidorCiclo`, `MedidorPatinazo` y `MedidorDireccion`), no simula que el
## personaje camine, y no sabe de `speed_scale` ni del juego.
##
## POR QUÉ devuelve las posiciones en el espacio del ESQUELETO y no en el
## mundo: el mundo de Godot ya trae la vuelta de `Cuerpo.GIRO_MODELO` y la
## escala del modelo, y si se midiera ahí no se podría separar "la marcha va al
## revés" (culpa del `PI`) de "la marcha va al revés" (culpa del rig). Con los
## números del esqueleto, la vuelta se aplica DESPUÉS, en una operación pura y
## verificable, y las dos hipótesis se leen separadas en el informe.
##
## ADVERTENCIA, y es la misma que arruinó las tres pruebas anteriores: esto
## mide lo que el `AnimationPlayer` HACE, no lo que el `.glb` dice. Si hay un
## `AnimationTree` activo en el subárbol, el árbol toma el control y el
## `seek()` deja de mandar; por eso `bancada_animacion.gd` mide el clip crudo
## en una instancia limpia y la mezcla en otra.

const LOCALIZADOR: GDScript = preload("res://tools/anim_medida/localizador.gd")


## Separación mínima de dos instantes, en segundos. Con 60 fps son 16,67 ms.
const PASO_MIN: float = 0.001


## Recorre `clip` en `muestras` instantes y mide las patas.
##
## Devuelve un `Dictionary` con `ok` y `motivo` (por qué no se pudo medir, si
## `ok` es falso) y, cuando sí pudo, estas claves:
##
## - `clip`, `duracion` (s), `muestras`, `paso` (s entre instantes)
## - `pos`: `{clave -> PackedVector3Array}` en el espacio del esqueleto
## - `giro`: `{clave -> PackedFloat32Array}` grados girados entre instantes
## - `altura`: `{clave -> PackedFloat32Array}` la Y de cada posición
## - `excursion`: `{clave -> float}` el alto total que recorre el hueso
## - `recorrido_xz`: `{clave -> float}` el camino horizontal del hueso
## - `huesos`: `{clave -> {indice, nombre}}`
## - `posiciones_reales`: cuántos instantes cambió de verdad la pose
static func muestrear(nodo: Node, anim: AnimationPlayer, skel: Skeleton3D,
		clip: String, muestras: int) -> Dictionary:
	var salida: Dictionary = {"ok": false, "motivo": ""}
	if nodo == null or not is_instance_valid(nodo):
		salida["motivo"] = "el modelo no esta en el arbol, no hay pose que leer"
		return salida
	if not nodo.is_inside_tree():
		salida["motivo"] = "el modelo no esta dentro del arbol de escenas"
		return salida
	if anim == null or not is_instance_valid(anim):
		salida["motivo"] = "este modelo no tiene AnimationPlayer: es estatico"
		return salida
	if skel == null or not is_instance_valid(skel):
		salida["motivo"] = "este modelo no tiene Skeleton3D: no hay huesos que medir"
		return salida
	if not anim.has_animation(clip):
		salida["motivo"] = "el clip '%s' no existe en este AnimationPlayer" % clip
		return salida
	var piernas: Dictionary = LOCALIZADOR.piernas(skel)
	var claves: PackedStringArray = _claves_con_hueso(piernas)
	if claves.is_empty():
		salida["motivo"] = "ninguno de los huesos de la pierna existe en este rig"
		return salida
	# `maxi` y `maxf` NO son intercambiables: `maxi` es de enteros y trunca.
	# `maxi(1.0417, 0.0)` devuelve 1, y con esa duración el paso de muestreo
	# sale de un clip de un segundo en vez del clip de 1,042 s. El informe
	# daba una zancada correcta con una duración falsa, y el `speed_scale`
	# que sale de ahí salía 8% largo. Truncado, no redondeado, en silencio.
	var pasos: int = maxi(muestras, 2)
	var duracion: float = maxf(anim.get_animation(clip).length, 0.0)
	var paso: float = maxf(duracion / float(pasos - 1), PASO_MIN)
	# El clip se reproduce para que el mixer quede en ese clip, y se avanza
	# `paso` cada vez. `seek` con `update=true` es lo que aplica la pose; el
	# `advance` de un paso es lo que deja al mixer avanzar su reloj interno, y
	# sin esto el motor se queja de que se saltó un track.
	var anterior: String = str(anim.current_animation)
	anim.play(clip)
	anim.seek(0.0, true)
	# LAS SERIES SON `Array`, NO `Packed*Array`, Y HASTA EL FINAL. Un
	# `Packed*Array` guardado en un Dictionary es una COPIA por valor: hacer
	# `pos[clave].append(...)` agranda una copia temporal y se pierde, y el
	# medidor falla de la forma más silenciosa del mundo — midiendo una pose
	# que no se movió. Con `Array`, que es referencia, sí se acumula.
	var locales: Dictionary = {}
	var giros: Dictionary = {}
	var quinas_previas: Dictionary = {}
	var cambio_real: int = 0
	var huesos: Dictionary = {}
	for clave in claves:
		var serie: Array[Vector3] = []
		locales[clave] = serie
		var serie_giro: Array[float] = []
		giros[clave] = serie_giro
		var idx: int = _indice_de(piernas, clave)
		huesos[clave] = {"indice": idx, "nombre": LOCALIZADOR.nombres(skel, idx)}
	for i in pasos:
		var t: float = minf(paso * float(i), duracion)
		anim.seek(t, true)
		anim.advance(0.0)
		for clave in claves:
			var bone: int = _indice_de(piernas, clave)
			var transformacion: Transform3D = skel.get_bone_global_pose(bone)
			var serie: Array[Vector3] = locales[clave] as Array[Vector3]
			serie.append(transformacion.origin)
			locales[clave] = serie
			var quina: Quaternion = transformacion.basis.get_rotation_quaternion()
			var serie_giro: Array[float] = giros[clave] as Array[float]
			if quinas_previas.has(clave):
				var previa: Quaternion = quinas_previas[clave] as Quaternion
				serie_giro.append(rad_to_deg(previa.angle_to(quina)))
			else:
				serie_giro.append(0.0)
			giros[clave] = serie_giro
			quinas_previas[clave] = quina
		if i > 0 and _pose_cambio(locales, claves, i):
			cambio_real += 1
	# Restaura el clip que estaba sonando para no dejar el modelo cojo.
	if anterior != "" and anim.has_animation(StringName(anterior)):
		anim.play(StringName(anterior))
	else:
		anim.stop()
	var pos: Dictionary = {}
	var altura: Dictionary = {}
	var giro: Dictionary = {}
	for clave in claves:
		var serie: Array[Vector3] = locales[clave] as Array[Vector3]
		pos[clave] = PackedVector3Array(serie)
		var ys: PackedFloat32Array = PackedFloat32Array()
		for p in serie:
			ys.append(p.y)
		altura[clave] = ys
		giro[clave] = PackedFloat32Array(giros[clave] as Array[float])
	var excursion: Dictionary = {}
	var recorrido: Dictionary = {}
	for clave in claves:
		excursion[clave] = _excursion(altura[clave] as PackedFloat32Array)
		recorrido[clave] = _recorrido_xz(pos[clave] as PackedVector3Array)
	salida["ok"] = true
	salida["clip"] = clip
	salida["duracion"] = duracion
	salida["muestras"] = pasos
	salida["paso"] = paso
	salida["pos"] = pos
	salida["giro"] = giro
	salida["altura"] = altura
	salida["excursion"] = excursion
	salida["recorrido_xz"] = recorrido
	salida["huesos"] = huesos
	salida["posiciones_reales"] = cambio_real
	return salida


## Cuántos de los huesos watchList cambiaron de sitio entre el instante `i` y
## el anterior. Si es cero durante todo el ciclo, la animación NO se está
## moviendo: el `seek` no está mandando o el clip no tiene keys.
static func _pose_cambio(pos: Dictionary, claves: PackedStringArray, i: int) -> bool:
	for clave in claves:
		var serie: Array[Vector3] = pos[clave] as Array[Vector3]
		if i > 0 and i < serie.size():
			if serie[i].distance_to(serie[i - 1]) > 0.0001:
				return true
	return false


static func _excursion(serie: PackedFloat32Array) -> float:
	if serie.is_empty():
		return 0.0
	var alto: float = serie[0]
	var bajo: float = serie[0]
	for v in serie:
		alto = maxf(alto, v)
		bajo = minf(bajo, v)
	return alto - bajo


static func _recorrido_xz(serie: PackedVector3Array) -> float:
	var total: float = 0.0
	for i in range(1, serie.size()):
		total += Vector2(serie[i].x - serie[i - 1].x,
				serie[i].z - serie[i - 1].z).length()
	return total


## Las claves de hueso que existen de verdad en este rig, en orden fijo
## (izq.muslo, izq.espinilla, izq.pie, der.…). El orden fijo es lo que hace
## que dos informes se puedan DIFFEAR: si el rig de otro modelo viene en otro
## orden, las columnas del informe siguen igual.
static func _claves_con_hueso(piernas: Dictionary) -> PackedStringArray:
	var claves: PackedStringArray = PackedStringArray()
	for lado in ["izq", "der"]:
		var grupo: Dictionary = piernas.get(lado, {}) as Dictionary
		for vocal in LOCALIZADOR.VOCALES:
			if int(grupo.get(vocal, -1)) >= 0:
				claves.append(LOCALIZADOR.clave_hueso(lado, vocal))
	return claves


static func _indice_de(piernas: Dictionary, clave: String) -> int:
	var partes: PackedStringArray = clave.split(".") as PackedStringArray
	if partes.size() != 2:
		return -1
	var grupo: Dictionary = piernas.get(partes[0], {}) as Dictionary
	return int(grupo.get(partes[1], -1))
