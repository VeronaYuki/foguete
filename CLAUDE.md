# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

FOGUETE is a three-phase sci-fi vertical slice built in Godot 4.7 (GDScript, Forward Plus). It is **100% procedural**: every model, texture, sound effect, and level is generated in code — there are no asset files and none should be added.

## Commands

There is no build, lint, or test tooling — the only workflow is running the game in Godot.

```sh
godot --path .                          # run the game (starts at Phase 1)
godot --path . scenes/cockpit.tscn      # run a single phase directly
godot --headless --import .             # refresh class registry (required after adding a new class_name)
FOGUETE_PHOTO=1 godot --path . [scene]  # photo mode: flies a camera through the level, saves stills to .shots/
```

Photo mode is the primary way to review visuals without playing — each of the three phase scripts checks `FOGUETE_PHOTO` in `_ready()` and has its own `_photo_mode()` flythrough.

## Architecture

**Scenes are stubs; scripts build everything.** Each `.tscn` in `scenes/` is a single root node with a script attached. All geometry, materials, lighting, HUD, and audio are constructed in code from that script's `_ready()`. To change a level, edit its script — never the scene file.

**Phase flow.** `scripts/flow.gd` is the only autoload (`Flow`). It holds run stats (`kills`, `run_time`) and switches phases via `goto_planet()` / `goto_cockpit()` / `goto_runner()`. The run sequence:

1. `scenes/slime_planet.tscn` + `planet_main.gd` — Phase 1, FPS escape (main scene; calls `Flow.start_run()`)
2. `scenes/cockpit.tscn` + `cockpit.gd` — Phase 2, 2D Control-based console puzzles (Simon memory game + Robozzle-style probe programming)
3. `scenes/runner.tscn` + `runner_main.gd` — Phase 3, third-person ascent runner (calls `Flow.finish()` and shows run stats)

Phase transitions and restarts must go through `Flow` — its `_change()`/`restart_phase()` reset `Engine.time_scale` and the mouse mode, which phases mutate (slow-mo effects, mouse capture).

**Bonus mini-game.** `scenes/main.tscn` + `game_manager.gd` is a separate, earlier physics rocket-landing game kept as a bonus. It is not part of the phase flow and is run directly from the editor. The reusable `class_name` classes (`Rocket`, `Terrain`, `LandingPad`, `ChaseCamera`, `HUD`, `Crosshair`) belong to it; `Terrain` and `Sfx` are also used by the phase scripts.

**Audio.** `sfx.gd` (`Sfx`) synthesizes all sounds from waveforms at startup. Each phase instantiates its own `Sfx` node. New sounds are added as `_gen_*()` generator functions there.

**Face control.** Phase 3 supports webcam control: `tools/face_tracker.py` (Python + OpenCV, runs outside Godot) streams head position and smile state as JSON over UDP port 46464 and JPEG preview frames (mirror view + tracking overlay) over UDP 46465; `scripts/face_control.gd` (`FaceControl`) listens, exposes `head`/`smiling`/`active`/`preview_texture` plus a `smile_started` signal, and best-effort auto-launches the tracker (venv expected at `~/.local/share/foguete/venv`; uses `flatpak-spawn --host` when Godot runs in flatpak). `runner_main.gd` steers from `face.head`, triggers a 2 s speed boost on `smile_started`, and shows the preview bottom-right in the HUD. Everything degrades to WASD when no tracker/face is present — never make face control mandatory.

**Voice control.** `scripts/voice_control.gd` (`VoiceControl`) is fully in-engine: it captures the microphone via an `AudioEffectCapture` on a silenced `MicCapture` bus (`audio/driver/enable_input=true` in `project.godot`) and emits `piu_detected` on short loud high-pitched bursts — say "PIU!" to fire in Phase 3. The bus is created once and reused across scene reloads.

**Conventions.**
- `.uid` files next to scripts/shaders are Godot metadata — keep them paired with their file when renaming/moving.
- Input actions (move, fire, dash, interact, restart, quit, plus the mini-game's thrust/pitch/roll) are defined in `project.godot`; use action names, not raw keycodes.
- Gravity is globally lowered to 5.0 in `project.godot` — physics tuning assumes it.
- `runner_main.gd` seeds its RNG (`rng.seed = 1234`) for a deterministic obstacle course; keep phases deterministic where they already are.
