extends CharacterBody3D

signal health_changed(current_health : float, maximum_health : float)
signal stamina_changed(current_stamina : float, maximum_stamina : float)
signal stealth_alert_changed(alert_level : float)
signal died

const STANDING_COLLISION_HEIGHT : float = 1.0
const CROUCHING_COLLISION_HEIGHT : float = 0.62


@export var speed: float = 5.0
@export var sprint_speed : float = 8.0
@export var crouch_speed : float = 2.5
@export var jump_velocity : float = 5.5
@export var crouch_transition_speed : float = 8.0
@export var crouch_camera_drop : float = 0.3
@export var crouch_visual_drop : float = 0.24
@export var sensitivity: float = 0.003
@export var rotation_speed: float = 10.0

@export_category("Survival")
@export var max_health : float = 100.0
@export var max_stamina : float = 100.0
@export var stamina_drain_per_second : float = 28.0
@export var stamina_recovery_per_second : float = 20.0
@export var stamina_recovery_delay : float = 0.8
@export var sprint_recovery_threshold : float = 20.0
@export var stamina_exhaustion_cooldown : float = 3.0

@export_category("Stealth")
@export_range(0.1, 1.0, 0.05) var stealth : float = 1.0

@export_category("Damage Response")
@export var knockback_speed : float = 3.5

@export_category("Camera")
@export var camera_pitch_min: float = -80.0
@export var camera_pitch_max: float = 80.0

@onready var camera_pivot: Node3D = $CameraHolder
@onready var footstep_audio : Node = $FootstepAudio
@onready var collision_shape : CollisionShape3D = $CollisionShape3D
@onready var character_visual : Node3D = $ET
@onready var ragdoll : Node = $PlayerRagdoll

var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var is_crouching : bool = false
var _crouch_amount : float = 0.0
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

# Items
var carried_item : RigidBody3D = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health = max_health
	stamina = max_stamina

	camera_yaw = global_rotation.y
	camera_pitch = camera_pivot.rotation.x
	_standing_visual_position = character_visual.position

	if collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()

	health_changed.emit(health, max_health)
	stamina_changed.emit(stamina, max_stamina)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mouse_motion: Vector2 = event.relative

			camera_yaw -= mouse_motion.x * sensitivity
			camera_pitch -= -mouse_motion.y * sensitivity

			var minimum_pitch: float = deg_to_rad(camera_pitch_min)
			var maximum_pitch: float = deg_to_rad(camera_pitch_max)

			camera_pitch = clampf(camera_pitch,minimum_pitch,maximum_pitch)

# Items
	if event.is_action_pressed("interact"):
		if carried_item == null:
			try_pickup()
		else:
			carried_item.drop()
			carried_item = null

func _physics_process(delta: float) -> void:
	_update_crouch_state(delta)

	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not is_crouching:
			velocity.y = jump_velocity
		else:
			velocity.y = -0.1
	else:
		velocity.y += get_gravity().y * delta
	
	camera_pivot.global_position = (
		global_position
		+ Vector3.DOWN * crouch_camera_drop * _crouch_amount
	)
	var camera_rotation : Vector3 = Vector3(camera_pitch,camera_yaw,0.0)

	camera_pivot.global_rotation = camera_rotation

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
	)
	_update_stamina(delta, wants_to_sprint)

	if has_movement_input:
		movement_direction = movement_direction.normalized()

		var movement_speed : float = _get_movement_speed()
		velocity.x = movement_direction.x * movement_speed
		velocity.z = movement_direction.z * movement_speed

		var target_angle: float = atan2(movement_direction.x,movement_direction.z)

		rotation.y = rotate_toward(rotation.y,target_angle,rotation_speed * delta)
	else:
		var deceleration : float = _get_movement_speed()
		velocity.x = move_toward(velocity.x,0.0,deceleration)

		velocity.z = move_toward(velocity.z,0.0,deceleration)

	_apply_knockback(delta)

	move_and_slide()

	var horizontal_speed : float = Vector2(velocity.x, velocity.z).length()
	footstep_audio.set_motion(horizontal_speed, is_on_floor())


func _get_movement_speed() -> float:
	if is_crouching:
		return crouch_speed

	if _is_sprinting:
		return sprint_speed

	return speed


func _update_stamina(delta : float, wants_to_sprint : bool) -> void:
	var previous_stamina : float = stamina
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


func take_damage(
	amount : float,
	hit_direction : Vector3 = Vector3.ZERO,
	push_distance : float = 0.0
) -> void:
	if amount <= 0.0 or health <= 0.0:
		return

	var is_fatal : bool = health - amount <= 0.0

	if push_distance > 0.0 and not is_fatal:
		apply_knockback(hit_direction, push_distance)

	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)

	if health <= 0.0:
		_die(hit_direction)


func apply_knockback(direction : Vector3, distance : float) -> void:
	if distance <= 0.0 or health <= 0.0:
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


func is_alive() -> bool:
	return health > 0.0


func set_vision_contact(source : Node, is_visible : bool) -> void:
	if source == null:
		return

	var source_id : int = source.get_instance_id()
	var was_alerted : bool = not _vision_contacts.is_empty()
	if is_visible:
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


func _die(impact_direction : Vector3 = Vector3.ZERO) -> void:
	velocity = Vector3.ZERO
	_is_sprinting = false
	_knockback_remaining_distance = 0.0
	footstep_audio.set_motion(0.0, false)

	if carried_item != null:
		carried_item.drop()
		carried_item = null

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	collision_shape.set_deferred("disabled", true)
	ragdoll.call("start_ragdoll", impact_direction)
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


func _update_crouch_state(delta : float) -> void:
	var wants_crouch : bool = Input.is_action_pressed("crouch")

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

	character_visual.position = (
		_standing_visual_position
		+ Vector3.DOWN * crouch_visual_drop * _crouch_amount
	)


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

func deliver_item(_delivery_area : Area3D) -> void:
	if carried_item == null:
		return

	var score : int = carried_item.score_value

	GlobalScore.add_score(score)
	carried_item.queue_free()
	carried_item = null
