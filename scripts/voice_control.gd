class_name VoiceControl
extends Node
## Microphone trigger: emits `piu_detected` on short, loud, high-pitched
## bursts — say "PIU!" to fire. All in-engine (AudioEffectCapture on a
## silenced bus), no external process. Requires audio/driver/enable_input.

signal piu_detected

const BUS_NAME := "MicCapture"
const MIN_RMS := 0.02      # absolute loudness gate
const FLOOR_MULT := 4.0    # must also stand out from the ambient noise floor
const MIN_ZCR := 0.004     # zero-crossing gate: only rejects rumble/DC
const COOLDOWN := 0.25

var level := 0.0          ## smoothed 0..1 loudness, for HUD meters
var mic_alive := false    ## true while the mic is delivering frames

var _capture: AudioEffectCapture
var _floor := 0.01
var _cd := 0.0
var _last_frames := -1000.0
var _debug := false
var _debug_t := 0.0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _ready() -> void:
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUS_NAME)
		# silence the output; effects run pre-fader so capture still sees the mic
		AudioServer.set_bus_volume_db(idx, -80.0)
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
	_capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture
	if _capture == null:
		push_warning("VoiceControl: no capture effect on bus — voice fire disabled")
		set_process(false)
		return
	var mic := AudioStreamPlayer.new()
	mic.stream = AudioStreamMicrophone.new()
	mic.bus = BUS_NAME
	add_child(mic)
	mic.play()
	_debug = OS.get_environment("FOGUETE_VOICE_DEBUG") == "1"


func _process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	mic_alive = _now() - _last_frames < 1.0
	var avail := _capture.get_frames_available()
	if avail > 8192:  # stale backlog (e.g. after a stall) — drop it
		_capture.clear_buffer()
		return
	if avail < 256:
		return
	_last_frames = _now()
	var buf := _capture.get_buffer(avail)
	var sum_sq := 0.0
	var crossings := 0
	var prev := 0.0
	for v in buf:
		var s := (v.x + v.y) * 0.5
		sum_sq += s * s
		if (s > 0.0) != (prev > 0.0):
			crossings += 1
		prev = s
	var rms := sqrt(sum_sq / buf.size())
	var zcr := float(crossings) / buf.size()
	level = lerpf(level, clampf(rms * 8.0, 0.0, 1.0), 0.35)
	if _debug:
		_debug_t -= delta
		if _debug_t <= 0.0 or rms > maxf(MIN_RMS, _floor * FLOOR_MULT):
			_debug_t = 0.25
			print("[voice] rms=%.4f zcr=%.4f floor=%.4f gate=%.4f" %
				[rms, zcr, _floor, maxf(MIN_RMS, _floor * FLOOR_MULT)])
	if _cd <= 0.0 and rms > maxf(MIN_RMS, _floor * FLOOR_MULT) and zcr > MIN_ZCR:
		_cd = COOLDOWN
		if _debug:
			print("[voice] PIU! fired")
		piu_detected.emit()
	# ambient noise floor: rises slowly with sustained sound, falls fast
	_floor = lerpf(_floor, rms, 0.02 if rms > _floor else 0.1)
