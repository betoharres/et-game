extends SceneTree

## Saves occluders without running level scripts. Rebuild after moving buildings
## or regenerating their districts. Headless is sufficient for asset generation;
## culling effectiveness must be measured with a real renderer.
const OUTPUT: String = "res://scenes/CountryTown/Districts/Occlusion.tscn"
const WORLD: String = "res://scenes/CountryTown/CountryTown.tscn"
const CONTROLLER: Script = preload("res://scripts/country_town_occlusion.gd")
const DISTRICTS: PackedStringArray = ["FarmDistrict", "TownDistrict", "DeliveryYard"]
const CELL_SIZE: float = 32.0
const MIN_TRIANGLE_AREA: float = 0.5

var _cells: Dictionary[Vector2i, Dictionary] = {}
var _source_layers: int = 0
var _mesh_count: int = 0
var _triangle_count: int = 0


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	# Read only the three district instances and their transforms from the level.
	var level_text: String = FileAccess.get_file_as_string(WORLD)
	for name: String in DISTRICTS:
		var packed: PackedScene = load("res://scenes/CountryTown/Districts/%s.tscn" % name) as PackedScene
		assert(packed != null, "Missing district: " + name)
		var district: Node3D = packed.instantiate() as Node3D
		var section: RegEx = RegEx.create_from_string('(?m)^\\[node name="%s" parent="\\."[^\\n]*\\]\\n([^\\[]*)' % name)
		var match_section: RegExMatch = section.search(level_text)
		assert(match_section != null, "District is no longer a direct child: " + name)
		for line: String in match_section.get_string(1).split("\n"):
			if line.begins_with("transform = "):
				district.transform = str_to_var(line.trim_prefix("transform = "))
		print("Collecting occluders: " + name)
		_collect(district, Transform3D.IDENTITY, name)
		district.free()
	if _cells.is_empty():
		push_error("No opaque structural surfaces found")
		quit(1)
		return
	var scene: Node3D = Node3D.new()
	scene.name = "Occlusion"
	scene.set_script(CONTROLLER)
	scene.set("source_layers", _source_layers)
	for key: Vector2i in _cells:
		var cell: Dictionary = _cells[key]
		var occluder: ArrayOccluder3D = ArrayOccluder3D.new()
		occluder.set_arrays(cell["vertices"], cell["indices"])
		var instance: OccluderInstance3D = OccluderInstance3D.new()
		instance.name = "Buildings_%d_%d" % [key.x, key.y]
		instance.position = Vector3((key.x + 0.5) * CELL_SIZE, 0, (key.y + 0.5) * CELL_SIZE)
		instance.occluder = occluder
		instance.set_meta("sources", PackedStringArray(cell["sources"].keys()))
		scene.add_child(instance)
		instance.owner = scene
	var result: PackedScene = PackedScene.new()
	var error: Error = result.pack(scene)
	if error == OK:
		error = ResourceSaver.save(result, OUTPUT)
	print("Country Town occluders: %d cells, %d source meshes, %d triangles; save=%s" % [
		_cells.size(), _mesh_count, _triangle_count, error_string(error)])
	scene.free()
	quit(0 if error == OK else 1)


func _collect(node: Node, parent_transform: Transform3D, path: String) -> void:
	if node is GeometryInstance3D:
		var geometry: GeometryInstance3D = node as GeometryInstance3D
		# An invisible or distance-culled facade cannot remain an opaque blocker.
		if geometry.visibility_range_begin > 0.0 or geometry.visibility_range_end > 0.0 or not geometry.visibility_parent.is_empty():
			return
	if node is Node3D and not (node as Node3D).visible:
		return
	if node is AnimatableBody3D or (node is PhysicsBody3D and not node is StaticBody3D):
		return
	var node_name: String = String(node.name).to_lower()
	if node_name.contains("door") and not node_name.contains("wall"):
		return
	var script: Script = node.get_script() as Script
	if script != null and script.resource_path in ["res://scripts/house_door.gd", "res://scripts/windmill.gd"]:
		return
	if path.contains("Moveis") or path.contains("Cortina") or path.to_lower().contains("greenhouse"):
		return
	var transform: Transform3D = parent_transform
	if node is Node3D:
		transform *= (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node.mesh != null and (mesh_node.mesh.resource_path.contains("SM_Bld_") or String(mesh_node.name).begins_with("SM_Bld_")):
			_add_mesh(mesh_node, transform, path)
	for child: Node in node.get_children():
		_collect(child, transform, path + "/" + String(child.name))


func _add_mesh(node: MeshInstance3D, transform: Transform3D, path: String) -> void:
	var added: bool = false
	for surface: int in node.mesh.get_surface_count():
		var material: BaseMaterial3D = node.get_active_material(surface) as BaseMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		if material.proximity_fade_enabled or material.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED or material.grow or material.heightmap_enabled:
			continue
		var arrays: Array = node.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count: int = vertices.size() if indices.is_empty() else indices.size()
		for index: int in range(0, count - 2, 3):
			var a: Vector3 = transform * vertices[index if indices.is_empty() else indices[index]]
			var b: Vector3 = transform * vertices[index + 1 if indices.is_empty() else indices[index + 1]]
			var c: Vector3 = transform * vertices[index + 2 if indices.is_empty() else indices[index + 2]]
			if (b - a).cross(c - a).length() * 0.5 < MIN_TRIANGLE_AREA:
				continue
			# Keep original triangles: bounding boxes or hulls would close openings.
			_add_triangle(a, b, c, path)
			added = true
	if added:
		_mesh_count += 1
		_source_layers |= node.layers


func _add_triangle(a: Vector3, b: Vector3, c: Vector3, source: String) -> void:
	var center: Vector3 = (a + b + c) / 3.0
	var key: Vector2i = Vector2i(floori(center.x / CELL_SIZE), floori(center.z / CELL_SIZE))
	if not _cells.has(key):
		_cells[key] = {"vertices": PackedVector3Array(), "indices": PackedInt32Array(), "lookup": {}, "sources": {}}
	var cell: Dictionary = _cells[key]
	var origin: Vector3 = Vector3((key.x + 0.5) * CELL_SIZE, 0, (key.y + 0.5) * CELL_SIZE)
	for vertex: Vector3 in [a, b, c]:
		var local: Vector3 = vertex - origin
		if not cell["lookup"].has(local):
			cell["lookup"][local] = cell["vertices"].size()
			cell["vertices"].append(local)
		cell["indices"].append(cell["lookup"][local])
	cell["sources"][source] = true
	_triangle_count += 1
