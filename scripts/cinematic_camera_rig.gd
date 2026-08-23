class_name CinematicCameraRig
extends Node3D

## A lightly detached third-person camera. Input updates the desired pose while
## this rig eases toward it, leaving SpringArm3D responsible for obstructions.

@export_group("Framing")
@export_range(0.0, 2.0, 0.01) var pivot_height : float = 1.08
@export_range(-1.5, 1.5, 0.01) var shoulder_offset : float = 0.72

@export_group("Response")
@export_range(1.0, 30.0, 0.5) var position_response : float = 7.0
@export_range(1.0, 30.0, 0.5) var rotation_response : float = 9.0
@export_range(0.1, 3.0, 0.05) var maximum_follow_lag : float = 1.1
@export_range(1.0, 30.0, 0.5) var teleport_snap_distance : float = 8.0

@export_group("Organic Motion")
@export_range(0.0, 0.08, 0.001) var walk_sway_amount : float = 0.026
@export_range(0.0, 0.04, 0.001) var walk_vertical_amount : float = 0.012
@export_range(0.0, 5.0, 0.05) var walk_sway_frequency : float = 1.65
@export_range(0.0, 0.03, 0.001) var idle_breath_amount : float = 0.008
@export_range(0.0, 2.0, 0.05) var idle_breath_frequency : float = 0.22
@export_range(0.0, 0.2, 0.005) var turn_parallax_amount : float = 0.11

@onready var pitch_pivot : Node3D = $PitchPivot
@onready var shoulder : Node3D = $PitchPivot/ShoulderOffset
@onready var spring_arm : SpringArm3D = $PitchPivot/ShoulderOffset/SpringArm3D
@onready var camera : Camera3D = (
	$PitchPivot/ShoulderOffset/SpringArm3D/Camera3D
)

var _target_position : Vector3
var _target_yaw : float = 0.0
var _target_pitch : float = 0.0
var _target_crouch_drop : float = 0.0
var _target_speed : float = 0.0
var _target_grounded : bool = true
var _motion_blend : float = 0.0
var _sway_phase : float = 0.0
var _elapsed : float = 0.0
var _has_target : bool = false


func _ready() -> void:
	top_level = true
	process_priority = 10

	var followed_body := get_parent() as CollisionObject3D
	if followed_body != null:
		spring_arm.add_excluded_object(followed_body.get_rid())

	_target_position = global_position
	_target_yaw = global_rotation.y
	_target_pitch = pitch_pivot.rotation.x


func set_target_pose(
	position : Vector3,
	yaw : float,
	pitch : float,
	crouch_drop : float,
	horizontal_speed : float,
	grounded : bool,
	snap : bool = false
) -> void:
	_target_position = position
	_target_yaw = yaw
	_target_pitch = pitch
	_target_crouch_drop = crouch_drop
	_target_speed = horizontal_speed
	_target_grounded = grounded
	_has_target = true

	if snap or global_position.distance_to(position) >= teleport_snap_distance:
		_snap_to_target()


func get_camera() -> Camera3D:
	return camera


func _process(delta : float) -> void:
	if not _has_target:
		return

	_elapsed += delta
	var position_weight := 1.0 - exp(-position_response * delta)
	var rotation_weight := 1.0 - exp(-rotation_response * delta)

	global_position = global_position.lerp(_target_position, position_weight)
	var follow_offset := global_position - _target_position
	if follow_offset.length() > maximum_follow_lag:
		global_position = (
			_target_position + follow_offset.normalized() * maximum_follow_lag
		)

	rotation.y = lerp_angle(rotation.y, _target_yaw, rotation_weight)
	pitch_pivot.rotation.x = lerp_angle(
		pitch_pivot.rotation.x,
		_target_pitch,
		rotation_weight
	)

	_update_organic_motion(delta, position_weight, rotation_weight)


func _snap_to_target() -> void:
	global_position = _target_position
	rotation = Vector3(0.0, _target_yaw, 0.0)
	pitch_pivot.rotation.x = _target_pitch


func _update_organic_motion(
	delta : float,
	position_weight : float,
	rotation_weight : float
) -> void:
	var desired_motion := 0.0
	if _target_grounded:
		desired_motion = clampf(_target_speed / 3.0, 0.0, 1.0)
	_motion_blend = lerpf(_motion_blend, desired_motion, position_weight)
	_sway_phase += delta * walk_sway_frequency * TAU * lerpf(
		0.72,
		1.12,
		_motion_blend
	)

	var breath := sin(_elapsed * idle_breath_frequency * TAU)
	var lateral_sway := sin(_sway_phase) * walk_sway_amount * _motion_blend
	var vertical_sway := (
		(0.5 - 0.5 * cos(_sway_phase * 2.0))
		* walk_vertical_amount
		* _motion_blend
	)
	vertical_sway += breath * idle_breath_amount * (1.0 - _motion_blend * 0.7)

	pitch_pivot.position = Vector3(
		lateral_sway,
		pivot_height - _target_crouch_drop + vertical_sway,
		0.0
	)

	var yaw_lag := wrapf(_target_yaw - rotation.y, -PI, PI)
	var parallax := clampf(
		yaw_lag * turn_parallax_amount,
		-turn_parallax_amount,
		turn_parallax_amount
	)
	shoulder.position.x = lerpf(
		shoulder.position.x,
		shoulder_offset + parallax,
		rotation_weight
	)

	var walk_roll := sin(_sway_phase) * deg_to_rad(0.10) * _motion_blend
	var turn_roll := clampf(yaw_lag * 0.012, -0.004, 0.004)
	var idle_roll := breath * deg_to_rad(0.025) * (1.0 - _motion_blend)
	camera.rotation.z = lerpf(
		camera.rotation.z,
		walk_roll + turn_roll + idle_roll,
		rotation_weight
	)
