extends Node

const WIND_STREAM : Resource = preload("res://assets/audio/ambient/wind.wav")
const CRICKETS_STREAM := preload("res://assets/audio/ambient/crickets.mp3")
const BACKGROUND_MUSIC_STREAM : AudioStreamMP3 = preload("res://assets/audio/ambient/background-music.mp3")
const PURSUIT_MUSIC_STREAM : AudioStreamMP3 = preload("res://assets/audio/ambient/Pursuit.mp3")
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

@export_range(-40.0, 12.0, 0.5) var background_music_volume_db : float = -16.0
@export_range(0.1, 5.0, 0.1) var music_crossfade_duration : float = 1.5

var _background_music_player : AudioStreamPlayer
var _pursuit_music_player : AudioStreamPlayer
var _music_tween : Tween
var _pursuit_music_active : bool = false
var _dog_player : AudioStreamPlayer3D
var _dog_timer : Timer
var _last_dog_index : int = -1
var _random : RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _alert : Node = get_node("/root/PhotoAlertSystem")


func _ready() -> void:
	_alert.photo_count_changed.connect(_on_wanted_level_changed)
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


func start_background_music() -> void:
	if _background_music_player != null:
		return
	_pursuit_music_active = _alert.get_photo_count() > 0
	_background_music_player = _add_loop(
		"BackgroundMusic",
		BACKGROUND_MUSIC_STREAM.duplicate() as AudioStreamMP3,
		background_music_volume_db,
		not _pursuit_music_active
	)
	_pursuit_music_player = _add_loop(
		"PursuitMusic",
		PURSUIT_MUSIC_STREAM.duplicate() as AudioStreamMP3,
		background_music_volume_db,
		_pursuit_music_active
	)


func _on_wanted_level_changed(stars : int, _maximum : int) -> void:
	if _background_music_player == null:
		return
	var pursuit_active : bool = stars > 0
	if pursuit_active == _pursuit_music_active:
		return
	_pursuit_music_active = pursuit_active
	if _music_tween != null:
		_music_tween.kill()
	var incoming : AudioStreamPlayer = (
		_pursuit_music_player if pursuit_active else _background_music_player
	)
	var outgoing : AudioStreamPlayer = (
		_background_music_player if pursuit_active else _pursuit_music_player
	)
	if not incoming.playing:
		incoming.volume_linear = 0.0
		incoming.play()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(outgoing, "volume_linear", 0.0, music_crossfade_duration)
	_music_tween.tween_property(
		incoming, "volume_linear", db_to_linear(background_music_volume_db), music_crossfade_duration
	)
	_music_tween.chain().tween_callback(outgoing.stop)


func _add_loop(node_name : String, stream : AudioStream, volume_db : float,
	autoplay : bool = true) -> AudioStreamPlayer:
	_configure_loop(stream)

	var player : AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	if autoplay:
		player.play()
	return player


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
		var wav : AudioStreamWAV = stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.mix_rate * wav.get_length())
