class_name PlayerNoise
extends Node

signal noise_emitted(origin: Vector3, decibels: float, radius: float, heard: bool)

# Níveis de gameplay referidos a 1 m; independem do volume dos alto-falantes.
const AUDIBILITY_THRESHOLD_DB: float = 20.0
const JUMP_SOUND: AudioStream = preload("res://assets/audio/footsteps/dirt/step_1.wav")
const THEFT_SOUND: AudioStream = preload("res://assets/audio/footsteps/stone/step_2.wav")

@export_range(0.0, 80.0, 1.0) var crouch_decibels: float = 22.0
@export_range(0.0, 80.0, 1.0) var walk_decibels: float = 26.0
@export_range(0.0, 80.0, 1.0) var run_decibels: float = 44.0
@export_range(0.0, 80.0, 1.0) var jump_decibels: float = 42.0
@export_range(0.0, 80.0, 1.0) var theft_decibels: float = 46.0

var _step_elapsed: float = 0.0
var _action_audio: AudioStreamPlayer
@onready var _footstep_audio: Node = get_node_or_null("../FootstepAudio")


func _ready() -> void:
	_action_audio = AudioStreamPlayer.new()
	_action_audio.name = "ActionSound"
	_action_audio.max_polyphony = 2
	add_child(_action_audio)
	var player: Node = get_parent()
	if player.has_signal("item_collected"):
		player.connect("item_collected", _on_item_collected)


static func radius_for_decibels(decibels: float) -> float:
	return pow(10.0, (decibels - AUDIBILITY_THRESHOLD_DB) / 20.0)


func update_motion(delta: float, horizontal_speed: float, grounded: bool,
		sprinting: bool, crouching: bool) -> void:
	if not _can_emit_noise() or not grounded or horizontal_speed <= 0.45:
		stop_steps()
		return
	var speed_ratio: float = clampf((horizontal_speed - 2.0) / 5.0, 0.0, 1.0)
	var interval: float = lerpf(0.55, 0.32, speed_ratio)
	_step_elapsed += delta
	if _step_elapsed < interval:
		return
	_step_elapsed = fmod(_step_elapsed, interval)
	var decibels: float = movement_decibels(sprinting, crouching)
	if _footstep_audio != null:
		_footstep_audio.call("play_movement_step", decibels)
	emit_noise(decibels)


func movement_decibels(sprinting: bool, crouching: bool) -> float:
	return crouch_decibels if crouching else (run_decibels if sprinting else walk_decibels)


func stop_steps() -> void:
	_step_elapsed = 0.0


func emit_jump_noise() -> void:
	stop_steps()
	emit_noise(jump_decibels)
	_play_action_sound(JUMP_SOUND, jump_decibels, 0.86)


func _on_item_collected(_item: RigidBody3D) -> void:
	emit_noise(theft_decibels)
	_play_action_sound(THEFT_SOUND, theft_decibels, 1.18)


func _play_action_sound(stream: AudioStream, decibels: float, pitch: float) -> void:
	if not _can_emit_noise():
		return
	_action_audio.stream = stream
	_action_audio.volume_db = decibels - 64.0
	_action_audio.pitch_scale = pitch
	_action_audio.play()


func emit_noise(decibels: float) -> void:
	if not _can_emit_noise():
		return
	var origin: Vector3 = (get_parent() as Node3D).global_position
	var radius: float = radius_for_decibels(decibels)
	var heard: bool = false
	for listener: Node in get_tree().get_nodes_in_group(&"npc_hearing_listeners"):
		if not listener.has_method("hear_sound"):
			continue
		var received: bool = bool(listener.call("hear_sound", origin, decibels, radius))
		if received and listener.has_method("is_enemy_listener"):
			heard = bool(listener.call("is_enemy_listener")) or heard
	noise_emitted.emit(origin, decibels, radius, heard)


func _can_emit_noise() -> bool:
	var player: Node3D = get_parent() as Node3D
	return (
		player != null
		and player.can_process()
		and player.is_physics_processing()
		and player.has_method("can_emit_player_noise")
		and bool(player.call("can_emit_player_noise"))
	)
