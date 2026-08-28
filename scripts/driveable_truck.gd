extends VehicleBody3D

@export var brake_force : float = 25.0
@export var max_steering : float = 0.5
@export var steering_speed : float = 5.0
@export var max_engine_force : float = 500.0

# Vehicle interaction
@export var enter_distance : float = 2.5

@onready var front_left_wheel : VehicleWheel3D = $FrontLeftWheel
@onready var front_right_wheel : VehicleWheel3D = $FrontRightWheel
@onready var rear_left_wheel : VehicleWheel3D = $RearLeftWheel
@onready var rear_right_wheel : VehicleWheel3D = $RearRightWheel

@onready var steering_wheel_pivot : MeshInstance3D = $IKContainer/SteeringWheelPivot/SteeringWheel

# Camera
@onready var camera_arm : Node3D = $CameraArm
@onready var camera : Camera3D = $CameraArm/Camera3D

@export var interior_camera_offset : Vector3 = Vector3(0.43, 1.55, 0.95)

@export var sensitivity : float = 0.003
@export var camera_pitch_min : float = -80.0
@export var camera_pitch_max : float = 80.0

# Camera collision (keeps the chase camera from clipping through terrain/props)
@export var camera_collision_mask : int = 1
@export var camera_collision_margin : float = 0.3
@export var camera_collision_follow_speed : float = 12.0

# Pivot height above the vehicle origin. The origin sits at ground level, so
# tracing from there makes the ray graze the terrain and collapse the camera
# into the chassis (black frames).
@export var camera_pivot_height : float = 1.6

# The camera is never pulled closer than this, so it can never end up inside
# the truck mesh.
@export var camera_min_distance : float = 1.5

# Camera auto-return (snaps the chase camera back behind the vehicle when the
# player stops looking around, GTA-style)
@export var camera_return_delay : float = 1.2
@export var camera_return_speed : float = 3.0

var camera_yaw : float = 0.0
var camera_pitch : float = 0.0
var camera_distance : float = 0.0
var time_since_camera_input : float = 0.0

var vehicle_controlled : bool = false
var current_player : CharacterBody3D = null
var player_camera : Camera3D = null
var exterior_camera_position : Vector3
var exterior_camera_rotation : Vector3
var first_person_camera : bool = false

# Driver ET reference
@onready var ET_driver : Node3D = $ET2

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	camera_yaw = global_rotation.y
	camera_pitch = camera_arm.rotation.x

	# The arm is a child of the vehicle body: without top_level the chassis
	# roll/pitch keeps dragging the camera around between physics ticks.
	camera_arm.top_level = true

	exterior_camera_position = camera.position
	exterior_camera_rotation = camera.rotation
	camera_distance = exterior_camera_position.length()
	camera.current = false


func _input(event : InputEvent) -> void:

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G or event.physical_keycode == KEY_G:
			if vehicle_controlled:
				set_first_person_camera(!first_person_camera)
			return

	if event.is_action_pressed("interact"):
		if vehicle_controlled:
			exit_vehicle()
		else:
			try_enter_vehicle()

	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if not vehicle_controlled:
				return

			var mouse_motion : Vector2 = event.relative

			camera_yaw -= mouse_motion.x * sensitivity
			camera_pitch -= mouse_motion.y * sensitivity
			time_since_camera_input = 0.0

			var minimum_pitch : float = deg_to_rad(camera_pitch_min)
			var maximum_pitch : float = deg_to_rad(camera_pitch_max)

			camera_pitch = clampf(
				camera_pitch,
				minimum_pitch,
				maximum_pitch
			)

func _physics_process(delta : float) -> void:

	time_since_camera_input += delta

	if (
		vehicle_controlled
		and not first_person_camera
		and time_since_camera_input > camera_return_delay
	):
		camera_yaw = lerp_angle(
			camera_yaw,
			global_rotation.y,
			delta * camera_return_speed
		)

	# Camera follows vehicle position,
	# but not vehicle rotation.

	var camera_position : Vector3 = global_position

	if vehicle_controlled and first_person_camera:
		camera_position += global_transform.basis * interior_camera_offset
	else:
		camera_position += Vector3.UP * camera_pivot_height

	camera_arm.global_position = camera_position

	camera_arm.global_rotation = Vector3(
		camera_pitch,
		camera_yaw,
		0.0
	)

	if vehicle_controlled and not first_person_camera:
		_update_exterior_camera_collision(delta)

	_update_driving(delta)


func _update_exterior_camera_collision(delta : float) -> void:
	var desired_local_position : Vector3 = exterior_camera_position
	var desired_world_position : Vector3 = camera_arm.global_transform * (
		desired_local_position
	)

	var space_state : PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query : PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		camera_arm.global_position,
		desired_world_position
	)
	query.collision_mask = camera_collision_mask
	query.collide_with_areas = false

	var excluded : Array[RID] = [get_rid()]

	# The hidden driver still has a collider sitting next to the truck; without
	# this the ray hits it and slams the camera into the chassis.
	if current_player != null:
		excluded.append(current_player.get_rid())

	query.exclude = excluded

	var result : Dictionary = space_state.intersect_ray(query)

	var allowed_distance : float = camera_distance
	var minimum_distance : float = minf(camera_min_distance, camera_distance)

	if not result.is_empty():
		var hit_distance : float = camera_arm.global_position.distance_to(
			result.position
		)
		allowed_distance = clampf(
			hit_distance - camera_collision_margin,
			minf(camera_min_distance, camera_distance),
			camera_distance
		)

	var current_distance : float = camera.position.length()
	var new_distance : float

	if allowed_distance < current_distance:
		# Pull in immediately so the camera never clips through geometry.
		new_distance = allowed_distance
	else:
		# Ease back out smoothly once the obstruction is gone.
		new_distance = move_toward(
			current_distance,
			allowed_distance,
			delta * camera_collision_follow_speed * camera_distance
		)

	var direction : Vector3 = (
		desired_local_position / camera_distance
		if camera_distance > 0.0
		else Vector3.ZERO
	)

	camera.position = direction * maxf(new_distance, minimum_distance)
	camera.rotation = exterior_camera_rotation


func _update_driving(delta : float) -> void:
	if not vehicle_controlled:
		engine_force = 0.0
		brake = brake_force
		return

	var throttle : float = Input.get_axis(
		"ui_down",
		"ui_up"
	)

	var steering_input : float = Input.get_axis(
		"ui_right",
		"ui_left"
	)

	engine_force = throttle * max_engine_force

	var target_steering : float = steering_input * max_steering

	front_left_wheel.steering = lerp(
		front_left_wheel.steering,
		target_steering,
		delta * steering_speed
	)

	front_right_wheel.steering = lerp(
		front_right_wheel.steering,
		target_steering,
		delta * steering_speed
	)

	# Steering wheel turning
	var steering_wheel_angle : float = deg_to_rad(30.0)
	var target_wheel_rotation : float = steering_input * -steering_wheel_angle
	
	steering_wheel_pivot.rotation.z = lerp(
		steering_wheel_pivot.rotation.z,
		target_wheel_rotation,
		delta * steering_speed
	)
	
	
func try_enter_vehicle() -> void:
	var characters : Array[Node] = get_tree().get_nodes_in_group("characters")

	var closest_player : CharacterBody3D = null
	var closest_distance : float = enter_distance

	for character in characters:
		if not character is CharacterBody3D:
			continue

		var distance : float = global_position.distance_to(
			character.global_position
		)

		if distance < closest_distance:
			closest_distance = distance
			closest_player = character

	if closest_player == null:
		return


	enter_vehicle(closest_player)


func enter_vehicle(player : CharacterBody3D) -> void:
	current_player = player
	vehicle_controlled = true

	player.set_physics_process(false)
	player.set_process_input(false)

	player.visible = false
	ET_driver.visible = true
	self.freeze = false

	player_camera = find_player_camera(player)

	if player_camera != null:
		player_camera.current = false

	camera.current = true

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func exit_vehicle() -> void:
	if current_player == null:
		return

	vehicle_controlled = false
	first_person_camera = false

	engine_force = 0.0
	brake = brake_force

	current_player.global_position = global_position + (
		global_transform.basis.x * 2.0
	)

	current_player.visible = true
	ET_driver.visible = false
	self.freeze = true

	current_player.set_physics_process(true)
	current_player.set_process_input(true)

	if player_camera != null:
		player_camera.current = true

	set_first_person_camera(false)
	camera.current = false

	current_player = null
	player_camera = null


func set_first_person_camera(enabled : bool) -> void:
	first_person_camera = enabled

	if first_person_camera:
		# Keep the camera node at the driver's head and look through the windshield.
		camera.position = Vector3.ZERO
		camera.rotation = Vector3(0.0, PI, 0.0)
	else:
		# Restore the original third-person camera reference.
		camera.position = exterior_camera_position
		camera.rotation = exterior_camera_rotation


func find_player_camera(player : Node) -> Camera3D:
	var cameras : Array[Node] = player.find_children(
		"*",
		"Camera3D",
		true,
		false
	)

	if cameras.is_empty():
		return null

	return cameras[0] as Camera3D
