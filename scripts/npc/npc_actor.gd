class_name NPCActor
extends CharacterBody3D

## Chassi comum a todo NPC de pé (fazendeiro, morador, policial). Cuida de
## locomoção via NavigationAgent3D, patrulha por Marker3D e do estado exibido
## pela Behavior Tree; visão e audição ficam em componentes filhos separados
## (NPCVision/NPCHearing).

enum ReactionMode { CHASE, FLEE }
enum AwarenessState { NEUTRAL, ALERT, PURSUIT }

@export_category("Activity")
## Zero keeps simulation running regardless of player distance.
@export var activity_distance: float = 90.0
@export var activity_hysteresis: float = 15.0

var is_dormant: bool = false
var _activity_timer: Timer
var _saved_process_modes: Dictionary[Node, int] = {}
var _saved_avoidance: bool = false

@export_category("Movimento")
@export var walk_speed: float = 2.0
@export var alert_speed: float = 3.4
@export var rotation_speed: float = 2.5
@export var require_navigation: bool = false
@export var grounded: bool = false

@export_category("Rotina")
## Posições absolutas (mundo) que o NPC visita em sequência, na mesma
## convenção de `VehicleAIDriver.road_nodes`. Um único ponto (ou nenhum) faz o
## NPC ficar parado "trabalhando" em vez de patrulhar.
@export var patrol_points: Array[Vector3] = []
@export var patrol_wait_time_min: float = 2.0
@export var patrol_wait_time_max: float = 5.0
@export var idle_wait_time_min: float = 3.0
@export var idle_wait_time_max: float = 7.0

@export_category("Reação ao ET")
@export var reaction_mode: ReactionMode = ReactionMode.CHASE
@export var search_duration: float = 6.0
@export var investigate_wait_time: float = 3.0
@export var flee_distance: float = 18.0

@export_category("Social")
@export var can_socialize: bool = false
@export var social_group_name: StringName = &""
@export var chat_radius: float = 3.5
@export var chat_stop_distance: float = 1.4
@export var chat_duration_min: float = 2.5
@export var chat_duration_max: float = 5.0
@export var chat_cooldown: float = 12.0

@export_category("Lanterna")
@export var use_flashlight: bool = false
@export var flashlight_path: NodePath

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var vision: NPCVision = get_node_or_null("NPCVision")
@onready var hearing: NPCHearing = get_node_or_null("NPCHearing")
@onready var animation: NPCAnimation = get_node_or_null("NPCAnimation")
@onready var routine: NPCRoutine = get_node_or_null("NPCRoutine")
@onready var flashlight: Light3D = (
	get_node_or_null(flashlight_path) if not flashlight_path.is_empty() else null
)

var player: CharacterBody3D = null
var state: StringName = &"idle"
var awareness_state: AwarenessState = AwarenessState.NEUTRAL
var _wanted_alert: bool = false
var last_chat_time: float = -1000.0
var navigation_failed: bool = false
var _stuck_time: float = 0.0
var _motion_target: Vector3 = Vector3.INF
var _last_progress_position: Vector3 = Vector3.INF
var _navigation_failure_until: float = 0.0
var _report_cooldown: float = 0.0
var _detail_timer: float = 0.0
var _simple_routine: bool = false

signal state_changed(new_state: StringName)
signal awareness_state_changed(new_state: StringName)


func _ready() -> void:
	add_to_group(&"npc_actors")
	if social_group_name != &"":
		add_to_group(social_group_name)

	_find_player()
	var alert_system: Node = get_node_or_null("/root/PhotoAlertSystem")
	if alert_system != null:
		alert_system.photo_count_changed.connect(_on_photo_count_changed)
		_on_photo_count_changed(int(alert_system.get_photo_count()), int(alert_system.get_max_photo_count()))

	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = 0.8

	if flashlight:
		flashlight.visible = use_flashlight
	floor_snap_length = 0.45 if grounded else 0.0
	navigation_agent.avoidance_enabled = require_navigation
	navigation_agent.radius = 0.35
	navigation_agent.neighbor_distance = 3.0
	navigation_agent.max_neighbors = 5
	navigation_agent.velocity_computed.connect(_apply_safe_velocity)
	if routine != null:
		last_chat_time = Time.get_ticks_msec() / 1000.0 + randf_range(0.0, 10.0)
	_activity_timer = Timer.new()
	_activity_timer.name = "ActivityCheck"
	# Explicit mode lets the timer wake a disabled parent, but respects game pause.
	_activity_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_activity_timer.one_shot = true
	_activity_timer.timeout.connect(_check_activity)
	add_child(_activity_timer)
	_activity_timer.start(randf_range(0.01, 0.5))


func _check_activity() -> void:
	_activity_timer.start(0.5)
	if not is_dormant and not can_process():
		return
	var nearby: bool = activity_distance <= 0.0
	var radius: float = maxf(0.0, activity_distance - activity_hysteresis) if is_dormant else activity_distance
	for candidate: Node in get_tree().get_nodes_in_group(&"characters"):
		var character: CharacterBody3D = candidate as CharacterBody3D
		if character == null or character is NPCActor:
			continue
		if global_position.distance_squared_to(character.global_position) <= radius * radius:
			nearby = true
			break
	_set_dormant(not nearby)


func _set_dormant(sleeping: bool) -> void:
	if is_dormant == sleeping:
		return
	if sleeping:
		var tree: BeehaveTree = get_node_or_null("NPCBehaviorTree") as BeehaveTree
		if tree != null:
			tree.interrupt()
		if routine != null:
			routine.interrupt()
		stop_moving()
		velocity = Vector3.ZERO
		if vision != null:
			vision.suspend_contact()
		_saved_avoidance = navigation_agent.avoidance_enabled
		navigation_agent.avoidance_enabled = false
		_suspend_branch(self)
	else:
		for node: Node in _saved_process_modes:
			if is_instance_valid(node):
				node.process_mode = _saved_process_modes[node] as Node.ProcessMode
		_saved_process_modes.clear()
		navigation_agent.avoidance_enabled = _saved_avoidance
		_find_player()
		if vision != null:
			vision.player = player
		_detail_timer = 0.0
	is_dormant = sleeping


func _suspend_branch(node: Node) -> void:
	if node == _activity_timer:
		return
	_saved_process_modes[node] = node.process_mode
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for child: Node in node.get_children():
		_suspend_branch(child)


func _physics_process(delta: float) -> void:
	refresh_awareness()
	_detail_timer -= delta
	if routine != null and _detail_timer <= 0.0:
		_detail_timer = 0.5
		var calm: bool = state in [&"idle", &"patrol", &"home", &"work", &"observe", &"wait", &"social"]
		var alerted: bool = (vision != null and (vision.has_detected_player or vision.has_last_seen_position)) or (hearing != null and hearing.has_noise_to_investigate())
		var simplify: bool = is_instance_valid(player) and global_position.distance_to(player.global_position) > 90.0 and calm and not alerted
		if simplify != _simple_routine:
			var tree: BeehaveTree = get_node("NPCBehaviorTree") as BeehaveTree
			tree.interrupt()
			tree.enabled = not simplify
			_simple_routine = simplify
	if _simple_routine:
		routine.tick(delta)
	_report_cooldown -= delta
	if routine == null or vision == null or not vision.has_detected_player:
		return
	if _report_cooldown > 0.0 or not vision.is_currently_visible:
		return
	_report_cooldown = 8.0
	# Um grito local informa apenas a posição vista; nunca confirma visão alheia.
	for listener: Node in get_tree().get_nodes_in_group(&"npc_actors"):
		var other: NPCActor = listener as NPCActor
		if other == self or other == null or other.hearing == null:
			continue
		if global_position.distance_to(other.global_position) <= 18.0:
			other.hearing.hear_report(global_position, vision.last_seen_position)


func _find_player() -> void:
	player = null
	var characters: Array[Node] = get_tree().get_nodes_in_group("characters")
	for character in characters:
		if character is CharacterBody3D and not character is NPCActor:
			player = character
			break


func _on_photo_count_changed(count: int, _maximum: int) -> void:
	_wanted_alert = count > 0 and reaction_mode == ReactionMode.CHASE
	if vision != null:
		vision.set_alerted(_wanted_alert)
	refresh_awareness()


func refresh_awareness() -> void:
	var next_state: AwarenessState = AwarenessState.NEUTRAL
	var investigating: bool = hearing != null and hearing.has_noise_to_investigate()
	if vision != null and vision.has_detected_player and vision.is_currently_visible:
		next_state = AwarenessState.PURSUIT
	elif _wanted_alert or investigating or (vision != null and (vision.is_currently_visible or vision.has_last_seen_position)):
		next_state = AwarenessState.ALERT
	if next_state == awareness_state:
		return
	awareness_state = next_state
	awareness_state_changed.emit(get_awareness_state())


func get_awareness_state() -> StringName:
	match awareness_state:
		AwarenessState.ALERT:
			return &"alert"
		AwarenessState.PURSUIT:
			return &"pursuit"
	return &"neutral"


func get_patrol_positions() -> Array[Vector3]:
	return patrol_points


func set_state(new_state: StringName) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(new_state)


## Avança um passo em direção a `point`. Retorna `true` quando chegou perto o
## bastante (`target_desired_distance` do NavigationAgent3D). Usa o caminho do
## NavigationAgent3D quando há malha bakeada contribuindo para o mapa; sem
## isso (caso do Country Town hoje), cai para ir direto ao ponto em linha
## reta, em vez de ficar parado esperando uma malha que não existe.
func move_toward_point(point: Vector3, speed: float) -> bool:
	navigation_failed = false
	if _motion_target.distance_to(point) > 1.0:
		_motion_target = point
		_stuck_time = 0.0
		_last_progress_position = global_position
		_navigation_failure_until = 0.0
	elif Time.get_ticks_msec() / 1000.0 < _navigation_failure_until:
		navigation_failed = true
		stop_moving()
		return false
	var to_point: Vector3 = point - global_position
	to_point.y = 0.0
	if to_point.length() <= navigation_agent.target_desired_distance:
		stop_moving()
		return true

	var direction: Vector3 = Vector3.ZERO
	var nav_map: RID = navigation_agent.get_navigation_map()
	var has_synced_navmesh: bool = (
		nav_map.is_valid() and NavigationServer3D.map_get_iteration_id(nav_map) != 0
	)

	if has_synced_navmesh:
		if navigation_agent.target_position.distance_to(point) > 0.05:
			navigation_agent.target_position = point
		var next_position: Vector3 = navigation_agent.get_next_path_position()
		if navigation_agent.is_navigation_finished():
			navigation_failed = true
			_navigation_failure_until = Time.get_ticks_msec() / 1000.0 + 2.0
			stop_moving()
			return false
		direction = next_position - global_position
		direction.y = 0.0
	elif require_navigation:
		navigation_failed = true
		_navigation_failure_until = Time.get_ticks_msec() / 1000.0 + 2.0
		stop_moving()
		return false

	if direction.length_squared() < 0.01:
		direction = to_point

	direction = direction.normalized()
	var desired_velocity: Vector3 = direction * speed
	if navigation_agent.avoidance_enabled:
		navigation_agent.velocity = desired_velocity
	else:
		_apply_safe_velocity(desired_velocity)
	# Velocidade pode permanecer alta enquanto o CharacterBody3D escorrega
	# contra uma parede. Mede também o deslocamento real entre tentativas.
	if _last_progress_position.distance_to(global_position) < 0.03:
		_stuck_time += get_physics_process_delta_time()
	else:
		_stuck_time = 0.0
		_last_progress_position = global_position
	if _stuck_time > 4.0:
		navigation_failed = true
		_stuck_time = 0.0
		_navigation_failure_until = Time.get_ticks_msec() / 1000.0 + 2.0
		stop_moving()
		return false
	face_direction(direction)
	if animation:
		animation.set_moving(true)
	return false


func face_direction(direction: Vector3) -> void:
	if direction.length_squared() < 0.001:
		return
	var target_angle: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(
		rotation.y, target_angle, get_physics_process_delta_time() * rotation_speed
	)


func stop_moving() -> void:
	if navigation_agent.avoidance_enabled:
		navigation_agent.velocity = Vector3.ZERO
	else:
		_apply_safe_velocity(Vector3.ZERO)
	if animation:
		animation.set_moving(false)


func _apply_safe_velocity(safe_velocity: Vector3) -> void:
	if is_dormant:
		return
	var vertical: float = velocity.y
	velocity = safe_velocity
	if grounded:
		velocity.y = -0.5 if is_on_floor() else vertical - 9.8 * get_physics_process_delta_time()
		var motion: Vector3 = Vector3(velocity.x, 0, velocity.z) * get_physics_process_delta_time()
		if is_on_floor() and motion.length_squared() > 0.000001 and test_move(global_transform, motion):
			var raised: Transform3D = global_transform
			raised.origin.y += 0.32
			if not test_move(global_transform, Vector3.UP * 0.32) and not test_move(raised, motion):
				global_position.y += 0.32
	move_and_slide()


func is_player_alive() -> bool:
	if player == null:
		return false
	if player.has_method("is_alive"):
		return bool(player.call("is_alive"))
	return true
