extends "res://scripts/spaceship_scraps.gd"

signal pickup_requested(player: Node3D)
signal drop_requested(player: Node3D)

const PICKUP_RADIUS: float = 2.0
@export var network_id: StringName = &""
var _home: Node3D
var _target_pose: Transform3D
var _has_world_pose: bool = false
var network_consumed: bool = false


func is_available_for_abduction() -> bool:
	return not network_consumed and super.is_available_for_abduction()


func _ready() -> void:
	_home = get_parent() as Node3D
	freeze = true


func pickup(player: Node3D) -> void:
	pickup_requested.emit(player)


func drop() -> void:
	if is_instance_valid(carrier):
		drop_requested.emit(carrier)


func can_pickup(player: CharacterBody3D) -> bool:
	if not is_available_for_abduction() or player.get_world_3d() != get_world_3d():
		return false
	if not bool(player.call("is_alive")) or player.get("carried_item") != null or player.get("carried_character") != null:
		return false
	if player.global_position.distance_to(global_position) >= PICKUP_RADIUS:
		return false
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		player.global_position + player.global_basis.y, get_pickup_target_position(), 1, [player.get_rid(), get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func get_pickup_target_position() -> Vector3:
	var shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	return shape.global_position if shape != null else global_position


func apply_network_state(player: Node3D, pose: Transform3D, motion: Vector3, simulate_world: bool) -> void:
	if network_consumed:
		return
	if is_instance_valid(carrier) and carrier == player:
		return
	freeze = true
	if carried:
		carried = false
		carrier = null
		reparent(_home)
		collision_layer = _saved_collision_layer
		collision_mask = _saved_collision_mask
	if player != null:
		super.pickup(player)
		player.set("carried_item", self)
		tree_exiting.connect(player._clear_exploration_hands, CONNECT_ONE_SHOT)
		player.animation_controller.set_carry_mode(two_handed)
		player.emit_signal("exploration_inventory_changed")
		if bool(player.call("is_local_player")):
			player.emit_signal("item_collected", self)
	else:
		global_transform = pose
		_target_pose = pose
		_has_world_pose = true
		linear_velocity = motion
		angular_velocity = Vector3.ZERO
		freeze = not simulate_world


func receive_world_pose(pose: Transform3D, motion: Vector3) -> void:
	if carried:
		return
	_target_pose = pose
	_has_world_pose = true
	linear_velocity = motion


func _physics_process(delta: float) -> void:
	if freeze and not carried and _has_world_pose:
		global_transform = global_transform.interpolate_with(_target_pose, 1.0 - exp(-20.0 * delta))
