extends RigidBody3D

@export_range(0.0, 20.0, 0.1) var patrol_speed: float = 3.0
@export_range(0.0, 720.0, 1.0) var rotation_speed_degrees: float = 180.0
@export_range(0.0, 10.0, 0.1) var stop_duration: float = 0.1
@export_range(0.0, 5.0, 0.01) var float_height: float = 0.1
@export_range(0.0, 10.0, 0.1) var float_speed: float = 3.0

@export var pos1: Vector3 = Vector3(0, 0, 0)
@export var pos2: Vector3 = Vector3(0, 0, 0)
@export var pos3: Vector3 = Vector3(0, 0, 0)

var _positions: Array[Vector3]
var _current_position_index: int = 0
var _target_position: Vector3

var _patrol_position: Vector3
var _float_time: float = 0.0
var _stop_time: float = 0.0

enum PatrolState {
	ROTATING,
	MOVING,
	STOPPED,
}

var _patrol_state: PatrolState = PatrolState.STOPPED


func _ready() -> void:
	var patrol_height: float = position.y
	_positions = [
		Vector3(pos1.x, patrol_height, pos1.z),
		Vector3(pos2.x, patrol_height, pos2.z),
		Vector3(pos3.x, patrol_height, pos3.z),
	]

	# Start at position 1.
	_patrol_position = _positions[0]
	position = _patrol_position
	_current_position_index = 0

	_set_next_target()


func _physics_process(delta: float) -> void:
	_update_patrol(delta)
	_update_floating(delta)


func _set_next_target() -> void:
	var next_index: int = (_current_position_index + 1) % _positions.size()
	_target_position = _positions[next_index]

	_patrol_state = PatrolState.ROTATING


func _update_patrol(delta: float) -> void:
	if _positions.size() < 2 or patrol_speed <= 0.0:
		return

	match _patrol_state:
		PatrolState.ROTATING:
			_rotate_towards_target(delta)

		PatrolState.MOVING:
			_move_towards_target(delta)

		PatrolState.STOPPED:
			_stop_time += delta

			if _stop_time >= stop_duration:
				_current_position_index = (_current_position_index + 1) % _positions.size()
				_set_next_target()


func _rotate_towards_target(delta: float) -> void:
	var move_direction: Vector3 = _target_position - _patrol_position

	# Only use the horizontal direction for yaw.
	move_direction.y = 0.0

	if move_direction.length_squared() < 0.0001:
		_patrol_state = PatrolState.MOVING
		return

	move_direction = move_direction.normalized()

	# Godot's forward direction is -Z.
	var target_yaw: float = atan2(-move_direction.x, -move_direction.z)

	var rotation_step: float = deg_to_rad(rotation_speed_degrees) * delta

	rotation.y = rotate_toward(
		rotation.y,
		target_yaw,
		rotation_step
	)

	if is_equal_approx(rotation.y, target_yaw):
		_patrol_state = PatrolState.MOVING


func _move_towards_target(delta: float) -> void:
	_patrol_position = _patrol_position.move_toward(
		_target_position,
		patrol_speed * delta
	)

	if _patrol_position.is_equal_approx(_target_position):
		_patrol_position = _target_position
		_stop_time = 0.0
		_patrol_state = PatrolState.STOPPED


func _update_floating(delta: float) -> void:
	_float_time += delta

	var vertical_offset: float = sin(_float_time * float_speed) * float_height
	position = _patrol_position + Vector3.UP * vertical_offset
