# Entorno de la máquina (lo que NO está en el repo)

Todo lo que la PC nueva necesita y que no se puede subir a Git. Rutas y versiones
verificadas el 28-09-2026 en la máquina original (Omarchy, Arch).

| Qué | Versión / ruta | Nota |
|---|---|---|
| **Godot** | `4.7.2.stable.official.ed1daf0bf` | el motor del juego |
| **Blender portable** | `~/Tools/blender/blender` — 4.5.14 LTS | sin root, en `~/Tools`, **fuera del repo** |
| **Packs de modelos** | `~/Projects/modelos-3d-descarga/*.zip` — 2,6 GB | 5 packs (boss, clase, creep, job, npc) |
| **Piloto extraído** | `~/Projects/modelos-3d-descarga/piloto/` | 11 entradas ya extraídas |
| **Inventario** | `~/Projects/modelos-3d-descarga/inventario.json` | el mapa de los 85 modelos |
| **opencode-relay** | servicio systemd de usuario | rotación de IP para descargas |
| **omarchy-opencode-vpn** | `~/Projects/omarchy-opencode-vpn` | plugin de barra + scripts de rotación |

## Godot

Si la PC nueva no lo tiene, el juego se abre igual desde el editor, pero los
scripts de refactor y el bench de GPU asumen el 4.7.2. Versiones distintas
pueden cambiar el import de los `.glb` y ensuciar el repo.

## Blender portable (imprescindible)

El pipeline de modelos es Blender headless, en modo portable, sin sudo
(`--background --python`), con la versión **4.5 LTS** en `~/Tools`. Los scripts
del repo lo invocan por esa ruta, así que si en la PC nueva no está, o la ruta
cambia, hay que corregir la constante en `tools/preparar_modelo.py` (y en
cualquier script que la repita).

## Los packs de modelos (2,6 GB)

No están en el repo a propósito: son 2,6 GB y hay 85 modelos dentro. Lo que sí
está en el repo son los **ya extraídos y usados** (104 MB en `models/`).

Para volver a bajarlos hace falta lo mismo que se usó la primera vez:

```sh
omarchy-shell j.opencode-vpn status      # el túnel Proton (full-tunnel)
rotate-vpn.sh                            # rota la IP si GitHub limita
```

Los packs vienen de **descargas con token de GitHub** (`gh release download`
sobre repos de assets CC0/CC-BY). **Nunca Blizzard**, ni siquiera como
referencia: la regla del proyecto es 85 modelos autorizados, solo CC0/CC-BY, y
cualquier otra cosa no entra. Cuando se baje un pack nuevo:

1. Se descomprime en `~/Projects/modelos-3d-descarga/`.
2. Se añade al `inventario.json` la ruta de quién es quién.
3. Se crea un piloto en `piloto/` antes de meter nada en `models/`.

## Modelo de trabajo que no está en los archivos

- **Todo cambio importante se ve al pulsar F5** (o `godot --path .`). Un cambio
  que solo existe en un render de Blender no cuenta: la Fase 50.2 cerró las
  manos en el modelo y en la pantalla seguían extendidas.
- Cada fase acaba con: tests → commit → tag `fase-NN.N` → release → SHA-256
  (el usuario lo pide para verificar la descarga).
- El bench de GPU se mide con la ventana enfocada; sin foco, Wayland estrangula
  a ~7,5 Hz y las cifras no valen.

## Lo único que NO hay que rehacer

- **El repo**: `git clone https://github.com/extramega1-stack/Golden-Gods-RPG-v2.git`
- **Los modelos ya integrados**: van en git (`models/`, 104 MB).
- **La conversación**: `handover/sesion-ggv2-2026-09-28.json.gz` (ver
  [`README.md`](README.md)).
