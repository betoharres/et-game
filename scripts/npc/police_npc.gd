class_name PoliceNPC
extends NPCActor

func _ready() -> void:
	reaction_mode = ReactionMode.CHASE
	can_socialize = false
	use_flashlight = false
	walk_speed *= 0.8
	alert_speed *= 0.8
	vision.sight_distance *= 0.7
	vision.sight_half_angle_degrees *= 0.7
	super()
