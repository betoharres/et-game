extends Control

const MIN_MAP_DIAMETER : float = 180.0
const MAX_MAP_DIAMETER : float = 220.0
const MAP_HEIGHT_RATIO : float = 0.2
const MAP_MARGIN : float = 48.0
const WORLD_RADIUS : float = 35.0
const PLAYER_ICON : Texture2D = preload(
	"res://assets/ui/prototype_icons/player.png"
)
const CAMERA_ICON : Texture2D = preload(
	"res://assets/ui/prototype_icons/camera.png"
)
const WARNING_ICON : Texture2D = preload(
	"res://assets/ui/prototype_icons/warning.png"
)
const CIRCLE_ICON : Texture2D = preload(
	"res://assets/ui/prototype_icons/circle.png"
)
const GLOW_RING_ICON : Texture2D = preload(
	"res://assets/ui/prototype_icons/glow_ring.png"
)

var map_visible : bool = false
var map_center : Vector2
var map_radius : float = 100.0
var _elapsed : float = 0.0


func _ready() -> void:
	_update_map_geometry()
	queue_redraw()


func _input(event : InputEvent) -> void:
	if (
		event.is_action_pressed("debug_vision_map")
		and not event.is_echo()
	):
		map_visible = not map_visible
		queue_redraw()
		get_viewport().set_input_as_handled()


func _process(delta : float) -> void:
	_elapsed += delta
	if map_visible:
		_update_map_geometry()
		queue_redraw()


func _notification(what : int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_map_geometry()
		queue_redraw()


func _update_map_geometry() -> void:
	var diameter := clampf(
		size.y * MAP_HEIGHT_RATIO,
		MIN_MAP_DIAMETER,
		MAX_MAP_DIAMETER
	)
	map_radius = diameter * 0.5
	map_center = Vector2(
		size.x - MAP_MARGIN - map_radius,
		size.y - MAP_MARGIN - map_radius
	)


func _draw() -> void:
	if not map_visible:
		return

	draw_circle(
		map_center + Vector2(0.0, 5.0),
		map_radius + 5.0,
		Color(0, 0, 0, 0.25)
	)
	draw_circle(
		map_center,
		map_radius,
		Color(0.008, 0.018, 0.035, 0.72)
	)
	draw_arc(
		map_center,
		map_radius,
		0.0,
		TAU,
		72,
		Color(0.25, 0.78, 0.92, 0.42),
		1.5,
		true
	)

	var player := _find_player()
	if player == null:
		return

	_draw_north_tick(player)
	_draw_delivery_objective(player)

	for actor : Node in _find_vision_actors():
		_draw_vision_actor(actor, player)

	_draw_player_marker()


func _draw_north_tick(player : Node3D) -> void:
	var world_north := Vector3(0.0, 0.0, -1.0)
	var north_direction := Vector2(
		world_north.dot(_map_right(player)),
		-world_north.dot(_map_forward(player))
	).normalized()
	draw_line(
		map_center + north_direction * (map_radius - 12.0),
		map_center + north_direction * (map_radius - 4.0),
		Color(0.65, 0.92, 1.0, 0.7),
		2.0,
		true
	)


func _draw_delivery_objective(player : Node3D) -> void:
	var delivery_area := _find_delivery_area()
	if delivery_area == null:
		return

	var point := _clamp_to_radar(
		_world_to_map(delivery_area.global_position, player),
		8.0
	)
	var pulse := 17.0 + sin(_elapsed * 3.2) * 2.5
	draw_texture_rect(
		GLOW_RING_ICON,
		Rect2(point - Vector2.ONE * pulse * 0.5, Vector2.ONE * pulse),
		false,
		Color(0.25, 0.9, 1.0, 0.34)
	)
	draw_texture_rect(
		CIRCLE_ICON,
		Rect2(point - Vector2(5.0, 5.0), Vector2(10.0, 10.0)),
		false,
		Color(0.35, 0.96, 1.0, 1.0)
	)


func _draw_player_marker() -> void:
	draw_texture_rect(
		PLAYER_ICON,
		Rect2(map_center - Vector2(6.0, 11.0), Vector2(12.0, 22.0)),
		false,
		Color(0.28, 0.96, 1.0, 1.0)
	)


func _draw_vision_actor(actor : Node, player : Node3D) -> void:
	if not actor is Node3D:
		return

	var actor_3d := actor as Node3D
	var actor_position : Vector3 = actor_3d.global_position
	if actor.has_method("get_vision_origin"):
		actor_position = Vector3(actor.call("get_vision_origin"))

	var distance : float = float(actor.get("sight_distance"))
	if actor.has_method("get_effective_sight_distance"):
		distance = float(actor.call("get_effective_sight_distance"))

	var half_angle_degrees : float = float(
		actor.get("sight_half_angle_degrees")
	)
	if actor.has_method("get_effective_sight_half_angle_degrees"):
		half_angle_degrees = float(
			actor.call("get_effective_sight_half_angle_degrees")
		)

	var forward : Vector3 = actor_3d.global_transform.basis.z
	if actor.has_method("get_vision_forward"):
		forward = Vector3(actor.call("get_vision_forward"))
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return
	forward = forward.normalized()

	var is_photographer := actor.is_in_group("photographers")
	var sees_player : bool = bool(actor.get("has_visual_contact"))
	var color := (
		Color(1.0, 0.78, 0.22)
		if is_photographer
		else Color(0.95, 0.25, 0.3)
	)
	if sees_player:
		color = Color(1.0, 0.16, 0.2)

	var center := _clamp_to_radar(
		_world_to_map(actor_position, player),
		7.0
	)
	var vision_radius := minf(
		distance / WORLD_RADIUS * map_radius,
		map_radius
	)
	var screen_forward := Vector2(
		forward.dot(_map_right(player)),
		-forward.dot(_map_forward(player))
	)
	var forward_angle := atan2(screen_forward.x, screen_forward.y)
	var points := PackedVector2Array([center])
	var segments : int = 16

	for index : int in range(segments + 1):
		var angle_offset := deg_to_rad(
			-half_angle_degrees
			+ (half_angle_degrees * 2.0) * float(index) / float(segments)
		)
		var direction := Vector2(
			sin(forward_angle + angle_offset),
			cos(forward_angle + angle_offset)
		)
		points.append(_clamp_to_radar(center + direction * vision_radius, 3.0))

	draw_colored_polygon(points, Color(color, 0.07 if not sees_player else 0.12))
	_draw_actor_marker(center, color, is_photographer)

	if sees_player:
		draw_line(
			center,
			map_center,
			Color(color, 0.46),
			1.2,
			true
		)


func _draw_actor_marker(
	point : Vector2,
	color : Color,
	is_photographer : bool
) -> void:
	if is_photographer:
		draw_texture_rect(
			CAMERA_ICON,
			Rect2(point - Vector2(6.5, 6.5), Vector2(13.0, 13.0)),
			false,
			color
		)
		return

	draw_texture_rect(
		WARNING_ICON,
		Rect2(point - Vector2(6.5, 6.5), Vector2(13.0, 13.0)),
		false,
		color
	)


func _clamp_to_radar(point : Vector2, padding : float) -> Vector2:
	var offset := point - map_center
	var maximum_distance := map_radius - padding
	if offset.length() > maximum_distance:
		offset = offset.normalized() * maximum_distance
	return map_center + offset


func _world_to_map(world_position : Vector3, player : Node3D) -> Vector2:
	var relative := world_position - player.global_position
	var normalized := Vector2(
		relative.dot(_map_right(player)),
		-relative.dot(_map_forward(player))
	) / WORLD_RADIUS
	return map_center + normalized * map_radius


func _map_right(player : Node3D) -> Vector3:
	var camera_holder := player.get_node_or_null("CameraHolder") as Node3D
	var right := (
		camera_holder.global_transform.basis.x
		if camera_holder != null
		else player.global_transform.basis.x
	)
	right.y = 0.0
	return -right.normalized()


func _map_forward(player : Node3D) -> Vector3:
	var camera_holder := player.get_node_or_null("CameraHolder") as Node3D
	var forward := (
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


func _find_delivery_area() -> Node3D:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	return current_scene.find_child("DeliveryArea", true, false) as Node3D


func _find_vision_actors() -> Array[Node]:
	var actors : Array[Node] = []
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return actors

	for candidate : Node in current_scene.find_children(
		"*",
		"CharacterBody3D",
		true,
		false
	):
		if candidate.has_method("_can_see_player"):
			actors.append(candidate)
	return actors
