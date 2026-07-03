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
| Ascent | WASD **or head-lean** steer · **smile = 2s boost** · LMB or say **"PIU!"** to fire |
| Everywhere | R restart phase · ESC quit |

### Face control (Ascent)

Phase 3 can be flown with your webcam: lean your head to steer the rocket and **smile to trigger a 2-second boost**. A live mirror preview with the tracking overlay shows in the bottom-right of the HUD so you can see where your head is. A small Python tracker (`tools/face_tracker.py`) reads the webcam with OpenCV and streams head position + smile state (UDP 46464) plus JPEG preview frames (UDP 46465) to the game. The game launches it automatically when it can; you can also run it by hand to watch the tracking status:

```sh
python3 -m venv ~/.local/share/foguete/venv
~/.local/share/foguete/venv/bin/pip install "opencv-python-headless==4.*"
~/.local/share/foguete/venv/bin/python tools/face_tracker.py
```

Hold your head still for a second at startup — that pose is calibrated as "fly straight". The HUD shows `FACE ✓` when tracking is live; without a tracker or a visible face the phase falls back to WASD.

### Voice fire (Ascent)

Say **"PIU!"** to shoot. This one is fully in-engine: `voice_control.gd` captures the microphone through an `AudioEffectCapture` on a silenced bus and fires on short, loud, high-pitched bursts (adaptive noise floor + zero-crossing gate — no speech model). The mouse button always works too.

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
