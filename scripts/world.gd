extends Node3D

## Plays the fase's arrival intro: the ET is lowered from the sky inside a
## tractor beam (scenes/FX/ArrivalBeam.tscn), seen from the player's own camera,
## before control is handed back. The descent starts at the SpaceShip's height
## so it visually reads as "beamed down from the ship". Movement is locked
## during the descent, but the player can still look around within a limited
## turn range (see LOOK_YAW_LIMIT_DEGREES).
##
## The sequence deliberately never holds a static frame: it already starts
## moving on _ready(), while SceneTransition's whiteout is still burning off,
## and it is cut into three beats with different curves —
##
##   1. PULL: the beam yanks the ET down fast, the lens is wide, the world
##      rushes up. The ET rotates slowly inside the beam.
##   2. BRAKE: the beam catches it just above the ground and almost stops it.
##   3. DROP: the beam releases and the last few centimetres are a free fall,
##      so the ground contact lands on an accent instead of easing into nothing.

const ARRIVAL_BEAM_SCENE : PackedScene = preload("res://scenes/FX/ArrivalBeam.tscn")
## Preloaded rather than referenced by class_name: the global class cache is
## only populated by the editor, so a class_name reference fails to parse when
## the project is launched straight from the command line.
const PROCEDURAL_SFX = preload("res://scripts/audio/procedural_sfx.gd")
const BEAM_TRAVEL_AUDIO = preload("res://scripts/audio/beam_travel_audio.gd")

const DESCEND_SPEED : float = 10.0
const MIN_DESCEND_HEIGHT : float = 10.0
const MIN_DESCEND_DURATION : float = 2.0
const MAX_DESCEND_DURATION : float = 4.5
const BEAM_HEIGHT_MARGIN : float = 3.0
const BEAM_FADE_DURATION : float = 0.28
const LOOK_YAW_LIMIT_DEGREES : float = 100.0

## Share of the total descent covered by the fast "pull" beat.
const PULL_DISTANCE_RATIO : float = 0.82
const PULL_DURATION_RATIO : float = 0.55
## Height above the spawn point where the beam brakes before letting go.
const RELEASE_HEIGHT : float = 0.45
const DROP_DURATION : float = 0.16

const ARRIVAL_FOV_BOOST : float = 26.0
const LANDING_FOV_KICK : float = -9.0
const LANDING_SHAKE : float = 0.95
const ARRIVAL_YAW_SWING_DEGREES : float = 42.0

const IMPACT_VOLUME_DB : float = -4.0

@onready var player : CharacterBody3D = $CharacterBody3D
@onready var spaceship : Node3D = $SpaceShip

var _look_tween : Tween
var _beam_audio : BEAM_TRAVEL_AUDIO
var _impact_player : AudioStreamPlayer

## Height range the current beam trip covers, used to drive the beam audio from
## the ET's actual position rather than from a timer. Keeping it tied to the
## position means the drone follows the real curve of the trip, and works
## unchanged when the trip runs the other way.
var _travel_start_height : float = 0.0
var _travel_end_height : float = 0.0


func _ready() -> void:
	_play_arrival_intro()


func _process(_delta : float) -> void:
	if _beam_audio == null or not _beam_audio.playing:
		return
	_beam_audio.set_progress(
		inverse_lerp(_travel_start_height, _travel_end_height, player.global_position.y)
	)


func _unhandled_input(event : InputEvent) -> void:
	# The scripted camera swing is a suggestion, not a cage: the moment the
	# player moves the mouse, the tween gets out of the way and the (still
	# limited) free look takes over.
	if _look_tween == null:
		return
	var motion : InputEventMouseMotion = event as InputEventMouseMotion
	if motion == null or motion.relative.length_squared() <= 1.0:
		return
	_look_tween.kill()
	_look_tween = null


func _play_arrival_intro() -> void:
	var spawn_position : Vector3 = player.global_position
	var descend_height : float = maxf(
		spaceship.global_position.y - spawn_position.y,
		MIN_DESCEND_HEIGHT
	)
	var descend_duration : float = clampf(
		descend_height / DESCEND_SPEED,
		MIN_DESCEND_DURATION,
		MAX_DESCEND_DURATION
	)
	var start_position : Vector3 = spawn_position + Vector3.UP * descend_height

	player.set_movement_locked(true, LOOK_YAW_LIMIT_DEGREES)
	player.global_position = start_position
	player.camera_pivot.global_position = start_position
	player.camera_pivot.set_fov_offset(ARRIVAL_FOV_BOOST)

	# Starts off-axis so the first thing the camera does is settle, not sit
	# still. The swing resolves exactly as the ET touches down.
	var landing_yaw : float = player.camera_yaw
	player.camera_yaw = landing_yaw + deg_to_rad(ARRIVAL_YAW_SWING_DEGREES)

	var beam : ArrivalBeam = ARRIVAL_BEAM_SCENE.instantiate() as ArrivalBeam
	add_child(beam)
	beam.configure(spawn_position, descend_height + BEAM_HEIGHT_MARGIN)

	_setup_arrival_audio(spawn_position, start_position)

	var brake_position : Vector3 = spawn_position + Vector3.UP * RELEASE_HEIGHT
	var pull_position : Vector3 = start_position.lerp(brake_position, PULL_DISTANCE_RATIO)
	var pull_duration : float = descend_duration * PULL_DURATION_RATIO
	var brake_duration : float = descend_duration - pull_duration - DROP_DURATION

	# Position runs as one chained tween; the camera swing and the lens run on
	# their own tweens so their (longer) durations never stretch a beat.
	var tween : Tween = create_tween()

	# 1. PULL - accelerating away from the ship.
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(player, "global_position", pull_position, pull_duration)

	# 2. BRAKE - the beam takes the speed out just above the ground.
	tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(player, "global_position", brake_position, brake_duration)

	# 3. DROP - released, the last stretch is a fall.
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(player, "global_position", spawn_position, DROP_DURATION)

	_look_tween = create_tween()
	_look_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_look_tween.tween_property(
		player, "camera_yaw", landing_yaw, descend_duration - DROP_DURATION
	)

	var lens_tween : Tween = create_tween()
	lens_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	lens_tween.tween_method(
		player.camera_pivot.set_fov_offset,
		ARRIVAL_FOV_BOOST,
		ARRIVAL_FOV_BOOST * 0.35,
		pull_duration
	)
	lens_tween.tween_method(
		player.camera_pivot.set_fov_offset,
		ARRIVAL_FOV_BOOST * 0.35,
		0.0,
		brake_duration
	)

	await tween.finished

	_on_touchdown(beam)


func _on_touchdown(beam : ArrivalBeam) -> void:
	_look_tween = null
	player.camera_pivot.add_shake(LANDING_SHAKE)
	player.camera_pivot.kick_fov(LANDING_FOV_KICK)
	player.set_movement_locked(false)

	if _impact_player != null:
		_impact_player.play()

	get_tree().call_group(&"alien_post_process", &"pulse_interference", 1.0, 0.6)

	if _beam_audio != null:
		_beam_audio.release(BEAM_FADE_DURATION)

	beam.fade_out(BEAM_FADE_DURATION)


## Placeholder audio, synthesized at runtime (see
## scripts/audio/procedural_sfx.gd). Swap the two stream assignments for real
## assets once they exist.
##
## The beam drone lives in its own reusable node: nothing here assumes the trip
## goes downward or how long it takes, so the same node covers the return trip
## to the ship once boarding it is a thing the player can do.
func _setup_arrival_audio(spawn_position : Vector3, start_position : Vector3) -> void:
	_travel_start_height = start_position.y
	_travel_end_height = spawn_position.y

	_beam_audio = BEAM_TRAVEL_AUDIO.new()
	_beam_audio.unit_size = 24.0
	_beam_audio.max_distance = 90.0
	add_child(_beam_audio)
	_beam_audio.global_position = spawn_position + Vector3.UP * 2.0
	_beam_audio.engage(BEAM_TRAVEL_AUDIO.Direction.DESCEND)

	_impact_player = AudioStreamPlayer.new()
	_impact_player.stream = PROCEDURAL_SFX.landing_impact()
	_impact_player.volume_db = IMPACT_VOLUME_DB
	add_child(_impact_player)
