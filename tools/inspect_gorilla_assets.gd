extends SceneTree

func _initialize() -> void:
	for path: String in ["res://PolygonFarm/Models/SM_Prop_Banana_01_Group.fbx", "res://PolygonFarm/Models/SM_Prop_Crate_01.fbx"]:
		var mesh: Mesh = load(path) as Mesh
		print("PROP ", path, " ", mesh.get_aabb())
	for path: String in ["res://PolygonKaiju/Characters/Kaiju_01_02_04.fbx", "res://SICSFarm/TFP_Banana_Box_Small_01A.fbx", "res://Temporarios/Animations/Meshes/PolygonSyntyCharacter.fbx", "res://animations/mixamo/ET_animated.glb"]:
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			continue
		var model: Node = scene.instantiate()
		print("ASSET ", path)
		for node: Node in model.find_children("*", "", true, false):
			if node is MeshInstance3D:
				print("MESH ", model.get_path_to(node), " bounds=", node.get_aabb(), " transform=", node.transform)
			elif node is Skeleton3D:
				var names: PackedStringArray = []
				for bone: int in range(node.get_bone_count()):
					names.append(node.get_bone_name(bone))
				print("RIG ", model.get_path_to(node), " bones=", names)
			elif node is AnimationPlayer:
				print("ANIMATIONS ", node.get_animation_list())
				if "Kaiju" in path:
					for clip: StringName in node.get_animation_list():
						var anim: Animation = node.get_animation(clip)
						print("CLIP ", clip, " length=", anim.length, " tracks=", anim.get_track_count())
		model.free()
	quit()
