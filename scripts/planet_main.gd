extends Node3D
## Phase 1 — dark slime planet. Find the rocket, survive the aliens.

const START_SPOT := { "pos": Vector2(0, -20), "height": 4.0, "radius": 8.0 }
const ROCKET_SPOT := { "pos": Vector2(0, 175), "height": 6.0, "radius": 10.0 }
const ALIEN_START := 2       # roaming when you arrive
const ALIEN_MAX_ALIVE := 5   # never more than this at once
const SPAWN_MIN := 4.0       # seconds between spawn attempts
const SPAWN_MAX := 8.0
const PART_DEFS := [
	{ "name": "CÉLULA DE COMBUSTÍVEL", "pos": Vector2(-26, 55) },
	{ "name": "MÓDULO DE NAVEGAÇÃO", "pos": Vector2(24, 105) },
	{ "name": "TUBEIRA DO MOTOR", "pos": Vector2(-14, 150) },
]

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
var parts: Array[Dictionary] = []
var parts_found := 0
var toast_label: Label
var _toast_t := 0.0
var _spawn_rng := RandomNumberGenerator.new()
var _alien_spawn_t := 5.0
var _briefing_active := false


func _ready() -> void:
	Flow.start_run()
	_build_environment()
	_build_terrain()
	_decorate()
	_build_rocket()
	_build_parts()
	_build_player()
	_spawn_aliens()
	_build_hud()
	sfx = Sfx.new()
	add_child(sfx)

	if OS.get_environment("FOGUETE_PHOTO") == "1":
		_photo_mode.call_deferred()
		return

	# Captain Gus radios the mission briefing over the helmet HUD;
	# freeze movement (the player can still look around) until he's done
	player.set_physics_process(false)
	hud.visible = false
	# hold the hunters until the briefing ends — no dying mid-transmission
	_briefing_active = true
	for a in get_tree().get_nodes_in_group("alien"):
		a.set_physics_process(false)
	var briefing := CaptainBriefing.new()
	briefing.setup(sfx)
	add_child(briefing)

	if OS.get_environment("FOGUETE_PHOTO_GUS") == "1":
		get_tree().create_timer(1.6).timeout.connect(func () -> void:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/Users/verona/Documents/foguete/.shots/gus.png")
			get_tree().quit()
		)
		return
	briefing.finished.connect(func () -> void:
		_briefing_active = false
		if is_instance_valid(player):
			player.set_physics_process(true)
		for a in get_tree().get_nodes_in_group("alien"):
			a.set_physics_process(true)
		hud.visible = true
		_show_card("BOA CAÇADA, RECRUTA",
			"WASD mover · SHIFT correr · ESPAÇO pular · Q esquiva · LMB atirar · E interagir")
		get_tree().create_timer(3.5).timeout.connect(func () -> void:
			if not _game_over:
				_fade_card()
		)
	)


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

	# tooth rocket — Capim is a dental company, so the ship is a giant molar
	var enamel := StandardMaterial3D.new()
	enamel.albedo_color = Color(0.97, 0.97, 0.94)
	enamel.roughness = 0.2
	enamel.metallic = 0.0
	var ivory := StandardMaterial3D.new()
	ivory.albedo_color = Color(0.9, 0.86, 0.74)
	ivory.roughness = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.13, 0.13, 0.16)
	dark.metallic = 0.7

	var warm_glow := StandardMaterial3D.new()
	warm_glow.albedo_color = Color(0.05, 0.04, 0.02)
	warm_glow.emission_enabled = true
	warm_glow.emission = Color(1.0, 0.75, 0.4)
	warm_glow.emission_energy_multiplier = 2.5

	# crown — bulbous enamel body
	var crown := SphereMesh.new()
	crown.radius = 0.82
	crown.height = 1.5
	var cr := MeshInstance3D.new()
	cr.mesh = crown
	cr.material_override = enamel
	cr.position = Vector3(0, 0.5, 0)
	cr.scale = Vector3(1.05, 1.05, 0.95)
	root.add_child(cr)

	# rounded cusps on the biting surface
	for cx in [-0.34, 0.34]:
		for cz in [-0.3, 0.3]:
			var cusp := SphereMesh.new()
			cusp.radius = 0.32
			cusp.height = 0.55
			var cu := MeshInstance3D.new()
			cu.mesh = cusp
			cu.material_override = enamel
			cu.position = Vector3(cx, 1.12, cz)
			root.add_child(cu)

	# neck tapering into the roots
	var neck := SphereMesh.new()
	neck.radius = 0.62
	neck.height = 0.9
	var nk := MeshInstance3D.new()
	nk.mesh = neck
	nk.material_override = enamel
	nk.position = Vector3(0, -0.35, 0)
	root.add_child(nk)

	# two tapering roots planted in the swamp (also read as landing legs)
	for rx in [-0.34, 0.34]:
		var rootcone := CylinderMesh.new()
		rootcone.top_radius = 0.4
		rootcone.bottom_radius = 0.04
		rootcone.height = 1.6
		var rc := MeshInstance3D.new()
		rc.mesh = rootcone
		rc.material_override = ivory
		rc.position = Vector3(rx, -1.4, 0)
		rc.rotation.z = -signf(rx) * 0.16
		root.add_child(rc)

	# hatch + glowing window on the front (the side the player approaches, -Z)
	var hatch := BoxMesh.new()
	hatch.size = Vector3(0.4, 0.55, 0.1)
	var hmi := MeshInstance3D.new()
	hmi.mesh = hatch
	hmi.material_override = dark
	hmi.position = Vector3(0, 0.05, -0.74)
	root.add_child(hmi)
	var win := BoxMesh.new()
	win.size = Vector3(0.24, 0.14, 0.04)
	var wmi := MeshInstance3D.new()
	wmi.mesh = win
	wmi.material_override = warm_glow
	wmi.position = Vector3(0, 0.24, -0.8)
	root.add_child(wmi)

	# Capim logo panel on the crown, facing the player
	var logo_mat := StandardMaterial3D.new()
	logo_mat.albedo_texture = load("res://assets/capim.png")
	logo_mat.emission_enabled = true
	logo_mat.emission_texture = load("res://assets/capim.png")
	logo_mat.emission_energy_multiplier = 0.35
	var logo := QuadMesh.new()
	logo.size = Vector2(0.66, 0.66)
	var lmi := MeshInstance3D.new()
	lmi.mesh = logo
	lmi.material_override = logo_mat
	lmi.position = Vector3(0, 0.66, -0.79)
	lmi.rotation_degrees = Vector3(0, 180, 0)
	root.add_child(lmi)

	# engine glow beneath the roots
	var eng := OmniLight3D.new()
	eng.position = Vector3(0, -2.1, 0)
	eng.omni_range = 6.0
	eng.light_energy = 2.0
	eng.light_color = Color(1.0, 0.6, 0.3)
	root.add_child(eng)

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


func _build_parts() -> void:
	var pedestal_mat := StandardMaterial3D.new()
	pedestal_mat.albedo_color = Color(0.1, 0.11, 0.13)
	pedestal_mat.metallic = 0.7
	pedestal_mat.roughness = 0.4

	for i in PART_DEFS.size():
		var def: Dictionary = PART_DEFS[i]
		var root := Node3D.new()
		add_child(root)
		var h := terrain.get_height(def.pos.x, def.pos.y)
		root.global_position = Vector3(def.pos.x, h, def.pos.y)

		var pedestal := BoxMesh.new()
		pedestal.size = Vector3(0.8, 0.25, 0.8)
		var pd := MeshInstance3D.new()
		pd.mesh = pedestal
		pd.material_override = pedestal_mat
		pd.position = Vector3(0, 0.12, 0)
		root.add_child(pd)

		var item := Node3D.new()
		item.position = Vector3(0, 1.1, 0)
		root.add_child(item)
		_build_part_item(item, i)

		# amber beacon column
		var beacon := SpotLight3D.new()
		beacon.position = Vector3(0, 0.4, 0)
		beacon.rotation_degrees = Vector3(90, 0, 0)
		beacon.spot_range = 70.0
		beacon.spot_angle = 5.0
		beacon.light_energy = 14.0
		beacon.light_color = Color(1.0, 0.72, 0.25)
		beacon.light_volumetric_fog_energy = 8.0
		beacon.shadow_enabled = false
		root.add_child(beacon)

		var glow := OmniLight3D.new()
		glow.position = Vector3(0, 1.2, 0)
		glow.omni_range = 9.0
		glow.light_energy = 1.4
		glow.light_color = Color(1.0, 0.72, 0.25)
		root.add_child(glow)

		var shaft_mesh := CylinderMesh.new()
		shaft_mesh.top_radius = 0.5
		shaft_mesh.bottom_radius = 0.2
		shaft_mesh.height = 26.0
		var shaft_mat := StandardMaterial3D.new()
		shaft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shaft_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shaft_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		shaft_mat.albedo_color = Color(1.0, 0.72, 0.25, 0.09)
		shaft_mesh.material = shaft_mat
		var shaft := MeshInstance3D.new()
		shaft.mesh = shaft_mesh
		shaft.position = Vector3(0, 13.5, 0)
		root.add_child(shaft)

		parts.append({ "root": root, "item": item, "name": def.name, "found": false, "idx": i })


func _build_part_item(item: Node3D, idx: int) -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.7, 0.72, 0.78)
	metal.metallic = 0.8
	metal.roughness = 0.3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.16, 0.18)
	dark.metallic = 0.7
	dark.roughness = 0.4

	match idx:
		0:  # fuel cell — canister with glowing green band
			var can := CylinderMesh.new()
			can.top_radius = 0.22
			can.bottom_radius = 0.22
			can.height = 0.55
			_item_mesh(item, can, metal, Vector3.ZERO)
			var band := CylinderMesh.new()
			band.top_radius = 0.23
			band.bottom_radius = 0.23
			band.height = 0.13
			var glow := StandardMaterial3D.new()
			glow.albedo_color = Color(0.02, 0.05, 0.02)
			glow.emission_enabled = true
			glow.emission = Color(0.3, 1.0, 0.4)
			glow.emission_energy_multiplier = 2.5
			band.material = glow
			var b := MeshInstance3D.new()
			b.mesh = band
			item.add_child(b)
		1:  # nav module — gyroscope sphere with ring
			var core := SphereMesh.new()
			core.radius = 0.18
			core.height = 0.36
			var cg := StandardMaterial3D.new()
			cg.albedo_color = Color(0.02, 0.04, 0.06)
			cg.emission_enabled = true
			cg.emission = Color(0.3, 0.9, 1.0)
			cg.emission_energy_multiplier = 2.2
			core.material = cg
			var c := MeshInstance3D.new()
			c.mesh = core
			item.add_child(c)
			var ring := TorusMesh.new()
			ring.inner_radius = 0.26
			ring.outer_radius = 0.31
			var r := _item_mesh(item, ring, metal, Vector3.ZERO)
			r.rotation_degrees = Vector3(35, 0, 20)
		2:  # engine nozzle — bell with hot core
			var bell := CylinderMesh.new()
			bell.top_radius = 0.13
			bell.bottom_radius = 0.3
			bell.height = 0.42
			_item_mesh(item, bell, dark, Vector3.ZERO)
			var hot := SphereMesh.new()
			hot.radius = 0.12
			hot.height = 0.24
			var hg := StandardMaterial3D.new()
			hg.albedo_color = Color(0.06, 0.02, 0.0)
			hg.emission_enabled = true
			hg.emission = Color(1.0, 0.5, 0.15)
			hg.emission_energy_multiplier = 2.5
			hot.material = hg
			var hm := MeshInstance3D.new()
			hm.mesh = hot
			hm.position = Vector3(0, -0.12, 0)
			hm.scale = Vector3(1, 0.5, 1)
			item.add_child(hm)


func _item_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


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
	_spawn_rng.seed = 31
	for i in ALIEN_START:
		var z := _spawn_rng.randf_range(30.0, 150.0)
		var x := _spawn_rng.randf_range(-24.0, 24.0)
		_make_alien(Vector3(x, terrain.get_height(x, z) + 1.0, z))


func _make_alien(pos: Vector3) -> void:
	var a := Alien.new()
	add_child(a)
	a.global_position = pos
	a.player = player
	a.planet = self
	a.killed.connect(_on_alien_killed)


func _tick_spawns(delta: float) -> void:
	if _briefing_active:
		return
	_alien_spawn_t -= delta
	if _alien_spawn_t > 0.0:
		return
	_alien_spawn_t = _spawn_rng.randf_range(SPAWN_MIN, SPAWN_MAX)
	if get_tree().get_nodes_in_group("alien").size() >= ALIEN_MAX_ALIVE:
		return
	# spawn at a random point on a ring around the player, biased ahead
	# toward the rocket, and never right on top of them
	var ang := _spawn_rng.randf_range(-1.4, 1.4)  # mostly in front
	var dist := _spawn_rng.randf_range(22.0, 34.0)
	var fwd := (rocket_pos - player.global_position)
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var dir := fwd.rotated(Vector3.UP, ang)
	var p := player.global_position + dir * dist
	p.x = clampf(p.x, Terrain.X_MIN + 6, Terrain.X_MAX - 6)
	p.z = clampf(p.z, Terrain.Z_MIN + 6, Terrain.Z_MAX - 6)
	p.y = terrain.get_height(p.x, p.z) + 1.0
	_make_alien(p)


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
	box.add_child(_mk_label("VIDA", 15, Color(0.7, 0.9, 1.0)))
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
	kills_label = _mk_label("ABATES  0", 15, Color(0.9, 0.9, 0.9))
	box.add_child(kills_label)

	objective = _mk_label("", 22, Color(0.85, 0.95, 1.0))
	objective.set_anchors_preset(Control.PRESET_CENTER_TOP)
	objective.position = Vector2(0, 28)
	objective.grow_horizontal = Control.GROW_DIRECTION_BOTH
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(objective)

	toast_label = _mk_label("", 22, Color(1.0, 0.85, 0.4))
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(0, 66)
	toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(toast_label)

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
	# freeze the first alien facing +Z so the face close-ups are deterministic
	if not aliens.is_empty():
		aliens[0].set_physics_process(false)
		(aliens[0] as Node3D).rotation.y = 0.0

	var shots := [
		{ "pos": a0 + Vector3(0, 1.78, 2.1), "look": a0 + Vector3(0, 1.76, 0) },
		{ "pos": a0 + Vector3(1.6, 1.6, 2.4), "look": a0 + Vector3(0, 1.4, 0) },
		{ "pos": a0 + Vector3(2.8, 1.2, 3.0), "look": a0 + Vector3(0, 1.1, 0) },
		{ "pos": a0 + Vector3(2.6, 1.9, 2.6), "look": a0 + Vector3(0, 1.2, 0) },
		{ "pos": rocket_pos + Vector3(10, 7, -18), "look": rocket_pos + Vector3(0, 3, 0) },
		{ "pos": player.global_position + Vector3(-1.2, 1.7, 1.8), "look": player.global_position + Vector3(-0.3, 1.3, 0.5) },
		{ "pos": (parts[0].root as Node3D).global_position + Vector3(2.4, 2.0, 2.4), "look": (parts[0].root as Node3D).global_position + Vector3(0, 1.1, 0) },
	]
	for i in shots.size():
		cam.global_position = shots[i].pos
		cam.look_at(shots[i].look)
		await get_tree().create_timer(0.9).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("/Users/verona/Documents/foguete/.shots/p%d.png" % i)
	get_tree().quit()


func _toast(text: String, color := Color(1.0, 0.85, 0.4)) -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", color)
	toast_label.modulate.a = 1.0
	_toast_t = 3.0


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	if Input.is_action_just_pressed("restart"):
		Flow.restart_phase()
		return
	if _game_over or player == null:
		return

	_tick_spawns(_delta)

	# toast fade
	if _toast_t > 0.0:
		_toast_t -= _delta
		if _toast_t <= 0.8:
			toast_label.modulate.a = maxf(_toast_t / 0.8, 0.0)

	# floating part items + pickup
	var t := Time.get_ticks_msec() / 1000.0
	for p in parts:
		if p.found:
			continue
		var item: Node3D = p.item
		item.position.y = 1.1 + sin(t * 2.0 + p.idx * 2.1) * 0.12
		item.rotation.y += _delta * 1.2
		if player.global_position.distance_to((p.root as Node3D).global_position) < 3.0:
			p.found = true
			parts_found += 1
			sfx.play_chime()
			_toast("%s A BORDO  —  %d/%d" % [p.name, parts_found, PART_DEFS.size()])
			(p.root as Node3D).queue_free()

	var total := PART_DEFS.size()
	var d := player.global_position.distance_to(rocket_pos)
	if parts_found < total:
		var nearest := 1e9
		for p in parts:
			if not p.found:
				nearest = minf(nearest, player.global_position.distance_to((p.root as Node3D).global_position))
		objective.text = "RECUPERE AS PEÇAS  %d/%d  —  baliza %0.0f m" % [parts_found, total, nearest]
	else:
		objective.text = "PEÇAS COMPLETAS  —  FOGUETE  %0.0f m" % d

	_near_rocket = d < 8.0
	prompt.visible = _near_rocket
	if _near_rocket:
		if parts_found < total:
			prompt.text = "FALTAM  %d  PEÇAS" % (total - parts_found)
			prompt.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
		else:
			prompt.text = "[E]  INSTALAR PEÇAS E ENTRAR"
			prompt.add_theme_color_override("font_color", Color(0.4, 1.0, 0.9))
	if _near_rocket and Input.is_action_just_pressed("interact"):
		if parts_found < total:
			sfx.play_hurt()
			_toast("o foguete não voa sem todas as peças", Color(1.0, 0.5, 0.4))
		else:
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
	_show_card("VOCÊ MORREU", "o pântano fica com seus ossos\n\nreiniciando…")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().create_timer(2.4).timeout.connect(Flow.restart_phase)


func _on_alien_killed(pos: Vector3) -> void:
	Flow.kills += 1
	kills_label.text = "ABATES  %d" % Flow.kills
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
