extends Node3D

enum State { TITLE, FLYING, CRASHED, WON }

const START := { "pos": Vector2(0, -10), "height": 8.0, "radius": 9.0 }
const PAD_DEFS := [
	{ "pos": Vector2(0, 60), "height": 6.0, "radius": 7.0, "name": "PAD ALPHA" },
	{ "pos": Vector2(-34, 140), "height": 2.0, "radius": 6.0, "name": "PAD BETA" },
	{ "pos": Vector2(52, 224), "height": 34.0, "radius": 6.0, "name": "PAD OMEGA" },
]

var state: State = State.TITLE
var current_pad := 0
var flight_time := 0.0

var rocket: Rocket
var terrain: Terrain
var pads: Array[LandingPad] = []
var cam: ChaseCamera
var hud: HUD
var sfx: Sfx


func _ready() -> void:
	_build_environment()
	_build_world()
	_build_rocket()

	cam = ChaseCamera.new()
	add_child(cam)
	cam.target = rocket
	cam.mode = "orbit"
	cam.global_position = rocket.global_position + Vector3(0, 5, -11)

	hud = HUD.new()
	add_child(hud)
	sfx = Sfx.new()
	add_child(sfx)

	hud.show_center("FOGUETE", "SPACE  thrust    ·    W A S D  tilt    ·    R  restart\n\npress SPACE to launch")
	hud.set_objective("")


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.07, 0.16)
	sky_mat.sky_horizon_color = Color(0.85, 0.38, 0.22)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.03, 0.03, 0.05)
	sky_mat.ground_horizon_color = Color(0.55, 0.25, 0.18)
	sky_mat.sun_angle_max = 40.0
	sky_mat.sun_curve = 0.08

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.6
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.sdfgi_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.022
	env.volumetric_fog_albedo = Color(0.6, 0.52, 0.62)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 240.0
	env.volumetric_fog_sky_affect = 0.25
	env.volumetric_fog_ambient_inject = 0.3

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-11.0, -130.0, 0.0)
	sun.light_color = Color(1.0, 0.55, 0.32)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	sun.light_angular_distance = 1.2
	add_child(sun)


func _build_world() -> void:
	var spots := [START]
	for d in PAD_DEFS:
		spots.append(d)

	var path := [START.pos]
	for d in PAD_DEFS:
		path.append(d.pos)

	terrain = Terrain.new()
	add_child(terrain)
	terrain.generate(spots, path)

	var start_pad := LandingPad.new()
	start_pad.setup(-1, "START", START.radius)
	add_child(start_pad)
	start_pad.global_position = Vector3(START.pos.x, START.height, START.pos.y)
	start_pad.set_pad_state(LandingPad.PadState.DONE)

	for i in PAD_DEFS.size():
		var d: Dictionary = PAD_DEFS[i]
		var pad := LandingPad.new()
		pad.setup(i, d.name, d.radius)
		add_child(pad)
		pad.global_position = Vector3(d.pos.x, d.height, d.pos.y)
		pad.set_pad_state(LandingPad.PadState.INACTIVE)
		pads.append(pad)

	pads[0].set_pad_state(LandingPad.PadState.ACTIVE)


func _build_rocket() -> void:
	rocket = Rocket.new()
	add_child(rocket)
	rocket.global_position = Vector3(START.pos.x, START.height + 2.6, START.pos.y)
	rocket.freeze = true
	rocket.crashed.connect(_on_rocket_crashed)
	rocket.touched_down.connect(_on_rocket_touched_down)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	if Input.is_action_just_pressed("restart"):
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
		return

	match state:
		State.TITLE:
			if Input.is_action_just_pressed("thrust"):
				_start_flight()
		State.FLYING:
			flight_time += delta
			_update_hud()
		_:
			pass

	if sfx != null and rocket != null:
		sfx.set_thrust(rocket.thrust_level if not rocket.dead else 0.0)


func _start_flight() -> void:
	state = State.FLYING
	rocket.freeze = false
	rocket.control_enabled = true
	cam.mode = "chase"
	hud.hide_center()
	_set_objective_text()
	sfx.play_beep()


func _set_objective_text() -> void:
	var d: Dictionary = PAD_DEFS[current_pad]
	var dist := rocket.global_position.distance_to(Vector3(d.pos.x, d.height, d.pos.y))
	hud.set_objective("LAND ON %s  —  %0.0f m" % [d.name, dist])


func _update_hud() -> void:
	var v := rocket.linear_velocity
	var h := Vector2(v.x, v.z).length()
	var ground := terrain.get_height(rocket.global_position.x, rocket.global_position.z)
	hud.set_fuel(rocket.fuel)
	hud.set_telemetry(h, v.y, rocket.global_position.y - ground - 1.8)
	_set_objective_text()


func _on_rocket_touched_down(pad: Node3D, impact_speed: float) -> void:
	if state != State.FLYING or not (pad is LandingPad):
		return
	var lp := pad as LandingPad
	if lp.index != current_pad:
		return

	lp.set_pad_state(LandingPad.PadState.DONE)
	sfx.play_chime()
	rocket.refuel()
	cam.add_trauma(0.25)

	var quality := "PERFECT TOUCHDOWN!" if impact_speed < 1.5 else "good landing"
	if current_pad >= PAD_DEFS.size() - 1:
		_win()
	else:
		current_pad += 1
		pads[current_pad].set_pad_state(LandingPad.PadState.ACTIVE)
		hud.toast("%s  ·  fuel restored" % quality)
		_set_objective_text()


func _win() -> void:
	state = State.WON
	hud.set_objective("")
	hud.show_center("MISSION COMPLETE",
		"time  %d:%04.1f      fuel left  %0.0f%%\n\npress R to fly again" % [
			int(flight_time) / 60, fmod(flight_time, 60.0), rocket.fuel])


func _on_rocket_crashed(pos: Vector3) -> void:
	if state == State.CRASHED:
		return
	state = State.CRASHED
	_spawn_explosion(pos)
	sfx.play_explosion()
	sfx.set_thrust(0.0)
	cam.add_trauma(1.0)
	Engine.time_scale = 0.25
	var t := get_tree().create_timer(0.35, true, false, true)
	t.timeout.connect(func () -> void:
		Engine.time_scale = 1.0
		hud.show_center("YOU CRASHED", "press R to try again")
	)
	hud.set_objective("")


func _spawn_explosion(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 260
	p.lifetime = 1.5
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.8
	pm.spread = 180.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3(0, -3.0, 0)
	pm.damping_min = 2.0
	pm.damping_max = 5.0
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 0.85, 1.0),
		Color(1.0, 0.55, 0.1, 1.0),
		Color(0.7, 0.15, 0.05, 0.8),
		Color(0.1, 0.08, 0.08, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var pmesh := SphereMesh.new()
	pmesh.radius = 0.2
	pmesh.height = 0.4
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.vertex_color_use_as_albedo = true
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.emission_enabled = true
	pmat.emission = Color(1.0, 0.5, 0.15)
	pmat.emission_energy_multiplier = 4.0
	pmesh.material = pmat
	p.draw_pass_1 = pmesh
	add_child(p)
	p.global_position = pos
	p.emitting = true

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.3)
	flash.light_energy = 25.0
	flash.omni_range = 35.0
	add_child(flash)
	flash.global_position = pos + Vector3(0, 2, 0)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 1.2)
	tw.tween_callback(flash.queue_free)

	get_tree().create_timer(3.0).timeout.connect(p.queue_free)
