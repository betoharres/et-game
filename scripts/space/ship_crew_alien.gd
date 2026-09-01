class_name ShipCrewAlien
extends CharacterBody3D

## Tripulante cenografico que passeia por uma pequena area do interior da nave.
## O limite e relativo a posicao inicial para que cada instancia possa ocupar
## um setor diferente sem precisar de NavigationMesh em uma nave movel.

const CARRIABLE_GROUP : StringName = &"carriable_characters"

enum MovementMode {
	WANDER,
	BOUNCE,
	DOWNED,
}

@export_category("Wander")
@export var movement_mode : MovementMode = MovementMode.WANDER
@export var running : bool = false
@export var walk_speed : float = 1.25
@export var run_speed : float = 3.4
@export var wander_extents : Vector2 = Vector2(4.5, 8.0)
@export var arrival_distance : float = 0.35
@export var wait_time_minimum : float = 0.5
@export var wait_time_maximum : float = 1.8
@export_range(0.0, 1.0, 0.05) var continue_walking_chance : float = 0.65
@export_range(0.0, 1.0, 0.05) var large_turn_chance : float = 0.3
@export var normal_curve_minimum : float = 0.12
@export var normal_curve_maximum : float = 0.42
@export var large_curve_minimum : float = 0.7
@export var large_curve_maximum : float = 1.1
@export var turn_speed : float = 5.0
@export var stuck_timeout : float = 1.25

@export_category("Downed")
@export var downed_pose_animation : StringName = &"carried_from_ground"
@export var downed_pose_time : float = 0.0
@export var downed_collision_height : float = 0.12
@export var release_forward_distance : float = 0.6
@export var minimum_lift_duration : float = 0.35

@export_category("Bounce")
@export var direction_time_minimum : float = 1.5
@export var direction_time_maximum : float = 4.0
@export_range(0.0, 90.0, 1.0) var bounce_random_degrees : float = 35.0

@onready var animation_controller : PlayerAnimationController = (
	$PlayerAnimationController
)
@onready var collision_shape : CollisionShape3D = $CollisionShape3D
@onready var ragdoll : PlayerRagdoll = $PlayerRagdoll

var _random : RandomNumberGenerator = RandomNumberGenerator.new()
var _anchor_position : Vector3 = Vector3.ZERO
var _target_position : Vector3 = Vector3.ZERO
var _previous_position : Vector3 = Vector3.ZERO
var _wait_timer : float = 0.0
var _stuck_timer : float = 0.0
var _bounce_direction : Vector3 = Vector3.FORWARD
var _direction_timer : float = 0.0
var _curve_amount : float = 0.0
var _carrier : Node3D = null
var _carry_socket : Node3D = null
var _home_parent : Node = null
var _lift_timer : float = 0.0
var _lift_duration : float = 0.0
var _lift_start : Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	_random.randomize()
	_home_parent = get_parent()
	_anchor_position = position
	_previous_position = position
	_choose_new_target()
	_choose_bounce_direction()
	if movement_mode == MovementMode.DOWNED:
		_enter_downed_state()


func _physics_process(delta : float) -> void:
	if _carrier != null:
		velocity = Vector3.ZERO
		_update_carried(delta)
		return

	if movement_mode == MovementMode.DOWNED:
		velocity = Vector3.ZERO
		return

	if movement_mode == MovementMode.BOUNCE:
		_update_bounce_movement(delta)
		return

	if _wait_timer > 0.0:
		_wait_timer = maxf(_wait_timer - delta, 0.0)
		velocity = Vector3.ZERO
		_update_animation()
		if _wait_timer <= 0.0:
			_choose_new_target()
		return

	var parent_3d : Node3D = get_parent_node_3d()
	if parent_3d == null:
		velocity = Vector3.ZERO
		_update_animation()
		return

	var target_global : Vector3 = parent_3d.to_global(_target_position)
	var direction : Vector3 = target_global - global_position
	var ship_up : Vector3 = parent_3d.global_transform.basis.y.normalized()
	direction = direction.slide(ship_up)

	if direction.length() <= arrival_distance:
		_finish_wander_leg()
		return

	var distance_to_target : float = direction.length()
	var direct_heading : Vector3 = direction / distance_to_target
	var curve_fade : float = clampf(distance_to_target / 4.0, 0.0, 1.0)
	var curved_heading : Vector3 = (
		direct_heading
		+ direct_heading.cross(ship_up) * _curve_amount * curve_fade
	).normalized()
	var move_direction : Vector3 = _face_direction(
		curved_heading,
		ship_up,
		delta
	)
	velocity = move_direction * _movement_speed()
	move_and_slide()
	_update_stuck_state(delta)
	_update_animation()


## Caido no chao da nave: o corpo fica congelado em um unico frame autorado e
## a capsula deita junto para o jogador nao esbarrar em um volume em pe.
func _enter_downed_state() -> void:
	movement_mode = MovementMode.DOWNED
	velocity = Vector3.ZERO
	collision_shape.disabled = false
	collision_shape.transform = Transform3D(
		Basis(Vector3.RIGHT, PI * 0.5),
		Vector3(0.0, downed_collision_height, 0.0)
	)
	animation_controller.hold_pose(downed_pose_animation, downed_pose_time)
	add_to_group(CARRIABLE_GROUP)


func is_carriable() -> bool:
	return movement_mode == MovementMode.DOWNED and _carrier == null


## Levantado do chao: o corpo vira ragdoll e fica mole. Nenhum clipe toca no
## ET carregado -- so o quadril e preso ao soquete do carregador, e o resto do
## corpo pendura pelos joints da simulacao.
func begin_carried(carrier : Node3D, lift_duration : float) -> bool:
	if not is_carriable() or carrier == null:
		return false

	var socket : Node3D = carrier.get_node_or_null("CarrySocket") as Node3D
	if socket == null:
		push_warning("Carregador sem CarrySocket: %s" % carrier.name)
		return false

	_carrier = carrier
	_carry_socket = socket
	remove_from_group(CARRIABLE_GROUP)
	velocity = Vector3.ZERO
	collision_shape.disabled = true
	animation_controller.release_pose()
	animation_controller.set_ragdoll_active(true)
	ragdoll.start_ragdoll()
	ragdoll.set_world_collision(false)
	_lift_duration = maxf(lift_duration, minimum_lift_duration)
	_lift_timer = _lift_duration
	_lift_start = Transform3D(
		global_transform.basis,
		ragdoll.get_body_global_position()
	)
	return true


## A subida interpola do chao ate os bracos: prender o quadril de uma vez so
## teleportaria o corpo para o colo no primeiro quadro.
func _update_carried(delta : float) -> void:
	if not is_instance_valid(_carry_socket):
		release()
		return

	var target : Transform3D = _carry_socket.global_transform.orthonormalized()
	if _lift_timer > 0.0:
		_lift_timer = maxf(_lift_timer - delta, 0.0)
		var progress : float = 1.0 - _lift_timer / maxf(_lift_duration, 0.001)
		target = _lift_start.interpolate_with(
			target,
			smoothstep(0.0, 1.0, progress)
		)

	ragdoll.pin_bone_to(PlayerRagdoll.ROOT_BONE, target)


func release() -> void:
	if _carrier == null:
		return

	var carrier_transform : Transform3D = _carrier.global_transform
	var drop_transform : Transform3D = carrier_transform
	drop_transform.origin += (
		carrier_transform.basis.z.normalized() * release_forward_distance
	)
	ragdoll.stop_ragdoll()
	animation_controller.set_ragdoll_active(false)
	global_transform = drop_transform.orthonormalized()
	_carrier = null
	_carry_socket = null
	_lift_timer = 0.0
	_enter_downed_state()


func _update_bounce_movement(delta : float) -> void:
	var parent_3d : Node3D = get_parent_node_3d()
	if parent_3d == null:
		velocity = Vector3.ZERO
		_update_animation()
		return

	_direction_timer -= delta
	if _direction_timer <= 0.0:
		_choose_bounce_direction()

	var ship_basis : Basis = parent_3d.global_transform.basis.orthonormalized()
	var ship_up : Vector3 = ship_basis.y.normalized()
	var desired_direction : Vector3 = (
		ship_basis * _bounce_direction
	).slide(ship_up).normalized()
	var move_direction : Vector3 = _face_direction(
		desired_direction,
		ship_up,
		delta
	)
	velocity = move_direction * _movement_speed()
	move_and_slide()

	if get_slide_collision_count() > 0:
		var collision : KinematicCollision3D = get_last_slide_collision()
		var wall_normal : Vector3 = collision.get_normal().slide(ship_up)
		if wall_normal.length_squared() > 0.0001:
			var reflected : Vector3 = move_direction.bounce(wall_normal.normalized())
			var random_angle : float = deg_to_rad(_random.randf_range(
				-bounce_random_degrees,
				bounce_random_degrees
			))
			reflected = Basis(ship_up, random_angle) * reflected
			_bounce_direction = (ship_basis.inverse() * reflected).normalized()
			_direction_timer = _random_direction_duration()

	_update_animation()


func _choose_new_target() -> void:
	var is_large_turn : bool = _random.randf() < large_turn_chance
	if is_large_turn:
		_target_position = _choose_distant_patrol_point()
		_curve_amount = _random_signed_range(
			large_curve_minimum,
			large_curve_maximum
		)
	else:
		_target_position = _random_patrol_point()
		_curve_amount = _random_signed_range(
			normal_curve_minimum,
			normal_curve_maximum
		)
	_stuck_timer = 0.0
	_previous_position = position


func _random_patrol_point() -> Vector3:
	return _anchor_position + Vector3(
		_random.randf_range(-wander_extents.x, wander_extents.x),
		0.0,
		_random.randf_range(-wander_extents.y, wander_extents.y)
	)


func _choose_distant_patrol_point() -> Vector3:
	var best_point : Vector3 = _random_patrol_point()
	var best_distance_squared : float = position.distance_squared_to(best_point)
	for _attempt : int in range(5):
		var candidate : Vector3 = _random_patrol_point()
		var candidate_distance_squared : float = position.distance_squared_to(
			candidate
		)
		if candidate_distance_squared > best_distance_squared:
			best_point = candidate
			best_distance_squared = candidate_distance_squared
	return best_point


func _random_signed_range(minimum : float, maximum : float) -> float:
	var magnitude : float = _random.randf_range(minimum, maxf(minimum, maximum))
	return magnitude if _random.randf() < 0.5 else -magnitude


func _choose_bounce_direction() -> void:
	var angle : float = _random.randf_range(-PI, PI)
	_bounce_direction = Vector3(sin(angle), 0.0, cos(angle))
	_direction_timer = _random_direction_duration()


func _random_direction_duration() -> float:
	return _random.randf_range(
		direction_time_minimum,
		maxf(direction_time_minimum, direction_time_maximum)
	)


func _begin_wait() -> void:
	velocity = Vector3.ZERO
	_wait_timer = _random.randf_range(
		wait_time_minimum,
		maxf(wait_time_minimum, wait_time_maximum)
	)
	_stuck_timer = 0.0
	_update_animation()


func _finish_wander_leg() -> void:
	if _random.randf() < continue_walking_chance:
		_choose_new_target()
		return
	_begin_wait()


func _face_direction(direction : Vector3, up : Vector3, delta : float) -> Vector3:
	var target_transform : Transform3D = global_transform.looking_at(
		global_position + direction,
		up,
		true
	)
	var blend : float = clampf(turn_speed * delta, 0.0, 1.0)
	var turned_transform : Transform3D = global_transform
	turned_transform.basis = global_transform.basis.slerp(
		target_transform.basis,
		blend
	).orthonormalized()
	global_transform = turned_transform
	return global_transform.basis.z.slide(up).normalized()


func _update_stuck_state(delta : float) -> void:
	var moved_distance : float = position.distance_to(_previous_position)
	_previous_position = position
	if moved_distance > _movement_speed() * delta * 0.2:
		_stuck_timer = 0.0
		return

	_stuck_timer += delta
	if _stuck_timer >= stuck_timeout:
		_choose_new_target()


func _update_animation() -> void:
	animation_controller.set_motion_state(
		velocity,
		true,
		running,
		false,
		0
	)


func _movement_speed() -> float:
	return run_speed if running else walk_speed
