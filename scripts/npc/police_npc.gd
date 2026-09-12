class_name PoliceNPC
extends NPCActor

func _ready() -> void:
	reaction_mode = ReactionMode.CHASE
	can_socialize = false
	use_flashlight = false
	super()
