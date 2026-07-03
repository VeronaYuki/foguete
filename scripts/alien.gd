class_name Alien
extends CharacterBody3D

signal killed(pos: Vector3)
signal health_changed(cur: int, mx: int)

const CHASE_RANGE := 36.0
const ATTACK_RANGE := 2.7
const SPEED_WANDER := 2.2
const SPEED_CHASE := 5.6
const GRAVITY := 14.0

var hp := 3
var max_hp := 3
var is_boss := false
var _summon_cd := 6.0
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
var _gait_step := PI * 0.5
var _model_holder: Node3D

const LUCAS_TEX := "res://assets/lucas.png"
const TARGET_HEIGHT := 2.0
# downloaded 3D hunter model
const ENEMY_GLBS := [
	"res://bald-cartoon-casual-male-character/source/Unnamed project.glb",
]


func _ready() -> void:
	add_to_group("alien")
	if is_boss:
		add_to_group("boss")
		hp = 26
		max_hp = 26
	_home = global_position
	_wander_target = global_position

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.9 if is_boss else 0.55
	cap.height = 1.7
	col.shape = cap
	col.position = Vector3(0, 0.95, 0)
	add_child(col)

	var glbs := ENEMY_GLBS.filter(func (p: String) -> bool: return ResourceLoader.exists(p))
	if not glbs.is_empty():
		cap.height = 3.4 if is_boss else 1.9
		col.position = Vector3(0, (1.7 if is_boss else 1.0), 0)
		_build_glb_body(glbs[randi() % glbs.size()])
	elif ResourceLoader.exists(LUCAS_TEX):
		cap.height = 1.9
		col.position = Vector3(0, 1.0, 0)
		_build_lucas_body()
	else:
		_build_body()


func _build_glb_body(path: String) -> void:
	_vis = Node3D.new()
	add_child(_vis)

	_model_holder = Node3D.new()
	_vis.add_child(_model_holder)

	var packed := load(path) as PackedScene
	var model := packed.instantiate()
	_model_holder.add_child(model)

	# auto-fit once transforms are live in the tree
	_fit_model.call_deferred(model)

	# eerie red underglow so the hunter reads as a threat in the dark
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 0.8, 0)
	glow.omni_range = 9.0 if is_boss else 4.5
	glow.light_energy = 1.6 if is_boss else 0.4
	glow.light_color = Color(1.0, 0.15, 0.08) if is_boss else Color(0.9, 0.2, 0.12)
	_vis.add_child(glow)

	# play a built-in animation if the model ships one
	var anim := _find_anim_player(model)
	if anim and not anim.get_animation_list().is_empty():
		var names := anim.get_animation_list()
		var pick := names[0]
		for n in names:
			var ln := String(n).to_lower()
			if ln.contains("walk") or ln.contains("idle") or ln.contains("run"):
				pick = n
				break
		var a := anim.get_animation(pick)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR
		anim.play(pick)


func _fit_model(model: Node3D) -> void:
	if not is_instance_valid(model) or not is_inside_tree():
		return
	var aabb := _local_aabb(_model_holder, model)
	if aabb.size.y <= 0.001:
		return
	# center on x/z, drop feet to y=0, then scale to human height
	model.position -= Vector3(
		aabb.position.x + aabb.size.x * 0.5,
		aabb.position.y,
		aabb.position.z + aabb.size.z * 0.5)
	var target: float = 3.9 if is_boss else TARGET_HEIGHT
	_model_holder.scale = Vector3.ONE * (target / aabb.size.y)
	# models export facing +Z, which matches the alien's forward — no turn needed


func _local_aabb(space: Node3D, root: Node3D) -> AABB:
	var inv := space.global_transform.affine_inverse()
	var merged := AABB()
	var started := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			var a: AABB = (inv * vi.global_transform) * vi.get_aabb()
			if started:
				merged = merged.merge(a)
			else:
				merged = a
				started = true
		for c in n.get_children():
			stack.append(c)
	return merged


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_anim_player(c)
		if found:
			return found
	return null


func _build_lucas_body() -> void:
	# Humanoid astronaut standing upright, facing +Z (toward the player).
	_vis = Node3D.new()
	add_child(_vis)
	_gait_step = PI

	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.82, 0.83, 0.86)
	suit.roughness = 0.65
	suit.metallic = 0.0
	suit.emission_enabled = true
	suit.emission = Color(1.0, 0.4, 0.3)
	suit.emission_energy_multiplier = 0.0
	_mats.append(suit)

	var soft := StandardMaterial3D.new()  # fabric joints
	soft.albedo_color = Color(0.7, 0.71, 0.74)
	soft.roughness = 0.85

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.13, 0.13, 0.16)
	dark.roughness = 0.6
	dark.metallic = 0.4

	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.95, 0.5, 0.12)
	orange.roughness = 0.5

	# ---- torso: rounded chest tapering to the waist ----
	var chest := SphereMesh.new()
	chest.radius = 0.26
	chest.height = 0.52
	var ch := _mesh(chest, suit, Vector3(0, 1.28, 0))
	ch.scale = Vector3(1.0, 0.95, 0.85)
	var waist := CylinderMesh.new()
	waist.top_radius = 0.2
	waist.bottom_radius = 0.22
	waist.height = 0.3
	_mesh(waist, soft, Vector3(0, 1.0, 0))
	# hip block
	var hips := SphereMesh.new()
	hips.radius = 0.23
	hips.height = 0.4
	var hp := _mesh(hips, suit, Vector3(0, 0.86, 0))
	hp.scale = Vector3(1.0, 0.7, 0.85)

	# chest control panel + mission stripe
	var panel := BoxMesh.new()
	panel.size = Vector3(0.18, 0.13, 0.04)
	_mesh(panel, dark, Vector3(0, 1.3, 0.22))
	for k in 3:
		var btn := SphereMesh.new()
		btn.radius = 0.02
		btn.height = 0.04
		var bmat := orange if k == 0 else soft
		_mesh(btn, bmat, Vector3(-0.05 + k * 0.05, 1.3, 0.245))
	# shoulder flag patch (sits flush on the upper arm cap area)
	var patch := BoxMesh.new()
	patch.size = Vector3(0.08, 0.1, 0.02)
	_mesh(patch, orange, Vector3(0.15, 1.36, 0.16))

	# ---- life-support backpack ----
	var pack := BoxMesh.new()
	pack.size = Vector3(0.36, 0.5, 0.2)
	var pk := _mesh(pack, suit, Vector3(0, 1.28, -0.26))
	pk.scale = Vector3(1, 1, 1)
	for side in [-1.0, 1.0]:
		var tank := CylinderMesh.new()
		tank.top_radius = 0.06
		tank.bottom_radius = 0.06
		tank.height = 0.42
		_mesh(tank, dark, Vector3(0.1 * side, 1.28, -0.34))

	# ---- shoulders ----
	for side in [-1.0, 1.0]:
		var sh := SphereMesh.new()
		sh.radius = 0.11
		sh.height = 0.22
		_mesh(sh, suit, Vector3(0.28 * side, 1.42, 0))

	# ---- arms (shoulder pivots) & legs (hip pivots) ----
	# order: legL, legR, armR, armL so opposite arm/leg swing together
	var limbs := [
		{ "at": Vector3(0.12, 0.82, 0), "arm": false },
		{ "at": Vector3(-0.12, 0.82, 0), "arm": false },
		{ "at": Vector3(-0.28, 1.42, 0), "arm": true },
		{ "at": Vector3(0.28, 1.42, 0), "arm": true },
	]
	for d in limbs:
		var pivot := Node3D.new()
		pivot.position = d.at
		_vis.add_child(pivot)
		_leg_pivots.append(pivot)
		if d.arm:
			_build_arm(pivot, suit, soft, dark, signf(d.at.x))
		else:
			_build_leg(pivot, suit, soft, dark)

	# ---- neck ring + head ----
	var ring := TorusMesh.new()
	ring.inner_radius = 0.1
	ring.outer_radius = 0.15
	_mesh(ring, orange, Vector3(0, 1.55, 0))

	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.4
	var head_mat := ShaderMaterial.new()
	head_mat.shader = load("res://shaders/lucas_head.gdshader")
	head_mat.set_shader_parameter("face_tex", load(LUCAS_TEX))
	head_mat.set_shader_parameter("skin_color", Color(0.74, 0.57, 0.46))
	head_mat.set_shader_parameter("face_emission", 0.06)
	var hd := MeshInstance3D.new()
	hd.mesh = head
	hd.material_override = head_mat
	hd.position = Vector3(0, 1.75, 0)
	hd.scale = Vector3(0.95, 1.05, 0.98)
	_vis.add_child(hd)

	# ---- clear helmet dome + rim ----
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.75, 0.9, 0.14)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.03
	glass.metallic = 0.4
	var helmet := SphereMesh.new()
	helmet.radius = 0.28
	helmet.height = 0.56
	var hm := MeshInstance3D.new()
	hm.mesh = helmet
	hm.material_override = glass
	hm.position = Vector3(0, 1.76, 0.0)
	_vis.add_child(hm)

	var rim := TorusMesh.new()
	rim.inner_radius = 0.26
	rim.outer_radius = 0.3
	_mesh(rim, orange, Vector3(0, 1.55, 0))

	# gentle fill so the face isn't pure black from the side; the player's
	# flashlight does the real lighting when they look at him
	var face_light := OmniLight3D.new()
	face_light.position = Vector3(0, 1.78, 0.5)
	face_light.omni_range = 1.6
	face_light.light_energy = 0.55
	face_light.light_color = Color(0.85, 0.9, 1.0)
	_vis.add_child(face_light)

	# faint red underglow — he is still the monster
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 0.7, 0)
	glow.omni_range = 4.0
	glow.light_energy = 0.35
	glow.light_color = Color(0.9, 0.25, 0.15)
	_vis.add_child(glow)


func _build_arm(pivot: Node3D, suit: Material, soft: Material, dark: Material, side: float) -> void:
	# arm hangs down and slightly out, elbow bent forward
	var upper := CapsuleMesh.new()
	upper.radius = 0.06
	upper.height = 0.4
	var u := MeshInstance3D.new()
	u.mesh = upper
	u.material_override = suit
	u.position = Vector3(0.04 * side, -0.18, 0)
	u.rotation_degrees = Vector3(0, 0, 8.0 * side)
	pivot.add_child(u)
	var elbow := _child_sphere(pivot, soft, 0.055, Vector3(0.07 * side, -0.37, 0))
	var lower := CapsuleMesh.new()
	lower.radius = 0.05
	lower.height = 0.36
	var l := MeshInstance3D.new()
	l.mesh = lower
	l.material_override = suit
	l.position = Vector3(0.09 * side, -0.54, 0.05)
	l.rotation_degrees = Vector3(18, 0, 6.0 * side)
	pivot.add_child(l)
	# glove
	var glove := SphereMesh.new()
	glove.radius = 0.06
	glove.height = 0.12
	_child_mesh(pivot, glove, dark, Vector3(0.1 * side, -0.72, 0.12))


func _build_leg(pivot: Node3D, suit: Material, soft: Material, dark: Material) -> void:
	var thigh := CapsuleMesh.new()
	thigh.radius = 0.085
	thigh.height = 0.44
	_child_mesh(pivot, thigh, suit, Vector3(0, -0.22, 0))
	_child_sphere(pivot, soft, 0.075, Vector3(0, -0.44, 0))
	var shin := CapsuleMesh.new()
	shin.radius = 0.07
	shin.height = 0.42
	_child_mesh(pivot, shin, suit, Vector3(0, -0.66, 0))
	# boot
	var boot := BoxMesh.new()
	boot.size = Vector3(0.13, 0.1, 0.24)
	_child_mesh(pivot, boot, dark, Vector3(0, -0.9, 0.05))


func _child_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _child_sphere(parent: Node3D, mat: Material, r: float, pos: Vector3) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return _child_mesh(parent, m, mat, pos)


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
	if not _mats.is_empty():
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
			speed = SPEED_CHASE + (1.6 if is_boss else 0.0)
			_zig += delta * 5.0
			var perp := to_player.cross(Vector3.UP).normalized()
			target = player.global_position + perp * sin(_zig) * 2.5
		"attack":
			speed = SPEED_CHASE + (1.6 if is_boss else 0.0)
			target = player.global_position
			var atk_range := 3.2 if is_boss else 2.0
			if _attack_cd <= 0.0:
				_attack_cd = 1.1 if is_boss else 1.3
				velocity += to_player.normalized() * (10.0 if is_boss else 7.0) + Vector3.UP * 2.5
				if dist < atk_range:
					player.take_damage(28.0 if is_boss else 18.0)

	# the boss periodically calls in reinforcements
	if is_boss and _state != "wander":
		_summon_cd -= delta
		if _summon_cd <= 0.0:
			_summon_cd = 7.0
			if planet:
				planet.call("boss_summon", global_position)

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
		_leg_pivots[i].rotation.x = sin(_gait + i * _gait_step) * 0.4
	if _tail_pivot:
		_tail_pivot.rotation.y = sin(_gait * 0.6) * 0.35
	if _vis:
		_vis.position.y = sin(_gait * 0.8) * 0.03

	# static GLB hunters can't animate — give them a lumbering shamble
	if _model_holder:
		var pace := 1.6 if _state != "wander" else 1.0
		_model_holder.position.y = absf(sin(_gait * 0.9)) * 0.09 * pace
		_model_holder.rotation.z = sin(_gait * 0.9) * 0.07 * pace
		var lean := 0.22 if _state == "attack" else (0.13 if _state == "chase" else 0.04)
		_model_holder.rotation.x = lerp_angle(_model_holder.rotation.x, lean, delta * 3.0)


func take_hit(dmg: int, dir: Vector3) -> void:
	hp -= dmg
	_flash = 1.0
	velocity += dir * (2.0 if is_boss else 5.0)
	health_changed.emit(maxi(hp, 0), max_hp)
	if hp <= 0:
		killed.emit(global_position + Vector3(0, 1, 0))
		queue_free()
