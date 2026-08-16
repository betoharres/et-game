extends RigidBody3D

@onready var target: Marker3D = $AimTargetArm/AimTarget
@onready var propeller: MeshInstance3D = (
	$SM_Veh_Plane_Stunt_01/SM_Veh_Plane_Stunt_01/SM_Veh_Plane_Stunt_01_Prop
)

@export_category("Engine")
@export_range(0.0, 50000.0, 100.0, "or_greater") var engine_force: float = 12000.0
@export_range(1.0, 200.0, 1.0, "or_greater") var top_speed: float = 55.0
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


func _ready() -> void:
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_weight = mass * gravity

	if target == null:
		push_error("FlyablePlane: AimTarget not found.")


func _physics_process(delta: float) -> void:
	_apply_engine_and_drag()
	_apply_lift()

	if target != null:
		_apply_aim_assist()

	if propeller != null:
		propeller.rotate_z(propeller_speed * delta)


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

	apply_central_force(forward * (engine_force + forward_drag_force))
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
