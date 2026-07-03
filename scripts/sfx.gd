class_name Sfx
extends Node
## All audio is synthesized at startup — no asset files needed.

const RATE := 22050

var thruster: AudioStreamPlayer
var drone: AudioStreamPlayer
var boom: AudioStreamPlayer
var chime: AudioStreamPlayer
var beep: AudioStreamPlayer
var laser: AudioStreamPlayer
var laser2: AudioStreamPlayer
var hurt: AudioStreamPlayer
var screech: AudioStreamPlayer
var splat: AudioStreamPlayer
var tones: Array[AudioStreamPlayer] = []
var tick: AudioStreamPlayer
var voice: AudioStreamPlayer
var radio: AudioStreamPlayer


func _ready() -> void:
	thruster = _mk_player(_gen_thruster(), -60.0, true)
	drone = _mk_player(_gen_drone(), -16.0, true)
	boom = _mk_player(_gen_explosion(), -2.0, false)
	chime = _mk_player(_gen_chime(), -6.0, false)
	beep = _mk_player(_gen_beep(), -10.0, false)
	laser = _mk_player(_gen_laser(1400.0, 250.0, 0.16), -8.0, false)
	laser2 = _mk_player(_gen_laser(700.0, 150.0, 0.22), -10.0, false)
	hurt = _mk_player(_gen_hurt(), -4.0, false)
	screech = _mk_player(_gen_screech(), -6.0, false)
	splat = _mk_player(_gen_splat(), -6.0, false)
	var freqs := [329.63, 392.0, 493.88, 587.33]
	for f in freqs:
		tones.append(_mk_player(_gen_tone(f), -8.0, false))
	tick = _mk_player(_gen_tone(1200.0, 0.06), -14.0, false)
	voice = _mk_player(_gen_voice_blip(), -13.0, false)
	radio = _mk_player(_gen_radio_crackle(), -12.0, false)
	thruster.play()
	drone.play()


func set_thrust(level: float) -> void:
	if level < 0.02:
		thruster.volume_db = -60.0
	else:
		thruster.volume_db = linear_to_db(clampf(level, 0.0, 1.0)) - 4.0
		thruster.pitch_scale = 0.9 + level * 0.25


func play_explosion() -> void:
	boom.play()


func play_chime() -> void:
	chime.play()


func play_beep() -> void:
	beep.play()


func play_laser() -> void:
	laser.play()


func play_enemy_laser() -> void:
	laser2.play()


func play_hurt() -> void:
	hurt.play()


func play_screech() -> void:
	screech.play()


func play_splat() -> void:
	splat.play()


func play_tone(i: int) -> void:
	tones[clampi(i, 0, tones.size() - 1)].play()


func play_tick() -> void:
	tick.play()


func play_voice(pitch: float) -> void:
	voice.pitch_scale = pitch
	voice.play()


func play_radio() -> void:
	radio.play()


func _mk_player(stream: AudioStream, vol_db: float, _loop: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	return p


func _make_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _gen_thruster() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var n := RATE * 2
	var fade := int(RATE * 0.15)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var v := 0.0
	var lp := 0.0
	for i in n + fade:
		v = clampf(v + rng.randf_range(-0.14, 0.14), -1.0, 1.0)
		lp += (v - lp) * 0.18
		raw[i] = lp * 0.9
	# crossfade tail into head for a seamless loop
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i]
	for i in fade:
		var t := float(i) / fade
		out[i] = raw[n + i] * (1.0 - t) + raw[i] * t
	return _make_wav(out, true)


func _gen_drone() -> AudioStreamWAV:
	var n := RATE * 4
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var lfo := 0.6 + 0.4 * sin(TAU * 0.25 * t)
		var s := sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 82.5 * t) * 0.3 + sin(TAU * 110.0 * t) * 0.2
		out[i] = s * lfo * 0.35
	return _make_wav(out, true)


func _gen_explosion() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise_s := rng.randf_range(-1.0, 1.0)
		lp += (noise_s - lp) * clampf(0.4 - t * 0.18, 0.05, 0.4)
		var s := lp * exp(-3.0 * t) + sin(TAU * 45.0 * t) * 0.7 * exp(-2.0 * t)
		out[i] = clampf(s * 1.4, -1.0, 1.0)
	return _make_wav(out, false)


func _gen_chime() -> AudioStreamWAV:
	var notes := [523.25, 659.25, 783.99]
	var n := int(RATE * 1.4)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in notes.size():
		var start := int(k * RATE * 0.14)
		for i in range(start, n):
			var t := float(i - start) / RATE
			out[i] += sin(TAU * notes[k] * t) * 0.28 * exp(-2.5 * t)
	return _make_wav(out, false)


func _gen_laser(f_start: float, f_end: float, dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f_start, f_end, t * t)
		phase += TAU * f / RATE
		out[i] = (sin(phase) * 0.7 + sin(phase * 2.0) * 0.2) * (1.0 - t) * 0.6
	return _make_wav(out, false)


func _gen_hurt() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var n := int(RATE * 0.28)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (sin(TAU * 85.0 * t) * 0.8 + rng.randf_range(-0.25, 0.25)) * exp(-9.0 * t)
	return _make_wav(out, false)


func _gen_screech() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 666
	var n := int(RATE * 0.7)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := minf(t * 12.0, 1.0) * exp(-2.8 * t)
		var f := 300.0 + 500.0 * sin(TAU * 3.0 * t) + sin(TAU * 31.0 * t) * 90.0
		phase += TAU * f / RATE
		out[i] = (sin(phase) * 0.6 + rng.randf_range(-0.3, 0.3)) * env
	return _make_wav(out, false)


func _gen_splat() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.12
		out[i] = lp * 1.6 * exp(-14.0 * t)
	return _make_wav(out, false)


func _gen_voice_blip() -> AudioStreamWAV:
	# short buzzy blip per character — reads as radio speech
	var n := int(RATE * 0.07)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(t * 30.0, 1.0) * exp(-16.0 * t)
		# square-ish formant for a vocal buzz
		var s := signf(sin(TAU * 220.0 * t)) * 0.4 + sin(TAU * 440.0 * t) * 0.3
		out[i] = s * env * 0.5
	return _make_wav(out, false)


func _gen_radio_crackle() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2020
	var n := int(RATE * 0.4)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-6.0 * t) + 0.3 * exp(-1.5 * t)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.5
		out[i] = lp * env * 0.5
	return _make_wav(out, false)


func _gen_tone(freq: float, dur := 0.35) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * freq * t) * 0.35 * minf(t * 40.0, 1.0) * exp(-4.0 * t)
	return _make_wav(out, false)


func _gen_beep() -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 880.0 * t) * 0.3 * (1.0 - t / 0.12)
	return _make_wav(out, false)
