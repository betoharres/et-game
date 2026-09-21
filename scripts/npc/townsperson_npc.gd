class_name TownspersonNPC
extends NPCActor

## Base do morador da zona urbana: caminha entre casa e comércio e foge ao
## ver o ET. "Procurar ajuda" fica documentado como extensão futura — hoje
## não há um destino de ajuda definido no jogo para apontar sem inventar um.

@onready var mesh_container: Node3D = $Characters/Skeleton3D

var selected_mesh : MeshInstance3D

func _ready() -> void:
	randomize_appearance()
	reaction_mode = ReactionMode.FLEE
	can_socialize = routine != null
	use_flashlight = false
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

	# Select a random mesh
	var random_index : int = randi_range(0, meshes.size() - 1)
	selected_mesh = meshes[random_index]

	# Hide all meshes except the selected one
	for mesh in meshes:
		mesh.visible = (mesh == selected_mesh)
