extends Control
## Phase 2 — hangar odonto. The tooth-ship landed damaged in the swamp;
## restore it with three dental procedures, then launch.
## Consoles: OBTURAÇÃO (amalgam shape-fit), CANAL (pipe routing to the
## root thrusters), POLIMENTO (brushing-protocol memory on the tooth itself).

enum PolishState { IDLE, SHOWING, INPUT, DONE }

const POLISH_LEN := 6

var sfx: Sfx
var rng := RandomNumberGenerator.new()

var tooth: ToothView
var fill_board: FillBoard
var canal_board: CanalBoard

var fill_done := false
var canal_done := false
var polish_done := false

var fill_status: Label
var canal_status: Label
var polish_status: Label
var hint: Label

var polish_state: PolishState = PolishState.IDLE
var polish_seq: Array[int] = []
var polish_idx := 0

var launch_btn: Button
var fade: ColorRect
var _launching := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rng.seed = 4242
	sfx = Sfx.new()
	add_child(sfx)
	_build_ui()

	if OS.get_environment("FOGUETE_PHOTO") == "1":
		_photo.call_deferred()


func _photo() -> void:
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://.shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir + "/cockpit.png")
	get_tree().quit()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.055, 0.06)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	vbox.add_child(_spacer(10))
	var title := _label("HANGAR ODONTO  —  RESTAURAÇÃO PRÉ-VOO", 30, Color(0.7, 1.0, 0.92))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	hint = _label("o pouso no pântano danificou o dente-nave — complete os 3 procedimentos      ·      R reinicia a corrida", 15, Color(0.5, 0.68, 0.62))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 46)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(row)

	row.add_child(_build_fill_panel())
	row.add_child(_build_center_column())
	row.add_child(_build_canal_panel())

	launch_btn = Button.new()
	launch_btn.text = "  D E C O L A R   C O M   F L Ú O R  "
	launch_btn.add_theme_font_size_override("font_size", 32)
	launch_btn.visible = false
	launch_btn.pressed.connect(_on_launch)
	_style_button(launch_btn, Color(0.75, 0.15, 0.1))
	var lb_wrap := HBoxContainer.new()
	lb_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	lb_wrap.add_child(launch_btn)
	vbox.add_child(lb_wrap)
	vbox.add_child(_spacer(24))

	fade = ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(1, 1, 1, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)


func _build_fill_panel() -> PanelContainer:
	var panel := _console_panel()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var h := _label("OBTURAÇÃO  —  CASCO", 22, Color(0.9, 0.98, 0.95))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	fill_status = _label("preencha as 3 cavidades do casco com amálgama", 15, Color(0.6, 0.85, 0.78))
	fill_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(fill_status)

	fill_board = FillBoard.new(rng)
	fill_board.cavity_filled.connect(_on_cavity_filled)
	fill_board.cavity_emptied.connect(func (idx: int) -> void: tooth.cavity_filled[idx] = false)
	fill_board.completed.connect(_on_fill_completed)
	fill_board.fx.connect(_on_board_fx)
	var bw := HBoxContainer.new()
	bw.alignment = BoxContainer.ALIGNMENT_CENTER
	bw.add_child(fill_board)
	v.add_child(bw)

	var legend := _label("clique numa peça da bandeja · botão direito gira\nclique numa cavidade para aplicar · clique numa peça aplicada para retirar", 13, Color(0.5, 0.62, 0.58))
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(legend)
	return panel


func _build_canal_panel() -> PanelContainer:
	var panel := _console_panel()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var h := _label("CANAL RADICULAR  —  PROPULSÃO", 22, Color(0.9, 0.98, 0.95))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	canal_status = _label("energize os canais radiculares", 15, Color(0.6, 0.85, 0.78))
	canal_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(canal_status)

	canal_board = CanalBoard.new(rng)
	canal_board.completed.connect(_on_canal_completed)
	canal_board.fx.connect(_on_board_fx)
	var bw := HBoxContainer.new()
	bw.alignment = BoxContainer.ALIGNMENT_CENTER
	bw.add_child(canal_board)
	v.add_child(bw)

	var legend := _label("clique num segmento para girar\nligue a polpa (reator) às duas raízes", 13, Color(0.5, 0.62, 0.58))
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(legend)
	return panel


func _build_center_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 6)

	tooth = ToothView.new()
	tooth.zone_clicked.connect(_on_zone_clicked)
	var tw := HBoxContainer.new()
	tw.alignment = BoxContainer.ALIGNMENT_CENTER
	tw.add_child(tooth)
	col.add_child(tw)

	var caption := _label("DENTE-NAVE  ·  VH-9", 14, Color(0.45, 0.6, 0.56))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(caption)

	var panel := _console_panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var h := _label("POLIMENTO  —  ESCUDO DE ESMALTE", 20, Color(0.9, 0.98, 0.95))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	polish_status = _label("veja o protocolo e escove as zonas na ordem", 15, Color(0.6, 0.85, 0.78))
	polish_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(polish_status)
	var btn := Button.new()
	btn.text = "▶ VER PROTOCOLO"
	_style_button(btn, Color(0.14, 0.32, 0.28))
	btn.pressed.connect(_polish_show)
	var bw := HBoxContainer.new()
	bw.alignment = BoxContainer.ALIGNMENT_CENTER
	bw.add_child(btn)
	v.add_child(bw)
	col.add_child(panel)
	return col


func _console_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.075, 0.075)
	sb.border_color = Color(0.25, 0.6, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 16.0
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


# ---------- console feedback ----------

func _on_board_fx(kind: String) -> void:
	match kind:
		"tick":
			sfx.play_tick()
		"place":
			sfx.play_beep()
		"remove":
			sfx.play_tick()


func _on_cavity_filled(idx: int) -> void:
	tooth.cavity_filled[idx] = true
	sfx.play_tone(idx)


func _on_fill_completed() -> void:
	fill_done = true
	fill_status.text = "✓ CASCO OBTURADO"
	fill_status.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	sfx.play_chime()
	_check_launch()


func _on_canal_completed() -> void:
	canal_done = true
	tooth.canal_on = true
	canal_status.text = "✓ REATOR LIGADO ÀS RAÍZES"
	canal_status.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	sfx.play_chime()
	_check_launch()


# ---------- POLIMENTO (brushing protocol on the tooth) ----------

func _polish_show() -> void:
	if polish_done or polish_state == PolishState.SHOWING:
		return
	if polish_seq.is_empty():
		for i in POLISH_LEN:
			polish_seq.append(rng.randi_range(0, 3))
	polish_state = PolishState.SHOWING
	tooth.show_zones = true
	polish_status.text = "observe o protocolo…"
	polish_idx = 0
	_polish_play.call_deferred()


func _polish_play() -> void:
	await get_tree().create_timer(0.6).timeout
	for z in polish_seq:
		if not is_inside_tree():
			return
		tooth.flash(z)
		sfx.play_tone(z)
		await get_tree().create_timer(0.62).timeout
	polish_state = PolishState.INPUT
	polish_status.text = "sua vez — escove na mesma ordem"


func _on_zone_clicked(z: int) -> void:
	if polish_state != PolishState.INPUT:
		return
	tooth.flash(z)
	sfx.play_drill(0.85 + z * 0.12)
	if z == polish_seq[polish_idx]:
		polish_idx += 1
		if polish_idx >= polish_seq.size():
			polish_done = true
			polish_state = PolishState.DONE
			tooth.polished = true
			tooth.show_zones = false
			polish_status.text = "✓ ESMALTE POLIDO — escudo térmico ativo"
			polish_status.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
			sfx.play_chime()
			_check_launch()
	else:
		polish_state = PolishState.IDLE
		polish_status.text = "✗ zona sensível! observe o protocolo de novo"
		sfx.play_hurt()
		polish_idx = 0
		get_tree().create_timer(1.2).timeout.connect(_polish_show)


# ---------- LAUNCH ----------

func _check_launch() -> void:
	if fill_done and canal_done and polish_done:
		tooth.restored = true
		hint.text = "✓ DENTE-NAVE RESTAURADO — pronto para decolar"
		hint.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
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


# ==================================================================
# ToothView — cross-section of the molar-ship, repaired live as the
# three procedures complete. Also the click surface for POLIMENTO.
# ==================================================================

class ToothView extends Control:
	signal zone_clicked(zone: int)

	const ZONES := [Vector2(120, 95), Vector2(240, 95), Vector2(120, 180), Vector2(240, 180)]
	const CAVS := [Vector2(125, 92), Vector2(243, 104), Vector2(168, 190)]
	const CAV_R := [17.0, 15.0, 13.0]
	const GRIME := [Vector2(100, 125), Vector2(152, 68), Vector2(210, 130), Vector2(262, 96), Vector2(142, 152), Vector2(228, 182)]
	const SPARKLES := [Vector2(100, 70), Vector2(255, 75), Vector2(90, 170)]

	var cavity_filled := [false, false, false]
	var canal_on := false
	var polished := false
	var restored := false
	var show_zones := false
	var flash_zone := -1
	var flash_a := 0.0
	var t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(360, 420)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func flash(zone: int) -> void:
		flash_zone = zone
		flash_a = 1.0

	func _process(delta: float) -> void:
		t += delta
		flash_a = maxf(0.0, flash_a - delta * 2.5)
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var best := -1
			var best_d := 62.0
			for i in ZONES.size():
				var d: float = event.position.distance_to(ZONES[i])
				if d < best_d:
					best_d = d
					best = i
			if best >= 0:
				zone_clicked.emit(best)

	func _outline() -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(95, 220), Vector2(72, 190), Vector2(62, 140), Vector2(70, 92),
			Vector2(92, 58), Vector2(118, 48), Vector2(142, 62), Vector2(165, 74),
			Vector2(180, 78), Vector2(195, 74), Vector2(218, 62), Vector2(242, 48),
			Vector2(268, 58), Vector2(290, 92), Vector2(298, 140), Vector2(288, 190),
			Vector2(265, 220),
			Vector2(258, 250), Vector2(252, 300), Vector2(240, 355), Vector2(228, 385),
			Vector2(214, 350), Vector2(210, 300), Vector2(206, 262),
			Vector2(180, 245), Vector2(154, 262), Vector2(150, 300), Vector2(146, 350),
			Vector2(132, 385), Vector2(120, 355), Vector2(108, 300), Vector2(102, 250),
		])

	func _canal_pts(side: int) -> PackedVector2Array:
		if side == 0:
			return PackedVector2Array([Vector2(172, 176), Vector2(160, 225), Vector2(148, 290), Vector2(138, 350), Vector2(132, 376)])
		return PackedVector2Array([Vector2(188, 176), Vector2(200, 225), Vector2(212, 290), Vector2(222, 350), Vector2(228, 376)])

	static func _along(pts: PackedVector2Array, f: float) -> Vector2:
		var total := 0.0
		for i in pts.size() - 1:
			total += pts[i].distance_to(pts[i + 1])
		var d := f * total
		for i in pts.size() - 1:
			var seg := pts[i].distance_to(pts[i + 1])
			if d <= seg:
				return pts[i].lerp(pts[i + 1], d / maxf(seg, 0.001))
			d -= seg
		return pts[pts.size() - 1]

	func _blob(c: Vector2, r: float, col: Color) -> void:
		draw_circle(c, r, col)
		draw_circle(c + Vector2(r * 0.5, -r * 0.3), r * 0.7, col)
		draw_circle(c + Vector2(-r * 0.5, r * 0.35), r * 0.6, col)

	func _draw() -> void:
		var pts := _outline()

		# enamel body
		var enamel := Color(0.93, 0.94, 0.9) if polished else Color(0.78, 0.77, 0.68)
		draw_polygon(pts, PackedColorArray([enamel]))

		# swamp grime, scrubbed away by polishing
		if not polished:
			for g in GRIME:
				_blob(g, 12.0, Color(0.32, 0.38, 0.2, 0.45))

		# root canals (energy conduits): dim when broken, flowing when on
		for side in 2:
			var cp := _canal_pts(side)
			if canal_on:
				draw_polyline(cp, Color(0.15, 0.7, 0.62, 0.35), 9.0, true)
				draw_polyline(cp, Color(0.25, 0.95, 0.85), 4.0, true)
				for k in 3:
					var f := fmod(t * 0.45 + float(k) / 3.0, 1.0)
					draw_circle(_along(cp, f), 4.5, Color(0.8, 1.0, 0.95))
			else:
				draw_polyline(cp, Color(0.4, 0.38, 0.34), 4.0, true)

		# pulp chamber = reactor behind a porthole
		var core := Color(0.25, 0.95, 0.85) if canal_on else Color(0.3, 0.28, 0.33)
		if canal_on:
			var pulse := 0.75 + 0.25 * sin(t * 3.0)
			draw_circle(Vector2(180, 140), 30.0, Color(0.2, 0.9, 0.8, 0.18 * pulse))
			core = core * pulse
			core.a = 1.0
		draw_circle(Vector2(180, 140), 24.0, Color(0.06, 0.09, 0.1))
		draw_circle(Vector2(180, 140), 17.0, core)
		draw_arc(Vector2(180, 140), 25.0, 0, TAU, 40, Color(0.35, 0.42, 0.45), 3.0, true)

		# cavities on the crown, filled with amalgam by OBTURAÇÃO
		for i in CAVS.size():
			if cavity_filled[i]:
				_blob(CAVS[i], CAV_R[i], Color(0.72, 0.76, 0.82))
				draw_circle(CAVS[i] + Vector2(-CAV_R[i] * 0.3, -CAV_R[i] * 0.3), CAV_R[i] * 0.25, Color(1, 1, 1, 0.6))
			else:
				_blob(CAVS[i], CAV_R[i], Color(0.14, 0.09, 0.06))

		# shine + sparkles once polished
		if polished:
			draw_line(Vector2(103, 78), Vector2(140, 60), Color(1, 1, 1, 0.4), 7.0, true)
			draw_line(Vector2(96, 100), Vector2(112, 90), Color(1, 1, 1, 0.3), 5.0, true)
			for i in SPARKLES.size():
				var p := 0.5 + 0.5 * sin(t * 3.0 + i * 2.1)
				var s: Vector2 = SPARKLES[i]
				var r := 4.0 + 7.0 * p
				var col := Color(1, 1, 0.9, 0.9 * p)
				draw_line(s + Vector2(-r, 0), s + Vector2(r, 0), col, 2.0, true)
				draw_line(s + Vector2(0, -r), s + Vector2(0, r), col, 2.0, true)

		# antenna mast in the central fossa
		draw_line(Vector2(180, 76), Vector2(180, 38), Color(0.4, 0.44, 0.46), 3.0, true)
		var blink := 1.0 if fmod(t, 0.8) < 0.4 else 0.25
		draw_circle(Vector2(180, 34), 4.0, Color(1.0, 0.25, 0.2, blink))

		# thruster nozzles at the root tips
		for side in 2:
			var tip := Vector2(132, 385) if side == 0 else Vector2(228, 385)
			draw_polygon(PackedVector2Array([
				tip + Vector2(-8, 3), tip + Vector2(8, 3),
				tip + Vector2(13, 21), tip + Vector2(-13, 21),
			]), PackedColorArray([Color(0.25, 0.27, 0.3)]))
			if canal_on:
				var fp := 0.6 + 0.4 * sin(t * 7.0 + side * 2.0)
				draw_circle(tip + Vector2(0, 26), 4.0 + 3.0 * fp, Color(1.0, 0.6, 0.2, 0.5 * fp))

		# brushing zone rings + flash
		if show_zones:
			for i in ZONES.size():
				draw_arc(ZONES[i], 48.0, 0, TAU, 40, Color(1, 1, 1, 0.16), 2.0, true)
		if flash_zone >= 0 and flash_a > 0.0:
			var z: Vector2 = ZONES[flash_zone]
			draw_circle(z, 52.0, Color(0.6, 1.0, 0.95, 0.4 * flash_a))
			draw_arc(z, 52.0, 0, TAU, 40, Color(1, 1, 1, 0.7 * flash_a), 3.0, true)

		# outline (+ glow once fully restored)
		var closed := pts.duplicate()
		closed.append(pts[0])
		if restored:
			draw_polyline(closed, Color(0.3, 1.0, 0.85, 0.25 + 0.15 * sin(t * 2.0)), 9.0, true)
		draw_polyline(closed, Color(0.1, 0.12, 0.14), 3.0, true)


# ==================================================================
# FillBoard — OBTURAÇÃO. Hull section with 3 cavities; fit the amalgam
# polyominoes exactly. Cavities are built from the solution placements,
# so the puzzle is always solvable.
# ==================================================================

class FillBoard extends Control:
	signal cavity_filled(idx: int)
	signal cavity_emptied(idx: int)
	signal completed
	signal fx(kind: String)

	const GW := 7
	const GH := 6
	const CELL := 46
	const TRAY_CELL := 20
	const TRAY_Y := GH * CELL + 14

	var pieces: Array[Dictionary] = []
	var cavity_cells := {}          # Vector2i -> cavity idx
	var occupied := {}              # Vector2i -> piece idx
	var cav_done := [false, false, false]
	var selected := -1
	var hover := Vector2i(-99, -99)
	var done := false
	var tray_rects: Array[Rect2] = []

	func _init(rng: RandomNumberGenerator) -> void:
		custom_minimum_size = Vector2(GW * CELL, TRAY_Y + 92)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_exited.connect(func () -> void:
			hover = Vector2i(-99, -99)
			queue_redraw()
		)
		var defs := [
			{ "shape": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)], "pos": Vector2i(1, 1), "cav": 0 },
			{ "shape": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)], "pos": Vector2i(2, 1), "cav": 0 },
			{ "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)], "pos": Vector2i(4, 0), "cav": 1 },
			{ "shape": [Vector2i(0, 0), Vector2i(0, 1)], "pos": Vector2i(6, 1), "cav": 1 },
			{ "shape": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)], "pos": Vector2i(3, 4), "cav": 2 },
			{ "shape": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)], "pos": Vector2i(2, 3), "cav": 2 },
		]
		for d in defs:
			for c in d.shape:
				cavity_cells[d.pos + c] = d.cav
			pieces.append({ "shape": d.shape, "rot": rng.randi_range(0, 3), "placed": false, "at": Vector2i.ZERO })
		for i in range(pieces.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := pieces[i]
			pieces[i] = pieces[j]
			pieces[j] = tmp
		tray_rects.resize(pieces.size())

	static func _rot_cells(shape: Array, r: int) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for c in shape:
			var v: Vector2i = c
			for k in r % 4:
				v = Vector2i(-v.y, v.x)
			out.append(v)
		var mn := Vector2i(9999, 9999)
		for v in out:
			mn = Vector2i(mini(mn.x, v.x), mini(mn.y, v.y))
		for i in out.size():
			out[i] -= mn
		return out

	func _cell_at(pos: Vector2) -> Vector2i:
		var c := Vector2i(int(pos.x / CELL), int(pos.y / CELL))
		if pos.x < 0 or pos.y < 0 or c.x >= GW or c.y >= GH:
			return Vector2i(-99, -99)
		return c

	func _can_place(pi: int, base: Vector2i) -> bool:
		for v in _rot_cells(pieces[pi].shape, pieces[pi].rot):
			var p: Vector2i = base + v
			if not cavity_cells.has(p) or occupied.has(p):
				return false
		return true

	func _place(pi: int, base: Vector2i) -> void:
		for v in _rot_cells(pieces[pi].shape, pieces[pi].rot):
			occupied[base + v] = pi
		pieces[pi].placed = true
		pieces[pi].at = base
		selected = -1
		fx.emit("place")
		for cav in 3:
			if cav_done[cav]:
				continue
			var full := true
			for cell in cavity_cells:
				if cavity_cells[cell] == cav and not occupied.has(cell):
					full = false
					break
			if full:
				cav_done[cav] = true
				cavity_filled.emit(cav)
		if occupied.size() == cavity_cells.size():
			done = true
			completed.emit()
		queue_redraw()

	func _clear_piece(pi: int) -> void:
		for cell in occupied.keys():
			if occupied[cell] == pi:
				occupied.erase(cell)
		pieces[pi].placed = false
		for cav in 3:
			if not cav_done[cav]:
				continue
			for cell in cavity_cells:
				if cavity_cells[cell] == cav and not occupied.has(cell):
					cav_done[cav] = false
					cavity_emptied.emit(cav)
					break

	func _gui_input(event: InputEvent) -> void:
		if done:
			return
		if event is InputEventMouseMotion:
			var c := _cell_at(event.position)
			if c != hover:
				hover = c
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				if selected >= 0:
					pieces[selected].rot = (pieces[selected].rot + 1) % 4
					fx.emit("tick")
					queue_redraw()
			elif event.button_index == MOUSE_BUTTON_LEFT:
				for i in pieces.size():
					if not pieces[i].placed and tray_rects[i].has_point(event.position):
						selected = i
						fx.emit("tick")
						queue_redraw()
						return
				var c := _cell_at(event.position)
				if c.x < 0:
					return
				if occupied.has(c):
					var pi: int = occupied[c]
					_clear_piece(pi)
					selected = pi
					fx.emit("remove")
					queue_redraw()
					return
				if selected >= 0 and _can_place(selected, c):
					_place(selected, c)

	func _draw() -> void:
		for y in GH:
			for x in GW:
				var p := Vector2i(x, y)
				var rect := Rect2(x * CELL + 1, y * CELL + 1, CELL - 2, CELL - 2)
				if occupied.has(p):
					draw_rect(rect, Color(0.72, 0.76, 0.8))
					draw_line(rect.position + Vector2(3, 3), rect.position + Vector2(rect.size.x - 3, 3), Color(1, 1, 1, 0.5), 2.0)
				elif cavity_cells.has(p):
					draw_rect(rect, Color(0.1, 0.06, 0.045))
					draw_rect(rect, Color(0.45, 0.3, 0.2), false, 2.0)
				else:
					draw_rect(rect, Color(0.16, 0.2, 0.24))

		# ghost preview of the selected piece
		if selected >= 0 and hover.x >= 0:
			var ok := _can_place(selected, hover)
			var col := Color(0.3, 1.0, 0.6, 0.4) if ok else Color(1.0, 0.3, 0.25, 0.4)
			for v in _rot_cells(pieces[selected].shape, pieces[selected].rot):
				var p: Vector2i = hover + v
				if p.x >= 0 and p.x < GW and p.y >= 0 and p.y < GH:
					draw_rect(Rect2(p.x * CELL + 1, p.y * CELL + 1, CELL - 2, CELL - 2), col)

		# amalgam tray
		var x := 4.0
		for i in pieces.size():
			if pieces[i].placed:
				tray_rects[i] = Rect2()
				continue
			var cells := _rot_cells(pieces[i].shape, pieces[i].rot)
			var mx := 0
			var my := 0
			for v in cells:
				mx = maxi(mx, v.x)
				my = maxi(my, v.y)
			tray_rects[i] = Rect2(x - 4, TRAY_Y + 4, (mx + 1) * TRAY_CELL + 8, (my + 1) * TRAY_CELL + 8)
			for v in cells:
				draw_rect(Rect2(x + v.x * TRAY_CELL, TRAY_Y + 8 + v.y * TRAY_CELL, TRAY_CELL - 2, TRAY_CELL - 2), Color(0.7, 0.74, 0.8))
			if i == selected:
				draw_rect(tray_rects[i], Color(0.3, 1.0, 0.85), false, 2.0)
			x += (mx + 1) * TRAY_CELL + 18


# ==================================================================
# CanalBoard — CANAL RADICULAR. Rotate the canal segments so energy
# flows from the pulp reactor down to both root thrusters.
# ==================================================================

class CanalBoard extends Control:
	signal completed
	signal fx(kind: String)

	const N := 5
	const CELL := 54
	const TOP := 44
	const BOT := 50
	# tile types: -1 solid dentin, 0 straight (N+S), 1 elbow (N+E), 2 tee (N+E+W)
	const BASE_MASK := { 0: 5, 1: 3, 2: 11 }
	const LAYOUT := [
		[1, 0, 0, 2, 1],
		[0, 1, 2, 1, 2],
		[1, 0, 2, 0, 0],
		[-1, 0, 1, 0, -1],
		[1, 0, 2, 0, 0],
	]
	const SRC := Vector2i(2, 0)
	const SINKS := [Vector2i(1, 4), Vector2i(3, 4)]
	const DIRS := [
		{ "v": Vector2i(0, -1), "b": 1, "ob": 4 },
		{ "v": Vector2i(1, 0), "b": 2, "ob": 8 },
		{ "v": Vector2i(0, 1), "b": 4, "ob": 1 },
		{ "v": Vector2i(-1, 0), "b": 8, "ob": 2 },
	]

	var rots := []
	var energized := {}
	var done := false
	var t := 0.0

	func _init(rng: RandomNumberGenerator) -> void:
		custom_minimum_size = Vector2(N * CELL, TOP + N * CELL + BOT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		for y in N:
			var row := []
			for x in N:
				row.append(rng.randi_range(0, 3) if LAYOUT[y][x] >= 0 else 0)
			rots.append(row)
		_flow()
		if _solved():
			rots[SRC.y][SRC.x] = (rots[SRC.y][SRC.x] + 1) % 4
			_flow()

	func _mask(x: int, y: int) -> int:
		var tpe: int = LAYOUT[y][x]
		if tpe < 0:
			return 0
		var m: int = BASE_MASK[tpe]
		var r: int = rots[y][x]
		return ((m << r) | (m >> (4 - r))) & 15

	func _flow() -> void:
		energized.clear()
		if (_mask(SRC.x, SRC.y) & 1) == 0:
			queue_redraw()
			return
		var stack: Array[Vector2i] = [SRC]
		energized[SRC] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			var m := _mask(c.x, c.y)
			for d in DIRS:
				if (m & d.b) == 0:
					continue
				var nb: Vector2i = c + d.v
				if nb.x < 0 or nb.x >= N or nb.y < 0 or nb.y >= N:
					continue
				if energized.has(nb):
					continue
				if (_mask(nb.x, nb.y) & d.ob) == 0:
					continue
				energized[nb] = true
				stack.append(nb)
		queue_redraw()

	func _solved() -> bool:
		for s in SINKS:
			if not energized.has(s) or (_mask(s.x, s.y) & 4) == 0:
				return false
		return true

	func _gui_input(event: InputEvent) -> void:
		if done:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var c := Vector2i(int(event.position.x / CELL), int((event.position.y - TOP) / CELL))
			if event.position.y < TOP or c.x < 0 or c.x >= N or c.y < 0 or c.y >= N:
				return
			if LAYOUT[c.y][c.x] < 0:
				return
			rots[c.y][c.x] = (rots[c.y][c.x] + 1) % 4
			fx.emit("tick")
			_flow()
			if _solved():
				done = true
				completed.emit()

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var src_x := SRC.x * CELL + CELL * 0.5

		# pulp reactor feeding the grid from above
		var pulse := 0.75 + 0.25 * sin(t * 3.0)
		draw_circle(Vector2(src_x, 18), 12.0, Color(0.25, 0.95, 0.85) * pulse)
		draw_arc(Vector2(src_x, 18), 15.0, 0, TAU, 30, Color(0.35, 0.5, 0.5), 2.0, true)
		draw_line(Vector2(src_x, 30), Vector2(src_x, TOP), Color(0.25, 0.95, 0.85), 8.0)
		draw_string(font, Vector2(src_x + 24, 24), "POLPA / REATOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.65, 0.6))

		for y in N:
			for x in N:
				var rect := Rect2(x * CELL + 2, TOP + y * CELL + 2, CELL - 4, CELL - 4)
				if LAYOUT[y][x] < 0:
					draw_rect(rect, Color(0.09, 0.08, 0.07))
					for k in 4:
						draw_circle(rect.position + Vector2(10 + (k % 2) * 24, 12 + (k / 2) * 22), 2.0, Color(0.18, 0.15, 0.12))
					continue
				draw_rect(rect, Color(0.07, 0.1, 0.11))
				var m := _mask(x, y)
				var center := rect.get_center()
				var on: bool = energized.has(Vector2i(x, y))
				var col := Color(0.25, 0.95, 0.85) if on else Color(0.35, 0.4, 0.44)
				for d in DIRS:
					if (m & d.b) == 0:
						continue
					var edge := center + Vector2(d.v) * (CELL * 0.5 - 2.0)
					if on:
						draw_line(center, edge, Color(0.15, 0.7, 0.62, 0.3), 15.0)
					draw_line(center, edge, col, 8.0)
				draw_circle(center, 6.0, col)

		# root thrusters below the grid
		for i in SINKS.size():
			var s: Vector2i = SINKS[i]
			var cx := s.x * CELL + CELL * 0.5
			var gy := TOP + N * CELL
			var lit: bool = done and energized.has(s)
			var col := Color(0.25, 0.95, 0.85) if lit else Color(0.35, 0.4, 0.44)
			draw_line(Vector2(cx, gy), Vector2(cx, gy + 10), col, 8.0)
			draw_polygon(PackedVector2Array([
				Vector2(cx - 9, gy + 10), Vector2(cx + 9, gy + 10),
				Vector2(cx + 14, gy + 30), Vector2(cx - 14, gy + 30),
			]), PackedColorArray([Color(0.25, 0.27, 0.3)]))
			if lit:
				var fp := 0.6 + 0.4 * sin(t * 7.0 + i * 2.0)
				draw_circle(Vector2(cx, gy + 36), 4.0 + 3.0 * fp, Color(1.0, 0.6, 0.2, 0.5 * fp))
			draw_string(font, Vector2(cx - 22, gy + 46), "RAIZ %s" % ("E" if i == 0 else "D"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.65, 0.6))
