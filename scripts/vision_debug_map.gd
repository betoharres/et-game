extends Control

const MAP_SIZE : Vector2 = Vector2(240.0, 240.0)
const MAP_MARGIN : float = 24.0
const WORLD_RADIUS : float = 35.0
const STEALTH_BAR_HEIGHT : float = 14.0

var map_visible : bool = true
var map_rect : Rect2
var panel_style : StyleBoxFlat
var font : Font
var stealth_display : float = 0.0


func _ready() -> void:
	set_process(true)
	font = ThemeDB.fallback_font
	panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.008, 0.016, 0.045, 0.94)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.18, 0.7, 0.9, 0.8)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.shadow_color = Color(0, 0, 0, 0.45)
	panel_style.shadow_size = 12
	panel_style.shadow_offset = Vector2(0, 5)
	_update_map_rect()


func _input(event : InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event : InputEventKey = event as InputEventKey
		var is_debug_key : bool = (
			key_event.keycode == KEY_F3
			or key_event.physical_keycode == KEY_F3
			or key_event.is_action_pressed("debug_vision_map")
		)
		if is_debug_key:
			map_visible = not map_visible
			queue_redraw()
			get_viewport().set_input_as_handled()


func _process(_delta : float) -> void:
	_update_stealth_display(_delta)
	if map_visible:
		_update_map_rect()
		queue_redraw()


func _notification(what : int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_map_rect()
		queue_redraw()


func _update_map_rect() -> void:
	map_rect = Rect2(
		size.x - MAP_SIZE.x - MAP_MARGIN,
		size.y - MAP_SIZE.y - MAP_MARGIN,
		MAP_SIZE.x,
		MAP_SIZE.y
	)


func _draw() -> void:
	if not map_visible:
		return

	draw_style_box(panel_style, map_rect.grow(10.0))
	draw_string(font, map_rect.position + Vector2(0, -1), "VISION DEBUG  [F3]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.9, 1.0))
	draw_string(font, map_rect.position + Vector2(0, 16), "cones / line of sight / actors", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.63, 0.75))

	var area : Rect2 = map_rect
	area.position += Vector2(0, 26)
	area.size.y -= 50
	draw_rect(area, Color(0.015, 0.03, 0.07, 0.98), true)
	draw_rect(area, Color(0.18, 0.35, 0.52, 0.75), false, 1.0)
	_draw_stealth_bar()

	var player : Node3D = _find_player()
	if player == null:
		return

	var grid_limit : int = floori(WORLD_RADIUS / 10.0) * 10
	for grid_value : int in range(-grid_limit, grid_limit + 1, 10):
		var vertical_x : float = _world_to_map(Vector3(grid_value, 0, 0), area, player).x
		var horizontal_y : float = _world_to_map(Vector3(0, 0, grid_value), area, player).y
		draw_line(Vector2(vertical_x, area.position.y), Vector2(vertical_x, area.end.y), Color(0.12, 0.25, 0.38, 0.3), 1.0)
		draw_line(Vector2(area.position.x, horizontal_y), Vector2(area.end.x, horizontal_y), Color(0.12, 0.25, 0.38, 0.3), 1.0)

	_draw_actor(player, area, Color(0.25, 0.95, 1.0), "ET", player)

	for actor : Node in _find_vision_actors():
		_draw_vision_actor(actor, area, player)

	draw_string(font, map_rect.position + Vector2(0, MAP_SIZE.y - 11), "ET", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.25, 0.95, 1.0))
	draw_string(font, map_rect.position + Vector2(43, MAP_SIZE.y - 11), "FARMER", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.34, 0.31))
	draw_string(font, map_rect.position + Vector2(102, MAP_SIZE.y - 11), "PHOTO", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.8, 0.28))


func _draw_vision_actor(actor : Node, area : Rect2, player : Node3D) -> void:
	if not actor is Node3D:
		return

	var actor_3d : Node3D = actor as Node3D
	var actor_position : Vector3 = actor_3d.global_position
	if actor.has_method("get_vision_origin"):
		actor_position = Vector3(actor.call("get_vision_origin"))
	var distance : float = float(actor.get("sight_distance"))
	var angle : float = float(actor.get("sight_angle"))
	var forward : Vector3 = actor_3d.global_transform.basis.z
	if actor.has_method("get_vision_forward"):
		forward = Vector3(actor.call("get_vision_forward"))
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return
	forward = forward.normalized()

	var color : Color = Color(1.0, 0.8, 0.28) if actor.is_in_group("photographers") else Color(1.0, 0.34, 0.31)
	var sees_player : bool = bool(actor.get("has_visual_contact"))
	if sees_player:
		color = Color(0.35, 1.0, 0.45)

	var center : Vector2 = _clamp_map_point(_world_to_map(actor_position, area, player), area)
	var radius : float = minf(
		distance / WORLD_RADIUS * area.size.x * 0.5,
		minf(area.size.x, area.size.y) * 0.5
	)
	var player_right : Vector3 = _map_right(player)
	var player_forward : Vector3 = _map_forward(player)
	var screen_forward : Vector2 = Vector2(
		forward.dot(player_right),
		-forward.dot(player_forward)
	)
	var forward_angle : float = atan2(screen_forward.x, screen_forward.y)
	var points := PackedVector2Array([center])
	var segments : int = 18
	for index : int in range(segments + 1):
		var angle_offset : float = deg_to_rad(-angle + (angle * 2.0) * index / segments)
		var direction : Vector2 = Vector2(sin(forward_angle + angle_offset), cos(forward_angle + angle_offset))
		points.append(_clamp_map_point(center + direction * radius, area))

	draw_colored_polygon(points, Color(color, 0.1 if not sees_player else 0.18))
	var outline := PackedVector2Array(points)
	outline.append(center)
	draw_polyline(outline, Color(color, 0.75), 1.0, true)
	var close_radius : float = 0.0
	if actor.get("close_perception_radius") != null:
		close_radius = float(actor.get("close_perception_radius"))
	if close_radius > 0.0:
		var close_map_radius : float = close_radius / WORLD_RADIUS * area.size.x * 0.5
		draw_arc(center, close_map_radius, 0.0, TAU, 24, Color(color, 0.7), 1.0, true)
	_draw_actor(actor_3d, area, color, "P" if actor.is_in_group("photographers") else "F", player)

	if sees_player:
		draw_line(center, _clamp_map_point(_world_to_map(player.global_position, area, player), area), Color(0.35, 1.0, 0.45, 0.9), 2.0)


func _draw_stealth_bar() -> void:
	var bar_position : Vector2 = map_rect.position + Vector2(0.0, MAP_SIZE.y + 15.0)
	var bar_rect := Rect2(bar_position, Vector2(MAP_SIZE.x, STEALTH_BAR_HEIGHT))
	draw_rect(bar_rect, Color(0.008, 0.016, 0.045, 0.94), true)
	draw_rect(bar_rect, Color(0.18, 0.7, 0.9, 0.75), false, 1.0)
	var fill_rect := Rect2(
		bar_rect.position + Vector2(2.0, 2.0),
		Vector2((bar_rect.size.x - 4.0) * stealth_display, bar_rect.size.y - 4.0)
	)
	if fill_rect.size.x > 0.0:
		draw_rect(fill_rect, Color(0.95, 0.25, 0.32, 0.86), true)
	draw_string(font, bar_position + Vector2(7.0, 11.0), "STEALTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.85, 0.92, 1.0, 0.9))


func _update_stealth_display(delta : float) -> void:
	var player : Node3D = _find_player()
	var target : float = 0.0
	if player != null and player.has_method("get_stealth_alert"):
		target = clampf(float(player.call("get_stealth_alert")), 0.0, 1.0)
	stealth_display = move_toward(stealth_display, target, delta * 8.0)


func _draw_actor(actor : Node3D, area : Rect2, color : Color, label : String, player : Node3D) -> void:
	var point : Vector2 = _clamp_map_point(_world_to_map(actor.global_position, area, player), area)
	draw_circle(point, 5.0, Color(0.01, 0.02, 0.05, 0.95))
	draw_circle(point, 4.0, color)
	draw_string(font, point + Vector2(7, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)


func _clamp_map_point(point : Vector2, area : Rect2) -> Vector2:
	var padding : float = 4.0
	return Vector2(
		clampf(point.x, area.position.x + padding, area.end.x - padding),
		clampf(point.y, area.position.y + padding, area.end.y - padding)
	)


func _world_to_map(world_position : Vector3, area : Rect2, player : Node3D) -> Vector2:
	var relative : Vector3 = world_position - player.global_position
	var player_right : Vector3 = _map_right(player)
	var player_forward : Vector3 = _map_forward(player)
	var normalized : Vector2 = Vector2(
		relative.dot(player_right),
		-relative.dot(player_forward)
	) / WORLD_RADIUS
	return area.get_center() + normalized * area.size.x * 0.5


func _map_right(player : Node3D) -> Vector3:
	var camera_holder : Node3D = player.get_node_or_null("CameraHolder") as Node3D
	var right : Vector3 = (
		camera_holder.global_transform.basis.x
		if camera_holder != null
		else player.global_transform.basis.x
	)
	right.y = 0.0
	# O eixo X do overlay usa a convenção visual da tela; inverter aqui
	# mantém a direita do mundo à direita do mini mapa.
	return -right.normalized()


func _map_forward(player : Node3D) -> Vector3:
	var camera_holder : Node3D = player.get_node_or_null("CameraHolder") as Node3D
	var forward : Vector3 = (
		camera_holder.global_transform.basis.z
		if camera_holder != null
		else player.global_transform.basis.z
	)
	forward.y = 0.0
	return forward.normalized()


func _find_player() -> Node3D:
	for character : Node in get_tree().get_nodes_in_group("characters"):
		if character is Node3D:
			return character as Node3D
	return null


func _find_vision_actors() -> Array[Node]:
	var actors : Array[Node] = []
	var current_scene : Node = get_tree().current_scene
	if current_scene == null:
		return actors

	for candidate : Node in current_scene.find_children("*", "CharacterBody3D", true, false):
		if candidate.has_method("_can_see_player"):
			actors.append(candidate)
	return actors
