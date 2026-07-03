extends Node
## Autoload: carries run stats and switches between the three phases.

const PLANET := "res://scenes/slime_planet.tscn"
const COCKPIT := "res://scenes/cockpit.tscn"
const RUNNER := "res://scenes/runner.tscn"

var kills := 0
var run_time := 0.0
var timing := false


func _process(delta: float) -> void:
	if timing:
		run_time += delta


func start_run() -> void:
	kills = 0
	run_time = 0.0
	timing = true


func goto_planet() -> void:
	_change(PLANET)


func goto_cockpit() -> void:
	_change(COCKPIT)


func goto_runner() -> void:
	_change(RUNNER)


func finish() -> void:
	timing = false


func restart_phase() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _change(path: String) -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file.call_deferred(path)
