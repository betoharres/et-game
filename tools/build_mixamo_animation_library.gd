extends SceneTree

## Called by build_mixamo_character.py after Blender bakes the source FBXs.


func _init() -> void:
	var arguments : PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 2:
		_fail("Expected a baked GLB path and an AnimationLibrary output path")
		return
	var document : GLTFDocument = GLTFDocument.new()
	var state : GLTFState = GLTFState.new()
	if document.append_from_file(arguments[0], state) != OK:
		_fail("Could not read the baked Mixamo GLB")
		return
	var model : Node = document.generate_scene(state)
	if model == null:
		_fail("Could not instantiate the baked Mixamo GLB")
		return
	var animation_player : AnimationPlayer = model.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	if animation_player == null:
		model.free()
		_fail("The baked GLB has no AnimationPlayer")
		return
	var library : AnimationLibrary = AnimationLibrary.new()
	for animation_name : StringName in animation_player.get_animation_list():
		if animation_name == &"RESET":
			continue
		var animation : Animation = animation_player.get_animation(animation_name)
		if not _has_bone_motion(animation):
			model.free()
			_fail("Baked clip has no bone motion: %s" % animation_name)
			return
		library.add_animation(animation_name, animation)
	if library.get_animation_list().size() != 37:
		model.free()
		_fail("Expected 37 Mixamo clips, got %d" % library.get_animation_list().size())
		return
	var save_error : Error = ResourceSaver.save(library, arguments[1], ResourceSaver.FLAG_COMPRESS)
	model.free()
	if save_error != OK:
		_fail("Could not save the animation library: %s" % error_string(save_error))
		return
	print("MIXAMO_LIBRARY|PASS|37 clips with bone motion")
	quit()


func _has_bone_motion(animation : Animation) -> bool:
	for track_index : int in animation.get_track_count():
		if animation.track_get_type(track_index) != Animation.TYPE_ROTATION_3D:
			continue
		if not String(animation.track_get_path(track_index)).begins_with(
			"ETArmature/Skeleton3D:mixamorig_"
		):
			continue
		var first : Quaternion = animation.track_get_key_value(track_index, 0)
		for key_index : int in range(1, animation.track_get_key_count(track_index)):
			var rotation : Quaternion = animation.track_get_key_value(track_index, key_index)
			if not first.is_equal_approx(rotation):
				return true
	return false


func _fail(message : String) -> void:
	push_error(message)
	quit(1)
