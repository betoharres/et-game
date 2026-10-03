extends "res://scripts/living_light.gd"

var _host_simulation: bool = false
var _target_pose: Transform3D
var _has_network_state: bool = false
var _spawn: Transform3D
var _session: Node3D


func _ready() -> void:
	_session = get_parent().get_parent() as Node3D
	super._ready()
	_spawn = global_transform


func _find_player() -> void:
	_player = null
	if _session == null:
		return
	var nearest: float = INF
	for candidate: CharacterBody3D in _session.players.values():
		if not candidate.is_alive() or candidate.get_stealth_visibility() <= 0.0:
			continue
		var distance: float = global_position.distance_squared_to(candidate.global_position)
		if distance < nearest:
			nearest = distance
			_player = candidate


func _refresh_player_if_needed() -> void:
	_find_player()


func set_host_simulation(enabled: bool) -> void:
	_host_simulation = enabled
	_player = null
	global_transform = _spawn
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if _host_simulation:
		super._physics_process(delta)
	elif _has_network_state:
		global_transform = global_transform.interpolate_with(_target_pose, 1.0 - exp(-20.0 * delta))
		_motion_time += delta
		_update_visual_language(delta)


func make_network_state() -> Dictionary:
	return {"pose": global_transform, "velocity": velocity, "state": current_state}


func receive_network_state(snapshot: Dictionary) -> void:
	_target_pose = snapshot["pose"]
	current_state = snapshot["state"]
	velocity = snapshot["velocity"]
	if not _has_network_state:
		global_transform = _target_pose
	_has_network_state = true
