extends CharacterBody3D

signal health_changed(current_health : float, maximum_health : float)
signal stamina_changed(current_stamina : float, maximum_stamina : float)
signal energy_changed(current_energy : float, maximum_energy : float)
signal stealth_alert_changed(alert_level : float)
signal died

const EYE_LIGHT_ENERGY_SOURCE : StringName = &"eye_light"

const STANDING_COLLISION_HEIGHT : float = 1.0
const CROUCHING_COLLISION_HEIGHT : float = 0.62
const FLOOR_PROBE_HEIGHT : float = 1.5
const FLOOR_PROBE_DEPTH : float = 4.0
const WALL_NORMAL_LIMIT : float = 0.7
const NEW_CONTACT_NORMAL_LIMIT : float = 0.7
const MIN_FALL_TIME_SCALE : float = 0.5

enum JumpState {
	READY,
	AIRBORNE,
}

enum FallState {
	NONE,
	FALLEN,
	STANDING_UP,
}

enum ImpactReaction {
	HIT,
	STUMBLE,
	RAGDOLL,
}


@export var speed: float = 3.0
@export var sprint_speed : float = 5.5
@export var crouch_speed : float = 1.6
@export var jump_velocity : float = 5.5
@export var crouch_transition_speed : float = 8.0
@export var crouch_camera_drop : float = 0.3
@export var sensitivity: float = 0.003
@export var rotation_speed: float = 10.0

@export_category("Movement Response")
@export var ground_acceleration : float = 32.0
@export var ground_deceleration : float = 36.0
@export var air_acceleration : float = 18.0
@export_range(70.0, 170.0, 1.0) var stationary_pivot_angle_degrees : float = 100.0
@export_range(90.0, 170.0, 1.0) var reversal_angle_degrees : float = 120.0
@export var reversal_minimum_speed : float = 1.5
@export_range(0.35, 0.75, 0.01) var reversal_commit_ratio : float = 0.55
@export_range(20.0, 80.0, 1.0) var reversal_cancel_angle : float = 50.0

@export_category("Survival")
@export var max_health : float = 100.0
@export var max_stamina : float = 100.0
@export var stamina_drain_per_second : float = 15.0
@export var stamina_recovery_per_second : float = 20.0
@export var stamina_recovery_delay : float = 0.8
@export var sprint_recovery_threshold : float = 20.0
@export var stamina_exhaustion_cooldown : float = 3.0

@export_category("Stealth")
@export_range(0.1, 1.0, 0.05) var stealth : float = 1.0

@export_category("Damage Response")
@export var knockback_speed : float = 3.5

@export_category("Balance")
@export var balance_max : float = 1.0
@export var balance_recovery_speed : float = 0.5
@export_range(0.0, 1.0, 0.01) var stumble_threshold : float = 0.65
@export var min_impact_speed : float = 2.0
@export var impact_balance_multiplier : float = 0.12
@export_range(0.0, 1.0, 0.05) var stumble_control_multiplier : float = 0.35
@export var fall_impact_speed : float = 5.15
@export_range(0.1, 2.0, 0.05) var impact_fall_strength : float = 0.35
@export_range(0.0, 2.0, 0.05) var stumble_push_distance : float = 0.45

@export_category("Landing")
@export var min_landing_speed : float = 5.8
@export var landing_balance_multiplier : float = 0.55
@export var landing_ragdoll_speed : float = 6.7

@export_category("Fall")
@export_range(0.3, 6.0, 0.1) var fall_recovery_delay : float = 1.8
@export_range(0.05, 0.8, 0.05) var ragdoll_pose_blend_duration : float = 0.25
@export_range(0.5, 20.0, 0.5) var fall_follow_speed : float = 8.0

@export_category("Camera")
@export var camera_pitch_min: float = -80.0
@export var camera_pitch_max: float = 80.0
@export_range(-35.0, 35.0, 0.5) var camera_initial_pitch_degrees : float = 10.0

@export_category("Debug Movement")
@export_range(1.0, 10.0, 0.5) var god_mode_speed_multiplier : float = 5.0
@export_range(1.0, 30.0, 0.5) var flight_speed : float = 6.0
@export_range(1.0, 100.0, 1.0) var flight_acceleration : float = 30.0

@export_category("Eye Light")
@export_range(0.0, 2.0, 0.05) var eye_light_energy : float = 0.55
@export_range(0.5, 8.0, 0.1) var eye_light_range : float = 4.0
@export_range(0.1, 3.0, 0.1) var eye_light_turn_on_duration : float = 1.2
@export_range(0.1, 3.0, 0.1) var eye_light_turn_off_duration : float = 1.6
@export_color_no_alpha var active_eye_color : Color = Color(0.2, 0.92, 0.7)
@export_range(0.0, 8.0, 0.05) var eye_glow_energy : float = 1.6
@export_range(0.5, 12.0, 0.1) var eye_glow_range : float = 4.5
@export_range(0.0, 30.0, 0.1) var eye_light_energy_cost_per_second : float = 3.5

@onready var camera_pivot : CinematicCameraRig = $CameraHolder
@onready var footstep_audio : Node = $FootstepAudio
@onready var collision_shape : CollisionShape3D = $CollisionShape3D
@onready var character_visual : Node3D = $ET
@onready var character_mesh : MeshInstance3D = $ET/ETArmature/Skeleton3D/ET
@onready var ragdoll : PlayerRagdoll = $PlayerRagdoll
@onready var ik_target_container : Node = $IKtargetContainer
@onready var animation_controller : PlayerAnimationController = (
	$PlayerAnimationController
)
@onready var eye_area_light : SpotLight3D = (
	$ET/ETArmature/Skeleton3D/EyeLightAttachment/EyeAreaLight
)
@onready var eye_glow_light : OmniLight3D = (
	$ET/ETArmature/Skeleton3D/EyeLightAttachment/EyeGlowLight
)
@onready var energy_pool : EnergyPool = $EnergyPool

var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var is_crouching : bool = false
var _crouch_amount : float = 0.0
var _jump_state : int = JumpState.READY
var _standing_visual_position : Vector3
var health : float = 100.0
var stamina : float = 100.0
var _stamina_recovery_timer : float = 0.0
var _sprint_exhausted : bool = false
var _is_sprinting : bool = false
var _stamina_exhaustion_timer : float = 0.0
var _knockback_direction : Vector3 = Vector3.ZERO
var _knockback_remaining_distance : float = 0.0
var _concealment_sources : Dictionary = {}
var _vision_contacts : Dictionary = {}
var _eye_light_enabled : bool = false
var _eye_light_tween : Tween
var _eye_material : StandardMaterial3D
var _movement_locked : bool = false
var _look_yaw_limit : float = 0.0
var _look_center_yaw : float = 0.0
var _moving_turn_active : bool = false
var _moving_turn_elapsed : float = 0.0
var _moving_turn_duration : float = 0.0
var _moving_turn_start_yaw : float = 0.0
var _moving_turn_target_yaw : float = 0.0
var _moving_turn_target_direction : Vector3 = Vector3.ZERO
var _moving_turn_start_speed : float = 0.0
var _moving_turn_target_speed : float = 0.0
var _moving_turn_rotation_exponent : float = 1.0

# Balance and falling
var _balance : float = 1.0
var _stumble_direction : Vector3 = Vector3.ZERO
var _stumble_strength : float = 0.0
var _last_impact_normal : Vector3 = Vector3.ZERO
var _was_on_wall : bool = false
var _fall_state : int = FallState.NONE
var _fall_timer : float = 0.0
var _fall_target_position : Vector3 = Vector3.ZERO
var _fall_impact_normal : Vector3 = Vector3.ZERO
var _stand_up_elapsed : float = 0.0
var _is_dead : bool = false
var _debug_god_mode_enabled : bool = false
var _debug_flight_enabled : bool = false

# Items
var carried_item : RigidBody3D = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health = max_health
	stamina = max_stamina
	_balance = balance_max

	camera_yaw = global_rotation.y
	camera_pitch = deg_to_rad(camera_initial_pitch_degrees)
	_standing_visual_position = character_visual.position
	_setup_eye_light()
	camera_pivot.set_target_pose(
		global_position,
		camera_yaw,
		camera_pitch,
		0.0,
		0.0,
		true,
		true
	)

	if collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()

	energy_pool.energy_changed.connect(_on_energy_changed)
	energy_pool.depleted.connect(_on_energy_depleted)

	health_changed.emit(health, max_health)
	stamina_changed.emit(stamina, max_stamina)
	energy_changed.emit(
		energy_pool.get_energy(),
		energy_pool.get_max_energy()
	)

func set_movement_locked(locked : bool, yaw_limit_degrees : float = 0.0) -> void:
	_movement_locked = locked
	if locked:
		_cancel_moving_turn()
		_look_center_yaw = camera_yaw
		_look_yaw_limit = deg_to_rad(yaw_limit_degrees)
	else:
		_look_yaw_limit = 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mouse_motion: Vector2 = event.relative

			camera_yaw -= mouse_motion.x * sensitivity
			camera_pitch -= -mouse_motion.y * sensitivity

			var minimum_pitch: float = deg_to_rad(camera_pitch_min)
			var maximum_pitch: float = deg_to_rad(camera_pitch_max)

			camera_pitch = clampf(camera_pitch,minimum_pitch,maximum_pitch)

			if _movement_locked and _look_yaw_limit > 0.0:
				camera_yaw = clampf(
					camera_yaw,
					_look_center_yaw - _look_yaw_limit,
					_look_center_yaw + _look_yaw_limit
				)

	if _movement_locked:
		return

	if event.is_action_pressed("toggle_eye_light") and not event.is_echo():
		set_eye_light_enabled(not _eye_light_enabled)
		return

	# Items
	if event.is_action_pressed("interact"):
		
		if carried_item == null:
			if _is_delivery_interaction_reserved():
				return
			try_pickup()
		else:
			carried_item.drop()
			carried_item = null
			if ik_target_container.has_method("set_carrying"):
				ik_target_container.call("set_carrying", false)

func _physics_process(delta: float) -> void:
	if _fall_state != FallState.NONE:
		_update_fall(delta)

	_update_camera_target()

	if _fall_state != FallState.NONE:
		return
	if _movement_locked:
		# Durante a intro o corpo desce por tween, sem chegar ao chao pela
		# fisica. Reportar "no chao" mantem o ET em idle no feixe em vez de
		# entrar na animacao de queda.
		animation_controller.set_motion_state(
			Vector3.ZERO,
			true,
			false,
			is_crouching,
			JumpState.READY
		)
		return
	if _debug_flight_enabled:
		_update_flight_movement(delta)
		return

	_update_jump_state(delta)
	_update_crouch_state(delta)
	_update_balance(delta)

	var was_on_floor : bool = is_on_floor()

	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	elif velocity.y <= 0.0:
		velocity.y = -0.1

	var input_direction: Vector2 = Input.get_vector("ui_right","ui_left","ui_up","ui_down")

	var camera_forward: Vector3 = Vector3(-sin(camera_yaw),0.0,-cos(camera_yaw))

	var camera_right: Vector3 = Vector3(cos(camera_yaw),0.0,-sin(camera_yaw))

	var movement_direction: Vector3 = (camera_right * input_direction.x +
		camera_forward * input_direction.y)

	movement_direction.y = 0.0
	var has_movement_input : bool = (
		movement_direction.length_squared() > 0.0001
	)
	var wants_to_sprint : bool = (
		has_movement_input
		and Input.is_action_pressed("sprint")
		and not is_crouching
		and is_on_floor()
		and _jump_state == JumpState.READY
	)
	_update_stamina(delta, wants_to_sprint)

	if has_movement_input:
		movement_direction = movement_direction.normalized()

	if _should_start_moving_turn(movement_direction, has_movement_input):
		_start_moving_turn(movement_direction)

	var moving_turn_handled := false
	if _moving_turn_active:
		moving_turn_handled = _update_moving_turn(
			delta,
			movement_direction,
			has_movement_input
		)

	if not moving_turn_handled:
		_update_horizontal_movement(
			delta,
			movement_direction,
			has_movement_input
		)

	_apply_knockback(delta)

	var velocity_before_move : Vector3 = velocity

	move_and_slide()

	_detect_landing(was_on_floor, velocity_before_move)
	_detect_body_impacts(velocity_before_move)

	var horizontal_speed : float = Vector2(velocity.x, velocity.z).length()
	footstep_audio.set_motion(horizontal_speed, is_on_floor())
	_update_animation_controller()


func _update_camera_target() -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	camera_pivot.set_target_pose(
		global_position,
		camera_yaw,
		camera_pitch,
		crouch_camera_drop * _crouch_amount,
		horizontal_speed,
		is_on_floor()
	)


func _get_movement_speed() -> float:
	var base_speed : float = speed

	if is_crouching:
		base_speed = crouch_speed
	elif _is_sprinting:
		base_speed = sprint_speed

	return base_speed * _control_multiplier() * _debug_speed_multiplier()


func _update_horizontal_movement(delta : float, movement_direction : Vector3,
	has_movement_input : bool) -> void:
	var horizontal_velocity := Vector2(velocity.x, velocity.z)

	if has_movement_input:
		var movement_speed := _get_movement_speed()
		var target_velocity := Vector2(
			movement_direction.x,
			movement_direction.z
		) * movement_speed
		var acceleration := ground_acceleration if is_on_floor() else air_acceleration
		horizontal_velocity = horizontal_velocity.move_toward(
			target_velocity,
			acceleration
			* _control_multiplier()
			* _debug_speed_multiplier()
			* delta
		)

		var target_angle := atan2(movement_direction.x, movement_direction.z)
		rotation.y = rotate_toward(
			rotation.y,
			target_angle,
			rotation_speed * _control_multiplier() * delta
		)
	else:
		var deceleration := ground_deceleration if is_on_floor() else air_acceleration
		horizontal_velocity = horizontal_velocity.move_toward(
			Vector2.ZERO,
			deceleration * _debug_speed_multiplier() * delta
		)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y


func _should_start_moving_turn(movement_direction : Vector3,
	has_movement_input : bool) -> bool:
	if (
		_moving_turn_active
		or _debug_god_mode_enabled
		or not has_movement_input
		or not is_on_floor()
		or is_crouching
		or _jump_state != JumpState.READY
		or _stumble_strength > 0.0
	):
		return false

	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	if horizontal_velocity.length() < reversal_minimum_speed:
		var target_yaw := atan2(movement_direction.x, movement_direction.z)
		var facing_angle := absf(wrapf(target_yaw - rotation.y, -PI, PI))
		return facing_angle >= deg_to_rad(stationary_pivot_angle_degrees)

	var desired := Vector2(movement_direction.x, movement_direction.z).normalized()
	var current := horizontal_velocity.normalized()
	var angle := acos(clampf(current.dot(desired), -1.0, 1.0))
	return angle >= deg_to_rad(reversal_angle_degrees)


func _start_moving_turn(movement_direction : Vector3) -> void:
	var current_speed := Vector2(velocity.x, velocity.z).length()
	var is_running := (
		_is_sprinting
		and current_speed >= maxf(speed * 0.85, reversal_minimum_speed)
	)
	var duration := animation_controller.trigger_moving_turn(is_running)
	if duration <= 0.0:
		return

	_moving_turn_active = true
	_moving_turn_elapsed = 0.0
	_moving_turn_duration = duration
	_moving_turn_start_yaw = rotation.y
	_moving_turn_target_direction = movement_direction.normalized()
	_moving_turn_target_yaw = atan2(
		_moving_turn_target_direction.x,
		_moving_turn_target_direction.z
	)
	_moving_turn_start_speed = Vector2(velocity.x, velocity.z).length()
	_moving_turn_target_speed = _get_movement_speed()
	# The walk clip turns slightly ahead of linear time; the run clip plants
	# first and completes most of its rotation in the second half.
	_moving_turn_rotation_exponent = 1.45 if is_running else 0.75


func _update_moving_turn(delta : float, movement_direction : Vector3,
	has_movement_input : bool) -> bool:
	if (
		not has_movement_input
		or not is_on_floor()
		or is_crouching
		or _jump_state != JumpState.READY
	):
		_cancel_moving_turn()
		return false

	var desired := movement_direction.normalized()
	var input_angle := acos(clampf(
		desired.dot(_moving_turn_target_direction),
		-1.0,
		1.0
	))
	if input_angle > deg_to_rad(reversal_cancel_angle):
		_cancel_moving_turn()
		return false

	_moving_turn_elapsed = minf(
		_moving_turn_elapsed + delta,
		_moving_turn_duration
	)
	var ratio := clampf(
		_moving_turn_elapsed / maxf(_moving_turn_duration, 0.001),
		0.0,
		1.0
	)
	var rotation_ratio := pow(ratio, _moving_turn_rotation_exponent)
	rotation.y = lerp_angle(
		_moving_turn_start_yaw,
		_moving_turn_target_yaw,
		rotation_ratio
	)

	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	if ratio < reversal_commit_ratio:
		var braking_duration := maxf(
			_moving_turn_duration * reversal_commit_ratio,
			0.05
		)
		horizontal_velocity = horizontal_velocity.move_toward(
			Vector2.ZERO,
			_moving_turn_start_speed / braking_duration * delta
		)
	else:
		var acceleration_duration := maxf(
			_moving_turn_duration * (1.0 - reversal_commit_ratio),
			0.05
		)
		var target_velocity := Vector2(
			_moving_turn_target_direction.x,
			_moving_turn_target_direction.z
		) * _moving_turn_target_speed
		horizontal_velocity = horizontal_velocity.move_toward(
			target_velocity,
			_moving_turn_target_speed / acceleration_duration * delta
		)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y

	if ratio >= 1.0:
		rotation.y = _moving_turn_target_yaw
		_moving_turn_active = false

	return true


func _cancel_moving_turn() -> void:
	if not _moving_turn_active:
		return
	_moving_turn_active = false
	_moving_turn_elapsed = 0.0
	_moving_turn_duration = 0.0
	animation_controller.cancel_moving_turn()


## How much of the player input still reaches the character. Drops while the ET
## is trying to recover its balance.
func _control_multiplier() -> float:
	return lerpf(1.0, stumble_control_multiplier, _stumble_strength)


func _debug_speed_multiplier() -> float:
	return god_mode_speed_multiplier if _debug_god_mode_enabled else 1.0


func _update_flight_movement(delta : float) -> void:
	var input_direction := Input.get_vector(
		"ui_right",
		"ui_left",
		"ui_up",
		"ui_down"
	)
	var camera_forward := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
	var camera_right := Vector3(cos(camera_yaw), 0.0, -sin(camera_yaw))
	var vertical_input := (
		Input.get_action_strength("jump")
		- Input.get_action_strength("crouch")
	)
	var movement_direction := (
		camera_right * input_direction.x
		+ camera_forward * input_direction.y
		+ Vector3.UP * vertical_input
	)

	if movement_direction.length_squared() > 0.0001:
		movement_direction = movement_direction.normalized()

	var speed_multiplier := _debug_speed_multiplier()
	var target_velocity := movement_direction * flight_speed * speed_multiplier
	velocity = velocity.move_toward(
		target_velocity,
		flight_acceleration * speed_multiplier * delta
	)

	var horizontal_direction := Vector3(
		movement_direction.x,
		0.0,
		movement_direction.z
	)
	if horizontal_direction.length_squared() > 0.0001:
		var target_angle := atan2(
			horizontal_direction.x,
			horizontal_direction.z
		)
		rotation.y = rotate_toward(rotation.y, target_angle, rotation_speed * delta)

	_update_stamina(delta, false)
	move_and_slide()
	footstep_audio.set_motion(0.0, false)
	_jump_state = JumpState.AIRBORNE
	_update_animation_controller()


func _update_jump_state(_delta : float) -> void:
	if _jump_state == JumpState.AIRBORNE and is_on_floor():
		_jump_state = JumpState.READY

	if (
		_jump_state == JumpState.READY
		and is_on_floor()
		and Input.is_action_just_pressed("jump")
	):
		_cancel_moving_turn()
		velocity.y = jump_velocity
		_jump_state = JumpState.AIRBORNE


func _update_stamina(delta : float, wants_to_sprint : bool) -> void:
	var previous_stamina : float = stamina
	if _debug_god_mode_enabled:
		stamina = max_stamina
		_is_sprinting = wants_to_sprint
		_sprint_exhausted = false
		_stamina_recovery_timer = 0.0
		_stamina_exhaustion_timer = 0.0
		if not is_equal_approx(previous_stamina, stamina):
			stamina_changed.emit(stamina, max_stamina)
		return

	_is_sprinting = (
		wants_to_sprint
		and not _sprint_exhausted
		and stamina > 0.0
	)

	if _is_sprinting:
		stamina = maxf(stamina - stamina_drain_per_second * delta, 0.0)
		_stamina_recovery_timer = stamina_recovery_delay

		if stamina <= 0.0:
			_sprint_exhausted = true
			_stamina_exhaustion_timer = stamina_exhaustion_cooldown
			_is_sprinting = false
	else:
		if _sprint_exhausted and _stamina_exhaustion_timer > 0.0:
			_stamina_exhaustion_timer = maxf(
				_stamina_exhaustion_timer - delta,
				0.0
			)
			return

		_stamina_recovery_timer = maxf(
			_stamina_recovery_timer - delta,
			0.0
		)

		if _stamina_recovery_timer <= 0.0:
			stamina = minf(
				stamina + stamina_recovery_per_second * delta,
				max_stamina
			)

	if _sprint_exhausted and stamina >= sprint_recovery_threshold:
		_sprint_exhausted = false

	if not is_equal_approx(previous_stamina, stamina):
		stamina_changed.emit(stamina, max_stamina)


func take_damage(amount : float, hit_direction : Vector3 = Vector3.ZERO,
	push_distance : float = 0.0) -> void:
		
	if _debug_god_mode_enabled or amount <= 0.0 or health <= 0.0:
		return

	var is_fatal : bool = health - amount <= 0.0

	if not is_fatal:
		if push_distance > 0.0:
			apply_knockback(hit_direction, push_distance)
		_trigger_impact_reaction(hit_direction, ImpactReaction.HIT)

	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)

	if health <= 0.0:
		_die(hit_direction)


func apply_knockback(direction : Vector3, distance : float) -> void:
	if _debug_god_mode_enabled or distance <= 0.0 or health <= 0.0:
		return

	direction.y = 0.0

	if direction.length_squared() <= 0.0001:
		return

	_knockback_direction = direction.normalized()
	_knockback_remaining_distance = maxf(
		_knockback_remaining_distance,
		distance
	)


func get_health() -> float:
	return health


func get_max_health() -> float:
	return max_health


func get_stamina() -> float:
	return stamina


func get_max_stamina() -> float:
	return max_stamina


func get_energy() -> float:
	return _get_energy_pool().get_energy()


func get_max_energy() -> float:
	return _get_energy_pool().get_max_energy()


## O HUD é filho do jogador e consulta a reserva antes do [method _ready]
## daqui, quando a variável [member energy_pool] ainda não foi resolvida.
func _get_energy_pool() -> EnergyPool:
	if energy_pool == null:
		energy_pool = $EnergyPool
	return energy_pool


func _on_energy_changed(current : float, maximum : float) -> void:
	energy_changed.emit(current, maximum)


func _on_energy_depleted() -> void:
	if _eye_light_enabled:
		set_eye_light_enabled(false)


func set_debug_god_mode_enabled(enabled : bool) -> void:
	_debug_god_mode_enabled = enabled
	if not enabled:
		return

	var health_changed_value := not is_equal_approx(health, max_health)
	var stamina_changed_value := not is_equal_approx(stamina, max_stamina)
	health = max_health
	stamina = max_stamina
	_sprint_exhausted = false
	_stamina_recovery_timer = 0.0
	_stamina_exhaustion_timer = 0.0
	_balance = balance_max
	_stumble_strength = 0.0
	_knockback_remaining_distance = 0.0
	energy_pool.refill()
	if health_changed_value:
		health_changed.emit(health, max_health)
	if stamina_changed_value:
		stamina_changed.emit(stamina, max_stamina)


func is_debug_god_mode_enabled() -> bool:
	return _debug_god_mode_enabled


func set_debug_flight_enabled(enabled : bool) -> void:
	if _debug_flight_enabled == enabled:
		return

	_debug_flight_enabled = enabled
	_cancel_moving_turn()
	velocity.y = 0.0
	_jump_state = JumpState.AIRBORNE
	motion_mode = (
		CharacterBody3D.MOTION_MODE_FLOATING
		if enabled
		else CharacterBody3D.MOTION_MODE_GROUNDED
	)

	if enabled:
		is_crouching = false
		_crouch_amount = 0.0
		var capsule := collision_shape.shape as CapsuleShape3D
		if capsule != null:
			capsule.height = STANDING_COLLISION_HEIGHT
			collision_shape.position.y = STANDING_COLLISION_HEIGHT * 0.5


func is_debug_flight_enabled() -> bool:
	return _debug_flight_enabled


func is_alive() -> bool:
	return health > 0.0


func set_intervention_signal_pose(active : bool) -> void:
	if ik_target_container.has_method("set_intervention_pose"):
		ik_target_container.call("set_intervention_pose", active)


func set_eye_light_enabled(enabled : bool, immediate : bool = false) -> void:
	if enabled and not energy_pool.can_be_used():
		return

	_eye_light_enabled = enabled
	if enabled:
		energy_pool.set_drain(
			EYE_LIGHT_ENERGY_SOURCE,
			eye_light_energy_cost_per_second
		)
	else:
		energy_pool.clear_drain(EYE_LIGHT_ENERGY_SOURCE)

	if _eye_light_tween != null:
		_eye_light_tween.kill()

	var target_energy : float = eye_light_energy if enabled else 0.0
	var target_glow_energy : float = eye_glow_energy if enabled else 0.0
	var target_albedo := active_eye_color * 0.42 if enabled else Color.BLACK
	target_albedo.a = 1.0
	var target_emission := active_eye_color if enabled else Color.BLACK
	var target_emission_energy : float = 1.35 if enabled else 0.0
	var duration : float = (
		eye_light_turn_on_duration
		if enabled
		else eye_light_turn_off_duration
	)

	if immediate:
		eye_area_light.light_energy = target_energy
		eye_glow_light.light_energy = target_glow_energy
		if _eye_material != null:
			_eye_material.albedo_color = target_albedo
			_eye_material.emission = target_emission
			_eye_material.emission_energy_multiplier = target_emission_energy
		return

	_eye_light_tween = create_tween()
	_eye_light_tween.set_parallel(true)
	_eye_light_tween.set_trans(Tween.TRANS_QUAD)
	_eye_light_tween.set_ease(Tween.EASE_IN_OUT)
	_eye_light_tween.tween_property(
		eye_area_light,
		"light_energy",
		target_energy,
		duration
	)
	_eye_light_tween.tween_property(
		eye_glow_light,
		"light_energy",
		target_glow_energy,
		duration
	)
	if _eye_material != null:
		_eye_light_tween.tween_property(
			_eye_material,
			"albedo_color",
			target_albedo,
			duration
		)
		_eye_light_tween.tween_property(
			_eye_material,
			"emission",
			target_emission,
			duration
		)
		_eye_light_tween.tween_property(
			_eye_material,
			"emission_energy_multiplier",
			target_emission_energy,
			duration
		)


func is_eye_light_enabled() -> bool:
	return _eye_light_enabled


func _setup_eye_light() -> void:
	eye_area_light.spot_range = eye_light_range
	eye_glow_light.omni_range = eye_glow_range
	eye_glow_light.light_color = active_eye_color
	character_mesh.layers = 2
	var source_material : StandardMaterial3D = character_mesh.get_active_material(1)
	if source_material is StandardMaterial3D:
		_eye_material = source_material.duplicate() as StandardMaterial3D
		_eye_material.resource_local_to_scene = true
		_eye_material.emission_enabled = true
		character_mesh.set_surface_override_material(1, _eye_material)
	set_eye_light_enabled(false, true)


func set_vision_contact(source : Node, is_visible2 : bool) -> void:
	if source == null:
		return

	var source_id : int = source.get_instance_id()
	var was_alerted : bool = not _vision_contacts.is_empty()
	if is_visible2:
		_vision_contacts[source_id] = true
	else:
		_vision_contacts.erase(source_id)

	var is_alerted : bool = not _vision_contacts.is_empty()
	if was_alerted != is_alerted:
		stealth_alert_changed.emit(1.0 if is_alerted else 0.0)


func get_stealth_alert() -> float:
	return 1.0 if not _vision_contacts.is_empty() else 0.0


func enter_concealment(source : Node, visibility_multiplier : float) -> void:
	if source == null:
		return

	_concealment_sources[source.get_instance_id()] = clampf(
		visibility_multiplier,
		0.1,
		1.0
	)


func exit_concealment(source : Node) -> void:
	if source == null:
		return

	_concealment_sources.erase(source.get_instance_id())


func get_visibility_multiplier() -> float:
	return get_stealth_visibility()


func get_stealth_visibility() -> float:
	var visibility_multiplier : float = clampf(stealth, 0.1, 1.0)

	for source_multiplier : Variant in _concealment_sources.values():
		visibility_multiplier = minf(
			visibility_multiplier,
			float(source_multiplier)
		)

	if is_crouching and visibility_multiplier < 1.0:
		visibility_multiplier *= 0.65

	return clampf(visibility_multiplier, 0.1, 1.0)


## Shared entry into the ragdoll. Carries none of the side effects of dying, so
## the comic fall can reuse it and _die() only adds what belongs to death.
func _enter_ragdoll(impact_direction : Vector3, comic : bool,
	strength : float) -> void:
	_cancel_moving_turn()
	set_intervention_signal_pose(false)
	velocity = Vector3.ZERO
	_is_sprinting = false
	_jump_state = JumpState.READY
	_knockback_remaining_distance = 0.0
	_balance = balance_max
	_stumble_strength = 0.0
	_stumble_direction = Vector3.ZERO
	_last_impact_normal = Vector3.ZERO
	_was_on_wall = false
	is_crouching = false
	_crouch_amount = 0.0
	character_visual.position = _standing_visual_position
	footstep_audio.set_motion(0.0, false)

	if carried_item != null:
		carried_item.drop()
		carried_item = null
		if ik_target_container.has_method("set_carrying"):
			ik_target_container.call("set_carrying", false)

	animation_controller.set_ragdoll_active(true)
	collision_shape.set_deferred("disabled", true)

	if comic:
		ragdoll.start_comic_fall(impact_direction, strength)
	else:
		ragdoll.start_ragdoll(impact_direction)


func _die(impact_direction : Vector3 = Vector3.ZERO) -> void:
	if _is_dead:
		return

	_is_dead = true
	_fall_state = FallState.NONE
	set_eye_light_enabled(false)
	_enter_ragdoll(impact_direction, false, 1.0)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_physics_process(false)
	set_process_input(false)
	died.emit()


func _apply_knockback(delta : float) -> void:
	if _knockback_remaining_distance <= 0.0 or delta <= 0.0:
		return

	var step_distance : float = minf(
		knockback_speed * delta,
		_knockback_remaining_distance
	)
	var knockback_velocity : Vector3 = (
		_knockback_direction * step_distance / delta
	)
	velocity.x += knockback_velocity.x
	velocity.z += knockback_velocity.z
	_knockback_remaining_distance -= step_distance


func _update_balance(delta : float) -> void:
	_balance = minf(_balance + balance_recovery_speed * delta, balance_max)
	_stumble_strength = _stumble_strength_for(_balance)

	if _stumble_strength <= 0.0:
		_stumble_direction = Vector3.ZERO


func _stumble_strength_for(balance : float) -> float:
	if stumble_threshold <= 0.0:
		return 0.0

	return clampf((stumble_threshold - balance) / stumble_threshold, 0.0, 1.0)


## Turns a hard landing into balance loss, and a landing from very high into a
## fall. A plain jump from flat ground lands at jump_velocity, well below
## min_landing_speed, so it never costs anything.
func _detect_landing(was_on_floor : bool, velocity_before_move : Vector3) -> void:
	if _debug_god_mode_enabled or _debug_flight_enabled:
		return
	if was_on_floor or not is_on_floor():
		return

	var landing_speed : float = -velocity_before_move.y

	if landing_speed < min_landing_speed:
		return

	var direction : Vector3 = Vector3(
		velocity_before_move.x,
		0.0,
		velocity_before_move.z
	)

	if direction.length_squared() > 0.0001:
		direction = direction.normalized()
	else:
		# Landing straight down still needs a direction to buckle towards.
		direction = global_transform.basis.z

	# Right at the threshold the ET only trips; the extra speed of a longer drop
	# is what turns it into the full pratfall.
	if landing_speed > landing_ragdoll_speed:
		_trigger_impact_reaction(
			direction,
			ImpactReaction.RAGDOLL,
			impact_fall_strength
			+ (landing_speed - landing_ragdoll_speed)
			/ maxf(landing_ragdoll_speed, 0.001)
		)
		return

	animation_controller.trigger_landing(landing_speed)

	var balance_cost : float = (
		(landing_speed - min_landing_speed) * landing_balance_multiplier
	)

	if balance_cost <= 0.0:
		return

	_balance = maxf(_balance - balance_cost, 0.0)
	_stumble_direction = direction
	_stumble_strength = _stumble_strength_for(_balance)

	if _balance <= 0.0:
		_trigger_impact_reaction(
			direction,
			ImpactReaction.RAGDOLL,
			impact_fall_strength
		)


## Turns wall collisions from the last move_and_slide() into balance loss.
## Resting against a surface is not an impact: only a fresh contact, or a
## clearly different surface, counts as one.
func _detect_body_impacts(velocity_before_move : Vector3) -> void:
	if _debug_god_mode_enabled or _debug_flight_enabled:
		_was_on_wall = is_on_wall()
		return

	if not is_on_wall():
		_was_on_wall = false
		_last_impact_normal = Vector3.ZERO
		return

	var travel : Vector3 = Vector3(
		velocity_before_move.x,
		0.0,
		velocity_before_move.z
	)

	if travel.length() < min_impact_speed:
		_was_on_wall = true
		return

	var impact_speed : float = 0.0
	var impact_normal : Vector3 = Vector3.ZERO

	for index : int in get_slide_collision_count():
		var collision : KinematicCollision3D = get_slide_collision(index)
		var normal : Vector3 = collision.get_normal()

		if absf(normal.y) > WALL_NORMAL_LIMIT:
			continue

		var entering_speed : float = -travel.dot(normal)

		if entering_speed <= impact_speed:
			continue

		impact_speed = entering_speed
		impact_normal = Vector3(normal.x, 0.0, normal.z)

	var was_on_wall : bool = _was_on_wall
	_was_on_wall = true

	if (
		impact_speed < min_impact_speed
		or impact_normal.length_squared() <= 0.0001
	):
		return

	impact_normal = impact_normal.normalized()

	var is_new_contact : bool = (
		not was_on_wall
		or impact_normal.dot(_last_impact_normal) < NEW_CONTACT_NORMAL_LIMIT
	)

	if not is_new_contact:
		return

	_last_impact_normal = impact_normal
	_apply_body_impact(impact_normal, impact_speed)


## direction points away from whatever the ET hit, so it is also the direction
## the body is thrown. strength is the speed, in m/s, entering the surface.
## Note that running tops out at sprint_speed, so fall_impact_speed has to stay
## below it for a head-on crash to knock the ET down at all.
func _apply_body_impact(direction : Vector3, strength : float) -> void:
	if _fall_state != FallState.NONE or not is_alive():
		return

	var balance_cost : float = (
		(strength - min_impact_speed) * impact_balance_multiplier
	)

	if balance_cost <= 0.0:
		return

	_balance = maxf(_balance - balance_cost, 0.0)
	_stumble_direction = direction

	# Running into something never launches the ET across the map: a hard
	# horizontal hit, or a balance that ran out, is a short trip on the spot.
	if _balance <= 0.0 or strength >= fall_impact_speed:
		_trigger_impact_reaction(
			direction,
			ImpactReaction.RAGDOLL,
			impact_fall_strength
		)
		return

	_stumble_strength = _stumble_strength_for(_balance)

	if _stumble_strength <= 0.0:
		_trigger_impact_reaction(direction, ImpactReaction.HIT)
		return

	_trigger_impact_reaction(direction, ImpactReaction.STUMBLE)
	apply_knockback(direction, stumble_push_distance * _stumble_strength)


## One gate for visual/physical impact reactions. Callers determine severity;
## this method guarantees that only the selected tier is dispatched.
func _trigger_impact_reaction(direction : Vector3, reaction : ImpactReaction,
	fall_strength : float = 1.0) -> void:
	if _debug_god_mode_enabled:
		return
	_cancel_moving_turn()
	match reaction:
		ImpactReaction.HIT:
			animation_controller.trigger_hit(direction)
		ImpactReaction.STUMBLE:
			animation_controller.trigger_stumble(direction)
		ImpactReaction.RAGDOLL:
			_begin_fall(direction, fall_strength)


## strength scales both how hard the ragdoll is thrown and how long the ET
## stays down, so a trip against a wall is a short drop on the spot while a
## landing from very high is the full pratfall.
func _begin_fall(impact_direction : Vector3, strength : float) -> void:
	if _fall_state != FallState.NONE or not is_alive():
		return

	_enter_ragdoll(impact_direction, true, strength)
	_fall_impact_normal = impact_direction
	_fall_state = FallState.FALLEN
	_fall_timer = fall_recovery_delay * clampf(
		strength,
		MIN_FALL_TIME_SCALE,
		1.0
	)
	_stand_up_elapsed = 0.0
	_fall_target_position = global_position


func _update_fall(delta : float) -> void:
	velocity = Vector3.ZERO

	if _fall_state == FallState.FALLEN:
		_fall_target_position = _project_to_floor(
			ragdoll.get_body_global_position()
		)
		global_position = global_position.lerp(
			_fall_target_position,
			clampf(delta * fall_follow_speed, 0.0, 1.0)
		)
		_fall_timer = maxf(_fall_timer - delta, 0.0)

		if _fall_timer <= 0.0:
			_begin_stand_up()

		return

	_stand_up_elapsed += delta
	var pose_blend_ratio : float = 1.0
	if ragdoll_pose_blend_duration > 0.0:
		pose_blend_ratio = clampf(
			_stand_up_elapsed / ragdoll_pose_blend_duration,
			0.0,
			1.0
		)
	ragdoll.apply_recovery(smoothstep(0.0, 1.0, pose_blend_ratio))

	if animation_controller.is_get_up_ready_for_control():
		_finish_stand_up()


func _begin_stand_up() -> void:
	var face_up : bool = ragdoll.is_face_up()
	ragdoll.stop_ragdoll()
	collision_shape.set_deferred("disabled", false)
	_fall_state = FallState.STANDING_UP
	_stand_up_elapsed = 0.0
	animation_controller.begin_get_up(face_up)


func _finish_stand_up() -> void:
	ragdoll.apply_recovery(1.0)
	animation_controller.finish_get_up()
	_fall_state = FallState.NONE
	_balance = balance_max
	_stumble_strength = 0.0
	_stumble_direction = Vector3.ZERO
	_knockback_remaining_distance = 0.0
	_jump_state = JumpState.READY

	# The ET usually stands up still touching whatever knocked it down. Treating
	# that surface as an already known contact keeps a held movement key from
	# knocking it down again on the very next frame; _detect_body_impacts clears
	# both values as soon as the ET is no longer against a wall.
	_last_impact_normal = _fall_impact_normal
	_was_on_wall = _fall_impact_normal.length_squared() > 0.0001


func _project_to_floor(probe_position : Vector3) -> Vector3:
	var world : World3D = get_world_3d()

	if world == null:
		return probe_position

	var query := PhysicsRayQueryParameters3D.create(
		probe_position + Vector3.UP * FLOOR_PROBE_HEIGHT,
		probe_position + Vector3.DOWN * FLOOR_PROBE_DEPTH
	)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]

	var hit : Dictionary = world.direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return Vector3(probe_position.x, global_position.y, probe_position.z)

	return hit["position"] as Vector3


func _update_animation_controller() -> void:
	animation_controller.set_motion_state(
		velocity,
		is_on_floor(),
		_is_sprinting,
		is_crouching,
		_jump_state
	)


func get_balance() -> float:
	return _balance


func is_stumbling() -> bool:
	return _stumble_strength > 0.0


func is_fallen() -> bool:
	return _fall_state != FallState.NONE


func _update_crouch_state(delta : float) -> void:
	var wants_crouch := Input.is_action_pressed("crouch")

	if not wants_crouch and is_crouching and not _can_stand():
		wants_crouch = true

	is_crouching = wants_crouch

	var target_amount : float = 1.0 if is_crouching else 0.0
	_crouch_amount = move_toward(
		_crouch_amount,
		target_amount,
		delta * crouch_transition_speed
	)

	var capsule := collision_shape.shape as CapsuleShape3D

	if capsule != null:
		capsule.height = lerpf(
			STANDING_COLLISION_HEIGHT,
			CROUCHING_COLLISION_HEIGHT,
			_crouch_amount
		)
		collision_shape.position.y = capsule.height * 0.5

func _can_stand() -> bool:
	var capsule := collision_shape.shape as CapsuleShape3D

	if capsule == null or get_world_3d() == null:
		return true

	var standing_shape := capsule.duplicate() as CapsuleShape3D
	standing_shape.height = STANDING_COLLISION_HEIGHT

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing_shape
	query.transform = Transform3D(
		Basis.IDENTITY,
		global_position + Vector3.UP * (STANDING_COLLISION_HEIGHT * 0.5)
	)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]

	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
	
func try_pickup() -> void:

	if carried_item != null:
		return

	var items : Array[Node] = get_tree().get_nodes_in_group("pickup_items")

	var closest_item : RigidBody3D = null
	var closest_distance : float = 2.0

	for item in items:
		if not item is RigidBody3D:
			continue

		var distance : float = (
			global_position.distance_to(
				item.global_position
			)
		)

		if distance < closest_distance:
			closest_distance = distance
			closest_item = item


	if closest_item != null:
		carried_item = closest_item
		closest_item.pickup(self)
		if ik_target_container.has_method("set_carrying"):
			ik_target_container.call("set_carrying", true)


func _is_delivery_interaction_reserved() -> bool:
	for area : Node in get_tree().get_nodes_in_group("delivery_areas"):
		if not area.has_method("reserves_interaction_for"):
			continue

		if bool(area.call("reserves_interaction_for", self)):
			return true

	return false
	
