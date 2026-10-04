extends Node3D

var session: Node3D
var _body: Node3D
var _host: bool = false
var _target: Transform3D
var _has_pose: bool = false


func _ready() -> void:
	_body = get_parent() as Node3D
	_body.ready.connect(func() -> void: set_host_simulation(false), CONNECT_ONE_SHOT)


func set_host_simulation(enabled: bool) -> void:
	_host = enabled
	_body.set_physics_process(enabled)
	_body.set_process_input(false)
	_body.set_process_unhandled_input(false)
	if _body is RigidBody3D:
		(_body as RigidBody3D).freeze = not enabled


func _physics_process(delta: float) -> void:
	if not _host and _has_pose:
		_body.global_transform = _body.global_transform.interpolate_with(_target, 1.0 - exp(-20.0 * delta))


func make_network_state() -> Dictionary:
	return {"pose": _body.global_transform, "velocity": _body.velocity if _body is CharacterBody3D else (_body as RigidBody3D).linear_velocity,
		"angular": (_body as RigidBody3D).angular_velocity if _body is RigidBody3D else Vector3.ZERO}


func receive_network_state(state: Dictionary) -> void:
	if _host:
		return
	_target = state.pose
	if not _has_pose:
		_body.global_transform = _target
	_has_pose = true
	if _body is CharacterBody3D:
		(_body as CharacterBody3D).velocity = state.velocity


func make_migration_state() -> Dictionary:
	return make_network_state()


func restore_migration_state(state: Dictionary) -> void:
	_body.global_transform = state.pose
	if _body is RigidBody3D:
		(_body as RigidBody3D).linear_velocity = state.velocity
		(_body as RigidBody3D).angular_velocity = state.angular
	elif _body is CharacterBody3D:
		(_body as CharacterBody3D).velocity = state.velocity
