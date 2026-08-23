extends SceneTree

var _failed : bool = false


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20.0, 0.2, 20.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.1
	root.add_child(floor_body)

	var player := (
		load("res://scenes/Player.tscn") as PackedScene
	).instantiate() as CharacterBody3D
	root.add_child(player)
	await process_frame
	player.set_physics_process(false)

	var ragdoll := player.get_node("PlayerRagdoll") as PlayerRagdoll
	var controller := player.get_node(
		"PlayerAnimationController"
	) as PlayerAnimationController
	ragdoll.start_comic_fall(Vector3.BACK, 0.3)
	controller.set_ragdoll_active(true)

	for _frame : int in 12:
		await physics_frame

	check(ragdoll.is_active(), "Ragdoll active")
	check(ragdoll.get_body_global_position().is_finite(), "Finite body position")
	var face_up := ragdoll.is_face_up()

	ragdoll.stop_ragdoll()
	check(ragdoll.is_recovering(), "Recovery pose captured")
	controller.begin_get_up(face_up)
	ragdoll.apply_recovery(1.0)
	controller.finish_get_up()
	check(not ragdoll.is_recovering(), "Recovery released")

	player.queue_free()
	floor_body.queue_free()
	await process_frame
	if _failed:
		quit(1)
	else:
		print("PLAYER_RAGDOLL_TEST|PASS|face_up=%s" % face_up)
		quit()


func check(condition : bool, label : String) -> void:
	if condition:
		print("CHECK|PASS|%s" % label)
		return
	_failed = true
	push_error("CHECK|FAIL|%s" % label)
