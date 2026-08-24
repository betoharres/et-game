extends SceneTree

var _failed : bool = false


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var floor_body : StaticBody3D = StaticBody3D.new()
	var floor_collision : CollisionShape3D = CollisionShape3D.new()
	var floor_shape : BoxShape3D = BoxShape3D.new()
	floor_shape.size = Vector3(100.0, 0.2, 100.0)
	floor_collision.shape = floor_shape
	floor_collision.position.y = -0.1
	floor_body.add_child(floor_collision)
	root.add_child(floor_body)

	var player : CharacterBody3D = (
		load("res://scenes/Player.tscn") as PackedScene
	).instantiate() as CharacterBody3D
	root.add_child(player)
	for _frame : int in 5:
		await physics_frame

	var controller : PlayerAnimationController = player.get_node(
		"PlayerAnimationController"
	) as PlayerAnimationController
	var collision : CollisionShape3D = player.get_node("CollisionShape3D") as CollisionShape3D
	var capsule : CapsuleShape3D = collision.shape as CapsuleShape3D

	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	check(player.velocity.y > 5.0, "Jump impulse is immediate")
	check(not player.is_crouching, "Jump does not force crouch")
	check(is_equal_approx(capsule.height, 1.0), "Jump keeps standing capsule")
	check(controller.get_current_state() == &"Jump", "Jump uses one ascent clip")

	for _frame : int in 80:
		await physics_frame
	Input.action_press("ui_up")
	Input.action_press("sprint")
	for _frame : int in 180:
		await physics_frame
	Input.action_release("sprint")
	Input.action_release("ui_up")
	check(player.stamina > 53.0 and player.stamina < 57.0, "Stamina drains 15 per second")

	player.free()
	floor_body.free()
	if _failed:
		quit(1)
	else:
		print("PLAYER_JUMP_STAMINA_TEST|PASS")
		quit()


func check(condition : bool, label : String) -> void:
	if condition:
		print("CHECK|PASS|%s" % label)
		return
	_failed = true
	push_error("CHECK|FAIL|%s" % label)
