extends Node3D
## Phase 3 — the ascent. Dodge debris, shoot back, reach the Moon.

const RUN_TIME := 75.0
const BOUNDS_X := 16.0
const BOUNDS_Y_MIN := -8.0
const BOUNDS_Y_MAX := 11.0
const MOVE_SPEED := 14.0
const FIRE_CD := 0.18
const BOOST_TIME := 2.0
const BOOST_MULT := 1.9
const BOOST_COOLDOWN := 1.2
const FACE_GAIN := 1.6
const FACE_DEADZONE := 0.12

var sfx: Sfx
var face: FaceControl
var voice: VoiceControl
var rocket: Node3D
var rocket_vel := Vector2.ZERO
var cam: Camera3D
var moon: Node3D
var eng_light: OmniLight3D
var exhaust_pm: ParticleProcessMaterial
var _streaks: GPUParticles3D
var _cine := false
var _cine_look := Vector3(1, 3, 11)
var _sun: DirectionalLight3D
var _env: Environment

var boost_t := 0.0
var boost_cd := 0.0
var speed_mult := 1.0

var shields := 3
var kills := 0
var progress := 0.0
var state := "intro"  # intro | flying | dead | won
var _invuln := 0.0
var _fire_cd := 0.0
var _spawn_t := 1.0
var _trauma := 0.0
var rng := RandomNumberGenerator.new()

var obstacles: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var enemy_shots: Array[Dictionary] = []

var hud: CanvasLayer
var shield_label: Label
var kills_label: Label
var progress_bar: ProgressBar
var card_box: VBoxContainer
var card_title: Label
var card_sub: Label
var vignette: ColorRect
var face_label: Label
var boost_label: Label
var preview_box: Control
var mic_label: Label


func _ready() -> void:
	rng.seed = 1234
	sfx = Sfx.new()
	add_child(sfx)
	sfx.set_thrust(0.55)
	_start_music()
	face = FaceControl.new()
	add_child(face)
	face.smile_started.connect(_boost)
	voice = VoiceControl.new()
	add_child(voice)
	voice.piu_detected.connect(_voice_fire)
	_build_environment()
	_build_rocket()
	_build_hud()
	_show_card("ASCENT", "WASD or head-lean steer · LMB or \"PIU!\" fires\nSMILE to boost · survive to the Moon")
	get_tree().create_timer(2.5).timeout.connect(func () -> void:
		if state == "intro":
			state = "flying"
			_fade_card()
	)
	if OS.get_environment("FOGUETE_PHOTO") == "1":
		_photo.call_deferred()
	# atalho de dev: pula direto para a cinemática de pouso, sem jogar o jogo todo
	if OS.get_environment("FOGUETE_ENDING") == "1":
		_win.call_deferred()


func _start_music() -> void:
	var stream: AudioStreamMP3 = load("res://audio/Moonreach.mp3")
	stream.loop = true
	var music := AudioStreamPlayer.new()
	music.stream = stream
	music.volume_db = -8.0
	add_child(music)
	music.play()


func _photo() -> void:
	state = "flying"
	card_box.visible = false
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/Users/verona/Documents/foguete/.shots/runner1.png")
	await get_tree().create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/Users/verona/Documents/foguete/.shots/runner2.png")
	get_tree().quit()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.005, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.28, 0.38)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_bloom = 0.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, 140, 0)
	sun.light_color = Color(0.9, 0.9, 1.0)
	sun.light_energy = 1.1
	add_child(sun)
	_sun = sun

	# static starfield shell
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 0.5
	star_mesh.height = 1.0
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = Color(0.9, 0.92, 1.0)
	star_mesh.material = star_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = star_mesh
	mm.instance_count = 700
	for i in 700:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-0.4, 1)).normalized()
		var d := rng.randf_range(250.0, 480.0)
		var s := rng.randf_range(0.3, 1.1)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), dir * d))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)

	# speed streaks flying past
	var streaks := GPUParticles3D.new()
	streaks.amount = 90
	streaks.lifetime = 3.0
	streaks.local_coords = false
	streaks.preprocess = 3.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(40, 25, 10)
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 0.0
	pm.initial_velocity_min = 70.0
	pm.initial_velocity_max = 110.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.2
	pm.scale_max = 0.5
	pm.color = Color(0.6, 0.7, 1.0, 0.35)
	streaks.process_material = pm
	var smesh := SphereMesh.new()
	smesh.radius = 0.1
	smesh.height = 0.2
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.vertex_color_use_as_albedo = true
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smesh.material = smat
	streaks.draw_pass_1 = smesh
	streaks.position = Vector3(0, 0, 120)
	add_child(streaks)
	_streaks = streaks

	# the Moon, far ahead — usa o modelo real moon.glb se existir
	moon = Node3D.new()
	if ResourceLoader.exists("res://assets/moon.glb"):
		var mscene: PackedScene = load("res://assets/moon.glb")
		var minst := mscene.instantiate()
		minst.scale = Vector3.ONE * 0.42   # raio ~100 -> ~42 (igual ao procedural antigo)
		moon.add_child(minst)
	else:
		var moon_mesh := SphereMesh.new()
		moon_mesh.radius = 42.0
		moon_mesh.height = 84.0
		var moon_mat := StandardMaterial3D.new()
		moon_mat.albedo_color = Color(0.75, 0.75, 0.78)
		moon_mat.roughness = 0.9
		moon_mat.emission_enabled = true
		moon_mat.emission = Color(0.4, 0.4, 0.45)
		moon_mat.emission_energy_multiplier = 0.25
		moon_mesh.material = moon_mat
		var mi := MeshInstance3D.new()
		mi.mesh = moon_mesh
		moon.add_child(mi)
	moon.position = Vector3(0, 6, 560)
	add_child(moon)


func _build_rocket() -> void:
	rocket = Node3D.new()
	add_child(rocket)

	var vis := Node3D.new()
	vis.rotation_degrees = Vector3(90, 0, 0)  # nose points +Z (forward)
	vis.scale = Vector3.ONE * 1.8
	rocket.add_child(vis)

	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.85, 0.86, 0.9)
	hull.metallic = 0.6
	hull.roughness = 0.35
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.9, 0.25, 0.15)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.15, 0.17)
	dark.metallic = 0.8

	var body := CylinderMesh.new()
	body.top_radius = 0.5
	body.bottom_radius = 0.58
	body.height = 2.0
	_vis_mesh(vis, body, hull, Vector3.ZERO)
	var taper := CylinderMesh.new()
	taper.top_radius = 0.34
	taper.bottom_radius = 0.5
	taper.height = 0.7
	_vis_mesh(vis, taper, hull, Vector3(0, 1.35, 0))
	var nose := CylinderMesh.new()
	nose.top_radius = 0.02
	nose.bottom_radius = 0.34
	nose.height = 0.9
	_vis_mesh(vis, nose, accent, Vector3(0, 2.15, 0))
	var bell := CylinderMesh.new()
	bell.top_radius = 0.3
	bell.bottom_radius = 0.48
	bell.height = 0.5
	_vis_mesh(vis, bell, dark, Vector3(0, -1.25, 0))
	for i in 4:
		var ang := TAU * i / 4.0 + TAU / 8.0
		var fin := BoxMesh.new()
		fin.size = Vector3(0.06, 1.0, 0.5)
		var f := _vis_mesh(vis, fin, accent, Vector3(sin(ang) * 0.68, -0.7, cos(ang) * 0.68))
		f.rotation.y = ang

	# engine exhaust
	var exhaust := GPUParticles3D.new()
	exhaust.position = Vector3(0, 0, -2.6)
	exhaust.amount = 90
	exhaust.lifetime = 0.22
	exhaust.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 6.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 36.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.2
	pm.scale_max = 0.45
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.8, 0.95, 1.0, 1.0),
		Color(0.3, 0.6, 1.0, 0.8),
		Color(0.1, 0.2, 0.6, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	exhaust.process_material = pm
	var pmesh := SphereMesh.new()
	pmesh.radius = 0.16
	pmesh.height = 0.32
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.vertex_color_use_as_albedo = true
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.emission_enabled = true
	pmat.emission = Color(0.4, 0.7, 1.0)
	pmat.emission_energy_multiplier = 3.0
	pmesh.material = pmat
	exhaust.draw_pass_1 = pmesh
	rocket.add_child(exhaust)

	exhaust_pm = pm

	eng_light = OmniLight3D.new()
	eng_light.position = Vector3(0, 0, -2.0)
	eng_light.light_color = Color(0.4, 0.7, 1.0)
	eng_light.light_energy = 3.0
	eng_light.omni_range = 10.0
	rocket.add_child(eng_light)

	cam = Camera3D.new()
	cam.fov = 75.0
	cam.far = 1200.0
	add_child(cam)
	cam.position = Vector3(0, 6.5, -14)
	cam.current = true


func _vis_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.9, 0.1, 0.05, 0.0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	shield_label = _mk_label("SHIELDS  ◆ ◆ ◆", 20, Color(0.5, 0.85, 1.0))
	shield_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	shield_label.position = Vector2(24, -50)
	root.add_child(shield_label)

	kills_label = _mk_label("KILLS  0", 20, Color(0.9, 0.9, 0.9))
	kills_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	kills_label.position = Vector2(-160, -50)
	root.add_child(kills_label)

	face_label = _mk_label("FACE  —", 15, Color(0.55, 0.6, 0.7))
	face_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	face_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	face_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	face_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face_label.position.y -= 46
	root.add_child(face_label)

	mic_label = _mk_label("MIC", 15, Color(0.55, 0.6, 0.7))
	mic_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	mic_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mic_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	mic_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mic_label.position.y -= 70
	root.add_child(mic_label)

	boost_label = _mk_label("BOOST!", 46, Color(1.0, 0.75, 0.2))
	boost_label.set_anchors_preset(Control.PRESET_CENTER)
	boost_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boost_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boost_label.position.y += 130
	boost_label.visible = false
	root.add_child(boost_label)

	# webcam preview, bottom-right
	preview_box = Control.new()
	preview_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	preview_box.position = Vector2(-248, -248)
	preview_box.size = Vector2(228, 172)
	preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_box.visible = false
	root.add_child(preview_box)
	var frame_bg := ColorRect.new()
	frame_bg.color = Color(0.4, 0.5, 0.7, 0.6)
	frame_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_box.add_child(frame_bg)
	var preview_rect := TextureRect.new()
	preview_rect.texture = face.preview_texture
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_rect.position = Vector2(2, 2)
	preview_rect.size = Vector2(224, 168)
	preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_box.add_child(preview_rect)

	var pv := VBoxContainer.new()
	pv.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pv.position = Vector2(-220, 20)
	root.add_child(pv)
	var pl := _mk_label("DISTANCE TO MOON", 14, Color(0.7, 0.8, 0.9))
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(pl)
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0
	progress_bar.max_value = 1
	progress_bar.value = 0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(440, 12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.12, 0.2, 0.7)
	bg.border_color = Color(0.4, 0.5, 0.7, 0.6)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.8, 0.85, 1.0)
	fill.set_corner_radius_all(4)
	progress_bar.add_theme_stylebox_override("background", bg)
	progress_bar.add_theme_stylebox_override("fill", fill)
	pv.add_child(progress_bar)

	card_box = VBoxContainer.new()
	card_box.set_anchors_preset(Control.PRESET_CENTER)
	card_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(card_box)
	card_title = _mk_label("", 62, Color.WHITE)
	card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_box.add_child(card_title)
	card_sub = _mk_label("", 21, Color(0.75, 0.85, 0.95))
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
	card_box.visible = true
	card_title.text = title
	card_sub.text = sub


func _fade_card() -> void:
	var tw := create_tween()
	tw.tween_property(card_box, "modulate:a", 0.0, 0.8)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	if Input.is_action_just_pressed("restart"):
		if state == "won":
			Flow.goto_planet()
		else:
			Flow.restart_phase()
		return
	if _cine and is_instance_valid(cam):
		cam.look_at(_cine_look)
	if state == "dead" or state == "won":
		return
	if state == "intro":
		return

	# boost (smile-triggered) scales how fast the world streams past
	boost_t = maxf(boost_t - delta, 0.0)
	boost_cd = maxf(boost_cd - delta, 0.0)
	speed_mult = lerpf(speed_mult, BOOST_MULT if boost_t > 0.0 else 1.0, 1.0 - exp(-6.0 * delta))
	_boost_fx()

	# progress + difficulty
	progress = minf(progress + delta * speed_mult / RUN_TIME, 1.0)
	progress_bar.value = progress
	moon.position.z = lerpf(560.0, 80.0, progress)
	if progress >= 1.0:
		_win()
		return

	_move_rocket(delta)
	_shoot(delta)
	_spawn(delta * speed_mult)
	_step_world(delta * speed_mult)
	_camera(delta)
	_face_hud()
	_invuln = maxf(_invuln - delta, 0.0)


func _boost() -> void:
	if state != "flying" or boost_t > 0.0 or boost_cd > 0.0:
		return
	boost_t = BOOST_TIME
	boost_cd = BOOST_TIME + BOOST_COOLDOWN
	sfx.play_boost()
	boost_label.visible = true
	boost_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(boost_label, "modulate:a", 0.0, BOOST_TIME)
	tw.tween_callback(func () -> void: boost_label.visible = false)


func _boost_fx() -> void:
	var bf := (speed_mult - 1.0) / (BOOST_MULT - 1.0)
	eng_light.light_energy = 3.0 + 6.0 * bf
	exhaust_pm.initial_velocity_min = 26.0 * (1.0 + bf)
	exhaust_pm.initial_velocity_max = 36.0 * (1.0 + bf)
	sfx.set_thrust(0.55 + 0.4 * bf)


func _face_hud() -> void:
	preview_box.visible = face.preview_active
	if voice.mic_alive:
		var blocks := clampi(int(voice.level * 10.0), 0, 10)
		mic_label.text = "MIC  %s%s  say PIU! to fire" % ["▮".repeat(blocks), "▯".repeat(10 - blocks)]
		mic_label.add_theme_color_override("font_color",
			Color(1.0, 0.8, 0.3) if blocks >= 3 else Color(0.5, 0.95, 0.7))
	else:
		mic_label.text = "MIC  ✗  no microphone"
		mic_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	if not face.active:
		face_label.text = "FACE  —  no face in view · WASD"
		face_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	elif boost_t > 0.0:
		face_label.text = "FACE  ✓  BOOSTING"
		face_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	elif boost_cd > 0.0:
		face_label.text = "FACE  ✓  boost recharging…"
		face_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	else:
		face_label.text = "FACE  ✓  lean to steer · SMILE to boost"
		face_label.add_theme_color_override("font_color", Color(0.5, 0.95, 0.7))


func _face_axis(v: float) -> float:
	if absf(v) < FACE_DEADZONE:
		return 0.0
	return (v - signf(v) * FACE_DEADZONE) / (1.0 - FACE_DEADZONE)


func _move_rocket(delta: float) -> void:
	var in2 := Input.get_vector("move_left", "move_right", "move_fwd", "move_back")
	var steer := Vector2(-in2.x, -in2.y)
	if face.active:
		# camera looks down +Z, so screen-right is world -X
		steer += Vector2(-_face_axis(face.head.x), _face_axis(face.head.y)) * FACE_GAIN
	steer = steer.limit_length(1.0)
	rocket_vel = rocket_vel.lerp(steer * MOVE_SPEED, 1.0 - exp(-8.0 * delta))
	rocket.position.x = clampf(rocket.position.x + rocket_vel.x * delta, -BOUNDS_X, BOUNDS_X)
	rocket.position.y = clampf(rocket.position.y + rocket_vel.y * delta, BOUNDS_Y_MIN, BOUNDS_Y_MAX)
	# banking
	rocket.rotation.z = lerpf(rocket.rotation.z, -rocket_vel.x * 0.03, 8.0 * delta)
	rocket.rotation.x = lerpf(rocket.rotation.x, rocket_vel.y * 0.02, 8.0 * delta)


func _shoot(delta: float) -> void:
	_fire_cd -= delta
	if Input.is_action_pressed("fire") and _fire_cd <= 0.0:
		_fire_shot()


func _voice_fire() -> void:
	if state == "flying" and _fire_cd <= 0.0:
		_fire_shot()


func _fire_shot() -> void:
	_fire_cd = FIRE_CD
	sfx.play_laser()
	var s := _orb(Color(0.3, 1.0, 0.85), 0.3)
	add_child(s)
	s.global_position = rocket.position + Vector3(0, 0, 2.2)
	shots.append({ "node": s, "vel": Vector3(0, 0, 130) })


func _spawn(delta: float) -> void:
	_spawn_t -= delta
	if _spawn_t > 0.0:
		return
	_spawn_t = lerpf(1.5, 0.55, progress)
	var roll := rng.randf()
	if roll < 0.42:
		_spawn_satellite()
	elif roll < 0.75:
		_spawn_comet()
	elif progress > 0.2:
		_spawn_ship()
	else:
		_spawn_satellite()


func _spawn_pos() -> Vector3:
	return Vector3(rng.randf_range(-BOUNDS_X - 3, BOUNDS_X + 3),
		rng.randf_range(BOUNDS_Y_MIN - 2, BOUNDS_Y_MAX + 3), 190.0)


func _spawn_satellite() -> void:
	var n := Node3D.new()
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.6, 0.62, 0.68)
	body_mat.metallic = 0.7
	body_mat.roughness = 0.4
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.1, 0.2, 0.5)
	panel_mat.metallic = 0.4
	panel_mat.roughness = 0.3
	var body := BoxMesh.new()
	body.size = Vector3(1.2, 1.2, 1.8)
	_vis_mesh(n, body, body_mat, Vector3.ZERO)
	for side in [-1.0, 1.0]:
		var panel := BoxMesh.new()
		panel.size = Vector3(2.6, 0.06, 1.2)
		_vis_mesh(n, panel, panel_mat, Vector3(2.0 * side, 0, 0))
	var dish := CylinderMesh.new()
	dish.top_radius = 0.5
	dish.bottom_radius = 0.1
	dish.height = 0.3
	_vis_mesh(n, dish, body_mat, Vector3(0, 0.8, 0))
	add_child(n)
	n.global_position = _spawn_pos()
	obstacles.append({ "node": n, "vel": Vector3(0, 0, -55), "hp": 2, "radius": 2.4,
		"type": "sat", "spin": Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) })


func _spawn_comet() -> void:
	var n := Node3D.new()
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.45, 0.4, 0.38)
	rock_mat.roughness = 0.9
	var core := SphereMesh.new()
	core.radius = 1.3
	core.height = 2.6
	var c := _vis_mesh(n, core, rock_mat, Vector3.ZERO)
	c.scale = Vector3(1.0, 0.85, 1.1)
	var tail_mat := StandardMaterial3D.new()
	tail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tail_mat.albedo_color = Color(0.5, 0.8, 1.0, 0.3)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(0.5, 0.8, 1.0)
	tail_mat.emission_energy_multiplier = 1.2
	var tail := CylinderMesh.new()
	tail.top_radius = 0.1
	tail.bottom_radius = 1.1
	tail.height = 9.0
	tail.material = tail_mat
	var t := MeshInstance3D.new()
	t.mesh = tail
	t.rotation_degrees = Vector3(-90, 0, 0)
	t.position = Vector3(0, 0, 5.0)
	n.add_child(t)
	add_child(n)
	n.global_position = _spawn_pos()
	obstacles.append({ "node": n, "vel": Vector3(rng.randf_range(-4, 4), rng.randf_range(-2, 2), -80),
		"hp": 1, "radius": 2.6, "type": "comet", "spin": Vector3(1.5, 0, 0) })


func _spawn_ship() -> void:
	var n := Node3D.new()
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.16, 0.14, 0.2)
	hull_mat.metallic = 0.8
	hull_mat.roughness = 0.35
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.05, 0.02, 0.02)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.25, 0.15)
	glow_mat.emission_energy_multiplier = 3.0
	var body := PrismMesh.new()
	body.size = Vector3(2.6, 0.7, 2.4)
	var b := _vis_mesh(n, body, hull_mat, Vector3.ZERO)
	b.rotation_degrees = Vector3(-90, 0, 0)
	var cockpit_m := SphereMesh.new()
	cockpit_m.radius = 0.35
	cockpit_m.height = 0.7
	_vis_mesh(n, cockpit_m, glow_mat, Vector3(0, 0.3, -0.3))
	for side in [-1.0, 1.0]:
		var eng := CylinderMesh.new()
		eng.top_radius = 0.15
		eng.bottom_radius = 0.22
		eng.height = 0.5
		var e := _vis_mesh(n, eng, glow_mat, Vector3(0.9 * side, 0, 1.1))
		e.rotation_degrees = Vector3(90, 0, 0)
	add_child(n)
	n.global_position = _spawn_pos()
	obstacles.append({ "node": n, "vel": Vector3(0, 0, -42), "hp": 3, "radius": 2.2,
		"type": "ship", "fire_t": rng.randf_range(0.8, 1.4), "spin": Vector3.ZERO })


func _orb(color: Color, radius: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.5
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _step_world(delta: float) -> void:
	# player shots
	for i in range(shots.size() - 1, -1, -1):
		var s := shots[i]
		s.node.position += s.vel * delta
		if s.node.position.z > 220.0:
			s.node.queue_free()
			shots.remove_at(i)

	# enemy shots
	for i in range(enemy_shots.size() - 1, -1, -1):
		var s := enemy_shots[i]
		s.node.position += s.vel * delta
		if s.node.position.z < -20.0 or s.node.position.z > 240.0:
			s.node.queue_free()
			enemy_shots.remove_at(i)
			continue
		if s.node.position.distance_to(rocket.position) < 1.6:
			s.node.queue_free()
			enemy_shots.remove_at(i)
			_hit_player()

	# obstacles
	for i in range(obstacles.size() - 1, -1, -1):
		var o := obstacles[i]
		var n: Node3D = o.node
		n.position += o.vel * delta
		n.rotation += o.spin * delta
		if o.type == "ship":
			n.position.x = lerpf(n.position.x, rocket.position.x, 0.4 * delta)
			o.fire_t -= delta
			if o.fire_t <= 0.0 and n.position.z > 30.0:
				o.fire_t = 1.7
				sfx.play_enemy_laser()
				var shot := _orb(Color(1.0, 0.3, 0.2), 0.35)
				add_child(shot)
				shot.global_position = n.global_position + Vector3(0, 0, -2)
				var dir := (rocket.position - shot.global_position).normalized()
				enemy_shots.append({ "node": shot, "vel": dir * 55.0 })
		if n.position.z < -25.0:
			n.queue_free()
			obstacles.remove_at(i)
			continue
		# collide with player
		if _invuln <= 0.0 and n.position.distance_to(rocket.position) < o.radius + 1.1:
			_explode_at(n.global_position, 1.5)
			n.queue_free()
			obstacles.remove_at(i)
			_hit_player()
			continue
		# collide with player shots
		for j in range(shots.size() - 1, -1, -1):
			var s := shots[j]
			if s.node.position.distance_to(n.position) < o.radius + 0.5:
				s.node.queue_free()
				shots.remove_at(j)
				o.hp -= 1
				if o.hp <= 0:
					kills += 1
					Flow.kills += 1
					kills_label.text = "KILLS  %d" % kills
					_explode_at(n.global_position, 2.0)
					sfx.play_splat()
					n.queue_free()
					obstacles.remove_at(i)
				break


func _hit_player() -> void:
	if _invuln > 0.0:
		return
	_invuln = 1.0
	shields -= 1
	sfx.play_crash()
	_trauma = 1.0
	vignette.color.a = 0.4
	var tw := create_tween()
	tw.tween_property(vignette, "color:a", 0.0, 0.5)
	var pips := ""
	for i in 3:
		pips += "◆ " if i < shields else "◇ "
	shield_label.text = "SHIELDS  " + pips
	if shields <= 0:
		_die()


func _die() -> void:
	state = "dead"
	_explode_at(rocket.position, 4.0)
	sfx.play_ship_explosion()
	sfx.set_thrust(0.0)
	rocket.visible = false
	_show_card("SHIP DESTROYED", "so close…\n\npress R to relaunch")


func _win() -> void:
	state = "won"
	Flow.finish()
	sfx.set_thrust(0.0)
	card_box.visible = false
	_landing_cinematic()


# ============================================================================
#  CINEMÁTICA DE POUSO NA LUA  →  astronauta finca a bandeira Capim
#  (pré-visualize só este trecho com:  FOGUETE_ENDING=1 godot --path .)
# ============================================================================
func _landing_cinematic() -> void:
	# limpa o gameplay
	for o in obstacles:
		if is_instance_valid(o.node):
			o.node.queue_free()
	obstacles.clear()
	for s in shots:
		if is_instance_valid(s.node):
			s.node.queue_free()
	shots.clear()
	for s in enemy_shots:
		if is_instance_valid(s.node):
			s.node.queue_free()
	enemy_shots.clear()
	if is_instance_valid(_streaks):
		_streaks.emitting = false
	if progress_bar.get_parent():
		progress_bar.get_parent().visible = false  # esconde a barra + "DISTANCE TO MOON"
	shield_label.visible = false
	kills_label.visible = false

	# cenário lunar + Terra ao fundo
	_build_lunar_scene()
	var astro := _build_astronaut()
	astro.visible = false
	var flag := _build_flag()
	flag.visible = false

	# foguete GRANDE, em pé, no alto, pronto pra descer (bico pra cima)
	rocket.scale = Vector3.ONE * 1.7
	rocket.rotation_degrees = Vector3(-90, 0, 0)
	rocket.position = Vector3(4.0, 26.0, 13.0)
	_deploy_landing_legs()

	# durante o pouso já estamos NA Lua → esconde a Lua distante da fase de voo
	if is_instance_valid(moon):
		moon.visible = false

	# câmera cinematográfica em 3/4 (aim contínuo via _cine_look no _process)
	_cine = true
	cam.position = Vector3(-13.0, 8.5, -1.0)
	_cine_look = Vector3(2.0, 5.4, 12.5)
	await get_tree().process_frame

	# BEAT 1 — descida e pouso (~4.2s)
	sfx.set_thrust(0.5)
	var touchdown := Vector3(4.0, 4.1, 13.0)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(rocket, "position", touchdown, 4.2)
	var cw := create_tween()
	cw.set_parallel(true)
	cw.tween_property(cam, "position", Vector3(-10.5, 6.2, 3.0), 4.2)
	cw.tween_property(self, "_cine_look", Vector3(2.4, 4.8, 12.8), 4.2)
	await tw.finished
	_dust_puff(Vector3(4.0, 0.2, 13.0))
	_trauma = 0.6
	sfx.set_thrust(0.0)
	sfx.play_chime()
	await get_tree().create_timer(0.9).timeout
	await _shot("a_touchdown")

	# BEAT 2 — astronauta sai da escotilha e desce ao solo (~2.5s)
	astro.visible = true
	astro.position = Vector3(5.0, 2.6, 12.0)
	await _hop(astro, Vector3(3.4, 0.0, 11.0), 1.0, 0.65)
	await _hop(astro, Vector3(1.4, 0.0, 10.4), 1.1, 0.65)

	# aproxima a câmera pra enquadrar o astronauta + a bandeira
	var cw2 := create_tween()
	cw2.set_parallel(true)
	cw2.tween_property(cam, "position", Vector3(-8.5, 4.4, 5.6), 1.1)
	cw2.tween_property(self, "_cine_look", Vector3(-1.2, 2.2, 10.2), 1.1)

	# BEAT 3 — anda até o ponto e finca a bandeira (~3s)
	await _hop(astro, Vector3(-1.0, 0.0, 9.6), 1.1, 0.7)
	# gira SUAVEMENTE pra encarar a câmera (antes virava de repente)
	var cur_rot := astro.rotation
	astro.look_at(Vector3(cam.position.x, astro.position.y, cam.position.z), Vector3.UP)
	astro.rotate_y(deg_to_rad(180))   # corrige o eixo "frente" do modelo NASA
	var face_rot := astro.rotation
	astro.rotation = cur_rot
	var rt := create_tween()
	rt.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	rt.tween_property(astro, "rotation", face_rot, 0.8)
	await rt.finished
	# bandeira à esquerda do astronauta (lado da mão esquerda, que fica à direita da câmera)
	flag.position = Vector3(-2.4, 0.0, 9.6)
	flag.visible = true
	flag.scale = Vector3(1.6, 0.03, 1.6)  # mastro crava e sobe
	var fw := create_tween()
	fw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	fw.tween_property(flag, "scale", Vector3.ONE * 1.6, 0.9)
	await fw.finished
	# comemora com um pulinho de baixa gravidade
	await _hop(astro, Vector3(-1.0, 0.0, 9.6), 2.0, 0.7)
	await _shot("b_flag")

	# BEAT 4 — card final com a foto do Eric
	await get_tree().create_timer(0.6).timeout
	_show_final_card()
	await get_tree().create_timer(0.4).timeout
	await _shot("c_card")


func _shot(fname: String) -> void:
	if OS.get_environment("FOGUETE_SHOT") != "1":
		return
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("FOGUETE_SHOT_DIR")
	if dir == "":
		dir = "."
	get_viewport().get_texture().get_image().save_png(dir + "/" + fname + ".png")


func _deploy_landing_legs() -> void:
	var vis := rocket.get_child(0) as Node3D
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.2, 0.2, 0.22)
	leg_mat.metallic = 0.7
	for i in 3:
		var ang := TAU * i / 3.0
		var leg := BoxMesh.new()
		leg.size = Vector3(0.09, 0.9, 0.09)
		var l := _vis_mesh(vis, leg, leg_mat, Vector3(sin(ang) * 0.7, -1.55, cos(ang) * 0.7))
		l.rotation = Vector3(cos(ang) * 0.5, 0.0, -sin(ang) * 0.5)
		var foot := BoxMesh.new()
		foot.size = Vector3(0.28, 0.08, 0.28)
		_vis_mesh(vis, foot, leg_mat, Vector3(sin(ang) * 1.0, -1.95, cos(ang) * 1.0))


func _build_lunar_scene() -> void:
	# esconde as estrelas procedurais — a foto de fundo já traz espaço + Terra
	for c in get_children():
		if c is MultiMeshInstance3D:
			c.visible = false

	_apply_lunar_lighting()

	# FUNDO realista: foto Lua+Terra como painel gigante atrás de tudo
	if ResourceLoader.exists("res://assets/lua.jpg"):
		var bg := MeshInstance3D.new()
		var bq := QuadMesh.new()
		bq.size = Vector2(900, 506)
		bg.mesh = bq
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.albedo_texture = load("res://assets/lua.jpg")
		bmat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		bmat.billboard_keep_scale = true
		bg.mesh.material = bmat
		bg.position = Vector3(0, -30, 235)
		add_child(bg)

	# solo de pouso: terreno real petavius (glb). Escalado e achatado p/ os atores ficarem no chão.
	if ResourceLoader.exists("res://assets/petavius.glb"):
		var pscene: PackedScene = load("res://assets/petavius.glb")
		var terrain := pscene.instantiate()
		terrain.scale = Vector3(120, 45, 120)   # largura ~265 u, relevo suave
		terrain.position = Vector3(4, 0.5, 13)   # centro sob a área de pouso (y ajustável)
		add_child(terrain)
	else:
		var ground_mat := StandardMaterial3D.new()
		ground_mat.roughness = 1.0
		if ResourceLoader.exists("res://assets/moon_ground.jpg"):
			ground_mat.albedo_texture = load("res://assets/moon_ground.jpg")
			ground_mat.uv1_scale = Vector3(5, 5, 5)
		else:
			ground_mat.albedo_color = Color(0.5, 0.48, 0.47)
		var ground := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(360, 360)
		ground.mesh = pm
		ground.material_override = ground_mat
		ground.position = Vector3(0, 0, 30)
		add_child(ground)


# ---- BLOCO A: iluminação lunar estilo foto da Apollo ----
func _apply_lunar_lighting() -> void:
	if _env:
		# ambiente baixo (lado escuro fundo, mas ainda legível); sem névoa; contraste fotográfico
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_color = Color(0.11, 0.12, 0.16)
		_env.ambient_light_energy = 0.09           # sombras bem escuras = contraste Apollo
		_env.fog_enabled = false
		_env.tonemap_mode = Environment.TONE_MAPPER_ACES
		_env.tonemap_exposure = 0.95
		_env.tonemap_white = 6.0
		_env.ssao_enabled = true          # oclusão de contato (sombras suaves nos cantos)
		_env.ssao_radius = 1.5
		_env.ssao_intensity = 1.8
		_env.adjustment_enabled = true
		_env.adjustment_contrast = 1.18
		_env.adjustment_saturation = 1.06
		# glow contido: só o mais brilhante floresce (evita o "flare" lavando a cena)
		_env.glow_enabled = true
		_env.glow_intensity = 0.5
		_env.glow_bloom = 0.02
		_env.glow_hdr_threshold = 1.3
	if _sun:
		# Sol único e forte, vindo de cima-frente-esquerda (lado da câmera):
		# ilumina o lado visível dos objetos e joga sombras longas pra trás/direita.
		_sun.look_at_from_position(Vector3(-16, 10, 2), Vector3(3, 0.5, 13), Vector3.UP)
		_sun.light_color = Color(1.0, 0.97, 0.9)
		_sun.light_energy = 1.6
		_sun.shadow_enabled = true
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		_sun.light_angular_distance = 0.15   # penumbra mínima = sombra nítida
		_sun.shadow_blur = 0.4
		_sun.shadow_bias = 0.03
		_sun.directional_shadow_max_distance = 140.0
	# fill fraco do lado da câmera pra os lados sombreados não virarem preto puro
	var fill := DirectionalLight3D.new()
	fill.look_at_from_position(Vector3(-10, 6, 0), Vector3(0, 1.5, 11), Vector3.UP)
	fill.light_color = Color(0.7, 0.78, 0.95)
	fill.light_energy = 0.18
	fill.shadow_enabled = false
	add_child(fill)
	# rim/back light atrás do astronauta pra recortar a silhueta
	var rim := OmniLight3D.new()
	rim.position = Vector3(2.5, 6.0, 15.0)
	rim.light_color = Color(0.55, 0.68, 1.0)
	rim.light_energy = 3.0
	rim.omni_range = 26.0
	rim.omni_attenuation = 1.2
	add_child(rim)


func _build_astronaut() -> Node3D:
	# BLOCO D — usa o modelo EVA da NASA (glTF) se existir; senão, o bonequinho de primitivas
	if ResourceLoader.exists("res://assets/astronaut.glb"):
		var scene: PackedScene = load("res://assets/astronaut.glb")
		if scene:
			var holder := Node3D.new()
			var inst := scene.instantiate()
			# modelo da NASA vem gigante (~74 u) → normaliza p/ ~3.4 u de altura
			inst.scale = Vector3.ONE * 0.046
			inst.position.y = 1.7   # apoia os pés no chão (ajuste fino depois de ver a pose)
			holder.add_child(inst)
			add_child(holder)
			return holder

	var a := Node3D.new()
	add_child(a)
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.93, 0.94, 0.96)
	suit.roughness = 0.8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	dark.metallic = 0.3
	var visor := StandardMaterial3D.new()
	visor.albedo_color = Color(0.15, 0.2, 0.28)
	visor.metallic = 0.9
	visor.roughness = 0.1
	# torso
	var torso := CapsuleMesh.new()
	torso.radius = 0.32
	torso.height = 1.0
	_vis_mesh(a, torso, suit, Vector3(0, 0.85, 0))
	# cabeça/capacete
	var head := SphereMesh.new()
	head.radius = 0.28
	head.height = 0.56
	_vis_mesh(a, head, suit, Vector3(0, 1.5, 0))
	var vz := SphereMesh.new()
	vz.radius = 0.2
	vz.height = 0.4
	_vis_mesh(a, vz, visor, Vector3(0, 1.5, 0.16))
	# mochila
	var pack := BoxMesh.new()
	pack.size = Vector3(0.44, 0.6, 0.24)
	_vis_mesh(a, pack, dark, Vector3(0, 0.95, -0.34))
	# braços
	for sx in [-1.0, 1.0]:
		var arm := CapsuleMesh.new()
		arm.radius = 0.11
		arm.height = 0.7
		var m := _vis_mesh(a, arm, suit, Vector3(sx * 0.42, 0.85, 0.05))
		m.rotation_degrees = Vector3(10, 0, sx * 12)
	# pernas
	for sx in [-1.0, 1.0]:
		var leg := CapsuleMesh.new()
		leg.radius = 0.13
		leg.height = 0.7
		_vis_mesh(a, leg, suit, Vector3(sx * 0.16, 0.2, 0))
	# botas
	for sx in [-1.0, 1.0]:
		var boot := BoxMesh.new()
		boot.size = Vector3(0.22, 0.14, 0.34)
		_vis_mesh(a, boot, dark, Vector3(sx * 0.16, -0.05, 0.06))
	a.scale = Vector3.ONE * 1.9   # (antes era aplicado na cinemática)
	return a


func _build_flag() -> Node3D:
	var f := Node3D.new()
	add_child(f)
	# mastro
	var pole := CylinderMesh.new()
	pole.top_radius = 0.045
	pole.bottom_radius = 0.045
	pole.height = 3.0
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.85, 0.85, 0.9)
	pole_mat.metallic = 0.8
	_vis_mesh(f, pole, pole_mat, Vector3(0, 1.5, 0))
	# pano com a bandeira Capim (imagem real), virado para a câmera; "voa" em +Z
	var cloth := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.75, 1.12)
	cloth.mesh = q
	var cmat := StandardMaterial3D.new()
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if ResourceLoader.exists("res://assets/flag.png"):
		cmat.albedo_texture = load("res://assets/flag.png")
	else:
		cmat.albedo_color = Color(1, 1, 1)
	cloth.mesh.material = cmat
	cloth.rotation_degrees = Vector3(0, -90, 0)
	cloth.position = Vector3(0, 2.35, 0.95)
	f.add_child(cloth)
	return f


func _dust_puff(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.direction = Vector3(0, 0.3, 0)
	pm.spread = 90.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -1.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.color = Color(0.7, 0.7, 0.72, 0.5)
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.72, 0.72, 0.75, 0.5)
	mesh.material = mat
	p.draw_pass_1 = mesh
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


# pulinho de baixa gravidade: move até to_pos com um arco de altura `up`
func _hop(node: Node3D, to_pos: Vector3, up: float, dur: float) -> void:
	var from := node.position
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "position:x", to_pos.x, dur)
	tw.tween_property(node, "position:z", to_pos.z, dur)
	# arco vertical: sobe até o meio e desce
	var up_tw := create_tween()
	up_tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	up_tw.tween_property(node, "position:y", maxf(from.y, to_pos.y) + up, dur * 0.5)
	up_tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	up_tw.tween_property(node, "position:y", to_pos.y, dur * 0.5)
	await tw.finished


func _show_final_card() -> void:
	# foto do Eric acima do texto (some se o arquivo não existir)
	if ResourceLoader.exists("res://assets/astronaut.png"):
		var tr := TextureRect.new()
		tr.texture = load("res://assets/astronaut.png")
		tr.custom_minimum_size = Vector2(220, 220)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card_box.add_child(tr)
		card_box.move_child(tr, 0)
	var mins := int(Flow.run_time) / 60
	var secs := fmod(Flow.run_time, 60.0)
	_show_card("MISSÃO CUMPRIDA",
		"a bandeira da Capim está na Lua 🚀\n\ntempo  %d:%04.1f      abates  %d\n\naperte R para jogar de novo" % [mins, secs, Flow.kills])


func _explode_at(pos: Vector3, scale_f: float) -> void:
	sfx.play_explosion()
	var p := GPUParticles3D.new()
	p.amount = 120
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4 * scale_f
	pm.spread = 180.0
	pm.initial_velocity_min = 6.0 * scale_f
	pm.initial_velocity_max = 16.0 * scale_f
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.3 * scale_f
	pm.scale_max = 0.8 * scale_f
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.8, 1.0),
		Color(1.0, 0.5, 0.1, 0.9),
		Color(0.4, 0.1, 0.05, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var pmesh := SphereMesh.new()
	pmesh.radius = 0.15
	pmesh.height = 0.3
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.vertex_color_use_as_albedo = true
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.emission_enabled = true
	pmat.emission = Color(1.0, 0.5, 0.15)
	pmat.emission_energy_multiplier = 3.0
	pmesh.material = pmat
	p.draw_pass_1 = pmesh
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func _camera(delta: float) -> void:
	_trauma = maxf(_trauma - delta * 1.5, 0.0)
	var sh := _trauma * _trauma
	var desired := Vector3(rocket.position.x * 0.6, 6.5 + rocket.position.y * 0.5, -14)
	cam.position = cam.position.lerp(desired, 1.0 - exp(-5.0 * delta))
	cam.fov = lerpf(cam.fov, lerpf(75.0, 90.0, (speed_mult - 1.0) / (BOOST_MULT - 1.0)), 1.0 - exp(-5.0 * delta))
	cam.look_at(rocket.position + Vector3(0, 2.5, 22))
	cam.h_offset = rng.randf_range(-1, 1) * 0.4 * sh
	cam.v_offset = rng.randf_range(-1, 1) * 0.4 * sh
