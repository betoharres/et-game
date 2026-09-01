extends RigidBody3D

@export_range(0.0, 100.0, 0.1) var patrol_distance: float = 6.0
@export_range(0.0, 20.0, 0.1) var patrol_speed: float = 2.0
@export_range(0.0, 720.0, 1.0) var rotation_speed_degrees: float = 180.0
@export_range(0.0, 10.0, 0.1) var stop_duration: float = 1.0
@export_range(0.0, 5.0, 0.01) var float_height: float = 0.2
@export_range(0.0, 10.0, 0.1) var float_speed: float = 2.0

var _patrol_origin: Vector3
var _patrol_offset: float = 0.0
var _patrol_direction: float = 1.0
var _float_time: float = 0.0
var _stop_time: float = 0.0

enum PatrolState {
	ROTATING,
	MOVING,
	STOPPED,
}

var _patrol_state: PatrolState = PatrolState.STOPPED


func _ready() -> void:
	_patrol_origin = position


func _physics_process(delta: float) -> void:
	_update_patrol(delta)
	_update_floating(delta)


func _update_patrol(delta: float) -> void:
	if patrol_distance <= 0.0 or patrol_speed <= 0.0:
		_patrol_offset = 0.0
		return

	match _patrol_state:
		PatrolState.ROTATING:
			_rotate_towards_patrol_direction(delta)
		PatrolState.MOVING:
			_move_towards_patrol_end(delta)
		PatrolState.STOPPED:
			_stop_time += delta
			if _stop_time >= stop_duration:
				_patrol_direction *= -1.0
				_patrol_state = PatrolState.ROTATING


func _rotate_towards_patrol_direction(delta: float) -> void:
	var move_direction: Vector3 = Vector3.RIGHT * _patrol_direction
	var target_yaw: float = atan2(move_direction.x, move_direction.z)
	var rotation_step: float = deg_to_rad(rotation_speed_degrees) * delta
	rotation.y = rotate_toward(rotation.y, target_yaw, rotation_step)

	if is_equal_approx(rotation.y, target_yaw):
		_patrol_state = PatrolState.MOVING


func _move_towards_patrol_end(delta: float) -> void:
	var target_offset: float = patrol_distance * _patrol_direction
	_patrol_offset = move_toward(_patrol_offset, target_offset, patrol_speed * delta)

	if is_equal_approx(_patrol_offset, target_offset):
		_stop_time = 0.0
		_patrol_state = PatrolState.STOPPED


func _update_floating(delta: float) -> void:
	_float_time += delta
	var vertical_offset: float = sin(_float_time * float_speed) * float_height
	position = (
		_patrol_origin
		+ Vector3.RIGHT * _patrol_offset
		+ Vector3.UP * vertical_offset
	)
