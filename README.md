# FOGUETE 🚀

A three-phase sci-fi vertical slice built in **Godot 4.7** — 100% procedural: every model, texture, sound effect, and level is generated in code. Zero downloaded assets.

## The run (~3 minutes)

1. **VH-9 · The Swamp** — first-person escape across a dark bioluminescent planet. Xenomorph-like creatures hunt you; find the rocket by its light beacon and get inside.
2. **Pre-Launch Check** — two cockpit consoles: a color-sequence memory calibration and a program-the-probe logic puzzle (Robozzle-style). Solve both to ignite the engines.
3. **Ascent** — third-person runner to the Moon. Dodge tumbling satellites and comets, shoot back at hostile ships, survive with 3 shields.

## Controls

| Phase | Keys |
|---|---|
| Swamp | WASD move · SHIFT sprint · SPACE jump · Q dash · mouse aim · LMB fire · E interact |
| Cockpit | mouse only |
| Ascent | WASD steer · LMB fire |
| Everywhere | R restart phase · ESC quit |

## Running it

1. Install [Godot 4.7](https://godotengine.org/download) (no extra dependencies).
2. Open `project.godot` in the editor and press ▶ (F5) — or from a terminal:
   ```sh
   godot --path .
   ```

## For developers

- Scenes are minimal stubs; each phase builds itself in code from its script in `scripts/` (`planet_main.gd`, `cockpit.gd`, `runner_main.gd`). `flow.gd` is the autoload that carries run stats and switches phases.
- `scenes/main.tscn` is an earlier, separate mini-game (physics rocket-landing) kept as a bonus — run it directly from the editor.
- **Photo mode**: `FOGUETE_PHOTO=1 godot --path . [scene]` flies a camera through a level and saves stills to `.shots/` — useful for reviewing visuals without playing.
- After adding a script with a new `class_name`, run `godot --headless --import .` once (or open the editor) so the class registry updates.
