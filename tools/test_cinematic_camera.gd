extends SceneTree

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var test_world : Node3D = Node3D.new()
	root.add_child(test_world)

	var packed : PackedScene = load("res://scenes/Player.tscn") as PackedScene
	var player : CharacterBody3D = packed.instantiate() as CharacterBody3D
	test_world.add_child(player)
	player.set_physics_process(false)

	var wall : StaticBody3D = StaticBody3D.new()
	var wall_shape : CollisionShape3D = CollisionShape3D.new()
	var box : BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.2)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	wall.position = Vector3(0.58, 0.8, -1.45)
	test_world.add_child(wall)

	await physics_frame
	await physics_frame
	await process_frame
	await process_frame

	var rig : CinematicCameraRig = player.get_node("CameraHolder") as CinematicCameraRig
	var spring_arm : SpringArm3D = rig.get_node(
		"PitchPivot/ShoulderOffset/SpringArm3D"
	) as SpringArm3D
	var camera : Camera3D = spring_arm.get_node("Camera3D") as Camera3D
	var hit_length : float = spring_arm.get_hit_length()

	var ship_packed : PackedScene = load(
		"res://scenes/Space/AlienShip.tscn"
	) as PackedScene
	var ship : AlienShip = ship_packed.instantiate() as AlienShip
	ship.position = Vector3(100.0, 0.0, 0.0)
	ship.spin_speed = 0.0
	test_world.add_child(ship)

	await physics_frame
	await physics_frame

	# A parede direita tem esta normal no plano XZ. O rig fica perto da borda e
	# olha para fora, reproduzindo o caso em que a camera tentava atravessar a
	# parede interna da nave.
	var wall_direction : Vector3 = Vector3(0.8660254, 0.0, -0.5)
	rig.set_process(false)
	rig.set_interior_camera_mode(true, ship.interior)
	rig.global_position = (
		ship.global_position
		+ wall_direction * 3.5
		+ Vector3(0.0, 0.2, 0.0)
	)
	rig.global_basis = Basis.looking_at(wall_direction, Vector3.UP)

	await physics_frame
	await physics_frame
	await process_frame
	var ship_wall_hit_length : float = spring_arm.get_hit_length()

	# Posicao extrema observada nesta secao da parede: a origem do rig fica
	# praticamente colada a face interna, reproduzindo o problema da borda.
	rig.global_position = (
		ship.global_position
		+ wall_direction * 5.8
		+ Vector3(0.0, 0.2, 0.0)
	)
	await physics_frame
	await physics_frame
	await process_frame
	var flush_wall_hit_length : float = spring_arm.get_hit_length()

	# Exercita o fallback geometrico diretamente. O processo do rig permanece
	# desligado para que a pose manual usada pelos checks do SpringArm nao seja
	# substituida pelo alvo publicado pelo Player.
	var unclamped_camera_local : Vector3 = Vector3(20.0, 5.0, 20.0)
	camera.global_position = ship.interior.to_global(unclamped_camera_local)
	rig.call("_clamp_camera_to_interior")
	var clamped_camera_local : Vector3 = ship.interior.to_local(
		camera.global_position
	)
	var clamp_radial_scale : float = lerpf(
		1.0,
		0.09,
		clampf(clamped_camera_local.y / 2.45, 0.0, 1.0)
	)
	var clamp_base_z : float = clamped_camera_local.z / clamp_radial_scale
	var clamp_base_x : float = clamped_camera_local.x / clamp_radial_scale
	var clamp_half_width : float = maxf(
		(clamp_base_z + 9.4) / 14.1 * 8.141 - 0.12,
		0.0
	)

	var checks : Dictionary = {
		"Cinematic rig is active": rig != null,
		"Third-person FOV is 60": is_equal_approx(camera.fov, 60.0),
		"Spring arm uses a volume": spring_arm.shape is SphereShape3D,
		"Wall shortens camera arm": hit_length > 0.4 and hit_length < 2.0,
		"Ship wall shortens camera arm": (
			ship_wall_hit_length > 0.2 and ship_wall_hit_length < 4.0
		),
		"Ship wall blocks camera when character is flush": (
			flush_wall_hit_length >= 0.0 and flush_wall_hit_length < 0.4
		),
		"Interior camera volume fits inside player clearance": (
			(spring_arm.shape as SphereShape3D).radius < 0.1
		),
		"Interior fallback clamps camera into tapered shell": (
			clamped_camera_local.distance_to(unclamped_camera_local) > 0.1
			and clamped_camera_local.y >= 0.079
			and clamped_camera_local.y <= 2.371
			and clamp_base_z >= -9.281
			and clamp_base_z <= 4.581
			and absf(clamp_base_x) <= clamp_half_width + 0.001
		),
	}
	var failed : bool = false
	for label : String in checks:
		var passed : bool = checks[label]
		print("CHECK|%s|%s" % ["PASS" if passed else "FAIL", label])
		failed = failed or not passed

	print("METRIC|camera_hit_length|%.3f" % hit_length)
	print("METRIC|ship_wall_hit_length|%.3f" % ship_wall_hit_length)
	print("METRIC|flush_wall_hit_length|%.3f" % flush_wall_hit_length)
	print("METRIC|clamped_camera_local|%s" % clamped_camera_local)
	print("CINEMATIC_CAMERA_TEST|%s" % ["FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
