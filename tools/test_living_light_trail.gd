extends SceneTree

var failures : int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ship : Node3D = Node3D.new()
	root.add_child(ship)
	current_scene = ship
	var light_scene : PackedScene = load("res://scenes/NPCs/LivingLight.tscn") as PackedScene
	var light : Node3D = light_scene.instantiate() as Node3D
	ship.add_child(light)
	light.set_physics_process(false)
	var body : LivingLightTrail = light.get_node("Trail3D") as LivingLightTrail
	var core : LivingLightTrail = light.get_node("TrailCore") as LivingLightTrail
	body.set_process(false)
	core.set_process(false)
	_check(body.material_override != core.material_override, "Body and core keep independent shader materials")
	light.call("_set_trail_emitting", true)
	for index : int in range(12):
		light.position.x = float(index) * 0.1
		body._process(0.01)
		core._process(0.01)
	_check_ribbon(body)
	_check_ribbon(core)
	var arrays : Array = body.mesh.surface_get_arrays(0)
	var colors : PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var custom : PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	_check(colors[0].a > colors[-1].a, "Gradient fades from the creature to the tail")
	_check(is_equal_approx(absf(custom[3]), body.width * 0.5 * body.width_curve.sample(0.0)), "Shader receives tapered half-width")
	var previous_world_point : Vector3 = body._points[-1]
	ship.rotation.y = 0.4
	ship.position.z = 2.0
	body._process(0.01)
	_check(body._points.has(previous_world_point), "Ship motion leaves old samples in world space")
	arrays = body.mesh.surface_get_arrays(0)
	var vertices : PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var found_world_point : bool = false
	for vertex : Vector3 in vertices:
		found_world_point = found_world_point or body.to_global(vertex).is_equal_approx(previous_world_point)
	_check(found_world_point, "Ribbon geometry compensates for the moving parent")
	light.call("_update_trail", 1.0, float(light.get("scared_speed")), float(light.get("scared_speed")))
	_check(body.width > core.width and body.lifetime > core.lifetime, "Body and core retain separate widths and lifetimes")
	light.call("_set_trail_emitting", false)
	_check(body.mesh.get_surface_count() == 0 and core.mesh.get_surface_count() == 0, "Stopping emission clears both ribbons")
	light.call("_set_trail_emitting", true)
	body._process(0.01)
	light.position.x += 0.2
	body._process(0.01)
	body.emitting = false
	body._process(body.lifetime + 0.01)
	_check(body._points.is_empty() and body.mesh.get_surface_count() == 0, "Lifetime removes expired samples and geometry")
	ship.free()
	print("Living light trail: %d failures on Godot %s" % [failures, Engine.get_version_info()["string"]])
	quit(1 if failures else 0)


func _check_ribbon(trail : LivingLightTrail) -> void:
	_check(trail.mesh.get_surface_count() == 1, "%s emits ribbon geometry" % trail.name)
	if trail.mesh.get_surface_count() == 0:
		return
	var arrays : Array = trail.mesh.surface_get_arrays(0)
	var vertices : PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var custom : PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	_check(vertices.size() >= 4 and custom.size() == vertices.size() * 4, "Ribbon supplies camera-facing shader attributes")
	_check(trail.to_global(vertices[0]).is_equal_approx(trail.global_position), "Ribbon starts on the creature")
	for vertex : Vector3 in vertices:
		_check(trail.custom_aabb.has_point(vertex), "Culling bounds include the trail history")


func _check(condition : bool, message : String) -> void:
	if not condition:
		failures += 1
		push_error(message)
