extends RefCounted
## InformeAnimacion — los números, arriba, y en un orden que se diffea.
##
## RESPONSABILIDAD ÚNICA: escribir. Toma el paquete de mediciones que arma
## `bancada_animacion.gd` y produce el informe de texto y el JSON. No mide
## nada, no toca el juego, no decide.
##
## POR QUÉ ESTE ARCHIVO Y NO `print()`: el encargo es comparar DOS corridas
## (antes y después de arreglar la animación). Para eso el informe tiene que
## ser texto estable: mismos encabezados, mismo orden, mismas columnas, y
## arriba un bloque de números que va arriba de todo. La fecha va ABAJO, en el
## bloque de metadata, para que `diff` de dos corridas no ensucie con ella.
##
## LO QUE NO SE PUDO MEDIR tiene su propia sección y escribe los motivos
## tal cual los devolvieron los medidores. Un número inventado es peor que un
## hueco: el hueco se ve y el número se cree.

## Separador de columnas de la tabla de números, para que se lea de un vistazo.
const ANCHO_CLAVE: int = 34
const ANCHO_NUM: int = 14
const ANCHO_VEREDICTO: int = 11

## Extensión del informe de texto.
const RUTA_TEXTO: String = "informe_animacion.md"
## Extensión del volcado de máquina, para comparar número con número.
const RUTA_JSON: String = "informe_animacion.json"


## Los mismos datos, en markdown y en JSON.
static func texto(datos: Dictionary) -> String:
	var m: Dictionary = datos.get("meta", {}) as Dictionary
	var s: PackedStringArray = PackedStringArray()
	s.append("# Informe de animación — %s" % str(m.get("modelo", "?")))
	s.append("")
	s.append("Instrumento de la fase de medición. Los números de arriba son los que")
	s.append("se discuten; el detalle está abajo y la fecha, más abajo todavía.")
	s.append("")
	s.append("## Números")
	s.append("")
	s.append("%-*s %*s  %-*s" % [ANCHO_CLAVE, "número", ANCHO_NUM, "valor",
			ANCHO_VEREDICTO, "veredicto"])
	s.append("─".repeat(ANCHO_CLAVE + ANCHO_NUM + ANCHO_VEREDICTO + 8))
	for fila in _numeros(datos):
		s.append("%-*s %*s  %-*s" % [ANCHO_CLAVE, str(fila["clave"]),
				ANCHO_NUM, str(fila["valor"]), ANCHO_VEREDICTO,
				str(fila["veredicto"])])
	s.append("")
	s.append("## No se pudo medir")
	s.append("")
	var huecos: Array[String] = _no_medido(datos)
	if huecos.is_empty():
		s.append("- nada: se midió todo lo pedido")
	else:
		for h in huecos:
			s.append("- %s" % h)
	s.append("")
	s.append("## Clips del AnimationPlayer")
	s.append("")
	var clips: Dictionary = datos.get("clips", {}) as Dictionary
	if not bool(clips.get("ok", false)):
		s.append("- %s" % str(clips.get("motivo", "")))
	else:
		s.append("- nombres: %s" % ", ".join(_arreglo_strings(clips.get("clips", []))))
		var faltan: Array[String] = _arreglo_strings(clips.get("faltan", []))
		s.append("- faltan de los cuatro del juego: %s" % \
				("ninguno" if faltan.is_empty() else ", ".join(faltan)))
		s.append("- clip sonando: `%s` en t=%.3f s, speed_scale=%.3f, sonando=%s" % [
				str(clips.get("actual", "")), float(clips.get("posicion", 0.0)),
				float(clips.get("speed_scale", 0.0)), str(clips.get("sonando", false))])
		s.append("- hay AnimationTree activo: %s" % str(clips.get("arbol_activo", false)))
		s.append("")
		s.append("| clip | duración (s) | cicla | keys en piernas | pistas en piernas |")
		s.append("|---|---|---|---|---|")
		for nombre in _arreglo_strings(clips.get("clips", [])):
			var d: Dictionary = (clips.get("detalle", {}) as Dictionary).get(nombre, {}) as Dictionary
			s.append("| `%s` | %.3f | %s | %d | %d |" % [nombre,
					float(d.get("duracion", 0.0)), str(d.get("cicla", false)),
					int(d.get("keys_pierna", 0)), int(d.get("pistas_pierna", 0))])
	s.append("")
	s.append("## Ciclo: grados por frame")
	s.append("")
	var ciclo: Dictionary = datos.get("ciclo", {}) as Dictionary
	if not bool(ciclo.get("ok", false)):
		s.append("- %s" % str(ciclo.get("motivo", "")))
	else:
		s.append("- veredicto: **%s**" % str(ciclo.get("veredicto", "")))
		s.append("- grados acumulados en un ciclo (las dos piernas): %.1f" % \
				float(ciclo.get("giro_total", 0.0)))
		s.append("- pico de giro: %.2f grados/frame a 60 fps" % \
				float(ciclo.get("giro_max", 0.0)))
		s.append("- excursion vertical de cada hueso (u):")
		for clave in (ciclo.get("excursion", {}) as Dictionary).keys():
			s.append("    %-14s %.4f" % [clave,
					float((ciclo.get("excursion", {}) as Dictionary)[clave])])
	s.append("")
	s.append("## Patinaje (foot sliding)")
	s.append("")
	var patinazo: Dictionary = datos.get("patinazo", {}) as Dictionary
	if not bool(patinazo.get("ok", false)):
		s.append("- %s" % str(patinazo.get("motivo", "")))
	else:
		s.append("- velocidad natural del clip (zancada/ciclo): **%.3f u/s**" % \
				float(patinazo.get("velocidad_natural", 0.0)))
		s.append("- la misma, medida solo en la pisada: %.3f u/s" % \
				float(patinazo.get("velocidad_natural_ventana", 0.0)))
		s.append("- velocidad del juego: %.3f u/s" % float(patinazo.get("velocidad_juego", 0.0)))
		s.append("- patinaje por ciclo: **%.2f cm** (%.1f %% del avance del personaje)" % [
				float(patinazo.get("patinaje_cm", 0.0)), float(patinazo.get("patinaje_pct", 0.0))])
		s.append("- `speed_scale` que cancela el patinaje: **%.2f**" % \
				float(patinazo.get("speed_scale_sugerido", 0.0)))
		s.append("- veredicto: **%s**" % str(patinazo.get("veredicto", "")))
		s.append("")
		s.append("| pie | zancada (u) | pisada (% ciclo) | fiable | avance del personaje (cm) | pie en el mundo (cm) | deslizamiento (cm) | % | vel. natural ciclo | vel. natural pisada |")
		s.append("|---|---|---|---|---|---|---|---|---|---|")
		for clave in _orden_pies(patinazo.get("pies", {}) as Dictionary):
			var p: Dictionary = (patinazo.get("pies", {}) as Dictionary)[clave] as Dictionary
			if not bool(p.get("ok", false)):
				s.append("| `%s` | — | — | — | — | — | — | — | — | no medible: %s |" % [clave,
						str(p.get("motivo", ""))])
				continue
			s.append("| `%s` | %.3f | %.0f%% | %s | %.2f | %.2f | %.2f | %.1f | %.3f | %.3f |" % [
					clave, float(p["zancada"]), float(p["fraccion_de_ciclo"]) * 100.0,
					"si" if bool(p["fiable"]) else "NO",
					float(p["avance_personaje"]) * 100.0,
					float(p["recorrido_pie"]) * 100.0, float(p["deslizamiento_cm"]),
					float(p["deslizamiento_pct"]), float(p["velocidad_natural_ciclo"]),
					float(p["velocidad_natural_ventana"])])
	s.append("")
	s.append("## Dirección")
	s.append("")
	var direccion: Dictionary = datos.get("direccion", {}) as Dictionary
	s.append("- eje de avance del personaje: `%s`" % \
			_eje(direccion.get("direccion_juego", Vector3.ZERO)))
	s.append("- vuelta aplicada al modelo: %.4f rad (PI = el modelo mira al revés del eje del juego)" % \
			float(direccion.get("giro", 0.0)))
	s.append("- veredicto: **%s**" % str(direccion.get("veredicto", "")))
	if str(direccion.get("motivo", "")) != "":
		s.append("- ojo: %s" % str(direccion.get("motivo", "")))
	s.append("")
	s.append("Los dos números de cada pie van proyectados sobre el eje de avance del")
	s.append("juego (con la vuelta del modelo deshecha), así que el SIGNO lo es todo:")
	s.append("positivo es \"hacia donde va el personaje\", negativo es \"al revés\".")
	s.append("")
	s.append("| pie | eje del barrido (crudo) | amplitud X / Z (u) | en vuelo (u) | en contacto (u) | pisada (% del ciclo) | veredicto |")
	s.append("|---|---|---|---|---|---|---|")
	for clave in _orden_pies(direccion.get("pies", {}) as Dictionary):
		var p: Dictionary = (direccion.get("pies", {}) as Dictionary)[clave] as Dictionary
		if str(p.get("veredicto", "")) == "PERDIDO":
			s.append("| `%s` | — | — | — | — | — | no medible: %s |" % [clave,
					str(p.get("motivo", ""))])
			continue
		s.append("| `%s` | **%s** | %.3f / %.3f | %+.3f | %+.3f | %.0f%% | **%s** |" % [
				clave, str(p.get("eje_crudo", "?")), float(p.get("amplitud_x", 0.0)),
				float(p.get("amplitud_z", 0.0)), float(p.get("vuelo_hacia_adelante", 0.0)),
				float(p.get("contacto_hacia_adelante", 0.0)),
				float(p.get("fraccion_de_ciclo", 0.0)) * 100.0,
				str(p.get("veredicto", ""))])
	s.append("")
	s.append("Eje del barrido del hueso del pie a lo largo del ciclo: en crudo va "
			+ "hacia `%s`, y con la vuelta de `Cuerpo.GIRO_MODELO` ya aplicada va "
			% _eje_crudo(direccion)
			+ "hacia `%s`, mientras el personaje avanza hacia `%s`." % [
			_eje_mundo(direccion),
			_eje(direccion.get("direccion_juego", Vector3.ZERO))])
	s.append("")
	s.append("## Mezcla (blend_position)")
	s.append("")
	var blend: Dictionary = datos.get("blend", {}) as Dictionary
	if not bool(blend.get("ok", false)):
		s.append("- %s" % str(blend.get("motivo", "")))
	else:
		s.append("- veredicto: **%s** — la mezcla se mueve de verdad en el %.0f %% del barrido" % [
				str(blend.get("veredicto", "")), float(blend.get("rango_util", 0.0))])
		s.append("- llega a 1.0 (tope, se acabó el cross-fade) desde: %s u/s" % \
				_saturacion(blend))
		s.append("- barrido completo, 0 a %.2f u/s:" % float(blend.get("tope_barrido", 0.0)))
		s.append("")
		for linea in _lineas_blend(blend):
			s.append("    %s" % linea)
	s.append("")
	s.append("## Tira de PNGs (playtest visual)")
	s.append("")
	var tira: Dictionary = datos.get("tira", {}) as Dictionary
	if tira.is_empty():
		s.append("- no se corrió: `tools/tira_animacion.gd` es un paso aparte, "
				+ "porque necesita ventana")
	elif not bool(tira.get("ok", false)):
		s.append("- %s" % str(tira.get("motivo", "")))
	else:
		s.append("- ciclo renderizado en %d frames a %dx%d px, fondo uniforme `%s`" % [
				int(tira.get("frames", 0)), int(tira.get("ancho", 0)),
				int(tira.get("alto", 0)), str(tira.get("fondo", ""))])
		s.append("- velocidad a la que se renderiza la tira `mundo`: %.3f u/s" % \
				float(tira.get("velocidad", 0.0)))
		# Las dos tiras van por separado: `lugar` es el clip en el sitio y
		# `mundo` es el clip con el cuerpo avanzando de verdad, que es la que
		# muestra el patinaje contra las marcas del suelo.
		s.append("- `mundo` (el cuerpo avanza a la velocidad del juego, con el")
		s.append("  suelo rayado: si el pie patina, la bola se va de la marca): `%s`" % \
				str(tira.get("tira_mundo", "no se pudo renderizar")))
		s.append("- `lugar` (el ciclo en el sitio, para ver la máquina del clip): `%s`" % \
				str(tira.get("tira_lugar", "no se pudo renderizar")))
		s.append("- frames sueltos: `%s`" % str(tira.get("carpeta", "")))
	s.append("")
	s.append("## Metadata (cambia entre corridas, no forma parte del diff)")
	s.append("")
	for clave in _orden_meta(m):
		s.append("- %s: %s" % [clave, str(m[clave])])
	s.append("")
	return "\n".join(s)


## El bloque de arriba: tres columnas, en el MISMO orden siempre.
static func _numeros(datos: Dictionary) -> Array[Dictionary]:
	var filas: Array[Dictionary] = []
	var meta: Dictionary = datos.get("meta", {}) as Dictionary
	filas.append({"clave": "modelo", "valor": str(meta.get("modelo", "?")),
			"veredicto": ""})
	var clips: Dictionary = datos.get("clips", {}) as Dictionary
	if bool(clips.get("ok", false)):
		var detalle: Dictionary = clips.get("detalle", {}) as Dictionary
		var nombre_walk: String = "walk" if detalle.has("walk") else "?"
		var dur: float = float((detalle.get(nombre_walk, {}) as Dictionary).get("duracion", 0.0))
		filas.append({"clave": "clip walk (s)", "valor": "%.3f" % dur, "veredicto": ""})
		filas.append({"clave": "clips del juego que faltan",
				"valor": "%d" % (clips.get("faltan", []) as Array).size(),
				"veredicto": ""})
		filas.append({"clave": "speed_scale en juego",
				"valor": "%.3f" % float(clips.get("speed_scale", 0.0)), "veredicto": ""})
		filas.append({"clave": "clip sonando",
				"valor": str(clips.get("actual", "")), "veredicto": ""})
	var ciclo: Dictionary = datos.get("ciclo", {}) as Dictionary
	filas.append({"clave": "ciclo (grados acumulados)",
			"valor": "%.1f" % float(ciclo.get("giro_total", 0.0)),
			"veredicto": str(ciclo.get("veredicto", ""))})
	filas.append({"clave": "ciclo (grados/frame a 60 fps)",
			"valor": "%.2f" % float(ciclo.get("giro_max", 0.0)), "veredicto": ""})
	var patinazo: Dictionary = datos.get("patinazo", {}) as Dictionary
	filas.append({"clave": "patinaje por ciclo (cm)",
			"valor": "%.2f" % float(patinazo.get("patinaje_cm", NAN)),
			"veredicto": str(patinazo.get("veredicto", ""))})
	filas.append({"clave": "patinaje sobre el avance (%)",
			"valor": "%.1f" % float(patinazo.get("patinaje_pct", NAN)), "veredicto": ""})
	filas.append({"clave": "zancada del pie por ciclo (u)",
			"valor": "%.3f" % float(_campo_pies(patinazo, "zancada")), "veredicto": ""})
	filas.append({"clave": "velocidad natural del clip (u/s)",
			"valor": "%.3f" % float(patinazo.get("velocidad_natural", NAN)),
			"veredicto": ""})
	filas.append({"clave": "velocidad del juego (u/s)",
			"valor": "%.3f" % float(patinazo.get("velocidad_juego", NAN)), "veredicto": ""})
	filas.append({"clave": "speed_scale que cancela el patinaje",
			"valor": "%.2f" % float(patinazo.get("speed_scale_sugerido", NAN)),
			"veredicto": ""})
	var direccion: Dictionary = datos.get("direccion", {}) as Dictionary
	filas.append({"clave": "eje de avance del pie (crudo)",
			"valor": _eje_crudo(direccion), "veredicto": ""})
	filas.append({"clave": "eje de avance del pie (con giro PI)",
			"valor": _eje_mundo(direccion), "veredicto": ""})
	filas.append({"clave": "pie en vuelo, hacia adelante (u)",
			"valor": "%.3f" % float(_campo_pies_proyectado(direccion, "vuelo_hacia_adelante")),
			"veredicto": ""})
	filas.append({"clave": "pie en contacto, hacia adelante (u)",
			"valor": "%.3f" % float(_campo_pies_proyectado(direccion, "contacto_hacia_adelante")),
			"veredicto": str(direccion.get("veredicto", ""))})
	var blend: Dictionary = datos.get("blend", {}) as Dictionary
	var ritmos: Array = blend.get("tres_ritmos", []) as Array
	filas.append({"clave": "blend_position caminando lento",
			"valor": _blend_de(ritmos, 0), "veredicto": ""})
	filas.append({"clave": "blend_position trotando",
			"valor": _blend_de(ritmos, 1), "veredicto": str(blend.get("veredicto", ""))})
	filas.append({"clave": "blend_position corriendo",
			"valor": _blend_de(ritmos, 2), "veredicto": ""})
	filas.append({"clave": "blend se satura desde (u/s)",
			"valor": _saturacion(blend), "veredicto": ""})
	filas.append({"clave": "tira de PNGs", "valor": _tira(datos),
			"veredicto": ""})
	return filas


## Todos los huecos, en un solo bloque. Recorre lo que los medidores dejaron
## sin poder hacer y lo copia tal cual, con de dónde vino.
static func _no_medido(datos: Dictionary) -> Array[String]:
	var salida: Array[String] = []
	for seccion in ["clips", "ciclo", "patinazo", "direccion", "blend", "tira"]:
		var bloque: Dictionary = datos.get(seccion, {}) as Dictionary
		if bloque.is_empty():
			continue
		if not bool(bloque.get("ok", false)):
			var motivo: String = str(bloque.get("motivo", "")).strip_edges()
			if motivo != "":
				salida.append("%s: %s" % [seccion, motivo])
			continue
		for clave in bloque.keys():
			var valor: Variant = bloque[clave]
			if valor is Dictionary and not bool((valor as Dictionary).get("ok", true)):
				var por_que: String = str((valor as Dictionary).get("motivo", "")).strip_edges()
				if por_que != "":
					salida.append("%s/%s: %s" % [seccion, str(clave), por_que])
	return salida


static func guardar(datos: Dictionary, carpeta: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(carpeta):
		if DirAccess.make_dir_recursive_absolute(carpeta) != OK:
			return {"ok": false, "motivo": "no se pudo crear la carpeta %s" % carpeta}
	if not DirAccess.dir_exists_absolute(carpeta):
		return {"ok": false, "motivo": "la carpeta %s no existe" % carpeta}
	var ruta_txt: String = carpeta.path_join(RUTA_TEXTO)
	var ruta_json: String = carpeta.path_join(RUTA_JSON)
	var f_txt: FileAccess = FileAccess.open(ruta_txt, FileAccess.WRITE)
	if f_txt == null:
		return {"ok": false, "motivo": "no se pudo escribir %s" % ruta_txt}
	f_txt.store_string(texto(datos))
	f_txt.close()
	var f_json: FileAccess = FileAccess.open(ruta_json, FileAccess.WRITE)
	if f_json == null:
		return {"ok": false, "motivo": "no se pudo escribir %s" % ruta_json}
	f_json.store_string(json(datos))
	f_json.close()
	return {"ok": true, "txt": ruta_txt, "json": ruta_json}


## El volcado de máquina. Es el que se compara con un `diff -u` numérico, y el
## que se puede alimentar a otro script sin pasar por el texto.
static func json(datos: Dictionary) -> String:
	return JSON.stringify(datos, "  ")


## Un vector deGodot como eje legible: `+X`, `-Z`, `X0.0/Z-1.0`… El eje se
## escribe con signo porque lo que importa es si va O NO en la dirección del
## juego, y eso es el signo.
static func _eje(v: Variant) -> String:
	if not (v is Vector3):
		return "?"
	var p: Vector3 = v as Vector3
	if p.length() < 0.0001:
		return "ninguno"
	# Una componente cuenta si es el 5% de la mayor: el pie barre 0,74 u en Z
	# y 0,02 u en X, y si se listan las dos el informe dice "-X +Z" y parece
	# que la marcha va en diagonal cuando va recta.
	var mayor: float = maxf(maxf(absi(p.x), absi(p.y)), absi(p.z))
	var corte: float = mayor * 0.05
	var partes: PackedStringArray = PackedStringArray()
	if absf(p.x) > corte:
		partes.append("%sX" % ("+" if p.x > 0.0 else "-"))
	if absf(p.y) > corte:
		partes.append("%sY" % ("+" if p.y > 0.0 else "-"))
	if absf(p.z) > corte:
		partes.append("%sZ" % ("+" if p.z > 0.0 else "-"))
	return " ".join(partes) if not partes.is_empty() else "ninguno"


## El nombre del primer pie del bloque, para citar "el pie izquierdo" en una
## línea de prosa sin abrir la tabla.
static func _primer_pie(d: Dictionary) -> String:
	var orden: Array[String] = _orden_pies(d.get("pies", {}) as Dictionary)
	return "" if orden.is_empty() else orden[0]


static func _eje_crudo(d: Dictionary) -> String:
	var primero: String = _primer_pie(d)
	if primero == "":
		return "?"
	return _eje((d["pies"] as Dictionary)[primero].get("eje_crudo_vector", Vector3.ZERO))


static func _eje_mundo(d: Dictionary) -> String:
	var primero: String = _primer_pie(d)
	if primero == "":
		return "?"
	return _eje((d["pies"] as Dictionary)[primero].get("eje_mundo", Vector3.ZERO))


## El valor de la mezcla en el ritmo pedido (0 lento, 1 trote, 2 carrera), de
## la lista `tres_ritmos` y NO del barrido completo: son dos listas distintas y
## confundirlas fue un error pagado (daba el valor del segundo sample del
## barrido, que es un 10% de la velocidad, y parecía la mezcla del trote).
static func _blend_de(ritmos: Array, indice: int) -> String:
	if indice >= ritmos.size():
		return "—"
	return "%.3f" % float((ritmos[indice] as Dictionary)["blend"])


## La primera velocidad en la que la mezcla llega a 1.0, o "nunca".
static func _saturacion(blend: Dictionary) -> String:
	if not bool(blend.get("ok", false)):
		return "—"
	var v: float = float(blend.get("saturado_desde", NAN))
	return "nunca" if is_nan(v) else "%.2f" % v


## Igual que `_campo_pies`, pero para un campo que se promedia sobre los pies
## MEDIBLES. Misma regla, distinto nombre, porque leer "el promedio de un
## campo que no existe" en el informe es confuso.
static func _campo_pies_proyectado(bloque: Dictionary, campo: String) -> float:
	return _campo_pies(bloque, campo)


## El promedio de un campo de todos los pies medibles del bloque.
static func _campo_pies(bloque: Dictionary, campo: String) -> float:
	var pies: Dictionary = bloque.get("pies", {}) as Dictionary
	var suma: float = 0.0
	var cuenta: int = 0
	for clave in pies.keys():
		var p: Dictionary = pies[clave] as Dictionary
		# Por `has`, no por `ok`: un pie con veredicto `AL_REVES` tiene `ok`
		# en false y sus numeros son justo los que hay que promediar.
		if p.has(campo):
			suma += float(p[campo])
			cuenta += 1
	return 0.0 if cuenta == 0 else suma / float(cuenta)


static func _tira(datos: Dictionary) -> String:
	var tira: Dictionary = datos.get("tira", {}) as Dictionary
	if tira.is_empty():
		return "no corrida"
	if not bool(tira.get("ok", false)):
		return "no medible"
	return "%d frames" % int(tira.get("frames", 0))


static func _lineas_blend(blend: Dictionary) -> Array[String]:
	var salida: Array[String] = []
	if not bool(blend.get("ok", false)):
		return salida
	for m in (blend.get("muestras", []) as Array):
		var fila: Dictionary = m as Dictionary
		salida.append("v=%5.2f u/s  blend=%5.3f  %-6s %sx" % [
				float(fila["velocidad"]), float(fila["blend"]),
				str(fila["actual"]), str(fila["speed"])])
	return salida


## Orden estable de los pies: primero el izquierdo, después el derecho. El
## `Dictionary` de Godot no tiene orden, y un informe que cambia de columnas
## entre corridas no se puede diffear.
static func _orden_pies(pies: Dictionary) -> Array[String]:
	var salida: Array[String] = []
	for clave in ["izq.pie", "der.pie"]:
		if pies.has(clave):
			salida.append(clave)
	for clave in pies.keys():
		if not salida.has(clave):
			salida.append(clave)
	return salida


static func _orden_meta(m: Dictionary) -> Array[String]:
	var salida: Array[String] = []
	for clave in m.keys():
		salida.append(str(clave))
	salida.sort()
	return salida


static func _arreglo_strings(v: Variant) -> Array[String]:
	var salida: Array[String] = []
	if v is Array:
		for e in (v as Array):
			salida.append(str(e))
	return salida


