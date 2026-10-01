# Golden Gods RPG — Remake

Rewrite limpio del proyecto **Golden Gods RPG** (Godot 4.7.2), empezado desde cero
por decisión de Juan Diego el 2026-09-21: el proyecto anterior acumuló 26 versiones
de parches y se congeló como referencia.

- **Motor:** Godot 4.7.2
- **Género:** RPG local single-player, mundo abierto estilo Lineage II / MU
- **Documento maestro:** [`docs/MASTER_SPEC.md`](docs/MASTER_SPEC.md) — inventario
  completo de sistemas, canon narrativo, controles, estándar de código y plan de fases.
- **Proyecto legado (referencia, no tocar):**
  https://github.com/extramega1-stack/Golden-Gods-RPG (congelado en v10.26.0)

## Estado

**Fase 72.** El juego es jugable de principio a fin: título → creación de
personaje → mundo abierto → pausa → volver al título, con guardado que sobrevive
al cierre.

Contenido real, no placeholders:

| Sistema | Qué hay |
|---|---|
| Combate | Ciclo completo con hit-stop, knockback, telegrafía de jefe, fases y élites |
| Progresión | XP, niveles, 4 atributos, equipo, inventario, 40 habilidades, 15 talentos, NG+ |
| Misiones | 56 misiones encadenadas (5 actos + 2 finales canónicos) |
| Enemigos | 20 arquetipos con IA determinista; 6 jefes con 3 fases y enrage |
| Mundo | 36.864 u, 10 regiones, 9 ciudades, 1.133 spawns, ciclo día/noche, clima |
| Personajes | 5 clases con modelo 3D y esqueleto, y 1 arquetipo enemigo con modelo |

Verificación: **121/121 tests en verde** (`tools/run_tests.sh --smokes`), y el
p95 de frame time entra en presupuesto en la GTX 1660 de referencia
(`docs/bench_gtx1660.md`).

Lo que falta para terminar: condiciones de victoria y derrota, y pulido de los
sistemas que están escritos pero aún no se alcanzan jugando.

## Abrir el proyecto

1. **Godot 4.7.2** (rama 4.x estable). En esta máquina:
   `/home/webo/Tools/godot/godot`
2. Importar `project.godot` desde el editor, o correr directo:

   ```sh
   /home/webo/Tools/godot/godot --path /home/webo/Projects/Golden-Gods-RPG-v2
   ```

   La escena principal es `scenes/titulo/pantalla_titulo.tscn` (la que declara
   `run/main_scene` en `project.godot`).

## Correr los tests

```sh
# Suite completa (121 tests). Sale con codigo != 0 si hay alguno en rojo.
GODOT=/home/webo/Tools/godot/godot tools/run_tests.sh --smokes

# Uno suelto
GODOT=/home/webo/Tools/godot/godot tools/run_tests.sh test_fase71_clips

# Parseo de un script nuevo (0 fallos)
godot --headless --path . --check-only --script res://scripts/<dominio>/<script>.gd
```

Si agregaste un `class_name` nuevo, corré `godot --headless --path . --import`
ANTES de los tests: el tipo se registra en la caché global de clases de Godot, no
en el repo, y sin ese paso media suite se cae con
`Could not find type "X" in the current scope`.
