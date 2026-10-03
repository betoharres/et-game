extends NPCActor

@export var attack_damage: float = 25.0
@export var attack_range: float = 2.0
@export var attack_interval: float = 1.2

var _host_simulation: bool = false
var _cooldown: float = 0.0
var _spawn: Transform3D
var _target_pose: Transform3D
var _has_network_state: bool = false
var target_peer_id: int = 0
var _session: Node3D


func _ready() -> void:
	super._ready()
	_session = get_parent().get_parent() as Node3D
	_spawn = global_transform
	_activity_timer.stop()
	var alerts: Node = get_node_or_null("/root/PhotoAlertSystem")
	if alerts != null and alerts.photo_count_changed.is_connected(_on_photo_count_changed):
		alerts.photo_count_changed.disconnect(_on_photo_count_changed)
	set_host_simulation(false)


func set_host_simulation(enabled: bool) -> void:
	_host_simulation = enabled
	var tree: BeehaveTree = get_node("NPCBehaviorTree") as BeehaveTree
	tree.interrupt()
	tree.enabled = enabled
	vision.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	vision.suspend_contact()
	vision.player = null
	player = null
	target_peer_id = 0
	_cooldown = 0.0
	_has_network_state = false
	global_transform = _spawn
	velocity = Vector3.ZERO
	set_state(&"patrol" if enabled else &"idle")


func _physics_process(delta: float) -> void:
	if not _host_simulation:
		if _has_network_state:
			global_transform = global_transform.interpolate_with(_target_pose, 1.0 - exp(-20.0 * delta))
		return
	_select_target()
	super._physics_process(delta)
	_cooldown = maxf(0.0, _cooldown - delta)


func attack_target() -> bool:
	if not _host_simulation or not is_instance_valid(player) or not player.is_alive() or not vision.has_detected_player or not vision.is_currently_visible or global_position.distance_to(player.global_position) > attack_range:
		return false
	stop_moving()
	face_direction(player.global_position - global_position)
	set_state(&"attack")
	if _cooldown <= 0.0:
		_cooldown = attack_interval
		_session.call("damage_player", target_peer_id, attack_damage, (player.global_position - global_position).normalized())
	return true


func _select_target() -> void:
	var selected: CharacterBody3D = null
	var nearest: float = INF
	var roster: Dictionary = _session.get("players")
	for candidate: CharacterBody3D in roster.values():
		if not candidate.is_alive():
			continue
		vision.player = candidate
		var distance: float = global_position.distance_squared_to(candidate.global_position)
		if distance < nearest and vision._can_see_player():
			selected = candidate
			nearest = distance
	vision.player = player if is_instance_valid(player) else null
	if selected == null and is_instance_valid(player) and player.is_alive():
		return
	if selected != player:
		vision.suspend_contact()
		player = selected
	vision.player = player
	target_peer_id = player.get_multiplayer_authority() if is_instance_valid(player) else 0


func _find_player() -> void:
	# The session roster supplies targets; global groups can include another viewport.
	player = null


func make_network_state() -> Dictionary:
	return {"pose": global_transform, "velocity": velocity, "state": state, "target": target_peer_id}


func receive_network_state(snapshot: Dictionary) -> void:
	if _host_simulation:
		return
	_target_pose = snapshot["pose"]
	if not _has_network_state:
		global_transform = _target_pose
	_has_network_state = true
	velocity = snapshot["velocity"]
	target_peer_id = snapshot["target"]
	set_state(snapshot["state"])
