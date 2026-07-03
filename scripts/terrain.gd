class_name Terrain
extends StaticBody3D

const X_MIN := -130.0
const X_MAX := 170.0
const Z_MIN := -90.0
const Z_MAX := 310.0
const STEP := 2.0

var _noise := FastNoiseLite.new()
var _roll := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _spots: Array = []   # { pos: Vector2, height: float, radius: float }
var _path: Array = []    # Vector2 waypoints the flight route follows

# look parameters — override before calling generate()
var col_low := Color(0.30, 0.21, 0.27)
var col_mid := Color(0.46, 0.26, 0.20)
var col_high := Color(0.72, 0.62, 0.58)
var col_steep := Color(0.15, 0.12, 0.14)
var ground_roughness := 0.95
var amp_min := 5.0
var amp_max := 30.0
var with_crystals := true
var slime_shader := false  # planet phase: glowing slime veins painted into the ground


func generate(flatten_spots: Array, path_points: Array) -> void:
	_spots = flatten_spots
	_path = path_points
	add_to_group("terrain")

	_noise.seed = 7
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_noise.fractal_octaves = 4
	_noise.frequency = 0.009

	_roll.seed = 21
	_roll.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_roll.frequency = 0.004

	_detail.seed = 3
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail.frequency = 0.08

	_build_mesh()
	if with_crystals:
		_scatter_crystals()


func get_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var d := _dist_to_path(p)
	# low relief along the flight corridor, mountains away from it
	var wall := clampf((d - 12.0) / 60.0, 0.0, 1.0)
	wall = wall * wall * (3.0 - 2.0 * wall)
	var amp := lerpf(amp_min, amp_max, wall)
	var ridged := (_noise.get_noise_2d(x, z) + 1.0) * 0.5
	var h := ridged * amp + _roll.get_noise_2d(x, z) * 5.0 + _detail.get_noise_2d(x, z) * 0.8

	for s in _spots:
		var ds: float = p.distance_to(s.pos)
		var t := 1.0 - clampf((ds - s.radius) / 20.0, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		h = lerpf(h, s.height, t)
	return h


func get_normal(x: float, z: float) -> Vector3:
	var e := 1.0
	return Vector3(
		get_height(x - e, z) - get_height(x + e, z),
		2.0 * e,
		get_height(x, z - e) - get_height(x, z + e)
	).normalized()


func _dist_to_path(p: Vector2) -> float:
	var best := 1e9
	for i in _path.size() - 1:
		var a: Vector2 = _path[i]
		var b: Vector2 = _path[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func _build_mesh() -> void:
	var nx := int((X_MAX - X_MIN) / STEP) + 1
	var nz := int((Z_MAX - Z_MIN) / STEP) + 1

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(nx * nz)
	normals.resize(nx * nz)
	colors.resize(nx * nz)

	var sand := col_low
	var rust := col_mid
	var pale := col_high
	var rock := col_steep

	for iz in nz:
		for ix in nx:
			var x := X_MIN + ix * STEP
			var z := Z_MIN + iz * STEP
			var h := get_height(x, z)
			var n := get_normal(x, z)
			var idx := iz * nx + ix
			verts[idx] = Vector3(x, h, z)
			normals[idx] = n

			var ch := clampf(h / 38.0, 0.0, 1.0)
			var col := sand.lerp(rust, clampf(ch * 2.0, 0.0, 1.0))
			col = col.lerp(pale, clampf((ch - 0.55) * 2.2, 0.0, 1.0))
			var steep := clampf((0.78 - n.y) * 3.5, 0.0, 1.0)
			col = col.lerp(rock, steep)
			var v := _detail.get_noise_2d(x * 3.0, z * 3.0) * 0.05
			var a := 1.0
			if slime_shader:
				# alpha channel = slime mask: flat and low ground glows
				var flat_k := clampf((n.y - 0.86) / 0.08, 0.0, 1.0)
				var low_k := 1.0 - clampf((h - 3.0) / 7.0, 0.0, 1.0)
				a = flat_k * low_k
			colors[idx] = Color(col.r + v, col.g + v, col.b + v, a)

	for iz in nz - 1:
		for ix in nx - 1:
			var i := iz * nx + ix
			indices.append_array(PackedInt32Array([
				i, i + 1, i + nx + 1,
				i, i + nx + 1, i + nx,
			]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat: Material
	if slime_shader:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/terrain_slime.gdshader")
		var nn := FastNoiseLite.new()
		nn.seed = 99
		nn.frequency = 0.02
		var img := nn.get_seamless_image(512, 512)
		sm.set_shader_parameter("slime_noise", ImageTexture.create_from_image(img))
		sm.set_shader_parameter("wet_roughness", ground_roughness)
		mat = sm
	else:
		var std := StandardMaterial3D.new()
		std.vertex_color_use_as_albedo = true
		std.roughness = ground_roughness
		std.metallic = 0.0
		mat = std

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)

	var col_shape := CollisionShape3D.new()
	col_shape.shape = mesh.create_trimesh_shape()
	add_child(col_shape)


func _scatter_crystals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12

	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.9, 2.4, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.12, 0.18)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 1.0)
	mat.emission_energy_multiplier = 2.4
	mat.roughness = 0.2
	mesh.material = mat

	var transforms: Array[Transform3D] = []
	for i in 260:
		var x := rng.randf_range(X_MIN + 10.0, X_MAX - 10.0)
		var z := rng.randf_range(Z_MIN + 10.0, Z_MAX - 10.0)
		var p := Vector2(x, z)
		var near_spot := false
		for s in _spots:
			if p.distance_to(s.pos) < s.radius + 8.0:
				near_spot = true
				break
		if near_spot:
			continue
		if get_normal(x, z).y < 0.55:
			continue
		var h := get_height(x, z)
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		b = b.rotated(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		b = b.scaled(Vector3.ONE * rng.randf_range(0.5, 2.4))
		transforms.append(Transform3D(b, Vector3(x, h + 0.6, z)))
		if transforms.size() >= 90:
			break

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
