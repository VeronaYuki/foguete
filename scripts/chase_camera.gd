class_name ChaseCamera
extends Node3D

var target: Node3D
var mode := "orbit"  # "orbit" | "chase"
var trauma := 0.0
var camera: Camera3D
var _orbit_angle := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.far = 900.0
	add_child(camera)
	camera.current = true
	_rng.seed = 99


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if target == null:
		return
	trauma = maxf(trauma - delta * 1.2, 0.0)

	var desired: Vector3
	if mode == "orbit":
		_orbit_angle += delta * 0.25
		desired = target.global_position + Vector3(sin(_orbit_angle) * 11.0, 4.5, cos(_orbit_angle) * 11.0)
	else:
		desired = target.global_position + Vector3(0, 6.5, -13.0)

	if global_position.distance_to(desired) > 80.0:
		global_position = desired
	else:
		global_position = global_position.lerp(desired, 1.0 - exp(-4.0 * delta))

	look_at(target.global_position + Vector3(0, 1.2, 0), Vector3.UP)

	# trauma shake
	var sh := trauma * trauma
	camera.h_offset = _rng.randf_range(-1.0, 1.0) * 0.5 * sh
	camera.v_offset = _rng.randf_range(-1.0, 1.0) * 0.5 * sh
	camera.rotation.z = _rng.randf_range(-1.0, 1.0) * 0.06 * sh

	# subtle speed FOV kick
	var speed := 0.0
	if target is RigidBody3D:
		speed = (target as RigidBody3D).linear_velocity.length()
	camera.fov = lerpf(camera.fov, 68.0 + clampf(speed, 0.0, 25.0) * 0.4, 1.0 - exp(-3.0 * delta))
