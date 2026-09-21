class_name FarmerNPC
extends NPCActor

## Fazendeiro da zona rural: patrulha ou trabalha parado (via `patrol_points`),
## conversa ocasionalmente com outro fazendeiro, usa lanterna (o mapa é
## permanentemente noturno) e persegue o ET ao vê-lo. Toda a lógica de
## decisão vive na `NPCBehaviorTree.tscn` compartilhada; este script só fixa
## os parâmetros padrão do papel de fazendeiro.

@onready var mesh_container: Node3D = $Characters/Skeleton3D

var selected_mesh : MeshInstance3D

func _ready() -> void:
	randomize_appearance()
	can_socialize = true
	social_group_name = &"farmers"
	reaction_mode = ReactionMode.CHASE
	use_flashlight = true
	super()

func randomize_appearance() -> void:
	var meshes: Array[MeshInstance3D] = []

	# Get all mesh children from Skeleton3D
	for child in mesh_container.get_children():
		if child is MeshInstance3D:
			meshes.append(child)

	if meshes.is_empty():
		push_warning("No meshes found!")
		return

	# Select a random mesh, from 1 to exclude scarecrow
	var random_index : int = randi_range(1, meshes.size() - 1)
	selected_mesh = meshes[random_index]

	# Hide all meshes except the selected one
	for mesh in meshes:
		mesh.visible = (mesh == selected_mesh)
