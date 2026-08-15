extends Node

const WIND_STREAM := preload("res://assets/audio/ambient/wind.wav")
const CRICKETS_STREAM := preload("res://assets/audio/ambient/crickets.mp3")
const DOG_STREAMS : Array[AudioStream] = [
	preload("res://assets/audio/ambient/dogs/dog_1.wav"),
	preload("res://assets/audio/ambient/dogs/dog_2.wav")
]
const DOG_POSITIONS : Array[Vector3] = [
	Vector3(-2.0, 1.2, -23.0),
	Vector3(46.0, 1.2, -42.0),
	Vector3(-52.0, 1.2, 34.0),
	Vector3(58.0, 1.2, 28.0)
]

var _dog_player : AudioStreamPlayer3D
var _dog_timer : Timer
var _last_dog_index : int = -1
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	_random.randomize()
	_add_loop("FarmWind", WIND_STREAM, -19.0)
	_add_loop("FarmCrickets", CRICKETS_STREAM, -25.0)

	_dog_player = AudioStreamPlayer3D.new()
	_dog_player.name = "FarmDogs"
	_dog_player.volume_db = -10.0
	_dog_player.unit_size = 4.0
	_dog_player.max_distance = 90.0
	_dog_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_dog_player.panning_strength = 1.15
	add_child(_dog_player)

	_dog_timer = Timer.new()
	_dog_timer.name = "DogTimer"
	_dog_timer.one_shot = true
	_dog_timer.timeout.connect(_play_random_dog)
	add_child(_dog_timer)
	_dog_timer.start(_random.randf_range(5.0, 10.0))


func _add_loop(node_name : String, stream : AudioStream, volume_db : float) -> void:
	_configure_loop(stream)

	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.play()


func _play_random_dog() -> void:
	var dog_index : int = _random.randi_range(0, DOG_STREAMS.size() - 1)

	if DOG_STREAMS.size() > 1 and dog_index == _last_dog_index:
		dog_index = (dog_index + 1) % DOG_STREAMS.size()

	_last_dog_index = dog_index
	_dog_player.stream = DOG_STREAMS[dog_index]
	_dog_player.position = DOG_POSITIONS[
		_random.randi_range(0, DOG_POSITIONS.size() - 1)
	]
	_dog_player.pitch_scale = _random.randf_range(0.94, 1.06)
	_dog_player.play()
	_dog_timer.start(
		_dog_player.stream.get_length() + _random.randf_range(12.0, 28.0)
	)


func _configure_loop(stream : AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.mix_rate * wav.get_length())
