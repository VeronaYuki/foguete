extends Node
## Autoload: campaign progression, per-mission stats, upgrades, and scene flow.
## Persists to user://save.json so progress survives between sessions.

const MENU := "res://scenes/main_menu.tscn"
const PLANET := "res://scenes/slime_planet.tscn"
const COCKPIT := "res://scenes/cockpit.tscn"
const RUNNER := "res://scenes/runner.tscn"

const SAVE_PATH := "user://save.json"
const MISSION_COUNT := 3
const MISSION_NAMES := {
	1: "PÂNTANO DE VH-9",
	2: "PRÉ-LANÇAMENTO",
	3: "ASCENSÃO À LUA",
}
const MISSION_SCENES := { 1: PLANET, 2: COCKPIT, 3: RUNNER }

# --- live run state (current mission attempt) ---
var kills := 0
var run_time := 0.0
var timing := false
var current_mission := 1

# --- persisted campaign state ---
var data := {}


func _ready() -> void:
	_load()


func _process(delta: float) -> void:
	if timing:
		run_time += delta


# ---------- persistence ----------

func _default_data() -> Dictionary:
	return {
		"furthest": 1,               # highest unlocked mission (1..3)
		"missions": {},              # "1": {cleared, best_time, best_kills, deaths}
		"upgrades": {                # carried between missions
			"brush_power": 0,        # faster/stronger toothbrush
			"gold_tooth": false,     # hidden collectible found
			"runner_shields": 0,     # extra shields (applied in phase 3 on merge)
		},
	}


func _load() -> void:
	data = _default_data()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		# merge onto defaults so new fields survive old saves
		for k in parsed:
			if k == "upgrades" and typeof(parsed[k]) == TYPE_DICTIONARY:
				for uk in parsed[k]:
					data.upgrades[uk] = parsed[k][uk]
			else:
				data[k] = parsed[k]


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func reset_progress() -> void:
	data = _default_data()
	save()


# ---------- queries for the menu ----------

func furthest() -> int:
	return int(data.get("furthest", 1))

func is_unlocked(mission: int) -> bool:
	return mission <= furthest()

func mission_record(mission: int) -> Dictionary:
	var m: Dictionary = data.get("missions", {})
	return m.get(str(mission), {})

func upgrade(name: String) -> Variant:
	return data.get("upgrades", {}).get(name, 0)


# ---------- run lifecycle ----------

func start_mission(mission: int) -> void:
	current_mission = mission
	_reset_stats()
	_change(MISSION_SCENES.get(mission, PLANET))


func _reset_stats() -> void:
	kills = 0
	run_time = 0.0
	timing = true


func start_run() -> void:
	# called by the planet on _ready; safe whether launched from the menu or directly
	current_mission = 1
	_reset_stats()


func register_death() -> void:
	var rec := _rec(current_mission)
	rec.deaths = int(rec.get("deaths", 0)) + 1
	_write_rec(current_mission, rec)
	save()


func clear_current_mission() -> void:
	timing = false
	var rec := _rec(current_mission)
	rec.cleared = true
	var bt: float = rec.get("best_time", 0.0)
	if bt <= 0.0 or run_time < bt:
		rec.best_time = run_time
	rec.best_kills = maxi(int(rec.get("best_kills", 0)), kills)
	_write_rec(current_mission, rec)

	data.furthest = maxi(furthest(), mini(current_mission + 1, MISSION_COUNT))
	_grant_upgrades(current_mission)
	save()


func _grant_upgrades(mission: int) -> void:
	if mission == 1:
		# surviving the swamp earns a reinforced shield for the ascent
		data.upgrades.runner_shields = maxi(int(data.upgrades.runner_shields), 1)


func grant_gold_tooth() -> void:
	data.upgrades.gold_tooth = true
	data.upgrades.brush_power = maxi(int(data.upgrades.brush_power), 1)
	save()


func _rec(mission: int) -> Dictionary:
	if not data.has("missions"):
		data.missions = {}
	return data.missions.get(str(mission), {})

func _write_rec(mission: int, rec: Dictionary) -> void:
	if not data.has("missions"):
		data.missions = {}
	data.missions[str(mission)] = rec


# ---------- scene transitions ----------

func goto_menu() -> void:
	timing = false
	_change(MENU)

func goto_planet() -> void:
	start_mission(1)

func goto_cockpit() -> void:
	clear_current_mission()
	current_mission = 2
	_reset_stats()
	_change(COCKPIT)

func goto_runner() -> void:
	clear_current_mission()
	current_mission = 3
	_reset_stats()
	_change(RUNNER)

func finish() -> void:
	# runner win — mark the final mission cleared
	clear_current_mission()


func restart_phase() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _change(path: String) -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file.call_deferred(path)
