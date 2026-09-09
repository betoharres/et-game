class_name NPCVision
extends Node3D

## Sensor de visão reutilizável: distância, ângulo (FOV) e linha de visão por
## raycast, com progressão de detecção e memória de curto prazo da última
## posição vista. Consome os mesmos ganchos de camuflagem já usados por
## `smelly_farmer.gd`/`photographer.gd` (`get_stealth_visibility()`,
## `get_visibility_multiplier()`, `set_vision_contact()`), sem duplicar essa
## lógica no lado do jogador.

@export_range(1.0, 60.0, 0.5) var sight_distance: float = 14.0
@export_range(5.0, 120.0, 1.0) var sight_half_angle_degrees: float = 45.0
@export var eye_height: float = 1.6
@export var player_target_height: float = 0.5
@export var detection_time: float = 0.6
@export var lose_sight_after: float = 4.0
## Desligue para NPCs que não devem contar como "alguém está me vigiando"
## (ex.: moradores que só fogem, sem alimentar o medidor de stealth do ET).
@export var reports_vision_contact: bool = true

var player: CharacterBody3D = null
var is_currently_visible: bool = false
var has_detected_player: bool = false
var detection_progress: float = 0.0
var time_since_lost: float = 0.0
var last_seen_position: Vector3 = Vector3.ZERO
var has_last_seen_position: bool = false
var _sample_elapsed: float = 0.0
var _sample_interval: float = 0.0

@onready var _actor: CollisionObject3D = get_parent() as CollisionObject3D


func _ready() -> void:
	var characters: Array[Node] = get_tree().get_nodes_in_group("characters")
	for character in characters:
		if character is CharacterBody3D:
			player = character
			break


func _exit_tree() -> void:
	if reports_vision_contact and player != null and player.has_method("set_vision_contact"):
		player.call("set_vision_contact", self, false)


func _physics_process(delta: float) -> void:
	_sample_elapsed += delta
	if _sample_elapsed < _sample_interval:
		return
	delta = _sample_elapsed
	_sample_elapsed = 0.0
	_sample_interval = 0.1 if player != null and global_position.distance_to(player.global_position) < 70.0 else 0.5
	if player == null or not _is_player_alive():
		_clear_contact()
		return

	is_currently_visible = _can_see_player()

	if reports_vision_contact and player.has_method("set_vision_contact"):
		player.call("set_vision_contact", self, is_currently_visible)

	if is_currently_visible:
		last_seen_position = player.global_position
		has_last_seen_position = true
		time_since_lost = 0.0

		if not has_detected_player:
			var multiplier: float = _get_player_visibility_multiplier()
			detection_progress = minf(detection_progress + delta * multiplier, detection_time)
			if detection_progress >= detection_time:
				has_detected_player = true
	else:
		detection_progress = maxf(detection_progress - delta, 0.0)
		time_since_lost += delta

		if has_detected_player and time_since_lost >= lose_sight_after:
			has_detected_player = false


func get_player_position() -> Vector3:
	return player.global_position if player != null else global_position


func _clear_contact() -> void:
	is_currently_visible = false
	has_detected_player = false
	detection_progress = 0.0
	if reports_vision_contact and player != null and player.has_method("set_vision_contact"):
		player.call("set_vision_contact", self, false)


func _can_see_player() -> bool:
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var distance: float = to_player.length()

	var effective_distance: float = sight_distance * _get_player_visibility_multiplier()
	if distance > effective_distance:
		return false

	if distance > 0.01:
		to_player = to_player.normalized()
		var forward: Vector3 = global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.001:
			forward = forward.normalized()
			var dot_product: float = clampf(forward.dot(to_player), -1.0, 1.0)
			if rad_to_deg(acos(dot_product)) > sight_half_angle_degrees:
				return false

	return _has_clear_line_of_sight()


func _has_clear_line_of_sight() -> bool:
	if get_world_3d() == null:
		return false

	var origin: Vector3 = global_position + Vector3.UP * eye_height
	var target: Vector3 = player.global_position + Vector3.UP * player_target_height

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [_actor.get_rid()] if _actor != null else []
	query.collide_with_areas = false

	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true

	var collider: Object = hit.get("collider")
	return collider == player or (collider is Node and player.is_ancestor_of(collider as Node))


func _get_player_visibility_multiplier() -> float:
	if player != null and player.has_method("get_stealth_visibility"):
		return clampf(float(player.call("get_stealth_visibility")), 0.1, 1.0)
	if player != null and player.has_method("get_visibility_multiplier"):
		return clampf(float(player.call("get_visibility_multiplier")), 0.1, 1.0)
	return 1.0


func _is_player_alive() -> bool:
	if player == null:
		return false
	if player.has_method("is_alive"):
		return bool(player.call("is_alive"))
	return true
