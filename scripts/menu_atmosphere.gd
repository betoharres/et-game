extends Control

## Atmospheric background for the main menu. It deliberately draws softly so
## the existing menu remains the visual focus.

@export_category("Motion")
@export var reduced_motion : bool = false
@export var random_seed : int = 24081990
@export var loop_duration : float = 90.0

@export_category("Stars")
@export_range(4, 80, 1) var stars_per_layer : int = 24
@export var star_blink_min : float = 2.0
@export var star_blink_max : float = 8.0
@export var parallax_speed : Vector3 = Vector3(0.3, 0.55, 0.9)

@export_category("UFO")
@export var ufo_travel_duration : float = 80.0
@export var ufo_start_delay : float = 2.0
@export var ufo_color : Color = Color(0.04, 0.08, 0.15, 0.82)
@export var ufo_light_color : Color = Color(0.12, 0.82, 1.0, 0.72)

@export_category("Beams")
@export var beam_color : Color = Color(0.1, 0.8, 1.0, 0.1)
@export var beam_intensity : float = 1.0
@export var beam_length_ratio : float = 0.86
@export_range(0.12, 0.45, 0.01) var beam_target_spread : float = 0.42
@export var beam_target_change_min : float = 3.5
@export var beam_target_change_max : float = 7.0
@export var beam_target_speed : float = 0.08
@export_range(0.0, 1.0, 0.05) var beam_pair_chance : float = 0.4
@export_range(0.0, 1.0, 0.05) var beam_cluster_chance : float = 0.25
@export_range(0.01, 0.12, 0.01) var beam_cluster_radius : float = 0.045

var elapsed : float = 0.0
var rng : RandomNumberGenerator = RandomNumberGenerator.new()
var stars : Array[Dictionary] = []
var menu_state : String = "play"
var launch_pulse : float = 0.0
var shooting_star_timer : float = 0.0
var shooting_star_progress : float = -1.0
var shooting_star_start : Vector2 = Vector2.ZERO
var shooting_star_end : Vector2 = Vector2.ZERO
var beam_dropout_timer : float = 0.0
var beam_dropout_index : int = -1
var beam_target_positions : Array[float] = []
var beam_target_goals : Array[float] = []
var beam_pattern_timer : float = 0.0


func _ready() -> void:
	rng.seed = random_seed
	_build_stars()
	_schedule_shooting_star()
	_initialize_beam_targets()
	_update_beam_dropout()
	queue_redraw()


func _process(delta : float) -> void:
	if not reduced_motion:
		elapsed = fmod(elapsed + delta, maxf(loop_duration, 1.0) * 2.0)
		_update_shooting_star(delta)
		_update_beam_dropout()
		_update_beam_targets(delta)
		launch_pulse = maxf(launch_pulse - delta * 2.2, 0.0)
		queue_redraw()


func set_menu_state(state : String) -> void:
	menu_state = state
	_retarget_beams()
	queue_redraw()


func begin_launch() -> void:
	menu_state = "launch"
	launch_pulse = 1.0
	for beam_index : int in range(3):
		beam_target_goals[beam_index] = 0.0
	beam_pattern_timer = 0.0
	queue_redraw()


func _initialize_beam_targets() -> void:
	beam_target_positions.clear()
	beam_target_goals.clear()
	var initial_targets : Array[float] = _generate_beam_targets(_beam_spread_for_state())
	for beam_index : int in range(3):
		beam_target_positions.append(initial_targets[beam_index])
		beam_target_goals.append(initial_targets[beam_index])
	beam_pattern_timer = rng.randf_range(beam_target_change_min, beam_target_change_max)


func _update_beam_targets(delta : float) -> void:
	if beam_target_positions.size() != 3:
		_initialize_beam_targets()

	if menu_state == "launch":
		for beam_index : int in range(3):
			beam_target_positions[beam_index] = move_toward(beam_target_positions[beam_index], 0.0, delta * beam_target_speed * 2.5)
		return

	beam_pattern_timer -= delta
	if beam_pattern_timer <= 0.0:
		_retarget_beams()

	for beam_index : int in range(3):
		var speed_multiplier : float = 0.85 + beam_index * 0.18
		beam_target_positions[beam_index] = move_toward(
			beam_target_positions[beam_index],
			beam_target_goals[beam_index],
			delta * beam_target_speed * speed_multiplier
		)


func _retarget_beams() -> void:
	if beam_target_positions.size() != 3:
		return
	if menu_state == "launch":
		for beam_index : int in range(3):
			beam_target_goals[beam_index] = 0.0
		beam_pattern_timer = 0.0
		return

	var next_targets : Array[float] = _generate_beam_targets(_beam_spread_for_state())
	for beam_index : int in range(3):
		beam_target_goals[beam_index] = next_targets[beam_index]
	beam_pattern_timer = rng.randf_range(beam_target_change_min, beam_target_change_max)


func _beam_spread_for_state() -> float:
	if menu_state == "play":
		return beam_target_spread * 0.98
	if menu_state == "options":
		return minf(beam_target_spread * 1.1, 0.44)
	if menu_state == "exit":
		return beam_target_spread * 0.95
	return beam_target_spread


func _generate_beam_targets(spread : float) -> Array[float]:
	var generated : Array[float] = [0.0, 0.0, 0.0]
	var pattern_roll : float = rng.randf()
	if pattern_roll < beam_cluster_chance:
		var cluster_anchor : float = _random_cluster_anchor(spread)
		for beam_index : int in range(3):
			generated[beam_index] = clampf(
				cluster_anchor + rng.randf_range(-beam_cluster_radius, beam_cluster_radius),
				-0.46,
				0.46
			)
		return generated

	if pattern_roll < beam_cluster_chance + beam_pair_chance:
		var pair_anchor : float = _random_cluster_anchor(spread)
		var first_beam : int = rng.randi_range(0, 2)
		var second_beam : int = (first_beam + rng.randi_range(1, 2)) % 3
		var lone_beam : int = 3 - first_beam - second_beam
		generated[first_beam] = clampf(pair_anchor + rng.randf_range(-beam_cluster_radius, beam_cluster_radius), -0.46, 0.46)
		generated[second_beam] = clampf(pair_anchor + rng.randf_range(-beam_cluster_radius, beam_cluster_radius), -0.46, 0.46)
		generated[lone_beam] = rng.randf_range(-spread, spread)
		if absf(generated[lone_beam] - pair_anchor) < spread * 0.45:
			generated[lone_beam] = -spread if pair_anchor > 0.0 else spread
		return generated

	for beam_index : int in range(3):
		var lane_position : float = -spread + float(beam_index) * spread
		var lane_jitter : float = rng.randf_range(-spread * 0.12, spread * 0.12)
		generated[beam_index] = clampf(lane_position + lane_jitter, -0.46, 0.46)
	return generated


func _random_cluster_anchor(spread : float) -> float:
	if rng.randf() < 0.6:
		var side : float = -1.0 if rng.randf() < 0.5 else 1.0
		return side * rng.randf_range(spread * 0.68, spread)
	return rng.randf_range(-spread, spread)


func _build_stars() -> void:
	stars.clear()
	for layer : int in range(3):
		for index : int in range(stars_per_layer):
			stars.append({
				"layer": layer,
				"position": Vector2(rng.randf(), rng.randf() * 0.68),
				"radius": rng.randf_range(0.55, 1.6 if layer > 0 else 1.15),
				"alpha": rng.randf_range(0.16, 0.48 if layer > 0 else 0.32),
				"period": rng.randf_range(star_blink_min, star_blink_max),
				"phase": rng.randf_range(0.0, TAU),
				"hue": rng.randf_range(0.0, 1.0)
			})


func _schedule_shooting_star() -> void:
	shooting_star_timer = rng.randf_range(40.0, 90.0)
	shooting_star_progress = -1.0


func _update_shooting_star(delta : float) -> void:
	if shooting_star_progress >= 0.0:
		shooting_star_progress += delta / 0.75
		if shooting_star_progress >= 1.0:
			_schedule_shooting_star()
		return

	shooting_star_timer -= delta
	if shooting_star_timer > 0.0:
		return

	var viewport_size : Vector2 = size
	shooting_star_start = Vector2(
		rng.randf_range(0.08, 0.78) * viewport_size.x,
		rng.randf_range(0.08, 0.32) * viewport_size.y
	)
	shooting_star_end = shooting_star_start + Vector2(
		rng.randf_range(70.0, 150.0),
		rng.randf_range(35.0, 85.0)
	)
	shooting_star_progress = 0.0


func _update_beam_dropout() -> void:
	if beam_dropout_timer > 0.0:
		beam_dropout_timer -= get_process_delta_time()
		if beam_dropout_timer <= 0.0:
			beam_dropout_index = -1
		return

	if rng.randf() < 0.0025:
		beam_dropout_index = rng.randi_range(0, 2)
		beam_dropout_timer = rng.randf_range(0.5, 1.1)


func _draw() -> void:
	var viewport_size : Vector2 = size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return

	_draw_nebula(viewport_size)
	_draw_stars(viewport_size)
	_draw_terrain(viewport_size)
	_draw_ufo_and_beams(viewport_size)
	_draw_shooting_star()


func _draw_nebula(viewport_size : Vector2) -> void:
	var center : Vector2 = Vector2(viewport_size.x * 0.52, viewport_size.y * 0.27)
	for index : int in range(5):
		var radius : float = 270.0 - index * 42.0
		var alpha : float = 0.012 - index * 0.0015
		draw_circle(center + Vector2(sin(elapsed * 0.01 + index) * 5.0, 0), radius, Color(0.12, 0.16, 0.52, alpha))


func _draw_stars(viewport_size : Vector2) -> void:
	for star : Dictionary in stars:
		var layer : int = int(star["layer"])
		var base_position : Vector2 = star["position"] * viewport_size
		var drift : float = fmod(elapsed * parallax_speed[layer] * (layer + 1), viewport_size.x + 40.0) - 20.0
		var position2 : Vector2 = base_position + Vector2(drift, 0.0)
		if position2.x > viewport_size.x + 4.0:
			position2.x -= viewport_size.x + 40.0
		var pulse : float = 0.78 + 0.22 * sin(elapsed * TAU / float(star["period"]) + float(star["phase"]))
		var star_color : Color = Color(0.48, 0.76, 1.0, float(star["alpha"]) * pulse)
		if float(star["hue"]) > 0.82:
			star_color = Color(0.62, 0.38, 1.0, star_color.a * 0.65)
		draw_circle(position, float(star["radius"]), star_color)


func _draw_ufo_and_beams(viewport_size : Vector2) -> void:
	if elapsed < ufo_start_delay:
		return

	var ufo_progress : float = fmod(elapsed - ufo_start_delay, maxf(ufo_travel_duration, 1.0)) / maxf(ufo_travel_duration, 1.0)
	var ufo_position : Vector2 = Vector2(
		lerp(viewport_size.x * 0.12, viewport_size.x * 1.12, ufo_progress),
		viewport_size.y * 0.2 + sin(elapsed * 0.13) * 5.0
	)
	var ufo_alpha : float = 0.42 if menu_state != "exit" else 0.22
	var ship_scale : float = 1.0 + launch_pulse * 0.12
	var ship_points : PackedVector2Array = PackedVector2Array([
		ufo_position + Vector2(-48, 9) * ship_scale,
		ufo_position + Vector2(0, -13) * ship_scale,
		ufo_position + Vector2(48, 9) * ship_scale,
		ufo_position + Vector2(0, 18) * ship_scale
	])
	draw_colored_polygon(ship_points, Color(ufo_color, ufo_alpha))
	draw_polyline(ship_points, Color(0.12, 0.3, 0.5, ufo_alpha), 1.0, true)

	var light_pulse : float = 0.5 + 0.5 * sin(elapsed * 0.7)
	for light_index : int in range(3):
		var light_position : Vector2 = ufo_position + Vector2(-24 + light_index * 24, 9)
		draw_circle(light_position, 2.0 + launch_pulse * 2.0, Color(ufo_light_color, ufo_light_color.a * (0.55 + light_pulse * 0.3)))

	for beam_index : int in range(3):
		if beam_index == beam_dropout_index:
			continue
		var start : Vector2 = ufo_position + Vector2(-24 + beam_index * 24, 13)
		var target_offset : float = beam_target_positions[beam_index] if beam_target_positions.size() == 3 else 0.0
		var target : Vector2 = Vector2(
			viewport_size.x * (0.5 + target_offset) + sin(elapsed * (0.06 + beam_index * 0.01)) * 12.0,
			viewport_size.y * clampf(beam_length_ratio, 0.75, 0.96)
		)
		var beam_direction : Vector2 = (target - start).normalized()
		var perpendicular : Vector2 = Vector2(-beam_direction.y, beam_direction.x)
		var width : float = 22.0 + sin(elapsed * 0.3 + beam_index) * 4.0
		var beam_points : PackedVector2Array = PackedVector2Array([
			start - perpendicular * 2.0,
			start + perpendicular * 2.0,
			target + perpendicular * width,
			target - perpendicular * width
		])
		var beam_alpha : float = beam_color.a * beam_intensity * (0.82 + sin(elapsed * 0.23 + beam_index) * 0.14)
		if launch_pulse > 0.0:
			beam_alpha *= 1.0 + launch_pulse * 0.8
		draw_colored_polygon(beam_points, Color(beam_color, beam_alpha))


func _draw_terrain(viewport_size : Vector2) -> void:
	var horizon : float = viewport_size.y * 0.72
	var hills : PackedVector2Array = PackedVector2Array([
		Vector2(0, horizon + 30), Vector2(viewport_size.x * 0.16, horizon - 8),
		Vector2(viewport_size.x * 0.3, horizon + 18), Vector2(viewport_size.x * 0.48, horizon - 22),
		Vector2(viewport_size.x * 0.64, horizon + 10), Vector2(viewport_size.x * 0.82, horizon - 14),
		Vector2(viewport_size.x, horizon + 16), Vector2(viewport_size.x, viewport_size.y), Vector2(0, viewport_size.y)
	])
	draw_colored_polygon(hills, Color(0.006, 0.012, 0.027, 0.96))

	for tree_index : int in range(11):
		var x : float = fmod(tree_index * 173.0 + 30.0, viewport_size.x)
		var base_y : float = horizon + 20.0 + fmod(tree_index * 29.0, 45.0)
		var tree_height : float = 18.0 + fmod(tree_index * 13.0, 22.0)
		var sway : float = sin(elapsed * 0.12 + tree_index) * 1.2
		draw_line(Vector2(x, base_y), Vector2(x + sway, base_y - tree_height), Color(0.012, 0.026, 0.045, 0.92), 3.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x + sway, base_y - tree_height - 8),
			Vector2(x - 8 + sway, base_y - tree_height + 8),
			Vector2(x + 8 + sway, base_y - tree_height + 8)
		]), Color(0.01, 0.024, 0.045, 0.94))

	var fog_offset : float = fmod(elapsed * 3.0, viewport_size.x)
	for fog_index : int in range(3):
		var fog_y : float = viewport_size.y * (0.68 + fog_index * 0.045)
		draw_rect(Rect2(-viewport_size.x + fog_offset, fog_y, viewport_size.x * 1.5, 10.0), Color(0.1, 0.19, 0.32, 0.018), true)


func _draw_shooting_star() -> void:
	if shooting_star_progress < 0.0:
		return
	var head : Vector2 = shooting_star_start.lerp(shooting_star_end, shooting_star_progress)
	var tail : Vector2 = shooting_star_start.lerp(shooting_star_end, maxf(shooting_star_progress - 0.22, 0.0))
	draw_line(tail, head, Color(0.5, 0.84, 1.0, 0.45), 1.0, true)
	draw_circle(head, 1.4, Color(0.78, 0.94, 1.0, 0.7))
