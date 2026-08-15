extends Node3D


@onready var target_legL : Marker3D = $FootL
@onready var target_legR : Marker3D = $FootR

@onready var step_L : Marker3D = $StepL
@onready var step_R : Marker3D = $StepR

@export var stride_length : float = 0.62
@export var step_height : float = 0.18
@export var minimum_walk_speed : float = 0.08
@export var target_follow_speed : float = 16.0
@export var idle_return_speed : float = 9.0

var _phase : float = 0.0
var _left_rest_position : Vector3
var _right_rest_position : Vector3


func _ready() -> void:
	_left_rest_position = step_L.position
	_right_rest_position = step_R.position
	target_legL.position = _left_rest_position
	target_legR.position = _right_rest_position


func _physics_process(delta : float) -> void:

	var parent_character : CharacterBody3D = get_parent() as CharacterBody3D

	if parent_character == null:
		return

	update_feet_IK(parent_character.velocity, delta)


func update_feet_IK(character_velocity : Vector3, delta : float) -> void:

	var horizontal_velocity : Vector3 = Vector3(
		character_velocity.x,
		0.0,
		character_velocity.z
	)

	var movement_speed : float = horizontal_velocity.length()

	if movement_speed < minimum_walk_speed:
		_return_feet_to_rest(delta)
		return

	var safe_stride_length : float = maxf(stride_length, 0.1)
	var phase_speed : float = PI * movement_speed / safe_stride_length
	_phase = fmod(_phase + phase_speed * delta, TAU)

	var stride_scale : float = clampf(movement_speed / 2.0, 0.75, 1.3)
	var left_target : Vector3 = _get_step_position(
		_left_rest_position,
		_phase,
		stride_scale
	)
	var right_target : Vector3 = _get_step_position(
		_right_rest_position,
		fmod(_phase + PI, TAU),
		stride_scale
	)
	var follow_weight : float = clampf(delta * target_follow_speed, 0.0, 1.0)

	target_legL.position = target_legL.position.lerp(left_target, follow_weight)
	target_legR.position = target_legR.position.lerp(right_target, follow_weight)


func _get_step_position(
	rest_position : Vector3,
	foot_phase : float,
	stride_scale : float
) -> Vector3:
	var half_stride : float = stride_length * 0.5 * stride_scale
	var forward_offset : float = -cos(foot_phase) * half_stride
	var lift : float = maxf(sin(foot_phase), 0.0) * step_height * stride_scale

	return rest_position + Vector3(0.0, lift, forward_offset)


func _return_feet_to_rest(delta : float) -> void:
	var return_weight : float = clampf(delta * idle_return_speed, 0.0, 1.0)
	target_legL.position = target_legL.position.lerp(
		_left_rest_position,
		return_weight
	)
	target_legR.position = target_legR.position.lerp(
		_right_rest_position,
		return_weight
	)
