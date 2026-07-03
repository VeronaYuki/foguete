class_name Crosshair
extends Control
## Drawn crosshair, exactly centered on the screen (where hitscan rays go).


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size / 2.0
	var col := Color(1, 1, 1, 0.85)
	var gap := 5.0
	var len := 8.0
	var w := 2.0
	draw_circle(c, 1.6, col)
	draw_line(c + Vector2(gap, 0), c + Vector2(gap + len, 0), col, w)
	draw_line(c - Vector2(gap, 0), c - Vector2(gap + len, 0), col, w)
	draw_line(c + Vector2(0, gap), c + Vector2(0, gap + len), col, w)
	draw_line(c - Vector2(0, gap), c - Vector2(0, gap + len), col, w)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
