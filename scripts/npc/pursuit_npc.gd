class_name PursuitNPC
extends NPCActor

@export var profile: PursuitProfile


func _ready() -> void:
	walk_speed = profile.walk_speed
	alert_speed = profile.chase_speed
	rotation_speed = 8.0
	reaction_mode = ReactionMode.CHASE
	require_navigation = true
	grounded = true
	super()
	vision.sight_distance = profile.sight_distance
	navigation_agent.max_speed = alert_speed


func take_damage(amount: float, _hit_direction: Vector3 = Vector3.ZERO, _push_distance: float = 0.0) -> void:
	$NPCCombat.take_damage(amount)


func get_health() -> float:
	return $NPCCombat.health


func is_alive() -> bool:
	return get_health() > 0.0 and not is_queued_for_deletion()
