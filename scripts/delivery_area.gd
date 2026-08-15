extends Area3D

@export var default_score : int = 10

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body : Node3D) -> void:
	# For items that fall on the area, but are not being carried by the player
	if body is RigidBody3D:
		if body.is_in_group("pickup_items"):
			GlobalScore.add_score(body.score_value)
			body.queue_free()
			return

	if body is CharacterBody3D:
		if body.has_method("deliver_item"):
			body.deliver_item(self)
			return

	
