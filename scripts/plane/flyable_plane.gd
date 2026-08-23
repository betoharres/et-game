extends RigidBody3D

@onready var target: Marker3D = $AimTargetArm/AimTarget
@onready var target_arm: Node3D = $AimTargetArm
@onready var camera: Camera3D = $CameraArm/Camera3D
@onready var entry_point: Marker3D = $EntryPoint
@onready var exit_point: Marker3D = $ExitPoint
@onready var propeller: MeshInstance3D = (
	$SM_Veh_Plane_Stunt_01/SM_Veh_Plane_Stunt_01/SM_Veh_Plane_Stunt_01_Prop
)

@export_category("Interaction")
@export_range(0.5, 10.0, 0.1, "or_greater") var enter_distance: float = 4.0
## Keeps Run Current Scene useful while making an integrated plane wait for a player.
@export var standalone_control_if_no_player: bool = true
@export var freeze_when_unoccupied: bool = true

@export_category("Engine")
@export_range(0.0, 50000.0, 100.0, "or_greater") var engine_force: float = 12000.0
@export_range(1.0, 200.0, 1.0, "or_greater") var top_speed: float = 35.0
@export_range(0.0, 200.0, 1.0, "or_greater") var propeller_speed: float = 55.0

@export_category("Aerodynamics")
## Lift at top speed, expressed as a multiple of the plane's weight.
@export_range(0.0, 3.0, 0.05, "or_greater") var lift_at_top_speed: float = 1.05
## Linear drag that removes sideways sliding without making the plane feel on rails.
@export_range(0.0, 5000.0, 10.0, "or_greater") var lateral_drag: float = 900.0
## Vertical drag softens abrupt climbs and dives.
@export_range(0.0, 5000.0, 10.0, "or_greater") var vertical_drag: float = 250.0
@export_range(1.0, 5.0, 0.1, "or_greater") var max_lift_in_g: float = 2.0

@export_category("Aim Assist")
@export_range(1.0, 89.0, 1.0) var max_pitch_error: float = 55.0
@export_range(0.0, 80.0, 1.0) var max_bank_angle: float = 50.0
## How much aim error becomes banking. One radian of yaw error produces this many radians of bank.
@export_range(0.0, 2.0, 0.05) var turn_bank_gain: float = 0.9
@export_range(0.0, 10.0, 0.1) var aim_deadzone_degrees: float = 1.5
@export_range(0.0, 1.0, 0.05) var minimum_control_authority: float = 0.35

@export_category("Control Response")
@export_range(0.0, 100000.0, 100.0, "or_greater") var pitch_strength: float = 16000.0
@export_range(0.0, 20000.0, 100.0, "or_greater") var pitch_damping: float = 4500.0
@export_range(0.0, 100000.0, 100.0, "or_greater") var yaw_strength: float = 9000.0
@export_range(0.0, 20000.0, 100.0, "or_greater") var yaw_damping: float = 3000.0
@export_range(0.0, 100000.0, 100.0, "or_greater") var roll_strength: float = 24000.0
@export_range(0.0, 20000.0, 100.0, "or_greater") var roll_damping: float = 6000.0

var _weight: float = 0.0
var plane_controlled: bool = false
var current_player: CharacterBody3D = null
var player_camera: Camera3D = null
var _player_was_visible: bool = true
var _player_was_physics_processing: bool = true
var _player_was_input_processing: bool = true
var _player_camera_was_current: bool = false
var _player_collision_layer: int = 0
var _player_collision_mask: int = 0
var current_engine_force: float = 0.0
var throttle: float = 1200.0

func _ready() -> void:
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_weight = mass * gravity
	camera.current = false
	freeze = freeze_when_unoccupied
	_set_aim_control_enabled(false, false)

	if target == null:
		push_error("FlyablePlane: AimTarget not found.")

	call_deferred("_enable_standalone_control_if_needed")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("move_forward"):
		current_engine_force += throttle
		current_engine_force = clampf(current_engine_force, 0.0, engine_force)
	elif event.is_action_pressed("move_backward"):
		current_engine_force -= throttle
		current_engine_force = clampf(current_engine_force, 0.0, engine_force)
	
	if not event.is_action_pressed("interact") or event.is_echo():
		return

	if current_player != null:
		leave_plane()
	elif not plane_controlled:
		try_take_control()


	
	
func _physics_process(delta: float) -> void:
	if not plane_controlled:
		return

	_apply_engine_and_drag()
	_apply_lift()

	if target != null:
		_apply_aim_assist()

	if propeller != null:
		propeller.rotate_z(propeller_speed * delta)


func try_take_control() -> void:
	if plane_controlled:
		return

	var closest_player: CharacterBody3D = null
	var closest_distance: float = enter_distance

	for character: Node in get_tree().get_nodes_in_group("characters"):
		if not character is CharacterBody3D:
			continue

		var player: CharacterBody3D = character as CharacterBody3D
		if not player.visible or not player.is_physics_processing():
			continue
		var distance: float = entry_point.global_position.distance_to(
			player.global_position
		)
		if distance < closest_distance:
			closest_distance = distance
			closest_player = player

	if closest_player != null:
		take_control(closest_player)


func take_control(player: CharacterBody3D) -> void:
	if player == null or plane_controlled:
		return

	current_player = player
	plane_controlled = true
	_player_was_visible = player.visible
	_player_was_physics_processing = player.is_physics_processing()
	_player_was_input_processing = player.is_processing_input()
	_player_collision_layer = player.collision_layer
	_player_collision_mask = player.collision_mask

	player_camera = _find_player_camera(player)
	if player_camera != null:
		_player_camera_was_current = player_camera.current
		player_camera.current = false

	player.set_physics_process(false)
	player.set_process_input(false)
	player.visible = false
	player.collision_layer = 0
	player.collision_mask = 0
	player.velocity = Vector3.ZERO

	freeze = false
	camera.current = true
	_set_aim_control_enabled(true, true)
	_apply_fog_profile(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func leave_plane() -> void:
	if current_player == null:
		return

	var departing_player: CharacterBody3D = current_player
	plane_controlled = false
	_set_aim_control_enabled(false, false)
	camera.current = false
	_apply_fog_profile(false)
	freeze = freeze_when_unoccupied

	departing_player.global_position = exit_point.global_position
	departing_player.velocity = Vector3.ZERO
	departing_player.collision_layer = _player_collision_layer
	departing_player.collision_mask = _player_collision_mask
	departing_player.visible = _player_was_visible
	departing_player.set_physics_process(_player_was_physics_processing)
	departing_player.set_process_input(_player_was_input_processing)

	if player_camera != null:
		player_camera.current = _player_camera_was_current

	current_player = null
	player_camera = null


func _find_player_camera(player: Node) -> Camera3D:
	var cameras: Array[Node] = player.find_children(
		"*",
		"Camera3D",
		true,
		false
	)
	if cameras.is_empty():
		return null
	return cameras[0] as Camera3D


func _set_aim_control_enabled(enabled: bool, align_with_plane: bool) -> void:
	if target_arm.has_method("set_control_enabled"):
		target_arm.call("set_control_enabled", enabled, align_with_plane)


func _enable_standalone_control_if_needed() -> void:
	if plane_controlled or not standalone_control_if_no_player:
		return
	if not get_tree().get_nodes_in_group("characters").is_empty():
		return

	plane_controlled = true
	freeze = false
	camera.current = true
	_set_aim_control_enabled(true, true)
	_apply_fog_profile(true)


## Do ar a nevoa de 400 m fecharia antes de qualquer referencia no chao, entao
## o NightEnvironment troca para o perfil de voo enquanto o aviao e pilotado.
## E so alcance de nevoa: nao entra geometria nem impostor nenhum.
func _apply_fog_profile(flying: bool) -> void:
	for node: Node in get_tree().get_nodes_in_group("night_environment"):
		if node.has_method("set_fog_profile"):
			node.call("set_fog_profile", 1 if flying else 0)


func _apply_engine_and_drag() -> void:
	var forward: Vector3 = -global_basis.z
	var right: Vector3 = global_basis.x
	var up: Vector3 = global_basis.y

	# Quadratic forward drag balances the engine at top_speed. This gives the
	# aircraft a terminal speed without abruptly clamping its velocity.
	var safe_top_speed: float = maxf(top_speed, 0.1)
	var forward_speed: float = linear_velocity.dot(forward)
	var forward_drag_coefficient: float = engine_force / (safe_top_speed * safe_top_speed)
	var forward_drag_force: float = (
		-forward_speed * absf(forward_speed) * forward_drag_coefficient
	)

	var sideways_speed: float = linear_velocity.dot(right)
	var upward_speed: float = linear_velocity.dot(up)

	apply_central_force(forward * (current_engine_force + forward_drag_force))
	apply_central_force(-right * sideways_speed * lateral_drag)
	apply_central_force(-up * upward_speed * vertical_drag)


func _apply_lift() -> void:
	var forward: Vector3 = -global_basis.z
	var up: Vector3 = global_basis.y
	var forward_speed: float = maxf(linear_velocity.dot(forward), 0.0)
	var speed_ratio: float = forward_speed / maxf(top_speed, 0.1)
	var lift_force: float = _weight * lift_at_top_speed * speed_ratio * speed_ratio

	# A cap keeps collisions or steep dives from producing explosive lift.
	lift_force = minf(lift_force, _weight * max_lift_in_g)
	apply_central_force(up * lift_force)


func _apply_aim_assist() -> void:
	var to_target: Vector3 = target.global_position - global_position
	if to_target.length_squared() < 0.001:
		return

	var target_direction: Vector3 = to_target.normalized()
	var forward: Vector3 = -global_basis.z
	var right: Vector3 = global_basis.x
	var up: Vector3 = global_basis.y

	var pitch_error: float = atan2(
		target_direction.dot(up),
		target_direction.dot(forward)
	)
	var yaw_error: float = atan2(
		target_direction.dot(right),
		target_direction.dot(forward)
	)

	pitch_error = clampf(
		pitch_error,
		-deg_to_rad(max_pitch_error),
		deg_to_rad(max_pitch_error)
	)

	var deadzone: float = deg_to_rad(aim_deadzone_degrees)
	if absf(pitch_error) < deadzone:
		pitch_error = 0.0
	if absf(yaw_error) < deadzone:
		yaw_error = 0.0

	var control_authority: float = clampf(
		absf(linear_velocity.dot(forward)) / maxf(top_speed, 0.1),
		minimum_control_authority,
		1.0
	)

	var pitch_rate: float = angular_velocity.dot(right)
	var yaw_rate: float = angular_velocity.dot(up)
	var pitch_torque: float = pitch_error * pitch_strength - pitch_rate * pitch_damping
	# Positive local yaw error is to the right, which requires rotation around -up.
	var yaw_torque: float = -yaw_error * yaw_strength - yaw_rate * yaw_damping

	var desired_bank: float = clampf(
		yaw_error * turn_bank_gain,
		-deg_to_rad(max_bank_angle),
		deg_to_rad(max_bank_angle)
	)
	var desired_up: Vector3 = _get_level_up(forward).rotated(forward, desired_bank)
	var roll_error: float = up.signed_angle_to(desired_up, forward)
	var roll_rate: float = angular_velocity.dot(forward)
	var roll_torque: float = roll_error * roll_strength - roll_rate * roll_damping

	apply_torque(
		(
			right * pitch_torque
			+ up * yaw_torque
			+ forward * roll_torque
		) * control_authority
	)


func _get_level_up(forward: Vector3) -> Vector3:
	var level_up: Vector3 = Vector3.UP - forward * Vector3.UP.dot(forward)
	if level_up.length_squared() < 0.001:
		# When pointing almost vertically, retain the current wing orientation;
		# there is no stable horizon roll reference at this attitude.
		return global_basis.y
	return level_up.normalized()
