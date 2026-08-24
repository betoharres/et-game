extends Node3D

@onready var parent: Node3D = get_parent_node_3d()
var rotation_motion: float = 0.0

func _physics_process(_delta: float) -> void:
	
	
	var linear_motion: Vector3 = parent.get("current_velocity") as Vector3
	linear_motion.y = 0.0

	var angular_motion: float = float(parent.get("current_rotation_velocity"))

	var target_rotation_motion : float = angular_motion * 1.3

	rotation_motion = lerp(
		rotation_motion,
		target_rotation_motion,
		0.25
	)

	var target_basis: Basis = (
		Basis(Vector3.UP, angular_motion) * parent.global_transform.basis
	)

	var current_offset : float = 0.0
	
	if linear_motion.length_squared() < 0.001:
		current_offset = lerpf(current_offset, 0.0, 0.25)
	else:
		current_offset = lerpf(current_offset, 2.0, 0.25)
		

	global_transform = Transform3D(
		target_basis,
		parent.global_position - parent.global_transform.basis.z * current_offset
	)
		 

func reset_motion() -> void:
	global_transform = parent.global_transform
