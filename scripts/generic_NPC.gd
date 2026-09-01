class_name GenericNPC
extends CharacterBody3D

## Lightweight decorative NPC for the AlienShip interior.
## PATROL chooses reachable points from a baked NavigationRegion3D and waits at
## each destination. IDLE remains in place.

enum Behavior {
	IDLE,
	PATROL,
}

@export_category("Behavior")
@export var behavior: Behavior = Behavior.IDLE
@export_range(0.1, 10.0, 0.1) var movement_speed: float = 1.5
@export_range(0.0, 720.0, 1.0) var turn_speed_degrees: float = 180.0
@export_range(0.0, 30.0, 0.1) var patrol_wait_time: float = 1.0
@export_range(0.0, 20.0, 0.1) var minimum_patrol_distance: float = 1.0
@export_node_path("NavigationRegion3D") var navigation_region_path: NodePath

@export_category("Animation")
@export var idle_animation: StringName = &"Idle"
@export var movement_animation: StringName = &"Walk"
@export_range(0.0, 1.0, 0.01) var animation_blend_time: float = 0.15

@export_category("Physics")
@export_range(0.0, 50.0, 0.1) var gravity: float = 9.8

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var animation_player: AnimationPlayer = $VisualRoot/AnimationPlayer

var _patrol_space: Node3D
var _navigation_region: NavigationRegion3D
var _patrol_target_local: Vector3 = Vector3.ZERO
var _has_patrol_target: bool = false
var _wait_remaining: float = 0.0
var _is_moving: bool = false
var _current_animation: StringName = &""


func _ready() -> void:
	_patrol_space = get_parent() as Node3D
	_navigation_region = get_node_or_null(navigation_region_path) as NavigationRegion3D
	# The character origin sits below the baked polygon. Movement is horizontal,
	# so this must tolerate that vertical separation or the agent never advances
	# beyond path point zero.
	navigation_agent.path_desired_distance = 0.6
	navigation_agent.target_desired_distance = 0.2
	_set_moving(false)


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	if behavior == Behavior.PATROL:
		_update_patrol(delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_set_moving(false)
	move_and_slide()


func _update_patrol(delta: float) -> void:
	if _wait_remaining > 0.0:
		_wait_remaining = maxf(_wait_remaining - delta, 0.0)
		velocity.x = 0.0
		velocity.z = 0.0
		_set_moving(false)
		return

	if not _has_patrol_target and not _choose_patrol_target():
		velocity.x = 0.0
		velocity.z = 0.0
		_set_moving(false)
		return

	var target_position: Vector3 = _get_patrol_target()
	var target_direction: Vector3 = target_position - global_position
	target_direction.y = 0.0
	if target_direction.length_squared() <= 0.04:
		_arrive_at_patrol_point()
		return

	navigation_agent.target_position = target_position
	var movement_target: Vector3 = navigation_agent.get_next_path_position()

	var direction: Vector3 = movement_target - global_position
	direction.y = 0.0
	# NavigationServer may need a physics tick to synchronize a newly baked or
	# moving region. A next point equal to our position means "wait for a path",
	# not that the actual patrol target was reached.
	if direction.length_squared() <= 0.0001:
		velocity.x = 0.0
		velocity.z = 0.0
		_set_moving(false)
		return

	direction = direction.normalized()
	velocity.x = direction.x * movement_speed
	velocity.z = direction.z * movement_speed
	_turn_towards(direction, delta)
	_set_moving(true)


func _choose_patrol_target() -> bool:
	if _navigation_region == null:
		return false
	var navigation_map: RID = navigation_agent.get_navigation_map()
	if (
		not navigation_map.is_valid()
		or NavigationServer3D.map_get_iteration_id(navigation_map) == 0
	):
		return false

	var region_rid: RID = _navigation_region.get_rid()
	var selected_position: Vector3 = global_position
	for attempt: int in range(8):
		selected_position = NavigationServer3D.region_get_random_point(
			region_rid,
			navigation_agent.navigation_layers,
			true
		)
		var horizontal_offset: Vector3 = selected_position - global_position
		horizontal_offset.y = 0.0
		if horizontal_offset.length() >= minimum_patrol_distance or attempt == 7:
			break

	if _patrol_space != null:
		_patrol_target_local = _patrol_space.to_local(selected_position)
	else:
		_patrol_target_local = selected_position
	_has_patrol_target = true
	return true


func _get_patrol_target() -> Vector3:
	if _patrol_space != null:
		return _patrol_space.to_global(_patrol_target_local)
	return _patrol_target_local


func _arrive_at_patrol_point() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_set_moving(false)
	_wait_remaining = patrol_wait_time
	_has_patrol_target = false


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
