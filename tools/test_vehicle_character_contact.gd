extends SceneTree

var _failed : bool = false


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var floor_body : StaticBody3D = StaticBody3D.new()
	add_box(floor_body, Vector3(40.0, 0.2, 40.0), Vector3(0.0, -0.1, 0.0))
	root.add_child(floor_body)
	var vehicle : VehicleBody3D = VehicleBody3D.new()
	vehicle.mass = 1300.0
	vehicle.gravity_scale = 0.0
	vehicle.linear_damp = 0.0
	vehicle.angular_damp = 0.0
	add_box(vehicle, Vector3(2.0, 1.5, 5.0), Vector3(0.0, 0.9, 0.0))
	var contact : Node = load("res://scripts/vehicle_character_contact.gd").new()
	vehicle.add_child(contact)
	root.add_child(vehicle)
	var player : CharacterBody3D = load("res://scenes/Player.tscn").instantiate() as CharacterBody3D
	player.position = Vector3(0.0, 0.0, 2.9)
	root.add_child(player)
	await physics_frame
	await physics_frame
	var initial_z : float = player.position.z
	vehicle.linear_velocity = Vector3(0.0, 0.0, 1.0)
	for frame : int in 30:
		await physics_frame
	check(player.position.z > initial_z + 0.05, "Slow vehicle pushes stationary ET (z=%s, vehicle=%s)" % [player.position.z, vehicle.position.z])
	check(vehicle.linear_velocity.z > 0.8, "ET does not stop vehicle")
	check(not (player.get_node("PlayerRagdoll") as PlayerRagdoll).is_active(), "Slow nudge keeps ET standing")

	vehicle.linear_velocity = Vector3.ZERO
	await physics_frame
	await physics_frame
	check(not vehicle.get_collision_exceptions().has(player), "Stopped car regains solid collision outside chassis")
	player.position = Vector3(8.0, 0.0, 0.0)
	await physics_frame
	await physics_frame
	check(not vehicle.get_collision_exceptions().has(player), "Collision restored after separation")
	player.position = vehicle.position + Vector3(0.0, 1.65, 0.0)
	player.velocity = Vector3.ZERO
	vehicle.linear_velocity = Vector3(0.0, 0.0, 1.0)
	for frame : int in 5:
		await physics_frame
	check(not vehicle.get_collision_exceptions().has(player), "Standing on roof retains platform collision")
	check(not (player.get_node("PlayerRagdoll") as PlayerRagdoll).is_active(), "Roof passenger is not struck")
	player.queue_free()
	vehicle.queue_free()
	await process_frame
	vehicle = VehicleBody3D.new()
	vehicle.mass = 1300.0
	vehicle.gravity_scale = 0.0
	vehicle.linear_damp = 0.0
	add_box(vehicle, Vector3(2.0, 1.5, 5.0), Vector3(0.0, 0.9, 0.0))
	contact = load("res://scripts/vehicle_character_contact.gd").new()
	vehicle.add_child(contact)
	root.add_child(vehicle)
	player = load("res://scenes/Player.tscn").instantiate() as CharacterBody3D
	player.position = Vector3(0.0, 0.0, -3.0)
	root.add_child(player)
	await physics_frame
	await physics_frame
	vehicle.linear_velocity = Vector3(0.0, 0.0, -10.0)
	for frame : int in 6:
		await physics_frame
	var ragdoll : PlayerRagdoll = player.get_node("PlayerRagdoll") as PlayerRagdoll
	check(ragdoll.is_active(), "Reversing vehicle knocks stationary ET down")
	check(vehicle.linear_velocity.z < -8.0, "Fast impact preserves vehicle momentum")
	var bones : Dictionary = ragdoll.get("_physical_bones") as Dictionary
	var hips : PhysicalBone3D = bones.get("mixamorig_Hips") as PhysicalBone3D
	check(hips != null and hips.linear_velocity.z < -2.0, "Ragdoll inherits vehicle velocity")
	for frame : int in 30:
		await physics_frame
	check(player.position.z < -3.5, "ET root follows the thrown ragdoll")
	var camera_rig : Node = player.get("camera_pivot") as Node
	var camera_target : Vector3 = camera_rig.get("_target_position") as Vector3
	check(camera_target.z < -3.5 and absf(camera_target.z - player.position.z) < 0.1,
		"Camera target follows the displaced ET root")
	check(hips != null and ragdoll.get_body_global_position().distance_to(hips.global_position) < 0.05,
		"Ragdoll position comes from simulated hips")
	var recovery_started : bool = false
	var recovery_position : Vector3 = Vector3.ZERO
	for frame : int in 600:
		await physics_frame
		if not ragdoll.is_active() and not recovery_started:
			recovery_started = true
			recovery_position = player.global_position
		if recovery_started and int(player.get("_fall_state")) == 0:
			break
	check(recovery_started and int(player.get("_fall_state")) == 0, "ET completes automatic recovery")
	check(player.position.z < -3.5, "Recovered ET stays away from impact position")
	check(player.global_position.distance_to(recovery_position) < 0.1,
		"Finishing get-up does not teleport the root")
	player.queue_free()
	vehicle.queue_free()
	await process_frame

	vehicle = VehicleBody3D.new()
	vehicle.gravity_scale = 0.0
	vehicle.linear_damp = 0.0
	add_box(vehicle, Vector3(2.0, 1.5, 5.0), Vector3(0.0, 0.9, 0.0))
	contact = load("res://scripts/vehicle_character_contact.gd").new()
	vehicle.add_child(contact)
	root.add_child(vehicle)
	player = load("res://scenes/Player.tscn").instantiate() as CharacterBody3D
	player.position = Vector3(0.0, 0.0, 2.9)
	root.add_child(player)
	var wall : StaticBody3D = StaticBody3D.new()
	add_box(wall, Vector3(4.0, 3.0, 0.2), Vector3(0.0, 1.5, 3.35))
	root.add_child(wall)
	await physics_frame
	await physics_frame
	vehicle.linear_velocity = Vector3(0.0, 0.0, 1.0)
	for frame : int in 35:
		await physics_frame
	check((player.get_node("PlayerRagdoll") as PlayerRagdoll).is_active(), "Pinned ET falls at low speed")
	check(player.position.z < 3.45, "Pinned ET stays on near side of wall")
	player.queue_free()
	vehicle.queue_free()
	wall.queue_free()
	floor_body.queue_free()
	await process_frame
	print("VEHICLE_CHARACTER_CONTACT_TEST|%s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


func add_box(body : PhysicsBody3D, size : Vector3, offset : Vector3) -> void:
	var collider : CollisionShape3D = CollisionShape3D.new()
	var box : BoxShape3D = BoxShape3D.new()
	box.size = size
	collider.shape = box
	collider.position = offset
	body.add_child(collider)


func check(condition : bool, label : String) -> void:
	print("CHECK|%s|%s" % ["PASS" if condition else "FAIL", label])
	_failed = _failed or not condition
