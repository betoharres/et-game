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

var camera_yaw : float = 0.0
var camera_pitch : float = 0.0

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

	exterior_camera_position = camera.position
	exterior_camera_rotation = camera.rotation
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

			var minimum_pitch : float = deg_to_rad(camera_pitch_min)
			var maximum_pitch : float = deg_to_rad(camera_pitch_max)

			camera_pitch = clampf(
				camera_pitch,
				minimum_pitch,
				maximum_pitch
			)

func _physics_process(delta : float) -> void:

	# Camera follows vehicle position,
	# but not vehicle rotation.

	var camera_position : Vector3 = global_position
	if vehicle_controlled and first_person_camera:
		camera_position += global_transform.basis * interior_camera_offset

	camera_arm.global_position = camera_position

	camera_arm.global_rotation = Vector3(
		camera_pitch,
		camera_yaw,
		0.0
	)

	camera_arm.rotation.x = camera_pitch


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
