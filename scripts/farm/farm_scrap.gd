extends "res://scripts/spaceship_scraps.gd"


func _ready() -> void:
	add_to_group(&"pickup_items")
	add_to_group(&"farm_scraps")
	two_handed = false


func is_available_for_automatic_pickup() -> bool:
	return false


func get_pickup_target_position() -> Vector3:
	# A origem fica na base; mirar nela pode atingir a mesa após o assentamento da física.
	return ($CollisionShape3D as CollisionShape3D).global_position
