extends Node3D

const ARRIVAL_BEAM_SCENE : PackedScene = preload("res://scenes/FX/ArrivalBeam.tscn")

enum BehaviorState {
	STOWED,
	DESCENDING,
	GOING_TO_ITEM,
	CARRYING_TO_DELIVERY,
	WAITING_FOR_DELIVERY,
	RETURNING_TO_SHIP,
	ASCENDING,
}

@export_category("Task")
@export var move_speed : float = 10.0
@export var turn_speed : float = 2.0
@export var ground_offset : float = 1.0
@export var item_ship_radius : float = 45.0
@export var interaction_distance : float = 1.8
@export var ship_node : Node3D
@export var delivery_area : Node3D

@export_category("Deployment")
@export var ship_stow_offset : Vector3 = Vector3.ZERO
@export_range(1.0, 30.0, 0.5) var beam_travel_speed : float = 10.0
@export_range(0.1, 10.0, 0.1) var min_beam_duration : float = 2.0
@export_range(0.1, 10.0, 0.1) var max_beam_duration : float = 4.5
@export_range(0.0, 10.0, 0.1) var beam_height_margin : float = 3.0
@export_range(0.0, 2.0, 0.05) var beam_hold_duration : float = 0.35
@export_range(0.1, 2.0, 0.05) var beam_fade_duration : float = 0.6
@export_range(10.0, 300.0, 1.0) var ground_probe_distance : float = 100.0
@export_flags_3d_physics var ground_collision_mask : int = 1
@export var fallback_ground_y : float = 0.0

@onready var fl_leg : Marker3D = $FrontLeftIKTarget
@onready var fr_leg : Marker3D = $FrontRightIKTarget
@onready var bl_leg : Marker3D = $BackLeftIKTarget
@onready var br_leg : Marker3D = $BackRightIKTarget
@onready var step_target_container : Node3D = $StepTargetContainer

var _state : BehaviorState = BehaviorState.STOWED
var _target_item : RigidBody3D
var _transition_start : Vector3
var _transition_end : Vector3
var _transition_elapsed : float = 0.0
var _transition_duration : float = 0.0
var _active_beam : ArrivalBeam
var _awaiting_delivery_score : bool = false
var _expected_delivery_score : int = 0
var _leg_targets : Array[Marker3D] = []
var _leg_iks : Array[SkeletonIK3D] = []
var _deployment_requested : bool = false
var _leg_reset_requested : bool = false
# Motion completed during the current fixed tick. The IK target rig consumes
# these values directly so its offset shrinks and grows with the root motion.
var current_velocity : Vector3 = Vector3.ZERO
var current_rotation_velocity : float = 0.0


func _ready() -> void:
	_leg_targets = [fl_leg, fr_leg, bl_leg, br_leg]
	_leg_iks = [
		$Armature/Skeleton3D/FrontLeftIK,
		$Armature/Skeleton3D/FrontRightIK,
		$Armature/Skeleton3D/BackLeftIK,
		$Armature/Skeleton3D/BackRightIK,
	]
	_resolve_references()
	_set_terrestrial_processing(false)
	_enter_stowed()


func _physics_process(delta : float) -> void:
	var motion_start : Vector3 = global_position
	var forward_start : Vector3 = _get_horizontal_forward()
	current_velocity = Vector3.ZERO
	current_rotation_velocity = 0.0
	
	$Armature/Skeleton3D/Eye.rotation.y += 0.1

	if _leg_reset_requested:
		_leg_reset_requested = false
		_set_terrestrial_processing(true)
		_reset_leg_targets_to_ground()

	match _state:
		BehaviorState.STOWED:
			_update_stowed()
		BehaviorState.DESCENDING:
			_update_descent(delta)
		BehaviorState.ASCENDING:
			_update_ascent(delta)
		_:
			_apply_ground_alignment(delta)
			_update_ground_behavior(delta)

	_capture_current_motion(motion_start, forward_start)
	if _state != BehaviorState.STOWED or not _deployment_requested:
		return
	_deployment_requested = false
	if _is_valid_item(_target_item) and not _is_delivery_busy():
		_start_descent()


func _capture_current_motion(
	motion_start : Vector3,
	forward_start : Vector3
) -> void:
	current_velocity = global_position - motion_start
	current_velocity.y = 0.0
	current_rotation_velocity = forward_start.signed_angle_to(
		_get_horizontal_forward(),
		Vector3.UP
	)


func _get_horizontal_forward() -> Vector3:
	var forward : Vector3 = -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


func _resolve_references() -> void:
	if ship_node == null or not is_instance_valid(ship_node):
		ship_node = get_tree().get_first_node_in_group("ufo_lighting") as Node3D
	if delivery_area == null or not is_instance_valid(delivery_area):
		delivery_area = get_tree().get_first_node_in_group("delivery_areas") as Node3D
	_connect_delivery_signal()


func _connect_delivery_signal() -> void:
	if delivery_area == null or not delivery_area.has_signal("item_delivered"):
		return
	var callback : Callable = Callable(self, "_on_item_delivered")
	if not delivery_area.is_connected("item_delivered", callback):
		delivery_area.connect("item_delivered", callback)


func _enter_stowed() -> void:
	_state = BehaviorState.STOWED
	_target_item = null
	_deployment_requested = false
	_awaiting_delivery_score = false
	_expected_delivery_score = 0
	visible = false
	if ship_node != null and is_instance_valid(ship_node):
		global_position = _get_stowed_position()


func _update_stowed() -> void:
	_resolve_references()
	if ship_node == null:
		return
	global_position = _get_stowed_position()
	if _is_delivery_busy():
		return

	_target_item = _find_item_near_ship()
	if _target_item != null:
		_deployment_requested = true


func _start_descent() -> void:
	var ground_position : Vector3 = _find_ground_below_ship()
	_transition_start = _get_stowed_position()
	_transition_end = ground_position + Vector3.UP * ground_offset
	_transition_elapsed = 0.0
	_transition_duration = _get_beam_duration(
		_transition_start.distance_to(_transition_end)
	)
	global_position = _transition_start
	visible = true
	_active_beam = _spawn_arrival_beam(
		ground_position,
		maxf(_transition_start.y - ground_position.y, 1.0) + beam_height_margin
	)
	_state = BehaviorState.DESCENDING


func _update_descent(delta : float) -> void:
	_transition_elapsed = minf(_transition_elapsed + delta, _transition_duration)
	var progress : float = _get_transition_progress()
	global_position = _transition_start.lerp(
		_transition_end,
		smoothstep(0.0, 1.0, progress)
	)
	if progress < 1.0:
		return

	global_position = _transition_end
	_leg_reset_requested = true
	_fade_beam_after_hold(_active_beam)
	_active_beam = null
	if _is_valid_item(_target_item):
		_state = BehaviorState.GOING_TO_ITEM
	else:
		_begin_return_to_ship()


func _update_ground_behavior(delta : float) -> void:
	match _state:
		BehaviorState.GOING_TO_ITEM:
			_go_to_item(delta)
		BehaviorState.CARRYING_TO_DELIVERY:
			_go_to_delivery(delta)
		BehaviorState.WAITING_FOR_DELIVERY:
			_wait_for_delivery()
		BehaviorState.RETURNING_TO_SHIP:
			_return_to_ship(delta)


func _go_to_item(delta : float) -> void:
	if not _is_valid_item(_target_item):
		_begin_return_to_ship()
		return
	_move_towards(_target_item.global_position, delta)
	if _horizontal_distance_to(_target_item.global_position) <= interaction_distance:
		_pick_up_target_item()


func _go_to_delivery(delta : float) -> void:
	if delivery_area == null or not _is_target_carried_by_bot():
		_abandon_target_and_return()
		return
	_move_towards(delivery_area.global_position, delta)
	if _horizontal_distance_to(delivery_area.global_position) > interaction_distance:
		return
	if _is_delivery_busy():
		return
	_drop_at_delivery()


func _wait_for_delivery() -> void:
	if delivery_area == null or not delivery_area.has_method("is_delivery_active"):
		_abandon_target_and_return()
		return
	if _awaiting_delivery_score and not bool(delivery_area.call("is_delivery_active")):
		push_warning("Spider delivery ended without an item_delivered score confirmation.")
		_abandon_target_and_return()


func _on_item_delivered(item_score : int) -> void:
	if _state != BehaviorState.WAITING_FOR_DELIVERY or not _awaiting_delivery_score:
		return
	if item_score != _expected_delivery_score:
		push_warning(
			"Spider delivery score mismatch: expected %d, received %d."
			% [_expected_delivery_score, item_score]
		)
	_awaiting_delivery_score = false
	_expected_delivery_score = 0
	_target_item = null
	_begin_return_to_ship()


func _return_to_ship(delta : float) -> void:
	if ship_node == null or not is_instance_valid(ship_node):
		_resolve_references()
		if ship_node == null:
			_enter_stowed()
			return
	_move_towards(ship_node.global_position, delta)
	if _horizontal_distance_to(ship_node.global_position) <= interaction_distance:
		_start_ascent()


func _start_ascent() -> void:
	_transition_start = global_position
	_transition_end = _get_stowed_position()
	_transition_elapsed = 0.0
	_transition_duration = _get_beam_duration(
		_transition_start.distance_to(_transition_end)
	)
	var beam_origin : Vector3 = _transition_start - Vector3.UP * ground_offset
	_active_beam = _spawn_arrival_beam(
		beam_origin,
		maxf(_transition_end.y - beam_origin.y, 1.0) + beam_height_margin
	)
	_set_terrestrial_processing(false)
	_state = BehaviorState.ASCENDING


func _update_ascent(delta : float) -> void:
	if ship_node == null or not is_instance_valid(ship_node):
		_enter_stowed()
		return
	_transition_elapsed = minf(_transition_elapsed + delta, _transition_duration)
	var progress : float = _get_transition_progress()
	_transition_end = _get_stowed_position()
	global_position = _transition_start.lerp(
		_transition_end,
		smoothstep(0.0, 1.0, progress)
	)
	if progress < 1.0:
		return

	global_position = _transition_end
	visible = false
	_fade_beam_after_hold(_active_beam)
	_active_beam = null
	_enter_stowed()


func _find_item_near_ship() -> RigidBody3D:
	if ship_node == null:
		return null
	var closest_item : RigidBody3D
	var closest_distance : float = item_ship_radius * item_ship_radius
	var ship_position : Vector2 = Vector2(ship_node.global_position.x, ship_node.global_position.z)
	for candidate : Node in get_tree().get_nodes_in_group("pickup_items"):
		if not candidate is RigidBody3D:
			continue
		var item : RigidBody3D = candidate as RigidBody3D
		if not _is_valid_item(item):
			continue
		var item_position : Vector2 = Vector2(item.global_position.x, item.global_position.z)
		var distance : float = ship_position.distance_squared_to(item_position)
		if distance <= closest_distance:
			closest_distance = distance
			closest_item = item
	return closest_item


func _is_valid_item(item : RigidBody3D) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if item.has_method("is_available_for_abduction"):
		return bool(item.call("is_available_for_abduction"))
	return not bool(item.get("carried"))


func _is_target_carried_by_bot() -> bool:
	if _target_item == null or not is_instance_valid(_target_item):
		return false
	return bool(_target_item.get("carried")) and _target_item.get("carrier") == self


func _pick_up_target_item() -> void:
	if not _is_valid_item(_target_item):
		_begin_return_to_ship()
		return
	_target_item.call("pickup", self)
	if _is_target_carried_by_bot():
		_state = BehaviorState.CARRYING_TO_DELIVERY
		## activate effect
	else:
		_begin_return_to_ship()


func _drop_at_delivery() -> void:
	if not _is_target_carried_by_bot():
		_begin_return_to_ship()
		return
	var score_value : Variant = _target_item.get("score_value")
	_expected_delivery_score = int(score_value) if score_value != null else 0
	_target_item.call("drop")
	var delivery_requested : bool = false
	if delivery_area.has_method("request_automatic_delivery"):
		delivery_requested = bool(delivery_area.call(
			"request_automatic_delivery",
			_target_item,
			self
		))
	if delivery_requested:
		_awaiting_delivery_score = true
		_state = BehaviorState.WAITING_FOR_DELIVERY
	else:
		_abandon_target_and_return()


func _is_delivery_busy() -> bool:
	return (
		delivery_area != null
		and delivery_area.has_method("is_delivery_active")
		and bool(delivery_area.call("is_delivery_active"))
	)


func _begin_return_to_ship() -> void:
	_state = BehaviorState.RETURNING_TO_SHIP


func _abandon_target_and_return() -> void:
	if _is_target_carried_by_bot():
		_target_item.call("drop")
	_target_item = null
	_awaiting_delivery_score = false
	_expected_delivery_score = 0
	_begin_return_to_ship()


func _move_towards(target : Vector3, delta : float) -> void:
	var horizontal_target : Vector3 = Vector3(target.x, global_position.y, target.z)
	var offset : Vector3 = horizontal_target - global_position
	if offset.length() <= 0.01:
		return
	var direction : Vector3 = offset.normalized()
	global_position = global_position.move_toward(horizontal_target, move_speed * delta)
	var desired_yaw : float = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, turn_speed * delta)


func _horizontal_distance_to(target : Vector3) -> float:
	return Vector2(global_position.x, global_position.z).distance_to(
		Vector2(target.x, target.z)
	)


func _apply_ground_alignment(delta : float) -> void:
	var plane1 : Plane = Plane(bl_leg.global_position, fl_leg.global_position, fr_leg.global_position)
	var plane2 : Plane = Plane(fr_leg.global_position, br_leg.global_position, bl_leg.global_position)
	var avg_normal : Vector3 = (plane1.normal + plane2.normal).normalized()
	if avg_normal.length_squared() <= 0.0001:
		return
	if avg_normal.dot(Vector3.UP) < 0.0:
		avg_normal = -avg_normal
	if avg_normal.dot(Vector3.UP) < 0.35:
		avg_normal = Vector3.UP

	var current_basis : Basis = transform.basis.orthonormalized()
	var target_basis : Basis = _basis_from_normal(avg_normal).orthonormalized()
	transform.basis = current_basis.slerp(
		target_basis,
		clampf(move_speed * delta, 0.0, 1.0)
	).orthonormalized()
	var avg_position : Vector3 = (
		fl_leg.global_position
		+ fr_leg.global_position
		+ bl_leg.global_position
		+ br_leg.global_position
	) / 4.0
	var target_position : Vector3 = avg_position + global_transform.basis.y * ground_offset
	var distance : float = global_transform.basis.y.dot(target_position - global_position)
	global_position = global_position.lerp(
		global_position + global_transform.basis.y * distance,
		clampf(move_speed * delta, 0.0, 1.0)
	)


func _basis_from_normal(normal : Vector3) -> Basis:
	var result : Basis = Basis()
	result.x = normal.cross(transform.basis.z)
	result.y = normal
	result.z = transform.basis.x.cross(normal)
	result = result.orthonormalized()
	result.x *= scale.x
	result.y *= scale.y
	result.z *= scale.z
	return result


func _find_ground_below_ship() -> Vector3:
	var ship_position : Vector3 = ship_node.global_position
	var fallback : Vector3 = Vector3(ship_position.x, fallback_ground_y, ship_position.z)
	if get_world_3d() == null:
		return fallback

	var query : PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ship_position + Vector3.UP * 2.0,
		ship_position + Vector3.DOWN * ground_probe_distance,
		ground_collision_mask
	)
	query.collide_with_areas = false
	if ship_node is CollisionObject3D:
		query.exclude = [(ship_node as CollisionObject3D).get_rid()]
	var space_state : PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return fallback
	var hit : Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return fallback
	return hit.get("position", fallback) as Vector3


func _get_stowed_position() -> Vector3:
	return ship_node.global_position + ship_stow_offset


func _get_beam_duration(distance : float) -> float:
	return clampf(
		distance / maxf(beam_travel_speed, 0.01),
		min_beam_duration,
		max_beam_duration
	)


func _get_transition_progress() -> float:
	return clampf(
		_transition_elapsed / maxf(_transition_duration, 0.001),
		0.0,
		1.0
	)


func _spawn_arrival_beam(origin : Vector3, height : float) -> ArrivalBeam:
	var beam : ArrivalBeam = ARRIVAL_BEAM_SCENE.instantiate() as ArrivalBeam
	get_parent().add_child(beam)
	beam.configure(origin, height)
	return beam


func _fade_beam_after_hold(beam : ArrivalBeam) -> void:
	if beam == null or not is_instance_valid(beam):
		return
	await get_tree().create_timer(beam_hold_duration).timeout
	if is_instance_valid(beam):
		beam.fade_out(beam_fade_duration)


func _set_terrestrial_processing(active : bool) -> void:
	var target_process_mode : Node.ProcessMode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if active and step_target_container.has_method("reset_motion"):
		step_target_container.call("reset_motion")
	step_target_container.process_mode = target_process_mode
	for target : Marker3D in _leg_targets:
		target.process_mode = target_process_mode
	for leg_ik : SkeletonIK3D in _leg_iks:
		if active:
			leg_ik.start()
		else:
			leg_ik.stop()


func _reset_leg_targets_to_ground() -> void:
	var rays : Array[RayCast3D] = [
		$StepTargetContainer/FrontLeftRay,
		$StepTargetContainer/FrontRightRay,
		$StepTargetContainer/BackLeftRay,
		$StepTargetContainer/BackRightRay,
	]
	for index : int in range(rays.size()):
		var ray : RayCast3D = rays[index]
		ray.force_raycast_update()
		if ray.is_colliding():
			_leg_targets[index].global_position = ray.get_collision_point()
