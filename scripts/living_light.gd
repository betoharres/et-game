class_name LivingLight
extends CharacterBody3D

## Small floating creature that uses the ship navigation mesh while expressing
## its state through steering, light, particles, squash/stretch, and the native
## Trail3D introduced in Godot 4.8 dev4.

enum State {
	WANDER,
	CURIOUS,
	SCARED,
	REST,
}

enum CuriousPhase {
	NOTICE,
	APPROACH,
	ORBIT,
}

## Vertical probe used as the height reference wherever the NavigationRegion3D
## has no baked mesh, as is the case in the farm.
const GROUND_PROBE_UP : float = 3.0
const GROUND_PROBE_DOWN : float = 80.0
const GROUND_PROBE_INTERVAL : float = 0.2

@export_category("Navigation")
@export_node_path("NavigationRegion3D") var navigation_region_path : NodePath
@export_range(0.5, 30.0, 0.1) var wander_radius : float = 5.5
@export_range(0.1, 10.0, 0.1) var minimum_wander_distance : float = 1.5
@export_range(0.2, 3.0, 0.05) var destination_tolerance : float = 0.45
@export_range(0.5, 30.0, 0.1) var destination_time_min : float = 4.0
@export_range(0.5, 30.0, 0.1) var destination_time_max : float = 8.0
@export_range(0.0, 1.5, 0.05) var hesitation_time_max : float = 0.2

@export_category("Movement")
@export_range(0.1, 10.0, 0.1) var normal_speed : float = 2.25
@export_range(0.1, 10.0, 0.1) var curious_speed : float = 1.05
@export_range(0.1, 20.0, 0.1) var scared_speed : float = 6.5
@export_range(0.1, 30.0, 0.1) var scared_burst_speed : float = 8.0
@export_range(0.1, 30.0, 0.1) var acceleration : float = 4.8
@export_range(0.1, 50.0, 0.1) var scared_acceleration : float = 16.0
@export_range(0.0, 3.0, 0.05) var hover_height : float = 1.25
@export_range(0.5, 50.0, 0.5) var maximum_height_above_navigation : float = 3.0
@export_range(0.0, 1.0, 0.01) var bob_intensity : float = 0.12
@export_range(0.1, 10.0, 0.1) var bob_frequency : float = 1.5
@export_range(0.0, 1.0, 0.01) var lateral_motion_intensity : float = 0.18
@export_range(0.1, 10.0, 0.1) var lateral_motion_frequency : float = 2.2
@export_range(0.1, 10.0, 0.1) var vertical_follow_speed : float = 4.0

@export_category("Personality")
@export_range(0.5, 20.0, 0.1) var player_perception_distance : float = 7.0
@export_range(0.2, 15.0, 0.1) var minimum_player_distance : float = 5.5
@export_range(0.1, 20.0, 0.1) var rapid_approach_speed : float = 3.4
@export_range(1.0, 20.0, 0.5) var flee_step_distance : float = 8.0
@export_range(0.0, 1.0, 0.01) var curiosity_chance : float = 0.65
@export_range(0.0, 3.0, 0.05) var notice_time : float = 0.55
@export_range(0.5, 5.0, 0.1) var curious_approach_distance : float = 1.8
@export_range(0.5, 5.0, 0.1) var orbit_radius : float = 1.45
@export_range(1.0, 20.0, 0.1) var orbit_time : float = 5.0
@export_range(0.5, 10.0, 0.1) var scared_time : float = 2.8
@export_range(0.0, 20.0, 0.1) var player_interest_cooldown : float = 5.0
@export_range(0.0, 1.0, 0.01) var rest_chance : float = 0.08
@export_range(0.5, 20.0, 0.1) var rest_time_min : float = 1.5
@export_range(0.5, 20.0, 0.1) var rest_time_max : float = 3.0
@export var rest_marker_group : StringName = &"living_light_rest_points"

@export_category("Light and particles")
@export var light_color : Color = Color(1.0, 0.78, 0.36, 1.0)
@export_range(0.0, 16.0, 0.1) var light_intensity : float = 1.8
@export_range(0.1, 8.0, 0.05) var core_energy : float = 1.9
@export_range(0.0, 3.0, 0.01) var halo_size_min : float = 0.42
@export_range(0.0, 3.0, 0.01) var halo_size_max : float = 0.85
@export_range(0.0, 8.0, 0.05) var halo_energy : float = 1.35
@export_range(0.0, 1.0, 0.01) var flicker_amount : float = 0.22
@export_range(0.1, 10.0, 0.1) var flicker_speed : float = 2.6
@export_range(0.0, 1.0, 0.01) var rest_pulse_amount : float = 0.22
@export_range(0.1, 10.0, 0.1) var rest_pulse_frequency : float = 1.4
@export_range(0.0, 1.0, 0.01) var wisp_amount_idle : float = 0.5
@export_range(0.0, 1.0, 0.01) var wisp_amount_scared : float = 1.0
@export_range(0.1, 20.0, 0.1) var spark_interval_min : float = 1.2
@export_range(0.1, 20.0, 0.1) var spark_interval_max : float = 3.2

@export_category("Trail3D (Godot 4.8)")
@export var trail_color : Color = Color(1.0, 0.86, 0.4, 0.85)
@export var trail_head_color : Color = Color(1.0, 0.95, 0.62, 1.0)
@export var trail_tail_color : Color = Color(0.42, 0.95, 0.35, 0.0)
@export_range(0.01, 3.0, 0.01) var trail_slow_lifetime : float = 0.16
@export_range(0.01, 3.0, 0.01) var trail_fast_lifetime : float = 0.62
@export_range(0.01, 3.0, 0.01) var trail_scared_lifetime : float = 1.05
@export_range(0.01, 1.0, 0.01) var trail_width_min : float = 0.05
@export_range(0.01, 1.0, 0.01) var trail_width_max : float = 0.16
@export_range(0.05, 1.0, 0.01) var trail_min_section_length : float = 0.06
@export_range(0.1, 30.0, 0.1) var trail_response_speed : float = 7.0
@export_range(0.0, 4.0, 0.05) var trail_flow_speed : float = 0.75
@export_range(0.0, 1.0, 0.01) var trail_noise_strength : float = 0.45
@export_range(0.5, 6.0, 0.1) var trail_edge_softness : float = 2.1
@export_range(0.05, 1.0, 0.01) var trail_core_width_ratio : float = 0.38
@export_range(0.05, 1.0, 0.01) var trail_core_lifetime_ratio : float = 0.55

@export_category("Squash and stretch")
@export_range(0.0, 1.0, 0.01) var speed_stretch : float = 0.28
@export_range(0.0, 1.0, 0.01) var braking_squash : float = 0.16
@export_range(0.0, 1.0, 0.01) var turning_squash : float = 0.12
@export_range(0.1, 30.0, 0.1) var squash_response_speed : float = 9.0

@export_category("Debug")
@export var debug_enabled : bool = false

@onready var navigation_agent : NavigationAgent3D = $NavigationAgent3D
@onready var visual_root : Node3D = $VisualRoot
@onready var core_mesh : MeshInstance3D = $VisualRoot/Core
@onready var halo_mesh : MeshInstance3D = $Halo
@onready var glow_light : OmniLight3D = $GlowLight
@onready var sparks : GPUParticles3D = $Sparks
@onready var wisps : GPUParticles3D = $Wisps
@onready var trail : Trail3D = $Trail3D
@onready var trail_core : Trail3D = $TrailCore
@onready var debug_mesh : MeshInstance3D = $Debug/Lines
@onready var debug_label : Label3D = $Debug/StateLabel

var current_state : State = State.WANDER

var _curious_phase : CuriousPhase = CuriousPhase.NOTICE
var _player : CharacterBody3D = null
var _navigation_region : NavigationRegion3D = null
var _navigation_space : Node3D = null
var _rng : RandomNumberGenerator = RandomNumberGenerator.new()
var _wander_origin_local : Vector3 = Vector3.ZERO
var _target_local : Vector3 = Vector3.ZERO
var _has_target : bool = false
var _desired_velocity : Vector3 = Vector3.ZERO
var _destination_time : float = 0.0
var _state_time : float = 0.0
var _hesitation_time : float = 0.0
var _interest_cooldown : float = 0.0
var _interest_check_time : float = 0.0
var _player_search_time : float = 0.0
var _motion_time : float = 0.0
var _orbit_angle : float = 0.0
var _orbit_direction : float = 1.0
var _orbit_repath_time : float = 0.0
var _flee_repath_time : float = 0.0
var _rest_arrived : bool = false
var _stationary_position_local : Vector3 = Vector3.ZERO
var _spark_time : float = 0.0
var _ground_probe_time : float = 0.0
var _ground_surface_y : float = 0.0
var _has_ground_surface : bool = false
var _progress_time : float = 0.0
var _progress_position_local : Vector3 = Vector3.ZERO
var _previous_motion_position_local : Vector3 = Vector3.ZERO
var _previous_motion_global_position : Vector3 = Vector3.ZERO
var _measured_local_velocity : Vector3 = Vector3.ZERO
var _measured_world_speed : float = 0.0
var _previous_speed : float = 0.0
var _previous_direction : Vector3 = Vector3.FORWARD
var _core_material : StandardMaterial3D = null
var _core_alpha : float = 1.0
var _halo_material : StandardMaterial3D = null
var _trail_material : ShaderMaterial = null
var _trail_core_material : ShaderMaterial = null
var _trail_energy : float = 1.0
var _flicker_noise : FastNoiseLite = FastNoiseLite.new()
var _trail_emitting : bool = false
var _trail_lifetime : float = 0.0
var _trail_width : float = 0.0
var _debug_immediate : ImmediateMesh = null
var _debug_material : StandardMaterial3D = null


func _ready() -> void:
	_rng.randomize()
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_navigation_space = get_parent() as Node3D
	_navigation_region = get_node_or_null(navigation_region_path) as NavigationRegion3D
	_wander_origin_local = (
		_navigation_space.to_local(global_position)
		if _navigation_space != null
		else global_position
	)
	_remember_stationary_position()
	_progress_position_local = _get_navigation_local_position()
	_previous_motion_position_local = _progress_position_local
	_previous_motion_global_position = global_position
	navigation_agent.path_desired_distance = maxf(destination_tolerance, 0.2)
	navigation_agent.target_desired_distance = destination_tolerance
	# NavigationAgent3D subtracts this offset from every path point, so it has to
	# be negative for the path to sit above the navigation surface.
	navigation_agent.path_height_offset = -hover_height
	_flicker_noise.seed = _rng.randi()
	_flicker_noise.frequency = 0.6
	_setup_core_material()
	_setup_halo()
	_setup_trail()
	_setup_debug_draw()
	_find_player()
	_spark_time = _random_range(spark_interval_min, spark_interval_max)
	_hesitation_time = _random_range(0.0, hesitation_time_max)
	_set_debug_visible(debug_enabled)


func _physics_process(delta : float) -> void:
	_motion_time += delta
	_interest_cooldown = maxf(_interest_cooldown - delta, 0.0)
	_interest_check_time = maxf(_interest_check_time - delta, 0.0)
	_player_search_time = maxf(_player_search_time - delta, 0.0)
	_update_ground_probe(delta)
	_refresh_player_if_needed()
	_update_player_reactions()

	_desired_velocity = Vector3.ZERO
	match current_state:
		State.WANDER:
			_update_wander(delta)
		State.CURIOUS:
			_update_curious(delta)
		State.SCARED:
			_update_scared(delta)
		State.REST:
			_update_rest(delta)

	var active_acceleration : float = (
		scared_acceleration if current_state == State.SCARED else acceleration
	)
	velocity = velocity.move_toward(_desired_velocity, active_acceleration * delta)
	var maximum_speed : float = (
		scared_burst_speed if current_state == State.SCARED else scared_speed
	)
	if velocity.length() > maximum_speed:
		velocity = velocity.normalized() * maximum_speed

	move_and_slide()
	_enforce_maximum_height()
	_measure_relative_motion(delta)
	_update_stuck_detection(delta)
	_update_visual_language(delta)
	_update_sparks(delta)
	_update_debug_draw()


func _update_wander(delta : float) -> void:
	if _hesitation_time > 0.0:
		_hesitation_time = maxf(_hesitation_time - delta, 0.0)
		_desired_velocity = _stationary_hover_velocity(bob_intensity * 0.65)
		return

	if not _has_target:
		if not _choose_wander_target():
			_desired_velocity = _stationary_hover_velocity(bob_intensity)
			return

	_destination_time = maxf(_destination_time - delta, 0.0)
	if _destination_reached():
		if _rng.randf() <= rest_chance and _start_rest():
			return
		_prepare_new_wander_direction()
		return
	if _destination_time <= 0.0:
		_prepare_new_wander_direction()
		return

	_desired_velocity = _navigation_velocity(normal_speed, 1.0)


func _update_curious(delta : float) -> void:
	if _player == null:
		_enter_wander()
		return

	match _curious_phase:
		CuriousPhase.NOTICE:
			_state_time = maxf(_state_time - delta, 0.0)
			_desired_velocity = _stationary_hover_velocity(bob_intensity * 0.35)
			if _state_time <= 0.0:
				_curious_phase = CuriousPhase.APPROACH
				_state_time = 4.0
				_set_target(_curious_approach_point())
		CuriousPhase.APPROACH:
			_state_time = maxf(_state_time - delta, 0.0)
			_set_target(_curious_approach_point())
			_desired_velocity = _navigation_velocity(curious_speed, 0.35)
			var player_distance : float = global_position.distance_to(
				_player.global_position
			)
			if (
				player_distance <= curious_approach_distance + 0.45
				or _state_time <= 0.0
			):
				_begin_orbit()
		CuriousPhase.ORBIT:
			_state_time = maxf(_state_time - delta, 0.0)
			_orbit_repath_time = maxf(_orbit_repath_time - delta, 0.0)
			_orbit_angle += _orbit_direction * TAU * delta / maxf(orbit_time, 0.1)
			if _orbit_repath_time <= 0.0:
				_set_target(_orbit_point())
				_orbit_repath_time = 0.18
			_desired_velocity = _navigation_velocity(curious_speed, 0.55)
			if _state_time <= 0.0:
				_interest_cooldown = player_interest_cooldown
				_enter_wander()


func _update_scared(delta : float) -> void:
	_state_time = maxf(_state_time - delta, 0.0)
	_flee_repath_time = maxf(_flee_repath_time - delta, 0.0)
	if _player != null:
		var player_offset : Vector3 = global_position - _player.global_position
		player_offset.y = 0.0
		if player_offset.length() <= player_perception_distance:
			_state_time = scared_time
	if _flee_repath_time <= 0.0 or not _has_target or _destination_reached():
		_choose_flee_target()
		_flee_repath_time = 0.2
	_desired_velocity = _navigation_velocity(scared_speed, 2.0)
	if _state_time <= 0.0:
		_interest_cooldown = player_interest_cooldown
		_enter_wander()


func _update_rest(delta : float) -> void:
	if not _rest_arrived:
		if _destination_reached():
			_rest_arrived = true
			_remember_stationary_position()
			_state_time = _random_range(rest_time_min, rest_time_max)
		else:
			_desired_velocity = _navigation_velocity(curious_speed * 0.75, 0.25)
		return

	_state_time = maxf(_state_time - delta, 0.0)
	_desired_velocity = _stationary_hover_velocity(bob_intensity * 0.55)
	if _state_time <= 0.0:
		_enter_wander()


func _update_player_reactions() -> void:
	if _player == null:
		return
	var offset_from_player : Vector3 = global_position - _player.global_position
	var player_distance : float = offset_from_player.length()
	var approach_speed : float = 0.0
	if player_distance > 0.001:
		approach_speed = _player.velocity.dot(offset_from_player / player_distance)

	if (
		current_state != State.SCARED
		and (
			player_distance <= minimum_player_distance
			or (
				player_distance <= player_perception_distance
				and approach_speed >= rapid_approach_speed
			)
		)
	):
		_start_scared(offset_from_player)
		return

	if (
		(current_state == State.WANDER or current_state == State.REST)
		and _interest_cooldown <= 0.0
		and _interest_check_time <= 0.0
		and player_distance <= player_perception_distance
	):
		_interest_check_time = 1.5
		if _rng.randf() <= curiosity_chance:
			_start_curious()


func _start_curious() -> void:
	current_state = State.CURIOUS
	_curious_phase = CuriousPhase.NOTICE
	_state_time = notice_time
	_remember_stationary_position()
	_clear_target()


func _begin_orbit() -> void:
	if _player == null:
		_enter_wander()
		return
	_curious_phase = CuriousPhase.ORBIT
	_state_time = orbit_time
	_orbit_repath_time = 0.0
	var relative : Vector3 = global_position - _player.global_position
	_orbit_angle = atan2(relative.z, relative.x)
	_orbit_direction = -1.0 if _rng.randi_range(0, 1) == 0 else 1.0


func _start_scared(offset_from_player : Vector3) -> void:
	current_state = State.SCARED
	_state_time = scared_time
	_flee_repath_time = 0.0
	_hesitation_time = 0.0
	var away : Vector3 = offset_from_player
	away.y = 0.0
	if away.length_squared() <= 0.001:
		away = Vector3.RIGHT.rotated(Vector3.UP, _rng.randf_range(-PI, PI))
	away = away.normalized()
	velocity = away * scared_burst_speed + Vector3.UP * 0.45
	_choose_flee_target()
	sparks.restart()


func _start_rest() -> bool:
	var markers : Array[Node] = get_tree().get_nodes_in_group(rest_marker_group)
	var candidates : Array[Vector3] = []
	for marker_node : Node in markers:
		if marker_node is not Node3D:
			continue
		var marker : Node3D = marker_node as Node3D
		var projected : Vector3 = _project_to_navigation(marker.global_position)
		if _is_point_inside_wander_area(projected):
			candidates.append(projected)
	if candidates.is_empty():
		return false

	current_state = State.REST
	_rest_arrived = false
	_state_time = 0.0
	_set_target(candidates[_rng.randi_range(0, candidates.size() - 1)])
	return true


func _enter_wander() -> void:
	current_state = State.WANDER
	_rest_arrived = false
	_remember_stationary_position()
	_prepare_new_wander_direction()


func _prepare_new_wander_direction() -> void:
	_clear_target()
	_hesitation_time = _random_range(0.08, hesitation_time_max)
	_remember_stationary_position()


func _choose_wander_target() -> bool:
	if not _navigation_is_ready() and not _has_ground_surface:
		return false
	var selected : Vector3 = Vector3.ZERO
	var found : bool = false
	for attempt : int in range(16):
		var candidate : Vector3 = _sample_wander_point(minimum_wander_distance)
		var horizontal_offset : Vector3 = candidate - global_position
		horizontal_offset.y = 0.0
		if (
			_is_point_inside_wander_area(candidate)
			and (
				horizontal_offset.length() >= minimum_wander_distance
				or attempt == 15
			)
		):
			selected = candidate
			found = true
			break
	if not found:
		return false
	_set_target(selected)
	_destination_time = _random_range(destination_time_min, destination_time_max)
	return true


func _choose_flee_target() -> bool:
	if not _navigation_is_ready() and not _has_ground_surface:
		return false
	if _player == null:
		var fallback : Vector3 = _sample_wander_point(minimum_wander_distance)
		_set_target(fallback)
		return true
	var away_from_player : Vector3 = global_position - _player.global_position
	away_from_player.y = 0.0
	if away_from_player.length_squared() <= 0.001:
		away_from_player = Vector3.RIGHT.rotated(
			Vector3.UP,
			_rng.randf_range(-PI, PI)
		)
	away_from_player = away_from_player.normalized()
	var best_point : Vector3 = Vector3.ZERO
	var best_score : float = -INF
	var found : bool = false
	for attempt : int in range(16):
		var direction : Vector3 = away_from_player.rotated(
			Vector3.UP,
			_rng.randf_range(-0.7, 0.7)
		)
		var desired : Vector3 = global_position + direction * _random_range(
			flee_step_distance * 0.75,
			flee_step_distance * 1.25
		)
		var candidate : Vector3 = _project_to_navigation(desired)
		var travel : Vector3 = candidate - global_position
		travel.y = 0.0
		if travel.length() < minimum_wander_distance * 0.5:
			continue
		var alignment : float = travel.normalized().dot(away_from_player)
		var score : float = candidate.distance_squared_to(_player.global_position)
		score += alignment * flee_step_distance * flee_step_distance * 2.0
		if score > best_score:
			best_score = score
			best_point = candidate
			found = true
	if not found:
		return false
	_set_target(best_point)
	return true


func _curious_approach_point() -> Vector3:
	if _player == null:
		return global_position
	var away : Vector3 = global_position - _player.global_position
	away.y = 0.0
	if away.length_squared() <= 0.001:
		away = Vector3.RIGHT
	var desired : Vector3 = (
		_player.global_position + away.normalized() * curious_approach_distance
	)
	return _project_to_navigation(desired)


func _orbit_point() -> Vector3:
	if _player == null:
		return global_position
	var orbit_offset : Vector3 = Vector3(
		cos(_orbit_angle) * orbit_radius,
		0.0,
		sin(_orbit_angle) * orbit_radius
	)
	return _project_to_navigation(_player.global_position + orbit_offset)


func _navigation_velocity(speed : float, lateral_multiplier : float) -> Vector3:
	if not _has_target:
		return _stationary_hover_velocity(bob_intensity)
	var target : Vector3 = _get_target()
	# With no baked mesh the agent has no path and hands back the creature's own
	# position, which turns the vertical control into an integrator with no
	# reference and makes it climb forever. There, steer straight at the
	# destination and hover over the probed ground instead.
	var next_position : Vector3 = target
	var hover_offset : float = hover_height
	if _navigation_is_ready():
		navigation_agent.target_position = target
		next_position = navigation_agent.get_next_path_position()
		hover_offset = 0.0
	var current_local : Vector3 = _get_navigation_local_position()
	var next_local : Vector3 = _to_navigation_local(next_position)
	var target_local : Vector3 = _to_navigation_local(target)
	var horizontal_local : Vector3 = next_local - current_local
	horizontal_local.y = 0.0
	if horizontal_local.length_squared() <= 0.0001:
		horizontal_local = target_local - current_local
		horizontal_local.y = 0.0
	if horizontal_local.length_squared() <= 0.0001:
		return _stationary_hover_velocity(bob_intensity)

	var forward_local : Vector3 = horizontal_local.normalized()
	var side_local : Vector3 = Vector3(-forward_local.z, 0.0, forward_local.x)
	var lateral_wave : float = sin(
		_motion_time * lateral_motion_frequency + float(get_instance_id() % 31)
	)
	var steering_local : Vector3 = (
		forward_local
		+ side_local * lateral_wave * lateral_motion_intensity * lateral_multiplier
	).normalized()
	var bob_offset : float = sin(_motion_time * bob_frequency * TAU) * bob_intensity
	var desired_local_height : float = next_local.y + hover_offset + bob_offset
	var vertical_speed_local : float = clampf(
		(desired_local_height - current_local.y) * vertical_follow_speed,
		-speed,
		speed
	)
	var desired_local_velocity : Vector3 = (
		steering_local * speed + Vector3.UP * vertical_speed_local
	)
	return _navigation_local_direction_to_global(desired_local_velocity)


func _stationary_hover_velocity(amplitude : float) -> Vector3:
	var stationary_world : Vector3 = (
		_navigation_space.to_global(_stationary_position_local)
		if _navigation_space != null
		else _stationary_position_local
	)
	var desired_height : float = (
		stationary_world.y + sin(_motion_time * bob_frequency * TAU) * amplitude
	)
	return Vector3.UP * clampf(
		(desired_height - global_position.y) * vertical_follow_speed,
		-1.0,
		1.0
	)


func _remember_stationary_position() -> void:
	_stationary_position_local = _get_navigation_local_position()


func _get_navigation_local_position() -> Vector3:
	return _to_navigation_local(global_position)


func _to_navigation_local(world_position : Vector3) -> Vector3:
	if _navigation_space != null:
		return _navigation_space.to_local(world_position)
	return world_position


func _navigation_local_direction_to_global(local_direction : Vector3) -> Vector3:
	if _navigation_space == null:
		return local_direction
	return _navigation_space.global_basis.orthonormalized() * local_direction


func _enforce_maximum_height() -> void:
	if not _navigation_is_ready() and not _has_ground_surface:
		return
	var navigation_surface_world : Vector3 = _project_to_navigation(global_position)
	var current_local : Vector3 = _to_navigation_local(global_position)
	var navigation_surface_local : Vector3 = _to_navigation_local(
		navigation_surface_world
	)
	var maximum_local_y : float = (
		navigation_surface_local.y + maximum_height_above_navigation
	)
	if current_local.y <= maximum_local_y:
		return
	current_local.y = maximum_local_y
	global_position = (
		_navigation_space.to_global(current_local)
		if _navigation_space != null
		else current_local
	)
	var local_velocity : Vector3 = velocity
	if _navigation_space != null:
		local_velocity = (
			_navigation_space.global_basis.orthonormalized().inverse() * velocity
		)
	local_velocity.y = minf(local_velocity.y, 0.0)
	velocity = _navigation_local_direction_to_global(local_velocity)


func _set_target(world_position : Vector3) -> void:
	if _navigation_space != null:
		_target_local = _navigation_space.to_local(world_position)
	else:
		_target_local = world_position
	_has_target = true
	navigation_agent.target_position = world_position


func _get_target() -> Vector3:
	if _navigation_space != null:
		return _navigation_space.to_global(_target_local)
	return _target_local


func _clear_target() -> void:
	_has_target = false


func _destination_reached() -> bool:
	if not _has_target:
		return true
	var offset : Vector3 = _get_target() - global_position
	offset.y = 0.0
	return offset.length() <= destination_tolerance


func _navigation_is_ready() -> bool:
	if _navigation_region == null:
		return false
	# A region whose mesh was never baked still answers queries, but every
	# closest point comes back as the world origin, which would drag both the
	# destinations and the height ceiling there.
	var navigation_mesh : NavigationMesh = _navigation_region.navigation_mesh
	if navigation_mesh == null or navigation_mesh.get_polygon_count() == 0:
		return false
	var navigation_map : RID = navigation_agent.get_navigation_map()
	return (
		navigation_map.is_valid()
		and NavigationServer3D.map_get_iteration_id(navigation_map) > 0
	)


func _sample_wander_point(minimum_distance : float = 0.0) -> Vector3:
	var angle : float = _rng.randf_range(0.0, TAU)
	var sample_distance : float = _rng.randf_range(
		minf(minimum_distance, wander_radius),
		wander_radius
	)
	var candidate_local : Vector3 = _wander_origin_local + Vector3(
		cos(angle) * sample_distance,
		0.0,
		sin(angle) * sample_distance
	)
	var candidate_world : Vector3 = (
		_navigation_space.to_global(candidate_local)
		if _navigation_space != null
		else candidate_local
	)
	return _project_to_navigation(candidate_world)


func _project_to_navigation(world_position : Vector3) -> Vector3:
	if _navigation_is_ready():
		var navigation_map : RID = navigation_agent.get_navigation_map()
		if navigation_map.is_valid():
			return NavigationServer3D.map_get_closest_point(
				navigation_map,
				world_position
			)
	if _has_ground_surface:
		return Vector3(world_position.x, _ground_surface_y, world_position.z)
	return world_position


func _update_ground_probe(delta : float) -> void:
	_ground_probe_time = maxf(_ground_probe_time - delta, 0.0)
	if _ground_probe_time > 0.0:
		return
	_ground_probe_time = GROUND_PROBE_INTERVAL
	var space_state : PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return
	var query : PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * GROUND_PROBE_UP,
		global_position + Vector3.DOWN * GROUND_PROBE_DOWN,
		collision_mask,
		[get_rid()]
	)
	query.collide_with_areas = false
	var hit : Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_ground_surface_y = (hit["position"] as Vector3).y
	_has_ground_surface = true


func _is_point_inside_wander_area(world_position : Vector3) -> bool:
	var local_position : Vector3 = (
		_navigation_space.to_local(world_position)
		if _navigation_space != null
		else world_position
	)
	var offset : Vector3 = local_position - _wander_origin_local
	offset.y = 0.0
	return offset.length() <= wander_radius


func _update_stuck_detection(delta : float) -> void:
	if not _has_target or _desired_velocity.length_squared() < 0.04:
		_progress_time = 0.0
		_progress_position_local = _get_navigation_local_position()
		return
	_progress_time += delta
	if _progress_time < 1.25:
		return
	var current_local : Vector3 = _get_navigation_local_position()
	var progress : Vector3 = current_local - _progress_position_local
	progress.y = 0.0
	_progress_time = 0.0
	_progress_position_local = current_local
	if progress.length() >= 0.12:
		return
	if current_state == State.SCARED:
		_choose_flee_target()
	elif current_state == State.CURIOUS:
		_set_target(_project_to_navigation(_get_target()))
	else:
		_prepare_new_wander_direction()


func _setup_core_material() -> void:
	var source : StandardMaterial3D = core_mesh.material_override as StandardMaterial3D
	if source == null:
		return
	_core_material = source.duplicate() as StandardMaterial3D
	core_mesh.material_override = _core_material
	# The core and the halo are unshaded, and an unshaded StandardMaterial3D
	# outputs albedo alone: its emission is never added, so the pulse has to ride
	# on an HDR albedo instead. That is also what pushes the glow pass.
	_core_alpha = _core_material.albedo_color.a
	_apply_core_energy(1.0)
	glow_light.light_color = light_color


func _setup_halo() -> void:
	var source : StandardMaterial3D = halo_mesh.material_override as StandardMaterial3D
	if source == null:
		return
	_halo_material = source.duplicate() as StandardMaterial3D
	halo_mesh.material_override = _halo_material
	halo_mesh.scale = Vector3.ONE * halo_size_min
	_apply_halo_energy(1.0)


func _apply_core_energy(energy : float) -> void:
	if _core_material == null:
		return
	var amount : float = core_energy * energy
	_core_material.albedo_color = Color(
		light_color.r * amount,
		light_color.g * amount,
		light_color.b * amount,
		_core_alpha
	)


func _apply_halo_energy(energy : float) -> void:
	if _halo_material == null:
		return
	var amount : float = halo_energy * energy
	_halo_material.albedo_color = Color(
		light_color.r * amount,
		light_color.g * amount,
		light_color.b * amount,
		1.0
	)


func _setup_trail() -> void:
	# Trail3D samples width_curve and color_gradient with ratio 0 on the creature
	# and ratio 1 on the oldest point, so the ribbon swells right behind the core
	# and tapers into nothing at the tail.
	var width_curve : Curve = Curve.new()
	width_curve.min_value = 0.0
	width_curve.max_value = 1.0
	width_curve.add_point(Vector2(0.0, 0.55))
	width_curve.add_point(Vector2(0.18, 1.0))
	width_curve.add_point(Vector2(1.0, 0.0))

	var body_gradient : Gradient = Gradient.new()
	body_gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	body_gradient.colors = PackedColorArray([
		trail_head_color,
		trail_color,
		trail_tail_color,
	])
	_apply_trail_shape(trail, body_gradient, width_curve)

	var core_gradient : Gradient = Gradient.new()
	core_gradient.offsets = PackedFloat32Array([0.0, 1.0])
	core_gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	_apply_trail_shape(trail_core, core_gradient, width_curve)

	# Trail3D packs the vertex color as RGBA8, so trail.color alone can never go
	# overbright. The custom shader is what carries the intensity, and each ribbon
	# drives its own copy of the material that comes from the scene.
	var shared_material : ShaderMaterial = trail.material
	if shared_material != null:
		_trail_material = shared_material.duplicate() as ShaderMaterial
		trail.material = _trail_material
		_trail_material.set_shader_parameter(&"flow_speed", trail_flow_speed)
		_trail_material.set_shader_parameter(&"noise_strength", trail_noise_strength)
		_trail_material.set_shader_parameter(&"edge_softness", trail_edge_softness)
		_trail_material.set_shader_parameter(&"flare_color", trail_head_color)

		# The inner ribbon runs the same shader with a tighter, less noisy and
		# whiter profile, which is what reads as the hot core of the creature.
		_trail_core_material = shared_material.duplicate() as ShaderMaterial
		trail_core.material = _trail_core_material
		_trail_core_material.set_shader_parameter(&"flow_speed", trail_flow_speed * 1.4)
		_trail_core_material.set_shader_parameter(
			&"noise_strength",
			trail_noise_strength * 0.35
		)
		_trail_core_material.set_shader_parameter(
			&"edge_softness",
			maxf(trail_edge_softness * 0.6, 0.5)
		)
		_trail_core_material.set_shader_parameter(&"flare_color", Color(1.0, 1.0, 1.0, 1.0))

	trail.lifetime = trail_slow_lifetime
	trail.width = trail_width_min
	trail.color = trail_color
	trail_core.lifetime = trail_slow_lifetime * trail_core_lifetime_ratio
	trail_core.width = trail_width_min * trail_core_width_ratio
	trail_core.color = trail_head_color
	_trail_lifetime = trail_slow_lifetime
	_trail_width = trail_width_min
	_set_trail_emitting(false)


func _apply_trail_shape(
	target : Trail3D,
	gradient : Gradient,
	width_curve : Curve
) -> void:
	target.limit_mode = Trail3D.LIMIT_MODE_LIFETIME
	target.mesh_alignment = Line3D.MESH_ALIGNMENT_BILLBOARD
	target.min_section_length = trail_min_section_length
	target.color_gradient = gradient
	target.width_curve = width_curve


func _measure_relative_motion(delta : float) -> void:
	var current_local : Vector3 = _get_navigation_local_position()
	_measured_local_velocity = (
		current_local - _previous_motion_position_local
	) / maxf(delta, 0.001)
	_measured_world_speed = global_position.distance_to(
		_previous_motion_global_position
	) / maxf(delta, 0.001)
	_previous_motion_position_local = current_local
	_previous_motion_global_position = global_position


func _update_visual_language(delta : float) -> void:
	var speed : float = Vector2(
		_measured_local_velocity.x,
		_measured_local_velocity.z
	).length()
	var speed_ratio : float = clampf(speed / maxf(normal_speed, 0.1), 0.0, 1.5)
	var movement_direction : Vector3 = _navigation_local_direction_to_global(
		_measured_local_velocity
	)
	movement_direction.y = 0.0
	var turn_amount : float = 0.0
	if movement_direction.length_squared() > 0.001:
		movement_direction = movement_direction.normalized()
		turn_amount = 1.0 - clampf(_previous_direction.dot(movement_direction), -1.0, 1.0)
		_previous_direction = movement_direction
		visual_root.look_at(
			visual_root.global_position + movement_direction,
			Vector3.UP,
			true
		)

	var speed_change : float = (speed - _previous_speed) / maxf(delta, 0.001)
	var longitudinal : float = 1.0 + minf(speed_ratio, 1.0) * speed_stretch
	if speed_change < -0.2:
		longitudinal -= minf(absf(speed_change) * 0.025, braking_squash)
	longitudinal -= minf(turn_amount * turning_squash, turning_squash)
	longitudinal = clampf(longitudinal, 0.72, 1.4)
	var transverse : float = 1.0 / sqrt(longitudinal)
	var target_scale : Vector3 = Vector3(transverse, transverse, longitudinal)
	visual_root.scale = visual_root.scale.lerp(
		target_scale,
		clampf(delta * squash_response_speed, 0.0, 1.0)
	)
	_previous_speed = speed

	var pulse : float = _flicker_value()
	if current_state == State.REST and _rest_arrived:
		pulse += sin(_motion_time * rest_pulse_frequency * TAU) * rest_pulse_amount
	elif current_state == State.SCARED:
		pulse *= 1.45
	glow_light.light_energy = light_intensity * pulse
	_apply_core_energy(pulse)
	_update_halo(delta, speed_ratio, pulse)

	_update_trail(delta, speed, _measured_world_speed)


func _flicker_value() -> float:
	# A firefly never sits on a clean sine: a slow breath plus low frequency noise
	# keeps the glow alive without reading as a blinking lamp.
	var breath : float = sin(_motion_time * 0.9) * 0.4
	var wobble : float = _flicker_noise.get_noise_1d(_motion_time * flicker_speed)
	return maxf(1.0 + (breath + wobble) * flicker_amount, 0.05)


func _update_halo(delta : float, speed_ratio : float, pulse : float) -> void:
	if _halo_material == null:
		return
	var target_size : float = lerpf(
		halo_size_min,
		halo_size_max,
		clampf(speed_ratio, 0.0, 1.0)
	)
	if current_state == State.SCARED:
		target_size = halo_size_max
	halo_mesh.scale = halo_mesh.scale.lerp(
		Vector3.ONE * target_size * pulse,
		clampf(delta * squash_response_speed * 0.5, 0.0, 1.0)
	)
	_apply_halo_energy(pulse)


func _update_trail(delta : float, speed : float, world_speed : float) -> void:
	var movement_ratio : float = clampf(speed / maxf(scared_speed, 0.1), 0.0, 1.0)
	var target_lifetime : float = lerpf(
		trail_slow_lifetime,
		trail_fast_lifetime,
		clampf(speed / maxf(normal_speed, 0.1), 0.0, 1.0)
	)
	var target_width : float = lerpf(trail_width_min, trail_width_max, movement_ratio)
	var target_alpha : float = lerpf(0.25, trail_color.a, movement_ratio)
	var target_energy : float = lerpf(0.85, 1.5, movement_ratio)
	if current_state == State.SCARED:
		target_lifetime = trail_scared_lifetime
		target_width = trail_width_max
		target_alpha = trail_color.a
		target_energy = 2.1
	# Trail3D stores its points in world space. The ship rotates around a distant
	# pivot, so its inherited tangential speed can otherwise dwarf the creature's
	# actual motion inside the room and make the trail look externally dragged.
	if speed > 0.01 and world_speed > speed:
		target_lifetime *= clampf(speed / world_speed, 0.12, 1.0)
	var response : float = clampf(delta * trail_response_speed, 0.0, 1.0)
	_trail_lifetime = lerpf(_trail_lifetime, target_lifetime, response)
	_trail_width = lerpf(_trail_width, target_width, response)
	_trail_energy = lerpf(_trail_energy, target_energy, response)
	trail.lifetime = _trail_lifetime
	trail.width = _trail_width
	trail_core.lifetime = _trail_lifetime * trail_core_lifetime_ratio
	trail_core.width = _trail_width * trail_core_width_ratio
	var runtime_color : Color = trail_color
	runtime_color.a = target_alpha
	trail.color = runtime_color
	trail_core.color = Color(
		trail_head_color.r,
		trail_head_color.g,
		trail_head_color.b,
		target_alpha * trail_head_color.a
	)
	if _trail_material != null:
		_trail_material.set_shader_parameter(&"energy", _trail_energy)
	if _trail_core_material != null:
		_trail_core_material.set_shader_parameter(&"energy", _trail_energy * 1.6)
	_set_trail_emitting(speed > 0.12 and not (current_state == State.REST and _rest_arrived))


func _set_trail_emitting(emitting : bool) -> void:
	if _trail_emitting == emitting:
		return
	_trail_emitting = emitting
	trail.emitting = emitting
	trail_core.emitting = emitting
	if not emitting:
		trail.clear()
		trail_core.clear()


func _update_sparks(delta : float) -> void:
	_update_wisps(delta)
	_spark_time = maxf(_spark_time - delta, 0.0)
	if _spark_time > 0.0:
		return
	sparks.restart()
	var interval_scale : float = 0.45 if current_state == State.SCARED else 1.0
	_spark_time = _random_range(spark_interval_min, spark_interval_max) * interval_scale


func _update_wisps(delta : float) -> void:
	# Small motes stay around the creature all the time; the state only changes
	# how many of them are alive, which is cheaper than restarting the emitter.
	if not wisps.emitting:
		wisps.emitting = true
	var target_ratio : float = wisp_amount_idle
	if current_state == State.SCARED:
		target_ratio = wisp_amount_scared
	elif current_state == State.REST and _rest_arrived:
		target_ratio = wisp_amount_idle * 0.45
	wisps.amount_ratio = lerpf(
		wisps.amount_ratio,
		clampf(target_ratio, 0.0, 1.0),
		clampf(delta * 3.0, 0.0, 1.0)
	)


func _setup_debug_draw() -> void:
	_debug_immediate = ImmediateMesh.new()
	debug_mesh.mesh = _debug_immediate
	_debug_material = StandardMaterial3D.new()
	_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_material.vertex_color_use_as_albedo = true
	_debug_material.albedo_color = Color(0.2, 0.95, 1.0, 0.9)


func _update_debug_draw() -> void:
	if debug_mesh.visible != debug_enabled:
		_set_debug_visible(debug_enabled)
	if not debug_enabled or _debug_immediate == null:
		return
	debug_label.text = "%s\nDestino: %s" % [
		_state_name(),
		str(_get_target().snapped(Vector3.ONE * 0.01)) if _has_target else "--",
	]
	_debug_immediate.clear_surfaces()
	_debug_immediate.surface_begin(Mesh.PRIMITIVE_LINES, _debug_material)
	if _has_target:
		_add_debug_line(Vector3.ZERO, to_local(_get_target()) + Vector3.UP * hover_height)
		var marker : Vector3 = to_local(_get_target()) + Vector3.UP * hover_height
		_add_debug_line(marker - Vector3.RIGHT * 0.18, marker + Vector3.RIGHT * 0.18)
		_add_debug_line(marker - Vector3.FORWARD * 0.18, marker + Vector3.FORWARD * 0.18)
	var segments : int = 40
	for index : int in range(segments):
		var angle_a : float = TAU * float(index) / float(segments)
		var angle_b : float = TAU * float(index + 1) / float(segments)
		_add_debug_line(
			Vector3(cos(angle_a), 0.0, sin(angle_a)) * player_perception_distance,
			Vector3(cos(angle_b), 0.0, sin(angle_b)) * player_perception_distance
		)
	_debug_immediate.surface_end()


func _add_debug_line(from : Vector3, to : Vector3) -> void:
	_debug_immediate.surface_add_vertex(from)
	_debug_immediate.surface_add_vertex(to)


func _set_debug_visible(visible : bool) -> void:
	debug_mesh.visible = visible
	debug_label.visible = visible
	if not visible and _debug_immediate != null:
		_debug_immediate.clear_surfaces()


func _state_name() -> String:
	match current_state:
		State.WANDER:
			return "WANDER"
		State.CURIOUS:
			return "CURIOUS"
		State.SCARED:
			return "SCARED"
		State.REST:
			return "REST"
	return "UNKNOWN"


func _refresh_player_if_needed() -> void:
	if is_instance_valid(_player):
		return
	_player = null
	if _player_search_time > 0.0:
		return
	_player_search_time = 1.0
	_find_player()


func _find_player() -> void:
	for character : Node in get_tree().get_nodes_in_group(&"characters"):
		if character is CharacterBody3D:
			_player = character as CharacterBody3D
			return


func _random_range(minimum : float, maximum : float) -> float:
	return _rng.randf_range(minf(minimum, maximum), maxf(minimum, maximum))
