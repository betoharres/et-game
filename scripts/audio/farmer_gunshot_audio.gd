extends AudioStreamPlayer3D

const SAMPLE_RATE : int = 22050
const SHOT_DURATION : float = 0.32


func _ready() -> void:
	stream = _create_gunshot_stream()


func play_shot() -> void:
	play()


func _create_gunshot_stream() -> AudioStreamWAV:
	var frame_count : int = roundi(SAMPLE_RATE * SHOT_DURATION)
	var audio_data := PackedByteArray()
	audio_data.resize(frame_count * 2)

	var random := RandomNumberGenerator.new()
	random.seed = 73921

	for frame in range(frame_count):
		var time : float = float(frame) / float(SAMPLE_RATE)
		var progress : float = time / SHOT_DURATION
		var crack_envelope : float = exp(-time * 34.0)
		var body_envelope : float = exp(-time * 11.0)
		var noise : float = random.randf_range(-1.0, 1.0)
		var low_body : float = sin(TAU * (92.0 - 45.0 * progress) * time)
		var sample : float = (
			noise * crack_envelope * 0.78
			+ low_body * body_envelope * 0.48
		)
		sample = clampf(sample, -1.0, 1.0)
		audio_data.encode_s16(frame * 2, roundi(sample * 32767.0))

	var shot_stream := AudioStreamWAV.new()
	shot_stream.format = AudioStreamWAV.FORMAT_16_BITS
	shot_stream.mix_rate = SAMPLE_RATE
	shot_stream.stereo = false
	shot_stream.data = audio_data
	return shot_stream
