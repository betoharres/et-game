class_name LegacyEnemyAwareness
extends NPCHearing

@export var investigate_wait_time: float = 2.0
@export var investigation_timeout: float = 15.0

var _investigation_elapsed: float = 0.0
var _arrival_elapsed: float = 0.0

@onready var _body: CharacterBody3D = get_parent() as CharacterBody3D
@onready var _navigation: NavigationAgent3D = get_node("../NavigationAgent3D") as NavigationAgent3D
@onready var _alert: Node = get_node_or_null("/root/PhotoAlertSystem")


func is_enemy_listener() -> bool:
	return true


func is_globally_alerted() -> bool:
	return is_instance_valid(_alert) and int(_alert.call("get_photo_count")) > 0


func get_awareness_state() -> StringName:
	if not bool(_body.call("_is_player_alive")):
		return &"neutral"
	var detected: bool = bool(_body.get("has_detected_player"))
	if detected and bool(_body.get("has_visual_contact")):
		return &"pursuit"
	if is_globally_alerted() or detected or has_noise_to_investigate() or float(_body.get("detection_progress")) > 0.0:
		return &"alert"
	return &"neutral"


func get_sight_distance(neutral_distance: float) -> float:
	return NPCVision.ALERT_SIGHT_DISTANCE if is_globally_alerted() else neutral_distance


func get_sight_half_angle(neutral_half_angle: float) -> float:
	return NPCVision.ALERT_SIGHT_HALF_ANGLE_DEGREES if is_globally_alerted() else neutral_half_angle


func investigate(delta: float, speed: float, turn_speed: float) -> bool:
	if not bool(_body.call("_is_player_alive")) or (
		bool(_body.get("has_visual_contact")) and bool(_body.get("has_detected_player"))
	):
		consume_noise()
		finish_investigation()
		return false
	if not has_noise_to_investigate():
		return false
	if has_pending_noise():
		_navigation.target_position = begin_investigation()
		_investigation_elapsed = 0.0
		_arrival_elapsed = 0.0
		_body.set("has_wander_target", false)
	_investigation_elapsed += delta
	if _investigation_elapsed >= investigation_timeout:
		finish_investigation()
		_body.velocity = Vector3.ZERO
		return true
	var navigation_map: RID = _navigation.get_navigation_map()
	if not navigation_map.is_valid() or NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		_body.velocity = Vector3.ZERO
		return true
	var next_position: Vector3 = _navigation.get_next_path_position()
	if _navigation.is_navigation_finished():
		_body.velocity = Vector3.ZERO
		_arrival_elapsed += delta
		if _arrival_elapsed >= investigate_wait_time:
			finish_investigation()
		return true
	var direction: Vector3 = next_position - _body.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		_body.velocity = Vector3.ZERO
		return true
	direction = direction.normalized()
	_body.velocity = direction * speed
	_body.move_and_slide()
	_body.rotation.y = lerp_angle(_body.rotation.y, atan2(direction.x, direction.z), delta * turn_speed)
	return true
