class_name FaceControl
extends Node
## Webcam head/smile control. Listens for UDP packets from
## tools/face_tracker.py and exposes a virtual stick plus smile events.
## Degrades silently: `active` stays false when no tracker is sending,
## so phases can always fall back to keyboard input.

signal smile_started

const PORT := 46464
const PREVIEW_PORT := 46465
const PACKET_TIMEOUT := 0.6
const PREVIEW_TIMEOUT := 1.0

var head := Vector2.ZERO  ## -1..1; +x = head leaned right, +y = head up
var smiling := false
var active := false
var preview_texture := ImageTexture.new()  ## mirror view with tracking overlay
var preview_active := false

var _udp := PacketPeerUDP.new()
var _preview_udp := PacketPeerUDP.new()
var _last_seen := -1000.0
var _preview_seen := -1000.0
var _tracker_pid := -1


func _ready() -> void:
	if _udp.bind(PORT, "127.0.0.1") != OK:
		push_warning("FaceControl: UDP port %d busy — face control disabled" % PORT)
		set_process(false)
		return
	_preview_udp.bind(PREVIEW_PORT, "127.0.0.1")
	# Give a manually-run tracker (the reliable path on macOS, where a
	# subprocess can't get a camera-permission prompt) a moment to appear.
	# Only auto-spawn our own if nothing is already streaming.
	get_tree().create_timer(1.5).timeout.connect(_maybe_spawn_tracker)


func _maybe_spawn_tracker() -> void:
	if active:
		return  # a tracker (e.g. run_tracker.command) is already sending
	_spawn_tracker()


func _process(_delta: float) -> void:
	while _udp.get_available_packet_count() > 0:
		var data: Variant = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
		if not (data is Dictionary):
			continue
		if int(data.get("face", 0)) != 1:
			continue
		_last_seen = Time.get_ticks_msec() / 1000.0
		active = true
		head = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
		var now_smiling: bool = int(data.get("smile", 0)) == 1
		if now_smiling and not smiling:
			smile_started.emit()
		smiling = now_smiling
	if Time.get_ticks_msec() / 1000.0 - _last_seen > PACKET_TIMEOUT:
		active = false
		head = Vector2.ZERO
		smiling = false

	# camera preview: decode only the newest JPEG frame
	var jpg := PackedByteArray()
	while _preview_udp.get_available_packet_count() > 0:
		jpg = _preview_udp.get_packet()
	if jpg.size() > 0:
		var img := Image.new()
		if img.load_jpg_from_buffer(jpg) == OK:
			preview_texture.set_image(img)
			_preview_seen = Time.get_ticks_msec() / 1000.0
	preview_active = Time.get_ticks_msec() / 1000.0 - _preview_seen < PREVIEW_TIMEOUT


## Best-effort: launch the Python tracker next to the game. Any failure is
## fine — the player can run tools/face_tracker.py manually, or play WASD.
func _spawn_tracker() -> void:
	var script := ProjectSettings.globalize_path("res://tools/face_tracker.py")
	if not FileAccess.file_exists(script):
		return
	var venv_py := OS.get_environment("HOME") + "/.local/share/foguete/venv/bin/python"
	var py := venv_py if FileAccess.file_exists(venv_py) else "python3"
	if OS.get_environment("FLATPAK_ID") != "":
		# Godot itself is sandboxed; the tracker needs host python + webcam.
		_tracker_pid = OS.create_process("flatpak-spawn", ["--host", py, script])
	else:
		_tracker_pid = OS.create_process(py, [script])


func _exit_tree() -> void:
	if _tracker_pid > 0:
		OS.kill(_tracker_pid)
