class_name PursuitDirector
extends Node3D

@export var player_path: NodePath
@export var terrain_path: NodePath
@export var geometry_root_path: NodePath = NodePath("..")
@export var agent_scene: PackedScene
@export var factions: Array[PursuitProfile] = []

@export_category("Regras de alerta")
@export_range(0, 3) var stars_per_theft: int = 1
@export_range(0, 3) var stars_per_photo: int = 1
@export_range(1.0, 300.0) var hidden_seconds_per_star: float = 30.0

@export_category("Limites de reforços")
@export_range(1, 20) var maximum_active_enemies: int = 6
@export_range(0.1, 30.0) var initial_response_delay: float = 2.0
@export_range(5.0, 100.0) var minimum_spawn_distance: float = 20.0
@export_range(5.0, 150.0) var maximum_spawn_distance: float = 36.0
@export_range(1, 64) var spawn_attempts_per_wave: int = 24
@export_range(40.0, 300.0) var despawn_distance: float = 110.0

var active_enemies: Array[PursuitNPC] = []
var _player: CharacterBody3D
var _last_reported_position: Vector3 = Vector3.INF
var _reinforcement_timer: float = 0.0
var _report_timer: float = 0.0
var _spawn_shape: CapsuleShape3D

@onready var navigation: PursuitNavigation = $Navigation
@onready var _units: Node3D = $Reinforcements
@onready var _alert: Node = get_node("/root/PhotoAlertSystem")


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	if _player == null:
		_player = get_tree().get_first_node_in_group("players") as CharacterBody3D
	if _player == null or agent_scene == null:
		push_error("Perseguição: configure o jogador e a cena do reforço.")
		set_physics_process(false)
		return
	_alert.reset()
	_alert.stars_per_theft = stars_per_theft
	_alert.stars_per_photo = stars_per_photo
	_alert.hidden_seconds_per_star = hidden_seconds_per_star
	_alert.photo_count_changed.connect(_on_level_changed)
	_alert.incident_reported.connect(_on_incident)
	_player.connect("item_collected", _on_item_collected)
	_player.connect("died", _on_player_died)
	_spawn_shape = CapsuleShape3D.new()
	_spawn_shape.radius = 0.35
	_spawn_shape.height = 1.9
	var geometry_root: Node3D = get_node(geometry_root_path) as Node3D
	var terrain: Terrain3D = get_node_or_null(terrain_path) as Terrain3D if not terrain_path.is_empty() else null
	navigation.build.call_deferred(geometry_root, terrain)


func _exit_tree() -> void:
	if is_instance_valid(_alert) and _alert.photo_count_changed.is_connected(_on_level_changed):
		_alert.photo_count_changed.disconnect(_on_level_changed)
		_alert.incident_reported.disconnect(_on_incident)
		_alert.reset()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player) or not _player.is_alive():
		return
	_reinforcement_timer = maxf(_reinforcement_timer - delta, 0.0)
	_report_timer -= delta
	if _report_timer <= 0.0:
		_report_timer = 0.2
		_update_reports()
	var profile: PursuitProfile = get_profile(_alert.get_photo_count())
	if profile == null or not navigation.is_ready_for_paths() or _reinforcement_timer > 0.0:
		return
	_reinforcement_timer = maxf(profile.reinforcement_interval, 1.0)
	_spawn_wave(profile)


func get_profile(level: int) -> PursuitProfile:
	for profile: PursuitProfile in factions:
		if profile != null and profile.stars == level:
			return profile
	return null


func _on_item_collected(item: RigidBody3D) -> void:
	_alert.register_theft(item, _player.global_position)


func _on_incident(position_seen: Vector3) -> void:
	_last_reported_position = position_seen
	for npc: PursuitNPC in active_enemies:
		if is_instance_valid(npc) and not npc.is_queued_for_deletion():
			npc.vision.last_seen_position = position_seen
			npc.vision.has_last_seen_position = true


func _on_level_changed(level: int, _maximum: int) -> void:
	for npc: PursuitNPC in active_enemies.duplicate():
		if is_instance_valid(npc) and npc.profile.stars != level:
			_retire(npc)
	if level == 0:
		_last_reported_position = Vector3.INF
		_reinforcement_timer = 0.0
	else:
		_reinforcement_timer = maxf(_reinforcement_timer, initial_response_delay)
		if not _last_reported_position.is_finite():
			_last_reported_position = _player.global_position


func _on_player_died() -> void:
	_alert.reset()


func _update_reports() -> void:
	for npc: PursuitNPC in active_enemies.duplicate():
		if not is_instance_valid(npc) or npc.is_queued_for_deletion():
			continue
		var observed: bool = npc.vision.is_currently_visible
		_alert.set_pursuer_observing(npc.get_instance_id(), observed)
		if observed:
			_on_incident(npc.vision.last_seen_position)
		elif npc.global_position.distance_to(_player.global_position) > despawn_distance:
			_retire(npc)


func _spawn_wave(profile: PursuitProfile) -> void:
	if not _last_reported_position.is_finite():
		return
	if _last_reported_position.distance_to(_player.global_position) > despawn_distance:
		return
	var available: int = mini(maximum_active_enemies, profile.max_active) - active_enemies.size()
	var remaining: int = mini(available, profile.wave_size)
	for attempt: int in range(spawn_attempts_per_wave):
		if remaining <= 0:
			break
		var angle: float = randf() * TAU
		var radius: float = randf_range(minimum_spawn_distance, maxf(maximum_spawn_distance, minimum_spawn_distance))
		var requested: Vector3 = _last_reported_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var point: Vector3 = find_spawn_position(requested)
		if not point.is_finite():
			continue
		var npc: PursuitNPC = agent_scene.instantiate() as PursuitNPC
		npc.profile = profile
		npc.position = _units.to_local(point)
		_units.add_child(npc)
		npc.player = _player
		npc.vision.player = _player
		npc.navigation_agent.set_navigation_map(navigation.get_navigation_map())
		npc.patrol_points = [point]
		npc.vision.last_seen_position = _last_reported_position
		npc.vision.has_last_seen_position = true
		npc.look_at(Vector3(_last_reported_position.x, point.y, _last_reported_position.z), Vector3.UP, true)
		active_enemies.append(npc)
		npc.tree_exiting.connect(_on_enemy_exiting.bind(npc), CONNECT_ONE_SHOT)
		remaining -= 1


func find_spawn_position(requested: Vector3) -> Vector3:
	if not navigation.is_ready_for_paths():
		return Vector3.INF
	var map: RID = navigation.get_navigation_map()
	var point: Vector3 = NavigationServer3D.map_get_closest_point(map, requested)
	if point.distance_to(requested) > 3.0 or point.distance_to(_player.global_position) < minimum_spawn_distance:
		return Vector3.INF
	var target: Vector3 = NavigationServer3D.map_get_closest_point(map, _last_reported_position)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, point, target, true)
	var profile: PursuitProfile = get_profile(_alert.get_photo_count())
	var approach_range: float = profile.attack_range if profile != null else 1.0
	# Um ET atrás de uma cerca pode ser alcançado por tiro do lado de fora;
	# exigir chegar aos seus pés impediria qualquer reforço nesse cercado.
	if path.is_empty() or path[path.size() - 1].distance_to(target) > approach_range:
		return Vector3.INF
	var ground_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP * 2.0, 1)
	var ground: Dictionary = get_world_3d().direct_space_state.intersect_ray(ground_ray)
	if ground.is_empty() or Vector3(ground["normal"]).dot(Vector3.UP) < 0.7:
		return Vector3.INF
	var ground_point: Vector3 = ground["position"]
	if absf(ground_point.y - point.y) > 0.6:
		return Vector3.INF
	point = ground_point + Vector3.UP * 0.08
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = _spawn_shape
	query.transform.origin = point + Vector3.UP * 0.95
	query.collision_mask = 1
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return Vector3.INF
	for npc: PursuitNPC in active_enemies:
		if is_instance_valid(npc) and npc.global_position.distance_to(point) < 1.2:
			return Vector3.INF
	return point


func _retire(npc: PursuitNPC) -> void:
	_alert.set_pursuer_observing(npc.get_instance_id(), false)
	active_enemies.erase(npc)
	npc.process_mode = Node.PROCESS_MODE_DISABLED
	npc.queue_free()


func _on_enemy_exiting(npc: PursuitNPC) -> void:
	_alert.set_pursuer_observing(npc.get_instance_id(), false)
	active_enemies.erase(npc)
