# Traspaso a la PC nueva

Todo lo necesario para retomar este proyecto en otra máquina, incluido **el
historial de la conversación con OpenCode**.

- **Sesión exportada:** `sesion-ggv2-2026-09-28.json.gz` (0,8 MB)
- **Session ID:** `ses_f2c05d0b4ffeYR21N5g3XQZjzx` — *Punto donde quedó conversación*
- **Generado con:** opencode `1.18.32` (26-09-2026), 1.308 mensajes

---

## 1. Traer el proyecto

```sh
git clone https://github.com/extramega1-stack/Golden-Gods-RPG-v2.git
cd Golden-Gods-RPG-v2
```

El repo ya trae los 104 MB de modelos 3D en `models/`, así que el juego se abre
sin descargar nada más. Falta lo demás (Blender, packs de modelos): mira
[`ENTORNO.md`](ENTORNO.md).

## 2. Abrir la conversación

```sh
cd handover
gunzip sesion-ggv2-2026-09-28.json.gz
opencode import sesion-ggv2-2026-09-28.json
opencode -s ses_f2c05d0b4ffeYR21N5g3XQZjzx     # abrir y seguir la conversación
```

`opencode import` **no** acepta `.gz`: hay que descomprimir antes (el paso
`gunzip` va por eso). Verificado: el import recrea los 1.308 mensajes y las
5.004 partes, y la sesión aparece en `opencode session list`.

> La sesión se grabó con el directorio de trabajo `/home/webo`. Al abrirla en la
> PC nueva, `opencode` laontinúa desde donde la dejes; para trabajar dentro del
> juego, `cd Golden-Gods-RPG-v2` antes de arrancar.

### Qué lleva el archivo y qué no

| | |
|---|---|
| Texto del usuario y del asistente | **íntegro** |
| Razonamientos, pasos y llamadas a herramienta | **conservados** (resumen de 400 caracteres) |
| Volcados grandes: capturas en base64, listados de ficheros, logs completos | recortados |
| Razonamiento cifrado del modelo (`reasoningEncryptedContent`) | vaciado (basura específica de esta máquina) |
| **Credenciales** | **redactadas** (ver abajo) |

El objetivo era que el archivo **cupiera en git**. El historial completo son 55 MB
sin recortar, 37 MB con gzip: no entran. Si en algún momento lo quieres entero,
en la PC original:

```sh
opencode export ses_f2c05d0b4ffeYR21N5g3XQZjzx > sesion-full.json
```

### Aviso de credenciales

Al exportar la sesión aparecieron **un token de GitHub (`ghr_…`) y dos claves
`sk-…`** en salidas de herramientas antiguas. En la copia del repo están
redactados (`<REDACTED_CLAVE_SK>`, `<REDACTED_GITHUB_TOKEN>`), verificado con un
barrido de patrones: 0 secretos en el archivo. Aun así, si la sesión completa la
vas a compartir, **rota esas credenciales antes**.

---

## 3. Dónde lo dejamos

Proyecto completo hasta la **Fase 50.3** (historia completa en
[`docs/MASTER_SPEC.md`](../docs/MASTER_SPEC.md), 1.100 líneas de bitácora).

- **Estado del juego:** el jugador ya es un humanoide con modelos reales de las
  5 clases, animations propias (`idle`/`walk`/`attack`/`die`) y el bandido es el
  primer enemigo con modelo 3D. El mundo es placeholder todavía.
- **Lo último que arreglé:** las manos. Dos veces. La Fase 50.2 cerró la ropa en
  vez de la mano (la muñeca del lado derecho salía 34 cm desplazada porque no
  reflejaba el hombro). La 50.3 **detecta** la mano por la forma de la malla en
  vez de calcularla, con guarda de ropa. Commit `654755b`, tag `fase-50.3`.
- **Pendiente conocido, en orden:**
  1. **El equipo no sigue a la animación** (casco y armas anclados a offsets
     fijos). Se arregla con los huesos que ya tiene el esqueleto.
  2. **El mago conserva las manos abiertas** a propósito: su túnica se confunde
     con las manos y el script lo salta antes que deformarle el vestido. Pide
     una solución a medida.
  3. 79 modelos por integrar de los 85 packs.
  4. Mundo: todo placeholder.
- **Lección que me llevé de esta fase** (y que está en `AGENTS.md`): una
  verificación en Blender no es una verificación. El fallo de las manos era
  visible en pantalla y yo lo di por bueno porque los renders cuadraban. Si algo
  no cuadra, dilo aunque yo crea que sí.

## 4. Lo que hay que rehacer en la máquina nueva

Todo lo que vive **fuera** del repo está en [`ENTORNO.md`](ENTORNO.md): Godot,
Blender portable, los 2,6 GB de packs de modelos, el proyecto `omarchy-relay` y
el servicio `opencode-relay` (necesario para volver a bajar packs a speed).
