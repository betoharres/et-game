extends SceneTree

const PORTAL_SCENE: PackedScene = preload("res://scenes/Portal/portal.tscn")
const EPSILON: float = 0.001


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pair: Node3D = PORTAL_SCENE.instantiate()
	root.add_child(pair)
	await process_frame
	pair.set_physics_process(false)
	var entrance: MeshInstance3D = pair.get_node("Mesh1")
	var exit: MeshInstance3D = pair.get_node("Mesh2")
	exit.rotate_y(PI * 0.5)
	var entrance_frame: Transform3D = pair._portal_transform(entrance)
	var exit_frame: Transform3D = pair._portal_transform(exit)
	var mapping: Transform3D = pair._portal_mapping(entrance, exit)
	_assert_vector_close(mapping.basis * Vector3.UP, Vector3.UP, "upright mapping")
	_assert_vector_close(mapping * (entrance_frame * Vector3(0.2, -0.3, 0.1)),
		exit_frame * Vector3(-0.2, -0.3, -0.1), "surface frame mapping")

	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.global_position = entrance_frame * Vector3(0.2, 0.1, 3.0)
	pair.player_camera = camera
	var portal_camera: Camera3D = pair.get_node("Mesh1/SubViewport/Camera3D")
	pair._update_camera_for_portal(portal_camera, entrance, exit)
	assert(portal_camera.projection == Camera3D.PROJECTION_FRUSTUM)
	_assert_vector_close(portal_camera.global_position, mapping * camera.global_position, "virtual camera")
	assert(absf(portal_camera.near + portal_camera.to_local(exit_frame.origin).z - pair.CLIP_PLANE_OFFSET) < EPSILON)
	assert((portal_camera.cull_mask & 512) != 0, "Props must remain visible")
	assert((portal_camera.cull_mask & 4) != 0, "FX must remain visible")
	assert((portal_camera.cull_mask & pair.PORTAL_LAYER) == 0)

	var body: CharacterBody3D = CharacterBody3D.new()
	body.add_to_group(&"players")
	root.add_child(body)
	body.global_position = entrance_frame * Vector3(0.2, -0.3, 0.1)
	body.velocity = entrance_frame.basis * Vector3(0.0, 0.0, -4.0)
	var original_position: Vector3 = body.global_position
	pair._on_portal_body_entered(body, entrance, exit)
	pair._physics_process(0.016)
	_assert_vector_close(body.global_position, original_position, "Entering threshold must not teleport")
	body.global_position = entrance_frame * Vector3(0.2, -0.3, -0.1)
	pair._physics_process(0.016)
	_assert_vector_close(body.global_position, exit_frame * Vector3(-0.2, -0.3, 0.1), "crossing position")
	_assert_vector_close(body.velocity, exit_frame.basis * Vector3(0.0, 0.0, 4.0), "crossing velocity")
	pair._on_portal_body_entered(body, exit, entrance)
	pair._on_portal_body_exited(body, entrance)
	original_position = body.global_position
	pair._physics_process(0.016)
	_assert_vector_close(body.global_position, original_position, "Destination tracking prevents bounce")
	body.global_position = exit_frame * Vector3(-0.2, -0.3, -0.1)
	pair._physics_process(0.016)
	_assert_vector_close(body.global_position, entrance_frame * Vector3(0.2, -0.3, 0.1), "Immediate reverse crossing")
	pair._on_portal_body_exited(body, entrance)
	assert(pair._travellers.is_empty(), "Leaving destination clears tracking")

	var player_scene: PackedScene = load("res://scenes/Player.tscn") as PackedScene
	var player: CharacterBody3D = player_scene.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.camera_pivot.set_process(false)
	player.global_position = entrance_frame * Vector3(0.0, -1.0, -0.1)
	player.camera_yaw = 0.3
	player.camera_pivot.set_target_pose(player.global_position, player.camera_yaw, 0.0, 0.0, 0.0, true, true)
	var previous_rig: Transform3D = player.camera_pivot.global_transform
	var old_forward: Vector3 = Vector3(-sin(player.camera_yaw), 0.0, -cos(player.camera_yaw))
	pair._teleport_body(player, entrance, exit)
	_assert_vector_close(player.camera_pivot.global_position, mapping * previous_rig.origin, "Player camera handoff")
	_assert_vector_close(player.camera_pivot.global_basis.z, mapping.basis * previous_rig.basis.z, "Player camera orientation")
	_assert_vector_close(Vector3(-sin(player.camera_yaw), 0.0, -cos(player.camera_yaw)), mapping.basis * old_forward, "Player look direction")

	var original_material: Material = player.character_mesh.get_surface_override_material(0)
	pair._on_portal_body_entered(player, exit, entrance)
	pair._update_traveller_visuals()
	var visual: Node3D = pair._travellers[player.get_instance_id()]["visual"]
	assert(visual._meshes.size() >= 4, "Body and equipment must have visual clones")
	assert(not visual._skeletons.is_empty(), "Animated skeleton must be mirrored")
	for entry: Dictionary in visual._meshes:
		var source: MeshInstance3D = entry["source"]
		var clone: MeshInstance3D = entry["clone"]
		_assert_vector_close(clone.global_position, pair._portal_mapping(exit, entrance) * source.global_position, "Clone position")
		assert(clone.visible == source.is_visible_in_tree(), "Equipment visibility must match")
		assert(source.get_active_material(0).shader.code.contains("portal_world_position"), "Original must be sliced")
		assert(clone.get_active_material(0) == source.get_active_material(0), "Clone appearance must match")
	for entry: Dictionary in visual._skeletons.values():
		var source: Skeleton3D = entry["source"]
		var clone: Skeleton3D = entry["clone"]
		assert(source.get_bone_count() == clone.get_bone_count())
		for bone: int in source.get_bone_count():
			_assert_vector_close(clone.get_bone_global_pose(bone).origin, source.get_bone_global_pose(bone).origin, "Mirrored final pose")
	await process_frame
	await process_frame
	pair._on_portal_body_exited(player, exit)
	assert(player.character_mesh.get_surface_override_material(0) == original_material, "Original material must be restored")
	assert(pair._travellers.is_empty())

	if DisplayServer.get_name() != "headless":
		await _test_slice_pixels()
		await _test_recursive_pixels()
	print("Portal crossing, camera, velocity and sliced clone tests passed")
	quit(0)


func _assert_vector_close(actual: Vector3, expected: Vector3, label: String) -> void:
	assert(actual.distance_to(expected) <= EPSILON, "%s: expected %s, got %s" % [label, expected, actual])


func _test_slice_pixels() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var body: Node3D = Node3D.new()
	viewport.add_child(body)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = "shader_type spatial; render_mode unshaded; void fragment() { ALBEDO = vec3(1.0, 0.0, 0.0); }"
	mesh.material_override = material
	body.add_child(mesh)
	var camera: Camera3D = Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position = Vector3(0.0, 0.0, 3.0)
	camera.current = true
	var visual: Node3D = load("res://scripts/portal/portal_traveller_visual.gd").new()
	viewport.add_child(visual)
	visual.setup(body)
	var frame: Transform3D = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	visual.update_visual(Transform3D(Basis(Vector3.UP, PI), Vector3(5.0, 0.0, 0.0)), frame,
		Transform3D(frame.basis, Vector3(5.0, 0.0, 0.0)), 1.0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	assert(image.get_pixel(40, 32).r > 0.8, "Visible half must remain red")
	assert(image.get_pixel(24, 32).r < 0.3, "Crossed half must be discarded")
	assert(image.get_pixel(32, 32).b > 0.15, "Original slice border must glow cyan")
	camera.position.x = 5.0
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	image = viewport.get_texture().get_image()
	assert(image.get_pixel(40, 32).r > 0.8, "Crossed half must appear at the exit")
	assert(image.get_pixel(24, 32).r < 0.3, "Uncrossed half of clone must be discarded")
	assert(image.get_pixel(32, 32).b > 0.15, "Clone slice border must glow cyan")
	print("Portal slice pixel test passed")
	viewport.queue_free()


func _test_recursive_pixels() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(96, 96)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pair: Node3D = PORTAL_SCENE.instantiate()
	viewport.add_child(pair)
	pair.set_process(false)
	pair.set_physics_process(false)
	pair.get_node("SmBldPortal01").hide()
	pair.get_node("SmBldPortal02").hide()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	pair.portal_1.mesh = quad
	pair.portal_2.mesh = quad
	pair.portal_1.global_transform = Transform3D.IDENTITY
	pair.portal_2.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, 6.0))
	pair.viewport_1.size = Vector2i(96, 96)
	pair.viewport_2.size = Vector2i(96, 96)
	var camera: Camera3D = Camera3D.new()
	viewport.add_child(camera)
	camera.position.z = 2.0
	camera.current = true
	pair.player_camera = camera
	var target: MeshInstance3D = MeshInstance3D.new()
	target.mesh = BoxMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.RED
	target.material_override = material
	viewport.add_child(target)
	target.position.z = -2.0
	var counts: Array[int] = []
	for limit: int in [1, 2, 3]:
		pair.recursion_limit = limit
		pair._update_camera_for_portal(pair.portal_1_camera, pair.portal_1, pair.portal_2)
		pair._update_camera_for_portal(pair.portal_2_camera, pair.portal_2, pair.portal_1)
		pair._recursive_views.update_views()
		for child_viewport: SubViewport in pair._recursive_views._viewports:
			child_viewport.size = Vector2i(96, 96)
		for frame: int in 6:
			await process_frame
			await RenderingServer.frame_post_draw
		var image: Image = pair.viewport_1.get_texture().get_image()
		var count: int = 0
		for y: int in image.get_height():
			for x: int in image.get_width():
				var color: Color = image.get_pixel(x, y)
				if color.r > 0.7 and color.g < 0.2:
					count += 1
		counts.append(count)
	assert(counts[0] > 0, "Single portal must show the red target")
	assert(counts[1] < counts[0] and counts[2] < counts[1], "Each recursive level must shrink the nested target")
	assert(pair._recursive_views._viewports.size() == 12, "Depth three must stop after two child levels")
	print("Portal recursion pixel test passed: ", counts)
	viewport.queue_free()
