class_name PursuitNavigation
extends NavigationRegion3D

@export var navigation_region_path: NodePath
var _level_region: NavigationRegion3D


func _ready() -> void:
	configure.call_deferred()


func configure() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_level_region = await NPCNavigation.wait_for_region(self, navigation_region_path)
	if not is_inside_tree():
		return
	if _level_region == null:
		push_warning("%s: no saved level navigation mesh found; reinforcements cannot spawn. Bake navigation in the editor." % get_path())
		return
	set_navigation_map(_level_region.get_navigation_map())


func is_ready_for_paths() -> bool:
	return is_instance_valid(_level_region) and _level_region.enabled and NavigationServer3D.map_get_iteration_id(get_navigation_map()) > 0
