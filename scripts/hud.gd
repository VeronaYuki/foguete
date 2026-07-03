class_name HUD
extends CanvasLayer

var fuel_bar: ProgressBar
var fuel_label: Label
var hspd: Label
var vspd: Label
var alt: Label
var objective: Label
var toast_label: Label
var center_box: VBoxContainer
var center_title: Label
var center_sub: Label
var landing: Label

var _toast_timer := 0.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- fuel, bottom-left ---
	var fuel_box := VBoxContainer.new()
	fuel_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	fuel_box.position = Vector2(24, -84)
	fuel_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(fuel_box)

	fuel_label = _mk_label("FUEL", 16, Color(0.7, 0.9, 1.0))
	fuel_box.add_child(fuel_label)

	fuel_bar = ProgressBar.new()
	fuel_bar.min_value = 0
	fuel_bar.max_value = 100
	fuel_bar.value = 100
	fuel_bar.show_percentage = false
	fuel_bar.custom_minimum_size = Vector2(260, 16)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.25, 1.0, 0.9)
	fill.set_corner_radius_all(4)
	fuel_bar.add_theme_stylebox_override("background", bg)
	fuel_bar.add_theme_stylebox_override("fill", fill)
	fuel_box.add_child(fuel_bar)

	# --- telemetry, bottom-right ---
	var tele := VBoxContainer.new()
	tele.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	tele.position = Vector2(-220, -110)
	root.add_child(tele)
	hspd = _mk_label("H-SPD  0.0", 17, Color.WHITE)
	vspd = _mk_label("V-SPD  0.0", 17, Color.WHITE)
	alt = _mk_label("ALT    0 m", 17, Color.WHITE)
	tele.add_child(hspd)
	tele.add_child(vspd)
	tele.add_child(alt)

	# --- objective, top-center ---
	objective = _mk_label("", 22, Color(0.85, 0.95, 1.0))
	objective.set_anchors_preset(Control.PRESET_CENTER_TOP)
	objective.position = Vector2(0, 28)
	objective.grow_horizontal = Control.GROW_DIRECTION_BOTH
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(objective)

	toast_label = _mk_label("", 20, Color(0.4, 1.0, 0.6))
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(0, 64)
	toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(toast_label)

	# --- landing assist, lower-center ---
	landing = _mk_label("", 30, Color.WHITE)
	landing.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	landing.position = Vector2(0, -150)
	landing.grow_horizontal = Control.GROW_DIRECTION_BOTH
	landing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(landing)

	# --- big center messages ---
	center_box = VBoxContainer.new()
	center_box.set_anchors_preset(Control.PRESET_CENTER)
	center_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(center_box)

	center_title = _mk_label("", 84, Color.WHITE)
	center_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(center_title)

	center_sub = _mk_label("", 22, Color(0.75, 0.8, 0.9))
	center_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(center_sub)


func _mk_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.6:
			toast_label.modulate.a = maxf(_toast_timer / 0.6, 0.0)


func set_fuel(v: float) -> void:
	fuel_bar.value = v
	var fill: StyleBoxFlat = fuel_bar.get_theme_stylebox("fill")
	fill.bg_color = Color(0.25, 1.0, 0.9) if v > 25.0 else Color(1.0, 0.35, 0.25)


func set_telemetry(h: float, v: float, altitude: float) -> void:
	hspd.text = "H-SPD  %5.1f" % h
	vspd.text = "V-SPD  %+5.1f" % v
	alt.text = "ALT   %4.0f m" % maxf(altitude, 0.0)
	var safe := absf(v) < 3.0 and h < 3.0
	vspd.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6) if safe else Color(1.0, 0.7, 0.3))


func set_objective(text: String) -> void:
	objective.text = text


func toast(text: String, color := Color(0.4, 1.0, 0.6), duration := 2.6) -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", color)
	toast_label.modulate.a = 1.0
	_toast_timer = duration


func set_landing(text: String, color: Color) -> void:
	landing.text = text
	landing.add_theme_color_override("font_color", color)


func show_center(title: String, sub: String) -> void:
	center_title.text = title
	center_sub.text = sub
	center_box.visible = true


func hide_center() -> void:
	center_box.visible = false
