extends SceneTree

const PORTAL_SCENE := preload("res://scenes/Portal/portal.tscn")
const EPSILON := 0.001


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var portal_pair := PORTAL_SCENE.instantiate()
	root.add_child(portal_pair)
	await process_frame

	var portal_1: MeshInstance3D = portal_pair.get_node("Mesh1")
	var portal_2: MeshInstance3D = portal_pair.get_node("Mesh2")
	var portal_camera: Camera3D = portal_pair.get_node("Mesh1/SubViewport/Camera3D")
	var player_camera := Camera3D.new()
	root.add_child(player_camera)
	player_camera.global_position = portal_1.to_global(Vector3(0.2, 0.1, 3.0))
	portal_pair.player_camera = player_camera
	portal_pair._update_camera_for_portal(portal_camera, portal_1, portal_2)
	assert(
		portal_camera.projection == Camera3D.PROJECTION_FRUSTUM,
		"Portal camera must use an asymmetric frustum"
	)
	var exit_center_in_camera := portal_camera.to_local(portal_2.global_position)
	_assert_close(
		portal_camera.near,
		-exit_center_in_camera.z + portal_pair.clip_plane_offset,
		"portal-aligned near plane"
	)

	var player := CharacterBody3D.new()
	player.add_to_group(&"players")
	root.add_child(player)
	player.global_position = portal_1.to_global(Vector3(0.2, -0.3, 0.1))
	player.velocity = portal_1.global_basis * Vector3(0.0, 0.0, -4.0)

	portal_pair._on_portal_body_entered(player, portal_1, portal_2)
	var expected_position := portal_2.to_global(Vector3(-0.2, -0.3, -0.1))
	_assert_vector_close(player.global_position, expected_position, "portal 1 -> 2 position")
	_assert_vector_close(
		player.velocity,
		portal_2.global_basis * Vector3(0.0, 0.0, 4.0),
		"portal 1 -> 2 velocity"
	)

	# The cooldown must prevent the exit area from immediately sending the body back.
	var position_after_teleport := player.global_position
	portal_pair._on_portal_body_entered(player, portal_2, portal_1)
	_assert_vector_close(player.global_position, position_after_teleport, "exit cooldown")

	print("Portal teleportation smoke test passed")
	quit(0)


func _assert_vector_close(actual: Vector3, expected: Vector3, label: String) -> void:
	assert(
		actual.distance_to(expected) <= EPSILON,
		"%s failed: expected %s, got %s" % [label, expected, actual]
	)


func _assert_close(actual: float, expected: float, label: String) -> void:
	assert(
		absf(actual - expected) <= EPSILON,
		"%s failed: expected %s, got %s" % [label, expected, actual]
	)
