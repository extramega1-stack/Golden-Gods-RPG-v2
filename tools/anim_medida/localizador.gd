extends RefCounted
## Localizador — encuentra las piezas de un rig POR NOMBRE, nunca por ruta.
##
## POR QUÉ EXISTE: la instrumentación de animación tiene que poder mirar
## CUALQUIER modelo de `models/` (6 ahora, 85 el día que entren) y no puede
## hardcodear `Rig/Skeleton3D` ni el índice 15 del hueso del pie, porque el
## importador deja el esqueleto donde quiere y el orden de los huesos cambia
## entre assets. Buscar por nombre con una lista de alias es lo único que
## sobrevive al próximo `.glb`.
##
## RESPONSABILIDAD ÚNICA: decir DÓNDE está el `AnimationPlayer`, dónde el
## `Skeleton3D` y qué índice tiene cada hueso de la pierna. No mide nada: eso
## es de `MuestraCiclo` y compañía. Si no encuentra un hueso lo dice
## (`-1`) y el que llama escribe "no se puede medir" en el informe; jamás
## inventa un índice.

## Los alias son los nombres reales de `data/modelos.json` primero, y después
## las convenciones de los packs de Meshy y de Mixamo por si entra uno nuevo.
const ALIAS_MUSLO_IZQ: Array[String] = ["Thigh.L", "thigh.l", "UpLeg.L", "LeftUpLeg", "muslo.L", "LeftThigh"]
const ALIAS_ESPINILLA_IZQ: Array[String] = ["Shin.L", "shin.l", "LowerLeg.L", "LeftLeg", "espinilla.L", "LeftShin"]
const ALIAS_PIE_IZQ: Array[String] = ["Foot.L", "foot.l", "LeftFoot", "Pie.L", "pie.L"]
const ALIAS_MUSLO_DER: Array[String] = ["Thigh.R", "thigh.r", "UpLeg.R", "RightUpLeg", "muslo.R", "RightThigh"]
const ALIAS_ESPINILLA_DER: Array[String] = ["Shin.R", "shin.r", "LowerLeg.R", "RightLeg", "espinilla.R", "RightShin"]
const ALIAS_PIE_DER: Array[String] = ["Foot.R", "foot.r", "RightFoot", "Pie.R", "pie.R"]
const ALIAS_CADERA: Array[String] = ["Hips", "hips", "Pelvis", "Root", "Cadera"]

## Lo que devuelve `piernas()`: "muslo"/"espinilla"/"pie" de cada lado.
## Valor `-1` = ese hueso no existe en este modelo.
const VOCALES: Array[String] = ["muslo", "espinilla", "pie"]


## Primer `AnimationPlayer` del subárbol, en profundidad, o `null`.
static func reproductor(nodo: Node) -> AnimationPlayer:
	if nodo == null or not is_instance_valid(nodo):
		return null
	if nodo is AnimationPlayer:
		return nodo as AnimationPlayer
	for c in nodo.get_children():
		var hallada: AnimationPlayer = reproductor(c)
		if hallada != null:
			return hallada
	return null


## Primer `Skeleton3D` del subárbol, en profundidad, o `null`.
static func esqueleto(nodo: Node) -> Skeleton3D:
	if nodo == null or not is_instance_valid(nodo):
		return null
	if nodo is Skeleton3D:
		return nodo as Skeleton3D
	for c in nodo.get_children():
		var hallada: Skeleton3D = esqueleto(c)
		if hallada != null:
			return hallada
	return null


## Índice del primer alias que exista en el esqueleto, o `-1`.
static func indice(skel: Skeleton3D, alias: Array[String]) -> int:
	if skel == null:
		return -1
	for nombre in alias:
		var i: int = skel.find_bone(nombre)
		if i >= 0:
			return i
	return -1


## Los seis huesos de las dos piernas, más la cadera.
##
## Devuelve un `Dictionary` con `"izq"`, `"der"` (cada uno con las tres
## `VOCALES`) y `"cadera"`. Los índices van por nombre del hueso, no por
## posición, y un `-1` significa que ese modelo no lo tiene.
static func piernas(skel: Skeleton3D) -> Dictionary:
	return {
		"izq": {
			"muslo": indice(skel, ALIAS_MUSLO_IZQ),
			"espinilla": indice(skel, ALIAS_ESPINILLA_IZQ),
			"pie": indice(skel, ALIAS_PIE_IZQ),
		},
		"der": {
			"muslo": indice(skel, ALIAS_MUSLO_DER),
			"espinilla": indice(skel, ALIAS_ESPINILLA_DER),
			"pie": indice(skel, ALIAS_PIE_DER),
		},
		"cadera": indice(skel, ALIAS_CADERA),
	}


## Nombres legibles de los huesos, para el informe (o `"?"` si no existe).
static func nombres(skel: Skeleton3D, idx: int) -> String:
	if skel == null or idx < 0 or idx >= skel.get_bone_count():
		return "?"
	return skel.get_bone_name(idx)


## Lista plana de índices de hueso que SÍ existen, en el orden de `VOCALES` y
## de los dos lados. Se usa para medir sin que falte un hueso a medias.
static func indices_existentes(piernas: Dictionary) -> Array[int]:
	var salida: Array[int] = []
	for lado in ["izq", "der"]:
		var grupo: Dictionary = piernas.get(lado, {}) as Dictionary
		for vocal in VOCALES:
			var i: int = int(grupo.get(vocal, -1))
			if i >= 0:
				salida.append(i)
	return salida


## Clave estable para nombrar un hueso en el informe y en el JSON, aunque el
## modelo no lo tenga: `"izq.pie"`, `"der.muslo"`, etc.
static func clave_hueso(lado: String, vocal: String) -> String:
	return "%s.%s" % [lado, vocal]
