extends SceneTree

## Render-only inspection; no player, input, or changes to the saved environment.
## Run without --headless. Captures are written to build/country-road-review/.
var _started: bool = false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_capture()
	return false


func _capture() -> void:
	var world: Node3D = (load("res://scenes/CountryTown/CountryTown.tscn") as PackedScene).instantiate() as Node3D
	var scene_lighting: bool = "--scene-lighting" in OS.get_cmdline_user_args()
	for label: String in ["Player", "PauseMenu", "EnvironmentAudio"]:
		world.get_node(label).free()
	if not scene_lighting:
		world.get_node("NightEnvironment").free()
	_uncull(world)
	root.add_child(world)
	if not scene_lighting:
		var environment: WorldEnvironment = WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.22, 0.29, 0.36)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color(0.85, 0.9, 1.0)
		environment.environment.ambient_light_energy = 0.65
		world.add_child(environment)
		var sun: DirectionalLight3D = DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-60, -25, 0)
		sun.light_energy = 1.1
		sun.shadow_enabled = true
		world.add_child(sun)
	var camera: Camera3D = Camera3D.new()
	camera.far = 2500
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(camera)
	camera.current = true
	var terrain: Terrain3D = world.get_node("NavigationRegion3D/Terrain3D") as Terrain3D
	terrain.set_camera(camera)
	var views: Array[Array] = [
		["07-farm-road", Vector3(111, 33, 193), Vector3(151, 6, 167.46), 80.0],
		["01-map", Vector3(300, 760, 230), Vector3(300, 6, 230), 660.0],
		["02-town", Vector3(457, 460, 254), Vector3(457, 6, 254), 270.0],
		["03-streets", Vector3(580, 125, 355), Vector3(481, 6, 242), 170.0],
		["04-north-bridge", Vector3(334, 65, 216), Vector3(312, 6, 167.46), 95.0],
		["05-south-bridge", Vector3(218, 65, 347), Vector3(205, 6, 298.48), 95.0],
		["06-junction", Vector3(491, 28, 231), Vector3(516, 6, 211), 55.0],
	]
	DirAccess.make_dir_recursive_absolute("res://build/country-road-review")
	for view: Array in views:
		camera.position = view[1]
		camera.size = view[3]
		camera.look_at(view[2], Vector3.FORWARD if view[0] in ["01-map", "02-town"] else Vector3.UP)
		for frame: int in 45:
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://build/country-road-review/%s%s.png" % [view[0], "-scene-lighting" if scene_lighting else ""]
		var result: Error = root.get_texture().get_image().save_png(path)
		if result != OK:
			push_error("Capture failed: %s" % path)
			quit(1)
			return
		print("Captured %s" % path)
	world.free()
	quit(0)


func _uncull(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visibility_range_end = 0.0
	for child: Node in node.get_children():
		_uncull(child)
