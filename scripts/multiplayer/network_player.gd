extends "res://scripts/player.gd"

var _target_transform: Transform3D
var _has_snapshot: bool = false
var _portal_epoch: int = 0
var _remote_epoch: int = -1
var _remote_on_floor: bool = true


func is_local_player() -> bool:
	return is_multiplayer_authority()


func get_pickup_candidate() -> RigidBody3D:
	if not is_local_player() or _movement_locked:
		return null
	var session: Node = get_parent().get_parent()
	var item: RigidBody3D = session.get("shared_item") as RigidBody3D
	return item if item != null and bool(item.call("can_pickup", self)) else null


func try_pickup() -> void:
	var item: RigidBody3D = get_pickup_candidate()
	if item != null:
		item.call("pickup", self)


func _enter_tree() -> void:
	if is_local_player():
		return
	get_node("PlayerHUD").hide()
	get_node("PlayerHUD").process_mode = Node.PROCESS_MODE_DISABLED
	get_node("ET/ETArmature/Skeleton3D/CharacterProportions").use_saved_appearance = false
	for node: Node in find_children("*", "Camera3D", true, false):
		(node as Camera3D).current = false
	remove_from_group(&"debug_player")


func _ready() -> void:
	var previous_mouse_mode: Input.MouseMode = Input.mouse_mode
	super._ready()
	if is_local_player():
		camera_pivot.get_camera().make_current()
	else:
		Input.mouse_mode = previous_mouse_mode
		set_process_input(false)
		camera_pivot.set_process_input(false)
		energy_pool.process_mode = Node.PROCESS_MODE_DISABLED


func _input(event: InputEvent) -> void:
	if is_local_player():
		super._input(event)


func _physics_process(delta: float) -> void:
	if is_local_player():
		super._physics_process(delta)
		return
	if not _has_snapshot:
		return
	global_transform = global_transform.interpolate_with(_target_transform, 1.0 - exp(-20.0 * delta))
	_update_camera_target()
	animation_controller.set_motion_state(velocity, _remote_on_floor, _is_sprinting, is_crouching, _jump_state)


func apply_portal_transform(mapping: Transform3D) -> void:
	if is_local_player():
		super.apply_portal_transform(mapping)
		_portal_epoch += 1


func make_snapshot() -> Dictionary:
	return {
		"transform": global_transform, "velocity": velocity,
		"on_floor": is_on_floor(), "sprinting": _is_sprinting,
		"crouching": is_crouching, "jump": _jump_state,
		"eye_light": is_eye_light_enabled(), "epoch": _portal_epoch,
		"yaw": camera_yaw, "pitch": camera_pitch,
	}


func receive_snapshot(state: Dictionary) -> void:
	if is_local_player():
		return
	_target_transform = state["transform"]
	var epoch: int = state["epoch"]
	# Portal crossings must jump directly to the exit instead of sliding through the map.
	if not _has_snapshot or epoch != _remote_epoch:
		global_transform = _target_transform
	_remote_epoch = epoch
	_has_snapshot = true
	velocity = state["velocity"]
	_remote_on_floor = state["on_floor"]
	_is_sprinting = state["sprinting"]
	is_crouching = state["crouching"]
	_jump_state = state["jump"]
	camera_yaw = state["yaw"]
	camera_pitch = state["pitch"]
	set_eye_light_enabled(state["eye_light"], true)
