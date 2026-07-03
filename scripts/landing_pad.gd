class_name LandingPad
extends StaticBody3D

enum PadState { INACTIVE, ACTIVE, DONE }

var index := -1
var pad_name := ""
var radius := 6.0
var state: PadState = PadState.INACTIVE

var _ring_mat: StandardMaterial3D
var _beacon: SpotLight3D
var _glow: OmniLight3D
var _pulse := 0.0

const COLOR_ACTIVE := Color(0.25, 1.0, 0.9)
const COLOR_DONE := Color(0.3, 1.0, 0.35)
const COLOR_INACTIVE := Color(0.6, 0.6, 0.65)


func setup(p_index: int, p_name: String, p_radius: float) -> void:
	index = p_index
	pad_name = p_name
	radius = p_radius


func _ready() -> void:
	add_to_group("pad")

	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.13, 0.14, 0.16)
	base_mat.metallic = 0.7
	base_mat.roughness = 0.5

	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = radius
	base_mesh.bottom_radius = radius + 0.6
	base_mesh.height = 0.7
	var base := MeshInstance3D.new()
	base.mesh = base_mesh
	base.material_override = base_mat
	base.position = Vector3(0, 0.35, 0)
	add_child(base)

	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.05, 0.05, 0.05)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = COLOR_INACTIVE
	_ring_mat.emission_energy_multiplier = 0.4

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius - 0.6
	ring_mesh.outer_radius = radius - 0.15
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = _ring_mat
	ring.position = Vector3(0, 0.72, 0)
	add_child(ring)

	_beacon = SpotLight3D.new()
	_beacon.position = Vector3(0, 0.8, 0)
	_beacon.rotation_degrees = Vector3(90, 0, 0)
	_beacon.spot_range = 100.0
	_beacon.spot_angle = 4.0
	_beacon.light_energy = 0.0
	_beacon.light_volumetric_fog_energy = 6.0
	_beacon.shadow_enabled = false
	add_child(_beacon)

	_glow = OmniLight3D.new()
	_glow.position = Vector3(0, 2.0, 0)
	_glow.omni_range = 14.0
	_glow.light_energy = 0.0
	add_child(_glow)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.7
	col.shape = shape
	col.position = Vector3(0, 0.35, 0)
	add_child(col)

	set_pad_state(state)


func set_pad_state(s: PadState) -> void:
	state = s
	match state:
		PadState.INACTIVE:
			_ring_mat.emission = COLOR_INACTIVE
			_ring_mat.emission_energy_multiplier = 0.4
			_beacon.light_energy = 0.0
			_glow.light_energy = 0.0
		PadState.ACTIVE:
			_ring_mat.emission = COLOR_ACTIVE
			_ring_mat.emission_energy_multiplier = 3.0
			_beacon.light_color = COLOR_ACTIVE
			_beacon.light_energy = 18.0
			_glow.light_color = COLOR_ACTIVE
			_glow.light_energy = 1.6
		PadState.DONE:
			_ring_mat.emission = COLOR_DONE
			_ring_mat.emission_energy_multiplier = 1.2
			_beacon.light_energy = 0.0
			_glow.light_color = COLOR_DONE
			_glow.light_energy = 0.8


func set_approach_warning(bad: bool) -> void:
	if state != PadState.ACTIVE:
		return
	var col := Color(1.0, 0.25, 0.15) if bad else COLOR_ACTIVE
	_ring_mat.emission = col
	_beacon.light_color = col
	_glow.light_color = col


func _process(delta: float) -> void:
	if state == PadState.ACTIVE:
		_pulse += delta * 3.0
		var k := 0.75 + 0.25 * sin(_pulse)
		_ring_mat.emission_energy_multiplier = 3.0 * k
		_beacon.light_energy = 18.0 * k
