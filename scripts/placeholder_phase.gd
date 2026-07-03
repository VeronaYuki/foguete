extends Control
## Temporary stand-in while a phase is under construction.

@export var title := "UNDER CONSTRUCTION"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.05)
	add_child(bg)
	var l := Label.new()
	l.text = title + "\n\nthis phase is being built — press R to replay the planet"
	l.add_theme_font_size_override("font_size", 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(l)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		Flow.goto_planet()
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
