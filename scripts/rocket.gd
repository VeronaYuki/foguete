class_name Rocket
extends RigidBody3D

signal crashed(pos: Vector3)
signal touched_down(pad: Node3D, impact_speed: float)

const THRUST_MAX := 13.0
const TORQUE := 2.2
const FUEL_MAX := 100.0
const FUEL_BURN := 5.5

var fuel := FUEL_MAX
var thrust_level := 0.0
var control_enabled := false
var dead := false
var prev_velocity := Vector3.ZERO
var last_impact_speed := 0.0
var touching_pads: Array = []
var touching_terrain := 0
var landed_reported: Node3D = null

var exhaust: GPUParticles3D
var engine_light: OmniLight3D
var visuals: Node3D
var _flicker := 0.0


func _ready() -> void:
	mass = 1.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visuals()
	_build_collision()


func _physics_process(delta: float) -> void:
	if dead:
		return

	var want_thrust := control_enabled and Input.is_action_pressed("thrust") and fuel > 0.0
	thrust_level = move_toward(thrust_level, 1.0 if want_thrust else 0.0, delta * 6.0)
	if thrust_level > 0.01:
		apply_central_force(global_transform.basis.y * THRUST_MAX * thrust_level)
		if want_thrust:
			fuel = maxf(fuel - FUEL_BURN * thrust_level * delta, 0.0)

	var torque := Vector3.ZERO
	if control_enabled:
		var pitch := Input.get_axis("pitch_back", "pitch_forward")
		var roll := Input.get_axis("roll_left", "roll_right")
		torque.x = pitch * TORQUE
		torque.z = roll * TORQUE
		# SAS: damp spin, and right the rocket when the player isn't steering
		torque += -angular_velocity * 1.4
		if absf(pitch) < 0.01 and absf(roll) < 0.01:
			torque += global_transform.basis.y.cross(Vector3.UP) * 2.5
	apply_torque(torque)

	# engine FX
	exhaust.emitting = thrust_level > 0.05
	_flicker += delta * 40.0
	engine_light.light_energy = thrust_level * (5.0 + sin(_flicker) * 1.2)

	# tipped over while touching ground = crash
	var upright := global_transform.basis.y.dot(Vector3.UP)
	if (touching_terrain > 0 or not touching_pads.is_empty()) and upright < 0.35:
		die()
		return

	# settled on a pad?
	if not touching_pads.is_empty() and landed_reported == null \
			and linear_velocity.length() < 0.7 and upright > 0.92:
		landed_reported = touching_pads[0]
		touched_down.emit(landed_reported, last_impact_speed)

	# fell out of the world
	if global_position.y < -30.0:
		die()
		return

	prev_velocity = linear_velocity


func refuel() -> void:
	fuel = FUEL_MAX


func die() -> void:
	if dead:
		return
	dead = true
	thrust_level = 0.0
	exhaust.emitting = false
	engine_light.light_energy = 0.0
	visuals.visible = false
	freeze = true
	crashed.emit(global_position)


func _on_body_entered(body: Node) -> void:
	if dead:
		return
	var impact := prev_velocity.length()
	last_impact_speed = impact
	if body.is_in_group("pad"):
		if impact > 5.0:
			die()
		else:
			touching_pads.append(body)
	elif body.is_in_group("terrain"):
		if impact > 4.0:
			die()
		else:
			touching_terrain += 1


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("pad"):
		touching_pads.erase(body)
		if body == landed_reported:
			landed_reported = null
	elif body.is_in_group("terrain"):
		touching_terrain = maxi(touching_terrain - 1, 0)


func _build_visuals() -> void:
	visuals = Node3D.new()
	add_child(visuals)

	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.85, 0.86, 0.9)
	hull_mat.metallic = 0.6
	hull_mat.roughness = 0.35

	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = Color(0.9, 0.25, 0.15)
	accent_mat.metallic = 0.3
	accent_mat.roughness = 0.4

	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.15, 0.15, 0.17)
	dark_mat.metallic = 0.8
	dark_mat.roughness = 0.45

	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.5
	body_mesh.bottom_radius = 0.55
	body_mesh.height = 2.2
	_add_mesh(body_mesh, hull_mat, Vector3.ZERO)

	var nose := CylinderMesh.new()
	nose.top_radius = 0.02
	nose.bottom_radius = 0.5
	nose.height = 1.0
	_add_mesh(nose, accent_mat, Vector3(0, 1.6, 0))

	var band := CylinderMesh.new()
	band.top_radius = 0.56
	band.bottom_radius = 0.56
	band.height = 0.18
	_add_mesh(band, accent_mat, Vector3(0, 0.5, 0))

	var nozzle := CylinderMesh.new()
	nozzle.top_radius = 0.28
	nozzle.bottom_radius = 0.42
	nozzle.height = 0.5
	_add_mesh(nozzle, dark_mat, Vector3(0, -1.35, 0))

	for i in 4:
		var ang := TAU * i / 4.0 + TAU / 8.0
		var leg := CylinderMesh.new()
		leg.top_radius = 0.05
		leg.bottom_radius = 0.05
		leg.height = 1.3
		var m := _add_mesh(leg, dark_mat, Vector3(sin(ang) * 0.8, -1.05, cos(ang) * 0.8))
		m.rotation = Vector3(cos(ang) * 0.6, 0, -sin(ang) * 0.6)

	exhaust = GPUParticles3D.new()
	exhaust.position = Vector3(0, -1.7, 0)
	exhaust.amount = 120
	exhaust.lifetime = 0.45
	exhaust.local_coords = false
	exhaust.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 11.0
	pm.initial_velocity_min = 13.0
	pm.initial_velocity_max = 19.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.7, 1.0),
		Color(1.0, 0.55, 0.15, 0.9),
		Color(0.6, 0.15, 0.05, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	exhaust.process_material = pm
	var pmesh := SphereMesh.new()
	pmesh.radius = 0.13
	pmesh.height = 0.26
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.vertex_color_use_as_albedo = true
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.emission_enabled = true
	pmat.emission = Color(1.0, 0.5, 0.15)
	pmat.emission_energy_multiplier = 3.0
	pmesh.material = pmat
	exhaust.draw_pass_1 = pmesh
	add_child(exhaust)

	engine_light = OmniLight3D.new()
	engine_light.position = Vector3(0, -2.0, 0)
	engine_light.light_color = Color(1.0, 0.6, 0.25)
	engine_light.light_energy = 0.0
	engine_light.omni_range = 8.0
	add_child(engine_light)


func _add_mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	visuals.add_child(mi)
	return mi


func _build_collision() -> void:
	var body_shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.55
	cyl.height = 3.2
	body_shape.shape = cyl
	body_shape.position = Vector3(0, 0.3, 0)
	add_child(body_shape)

	var base_shape := CollisionShape3D.new()
	var base := CylinderShape3D.new()
	base.radius = 1.05
	base.height = 0.5
	base_shape.shape = base
	base_shape.position = Vector3(0, -1.55, 0)
	add_child(base_shape)
