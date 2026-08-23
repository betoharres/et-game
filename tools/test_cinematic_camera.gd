extends SceneTree

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var test_world := Node3D.new()
	root.add_child(test_world)

	var packed := load("res://scenes/Player.tscn") as PackedScene
	var player := packed.instantiate() as CharacterBody3D
	test_world.add_child(player)
	player.set_physics_process(false)

	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.2)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	wall.position = Vector3(0.58, 0.8, -1.45)
	test_world.add_child(wall)

	await physics_frame
	await physics_frame
	await process_frame
	await process_frame

	var rig := player.get_node("CameraHolder") as CinematicCameraRig
	var spring_arm := rig.get_node(
		"PitchPivot/ShoulderOffset/SpringArm3D"
	) as SpringArm3D
	var camera := spring_arm.get_node("Camera3D") as Camera3D
	var hit_length := spring_arm.get_hit_length()

	var checks := {
		"Cinematic rig is active": rig != null,
		"Third-person FOV is 60": is_equal_approx(camera.fov, 60.0),
		"Spring arm uses a volume": spring_arm.shape is SphereShape3D,
		"Wall shortens camera arm": hit_length > 0.4 and hit_length < 2.0,
	}
	var failed := false
	for label : String in checks:
		var passed : bool = checks[label]
		print("CHECK|%s|%s" % ["PASS" if passed else "FAIL", label])
		failed = failed or not passed

	print("METRIC|camera_hit_length|%.3f" % hit_length)
	print("CINEMATIC_CAMERA_TEST|%s" % ["FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
