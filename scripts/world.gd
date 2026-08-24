extends Node3D

## Plays the fase's arrival intro: the ET is lowered from the sky inside a
## tractor beam (scenes/ArrivalBeam.tscn), seen from the player's own camera,
## before control is handed back. The descent starts at the SpaceShip's
## height so it visually reads as "beamed down from the ship". Movement is
## locked during the descent, but the player can still look around within a
## limited turn range (see LOOK_YAW_LIMIT_DEGREES).

const ARRIVAL_BEAM_SCENE : PackedScene = preload("res://scenes/ArrivalBeam.tscn")

const DESCEND_SPEED : float = 10.0
const MIN_DESCEND_HEIGHT : float = 10.0
const MIN_DESCEND_DURATION : float = 2.0
const MAX_DESCEND_DURATION : float = 4.5
const BEAM_HEIGHT_MARGIN : float = 3.0
const BEAM_HOLD_AFTER_LANDING : float = 0.35
const BEAM_FADE_DURATION : float = 0.6
const LOOK_YAW_LIMIT_DEGREES : float = 100.0

@onready var player : CharacterBody3D = $CharacterBody3D
@onready var spaceship : Node3D = $SpaceShip


func _ready() -> void:
	_play_arrival_intro()


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

	var beam : ArrivalBeam = ARRIVAL_BEAM_SCENE.instantiate() as ArrivalBeam
	add_child(beam)
	beam.configure(spawn_position, descend_height + BEAM_HEIGHT_MARGIN)

	var tween : Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(player, "global_position", spawn_position, descend_duration)
	await tween.finished

	player.set_movement_locked(false)

	await get_tree().create_timer(BEAM_HOLD_AFTER_LANDING).timeout
	beam.fade_out(BEAM_FADE_DURATION)
