extends SceneTree

const Layout: GDScript = preload("res://tools/build_country_town_layout.gd")
const Profile: GDScript = preload("res://scripts/terrain/rural_road_profile.gd")
const PRESET: String = "res://Materiais/rural_road_gentle.tres"
const BASE: String = "res://scenes/CountryTown/Districts/"


static func segments() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var primary: Array[Dictionary] = Layout.road_segments()
	for i: int in primary.size():
		if str(Layout.ROAD_RUNS[i][0]).begins_with("dirt"):
			var segment: Dictionary = primary[i].duplicate()
			segment["width"] = 8.0
			result.append(segment)
	for path: Dictionary in Layout.SECONDARY_PATHS:
		if path["urban"]:
			continue
		var points: Array = path["points"]
		for i: int in points.size() - 1:
			result.append({"start": points[i], "end": points[i + 1], "width": path["width"]})
	return result


static func protected_zones() -> Array[Vector3]:
	var result: Array[Vector3] = [Vector3(312.1, 167.46, 26.0), Vector3(204.9, 298.48, 26.0)]
	for path: Dictionary in Layout.SECONDARY_PATHS:
		if path["urban"]:
			continue
		var points: Array = path["points"]
		for point: Vector2 in [points.front(), points.back()]:
			result.append(Vector3(point.x, point.y, 2.0))
	return result


func _initialize() -> void:
	var profile: Resource = load(PRESET)
	if profile == null or profile.surface_material == null:
		push_error("Missing rural road profile/material; import the project first.")
		quit(1)
		return
	profile.configure(segments(), protected_zones())
	for scene_name: String in ["RoadNetwork", "SecondaryPaths"]:
		var path: String = BASE + scene_name + ".tscn"
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			push_error("Missing source road scene: " + path)
			quit(1)
			return
		var scene: Node = packed.instantiate()
		var labels: Array[String] = []
		labels.assign(["DirtRoadBed", "RuralShoulders"] if scene_name == "RoadNetwork" else ["RuralTrails", "TrailShoulders"])
		for label: String in labels:
			var node: MeshInstance3D = scene.get_node(label) as MeshInstance3D
			profile.bake(node, label == "DirtRoadBed" or label == "RuralTrails")
		var output: PackedScene = PackedScene.new()
		var result: Error = output.pack(scene)
		if result == OK:
			result = ResourceSaver.save(output, path)
		scene.free()
		if result != OK:
			push_error("Cannot save rural roads: " + path)
			quit(1)
			return
	print("Rural road profile applied; asphalt, route widths and bridge ramps retained.")
	quit()
