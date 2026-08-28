class_name BeamTravelAudio
extends AudioStreamPlayer3D

## Sound of a body travelling inside a tractor beam. Written for the fase's
## arrival intro, but deliberately direction-agnostic and duration-agnostic:
## the same node handles the ET being lowered from the ship, climbing back up,
## or hanging in the beam, however long each of those takes.
##
## Nothing about the trip is baked into the audio buffer. The drone loops
## forever (see ProceduralSFX.beam_hum_loop) and this node shapes it live:
## pitch tracks how far along the trip is, volume handles the entry and exit.
##
## Reusable across trips: release() fades and stops but keeps the node alive,
## so the next engage() can just start it again.

const PROCEDURAL_SFX = preload("res://scripts/audio/procedural_sfx.gd")

enum Direction {
	DESCEND, ## Ship to ground.
	ASCEND, ## Ground to ship.
}

## Drone pitch at either end of the trip. It sits lower near the ship (distant,
## slack beam) and tightens as the beam closes on the ground.
const PITCH_AT_SHIP : float = 0.86
const PITCH_AT_GROUND : float = 1.07

const DEFAULT_FADE_IN : float = 0.22
const DEFAULT_FADE_OUT : float = 0.28
const SILENT_VOLUME_DB : float = -60.0

## Volume the drone settles at while a trip is in progress.
@export_range(-40.0, 6.0, 0.5) var travel_volume_db : float = -9.0

var _direction : Direction = Direction.DESCEND
var _fade_tween : Tween

## The buffer is deterministic and read-only, so every beam in the game can
## share one instead of each synthesizing its own couple of hundred kilobytes.
static var _shared_stream : AudioStreamWAV = null


func _ready() -> void:
	if _shared_stream == null:
		_shared_stream = PROCEDURAL_SFX.beam_hum_loop()
	stream = _shared_stream
	volume_db = SILENT_VOLUME_DB


## Starts (or restarts) the drone for a trip in the given direction.
func engage(direction : Direction, fade_in : float = DEFAULT_FADE_IN) -> void:
	_direction = direction
	set_progress(0.0)

	if not playing:
		play()

	_fade_to(travel_volume_db, fade_in)


## Where the traveller is along the trip: 0.0 at the departure end, 1.0 at the
## arrival end, whichever way it is going. Safe to call every frame.
func set_progress(progress : float) -> void:
	var clamped : float = clampf(progress, 0.0, 1.0)
	var from_pitch : float = (
		PITCH_AT_SHIP if _direction == Direction.DESCEND else PITCH_AT_GROUND
	)
	var to_pitch : float = (
		PITCH_AT_GROUND if _direction == Direction.DESCEND else PITCH_AT_SHIP
	)
	pitch_scale = lerpf(from_pitch, to_pitch, clamped)


## Fades the drone out and stops it, leaving the node ready for the next trip.
func release(fade_out : float = DEFAULT_FADE_OUT) -> void:
	if not playing:
		return
	_fade_to(SILENT_VOLUME_DB, fade_out)
	_fade_tween.tween_callback(stop)


func _fade_to(target_db : float, duration : float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "volume_db", target_db, maxf(duration, 0.01))
