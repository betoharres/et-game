extends SceneTree

const OUTPUT_PATH := "res://scenes/SICSVegetationInstances.tscn"
const INSTANCE_REGION_WORLD_SIZE := 128.0
const ASSET_SCENES: Array[String] = [
	"res://scenes/SICS Trees/tem_tree_01a.tscn",
	"res://scenes/SICS Trees/tem_tree_02a.tscn",
	"res://scenes/SICS Trees/tem_tree_03a.tscn",
	"res://scenes/SICS Trees/tem_tree_04a.tscn",
	"res://scenes/SICS Trees/tem_tree_05a.tscn",
	"res://scenes/SICS Trees/tem_tree_06a.tscn",
	"res://scenes/SICS Trees/tem_grass_patch_01a.tscn",
	"res://scenes/SICS Trees/tem_grass_patch_02a.tscn",
	"res://scenes/SICS Trees/tem_grass_patch_03a.tscn",
	"res://scenes/SICS Trees/tem_grass_patch_04a.tscn",
	"res://scenes/SICS Trees/tem_grass_patch_05a.tscn",
]


func _initialize() -> void:
	var container := Node3D.new()
	container.name = "SICSVegetationInstances"
	var totals: PackedInt32Array = PackedInt32Array()
	totals.resize(ASSET_SCENES.size())
	var packed_assets: Array[PackedScene] = []
	for path: String in ASSET_SCENES:
		packed_assets.append(load(path) as PackedScene)

	var region_paths := _find_region_paths()
	for region_path: String in region_paths:
		var region: Resource = load(region_path)
		var location := _location_from_path(region_path)
		var region_origin := Vector3(
			location.x * INSTANCE_REGION_WORLD_SIZE,
			0.0,
			location.y * INSTANCE_REGION_WORLD_SIZE
		)
		var instances: Dictionary = region.get("instances")
		for asset_id: Variant in instances.keys():
			var id := int(asset_id)
			if id < 0 or id >= ASSET_SCENES.size():
				continue
			var cells: Dictionary = instances[asset_id]
			for cell: Variant in cells.keys():
				var cell_data: Array = cells[cell]
				var transforms: Array = cell_data[0]
				for stored_transform: Transform3D in transforms:
					var instance := packed_assets[id].instantiate() as Node3D
					instance.name = "%s_%05d" % [instance.name, totals[id]]
					instance.transform = Transform3D(
						stored_transform.basis,
						stored_transform.origin + region_origin
					)
					container.add_child(instance)
					instance.owner = container
					totals[id] += 1

	var output := PackedScene.new()
	var pack_error := output.pack(container)
	if pack_error != OK:
		push_error("Could not pack vegetation scene: %s" % error_string(pack_error))
		quit(1)
		return
	var save_error := ResourceSaver.save(output, OUTPUT_PATH)
	if save_error != OK:
		push_error("Could not save vegetation scene: %s" % error_string(save_error))
		quit(1)
		return
	for id: int in ASSET_SCENES.size():
		print("ASSET_ID_%d=%d %s" % [id, totals[id], ASSET_SCENES[id]])
	print("TOTAL=", _sum(totals))
	quit()


func _find_region_paths() -> Array[String]:
	var paths: Array[String] = []
	for file_name: String in DirAccess.get_files_at("res://scenes"):
		if file_name.begins_with("terrain3d") and file_name.ends_with(".res"):
			paths.append("res://scenes/" + file_name)
	paths.sort()
	return paths


func _location_from_path(path: String) -> Vector2i:
	var file_name := path.get_file().trim_prefix("terrain3d").trim_suffix(".res")
	var x_sign := -1 if file_name[0] == "-" else 1
	var z_sign := -1 if file_name[3] == "-" else 1
	return Vector2i(
		x_sign * int(file_name.substr(1, 2)),
		z_sign * int(file_name.substr(4, 2))
	)


func _sum(values: PackedInt32Array) -> int:
	var total := 0
	for value: int in values:
		total += value
	return total
