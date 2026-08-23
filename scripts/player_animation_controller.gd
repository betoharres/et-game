class_name PlayerAnimationController
extends Node

## Central visual state for the player. CharacterBody3D still owns movement;
## this controller only maps its physical state to authored Mixamo clips.

signal get_up_finished

const GET_UP_FRONT_SPEED_RAMP_START : float = 0.22
const GET_UP_FRONT_SPEED_RAMP_END : float = 0.52
const GET_UP_FRONT_DURATION_STEPS : int = 64

const LOOPING_ANIMATIONS : PackedStringArray = [
	"idle",
	"walk",
	"run",
	"strafe_left_walk",
	"strafe_right_walk",
	"strafe_left_run",
	"strafe_right_run",
	"crouch_idle",
	"crouch_walk",
	"crouch_left",
	"crouch_right",
	"fall",
]

const STATE_ANIMATIONS := {
	"Idle": "idle",
	"IdleVariantA": "idle_variant_a",
	"IdleVariantB": "idle_variant_b",
	"Walk": "walk",
	"Run": "run",
	"StrafeLeftWalk": "strafe_left_walk",
	"StrafeRightWalk": "strafe_right_walk",
	"StrafeLeftRun": "strafe_left_run",
	"StrafeRightRun": "strafe_right_run",
	"CrouchIdle": "crouch_idle",
	"CrouchWalk": "crouch_walk",
	"CrouchLeft": "crouch_left",
	"CrouchRight": "crouch_right",
	"TurnLeft": "turn_left",
	"TurnRight": "turn_right",
	"TurnLeftWide": "turn_left_wide",
	"TurnRightWide": "turn_right_wide",
	"WalkTurn180": "walk_turn_180",
	"RunTurn180": "run_turn_180",
	"RunTurnRight": "run_turn_right",
	"RunStop": "run_stop",
	"Jump": "jump",
	"Fall": "fall",
	"Landing": "land_hard",
	"HitFront": "hit_front",
	"HitSide": "hit_side",
	"StumbleForward": "stumble_forward",
	"StumbleBack": "stumble_back",
	"GetUpBack": "get_up_back",
	"GetUpFront": "get_up_front",
}

const LOCOMOTION_STATES : PackedStringArray = [
	"Idle",
	"Walk",
	"Run",
	"StrafeLeftWalk",
	"StrafeRightWalk",
	"StrafeLeftRun",
	"StrafeRightRun",
	"CrouchIdle",
	"CrouchWalk",
	"CrouchLeft",
	"CrouchRight",
]

const IDLE_VARIANT_STATES : PackedStringArray = [
	"Idle",
	"IdleVariantA",
	"IdleVariantB",
]

@export_category("Blend")
@export_range(0.0, 0.5, 0.01) var locomotion_blend : float = 0.16
@export_range(0.0, 0.5, 0.01) var action_blend : float = 0.10
@export_range(0.0, 1.0, 0.01) var idle_variant_blend : float = 0.40

@export_category("Locomotion")
@export var idle_speed_threshold : float = 0.25
@export_range(0.0, 1.0, 0.05) var lateral_threshold : float = 0.55
@export var walk_reference_speed : float = 1.65
@export var run_reference_speed : float = 3.4
@export var crouch_reference_speed : float = 1.05

@export_category("Get Up")
@export_range(1.0, 4.0, 0.1) var get_up_front_initial_speed : float = 3.2
@export_range(1.0, 4.0, 0.1) var get_up_front_standing_speed : float = 1.9
@export_range(0.0, 0.6, 0.01) var get_up_control_release_lead : float = 0.25

@export_category("Idle Variants")
@export var idle_variant_delay_minimum : float = 8.0
@export var idle_variant_delay_maximum : float = 18.0

@onready var animation_player : AnimationPlayer = $"../ET/AnimationPlayer"
@onready var animation_tree : AnimationTree = $"../AnimationTree"
@onready var player_body : CharacterBody3D = get_parent() as CharacterBody3D

var _playback : AnimationNodeStateMachinePlayback
var _random := RandomNumberGenerator.new()
var _current_state : StringName = &""
var _action_state : StringName = &""
var _action_timer : float = 0.0
var _action_speed : float = 1.0
var _action_cancels_on_motion : bool = false
var _get_up_active : bool = false
var _get_up_face_up : bool = true
var _get_up_front_position : float = 0.0
var _get_up_animation_length : float = 0.0
var _ragdoll_active : bool = false
var _horizontal_speed : float = 0.0
var _local_velocity : Vector3 = Vector3.ZERO
var _on_floor : bool = true
var _is_sprinting : bool = false
var _is_crouching : bool = false
var _jump_state : int = 0
var _vertical_velocity : float = 0.0
var _previous_horizontal_speed : float = 0.0
var _previous_sprinting : bool = false
var _idle_variant_timer : float = 0.0


func _ready() -> void:
	_random.randomize()
	_configure_animation_resources()
	_build_state_machine()
	_reset_idle_variant_timer()


func set_motion_state(world_velocity : Vector3, on_floor : bool,
	is_sprinting : bool, is_crouching : bool, jump_state : int) -> void:
	_previous_horizontal_speed = _horizontal_speed
	_previous_sprinting = _is_sprinting
	_horizontal_speed = Vector2(world_velocity.x, world_velocity.z).length()
	_vertical_velocity = world_velocity.y
	_on_floor = on_floor
	_is_sprinting = is_sprinting
	_is_crouching = is_crouching
	_jump_state = jump_state

	if player_body != null:
		_local_velocity = (
			player_body.global_transform.basis.inverse() * world_velocity
		)
	else:
		_local_velocity = world_velocity


func trigger_turn(turn_delta : float) -> void:
	if _ragdoll_active or _get_up_active or absf(turn_delta) < 0.01:
		return

	var is_wide_turn := absf(turn_delta) >= deg_to_rad(100.0)
	var state : StringName
	if turn_delta > 0.0:
		state = &"TurnLeftWide" if is_wide_turn else &"TurnLeft"
	else:
		state = &"TurnRightWide" if is_wide_turn else &"TurnRight"
	_trigger_action(
		state,
		minf(_animation_length_for_state(state), 1.2 if is_wide_turn else 0.72),
		false
	)


func trigger_moving_turn(is_running : bool) -> float:
	if _ragdoll_active or _get_up_active:
		return 0.0

	var state : StringName = &"RunTurn180" if is_running else &"WalkTurn180"
	var duration := _animation_length_for_state(state)
	_trigger_action(state, duration, false)
	return duration


func cancel_moving_turn() -> void:
	if _action_state not in [&"WalkTurn180", &"RunTurn180", &"RunTurnRight"]:
		return
	_action_state = &""
	_action_timer = 0.0
	_action_speed = 1.0
	animation_player.speed_scale = 1.0


func trigger_hit(impact_direction : Vector3) -> void:
	if _ragdoll_active or _get_up_active or _action_is_reaction():
		return

	var local_direction := _to_local_direction(impact_direction)
	var state : StringName = (
		&"HitSide"
		if absf(local_direction.x) > absf(local_direction.z) * 0.65
		else &"HitFront"
	)
	_trigger_action(state, minf(_animation_length_for_state(state), 1.15), false)


func trigger_stumble(impact_direction : Vector3) -> void:
	if _ragdoll_active or _get_up_active:
		return

	var local_direction := _to_local_direction(impact_direction)
	var state : StringName = (
		&"StumbleBack" if local_direction.z < 0.0 else &"StumbleForward"
	)
	_trigger_action(state, minf(_animation_length_for_state(state), 1.4), false)


func trigger_landing(landing_speed : float) -> void:
	if _ragdoll_active or _get_up_active or landing_speed <= 0.0:
		return

	_trigger_action(
		&"Landing",
		minf(_animation_length_for_state(&"Landing"), 1.0),
		false
	)


func set_ragdoll_active(active : bool) -> void:
	_ragdoll_active = active
	_action_state = &""
	_action_timer = 0.0
	_get_up_active = false
	_get_up_front_position = 0.0
	_get_up_animation_length = 0.0
	animation_tree.active = not active


func begin_get_up(face_up : bool) -> float:
	_ragdoll_active = false
	animation_tree.active = true
	_get_up_active = true
	_get_up_face_up = face_up
	_get_up_front_position = 0.0
	var state : StringName = &"GetUpBack" if face_up else &"GetUpFront"
	_get_up_animation_length = _animation_length_for_state(state)
	var action_speed : float = (
		1.0 if face_up else get_up_front_initial_speed
	)
	var duration : float = _get_up_animation_length / action_speed
	if not face_up:
		duration = _get_up_front_duration()
	_trigger_action(state, duration, false, action_speed)
	return duration


func finish_get_up() -> void:
	if not _get_up_active:
		return

	_get_up_active = false
	_get_up_front_position = 0.0
	_get_up_animation_length = 0.0
	_action_state = &""
	_action_timer = 0.0
	_travel(&"Idle")
	get_up_finished.emit()


func is_get_up_finished() -> bool:
	return _get_up_active and _action_timer <= 0.0


## The authored clips hold their final standing pose briefly. Return control
## during that settled tail instead of making input wait for the last frame.
func is_get_up_ready_for_control() -> bool:
	return (
		_get_up_active
		and _action_timer <= get_up_control_release_lead
	)


func get_current_state() -> StringName:
	return _current_state


func _physics_process(delta : float) -> void:
	if _ragdoll_active or _playback == null:
		return

	if not _action_state.is_empty():
		_update_get_up_front_speed(delta)
		_action_timer = maxf(_action_timer - delta, 0.0)
		if _action_cancels_on_motion and _horizontal_speed > idle_speed_threshold:
			_action_timer = 0.0
		if _action_timer > 0.0:
			animation_player.speed_scale = _action_speed
			return
		if _get_up_active:
			return
		_action_state = &""

	if not _on_floor or _jump_state != 0:
		_update_air_state()
		return

	if (
		_previous_sprinting
		and _previous_horizontal_speed > run_reference_speed * 0.65
		and _horizontal_speed <= idle_speed_threshold
	):
		_trigger_action(&"RunStop", 0.72, true)
		return

	_update_locomotion(delta)


## The face-down source clip starts with sparse arm motion and concentrates the
## lift in its middle. A smooth speed ramp evens that authored pacing without
## procedurally changing the pose: only the clip playback rate is adjusted.
func _update_get_up_front_speed(delta : float) -> void:
	if not _get_up_active or _get_up_face_up or _get_up_animation_length <= 0.0:
		return

	_get_up_front_position = minf(
		_get_up_front_position + delta * _action_speed,
		_get_up_animation_length
	)
	var progress := clampf(
		_get_up_front_position / _get_up_animation_length,
		0.0,
		1.0
	)
	_action_speed = _get_up_front_speed_at(progress)


func _get_up_front_speed_at(progress : float) -> float:
	var blend := smoothstep(
		GET_UP_FRONT_SPEED_RAMP_START,
		GET_UP_FRONT_SPEED_RAMP_END,
		clampf(progress, 0.0, 1.0)
	)
	return lerpf(
		get_up_front_initial_speed,
		get_up_front_standing_speed,
		blend
	)


func _get_up_front_duration() -> float:
	if _get_up_animation_length <= 0.0:
		return 0.05

	var source_step := _get_up_animation_length / GET_UP_FRONT_DURATION_STEPS
	var duration : float = 0.0
	for step : int in GET_UP_FRONT_DURATION_STEPS:
		var progress := (float(step) + 0.5) / GET_UP_FRONT_DURATION_STEPS
		duration += source_step / maxf(_get_up_front_speed_at(progress), 0.05)
	return duration


func _configure_animation_resources() -> void:
	for animation_name : StringName in animation_player.get_animation_list():
		var animation := animation_player.get_animation(animation_name)
		if animation == null:
			continue
		animation.loop_mode = (
			Animation.LOOP_LINEAR
			if String(animation_name) in LOOPING_ANIMATIONS
			else Animation.LOOP_NONE
		)
func _build_state_machine() -> void:
	var machine := AnimationNodeStateMachine.new()
	var state_names : Array[StringName] = []
	var column : int = 0
	var row : int = 0

	for state_name : String in STATE_ANIMATIONS:
		var animation_name : String = STATE_ANIMATIONS[state_name]
		if not animation_player.has_animation(animation_name):
			push_warning("Player animation missing: %s" % animation_name)
			continue

		var animation_node := AnimationNodeAnimation.new()
		animation_node.animation = StringName(animation_name)
		machine.add_node(
			StringName(state_name),
			animation_node,
			Vector2(column * 220.0, row * 100.0)
		)
		state_names.append(StringName(state_name))
		row += 1
		if row >= 8:
			row = 0
			column += 1

	for from_state : StringName in state_names:
		for to_state : StringName in state_names:
			if from_state == to_state:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			if from_state in IDLE_VARIANT_STATES and to_state in IDLE_VARIANT_STATES:
				transition.xfade_time = idle_variant_blend
			elif from_state in LOCOMOTION_STATES and to_state in LOCOMOTION_STATES:
				transition.xfade_time = locomotion_blend
			else:
				transition.xfade_time = action_blend
			machine.add_transition(from_state, to_state, transition)

	animation_tree.tree_root = machine
	animation_tree.active = true
	_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if _playback == null:
		push_error("Player AnimationTree playback was not created.")
		return
	_playback.start(&"Idle")
	_current_state = &"Idle"


func _update_air_state() -> void:
	animation_player.speed_scale = 1.0
	if _vertical_velocity > 0.35:
		_travel(&"Jump")
	else:
		_travel(&"Fall")


func _update_locomotion(delta : float) -> void:
	if _horizontal_speed <= idle_speed_threshold:
		animation_player.speed_scale = 1.0
		if _is_crouching:
			_reset_idle_variant_timer()
			_travel(&"CrouchIdle")
			return
		_idle_variant_timer -= delta
		if _idle_variant_timer <= 0.0:
			var variant : StringName = (
				&"IdleVariantA" if _random.randf() < 0.5 else &"IdleVariantB"
			)
			_trigger_action(
				variant,
				_animation_length_for_state(variant),
				true
			)
			_reset_idle_variant_timer()
			return
		_travel(&"Idle")
		return

	_reset_idle_variant_timer()
	var local_horizontal := Vector2(_local_velocity.x, _local_velocity.z)
	var lateral_ratio : float = (
		absf(local_horizontal.x) / maxf(local_horizontal.length(), 0.001)
	)
	var state : StringName

	if _is_crouching:
		if lateral_ratio >= lateral_threshold:
			state = &"CrouchLeft" if local_horizontal.x < 0.0 else &"CrouchRight"
		else:
			state = &"CrouchWalk"
		animation_player.speed_scale = clampf(
			_horizontal_speed / maxf(crouch_reference_speed, 0.1),
			0.7,
			2.1
		)
	elif lateral_ratio >= lateral_threshold:
		if _is_sprinting:
			state = (
				&"StrafeLeftRun"
				if local_horizontal.x < 0.0
				else &"StrafeRightRun"
			)
			animation_player.speed_scale = clampf(
				_horizontal_speed / maxf(run_reference_speed, 0.1), 0.8, 2.1
			)
		else:
			state = (
				&"StrafeLeftWalk"
				if local_horizontal.x < 0.0
				else &"StrafeRightWalk"
			)
			animation_player.speed_scale = clampf(
				_horizontal_speed / maxf(walk_reference_speed, 0.1), 0.75, 2.3
			)
	elif _is_sprinting:
		state = &"Run"
		animation_player.speed_scale = clampf(
			_horizontal_speed / maxf(run_reference_speed, 0.1), 0.8, 2.1
		)
	else:
		state = &"Walk"
		animation_player.speed_scale = clampf(
			_horizontal_speed / maxf(walk_reference_speed, 0.1), 0.75, 2.3
		)

	_travel(state)


func _trigger_action(state : StringName, duration : float,
	cancels_on_motion : bool, speed_scale : float = 1.0) -> void:
	if _playback == null or not STATE_ANIMATIONS.has(String(state)):
		return

	_action_state = state
	_action_timer = maxf(duration, 0.05)
	_action_speed = maxf(speed_scale, 0.05)
	_action_cancels_on_motion = cancels_on_motion
	animation_player.speed_scale = _action_speed
	_travel(state)


func _travel(state : StringName) -> void:
	if _playback == null or state == _current_state:
		return
	_playback.travel(state)
	_current_state = state


func _animation_length_for_state(state : StringName) -> float:
	var animation_name : String = STATE_ANIMATIONS.get(String(state), "")
	if animation_name.is_empty() or not animation_player.has_animation(animation_name):
		return 0.5
	return animation_player.get_animation(animation_name).length


func _to_local_direction(direction : Vector3) -> Vector3:
	if player_body == null or direction.length_squared() <= 0.0001:
		return Vector3.ZERO
	return (
		player_body.global_transform.basis.inverse() * direction.normalized()
	)


func _action_is_reaction() -> bool:
	return _action_state in [
		&"HitFront",
		&"HitSide",
		&"StumbleForward",
		&"StumbleBack",
	]


func _reset_idle_variant_timer() -> void:
	_idle_variant_timer = _random.randf_range(
		idle_variant_delay_minimum,
		maxf(idle_variant_delay_maximum, idle_variant_delay_minimum)
	)
