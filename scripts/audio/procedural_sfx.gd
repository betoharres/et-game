class_name ProceduralSFX
extends RefCounted

## Placeholder sound effects synthesized at runtime, so the arrival sequence
## has audio without shipping any asset. Every function returns a ready-to-play
## AudioStreamWAV; swap the calls for real files whenever they exist.

const MIX_RATE : int = 44100


## Seamlessly looping tractor-beam drone. Deliberately stationary: no glide and
## no envelope are baked in, so one buffer serves a descent, an ascent, or a
## hold of any length. Pitch and volume are shaped at playback time by
## BeamTravelAudio instead.
##
## The partials are all multiples of 0.5 Hz and the buffer is a whole number of
## seconds, so every one of them completes an integer number of cycles and the
## loop point lands on the same phase it started from.
static func beam_hum_loop() -> AudioStreamWAV:
	const LOOP_SECONDS : float = 2.0
	const CROSSFADE_SECONDS : float = 0.18
	const PARTIALS : Array[float] = [49.0, 73.5, 122.5]
	const PARTIAL_GAINS : Array[float] = [0.55, 0.22, 0.11]

	var frame_count : int = int(LOOP_SECONDS * MIX_RATE)
	var crossfade_frames : int = int(CROSSFADE_SECONDS * MIX_RATE)

	# Noise is generated past the loop end so the tail can be crossfaded back
	# over the head: white noise has no period of its own, and without this the
	# seam is an audible tick on every repeat.
	var noise : PackedFloat32Array = _filtered_noise(
		frame_count + crossfade_frames, 0.035, 91180
	)

	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(frame_count)

	for index : int in range(frame_count):
		var seconds : float = float(index) / float(MIX_RATE)

		var value : float = 0.0
		for partial : int in range(PARTIALS.size()):
			value += sin(TAU * PARTIALS[partial] * seconds) * PARTIAL_GAINS[partial]

		var noise_value : float = noise[index]
		if index < crossfade_frames:
			var blend : float = float(index) / float(crossfade_frames)
			noise_value = lerpf(noise[index + frame_count], noise[index], blend)
		value += noise_value * 0.9

		# 3 Hz over a 2 s buffer: six whole cycles, so the wobble loops too.
		var wobble : float = 0.82 + 0.18 * sin(TAU * 3.0 * seconds)
		samples[index] = clampf(value * wobble * 0.55, -1.0, 1.0)

	var stream : AudioStreamWAV = _to_stream(samples)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frame_count
	return stream


## Ground impact: a pitch-dropping body plus a short filtered noise crack.
static func landing_impact() -> AudioStreamWAV:
	var duration : float = 0.75
	var frame_count : int = int(duration * MIX_RATE)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(frame_count)

	var phase : float = 0.0
	var noise_state : float = 0.0
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 55021

	for index : int in range(frame_count):
		var progress : float = float(index) / float(frame_count)
		var frequency : float = lerpf(92.0, 34.0, sqrt(progress))
		phase += TAU * frequency / float(MIX_RATE)

		noise_state = lerpf(noise_state, rng.randf_range(-1.0, 1.0), 0.28)

		var body : float = sin(phase) * exp(-progress * 6.5)
		var crack : float = noise_state * exp(-progress * 26.0) * 0.6

		samples[index] = clampf((body + crack) * 0.9, -1.0, 1.0)

	return _to_stream(samples)


static func player_hit() -> AudioStreamWAV:
	const DURATION : float = 0.34
	var frame_count : int = int(DURATION * MIX_RATE)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(frame_count)

	var body_phase : float = 0.0
	var voice_phase : float = 0.0
	var noise : PackedFloat32Array = _filtered_noise(frame_count, 0.32, 81029)

	for index : int in range(frame_count):
		var seconds : float = float(index) / float(MIX_RATE)
		var progress : float = seconds / DURATION
		body_phase += TAU * lerpf(135.0, 48.0, sqrt(progress)) / float(MIX_RATE)
		voice_phase += TAU * lerpf(310.0, 155.0, progress) / float(MIX_RATE)

		var impact : float = (
			sin(body_phase) * exp(-seconds * 22.0) * 0.62
			+ noise[index] * exp(-seconds * 52.0) * 0.7
		)
		var voice_envelope : float = _envelope(progress, 0.1, 0.5) * exp(-progress * 3.0)
		var voice : float = (
			sin(voice_phase + sin(voice_phase * 1.47) * 0.5)
			* (0.85 + 0.15 * sin(TAU * 28.0 * seconds))
			* voice_envelope * 0.24
		)
		samples[index] = (impact + voice) * _envelope(progress, 0.008, 0.2)

	return _to_stream(samples)


## Rising whoosh for the moment the player commits to launching: a sweep that
## accelerates upward and then gets cut off by the scene swap.
static func launch_charge(duration : float = 1.1) -> AudioStreamWAV:
	var frame_count : int = int(duration * MIX_RATE)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(frame_count)

	var phase : float = 0.0
	var sub_phase : float = 0.0
	var noise_state : float = 0.0
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 40712

	for index : int in range(frame_count):
		var progress : float = float(index) / float(frame_count)
		var frequency : float = lerpf(110.0, 940.0, progress * progress * progress)
		phase += TAU * frequency / float(MIX_RATE)
		sub_phase += TAU * frequency * 0.5 / float(MIX_RATE)

		noise_state = lerpf(noise_state, rng.randf_range(-1.0, 1.0), 0.06 + progress * 0.2)

		var value : float = (
			sin(phase) * 0.42
			+ sin(sub_phase) * 0.2
			+ noise_state * (0.25 + progress * 0.55)
		)

		samples[index] = clampf(value * _envelope(progress, 0.06, 0.05) * (0.25 + progress), -1.0, 1.0)

	return _to_stream(samples)


## Hinge creak for a door swinging open or shut. Stick-slip is what makes a
## hinge sound like a hinge: the tone is chopped by an irregular tremolo, so
## the note grinds instead of humming.
static func door_creak(duration : float = 0.8) -> AudioStreamWAV:
	var frame_count : int = int(duration * MIX_RATE)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(frame_count)

	var phase : float = 0.0
	var grain_phase : float = 0.0
	var noise : PackedFloat32Array = _filtered_noise(frame_count, 0.09, 20517)

	for index : int in range(frame_count):
		var progress : float = float(index) / float(frame_count)
		var frequency : float = lerpf(232.0, 168.0, progress)
		phase += TAU * frequency / float(MIX_RATE)
		grain_phase += TAU * lerpf(26.0, 17.0, progress) / float(MIX_RATE)

		# Sawtooth-ish body: the odd partial gives the wood its rasp.
		var body : float = sin(phase) * 0.5 + sin(phase * 3.0) * 0.18
		var grain : float = 0.45 + 0.55 * absf(sin(grain_phase))
		var value : float = (body + noise[index] * 0.35) * grain

		samples[index] = clampf(value * _envelope(progress, 0.12, 0.35) * 0.7, -1.0, 1.0)

	return _to_stream(samples)


## Latch click: the bolt dropping into the strike plate, or the key turning.
static func door_latch() -> AudioStreamWAV:
	var duration : float = 0.16
	var frame_count : int = int(duration * MIX_RATE)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(frame_count)

	var phase : float = 0.0
	var noise : PackedFloat32Array = _filtered_noise(frame_count, 0.55, 77341)

	for index : int in range(frame_count):
		var progress : float = float(index) / float(frame_count)
		phase += TAU * lerpf(1450.0, 780.0, progress) / float(MIX_RATE)

		var tick : float = sin(phase) * exp(-progress * 34.0) * 0.5
		var snap : float = noise[index] * exp(-progress * 46.0) * 0.7

		samples[index] = clampf((tick + snap) * 0.9, -1.0, 1.0)

	return _to_stream(samples)


## Handle rattling against a door that will not budge: three tugs, so it reads
## as "locked" and not as a failed input.
static func door_rattle() -> AudioStreamWAV:
	const TUGS : Array[float] = [0.0, 0.17, 0.33]

	var duration : float = 0.55
	var frame_count : int = int(duration * MIX_RATE)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(frame_count)

	var noise : PackedFloat32Array = _filtered_noise(frame_count, 0.4, 31904)

	for index : int in range(frame_count):
		var seconds : float = float(index) / float(MIX_RATE)

		var value : float = 0.0
		for tug : float in TUGS:
			var since : float = seconds - tug
			if since < 0.0:
				continue
			# Two close metal partials: a knob knocking its plate, not a bell.
			var metal : float = sin(TAU * 620.0 * since) + sin(TAU * 940.0 * since) * 0.6
			value += (metal * 0.35 + noise[index] * 0.5) * exp(-since * 30.0)

		samples[index] = clampf(value * 0.8, -1.0, 1.0)

	return _to_stream(samples)


## One-pole lowpass over white noise. `smoothing` closer to 0.0 is darker.
static func _filtered_noise(
	frame_count : int,
	smoothing : float,
	seed_value : int
) -> PackedFloat32Array:
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value

	var noise : PackedFloat32Array = PackedFloat32Array()
	noise.resize(frame_count)

	var state : float = 0.0
	for index : int in range(frame_count):
		state = lerpf(state, rng.randf_range(-1.0, 1.0), smoothing)
		noise[index] = state

	return noise


static func _envelope(progress : float, attack : float, release : float) -> float:
	var attack_gain : float = clampf(progress / maxf(attack, 0.0001), 0.0, 1.0)
	var release_gain : float = clampf((1.0 - progress) / maxf(release, 0.0001), 0.0, 1.0)
	return attack_gain * release_gain


static func _to_stream(samples : PackedFloat32Array) -> AudioStreamWAV:
	var data : PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)

	for index : int in range(samples.size()):
		var value : int = int(clampf(samples[index], -1.0, 1.0) * 32767.0)
		data.encode_s16(index * 2, value)

	var stream : AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
