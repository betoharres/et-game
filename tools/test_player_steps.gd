extends SceneTree

var _failed : bool = false
var _world : Node3D
var _player : CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for height : float in [0.20, 0.28]:
		_new_case()
		_box(Vector3(4.0, height, 6.0), Vector3(0.0, height * 0.5, 4.0))
		await _settle()
		var airborne : int = await _walk(85)
		_check(_player.position.z > 3.0 and absf(_player.position.y - height) < 0.01,
			"Climbs %.2f m curb at walking speed" % height)
		_check(airborne == 0, "Curb keeps floor contact: %.2f m" % height)
		_check(_player.velocity.y <= 0.01, "Step adds no upward impulse")
		_check(_player.velocity.z > 2.9, "Step preserves walking speed")

	_new_case()
	_box(Vector3(4.0, 0.36, 6.0), Vector3(0.0, 0.18, 4.0))
	await _settle()
	await _walk(85)
	_check(_player.position.z < 1.0 and _player.position.y < 0.02,
		"Obstacle above step limit remains blocking")

	_new_case()
	_player.set("max_step_height", 0.0)
	_box(Vector3(4.0, 0.20, 6.0), Vector3(0.0, 0.10, 4.0))
	await _settle()
	await _walk(85)
	_check(_player.position.z < 1.0, "Zero step height disables climbing")

	_new_case()
	_box(Vector3(4.0, 0.20, 6.0), Vector3(0.0, 0.10, 4.0))
	_box(Vector3(4.0, 0.2, 10.0), Vector3(0.0, 1.25, 3.0))
	await _settle()
	await _walk(85)
	_check(_player.position.z < 1.0, "Ceiling without standing clearance blocks step")

	_new_case()
	_box(Vector3(4.0, 0.15, 6.0), Vector3(0.0, 0.075, 4.0))
	_box(Vector3(4.0, 0.2, 10.0), Vector3(0.0, 1.32, 3.0))
	await _settle()
	await _walk(85)
	_check(_player.position.z > 3.0, "Low ceiling allows a smaller valid step")

	_new_case()
	for index : int in 6:
		var height : float = float(index + 1) * 0.2
		_box(Vector3(4.0, height, 0.6), Vector3(0.0, height * 0.5, 1.3 + index * 0.6))
	await _settle()
	var stair_airborne : int = await _walk(90)
	_check(_player.position.z > 4.0 and _player.position.y > 1.19,
		"Climbs consecutive stair treads")
	_check(stair_airborne == 0, "Stair ascent stays grounded")
	# Face down the same staircase without engaging the reversal animation.
	_player.set("camera_yaw", PI)
	_player.rotation.y = PI
	_player.velocity = Vector3.ZERO
	var descending_airborne : int = await _walk(100)
	_check(_player.position.z < 1.0 and _player.position.y < 0.01,
		"Descends staircase to ground")
	_check(descending_airborne == 0, "Small descents never enter free fall")

	_new_case()
	_box(Vector3(4.0, 0.2, 2.0), Vector3(0.0, 0.1, 0.0))
	_player.position.y = 0.2
	await _settle()
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	_check(_player.velocity.y > 5.0 and not _player.is_on_floor(),
		"Jump keeps its impulse and detaches from step")
	_check(is_equal_approx(_player.floor_snap_length, 0.1), "Original snap setting restored")

	_new_case()
	_box(Vector3(4.0, 0.7, 2.0), Vector3(0.0, 0.35, 0.0))
	_player.position.y = 0.7
	await _settle()
	var falling_frames : int = await _walk(38)
	_check(falling_frames > 0, "Drop above step height preserves gravity/free fall")
	Input.action_release("ui_up")
	_world.free()
	print("PLAYER_STEPS_TEST|%s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _new_case() -> void:
	Input.action_release("ui_up")
	if is_instance_valid(_world):
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)
	_box(Vector3(40.0, 0.2, 40.0), Vector3(0.0, -0.1, 0.0))
	_player = (load("res://scenes/Player.tscn") as PackedScene).instantiate() as CharacterBody3D
	_world.add_child(_player)


func _box(size : Vector3, center : Vector3) -> void:
	var body : StaticBody3D = StaticBody3D.new()
	var collider : CollisionShape3D = CollisionShape3D.new()
	var shape : BoxShape3D = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	body.position = center
	_world.add_child(body)


func _settle() -> void:
	for frame : int in 5:
		await physics_frame


func _walk(frames : int) -> int:
	Input.action_press("ui_up")
	var airborne : int = 0
	for frame : int in frames:
		await physics_frame
		if not _player.is_on_floor():
			airborne += 1
	Input.action_release("ui_up")
	return airborne


func _check(condition : bool, label : String) -> void:
	if condition:
		print("CHECK|PASS|" + label)
	else:
		_failed = true
		push_error("CHECK|FAIL|%s at %s velocity %s" % [label, _player.global_position, _player.velocity])
