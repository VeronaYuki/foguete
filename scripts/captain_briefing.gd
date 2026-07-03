class_name CaptainBriefing
extends CanvasLayer
## Helmet-HUD comms transmission: a character radios the player, with a
## portrait, typewriter Portuguese subtitles, and a synthesized radio voice.
## Defaults to Capitão Gus; reusable for any speaker via setup().

signal finished

const GUS_LINES := [
	"Aqui é o Capitão Gus. Está me ouvindo, recruta?",
	"Seu foguete caiu no pântano de VH-9.",
	"A nave perdeu 3 peças no impacto. Recupere todas — siga as balizas âmbar.",
	"ATENÇÃO: o planeta está infestado de criaturas hostis.",
	"Se ver QUALQUER COISA parecida com o Lucas Djin... atire ou fuja. Não hesite.",
	"Instale as peças, decole e volte pra órbita. Boa sorte. Câmbio.",
]

var lines: Array = GUS_LINES
var speaker := "CAPITÃO GUS"
var portrait_path := "res://assets/gus.png"
var banner := "TRANSMISSÃO AO VIVO — CAPITÃO GUS"

var sfx: Sfx
# pacing (tunable per instance): seconds per typed char, and pause before auto-advance
var char_time := 0.03
var dwell_time := 2.4
var _line := 0
var _shown := 0
var _char_t := 0.0
var _dwell := 0.0
var _blip_t := 0.0
var _done := false

var root_ctrl: Control
var visor: ColorRect
var rec_dot: Panel
var subtitle: Label
var name_label: Label
var skip_hint: Label
var portrait: TextureRect
var _rec_blink := 0.0


func setup(p_sfx: Sfx, p_lines: Array = [], p_speaker := "", p_portrait := "", p_banner := "") -> void:
	sfx = p_sfx
	if not p_lines.is_empty():
		lines = p_lines
	if p_speaker != "":
		speaker = p_speaker
	if p_portrait != "":
		portrait_path = p_portrait
	if p_banner != "":
		banner = p_banner


func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root_ctrl = root

	# helmet visor vignette
	visor = ColorRect.new()
	visor.set_anchors_preset(Control.PRESET_FULL_RECT)
	visor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vmat := ShaderMaterial.new()
	vmat.shader = load("res://shaders/helmet_visor.gdshader")
	# Touch the uniform once so it's registered as a tweenable property (an
	# untouched shader default isn't in the material's property list yet, which
	# is why the _finish() strength-tween used to error out).
	vmat.set_shader_parameter("strength", 0.92)
	visor.material = vmat
	root.add_child(visor)

	# top transmission banner
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-170, 24)
	top.add_theme_constant_override("separation", 10)
	root.add_child(top)
	rec_dot = Panel.new()
	rec_dot.custom_minimum_size = Vector2(16, 16)
	var dot_sb := StyleBoxFlat.new()
	dot_sb.bg_color = Color(1.0, 0.2, 0.15)
	dot_sb.set_corner_radius_all(8)
	rec_dot.add_theme_stylebox_override("panel", dot_sb)
	top.add_child(rec_dot)
	top.add_child(_lbl(banner, 26, Color(0.6, 0.85, 1.0)))

	# comms panel bottom-left: portrait + name + subtitle
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.position = Vector2(0, -440)
	panel.offset_left = 40
	panel.offset_right = -40
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.03, 0.05, 0.08, 0.82)
	psb.border_color = Color(0.3, 0.6, 0.75, 0.9)
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(10)
	psb.content_margin_left = 18.0
	psb.content_margin_right = 18.0
	psb.content_margin_top = 14.0
	psb.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", psb)
	root.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)

	# portrait framed
	var frame := PanelContainer.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.1, 0.15, 0.2)
	fsb.border_color = Color(0.5, 0.75, 0.9)
	fsb.set_border_width_all(2)
	fsb.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", fsb)
	row.add_child(frame)
	portrait = TextureRect.new()
	portrait.texture = load(portrait_path)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.custom_minimum_size = Vector2(320, 384)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.add_child(portrait)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 8)
	row.add_child(text_col)
	name_label = _lbl(speaker, 36, Color(1.0, 0.8, 0.3))
	text_col.add_child(name_label)
	subtitle = _lbl("", 30, Color(0.92, 0.95, 1.0))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size = Vector2(0, 150)
	subtitle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_col.add_child(subtitle)
	skip_hint = _lbl("[ESPAÇO] avançar", 18, Color(0.5, 0.6, 0.7))
	text_col.add_child(skip_hint)

	_start_line()


func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _start_line() -> void:
	_shown = 0
	_char_t = 0.0
	_dwell = 0.0
	subtitle.text = ""
	if sfx:
		sfx.play_radio()


func _process(delta: float) -> void:
	if _done:
		return

	_rec_blink += delta * 3.0
	rec_dot.modulate.a = 0.4 + 0.6 * absf(sin(_rec_blink))

	# advance / complete current line (SPACE or E)
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("interact"):
		var full: String = lines[_line]
		if _shown < full.length():
			_shown = full.length()
			subtitle.text = full
		else:
			_next_line()
		return

	var line: String = lines[_line]
	if _shown < line.length():
		_char_t += delta
		_blip_t += delta
		while _char_t >= char_time and _shown < line.length():
			_char_t -= char_time
			_shown += 1
		subtitle.text = line.substr(0, _shown)
		if _blip_t >= 0.055 and sfx:
			_blip_t = 0.0
			var c := line.substr(maxi(_shown - 1, 0), 1)
			if c != " ":
				sfx.play_voice(randf_range(0.9, 1.25))
	else:
		_dwell += delta
		if _dwell >= dwell_time:
			_next_line()


func _next_line() -> void:
	_line += 1
	if _line >= lines.size():
		_finish()
	else:
		_start_line()


func _finish() -> void:
	if _done:
		return
	_done = true
	if sfx:
		sfx.play_radio()
	var tw := create_tween()
	tw.tween_property(visor.material, "shader_parameter/strength", 0.12, 1.0)
	tw.parallel().tween_property(root_ctrl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func () -> void:
		finished.emit()
		queue_free()
	)
