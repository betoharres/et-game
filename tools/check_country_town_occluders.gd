extends "res://tools/build_country_town_occluders.gd"

## Checks baked geometry and viewport lifecycle, not rendering effectiveness.
var _failures: int = 0


func _initialize() -> void:
	_check.call_deferred()


func _check() -> void:
	var fixture: Node3D = Node3D.new()
	_panel(fixture, "SM_Bld_LeftWall", -2.0)
	_panel(fixture, "SM_Bld_RightWall", 2.0)
	var glass: MeshInstance3D = _panel(fixture, "SM_Bld_Glass", 0.0)
	(glass.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_panel(fixture, "SM_Bld_House_Door_01", 0.0)
	var hidden: MeshInstance3D = _panel(fixture, "SM_Bld_Hidden", 0.0)
	hidden.hide()
	var ranged: MeshInstance3D = _panel(fixture, "SM_Bld_Distant", 0.0)
	ranged.visibility_range_end = 20.0
	var moving: AnimatableBody3D = AnimatableBody3D.new()
	fixture.add_child(moving)
	_panel(moving, "SM_Bld_Moving", 0.0)
	_collect(fixture, Transform3D.IDENTITY, "Fixture")
	_require(_mesh_count == 2, "Only the two opaque, static, always-visible walls may be baked")
	var faces: PackedVector3Array = []
	for key: Vector2i in _cells:
		var cell: Dictionary = _cells[key]
		var origin: Vector3 = Vector3((key.x + 0.5) * CELL_SIZE, 0, (key.y + 0.5) * CELL_SIZE)
		for index: int in cell["indices"]:
			faces.append(cell["vertices"][index] + origin)
	_require(not faces.is_empty(), "Fixture triangles are valid")
	var hits_opening: bool = false
	var hits_wall: bool = false
	for index: int in range(0, faces.size(), 3):
		hits_opening = hits_opening or Geometry3D.segment_intersects_triangle(Vector3(0, 0, 2), Vector3(0, 0, -2), faces[index], faces[index + 1], faces[index + 2]) != null
		hits_wall = hits_wall or Geometry3D.segment_intersects_triangle(Vector3(-2, 0, 2), Vector3(-2, 0, -2), faces[index], faces[index + 1], faces[index + 2]) != null
	_require(not hits_opening, "Door/window opening stays clear")
	_require(hits_wall, "Opaque wall remains a blocker")
	fixture.free()

	var packed: PackedScene = load(OUTPUT) as PackedScene
	var occlusion: Node3D = packed.instantiate() as Node3D
	_require(occlusion.get_child_count() > 0, "Saved level has occluders")
	for child: Node in occlusion.get_children():
		var instance: OccluderInstance3D = child as OccluderInstance3D
		_require(instance != null, "Saved cells use native OccluderInstance3D")
		if instance == null:
			continue
		var mesh: ArrayOccluder3D = instance.occluder as ArrayOccluder3D
		_require(mesh != null and mesh.indices.size() > 0, "Saved cell has baked triangles")
		for index: int in mesh.indices:
			_require(index >= 0 and index < mesh.vertices.size(), "Saved index is valid")
		for vertex: Vector3 in mesh.vertices:
			_require(vertex.is_finite(), "Saved vertex is finite")
	var viewport: SubViewport = SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var camera: Camera3D = Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	viewport.use_occlusion_culling = false
	viewport.add_child(occlusion)
	_require(viewport.use_occlusion_culling, "Entering Country Town enables viewport occlusion")
	occlusion.hide()
	occlusion.call("_update_occlusion")
	_require(not viewport.use_occlusion_culling, "Hiding Occlusion permits a profiler A/B comparison")
	occlusion.show()
	camera.cull_mask = 0
	occlusion.call("_update_occlusion")
	_require(not viewport.use_occlusion_culling, "Camera masks cannot leave invisible blockers")
	camera.cull_mask = 1048575
	occlusion.call("_update_occlusion")
	_require(viewport.use_occlusion_culling, "Restoring camera layers re-enables occlusion")
	occlusion.free()
	_require(not viewport.use_occlusion_culling, "Leaving the level restores the previous viewport setting")
	viewport.use_occlusion_culling = true
	occlusion = packed.instantiate() as Node3D
	viewport.add_child(occlusion)
	occlusion.free()
	_require(viewport.use_occlusion_culling, "Previously enabled occlusion is also preserved")
	viewport.free()
	print("Country Town occluders: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _panel(parent: Node3D, panel_name: String, x: float) -> MeshInstance3D:
	var panel: MeshInstance3D = MeshInstance3D.new()
	panel.name = panel_name
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2, 3)
	panel.mesh = quad
	panel.material_override = StandardMaterial3D.new()
	panel.position.x = x
	parent.add_child(panel)
	return panel


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
