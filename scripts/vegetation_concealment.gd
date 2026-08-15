extends Area3D

@export_range(0.1, 1.0, 0.05) var visibility_multiplier : float = 0.4


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body : Node3D) -> void:
	if body.has_method("enter_concealment"):
		body.call("enter_concealment", self, visibility_multiplier)


func _on_body_exited(body : Node3D) -> void:
	if body.has_method("exit_concealment"):
		body.call("exit_concealment", self)
