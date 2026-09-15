extends Node

@export_range(0.01, 0.5, 0.01) var box_margin : float = 0.15

var _vehicle : VehicleBody3D
var _bounds : AABB
var _box : BoxShape3D = BoxShape3D.new()
var _exceptions : Array[CharacterBody3D] = []


func _ready() -> void:
	_vehicle = get_parent() as VehicleBody3D
	var initialized : bool = false
	for child : Node in _vehicle.get_children():
		var collider : CollisionShape3D = child as CollisionShape3D
		if collider == null or collider.disabled or collider.shape == null:
			continue
		var bounds : AABB = collider.transform * collider.shape.get_debug_mesh().get_aabb()
		_bounds = _bounds.merge(bounds) if initialized else bounds
		initialized = true
	_bounds = _bounds.grow(box_margin)
	set_physics_process(initialized)
	# Respond after the character's movement, before the next solver step.
	process_physics_priority = 100


func _physics_process(delta : float) -> void:
	var basis : Basis = _vehicle.global_basis.orthonormalized()
	var local_motion : Vector3 = basis.inverse() * _vehicle.linear_velocity * delta
	var rotation_margin : float = (
		_vehicle.angular_velocity.length() * _bounds.size.length() * delta
	)
	# intersect_shape ignores query.motion; enclose the next displacement in
	# the same simple box instead, including the arc swept by turning corners.
	_box.size = _bounds.size + local_motion.abs() + Vector3.ONE * rotation_margin
	var query : PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = _box
	query.transform = Transform3D(
		basis, _vehicle.to_global(_bounds.get_center()) + _vehicle.linear_velocity * delta * 0.5
	)
	query.collision_mask = _vehicle.collision_mask
	query.exclude = [_vehicle.get_rid()]
	var contacts : Array[CharacterBody3D] = []
	var responding : Array[CharacterBody3D] = []
	var space : PhysicsDirectSpaceState3D = _vehicle.get_world_3d().direct_space_state
	# Page past scenery so a floor or several chassis shapes cannot hide an ET.
	while true:
		var hits : Array[Dictionary] = space.intersect_shape(query, 32)
		for hit : Dictionary in hits:
			var excluded : Array[RID] = query.exclude
			excluded.append(hit["rid"] as RID)
			query.exclude = excluded
			var character : CharacterBody3D = hit["collider"] as CharacterBody3D
			if character != null and not contacts.has(character):
				contacts.append(character)
		if hits.size() < 32:
			break

	for character : CharacterBody3D in contacts:
		if not character.has_method("receive_vehicle_contact") or not character.is_physics_processing():
			continue
		var center : Vector3 = character.global_position
		var collider : CollisionShape3D = character.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if collider != null:
			center = collider.global_position
		var local_center : Vector3 = _vehicle.to_local(center)
		var nearest : Vector3 = local_center.clamp(_bounds.position, _bounds.end)
		var direction : Vector3 = basis * (local_center - nearest)
		if direction.length_squared() < 0.0001:
			var offset : Vector3 = local_center - _bounds.get_center()
			var clearance : Vector3 = _bounds.size * 0.5 - offset.abs()
			var axis : int = clearance.min_axis_index()
			direction = basis[axis] * (1.0 if offset[axis] >= 0.0 else -1.0)
		direction = direction.normalized()
		# Standing on the roof must retain the ordinary platform collision.
		if absf(direction.dot(character.up_direction)) > 0.7:
			continue
		var point : Vector3 = _vehicle.to_global(nearest)
		var point_velocity : Vector3 = _vehicle.linear_velocity + _vehicle.angular_velocity.cross(
			point - _vehicle.to_global(_vehicle.center_of_mass)
		)
		var closing_speed : float = (point_velocity - character.velocity).dot(direction)
		if closing_speed <= 0.05 or point_velocity.dot(direction) <= 0.05:
			continue
		var wall_query : PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			point, center, _vehicle.collision_mask, [_vehicle.get_rid(), character.get_rid()]
		)
		if not space.intersect_ray(wall_query).is_empty():
			continue
		var owned : bool = _exceptions.has(character)
		var existing : bool = _vehicle.get_collision_exceptions().has(character)
		if not existing:
			_vehicle.add_collision_exception_with(character)
		var accepted : bool = character.call(
			"receive_vehicle_contact", direction, point_velocity, closing_speed, delta
		) as bool
		if accepted:
			responding.append(character)
		if accepted and not existing:
			_exceptions.append(character)
		elif not accepted and not existing and not owned:
			_vehicle.remove_collision_exception_with(character)

	for index : int in range(_exceptions.size() - 1, -1, -1):
		var character : CharacterBody3D = _exceptions[index]
		if not is_instance_valid(character):
			_exceptions.remove_at(index)
			continue
		if not character.is_physics_processing():
			continue
		# Keep the exception while the disabled ragdoll capsule or recovering
		# character is inside the car; a timeout could reintroduce a hard stop.
		var collider : CollisionShape3D = character.get_node_or_null("CollisionShape3D") as CollisionShape3D
		var overlapping : bool = responding.has(character)
		if collider != null and collider.shape != null:
			var bounds : AABB = (
				_vehicle.global_transform.affine_inverse() * collider.global_transform
			) * collider.shape.get_debug_mesh().get_aabb()
			overlapping = overlapping or _bounds.grow(-box_margin + 0.02).intersects(bounds)
		if not overlapping:
			_vehicle.remove_collision_exception_with(character)
			_exceptions.remove_at(index)


func _exit_tree() -> void:
	if not is_instance_valid(_vehicle):
		return
	for character : CharacterBody3D in _exceptions:
		if is_instance_valid(character):
			_vehicle.remove_collision_exception_with(character)
