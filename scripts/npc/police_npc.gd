class_name PoliceNPC
extends NPCActor

# this one points mesh container as itself, because the character
# meshes are spread among many skeletons instead of just one

@onready var mesh_container1: Node3D = $SK_Character_Female_Police/Root/Skeleton3D
@onready var mesh_container2: Node3D = $SK_Character_Male_Police/Root/Skeleton3D

var selected_mesh : MeshInstance3D

func _ready() -> void:
	randomize_appearance()
	reaction_mode = ReactionMode.CHASE
	can_socialize = false
	use_flashlight = false
	walk_speed *= 0.8
	alert_speed *= 0.8
	vision.sight_distance *= 0.7
	vision.sight_half_angle_degrees *= 0.7
	super()

func randomize_appearance() -> void:
	var meshes: Array[MeshInstance3D] = []

	# Get all mesh children from Skeleton3D
	for child in mesh_container1.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
			
	# Get all mesh children from Skeleton3D
	for child in mesh_container2.get_children():
		if child is MeshInstance3D:
			meshes.append(child)

	if meshes.is_empty():
		push_warning("No meshes found!")
		return

	# Select a random mesh
	var random_index : int = randi_range(0, meshes.size() - 1)
	selected_mesh = meshes[random_index]

	# Hide all meshes except the selected one
	for mesh in meshes:
		mesh.visible = (mesh == selected_mesh)
