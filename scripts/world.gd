extends Node3D

## Plays the fase's arrival intro: the ET is lowered from the sky inside a
## tractor beam (scenes/FX/ArrivalBeam.tscn), seen from the player's own camera,
## before control is handed back. The descent starts at the SpaceShip's height
## so it visually reads as "beamed down from the ship". Movement is locked
## during the descent, but the player can still look around within a limited
## turn range (see LOOK_YAW_LIMIT_DEGREES).
##
## The sequence deliberately never holds a static frame: it starts moving the
## instant it runs, and it is cut into three beats with different curves —
## whether that is on _ready() (opening the fase directly) or later, when the
## player steps on the descend pad on the saucer (see _spawn_on_saucer())
## after coming from the orbital terminal —
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
const MISSION_FLOW = preload("res://scripts/levels/mission_flow.gd")
const SAUCER_SCENE : PackedScene = preload("res://scenes/Space/Saucer.tscn")

## How far above its resting height the saucer starts, and how long it
## takes to settle into place -- sold as the ship coming down from higher up
## and parking, rather than appearing already parked.
const SAUCER_APPROACH_HEIGHT : float = 45.0
const SAUCER_APPROACH_DURATION : float = 3.4
const SAUCER_LANDING_SHAKE : float = 0.35
## NightEnvironment.FogProfile, by value: night_environment.gd is not reachable
## by class_name from here, and the group call takes a plain int anyway.
const FOG_PROFILE_GROUND : int = 0
const FOG_PROFILE_FLIGHT : int = 1

## Height above the fase's ground spawn under which the ET counts as arrived.
const GROUND_ARRIVAL_HEIGHT : float = 5.0

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

var _look_tween : Tween
var _beam_audio : BEAM_TRAVEL_AUDIO
var _impact_player : AudioStreamPlayer

## Height range the current beam trip covers, used to drive the beam audio from
## the ET's actual position rather than from a timer. Keeping it tied to the
## position means the drone follows the real curve of the trip, and works
## unchanged when the trip runs the other way.
var _travel_start_height : float = 0.0
var _travel_end_height : float = 0.0

## The fase's authored ground-level arrival point, captured before anything
## moves the player. _play_arrival_intro() always lands here regardless of
## where the player currently is when it runs -- on the ground already (the
## default path) or up on the saucer (the orbital terminal path).
var _ground_spawn_position : Vector3
var _saucer : Saucer
var _airborne_atmosphere : bool = false

@onready var player : CharacterBody3D = $CharacterBody3D
@onready var spaceship : Node3D = $SpaceShip


func _ready() -> void:
	_ground_spawn_position = player.global_position

	var arrived_from_orbit : bool = MISSION_FLOW.arrived_from_orbit
	MISSION_FLOW.arrived_from_orbit = false
	if arrived_from_orbit:
		_spawn_on_saucer()
	else:
		_play_arrival_intro()


func _process(_delta : float) -> void:
	_update_airborne_atmosphere()

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


## Arrival via the orbital terminal: the ET rides the saucer down from higher
## up and parks directly above the ground spawn point, at the same height as
## the fase's SpaceShip, so the descend pad always drops the beam in a straight
## column onto the exact spot the fase was designed to receive the player.
##
## The saucer is spawned from code rather than authored in world.tscn: it only
## exists for this one arrival path, and appending a node by hand to a scene
## this size is easy to get wrong. SpaceShip and the saucer now float at the
## same height without occupying the same footprint; consolidating them into
## a single object is follow-up work.
func _spawn_on_saucer() -> void:
	_saucer = SAUCER_SCENE.instantiate() as Saucer
	add_child(_saucer)
	# The saucer's safety net exists for Orbit.tscn, where stepping off the
	# edge is an endless fall through empty space. Here there is a fase right
	# below, so jumping off is a legitimate way down -- the ET takes the fall
	# it earned (see player.gd's landing_ragdoll_speed) instead of being
	# teleported back up. This also covers the tractor beam, whose column runs
	# straight down through the saucer's own footprint.
	_saucer.set_fall_guard_enabled(false)

	var rest_height : float = spaceship.global_position.y
	var start_height : float = rest_height + SAUCER_APPROACH_HEIGHT
	_saucer.global_position = Vector3(
		_ground_spawn_position.x, start_height, _ground_spawn_position.z
	)

	player.set_movement_locked(true)
	_place_player_on_saucer()

	_enter_airborne_atmosphere()

	var tween : Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		_set_saucer_height, start_height, rest_height, SAUCER_APPROACH_DURATION
	)
	await tween.finished

	player.camera_pivot.add_shake(SAUCER_LANDING_SHAKE)
	player.set_movement_locked(false)

	_saucer.descend_requested.connect(_on_descend_requested)
	_saucer.set_descend_trigger_enabled(true)


## The fase's atmosphere is calibrated for an ET standing on the ground, and
## the whole orbital arrival happens well above it -- on the saucer, then inside
## the beam. Both of its fog systems have to be told, or they read as bugs:
##
##   1. GroundFogLayer finds its height with a raycast straight down from the
##      camera. Standing on the saucer, that ray hits the saucer's own floor, so
##      the fog would sit at the ET's feet in mid-air and ride the saucer down.
##      Pinning it to the real ground height keeps the mat where it belongs.
##   2. The Environment's depth fog closes opaque at 400 m, which on foot is
##      hidden behind terrain and buildings. From up here the view reaches the
##      whole map, so that wall becomes a visible sheet whenever you turn
##      toward open distance and vanishes when you face the sky. This is the
##      same problem the plane has, so it uses the same fix: the FLIGHT
##      profile, which opens the fog out to 950 m (see night_environment.gd).
##
## Both are undone once the ET reaches the ground -- by whatever route, see
## _update_airborne_atmosphere().
func _enter_airborne_atmosphere() -> void:
	_airborne_atmosphere = true
	get_tree().call_group(
		&"ground_fog_layer", &"pin_ground_height", _ground_spawn_position.y
	)
	get_tree().call_group(&"night_environment", &"set_fog_profile", FOG_PROFILE_FLIGHT)


func _exit_airborne_atmosphere() -> void:
	if not _airborne_atmosphere:
		return
	_airborne_atmosphere = false
	get_tree().call_group(&"ground_fog_layer", &"unpin_ground_height")
	get_tree().call_group(&"night_environment", &"set_fog_profile", FOG_PROFILE_GROUND)


## Restoring the ground atmosphere is driven by the ET's height, not by the
## tractor beam finishing: jumping off the saucer is a valid way down too, and
## keying this to the beam alone would leave a player who jumped with the
## flight fog profile for the rest of the fase.
func _update_airborne_atmosphere() -> void:
	if not _airborne_atmosphere:
		return
	if player.global_position.y > _ground_spawn_position.y + GROUND_ARRIVAL_HEIGHT:
		return
	_exit_airborne_atmosphere()


## Drives the saucer's descent from a tween: keeps the player standing on the
## saucer's spawn point in sync every step, since the player is not an actual
## child of the saucer.
func _set_saucer_height(height : float) -> void:
	_saucer.global_position.y = height
	_place_player_on_saucer()


func _place_player_on_saucer() -> void:
	player.global_position = _saucer.spawn_point.global_position
	player.camera_pivot.global_position = player.global_position


func _on_descend_requested() -> void:
	_play_arrival_intro()


func _play_arrival_intro() -> void:
	var spawn_position : Vector3 = _ground_spawn_position
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
	# Only meaningful on the orbital path, where the atmosphere was switched to
	# its airborne settings; on the direct path both calls are already no-ops.
	_exit_airborne_atmosphere()
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
