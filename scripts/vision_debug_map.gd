extends Control

## Minimapa circular reutilizável (atalho `F3`). Desenha o jogador ao centro,
## o norte, um objetivo, os pontos de interesse do mapa e os NPCs com visão,
## incluindo o cone de visão de cada um.
##
## Tudo o que varia de mapa para mapa é export: o raio em metros que o círculo
## cobre, de quais grupos vêm objetivo/pontos de interesse, e se os nomes dos
## pontos aparecem. A fazenda usa o padrão de curto alcance; o Country Town,
## que é muito maior, sobe o raio e liga os POIs.

const SHORTCUT_FONT : Font = preload(
	"res://assets/menu/fonts/Oxanium-Regular.ttf"
)
const PLAYER_ICON : Texture2D = preload(
	"res://Texturas/ui/player.png"
)
const CAMERA_ICON : Texture2D = preload(
	"res://Texturas/ui/camera.png"
)
const CIRCLE_ICON : Texture2D = preload(
	"res://Texturas/ui/circle.png"
)
const GLOW_RING_ICON : Texture2D = preload(
	"res://Texturas/ui/glow_ring.png"
)

@export_category("Alcance")
## Quantos metros do mundo cabem do centro até a borda do círculo.
@export var world_radius : float = 35.0

@export_category("Layout")
@export var minimum_diameter : float = 180.0
@export var maximum_diameter : float = 220.0
@export_range(0.05, 0.6, 0.01) var height_ratio : float = 0.2
@export var screen_margin : float = 48.0

@export_category("Conteúdo")
## Grupo do objetivo destacado com o anel pulsante (área de entrega).
@export var objective_group : StringName = &"delivery_areas"
## Grupo de `Marker3D` desenhados como pontos de referência. Vazio desliga.
@export var landmark_group : StringName = &""
## Mostra o nome dos pontos de referência que estiverem dentro do círculo.
@export var show_landmark_names : bool = true
## Cor do quadrado dos NPCs comuns. Quem está enxergando o ET vira vermelho.
@export_color_no_alpha var npc_color : Color = Color(0.32, 0.6, 1.0)
## Usa quadrados da cor npc_color para todos os NPCs, mesmo em alerta.
@export var uniform_npc_markers : bool = false
## Lado do quadrado, em pixels.
@export_range(6.0, 20.0, 0.5) var npc_marker_size : float = 11.0
## Segundos entre varreduras da cena atrás de atores com visão. Evita
## percorrer a árvore inteira a cada frame em mapas grandes.
@export var actor_scan_interval : float = 0.5

@export_category("Ruído")
@export_range(0.5, 3.0, 0.1) var noise_pulse_duration : float = 1.4
@export_color_no_alpha var noise_color : Color = Color(0.35, 0.9, 1.0)
@export_color_no_alpha var heard_noise_color : Color = Color(1.0, 0.58, 0.16)

@export_category("Atalho")
@export var shortcut_action : StringName = &"debug_vision_map"
@export var shortcut_text : String = "F3"
@export var shortcut_font_size : int = 14

var map_visible : bool = true
var map_center : Vector2
var map_radius : float = 100.0

var _elapsed : float = 0.0
var _scan_timer : float = 0.0
var _player : Node3D = null
var _objective : Node3D = null
var _vision_actors : Array[Node] = []
var _landmarks : Array[Node3D] = []
var _character_bodies : Array[Node] = []
var _noise_source : Node = null
var _noise_pulses : Array[NoisePulse] = []


class NoisePulse:
	extends RefCounted

	var origin : Vector3
	var decibels : float
	var radius : float
	var heard : bool
	var age : float = 0.0

	func _init(position : Vector3, level : float, reach : float, was_heard : bool) -> void:
		origin = position
		decibels = level
		radius = reach
		heard = was_heard


func _ready() -> void:
	_character_bodies = get_tree().root.find_children("*", "CharacterBody3D", true, false)
	get_tree().node_added.connect(_on_scene_node_added)
	get_tree().node_removed.connect(_on_scene_node_removed)
	_update_map_geometry()
	_refresh_scene_references()
	queue_redraw()


func _input(event : InputEvent) -> void:
	if event.is_action_pressed(shortcut_action) and not event.is_echo():
		map_visible = not map_visible
		queue_redraw()
		get_viewport().set_input_as_handled()


func _process(delta : float) -> void:
	_elapsed += delta
	if not get_tree().paused:
		_update_noise_pulses(delta)

	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = actor_scan_interval
		_refresh_scene_references()

	if not map_visible:
		return
	_update_map_geometry()
	queue_redraw()


func _notification(what : int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_map_geometry()
		queue_redraw()


func _update_map_geometry() -> void:
	var diameter : float = clampf(
		size.y * height_ratio,
		minimum_diameter,
		maximum_diameter
	)
	map_radius = diameter * 0.5
	map_center = Vector2(
		size.x - screen_margin - map_radius,
		size.y - screen_margin - map_radius
	)


# --------------------------------------------------
# BUSCA NA CENA
# --------------------------------------------------

func _refresh_scene_references() -> void:
	_player = _find_player()
	_connect_noise_source()
	_objective = _find_objective()
	_landmarks = _find_landmarks()
	_vision_actors = _find_vision_actors()


func _find_player() -> Node3D:
	var active_player : Node3D = get_tree().get_first_node_in_group(&"players") as Node3D
	if active_player != null:
		return active_player
	for character : Node in get_tree().get_nodes_in_group(&"characters"):
		if character is Node3D:
			return character as Node3D
	return null


func _connect_noise_source() -> void:
	var source : Node = _player.get_node_or_null("PlayerNoise") if is_instance_valid(_player) else null
	if is_instance_valid(_noise_source) and _noise_source == source:
		return
	if is_instance_valid(_noise_source) and _noise_source.is_connected("noise_emitted", _on_noise_emitted):
		_noise_source.disconnect("noise_emitted", _on_noise_emitted)
	_noise_source = source
	_noise_pulses.clear()
	if _noise_source != null and _noise_source.has_signal("noise_emitted"):
		_noise_source.connect("noise_emitted", _on_noise_emitted)


func _on_noise_emitted(origin : Vector3, decibels : float, radius : float, heard : bool) -> void:
	_noise_pulses.append(NoisePulse.new(origin, decibels, radius, heard))
	if _noise_pulses.size() > 12:
		_noise_pulses.pop_front()
	queue_redraw()


func _update_noise_pulses(delta : float) -> void:
	for index : int in range(_noise_pulses.size() - 1, -1, -1):
		_noise_pulses[index].age += delta
		if _noise_pulses[index].age >= noise_pulse_duration:
			_noise_pulses.remove_at(index)


func _find_objective() -> Node3D:
	var objective : Node = get_tree().get_first_node_in_group(objective_group)
	if objective is Node3D:
		return objective as Node3D

	var current_scene : Node = get_tree().current_scene
	if current_scene == null:
		return null
	return current_scene.find_child("DeliveryArea", true, false) as Node3D


func _find_landmarks() -> Array[Node3D]:
	var landmarks : Array[Node3D] = []
	if landmark_group == &"":
		return landmarks

	for landmark : Node in get_tree().get_nodes_in_group(landmark_group):
		if landmark is Node3D:
			landmarks.append(landmark as Node3D)
	return landmarks


func _on_scene_node_added(node : Node) -> void:
	if node is CharacterBody3D:
		_character_bodies.append(node)


func _on_scene_node_removed(node : Node) -> void:
	if node is CharacterBody3D:
		_character_bodies.erase(node)
	_vision_actors.erase(node)
	if node is Node3D:
		_landmarks.erase(node as Node3D)


func _find_vision_actors() -> Array[Node]:
	var actors : Array[Node] = []

	for actor : Node in get_tree().get_nodes_in_group(&"npc_actors"):
		if actor is Node3D and (uniform_npc_markers or actor.get("vision") != null):
			actors.append(actor)

	var current_scene : Node = get_tree().current_scene
	if current_scene == null:
		return actors

	for candidate : Node in _character_bodies:
		if (
			current_scene.is_ancestor_of(candidate)
			and candidate.has_method("_can_see_player")
			and not actors.has(candidate)
		):
			actors.append(candidate)
	return actors


# --------------------------------------------------
# DESENHO
# --------------------------------------------------

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
	_draw_shortcut_hint()

	if _player == null or not is_instance_valid(_player):
		return

	_draw_north_tick(_player)

	for landmark : Node3D in _landmarks:
		if is_instance_valid(landmark):
			_draw_landmark(landmark, _player)

	_draw_objective(_player)

	for actor : Node in _vision_actors:
		# Freed objects are rejected before the typed function can check them.
		if is_instance_valid(actor):
			_draw_vision_actor(actor, _player)

	_draw_player_marker()
	_draw_noise_pulses(_player)
	_draw_noise_label()


func _draw_noise_pulses(player : Node3D) -> void:
	for pulse : NoisePulse in _noise_pulses:
		var center : Vector2 = _world_to_map(pulse.origin, player)
		var radius : float = pulse.radius / world_radius * map_radius
		var fade : float = 1.0 - pulse.age / noise_pulse_duration
		var color : Color = heard_noise_color if pulse.heard else noise_color
		_draw_noise_ring(center, radius, Color(color, fade * 0.8))


func _draw_noise_ring(center : Vector2, radius : float, color : Color) -> void:
	var segments : int = 72
	for index : int in range(segments):
		var start : Vector2 = center + Vector2.from_angle(TAU * float(index) / segments) * radius
		var end : Vector2 = center + Vector2.from_angle(TAU * float(index + 1) / segments) * radius
		var clipped : PackedVector2Array = _clip_noise_segment(start, end)
		if clipped.size() == 2:
			draw_line(clipped[0], clipped[1], color, 1.6, true)


func _clip_noise_segment(start : Vector2, end : Vector2) -> PackedVector2Array:
	# Recortar os segmentos preserva o círculo na origem; prender os pontos à
	# borda do radar desenharia um alcance diferente daquele usado pela audição.
	var offset : Vector2 = start - map_center
	var direction : Vector2 = end - start
	var a : float = direction.length_squared()
	if a < 0.000001:
		return PackedVector2Array()
	var b : float = 2.0 * offset.dot(direction)
	var c : float = offset.length_squared() - pow(map_radius - 2.0, 2.0)
	var discriminant : float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return PackedVector2Array()
	var root : float = sqrt(discriminant)
	var entry : float = maxf(0.0, (-b - root) / (2.0 * a))
	var leave : float = minf(1.0, (-b + root) / (2.0 * a))
	if entry >= leave:
		return PackedVector2Array()
	return PackedVector2Array([start + direction * entry, start + direction * leave])


func _draw_noise_label() -> void:
	if _noise_pulses.is_empty():
		return
	var pulse : NoisePulse = _noise_pulses.back()
	for index : int in range(_noise_pulses.size() - 1, -1, -1):
		if _noise_pulses[index].heard:
			pulse = _noise_pulses[index]
			break
	var label : String = "%.0f dB · %s" % [pulse.decibels, "OUVIDO" if pulse.heard else "RUÍDO"]
	var color : Color = heard_noise_color if pulse.heard else noise_color
	var text_size : Vector2 = SHORTCUT_FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11)
	var position : Vector2 = map_center + Vector2(-text_size.x * 0.5, map_radius * 0.7)
	draw_rect(Rect2(position + Vector2(-4.0, -12.0), text_size + Vector2(8.0, 2.0)), Color(0.008, 0.018, 0.035, 0.9))
	draw_string(SHORTCUT_FONT, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, color)


func _draw_shortcut_hint() -> void:
	var text_size : Vector2 = SHORTCUT_FONT.get_string_size(
		shortcut_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		shortcut_font_size
	)
	var text_position : Vector2 = Vector2(
		map_center.x - text_size.x * 0.5,
		map_center.y + map_radius + 25.0
	)
	draw_string(
		SHORTCUT_FONT,
		text_position + Vector2(1.0, 1.0),
		shortcut_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		shortcut_font_size,
		Color(0.0, 0.0, 0.0, 0.72)
	)
	draw_string(
		SHORTCUT_FONT,
		text_position,
		shortcut_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		shortcut_font_size,
		Color(0.65, 0.92, 1.0, 0.78)
	)


func _draw_north_tick(player : Node3D) -> void:
	var world_north : Vector3 = Vector3(0.0, 0.0, -1.0)
	var north_direction : Vector2 = Vector2(
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


func _draw_landmark(landmark : Node3D, player : Node3D) -> void:
	if not is_instance_valid(landmark):
		return

	var raw_point : Vector2 = _world_to_map(landmark.global_position, player)
	var is_inside : bool = raw_point.distance_to(map_center) < map_radius - 10.0
	var point : Vector2 = _clamp_to_radar(raw_point, 6.0)
	var color : Color = Color(0.55, 0.85, 0.7, 0.9 if is_inside else 0.45)

	# Losango pequeno, para não competir com os ícones de NPC e de objetivo.
	var diamond : PackedVector2Array = PackedVector2Array([
		point + Vector2(0.0, -3.5),
		point + Vector2(3.5, 0.0),
		point + Vector2(0.0, 3.5),
		point + Vector2(-3.5, 0.0),
	])
	draw_colored_polygon(diamond, color)

	if not show_landmark_names or not is_inside:
		return

	draw_string(
		SHORTCUT_FONT,
		point + Vector2(5.0, 3.0),
		landmark.name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		9,
		Color(0.72, 0.93, 0.84, 0.72)
	)


func _draw_objective(player : Node3D) -> void:
	if _objective == null or not is_instance_valid(_objective):
		return

	var point : Vector2 = _clamp_to_radar(
		_world_to_map(_objective.global_position, player),
		8.0
	)
	var pulse : float = 17.0 + sin(_elapsed * 3.2) * 2.5
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
	if not is_instance_valid(actor) or not actor is Node3D:
		return

	var actor_3d : Node3D = actor as Node3D
	if uniform_npc_markers:
		_draw_actor_marker(
			_clamp_to_radar(
				_world_to_map(actor_3d.global_position, player),
				npc_marker_size * 0.5 + 2.0
			),
			npc_color,
			false
		)
	var source : Object = actor
	var vision : Object = actor.get("vision") as Object
	if vision != null:
		source = vision

	var actor_position : Vector3 = actor_3d.global_position
	if source.has_method("get_vision_origin"):
		actor_position = Vector3(source.call("get_vision_origin"))
	elif source is Node3D:
		actor_position = (source as Node3D).global_position

	var distance : float = _read_number(source, &"sight_distance")
	if source.has_method("get_effective_sight_distance"):
		distance = float(source.call("get_effective_sight_distance"))

	var half_angle_degrees : float = _read_number(source, &"sight_half_angle_degrees")
	if source.has_method("get_effective_sight_half_angle_degrees"):
		half_angle_degrees = float(
			source.call("get_effective_sight_half_angle_degrees")
		)
	if distance <= 0.0 or half_angle_degrees <= 0.0:
		return

	var forward : Vector3 = actor_3d.global_transform.basis.z
	if source.has_method("get_vision_forward"):
		forward = Vector3(source.call("get_vision_forward"))
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return
	forward = forward.normalized()

	var is_photographer : bool = actor.is_in_group(&"photographers")
	# `has_visual_contact` é o nome nos NPCs antigos; `is_currently_visible`, o
	# do componente `NPCVision`. Cada estilo tem só um dos dois.
	var sees_player : bool = (
		_read_flag(source, &"has_visual_contact")
		or _read_flag(source, &"is_currently_visible")
	)

	var color : Color = (
		Color(1.0, 0.78, 0.22)
		if is_photographer
		else npc_color
	)
	if sees_player:
		color = Color(1.0, 0.16, 0.2)
	if actor.has_method("get_awareness_state"):
		match StringName(actor.call("get_awareness_state")):
			&"alert":
				color = heard_noise_color
			&"pursuit":
				color = Color(1.0, 0.16, 0.2)

	var center : Vector2 = _clamp_to_radar(
		_world_to_map(actor_position, player),
		7.0
	)
	var vision_radius : float = minf(
		distance / world_radius * map_radius,
		map_radius
	)
	var screen_forward : Vector2 = Vector2(
		forward.dot(_map_right(player)),
		-forward.dot(_map_forward(player))
	)
	var forward_angle : float = atan2(screen_forward.x, screen_forward.y)
	var points : PackedVector2Array = PackedVector2Array([center])
	var segments : int = 16

	for index : int in range(segments + 1):
		var angle_offset : float = deg_to_rad(
			-half_angle_degrees
			+ (half_angle_degrees * 2.0) * float(index) / float(segments)
		)
		var direction : Vector2 = Vector2(
			sin(forward_angle + angle_offset),
			cos(forward_angle + angle_offset)
		)
		points.append(_clamp_to_radar(center + direction * vision_radius, 3.0))

	draw_colored_polygon(points, Color(color, 0.07 if not sees_player else 0.12))
	if not uniform_npc_markers:
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

	# NPC comum é um quadrado cheio com contorno claro: lê rápido no radar e não
	# se confunde com o losango dos pontos de referência.
	var half : float = npc_marker_size * 0.5
	var box : Rect2 = Rect2(
		point - Vector2(half, half),
		Vector2(npc_marker_size, npc_marker_size)
	)
	draw_rect(box, Color(color, 0.85))
	draw_rect(box, Color(color.lightened(0.4), 0.95), false, 1.5)


## Lê uma propriedade numérica que pode não existir no ator, sem quebrar: os
## dois estilos de NPC do projeto expõem nomes diferentes.
func _read_number(source : Object, property : StringName) -> float:
	var value : Variant = source.get(property)
	if value == null:
		return 0.0
	return float(value)


## Idem para propriedades booleanas.
func _read_flag(source : Object, property : StringName) -> bool:
	var value : Variant = source.get(property)
	if value == null:
		return false
	return bool(value)


func _clamp_to_radar(point : Vector2, padding : float) -> Vector2:
	var offset : Vector2 = point - map_center
	var maximum_distance : float = map_radius - padding
	if offset.length() > maximum_distance:
		offset = offset.normalized() * maximum_distance
	return map_center + offset


func _world_to_map(world_position : Vector3, player : Node3D) -> Vector2:
	var relative : Vector3 = world_position - player.global_position
	var normalized : Vector2 = Vector2(
		relative.dot(_map_right(player)),
		-relative.dot(_map_forward(player))
	) / world_radius
	return map_center + normalized * map_radius


func _map_right(player : Node3D) -> Vector3:
	var camera_holder : Node3D = player.get_node_or_null("CameraHolder") as Node3D
	var right : Vector3 = (
		camera_holder.global_transform.basis.x
		if camera_holder != null
		else player.global_transform.basis.x
	)
	right.y = 0.0
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
