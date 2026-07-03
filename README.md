# FOGUETE 🚀

A three-mission sci-fi campaign built in **Godot 4.7**. Levels, materials, HUD, and most sound effects are generated in code; a handful of imported assets round it out (the tooth-ship and other `.glb` models in `assets/`, character portraits, recorded rocket sounds, and the background music in `audio/`).

## The campaign (~3 minutes per run)

The game opens on a title screen with mission select. Progress persists between sessions (`user://save.json`): missions unlock in order, and best time / kills / deaths are recorded per mission.

1. **Pântano de VH-9** — first-person escape across a dark bioluminescent swamp. Captain Gus radios the briefing over your helmet HUD, then xenomorph-like hunters come for you — including **O Alfa**, the boss with his own health bar. Find the tooth-rocket by its light beacon and get inside. Somewhere out there hides a **gold tooth**: find it to permanently upgrade your toothbrush gun.
2. **Pré-Lançamento (Hangar Odonto)** — the swamp landing damaged the tooth-ship. Restore it with three dental procedures: fill the hull cavities with amalgam pieces (shape-fit puzzle), rotate the root-canal segments to route reactor power to both root thrusters (pipe puzzle), and repeat the brushing protocol to polish the enamel shield (memory sequence). The tooth visibly heals as you work; finish all three to launch.
3. **Ascensão à Lua** — third-person runner to the Moon. Dodge tumbling satellites, asteroids, and comets, shoot back at hostile ships, and survive with 3 shields. Victory plays a lunar landing cinematic — flag planted on real Petavius terrain — and Eric from Mission Control delivers the ending transmission.

## Controls

| Phase | Keys |
|---|---|
| Menu | mouse |
| Swamp | WASD move · SHIFT sprint · SPACE jump · Q dash · mouse aim · LMB fire · E interact |
| Hangar | mouse only (right-click rotates an amalgam piece) |
| Ascent | WASD **or head-lean** steer · **smile = 2s boost** · LMB or say **"PIU!"** to fire |
| Everywhere | R restart phase · ESC quit |

### Face control (Ascent)

Mission 3 can be flown with your webcam: lean your head to steer the rocket and **smile to trigger a 2-second boost**. A live mirror preview with the tracking overlay shows in the bottom-right of the HUD so you can see where your head is. A small Python tracker (`tools/face_tracker.py`) reads the webcam with OpenCV and streams head position + smile state (UDP 46464) plus JPEG preview frames (UDP 46465) to the game. The game launches it automatically when it can; you can also run it by hand to watch the tracking status:

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
   godot --path .                     # campaign menu
   godot --path . scenes/runner.tscn  # jump straight into a mission
   ```

## For developers

- Scenes are minimal stubs; each phase builds itself in code from its script in `scripts/` (`planet_main.gd`, `cockpit.gd`, `runner_main.gd`). `flow.gd` is the autoload that owns campaign progression, the save file, per-mission stats, upgrades, and phase transitions.
- `scenes/main.tscn` is an earlier, separate mini-game (physics rocket-landing) kept as a bonus — run it directly from the editor.
- **Photo mode**: `FOGUETE_PHOTO=1 godot --path . [scene]` flies a camera through a level and saves stills to `.shots/` — useful for reviewing visuals without playing. Extra one-shot captures: `FOGUETE_PHOTO_MENU`, `FOGUETE_PHOTO_GUN`, `FOGUETE_PHOTO_BOSS`, `FOGUETE_PHOTO_GUS`.
- After adding a script with a new `class_name`, run `godot --headless --import .` once (or open the editor) so the class registry updates.
