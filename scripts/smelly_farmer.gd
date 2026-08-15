extends CharacterBody3D

# Navigation

@onready var navigation_agent : NavigationAgent3D = $NavigationAgent3D

@export var walk_speed : float = 2.0
@export var chase_speed : float = 3.0
@export var rotation_speed : float = 2.0

@export var wander_distance : float = 8.0
@export var wander_wait_time : float = 2.0
@export var wander_zone_center : Vector3 = Vector3.ZERO
@export var wander_zone_radius : float = 14.0

var has_wander_target : bool = false

@export_category("Vision")

@export var sight_distance : float = 12.0
@export_range(10.0, 120.0, 1.0) var sight_angle : float = 70.0
@export var detection_time : float = 0.55
@export var lose_sight_after : float = 4.0
@export var eye_height : float = 1.55
@export var player_target_height : float = 0.5
@export var close_perception_radius : float = 1.8

var player : CharacterBody3D = null
var has_detected_player : bool = false
var has_visual_contact : bool = false
var detection_progress : float = 0.0
var time_without_visual_contact : float = 0.0
var last_known_player_position : Vector3

# Shooting

@export var shoot_distance : float = 10.5
@export var shoot_damage : float = 15.0
@export var seconds_between_shots : float = 2.0
@export var shot_knockback_distance : float = 0.5
@export var muzzle_flash_duration : float = 0.08
@export var aim_stabilization_time : float = 0.45
@export_range(0.0, 1.0, 0.01) var maximum_shot_accuracy : float = 0.8
@export_range(0.0, 1.0, 0.01) var minimum_shot_accuracy : float = 0.45
@export_range(0.0, 1.0, 0.01) var movement_accuracy_penalty : float = 0.1
@export_range(0.0, 1.0, 0.01) var concealment_accuracy_penalty : float = 0.18
@export var close_spread_degrees : float = 1.5
@export var far_spread_degrees : float = 5.0
@export var movement_spread_bonus_degrees : float = 2.5
@export var concealment_spread_bonus_degrees : float = 4.0
@export var confirmed_hit_radius : float = 0.035
@export var confirmed_hit_height_variation : float = 0.18
@export var consecutive_hit_mercy_threshold : int = 2
@export var mercy_accuracy_penalty : float = 0.3
@export var mercy_spread_bonus_degrees : float = 7.0
@export var miss_target_radius : float = 0.55

var shoot_timer : float = 0.0
var aim_progress : float = 0.0
var consecutive_hits : int = 0

@onready var gunshot_audio : Node = (
	$IKcontainer/HandR/Shotgun/Muzzle/GunshotAudio
)
@onready var muzzle_flash : Node3D = (
	$IKcontainer/HandR/Shotgun/Muzzle/MuzzleFlash
)
@onready var muzzle_flash_timer : Timer = (
	$IKcontainer/HandR/Shotgun/Muzzle/MuzzleFlashTimer
)
@onready var muzzle : Node3D = $IKcontainer/HandR/Shotgun/Muzzle

# IK anims
@onready var target_marker : Marker3D = $IKcontainer/HeadTarget

@export var look_random_distance : float = 3.0
@export var look_random_interval : float = 2.0
@export var look_random_height : float = 1.5
@export var look_speed : float = 4.0

var look_random_timer : float = 0.0
var random_look_target : Vector3

# State

enum State {
	WANDERING,
	CHASING,
	SHOOTING
}

var current_state : State = State.WANDERING

var wander_wait_timer : float = 0.0


func _ready() -> void:
	var characters : Array[Node] = get_tree().get_nodes_in_group("characters")
	
	for character in characters:
		if character is CharacterBody3D:
			player = character
			break

	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = 0.8
	muzzle_flash_timer.wait_time = muzzle_flash_duration
	muzzle_flash_timer.timeout.connect(_hide_muzzle_flash)

	if player != null:
		last_known_player_position = player.global_position


func _exit_tree() -> void:
	if player != null and player.has_method("set_vision_contact"):
		player.call("set_vision_contact", self, false)
	
func _physics_process(delta : float) -> void:

	if player == null:
		return

	shoot_timer = maxf(shoot_timer - delta, 0.0)

	update_vision(delta)

	match current_state:

		State.WANDERING:
			random_walk(delta)

		State.CHASING:
			close_distance()

		State.SHOOTING:
			shoot(delta)

	update_head_look(delta)

# --------------------------------------------------
# RANDOM WALK
# --------------------------------------------------

func random_walk(delta : float) -> void:
	aim_progress = 0.0

	if wander_wait_timer > 0.0:
		velocity = Vector3.ZERO
		wander_wait_timer -= delta
		return


	var navigation_map : RID = navigation_agent.get_navigation_map()

	if not navigation_map.is_valid():
		velocity = Vector3.ZERO
		return


	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		velocity = Vector3.ZERO
		return


	# Pick a new destination

	if not has_wander_target:

		var random_direction : Vector3 = Vector3(
			randf_range(-1.0, 1.0),
			0.0,
			randf_range(-1.0, 1.0)
		)

		if random_direction.length_squared() < 0.01:
			return

		random_direction = random_direction.normalized()

		var random_distance : float = randf_range(2.0, wander_zone_radius)

		var random_position : Vector3 = (
			wander_zone_center
			+ random_direction * random_distance
		)

		var valid_position : Vector3 = (
			NavigationServer3D.map_get_closest_point(
				navigation_map,
				random_position
			)
		)

		navigation_agent.target_position = valid_position

		has_wander_target = true

		return


	# Wait until the navigation agent has calculated a path

	if navigation_agent.is_navigation_finished():

		velocity = Vector3.ZERO

		has_wander_target = false
		wander_wait_timer = wander_wait_time

		return


	# Follow the navigation path

	var next_position : Vector3 = (
		navigation_agent.get_next_path_position()
	)

	var direction : Vector3 = (
		next_position - global_position
	)

	direction.y = 0.0


	if direction.length_squared() < 0.01:

		velocity = Vector3.ZERO

		return


	direction = direction.normalized()

	velocity = direction * walk_speed

	move_and_slide()

	face_direction(direction)
		
# --------------------------------------------------
# VISION
# --------------------------------------------------

func update_vision(delta : float) -> void:

	if player == null:
		return

	if not _is_player_alive():
		has_visual_contact = false
		if player.has_method("set_vision_contact"):
			player.call("set_vision_contact", self, false)
		has_detected_player = false
		detection_progress = 0.0
		velocity = Vector3.ZERO
		current_state = State.WANDERING
		return

	has_visual_contact = _can_see_player()
	if player.has_method("set_vision_contact"):
		player.call("set_vision_contact", self, has_visual_contact)
	var visibility_multiplier : float = _get_player_visibility_multiplier()

	if has_visual_contact:
		last_known_player_position = player.global_position
		time_without_visual_contact = 0.0

		if not has_detected_player:
			detection_progress = minf(
				detection_progress + delta * visibility_multiplier,
				detection_time
			)

			if detection_progress >= detection_time:
				has_detected_player = true
	else:
		detection_progress = maxf(detection_progress - delta, 0.0)
		time_without_visual_contact += delta

		if (
			has_detected_player
			and time_without_visual_contact >= lose_sight_after
		):
			has_detected_player = false
			current_state = State.WANDERING
			velocity = Vector3.ZERO

	if not has_detected_player:
		return

	var player_distance : float = global_position.distance_to(
		player.global_position
	)

	if has_visual_contact and player_distance <= shoot_distance:
		current_state = State.SHOOTING
	else:
		current_state = State.CHASING


func _can_see_player() -> bool:
	if player == null:
		return false

	var direction : Vector3 = (
		player.global_position
		- global_position
	)

	direction.y = 0.0

	var distance : float = direction.length()
	if distance <= close_perception_radius:
		return _has_clear_line_of_sight()

	var effective_sight_distance : float = (
		sight_distance * _get_player_visibility_multiplier()
	)

	if distance > effective_sight_distance:
		return false


	if distance < 0.01:
		return true


	direction = direction.normalized()

	var forward : Vector3 = get_vision_forward()

	var dot_product : float = clampf(
		forward.dot(direction),
		-1.0,
		1.0
	)

	var angle : float = rad_to_deg(
		acos(dot_product)
	)

	if angle > sight_angle:
		return false

	return _has_clear_line_of_sight()


func _has_clear_line_of_sight() -> bool:
	if player == null or get_world_3d() == null:
		return false

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

# --------------------------------------------------
# CLOSE DISTANCE
# --------------------------------------------------

func close_distance() -> void:
	aim_progress = 0.0

	if player == null:
		return

	var distance : float = (
		global_position.distance_to(player.global_position)
	)

	if distance <= shoot_distance and has_visual_contact:

		velocity = Vector3.ZERO

		current_state = State.SHOOTING

		return


	navigation_agent.target_position = last_known_player_position


	if navigation_agent.is_navigation_finished():

		velocity = Vector3.ZERO

		return


	var next_position : Vector3 = (
		navigation_agent.get_next_path_position()
	)

	var direction : Vector3 = (
		next_position - global_position
	)

	direction.y = 0.0


	if direction.length_squared() < 0.01:

		velocity = Vector3.ZERO

		return


	direction = direction.normalized()

	velocity = direction * chase_speed

	move_and_slide()

	face_direction(direction)
# --------------------------------------------------
# SHOOT
# --------------------------------------------------

func shoot(delta : float) -> void:

	if player == null:
		return

	var direction : Vector3 = (
		player.global_position
		- global_position
	)

	direction.y = 0.0

	var distance : float = direction.length()

	if distance > shoot_distance or not has_visual_contact:

		aim_progress = 0.0
		current_state = State.CHASING

		return


	velocity = Vector3.ZERO


	if direction.length_squared() > 0.01:

		face_direction(
			direction.normalized()
		)

	aim_progress = minf(
		aim_progress + delta,
		maxf(aim_stabilization_time, 0.0)
	)

	if aim_progress < aim_stabilization_time:
		return

	if shoot_timer > 0.0:
		return


	_perform_shot()


func _perform_shot() -> void:
	if player == null or not _is_player_alive():
		return

	shoot_timer = maxf(seconds_between_shots, 0.1)
	aim_progress = 0.0
	gunshot_audio.call("play_shot")
	muzzle_flash.visible = true
	muzzle_flash_timer.start(maxf(muzzle_flash_duration, 0.01))

	var shot_origin : Vector3 = muzzle.global_position
	var target_position : Vector3 = (
		player.global_position + Vector3.UP * player_target_height
	)
	var distance : float = shot_origin.distance_to(target_position)
	var accuracy : float = _calculate_shot_accuracy(distance)
	var spread_degrees : float = _calculate_shot_spread(distance)
	var intends_to_hit : bool = randf() <= accuracy
	var shot_direction : Vector3 = _get_shot_direction(
		shot_origin,
		target_position,
		spread_degrees,
		intends_to_hit
	)
	var shot_end : Vector3 = (
		shot_origin + shot_direction * maxf(shoot_distance, sight_distance)
	)
	var query := PhysicsRayQueryParameters3D.create(shot_origin, shot_end)
	query.exclude = [get_rid()]
	query.collide_with_areas = false

	var hit : Dictionary = (
		get_world_3d().direct_space_state.intersect_ray(query)
	)
	var collider : Object = hit.get("collider") as Object
	var hit_player : bool = _is_player_collider(collider)

	if hit_player and player.has_method("take_damage"):
		consecutive_hits += 1
		player.call(
			"take_damage",
			shoot_damage,
			shot_direction,
			shot_knockback_distance
		)
	else:
		consecutive_hits = 0


func _calculate_shot_accuracy(distance : float) -> float:
	var distance_ratio : float = clampf(
		distance / maxf(shoot_distance, 0.01),
		0.0,
		1.0
	)
	var accuracy : float = lerpf(
		maximum_shot_accuracy,
		minimum_shot_accuracy,
		distance_ratio
	)
	var motion_ratio : float = clampf(
		Vector2(player.velocity.x, player.velocity.z).length() / 6.0,
		0.0,
		1.0
	)
	var visibility_multiplier : float = _get_player_visibility_multiplier()
	accuracy -= motion_ratio * movement_accuracy_penalty
	accuracy -= (
		(1.0 - visibility_multiplier)
		* concealment_accuracy_penalty
	)

	if (
		consecutive_hit_mercy_threshold > 0
		and consecutive_hits >= consecutive_hit_mercy_threshold
	):
		accuracy -= mercy_accuracy_penalty

	return clampf(accuracy, 0.05, maximum_shot_accuracy)


func _calculate_shot_spread(distance : float) -> float:
	var distance_ratio : float = clampf(
		distance / maxf(shoot_distance, 0.01),
		0.0,
		1.0
	)
	var motion_ratio : float = clampf(
		Vector2(player.velocity.x, player.velocity.z).length() / 6.0,
		0.0,
		1.0
	)
	var visibility_multiplier : float = _get_player_visibility_multiplier()
	var spread : float = lerpf(
		close_spread_degrees,
		far_spread_degrees,
		distance_ratio
	)
	spread += motion_ratio * movement_spread_bonus_degrees
	spread += (
		(1.0 - visibility_multiplier)
		* concealment_spread_bonus_degrees
	)

	if (
		consecutive_hit_mercy_threshold > 0
		and consecutive_hits >= consecutive_hit_mercy_threshold
	):
		spread += mercy_spread_bonus_degrees

	return maxf(spread, 0.0)


func _get_shot_direction(
	shot_origin : Vector3,
	target_position : Vector3,
	spread_degrees : float,
	intends_to_hit : bool
) -> Vector3:
	var aim_direction : Vector3 = (
		target_position - shot_origin
	).normalized()

	if intends_to_hit:
		return _get_confirmed_hit_direction(shot_origin, target_position)

	var distance : float = shot_origin.distance_to(target_position)
	var clearance_degrees : float = minf(
		rad_to_deg(atan2(miss_target_radius, maxf(distance, 0.01))),
		10.0
	)
	var miss_angle_degrees : float = (
		clearance_degrees
		+ randf_range(spread_degrees * 0.35, spread_degrees)
	)
	var miss_side : float = -1.0 if randf() < 0.5 else 1.0
	var missed_direction : Vector3 = aim_direction.rotated(
		Vector3.UP,
		deg_to_rad(miss_angle_degrees * miss_side)
	)
	var pitch_axis : Vector3 = missed_direction.cross(Vector3.UP)

	if pitch_axis.length_squared() > 0.001:
		missed_direction = missed_direction.rotated(
			pitch_axis.normalized(),
			deg_to_rad(randf_range(-spread_degrees, spread_degrees) * 0.2)
		)

	return missed_direction.normalized()


func _get_confirmed_hit_direction(
	shot_origin : Vector3,
	target_position : Vector3
) -> Vector3:
	var disk_angle : float = randf_range(0.0, TAU)
	var disk_radius : float = sqrt(randf()) * maxf(confirmed_hit_radius, 0.0)
	var aim_point : Vector3 = target_position + Vector3(
		cos(disk_angle) * disk_radius,
		randf_range(
			-maxf(confirmed_hit_height_variation, 0.0),
			maxf(confirmed_hit_height_variation, 0.0)
		),
		sin(disk_angle) * disk_radius
	)
	return (aim_point - shot_origin).normalized()


func _is_player_collider(collider : Object) -> bool:
	if collider == null or player == null:
		return false

	if collider == player:
		return true

	return (
		collider is Node
		and player.is_ancestor_of(collider as Node)
	)


func _hide_muzzle_flash() -> void:
	muzzle_flash.visible = false


# --------------------------------------------------
# ROTATION
# --------------------------------------------------

func face_direction(direction : Vector3) -> void:

	if direction.length_squared() < 0.001:
		return

	var target_angle : float = atan2(
		direction.x,
		direction.z
	)

	rotation.y = lerp_angle(
		rotation.y,
		target_angle,
		get_physics_process_delta_time()
		* rotation_speed
	)
	
func update_head_look(delta : float) -> void:

	if player == null:
		return

	if current_state == State.CHASING or current_state == State.SHOOTING:
		var look_position : Vector3 = player.global_position

		if current_state == State.CHASING and not has_visual_contact:
			look_position = last_known_player_position

		target_marker.global_position = target_marker.global_position.lerp(
			look_position,
			delta * look_speed
		)

		return


	look_random_timer -= delta

	if look_random_timer <= 0.0:

		look_random_timer = randf_range(
			look_random_interval * 0.5,
			look_random_interval * 1.5
		)

		var side : float = randf_range(-1.0, 1.0)

		var forward : Vector3 = global_transform.basis.z
		var right : Vector3 = global_transform.basis.x

		forward.y = 0.0
		right.y = 0.0

		forward = forward.normalized()
		right = right.normalized()

		random_look_target = (
			global_position
			+ forward * look_random_distance
			+ right * side * look_random_distance
		)

		random_look_target.y = (
			global_position.y
			+ look_random_height
		)

	target_marker.global_position = target_marker.global_position.lerp(
		random_look_target,
		delta * look_speed
	)
