extends SceneTree

var _failed : bool = false


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(30.0, 0.2, 30.0)
	floor_collision.shape = floor_shape
	floor_collision.position.y = -0.1
	floor_body.add_child(floor_collision)
	root.add_child(floor_body)

	var player := (
		load("res://scenes/Player.tscn") as PackedScene
	).instantiate() as CharacterBody3D
	root.add_child(player)
	for _frame : int in 5:
		await physics_frame
	var controller := player.get_node(
		"PlayerAnimationController"
	) as PlayerAnimationController

	Input.action_press("ui_down")
	await physics_frame
	check(controller.get_current_state() == &"WalkTurn180", "Idle pivot starts")
	var previous_yaw := player.rotation.y
	var accumulated_yaw := absf(wrapf(previous_yaw, -PI, PI))
	for _frame : int in 20:
		await physics_frame
		accumulated_yaw += absf(wrapf(player.rotation.y - previous_yaw, -PI, PI))
		previous_yaw = player.rotation.y
	check(
		Vector2(player.velocity.x, player.velocity.z).length() < 0.05,
		"Idle pivot plants before moving"
	)
	for _frame : int in 50:
		await physics_frame
		accumulated_yaw += absf(wrapf(player.rotation.y - previous_yaw, -PI, PI))
		previous_yaw = player.rotation.y
	var walk_direction := Vector2(player.velocity.x, player.velocity.z).normalized()
	check(
		Vector2(player.velocity.x, player.velocity.z).length() > 2.7,
		"Idle pivot exits walking"
	)
	check(
		absf(wrapf(player.rotation.y - PI, -PI, PI)) < 0.05,
		"Idle pivot ends at 180 degrees"
	)
	check(accumulated_yaw < PI * 1.1, "Idle pivot never spins 360 degrees")

	Input.action_release("ui_down")
	Input.action_press("ui_up")
	await physics_frame
	var first_reversal_velocity := Vector2(player.velocity.x, player.velocity.z)
	check(controller.get_current_state() == &"WalkTurn180", "Walk pivot starts")
	check(
		first_reversal_velocity.length() < 0.01
		or first_reversal_velocity.normalized().dot(walk_direction) > 0.0,
		"Walk does not reverse before the pivot"
	)
	for _frame : int in 70:
		await physics_frame
	var reversed_walk := Vector2(player.velocity.x, player.velocity.z).normalized()
	check(reversed_walk.dot(walk_direction) < -0.9, "Walk exits in new direction")

	Input.action_press("sprint")
	for _frame : int in 35:
		await physics_frame
	var run_direction := Vector2(player.velocity.x, player.velocity.z).normalized()
	check(
		Vector2(player.velocity.x, player.velocity.z).length() > 5.0,
		"Run reaches movement speed"
	)

	Input.action_release("ui_up")
	Input.action_press("ui_down")
	await physics_frame
	var first_run_reversal := Vector2(player.velocity.x, player.velocity.z)
	check(controller.get_current_state() == &"RunTurn180", "Run pivot starts")
	check(
		first_run_reversal.length() < 0.01
		or first_run_reversal.normalized().dot(run_direction) > 0.0,
		"Run does not reverse before the pivot"
	)
	for _frame : int in 50:
		await physics_frame
	var reversed_run := Vector2(player.velocity.x, player.velocity.z).normalized()
	check(reversed_run.dot(run_direction) < -0.9, "Run exits in new direction")

	Input.action_release("ui_down")
	Input.action_release("sprint")
	player.free()
	floor_body.free()
	if _failed:
		quit(1)
	else:
		print("PLAYER_REVERSAL_TEST|PASS")
		quit()


func check(condition : bool, label : String) -> void:
	if condition:
		print("CHECK|PASS|%s" % label)
		return
	_failed = true
	push_error("CHECK|FAIL|%s" % label)
