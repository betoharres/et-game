extends CharacterBody3D

## Loads the compatible Polygon animation clips into the local AnimationPlayer
## and drives locomotion, jumping, crouching and a third-person camera.

@export_category("Movement")
@export var controls_enabled: bool = true
@export var walk_speed: float = 3.5
@export var sprint_speed: float = 6.5
@export var crouch_speed: float = 2.0
@export var jump_velocity: float = 5.5
@export var ground_acceleration: float = 24.0
@export var ground_deceleration: float = 20.0
@export var air_acceleration: float = 7.0
@export var rotation_speed: float = 10.0
@export_range(0.0, 10.0, 0.1) var run_threshold: float = 4.0

@export_category("Turn In Place")
@export_range(10.0, 90.0, 1.0) var turn_in_place_threshold: float = 55.0
@export_range(100.0, 179.0, 1.0) var turn_180_threshold: float = 135.0

@export_category("Crouch")
@export_range(0.5, 1.0, 0.05) var crouch_height_ratio: float = 0.65
@export var crouch_transition_speed: float = 8.0
@export var crouch_camera_drop: float = 0.3

@export_category("Camera")
@export var mouse_sensitivity: float = 0.003
@export_range(-89.0, 0.0, 1.0) var camera_pitch_min: float = -80.0
@export_range(0.0, 89.0, 1.0) var camera_pitch_max: float = 80.0

@onready var camera_arm: Node3D = $CameraArm
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var character_visual: Node3D = $PolygonSyntyCharacter

var _playback: AnimationNodeStateMachinePlayback
var _requested_speed: float = 0.0
var _requested_crouch: bool = false
var _requested_grounded: bool = true
var _camera_yaw: float = 0.0
var _camera_pitch: float = 0.0
var _crouch_amount: float = 0.0
var _standing_collision_height: float = 0.0
var _standing_collision_y: float = 0.0
var _collision_bottom: float = 0.0
var _is_turning: bool = false
var _turn_elapsed: float = 0.0
var _turn_duration: float = 0.0
var _turn_start_yaw: float = 0.0
var _turn_target_yaw: float = 0.0
var _turn_crouching: bool = false

const CLIPS: Dictionary[StringName, PackedScene] = {
	&"Idle": preload("res://Temporarios/Animations/Polygon/Masculine/Idle/A_Idle_Standing_Masc.fbx"),
	&"IdleToWalk": preload("res://Temporarios/Animations/Polygon/Masculine/Transitions/Idle_ToWalk/A_Idle_ToWalkF_Masc.fbx"),
	&"Walk": preload("res://Temporarios/Animations/Polygon/Masculine/Locomotion/Walk/A_Walk_F_Masc.fbx"),
	&"WalkToIdle": preload("res://Temporarios/Animations/Polygon/Masculine/Transitions/Walk_ToIdle/A_Walk_ToIdleF_LFoot_Masc.fbx"),
	&"IdleToRun": preload("res://Temporarios/Animations/Polygon/Masculine/Transitions/Idle_ToRun/A_Idle_ToRunF_Masc.fbx"),
	&"Run": preload("res://Temporarios/Animations/Polygon/Masculine/Locomotion/Run/A_Run_F_Masc.fbx"),
	&"RunToIdle": preload("res://Temporarios/Animations/Polygon/Masculine/Transitions/Run_ToIdle/A_Run_ToIdleF_LFoot_Masc.fbx"),
	&"CrouchEnter": preload("res://Temporarios/Animations/Polygon/Masculine/Transitions/Stand_ToCrouch/A_Stand_ToCrouch_Masc.fbx"),
	&"CrouchIdle": preload("res://Temporarios/Animations/Polygon/Masculine/Idle/A_Idle_Crouching_Masc.fbx"),
	&"CrouchWalk": preload("res://Temporarios/Animations/Polygon/Masculine/Locomotion/Crouch/A_Crouch_FwdStrafeF_Masc.fbx"),
	&"CrouchExit": preload("res://Temporarios/Animations/Polygon/Masculine/Transitions/Crouch_ToStand/A_Crouch_ToStand_Masc.fbx"),
	&"TurnStand90L": preload("res://Temporarios/Animations/Polygon/Masculine/Locomotion/Turn/A_Turn_Standing_90L_Masc.fbx"),
	&"TurnStand90R": preload("res://Temporarios/Animations/Polygon/Masculine/Locomotion/Turn/A_Turn_Standing_90R_Masc.fbx"),
	&"TurnStand180L": preload("res://Temporarios/Animations/Polygon/Masculine/Locomotion/Turn/A_Turn_Standing_180L_Masc.fbx"),
	&"TurnStand180R": preload("res://Temporarios/Animations/Polygon/Masculine/Locomotion/Turn/A_Turn_Standing_180R_Masc.fbx"),
	&"TurnCrouch90L": preload("res://Temporarios/Animations/Polygon/Masculine/Locomotion/Turn/A_Turn_Crouching_90L_Masc.fbx"),
	&"TurnCrouch90R": preload("res://Temporarios/Animations/Polygon/Masculine/Locomotion/Turn/A_Turn_Crouching_90R_Masc.fbx"),
	&"Jump": preload("res://Temporarios/Animations/Polygon/Masculine/InAir/A_Jump_Idle_Masc.fbx"),
	&"Fall": preload("res://Temporarios/Animations/Polygon/Masculine/InAir/A_InAir_FallShort_Masc.fbx"),
	&"Land": preload("res://Temporarios/Animations/Polygon/Masculine/InAir/A_Land_IdleSoft_Masc.fbx"),
}

const LOOPING_CLIPS: Array[StringName] = [
	&"Idle", &"Walk", &"Run", &"CrouchIdle", &"CrouchWalk", &"Fall",
]


func _ready() -> void:
	_load_animation_library()
	animation_tree.active = true
	_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if _playback != null:
		_playback.start(&"Idle")

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_yaw = camera_arm.global_rotation.y
	_camera_pitch = camera_arm.global_rotation.x
	_setup_crouch_collision()
	_update_camera_arm()


func _input(event: InputEvent) -> void:
	if (
		controls_enabled
		and event is InputEventMouseMotion
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	):
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
		_apply_camera_input(mouse_motion.relative)


func _apply_camera_input(relative_motion: Vector2) -> void:
	_camera_yaw -= relative_motion.x * mouse_sensitivity
	_camera_pitch += relative_motion.y * mouse_sensitivity
	_camera_pitch = clampf(
		_camera_pitch,
		deg_to_rad(camera_pitch_min),
		deg_to_rad(camera_pitch_max)
	)


func _process(_delta: float) -> void:
	_update_camera_arm()


func _physics_process(delta: float) -> void:
	_update_crouch(delta)

	var grounded_before_move: bool = is_on_floor()
	if grounded_before_move:
		if velocity.y <= 0.0:
			velocity.y = -0.1
	elif not grounded_before_move:
		velocity.y += get_gravity().y * delta

	var movement_direction: Vector3 = Vector3.ZERO
	if controls_enabled:
		var input_vector: Vector2 = Input.get_vector(
			&"ui_left",
			&"ui_right",
			&"ui_up",
			&"ui_down"
		)
		movement_direction = Basis(Vector3.UP, _camera_yaw) * Vector3(
			input_vector.x,
			0.0,
			input_vector.y
		)
		if movement_direction.length_squared() > 1.0:
			movement_direction = movement_direction.normalized()

	if (
		controls_enabled
		and grounded_before_move
		and not _requested_crouch
		and Input.is_action_just_pressed(&"jump")
	):
		velocity.y = jump_velocity
		trigger_jump()

	var has_movement_input: bool = movement_direction.length_squared() > 0.0001
	var target_velocity: Vector3 = Vector3.ZERO
	if has_movement_input:
		var movement_speed: float = _get_movement_speed()
		target_velocity = movement_direction.normalized() * movement_speed

	var acceleration: float = ground_acceleration if grounded_before_move else air_acceleration
	if not has_movement_input and grounded_before_move:
		acceleration = ground_deceleration
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if has_movement_input:
		_cancel_turn_in_place()
		var target_angle: float = atan2(movement_direction.x, movement_direction.z)
		character_visual.global_rotation.y = rotate_toward(
			character_visual.global_rotation.y,
			target_angle,
			rotation_speed * delta
		)

	move_and_slide()
	_update_camera_arm()
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	_update_turn_in_place(
		delta,
		has_movement_input,
		horizontal_speed,
		is_on_floor()
	)
	set_animation_motion(horizontal_speed, _requested_crouch, is_on_floor(), velocity.y)


func _get_movement_speed() -> float:
	if _requested_crouch:
		return crouch_speed
	if Input.is_action_pressed(&"sprint"):
		return sprint_speed
	return walk_speed


## Can also be called by an external gameplay controller when controls are disabled.
func set_animation_motion(
	speed: float,
	crouching: bool,
	grounded: bool,
	vertical_speed: float = 0.0
) -> void:
	var was_grounded: bool = _requested_grounded
	_requested_speed = maxf(speed, 0.0)
	_requested_crouch = crouching
	_requested_grounded = grounded

	if _playback == null:
		return
	if not grounded:
		_cancel_turn_in_place()
		_playback.travel(&"Jump" if vertical_speed > 0.05 else &"Fall")
		return
	if not was_grounded:
		_playback.travel(&"Land")
		return
	if _is_turning:
		return

	_playback.travel(_get_ground_state())


func trigger_jump() -> void:
	if _playback == null or not _requested_grounded:
		return
	_cancel_turn_in_place()
	_requested_grounded = false
	_playback.travel(&"Jump")


func _get_ground_state() -> StringName:
	if _requested_crouch:
		return &"CrouchWalk" if _requested_speed > 0.1 else &"CrouchIdle"
	if _requested_speed >= run_threshold:
		return &"Run"
	if _requested_speed > 0.1:
		return &"Walk"
	return &"Idle"


func _update_turn_in_place(
	delta: float,
	has_movement_input: bool,
	horizontal_speed: float,
	grounded: bool
) -> void:
	if not grounded or has_movement_input or horizontal_speed > 0.1:
		_cancel_turn_in_place()
		return
	if _playback == null:
		return
	if _is_turning and _turn_crouching != _requested_crouch:
		_cancel_turn_in_place()

	if not _is_turning:
		var stable_state: StringName = (
			&"CrouchIdle" if _requested_crouch else &"Idle"
		)
		if _playback.get_current_node() != stable_state:
			return
		var yaw_difference: float = angle_difference(
			character_visual.global_rotation.y,
			_camera_yaw
		)
		if absf(yaw_difference) < deg_to_rad(turn_in_place_threshold):
			return
		_start_turn_in_place(yaw_difference)

	_turn_elapsed = minf(_turn_elapsed + delta, _turn_duration)
	var turn_weight: float = smoothstep(
		0.0,
		1.0,
		_turn_elapsed / maxf(_turn_duration, 0.001)
	)
	character_visual.global_rotation.y = lerp_angle(
		_turn_start_yaw,
		_turn_target_yaw,
		turn_weight
	)
	if _turn_elapsed >= _turn_duration:
		character_visual.global_rotation.y = _turn_target_yaw
		_is_turning = false
		_playback.travel(&"CrouchIdle" if _turn_crouching else &"Idle")


func _start_turn_in_place(yaw_difference: float) -> void:
	var turn_state: StringName
	var applied_yaw_difference: float = yaw_difference
	if _requested_crouch:
		turn_state = &"TurnCrouch90L" if yaw_difference > 0.0 else &"TurnCrouch90R"
		applied_yaw_difference = clampf(
			yaw_difference,
			-deg_to_rad(90.0),
			deg_to_rad(90.0)
		)
	elif absf(yaw_difference) >= deg_to_rad(turn_180_threshold):
		turn_state = &"TurnStand180L" if yaw_difference > 0.0 else &"TurnStand180R"
	else:
		turn_state = &"TurnStand90L" if yaw_difference > 0.0 else &"TurnStand90R"

	var turn_animation: Animation = animation_player.get_animation(turn_state)
	_is_turning = true
	_turn_crouching = _requested_crouch
	_turn_elapsed = 0.0
	_turn_duration = maxf(turn_animation.length, 0.001)
	_turn_start_yaw = character_visual.global_rotation.y
	_turn_target_yaw = _turn_start_yaw + applied_yaw_difference
	_playback.travel(turn_state)


func _cancel_turn_in_place() -> void:
	_is_turning = false
	_turn_elapsed = 0.0


func _setup_crouch_collision() -> void:
	if collision_shape.shape == null or not collision_shape.shape is CapsuleShape3D:
		return
	collision_shape.shape = collision_shape.shape.duplicate()
	var capsule: CapsuleShape3D = collision_shape.shape as CapsuleShape3D
	_standing_collision_height = capsule.height
	_standing_collision_y = collision_shape.position.y
	_collision_bottom = _standing_collision_y - _standing_collision_height * 0.5


func _update_crouch(delta: float) -> void:
	var was_crouching: bool = _requested_crouch
	var wants_to_crouch: bool = (
		controls_enabled
		and Input.is_action_pressed(&"crouch")
		and is_on_floor()
	)
	_requested_crouch = wants_to_crouch
	if was_crouching != _requested_crouch:
		_cancel_turn_in_place()
	var target_amount: float = 1.0 if wants_to_crouch else 0.0
	_crouch_amount = move_toward(
		_crouch_amount,
		target_amount,
		crouch_transition_speed * delta
	)

	if collision_shape.shape is CapsuleShape3D and _standing_collision_height > 0.0:
		var capsule: CapsuleShape3D = collision_shape.shape as CapsuleShape3D
		var crouching_height: float = _standing_collision_height * crouch_height_ratio
		capsule.height = lerpf(_standing_collision_height, crouching_height, _crouch_amount)
		collision_shape.position.y = _collision_bottom + capsule.height * 0.5


func _update_camera_arm() -> void:
	if not is_instance_valid(camera_arm):
		return
	camera_arm.global_position = global_position + Vector3.DOWN * crouch_camera_drop * _crouch_amount
	camera_arm.global_rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)


func _load_animation_library() -> void:
	var library: AnimationLibrary = AnimationLibrary.new()
	for animation_name: StringName in CLIPS:
		var packed_scene: PackedScene = CLIPS[animation_name]
		var source_root: Node = packed_scene.instantiate()
		var source_player: AnimationPlayer = (
			source_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		)
		if source_player == null:
			push_error("AnimationPlayer not found in clip: %s" % animation_name)
			source_root.free()
			continue

		var source_names: PackedStringArray = source_player.get_animation_list()
		if source_names.is_empty():
			push_error("Animation not found in clip: %s" % animation_name)
			source_root.free()
			continue

		var animation: Animation = (
			source_player.get_animation(source_names[0]).duplicate(true) as Animation
		)
		animation.loop_mode = Animation.LOOP_LINEAR if animation_name in LOOPING_CLIPS else Animation.LOOP_NONE
		library.add_animation(animation_name, animation)
		source_root.free()

	if animation_player.has_animation_library(&""):
		animation_player.remove_animation_library(&"")
	animation_player.add_animation_library(&"", library)
