class_name GenericNPC
extends CharacterBody3D

## Lightweight decorative NPC for the AlienShip interior.
## PATROL follows the Marker3D children of Behaviors/Patrol/Points and waits
## at each one. IDLE remains in place. Navigation is optional because the ship
## currently has no NavigationRegion3D; direct waypoint movement works now.

enum Behavior {
	IDLE,
	PATROL,
}

@export_category("Behavior")
@export var behavior: Behavior = Behavior.IDLE
@export_range(0.1, 10.0, 0.1) var movement_speed: float = 1.5
@export_range(0.0, 720.0, 1.0) var turn_speed_degrees: float = 240.0
@export_range(0.0, 30.0, 0.1) var patrol_wait_time: float = 2.0
@export var loop_patrol: bool = true
@export var navigation_enabled: bool = false

@export_category("Animation")
@export var idle_animation: StringName = &"Idle"
@export var movement_animation: StringName = &"Walk"
@export_range(0.0, 1.0, 0.01) var animation_blend_time: float = 0.15

@export_category("Physics")
@export_range(0.0, 50.0, 0.1) var gravity: float = 9.8

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var animation_player: AnimationPlayer = $VisualRoot/AnimationPlayer
@onready var patrol_points: Node3D = $Behaviors/Patrol/Points

var _patrol_space: Node3D
var _patrol_positions: Array[Vector3] = []
var _patrol_index: int = 0
var _patrol_direction: int = 1
var _wait_remaining: float = 0.0
var _is_moving: bool = false
var _current_animation: StringName = &""


func _ready() -> void:
	_patrol_space = get_parent() as Node3D
	_cache_patrol_points()
	navigation_agent.path_desired_distance = 0.15
	navigation_agent.target_desired_distance = 0.2
	_set_moving(false)


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	if behavior == Behavior.PATROL and not _patrol_positions.is_empty():
		_update_patrol(delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_set_moving(false)
	move_and_slide()


func _cache_patrol_points() -> void:
	_patrol_positions.clear()
	for child: Node in patrol_points.get_children():
		var marker: Marker3D = child as Marker3D
		if marker == null:
			continue
		if _patrol_space != null:
			_patrol_positions.append(_patrol_space.to_local(marker.global_position))
		else:
			_patrol_positions.append(marker.global_position)


func _update_patrol(delta: float) -> void:
	if _wait_remaining > 0.0:
		_wait_remaining = maxf(_wait_remaining - delta, 0.0)
		velocity.x = 0.0
		velocity.z = 0.0
		_set_moving(false)
		return

	var target_position: Vector3 = _get_patrol_position(_patrol_index)
	var movement_target: Vector3 = target_position
	if navigation_enabled:
		navigation_agent.target_position = target_position
		movement_target = navigation_agent.get_next_path_position()

	var direction: Vector3 = movement_target - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.04:
		_arrive_at_patrol_point()
		return

	direction = direction.normalized()
	velocity.x = direction.x * movement_speed
	velocity.z = direction.z * movement_speed
	_turn_towards(direction, delta)
	_set_moving(true)


func _get_patrol_position(index: int) -> Vector3:
	var stored_position: Vector3 = _patrol_positions[index]
	if _patrol_space != null:
		return _patrol_space.to_global(stored_position)
	return stored_position


func _arrive_at_patrol_point() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_set_moving(false)
	_wait_remaining = patrol_wait_time
	if _patrol_positions.size() <= 1:
		return

	var next_index: int = _patrol_index + _patrol_direction
	if next_index >= _patrol_positions.size() or next_index < 0:
		if loop_patrol:
			next_index = posmod(next_index, _patrol_positions.size())
		else:
			_patrol_direction *= -1
			next_index = _patrol_index + _patrol_direction
	_patrol_index = next_index


func _turn_towards(direction: Vector3, delta: float) -> void:
	var target_yaw: float = atan2(-direction.x, -direction.z)
	var turn_step: float = deg_to_rad(turn_speed_degrees) * delta
	global_rotation.y = rotate_toward(global_rotation.y, target_yaw, turn_step)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta


func _set_moving(moving: bool) -> void:
	if _is_moving == moving and not _current_animation.is_empty():
		return
	_is_moving = moving
	var animation_name: StringName = movement_animation if moving else idle_animation
	_play_animation(animation_name)


func _play_animation(animation_name: StringName) -> void:
	if animation_name.is_empty() or not animation_player.has_animation(animation_name):
		_current_animation = &""
		return
	if _current_animation == animation_name:
		return
	animation_player.play(animation_name, animation_blend_time)
	_current_animation = animation_name
