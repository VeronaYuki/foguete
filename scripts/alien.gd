class_name Alien
extends CharacterBody3D

signal killed(pos: Vector3)

const CHASE_RANGE := 36.0
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

	# smooth spine: overlapping spheres rising from hips to shoulders
	var spine := [
		[Vector3(0, 0.95, -0.55), 0.30],
		[Vector3(0, 1.05, -0.20), 0.36],
		[Vector3(0, 1.18, 0.15), 0.40],
		[Vector3(0, 1.32, 0.45), 0.36],
		[Vector3(0, 1.45, 0.62), 0.24],
	]
	for s in spine:
		_sphere(chitin, s[1], s[0], Vector3(0.95, 0.8, 1.1))

	# ribbed carapace rings around the torso
	for i in 3:
		var rib := TorusMesh.new()
		rib.inner_radius = 0.3
		rib.outer_radius = 0.4
		var r := _mesh(rib, chitin, Vector3(0, 1.14 + i * 0.07, -0.05 + i * 0.22))
		r.rotation_degrees = Vector3(78, 0, 0)
		r.scale = Vector3(0.95, 1.0, 0.72)

	# long smooth cranium sweeping back over the shoulders
	var head := CapsuleMesh.new()
	head.radius = 0.24
	head.height = 2.0
	var head_mi := _mesh(head, chitin, Vector3(0, 1.62, 0.62))
	head_mi.rotation_degrees = Vector3(102, 0, 0)
	head_mi.scale = Vector3(0.68, 1.0, 0.78)

	# dorsal back-tubes
	for i in 3:
		var tube := CylinderMesh.new()
		tube.top_radius = 0.035
		tube.bottom_radius = 0.055
		tube.height = 0.5 - i * 0.06
		var tb := _mesh(tube, chitin, Vector3(0, 1.5 - i * 0.06, -0.05 - i * 0.24))
		tb.rotation_degrees = Vector3(-128, 0, 0)

	# curved side mandibles
	for side in [-1.0, 1.0]:
		var mand := CylinderMesh.new()
		mand.top_radius = 0.0
		mand.bottom_radius = 0.035
		mand.height = 0.34
		var mm := _mesh(mand, chitin, Vector3(0.15 * side, 1.4, 1.28))
		mm.rotation_degrees = Vector3(105, 0, -18.0 * side)

	# jaw with teeth
	var jaw := BoxMesh.new()
	jaw.size = Vector3(0.16, 0.08, 0.36)
	_mesh(jaw, chitin, Vector3(0, 1.45, 1.22))
	for i in 4:
		var tooth := CylinderMesh.new()
		tooth.top_radius = 0.0
		tooth.bottom_radius = 0.014
		tooth.height = 0.06
		var t := _mesh(tooth, teeth_mat, Vector3(-0.055 + 0.037 * i, 1.4, 1.34))
		t.rotation_degrees = Vector3(180, 0, 0)

	# faint eye slits low on the crest
	for side in [-1.0, 1.0]:
		var eye := BoxMesh.new()
		eye.size = Vector3(0.09, 0.02, 0.05)
		var e := _mesh(eye, eye_mat, Vector3(0.12 * side, 1.56, 1.24))
		e.rotation_degrees = Vector3(0, 0, 10.0 * side)

	# four two-segment legs
	var defs := [
		Vector3(0.3, 1.3, 0.4),
		Vector3(-0.3, 1.3, 0.4),
		Vector3(0.3, 1.0, -0.35),
		Vector3(-0.3, 1.0, -0.35),
	]
	for at in defs:
		var side := signf(at.x)
		var pivot := Node3D.new()
		pivot.position = at
		_vis.add_child(pivot)
		_leg_pivots.append(pivot)

		# digitigrade silhouette: upper arcs up-out, knee above the back
		var upper := CylinderMesh.new()
		upper.top_radius = 0.06
		upper.bottom_radius = 0.045
		upper.height = 0.8
		var u := MeshInstance3D.new()
		u.mesh = upper
		u.material_override = chitin
		u.rotation_degrees = Vector3(0, 0, -50.0 * side)
		u.position = Vector3(0.3 * side, 0.26, 0)
		pivot.add_child(u)
		# knee cap
		var cap_m := SphereMesh.new()
		cap_m.radius = 0.07
		cap_m.height = 0.14
		var kc := MeshInstance3D.new()
		kc.mesh = cap_m
		kc.material_override = chitin
		kc.position = Vector3(0.61 * side, 0.51, 0)
		pivot.add_child(kc)

		var knee := Node3D.new()
		knee.position = Vector3(0.61 * side, 0.51, 0)
		pivot.add_child(knee)
		var lower := CylinderMesh.new()
		lower.top_radius = 0.04
		lower.bottom_radius = 0.012
		lower.height = 1.75
		var l := MeshInstance3D.new()
		l.mesh = lower
		l.material_override = chitin
		l.rotation_degrees = Vector3(0, 0, -168.0 * side)
		l.position = Vector3(0.16 * side, -0.86, 0)
		knee.add_child(l)

	# segmented tail arcing up and back, ends in a blade
	_tail_pivot = Node3D.new()
	_tail_pivot.position = Vector3(0, 1.0, -0.7)
	_tail_pivot.rotation_degrees = Vector3(-42, 0, 0)
	_vis.add_child(_tail_pivot)
	var seg_defs := [
		[0.09, 0.8, Vector3(0, 0, -0.38), -8.0],
		[0.07, 0.7, Vector3(0, 0.1, -0.95), -22.0],
		[0.05, 0.6, Vector3(0, 0.28, -1.42), -38.0],
	]
	for sd in seg_defs:
		var seg := CapsuleMesh.new()
		seg.radius = sd[0]
		seg.height = sd[1]
		var sm := MeshInstance3D.new()
		sm.mesh = seg
		sm.material_override = chitin
		sm.rotation_degrees = Vector3(90.0 + sd[3], 0, 0)
		sm.position = sd[2]
		_tail_pivot.add_child(sm)
	var blade := CylinderMesh.new()
	blade.top_radius = 0.0
	blade.bottom_radius = 0.05
	blade.height = 0.45
	var bm := MeshInstance3D.new()
	bm.mesh = blade
	bm.material_override = chitin
	bm.rotation_degrees = Vector3(38, 0, 0)
	bm.position = Vector3(0, 0.55, -1.72)
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
