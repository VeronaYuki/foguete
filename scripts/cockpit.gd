extends Control
## Phase 2 — inside the rocket. Two console puzzles, then launch.

enum SimonState { IDLE, SHOWING, INPUT, DONE }

const SIMON_COLORS: Array[Color] = [
	Color(0.9, 0.25, 0.22),
	Color(0.25, 0.85, 0.4),
	Color(0.3, 0.55, 1.0),
	Color(0.95, 0.8, 0.25),
]
const SEQ_LEN := 5
const GRID := 5
const SLOTS := 8
const INSTR_NONE := 0
const INSTR_FWD := 1
const INSTR_LEFT := 2
const INSTR_RIGHT := 3
const INSTR_CHARS := ["·", "↑", "L", "R"]
const CELL := 58

var sfx: Sfx
var rng := RandomNumberGenerator.new()

var simon_state: SimonState = SimonState.IDLE
var simon_seq: Array[int] = []
var simon_idx := 0
var simon_buttons: Array[Button] = []
var simon_done := false
var simon_status: Label

var robo_done := false
var program: Array[int] = []
var slot_buttons: Array[Button] = []
var cells: Array[Label] = []
var cell_bgs: Array[Panel] = []
var robot_pos := Vector2i(0, 4)
var robot_dir := Vector2i(1, 0)
var stars: Array[Vector2i] = [Vector2i(1, 4), Vector2i(3, 4), Vector2i(3, 2)]
var collected: Array[Vector2i] = []
var running := false
var robo_status: Label

var launch_btn: Button
var fade: ColorRect
var _launching := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rng.seed = 4242
	sfx = Sfx.new()
	add_child(sfx)
	for i in SLOTS:
		program.append(INSTR_NONE)
	_build_ui()
	_render_grid()
	get_tree().create_timer(1.2).timeout.connect(_simon_show)

	if OS.get_environment("FOGUETE_PHOTO") == "1":
		_photo.call_deferred()


func _photo() -> void:
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/Users/verona/Documents/foguete/.shots/cockpit.png")
	get_tree().quit()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.035, 0.05, 0.07)
	add_child(bg)

	# viewport strip up top — the swamp you just escaped
	var strip := ColorRect.new()
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.custom_minimum_size = Vector2(0, 110)
	strip.color = Color(0.02, 0.09, 0.07)
	add_child(strip)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	var title := _label("ONBOARD SYSTEMS  —  PRE-LAUNCH CHECK", 30, Color(0.7, 0.95, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var hint := _label("complete both consoles to enable launch      ·      R restart run", 15, Color(0.5, 0.6, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 60)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(row)

	row.add_child(_build_simon_panel())
	row.add_child(_build_robo_panel())

	launch_btn = Button.new()
	launch_btn.text = "  I G N I T E   E N G I N E S  "
	launch_btn.add_theme_font_size_override("font_size", 34)
	launch_btn.visible = false
	launch_btn.pressed.connect(_on_launch)
	_style_button(launch_btn, Color(0.75, 0.15, 0.1))
	var lb_wrap := HBoxContainer.new()
	lb_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	lb_wrap.add_child(launch_btn)
	vbox.add_child(lb_wrap)
	vbox.add_child(_spacer(30))

	fade = ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(1, 1, 1, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)


func _build_simon_panel() -> PanelContainer:
	var panel := _console_panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	var h := _label("MEMORY CALIBRATION", 22, Color(0.9, 0.95, 1.0))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	simon_status = _label("watch the sequence…", 16, Color(0.6, 0.8, 0.9))
	simon_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(simon_status)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	for i in 4:
		var b := Button.new()
		b.custom_minimum_size = Vector2(130, 130)
		_style_button(b, SIMON_COLORS[i])
		b.self_modulate = Color(0.45, 0.45, 0.45)
		var idx := i
		b.pressed.connect(func () -> void: _simon_press(idx))
		grid.add_child(b)
		simon_buttons.append(b)

	var replay := Button.new()
	replay.text = "REPLAY SEQUENCE"
	_style_button(replay, Color(0.2, 0.3, 0.4))
	replay.pressed.connect(func () -> void:
		if simon_state == SimonState.INPUT:
			_simon_show()
	)
	v.add_child(replay)
	return panel


func _build_robo_panel() -> PanelContainer:
	var panel := _console_panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var h := _label("NAV COMPUTER BOOT", 22, Color(0.9, 0.95, 1.0))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	robo_status = _label("program the probe: collect all ✦", 16, Color(0.6, 0.8, 0.9))
	robo_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(robo_status)

	var grid := GridContainer.new()
	grid.columns = GRID
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var gw := HBoxContainer.new()
	gw.alignment = BoxContainer.ALIGNMENT_CENTER
	gw.add_child(grid)
	v.add_child(gw)
	for i in GRID * GRID:
		var cell_panel := Panel.new()
		cell_panel.custom_minimum_size = Vector2(CELL, CELL)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.1, 0.14)
		sb.set_corner_radius_all(6)
		cell_panel.add_theme_stylebox_override("panel", sb)
		var l := _label("", 28, Color.WHITE)
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell_panel.add_child(l)
		grid.add_child(cell_panel)
		cells.append(l)
		cell_bgs.append(cell_panel)

	v.add_child(_label("PROGRAM  (click slots: · none → ↑ forward → L turn left → R turn right)", 14, Color(0.55, 0.65, 0.75)))
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 6)
	v.add_child(slots)
	for i in SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.text = INSTR_CHARS[INSTR_NONE]
		b.add_theme_font_size_override("font_size", 22)
		_style_button(b, Color(0.12, 0.18, 0.26))
		var idx := i
		b.pressed.connect(func () -> void: _slot_cycle(idx))
		slots.add_child(b)
		slot_buttons.append(b)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 14)
	v.add_child(btns)
	var run_b := Button.new()
	run_b.text = "▶ RUN"
	_style_button(run_b, Color(0.1, 0.4, 0.25))
	run_b.pressed.connect(_run_program)
	btns.add_child(run_b)
	var clr := Button.new()
	clr.text = "CLEAR"
	_style_button(clr, Color(0.3, 0.2, 0.15))
	clr.pressed.connect(func () -> void:
		if running:
			return
		for i in SLOTS:
			program[i] = INSTR_NONE
			slot_buttons[i].text = INSTR_CHARS[INSTR_NONE]
		_robo_reset()
	)
	btns.add_child(clr)
	return panel


func _console_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1)
	sb.border_color = Color(0.2, 0.5, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 18.0
	sb.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _style_button(b: Button, color: Color) -> void:
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color if state == "normal" else color.lightened(0.15 if state == "hover" else 0.3)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 12.0
		sb.content_margin_right = 12.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		b.add_theme_stylebox_override(state, sb)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	if Input.is_action_just_pressed("restart") and not _launching:
		Flow.goto_planet()


# ---------- SIMON ----------

func _simon_show() -> void:
	if simon_done:
		return
	if simon_seq.is_empty():
		for i in SEQ_LEN:
			simon_seq.append(rng.randi_range(0, 3))
	simon_state = SimonState.SHOWING
	simon_status.text = "watch the sequence…"
	simon_idx = 0
	_simon_play_seq.call_deferred()


func _simon_play_seq() -> void:
	await get_tree().create_timer(0.5).timeout
	for i in simon_seq:
		if not is_inside_tree():
			return
		_simon_flash(i)
		await get_tree().create_timer(0.62).timeout
	simon_state = SimonState.INPUT
	simon_status.text = "your turn — repeat it"


func _simon_flash(i: int) -> void:
	sfx.play_tone(i)
	var b := simon_buttons[i]
	b.self_modulate = Color(1.6, 1.6, 1.6)
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_property(b, "self_modulate", Color(0.45, 0.45, 0.45), 0.15)


func _simon_press(i: int) -> void:
	if simon_state != SimonState.INPUT:
		return
	_simon_flash(i)
	if i == simon_seq[simon_idx]:
		simon_idx += 1
		if simon_idx >= simon_seq.size():
			simon_done = true
			simon_state = SimonState.DONE
			simon_status.text = "✓ MEMORY CALIBRATED"
			simon_status.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
			sfx.play_chime()
			_check_launch()
	else:
		simon_state = SimonState.IDLE
		simon_status.text = "✗ wrong — watch again"
		sfx.play_hurt()
		simon_idx = 0
		get_tree().create_timer(1.0).timeout.connect(_simon_show)


# ---------- ROBOZZLE ----------

func _slot_cycle(i: int) -> void:
	if running or robo_done:
		return
	program[i] = (program[i] + 1) % 4
	slot_buttons[i].text = INSTR_CHARS[program[i]]
	sfx.play_tick()


func _robo_reset() -> void:
	robot_pos = Vector2i(0, 4)
	robot_dir = Vector2i(1, 0)
	collected.clear()
	_render_grid()


func _render_grid() -> void:
	for y in GRID:
		for x in GRID:
			var p := Vector2i(x, y)
			var l := cells[y * GRID + x]
			if p == robot_pos:
				l.text = _dir_char()
				l.add_theme_color_override("font_color", Color(0.3, 1.0, 0.9))
			elif p in stars and p not in collected:
				l.text = "✦"
				l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			elif p in collected:
				l.text = "·"
				l.add_theme_color_override("font_color", Color(0.3, 0.5, 0.4))
			else:
				l.text = ""


func _dir_char() -> String:
	if robot_dir == Vector2i(1, 0):
		return "▶"
	if robot_dir == Vector2i(-1, 0):
		return "◀"
	if robot_dir == Vector2i(0, -1):
		return "▲"
	return "▼"


func _run_program() -> void:
	if running or robo_done:
		return
	running = true
	_robo_reset()
	robo_status.text = "executing…"
	await get_tree().create_timer(0.4).timeout
	var ok := true
	for instr in program:
		if instr == INSTR_NONE:
			continue
		if not is_inside_tree():
			return
		await get_tree().create_timer(0.24).timeout
		sfx.play_tick()
		match instr:
			INSTR_FWD:
				robot_pos += robot_dir
				if robot_pos.x < 0 or robot_pos.x >= GRID or robot_pos.y < 0 or robot_pos.y >= GRID:
					ok = false
					_render_grid()
					break
				if robot_pos in stars and robot_pos not in collected:
					collected.append(robot_pos)
					sfx.play_beep()
			INSTR_LEFT:
				robot_dir = Vector2i(robot_dir.y, -robot_dir.x)
			INSTR_RIGHT:
				robot_dir = Vector2i(-robot_dir.y, robot_dir.x)
		_render_grid()
		if collected.size() == stars.size():
			break

	if ok and collected.size() == stars.size():
		robo_done = true
		robo_status.text = "✓ NAV COMPUTER ONLINE"
		robo_status.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
		sfx.play_chime()
		_check_launch()
	else:
		robo_status.text = "✗ probe lost — try again" if not ok else "✗ stars remain — try again"
		sfx.play_hurt()
		get_tree().create_timer(1.0).timeout.connect(func () -> void:
			if not robo_done:
				_robo_reset()
				robo_status.text = "program the probe: collect all ✦"
		)
	running = false


# ---------- LAUNCH ----------

func _check_launch() -> void:
	if simon_done and robo_done:
		launch_btn.visible = true
		var tw := create_tween().set_loops()
		tw.tween_property(launch_btn, "self_modulate", Color(1.5, 1.2, 1.2), 0.5)
		tw.tween_property(launch_btn, "self_modulate", Color.WHITE, 0.5)


func _on_launch() -> void:
	if _launching:
		return
	_launching = true
	sfx.set_thrust(1.0)
	sfx.play_beep()
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 1.8)
	tw.tween_callback(Flow.goto_runner)
