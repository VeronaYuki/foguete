class_name FPSPlayer
extends CharacterBody3D

signal died
signal damaged(hp: float)

const SPEED := 6.0
const SPRINT := 10.5
const JUMP_VELOCITY := 5.8
const DASH_SPEED := 18.0
const DASH_COOLDOWN := 1.1
const GRAVITY := 14.0
const MOUSE_SENS := 0.0025
const FIRE_COOLDOWN := 0.16
const GUN_RANGE := 120.0

var hp := 100.0
var dead := false
var planet: Node3D

var cam: Camera3D
var flashlight: SpotLight3D
var gun: Node3D
var muzzle_light: OmniLight3D
var _cooldown := 0.0
var _recoil := 0.0
var _bob := 0.0
var _dash_cd := 0.0
var _dash_vel := Vector3.ZERO
var _sway := Vector2.ZERO


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	cam = Camera3D.new()
	cam.position = Vector3(0, 1.6, 0)
	cam.fov = 75.0
	cam.far = 500.0
	add_child(cam)
	cam.current = true

	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0, -0.15, 0)
	flashlight.spot_range = 55.0
	flashlight.spot_angle = 38.0
	flashlight.light_energy = 4.5
	flashlight.light_color = Color(0.95, 0.95, 0.85)
	flashlight.shadow_enabled = true
	cam.add_child(flashlight)

	_build_gun()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_gun() -> void:
	gun = Node3D.new()
	gun.position = Vector3(0.3, -0.28, -0.5)
	cam.add_child(gun)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.14, 0.15, 0.18)
	metal.metallic = 0.85
	metal.roughness = 0.3

	var polymer := StandardMaterial3D.new()
	polymer.albedo_color = Color(0.09, 0.095, 0.11)
	polymer.metallic = 0.1
	polymer.roughness = 0.75

	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.02, 0.02, 0.02)
	glow.emission_enabled = true
	glow.emission = Color(0.3, 1.0, 0.8)
	glow.emission_energy_multiplier = 2.4

	# receiver
	_gun_box(metal, Vector3(0.085, 0.13, 0.46), Vector3(0, 0, 0.02))
	# barrel shroud + inner barrel + muzzle brake
	_gun_box(polymer, Vector3(0.075, 0.085, 0.34), Vector3(0, 0.02, -0.36))
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.022
	barrel.bottom_radius = 0.022
	barrel.height = 0.5
	var b := _gun_mesh(barrel, metal, Vector3(0, 0.03, -0.42))
	b.rotation_degrees = Vector3(90, 0, 0)
	var brake := CylinderMesh.new()
	brake.top_radius = 0.036
	brake.bottom_radius = 0.036
	brake.height = 0.09
	var br := _gun_mesh(brake, metal, Vector3(0, 0.03, -0.66))
	br.rotation_degrees = Vector3(90, 0, 0)
	# glowing muzzle ring
	var ring := TorusMesh.new()
	ring.inner_radius = 0.03
	ring.outer_radius = 0.045
	var rg := _gun_mesh(ring, glow, Vector3(0, 0.03, -0.7))
	rg.rotation_degrees = Vector3(90, 0, 0)
	# stock, grip, magazine
	var stock := _gun_box(polymer, Vector3(0.07, 0.11, 0.22), Vector3(0, -0.03, 0.33))
	stock.rotation_degrees = Vector3(-6, 0, 0)
	var grip := _gun_box(polymer, Vector3(0.05, 0.15, 0.07), Vector3(0, -0.12, 0.15))
	grip.rotation_degrees = Vector3(18, 0, 0)
	var mag := _gun_box(metal, Vector3(0.055, 0.16, 0.09), Vector3(0, -0.14, -0.02))
	mag.rotation_degrees = Vector3(-10, 0, 0)
	# top rail + sight with glowing dot
	_gun_box(metal, Vector3(0.03, 0.02, 0.4), Vector3(0, 0.085, -0.08))
	_gun_box(metal, Vector3(0.04, 0.05, 0.05), Vector3(0, 0.115, 0.05))
	_gun_box(glow, Vector3(0.012, 0.012, 0.012), Vector3(0, 0.125, 0.03))
	# energy cell + side strips
	_gun_box(glow, Vector3(0.09, 0.03, 0.1), Vector3(0, -0.045, 0.12))
	for side in [-1.0, 1.0]:
		_gun_box(glow, Vector3(0.004, 0.015, 0.3), Vector3(0.045 * side, 0.02, -0.1))

	muzzle_light = OmniLight3D.new()
	muzzle_light.position = Vector3(0, 0.03, -0.75)
	muzzle_light.light_color = Color(0.4, 1.0, 0.85)
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 10.0
	gun.add_child(muzzle_light)


func _gun_box(mat: Material, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _gun_mesh(m, mat, pos)


func _gun_mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	gun.add_child(mi)
	return mi


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		rotate_y(-mm.relative.x * MOUSE_SENS)
		cam.rotation.x = clampf(cam.rotation.x - mm.relative.y * MOUSE_SENS, -1.45, 1.45)
		_sway += mm.relative * 0.0006


func _physics_process(delta: float) -> void:
	if dead:
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var in2 := Input.get_vector("move_left", "move_right", "move_fwd", "move_back")
	var dir := (global_transform.basis * Vector3(in2.x, 0, in2.y)).normalized()
	var sprinting := Input.is_action_pressed("sprint") and in2.length() > 0.1
	var speed := SPRINT if sprinting else SPEED

	# dash: quick burst in the movement (or facing) direction
	_dash_cd -= delta
	if Input.is_action_just_pressed("dash") and _dash_cd <= 0.0:
		_dash_cd = DASH_COOLDOWN
		var ddir := dir if dir.length() > 0.1 else -global_transform.basis.z * Vector3(1, 0, 1)
		_dash_vel = ddir.normalized() * DASH_SPEED
	_dash_vel = _dash_vel.move_toward(Vector3.ZERO, DASH_SPEED * 4.0 * delta)

	velocity.x = dir.x * speed + _dash_vel.x
	velocity.z = dir.z * speed + _dash_vel.z
	move_and_slide()

	# head bob + speed FOV kick
	if is_on_floor() and dir.length() > 0.1:
		_bob += delta * (13.0 if sprinting else 8.0)
		cam.position.y = 1.6 + sin(_bob) * 0.045
	else:
		cam.position.y = lerpf(cam.position.y, 1.6, 8.0 * delta)
	var target_fov := 75.0
	if sprinting:
		target_fov = 82.0
	if _dash_vel.length() > 4.0:
		target_fov = 88.0
	cam.fov = lerpf(cam.fov, target_fov, 1.0 - exp(-9.0 * delta))

	# gun recoil + look sway
	_recoil = maxf(_recoil - delta * 6.0, 0.0)
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * delta))
	gun.position.x = 0.3 - clampf(_sway.x, -0.05, 0.05)
	gun.position.y = -0.28 + clampf(_sway.y, -0.04, 0.04) + sin(_bob) * 0.006
	gun.position.z = -0.5 + _recoil * 0.08
	gun.rotation.x = _recoil * 0.12
	muzzle_light.light_energy = maxf(muzzle_light.light_energy - delta * 30.0, 0.0)

	_cooldown -= delta
	if Input.is_action_pressed("fire") and _cooldown <= 0.0:
		_fire()


func _fire() -> void:
	_cooldown = FIRE_COOLDOWN
	_recoil = 1.0
	muzzle_light.light_energy = 5.0

	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * GUN_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var end := to
	var hit_alien := false
	if hit:
		end = hit.position
		var collider: Object = hit.collider
		if collider is Node and (collider as Node).is_in_group("alien"):
			hit_alien = true
			(collider as Node).call("take_hit", 1, (-cam.global_transform.basis.z))

	if planet:
		var muzzle := muzzle_light.global_position
		planet.call("spawn_tracer", muzzle, end)
		if hit:
			planet.call("spawn_sparks", end, hit_alien)
		planet.call("on_player_fired")


func take_damage(dmg: float) -> void:
	if dead:
		return
	hp = maxf(hp - dmg, 0.0)
	damaged.emit(hp)
	if hp <= 0.0:
		dead = true
		died.emit()
