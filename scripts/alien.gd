class_name Alien
extends CharacterBody3D

signal killed(pos: Vector3)

const CHASE_RANGE := 42.0
const ATTACK_RANGE := 2.7
const SPEED_WANDER := 2.2
const SPEED_CHASE := 5.6
const GRAVITY := 14.0

var hp := 3
var player: FPSPlayer
var planet: Node3D

var _state := "wander"
var _home := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _attack_cd := 0.0
var _gait := 0.0
var _zig := 0.0
var _flash := 0.0
var _mats: Array[StandardMaterial3D] = []
var _leg_pivots: Array[Node3D] = []
var _tail_pivot: Node3D
var _vis: Node3D
var _screech_cd := 0.0


func _ready() -> void:
	add_to_group("alien")
	_home = global_position
	_wander_target = global_position

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = 1.7
	col.shape = cap
	col.position = Vector3(0, 0.95, 0)
	add_child(col)

	_build_body()


func _build_body() -> void:
	_vis = Node3D.new()
	_vis.scale = Vector3.ONE * 1.3
	add_child(_vis)

	var chitin := StandardMaterial3D.new()
	chitin.albedo_color = Color(0.1, 0.11, 0.14)
	chitin.metallic = 0.5
	chitin.roughness = 0.3
	chitin.emission_enabled = true
	chitin.emission = Color(0.9, 0.95, 1.0)
	chitin.emission_energy_multiplier = 0.0
	_mats.append(chitin)

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color.BLACK
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.12, 0.08)
	eye_mat.emission_energy_multiplier = 4.0

	var teeth_mat := StandardMaterial3D.new()
	teeth_mat.albedo_color = Color(0.85, 0.82, 0.7)
	teeth_mat.roughness = 0.4

	# hunched spine: hips low, chest high
	_sphere(chitin, 0.40, Vector3(0, 1.02, -0.38), Vector3(1.0, 0.85, 1.15))
	_sphere(chitin, 0.42, Vector3(0, 1.32, 0.12), Vector3(1.0, 0.9, 1.2))
	_sphere(chitin, 0.34, Vector3(0, 1.5, 0.45), Vector3(1.0, 0.85, 1.0))

	# long smooth cranium sweeping back over the shoulders
	var head := CapsuleMesh.new()
	head.radius = 0.26
	head.height = 1.9
	var head_mi := _mesh(head, chitin, Vector3(0, 1.72, 0.3))
	head_mi.rotation_degrees = Vector3(100, 0, 0)
	head_mi.scale = Vector3(0.72, 1.0, 0.88)

	# curved side mandibles
	for side in [-1.0, 1.0]:
		var mand := CylinderMesh.new()
		mand.top_radius = 0.0
		mand.bottom_radius = 0.035
		mand.height = 0.34
		var mm := _mesh(mand, chitin, Vector3(0.16 * side, 1.44, 1.12))
		mm.rotation_degrees = Vector3(105, 0, -18.0 * side)

	# jaw with teeth
	var jaw := BoxMesh.new()
	jaw.size = Vector3(0.17, 0.09, 0.34)
	_mesh(jaw, chitin, Vector3(0, 1.5, 1.02))
	for i in 4:
		var tooth := CylinderMesh.new()
		tooth.top_radius = 0.0
		tooth.bottom_radius = 0.016
		tooth.height = 0.07
		var t := _mesh(tooth, teeth_mat, Vector3(-0.06 + 0.04 * i, 1.44, 1.14))
		t.rotation_degrees = Vector3(180, 0, 0)

	# eye slits
	for side in [-1.0, 1.0]:
		var eye := BoxMesh.new()
		eye.size = Vector3(0.1, 0.025, 0.06)
		var e := _mesh(eye, eye_mat, Vector3(0.13 * side, 1.64, 1.05))
		e.rotation_degrees = Vector3(0, 0, 12.0 * side)

	# dorsal spikes
	for i in 4:
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = 0.05
		spike.height = 0.34 - i * 0.04
		var s := _mesh(spike, chitin, Vector3(0, 1.52 - i * 0.09, 0.2 - i * 0.24))
		s.rotation_degrees = Vector3(-38, 0, 0)

	# four two-segment legs
	var defs := [
		[Vector3(0.34, 1.42, 0.32), 0.0],
		[Vector3(-0.34, 1.42, 0.32), 1.0],
		[Vector3(0.36, 1.05, -0.5), 2.0],
		[Vector3(-0.36, 1.05, -0.5), 3.0],
	]
	for d in defs:
		var at: Vector3 = d[0]
		var side := signf(at.x)
		var pivot := Node3D.new()
		pivot.position = at
		_vis.add_child(pivot)
		_leg_pivots.append(pivot)

		# spider silhouette: upper segment arcs UP and out, knee above the back
		var upper := CylinderMesh.new()
		upper.top_radius = 0.075
		upper.bottom_radius = 0.05
		upper.height = 0.85
		var u := MeshInstance3D.new()
		u.mesh = upper
		u.material_override = chitin
		u.rotation_degrees = Vector3(0, 0, -55.0 * side)
		u.position = Vector3(0.33 * side, 0.24, 0)
		pivot.add_child(u)

		var knee := Node3D.new()
		knee.position = Vector3(0.68 * side, 0.48, 0)
		pivot.add_child(knee)
		var lower := CylinderMesh.new()
		lower.top_radius = 0.05
		lower.bottom_radius = 0.015
		lower.height = 1.7
		var l := MeshInstance3D.new()
		l.mesh = lower
		l.material_override = chitin
		l.rotation_degrees = Vector3(0, 0, -166.0 * side)
		l.position = Vector3(0.2 * side, -0.82, 0)
		knee.add_child(l)

	# tail: arcs up and back, ends in a blade
	_tail_pivot = Node3D.new()
	_tail_pivot.position = Vector3(0, 1.05, -0.62)
	_tail_pivot.rotation_degrees = Vector3(-45, 0, 0)
	_vis.add_child(_tail_pivot)
	var t1 := CapsuleMesh.new()
	t1.radius = 0.09
	t1.height = 0.95
	var t1m := MeshInstance3D.new()
	t1m.mesh = t1
	t1m.material_override = chitin
	t1m.rotation_degrees = Vector3(90, 0, 0)
	t1m.position = Vector3(0, 0, -0.45)
	_tail_pivot.add_child(t1m)
	var t2m := MeshInstance3D.new()
	var t2 := CapsuleMesh.new()
	t2.radius = 0.055
	t2.height = 0.85
	t2m.mesh = t2
	t2m.material_override = chitin
	t2m.rotation_degrees = Vector3(72, 0, 0)
	t2m.position = Vector3(0, 0.18, -1.15)
	_tail_pivot.add_child(t2m)
	var blade := CylinderMesh.new()
	blade.top_radius = 0.0
	blade.bottom_radius = 0.05
	blade.height = 0.4
	var bm := MeshInstance3D.new()
	bm.mesh = blade
	bm.material_override = chitin
	bm.rotation_degrees = Vector3(55, 0, 0)
	bm.position = Vector3(0, 0.42, -1.5)
	_tail_pivot.add_child(bm)

	# eerie underglow so the silhouette reads in the dark
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 0.6, 0)
	glow.omni_range = 4.5
	glow.light_energy = 0.4
	glow.light_color = Color(0.9, 0.25, 0.15)
	_vis.add_child(glow)


func _sphere(mat: Material, r: float, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	var mi := _mesh(m, mat, pos)
	mi.scale = scl
	return mi


func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_vis.add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	if player == null or player.dead:
		velocity.x = 0
		velocity.z = 0
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		return

	_attack_cd -= delta
	_screech_cd -= delta
	_flash = maxf(_flash - delta * 4.0, 0.0)
	_mats[0].emission_energy_multiplier = _flash * 4.0

	var to_player := player.global_position - global_position
	var dist := to_player.length()

	var was := _state
	if dist < ATTACK_RANGE:
		_state = "attack"
	elif dist < CHASE_RANGE:
		_state = "chase"
	else:
		_state = "wander"
	if _state == "chase" and was == "wander" and _screech_cd <= 0.0:
		_screech_cd = 4.0
		if planet:
			planet.call("on_alien_screech")

	var speed := SPEED_WANDER
	var target := _wander_target
	match _state:
		"wander":
			_wander_timer -= delta
			if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 2.0:
				_wander_timer = randf_range(3.0, 6.0)
				_wander_target = _home + Vector3(randf_range(-25, 25), 0, randf_range(-25, 25))
			target = _wander_target
		"chase":
			speed = SPEED_CHASE
			_zig += delta * 5.0
			var perp := to_player.cross(Vector3.UP).normalized()
			target = player.global_position + perp * sin(_zig) * 2.5
		"attack":
			speed = SPEED_CHASE
			target = player.global_position
			if _attack_cd <= 0.0:
				_attack_cd = 1.3
				velocity += to_player.normalized() * 7.0 + Vector3.UP * 2.5
				if dist < 2.0:
					player.take_damage(18.0)

	var dir := target - global_position
	dir.y = 0.0
	if dir.length() > 0.5:
		dir = dir.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		var yaw := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, 6.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()

	# gait + tail sway + breathing bob
	_gait += delta * (10.0 if _state != "wander" else 5.0)
	for i in _leg_pivots.size():
		_leg_pivots[i].rotation.x = sin(_gait + i * PI * 0.5) * 0.4
	if _tail_pivot:
		_tail_pivot.rotation.y = sin(_gait * 0.6) * 0.35
	if _vis:
		_vis.position.y = sin(_gait * 0.8) * 0.03


func take_hit(dmg: int, dir: Vector3) -> void:
	hp -= dmg
	_flash = 1.0
	velocity += dir * 5.0
	if hp <= 0:
		killed.emit(global_position + Vector3(0, 1, 0))
		queue_free()
