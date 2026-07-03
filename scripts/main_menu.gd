extends Control
## Campaign title + mission select. Reads progress from Flow (persisted).

var sfx: Sfx
var _stars: Array[Dictionary] = []
var _t := 0.0
var star_layer: Control


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.time_scale = 1.0
	sfx = Sfx.new()
	add_child(sfx)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()

	if OS.get_environment("FOGUETE_PHOTO_MENU") == "1":
		get_tree().create_timer(1.0).timeout.connect(func () -> void:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/Users/verona/Documents/foguete/.shots/menu.png")
			get_tree().quit()
		)


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.06)
	add_child(bg)

	# animated starfield
	star_layer = Control.new()
	star_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	star_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(star_layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 90:
		_stars.append({
			"p": Vector2(rng.randf_range(0, 1600), rng.randf_range(0, 900)),
			"r": rng.randf_range(0.6, 2.0),
			"tw": rng.randf_range(0.0, TAU),
		})
	star_layer.draw.connect(_draw_stars)

	var title := _label("FOGUETE", 96, Color(0.85, 0.95, 1.0))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(0, 70)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var sub := _label("uma campanha em 3 missões", 22, Color(0.55, 0.7, 0.85))
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(0, 178)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.position = Vector2(0, 70)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	# Continue = furthest unlocked mission
	var cont := _mk_button("CONTINUAR  ·  Missão %d — %s" % [Flow.furthest(), Flow.MISSION_NAMES[Flow.furthest()]], Color(0.15, 0.5, 0.35))
	cont.pressed.connect(func () -> void: _launch(Flow.furthest()))
	box.add_child(cont)

	box.add_child(_spacer(8))
	var pick := _label("MISSÕES", 16, Color(0.5, 0.65, 0.8))
	pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(pick)

	for m in range(1, Flow.MISSION_COUNT + 1):
		var unlocked := Flow.is_unlocked(m)
		var rec := Flow.mission_record(m)
		var label := "%d. %s" % [m, Flow.MISSION_NAMES[m]]
		if not unlocked:
			label = "🔒  " + label
		elif rec.get("cleared", false):
			var bt: float = rec.get("best_time", 0.0)
			label += "   ✓  %d:%04.1f · %d abates" % [int(bt) / 60, fmod(bt, 60.0), int(rec.get("best_kills", 0))]
		var b := _mk_button(label, Color(0.12, 0.2, 0.3) if unlocked else Color(0.1, 0.1, 0.12))
		b.disabled = not unlocked
		var idx := m
		b.pressed.connect(func () -> void: _launch(idx))
		box.add_child(b)

	# upgrades summary
	box.add_child(_spacer(10))
	var ups := PackedStringArray()
	if Flow.upgrade("gold_tooth"):
		ups.append("🦷 escova turbo")
	if int(Flow.upgrade("runner_shields")) > 0:
		ups.append("🛡 +%d escudo" % int(Flow.upgrade("runner_shields")))
	var up_text := "melhorias: " + (", ".join(ups) if ups.size() > 0 else "nenhuma ainda")
	var up_lbl := _label(up_text, 15, Color(0.7, 0.8, 0.5))
	up_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(up_lbl)

	# footer
	var foot := _label("ENTER continuar   ·   ESC sair   ·   segure BACKSPACE p/ zerar progresso", 14, Color(0.4, 0.5, 0.6))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.position = Vector2(0, -34)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(foot)


func _draw_stars() -> void:
	for s in _stars:
		var a: float = 0.4 + 0.6 * absf(sin(_t * 1.5 + s.tw))
		star_layer.draw_circle(s.p, s.r, Color(1, 1, 1, a))


func _process(delta: float) -> void:
	_t += delta
	star_layer.queue_redraw()
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	if Input.is_key_pressed(KEY_ENTER):
		_launch(Flow.furthest())
	if Input.is_key_pressed(KEY_BACKSPACE):
		Flow.reset_progress()
		get_tree().reload_current_scene()


func _launch(mission: int) -> void:
	if not Flow.is_unlocked(mission):
		return
	if sfx:
		sfx.play_beep()
	Flow.start_mission(mission)


func _mk_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = "   " + text + "   "
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(540, 46)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		var c := color
		if state == "hover":
			c = color.lightened(0.18)
		elif state == "pressed":
			c = color.lightened(0.3)
		elif state == "disabled":
			c = color.darkened(0.3)
		sb.bg_color = c
		sb.set_corner_radius_all(8)
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55))
	return b


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
