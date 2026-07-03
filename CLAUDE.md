# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

FOGUETE is a three-mission sci-fi campaign built in Godot 4.7 (GDScript, Forward Plus). Levels, materials, lighting, HUD, and most sound effects are **generated in code**; the exceptions are the imported assets in `assets/` (`.glb` models + textures: tooth-ship, asteroids, satellites, enemy ships, moon/Petavius terrain, astronaut, Capim flag), the character portraits (`gus.png`, `eric.png`, `lucas.png`), and the audio files in `audio/` (background music MP3s and recorded rocket WAVs). Scripts that use imported models guard with `ResourceLoader.exists()` and fall back to procedural geometry — keep that pattern.

## Commands

There is no build, lint, or test tooling — the only workflow is running the game in Godot.

```sh
godot --path .                          # run the game (campaign title/mission-select menu)
godot --path . scenes/cockpit.tscn      # run a single mission directly
godot --headless --import .             # refresh class registry (required after adding a new class_name)
FOGUETE_PHOTO=1 godot --path . [scene]  # photo mode: flies a camera through the level, saves stills to .shots/
```

Photo mode is the primary way to review visuals without playing — each of the three mission scripts checks `FOGUETE_PHOTO` in `_ready()` and has its own `_photo_mode()` flythrough. There are also one-shot capture variants: `FOGUETE_PHOTO_MENU` (main menu), `FOGUETE_PHOTO_GUN`, `FOGUETE_PHOTO_BOSS`, `FOGUETE_PHOTO_GUS` (all in `planet_main.gd`).

## Architecture

**Scenes are stubs; scripts build everything.** Each `.tscn` in `scenes/` is a single root node with a script attached. All geometry, materials, lighting, HUD, and audio are constructed in code from that script's `_ready()`. To change a level, edit its script — never the scene file.

**Campaign flow.** `scripts/flow.gd` is the only autoload (`Flow`). It owns campaign progression persisted to `user://save.json` (mission unlocks, per-mission records — best time / kills / deaths — and cross-mission upgrades: `brush_power`, `gold_tooth`, `runner_shields`), live run stats (`kills`, `run_time`), and scene transitions via `goto_menu()` / `start_mission()` / `goto_planet()` / `goto_cockpit()` / `goto_runner()`. The sequence:

1. `scenes/main_menu.tscn` + `main_menu.gd` — title + mission select (main scene; reads progress from `Flow`)
2. `scenes/slime_planet.tscn` + `planet_main.gd` — Mission 1 "Pântano de VH-9", FPS escape (calls `Flow.start_run()`): Captain Gus briefing (`CaptainBriefing`), hunter aliens, boss O Alfa, hidden gold-tooth collectible (`Flow.grant_gold_tooth()`)
3. `scenes/cockpit.tscn` + `cockpit.gd` — Mission 2 "Pré-Lançamento" (hangar odonto): restore the damaged tooth-ship via three 2D Control-based dental puzzles (amalgam filling shape-fit, root-canal pipe routing, enamel-polish memory sequence played on the central tooth view)
4. `scenes/runner.tscn` + `runner_main.gd` — Mission 3 "Ascensão à Lua", third-person ascent runner; on victory plays the lunar-landing cinematic (flag on Petavius terrain) and Eric's ending transmission (reuses `CaptainBriefing`), then calls `Flow.finish()`

Scene transitions and restarts must go through `Flow` — its `_change()`/`restart_phase()` reset `Engine.time_scale` and the mouse mode, which missions mutate (slow-mo effects, mouse capture). Mission completion goes through `clear_current_mission()`, which records stats, unlocks the next mission, and saves.

**Bonus mini-game.** `scenes/main.tscn` + `game_manager.gd` is a separate, earlier physics rocket-landing game kept as a bonus. It is not part of the phase flow and is run directly from the editor. The reusable `class_name` classes (`Rocket`, `Terrain`, `LandingPad`, `ChaseCamera`, `HUD`, `Crosshair`) belong to it; `Terrain` and `Sfx` are also used by the phase scripts.

**Audio.** `sfx.gd` (`Sfx`) synthesizes most sounds from waveforms at startup. Each phase instantiates its own `Sfx` node. New sounds are added as `_gen_*()` generator functions there. Exceptions: background music (`audio/*.mp3`) and the four recorded rocket sounds (`audio/rocket_*.wav` — engine loop, boost, crash, ship explosion), which `Sfx._load_wav()` loads with a graceful fallback to the synthesized versions when the files are missing.

**Face control.** Phase 3 supports webcam control: `tools/face_tracker.py` (Python + OpenCV, runs outside Godot) streams head position and smile state as JSON over UDP port 46464 and JPEG preview frames (mirror view + tracking overlay) over UDP 46465; `scripts/face_control.gd` (`FaceControl`) listens, exposes `head`/`smiling`/`active`/`preview_texture` plus a `smile_started` signal, and best-effort auto-launches the tracker (venv expected at `~/.local/share/foguete/venv`; uses `flatpak-spawn --host` when Godot runs in flatpak). `runner_main.gd` steers from `face.head`, triggers a 2 s speed boost on `smile_started`, and shows the preview bottom-right in the HUD. Everything degrades to WASD when no tracker/face is present — never make face control mandatory.

**Voice control.** `scripts/voice_control.gd` (`VoiceControl`) is fully in-engine: it captures the microphone via an `AudioEffectCapture` on a silenced `MicCapture` bus (`audio/driver/enable_input=true` in `project.godot`) and emits `piu_detected` on short loud high-pitched bursts — say "PIU!" to fire in Phase 3. The bus is created once and reused across scene reloads.

**Conventions.**
- `.uid` files next to scripts/shaders are Godot metadata — keep them paired with their file when renaming/moving.
- Input actions (move, fire, dash, interact, restart, quit, plus the mini-game's thrust/pitch/roll) are defined in `project.godot`; use action names, not raw keycodes.
- Gravity is globally lowered to 5.0 in `project.godot` — physics tuning assumes it.
- `runner_main.gd` seeds its RNG (`rng.seed = 1234`) for a deterministic obstacle course; keep phases deterministic where they already are.
