extends StaticBody3D

@export var var_speed : float = 1.0

func _physics_process(delta: float) -> void:
	self.rotation.y += var_speed * delta
