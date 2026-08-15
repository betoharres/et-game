extends CharacterBody3D

signal photo_taken(current_photo_count : int)

@export_category("Movement")
@export var walk_speed : float = 1.8
@export var chase_speed : float = 3.2
@export var rotation_speed : float = 4.0
@export var wander_distance : float = 10.0
@export var wander_wait_time : float = 2.0
@export var wander_zone_center : Vector3 = Vector3.ZERO
@export var wander_zone_radius : float = 14.0

@export_category("Vision")
@export var sight_distance : float = 17.0
@export_range(10.0, 120.0, 1.0) var sight_angle : float = 70.0
@export var detection_time : float = 0.55
@export var lose_sight_after : float = 3.5
@export var eye_height : float = 1.55
@export var player_target_height : float = 0.5
@export var close_perception_radius : float = 1.8

@export_category("Photography")
@export var photo_distance : float = 9.0
@export var focus_time : float = 1.2
@export var seconds_between_photos : float = 6.0
@export var flash_duration : float = 0.1

@onready var navigation_agent : NavigationAgent3D = $NavigationAgent3D
@onready var camera_flash : Node3D = $CameraRig/CameraFlash
@onready var flash_timer : Timer = $CameraRig/FlashTimer

var player : CharacterBody3D = null
var has_visual_contact : bool = false
var has_detected_player : bool = false
var detection_progress : float = 0.0
var focus_progress : float = 0.0
var photo_cooldown : float = 0.0
var has_wander_target : bool = false
var wander_wait_timer : float = 0.0
var time_without_visual_contact : float = 0.0
var last_known_player_position : Vector3
var has_last_known_position : bool = false
var photo_alert_system : Node = null


func _ready() -> void:
	_find_player()
	photo_alert_system = get_node_or_null("/root/PhotoAlertSystem")
	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = 1.0
	flash_timer.wait_time = flash_duration
	flash_timer.timeout.connect(_hide_camera_flash)
	if photo_alert_system != null:
		photo_alert_system.set_photographer_observing(get_instance_id(), false)


func _exit_tree() -> void:
	if photo_alert_system != null:
		photo_alert_system.unregister_photographer(get_instance_id())
	if player != null and player.has_method("set_vision_contact"):
		player.call("set_vision_contact", self, false)


func _physics_process(delta : float) -> void:
	photo_cooldown = maxf(photo_cooldown - delta, 0.0)

	if player == null or not is_instance_valid(player):
		_find_player()

	if player == null or not _is_player_alive():
		has_visual_contact = false
		has_detected_player = false
		detection_progress = 0.0
		if player != null and player.has_method("set_vision_contact"):
			player.call("set_vision_contact", self, false)
		focus_progress = 0.0
		time_without_visual_contact = 0.0
		velocity = Vector3.ZERO
		if photo_alert_system != null:
			photo_alert_system.set_photographer_observing(
				get_instance_id(),
				false
			)
		return

	has_visual_contact = _can_see_player()
	if player.has_method("set_vision_contact"):
		player.call("set_vision_contact", self, has_visual_contact)
	var visibility_multiplier : float = _get_player_visibility_multiplier()
	if has_visual_contact:
		last_known_player_position = player.global_position
		has_last_known_position = true
		time_without_visual_contact = 0.0
		if not has_detected_player:
			detection_progress = minf(
				detection_progress + delta * visibility_multiplier,
				maxf(detection_time, 0.0)
			)
			if detection_progress >= detection_time:
				has_detected_player = true
	else:
		detection_progress = maxf(detection_progress - delta, 0.0)
		time_without_visual_contact += delta
		if has_detected_player and time_without_visual_contact >= lose_sight_after:
			has_detected_player = false
	if photo_alert_system != null:
		photo_alert_system.set_photographer_observing(
			get_instance_id(),
			has_visual_contact
		)

	if has_visual_contact and has_detected_player:
		_follow_or_photograph(delta)
	elif has_detected_player and has_last_known_position and time_without_visual_contact < lose_sight_after:
		focus_progress = 0.0
		_move_toward_position(last_known_player_position, chase_speed, delta)
	else:
		focus_progress = 0.0
		_wander(delta)


func _find_player() -> void:
	for character : Node in get_tree().get_nodes_in_group("characters"):
		if character is CharacterBody3D:
			player = character
			return

	player = null


func _follow_or_photograph(delta : float) -> void:
	var offset : Vector3 = player.global_position - global_position
	offset.y = 0.0
	var distance : float = offset.length()

	if offset.length_squared() > 0.001:
		_face_direction(offset.normalized(), delta)

	if distance > photo_distance:
		focus_progress = 0.0
		_move_toward_position(player.global_position, chase_speed, delta)
		return

	velocity = Vector3.ZERO
	focus_progress = minf(
		focus_progress + delta,
		maxf(focus_time, 0.0)
	)

	if focus_progress >= focus_time and photo_cooldown <= 0.0:
		_take_photo()


func _take_photo() -> void:
	if player == null or not has_visual_contact or not has_detected_player or not _is_player_alive():
		return

	photo_cooldown = maxf(seconds_between_photos, 0.1)
	focus_progress = 0.0
	camera_flash.visible = true
	flash_timer.start(maxf(flash_duration, 0.01))

	var current_photo_count : int = 0
	if photo_alert_system != null:
		current_photo_count = photo_alert_system.register_photo(
			get_instance_id()
		)
	photo_taken.emit(current_photo_count)


func _hide_camera_flash() -> void:
	camera_flash.visible = false


func _wander(delta : float) -> void:
	if wander_wait_timer > 0.0:
		wander_wait_timer -= delta
		velocity = Vector3.ZERO
		return

	var navigation_map : RID = navigation_agent.get_navigation_map()

	if (
		not navigation_map.is_valid()
		or NavigationServer3D.map_get_iteration_id(navigation_map) == 0
	):
		velocity = Vector3.ZERO
		return

	if not has_wander_target:
		var random_direction := Vector3(
			randf_range(-1.0, 1.0),
			0.0,
			randf_range(-1.0, 1.0)
		)

		if random_direction.length_squared() < 0.01:
			return

		var requested_position : Vector3 = (
			wander_zone_center
			+ random_direction.normalized()
			* randf_range(2.0, wander_zone_radius)
		)
		navigation_agent.target_position = (
			NavigationServer3D.map_get_closest_point(
				navigation_map,
				requested_position
			)
		)
		has_wander_target = true
		return

	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		has_wander_target = false
		wander_wait_timer = wander_wait_time
		return

	_move_along_navigation(walk_speed, delta)


func _move_toward_position(
	target_position : Vector3,
	movement_speed : float,
	delta : float
) -> void:
	var navigation_map : RID = navigation_agent.get_navigation_map()

	if (
		not navigation_map.is_valid()
		or NavigationServer3D.map_get_iteration_id(navigation_map) == 0
	):
		velocity = Vector3.ZERO
		return

	navigation_agent.target_position = target_position
	_move_along_navigation(movement_speed, delta)


func _move_along_navigation(movement_speed : float, delta : float) -> void:
	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		return

	var direction : Vector3 = (
		navigation_agent.get_next_path_position() - global_position
	)
	direction.y = 0.0

	if direction.length_squared() < 0.01:
		velocity = Vector3.ZERO
		return

	direction = direction.normalized()
	velocity = direction * movement_speed
	move_and_slide()
	_face_direction(direction, delta)


func _face_direction(direction : Vector3, delta : float) -> void:
	if direction.length_squared() < 0.001:
		return

	rotation.y = lerp_angle(
		rotation.y,
		atan2(direction.x, direction.z),
		delta * rotation_speed
	)


func _can_see_player() -> bool:
	if player == null or get_world_3d() == null:
		return false

	var direction : Vector3 = player.global_position - global_position
	direction.y = 0.0
	var distance : float = direction.length()
	if distance <= close_perception_radius:
		return _has_clear_line_of_sight()

	var effective_sight_distance : float = (
		sight_distance * _get_player_visibility_multiplier()
	)

	if distance > effective_sight_distance:
		return false

	if distance >= 0.01:
		direction = direction.normalized()
		var forward : Vector3 = get_vision_forward()
		var view_angle : float = rad_to_deg(
			acos(clampf(forward.dot(direction), -1.0, 1.0))
		)

		if view_angle > sight_angle:
			return false

	return _has_clear_line_of_sight()


func _has_clear_line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		get_vision_origin(),
		player.global_position + Vector3.UP * player_target_height
	)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit : Dictionary = get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return true

	var collider : Object = hit.get("collider") as Object

	if collider == player:
		return true

	return collider is Node and player.is_ancestor_of(collider as Node)


func _get_player_visibility_multiplier() -> float:
	if player != null and player.has_method("get_stealth_visibility"):
		return clampf(
			float(player.call("get_stealth_visibility")),
			0.1,
			1.0
		)

	if player != null and player.has_method("get_visibility_multiplier"):
		return clampf(
			float(player.call("get_visibility_multiplier")),
			0.1,
			1.0
		)

	return 1.0


func get_vision_origin() -> Vector3:
	return global_position + Vector3.UP * eye_height


func get_vision_forward() -> Vector3:
	var forward : Vector3 = global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return Vector3.FORWARD
	return forward.normalized()


func _is_player_alive() -> bool:
	if player == null:
		return false

	if player.has_method("is_alive"):
		return bool(player.call("is_alive"))

	return true
