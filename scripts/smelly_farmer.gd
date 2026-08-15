extends CharacterBody3D

# Navigation

@onready var navigation_agent : NavigationAgent3D = $NavigationAgent3D

@export var walk_speed : float = 2.0
@export var chase_speed : float = 3.0
@export var rotation_speed : float = 2.0

@export var wander_distance : float = 8.0
@export var wander_wait_time : float = 2.0

var has_wander_target : bool = false

# Vision

@export var sight_distance : float = 12.0
@export var sight_angle : float = 60.0

var player : CharacterBody3D = null

# Shooting

@export var shoot_distance : float = 8.0
@export var shoot_cooldown : float = 2.0

var shoot_timer : float = 0.0

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
	
func _physics_process(delta : float) -> void:

	if player == null:
		return

	shoot_timer -= delta

	check_sight()

	match current_state:

		State.WANDERING:
			random_walk(delta)

		State.CHASING:
			close_distance()

		State.SHOOTING:
			shoot()

	update_head_look(delta)

# --------------------------------------------------
# RANDOM WALK
# --------------------------------------------------

func random_walk(delta : float) -> void:

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

		var random_distance : float = randf_range(
			2.0,
			wander_distance
		)

		var random_position : Vector3 = (
			global_position
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
# CHECK SIGHT
# --------------------------------------------------

func check_sight() -> void:

	if player == null:
		return

	var direction : Vector3 = (
		player.global_position
		- global_position
	)

	direction.y = 0.0

	var distance : float = direction.length()

	if distance > sight_distance:

		if current_state != State.WANDERING:
			current_state = State.WANDERING

		return


	if distance < 0.01:
		return


	direction = direction.normalized()

	var forward : Vector3 = global_transform.basis.z

	forward.y = 0.0
	forward = forward.normalized()

	var dot_product : float = clampf(
		forward.dot(direction),
		-1.0,
		1.0
	)

	var angle : float = rad_to_deg(
		acos(dot_product)
	)

	if angle <= sight_angle:

		if distance <= shoot_distance:
			current_state = State.SHOOTING
		else:
			current_state = State.CHASING

# --------------------------------------------------
# CLOSE DISTANCE
# --------------------------------------------------

func close_distance() -> void:

	if player == null:
		return

	var distance : float = (
		global_position.distance_to(player.global_position)
	)

	if distance <= shoot_distance:

		velocity = Vector3.ZERO

		current_state = State.SHOOTING

		return


	navigation_agent.target_position = player.global_position


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

func shoot() -> void:

	if player == null:
		return

	var direction : Vector3 = (
		player.global_position
		- global_position
	)

	direction.y = 0.0

	var distance : float = direction.length()

	if distance > shoot_distance:

		current_state = State.CHASING

		return


	velocity = Vector3.ZERO


	if direction.length_squared() > 0.01:

		face_direction(
			direction.normalized()
		)


	if shoot_timer > 0.0:
		return


	shoot_timer = shoot_cooldown

	print("SMELLY FARMER SHOOTS PLAYER")


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

		target_marker.global_position = target_marker.global_position.lerp(
			player.global_position,
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
