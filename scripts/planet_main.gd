extends Node3D
## Phase 1 — dark slime planet. Find the rocket, survive the aliens.

const START_SPOT := { "pos": Vector2(0, -20), "height": 4.0, "radius": 8.0 }
const ROCKET_SPOT := { "pos": Vector2(0, 175), "height": 6.0, "radius": 10.0 }
const ALIEN_COUNT := 10

var terrain: Terrain
var player: FPSPlayer
var sfx: Sfx
var rocket_pos: Vector3

var hud: CanvasLayer
var health_bar: ProgressBar
var kills_label: Label
var objective: Label
var prompt: Label
var vignette: ColorRect
var card_box: VBoxContainer
var card_title: Label
var card_sub: Label

var _near_rocket := false
var _game_over := false
var _spores: GPUParticles3D


func _ready() -> void:
	Flow.start_run()
	_build_environment()
	_build_terrain()
	_decorate()
	_build_rocket()
	_build_player()
	_spawn_aliens()
	_build_hud()
	sfx = Sfx.new()
	add_child(sfx)
	_start_music()

	_show_card("VH-9  ·  THE SWAMP",
		"Find your rocket.\nWASD move · SHIFT sprint · MOUSE aim · LMB fire · E interact")
	get_tree().create_timer(5.0).timeout.connect(func () -> void:
		if not _game_over:
			_fade_card()
	)

	if OS.get_environment("FOGUETE_PHOTO") == "1":
		_photo_mode.call_deferred()


func _start_music() -> void:
	var stream: AudioStreamMP3 = load("res://audio/Moonbound.mp3")
	stream.loop = true
	var music := AudioStreamPlayer.new()
	music.stream = stream
	music.volume_db = -8.0
	add_child(music)
	music.play()


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.012, 0.02, 0.035)
	sky_mat.sky_horizon_color = Color(0.05, 0.13, 0.11)
	sky_mat.sky_curve = 0.2
	sky_mat.ground_bottom_color = Color(0.01, 0.02, 0.02)
	sky_mat.ground_horizon_color = Color(0.05, 0.13, 0.11)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.42, 0.4)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.08
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.03
	env.volumetric_fog_albedo = Color(0.45, 0.6, 0.5)
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 170.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# cold blue "moon" key light
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-38, 25, 0)
	moon.light_color = Color(0.55, 0.7, 1.0)
	moon.light_energy = 0.5
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 120.0
	add_child(moon)

	# faint warm rim from the opposite horizon for modeling
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-12, -160, 0)
	rim.light_color = Color(0.5, 0.9, 0.6)
	rim.light_energy = 0.18
	add_child(rim)


func _build_terrain() -> void:
	terrain = Terrain.new()
	terrain.col_low = Color(0.09, 0.15, 0.11)
	terrain.col_mid = Color(0.13, 0.2, 0.13)
	terrain.col_high = Color(0.28, 0.32, 0.24)
	terrain.col_steep = Color(0.055, 0.065, 0.085)
	terrain.ground_roughness = 0.3
	terrain.amp_min = 3.0
	terrain.amp_max = 22.0
	terrain.with_crystals = false
	terrain.slime_shader = true
	add_child(terrain)
	var path := [Vector2(0, -20), Vector2(-15, 60), Vector2(10, 120), Vector2(0, 175)]
	terrain.generate([START_SPOT, ROCKET_SPOT], path)


func _decorate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77

	# dark rock formations — break up the terrain and give the player cover
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.07, 0.09, 0.1)
	rock_mat.roughness = 0.85
	rock_mesh.material = rock_mat
	var rock_scale := func (r: RandomNumberGenerator) -> Vector3:
		var s: float = r.randf_range(1.5, 5.0)
		return Vector3(s * r.randf_range(0.8, 1.3), s * 0.7, s * r.randf_range(0.8, 1.3))
	_scatter(rng, rock_mesh, 70, 0.6, rock_scale, -0.4)

	# drifting spores around the player
	var spores := GPUParticles3D.new()
	spores.amount = 260
	spores.lifetime = 9.0
	spores.local_coords = false
	spores.preprocess = 5.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(45, 8, 45)
	pm.gravity = Vector3(0, 0.15, 0)
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.spread = 180.0
	pm.scale_min = 0.03
	pm.scale_max = 0.1
	pm.color = Color(0.5, 1.0, 0.6, 0.7)
	spores.process_material = pm
	var smesh := SphereMesh.new()
	smesh.radius = 0.5
	smesh.height = 1.0
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.vertex_color_use_as_albedo = true
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.emission_enabled = true
	smat.emission = Color(0.5, 1.0, 0.6)
	smat.emission_energy_multiplier = 1.5
	smesh.material = smat
	spores.draw_pass_1 = smesh
	spores.position = Vector3(0, 5, 40)
	add_child(spores)
	_spores = spores


func _scatter(rng: RandomNumberGenerator, mesh: Mesh, count: int, min_ny: float,
		scale_fn: Callable, y_off: float) -> void:
	var transforms: Array[Transform3D] = []
	for i in count * 4:
		if transforms.size() >= count:
			break
		var x := rng.randf_range(Terrain.X_MIN + 10, Terrain.X_MAX - 10)
		var z := rng.randf_range(Terrain.Z_MIN + 10, Terrain.Z_MAX - 10)
		if terrain.get_normal(x, z).y < min_ny:
			continue
		var s: Vector3 = scale_fn.call(rng)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(s)
		transforms.append(Transform3D(b, Vector3(x, terrain.get_height(x, z) + y_off, z)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _build_rocket() -> void:
	var h: float = ROCKET_SPOT.height
	rocket_pos = Vector3(ROCKET_SPOT.pos.x, h, ROCKET_SPOT.pos.y)

	var root := StaticBody3D.new()
	add_child(root)
	root.global_position = rocket_pos + Vector3(0, 3.5, 0)
	root.scale = Vector3.ONE * 2.0

	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.8
	cyl.height = 3.4
	col.shape = cyl
	root.add_child(col)

	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.85, 0.86, 0.9)
	hull.metallic = 0.6
	hull.roughness = 0.35
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.9, 0.25, 0.15)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.15, 0.17)
	dark.metallic = 0.8

	var warm_glow := StandardMaterial3D.new()
	warm_glow.albedo_color = Color(0.05, 0.04, 0.02)
	warm_glow.emission_enabled = true
	warm_glow.emission = Color(1.0, 0.75, 0.4)
	warm_glow.emission_energy_multiplier = 2.5

	# main hull with a tapered upper section
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.5
	body_mesh.bottom_radius = 0.58
	body_mesh.height = 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = body_mesh
	mi.material_override = hull
	mi.position = Vector3(0, -0.2, 0)
	root.add_child(mi)

	var taper := CylinderMesh.new()
	taper.top_radius = 0.34
	taper.bottom_radius = 0.5
	taper.height = 0.7
	var tmi := MeshInstance3D.new()
	tmi.mesh = taper
	tmi.material_override = hull
	tmi.position = Vector3(0, 1.15, 0)
	root.add_child(tmi)

	var nose := CylinderMesh.new()
	nose.top_radius = 0.02
	nose.bottom_radius = 0.34
	nose.height = 0.9
	var nmi := MeshInstance3D.new()
	nmi.mesh = nose
	nmi.material_override = accent
	nmi.position = Vector3(0, 1.95, 0)
	root.add_child(nmi)

	# accent band + glowing portholes + hatch
	var band := CylinderMesh.new()
	band.top_radius = 0.6
	band.bottom_radius = 0.6
	band.height = 0.14
	var bmi := MeshInstance3D.new()
	bmi.mesh = band
	bmi.material_override = accent
	bmi.position = Vector3(0, -1.0, 0)
	root.add_child(bmi)

	for i in 3:
		var port := SphereMesh.new()
		port.radius = 0.07
		port.height = 0.14
		var pmi := MeshInstance3D.new()
		pmi.mesh = port
		pmi.material_override = warm_glow
		pmi.position = Vector3(0, 0.9 - i * 0.5, -0.52)
		pmi.scale = Vector3(1, 1, 0.4)
		root.add_child(pmi)

	var hatch := BoxMesh.new()
	hatch.size = Vector3(0.34, 0.5, 0.08)
	var hmi := MeshInstance3D.new()
	hmi.mesh = hatch
	hmi.material_override = dark
	hmi.position = Vector3(0, -0.5, -0.56)
	root.add_child(hmi)

	# engine bell
	var bell := CylinderMesh.new()
	bell.top_radius = 0.3
	bell.bottom_radius = 0.48
	bell.height = 0.5
	var bell_mi := MeshInstance3D.new()
	bell_mi.mesh = bell
	bell_mi.material_override = dark
	bell_mi.position = Vector3(0, -1.42, 0)
	root.add_child(bell_mi)

	# four fins + sturdy legs with feet
	for i in 4:
		var ang := TAU * i / 4.0 + TAU / 8.0
		var out := Vector3(sin(ang), 0, cos(ang))

		var fin := BoxMesh.new()
		fin.size = Vector3(0.06, 1.1, 0.5)
		var fmi := MeshInstance3D.new()
		fmi.mesh = fin
		fmi.material_override = accent
		fmi.position = out * 0.72 + Vector3(0, -0.85, 0)
		fmi.rotation.y = ang
		fmi.rotation.z = 0.0
		root.add_child(fmi)

		var leg := CylinderMesh.new()
		leg.top_radius = 0.07
		leg.bottom_radius = 0.07
		leg.height = 1.4
		var lmi := MeshInstance3D.new()
		lmi.mesh = leg
		lmi.material_override = dark
		lmi.position = out * 0.85 + Vector3(0, -1.15, 0)
		lmi.rotation = Vector3(cos(ang) * 0.55, 0, -sin(ang) * 0.55)
		root.add_child(lmi)

		var foot := CylinderMesh.new()
		foot.top_radius = 0.16
		foot.bottom_radius = 0.2
		foot.height = 0.08
		var ft := MeshInstance3D.new()
		ft.mesh = foot
		ft.material_override = dark
		ft.position = out * 1.22 + Vector3(0, -1.78, 0)
		root.add_child(ft)

	# beacon column visible across the swamp
	var beacon := SpotLight3D.new()
	beacon.position = Vector3(0, 2.4, 0)
	beacon.rotation_degrees = Vector3(90, 0, 0)
	beacon.spot_range = 120.0
	beacon.spot_angle = 8.0
	beacon.light_energy = 30.0
	beacon.light_color = Color(0.4, 0.95, 1.0)
	beacon.light_volumetric_fog_energy = 16.0
	root.add_child(beacon)

	# fake light shaft so the pillar reads at any distance
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.9
	shaft_mesh.bottom_radius = 0.35
	shaft_mesh.height = 50.0
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shaft_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shaft_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shaft_mat.albedo_color = Color(0.3, 0.9, 1.0, 0.10)
	shaft_mat.emission_enabled = true
	shaft_mat.emission = Color(0.3, 0.9, 1.0)
	shaft_mat.emission_energy_multiplier = 0.5
	shaft_mesh.material = shaft_mat
	var shaft := MeshInstance3D.new()
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0, 26.0, 0)
	root.add_child(shaft)

	# blinking red nav light on the nose
	var nav := OmniLight3D.new()
	nav.position = Vector3(0, 2.3, 0)
	nav.omni_range = 6.0
	nav.light_energy = 2.0
	nav.light_color = Color(1.0, 0.2, 0.15)
	root.add_child(nav)
	var blink := create_tween().set_loops()
	blink.tween_property(nav, "light_energy", 0.2, 0.5)
	blink.tween_interval(0.3)
	blink.tween_property(nav, "light_energy", 2.0, 0.15)
	blink.tween_interval(0.6)

	# warm launch-pad glow at the base
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 0.2, 0)
	glow.omni_range = 20.0
	glow.light_energy = 3.0
	glow.light_color = Color(1.0, 0.75, 0.45)
	root.add_child(glow)


func _build_player() -> void:
	player = FPSPlayer.new()
	add_child(player)
	var h := terrain.get_height(START_SPOT.pos.x, START_SPOT.pos.y)
	player.global_position = Vector3(START_SPOT.pos.x, h + 1.5, START_SPOT.pos.y)
	player.rotation.y = PI  # face the rocket, not the map edge
	player.planet = self
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)


func _spawn_aliens() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in ALIEN_COUNT:
		var z := rng.randf_range(20.0, 155.0)
		var x := rng.randf_range(-24.0, 24.0)
		var a := Alien.new()
		add_child(a)
		a.global_position = Vector3(x, terrain.get_height(x, z) + 1.0, z)
		a.player = player
		a.planet = self
		a.killed.connect(_on_alien_killed)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.8, 0.05, 0.05, 0.0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	root.add_child(Crosshair.new())

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(24, -110)
	root.add_child(box)
	box.add_child(_mk_label("HEALTH", 15, Color(0.7, 0.9, 1.0)))
	health_bar = ProgressBar.new()
	health_bar.min_value = 0
	health_bar.max_value = 100
	health_bar.value = 100
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(240, 14)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 1.0, 0.5)
	fill.set_corner_radius_all(4)
	health_bar.add_theme_stylebox_override("background", bg)
	health_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(health_bar)
	kills_label = _mk_label("KILLS  0", 15, Color(0.9, 0.9, 0.9))
	box.add_child(kills_label)

	objective = _mk_label("", 22, Color(0.85, 0.95, 1.0))
	objective.set_anchors_preset(Control.PRESET_CENTER_TOP)
	objective.position = Vector2(0, 28)
	objective.grow_horizontal = Control.GROW_DIRECTION_BOTH
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(objective)

	prompt = _mk_label("[E]  ENTER ROCKET", 30, Color(0.4, 1.0, 0.9))
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position = Vector2(0, -160)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.visible = false
	root.add_child(prompt)

	card_box = VBoxContainer.new()
	card_box.set_anchors_preset(Control.PRESET_CENTER)
	card_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(card_box)
	card_title = _mk_label("", 62, Color.WHITE)
	card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_box.add_child(card_title)
	card_sub = _mk_label("", 21, Color(0.75, 0.85, 0.8))
	card_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_box.add_child(card_sub)


func _mk_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _show_card(title: String, sub: String) -> void:
	card_box.modulate.a = 1.0
	card_title.text = title
	card_sub.text = sub
	card_box.visible = true


func _fade_card() -> void:
	var tw := create_tween()
	tw.tween_property(card_box, "modulate:a", 0.0, 1.0)


func _photo_mode() -> void:
	# flies a camera through the level and saves stills so the look can be reviewed
	card_box.visible = false
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	cam.current = true

	await get_tree().process_frame
	var aliens := get_tree().get_nodes_in_group("alien")
	var a0: Vector3 = aliens[0].global_position if not aliens.is_empty() else Vector3(0, 5, 60)

	var shots := [
		{ "pos": Vector3(0, terrain.get_height(0, -28) + 4.0, -28), "look": Vector3(0, 10, 60) },
		{ "pos": Vector3(-14, terrain.get_height(-14, 55) + 5.0, 55), "look": rocket_pos + Vector3(0, 10, 0) },
		{ "pos": Vector3(6, terrain.get_height(6, 90) + 1.8, 90), "look": Vector3(6, terrain.get_height(6, 110) + 1.0, 110) },
		{ "pos": a0 + Vector3(2.6, 1.9, 2.6), "look": a0 + Vector3(0, 1.2, 0) },
		{ "pos": rocket_pos + Vector3(10, 7, -18), "look": rocket_pos + Vector3(0, 3, 0) },
		{ "pos": player.global_position + Vector3(-1.2, 1.7, 1.8), "look": player.global_position + Vector3(-0.3, 1.3, 0.5) },
	]
	for i in shots.size():
		cam.global_position = shots[i].pos
		cam.look_at(shots[i].look)
		await get_tree().create_timer(0.9).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("/Users/verona/Documents/foguete/.shots/p%d.png" % i)
	get_tree().quit()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	if Input.is_action_just_pressed("restart"):
		Flow.restart_phase()
		return
	if _game_over or player == null:
		return

	var d := player.global_position.distance_to(rocket_pos)
	objective.text = "FIND THE ROCKET  —  %0.0f m" % d
	_near_rocket = d < 7.0
	prompt.visible = _near_rocket
	if _near_rocket and Input.is_action_just_pressed("interact"):
		_game_over = true
		Flow.goto_cockpit()

	# low health heartbeat vignette
	if player.hp < 30.0 and not player.dead:
		vignette.color.a = maxf(vignette.color.a, 0.12 + 0.08 * sin(Time.get_ticks_msec() / 180.0))


func _on_player_damaged(hp: float) -> void:
	health_bar.value = hp
	var fill: StyleBoxFlat = health_bar.get_theme_stylebox("fill")
	fill.bg_color = Color(0.35, 1.0, 0.5) if hp > 35 else Color(1.0, 0.3, 0.2)
	sfx.play_hurt()
	vignette.color.a = 0.45
	var tw := create_tween()
	tw.tween_property(vignette, "color:a", 0.0, 0.5)


func _on_player_died() -> void:
	_game_over = true
	sfx.set_thrust(0.0)
	_show_card("YOU DIED", "the swamp keeps your bones\n\nrestarting…")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().create_timer(2.4).timeout.connect(Flow.restart_phase)


func _on_alien_killed(pos: Vector3) -> void:
	Flow.kills += 1
	kills_label.text = "KILLS  %d" % Flow.kills
	sfx.play_splat()
	_burst(pos, Color(0.4, 1.0, 0.3), 80, 9.0)


func on_alien_screech() -> void:
	sfx.play_screech()


func on_player_fired() -> void:
	sfx.play_laser()


func spawn_tracer(from: Vector3, to: Vector3) -> void:
	var dir := to - from
	var len := dir.length()
	if len < 0.5:
		return
	dir /= len
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.02
	mesh.height = len
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.5, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 1.0, 0.85)
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var x := dir.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(dir)
	mi.basis = Basis(x, dir, z)
	add_child(mi)
	mi.global_position = (from + to) * 0.5
	var tw := create_tween()
	tw.tween_property(mi, "transparency", 1.0, 0.09)
	tw.tween_callback(mi.queue_free)


func spawn_sparks(pos: Vector3, alien_hit: bool) -> void:
	var color := Color(0.5, 1.0, 0.3) if alien_hit else Color(0.4, 0.9, 1.0)
	_burst(pos, color, 20, 5.0)


func _burst(pos: Vector3, color: Color, amount: int, speed: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -8, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	pm.color = color
	p.process_material = pm
	var pmesh := SphereMesh.new()
	pmesh.radius = 0.06
	pmesh.height = 0.12
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.vertex_color_use_as_albedo = true
	pmat.emission_enabled = true
	pmat.emission = color
	pmat.emission_energy_multiplier = 2.0
	pmesh.material = pmat
	p.draw_pass_1 = pmesh
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)
