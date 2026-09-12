extends NavigationRegion3D

var _pedestrian_map: RID


func _ready() -> void:
	# A população antiga ainda usa movimento direto; não altere seu mapa global.
	_pedestrian_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(_pedestrian_map, navigation_mesh.cell_size)
	NavigationServer3D.map_set_cell_height(_pedestrian_map, navigation_mesh.cell_height)
	NavigationServer3D.map_set_active(_pedestrian_map, true)
	set_navigation_map(_pedestrian_map)
	for child: Node in get_node("Pedestrians").get_children():
		var actor: NPCActor = child as NPCActor
		actor.navigation_agent.set_navigation_map(_pedestrian_map)


func _exit_tree() -> void:
	if _pedestrian_map.is_valid():
		NavigationServer3D.free_rid(_pedestrian_map)
